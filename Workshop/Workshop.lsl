string VERSION = "Workshop v0.9.1 (2026-11-02)";
// Session and treatment coordinator; sole writer of ws:core and ws:collector.
// ROOT: Config, Interface, HUD, Eval, Output, Storage. See README.md.
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
integer gHover = TRUE;
string gAction;
key gConfigTicket = NULL_KEY;
key gPendingRun = NULL_KEY;
key gPendingSession = NULL_KEY;
integer gPendingDeadline;
integer gReady; // HUD=1, Eval=2, Output=4, Storage=8, Interface=16; Config is correlated separately.
integer gConfigReady;
integer gConfigPending;
integer gFault;
integer gDeadline;

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
outputState() { llMessageLinked(LINK_THIS, 970260, "OUTPUT", NULL_KEY); }
collectorOffer()
{
    sendTo(gCollectorUser, gCollectorSession, NULL_KEY, "OFFER", gKind + "|" + (string)gSingle
        + "|" + (string)gKeep + "|" + (string)(!gDev) + "|OUTPUT");
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
    if (verb == "TRANSFER" && llGetListLength(fields) == 7
        && llList2Key(fields, 5) != NULL_KEY)
    {
        llMessageLinked(LINK_THIS, 970220, "TRANSFER|" + llList2String(fields, 5)
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
loadConfig()
{
    gConfigReady = FALSE;
    if (gPendingRun != NULL_KEY)
        sendTo(gHUD, gPendingSession, gPendingRun, "RESULT", "NO|Configuration%20reloading");
    gPendingRun = NULL_KEY;
    gConfigTicket = llGenerateKey();
    llMessageLinked(LINK_THIS, 970250, "LOAD", gConfigTicket);
}
configureOutput()
{
    if (write("ws:hover", (string)gHover)) llMessageLinked(LINK_THIS, 970252, (string)gHover, NULL_KEY);
}
resume()
{
    if (gFault || !gConfigReady || gReady != 31) return;
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
    if (source == gHUD && verb == "ACTIVITY" && gPhase == "BOUND"
        && llGetListLength(fields) == 6 && (run == NULL_KEY || run == gRun)
        && (llList2String(fields, 5) == "0" || llList2String(fields, 5) == "1"))
    { llMessageLinked(LINK_THIS, 970220, "ACTIVITY|" + llList2String(fields, 5), gRun); return; }
    if (source != gHUD || !validKey(run)) return;
    if (verb == "INSPECT") { llMessageLinked(LINK_THIS, 970256, wire, source); return; }
    if (verb == "BEGIN")
    {
        if (run == gRun && gPhase == "RECEIVING")
        { llMessageLinked(LINK_THIS, 970213, "BEGIN", run); return; }
        if (run == gRun && gLastResult != "") { reply("RESULT", gLastResult); return; }
        if (gPhase != "BOUND" || !gConfigReady || gReady != 31 || (llGetListLength(fields) != 8 && llGetListLength(fields) != 9)) return;
        if (gPendingRun != NULL_KEY) return;
        gPendingRun = run; gPendingSession = gSession; gPendingDeadline = llGetUnixTime() + 10;
        llMessageLinked(LINK_THIS, 970254, wire, run);
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
        if (save()) { llMessageLinked(LINK_THIS, 970220, "ACTIVITY|0", run); sendTo(hud, lease, run, "RELEASED", ""); }
    }
}
default
{
    state_entry()
    {
        llOwnerSay("[Nexus] " + VERSION);
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

    }
    changed(integer flags)
    {
        if (flags & CHANGED_INVENTORY)
        {
            if (gPhase == "FREE" || gPhase == "BOUND") loadConfig();
            else gConfigPending = TRUE;
        }
    }
    touch_start(integer count)
    {
        key user = llDetectedKey(0);
        llMessageLinked(LINK_THIS, 970260, "INFO", user);
        if (gFault || !gConfigReady || gReady != 31)
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
            llMessageLinked(LINK_THIS, 970220, "INFO", gRun);
            if (previousHUD != NULL_KEY && previousHUD != gHUD)
                sendTo(previousHUD, previousSession, gRun, "RELEASED", "");
            if (gCollectorHUD) outputState();
            else { llMessageLinked(LINK_THIS, 970260, "PROVISION|" + (string)gCollectorSession, user); collectorOffer(); }
            return;
        }
        if (gPhase == "OFFERED" && user == gUser) { offer(); return; }
        if (gPhase == "BOUND" && user == gUser)
        {
            llMessageLinked(LINK_THIS, 970260, "MENU", user);
            return;
        }
        if (gPhase != "FREE") { llOwnerSay("[Workshop] Treatment phase: " + gPhase + ". Session retained with its HUD."); return; }
        if (!gDev && llGetInventoryType(gHudObject) != INVENTORY_OBJECT)
        { llOwnerSay("[Workshop] Missing configured HUDObject."); return; }
        gUser = user; gSession = llGenerateKey(); gPhase = "OFFERED";
        if (!save()) return;
        llMessageLinked(LINK_THIS, 970260, "PROVISION|" + (string)gSession, user);
        offer();
    }
    object_rez(key object)
    {
        if (gPhase == "OFFERED") offer();
        else if (productPending() && gCollectorHUD == NULL_KEY) collectorOffer();
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
            else if (text == "INTERFACE") gReady = gReady | 16;
            if (gReady == 31) resume();
            return;
        }
        if (number == 970290)
        { llOwnerSay("[Workshop core] Free: " + (string)llGetFreeMemory()); return; }
        if (number == 970210) { receiveControl(run, text); return; }
        if (number == 970251)
        {
            if (text == "RESET") { loadConfig(); return; }
            if (run != gConfigTicket || run == NULL_KEY) return;
            gConfigTicket = NULL_KEY;
            list config = llJson2List(text);
            if (llGetListLength(config) != 7) { gConfigReady = FALSE; return; }
            gKind = llList2String(config, 0);
            gHudObject = llList2String(config, 2); gSingle = llList2Integer(config, 3);
            gKeep = llList2Integer(config, 4); gDev = llList2Integer(config, 5); gHover = llList2Integer(config, 6);
            gConfigReady = TRUE;
            if (save()) resume();
            return;
        }
        if (number == 970255 && run == gPendingRun && run != NULL_KEY)
        {
            gPendingRun = NULL_KEY;
            if (gPhase != "BOUND" || gSession != gPendingSession || !gConfigReady) return;
            if (llSubStringIndex(text, "NO|") == 0) { sendTo(gHUD, gSession, run, "RESULT", text); return; }
            list inputs = llJson2List(text);
            if (llGetListLength(inputs) != 4) return;
            if (!write("ws:inputs", llList2Json(JSON_ARRAY, [run, (float)llList2String(inputs, 1), llList2Integer(inputs, 2)]))) return;
            llMessageLinked(LINK_THIS, 970220, "ACTIVITY|0", gRun);
            gRun = run; gChoice = llList2String(inputs, 0); gSeconds = (float)llList2String(inputs, 1);
            gAction = llList2String(inputs, 3); gLastResult = "";
            gCollectorUser = NULL_KEY; gCollectorHUD = NULL_KEY; gCollectorSession = NULL_KEY;
            gPhase = "RECEIVING";
            if (save()) llMessageLinked(LINK_THIS, 970213, "BEGIN", gRun);
            return;
        }
        if (number == 970261 && run == gSession && gSession != NULL_KEY && gPhase == "BOUND")
        {
            if (text == "HOVER")
            {
                gHover = !gHover; configureOutput();
                llWhisper(-918273, "HOVER|" + (string)gHover);
                llMessageLinked(LINK_THIS, 970260, "MENU", gUser);
            }
            else if (text == "Resume")
            {
                offer(); sendTo(gHUD, gSession, NULL_KEY, "BOUND", "");
                llOwnerSay("[Workshop] Session retained. Continue with the associated HUD.");
            }
            else if (text == "Exit") sendTo(gHUD, gSession, NULL_KEY, "EXIT_REQUEST", "");
            return;
        }
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
                || llSubStringIndex(text, "TRANSFER_EXPIRED|") == 0)
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
        if (gPendingRun != NULL_KEY && llGetUnixTime() >= gPendingDeadline)
        {
            if (gPhase == "BOUND" && gSession == gPendingSession)
                sendTo(gHUD, gSession, gPendingRun, "RESULT", "NO|Input%20mapping%20timed%20out");
            gPendingRun = NULL_KEY;
        }
        if (gReady != 31) llMessageLinked(LINK_THIS, 970298, "READY?", NULL_KEY);
        if (gPhase == "OFFERED") offer();
        else if (productPending() && gCollectorSession != NULL_KEY && gCollectorHUD == NULL_KEY) collectorOffer();
        if (gPhase == "EVALUATING" && gDeadline && llGetUnixTime() >= gDeadline)
        { gDeadline = 0; llOwnerSay("[Workshop] Evaluation pending. Lock retained; no stock operation sent."); }
    }
}

