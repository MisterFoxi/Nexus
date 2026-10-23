// ROOT. One preparation: first START commits craft_started, CONT never consumes again.
// 918360 START/CONT/STOP: explicit preparation actions, unique non-null request id.
// START on an already used preparation spoils it. Normal P1_CUT becomes CONT.
string ATLAS = "atlas_chop";
string CUT_BUTTON = "p1_cut";
string STOP_BUTTON = "p1_stop";
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
integer gSpoiled;
float gElapsed;
integer gClockActive;
float gClockAt;
key gStartTicket = NULL_KEY;
float gStartAt;
integer gButtonsLoaded;
key gButtonsLoadTicket;
key gButtonsStateTicket;
integer gProgressLoaded;
key gProgressLoadTicket;
key gProgressShowTicket;
string gVisualError;
float gProgressLoadAt;
integer gProgressAttempts;

clock()
{
    float now = llGetTime();
    if (gClockActive) gElapsed += now - gClockAt;
    gClockAt = now;
}

integer saveSession()
{
    integer result = llLinksetDataWrite(SESSION_KEY,
        llList2Json(JSON_ARRAY, [gStarted, gSpoiled, gElapsed]));
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
        if (llJsonValueType(saved, []) == JSON_ARRAY && llGetListLength(values) == 3
            && llJsonValueType(saved, [0]) == JSON_NUMBER
            && llJsonValueType(saved, [1]) == JSON_NUMBER
            && llJsonValueType(saved, [2]) == JSON_NUMBER)
        {
            gStarted = llList2Integer(values, 0);
            gSpoiled = llList2Integer(values, 1);
            gElapsed = (float)llList2String(values, 2);
            if ((gStarted != 0 && gStarted != 1) || (gSpoiled != 0 && gSpoiled != 1)
                || gElapsed < 0.0 || (!gStarted && (gElapsed > 0.0 || gSpoiled))) { gStarted = TRUE; gSpoiled = TRUE; gElapsed = 0.0; }
        }
        else { gStarted = TRUE; gSpoiled = TRUE; }
    }
    // A previously consumed preparation with no timing checkpoint cannot be restarted.
    if (llLinksetDataRead("mc:simple:craft_started") == "1" && !gStarted)
    { gStarted = TRUE; gSpoiled = TRUE; }
    gClockAt = llGetTime(); // On reset, remain suspended; offline time is never counted.
}

updateTimer()
{
    if (gClockActive || gStartTicket != NULL_KEY
        || (!gProgressLoaded && gProgressAttempts > 0 && gProgressAttempts < 4)) llSetTimerEvent(TICK);
    else llSetTimerEvent(0.0);
}

