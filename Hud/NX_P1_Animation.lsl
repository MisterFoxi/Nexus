#define SCRIPT_NAME    "NX_P1_Animation"
#define SCRIPT_VERSION "v0.2.3"
#include "nexus_header"

// ROOT. P1 playback + active-time clock + atlas/button/progress bring-up for the worn HUD.
// Migrated into the refonte (was v0.10.0): brought onto the convention, and the craft START no longer
// waits for the removed backend's CRAFT_STARTED ACK — start is authorized LOCALLY (the stock commitment
// will re-gate it when WS_Stock exists). Everything visual (textures, clock, PAUSE->P4, SNAPSHOT) is kept.
//
// One preparation: first START commits craft_started, CONT never consumes again.
// 918360 START/CONT/STOP: explicit preparation actions, unique non-null request id.
// ACTION1 is CUT/CONT. ACTION2 is PAUSE -> P4 while active, TAKE while paused.
// Explicit START on an already used preparation spoils it; CONT never restarts it.
string ATLAS = "atlas_chop";
string CUT_BUTTON = "p1_action1";
string SESSION_KEY = "mc:chop:session";
float TICK = 0.25;
integer gLoaded;
string gState = "STOPPED";
string gWanted = "STOPPED";
key gLoadTicket;
key gCommandTicket;
key gLastContinue;
key gLastDiscard;
key gLastAction;
integer gStarted;
integer gFinalizing;
integer gSpoiled;
float gElapsed;
float gPublishedElapsed;
// Optional independent heat intensity, 0..30 gameplay units; -1 = not selected.
// Frozen for the whole preparation. Existing one-input workshops retain old snapshots.
integer gHeat = -1;
integer gClockActive;
float gClockAt;
key gStartTicket = NULL_KEY;
float gStartAt;
integer gButtonsLoaded;
float gButtonsLoadAt;
integer gButtonsAttempts;
key gButtonsLoadTicket;
key gButtonsStateTicket;
string gButtonsVisual;
integer gProgressLoaded;
key gProgressLoadTicket;
key gProgressShowTicket;
string gVisualError;
float gProgressLoadAt;
integer gProgressAttempts;
key gObservationTicket = NULL_KEY;
integer gObservationOpen;
float gObservationDeadline;

clock()
{
    float now = llGetTime();
    if (gClockActive) gElapsed += now - gClockAt;
    gClockAt = now;
}

integer saveSession()
{
    integer result = llLinksetDataWrite(SESSION_KEY,
        llList2Json(JSON_ARRAY, [gStarted, gSpoiled, gElapsed, gHeat]));
    if (result == 0 || result == 5) return TRUE;
    gSpoiled = TRUE;
    gClockActive = FALSE;
    gWanted = "STOPPED";
    llOwnerSay("[Chop] Cannot save preparation. Locked; no restart allowed.");
    return FALSE;
}

restoreSession()
{
    string saved = llLinksetDataRead(SESSION_KEY);
    if (saved != "")
    {
        list values = llJson2List(saved);
        if (llJsonValueType(saved, []) == JSON_ARRAY && (llGetListLength(values) == 3 || llGetListLength(values) == 4)
            && llJsonValueType(saved, [0]) == JSON_NUMBER
            && llJsonValueType(saved, [1]) == JSON_NUMBER
            && llJsonValueType(saved, [2]) == JSON_NUMBER)
        {
            gStarted = llList2Integer(values, 0);
            gSpoiled = llList2Integer(values, 1);
            gElapsed = (float)llList2String(values, 2);
            if (llGetListLength(values) == 4)
            {
                string heat = llList2String(values, 3);
                gHeat = (integer)heat;
                if (llJsonValueType(saved, [3]) != JSON_NUMBER || (string)gHeat != heat
                    || gHeat < -1 || gHeat > 30) { gStarted = TRUE; gSpoiled = TRUE; gHeat = -1; }
            }
            if ((gStarted != 0 && gStarted != 1) || (gSpoiled != 0 && gSpoiled != 1)
                || gElapsed < 0.0 || (!gStarted && (gElapsed > 0.0 || gSpoiled))) { gStarted = TRUE; gSpoiled = TRUE; gElapsed = 0.0; }
        }
        else { gStarted = TRUE; gSpoiled = TRUE; }
    }
    // A previously consumed preparation with no timing checkpoint cannot be restarted.
    if (llLinksetDataRead("mc:simple:craft_started") == "1" && !gStarted)
    { gStarted = TRUE; gSpoiled = TRUE; }
    list workshop = llJson2List(llLinksetDataRead("mc:workshop:session"));
    string phase = llList2String(workshop, 5);
    gFinalizing = phase != "" && phase != "IDLE";
    gClockAt = llGetTime(); // On reset, remain suspended; offline time is never counted.
}

