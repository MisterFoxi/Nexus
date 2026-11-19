#define SCRIPT_NAME    "WS_Core"
#define SCRIPT_VERSION "v0.2.0"
#include "nexus_header"

// WS_Core — the bench-side state machine. First slice: reservation (occupancy lock) + HUD provisioning
// + contention/force + bind. Craft phases (select/action/commit) come later. Runs in the bench linkset,
// shares its LinksetData with WS_Boot (OPR gate, world, bench config).
//
// Lock = craft lifetime (socle §8): one player per bench, acquired on touch when OPR and free, released
// only when the player takes (COMMIT) or discards (RELEASE) their craft. No TTL. Persisted in LSD so a
// bench reset does not free it.
//
// Provisioning (socle §8): the bench carries THE reference HUD in inventory, named "<model> v<X.Y.Z>".
// On lock, it probes the toucher's worn HUD on NX_HUD; absent / wrong model / wrong version -> give it.
//   bench  -> avatar : NX|HUDQ|<benchKey>|<model>|<version>
//   wornHUD-> bench  : NX|HUDA|<model>|<version>
//
// Bind (ported from docs/README_workshop_link.md "Association and lock"): once the HUD is present, the bench
// OFFERs the session; the HUD ACCEPTs; the bench confirms BOUND. session = state:session (minted at acquire,
// kept across force, cleared at release). kind/single/keep come from the bench config (WS_Boot -> LSD).
//   bench  -> avatar : NX|OFFER|<benchKey>|<session>|<kind>|<single>|<keep>
//   wornHUD-> bench  : NX|ACCEPT|<session>|<kind>
//   bench  -> avatar : NX|BOUND|<session>
//
// Contention: holder present in region -> "in use"; holder away (out of region) -> offer Force. Forcing
// transfers the lock and LEAVES any pending craft (and its session) in the bench for the new player.
//
// OPR gate: reservations are refused until the world is loaded (WS_Boot broadcasts WS_OPR; we also infer
// readiness from ws:worldver being set, to survive a lone WS_Core reset).

integer NX_HUD = -918282;              // bench <-> worn HUD
integer WS_OPR = 970110;               // link_message from WS_Boot: "OPR|<ver>"
float   PROBE_WAIT = 2.5;              // seconds to wait for a worn-HUD answer before giving

// LSD (shared linkset): state:lock = holder avatar key ("" free), state:lockname = legible name,
//                       state:craft = "0"/"1" pending craft, state:session = bind/craft session (ticket).
// Bench config read from WS_Boot: ws:genre, ws:cfg:HUDKind, ws:cfg:SingleIngredient, ws:cfg:AllowKeep.

integer gReady;                        // OPR reached (world loaded)
string  gHudInv;                       // exact inventory name of the reference HUD ("<model> v<X.Y.Z>")
string  gModel;                        // parsed model (name before " v")
string  gVersion;                      // parsed expected version ("vX.Y.Z")

key     gProbeAv = NULL_KEY;           // avatar currently being probed
integer gHasHud;                       // a matching NX|HUDA was heard this probe
integer gBound;                        // HUD ACCEPT received for the current session

integer gDlgChan;                      // dialog channel
key     gDlgAv = NULL_KEY;             // avatar in the current dialog
string  gDlgKind;                      // "force" | "locker"

integer ready(){ return gReady || llLinksetDataRead("ws:worldver") != ""; }
integer inRegion(key k){ return llListFindList(llGetAgentList(AGENT_LIST_REGION, []), [k]) != -1; }

status(){
    if(!ready()) return;                                   // WS_Boot owns the floating text until OPR
    string h = llLinksetDataRead("state:lock");
    if(h == "") llSetText("Nexus - bench FREE", <0.6,1.0,0.6>, 1.0);
    else        llSetText("Nexus - held by " + llLinksetDataRead("state:lockname"), <1.0,0.8,0.4>, 1.0);
}

