#define SCRIPT_NAME    "Nexus_Server"
#define SCRIPT_VERSION "v0.4.3"
#include "nexus_header"

// Nexus server (Model 1: physical objects + server referee).
// TWO planes, one prim, one channel for now (stock-protocol §7):
//   STOCK plane (hot)  : authority on QUANTITIES. reserve/commit/release.
//   WORLD plane (cold) : authority on the compiled dictionaries. pull + cache, versioned.
// Ledger + ticket holds + world buffer live in LinksetData, survive reset/re-rez.
//
// STOCK wire (region say on NX_STOCK, fields "|"):
//   component -> srv : NX|REGISTER|<sid>|<owner>|<dnaHash>|<expiryUnix>|<initQty>
//   srv -> *         : NX|QTY|<sid>|<available>          (available = total minus all reserved)
//   any -> srv       : NX|DISCOVER|<owner>|<name>        srv -> who : NX|SERVER|<srvKey>
//   ws  -> srv       : NX|RESERVE|<ticket>|<sid>:<u>^... (DECLARATIVE: the ticket should hold exactly this set)
//                      srv -> ws : NX|RES_OK|<ticket> | NX|RES_NO|<ticket>|<sid>:<avail>^...
//   ws  -> srv       : NX|COMMIT|<ticket>[|OUT|<newSid>|<qty>|<dnaHash>]  srv -> ws : NX|COMMIT_OK|<ticket> | NX|COMMIT_NO|<ticket>
//   ws  -> srv       : NX|RELEASE|<ticket>               srv -> ws : NX|REL_OK|<ticket>
//   any -> srv       : NX|DISCARD|<sid>                  srv -> * : NX|QTY|<sid>|0
//
// WORLD wire (region say on NX_STOCK, fields "|"; payload is OPAQUE -> extract by position, never re-split):
//   ws  -> srv : NX|HELLO|<wsKey>|<cachedVer>|<type>   (type = bench Genre, from bench_config; optional/empty ok)
//   srv -> ws  : NX|WORLD_OK|<ver>                       cache valid -> WS boots from LSD, no transfer
//   srv -> ws  : NX|WORLD_BEGIN|<ver>|<nLines>
//   srv -> ws  : NX|WORLD_CHUNK|<ver>|<seq>|<payload>    payload = world lines joined by "\n"
//   srv -> ws  : NX|WORLD_END|<ver>|<nChunks>
//   srv -> ws  : NX|WORLD_WAIT                           world not ingested yet (retry on BUMP/soon)
//   srv -> *   : NX|WORLD_BUMP|<ver>                     world re-ingested with a new version
//
// Version: an "ver = <token>" header line in monde.nc, posted by the compiler (future contract). If absent,
// the server derives a folded-md5 content signature "sig-<hash>" so the mechanism works today. The header line
// is metadata: it is NOT stored as world data. Everything else is stored verbatim.
//
// Reservation model: reserve at pick / commit at take / release at discard. Held by the BENCH for the whole
// (possibly paused) craft: NO TTL, NO keep-alive. Freed only by COMMIT or RELEASE. RESERVE is declarative and
// idempotent; COMMIT/RELEASE idempotent by ticket state. Redo on loss. No ACK/sequence. Ever.

integer NX_STOCK = -918280;          // REVIEW: single channel for cold+hot for now (stock-protocol §7).

// ---- STOCK keys ----
// Ledger key  sv:q:<sid>   = "avail|expiryUnix|owner|dnaHash"   (avail = total minus units reserved by any ticket)
// Ticket key  sv:t:<tk>    = "<state>|<sid>:<u>^..."            state R=reserved C=committed X=released
// ---- WORLD keys ----
// w:ver  = version token      w:n = stored line count      w:<i> = i-th world data line (verbatim)
// ---- registry ----
// sv:bench:<wsKey> = last version served to that bench (info/admin only)

string  WORLD_NC = "monde.nc";       // preferred world notecard; else first card not named bench_config
integer WORLD_BUDGET = 900;          // max payload chars per WORLD_CHUNK (region say cap ~1024 bytes)

// ---- world ingest state ----
key     gWorldQ;                     // active notecard read handle
string  gWorldName;                  // notecard being ingested
integer gWorldLine;                  // current notecard line number
integer gWorldIx;                    // stored data-line count
string  gWorldSig;                   // folded content signature
string  gWorldVerHdr;                // explicit "ver =" header, if seen
string  gWorldPrevVer;               // version before this ingest (for BUMP)

