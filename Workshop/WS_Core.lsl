#define SCRIPT_NAME    "WS_Core"
#define SCRIPT_VERSION "v0.4.2"
#include "nexus_header"

// WS_Core — the bench-side state machine. First slice: reservation (occupancy lock) + HUD provisioning
// + bind + a periodic heartbeat that frees the bench when the holder's HUD disappears. Craft phases
// (select/action/commit) come later. Runs in the bench linkset, shares LinksetData with WS_Boot.
//
// Lock = craft lifetime (socle §8): one player per bench. Acquired on touch when OPR and free. Released
// by the player's take/discard (release), OR freed automatically when the holder no longer has a HUD.
// Persisted in LSD so a bench reset does not free it (the heartbeat re-arms on reset).
//
// Heartbeat (the holder MUST keep a HUD to keep the bench): while locked, every HEARTBEAT seconds the
// bench pings the holder's worn HUD (NX|HUDQ) and expects NX|HUDA. While unbound this also provisions
// (gives the reference HUD once) and binds (OFFER on the first answer). After MISS_MAX unanswered pings
// the HUD is considered gone -> the bench frees the lock (a pending craft, if any, is KEPT, never
// auto-discarded; §8). Removing the HUD therefore releases the bench on its own.
//   bench  -> avatar : NX|HUDQ|<benchKey>|<model>|<version>     (every heartbeat)
//   wornHUD-> bench  : NX|HUDA|<model>|<version>
//   bind   : NX|OFFER|<benchKey>|<session>|<kind>|<single>|<keep>  ->  NX|ACCEPT|<session>|<kind>  ->  NX|BOUND|<session>
//   wornHUD-> bench  : NX|UNBIND|<session>   (best-effort fast free on detach; the heartbeat is the reliable path)
//
// Contention: holder present -> "in use"; holder out of region -> Force (immediate manual takeover; the
// heartbeat would free it within MISS_MAX*HEARTBEAT anyway). Force keeps any pending craft (§8).
//
// OPR gate: reservations refused until the world is loaded (WS_OPR, or ws:worldver set after a lone reset).

integer NX_HUD = -918282;              // bench <-> worn HUD
integer WS_OPR = 970110;               // link_message from WS_Boot: "OPR|<ver>"
integer STOCK_RELEASE_REQ = 918250;    // -> WS_Stock: take/discard -> release the reserved basket
float   HEARTBEAT = 5.0;               // seconds between holder-HUD pings while locked
integer MISS_MAX  = 3;                 // consecutive unanswered pings before the bench frees itself (~15 s)

// LSD (shared linkset): state:lock = holder key ("" free), state:lockname, state:craft "0"/"1",
//                       state:session = bind/craft session (ticket).
// Bench config (WS_Boot): ws:genre, ws:cfg:HUDKind, ws:cfg:SingleIngredient, ws:cfg:AllowKeep.

integer gReady;                        // OPR reached
string  gHudInv;                       // reference HUD inventory name "<model> v<X.Y.Z>"
string  gModel;
string  gVersion;

integer gBound;                        // NX|ACCEPT received for the current session
integer gMisses;                       // consecutive unanswered heartbeat pings
integer gPingAck;                      // current ping answered by the holder's HUD
integer gGiven;                        // reference HUD already handed to this holder

integer gDlgChan;
key     gDlgAv = NULL_KEY;
string  gDlgKind;                      // "force" | "locker"

integer ready(){ return gReady || llLinksetDataRead("ws:worldver") != ""; }
integer inRegion(key k){ return llListFindList(llGetAgentList(AGENT_LIST_REGION, []), [k]) != -1; }

status(){
    if(!ready()) return;                                   // WS_Boot owns the floating text until OPR
    string h = llLinksetDataRead("state:lock");
    if(h == "") llSetText("Nexus - bench FREE", <0.6,1.0,0.6>, 1.0);
    else        llSetText("Nexus - held by " + llLinksetDataRead("state:lockname"), <1.0,0.8,0.4>, 1.0);
}

parseHud(){
    gHudInv = ""; gModel = ""; gVersion = "";
    integer n = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    for(i = 0; i < n; ++i){
        string nm = llGetInventoryName(INVENTORY_OBJECT, i);
        integer p = llSubStringIndex(nm, " v");
        if(p > 0){
            string tail = llGetSubString(nm, p + 1, -1);
            if(llGetSubString(tail, 0, 0) == "v"){
                gHudInv = nm;
                gModel = llStringTrim(llGetSubString(nm, 0, p - 1), STRING_TRIM);
                gVersion = tail;
                return;
            }
        }
    }
}

giveHud(key av){
    if(gHudInv == ""){ llOwnerSay("[Nexus] WS_Core: no reference HUD in inventory (name it '<model> v<X.Y.Z>')."); return; }
    llGiveInventory(av, gHudInv);
    llRegionSayTo(av, 0, "[Nexus] HUD delivered: " + gModel + " " + gVersion + ". Wear it.");
}

// kind = the reference HUD MODEL (what the worn HUD gates its ACCEPT on), NOT the craft genre. The worn
// HUD and the bench's reference HUD are the same model, so this matches; the genre is a craft concept
// delivered later for scan gating, not a bind key.
offerHud(key av){
    string single = (string)((integer)llLinksetDataRead("ws:cfg:SingleIngredient"));
    string keep   = (string)((integer)llLinksetDataRead("ws:cfg:AllowKeep"));
    llRegionSayTo(av, NX_HUD, "NX|OFFER|" + (string)llGetKey() + "|"
        + llLinksetDataRead("state:session") + "|" + gModel + "|" + single + "|" + keep);
}

