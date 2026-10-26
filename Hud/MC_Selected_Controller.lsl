// ROOT. One persistent row per source; only four display rows in script memory.
// TAKE sets units aside; RETURN restores unused units; COMMIT closes used units after OK.
string PREFIX = "mc:simple:row:";
integer gFault;
integer gPage;
integer gPages = 1;
integer gBusy = TRUE;
integer gScanning;
integer gIndex;
integer gCount;
integer gAvailable;
integer gCanContinue;
list gKeys; // At most four visible source UUIDs.
list gView; // At most sixteen visible row fields.
key gRender;
key gActive = NULL_KEY;
integer gMinFree = 65536;
integer gCraftStarted;
integer gDiscard; // 0 idle, 1 return all, 2 commit used units (loss, no product).
integer gDiscardIndex;
integer gDiscardSweep; // Clear pre-existing pending rows before returning confirmed rows.
integer gDiscardHasUnits;
key gDiscardRun;
key gDiscardTicket;
key gCompletionTicket = NULL_KEY;
key gExportTicket = NULL_KEY;
integer gExportIndex;
integer gExportCheck;
integer gExportCount;
string gExportType;
key gTypeSource = NULL_KEY;
string gTypeHere;
integer gTypeIndex;

integer validKey(key value)
{
    if (value) return TRUE;
    return FALSE;
}

memory()
{
    integer free = llGetFreeMemory();
    if (free < gMinFree) gMinFree = free;
}

fault(string reason)
{
    gFault = TRUE;
    llOwnerSay("[Selected] " + reason + " Ingredients retained; storage is locked.");
}

// Row: held quantity | last applied request | pending request | TAKE/RETURN/COMMIT |
// amount | URL-escaped HERE. No session, take ledger or batch.
// Persist one source balance and its pending operation together; URL-escape nested HERE data.
list readRow(key source)
{
    string text = llLinksetDataRead(PREFIX + (string)source);
    if (text == "") return [0, "", "", "", 0, ""];
    list row = llParseStringKeepNulls(text, ["|"], []);
    if (llGetListLength(row) != 6 || llList2Integer(row, 0) < 0
        || (string)llList2Integer(row, 0) != llList2String(row, 0))
    { fault("Invalid saved row."); return []; }
    if (llList2String(row, 2) != "")
    {
        key request = llList2Key(row, 2);
        string verb = llList2String(row, 3);
        if (!validKey(request) || (verb != "TAKE" && verb != "RETURN" && verb != "COMMIT")
            || llList2Integer(row, 4) < 1)
        { fault("Invalid pending request."); return []; }
    }
    return row;
}

integer writeRow(key source, list row)
{
    integer result = llLinksetDataWrite(PREFIX + (string)source, llDumpList2String(row, "|"));
    if (result == 0 || result == 5) return TRUE;
    fault("Storage write failed."); return FALSE;
}

integer saveFlag(string name, integer value)
{
    integer result = llLinksetDataWrite("mc:simple:" + name, (string)value);
    if (result == 0 || result == 5) return TRUE;
    fault("Cannot save basket state."); return FALSE;
}

queueDiscard()
{
    if (!gDiscard || gFault) return;
    if ((!gDiscardSweep || gDiscard == 2) && (gBusy || gActive != NULL_KEY)) return;
    gDiscardRun = llGenerateKey();
    llMessageLinked(LINK_THIS, 918316, "", gDiscardRun);
}

render()
{
    if (gFault) return;
    gRender = llGenerateKey();
    gScanning = TRUE; gIndex = 0; gCount = 0; gAvailable = FALSE;
    gKeys = []; gView = [];
    llMessageLinked(LINK_THIS, 918307, "", gRender);
}

