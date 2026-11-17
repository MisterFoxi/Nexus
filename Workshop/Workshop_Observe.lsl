// ROOT. Transient read-only basket snapshot -> cumulative observation calculation.
// No source transactions, product records or persistent observation spool.
string VERSION = "Workshop_Observe v0.1.2 (2026-11-17)";
key gTicket = NULL_KEY;
key gHUD;
key gSession;
integer gOffset;
integer gSources;
integer gDeadline;
string gAction;
string gHash;
string gLastRow;
string gName;
string gPhase;
list gLabels;
list gGroups;

integer current()
{
    list core = llJson2List(llLinksetDataRead("ws:core"));
    return llList2String(core,4) == "BOUND" && llList2Key(core,1) == gHUD
        && llList2Key(core,2) == gSession && gTicket != NULL_KEY;
}
send(string verb, string body)
{
    string wire = "MCW|"+verb+"|"+(string)gHUD+"|"+(string)gSession+"|"+(string)gTicket;
    if(body != "") wire += "|"+body;
    llMessageLinked(LINK_THIS,970211,wire,gTicket);
}
finish(string result)
{
    key ticket = gTicket;
    gTicket = NULL_KEY; gGroups = []; gLabels = []; gPhase = "";
    llSetTimerEvent(0.0);
    if(ticket != NULL_KEY) llMessageLinked(LINK_THIS,970241,result,ticket);
}
begin(string text, key ticket)
{
    if(gTicket != NULL_KEY){ llMessageLinked(LINK_THIS,970241,"ERROR|Observation already in progress.",ticket); return; }
    list input = llParseStringKeepNulls(text,["|"],[]);
    if(llGetListLength(input) != 4 || llList2String(input,0) != "INPUTS") {
        llMessageLinked(LINK_THIS,970241,"ERROR|Invalid observation request from Workshop_Config.",ticket); return;
    }
    list core = llJson2List(llLinksetDataRead("ws:core"));
    gHUD = llList2Key(core,1); gSession = llList2Key(core,2); gTicket = ticket;
    if(!current()){ finish("ERROR|Observation session unavailable."); return; }
    gGroups=[]; gLabels=[]; gOffset=0; gSources=0; gLastRow=""; gName=""; gHash="";
    gAction = llUnescapeURL(llList2String(input,3));
    gPhase="ROWS"; gDeadline=llGetUnixTime()+10; llSetTimerEvent(1.0);
    llMessageLinked(LINK_THIS,970242,"STARTED",gTicket);
    send("INSPECT_NEXT","0");
}
row(list fields, string wire)
{
    if(gPhase != "ROWS" || llGetListLength(fields) != 8) return;
    if(wire == gLastRow){ send("INSPECT_NEXT",(string)gOffset); return; }
    integer next = llList2Integer(fields,5);
    integer quantity = llList2Integer(fields,6);
    if(next <= gOffset || (string)next != llList2String(fields,5)
        || quantity < 1 || (string)quantity != llList2String(fields,6)){
        finish("ERROR|Invalid observation row."); return;
    }
    list here = llParseStringKeepNulls(llUnescapeURL(llList2String(fields,7)),["|"],[]);
    integer length = llGetListLength(here);
    if((length != 13 && length != 14) || llList2String(here,0) != "HERE" || llList2String(here,9) != "5"){
        finish("ERROR|Invalid ingredient metadata."); return;
    }
    // Preserve the final craft's existing name/stage grouping and first-source metadata.
    string label = llList2String(here,2)+"/"+llList2String(here,7);
    integer found = llListFindList(gLabels,[label]);
    if(found == -1){
        gLabels += [label];
        gGroups += [llDumpList2String([llList2String(here,2),quantity,llList2String(here,6),
            llList2String(here,7),llList2String(here,8),llList2String(here,5),
            llList2String(here,10),llList2String(here,12)],"|")];
    }
    else{
        list group = llParseStringKeepNulls(llList2String(gGroups,found),["|"],[]);
        integer previous = llList2Integer(group,1);
        if(quantity > 2147483647-previous){ finish("ERROR|Ingredient quantity overflow."); return; }
        group = llListReplaceList(group,[quantity+previous],1,1);
        gGroups = llListReplaceList(gGroups,[llDumpList2String(group,"|")],found,found);
    }
    if(llStringLength(llStringToBase64(gAction+"\n\n"+llDumpList2String(gGroups,"\n"))) > 5460){
        finish("ERROR|Observation basket is too large."); return;
    }
    if(!gSources) gName=llList2String(here,2);
    ++gSources; gOffset=next; gLastRow=wire;
    send("INSPECT_NEXT",(string)gOffset);
}
default
{
    state_entry(){ llOwnerSay("[Nexus] "+VERSION); llMessageLinked(LINK_THIS,970299,"OBSERVE",NULL_KEY); }
    link_message(integer sender,integer number,string text,key id){
        if(sender != llGetLinkNumber()) return;
        if(number == 970298){ llMessageLinked(LINK_THIS,970299,"OBSERVE",NULL_KEY); return; }
        if(number == 970290){ llOwnerSay("[Workshop Observe] Free: "+(string)llGetFreeMemory()); return; }
        if(number == 970240 && id != NULL_KEY){ begin(text,id); return; }
        if(number == 970205 && id == gTicket && gTicket != NULL_KEY && gPhase == "EVALUATING"){
            if(!current()){ finish("ERROR|Observation session changed."); return; }
            if(llSubStringIndex(text,"OBSERVATIONS|") == 0) text += "|"+llEscapeURL(gName);
            else if(text == "NO_OBSERVATIONS") text += "||"+llEscapeURL(gName);
            finish(text); return;
        }
        if(number != 970247 || gTicket == NULL_KEY) return;
        list fields = llParseStringKeepNulls(text,["|"],[]);
        if(id != gHUD || llList2Key(fields,3) != gSession || llList2Key(fields,4) != gTicket) return;
        if(!current()){ finish("ERROR|Observation session changed."); return; }
        string verb = llList2String(fields,1);
        if(verb == "INSPECT_CANCEL"){ finish("ERROR|Observation cancelled."); return; }
        if(verb == "INSPECT_ERROR"){
            finish("ERROR|"+llUnescapeURL(llList2String(fields,5))); return;
        }
        if(verb == "INSPECT_ROW"){ row(fields,text); return; }
        if(verb == "INSPECT_END" && gPhase == "ROWS" && llGetListLength(fields) == 7){
            if(llList2Integer(fields,5) != gSources || !gSources){ finish("ERROR|Empty or incomplete observation basket."); return; }
            gHash=llList2String(fields,6); gPhase="VERIFY"; send("INSPECT_VERIFY",""); return;
        }
        if(verb == "INSPECT_VERIFIED" && gPhase == "VERIFY" && llGetListLength(fields) == 6){
            if(llList2String(fields,5) != gHash){ finish("ERROR|Observation basket changed."); return; }
            gPhase="EVALUATING";
            llMessageLinked(LINK_THIS,970204,gAction+"\n\n"+llDumpList2String(gGroups,"\n"),gTicket);
        }
    }
    timer(){
        if(gTicket == NULL_KEY) return;
        if(!current()){ finish("ERROR|Observation session changed."); return; }
        if(llGetUnixTime() < gDeadline) return;
        if(gPhase == "ROWS") finish("ERROR|No complete HUD basket reply reached Workshop_Observe (received "+(string)gSources+" sources). Workshop must forward INSPECT replies; MC_Workshop_Link must support INSPECT_NEXT.");
        else if(gPhase == "VERIFY") finish("ERROR|HUD basket verification did not reach Workshop_Observe. Check the INSPECT_VERIFY / INSPECT_VERIFIED transport.");
        else finish("ERROR|Workshop_Eval did not answer observation request 970204. It must be running in workshop ROOT with observation support (v0.9.1 or newer).");
    }
}
