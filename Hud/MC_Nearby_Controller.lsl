// Nearby data and independent pagination controller. Install in ROOT with MC_Render.
// Replaces MC_Nearby_Display; never install both controllers together.
// All physical buttons are script-free; root receives their touch events.
string PREV_NAME = "P0_NEAR_PREV";
string NEXT_NAME = "P0_NEAR_NEXT";
integer VIEW = 918290;
integer RENDER_READY = 918291;
integer ADD = 918300;
integer TX_STATE = 918302;
integer STOCK = 918305;
integer REFRESH_REQUEST = 918287;
// Verify these names against the physical '+' buttons before installation.
string ADD_PREFIX = "P0_NEAR_ADD_";
integer gTxBusy = TRUE;
integer gRescan;
integer gPreserveNextScan;
integer gKeepPage;
integer SCAN_REFRESH = 918270;
// MC_Scan_Refresh relays SCAN_* messages with code + 10, same text/request.
integer DISPLAY_BEGIN = 918281;
integer DISPLAY_ITEM  = 918282;
integer DISPLAY_BLANK = 918283;
integer DISPLAY_END   = 918284;
integer DISPLAY_ABORT = 918285;

integer gPage; // zero-based, displayed one-based
integer gWaiting;
integer gReceiving;
integer gRefreshLink;
integer gBlankCount;
key gRequest;
// Stride 3: full name, source UUID, complete original HERE message.
list gRows;
// REVIEW: both snapshots retain complete HERE messages without a size/count budget; many sources or large payloads can exhaust script memory.
list gPending;

integer pageCount()
{
    integer count = (llGetListLength(gRows) / 3 + 3) / 4;
    if (count < 1) count = 1;
    return count;
}

string packView(list view)
{
    // Only the visible page: 18 bounded fields, never the basket.
    string text = "";
    integer i;
    for (i = 0; i < 18; ++i)
    {
        if (i) text += "|";
        text += llEscapeURL(llList2String(view, i));
    }
    return text;
}

render()
{
    integer total = pageCount();
    if (gPage >= total) gPage = total - 1;
    if (gPage < 0) gPage = 0;
    list view = [gPage + 1, total];
    integer row;
    for (row = 0; row < 4; ++row)
    {
        integer index = (gPage * 4 + row) * 3;
        if (index >= llGetListLength(gRows)) view += ["", 0, "", 0];
        else
        {
            list fields = llParseStringKeepNulls(llList2String(gRows, index + 2), ["|"], []);
            view += [llList2String(gRows, index), llList2Integer(fields, 3),
                llList2String(fields, 12), 1];
        }
    }
    llMessageLinked(LINK_THIS, VIEW, packView(view), (key)"NEARBY");
}

navigate(integer direction)
{
    integer total = pageCount();
    gPage = (gPage + direction + total) % total;
    render();
}


button(string name)
{
    if (name == llToLower(PREV_NAME)) { navigate(-1); return; }
    if (name == llToLower(NEXT_NAME)) { navigate(1); return; }
    integer row;
    for (row = 1; row <= 4; ++row)
        if (name == llToLower(ADD_PREFIX) + (string)row)
        {
            if (gTxBusy) { llOwnerSay("[Nearby] Wait for the transaction manager."); return; }
            integer index = (gPage * 4 + row - 1) * 3;
            if (index >= llGetListLength(gRows)) return;
            key source = llList2Key(gRows, index + 1);
            if (!llGetListLength(llGetObjectDetails(source, [OBJECT_NAME])))
            {
                gRows = llDeleteSubList(gRows, index, index + 2);
                gWaiting = FALSE; gReceiving = FALSE; gPending = [];
                render();
                llOwnerSay("[Nearby] Source missing: row removed; no ingredient taken.");
                llMessageLinked(LINK_THIS, REFRESH_REQUEST, "KEEP_PAGE", NULL_KEY);
                return;
            }
            llMessageLinked(LINK_THIS, ADD, llList2String(gRows, index + 2), llList2Key(gRows, index + 1));
            return;
        }
}

