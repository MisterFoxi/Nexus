#define SCRIPT_NAME    "NX_P4_Controller"
#define SCRIPT_VERSION "v0.2.0"
#include "nexus_header"

// NX_P4_Controller — ROOT beside FURWARE. Read-only observation page (refonte).
//   918411 OPEN (in, from NX_P1_Animation PAUSE) -> ack + rotate (918410 OPEN) + ask NX_Nearby to observe
//   918410 OPEN / BACK (out) -> NX_Turn_Z pivots P1<->P4
//   918412 OPENED / CLOSED / RESET (out) -> NX_P1_Animation navigation gate
//   918420 OBS_REQ   (out) -> NX_Nearby: assemble a snapshot and observe
//   918421 OBS_RESULT (in) <- NX_Nearby: "<STATUS>|<nameEsc>|<descEsc>"  (STATUS = OK | NONE | ERR)
//   918371 phase, 918391 output phase, 918317 DISCARD_DONE/CRAFT_DONE -> close
//
// Tables: P4_Table1 (1 row x N) = component name ; P4_Table2 (4 rows x 40) = description.
// Put the action atlas in ROOT inventory as "Atlas_obs"; action prims P4_ACTION1 (BACK) / P4_ACTION2 (REFRESH).
integer OBS_REQ = 918420;
integer OBS_RESULT = 918421;
string ATLAS = "Atlas_obs";
string BACK_PRIM = "P4_ACTION1";
string REFRESH_PRIM = "P4_ACTION2";
integer FACE = 1;
integer TEXT_COLUMNS = 40;
integer TEXT_ROWS = 4;
integer gOpen;
integer gProductPage;
string gName = "Current preparation";
string gBody = "Open observation from the preparation page.";
string gSetupError;
integer gTextPage;
key gObservationTicket = NULL_KEY;

