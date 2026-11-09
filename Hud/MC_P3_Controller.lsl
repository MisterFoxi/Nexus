string VERSION = "MC_P3_Controller v0.8.5 (2026-11-09)";
// ROOT. Finished-product recipients only. Never sends ingredient TAKE/RETURN/COMMIT.
// Views group container UUIDs by object name + icon UUID: four available types, one selected type.
list gNear; // stride 3: UUID, display name, capacity
list gIcons; // stride 2: container UUID, resolved icon (empty = default).
list gPendingIcons;
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

integer pages(list groups, integer pageSize)
{
    integer total = (llGetListLength(groups) / 3 + pageSize - 1) / pageSize;
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
// Keep the existing transfer rows and persisted UUIDs unchanged.
string iconFor(key source)
{
    integer i;
    for (i = 0; i < llGetListLength(gIcons); i += 2)
        if (llList2Key(gIcons, i) == source) return llList2String(gIcons, i + 1);
    return "";
}
// View groups: name/count/icon. Equal names with distinct icons stay separate.
list grouped(list rows, integer excludeSelected)
{
    list groups;
    integer i;
    for (i = 0; i < llGetListLength(rows); i += 3)
    {
        key source = llList2Key(rows, i);
        if (!excludeSelected || find(gSelected, source) < 0)
        {
            string name = llList2String(rows, i + 1);
            string icon = iconFor(source);
            integer match = -1;
            integer j;
            for (j = 0; j < llGetListLength(groups); j += 3)
                if (llList2String(groups, j) == name && llList2String(groups, j + 2) == icon) match = j;
            if (match < 0) groups += [name, 1, icon];
            else groups = llListReplaceList(groups, [llList2Integer(groups, match + 1) + 1], match + 1, match + 1);
        }
    }
    return groups;
}
integer save()
{
    list selectedIcons;
    integer i;
    for (i = 0; i < llGetListLength(gSelected); i += 3)
    {
        key source = llList2Key(gSelected, i);
        selectedIcons += [source, iconFor(source)];
    }
    integer result = llLinksetDataWrite("mc:p3:selection", llList2Json(JSON_ARRAY,
        [gProduct, llList2Json(JSON_ARRAY, gSelected), gOperation, gDestination, 0, NULL_KEY, llList2Json(JSON_ARRAY, selectedIcons)]));
    if (result == 0 || result == 5) return TRUE;
    gOpen = FALSE; gBatch = FALSE;
    llOwnerSay("[Containers] Cannot save selection. Actions stopped.");
    return FALSE;
}
view(list groups, integer page, string panel)
{
    integer pageSize = 4;
    if (panel == "P3_SEL") pageSize = 1;
    integer total = pages(groups, pageSize);
    list fields = [page + 1, total];
    // Informational rows stay unoccupied: no icon, quantity or selectable UUID.
    list guidance;
    if (gOpen && panel == "P3_NEAR" && !llGetListLength(groups))
    {
        if (gScanning) guidance = ["Recherche en cours", "Patientez...", "", ""];
        else if (llGetListLength(gSelected)) guidance = ["Tous les conteneurs", "sont selectionnes.", "Cliquez Transferer.", ""];
        else guidance = ["Aucun conteneur vide.", "Placez-en a proximite", "puis cliquez Actualiser.", ""];
    }
    integer i;
    for (i = 0; i < 4; ++i)
    {
        integer offset = (page * pageSize + i) * 3;
        if (!gOpen || i >= pageSize || offset >= llGetListLength(groups)) fields += [llList2String(guidance, i), 0, "", 0];
        else fields += [llList2String(groups, offset), llList2Integer(groups, offset + 1), llList2String(groups, offset + 2), 1];
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
    list nearGroups = grouped(gNear, TRUE);
    list selectedGroups = grouped(gSelected, FALSE);
    if (gNearPage >= pages(nearGroups, 4)) gNearPage = pages(nearGroups, 4) - 1;
    if (gSelectedPage >= pages(selectedGroups, 1)) gSelectedPage = pages(selectedGroups, 1) - 1;
    view(nearGroups, gNearPage, "P3_NEAR");
    view(selectedGroups, gSelectedPage, "P3_SEL");
}
refresh()
{
    if (!gOpen || (gOperation != NULL_KEY)) return;
    gScan = llGenerateKey(); gScanning = TRUE; gReceiving = FALSE; gPending = []; gPendingIcons = [];
    // Use production discovery, not the P0 DEV Refresh adapter.
    llMessageLinked(LINK_THIS, 918270, "-918273", gScan);
    llSetTimerEvent(10.0);
    render();
}
nextTransfer()
{
    if (!gBatch || (gOperation != NULL_KEY) || !gOpen || gRemaining <= 0) return;
    list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
    if (llList2String(session, 5) != "OUTPUT" || llList2Key(session, 6) != gProduct) return;
    if (!llGetListLength(gSelected)) { gBatch = FALSE; return; }
    gDestination = llList2Key(gSelected, 0); gOperation = llGenerateKey();
    if (save()) llMessageLinked(LINK_THIS, 918390, "TRANSFER|" + (string)gDestination, gOperation);
}
product(string text, key run)
{
    list fields = llParseStringKeepNulls(text, ["|"], []);
    string outputPhase = llList2String(fields, 0);
    // P3 is a recipient page, opened only by a known container output.
    if (outputPhase == "SELECTING") return; // Ignore obsolete preflight notifications.
    integer closed = outputPhase == "CLOSED" || outputPhase == "RELEASED";
    if (!closed && outputPhase != "WAIT_CONTAINER" && !gOpen) return;
    gOpen = !closed;
    if (gProduct != run)
    {
        gSelected = []; gNear = []; gNearPage = 0; gSelectedPage = 0;
        gOperation = NULL_KEY; gDestination = NULL_KEY; gBatch = FALSE;
    }
    integer wasOpen = gProduct == run && llGetListLength(gNear) > 0;
    gProduct = run; gRemaining = llList2Integer(fields, 1);
    if (!gOpen)
    {
        gBatch = FALSE; gOperation = NULL_KEY; gSelected = []; gNear = [];
        gScanning = FALSE; gReceiving = FALSE; gPending = []; gPendingIcons = []; gScan = NULL_KEY;
        llSetTimerEvent(0.0);
    }
    if (!save()) return;
    render();
    if (gOpen && outputPhase == "WAIT_CONTAINER")
    {
        if (!wasOpen && !gBatch && (gOperation == NULL_KEY)) refresh();
        nextTransfer();
    }
}
button(string name)
{
    if (llGetSubString(name, 0, 2) != "p3_") return;
    if (name == "p3_retry") { llMessageLinked(LINK_THIS, 918370, "RETRY", llGenerateKey()); return; }
    if (!gOpen) return;
    if (name == "p3_near_prev") { gNearPage = (gNearPage + pages(grouped(gNear, TRUE), 4) - 1) % pages(grouped(gNear, TRUE), 4); render(); return; }
    if (name == "p3_near_next") { gNearPage = (gNearPage + 1) % pages(grouped(gNear, TRUE), 4); render(); return; }
    if (name == "p3_selected_prev") { gSelectedPage = (gSelectedPage + pages(grouped(gSelected, FALSE), 1) - 1) % pages(grouped(gSelected, FALSE), 1); render(); return; }
    if (name == "p3_selected_next") { gSelectedPage = (gSelectedPage + 1) % pages(grouped(gSelected, FALSE), 1); render(); return; }
    if (gOperation) { llOwnerSay("[Containers] Request pending. Retry repeats the saved request."); return; }
    if (gBatch)
    { llOwnerSay("[Containers] Treatment or transfer pending. Selection retained."); return; }
    if (name == "p3_action1" || name == "p3_refresh") { refresh(); return; }
    if (name == "p3_action2" || name == "p3_action")
    {
        if (gScanning)
        { llOwnerSay("[Containers] Wait for the recipient scan."); return; }
        if (llGetListLength(grouped(gSelected, FALSE)) > 3)
        { llOwnerSay("[Containers] Previous selection has multiple types. Select one container type again before Transfer."); return; }
        list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
        if (llList2String(session, 5) != "OUTPUT")
        { llOwnerSay("[Containers] Ingredient closure is still pending in this HUD."); return; }
        if (!llGetListLength(gSelected))
        { llOwnerSay("[Containers] Select at least one recipient first."); return; }
        gBatch = TRUE; nextTransfer(); return;
    }
    if (gScanning) return;
    integer i;
    for (i = 0; i < 4; ++i)
    {
        if (name == "p3_sel_" + (string)i)
        {
            list groups = grouped(gNear, TRUE);
            integer offset = (gNearPage * 4 + i) * 3;
            if (offset >= llGetListLength(groups)) return;
            string selectedName = llList2String(groups, offset);
            string selectedIcon = llList2String(groups, offset + 2);
            // The lower table has one type row. A different type replaces the selection.
            if (llGetListLength(grouped(gSelected, FALSE)) > 3
                || (llGetListLength(gSelected) && (llList2String(gSelected, 1) != selectedName
                    || iconFor(llList2Key(gSelected, 0)) != selectedIcon)))
                gSelected = [];
            integer candidate;
            for (candidate = 0; candidate < llGetListLength(gNear); candidate += 3)
            {
                if (llList2String(gNear, candidate + 1) == selectedName
                    && iconFor(llList2Key(gNear, candidate)) == selectedIcon
                    && find(gSelected, llList2Key(gNear, candidate)) < 0)
                {
                    gSelected += llList2List(gNear, candidate, candidate + 2);
                    gSelectedPage = 0;
                    if (save()) render();
                    return;
                }
            }
            return;
        }
        if (name == "p3_sel_rem_0" && i == 0)
        {
            list groups = grouped(gSelected, FALSE);
            if (gSelectedPage * 3 >= llGetListLength(groups)) return;
            string selectedName = llList2String(groups, gSelectedPage * 3);
            string selectedIcon = llList2String(groups, gSelectedPage * 3 + 2);
            integer candidate;
            for (candidate = llGetListLength(gSelected) - 3; candidate >= 0; candidate -= 3)
            {
                if (llList2String(gSelected, candidate + 1) == selectedName
                    && iconFor(llList2Key(gSelected, candidate)) == selectedIcon)
                {
                    gSelected = llDeleteSubList(gSelected, candidate, candidate + 2);
                    if (save()) render();
                    return;
                }
            }
            return;
        }
    }
}
default
{
    state_entry()
    {
        llOwnerSay("[Nexus] " + VERSION);
        list saved = llJson2List(llLinksetDataRead("mc:p3:selection"));
        if (llGetListLength(saved) == 4 || llGetListLength(saved) == 6 || llGetListLength(saved) == 7)
        {
            gProduct = llList2Key(saved, 0); gSelected = llJson2List(llList2String(saved, 1));
            gOperation = llList2Key(saved, 2); gDestination = llList2Key(saved, 3);
            if (llGetListLength(saved) == 7) gIcons = llJson2List(llList2String(saved, 6));
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
        if (number == 918271) { gReceiving = TRUE; gPending = []; gPendingIcons = []; gItems = 0; gBlanks = 0; return; }
        if (!gReceiving) return;
        if (number == 918272) { ++gItems; return; }
        if (number == 918273)
        {
            ++gBlanks;
            list fields = llParseStringKeepNulls(text, ["|"], []);
            key source = llList2Key(fields, 1);
            integer capacity = llList2Integer(fields, 2);
            if ((llGetListLength(fields) != 3 && llGetListLength(fields) != 4) || source == NULL_KEY || capacity < 0
                || (string)capacity != llList2String(fields, 2) || llGetOwnerKey(source) != llGetOwner()) return;
            list details = llGetObjectDetails(source, [OBJECT_NAME]);
            if (!llGetListLength(details)) return;
            // Capacity 0 is unlimited in the existing physical protocol; keep it as 0.
            integer existing = find(gPending, source);
            list row = [source, llList2String(details, 0), capacity];
            string icon;
            key texture = (key)llStringTrim(llList2String(fields, 3), STRING_TRIM);
            if (texture) icon = llToLower((string)texture);
            if (existing < 0)
            {
                gPending += row;
                gPendingIcons += [source, icon];
            }
            else
            {
                gPending = llListReplaceList(gPending, row, existing, existing + 2);
                integer iconIndex = existing / 3 * 2;
                gPendingIcons = llListReplaceList(gPendingIcons, [source, icon], iconIndex, iconIndex + 1);
            }
            return;
        }
        if (number == 918274)
        {
            list counts = llParseStringKeepNulls(text, ["|"], []);
            if (llList2Integer(counts, 0) == gItems && llList2Integer(counts, 1) == gBlanks)
            {
                gNear = gPending; gIcons = gPendingIcons; gPendingIcons = [];
                integer i = llGetListLength(gSelected) - 3;
                for (; i >= 0; i -= 3)
                {
                    integer current = find(gNear, llList2Key(gSelected, i));
                    if (current < 0) gSelected = llDeleteSubList(gSelected, i, i + 2);
                    else gSelected = llListReplaceList(gSelected, llList2List(gNear, current, current + 2), i, i + 2);
                }
                gScanning = FALSE;
                if (save()) render();
            }
            gScanning = FALSE; gReceiving = FALSE; gPending = []; gPendingIcons = []; llSetTimerEvent(0.0);
        }
    }
    timer()
    {
        gScanning = FALSE; gReceiving = FALSE; gPending = []; gPendingIcons = []; llSetTimerEvent(0.0);
        render();
        llOwnerSay("[Containers] Recherche interrompue. Cliquez sur Actualiser.");
    }
}

