// Current installation uses MC_Nearby_Controller instead of the archived MC_Nearby_Display.
// Place in the HUD ROOT prim, beside MC_Scan and MC_Nearby_Display.
// Remove the old script from the Refresh button; its touches must reach root.
// Only touching the named button starts a scan. Display receives relays.
string REFRESH_NAME = "P0_REFRESH";
integer TEST_CHANNEL = -918274;
integer SCAN_REFRESH = 918270;
integer SCAN_BEGIN   = 918271;
integer SCAN_ITEM    = 918272;
integer SCAN_BLANK   = 918273;
integer SCAN_END     = 918274;
integer DISPLAY_ABORT = 918285;
integer REFRESH_REQUEST = 918287;
key gRequest;
integer gWaiting;
integer gReceiving;


startRefresh()
{
    gRequest = llGenerateKey();
    gWaiting = TRUE;
    gReceiving = FALSE;
    llMessageLinked(LINK_SET, SCAN_REFRESH, (string)TEST_CHANNEL, gRequest);
    llSetTimerEvent(10.0);
}

default
{
    on_rez(integer parameter) { llResetScript(); }

    touch_start(integer count)
    {
        // REVIEW: only detection index zero is inspected; simultaneous touches can hide a valid owner click.
        if (llDetectedKey(0) != llGetOwner()) return;
        string touched = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(0)), STRING_TRIM));
        if (touched != llToLower(REFRESH_NAME)) return;
        startRefresh();
    }

    link_message(integer sender, integer number, string payload, key request)
    {
        if (number == REFRESH_REQUEST && sender == llGetLinkNumber()) { startRefresh(); return; }
        // REVIEW: matching a ticket alone does not validate the scan responder link; restrict sender when child scripts are not trusted.
        if (!gWaiting || request != gRequest) return;
        if (number < SCAN_BEGIN || number > SCAN_END) return;
        if (number == SCAN_BEGIN) gReceiving = TRUE;
        if (!gReceiving) return;
        // Distinct codes prevent relays from being received again as scan data.
        llMessageLinked(LINK_SET, number + 10, payload, request);
        if (number == SCAN_END)
        {
            gWaiting = FALSE;
            gReceiving = FALSE;
            llSetTimerEvent(0.0);
        }
    }

    timer()
    {
        llSetTimerEvent(0.0);
        if (gWaiting)
        {
            llMessageLinked(LINK_SET, DISPLAY_ABORT, "", gRequest);
            llOwnerSay("[HUD Refresh] No complete scan result within 10 seconds. Check MC_Scan.");
        }
        gWaiting = FALSE;
        gReceiving = FALSE;
    }
}