updateTimer()
{
    // Cosmetic activity only. The Workshop never advances the preparation clock.
    llMessageLinked(LINK_THIS, 918394, (string)gClockActive, NULL_KEY);
    if (gClockActive || gStartTicket != NULL_KEY
        || gObservationDeadline > 0.0
        || (!gButtonsLoaded && gButtonsAttempts > 0 && gButtonsAttempts < 4)
        || (!gProgressLoaded && gProgressAttempts > 0 && gProgressAttempts < 4)) llSetTimerEvent(TICK);
    else llSetTimerEvent(0.0);
}

loadButtons()
{
    gButtonsLoaded = FALSE;
    gButtonsVisual = "";
    ++gButtonsAttempts;
    gButtonsLoadAt = llGetTime();
    gButtonsLoadTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918340, "", gButtonsLoadTicket);
    updateTimer();
}

loadProgress()
{
    gProgressLoaded = FALSE;
    ++gProgressAttempts;
    gProgressLoadAt = llGetTime();
    gProgressLoadTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918350, "", gProgressLoadTicket);
    updateTimer();
}

showVisuals()
{
    if (gButtonsLoaded)
    {
        string visualState = "STOPPED";
        if (gStarted) visualState = "USED";
        if (gStarted && gClockActive && gWanted == "PLAYING") visualState = "PLAYING";
        if (gSpoiled) visualState = "SPOILED";
        if (gStartTicket != NULL_KEY) visualState = "STARTING";
        if (gFinalizing) visualState = "LOCKED";
        if (visualState != gButtonsVisual)
        {
            gButtonsVisual = visualState;
            gButtonsStateTicket = llGenerateKey();
            llMessageLinked(LINK_THIS, 918342, visualState, gButtonsStateTicket);
        }
    }
    if (gProgressLoaded)
    {
        string value = "IDLE";
        if (gStarted && !gSpoiled)
        {
            value = (string)gElapsed;
            gPublishedElapsed = (float)value;
        }
        if (gSpoiled) value = "SPOILED";
        gProgressShowTicket = llGenerateKey();
        llMessageLinked(LINK_THIS, 918351, value, gProgressShowTicket);
    }
}

loadAtlas()
{
    clock();
    gClockActive = FALSE;
    if (gStarted) saveSession();
    gLoaded = FALSE;
    gState = "STOPPED";
    gWanted = "STOPPED"; // A visual reset must never restart a used component.
    gCommandTicket = NULL_KEY;
    gLoadTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918330, ATLAS, gLoadTicket);
    updateTimer();
    showVisuals();
}

applyDesired()
{
    if (!gLoaded || gCommandTicket != NULL_KEY || gWanted == gState) return;
    integer command = 918332;
    if (gWanted == "PLAYING" && gStarted && !gSpoiled)
    {
        command = 918331; // Visual playback only; gElapsed is never reset here.
        if (gState == "PAUSED") command = 918335;
    }
    else if (gWanted == "PAUSED" && gState == "PLAYING") command = 918334;
    else if (gWanted == "PAUSED") { gWanted = gState; return; }
    gCommandTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, command, "", gCommandTicket);
}

