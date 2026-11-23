#define SCRIPT_NAME    "WS_Stock"
#define SCRIPT_VERSION "v0.1.1"
#include "nexus_header"

// WS_Stock — bench stock client. Holds the craft basket and reserves it with the server. The HUD never
// talks to the server: it sends picks here over NX_HUD; this reserves on NX_STOCK; the basket is pushed
// back to the HUD for display + the Continue gate.
//
//   HUD -> WS_Stock (NX_HUD):
//     NX|PICK|<session>|<sid>|<u>|<name>|<icon>      add u of sid to the basket
//     NX|UNPICK|<session>|<sid>                      remove sid from the basket
//   WS_Stock -> HUD (NX_HUD, to the holder):
//     NX|BASKET|<session>|<count>|sid~name~qty~icon^...  the current basket (for the SELECTED panel)
//     NX|PICKNO|<session>|<sid>|<avail>              a pick was refused (not enough available)
//   WS_Stock <-> server (NX_STOCK, declarative):
//     NX|RESERVE|<ticket>|sid:u^...  -> NX|RES_OK|<ticket> | NX|RES_NO|<ticket>|sid:avail^...
//     NX|RELEASE|<ticket>            -> NX|REL_OK|<ticket>
//
// ticket = the bench craft session (state:session), shared with WS_Core. holder = state:lock.
// Basket persisted in state:stock = "sid~u~name~icon^..." so it survives a reset / HUD loss (§8:
// freeLock keeps it; only a take/discard releases). WS_Core signals discard via link STOCK_RELEASE_REQ.

integer NX_HUD   = -918282;
integer NX_STOCK = -918280;
integer STOCK_RELEASE_REQ = 918250;   // link from WS_Core: take/discard -> release the whole ticket

float   SRV_WAIT = 3.0;                // seconds to wait for a server reply before giving up
string  gPendSid = "";                 // sid of a pick awaiting a server reply ("" = idle)

// ---- basket helpers (LSD state:stock = "sid~u~name~icon^...") ----
list basketList(){
    string s = llLinksetDataRead("state:stock");
    if(s == "") return [];
    return llParseStringKeepNulls(s, ["^"], []);
}
saveBasket(list b){ llLinksetDataWrite("state:stock", llDumpList2String(b, "^")); }

integer findSid(list b, string sid){
    integer i;
    for(i = 0; i < llGetListLength(b); ++i)
        if(llList2String(llParseStringKeepNulls(llList2String(b, i), ["~"], []), 0) == sid) return i;
    return -1;
}

// declarative set for the server: "sid:u^sid:u..."
string serverSet(list b){
    string out = "";
    integer i;
    for(i = 0; i < llGetListLength(b); ++i){
        list e = llParseStringKeepNulls(llList2String(b, i), ["~"], []);
        if(out != "") out += "^";
        out += llList2String(e, 0) + ":" + llList2String(e, 1);
    }
    return out;
}

reserveNow(){                          // (re)send the whole declarative set for the current ticket
    string ticket = llLinksetDataRead("state:session");
    if(ticket == "") return;
    list b = basketList();
    if(llGetListLength(b) == 0){        // empty basket -> release the ticket instead of reserving nothing
        llRegionSay(NX_STOCK, "NX|RELEASE|" + ticket);
        return;
    }
    llRegionSay(NX_STOCK, "NX|RESERVE|" + ticket + "|" + serverSet(b));
    llSetTimerEvent(SRV_WAIT);
}

pushBasket(){
    string holder = llLinksetDataRead("state:lock");
    string ticket = llLinksetDataRead("state:session");
    if(holder == "") return;
    list b = basketList();
    string lines = "";
    integer i;
    for(i = 0; i < llGetListLength(b); ++i){
        list e = llParseStringKeepNulls(llList2String(b, i), ["~"], []);
        if(lines != "") lines += "^";
        // e = sid~u~name~icon  ->  BASKET line sid~name~qty~icon
        lines += llList2String(e, 0) + "~" + llList2String(e, 2) + "~" + llList2String(e, 1) + "~" + llList2String(e, 3);
    }
    llRegionSayTo((key)holder, NX_HUD,
        "NX|BASKET|" + ticket + "|" + (string)llGetListLength(b) + "|" + lines);
}

