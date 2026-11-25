#define SCRIPT_NAME    "NX_P3_Controller"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// NX_P3_Controller — ROOT. Récipient-selection page of the refonte take flow. Replaces MC_P3_Controller
// (no mc:workshop:session, no 918390/918391/918392 MCW transfer; a single NX|CONTAINER to the bench).
//
//   bench -> HUD (NX_HUD):
//     NX|OUTPUT|<session>|WAIT_CONTAINER|<qty>   open P3, scan empty containers, let the player choose
//     NX|TAKEDONE|<newSession>|<note>            craft closed -> close P3
//   HUD -> bench (NX_HUD):
//     NX|CONTAINER|<session>|<containerKey>       the chosen récipient (WS_Core commits + CONFIGs it)
//
// Scanning uses NX_Scan (918270 -> 918271/273/274) on NX_SCAN (-918281); we keep only BLANK containers.
// Rendering uses two NX_Render instances (PANEL "P3_NEAR" / "P3_SEL") via VIEW 918290. Rotation to/from the
// P3 page is NX_Turn_Z's job, driven by the 918391 phase we emit (WAIT_CONTAINER -> P3, CLOSED -> P0).
//
// V1: one take delivers the whole lot into ONE chosen container (the server SID is the stock identity;
// splitting across containers with capacities is a later feature). Selection is therefore single-type.

integer NX_HUD    = -918282;
integer BIND_INFO = 918260;            // <- NX_HudFace: "<bench>|<session>"
integer VIEW      = 918290;
integer RENDER_READY = 918291;
integer OUTPUT_PHASE = 918391;         // -> NX_Turn_Z / NX_P4: "<phase>|..." (WAIT_CONTAINER -> P3, CLOSED -> P0)
integer SCAN_REFRESH = 918270;         // -> NX_Scan
integer SCAN_BEGIN   = 918271;
integer SCAN_ITEM    = 918272;         // HERE ingredients (ignored here)
integer SCAN_BLANK   = 918273;         // BLANK|objkey|capacity[|icon]
integer SCAN_END     = 918274;
float   SCAN_SECONDS = 10.0;

key     gBench = NULL_KEY;
string  gSession = "";
integer gOpen;
integer gBusy;                         // a container was sent; waiting for TAKEDONE

// scan buffers
key     gScan = NULL_KEY;
integer gScanning;
integer gReceiving;
list    gNear;                         // stride 3: uuid, name, capacity
list    gIcons;                        // stride 2: uuid, icon
list    gPending;
list    gPendingIcons;

// current single selection
string  gSel = "";
string  gSelName = "";
string  gSelIcon = "";
integer gNearPage;

string iconFor(key src)
{
    integer i;
    for(i = 0; i < llGetListLength(gIcons); i += 2)
        if(llList2Key(gIcons, i) == src) return llList2String(gIcons, i + 1);
    return "";
}
integer findNear(key src)
{
    integer i;
    for(i = 0; i < llGetListLength(gNear); i += 3)
        if(llList2Key(gNear, i) == src) return i;
    return -1;
}
integer findNearPending(key src)
{
    integer i;
    for(i = 0; i < llGetListLength(gPending); i += 3)
        if(llList2Key(gPending, i) == src) return i;
    return -1;
}
// group the available containers by name+icon -> stride 3: name, count, icon
list grouped()
{
    list g;
    integer i;
    for(i = 0; i < llGetListLength(gNear); i += 3){
        key src = llList2Key(gNear, i);
        string nm = llList2String(gNear, i + 1);
        string ic = iconFor(src);
        integer m = -1;
        integer j;
        for(j = 0; j < llGetListLength(g); j += 3)
            if(llList2String(g, j) == nm && llList2String(g, j + 2) == ic) m = j;
        if(m < 0) g += [nm, 1, ic];
        else g = llListReplaceList(g, [llList2Integer(g, m + 1) + 1], m + 1, m + 1);
    }
    return g;
}

string packView(list v)
{
    string s = "";
    integer i;
    for(i = 0; i < 18; ++i){ if(i) s += "|"; s += llEscapeURL(llList2String(v, i)); }
    return s;
}

