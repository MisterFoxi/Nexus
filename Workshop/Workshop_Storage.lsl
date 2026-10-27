// Workshop v0.7 - kept products, one durable record per lot.
// No gKept list. The old state:kept value is migrated without deleting data first.
integer gFault;
integer gReady;
integer gImportIndex;

integer write(string name, string value)
{
    integer result = llLinksetDataWrite(name, value);
    if (result == 0 || result == 5) return TRUE;
    gFault = TRUE; llOwnerSay("[Workshop Storage] Write failed. Kept products retained."); return FALSE;
}
integer freshness(integer life, integer expiry)
{
    if (life <= 0 || expiry <= 0) return 1000;
    integer remaining = expiry - llGetUnixTime();
    if (remaining <= 0) return 0;
    integer value = (integer)((float)remaining * 1000.0 / (float)life);
    if (value > 1000) value = 1000;
    return value;
}
ready() { if (gReady && !gFault) llMessageLinked(LINK_THIS, 970299, "STORAGE", NULL_KEY); }
importStep()
{
    string old = llLinksetDataRead("state:kept");
    if (old == "") { gReady = TRUE; ready(); return; }
    list lines = llParseStringKeepNulls(old, ["\n"], []);
    if (gImportIndex >= llGetListLength(lines))
    {
        integer result = llLinksetDataDelete("state:kept");
        if (result != 0 && result != 4) { gFault = TRUE; return; }
        gReady = TRUE; ready(); return;
    }
    list row = llParseStringKeepNulls(llList2String(lines, gImportIndex), ["|"], []);
    if (llGetListLength(row) != 7 || llList2Integer(row, 1) < 0)
    { gFault = TRUE; llOwnerSay("[Workshop Storage] Invalid existing kept record. Original retained."); return; }
    if (!write("ws:kept:import:" + (string)gImportIndex, llList2Json(JSON_ARRAY, row))) return;
    ++gImportIndex;
    if (write("ws:storage:import", (string)gImportIndex)) llMessageLinked(LINK_THIS, 970232, "", NULL_KEY);
}
keep(key run)
{
    list product = llJson2List(llLinksetDataRead("ws:product"));
    if (llList2Key(product, 0) != run) return;
    string slot = "ws:kept:" + (string)run;
    if (llLinksetDataRead(slot) != "" || llLinksetDataRead("ws:storage:last") == (string)run)
    { llMessageLinked(LINK_THIS, 970231, "KEPT", run); return; }
    list data = llParseStringKeepNulls(llList2String(product, 1), ["|"], []);
    if (llGetListLength(data) != 11 || llList2String(data, 0) != "1")
    { llMessageLinked(LINK_THIS, 970231, "ERROR|Invalid product.", run); return; }
    integer life = llList2Integer(data, 5);
    integer effect = llList2Integer(data, 10);
    if (effect > 1000) effect = 1000;
    if (effect < 0) effect = 0;
    integer expiry;
    if (life > 0) expiry = llGetUnixTime() + (integer)((float)effect * (float)life / 1000.0);
    string record = llList2Json(JSON_ARRAY, [llList2String(data, 2), llList2Integer(data, 3),
        llList2String(data, 6), llList2String(data, 7), llList2String(data, 8), life, expiry]);
    if (!write(slot, record) || !write("ws:storage:last", (string)run)) return;
    llMessageLinked(LINK_THIS, 970231, "KEPT", run);
}
page(integer offset, key ticket)
{
    list keys = llLinksetDataFindKeys("^ws:kept:", offset, 1);
    if (!llGetListLength(keys)) { llMessageLinked(LINK_THIS, 970231, "END", ticket); return; }
    string name = llList2String(keys, 0);
    list record = llJson2List(llLinksetDataRead(name));
    integer effect = freshness(llList2Integer(record, 5), llList2Integer(record, 6));
    if (llList2Integer(record, 1) <= 0 || effect <= 0)
    {
        integer result = llLinksetDataDelete(name);
        if (result != 0 && result != 4) { gFault = TRUE; return; }
        llMessageLinked(LINK_THIS, 970231, "SKIP|" + (string)offset, ticket);
        return;
    }
    llMessageLinked(LINK_THIS, 970231, "ITEM|" + (string)(offset + 1) + "|" + name + "|"
        + llEscapeURL(llList2Json(JSON_ARRAY, record + [effect])), ticket);
}
default
{
    state_entry()
    {
        gImportIndex = (integer)llLinksetDataRead("ws:storage:import");
        llMessageLinked(LINK_THIS, 970232, "", NULL_KEY);
    }
    link_message(integer sender, integer number, string text, key run)
    {
        if (sender != llGetLinkNumber() || gFault) return;
        if (number == 970298) { ready(); return; }
        if (number == 970232) { importStep(); return; }
        if (number == 970290) { llOwnerSay("[Workshop Storage] Free: " + (string)llGetFreeMemory()); return; }
        if (number != 970230 || !gReady) return;
        if (text == "KEEP")
        {
            list sessionData = llJson2List(llLinksetDataRead("ws:core"));
            if (llList2Key(sessionData, 3) == run && llList2Integer(sessionData, 10)) keep(run);
            else llMessageLinked(LINK_THIS, 970231, "ERROR|Keep is not allowed.", run);
            return;
        }
        list request = llParseStringKeepNulls(text, ["|"], []);
        if (llList2String(request, 0) == "PAGE" && llList2Integer(request, 1) >= 0)
            page(llList2Integer(request, 1), run);
    }
}
