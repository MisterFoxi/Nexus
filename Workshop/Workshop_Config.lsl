string VERSION = "Workshop_Config v0.9.1 (2026-11-02)";
// ROOT. Owns notecard parsing, bounded input mapping and read-only inspection hook.
// Never writes ws:core, acknowledges ingredient rows, evaluates or delivers products.
string gKind;
string gWorkshopType;
string gHudObject;
integer gSingle;
integer gKeep;
integer gDev;
integer gHover;
string gCookSound;
string gReadySound;
string gFailSound;
list gActions;
float gScale;
integer gMax;
string gHeatAction;
string gDurationAction;
float gDurationScale;
integer gDurationMax;
integer gInspectHandler;
integer gConfigReady;
integer gLine;
key gQuery;
string gNotecard;
key gRequest = NULL_KEY;
key gInspectTicket = NULL_KEY;
integer gInspectDeadline;
key gInspectSession = NULL_KEY;
key gInspectHUD = NULL_KEY;

string trim(string value) { return llStringTrim(value, STRING_TRIM); }
report(string text) { llMessageLinked(LINK_THIS, 970251, text, gRequest); }
sendTo(key hud, key session, key run, string verb, string body)
{
    llMessageLinked(LINK_THIS, 970211, "MCW|" + verb + "|" + (string)hud + "|"
        + (string)session + "|" + (string)run + "|" + body, run);
}
inputError(key request, string reason) { llMessageLinked(LINK_THIS, 970255, reason, request); }
string snapshot()
{
    return llList2Json(JSON_ARRAY, [gKind, gWorkshopType, gHudObject, gSingle, gKeep, gDev, gHover]);
}
string configNotecard()
{
    integer i;
    for (i = 0; i < llGetInventoryNumber(INVENTORY_NOTECARD); ++i)
    {
        string name = llGetInventoryName(INVENTORY_NOTECARD, i);
        if (llToLower(name) == "bench_config") return name;
    }
    return "";
}
loadConfig(key request)
{
    gRequest = request;
    gConfigReady = FALSE; gActions = []; gKind = ""; gWorkshopType = ""; gHudObject = "";
    gSingle = TRUE; gKeep = FALSE; gDev = TRUE; gScale = 1.0; gMax = 10;
    gHeatAction = ""; gDurationAction = ""; gDurationScale = 1.0; gDurationMax = 3600; gInspectHandler = FALSE;
    gHover = TRUE;
    gCookSound = "cook_sound"; gReadySound = "ready_sound"; gFailSound = "fail_sound";
    gNotecard = configNotecard();
    if (gNotecard == "") { llOwnerSay("[Workshop config] Missing bench_config."); report("ERROR"); return; }
    gLine = 0; gQuery = llGetNotecardLine(gNotecard, 0);
}
applyConfig(string data)
{
    integer hash = llSubStringIndex(data, "#");
    if (hash == 0) return;
    if (hash > 0) data = llGetSubString(data, 0, hash - 1);
    integer eq = llSubStringIndex(data, "=");
    if (eq < 1) return;
    string name = llToLower(trim(llGetSubString(data, 0, eq - 1)));
    string value = trim(llGetSubString(data, eq + 1, -1));
    if (name == "genre")
    {
        if (gWorkshopType != "" && value != "") gWorkshopType += ", ";
        gWorkshopType += value;
        if (gKind == "") gKind = trim(llList2String(llParseString2List(value, [","], []), 0));
    }
    else if (name == "hudkind") gKind = value;
    else if (name == "hudobject") gHudObject = value;
    else if (name == "singleingredient") gSingle = (integer)value != 0;
    else if (name == "allowkeep") gKeep = (integer)value != 0;
    else if (name == "dev") gDev = (integer)value != 0;
    else if (name == "showhover") gHover = (integer)value != 0;
    else if (name == "cooksound") gCookSound = value;
    else if (name == "readysound") gReadySound = value;
    else if (name == "failsound") gFailSound = value;
    else if (name == "action") gActions += trim(llList2String(llParseStringKeepNulls(value, [":"], []), 0));
    else if (name == "grindscale") gScale = (float)value;
    else if (name == "grindmax") gMax = (integer)value;
    else if (name == "heataction") gHeatAction = value;
    else if (name == "durationaction") gDurationAction = value;
    else if (name == "durationscale") gDurationScale = (float)value;
    else if (name == "durationmax") gDurationMax = (integer)value;
    else if (name == "inspecthandler") gInspectHandler = (integer)value != 0;
}