// find the reference HUD object: name "<model> v<MAJOR.MINOR.PATCH>"
parseHud(){
    gHudInv = ""; gModel = ""; gVersion = "";
    integer n = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    for(i = 0; i < n; ++i){
        string nm = llGetInventoryName(INVENTORY_OBJECT, i);
        integer p = llSubStringIndex(nm, " v");            // last-ish " v" token
        if(p > 0){
            string tail = llGetSubString(nm, p + 1, -1);   // "vX.Y.Z"
            if(llGetSubString(tail, 0, 0) == "v"){
                gHudInv  = nm;
                gModel   = llStringTrim(llGetSubString(nm, 0, p - 1), STRING_TRIM);
                gVersion = tail;
                return;
            }
        }
    }
}

giveHud(key av){
    if(gHudInv == ""){ llOwnerSay("[Nexus] WS_Core: no reference HUD in inventory (name it '<model> v<X.Y.Z>')."); return; }
    llGiveInventory(av, gHudInv);
    llRegionSayTo(av, 0, "[Nexus] HUD delivered: " + gModel + " " + gVersion + ".");
}

startProbe(key av){
    if(gHudInv == ""){ giveHud(av); return; }              // nothing to probe against; owner already warned
    gProbeAv = av; gHasHud = FALSE;
    llRegionSayTo(av, NX_HUD, "NX|HUDQ|" + (string)llGetKey() + "|" + gModel + "|" + gVersion);
    llSetTimerEvent(PROBE_WAIT);
}

// kind/single/keep for the bind OFFER, from the bench config WS_Boot wrote to LSD.
offerHud(key av){
    string kind = llLinksetDataRead("ws:cfg:HUDKind");
    if(kind == "") kind = llLinksetDataRead("ws:genre");               // HUDKind defaults to the Genre
    string single = (string)((integer)llLinksetDataRead("ws:cfg:SingleIngredient"));
    string keep   = (string)((integer)llLinksetDataRead("ws:cfg:AllowKeep"));
    llRegionSayTo(av, NX_HUD, "NX|OFFER|" + (string)llGetKey() + "|"
        + llLinksetDataRead("state:session") + "|" + kind + "|" + single + "|" + keep);
}

acquire(key av){
    llLinksetDataWrite("state:lock", (string)av);
    llLinksetDataWrite("state:lockname", llKey2Name(av));
    if(llLinksetDataRead("state:session") == "")
        llLinksetDataWrite("state:session", (string)llGenerateKey());  // new craft session (ticket)
    gBound = FALSE;
    status();
    llRegionSayTo(av, 0, "[Nexus] Bench reserved.");
    startProbe(av);
}

forceTo(key av){
    llLinksetDataWrite("state:lock", (string)av);
    llLinksetDataWrite("state:lockname", llKey2Name(av));  // state:craft + state:session kept: pending craft inherited
    gBound = FALSE;
    status();
    if(llLinksetDataRead("state:craft") == "1")
        llRegionSayTo(av, 0, "[Nexus] Bench forced. A craft is pending here - take or discard it.");
    else
        llRegionSayTo(av, 0, "[Nexus] Bench forced - reserved.");
    startProbe(av);
}

release(){
    llLinksetDataDelete("state:lock");
    llLinksetDataDelete("state:lockname");
    llLinksetDataDelete("state:session");                  // end the craft session (ticket)
    llLinksetDataWrite("state:craft", "0");                // take/discard clears the pending craft
    gBound = FALSE;
    status();
    // REVIEW: wire COMMIT/RELEASE to WS_Stock here when the craft flow exists.
}

