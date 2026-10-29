// Workshop v0.7 - small session/configuration coordinator.
// Same ROOT: Workshop_HUD, Workshop_Eval, Workshop_Output, Workshop_Storage.
// No ingredient, container, output-DNA or kept-source collection in this script.
// Origin session closes ingredients; collector session only controls the finished product.
key gCollectorUser = NULL_KEY;
key gCollectorHUD = NULL_KEY;
key gCollectorSession = NULL_KEY;
key gUser = NULL_KEY;
key gHUD = NULL_KEY;
key gSession = NULL_KEY;
key gRun = NULL_KEY;
string gPhase = "FREE";
string gLastResult;
string gChoice;
float gSeconds;
string gKind;
string gHudObject;
integer gSingle = 1;
integer gKeep;
integer gDev = TRUE;
integer gCookTime = 20;
integer gHover = TRUE;
string gCookSound = "cook_sound";
string gReadySound = "ready_sound";
string gFailSound = "fail_sound";
list gActions;
float gScale = 1.0;
integer gMax = 10;
string gAction;
integer gReady;
integer gConfigReady;
integer gConfigPending;
integer gLine;
key gQuery;
string gNotecard;
integer gFault;
integer gDeadline;
integer gSessionMenu;
integer gSessionListen;
key gMenuSession = NULL_KEY;