sayTo(key who, string msg){ llRegionSayTo(who, NX_STOCK, msg); }
pushQty(key sid){
    string s = llLinksetDataRead("sv:q:" + (string)sid);
    integer q = 0;
    if(s != "") q = (integer)llList2String(llParseStringKeepNulls(s, ["|"], []), 0);
    llRegionSay(NX_STOCK, "NX|QTY|" + (string)sid + "|" + (string)q);
}
list qRead(key sid){
    string s = llLinksetDataRead("sv:q:" + (string)sid);
    if(s == "") return [];
    return llParseStringKeepNulls(s, ["|"], []);
}
qWrite(key sid, integer avail, integer expiry, key owner, string hash){
    // REVIEW: unchecked write result; clamp negatives; guard LSD-full.
    llLinksetDataWrite("sv:q:" + (string)sid, (string)avail + "|" + (string)expiry + "|" + (string)owner + "|" + hash);
}
integer qExpired(list r){ integer e = llList2Integer(r, 1); return e > 0 && llGetUnixTime() >= e; }

// ---------- REGISTER: seed-once, else reconcile (server avail wins; refresh metadata) ----------
reg(list f, key who){
    key sid = (key)llList2String(f, 2);
    if(sid == NULL_KEY) return;
    key owner = (key)llList2String(f, 3);
    string hash = llList2String(f, 4);
    integer expiry = (integer)llList2String(f, 5);
    integer initQty = (integer)llList2String(f, 6);
    list r = qRead(sid);
    if(llGetListLength(r) == 0) qWrite(sid, initQty, expiry, owner, hash);   // first-ever seed (REVIEW: trusts NC qty)
    else qWrite(sid, llList2Integer(r, 0), expiry, owner, hash);             // known: avail authoritative, refresh meta
    pushQty(sid);
}

// ---------- RESERVE: declarative set-reconcile, atomic, idempotent ----------
// The ticket's held set becomes exactly <pairs>. Positive deltas are checked against avail (all-or-nothing);
// negative deltas (unpick) always apply. Re-sending the same set changes nothing.
reserveSet(key ticket, string pairs, key who){
    list tr = llParseStringKeepNulls(llLinksetDataRead("sv:t:" + (string)ticket), ["|"], []);
    string tstate = llList2String(tr, 0);
    if(tstate == "C" || tstate == "X"){ sayTo(who, "NX|RES_NO|" + (string)ticket + "|"); return; }  // finalized ticket (state is reserved -> tstate)

    list cs; list cu;                              // current held
    list items = llParseStringKeepNulls(llList2String(tr, 1), ["^"], []);
    integer i;
    for(i = 0; i < llGetListLength(items); ++i){
        list kv = llParseStringKeepNulls(llList2String(items, i), [":"], []);
        if(llList2String(kv, 0) != ""){ cs += llList2String(kv, 0); cu += (integer)llList2String(kv, 1); }
    }
    list ds; list du;                              // desired held
    items = llParseStringKeepNulls(pairs, ["^"], []);
    for(i = 0; i < llGetListLength(items); ++i){
        list kv = llParseStringKeepNulls(llList2String(items, i), [":"], []);
        string sd = llList2String(kv, 0); integer u = (integer)llList2String(kv, 1);
        if(sd != "" && u > 0){ ds += sd; du += u; }
    }
    list uni = cs;
    for(i = 0; i < llGetListLength(ds); ++i)
        if(llListFindList(uni, [llList2String(ds, i)]) == -1) uni += llList2String(ds, i);

    string shortfall = "";                         // pass 1: check positive deltas
    for(i = 0; i < llGetListLength(uni); ++i){
        string sd = llList2String(uni, i);
        integer cuv = 0; integer ci = llListFindList(cs, [sd]); if(ci != -1) cuv = llList2Integer(cu, ci);
        integer duv = 0; integer di = llListFindList(ds, [sd]); if(di != -1) duv = llList2Integer(du, di);
        integer delta = duv - cuv;
        if(delta > 0){
            list r = qRead((key)sd); integer avail = 0; integer oksid = FALSE;
            if(llGetListLength(r) > 0 && !qExpired(r)){ avail = llList2Integer(r, 0); oksid = (avail >= delta); }
            if(!oksid){ if(shortfall != "") shortfall += "^"; shortfall += sd + ":" + (string)avail; }
        }
    }
    if(shortfall != ""){ sayTo(who, "NX|RES_NO|" + (string)ticket + "|" + shortfall); return; }

    for(i = 0; i < llGetListLength(uni); ++i){      // pass 2: apply deltas to avail
        string sd = llList2String(uni, i);
        integer cuv = 0; integer ci = llListFindList(cs, [sd]); if(ci != -1) cuv = llList2Integer(cu, ci);
        integer duv = 0; integer di = llListFindList(ds, [sd]); if(di != -1) duv = llList2Integer(du, di);
        integer delta = duv - cuv;
        if(delta != 0){
            list r = qRead((key)sd);
            if(llGetListLength(r) > 0)
                qWrite((key)sd, llList2Integer(r, 0) - delta, llList2Integer(r, 1), llList2Key(r, 2), llList2String(r, 3));
        }
        pushQty((key)sd);
    }
    string dp = "";                                 // persist desired held set
    for(i = 0; i < llGetListLength(ds); ++i){ if(dp != "") dp += "^"; dp += llList2String(ds, i) + ":" + (string)llList2Integer(du, i); }
    llLinksetDataWrite("sv:t:" + (string)ticket, "R|" + dp);
    sayTo(who, "NX|RES_OK|" + (string)ticket);
}

