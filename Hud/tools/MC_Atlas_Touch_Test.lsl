// Optional standalone test driver, in ROOT beside MC_Atlas_Player and textures.
// Display child must be named P1_DISPLAY. Do not install with MC_P1_Animation.
// Remove MC_Chop_Atlas_Test: it must not write the same face concurrently.
// Only this caller knows the texture name; player is generic.
string ATLAS = "atlas_chop";
integer gLoaded = FALSE;
integer gRunning = FALSE;
integer gPending = FALSE;
key gRequest;

send(integer command, string payload)
{
    gRequest = llGenerateKey();
    // REVIEW: no response timeout clears this lock if the player is absent; reset after restoring the player.
    gPending = TRUE;
    llMessageLinked(LINK_THIS, command, payload, gRequest);
}

default
{
    state_entry() { send(918330, ATLAS); }

    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber() || number != 918333) return;
        if (text == "READY" || text == "UNLOADED")
        {
            gLoaded = FALSE;
            gRunning = FALSE;
            send(918330, ATLAS);
            return;
        }
        if (ticket != gRequest) return;
        gPending = FALSE;
        if (llSubStringIndex(text, "ERROR:") == 0)
        {
            llOwnerSay("[Atlas test] " + text);
            return;
        }
        if (text == "LOADED")
        {
            gLoaded = TRUE;
            gRunning = FALSE;
            llOwnerSay("[Atlas test] Loaded " + ATLAS + ". Touch to play.");
        }
        else if (text == "PLAYING") gRunning = TRUE;
        else if (text == "REST") gRunning = FALSE;
    }

    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
        {
            if (llDetectedKey(i) == llGetOwner())
            {
                if (gPending) return;
                if (!gLoaded) send(918330, ATLAS);
                else if (gRunning) send(918332, "");
                else send(918331, "");
                return;
            }
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    on_rez(integer parameter) { llResetScript(); }
}
