#define SCRIPT_NAME    "NX_Selected_Controller"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// HUD basket (SELECTED panel) mirror. The basket LIVES IN THE BENCH now; this script only reflects it:
// it receives NX|BASKET from the bound bench, drives NX_Render_Selected (VIEW, panel "SELECTED"),
// paginates, sends unpicks, and reports the basket count to NX_HudNav for the Continue gate.
//   in  (NX_HUD)      : NX|BASKET|<session>|<count>|sid~name~qty~icon^...
//   out (NX_HUD->bench): NX|UNPICK|<session>|<sid>                 (P0_SEL_DEL_n)
//   in  link 918260 BIND_INFO "<bench>|<session>"
//   out link 918290 VIEW (panel "SELECTED") -> NX_Render_Selected
//   out link 918261 CANCONT "<count>"       -> NX_HudNav (Continue gate)

integer NX_HUD     = -918282;
integer VIEW       = 918290;
integer BIND_INFO  = 918260;
integer CANCONT    = 918261;
string  PREV_NAME  = "P0_SEL_PREV";
string  NEXT_NAME  = "P0_SEL_NEXT";
string  DEL_PREFIX = "p0_sel_del_";

key     gBench   = NULL_KEY;
string  gSession = "";
integer gPage;
list    gRows;                          // each entry "sid~name~qty~icon"

integer pageCount(){
    integer c = (llGetListLength(gRows) + 3) / 4;
    if(c < 1) c = 1;
    return c;
}

string packView(list view){
    string t = "";
    integer i;
    for(i = 0; i < 18; ++i){
        if(i) t += "|";
        t += llEscapeURL(llList2String(view, i));
    }
    return t;
}

render(){
    integer total = pageCount();
    if(gPage >= total) gPage = total - 1;
    if(gPage < 0) gPage = 0;
    list view = [gPage + 1, total];
    integer row;
    for(row = 0; row < 4; ++row){
        integer idx = gPage * 4 + row;
        if(idx >= llGetListLength(gRows)) view += ["", 0, "", 0];
        else {
            list e = llParseStringKeepNulls(llList2String(gRows, idx), ["~"], []);
            view += [llList2String(e, 1), (integer)llList2String(e, 2), llList2String(e, 3), 1]; // name,qty,icon,occupied
        }
    }
    llMessageLinked(LINK_THIS, VIEW, packView(view), (key)"SELECTED");
    llMessageLinked(LINK_THIS, CANCONT, (string)llGetListLength(gRows), NULL_KEY);
}

clearBasket(){ gRows = []; gPage = 0; render(); }

button(string name){
    if(name == llToLower(PREV_NAME)){ integer t = pageCount(); gPage = (gPage - 1 + t) % t; render(); return; }
    if(name == llToLower(NEXT_NAME)){ integer t = pageCount(); gPage = (gPage + 1) % t; render(); return; }
    integer row;
    for(row = 0; row < 4; ++row)
        if(name == DEL_PREFIX + (string)row){
            integer idx = gPage * 4 + row;
            if(idx >= llGetListLength(gRows) || gBench == NULL_KEY || gSession == "") return;
            string sid = llList2String(llParseStringKeepNulls(llList2String(gRows, idx), ["~"], []), 0);
            llRegionSayTo(gBench, NX_HUD, "NX|UNPICK|" + gSession + "|" + sid);   // bench updates + re-pushes BASKET
            return;
        }
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_HUD, "", NULL_KEY, "");
        render();                        // empty at boot
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

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(num == BIND_INFO){
            list p = llParseStringKeepNulls(str, ["|"], []);
            key nb = (key)llList2String(p, 0);
            string ns = llList2String(p, 1);
            // Unbound, or a NEW session (fresh craft after a consume-discard) -> start from an empty basket.
            // A re-bind to the SAME session keeps the current rows (the bench re-pushes BASKET if any).
            if(nb == NULL_KEY || ns == "" || ns != gSession) clearBasket();
            gBench = nb; gSession = ns;
            return;
        }
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_HUD) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX" || llList2String(f, 1) != "BASKET") return;
        if(gSession == "" || llList2String(f, 2) != gSession) return;
        if(gBench != NULL_KEY && who != NULL_KEY && llGetOwnerKey(who) != llGetOwnerKey(gBench)) return;
        gRows = [];
        if(llGetListLength(f) >= 5 && llList2String(f, 4) != "")
            gRows = llParseStringKeepNulls(llList2String(f, 4), ["^"], []);
        render();
    }
}
// REVIEW: 2026-11-19 — SELECTED pagination prims P0_SEL_PREV/NEXT and delete P0_SEL_DEL_0..3 assumed; confirm names.