suspend(integer keepPublishedProgress)
{
    // Explicit Stop uses the last time sent to the progression renderer.
    // Other suspensions, or a missing renderer, checkpoint the active clock.
    integer usePublished = keepPublishedProgress && gClockActive && gProgressLoaded && !gSpoiled;
    clock();
    if (usePublished) gElapsed = gPublishedElapsed;
    gClockActive = FALSE;
    if (gStarted) saveSession();
    gWanted = "STOPPED";
    if (gStarted && !gSpoiled) gWanted = "PAUSED";
    showVisuals();
    applyDesired();
    updateTimer();
}

spoil()
{
    clock();
    gStarted = TRUE;
    gSpoiled = TRUE;
    gClockActive = FALSE;
    gWanted = "STOPPED";
    gStartTicket = NULL_KEY;
    saveSession();
    updateTimer();
    showVisuals();
    applyDesired();
    llOwnerSay("[Chop] Spoiled: this preparation cannot be started again. Discard it.");
}

// Refonte: craft start authorized LOCALLY (no basket CRAFT_STARTED ACK). The stock commitment will
// re-gate this when WS_Stock exists; this replaces the old 918315/918317 handshake.
startPreparation()
{
    if (gFinalizing) return;
    if (gSpoiled || gStarted) { spoil(); return; }
    if (gStartTicket != NULL_KEY) return;
    if (!gLoaded) { llOwnerSay("[Chop] Wait for the animation atlas to load."); return; }
    if (gState != "STOPPED" || gCommandTicket != NULL_KEY)
    { llOwnerSay("[Chop] Wait for the previous visual stop."); return; }
    gWanted = "PLAYING";
    gStarted = TRUE;
    llLinksetDataWrite("mc:simple:craft_started", "1"); // this script now owns the used-preparation flag
    llMessageLinked(LINK_THIS, 918318, "CRAFTSTART", llGenerateKey()); // tell the bench the prep is now USED (keep it on a leave)
    gElapsed = 0.0;                                      // sole first-start initialization
    gClockAt = llGetTime();
    gClockActive = !gSpoiled && !gFinalizing;
    if (!saveSession()) { showVisuals(); updateTimer(); return; }
    showVisuals();
    applyDesired();
    updateTimer();
}

continuePreparation()
{
    if (!gStarted || gSpoiled || gFinalizing) return;
    clock(); // Rebase while paused so none of the pause duration enters active time.
    gClockActive = TRUE;
    gWanted = "PLAYING";
    if (!saveSession()) { showVisuals(); applyDesired(); updateTimer(); return; }
    showVisuals();
    if (gLoaded) applyDesired();
    else if (gLoadTicket == NULL_KEY) loadAtlas();
    updateTimer();
}

heatInput(string command, key ticket)
{
    list parts = llParseStringKeepNulls(command, ["|"], []);
    string verb = llList2String(parts, 0);
    if (verb == "GET")
    { llMessageLinked(LINK_THIS, 918396, "HEAT|" + (string)gHeat, ticket); return; }
    if (gStarted || gStartTicket != NULL_KEY || gFinalizing || gSpoiled
        || llLinksetDataRead("mc:simple:craft_started") == "1")
    { llMessageLinked(LINK_THIS, 918396, "ERROR|Preparation locked", ticket); return; }
    if (verb != "SET" || llGetListLength(parts) != 2) return;
    string value = llList2String(parts, 1);
    integer heat = (integer)value;
    if ((string)heat != value || heat < 0 || heat > 30)
    { llMessageLinked(LINK_THIS, 918396, "ERROR|Heat must be an integer from 0 to 30", ticket); return; }
    gHeat = heat;
    if (saveSession()) llMessageLinked(LINK_THIS, 918396, "HEAT|" + (string)gHeat, ticket);
}

