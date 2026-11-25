#define SCRIPT_NAME    "WS_Output"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// WS_Output — bench output face (socle §7): hands the forged product to a récipient by CONFIGuring it
// on NX_SCAN, so a blank container adopts the output SID and becomes a product component (it then
// REGISTERs the SID with the server, which already holds its quantity from the COMMIT|OUT).
//
//   WS_Core -> WS_Output (link OUTPUT_CONFIG):
//     "<container>|<newSid>|<name>|<use>|<life>|<tax>|<stage>|<props>|<med>|<eff>"
//     <container> = a chosen blank's key (P3), or "" to auto-pick the first empty container nearby (V1).
//   WS_Output -> WS_Core (link OUTPUT_DONE):
//     "OK|<container>"            the CONFIG was dispatched
//     "FAIL|<reason>"             no empty container found (auto-pick)
//
//   WS_Output -> container (NX_SCAN):
//     CONFIG|<objkey>|<sid>|<name>|<use>|<life>|<taxonomy>|<stage>|<props>|<med>|<eff>   (NX_Component format)
//
// IMPORTANT ordering: the server must have created sv:q:<newSid> (COMMIT|OUT confirmed) BEFORE the container
// REGISTERs the SID — otherwise a blank seeds it at qty 0. WS_Core only sends OUTPUT_CONFIG after
// STOCK_COMMIT_DONE, so that ordering is guaranteed upstream.

integer NX_SCAN = -918281;
integer OUTPUT_CONFIG = 918440;      // <- WS_Core: CONFIG a récipient with a transformed product
integer OUTPUT_GIVE   = 918442;      // <- WS_Core: hand out source mesh(es) directly (give/harvest)
integer OUTPUT_DONE   = 918441;      // -> WS_Core
float   SCAN_WAIT = 2.0;             // auto-pick blank-scan window (absorbs PING -> BLANK)

list    gPend;                       // pending config fields (0 container,1 sid,2 name,3 use,4 life,5 tax,6 stage,7 props,8 med,9 eff)
list    gBlanks;                     // blank container keys collected during an auto-pick scan

doConfig(key container)
{
    string wire = "CONFIG|" + (string)container
        + "|" + llList2String(gPend, 1) + "|" + llList2String(gPend, 2)
        + "|" + llList2String(gPend, 3) + "|" + llList2String(gPend, 4)
        + "|" + llList2String(gPend, 5) + "|" + llList2String(gPend, 6)
        + "|" + llList2String(gPend, 7) + "|" + llList2String(gPend, 8)
        + "|" + llList2String(gPend, 9);
    llRegionSay(NX_SCAN, wire);
    llMessageLinked(LINK_SET, OUTPUT_DONE, "OK|" + (string)container, NULL_KEY);
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_SCAN, "", NULL_KEY, "");
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(num == OUTPUT_CONFIG){
            gPend = llParseStringKeepNulls(str, ["|"], []);
            if(llGetListLength(gPend) < 10){ gPend = []; return; }
            string container = llList2String(gPend, 0);
            if(container != ""){ doConfig((key)container); gPend = []; return; }
            // auto-pick: scan for the first empty container owned by us
            gBlanks = [];
            llRegionSay(NX_SCAN, "PING");
            llSetTimerEvent(SCAN_WAIT);
            return;
        }
        if(num == OUTPUT_GIVE){
            // str = "<holder>|<organs>|<srcKey>^<srcKey>..."  (organs empty = each source's single mesh)
            list g = llParseStringKeepNulls(str, ["|"], []);
            key holder = (key)llList2String(g, 0);
            string organs = llList2String(g, 1);
            list srcs = llParseStringKeepNulls(llList2String(g, 2), ["^"], []);
            integer i;
            for(i = 0; i < llGetListLength(srcs); i++){
                key src = (key)llList2String(srcs, i);
                if(src != NULL_KEY){
                    llRegionSay(NX_SCAN, "CUT|" + (string)src + "|" + (string)holder);   // record the recipient
                    if(organs != "") llRegionSay(NX_SCAN, "GIVE|" + (string)src + "|" + organs);
                    else             llRegionSay(NX_SCAN, "GIVE|" + (string)src);
                }
            }
            return;   // WS_Core closes the craft itself on a give (no container round-trip)
        }
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_SCAN || llGetListLength(gPend) == 0) return;
        list p = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(p, 0) != "BLANK") return;
        key src = (key)llList2String(p, 1);
        if(src == NULL_KEY || llGetOwnerKey(src) != llGetOwner()) return;
        if(llListFindList(gBlanks, [src]) == -1) gBlanks += src;
    }

    timer()
    {
        llSetTimerEvent(0.0);
        if(llGetListLength(gPend) == 0) return;
        if(llGetListLength(gBlanks) == 0){
            llMessageLinked(LINK_SET, OUTPUT_DONE, "FAIL|no empty container nearby", NULL_KEY);
            gPend = [];
            return;
        }
        doConfig(llList2Key(gBlanks, 0));
        gPend = [];
    }
}