prepare(string wire, key run)
{
    list fields = llParseStringKeepNulls(wire, ["|"], []);
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    if (!gConfigReady || llList2String(sessionData, 4) != "BOUND"
        || llList2Key(fields, 3) != llList2Key(sessionData, 2) || run == NULL_KEY
        || llList2Key(fields, 4) != run || (llGetListLength(fields) != 8 && llGetListLength(fields) != 9))
    { inputError(run, "NO|Configuration%20or%20session%20unavailable"); return; }
    string choice = llList2String(fields, 5);
    string seconds = llList2String(fields, 6);
    integer heat = -1;
    if (llGetListLength(fields) == 9)
    {
        string value = llList2String(fields, 8);
        heat = (integer)value;
        if ((string)heat != value || heat < 0 || heat > 30)
        { inputError(run, "NO|Invalid%20heat%20input"); return; }
    }
    if (gHeatAction != "" && heat < 0)
    { inputError(run, "NO|Heat%20input%20required"); return; }
    if ((choice != "CONTAINER" && choice != "KEEP") || (choice == "KEEP" && !gKeep)
        || llJsonValueType(seconds, []) != JSON_NUMBER || (float)seconds < 0.0
        || llList2String(fields, 7) != "0")
    { inputError(run, "NO|Invalid%20choice%20or%20gesture"); return; }
    float elapsed = (float)seconds;
    string action = "";
    integer value = llRound(elapsed * gScale);
    if (value < 0) value = 0;
    if (value > gMax) value = gMax;
    integer i;
    for (i = 0; i < llGetListLength(gActions); ++i)
    {
        if (i) action += "^";
        action += llList2String(gActions, i) + "=" + (string)value;
    }
    if (gHeatAction != "")
    {
        if (action != "") action += "^";
        action += gHeatAction + "=" + (string)heat;
    }
    if (gDurationAction != "")
    {
        float duration = elapsed * gDurationScale;
        integer intensity = gDurationMax;
        // Bound before converting to integer, including very long preparations.
        if (duration < (float)gDurationMax) intensity = llRound(duration);
        if (intensity < 0) intensity = 0;
        if (action != "") action += "^";
        action += gDurationAction + "=" + (string)intensity;
    }
    llMessageLinked(LINK_THIS, 970255, llList2Json(JSON_ARRAY, [choice, elapsed, heat, action]), run);
}
inspect(string wire, key hud)
{
    list fields = llParseStringKeepNulls(wire, ["|"], []);
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    key session = llList2Key(sessionData, 2);
    key run = llList2Key(fields, 4);
    if (session == NULL_KEY || run == NULL_KEY || hud != llList2Key(sessionData, 1)
        || llList2Key(fields, 3) != session) return;
    if (llList2String(sessionData, 4) != "BOUND" || !gConfigReady || llGetListLength(fields) != 7) return;
    string seconds = llList2String(fields, 5);
    string heat = llList2String(fields, 6);
    if (llJsonValueType(seconds, []) != JSON_NUMBER || (float)seconds < 0.0
        || (string)((integer)heat) != heat || (integer)heat < -1 || (integer)heat > 30) return;
    if (!gInspectHandler)
    { sendTo(hud, session, run, "INSPECT_REPLY", "NOT_IMPLEMENTED"); return; }
    if (gInspectTicket != NULL_KEY)
    { sendTo(hud, session, run, "INSPECT_REPLY", "BUSY"); return; }
    gInspectTicket = run; gInspectDeadline = llGetUnixTime() + 10;
    llSetTimerEvent(5.0);
    gInspectSession = session; gInspectHUD = hud;
    // Future product consultation adapter. No evaluator, output or stock action here.
    llMessageLinked(LINK_THIS, 970240, "INPUTS|" + seconds + "|" + heat, run);
    return;
}
finishInspect(string result)
{
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    if (llList2String(sessionData, 4) == "BOUND" && gInspectSession == llList2Key(sessionData, 2)
        && gInspectHUD == llList2Key(sessionData, 1))
        sendTo(gInspectHUD, gInspectSession, gInspectTicket, "INSPECT_REPLY", llEscapeURL(result));
    gInspectTicket = NULL_KEY; gInspectDeadline = 0;
    llSetTimerEvent(0.0);
}
default
{
    state_entry()
    {
        llOwnerSay("[Nexus] " + VERSION);
        llMessageLinked(LINK_THIS, 970251, "RESET", NULL_KEY);
    }
    dataserver(key query, string data)
    {
        if (query != gQuery) return;
        if (data == EOF)
        {
            if (gKind == "cutting_board") gKeep = FALSE;
            gConfigReady = gKind != "" && gMax >= 0 && gScale >= 0.0
                && gDurationScale >= 0.0 && gDurationMax >= 0;
            if (gHeatAction != "" && llLinksetDataRead("tok:" + gHeatAction) == "") gConfigReady = FALSE;
            if (gDurationAction != "" && llLinksetDataRead("tok:" + gDurationAction) == "") gConfigReady = FALSE;
            if (gHeatAction != "" && gHeatAction == gDurationAction) gConfigReady = FALSE;
            if (gHeatAction != "" && gDurationAction != ""
                && llLinksetDataRead("tok:" + gHeatAction) == llLinksetDataRead("tok:" + gDurationAction))
                gConfigReady = FALSE;
            if (llListFindList(gActions, [gHeatAction]) != -1 || llListFindList(gActions, [gDurationAction]) != -1)
                gConfigReady = FALSE;
            integer axisIndex;
            for (axisIndex = 0; axisIndex < llGetListLength(gActions); ++axisIndex)
            {
                string axisId = llLinksetDataRead("tok:" + llList2String(gActions, axisIndex));
                if (axisId != "" && ((gHeatAction != "" && axisId == llLinksetDataRead("tok:" + gHeatAction))
                    || (gDurationAction != "" && axisId == llLinksetDataRead("tok:" + gDurationAction))))
                    gConfigReady = FALSE;
            }
            if (!gConfigReady) llOwnerSay("[Workshop] Invalid input configuration or missing compiled input axis.");
            if (!gConfigReady) { report("ERROR"); return; }
            string config = snapshot();
            integer result = llLinksetDataWrite("ws:config", config);
            if (result != 0 && result != 5) { gConfigReady = FALSE; report("ERROR"); return; }
            llOwnerSay("[Workshop] WS type (Genre) = " + gWorkshopType + " | HUDKind = " + gKind);
            report(config);
            return;
        }
        applyConfig(data); ++gLine; gQuery = llGetNotecardLine(gNotecard, gLine);
    }
    link_message(integer sender, integer number, string text, key request)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == 970290) { llOwnerSay("[Workshop config] Free: " + (string)llGetFreeMemory()); return; }
        if (number == 970250)
        {
            if (text == "LOAD" && request != NULL_KEY) loadConfig(request);
            else if (text == "STATUS" && request == gRequest && gConfigReady) report(snapshot());
            return;
        }
        if (number == 970252 && gConfigReady)
        {
            llMessageLinked(LINK_THIS, 970222, llList2Json(JSON_ARRAY,
                [(integer)text, gCookSound, gReadySound, gFailSound, gKeep, gWorkshopType, gKind]), NULL_KEY);
            return;
        }
        if (number == 970254 && request != NULL_KEY) { prepare(text, request); return; }
        if (number == 970256) { inspect(text, request); return; }
        if (number == 970241 && request == gInspectTicket && request != NULL_KEY) finishInspect(text);
    }
    timer() { if (gInspectTicket != NULL_KEY && llGetUnixTime() >= gInspectDeadline) finishInspect("UNAVAILABLE"); }
}