restoreUnits(string pairs){
    list items = llParseStringKeepNulls(pairs, ["^"], []);
    integer i;
    for(i = 0; i < llGetListLength(items); ++i){
        list kv = llParseStringKeepNulls(llList2String(items, i), [":"], []);
        key sid = (key)llList2String(kv, 0); integer u = (integer)llList2String(kv, 1);
        list r = qRead(sid);
        if(llGetListLength(r) > 0){
            qWrite(sid, llList2Integer(r, 0) + u, llList2Integer(r, 1), llList2Key(r, 2), llList2String(r, 3));
            pushQty(sid);
        }
    }
}

// ---------- COMMIT: finalize (held already subtracted); optional output SID ----------
commit(key ticket, list outF, key who){
    list tr = llParseStringKeepNulls(llLinksetDataRead("sv:t:" + (string)ticket), ["|"], []);
    string st = llList2String(tr, 0);
    if(st == ""){ sayTo(who, "NX|COMMIT_NO|" + (string)ticket); return; }
    if(st == "C"){ sayTo(who, "NX|COMMIT_OK|" + (string)ticket); return; }   // idempotent
    if(st != "R"){ sayTo(who, "NX|COMMIT_NO|" + (string)ticket); return; }
    string held = llList2String(tr, 1);
    llLinksetDataWrite("sv:t:" + (string)ticket, "C|" + held);
    if(llGetListLength(outF) >= 3){                                         // OUT newSid qty dnaHash
        key nsid = (key)llList2String(outF, 0);
        integer q = (integer)llList2String(outF, 1);
        string hash = llList2String(outF, 2);
        if(nsid != NULL_KEY && llLinksetDataRead("sv:q:" + (string)nsid) == ""){   // create once (pending product may have no object)
            qWrite(nsid, q, 0, llGetOwnerKey(who), hash);                   // REVIEW: expiry/owner placeholder until the blank REGISTERs
            pushQty(nsid);
        }
    }
    list items = llParseStringKeepNulls(held, ["^"], []);                   // refresh consumed inputs (avail already reduced)
    integer i;
    for(i = 0; i < llGetListLength(items); ++i)
        pushQty((key)llList2String(llParseStringKeepNulls(llList2String(items, i), [":"], []), 0));
    sayTo(who, "NX|COMMIT_OK|" + (string)ticket);
}

release(key ticket, key who){
    list tr = llParseStringKeepNulls(llLinksetDataRead("sv:t:" + (string)ticket), ["|"], []);
    if(llList2String(tr, 0) == "R"){
        restoreUnits(llList2String(tr, 1));
    }
    llLinksetDataDelete("sv:t:" + (string)ticket);   // delete (not "X") so the ticket is reusable for the next pick
    sayTo(who, "NX|REL_OK|" + (string)ticket);
}

discard(key sid, key who){
    list r = qRead(sid);
    // REVIEW: discard auth — restrict to the SID's stored owner to avoid griefing someone else's stock.
    if(llGetListLength(r) > 0 && llGetOwnerKey(who) == llList2Key(r, 2))
        qWrite(sid, 0, llList2Integer(r, 1), llList2Key(r, 2), llList2String(r, 3));
    pushQty(sid);
}

