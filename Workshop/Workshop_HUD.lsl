// Workshop v0.7 - MCW whisper endpoint and progressive input spool.
// No stock operations. Input rows/groups live in Linkset Data, not in a basket list.
integer CHANNEL = -918275;
key gRun = NULL_KEY;
string gPhase;
integer gNext;
integer gGroups;
integer gIndex;
string gType;
integer gFault;

integer write(string name, string value)
{
    integer result = llLinksetDataWrite(name, value);
    if (result == 0 || result == 5) return TRUE;
    gFault = TRUE; llOwnerSay("[Workshop HUD] Storage full/failure. No row acknowledged."); return FALSE;
}
integer save()
{
    return write("ws:input", llList2Json(JSON_ARRAY, [gRun, gPhase, gNext, gGroups, gIndex, gType]));
}
list core() { return llJson2List(llLinksetDataRead("ws:core")); }
notify(string text) { llMessageLinked(LINK_THIS, 970215, text, gRun); }
step() { llMessageLinked(LINK_THIS, 970214, "", gRun); }
ackRow(integer sequence)
{
    list sessionData = core();
    llWhisper(CHANNEL, "MCW|ACK|" + llList2String(sessionData, 1) + "|" + llList2String(sessionData, 2)
        + "|" + (string)gRun + "|ROW|" + (string)sequence);
}
string rowKey(integer index) { return "ws:in:row:" + (string)index; }
string groupKey(integer index) { return "ws:in:group:" + (string)index; }
ready() { llMessageLinked(LINK_THIS, 970299, "HUD", NULL_KEY); }
cleanup()
{
    string pattern = "^ws:in:";
    if (gPhase == "CLEAR_BUILD") pattern = "^ws:in:(group|label):";
    list keys = llLinksetDataFindKeys(pattern, 0, 1);
    if (llGetListLength(keys))
    {
        integer result = llLinksetDataDelete(llList2String(keys, 0));
        if (result != 0 && result != 4) { gFault = TRUE; return; }
        step(); return;
    }
    if (gPhase == "CLEAR_BEGIN")
    {
        gPhase = "RECEIVING"; gNext = 0; gGroups = 0; gIndex = 0; gType = "";
        if (save()) notify("BEGIN_READY");
    }
    else if (gPhase == "CLEAR_BUILD")
    {
        gPhase = "BUILDING"; gGroups = 0; gIndex = 0;
        if (save()) step();
    }
    else { gPhase = "EMPTY"; save(); }
}
buildGroup()
{
    if (gIndex >= gNext)
    {
        gPhase = "READY";
        if (save()) notify("INPUT_READY");
        return;
    }
    list row = llParseStringKeepNulls(llLinksetDataRead(rowKey(gIndex)), ["|"], []);
    list here = llParseStringKeepNulls(llUnescapeURL(llList2String(row, 2)), ["|"], []);
    // Preserve Workshop's existing name/stage batch grouping and first-row metadata.
    string label = llList2String(here, 2) + "/" + llList2String(here, 7);
    string mapKey = "ws:in:label:" + llMD5String(label, 0);
    string found = llLinksetDataRead(mapKey);
    integer quantity = llList2Integer(row, 1);
    if (found == "")
    {
        string group = llDumpList2String([llList2String(here, 2), quantity,
            llList2String(here, 6), llList2String(here, 7), llList2String(here, 8),
            llList2String(here, 5), llList2String(here, 10), llList2String(here, 12)], "|");
        if (!write(groupKey(gGroups), group) || !write(mapKey, (string)gGroups)) return;
        ++gGroups;
    }
    else
    {
        integer index = (integer)found;
        list group = llParseStringKeepNulls(llLinksetDataRead(groupKey(index)), ["|"], []);
        integer held = llList2Integer(group, 1);
        if (quantity > 2147483647 - held) { notify("ERROR|Ingredient quantity overflow."); return; }
        group = llListReplaceList(group, [held + quantity], 1, 1);
        if (!write(groupKey(index), llDumpList2String(group, "|"))) return;
    }
    ++gIndex;
    if (save()) step();
}
receiveRow(list fields)
{
    list sessionData = core();
    if (gPhase != "RECEIVING" || llList2String(sessionData, 4) != "RECEIVING"
        || llGetListLength(fields) != 9 || llList2Key(fields, 4) != gRun) return;
    integer sequence = llList2Integer(fields, 5);
    integer quantity = llList2Integer(fields, 7);
    if (sequence < 0 || sequence > gNext || (string)sequence != llList2String(fields, 5)
        || quantity < 1 || (string)quantity != llList2String(fields, 7)) return;
    string payload = llDumpList2String(llList2List(fields, 6, 8), "|");
    string previous = llLinksetDataRead(rowKey(sequence));
    if (previous != "")
    {
        if (previous != payload) return;
        if (sequence == gNext) { ++gNext; if (!save()) return; }
        ackRow(sequence); return;
    }
    if (sequence != gNext) return;
    list here = llParseStringKeepNulls(llUnescapeURL(llList2String(fields, 8)), ["|"], []);
    key source = llList2Key(fields, 6);
    integer valid;
    if (source) valid = TRUE;
    if (!valid || llGetListLength(here) != 13 || llList2String(here, 0) != "HERE"
        || llList2Key(here, 1) != source || llList2String(here, 9) != "5") return;
    string kind = llList2Json(JSON_ARRAY, [llList2String(here, 2), llList2String(here, 6),
        llList2String(here, 7), llList2String(here, 12)]);
    if (gNext && llList2Integer(sessionData, 9) && kind != gType) return;
    if (!write(rowKey(sequence), payload)) return;
    if (!gNext) gType = kind;
    ++gNext;
    if (save()) ackRow(sequence);
}
default
{
    state_entry()
    {
        llListen(CHANNEL, "", NULL_KEY, "");
        string saved = llLinksetDataRead("ws:input");
        if (saved != "")
        {
            list data = llJson2List(saved);
            if (llGetListLength(data) != 6) { gFault = TRUE; return; }
            gRun = llList2Key(data, 0); gPhase = llList2String(data, 1);
            gNext = llList2Integer(data, 2); gGroups = llList2Integer(data, 3);
            gIndex = llList2Integer(data, 4); gType = llList2String(data, 5);
            if (gPhase == "BUILDING") { gPhase = "CLEAR_BUILD"; save(); }
            if (llSubStringIndex(gPhase, "CLEAR") == 0) step();
        }
        ready();
    }
    listen(integer channel, string name, key source, string wire)
    {
        if (channel != CHANNEL || gFault) return; // Coordinator authenticates the touched player/HUD/session.
        list fields = llParseStringKeepNulls(wire, ["|"], []);
        if (llGetListLength(fields) < 5 || llList2String(fields, 0) != "MCW"
            || llList2Key(fields, 2) != llGetKey()) return;
        if (llList2String(fields, 1) == "ROW")
        {
            list sessionData = core();
            if (source != llList2Key(sessionData, 1) || llList2Key(fields, 3) != llList2Key(sessionData, 2)) return;
            receiveRow(fields);
        }
        else llMessageLinked(LINK_THIS, 970210, wire, source);
    }
    link_message(integer sender, integer number, string text, key run)
    {
        if (sender != llGetLinkNumber() || gFault) return;
        if (number == 970298) { ready(); return; }
        if (number == 970211)
        {
            if (llStringLength(llStringToBase64(text)) <= 1364) llWhisper(CHANNEL, text);
            else llOwnerSay("[Workshop HUD] Reply too large. Nothing truncated.");
            return;
        }
        if (number == 970214 && run == gRun)
        {
            if (llSubStringIndex(gPhase, "CLEAR") == 0) cleanup();
            else if (gPhase == "BUILDING") buildGroup();
            return;
        }
        if (number == 970213)
        {
            list sessionData = core();
            if (run != llList2Key(sessionData, 3)) return;
            if (text == "STATUS")
            {
                if (gPhase == "READY") { notify("BUILD_STARTED"); notify("INPUT_READY"); }
                else if (gPhase == "BUILDING" || gPhase == "CLEAR_BUILD") { notify("BUILD_STARTED"); step(); }
                else if (gPhase == "RECEIVING")
                {
                    if (llList2String(sessionData, 4) == "BUILDING") notify("ERROR|Input finalization interrupted before receipt.");
                    else notify("BEGIN_READY");
                }
            }
            else if (text == "BEGIN")
            {
                if (run == gRun && gPhase == "RECEIVING") { notify("BEGIN_READY"); return; }
                if (run == gRun && gPhase == "CLEAR_BEGIN") return;
                gRun = run; gPhase = "CLEAR_BEGIN";
                if (save()) step();
            }
            else if (text == "CLEAN") { gPhase = "CLEAR"; if (save()) step(); }
            else if (llSubStringIndex(text, "END|") == 0)
            {
                integer count = (integer)llGetSubString(text, 4, -1);
                if (gPhase != "RECEIVING" || count != gNext || count <= 0)
                { notify("ERROR|Incomplete input."); return; }
                gPhase = "CLEAR_BUILD";
                if (save()) step();
            }
        }
        else if (number == 970290) llOwnerSay("[Workshop HUD] Free: " + (string)llGetFreeMemory());
    }
}
