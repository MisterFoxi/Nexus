// ROOT. Craft-page view of the existing basket. No second basket or source debit.
// Four visible source UUIDs only. P1 navigation never changes P0 pagination.
string PREFIX = "mc:simple:row:";
integer gPage;
integer gSelectedPage;
integer gPages = 1;
integer gScanning;
integer gIndex;
integer gCount;
integer gMinFree = 65536;
list gKeys;
list gView;
key gRender;
key gLastTicket;
// REVIEW: closed/cleared state is transient; resetting this controller after Discard reopens the empty 1/1 view.
integer gClosed;

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

render()
{
    gRender = llGenerateKey();
    gScanning = TRUE; gIndex = 0; gCount = 0;
    gKeys = []; gView = [];
    if (gClosed)
    {
        gScanning = FALSE;
        llMessageLinked(LINK_THIS, 918314, "CLEAR", (key)"P1");
        return;
    }
    llMessageLinked(LINK_THIS, 918313, "", gRender);
}

pump()
{
    // Same persistent basket, separate page cursor; this view never writes balances or sends TAKE.
    list keys = llLinksetDataFindKeys("^mc:simple:row:", gIndex, 1);
    if (llGetListLength(keys))
    {
        ++gIndex;
        string name = llList2String(keys, 0);
        key source = (key)llGetSubString(name, llStringLength(PREFIX), -1);
        list row = llParseStringKeepNulls(llLinksetDataRead(name), ["|"], []);
        integer quantity = llList2Integer(row, 0);
        // REVIEW: malformed storage leaves gScanning true and the previous display visible until reset or a new render request.
        if (!validKey(source) || llGetListLength(row) != 6 || quantity < 0
            || (string)quantity != llList2String(row, 0))
        {
            // Stop actions rather than keep a partially rebuilt row mapping.
            llOwnerSay("[Craft page] Invalid saved row. Refresh stopped.");
            return;
        }
        if (quantity > 0)
        {
            if (gCount >= gPage * 4 && gCount < gPage * 4 + 4)
            {
                list here = llParseStringKeepNulls(llUnescapeURL(llList2String(row, 5)), ["|"], []);
                gKeys += [source];
                gView += [llList2String(here, 2), quantity, llList2String(here, 12), 1];
            }
            ++gCount;
        }
        memory();
        llMessageLinked(LINK_THIS, 918313, "", gRender);
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
    gScanning = FALSE;
    llMessageLinked(LINK_THIS, 918314, text, (key)"P1");
    memory();
}

button(string name)
{
    if (name == "p1_take" || name == "p1_later" || name == "p1_exit" || name == "p1_retry")
    {
        string choice = "CONTAINER";
        if (name == "p1_later") choice = "KEEP";
        else if (name == "p1_exit") choice = "EXIT";
        else if (name == "p1_retry") choice = "RETRY";
        llMessageLinked(LINK_THIS, 918370, choice, llGenerateKey());
        return;
    }
    if (name == "p1_discard")
    {
        if (!gClosed) llMessageLinked(LINK_THIS, 918315, "DISCARD", llGenerateKey());
        return;
    }
    if (gScanning) return;
    if (gClosed) return;
    if (name == "p1_prev") { gPage = (gPage - 1 + gPages) % gPages; render(); return; }
    if (name == "p1_next") { gPage = (gPage + 1) % gPages; render(); return; }
    integer i;
    for (i = 1; i <= 4; ++i)
        if (name == "p1_remove_" + (string)i && i <= llGetListLength(gKeys))
        {
            // The basket controller validates and persists the RETURN request.
            llMessageLinked(LINK_THIS, 918312, "RETURN", llList2Key(gKeys, i - 1));
            return;
        }
}

default
{
    state_entry()
    {
        render();
        // Request the existing generic view, including its current page number.
        llMessageLinked(LINK_THIS, 918291, "SELECTED", NULL_KEY);
    }
    on_rez(integer parameter) { llResetScript(); }
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
    }
    link_message(integer sender, integer number, string text, key id)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == 918309)
        {
            memory();
            llOwnerSay("[Craft page] Free Mono memory: " + (string)llGetFreeMemory()
                + " bytes; observed minimum: " + (string)gMinFree + ".");
            return;
        }
        if (number == 918313 && id == gRender) { pump(); return; }
        if (number == 918317 && (text == "DISCARD_DONE" || text == "CRAFT_DONE") && id != NULL_KEY)
        {
            gClosed = TRUE; gPage = 0;
            render(); return;
        }
        if (number == 918290 && (string)id == "SELECTED")
        {
            // Observe only the P0 page number. Never navigate or write to P0.
            list view = llParseStringKeepNulls(text, ["|"], []);
            if (llGetListLength(view) == 18)
            {
                integer page = (integer)llUnescapeURL(llList2String(view, 0));
                if (page > 0) gSelectedPage = page - 1;
            }
            return;
        }
        if (number == 918310 && text == "CONTINUE" && id != NULL_KEY && id != gLastTicket)
        {
            gLastTicket = id;
            gClosed = FALSE;
            gPage = gSelectedPage;
            render(); return;
        }
        // Basket controller emits STOCK only after saving a confirmed result.
        // Restart with a new render token after a confirmed basket mutation; obsolete pump events are ignored.
        if (number == 918305 || (number == 918291 && text == "P1"))
        { render(); return; }
    }
}