// ============================================================
//  WORLD plane — ingest monde.nc into LSD, then stream on demand
// ============================================================

// notecard to ingest: WORLD_NC if present, else first card that is NOT bench_config
string pickWorldNC(){
    if(llGetInventoryType(WORLD_NC) == INVENTORY_NOTECARD) return WORLD_NC;
    integer n = llGetInventoryNumber(INVENTORY_NOTECARD);
    integer i;
    for(i = 0; i < n; ++i){
        string nm = llGetInventoryName(INVENTORY_NOTECARD, i);
        if(llToLower(nm) != "bench_config") return nm;
    }
    return "";
}

// wipe the w:* buffer (never touches sv:* stock or registry)
wipeWorld(){
    list keys = llLinksetDataFindKeys("^w:", 0, 512);
    integer guard = 0;
    while(llGetListLength(keys) > 0 && guard < 20000){
        integer L = llGetListLength(keys); integer i;
        for(i = 0; i < L; ++i) llLinksetDataDelete(llList2String(keys, i));
        guard += L;
        keys = llLinksetDataFindKeys("^w:", 0, 512);
    }
}

startWorldIngest(){
    gWorldPrevVer = llLinksetDataRead("w:ver");
    wipeWorld();
    gWorldLine = 0; gWorldIx = 0; gWorldSig = ""; gWorldVerHdr = "";
    gWorldName = pickWorldNC();
    if(gWorldName == ""){ llOwnerSay("[Nexus] server: no world notecard (drop '" + WORLD_NC + "')."); return; }
    llOwnerSay("[Nexus] server ingesting world '" + gWorldName + "'...");
    gWorldQ = llGetNotecardLine(gWorldName, 0);
}

// stream the cached world to one bench, synchronously from LSD (concurrent-safe)
streamWorld(key who, string ver){
    integer n = (integer)llLinksetDataRead("w:n");
    sayTo(who, "NX|WORLD_BEGIN|" + ver + "|" + (string)n);
    integer i = 0; integer seq = 0; string buf = "";
    while(i < n){
        string line = llLinksetDataRead("w:" + (string)i);
        if(buf != "" && llStringLength(buf) + 1 + llStringLength(line) > WORLD_BUDGET){
            sayTo(who, "NX|WORLD_CHUNK|" + ver + "|" + (string)seq + "|" + buf);
            ++seq; buf = "";
        }
        if(buf == "") buf = line; else buf += "\n" + line;
        ++i;
    }
    if(buf != ""){ sayTo(who, "NX|WORLD_CHUNK|" + ver + "|" + (string)seq + "|" + buf); ++seq; }
    sayTo(who, "NX|WORLD_END|" + ver + "|" + (string)seq);
}

hello(key wsKey, string cachedVer, string genre, key who){
    string ver = llLinksetDataRead("w:ver");
    if(ver == ""){ sayTo(who, "NX|WORLD_WAIT"); return; }         // world not ingested yet
    llLinksetDataWrite("sv:bench:" + (string)wsKey, ver + "|" + genre);   // registry: "<ver>|<type>" (info/admin)
    if(cachedVer == ver){ sayTo(who, "NX|WORLD_OK|" + ver); return; }
    streamWorld(who, ver);
}