pump()
{
    // Read exactly one key and one record per event.
    // Yield between records to bound working memory; gRender invalidates obsolete traversal events.
    list keys = llLinksetDataFindKeys("^mc:simple:row:", gIndex, 1);
    if (llGetListLength(keys))
    {
        ++gIndex;
        key source = (key)llGetSubString(llList2String(keys, 0), llStringLength(PREFIX), -1);
        if (!validKey(source)) { fault("Invalid source key."); return; }
        list row = readRow(source);
        if (gFault) return;
        integer quantity = llList2Integer(row, 0);
        if (quantity > 0)
        {
            if (llList2String(row, 2) == "") gAvailable = TRUE;
            if (gCount >= gPage * 4 && gCount < gPage * 4 + 4)
            {
                list here = llParseStringKeepNulls(llUnescapeURL(llList2String(row, 5)), ["|"], []);
                gKeys += [source];
                gView += [llList2String(here, 2), quantity, llList2String(here, 12), 1];
            }
            ++gCount;
        }
        memory();
        llMessageLinked(LINK_THIS, 918307, "", gRender);
        return;
    }
    gPages = (gCount + 3) / 4;
    if (gPages < 1) gPages = 1;
    if (gPage >= gPages) { gPage = gPages - 1; render(); return; }
    integer i;
    for (i = llGetListLength(gKeys); i < 4; ++i) gView += ["", 0, "", 0];
    list view = [gPage + 1, gPages] + gView;
    string text = "";
    for (i = 0; i < 18; ++i)
    {
        if (i) text += "|";
        text += llEscapeURL(llList2String(view, i));
    }
    gScanning = FALSE; gCanContinue = gAvailable;
    llMessageLinked(LINK_THIS, 918290, text, (key)"SELECTED");
    memory();
}

start(string verb, key source, string here)
{
    if (verb != "COMMIT" && !gDiscard && (workshopBlocked() || gExportTicket != NULL_KEY || gTypeSource != NULL_KEY))
    { llOwnerSay("[Selected] Workshop treatment pending. Basket retained."); return; }
    if (gCraftStarted && verb != "COMMIT")
    { llOwnerSay("[Selected] Craft has started. Ingredients cannot be returned or added."); return; }
    if (verb == "COMMIT" && (!gCraftStarted || gDiscard != 2)) return;
    if (gBusy || gActive != NULL_KEY) { llOwnerSay("[Selected] Please wait for the source."); return; }
    list row = readRow(source);
    if (gFault) return;
    if (llList2String(row, 2) != "")
    { llOwnerSay("[Selected] This source has an unresolved request. Nothing sent."); return; }
    if ((verb == "RETURN" || verb == "COMMIT") && llList2Integer(row, 0) < 1) return;
    integer amount = 1;
    if (verb == "COMMIT") amount = llList2Integer(row, 0);
    gActive = llGenerateKey();
    row = llListReplaceList(row, [gActive, verb, amount, llEscapeURL(here)], 2, 5);
    if (!writeRow(source, row)) { gActive = NULL_KEY; return; }
    gBusy = TRUE;
    // The pending marker is saved first. Never resend it on reset or timeout.
    llMessageLinked(LINK_THIS, 918301, verb + "|" + (string)source + "|" + (string)amount, gActive);
    render(); memory();
}


// Workshop state is owned exclusively by MC_Workshop_Link.
list workshopSession()
{
    return llJson2List(llLinksetDataRead("mc:workshop:session"));
}

integer workshopBlocked()
{
    string saved = llLinksetDataRead("mc:workshop:session");
    if (saved == "") return FALSE; // Preserve the standalone DEV basket.
    list session = llJson2List(saved);
    return llGetListLength(session) != 13 || llList2Key(session, 0) != llGetKey()
        || llList2String(session, 5) != "IDLE";
}

string ingredientType(string text)
{
    list here = llParseStringKeepNulls(text, ["|"], []);
    // Type is independent of source UUID, stock, freshness and property variation.
    return llList2Json(JSON_ARRAY, [llList2String(here, 2), llList2String(here, 6),
        llList2String(here, 7), llList2String(here, 12)]);
}

typePump()
{
    if (gTypeSource == NULL_KEY) return;
    if (gDiscard || gCraftStarted) { gTypeSource = NULL_KEY; gTypeHere = ""; return; }
    if (workshopBlocked()) { gTypeSource = NULL_KEY; return; }
    list keys = llLinksetDataFindKeys("^mc:simple:row:", gTypeIndex, 1);
    if (llGetListLength(keys))
    {
        ++gTypeIndex;
        key source = (key)llGetSubString(llList2String(keys, 0), llStringLength(PREFIX), -1);
        list row = readRow(source);
        if (gFault) { gTypeSource = NULL_KEY; return; }
        if ((llList2Integer(row, 0) > 0 || llList2String(row, 2) != "")
            && ingredientType(llUnescapeURL(llList2String(row, 5))) != ingredientType(gTypeHere))
        {
            gTypeSource = NULL_KEY;
            llOwnerSay("[Selected] This workshop accepts one ingredient type. Multiple sources and units of that type are allowed.");
            return;
        }
        llMessageLinked(LINK_THIS, 918384, "", gTypeSource);
        return;
    }
    key source = gTypeSource; string here = gTypeHere;
    gTypeSource = NULL_KEY; gTypeHere = "";
    start("TAKE", source, here);
}