// Keep source UUID as identity even when two sources share the same displayed name.
addPending(string payload)
{
    list fields = llParseStringKeepNulls(payload, ["|"], []);
    if (llGetListLength(fields) < 10 || llList2String(fields, 0) != "HERE") return;
    key source = llList2Key(fields, 1);
    if (source == NULL_KEY || llList2Integer(fields, 3) <= 0) return;
    integer i;
    for (i = 0; i < llGetListLength(gPending); i += 3)
        if (llList2Key(gPending, i + 1) == source) return;
    gPending += [llList2String(fields, 2), source, payload];
}

default
{
    state_entry() { render(); }

    on_rez(integer parameter) { llResetScript(); }

    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
        {
            if (llDetectedKey(i) == llGetOwner())
            {
                string name = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM));
                button(name);
            }
        }
    }

    link_message(integer sender, integer number, string payload, key request)
    {
        if (sender == llGetLinkNumber() && number == REFRESH_REQUEST)
        { gPreserveNextScan = payload == "KEEP_PAGE"; return; }
        if (sender == llGetLinkNumber() && number == TX_STATE)
        {
            integer wasBusy = gTxBusy;
            gTxBusy = payload != "IDLE";
            if (gTxBusy)
            {
                // A scan begun before a stock mutation must never overwrite its result.
                if (!wasBusy) { gWaiting = FALSE; gReceiving = FALSE; gPending = []; }
                gRescan = TRUE;
            }
            else if (gRescan)
            {
                gRescan = FALSE;
                llMessageLinked(LINK_THIS, REFRESH_REQUEST, "KEEP_PAGE", NULL_KEY);
            }
            return;
        }
        if (sender == llGetLinkNumber() && number == STOCK)
        {
            list stock = llParseStringKeepNulls(payload, ["|"], []);
            if (llGetListLength(stock) != 2) return;
            key source = llList2Key(stock, 0);
            integer quantity = llList2Integer(stock, 1);
            // A stock check during an unknown operation may have preceded its application.
            gWaiting = FALSE; gReceiving = FALSE; gPending = [];
            integer i;
            for (i = 0; i < llGetListLength(gRows); i += 3)
                if (llList2Key(gRows, i + 1) == source)
                {
                    if (quantity <= 0) gRows = llDeleteSubList(gRows, i, i + 2);
                    else
                    {
                        list here = llParseStringKeepNulls(llList2String(gRows, i + 2), ["|"], []);
                        here = llListReplaceList(here, [quantity], 3, 3);
                        gRows = llListReplaceList(gRows, [llDumpList2String(here, "|")], i + 2, i + 2);
                    }
                    jump stockApplied;
                }
            @stockApplied;
            render(); return;
        }
        if (number == RENDER_READY && sender == llGetLinkNumber() && payload == "NEARBY") { render(); return; }
        // REVIEW: this branch accepts scan requests from any link; enforce the intended root/client link if child scripts are not trusted.
        if (number == SCAN_REFRESH && request != NULL_KEY)
        {
            gKeepPage = gPreserveNextScan;
            gPreserveNextScan = FALSE;
            gRequest = request;
            gRefreshLink = sender;
            gWaiting = TRUE;
            gReceiving = FALSE;
            gPending = [];
            gBlankCount = 0;
            return;
        }
        if (!gWaiting || request != gRequest || sender != gRefreshLink) return;
        if (number == DISPLAY_ABORT)
        {
            gWaiting = FALSE;
            gReceiving = FALSE;
            gPending = [];
            return; // keep last completed snapshot
        }
        if (number == DISPLAY_BEGIN)
        {
            gPending = [];
            gBlankCount = 0;
            gReceiving = TRUE;
            return;
        }
        if (!gReceiving) return;
        if (number == DISPLAY_ITEM) addPending(payload);
        else if (number == DISPLAY_BLANK) ++gBlankCount;
        else if (number == DISPLAY_END)
        {
            list counts = llParseStringKeepNulls(payload, ["|"], []);
            if (llList2Integer(counts, 0) == llGetListLength(gPending) / 3
                && llList2Integer(counts, 1) == gBlankCount)
            {
                gRows = llListSort(gPending, 3, TRUE);
                if (!gKeepPage) gPage = 0;
                render();
            }
            else llOwnerSay("[Nearby] Incomplete scan result. Press Refresh again.");
            gPending = [];
            gWaiting = FALSE;
            gReceiving = FALSE;
        }
    }
}