render()
{
    list ng = grouped();
    integer total = (llGetListLength(ng) / 3 + 3) / 4;
    if(total < 1) total = 1;
    if(gNearPage >= total) gNearPage = total - 1;
    if(gNearPage < 0) gNearPage = 0;
    list v = [gNearPage + 1, total];
    integer row;
    for(row = 0; row < 4; ++row){
        integer off = (gNearPage * 4 + row) * 3;
        if(off >= llGetListLength(ng)) v += ["", 0, "", 0];
        else v += [llList2String(ng, off), llList2Integer(ng, off + 1), llList2String(ng, off + 2), 1];
    }
    llMessageLinked(LINK_THIS, VIEW, packView(v), (key)"P3_NEAR");

    list sv = [1, 1];
    if(gSel != "") sv += [gSelName, 1, gSelIcon, 1];
    else sv += ["", 0, "", 0];
    sv += ["", 0, "", 0, "", 0, "", 0, "", 0, "", 0];
    llMessageLinked(LINK_THIS, VIEW, packView(sv), (key)"P3_SEL");
}

scan()
{
    gScan = llGenerateKey();
    gScanning = TRUE; gReceiving = FALSE;
    gPending = []; gPendingIcons = [];
    llMessageLinked(LINK_THIS, SCAN_REFRESH, "", gScan);   // "" -> NX_SCAN (-918281)
    llSetTimerEvent(SCAN_SECONDS);
}

openP3(string qty)
{
    gOpen = TRUE; gBusy = FALSE; gSel = ""; gSelName = ""; gSelIcon = "";
    gNear = []; gIcons = []; gNearPage = 0;
    llMessageLinked(LINK_SET, OUTPUT_PHASE, "WAIT_CONTAINER|" + qty + "|", NULL_KEY);   // NX_Turn_Z -> P3
    scan();
    render();
}
closeP3()
{
    gOpen = FALSE; gBusy = FALSE; gSel = ""; gSelName = ""; gSelIcon = "";
    gNear = []; gIcons = []; gScanning = FALSE; gReceiving = FALSE;
    llSetTimerEvent(0.0);
    llMessageLinked(LINK_SET, OUTPUT_PHASE, "CLOSED|0|", NULL_KEY);                     // NX_Turn_Z -> P0
    render();
}

selectRow(integer i)
{
    list ng = grouped();
    integer off = (gNearPage * 4 + i) * 3;
    if(off >= llGetListLength(ng)) return;
    string nm = llList2String(ng, off);
    string ic = llList2String(ng, off + 2);
    integer c;
    for(c = 0; c < llGetListLength(gNear); c += 3)
        if(llList2String(gNear, c + 1) == nm && iconFor(llList2Key(gNear, c)) == ic){
            gSel = (string)llList2Key(gNear, c); gSelName = nm; gSelIcon = ic;
            render();
            return;
        }
}

transfer()
{
    if(gBusy){ llRegionSayTo(llGetOwner(), 0, "[Nexus] Transfert déjà en cours."); return; }
    if(gSel == ""){ llRegionSayTo(llGetOwner(), 0, "[Nexus] Choisis un récipient d'abord."); return; }
    if(gBench == NULL_KEY || gSession == ""){ llRegionSayTo(llGetOwner(), 0, "[Nexus] HUD non associé."); return; }
    llRegionSayTo(gBench, NX_HUD, "NX|CONTAINER|" + gSession + "|" + gSel);
    gBusy = TRUE;
    llRegionSayTo(llGetOwner(), 0, "[Nexus] Transfert en cours...");
}