exportError(string reason)
{
    key ticket = gExportTicket; gExportTicket = NULL_KEY;
    llMessageLinked(LINK_THIS, 918381, "ERROR|" + reason, ticket);
}

exportPump()
{
    if (gExportTicket == NULL_KEY || gFault) return;
    list session = workshopSession();
    if (llList2Key(session, 6) != gExportTicket) { gExportTicket = NULL_KEY; return; }
    list keys = llLinksetDataFindKeys("^mc:simple:row:", gExportIndex, 1);
    if (llGetListLength(keys))
    {
        ++gExportIndex;
        key source = (key)llGetSubString(llList2String(keys, 0), llStringLength(PREFIX), -1);
        list row = readRow(source);
        if (gFault) return;
        if (llList2String(row, 2) != "") { exportError("A source request is unresolved."); return; }
        if (llList2Integer(row, 0) > 0)
        {
            string here = llUnescapeURL(llList2String(row, 5));
            if (gExportCheck)
            {
                string kind = ingredientType(here);
                if (gExportCount && llList2Integer(session, 3) && kind != gExportType)
                { exportError("The basket contains different ingredient types."); return; }
                gExportType = kind; ++gExportCount;
            }
            else
            {
                llMessageLinked(LINK_THIS, 918381, "ROW|" + (string)gExportIndex + "|"
                    + (string)source + "|" + llList2String(row, 0) + "|" + llEscapeURL(here), gExportTicket);
                return; // Wait for the remote row acknowledgement through the link controller.
            }
        }
        llMessageLinked(LINK_THIS, 918382, "", gExportTicket);
        return;
    }
    if (gExportCheck)
    {
        if (!gExportCount) { exportError("The basket is empty."); return; }
        gExportCheck = FALSE; gExportIndex = 0;
        llMessageLinked(LINK_THIS, 918381, "BEGIN", gExportTicket);
    }
    else llMessageLinked(LINK_THIS, 918381, "END", gExportTicket);
}

exportRequest(string text, key ticket)
{
    list session = workshopSession();
    if (ticket == NULL_KEY || ticket != llList2Key(session, 6)) return;
    if (text == "CANCEL") { gExportTicket = NULL_KEY; return; }
    if (text == "EXPORT")
    {
        if (llList2String(session, 5) != "SNAPSHOT") return;
        gExportTicket = ticket;
        if (!gCraftStarted || gDiscard || gBusy || gActive != NULL_KEY || gTypeSource != NULL_KEY)
        { exportError("Basket update pending or preparation not started."); return; }
        gExportCheck = TRUE; gExportIndex = 0; gExportCount = 0; gExportType = "";
        llMessageLinked(LINK_THIS, 918382, "", ticket);
        return;
    }
    list fields = llParseStringKeepNulls(text, ["|"], []);
    if (llList2String(fields, 0) != "NEXT" || llGetListLength(fields) != 2
        || llList2String(session, 5) != "ROWS") return;
    integer index = llList2Integer(fields, 1);
    if (index < 0 || (string)index != llList2String(fields, 1)) return;
    gExportTicket = ticket; gExportCheck = FALSE; gExportIndex = index;
    llMessageLinked(LINK_THIS, 918382, "", ticket);
}

// REVIEW: discard and craft_started are separate writes. A reset/write failure between them can leave a partially finalized basket state.
finishDiscard()
{
    if (!saveFlag("discard", 0) || !saveFlag("craft_started", FALSE)) return;
    gCraftStarted = FALSE; gDiscard = 0;
    gDiscardRun = NULL_KEY;
    render();
    gExportTicket = NULL_KEY;
    if (gCompletionTicket != NULL_KEY)
    {
        integer result = llLinksetDataWrite("mc:simple:completed", (string)gCompletionTicket);
        if (result != 0 && result != 5) { fault("Cannot save craft closure."); return; }
        llMessageLinked(LINK_THIS, 918317, "CRAFT_DONE", gCompletionTicket);
        llOwnerSay("[Selected] Craft stock closure complete.");
    }
    else
    {
        llMessageLinked(LINK_THIS, 918317, "DISCARD_DONE", gDiscardTicket);
        llOwnerSay("[Selected] Discard complete.");
    }
}