default
{
    state_entry()
    {
        nexusBoot();
        gDlgChan = -1000000 - (integer)llFrand(1000000.0);
        llListen(NX_HUD, "", NULL_KEY, "");
        llListen(gDlgChan, "", NULL_KEY, "");
        parseHud();
        gReady = (llLinksetDataRead("ws:worldver") != "");
        gProbeAv = NULL_KEY; gDlgAv = NULL_KEY; gBound = FALSE;
        status();
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c)
    {
        if(c & CHANGED_OWNER){ llResetScript(); return; }
        if(c & CHANGED_INVENTORY) parseHud();              // reference HUD may have been updated
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == WS_OPR){ gReady = TRUE; status(); return; }
        if(num == NEXUS_MEM_REPORT) nexusMemReport();
    }

    touch_start(integer n)
    {
        key av = llDetectedKey(0);
        if(!ready()){ llRegionSayTo(av, 0, "[Nexus] Bench not ready (still booting)."); return; }
        string holder = llLinksetDataRead("state:lock");
        if(holder == ""){ acquire(av); return; }
        if((key)holder == av){                             // locker re-touch
            if(!gBound){ startProbe(av); return; }         // not bound yet (e.g. just wore the given HUD) -> (re)probe & bind
            gDlgAv = av; gDlgKind = "locker";
            llDialog(av, "You hold this bench.\nRelease it (take/discard your work)?", ["Release", "Close"], gDlgChan);
            return;
        }
        key hk = (key)holder;                              // locked by someone else
        if(inRegion(hk)){
            llRegionSayTo(av, 0, "[Nexus] Bench in use by " + llLinksetDataRead("state:lockname") + ".");
        } else {
            gDlgAv = av; gDlgKind = "force";
            llDialog(av, llLinksetDataRead("state:lockname") + " seems away.\nForce allocation?", ["Force", "Cancel"], gDlgChan);
        }
    }

    listen(integer chan, string nm, key id, string msg)
    {
        if(chan == NX_HUD){                                // worn-HUD traffic
            list f = llParseStringKeepNulls(msg, ["|"], []);
            if(llList2String(f, 0) != "NX") return;
            string verb = llList2String(f, 1);
            if(verb == "HUDA"){                            // provisioning answer during a probe -> HUD present, bind now
                if(gProbeAv != NULL_KEY && id != NULL_KEY && llGetOwnerKey(id) == gProbeAv
                   && llList2String(f, 2) == gModel && llList2String(f, 3) == gVersion){
                    gHasHud = TRUE;
                    offerHud(gProbeAv);
                }
                return;
            }
            if(verb == "ACCEPT"){                          // HUD accepts the offer -> confirm BOUND
                string holder = llLinksetDataRead("state:lock");
                if(holder == "" || id == NULL_KEY || llGetOwnerKey(id) != (key)holder) return;
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                llRegionSayTo((key)holder, NX_HUD, "NX|BOUND|" + llLinksetDataRead("state:session"));
                gBound = TRUE;
                llOwnerSay("[Nexus] WS_Core: HUD bound (" + llLinksetDataRead("state:lockname") + ").");
            }
            return;
        }
        if(chan == gDlgChan && id == gDlgAv){
            if(gDlgKind == "force" && msg == "Force") forceTo(gDlgAv);
            else if(gDlgKind == "locker" && msg == "Release") release();
            gDlgAv = NULL_KEY; gDlgKind = "";
            return;
        }
    }

    timer()
    {
        llSetTimerEvent(0.0);                              // one-shot: provisioning window elapsed
        if(gProbeAv != NULL_KEY){
            if(!gHasHud){
                giveHud(gProbeAv);
                llRegionSayTo(gProbeAv, 0, "[Nexus] Wear the HUD, then touch the bench again.");
            }
            gProbeAv = NULL_KEY;
        }
    }
}
// REVIEW: 2026-11-18 — version match is exact (reported == expected); a semver ">=" compare would avoid
//   re-giving when the player has a newer HUD. Fine while HUDs are single-source.
// REVIEW: 2026-11-18 — llSetText is shared with WS_Boot (socle §6); WS_HMI will own the text layer.
// REVIEW: 2026-11-18 — release() is a stand-in; COMMIT/RELEASE to WS_Stock wired with the craft flow.
// REVIEW: 2026-11-18 — the bind has no RELEASE round-trip to the HUD yet; the HUD clears its bind on re-wear.
// REVIEW: 2026-11-18 — one probe at a time (single timer); concurrent reservations are not expected yet.
