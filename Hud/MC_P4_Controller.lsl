string VERSION = "MC_P4_Controller v0.2.0 (2026-11-16)";
// ROOT beside FURWARE. Read-only observation view; no stock or craft submission.
string ATLAS = "Atlas_obs";
string BACK_PRIM = "P4_ACTION1";
string REFRESH_PRIM = "P4_ACTION2";
integer FACE = 1;
integer TEXT_COLUMNS = 40;
integer TEXT_ROWS = 24;
integer gOpen;
integer gProductPage;
integer gPending;
key gRequest = NULL_KEY;
integer gDeadline;
string gBody = "Open observation from the preparation page.";
string gStatus = "";
string gName = "Current preparation";
string gSetupError;
integer gTextPage;
key gObservationTicket = NULL_KEY;

integer findPrim(string name)
{
    integer found; integer i;
    name = llToLower(name);
    for(i=1;i<=llGetNumberOfPrims();++i)
        if(llToLower(llStringTrim(llGetLinkName(i),STRING_TRIM)) == name){
            if(found) return 0;
            found = i;
        }
    return found;
}
integer hasTextTable(string name)
{
    integer i;
    for(i=1;i<=llGetNumberOfPrims();++i){
        list parts = llParseStringKeepNulls(llGetLinkName(i),[":"],[]);
        if(llList2String(parts,0) == "FURWARE text mesh" && llList2String(parts,1) == name) return TRUE;
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
    if(!link) return "Missing or duplicate "+name+". ";
    if(!validFace(link)) return name+": requested face "+(string)FACE
        +", but prim has "+(string)llGetLinkNumberOfSides(link)+" faces. ";
    return "";
}
buttonTexture(integer link, string atlas, float u, float v)
{
    if(!validFace(link) || atlas == "") return;
    // Crop around the visible plaques rather than displaying large transparent margins.
    llSetLinkTextureAnim(link,0,FACE,1,1,0.0,0.0,0.0);
    llSetLinkPrimitiveParamsFast(link,[
        PRIM_TEXTURE,FACE,atlas,<0.47,0.19,0.0>,<u,v,0.0>,0.0,
        PRIM_COLOR,FACE,<1.0,1.0,1.0>,1.0,PRIM_FULLBRIGHT,FACE,TRUE]);
}
configure()
{
    string atlas = "";
    if(llGetInventoryType(ATLAS) == INVENTORY_TEXTURE) atlas = ATLAS;
    integer back = buttonPrim(BACK_PRIM,"P4_BACK");
    integer refresh = buttonPrim(REFRESH_PRIM,"P4_REFRESH");
    string error = "";
    if(atlas == "") error += "Missing "+ATLAS+" texture. ";
    error += buttonError(BACK_PRIM,back)+buttonError(REFRESH_PRIM,refresh);
    if(!hasTextTable("P4_Table1")) error += "Missing P4_Table1 text table. ";
    if(error != "" && error != gSetupError) llOwnerSay("[Observation setup] "+error);
    gSetupError = error;
    // Measured cell centers in Atlas_Obs.png (627px cells, plaque center y=328px).
    buttonTexture(back,atlas,0.25,0.2385);
    buttonTexture(refresh,atlas,-0.25,-0.2615);
}
string displayText()
{
    // Word-wrap without throwing away overflow. Optional P4_NEXT/P4_PREV browse it.
    string text = gBody;
    list lines;
    while(llStringLength(text) > TEXT_COLUMNS){
        integer end = TEXT_COLUMNS;
        integer i;
        for(i=TEXT_COLUMNS-1;i>0;--i)
            if(llGetSubString(text,i,i) == " "){ end=i; jump wrapped; }
        @wrapped;
        lines += [llGetSubString(text,0,end-1)];
        text = llStringTrim(llGetSubString(text,end,-1),STRING_TRIM);
    }
    lines += [text];
    integer pages = (llGetListLength(lines)+TEXT_ROWS-1)/TEXT_ROWS;
    if(gTextPage < 0) gTextPage = pages-1;
    if(gTextPage >= pages) gTextPage = 0;
    return llDumpList2String(llList2List(lines,gTextPage*TEXT_ROWS,(gTextPage+1)*TEXT_ROWS-1),"\n");
}
table(string name, string text)
{
    if(!hasTextTable(name)) return;
    llMessageLinked(LINK_SET,0,"c=white;a=left;w=none;tags=off",(key)("fw_conf:"+name));
    llMessageLinked(LINK_SET,0,text,(key)("fw_data:"+name));
}
render()
{
    table("P4_Name",gName);
    table("P4_Table1",displayText());
    table("P4_Status",gStatus);
}
cancel()
{
    key request = gRequest;
    gRequest = NULL_KEY; gPending = FALSE; gDeadline = 0;
    llSetTimerEvent(0.0);
    if(request != NULL_KEY) llMessageLinked(LINK_THIS,918397,"CANCEL",request);
}
close(integer back)
{
    integer wasOpen = gOpen;
    gOpen = FALSE; cancel();
    key observation = gObservationTicket;
    gObservationTicket = NULL_KEY;
    if(observation != NULL_KEY) llMessageLinked(LINK_THIS,918412,"CLOSED",observation);
    if(back && wasOpen) llMessageLinked(LINK_THIS,918410,"BACK",llGenerateKey());
}
refresh()
{
    if(!gOpen || gPending) return;
    list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
    gTextPage = 0;
    if(llList2Key(session,2) == NULL_KEY || llList2String(session,2) == ""){
        gBody = "Touch a workshop to associate this HUD before requesting an observation.";
        gStatus = "No workshop associated"; render(); return;
    }
    if(llList2String(session,5) != "IDLE"){
        gBody = "An observation is available only while preparing, before submitting the craft.";
        gStatus = "Treatment pending"; render(); return;
    }
    gRequest = llGenerateKey(); gPending = TRUE;
    gDeadline = llGetUnixTime()+20; llSetTimerEvent(1.0);
    gBody = "Requesting an observation of the current preparation...";
    gStatus = "Please wait"; render();
    llMessageLinked(LINK_THIS,918397,"TEST",gRequest);
}
openObservation(key ticket)
{
    if(gOpen && ticket == gObservationTicket){ llMessageLinked(LINK_THIS,918412,"OPENED",ticket); return; }
    list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
    string phase = llList2String(session,5);
    if(gProductPage || gOpen || (phase != "" && phase != "IDLE")){
        llMessageLinked(LINK_THIS,918412,"UNAVAILABLE",ticket); return;
    }
    gObservationTicket = ticket; gOpen = TRUE;
    llMessageLinked(LINK_THIS,918410,"OPEN",ticket);
    llMessageLinked(LINK_THIS,918412,"OPENED",ticket);
    refresh();
}
button(string name)
{
    if(!gOpen) return;
    if(name == "p4_action1" || name == "p4_back") close(TRUE);
    else if(name == "p4_action2" || name == "p4_refresh") refresh();
    else if(name == "p4_next"){ ++gTextPage; render(); }
    else if(name == "p4_prev"){ --gTextPage; render(); }
}
result(string text)
{
    gPending = FALSE; gRequest = NULL_KEY; llSetTimerEvent(0.0);
    if(llSubStringIndex(text,"OBSERVATIONS|") == 0){
        gBody = llUnescapeURL(llGetSubString(text,13,-1));
        gStatus = "Observation captured; REFRESH to update";
    }
    else if(text == "NO_OBSERVATIONS"){
        gBody = "There are no observations for the current preparation.";
        gStatus = "No matching observation";
    }
    else if(text == "NOT_IMPLEMENTED"){
        gBody = "The workshop observation service is not connected yet.";
        gStatus = "Observation unavailable";
    }
    else if(text == "BUSY"){
        gBody = "The workshop is busy. Please try REFRESH shortly.";
        gStatus = "Workshop busy";
    }
    else if(llSubStringIndex(text,"ERROR|") == 0){
        gBody = llGetSubString(text,6,-1); gStatus = "Observation unavailable";
    }
    else{
        gBody = "Start a preparation on P1 and check the workshop connection, then try REFRESH.";
        gStatus = "Observation unavailable";
    }
    render();
}
default
{
    state_entry(){
        llOwnerSay("[Nexus] "+VERSION); configure(); render();
        llMessageLinked(LINK_THIS,918412,"RESET",NULL_KEY);
        llMessageLinked(LINK_THIS,918410,"BACK",llGenerateKey());
    }
    on_rez(integer parameter){ llResetScript(); }
    changed(integer flags){ if(flags & (CHANGED_LINK | CHANGED_INVENTORY)){ configure(); render(); } }
    touch_start(integer count){
        integer i;
        for(i=0;i<count;++i)
            if(llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)),STRING_TRIM)));
    }
    link_message(integer sender, integer number, string text, key ticket){
        if((string)ticket == "fw_ready"){ render(); return; }
        if(sender != llGetLinkNumber()) return;
        if(number == 918411 && text == "OPEN" && ticket != NULL_KEY){ openObservation(ticket); return; }
        if(number == 918398 && ticket == gRequest && ticket != NULL_KEY && gOpen){ result(text); return; }
        if(number == 918371 && text != "IDLE"){ close(TRUE); return; }
        if(number == 918317 && (text == "DISCARD_DONE" || text == "CRAFT_DONE")){ close(FALSE); return; }
        if(number == 918391){
            string phase = llList2String(llParseStringKeepNulls(text,["|"],[]),0);
            if(phase == "WAIT_CONTAINER"){ gProductPage = TRUE; close(FALSE); }
            else if(phase == "CLOSED" || phase == "RELEASED"){ gProductPage = FALSE; close(FALSE); }
        }
    }
    timer(){
        if(gPending && llGetUnixTime() >= gDeadline){ cancel(); result("UNAVAILABLE"); }
    }
}