discardPump()
{
    if (!gDiscard) return;
    if ((!gDiscardSweep || gDiscard == 2) && (gBusy || gActive != NULL_KEY)) return;
    // REVIEW: zero rows are never collected. Unique sources accumulate persistent records and increase every full traversal cost.
    // Never delete row keys: zero rows keep stable progressive offsets.
    list keys = llLinksetDataFindKeys("^mc:simple:row:", gDiscardIndex, 1);
    if (llGetListLength(keys))
    {
        key source = (key)llGetSubString(llList2String(keys, 0), llStringLength(PREFIX), -1);
        if (!validKey(source)) { fault("Invalid source key."); return; }
        list row = readRow(source);
        if (gFault) return;
        if (llList2String(row, 2) != "")
        {
            // Used units must remain recorded until the component confirms closure.
            // Includes a pending COMMIT restored after reset. Never resend automatically.
            if (gDiscard == 2) return;
            // Before Start, preserve the existing explicit-Discard uncertainty policy.
            // Clear the pending UUID before releasing the relay: late replies are ignored.
            key pending = llList2Key(row, 2);
            row = llListReplaceList(row, [0, llList2String(row, 1), "", "", 0], 0, 4);
            if (!writeRow(source, row)) return;
            if (gActive == pending) gActive = NULL_KEY;
            llMessageLinked(LINK_THIS, 918304, "", pending);
            llOwnerSay("[Selected] Unconfirmed request discarded for source "
                + (string)source + ". Remaining units abandoned.");
            ++gDiscardIndex;
        }
        else if (!gDiscardSweep && llList2Integer(row, 0) > 0)
        {
            if (gDiscard == 1)
            {
                // Repeat only after OK. Each request uses the existing saved-row path.
                start("RETURN", source, llUnescapeURL(llList2String(row, 5)));
                return;
            }
            // Commit all confirmed units from this source; no second stock debit.
            start("COMMIT", source, llUnescapeURL(llList2String(row, 5)));
            return;
        }
        else
        {
            if (llList2Integer(row, 0) > 0) gDiscardHasUnits = TRUE;
            ++gDiscardIndex;
        }
        memory(); queueDiscard(); return;
    }
    if (gDiscardSweep)
    {
        // An empty basket needs no relay availability to finish.
        if (!gDiscardHasUnits) { finishDiscard(); return; }
        gDiscardSweep = FALSE; gDiscardIndex = 0;
        queueDiscard(); return;
    }
    // All rows are empty; uncertainties were explicitly abandoned by Discard.
    finishDiscard();
}

basketAction(string action, key ticket)
{
    if (!validKey(ticket)) return;
    list workshop = workshopSession();
    if (action == "COMPLETE")
    {
        if (ticket != llList2Key(workshop, 6) || llList2String(workshop, 5) != "SETTLING") return;
        if (llLinksetDataRead("mc:simple:completed") == (string)ticket)
        { llMessageLinked(LINK_THIS, 918317, "CRAFT_DONE", ticket); return; }
        if (gDiscard) return;
        // A reset after all balances were closed can finish without a new source request.
        if (!gCraftStarted)
        {
            gCompletionTicket = ticket;
            finishDiscard();
            return;
        }
        integer saved = llLinksetDataWrite("mc:simple:completion", (string)ticket);
        if (saved != 0 && saved != 5) { fault("Cannot save craft closure."); return; }
        gCompletionTicket = ticket;
        if (!saveFlag("discard", 2)) return;
        gDiscard = 2; gDiscardIndex = 0; gDiscardSweep = TRUE; gDiscardHasUnits = FALSE;
        gExportTicket = NULL_KEY;
        queueDiscard();
        return;
    }
    if (workshopBlocked() && !(action == "DISCARD" && llList2String(workshop, 5) == "EXITING"
        && ticket == llList2Key(workshop, 6)))
    { llOwnerSay("[Selected] Workshop treatment pending. Basket retained."); return; }
    // This is the engine handshake, independent of visual Cut/Stop; wait for its persisted ACK.
    if (action == "CRAFT_STARTED")
    {
        if (gDiscard || gBusy || gActive != NULL_KEY || gTypeSource != NULL_KEY || gScanning || !gCanContinue)
        { llOwnerSay("[Selected] Cannot start craft during a basket update or with no available ingredients."); return; }
        // The craft engine must request this before starting and wait for this ACK.
        if (!saveFlag("craft_started", TRUE)) return;
        gCraftStarted = TRUE;
        llMessageLinked(LINK_THIS, 918317, "CRAFT_STARTED", ticket);
        return;
    }
    if (action != "DISCARD") return;
    gTypeSource = NULL_KEY; gTypeHere = "";
    if (gDiscard)
    {
        llOwnerSay("[Selected] Discard is in progress. Please wait.");
        return;
    }
    integer cleared = llLinksetDataDelete("mc:simple:completion");
    if (cleared != 0 && cleared != 4) { fault("Cannot initialize discard."); return; }
    gCompletionTicket = NULL_KEY;
    integer mode = 1;
    if (gCraftStarted) mode = 2;
    if (!saveFlag("discard", mode)) return;
    gDiscard = mode; gDiscardTicket = ticket;
    gDiscardIndex = 0; gDiscardSweep = TRUE; gDiscardHasUnits = FALSE;
    queueDiscard();
}