pingHolder(){
    string holder = llLinksetDataRead("state:lock");
    if(holder == "") return;
    gPingAck = FALSE;
    llRegionSayTo((key)holder, NX_HUD, "NX|HUDQ|" + (string)llGetKey() + "|" + gModel + "|" + gVersion);
}

startMonitor(){                                            // (re)arm the heartbeat for the current holder
    gBound = FALSE; gMisses = 0; gGiven = FALSE;
    llSetTimerEvent(HEARTBEAT);
    pingHolder();
}

acquire(key av){
    llLinksetDataWrite("state:lock", (string)av);
    llLinksetDataWrite("state:lockname", llKey2Name(av));
    if(llLinksetDataRead("state:session") == "")
        llLinksetDataWrite("state:session", (string)llGenerateKey());
    status();
    llRegionSayTo(av, 0, "[Nexus] Bench reserved.");
    startMonitor();
}

forceTo(key av){
    llLinksetDataWrite("state:lock", (string)av);
    llLinksetDataWrite("state:lockname", llKey2Name(av));  // state:craft + state:session kept: pending craft inherited
    status();
    if(llLinksetDataRead("state:craft") == "1")
        llRegionSayTo(av, 0, "[Nexus] Bench forced. A craft is pending here - take or discard it.");
    else
        llRegionSayTo(av, 0, "[Nexus] Bench forced - reserved.");
    startMonitor();
}

// Free the lock but KEEP a pending craft (§8: never auto-discard). No craft -> also clear the session.
freeLock(string why){
    llLinksetDataDelete("state:lock");
    llLinksetDataDelete("state:lockname");
    if(llLinksetDataRead("state:craft") != "1") llLinksetDataDelete("state:session");
    gBound = FALSE; gMisses = 0; gGiven = FALSE;
    llSetTimerEvent(0.0);
    status();
    llOwnerSay("[Nexus] WS_Core: bench freed (" + why + ").");
}

// Player take/discard: clear everything.
release(){
    llLinksetDataDelete("state:lock");
    llLinksetDataDelete("state:lockname");
    llLinksetDataDelete("state:session");
    llLinksetDataWrite("state:craft", "0");
    gBound = FALSE; gMisses = 0; gGiven = FALSE;
    llSetTimerEvent(0.0);
    llMessageLinked(LINK_SET, STOCK_RELEASE_REQ, "", NULL_KEY);   // WS_Stock releases the reserved basket
    status();
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
        gDlgAv = NULL_KEY; gBound = FALSE; gMisses = 0; gGiven = FALSE;
        if(llLinksetDataRead("state:lock") != "") startMonitor();   // resume monitoring after a reset
        status();
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c)
    {
        if(c & CHANGED_OWNER){ llResetScript(); return; }
        if(c & CHANGED_INVENTORY) parseHud();
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
        if((key)holder == av){                             // the holder
            if(!gBound){ pingHolder(); llRegionSayTo(av, 0, "[Nexus] Linking your HUD..."); return; }
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
        if(chan == NX_HUD){
            list f = llParseStringKeepNulls(msg, ["|"], []);
            if(llList2String(f, 0) != "NX") return;
            string verb = llList2String(f, 1);
            string holder = llLinksetDataRead("state:lock");
            if(holder == "" || id == NULL_KEY || llGetOwnerKey(id) != (key)holder) return;  // only the holder's HUD matters

            if(verb == "DISCARD"){                         // player discard on the HUD -> release the craft + stock
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                release();
                return;
            }
            if(verb == "HUDA"){                            // holder's HUD answered the heartbeat
                if(llList2String(f, 2) == gModel && llList2String(f, 3) == gVersion){
                    gPingAck = TRUE; gMisses = 0;
                    if(!gBound) offerHud((key)holder);     // not bound yet -> bind now
                }
                return;
            }
            if(verb == "ACCEPT"){                          // bind handshake
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                llRegionSayTo((key)holder, NX_HUD, "NX|BOUND|" + llLinksetDataRead("state:session"));
                gBound = TRUE;
                llOwnerSay("[Nexus] WS_Core: HUD bound (" + llLinksetDataRead("state:lockname") + ").");
                return;
            }
            if(verb == "UNBIND"){                          // best-effort fast free on detach
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                freeLock("HUD detached");
                return;
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

    timer()   // heartbeat while locked
    {
        string holder = llLinksetDataRead("state:lock");
        if(holder == ""){ llSetTimerEvent(0.0); return; }
        if(!gPingAck){
            ++gMisses;
            if(!gBound && !gGiven){ giveHud((key)holder); gGiven = TRUE; }   // provision once while unbound
        }
        if(gMisses >= MISS_MAX){ freeLock("holder HUD not responding"); return; }
        pingHolder();                                      // next heartbeat ping
    }
}
// REVIEW: 2026-11-19 — version match is exact; a semver ">=" compare would avoid re-giving a newer HUD.
// REVIEW: 2026-11-19 — llSetText shared with WS_Boot (socle §6); WS_HMI will own the text layer.
// REVIEW: 2026-11-19 — release() is a stand-in; COMMIT/RELEASE to WS_Stock wired with the craft flow.
// REVIEW: 2026-11-19 — freeLock keeps a pending craft+session; acquire() does not yet prompt take/discard
//   for an inherited craft (no craft tracking on the bench yet). Wire with the craft flow.
// REVIEW: 2026-11-19 — HEARTBEAT=5 s, MISS_MAX=3 -> ~15 s to free after HUD removal; tune as needed.
