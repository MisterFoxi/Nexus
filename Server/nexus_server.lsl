#define SCRIPT_NAME    "Nexus_Server"
#define SCRIPT_VERSION "v0.2.0"
#include "nexus_header.lsl"

// Nexus stock server (Model 1: physical objects + server referee).
// Authority on QUANTITIES only. See dev/stock-protocol.md.
// Single fixed prim. Ledger + ticket holds live in LinksetData, survive reset/re-rez.
//
// Wire (region say on NX_STOCK, fields "|"):
//   component -> srv : NX|REGISTER|<sid>|<owner>|<dnaHash>|<expiryUnix>|<initQty>
//   srv -> *         : NX|QTY|<sid>|<available>          (available = total minus all reserved)
//   any -> srv       : NX|DISCOVER|<owner>|<name>        srv -> who : NX|SERVER|<srvKey>
//   ws  -> srv       : NX|RESERVE|<ticket>|<sid>:<u>^... (DECLARATIVE: the ticket should hold exactly this set)
//                      srv -> ws : NX|RES_OK|<ticket> | NX|RES_NO|<ticket>|<sid>:<avail>^...
//   ws  -> srv       : NX|COMMIT|<ticket>[|OUT|<newSid>|<qty>|<dnaHash>]  srv -> ws : NX|COMMIT_OK|<ticket> | NX|COMMIT_NO|<ticket>
//   ws  -> srv       : NX|RELEASE|<ticket>               srv -> ws : NX|REL_OK|<ticket>   (whole ticket; unpick = a smaller RESERVE)
//   any -> srv       : NX|DISCARD|<sid>                  srv -> * : NX|QTY|<sid>|0
//
// Model: reserve at pick / commit at take / release at discard. The reservation is held by the BENCH for the
// whole (possibly paused) craft: NO TTL, NO keep-alive. Freed only by COMMIT or RELEASE (a human act). RESERVE
// is declarative and idempotent by construction (re-sending the same set is a no-op); COMMIT/RELEASE idempotent
// by ticket state. Redo on loss. No ACK/sequence. Ever.

integer NX_STOCK = -918280;          // REVIEW: single channel for cold+hot for now (stock-protocol §7).

// Ledger key  sv:q:<sid>  = "avail|expiryUnix|owner|dnaHash"   (avail = total minus units reserved by any ticket)
// Ticket key  sv:t:<tk>   = "<state>|<sid>:<u>^..."            state R=reserved C=committed X=released

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
    string state = llList2String(tr, 0);
    if(state == "C" || state == "X"){ sayTo(who, "NX|RES_NO|" + (string)ticket + "|"); return; }  // finalized ticket

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
        llLinksetDataWrite("sv:t:" + (string)ticket, "X|" + llList2String(tr, 1));
    }
    sayTo(who, "NX|REL_OK|" + (string)ticket);
}

discard(key sid, key who){
    list r = qRead(sid);
    // REVIEW: discard auth — restrict to the SID's stored owner to avoid griefing someone else's stock.
    if(llGetListLength(r) > 0 && llGetOwnerKey(who) == llList2Key(r, 2))
        qWrite(sid, 0, llList2Integer(r, 1), llList2Key(r, 2), llList2String(r, 3));
    pushQty(sid);
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_STOCK, "", NULL_KEY, "");
        llRegionSay(NX_STOCK, "NX|SERVER|" + (string)llGetKey());   // announce presence (clients refresh cached key)
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_STOCK) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);

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