button(string name)
{
    // Ignore P1 and other root touches before reporting any Selected state.
    if (name != "p0_continue" && name != "p0_sel_prev" && name != "p0_sel_next"
        && llGetSubString(name, 0, 13) != "p0_sel_remove_") return;
    if (gFault) return;
    if (gDiscard) { llOwnerSay("[Selected] Discard is in progress. Please wait."); return; }
    if (name == "p0_continue")
    {
        if (gBusy || gActive != NULL_KEY || gScanning)
        { llOwnerSay("[Selected] Please wait for the current update."); return; }
        if (!gCanContinue) { llOwnerSay("[Selected] No available ingredients set aside."); return; }
        llMessageLinked(LINK_THIS, 918310, "CONTINUE", llGenerateKey());
        return;
    }
    if (gScanning) return;
    if (name == "p0_sel_prev") { gPage = (gPage - 1 + gPages) % gPages; render(); return; }
    if (name == "p0_sel_next") { gPage = (gPage + 1) % gPages; render(); return; }
    integer i;
    for (i = 1; i <= 4; ++i)
        if (name == "p0_sel_remove_" + (string)i && i <= llGetListLength(gKeys))
        {
            key source = llList2Key(gKeys, i - 1);
            list row = readRow(source);
            if (!gFault) start("RETURN", source, llUnescapeURL(llList2String(row, 5)));
            return;
        }
}