// ---------- admin: dump the registered benches (owner touch) ----------
// Lists the sv:bench:* registry: each WS key that has said HELLO, with the world version last served to it.
dumpBenches(){
    list ks = llLinksetDataFindKeys("^sv:bench:", 0, 256);
    integer n = llGetListLength(ks);
    llOwnerSay("[Nexus] server dump | world ver " + llLinksetDataRead("w:ver")
        + " (" + llLinksetDataRead("w:n") + " lines) | benches registered: " + (string)n);
    integer i;
    for(i = 0; i < n; ++i){
        string k = llList2String(ks, i);
        list bv = llParseStringKeepNulls(llLinksetDataRead(k), ["|"], []);   // "<ver>|<type>"
        string ty = llList2String(bv, 1); if(ty == "") ty = "(unconfigured)";
        llOwnerSay("  WS " + llGetSubString(k, 9, -1) + " | genre " + ty + " | world " + llList2String(bv, 0));   // strip "sv:bench:" (9 chars)
    }
    if(n == 0) llOwnerSay("  (no bench has said HELLO yet)");
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_STOCK, "", NULL_KEY, "");
        llRegionSay(NX_STOCK, "NX|SERVER|" + (string)llGetKey());   // announce presence (clients refresh cached key)
        startWorldIngest();                                         // ingest world into LSD (cold plane)
    }
    on_rez(integer p){ llResetScript(); }
    touch_start(integer tn)                                      // owner: dump + push a world-update to all benches
    {
        if(llDetectedKey(0) != llGetOwner()) return;
        dumpBenches();
        string ver = llLinksetDataRead("w:ver");
        if(ver != ""){
            llRegionSay(NX_STOCK, "NX|WORLD_BUMP|" + ver);       // force every bench to re-HELLO and re-sync
            llOwnerSay("[Nexus] server pushed WORLD_BUMP " + ver + " to all benches.");
        }
    }
    changed(integer c)
    {
        if(c & CHANGED_OWNER){ llResetScript(); return; }
        if(c & CHANGED_INVENTORY) startWorldIngest();               // new monde.nc dropped -> re-ingest + BUMP
    }

    dataserver(key id, string data)
    {
        if(id != gWorldQ) return;
        if(data == EOF){
            llLinksetDataWrite("w:n", (string)gWorldIx);
            string ver = gWorldVerHdr;
            if(ver == "") ver = "sig-" + gWorldSig;
            llLinksetDataWrite("w:ver", ver);
            llOwnerSay("[Nexus] server world ready: " + (string)gWorldIx + " lines, ver " + ver);
            if(gWorldPrevVer != "" && gWorldPrevVer != ver)
                llRegionSay(NX_STOCK, "NX|WORLD_BUMP|" + ver);      // tell benches to re-HELLO
            return;
        }
        string line = llStringTrim(data, STRING_TRIM);
        if(line != "" && llGetSubString(line, 0, 0) != "#"){
            integer sep = llSubStringIndex(line, "=");
            string kk = "";
            if(sep > 0) kk = llStringTrim(llGetSubString(line, 0, sep - 1), STRING_TRIM);
            if(kk == "ver"){                                        // version header: metadata, not world data
                gWorldVerHdr = llStringTrim(llGetSubString(line, sep + 1, -1), STRING_TRIM);
            } else {
                llLinksetDataWrite("w:" + (string)gWorldIx, line);  // store verbatim (opaque payload)
                gWorldSig = llMD5String(gWorldSig + line, 0);       // fold content signature (fallback version)
                ++gWorldIx;
            }
        }
        gWorldQ = llGetNotecardLine(gWorldName, ++gWorldLine);
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_STOCK) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);

        // --- world plane ---
        if(verb == "HELLO" && llGetListLength(f) >= 4){ hello((key)llList2String(f, 2), llList2String(f, 3), llList2String(f, 4), who); return; }   // f[4] type, "" if absent

        // --- stock plane ---
        if(verb == "DISCOVER"){
            if(llList2Key(f, 2) == llGetOwner() && llList2String(f, 3) == llGetObjectName())
                sayTo(who, "NX|SERVER|" + (string)llGetKey());
            return;
        }
        if(verb == "REGISTER" && llGetListLength(f) == 7){ reg(f, who); return; }
        if(verb == "RESERVE"  && llGetListLength(f) == 4){ reserveSet((key)llList2String(f, 2), llList2String(f, 3), who); return; }
        if(verb == "COMMIT"   && llGetListLength(f) >= 3){ commit((key)llList2String(f, 2), llList2List(f, 4, -1), who); return; }
        if(verb == "RELEASE"  && llGetListLength(f) == 3){ release((key)llList2String(f, 2), who); return; }
        if(verb == "DISCARD"  && llGetListLength(f) == 3){ discard((key)llList2String(f, 2), who); return; }
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT) nexusMemReport();
    }
}
// REVIEW: no TTL sweep. A reservation is held until COMMIT/RELEASE (the bench owns the craft). If the bench
// itself is derezzed mid-craft, its ticket orphans; a very long safety sweep could reclaim it later (stock-protocol §7).
// REVIEW: committed/released tickets (sv:t C/X) are never pruned -> add retention/GC before scaling.
// REVIEW: world ingest trusts the NC; md5-fold is one-time at boot. Explicit "ver =" header (compiler) overrides.
// REVIEW: sv:bench:* registry is info-only and never pruned; a cold-plane BUMP is broadcast, not per-bench.
