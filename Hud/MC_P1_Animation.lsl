// ROOT. Visual wiring only; does not start/consume a business craft.
// MC_Atlas_Player and atlas textures must also be in ROOT.
// Remove MC_Atlas_Touch_Test and MC_Chop_Atlas_Test from the HUD.
string ATLAS = "atlas_chop";
string CUT_BUTTON = "p1_cut";
string STOP_BUTTON = "p1_stop";

integer gLoaded;
integer gWantRunning;
key gLoadTicket;
key gCommandTicket;
key gLastContinue;

// REVIEW: no LOAD timeout/retry exists. A missing or stopped player leaves the request pending until READY or reset.
loadAtlas()
{
    gLoaded = FALSE;
    gLoadTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918330, ATLAS, gLoadTicket);
}

applyDesired()
{
    if (!gLoaded) return;
    integer command = 918332;
    if (gWantRunning) command = 918331;
    gCommandTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, command, "", gCommandTicket);
}

// Save the latest intent so Stop overrides Cut even while atlas loading is pending.
want(integer running)
{
    gWantRunning = running;
    if (gLoaded) applyDesired();
    else if (gLoadTicket == NULL_KEY) loadAtlas();
}

button(string name)
{
    // Visual animation only: this does not debit stock or send CRAFT_STARTED.
    if (name == CUT_BUTTON) { want(TRUE); return; }
    if (name == STOP_BUTTON || name == "p1_discard" || name == "p1_later")
        want(FALSE);
}

default
{
    state_entry() { loadAtlas(); }

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
        if (number == 918310 && text == "CONTINUE" && ticket != NULL_KEY
            && ticket != gLastContinue)
        {
            gLastContinue = ticket;
            want(FALSE);
            return;
        }
        if (number == 918317 && text == "DISCARD_DONE" && ticket != NULL_KEY)
        { want(FALSE); return; }
        if (number != 918333) return;
        if (text == "READY") { loadAtlas(); return; }
        if (text == "UNLOADED")
        {
            gLoaded = FALSE;
            gWantRunning = FALSE;
            gLoadTicket = NULL_KEY;
            gCommandTicket = NULL_KEY;
            llOwnerSay("[P1 animation] Atlas removed from ROOT. Restore it, then press Cut.");
            return;
        }
        if (text == "LOADED" && ticket == gLoadTicket)
        {
            gLoadTicket = NULL_KEY;
            gLoaded = TRUE;
            applyDesired(); // Uses latest intent, including Stop while loading.
            return;
        }
        if (llSubStringIndex(text, "ERROR:") == 0
            && (ticket == gLoadTicket || ticket == gCommandTicket))
        {
            if (ticket == gLoadTicket) gLoadTicket = NULL_KEY;
            gCommandTicket = NULL_KEY;
            gLoaded = FALSE;
            gWantRunning = FALSE;
            llOwnerSay("[P1 animation] " + text);
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    on_rez(integer parameter) { llResetScript(); }
}