button(string name)
{
    if (name == "p1_heat_plus" || name == "p1_heat_minus")
    {
        integer heat = gHeat;
        if (heat < 0) heat = 0;
        if (name == "p1_heat_plus" && heat < 30) ++heat;
        else if (name == "p1_heat_minus" && heat > 0) heat -= 1;
        heatInput("SET|" + (string)heat, llGenerateKey());
        return;
    }
    if (name == "p1_test")
    { llMessageLinked(LINK_THIS, 918397, "TEST", llGenerateKey()); return; }
    if (name == CUT_BUTTON)
    {
        if (gObservationOpen || gClockActive || gStartTicket != NULL_KEY) return;
        if (gStarted) continuePreparation();
        else startPreparation();
        return;
    }
    if (name == "p1_action2")
    {
        if (!gStarted || gSpoiled || gFinalizing || gStartTicket != NULL_KEY || gObservationOpen) return;
        if (gClockActive)
        {
            // Persist the actual pause time before opening the read-only observation.
            suspend(FALSE);
            if (gSpoiled) return;
            gObservationTicket = llGenerateKey();
            gObservationOpen = TRUE;
            gObservationDeadline = llGetTime() + 5.0;
            llMessageLinked(LINK_THIS, 918411, "OPEN", gObservationTicket);
            updateTimer();
        }
        else llMessageLinked(LINK_THIS, 918370, "CONTAINER", llGenerateKey());
        return;
    }
    if (name == "p1_later") { suspend(FALSE); return; }
    if (name == "p1_action3")
    {
        // DISCARD: close the preparation. The started flag tells the bench whether to RETURN the picked
        // units (cut not begun) or CONSUME them (cut begun, no product). The bench round-trip and the
        // local page reset (918317 DISCARD_DONE) are driven by NX_HudFace. Available in every P1 state.
        llMessageLinked(LINK_THIS, 918315, "DISCARD|" + (string)gStarted, llGenerateKey());
    }
}

visualStatus(integer number, string text, key ticket)
{
    integer buttons = number == 918343;
    if (text == "READY")
    {
        if (buttons) { gButtonsAttempts = 0; loadButtons(); }
        else { gProgressAttempts = 0; loadProgress(); }
        return;
    }
    if (text == "LOADED")
    {
        gVisualError = "";
        if (buttons && ticket == gButtonsLoadTicket)
        { gButtonsLoadTicket = NULL_KEY; gButtonsLoaded = TRUE; gButtonsAttempts = 0; showVisuals(); updateTimer(); }
        else if (!buttons && ticket == gProgressLoadTicket)
        { gProgressLoadTicket = NULL_KEY; gProgressLoaded = TRUE; gProgressAttempts = 0; showVisuals(); updateTimer(); }
        return;
    }
    if (text == "UNLOADED")
    {
        if (buttons) { gButtonsLoaded = FALSE; gButtonsLoadTicket = NULL_KEY; gButtonsAttempts = 0; updateTimer(); }
        else { gProgressLoaded = FALSE; gProgressLoadTicket = NULL_KEY; }
        return;
    }
    if (llSubStringIndex(text, "ERROR:") == 0)
    {
        if (ticket == gButtonsLoadTicket)
        { gButtonsLoadTicket = NULL_KEY; gButtonsLoaded = FALSE; gButtonsAttempts = 4; updateTimer(); }
        else if (ticket == gProgressLoadTicket) { gProgressLoadTicket = NULL_KEY; gProgressLoaded = FALSE; gProgressAttempts = 4; updateTimer(); }
        else if (ticket != gButtonsStateTicket && ticket != gProgressShowTicket) return;
        if (text != gVisualError) llOwnerSay("[Chop visual] " + text);
        gVisualError = text;
    }
}