string trim(string value) { return llStringTrim(value, STRING_TRIM); }
integer validKey(key value) { if (value) return TRUE; return FALSE; }
integer write(string name, string value)
{
    integer result = llLinksetDataWrite(name, value);
    if (result == 0 || result == 5) return TRUE;
    gFault = TRUE; llOwnerSay("[Workshop] Storage failure. Session retained and locked."); return FALSE;
}
integer save()
{
    return write("ws:core", llList2Json(JSON_ARRAY, [gUser, gHUD, gSession, gRun,
        gPhase, gLastResult, gChoice, gSeconds, gKind, gSingle, gKeep, !gDev, gAction]));
}
sendTo(key hud, key session, key run, string verb, string body)
{
    string wire = "MCW|" + verb + "|" + (string)hud + "|" + (string)session + "|" + (string)run;
    if (body != "") wire += "|" + body;
    llMessageLinked(LINK_THIS, 970211, wire, run);
}
reply(string verb, string body) { sendTo(gHUD, gSession, gRun, verb, body); }
offer()
{
    sendTo(gUser, gSession, NULL_KEY, "OFFER", gKind + "|" + (string)gSingle
        + "|" + (string)gKeep + "|" + (string)(!gDev));
}
integer saveCollector()
{
    return write("ws:collector", llList2Json(JSON_ARRAY, [gRun, gCollectorUser, gCollectorHUD, gCollectorSession]));
}
integer productPending()
{
    list output = llJson2List(llLinksetDataRead("ws:output"));
    return llList2Key(output, 0) == gRun && llList2String(output, 3) == "WAIT_CONTAINER"
        && llList2Integer(output, 5) > 0;
}
outputState()
{
    if ((gCollectorHUD == NULL_KEY)) return;
    list output = llJson2List(llLinksetDataRead("ws:output"));
    list dna = llParseStringKeepNulls(llList2String(output, 4), ["|"], []);
    sendTo(gCollectorHUD, gCollectorSession, gRun, "OUTPUT_STATE",
        llList2String(output, 3) + "|" + (string)llList2Integer(output, 5) + "|" + llEscapeURL(llGetSubString(llList2String(dna, 2), 0, 63)));
}
collectorOffer()
{
    sendTo(gCollectorUser, gCollectorSession, NULL_KEY, "OFFER", gKind + "|" + (string)gSingle
        + "|" + (string)gKeep + "|" + (string)(!gDev) + "|OUTPUT");
}
provision(key player)
{
    if (gDev) return;
    if (player == llGetOwner())
        llRezObject(gHudObject, llGetPos() + <0.0, 0.0, 1.0>, ZERO_VECTOR, ZERO_ROTATION, 0);
    else
    {
        // A rezzed inventory object keeps the station owner's ownership.
        // Give the dedicated HUD so its stock transactions belong to the actual player.
        llGiveInventory(player, gHudObject);
        llRegionSayTo(player, 0, "Wear the workshop HUD you just received. Association will follow automatically.");
    }
}
finishProduct()
{
    // Both independently persisted facts are required before another preparation.
    list output = llJson2List(llLinksetDataRead("ws:output"));
    if (llList2Key(output, 0) != gRun || llList2String(output, 3) != "DONE"
        || llLinksetDataRead("ws:closed") != (string)gRun) return;
    key originHUD = gHUD; key originSession = gSession;
    if (gCollectorHUD)
    { gUser = gCollectorUser; gHUD = gCollectorHUD; gSession = gCollectorSession; }
    gPhase = "BOUND";
    if (!save()) return;
    if (originHUD != gHUD)
    {
        if (!write("ws:released", llList2Json(JSON_ARRAY, [originHUD, originSession, gRun]))) return;
        sendTo(originHUD, originSession, gRun, "RELEASED", "");
    }
    sendTo(gHUD, gSession, gRun, "OUTPUT_CLOSED", "");
    llMessageLinked(LINK_THIS, 970213, "CLEAN", gRun);
}
integer collectorControl(key source, list fields)
{
    if (llList2Key(fields, 3) != gCollectorSession || (gCollectorSession == NULL_KEY)) return FALSE;
    string verb = llList2String(fields, 1);
    key run = llList2Key(fields, 4);
    if (verb == "ACCEPT" && run == NULL_KEY && llGetListLength(fields) == 7
        && llGetOwnerKey(source) == gCollectorUser && llList2Key(fields, 5) == gCollectorUser
        && llList2String(fields, 6) == gKind && productPending())
    {
        if ((gCollectorHUD != NULL_KEY) && source != gCollectorHUD) return TRUE;
        gCollectorHUD = source;
        if (saveCollector())
        { sendTo(source, gCollectorSession, NULL_KEY, "BOUND", ""); outputState(); }
        return TRUE;
    }
    if (source != gCollectorHUD || run != gRun) return FALSE;
    if (verb == "OUTPUT_STATUS") { outputState(); finishProduct(); return TRUE; }
    if ((verb == "TRANSFER" || verb == "OUTPUT_DISCARD") && llGetListLength(fields) == 7
        && llList2Key(fields, 5) != NULL_KEY)
    {
        string command = "TRANSFER";
        if (verb == "OUTPUT_DISCARD") command = "DISCARD";
        llMessageLinked(LINK_THIS, 970220, command + "|" + llList2String(fields, 5)
            + "|" + llList2String(fields, 6) + "|" + (string)gCollectorUser, gRun);
        return TRUE;
    }
    return FALSE;
}
failure(string reason)
{
    gPhase = "BOUND"; gLastResult = "NO|" + llEscapeURL(reason);
    if (save()) reply("RESULT", gLastResult);
    llMessageLinked(LINK_THIS, 970220, "FAIL_SOUND", gRun);
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
loadConfig()
{
    gConfigReady = FALSE; gActions = []; gKind = ""; gHudObject = "";
    gSingle = TRUE; gKeep = FALSE; gDev = TRUE; gScale = 1.0; gMax = 10;
    gCookTime = 20; gHover = TRUE;
    gCookSound = "cook_sound"; gReadySound = "ready_sound"; gFailSound = "fail_sound";
    gNotecard = configNotecard();
    if (gNotecard == "") { llOwnerSay("[Workshop] Missing bench_config."); return; }
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
    if (name == "genre" && gKind == "") gKind = trim(llList2String(llParseString2List(value, [","], []), 0));
    else if (name == "hudkind") gKind = value;
    else if (name == "hudobject") gHudObject = value;
    else if (name == "singleingredient") gSingle = (integer)value != 0;
    else if (name == "allowkeep") gKeep = (integer)value != 0;
    else if (name == "dev") gDev = (integer)value != 0;
    else if (name == "cooktime")
    {
        integer seconds = (integer)value;
        string suffix = llToLower(llGetSubString(value, -1, -1));
        if (suffix == "m") seconds *= 60;
        else if (suffix == "h") seconds *= 3600;
        else if (suffix == "d") seconds *= 86400;
        if (seconds > 0) gCookTime = seconds;
    }
    else if (name == "showhover") gHover = (integer)value != 0;
    else if (name == "cooksound") gCookSound = value;
    else if (name == "readysound") gReadySound = value;
    else if (name == "failsound") gFailSound = value;
    else if (name == "action") gActions += trim(llList2String(llParseStringKeepNulls(value, [":"], []), 0));
    else if (name == "grindscale") gScale = (float)value;
    else if (name == "grindmax") gMax = (integer)value;
}
configureOutput()
{
    llMessageLinked(LINK_THIS, 970222, llList2Json(JSON_ARRAY,
        [gCookTime, gHover, gCookSound, gReadySound, gFailSound, gKeep]), NULL_KEY);
}
sessionMenu()
{
    if (gSessionListen) llListenRemove(gSessionListen);
    gSessionMenu = -3000000 - (integer)llFrand(900000.0);
    gMenuSession = gSession;
    gSessionListen = llListen(gSessionMenu, "", gUser, "");
    string hover = "Text: OFF";
    if (gHover) hover = "Text: ON";
    llDialog(gUser, "Resume, exit through the HUD stock cleanup, or toggle nearby component text.",
        ["Resume", "Exit", hover], gSessionMenu);
}
resume()
{
    if (gFault || !gConfigReady || gReady != 15) return;
    configureOutput();
    if (gPhase == "OUTPUT") llMessageLinked(LINK_THIS, 970220, "STATUS", gRun);
    if (gPhase == "RECEIVING" || gPhase == "BUILDING") llMessageLinked(LINK_THIS, 970213, "STATUS", gRun);
    else if (gPhase == "EVALUATING") llMessageLinked(LINK_THIS, 970202, gAction, gRun);
    else if (gPhase == "OUTPUT") llMessageLinked(LINK_THIS, 970220,
        "START|" + gChoice + "|" + (string)gUser, gRun);
    else if (gPhase == "SETTLING") { reply("RESULT", "OK"); outputState(); }
    else if (gPhase == "PRODUCT") { outputState(); finishProduct(); }
}
receiveControl(key source, string wire)
{
    list fields = llParseStringKeepNulls(wire, ["|"], []);
    if (llGetListLength(fields) < 5 || llList2Key(fields, 2) != llGetKey()) return;
    string verb = llList2String(fields, 1);
    key session = llList2Key(fields, 3);
    key run = llList2Key(fields, 4);
    if (verb == "EXIT" || verb == "CLOSED" || verb == "OUTPUT_STATUS")
    {
        list released = llJson2List(llLinksetDataRead("ws:released"));
        if (llList2Key(released, 0) == source && llList2Key(released, 1) == session
            && llList2Key(released, 2) == run)
        { sendTo(source, session, run, "RELEASED", ""); return; }
    }
    if (collectorControl(source, fields)) return;
    if (session != gSession || !validKey(session)) return;
    if (verb == "ACCEPT")
    {
        if (llGetListLength(fields) != 7 || run != NULL_KEY || llGetOwnerKey(source) != gUser
            || llList2Key(fields, 5) != gUser || llList2String(fields, 6) != gKind) return;
        if (gPhase == "OFFERED")
        { gHUD = source; gPhase = "BOUND"; if (!save()) return; }
        if (source == gHUD) sendTo(gHUD, gSession, NULL_KEY, "BOUND", "");
        return;
    }
    if (source != gHUD || !validKey(run)) return;
    if (verb == "BEGIN")
    {
        if (run == gRun && gPhase == "RECEIVING")
        { llMessageLinked(LINK_THIS, 970213, "BEGIN", run); return; }
        if (run == gRun && gLastResult != "") { reply("RESULT", gLastResult); return; }
        if (gPhase != "BOUND" || !gConfigReady || gReady != 15 || llGetListLength(fields) != 8) return;
        string choice = llList2String(fields, 5);
        string seconds = llList2String(fields, 6);
        if ((choice != "CONTAINER" && choice != "KEEP") || (choice == "KEEP" && !gKeep)
            || llJsonValueType(seconds, []) != JSON_NUMBER || (float)seconds < 0.0
            || llList2String(fields, 7) != "0")
        { sendTo(gHUD, gSession, run, "RESULT", "NO|Invalid%20choice%20or%20gesture"); return; }
        gRun = run; gChoice = choice; gSeconds = (float)seconds; gLastResult = ""; gAction = "";
        gCollectorUser = NULL_KEY; gCollectorHUD = NULL_KEY; gCollectorSession = NULL_KEY;
        integer value = llRound(gSeconds * gScale);
        if (value < 0) value = 0;
        if (value > gMax) value = gMax;
        integer i;
        for (i = 0; i < llGetListLength(gActions); ++i)
        {
            if (i) gAction += "^";
            gAction += llList2String(gActions, i) + "=" + (string)value;
        }
        gPhase = "RECEIVING";
        if (save()) llMessageLinked(LINK_THIS, 970213, "BEGIN", gRun);
        return;
    }
    if (verb == "END" && run == gRun)
    {
        if (gLastResult != "") { reply("RESULT", gLastResult); return; }
        if (gPhase != "RECEIVING" || llGetListLength(fields) != 6) return;
        gPhase = "BUILDING";
        if (save()) llMessageLinked(LINK_THIS, 970213, "END|" + llList2String(fields, 5), run);
    }
    else if (verb == "ABORT" && run == gRun && (gPhase == "RECEIVING" || gPhase == "BUILDING"))
    {
        gPhase = "BOUND"; gLastResult = "NO|Upload%20cancelled";
        if (save()) llMessageLinked(LINK_THIS, 970213, "CLEAN", run);
    }
    else if (verb == "CLOSED" && run == gRun && (gPhase == "SETTLING" || gPhase == "PRODUCT"))
    {
        if (!write("ws:closed", (string)run)) return;
        gPhase = "PRODUCT";
        if (save())
        {
            // Raw input is no longer needed for container output; GIVE has already finished here.
            llMessageLinked(LINK_THIS, 970213, "CLEAN", run);
            finishProduct();
        }
        if (gConfigPending) { gConfigPending = FALSE; loadConfig(); }
    }
    else if (verb == "EXIT" && gPhase == "BOUND")
    {
        if (!write("ws:released", llList2Json(JSON_ARRAY, [gHUD, gSession, run]))) return;
        key hud = gHUD; key lease = gSession;
        gUser = NULL_KEY; gHUD = NULL_KEY; gSession = NULL_KEY; gRun = NULL_KEY;
        gPhase = "FREE"; gLastResult = "";
        if (save()) sendTo(hud, lease, run, "RELEASED", "");
    }
}
default
{
    state_entry()
    {
        string saved = llLinksetDataRead("ws:core");
        if (saved != "")
        {
            list data = llJson2List(saved);
            if (llGetListLength(data) != 13) { gFault = TRUE; return; }
            gUser = llList2Key(data, 0); gHUD = llList2Key(data, 1); gSession = llList2Key(data, 2);
            gRun = llList2Key(data, 3); gPhase = llList2String(data, 4); gLastResult = llList2String(data, 5);
            gChoice = llList2String(data, 6); gSeconds = (float)llList2String(data, 7); gAction = llList2String(data, 12);
        }
        list collector = llJson2List(llLinksetDataRead("ws:collector"));
        if (llList2Key(collector, 0) == gRun)
        { gCollectorUser = llList2Key(collector, 1); gCollectorHUD = llList2Key(collector, 2); gCollectorSession = llList2Key(collector, 3); }
        loadConfig(); llSetTimerEvent(5.0);
        llMessageLinked(LINK_THIS, 970298, "READY?", NULL_KEY);
        llOwnerSay("[Workshop] v0.7 coordinator. No ingredient/output collections.");
    }
    changed(integer flags)
    {
        if (flags & CHANGED_INVENTORY)
        {
            if (gPhase == "FREE" || gPhase == "BOUND") loadConfig();
            else gConfigPending = TRUE;
        }
    }
    dataserver(key query, string data)
    {
        if (query != gQuery) return;
        if (data == EOF)
        {
            if (gKind == "cutting_board") gKeep = FALSE;
            gConfigReady = gKind != "" && gMax >= 0 && gScale >= 0.0;
            if (gConfigReady && save()) resume();
            return;
        }
        applyConfig(data); ++gLine; gQuery = llGetNotecardLine(gNotecard, gLine);
    }
    touch_start(integer count)
    {
        key user = llDetectedKey(0);
        if (gFault || !gConfigReady || gReady != 15)
        { llOwnerSay("[Workshop] Waiting for configuration/subsystems. Touch again when ready."); return; }
        if (productPending())
        {
            // Do not replace a collector while a transfer is being dispatched.
            if (user == gCollectorUser)
            { if (gCollectorHUD) outputState(); else collectorOffer(); return; }
            if (!gDev && llGetInventoryType(gHudObject) != INVENTORY_OBJECT)
            { llOwnerSay("[Workshop] Missing configured HUDObject."); return; }
            key previousHUD = gCollectorHUD; key previousSession = gCollectorSession;
            gCollectorUser = user; gCollectorHUD = NULL_KEY; gCollectorSession = llGenerateKey();
            if (user == gUser) { gCollectorHUD = gHUD; gCollectorSession = gSession; }
            if (!saveCollector()) return;
            if (previousHUD != NULL_KEY && previousHUD != gHUD)
                sendTo(previousHUD, previousSession, gRun, "RELEASED", "");
            if (gCollectorHUD) outputState();
            else { provision(user); collectorOffer(); }
            return;
        }
        if (gPhase == "OFFERED" && user == gUser) { offer(); return; }
        if (gPhase == "BOUND" && user == gUser)
        {
            sessionMenu();
            return;
        }
        if (gPhase != "FREE") { llOwnerSay("[Workshop] Treatment phase: " + gPhase + ". Session retained with its HUD."); return; }
        if (!gDev && llGetInventoryType(gHudObject) != INVENTORY_OBJECT)
        { llOwnerSay("[Workshop] Missing configured HUDObject."); return; }
        gUser = user; gSession = llGenerateKey(); gPhase = "OFFERED";
        if (!save()) return;
        provision(user);
        offer();
    }
    object_rez(key object)
    {
        if (gPhase == "OFFERED") offer();
        else if (productPending() && gCollectorHUD == NULL_KEY) collectorOffer();
    }
    listen(integer channel, string name, key user, string choice)
    {
        if (gFault || channel != gSessionMenu || !gSessionListen || user != gUser
            || gMenuSession != gSession || gPhase != "BOUND") return;
        if (choice == "Text: ON" || choice == "Text: OFF")
        {
            gHover = !gHover;
            configureOutput();
            llWhisper(-918273, "HOVER|" + (string)gHover);
            sessionMenu();
            return;
        }
        if (choice != "Resume" && choice != "Exit") return;
        llListenRemove(gSessionListen); gSessionListen = 0;
        if (choice == "Resume")
        {
            offer();
            sendTo(gHUD, gSession, NULL_KEY, "BOUND", "");
            llOwnerSay("[Workshop] Session retained. Continue with the associated HUD.");
        }
        else sendTo(gHUD, gSession, NULL_KEY, "EXIT_REQUEST", "");
    }
    link_message(integer sender, integer number, string text, key run)
    {
        if (sender != llGetLinkNumber() || gFault) return;
        if (number == 970299)
        {
            if (text == "HUD") gReady = gReady | 1;
            else if (text == "EVAL") gReady = gReady | 2;
            else if (text == "OUTPUT") gReady = gReady | 4;
            else if (text == "STORAGE") gReady = gReady | 8;
            if (gReady == 15) resume();
            return;
        }
        if (number == 970290)
        { llOwnerSay("[Workshop core] Free: " + (string)llGetFreeMemory()); return; }
        if (number == 970210) { receiveControl(run, text); return; }
        if (run != gRun || !validKey(run)) return;
        if (number == 970215)
        {
            if (text == "BEGIN_READY" && gPhase == "RECEIVING") reply("ACK", "BEGIN");
            else if (text == "BUILD_STARTED" && gPhase == "RECEIVING") { gPhase = "BUILDING"; save(); }
            else if (text == "INPUT_READY" && gPhase == "BUILDING")
            {
                gPhase = "EVALUATING";
                if (save()) { gDeadline = llGetUnixTime() + 15; llMessageLinked(LINK_THIS, 970202, gAction, run); }
            }
            else if (llSubStringIndex(text, "ERROR|") == 0 && (gPhase == "BUILDING" || gPhase == "RECEIVING"))
                failure(llGetSubString(text, 6, -1));
        }
        else if (number == 970201 && gPhase == "EVALUATING")
        {
            if (text == "STORED")
            {
                gPhase = "OUTPUT";
                if (save()) llMessageLinked(LINK_THIS, 970220, "START|" + gChoice + "|" + (string)gUser, run);
            }
            else if (llSubStringIndex(text, "ERROR|") == 0) failure(llGetSubString(text, 6, -1));
        }
        else if (number == 970221)
        {
            if (text == "READY" && gPhase == "OUTPUT")
            {
                gCollectorUser = gUser; gCollectorHUD = gHUD; gCollectorSession = gSession;
                if (!saveCollector()) return;
                gPhase = "SETTLING"; gLastResult = "OK";
                if (save()) { reply("RESULT", "OK"); outputState(); }
            }
            else if (text == "OK")
            {
                if (gPhase == "OUTPUT")
                { gPhase = "SETTLING"; gLastResult = "OK"; if (save()) reply("RESULT", "OK"); }
                else finishProduct();
            }
            else if (llSubStringIndex(text, "TRANSFERRED|") == 0 || llSubStringIndex(text, "TRANSFER_NO|") == 0
                || llSubStringIndex(text, "DISCARDED|") == 0)
            {
                sendTo(gCollectorHUD, gCollectorSession, gRun, "OUTPUT_REPLY", text);
                outputState();
                finishProduct();
            }
            else if (llSubStringIndex(text, "ERROR|") == 0 && gPhase == "OUTPUT") failure(llGetSubString(text, 6, -1));
        }
    }
    timer()
    {
        if (gReady != 15) llMessageLinked(LINK_THIS, 970298, "READY?", NULL_KEY);
        if (gPhase == "OFFERED") offer();
        else if (productPending() && gCollectorSession != NULL_KEY && gCollectorHUD == NULL_KEY) collectorOffer();
        if (gPhase == "EVALUATING" && gDeadline && llGetUnixTime() >= gDeadline)
        { gDeadline = 0; llOwnerSay("[Workshop] Evaluation pending. Lock retained; no stock operation sent."); }
    }
}

