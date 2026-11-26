#define SCRIPT_NAME    "WS_Core"
#define SCRIPT_VERSION "v0.7.11"
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
integer STOCK_RELEASE_REQ = 918250;    // -> WS_Stock: discard before start -> release (return) the basket
integer STOCK_COMMIT_REQ  = 918251;    // -> WS_Stock: commit (consume) the basket, optional output SID
integer EVAL_TAKE_RES     = 918430;    // <- WS_Eval: transformation result "1|..."/"2[|..]"/"0" (holder in id)
integer STOCK_COMMIT_DONE = 918431;    // <- WS_Stock: a take COMMIT|OUT was confirmed by the server (str = ticket)
integer OUTPUT_CONFIG     = 918440;    // -> WS_Output: CONFIG the récipient with the product DNA
integer OUTPUT_DONE       = 918441;    // <- WS_Output: CONFIG dispatched ("OK|<container>") / "FAIL|<reason>"
integer OUTPUT_GIVE       = 918442;    // -> WS_Output: hand source mesh(es) to the holder (give/harvest)
integer STOCK_DISCARD_REQ = 918252;    // -> WS_Stock: purge a held product SID on the server
integer FORGE_CACHED      = 918432;    // -> WS_Take: forge from the cached last-known snapshot (validate on leave)
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
string  gDlgKind;                      // "force" | "locker" | "held" | "resume"

// ---- take: forge the product, HOLD it on the bench, collect into a récipient (socle §7) ----
// The product is a server stock SID; the bench keeps its reference in state:held until the lot is collected
// into a récipient or purged (discard / leave). This is the universal "the bench keeps the product until it
// is collected or purged" model — KEEP needs no product object, the bench itself is the holder.
//   state:held = newSid|qty|dnaHash|name|use|life|tax|stage|props|med|eff   (persists across reset)
string  gForgeTicket;                  // ticket awaiting the forge COMMIT|OUT confirmation ("" = none)

integer ready(){ return gReady || llLinksetDataRead("ws:worldver") != ""; }
integer inRegion(key k){ return llListFindList(llGetAgentList(AGENT_LIST_REGION, []), [k]) != -1; }

