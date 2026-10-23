// ROOT. Visual controls only; no craft consumption or CRAFT_STARTED.
// Requires MC_Atlas_Player, MC_Playback_Buttons and both atlas textures in ROOT.
string ATLAS = "atlas_chop";
string CUT_BUTTON = "p1_cut";
string STOP_BUTTON = "p1_stop";

integer gLoaded;
string gState = "STOPPED";
string gWanted = "STOPPED";
key gLoadTicket;
key gCommandTicket;
key gLastContinue;
integer gButtonsLoaded;
key gButtonsLoadTicket;
key gButtonsStateTicket;

loadButtons()
{
    gButtonsLoaded = FALSE;
    gButtonsLoadTicket = llGenerateKey();
    // Empty name delegates to the library's DEFAULT_ATLAS (atlas_buttons).
    llMessageLinked(LINK_THIS, 918340, "", gButtonsLoadTicket);
}

showButtons()
{
    if (!gButtonsLoaded) return;
    gButtonsStateTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918342, gState, gButtonsStateTicket);
}

loadAtlas()
{
    gLoaded = FALSE;
    gCommandTicket = NULL_KEY;
    gLoadTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918330, ATLAS, gLoadTicket);
}

applyDesired()
{
    // Serialize commands: clicks during an acknowledgement retain the latest intent.
    if (!gLoaded || gCommandTicket != NULL_KEY || gWanted == gState) return;
    integer command = 918332;
    if (gWanted == "PLAYING")
    {
        command = 918331;
        if (gState == "PAUSED") command = 918335;
    }
    else if (gWanted == "PAUSED")
    {
        if (gState != "PLAYING")
        {
            gWanted = "STOPPED";
            if (gState == "STOPPED") return;
        }
        else command = 918334;
    }
    gCommandTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, command, "", gCommandTicket);
}

want(string value)
{
    gWanted = value;
    if (gLoaded) applyDesired();
    else if (gLoadTicket == NULL_KEY) loadAtlas();
}

button(string name)
{
    if (name == CUT_BUTTON) { want("PLAYING"); return; }
    if (name == STOP_BUTTON)
    {
        // Stop during initial loading cancels the pending Start.
        if (gLoaded && gWanted == "PLAYING") want("PAUSED");
        else want("STOPPED");
        return;
    }
    if (name == "p1_discard" || name == "p1_later") want("STOPPED");
}

buttonsStatus(string text, key ticket)
{
    if (text == "READY") { loadButtons(); return; }
    if (text == "LOADED" && ticket == gButtonsLoadTicket)
    {
        gButtonsLoadTicket = NULL_KEY;
        gButtonsLoaded = TRUE;
        showButtons(); // Replay the latest confirmed state after library reset/load.
        return;
    }
    if (text == "UNLOADED")
    {
        gButtonsLoaded = FALSE;
        gButtonsLoadTicket = NULL_KEY;
        gButtonsStateTicket = NULL_KEY;
        llOwnerSay("[P1 buttons] Button atlas removed. Restore it in ROOT.");
        return;
    }
    if (llSubStringIndex(text, "ERROR:") == 0
        && (ticket == gButtonsLoadTicket || ticket == gButtonsStateTicket))
    {
        if (ticket == gButtonsLoadTicket)
        {
            gButtonsLoadTicket = NULL_KEY;
            gButtonsLoaded = FALSE;
        }
        gButtonsStateTicket = NULL_KEY;
        llOwnerSay("[P1 buttons] " + text);
    }
}

default
{
    state_entry() { loadAtlas(); loadButtons(); }

    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
        {
            if (llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
        }
    }

    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == 918343) { buttonsStatus(text, ticket); return; }
        if (number == 918310 && text == "CONTINUE" && ticket != NULL_KEY
            && ticket != gLastContinue)
        {
            gLastContinue = ticket;
            want("STOPPED");
            return;
        }
        if (number == 918317 && text == "DISCARD_DONE" && ticket != NULL_KEY)
        { want("STOPPED"); return; }
        if (number != 918333) return;
        if (text == "READY") { loadAtlas(); return; }
        if (text == "UNLOADED")
        {
            gLoaded = FALSE;
            gWanted = "STOPPED";
            gState = "STOPPED";
            gLoadTicket = NULL_KEY;
            gCommandTicket = NULL_KEY;
            showButtons();
            llOwnerSay("[P1 animation] Atlas removed from ROOT. Restore it, then press Start.");
            return;
        }
        if (text == "LOADED" && ticket == gLoadTicket)
        {
            gLoadTicket = NULL_KEY;
            gLoaded = TRUE;
            gState = "STOPPED";
            // A script reset ends a paused session; it cannot resume a lost frame/time.
            if (gWanted == "PAUSED") gWanted = "STOPPED";
            showButtons();
            applyDesired();
            return;
        }
        if (text == "PLAYING" || text == "PAUSED" || text == "REST")
        {
            gState = text;
            if (text == "REST") gState = "STOPPED";
            integer ownCommand = ticket == gCommandTicket && ticket != NULL_KEY;
            if (ownCommand) gCommandTicket = NULL_KEY;
            else if (gCommandTicket == NULL_KEY) gWanted = gState;
            showButtons();
            if (ownCommand) applyDesired();
            return;
        }
        if (llSubStringIndex(text, "ERROR:") == 0
            && (ticket == gLoadTicket || ticket == gCommandTicket))
        {
            if (ticket == gLoadTicket)
            {
                gLoadTicket = NULL_KEY;
                gLoaded = FALSE;
            }
            gCommandTicket = NULL_KEY;
            gWanted = gState;
            showButtons();
            llOwnerSay("[P1 animation] " + text);
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) { llResetScript(); return; }
        // Retry a missing/restored button texture without restarting playback.
        if ((change & CHANGED_INVENTORY) && !gButtonsLoaded
            && gButtonsLoadTicket == NULL_KEY) loadButtons();
    }

    on_rez(integer parameter) { llResetScript(); }
}