default
{
    state_entry()
    {
        // DEV reset explicitly requested: discard old basket/transport data only.
        integer deleted = llLinksetDataDelete("mc:selected2");
        if (deleted != 0 && deleted != 4) { fault("Cannot remove old DEV basket."); return; }
        deleted = llLinksetDataDelete("mc:tx2");
        if (deleted != 0 && deleted != 4) { fault("Cannot remove old DEV transport."); return; }
        if (llLinksetDataRead("mc:simple:ready") != "1")
        {
            integer result = llLinksetDataWrite("mc:simple:owner", (string)llGetKey());
            if (result != 0 && result != 5) { fault("Cannot save HUD identity."); return; }
            result = llLinksetDataWrite("mc:simple:ready", "1");
            if (result != 0 && result != 5) { fault("Cannot initialize storage."); return; }
        }
        if (llLinksetDataRead("mc:simple:owner") != (string)llGetKey())
        { fault("HUD identity changed. Existing ingredients need review."); return; }
        gCompletionTicket = (key)llLinksetDataRead("mc:simple:completion");
        if (!validKey(gCompletionTicket)) gCompletionTicket = NULL_KEY;
        string savedCraft = llLinksetDataRead("mc:simple:craft_started");
        string savedDiscard = llLinksetDataRead("mc:simple:discard");
        if ((savedCraft != "" && savedCraft != "0" && savedCraft != "1")
            || (savedDiscard != "" && savedDiscard != "0" && savedDiscard != "1" && savedDiscard != "2"))
        { fault("Invalid saved basket state."); return; }
        gCraftStarted = (integer)savedCraft;
        gDiscard = (integer)savedDiscard;
        gDiscardSweep = gDiscard != 0;
        if (gDiscard == 1 && gCraftStarted) { fault("Invalid discard mode."); return; }
        if (gDiscard == 2 && !gCraftStarted) { fault("Invalid discard mode."); return; }
        gDiscardTicket = llGenerateKey();
        render();
        queueDiscard();
    }
    on_rez(integer parameter) { llResetScript(); }
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
    }
    link_message(integer sender, integer number, string text, key request)
    {
        // Trust boundary: same-prim scripts cooperate; this check does not distinguish individual scripts within the root.
        if (sender != llGetLinkNumber()) return;
        if (number == 918309)
        {
            memory(); llOwnerSay("[Selected] Free Mono memory: " + (string)llGetFreeMemory()
                + " bytes; observed minimum: " + (string)gMinFree + "."); return;
        }
        if (gFault) return;
        if (number == 918380) { exportRequest(text, request); return; }
        if (number == 918382 && request == gExportTicket) { exportPump(); return; }
        if (number == 918384 && request == gTypeSource) { typePump(); return; }
        if (number == 918315) { basketAction(text, request); return; }
        if (number == 918316 && request == gDiscardRun) { discardPump(); return; }
        if (number == 918307 && request == gRender) { pump(); return; }
        if (number == 918291 && text == "SELECTED") { render(); return; }
        if (number == 918302)
        {
            gBusy = text != "IDLE";
            // Relay reset/timeout releases other sources; saved pending rows remain blocked.
            if (!gBusy) gActive = NULL_KEY;
            queueDiscard();
            return;
        }
        // Generic basket API: return one held unit from a source UUID.
        // Caller supplies no quantity, HERE or saved-row contents.
        if (number == 918312 && text == "RETURN" && validKey(request))
        {
            if (gDiscard) return;
            list row = readRow(request);
            if (!gFault) start("RETURN", request, llUnescapeURL(llList2String(row, 5)));
            return;
        }
        if (number == 918300)
        {
            if (gDiscard) return;
            list fields = llParseStringKeepNulls(text, ["|"], []);
            if (!validKey(request) || llGetListLength(fields) < 10 || llList2String(fields, 0) != "HERE"
                || llList2Key(fields, 1) != request || llList2Integer(fields, 3) < 1
                || llList2Integer(fields, 9) != 5) return;
            if (workshopBlocked() || gTypeSource != NULL_KEY || gCraftStarted || gBusy || gActive != NULL_KEY) return;
            list session = workshopSession();
            if (llList2Integer(session, 3))
            {
                gTypeSource = request; gTypeHere = text; gTypeIndex = 0;
                llMessageLinked(LINK_THIS, 918384, "", request);
            }
            else start("TAKE", request, text);
            return;
        }
        if (number != 918303 || !validKey(request)) return;
        // verb | source | OK/NO | stock. Source authenticity checked by relay.
        list fields = llParseStringKeepNulls(text, ["|"], []);
        if (llGetListLength(fields) != 4) return;
        key source = llList2Key(fields, 1);
        if (!validKey(source)) return;
        list row = readRow(source);
        if (gFault || llList2Key(row, 2) != request
            || llList2String(row, 3) != llList2String(fields, 0)) return;
        string status = llList2String(fields, 2);
        if (status != "OK" && status != "NO") return;
        integer stock = llList2Integer(fields, 3);
        if (stock < 0 || (string)stock != llList2String(fields, 3)) return;
        integer quantity = llList2Integer(row, 0);
        if (status == "OK")
        {
            integer amount = llList2Integer(row, 4);
            // REVIEW: bound accumulated quantity before addition to prevent integer overflow from locking the row.
            if (llList2String(row, 3) == "TAKE") quantity += amount;
            else quantity -= amount;
            if (quantity < 0) { fault("Invalid returned quantity."); return; }
        }
        if (status == "NO" && llList2String(row, 3) == "COMMIT")
        {
            // A refusal is not closure. Keep the exact saved request and used latch.
            if (gActive == request) gActive = NULL_KEY;
            llMessageLinked(LINK_THIS, 918304, "", request);
            llOwnerSay("[Selected] COMMIT refused. Used units retained; Discard is not complete.");
            return;
        }
        if (status == "NO" && gDiscard == 1)
        {
            quantity = 0;
            llOwnerSay("[Selected] Source refused the return. Remaining units discarded.");
        }
        row = llListReplaceList(row, [quantity, request, "", "", 0], 0, 4);
        if (!writeRow(source, row)) return;
        if (gActive == request) gActive = NULL_KEY;
        if (status == "NO" && !gDiscard) llOwnerSay("[Selected] Source refused the request. Ingredients unchanged.");
        if (gDiscard)
        {
            gDiscardIndex = 0;
            queueDiscard();
        }
        llMessageLinked(LINK_THIS, 918305, (string)source + "|" + (string)stock, request);
        llMessageLinked(LINK_THIS, 918304, "", request);
        render(); memory();
    }
}