status(){
    if(!ready()) return;                                   // WS_Boot owns the floating text until OPR
    string h = llLinksetDataRead("state:lock");
    if(h != ""){ llSetText("Nexus - held by " + llLinksetDataRead("state:lockname"), <1.0,0.8,0.4>, 1.0); return; }
    if(llLinksetDataRead("state:held") != ""){            // free but a forged product is waiting to be collected
        llSetText("Nexus - product waiting\n(re-attach your HUD, or touch)", <0.9,0.9,0.5>, 1.0);
        return;
    }
    llSetText("Nexus - bench FREE", <0.6,1.0,0.6>, 1.0);
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

// Free the lock (HUD removed / Release). What happens to the craft on leave:
//   forged product (state:held)      -> kept as-is (collect/purge later); session kept.
//   started craft with a known stage -> VALIDATED at its last known stage: forge from the cached snapshot
//                                       (→ becomes a held product). No refund; session kept for the forge.
//   started craft, no known stage    -> consumed, no product, no refund (nothing was paused/observed).
//   never started (reserved only)    -> refund the picks.
freeLock(string why){
    key holder = (key)llLinksetDataRead("state:lock");
    string ticket = llLinksetDataRead("state:session");
    integer keepSession = FALSE;
    if(llLinksetDataRead("state:held") != ""){
        keepSession = TRUE;
    } else if(llLinksetDataRead("state:craft") == "1"){
        if(llLinksetDataRead("state:lastsnap") != ""){
            llMessageLinked(LINK_SET, FORGE_CACHED, "", holder);   // validate at last known stage (forge → held)
            keepSession = TRUE;                                   // the forge's COMMIT|OUT needs the ticket
        } else {
            if(ticket != "") llMessageLinked(LINK_SET, STOCK_COMMIT_REQ, ticket, holder);   // consume, no refund
            llLinksetDataDelete("state:stock");
            llLinksetDataDelete("state:takesrc");
            llLinksetDataWrite("state:craft", "0");
        }
    } else if(llLinksetDataRead("state:stock") != ""){
        llMessageLinked(LINK_SET, STOCK_RELEASE_REQ, ticket, holder);   // never started -> refund
        llLinksetDataDelete("state:takesrc");
    }
    llLinksetDataDelete("state:lock");
    llLinksetDataDelete("state:lockname");
    if(!keepSession) llLinksetDataDelete("state:session");
    gBound = FALSE; gMisses = 0; gGiven = FALSE;
    llSetTimerEvent(0.0);
    status();
    llOwnerSay("[Nexus] WS_Core: bench freed (" + why + ").");
}

// Purge a held product (discard / leave): tell the server to drop its stock, then forget the lot.
purgeHeld(){
    string held = llLinksetDataRead("state:held");
    if(held == "") return;
    string sid = llList2String(llParseStringKeepNulls(held, ["|"], []), 0);
    if(sid != "") llMessageLinked(LINK_SET, STOCK_DISCARD_REQ, sid, NULL_KEY);
    llLinksetDataDelete("state:held");
}

// Player DISCARD on the HUD: abandon the current preparation but KEEP the bench lock and the player.
// 'started' decides the stock fate. Only the Release dialog (release(), below) actually leaves the bench.
discardCraft(integer started){
    string ticket = llLinksetDataRead("state:session");
    key holder = (key)llLinksetDataRead("state:lock");
    purgeHeld();                                           // a held, uncollected product is purged with the craft
    llLinksetDataWrite("state:craft", "0");
    if(started){
        // Cut begun -> components are committed: CONSUME them (COMMIT, no product), NO refund. The committed
        // ticket is dead, so rotate to a fresh session and re-bind; the player keeps the bench.
        llMessageLinked(LINK_SET, STOCK_COMMIT_REQ, ticket, holder);
        llLinksetDataWrite("state:session", (string)llGenerateKey());
        gBound = FALSE;
        offerHud(holder);
    } else {
        // Cut not begun -> nothing committed: RETURN the reserved picks. Same session stays reusable;
        // WS_Stock empties the HUD basket and refreshes NEARBY.
        llMessageLinked(LINK_SET, STOCK_RELEASE_REQ, ticket, holder);
    }
}

// The take is done (product collected, or given): close the craft like a discard-commit — rotate to a fresh
// session, re-bind the HUD, and tell the HUD to reset P1 / close P3 (NX|TAKEDONE).
closeTake(key holder, string note){
    llLinksetDataWrite("state:craft", "0");
    llLinksetDataDelete("state:lastsnap"); llLinksetDataDelete("state:lastname"); llLinksetDataDelete("state:lastsrc");
    llLinksetDataWrite("state:session", (string)llGenerateKey());
    gBound = FALSE;
    string ns = llLinksetDataRead("state:session");
    if(holder != NULL_KEY){
        llRegionSayTo(holder, NX_HUD, "NX|TAKEDONE|" + ns + "|" + note);
        offerHud(holder);
    }
}

// Forge the product SID and HOLD it on the bench (state:held, persists across reset). COMMIT|OUT consumes
// the reserved inputs and creates the server stock; collection opens once the server confirms (COMMIT_DONE).
forgeProduct(string result, key holder){
    list f = llParseStringKeepNulls(result, ["|"], []);
    string ticket = llLinksetDataRead("state:session");
    key nsid = llGenerateKey();
    string tax   = llList2String(f, 6);
    string stage = llList2String(f, 7);
    string props = llList2String(f, 8);
    integer qty  = (integer)llList2String(f, 3);
    string dna = llMD5String(tax + "|" + stage + "|" + props, 0);   // matches NX_Component.dnaHash()
    // state:held = newSid|qty|dna|name|use|life|tax|stage|props|med|eff
    llLinksetDataWrite("state:held", (string)nsid + "|" + (string)qty + "|" + dna
        + "|" + llList2String(f, 2) + "|" + llList2String(f, 4) + "|" + llList2String(f, 5)
        + "|" + tax + "|" + stage + "|" + props + "|" + llList2String(f, 9) + "|" + llList2String(f, 10));
    gForgeTicket = ticket;
    llMessageLinked(LINK_SET, STOCK_COMMIT_REQ, ticket + "|" + (string)nsid + "|" + (string)qty + "|" + dna, holder);
}

// Offer collection of the held product: open the récipient page. If the player leaves without collecting,
// the lot stays held at the bench; the next take re-opens this instead of forging again.
openCollect(key holder){
    list h = llParseStringKeepNulls(llLinksetDataRead("state:held"), ["|"], []);
    if(llGetListLength(h) < 11) return;
    llRegionSayTo(holder, NX_HUD, "NX|OUTPUT|" + llLinksetDataRead("state:session") + "|WAIT_CONTAINER|" + llList2String(h, 1));
    llRegionSayTo(holder, 0, "[Nexus] Product ready - choose a container (or leave it; it stays on the bench).");
}

// Collect the held product into the chosen récipient: CONFIG it with the held SID (no new commit; the SID
// already carries the server stock forged at take). WS_Output confirms with OUTPUT_DONE.
collectInto(string container, key holder){
    list h = llParseStringKeepNulls(llLinksetDataRead("state:held"), ["|"], []);
    if(llGetListLength(h) < 11) return;
    // OUTPUT_CONFIG payload: container|sid|name|use|life|tax|stage|props|med|eff
    string cfg = container + "|" + llList2String(h, 0) + "|" + llList2String(h, 3) + "|" + llList2String(h, 4)
        + "|" + llList2String(h, 5) + "|" + llList2String(h, 6) + "|" + llList2String(h, 7)
        + "|" + llList2String(h, 8) + "|" + llList2String(h, 9) + "|" + llList2String(h, 10);
    llMessageLinked(LINK_SET, OUTPUT_CONFIG, cfg, NULL_KEY);
}

// A transformation result came back from WS_Eval (holder already validated).
//   code 1 (reaction) -> forge the product and hold it on the bench (collection opens on COMMIT_DONE).
//   code 2 (give)     -> consume the inputs and hand out the source mesh(es) directly, then close.
//   code 0 (inert)    -> nothing to deliver; keep the craft so the player can adjust or discard.
takeResult(string result, key holder){
    if(llLinksetDataRead("state:held") != ""){ openCollect(holder); return; }   // collect/purge the held lot first
    list f = llParseStringKeepNulls(result, ["|"], []);
    string code = llList2String(f, 0);
    if(code == "1"){
        forgeProduct(result, holder);
    } else if(code == "2"){
        // give/harvest: "2" (each source's single mesh) or "2|leaf^root" (listed organs). Consume the
        // reserved inputs (no product SID), hand the mesh(es) over, then close like a discard-commit.
        string ticket = llLinksetDataRead("state:session");
        string organs = "";
        if(llGetListLength(f) >= 2) organs = llList2String(f, 1);
        string srcs = llLinksetDataRead("state:takesrc");
        llMessageLinked(LINK_SET, STOCK_COMMIT_REQ, ticket, holder);                 // consume, no OUT
        llMessageLinked(LINK_SET, OUTPUT_GIVE, (string)holder + "|" + organs + "|" + srcs, NULL_KEY);
        llLinksetDataDelete("state:takesrc");
        closeTake(holder, "give");
    } else {
        llRegionSayTo(holder, 0, "[Nexus] Nothing reacts with this preparation. Adjust it or discard it.");
    }
}

// Player leaves the bench (Release dialog): same leave rules as freeLock (refund if unstarted, validate a
// started craft at its last known stage, keep a forged product).
release(){
    freeLock("released by player");
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
        if(num == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(num == EVAL_TAKE_RES){                       // WS_Take result; id = holder (may be gone on forge-on-leave, so no lock check)
            takeResult(str, id);
            return;
        }
        if(num == STOCK_COMMIT_DONE){                   // product forged on the server -> open its collection
            if(str == gForgeTicket && gForgeTicket != ""){
                gForgeTicket = "";
                openCollect((key)llLinksetDataRead("state:lock"));
            }
            return;
        }
        if(num == OUTPUT_DONE){                         // collection result from WS_Output
            key doneHolder = (key)llLinksetDataRead("state:lock");
            if(llGetSubString(str, 0, 3) == "FAIL"){   // no récipient: keep the held lot, collect later
                llRegionSayTo(doneHolder, 0, "[Nexus] No container found - the product stays on the bench (collect later).");
                return;
            }
            if(llLinksetDataRead("state:held") == "") return;   // nothing held -> stale/duplicate
            llLinksetDataDelete("state:held");         // collected: forget the lot (stock now lives in the récipient)
            closeTake(doneHolder, "done");
            return;
        }
    }

    touch_start(integer n)
    {
        key av = llDetectedKey(0);
        if(!ready()){ llRegionSayTo(av, 0, "[Nexus] Bench not ready (still booting)."); return; }
        string holder = llLinksetDataRead("state:lock");
        if(holder == ""){
            if(llLinksetDataRead("state:held") != ""){     // free but holding a product -> collect / jeter / conserver
                gDlgAv = av; gDlgKind = "held";
                llDialog(av, "A product is waiting on this bench.\nDiscard it, or keep it (choose a container)?",
                    ["Discard", "Keep"], gDlgChan);
                return;
            }
            // A started craft left behind was validated on leave (freeLock → forge-on-leave) and is now a held
            // product, handled by the branch above. A bare craft=1 here means it had no known stage to forge
            // from; just take the bench so the player can re-cut and take.
            acquire(av); return;
        }
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
            if(verb == "HERE"){                            // a (re)attached HUD announces itself (handled before the holder guard)
                if(ready() && llLinksetDataRead("state:lock") == "" && llLinksetDataRead("state:held") != ""
                    && id != NULL_KEY)
                    acquire(llGetOwnerKey(id));            // HELD-FREE -> auto-resume this avatar (bind -> openCollect -> P3)
                return;
            }
            string holder = llLinksetDataRead("state:lock");
            if(holder == "" || id == NULL_KEY || llGetOwnerKey(id) != (key)holder) return;  // only the holder's HUD matters

            if(verb == "CRAFTSTART"){                      // HUD: the cut has begun -> prep is started (committed, no refund)
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                llLinksetDataWrite("state:craft", "1");
                llLinksetDataDelete("state:lastsnap");     // scope the cached stage to THIS craft (re-cached on observe/take)
                llLinksetDataDelete("state:lastname");
                llLinksetDataDelete("state:lastsrc");
                return;
            }
            if(verb == "DISCARD"){                         // player discard on the HUD -> drop the basket, keep the bench
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                discardCraft((integer)llList2String(f, 3));   // f[3] = started flag (1 = consume, 0 = return)
                return;
            }
            if(verb == "CONTAINER"){                       // player chose a récipient on P3 -> collect the held product
                if(llList2String(f, 2) != llLinksetDataRead("state:session")) return;
                collectInto(llList2String(f, 3), (key)holder);
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
                if(llLinksetDataRead("state:held") != "") openCollect((key)holder);   // resume: go straight to collection
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
            else if(gDlgKind == "held"){
                // Keep -> take the bench; the HUD opens the container page on re-bind (openCollect). Discard -> purge.
                if(msg == "Keep") acquire(gDlgAv);
                else if(msg == "Discard"){ purgeHeld(); status(); }
            }
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
