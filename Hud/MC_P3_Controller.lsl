// ROOT. Finished-product recipients only. Never sends ingredient TAKE/RETURN/COMMIT.
// Shared MC_Scan, shared 18-field renderer format; independent four-row pages.
list gNear; // stride 3: UUID, display name, capacity
list gSelected;
list gPending;
integer gNearPage;
integer gSelectedPage;
integer gScanning;
integer gReceiving;
integer gItems;
integer gBlanks;
key gScan = NULL_KEY;
key gProduct = NULL_KEY;
integer gRemaining;
integer gOpen;
integer gBatch;
key gOperation = NULL_KEY;
key gDestination = NULL_KEY;

integer pages(list rows)
{
    integer total = (llGetListLength(rows) / 3 + 3) / 4;
    if (total < 1) total = 1;
    return total;
}
integer find(list rows, key source)
{
    integer i;
    for (i = 0; i < llGetListLength(rows); i += 3)
        if (llList2Key(rows, i) == source) return i;
    return -1;
}
integer save()
{
    integer result = llLinksetDataWrite("mc:p3:selection", llList2Json(JSON_ARRAY,
        [gProduct, llList2Json(JSON_ARRAY, gSelected), gOperation, gDestination]));
    if (result == 0 || result == 5) return TRUE;
    gOpen = FALSE; gBatch = FALSE;
    llOwnerSay("[Containers] Cannot save selection. Actions stopped.");
    return FALSE;
}
view(list rows, integer page, string panel)
{
    integer total = pages(rows);
    list fields = [page + 1, total];
    integer i;
    for (i = 0; i < 4; ++i)
    {
        integer offset = (page * 4 + i) * 3;
        if (!gOpen || offset >= llGetListLength(rows)) fields += ["", 0, "", 0];
        else fields += [llList2String(rows, offset + 1), llList2Integer(rows, offset + 2), "", 1];
    }
    string packed;
    for (i = 0; i < 18; ++i)
    {
        if (i) packed += "|";
        packed += llEscapeURL(llList2String(fields, i));
    }
    llMessageLinked(LINK_THIS, 918290, packed, (key)panel);
}
render()
{
    if (gNearPage >= pages(gNear)) gNearPage = pages(gNear) - 1;
    if (gSelectedPage >= pages(gSelected)) gSelectedPage = pages(gSelected) - 1;
    view(gNear, gNearPage, "P3_NEAR");
    view(gSelected, gSelectedPage, "P3_SEL");
}
refresh()
{
    if (!gOpen || (gOperation != NULL_KEY)) return;
    gScan = llGenerateKey(); gScanning = TRUE; gReceiving = FALSE; gPending = [];
    // Use production discovery, not the P0 DEV Refresh adapter.
    llMessageLinked(LINK_THIS, 918270, "-918273", gScan);
    llSetTimerEvent(10.0);
}
nextTransfer()
{
    if (!gBatch || (gOperation != NULL_KEY) || !gOpen || gRemaining <= 0) return;
    if (!llGetListLength(gSelected)) { gBatch = FALSE; return; }
    gDestination = llList2Key(gSelected, 0); gOperation = llGenerateKey();
    if (save()) llMessageLinked(LINK_THIS, 918390, "TRANSFER|" + (string)gDestination, gOperation);
}
product(string text, key run)
{
    list fields = llParseStringKeepNulls(text, ["|"], []);
    string outputPhase = llList2String(fields, 0);
    gOpen = outputPhase != "CLOSED" && outputPhase != "RELEASED";
    if (gProduct != run)
    {
        gSelected = []; gNear = []; gNearPage = 0; gSelectedPage = 0;
        gOperation = NULL_KEY; gDestination = NULL_KEY; gBatch = FALSE;
    }
    integer wasOpen = gProduct == run && llGetListLength(gNear) > 0;
    gProduct = run; gRemaining = llList2Integer(fields, 1);
    if (!gOpen) { gBatch = FALSE; gOperation = NULL_KEY; gSelected = []; gNear = []; }
    if (!save()) return;
    render();
    if (gOpen && outputPhase == "WAIT_CONTAINER" && !wasOpen && (gOperation == NULL_KEY)) refresh();
}
button(string name)
{
    if (name == "p3_retry") { llMessageLinked(LINK_THIS, 918370, "RETRY", llGenerateKey()); return; }
    if (!gOpen) return;
    if (name == "p3_near_prev") { gNearPage = (gNearPage + pages(gNear) - 1) % pages(gNear); render(); return; }
    if (name == "p3_near_next") { gNearPage = (gNearPage + 1) % pages(gNear); render(); return; }
    if (name == "p3_selected_prev") { gSelectedPage = (gSelectedPage + pages(gSelected) - 1) % pages(gSelected); render(); return; }
    if (name == "p3_selected_next") { gSelectedPage = (gSelectedPage + 1) % pages(gSelected); render(); return; }
    if (gOperation) { llOwnerSay("[Containers] Request pending. Retry repeats the saved request."); return; }
    if (name == "p3_refresh") { refresh(); return; }
    if (name == "p3_action")
    {
        list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
        if (llList2String(session, 5) != "OUTPUT")
        { llOwnerSay("[Containers] Ingredient closure is still pending in this HUD."); return; }
        gBatch = TRUE; nextTransfer(); return;
    }
    if (name == "p3_discard")
    {
        if (gRemaining <= 0) return;
        list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
        if (llList2String(session, 5) != "OUTPUT") return;
        gBatch = FALSE; gOperation = llGenerateKey(); gDestination = NULL_KEY;
        if (save()) llMessageLinked(LINK_THIS, 918390, "DISCARD", gOperation);
        return;
    }
    if (gScanning) return;
    integer i;
    for (i = 0; i < 4; ++i)
    {
        // Physical Nearby buttons are named Remove but select a destination (+).
        if (name == "p3_near_remove_" + (string)i)
        {
            integer offset = (gNearPage * 4 + i) * 3;
            if (offset >= llGetListLength(gNear)) return;
            key source = llList2Key(gNear, offset);
            if (find(gSelected, source) < 0) gSelected += llList2List(gNear, offset, offset + 2);
            if (save()) render(); return;
        }
        if (name == "p3_selected_remove_" + (string)i)
        {
            integer offset = (gSelectedPage * 4 + i) * 3;
            if (offset >= llGetListLength(gSelected)) return;
            gSelected = llDeleteSubList(gSelected, offset, offset + 2);
            if (save()) render(); return;
        }
    }
}
default
{
    state_entry()
    {
        list saved = llJson2List(llLinksetDataRead("mc:p3:selection"));
        if (llGetListLength(saved) == 4)
        {
            gProduct = llList2Key(saved, 0); gSelected = llJson2List(llList2String(saved, 1));
            gOperation = llList2Key(saved, 2); gDestination = llList2Key(saved, 3);
        }
        list outputPhase = llParseStringKeepNulls(llLinksetDataRead("mc:p3:output"), ["|"], []);
        list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
        if (llGetListLength(outputPhase) == 4 && llList2Key(outputPhase, 0) == llList2Key(session, 6)
            && (llList2String(session, 5) == "OUTPUT" || llList2String(session, 5) == "WAIT_TRANSFER"
                || llList2String(session, 5) == "SETTLING"))
            product(llDumpList2String(llList2List(outputPhase, 1, 3), "|"), llList2Key(outputPhase, 0));
        render();
        llMessageLinked(LINK_THIS, 918390, "STATUS", NULL_KEY);
    }
    on_rez(integer parameter) { llResetScript(); }
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
    }
    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == 918391) { product(text, ticket); return; }
        if (number == 918291 && (text == "P3_NEAR" || text == "P3_SEL")) { render(); return; }
        if (number == 918392 && ticket == gProduct)
        {
            list fields = llParseStringKeepNulls(text, ["|"], []);
            if (llList2Key(fields, 1) != gOperation || (gOperation == NULL_KEY)) return;
            string status = llList2String(fields, 0);
            gRemaining = llList2Integer(fields, 2);
            if (status == "TRANSFERRED")
            {
                integer offset = find(gSelected, gDestination);
                if (offset >= 0) gSelected = llDeleteSubList(gSelected, offset, offset + 2);
                offset = find(gNear, gDestination);
                if (offset >= 0) gNear = llDeleteSubList(gNear, offset, offset + 2);
            }
            else gBatch = FALSE;
            gOperation = NULL_KEY; gDestination = NULL_KEY;
            if (save()) { render(); nextTransfer(); }
            return;
        }
        if (!gScanning || ticket != gScan) return;
        if (number == 918271) { gReceiving = TRUE; gPending = []; gItems = 0; gBlanks = 0; return; }
        if (!gReceiving) return;
        if (number == 918272) { ++gItems; return; }
        if (number == 918273)
        {
            ++gBlanks;
            list fields = llParseStringKeepNulls(text, ["|"], []);
            key source = llList2Key(fields, 1);
            integer capacity = llList2Integer(fields, 2);
            if (llGetListLength(fields) != 3 || source == NULL_KEY || capacity < 0
                || (string)capacity != llList2String(fields, 2) || llGetOwnerKey(source) != llGetOwner()) return;
            list details = llGetObjectDetails(source, [OBJECT_NAME]);
            if (!llGetListLength(details)) return;
            // Capacity 0 is unlimited in the existing physical protocol; keep it as 0.
            gPending += [source, llList2String(details, 0), capacity];
            return;
        }
        if (number == 918274)
        {
            list counts = llParseStringKeepNulls(text, ["|"], []);
            if (llList2Integer(counts, 0) == gItems && llList2Integer(counts, 1) == gBlanks)
            {
                gNear = gPending;
                integer i = llGetListLength(gSelected) - 3;
                for (; i >= 0; i -= 3)
                    if (find(gNear, llList2Key(gSelected, i)) < 0) gSelected = llDeleteSubList(gSelected, i, i + 2);
                if (save()) render();
            }
            gScanning = FALSE; gReceiving = FALSE; gPending = []; llSetTimerEvent(0.0);
        }
    }
    timer()
    {
        gScanning = FALSE; gReceiving = FALSE; gPending = []; llSetTimerEvent(0.0);
        llOwnerSay("[Containers] Scan interrupted. Press Refresh.");
    }
}