button(string name)
{
    if(llGetSubString(name, 0, 2) != "p3_") return;
    if(!gOpen){ return; }
    if(name == "p3_action1" || name == "p3_refresh"){ if(!gBusy) scan(); return; }
    if(name == "p3_action2" || name == "p3_action"){ transfer(); return; }
    if(name == "p3_near_prev"){
        integer total = (llGetListLength(grouped()) / 3 + 3) / 4; if(total < 1) total = 1;
        gNearPage = (gNearPage + total - 1) % total; render(); return;
    }
    if(name == "p3_near_next"){
        integer total = (llGetListLength(grouped()) / 3 + 3) / 4; if(total < 1) total = 1;
        gNearPage = (gNearPage + 1) % total; render(); return;
    }
    if(name == "p3_sel_rem_0"){ gSel = ""; gSelName = ""; gSelIcon = ""; render(); return; }
    integer i;
    for(i = 0; i < 4; ++i)
        if(name == "p3_sel_" + (string)i){ if(!gBusy) selectRow(i); return; }
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_HUD, "", NULL_KEY, "");
        gOpen = FALSE;
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    touch_start(integer n)
    {
        integer i;
        for(i = 0; i < n; ++i)
            if(llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_HUD) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);
        if(who != NULL_KEY && gBench != NULL_KEY && llGetOwnerKey(who) != llGetOwnerKey(gBench)) return;

        if(verb == "OUTPUT"){
            if(llList2String(f, 2) != gSession) return;
            if(llList2String(f, 3) != "WAIT_CONTAINER") return;
            openP3(llList2String(f, 4));
            return;
        }
        if(verb == "TAKEDONE"){                 // new session in f[2]; accept from our bench, close the page
            if(who != gBench) return;
            if(gOpen) closeP3();
            return;
        }
    }

    link_message(integer sender, integer number, string payload, key request)
    {
        if(number == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(number == BIND_INFO){
            list bi = llParseStringKeepNulls(payload, ["|"], []);
            gBench = (key)llList2String(bi, 0); gSession = llList2String(bi, 1);
            return;
        }
        if(number == RENDER_READY && sender == llGetLinkNumber()
            && (payload == "P3_NEAR" || payload == "P3_SEL")){ render(); return; }

        // scan results (filtered by our request UUID; ignore the +10 NEARBY relays)
        if(number == SCAN_BEGIN && request == gScan){ gReceiving = TRUE; gPending = []; gPendingIcons = []; return; }
        if(!gReceiving || request != gScan) return;
        if(number == SCAN_ITEM) return;         // HERE ingredient: not a container
        if(number == SCAN_BLANK){
            list fl = llParseStringKeepNulls(payload, ["|"], []);
            key src = llList2Key(fl, 1);
            integer cap = llList2Integer(fl, 2);
            if((llGetListLength(fl) != 3 && llGetListLength(fl) != 4) || src == NULL_KEY || cap < 0
                || (string)cap != llList2String(fl, 2) || llGetOwnerKey(src) != llGetOwner()) return;
            list det = llGetObjectDetails(src, [OBJECT_NAME]);
            if(!llGetListLength(det)) return;
            string cname = llList2String(det, 0);
            string ic = "";
            key tex = (key)llStringTrim(llList2String(fl, 3), STRING_TRIM);
            if(tex) ic = llToLower((string)tex);
            integer ex = findNearPending(src);
            if(ex < 0){ gPending += [src, cname, cap]; gPendingIcons += [src, ic]; }
            else {
                gPending = llListReplaceList(gPending, [src, cname, cap], ex, ex + 2);
                integer ii = ex / 3 * 2;
                gPendingIcons = llListReplaceList(gPendingIcons, [src, ic], ii, ii + 1);
            }
            return;
        }
        if(number == SCAN_END){
            gNear = gPending; gIcons = gPendingIcons; gPending = []; gPendingIcons = [];
            gScanning = FALSE; gReceiving = FALSE; llSetTimerEvent(0.0);
            if(gSel != "" && findNear((key)gSel) < 0){ gSel = ""; gSelName = ""; gSelIcon = ""; }
            render();
            return;
        }
    }

    timer()
    {
        llSetTimerEvent(0.0);
        if(gScanning){
            gScanning = FALSE; gReceiving = FALSE; gPending = []; gPendingIcons = [];
            render();
            llRegionSayTo(llGetOwner(), 0, "[Nexus] Scan des récipients interrompu. Clique Actualiser.");
        }
    }
}