integer findPrim(string name)
{
    integer found; integer i;
    name = llToLower(name);
    for(i = 1; i <= llGetNumberOfPrims(); ++i)
        if(llToLower(llStringTrim(llGetLinkName(i), STRING_TRIM)) == name){
            if(found) return 0;
            found = i;
        }
    return found;
}
integer hasTextTable(string name)
{
    integer i;
    for(i = 1; i <= llGetNumberOfPrims(); ++i){
        list parts = llParseStringKeepNulls(llGetLinkName(i), [":"], []);
        if(llList2String(parts, 0) == "FURWARE text mesh" && llList2String(parts, 1) == name) return TRUE;
    }
    return FALSE;
}
integer validFace(integer link)
{
    if(!link || FACE < 0) return FALSE;
    return FACE < llGetLinkNumberOfSides(link);
}
integer buttonPrim(string primary, string alias)
{
    integer link = findPrim(primary);
    if(!link) link = findPrim(alias);
    return link;
}
string buttonError(string name, integer link)
{
    if(!link) return "Missing or duplicate " + name + ". ";
    if(!validFace(link)) return name + ": requested face " + (string)FACE
        + ", but prim has " + (string)llGetLinkNumberOfSides(link) + " faces. ";
    return "";
}
buttonTexture(integer link, string atlas, float u, float v)
{
    if(!validFace(link) || atlas == "") return;
    llSetLinkTextureAnim(link, 0, FACE, 1, 1, 0.0, 0.0, 0.0);
    llSetLinkPrimitiveParamsFast(link, [
        PRIM_TEXTURE, FACE, atlas, <0.47, 0.19, 0.0>, <u, v, 0.0>, 0.0,
        PRIM_COLOR, FACE, <1.0, 1.0, 1.0>, 1.0, PRIM_FULLBRIGHT, FACE, TRUE]);
}
configure()
{
    string atlas = "";
    if(llGetInventoryType(ATLAS) == INVENTORY_TEXTURE) atlas = ATLAS;
    integer back = buttonPrim(BACK_PRIM, "P4_BACK");
    integer refresh = buttonPrim(REFRESH_PRIM, "P4_REFRESH");
    string error = "";
    if(atlas == "") error += "Missing " + ATLAS + " texture. ";
    error += buttonError(BACK_PRIM, back) + buttonError(REFRESH_PRIM, refresh);
    if(!hasTextTable("P4_Table1")) error += "Missing P4_Table1 text table. ";
    if(!hasTextTable("P4_Table2")) error += "Missing P4_Table2 text table. ";
    if(error != "" && error != gSetupError) llOwnerSay("[Observation setup] " + error);
    gSetupError = error;
    // Measured cell centers in Atlas_Obs.png (627px cells, plaque center y=328px).
    buttonTexture(back, atlas, 0.25, 0.2385);
    buttonTexture(refresh, atlas, -0.25, -0.2615);
}
// Word-wrap gBody into TEXT_ROWS lines of TEXT_COLUMNS, keeping overflow for optional P4_NEXT/P4_PREV paging.
string wrapText()
{
    string text = gBody;
    list lines;
    while(llStringLength(text) > TEXT_COLUMNS){
        integer end = TEXT_COLUMNS;
        integer i;
        for(i = TEXT_COLUMNS - 1; i > 0; --i)
            if(llGetSubString(text, i, i) == " "){ end = i; jump wrapped; }
        @wrapped;
        lines += [llGetSubString(text, 0, end - 1)];
        text = llStringTrim(llGetSubString(text, end, -1), STRING_TRIM);
    }
    lines += [text];
    integer pages = (llGetListLength(lines) + TEXT_ROWS - 1) / TEXT_ROWS;
    if(pages < 1) pages = 1;
    if(gTextPage < 0) gTextPage = pages - 1;
    if(gTextPage >= pages) gTextPage = 0;
    return llDumpList2String(llList2List(lines, gTextPage * TEXT_ROWS, (gTextPage + 1) * TEXT_ROWS - 1), "\n");
}
table(string name, string text)
{
    if(!hasTextTable(name)) return;
    llMessageLinked(LINK_SET, 0, "c=white;a=left;w=none;tags=off", (key)("fw_conf:" + name));
    llMessageLinked(LINK_SET, 0, text, (key)("fw_data:" + name));
}
render()
{
    table("P4_Table1", gName);
    table("P4_Table2", wrapText());
}
close(integer back)
{
    integer wasOpen = gOpen;
    gOpen = FALSE;
    key observation = gObservationTicket;
    gObservationTicket = NULL_KEY;
    if(observation != NULL_KEY) llMessageLinked(LINK_THIS, 918412, "CLOSED", observation);
    if(back && wasOpen) llMessageLinked(LINK_THIS, 918410, "BACK", llGenerateKey());
}
observe()
{
    gTextPage = 0;
    gBody = "Observing the current preparation...";
    render();
    llMessageLinked(LINK_THIS, OBS_REQ, "", NULL_KEY);   // NX_Nearby assembles + sends to NX_Eval
}
openObservation(key ticket)
{
    if(gOpen && ticket == gObservationTicket){ llMessageLinked(LINK_THIS, 918412, "OPENED", ticket); return; }
    if(gProductPage || gOpen){ llMessageLinked(LINK_THIS, 918412, "UNAVAILABLE", ticket); return; }
    gObservationTicket = ticket; gOpen = TRUE;
    llMessageLinked(LINK_THIS, 918410, "OPEN", ticket);
    llMessageLinked(LINK_THIS, 918412, "OPENED", ticket);
    observe();
}
// OBS_RESULT payload: "<STATUS>|<nameEsc>|<descEsc>"
obsResult(string text)
{
    list f = llParseStringKeepNulls(text, ["|"], []);
    string st = llList2String(f, 0);
    string nm = llUnescapeURL(llList2String(f, 1));
    string ds = llUnescapeURL(llList2String(f, 2));
    if(nm != "") gName = nm;
    if(st == "OK") gBody = ds;
    else if(st == "NONE") gBody = "Nothing notable about this preparation yet.";
    else if(ds != "") gBody = ds;                 // ERR with a reason
    else gBody = "Observation unavailable.";
    gTextPage = 0;
    render();
}
button(string name)
{
    if(!gOpen) return;
    if(name == "p4_action1" || name == "p4_back") close(TRUE);
    else if(name == "p4_action2" || name == "p4_refresh") observe();
    else if(name == "p4_next"){ ++gTextPage; render(); }
    else if(name == "p4_prev"){ --gTextPage; render(); }
}
default
{
    state_entry(){
        nexusBoot(); configure(); render();
        llMessageLinked(LINK_THIS, 918412, "RESET", NULL_KEY);
        llMessageLinked(LINK_THIS, 918410, "BACK", llGenerateKey());
    }
    on_rez(integer parameter){ llResetScript(); }
    changed(integer flags){ if(flags & (CHANGED_LINK | CHANGED_INVENTORY)){ configure(); render(); } }
    touch_start(integer count){
        integer i;
        for(i = 0; i < count; ++i)
            if(llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
    }
    link_message(integer sender, integer number, string text, key ticket){
        if(number == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if((string)ticket == "fw_ready"){ render(); return; }
        if(sender != llGetLinkNumber()) return;
        if(number == 918411 && text == "OPEN" && ticket != NULL_KEY){ openObservation(ticket); return; }
        if(number == OBS_RESULT){ if(gOpen) obsResult(text); return; }
        if(number == 918371 && text != "IDLE"){ close(TRUE); return; }
        if(number == 918317 && (text == "DISCARD_DONE" || text == "CRAFT_DONE")){ close(FALSE); return; }
        if(number == 918391){
            string phase = llList2String(llParseStringKeepNulls(text, ["|"], []), 0);
            if(phase == "WAIT_CONTAINER"){ gProductPage = TRUE; close(FALSE); }
            else if(phase == "CLOSED" || phase == "RELEASED"){ gProductPage = FALSE; close(FALSE); }
        }
    }
}