default
{
    state_entry() { nexusBoot(); restoreSession(); loadAtlas(); loadButtons(); loadProgress(); }
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner())
                button(llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)));
    }
    link_message(integer sender, integer number, string text, key ticket)
    {
        if (number == NEXUS_MEM_REPORT) { nexusMemReport(); return; }
        if (sender != llGetLinkNumber()) return;
        if (number == 918412 && text == "RESET" && ticket == NULL_KEY)
        {
            gObservationOpen = FALSE; gObservationTicket = NULL_KEY; gObservationDeadline = 0.0;
            updateTimer(); return;
        }
        if (number == 918412 && ticket == gObservationTicket && ticket != NULL_KEY)
        {
            if (text == "OPENED") gObservationDeadline = 0.0;
            else if (text == "CLOSED" || text == "UNAVAILABLE")
            { gObservationOpen = FALSE; gObservationTicket = NULL_KEY; gObservationDeadline = 0.0; }
            updateTimer(); return;
        }
        if (number == 918395 && ticket != NULL_KEY) { heatInput(text, ticket); return; }
        if (number == 918372 && ticket != NULL_KEY)
        {
            if (text == "INSPECT")
            {
                if (!gStarted || gSpoiled || gFinalizing || gStartTicket != NULL_KEY)
                { llMessageLinked(LINK_THIS, 918399, "NO", ticket); return; }
                // Read the live clock without freezing, submitting, or advancing stock.
                clock();
                llMessageLinked(LINK_THIS, 918399, "OK|" + (string)gElapsed + "|" + (string)gHeat, ticket);
                return;
            }
            list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
            if (llList2Key(session, 6) != ticket) return;
            if (text == "UNFREEZE") { gFinalizing = FALSE; return; }
            if (text != "SNAPSHOT") return;
            if (!gStarted || gStartTicket != NULL_KEY)
            { llMessageLinked(LINK_THIS, 918373, "NO|0|0", ticket); return; }
            clock(); gClockActive = FALSE; gFinalizing = TRUE;
            gWanted = "PAUSED";
            applyDesired();
            if (!saveSession()) return;
            showVisuals(); updateTimer();
            string snapshot = "OK|" + (string)gElapsed + "|" + (string)gSpoiled;
            if (gHeat >= 0) snapshot += "|" + (string)gHeat;
            llMessageLinked(LINK_THIS, 918373, snapshot, ticket);
            return;
        }
        if (number == 918371)
        {
            gFinalizing = text != "" && text != "IDLE";
            if (gFinalizing) { clock(); gClockActive = FALSE; suspend(FALSE); }
            showVisuals();
            return;
        }
        if (number == 918396)
        {
            llOwnerSay("[Preparation inputs] " + text);
            return;
        }
        if (number == 918343 || number == 918353) { visualStatus(number, text, ticket); return; }
        if (number == 918360 && ticket != NULL_KEY && ticket != gLastAction)
        {
            gLastAction = ticket;
            if (text == "START") startPreparation();
            else if (text == "CONT") continuePreparation();
            else if (text == "STOP" || text == "PAUSE") suspend(TRUE);
            return;
        }
        if (number == 918310 && text == "CONTINUE" && ticket != NULL_KEY && ticket != gLastContinue)
        { gLastContinue = ticket; suspend(FALSE); return; } // Navigation is not a new preparation.
        if (number == 918317 && (text == "DISCARD_DONE" || text == "CRAFT_DONE") && ticket != NULL_KEY && ticket != gLastDiscard)
        {
            gLastDiscard = ticket;
            // Refonte: this script owns closure now; release the used-component latch and clear the flag.
            clock();
            gClockActive = FALSE;
            gStarted = FALSE;
            gFinalizing = FALSE;
            gSpoiled = FALSE;
            gElapsed = 0.0;
            gHeat = -1;
            gStartTicket = NULL_KEY;
            gObservationTicket = NULL_KEY; gObservationOpen = FALSE; gObservationDeadline = 0.0;
            gWanted = "STOPPED";
            llLinksetDataDelete("mc:simple:craft_started");
            saveSession();
            showVisuals();
            applyDesired();
            updateTimer();
            return;
        }
        if (number != 918333) return;
        if (text == "READY") { loadAtlas(); return; }
        if (text == "UNLOADED")
        {
            clock(); gClockActive = FALSE;
            if (gStarted) saveSession();
            gLoaded = FALSE; gState = "STOPPED"; gWanted = "STOPPED";
            gLoadTicket = NULL_KEY; gCommandTicket = NULL_KEY;
            showVisuals(); updateTimer(); return;
        }
        if (text == "LOADED" && ticket == gLoadTicket)
        {
            gLoadTicket = NULL_KEY; gLoaded = TRUE; gState = "STOPPED";
            showVisuals(); applyDesired(); return;
        }
        if (text == "PLAYING" || text == "PAUSED" || text == "REST")
        {
            clock();
            gState = text;
            if (text == "REST") gState = "STOPPED";
            // Visual state updates never start or resume the authoritative craft clock.
            integer ownCommand = ticket == gCommandTicket && ticket != NULL_KEY;
            if (ownCommand) gCommandTicket = NULL_KEY;
            else if (gCommandTicket == NULL_KEY) gWanted = gState;
            if (gStarted) saveSession();
            updateTimer(); showVisuals();
            if (ownCommand || gSpoiled || !gStarted) applyDesired();
            return;
        }
        if (llSubStringIndex(text, "ERROR:") == 0 && (ticket == gLoadTicket || ticket == gCommandTicket))
        {
            clock();
            if (ticket == gLoadTicket) { gLoadTicket = NULL_KEY; gLoaded = FALSE; }
            gCommandTicket = NULL_KEY; gWanted = gState;
            llOwnerSay("[Chop animation] " + text);
        }
    }
    timer()
    {
        clock();
        if (gObservationDeadline > 0.0 && llGetTime() >= gObservationDeadline)
        {
            gObservationOpen = FALSE; gObservationTicket = NULL_KEY; gObservationDeadline = 0.0;
            llOwnerSay("[Chop] Observation page did not respond. Preparation remains paused; CONT or TAKE is available.");
        }
        if (!gButtonsLoaded && gButtonsAttempts > 0 && gButtonsAttempts < 4
            && llGetTime() - gButtonsLoadAt >= 2.0)
        {
            // Retry only the local visual LOAD, never START, a source operation or a craft.
            if (gButtonsAttempts < 3) loadButtons();
            else
            {
                gButtonsAttempts = 4; gButtonsLoadTicket = NULL_KEY;
                llOwnerSay("[Chop buttons] No button renderer response. Install/run NX_Playback_Buttons in ROOT with NX_P1_Animation.");
            }
        }
        if (!gProgressLoaded && gProgressAttempts > 0 && gProgressAttempts < 4
            && llGetTime() - gProgressLoadAt >= 2.0)
        {
            if (gProgressAttempts < 3) loadProgress();
            else
            {
                gProgressAttempts = 4;
                gProgressLoadTicket = NULL_KEY;
                llOwnerSay("[Chop progress] No renderer response. Install/run NX_Chop_Progress in ROOT with NX_P1_Animation.");
            }
        }
        if (gClockActive)
        {
            if (!saveSession()) applyDesired();
            showVisuals();
        }
        updateTimer();
    }
    changed(integer change)
    {
        if (change & CHANGED_OWNER) { llResetScript(); return; }
        if (change & CHANGED_INVENTORY)
        {
            if (!gButtonsLoaded && gButtonsLoadTicket == NULL_KEY) { gButtonsAttempts = 0; loadButtons(); }
            if (!gProgressLoaded && gProgressLoadTicket == NULL_KEY) { gProgressAttempts = 0; loadProgress(); }
            if (!gLoaded && gLoadTicket == NULL_KEY) loadAtlas();
        }
    }
    on_rez(integer parameter)
    {
        // Rez/attach-from-inventory = fresh wear -> RAZ (clear the persisted cut before reset). on_rez does
        // NOT fire on a sim restart, so the sim-restart persistence of mc:chop:session is preserved.
        llLinksetDataDelete(SESSION_KEY);
        llLinksetDataDelete("mc:simple:craft_started");
        llResetScript();
    }
    attach(key id)
    {
        // (Re)worn = full RAZ too (whichever of on_rez/attach fires on this viewer). The bench is the craft
        // authority and re-drives the right page on re-bind; llResetScript alone would restore the stale cut.
        if(id != NULL_KEY)
        {
            llLinksetDataDelete(SESSION_KEY);
            llLinksetDataDelete("mc:simple:craft_started");
            llResetScript();
        }
    }
}