loadButtons()
{
    gButtonsLoaded = FALSE;
    gButtonsLoadTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 918340, "", gButtonsLoadTicket);
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
        if (gStarted && gState == "PLAYING") visualState = "PLAYING";
        if (gSpoiled) visualState = "SPOILED";
        gButtonsStateTicket = llGenerateKey();
        llMessageLinked(LINK_THIS, 918342, visualState, gButtonsStateTicket);
    }
    if (gProgressLoaded)
    {
        string value = "IDLE";
        if (gStarted) value = (string)gElapsed;
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

suspend()
{
    // STOP is resumable for the preparation, even when pressed repeatedly.
    gWanted = "STOPPED";
    if (gStarted && !gSpoiled) gWanted = "PAUSED";
    applyDesired();
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

startPreparation()
{
    if (gSpoiled || gStarted || llLinksetDataRead("mc:simple:craft_started") == "1")
    { spoil(); return; }
    if (gStartTicket != NULL_KEY) return; // Same in-flight first start is idempotent.
    if (!gLoaded) { llOwnerSay("[Chop] Wait for the animation atlas to load."); return; }
    if (gState != "STOPPED" || gCommandTicket != NULL_KEY)
    { llOwnerSay("[Chop] Wait for the previous visual stop."); return; }
    gWanted = "PLAYING";
    gStartTicket = llGenerateKey();
    gStartAt = llGetTime();
    llMessageLinked(LINK_THIS, 918315, "CRAFT_STARTED", gStartTicket);
    updateTimer(); // No animation or active-time clock before the persisted basket ACK.
}

continuePreparation()
{
    if (!gStarted || gSpoiled) return;
    gWanted = "PLAYING";
    if (gLoaded) applyDesired();
    else if (gLoadTicket == NULL_KEY) loadAtlas();
}

button(string name)
{
    if (name == CUT_BUTTON)
    {
        if (gStarted) continuePreparation();
        else startPreparation();
        return;
    }
    if (name == STOP_BUTTON || name == "p1_later" || name == "p1_discard") suspend();
}

visualStatus(integer number, string text, key ticket)
{
    integer buttons = number == 918343;
    if (text == "READY")
    {
        if (buttons) loadButtons();
        else { gProgressAttempts = 0; loadProgress(); }
        return;
    }
    if (text == "LOADED")
    {
        gVisualError = "";
        if (buttons && ticket == gButtonsLoadTicket)
        { gButtonsLoadTicket = NULL_KEY; gButtonsLoaded = TRUE; showVisuals(); }
        else if (!buttons && ticket == gProgressLoadTicket)
        { gProgressLoadTicket = NULL_KEY; gProgressLoaded = TRUE; gProgressAttempts = 0; showVisuals(); updateTimer(); }
        return;
    }
    if (text == "UNLOADED")
    {
        if (buttons) { gButtonsLoaded = FALSE; gButtonsLoadTicket = NULL_KEY; }
        else { gProgressLoaded = FALSE; gProgressLoadTicket = NULL_KEY; }
        return;
    }
    if (llSubStringIndex(text, "ERROR:") == 0)
    {
        if (ticket == gButtonsLoadTicket) { gButtonsLoadTicket = NULL_KEY; gButtonsLoaded = FALSE; }
        else if (ticket == gProgressLoadTicket) { gProgressLoadTicket = NULL_KEY; gProgressLoaded = FALSE; gProgressAttempts = 4; updateTimer(); }
        else if (ticket != gButtonsStateTicket && ticket != gProgressShowTicket) return;
        if (text != gVisualError) llOwnerSay("[Chop visual] " + text);
        gVisualError = text;
    }
}

default
{
    state_entry() { restoreSession(); loadAtlas(); loadButtons(); loadProgress(); }
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
        if (number == 918343 || number == 918353) { visualStatus(number, text, ticket); return; }
        if (number == 918360 && ticket != NULL_KEY && ticket != gLastAction)
        {
            gLastAction = ticket;
            if (text == "START") startPreparation();
            else if (text == "CONT") continuePreparation();
            else if (text == "STOP" || text == "PAUSE") suspend();
            return;
        }
        if (number == 918310 && text == "CONTINUE" && ticket != NULL_KEY && ticket != gLastContinue)
        { gLastContinue = ticket; suspend(); return; } // Navigation is not a new preparation.
        if (number == 918317 && text == "CRAFT_STARTED" && ticket == gStartTicket && ticket != NULL_KEY)
        {
            gStartTicket = NULL_KEY;
            gStarted = TRUE;
            gElapsed = 0.0; // The sole first-start initialization for this preparation.
            gClockAt = llGetTime();
            if (!saveSession()) { showVisuals(); updateTimer(); return; }
            showVisuals();
            applyDesired();
            updateTimer();
            return;
        }
        if (number == 918317 && text == "DISCARD_DONE" && ticket != NULL_KEY && ticket != gLastDiscard)
        {
            if (llLinksetDataRead("mc:simple:craft_started") == "1") return;
            gLastDiscard = ticket;
            // Only confirmed basket disposal releases the used-component latch.
            clock();
            gClockActive = FALSE;
            gStarted = FALSE;
            gSpoiled = FALSE;
            gElapsed = 0.0;
            gStartTicket = NULL_KEY;
            gWanted = "STOPPED";
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
            gClockActive = gStarted && !gSpoiled && gState == "PLAYING";
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
        if (!gProgressLoaded && gProgressAttempts > 0 && gProgressAttempts < 4
            && llGetTime() - gProgressLoadAt >= 2.0)
        {
            if (gProgressAttempts < 3) loadProgress();
            else
            {
                gProgressAttempts = 4;
                gProgressLoadTicket = NULL_KEY;
                llOwnerSay("[Chop progress] No renderer response. Install/run MC_Chop_Progress in ROOT with MC_P1_Animation.");
            }
        }
        if (gClockActive)
        {
            if (!saveSession()) applyDesired();
            showVisuals();
        }
        if (gStartTicket != NULL_KEY && llGetTime() - gStartAt >= 5.0)
        {
            gStartTicket = NULL_KEY;
            gWanted = "STOPPED";
            if (llLinksetDataRead("mc:simple:craft_started") == "1") spoil();
            else llOwnerSay("[Chop] Start not confirmed by the basket. Nothing started.");
        }
        updateTimer();
    }
    changed(integer change)
    {
        if (change & CHANGED_OWNER) { llResetScript(); return; }
        if (change & CHANGED_INVENTORY)
        {
            if (!gButtonsLoaded && gButtonsLoadTicket == NULL_KEY) loadButtons();
            if (!gProgressLoaded && gProgressLoadTicket == NULL_KEY) { gProgressAttempts = 0; loadProgress(); }
            if (!gLoaded && gLoadTicket == NULL_KEY) loadAtlas();
        }
    }
    on_rez(integer parameter) { llResetScript(); }
}