// Ask the holder's HUD to re-scan NEARBY. The server just changed availability (this bench OR another
// workshop reserving the same sid), so the authoritative qty must come from a fresh component scan, not a
// local decrement. The scan window (2 s) absorbs the server->component NX|QTY propagation.
rescanHud(){
    string holder = llLinksetDataRead("state:lock");
    string ticket = llLinksetDataRead("state:session");
    if(holder == "" || ticket == "") return;
    llRegionSayTo((key)holder, NX_HUD, "NX|RESCAN|" + ticket);
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_HUD, "", NULL_KEY, "");
        llListen(NX_STOCK, "", NULL_KEY, "");
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(num == STOCK_RELEASE_REQ){                  // WS_Core: take/discard -> release + clear
            string ticket = llLinksetDataRead("state:session");
            if(ticket != "") llRegionSay(NX_STOCK, "NX|RELEASE|" + ticket);
            llLinksetDataDelete("state:stock");
            gPendSid = ""; llSetTimerEvent(0.0);
            return;
        }
    }

    listen(integer chan, string nm, key who, string msg)
    {
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);
        string ticket = llLinksetDataRead("state:session");

        if(chan == NX_HUD){
            if(ticket == "" || llList2String(f, 2) != ticket) return;   // only our craft session
            // the pick must come from the holder's own attachment
            string holder = llLinksetDataRead("state:lock");
            if(holder == "" || who == NULL_KEY || llGetOwnerKey(who) != (key)holder) return;

            if(verb == "PICK"){
                string sid = llList2String(f, 3);
                integer u  = (integer)llList2String(f, 4);
                string name = llList2String(f, 5);
                string icon = llList2String(f, 6);
                if(sid == "" || u <= 0) return;
                list b = basketList();
                integer i = findSid(b, sid);
                if(i == -1) b += [sid + "~" + (string)u + "~" + name + "~" + icon];
                else {
                    list e = llParseStringKeepNulls(llList2String(b, i), ["~"], []);
                    integer nu = (integer)llList2String(e, 1) + u;
                    b = llListReplaceList(b, [sid + "~" + (string)nu + "~" + llList2String(e,2) + "~" + llList2String(e,3)], i, i);
                }
                saveBasket(b);
                gPendSid = sid;                         // remember to revert this pick on RES_NO/timeout
                reserveNow();
                pushBasket();                           // optimistic; corrected on RES_NO
                return;
            }
            if(verb == "UNPICK"){
                string sid = llList2String(f, 3);
                list b = basketList();
                integer i = findSid(b, sid);
                if(i != -1){ b = llDeleteSubList(b, i, i); saveBasket(b); reserveNow(); pushBasket(); }
                return;
            }
            return;
        }

        if(chan == NX_STOCK){
            if(llGetListLength(f) < 3 || llList2String(f, 2) != ticket) return;  // our ticket only
            if(verb == "RES_OK"){ gPendSid = ""; llSetTimerEvent(0.0); rescanHud(); return; }
            if(verb == "RES_NO"){
                // not enough: revert the pending pick and tell the HUD
                string avail = "";
                list short = llParseStringKeepNulls(llList2String(f, 3), ["^"], []);
                if(gPendSid != ""){
                    list b = basketList();
                    integer i = findSid(b, gPendSid);
                    if(i != -1){ b = llDeleteSubList(b, i, i); saveBasket(b); }
                    integer k;
                    for(k = 0; k < llGetListLength(short); ++k){
                        list pr = llParseStringKeepNulls(llList2String(short, k), [":"], []);
                        if(llList2String(pr, 0) == gPendSid) avail = llList2String(pr, 1);
                    }
                    string holder = llLinksetDataRead("state:lock");
                    if(holder != "") llRegionSayTo((key)holder, NX_HUD, "NX|PICKNO|" + ticket + "|" + gPendSid + "|" + avail);
                }
                gPendSid = ""; llSetTimerEvent(0.0);
                reserveNow();                           // re-assert the corrected set
                pushBasket();
                rescanHud();                            // avail changed -> refresh NEARBY from a scan
                return;
            }
            if(verb == "REL_OK"){ rescanHud(); return; }
            return;
        }
    }

    timer()   // server reply timeout -> treat as unreachable, revert the pending pick
    {
        llSetTimerEvent(0.0);
        if(gPendSid == "") return;
        list b = basketList();
        integer i = findSid(b, gPendSid);
        if(i != -1){ b = llDeleteSubList(b, i, i); saveBasket(b); }
        string holder = llLinksetDataRead("state:lock");
        if(holder != "") llRegionSayTo((key)holder, NX_HUD, "NX|PICKNO|" + llLinksetDataRead("state:session") + "|" + gPendSid + "|SRVDOWN");
        gPendSid = "";
        pushBasket();
    }
}
// REVIEW: 2026-11-19 — SRV_WAIT timeout treats any missing reply as server-down; a slow server could drop a valid pick. Redo on next pick.
// REVIEW: 2026-11-19 — RES_NO reverts only the last pending pick; concurrent picks are not expected (one HUD per bench).
// REVIEW: 2026-11-19 — COMMIT (take) not wired yet; comes with the craft take/output flow.
