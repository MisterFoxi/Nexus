// Workshop v0.7 - output owner: product, containers, CUT/GIVE, sounds/particles.
// Container discovery is spooled one key per object; no gRec list or ingredient basket.
integer CHANNEL = -918273;
key gRun = NULL_KEY;
key gUser = NULL_KEY;
string gPhase;
string gChoice;
string gResult;
integer gQuantity;
integer gDeadline;
integer gSourceIndex;
integer gUnit;
integer gDelivered;
integer gFault;
integer gBlankCount;
key gTicket = NULL_KEY;
key gTarget = NULL_KEY;
integer gCookTime = 20;
integer gHover = TRUE;
string gCookSound = "cook_sound";
string gReadySound = "ready_sound";
string gFailSound = "fail_sound";
string oName;
integer oUse;
integer oLife;
string oTax;
string oStage;
string oProps;
string oMed;
integer oEff;
integer oVerdict;

integer write(string name, string value)
{
    integer result = llLinksetDataWrite(name, value);
    if (result == 0 || result == 5) return TRUE;
    gFault = TRUE; llOwnerSay("[Workshop Output] Cannot save output. Locked; no automatic delivery retry."); return FALSE;
}
integer save()
{
    return write("ws:output", llList2Json(JSON_ARRAY, [gRun, gUser, gChoice, gPhase,
        gResult, gQuantity, gDeadline, gSourceIndex, gUnit, gDelivered]));
}
notify(string text) { llMessageLinked(LINK_THIS, 970221, text, gRun); }
step() { llMessageLinked(LINK_THIS, 970223, "", gRun); }
loopSnd(string sound) { if (sound != "" && llGetInventoryType(sound) == INVENTORY_SOUND) llLoopSound(sound, 1.0); }
oneSnd(string sound) { if (sound != "" && llGetInventoryType(sound) == INVENTORY_SOUND) llPlaySound(sound, 1.0); }
benchSmoke(integer on)
{
    if (!on) { llParticleSystem([]); return; }
    llParticleSystem([
        PSYS_PART_FLAGS, PSYS_PART_INTERP_COLOR_MASK | PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR, <0.8,0.8,0.8>, PSYS_PART_END_COLOR, <0.5,0.5,0.5>,
        PSYS_PART_START_ALPHA, 0.5, PSYS_PART_END_ALPHA, 0.0,
        PSYS_PART_START_SCALE, <0.15,0.15,0.0>, PSYS_PART_END_SCALE, <0.6,0.6,0.0>,
        PSYS_PART_MAX_AGE, 3.0, PSYS_SRC_BURST_RATE, 0.3, PSYS_SRC_BURST_PART_COUNT, 2,
        PSYS_SRC_ACCEL, <0.0,0.0,0.25>, PSYS_SRC_ANGLE_BEGIN, 0.0, PSYS_SRC_ANGLE_END, 0.3]);
}
parseProduct()
{
    list product = llParseStringKeepNulls(gResult, ["|"], []);
    oVerdict = llList2Integer(product, 1); oName = llList2String(product, 2);
    oUse = llList2Integer(product, 4); oLife = llList2Integer(product, 5);
    oTax = llList2String(product, 6); oStage = llList2String(product, 7);
    oProps = llList2String(product, 8); oMed = llList2String(product, 9); oEff = llList2Integer(product, 10);
}
string configWire(key container, integer quantity)
{
    return "CONFIG|" + (string)container + "|" + oName + "|" + (string)quantity
        + "|" + (string)oUse + "|" + (string)oLife + "|" + oTax + "|" + oStage
        + "|" + oProps + "|" + oMed + "|" + (string)oEff;
}
fail(string reason)
{
    if (gDelivered || gPhase == "DISPATCH_CONFIG" || gPhase == "DISPATCH_GIVE")
    {
        gPhase = "HOLD"; save();
        llOwnerSay("[Workshop Output] " + reason + " Output may already be handed over. Session retained; nothing replayed.");
        notify("HOLD"); return;
    }
    gPhase = "FAILED";
    if (save()) notify("ERROR|" + reason);
}
complete()
{
    gPhase = "DONE";
    if (!save()) return;
    benchSmoke(FALSE); llStopSound(); llSetText("", ZERO_VECTOR, 0.0);
    llWhisper(CHANNEL, "HOVER|" + (string)gHover);
    notify("OK");
}
ready()
{
    benchSmoke(FALSE); llStopSound();
    string verdict = "ready";
    if (oVerdict == 1) verdict = "a DANGEROUS brew";
    llSetText(oName + " (" + oTax + "/" + oStage + ")\n" + verdict + " - touch to collect", <0.6,0.9,0.6>, 1.0);
    loopSnd(gReadySound);
}
// One explicit destination per request. Never distribute to unselected blanks.
integer receipt(string status)
{
    string text = status + "|" + (string)gTicket + "|" + (string)gQuantity;
    if (!write("ws:out:receipt", llList2Json(JSON_ARRAY, [gRun, gTicket, text]))) return FALSE;
    notify(text);
    return TRUE;
}
finishTransfer()
{
    // Quantity is already persisted after dispatch. A reset here only finishes the receipt.
    if (!receipt("TRANSFERRED")) return;
    gPhase = "WAIT_CONTAINER";
    if (gQuantity <= 0) gPhase = "DONE";
    if (!save()) return;
    if (gQuantity <= 0) complete();
    else ready();
}
request(string verb, key ticket, key target, key user)
{
    list last = llJson2List(llLinksetDataRead("ws:out:receipt"));
    if (llList2Key(last, 0) == gRun && llList2Key(last, 1) == ticket)
    { notify(llList2String(last, 2)); return; }
    if ((ticket == NULL_KEY) || gPhase != "WAIT_CONTAINER") return;
    gTicket = ticket; gTarget = target; gUser = user;
    if (!write("ws:out:request", llList2Json(JSON_ARRAY, [gRun, ticket, target, user]))) return;
    if (verb == "DISCARD")
    {
        gQuantity = 0; gPhase = "DONE";
        if (save()) { receipt("DISCARDED"); complete(); }
    }
    else if (target) scan();
}
scan()
{
    gPhase = "CLEAR_BLANKS"; gBlankCount = 0;
    if (save()) step();
}
clearBlanks()
{
    list keys = llLinksetDataFindKeys("^ws:out:blank:", 0, 1);
    if (llGetListLength(keys))
    {
        integer result = llLinksetDataDelete(llList2String(keys, 0));
        if (result != 0 && result != 4) { fail("Cannot clear container discovery."); return; }
        step(); return;
    }
    gPhase = "SCANNING"; gDeadline = llGetUnixTime() + 2;
    if (save()) llWhisper(CHANNEL, "PING");
}
deliver()
{
    if (gQuantity <= 0) { complete(); return; }
    string entry = "ws:out:blank:" + (string)gTarget;
    string capacityText = llLinksetDataRead(entry);
    if (capacityText == "")
    {
        gPhase = "WAIT_CONTAINER";
        if (save()) receipt("TRANSFER_NO");
        return;
    }
    key container = gTarget;
    integer capacity = (integer)capacityText;
    integer quantity = gQuantity;
    if (capacity > 0 && quantity > capacity) quantity = capacity;
    string wire = configWire(container, quantity);
    if (llStringLength(llStringToBase64(wire)) > 1364) { fail("Product metadata exceeds one whisper."); return; }
    gPhase = "DISPATCH_CONFIG";
    if (!save()) return; // Persist the boundary before invoking the existing physical protocol.
    llWhisper(CHANNEL, wire);
    gQuantity -= quantity; gDelivered += quantity;
    integer removed = llLinksetDataDelete(entry);
    if (removed != 0 && removed != 4) { fail("Container receipt removal failed."); return; }
    gPhase = "RECEIPTING";
    if (save()) finishTransfer();
}
finishGive()
{
    list input = llJson2List(llLinksetDataRead("ws:input"));
    if (gSourceIndex >= llList2Integer(input, 2)) { complete(); return; }
    list row = llParseStringKeepNulls(llLinksetDataRead("ws:in:row:" + (string)gSourceIndex), ["|"], []);
    key source = llList2Key(row, 0);
    integer count = llList2Integer(row, 1);
    list here = llParseStringKeepNulls(llUnescapeURL(llList2String(row, 2)), ["|"], []);
    list result = llParseStringKeepNulls(gResult, ["|"], []);
    string organs = llList2String(result, 1);
    if (llGetListLength(row) != 3 || count < 1 || (organs == "" && llList2String(here, 11) == ""))
    { fail("Nothing to hand over for source."); return; }
    string wire = "GIVE|" + (string)source;
    if (organs != "") wire += "|" + organs;
    gPhase = "DISPATCH_GIVE";
    if (!save()) return;
    llWhisper(CHANNEL, "CUT|" + (string)source + "|" + (string)gUser);
    llWhisper(CHANNEL, wire);
    ++gDelivered; ++gUnit;
    if (gUnit >= count) { ++gSourceIndex; gUnit = 0; }
    gPhase = "GIVING";
    if (save()) step();
}
start(string choice, key user, key run)
{
    if (gRun == run)
    {
        if (gPhase == "DONE") notify("OK");
        else if (gPhase == "WAIT_CONTAINER") notify("READY");
        else if (gPhase == "KEEPING") llMessageLinked(LINK_THIS, 970230, "KEEP", run);
        else if (gPhase == "HOLD") notify("HOLD");
        return;
    }
    if (gPhase != "" && gPhase != "DONE" && gPhase != "FAILED") return;
    list cached = llJson2List(llLinksetDataRead("ws:eval:result"));
    if (llList2Key(cached, 0) != run) return;
    gRun = run; gUser = user; gChoice = choice; gResult = llList2String(cached, 1);
    gDelivered = 0; gSourceIndex = 0; gUnit = 0; gQuantity = 0;
    list result = llParseStringKeepNulls(gResult, ["|"], []);
    string code = llList2String(result, 0);
    if (code == "0") { fail("Nothing reacts."); return; }
    if (code != "1" && code != "2") { fail("Invalid evaluation result."); return; }
    if (code == "1")
    {
        if (llGetListLength(result) != 11 || llList2Integer(result, 3) <= 0)
        { fail("Invalid product DNA."); return; }
        gQuantity = llList2Integer(result, 3); parseProduct();
        if (llStringLength(llStringToBase64(configWire(NULL_KEY, gQuantity))) > 1364)
        { fail("Product metadata exceeds one whisper."); return; }
    }
    if (!write("ws:product", llList2Json(JSON_ARRAY, [run, gResult]))) return;
    gPhase = "COOKING"; gDeadline = llGetUnixTime() + gCookTime;
    if (!save()) return;
    llSetText("Cooking...", <0.95,0.85,0.5>, 1.0); benchSmoke(TRUE); loopSnd(gCookSound);
}
default
{
    state_entry()
    {
        llListen(CHANNEL, "", NULL_KEY, ""); llSetTimerEvent(1.0);
        string saved = llLinksetDataRead("ws:output");
        if (saved != "")
        {
            list data = llJson2List(saved);
            if (llGetListLength(data) != 10) { gFault = TRUE; return; }
            gRun = llList2Key(data, 0); gUser = llList2Key(data, 1); gChoice = llList2String(data, 2);
            gPhase = llList2String(data, 3); gResult = llList2String(data, 4); gQuantity = llList2Integer(data, 5);
            gDeadline = llList2Integer(data, 6); gSourceIndex = llList2Integer(data, 7);
            gUnit = llList2Integer(data, 8); gDelivered = llList2Integer(data, 9); parseProduct();
            list requestData = llJson2List(llLinksetDataRead("ws:out:request"));
            if (llList2Key(requestData, 0) == gRun)
            { gTicket = llList2Key(requestData, 1); gTarget = llList2Key(requestData, 2); gUser = llList2Key(requestData, 3); }
            if (gPhase == "DISPATCH_CONFIG" || gPhase == "DISPATCH_GIVE") fail("Reset at a physical dispatch boundary.");
            else if (gPhase == "RECEIPTING") finishTransfer();
            else if (gPhase == "SCANNING" || gPhase == "CLEAR_BLANKS") scan();
            else if (gPhase == "GIVING" || gPhase == "DELIVERING") step();
        }
        llMessageLinked(LINK_THIS, 970299, "OUTPUT", NULL_KEY);
    }
    link_message(integer sender, integer number, string text, key run)
    {
        if (sender != llGetLinkNumber() || gFault) return;
        if (number == 970298) { llMessageLinked(LINK_THIS, 970299, "OUTPUT", NULL_KEY); return; }
        if (number == 970222)
        {
            list config = llJson2List(text);
            gCookTime = llList2Integer(config, 0); if (gCookTime <= 0) gCookTime = 1;
            gHover = llList2Integer(config, 1); gCookSound = llList2String(config, 2);
            gReadySound = llList2String(config, 3); gFailSound = llList2String(config, 4);
            return;
        }
        if (number == 970290) { llOwnerSay("[Workshop Output] Free: " + (string)llGetFreeMemory()); return; }
        if (number == 970220)
        {
            if (text == "FAIL_SOUND") { oneSnd(gFailSound); return; }
            list fields = llParseStringKeepNulls(text, ["|"], []);
            if (llList2String(fields, 0) == "START") start(llList2String(fields, 1), llList2Key(fields, 2), run);
            else if (run == gRun && llGetListLength(fields) == 4
                && (llList2String(fields, 0) == "TRANSFER" || llList2String(fields, 0) == "DISCARD"))
                request(llList2String(fields, 0), llList2Key(fields, 1), llList2Key(fields, 2), llList2Key(fields, 3));
            else if (text == "STATUS" && run == gRun)
            {
                if (gPhase == "WAIT_CONTAINER") notify("READY");
                else if (gPhase == "DONE") notify("OK");
            }
            return;
        }
        if (run != gRun) return;
        if (number == 970231 && gPhase == "KEEPING")
        {
            if (text == "KEPT") complete();
            else if (llSubStringIndex(text, "ERROR|") == 0) fail(llGetSubString(text, 6, -1));
        }
        else if (number == 970223)
        {
            if (gPhase == "CLEAR_BLANKS") clearBlanks();
            else if (gPhase == "DELIVERING") deliver();
            else if (gPhase == "GIVING") finishGive();
        }
    }
    listen(integer channel, string name, key source, string text)
    {
        if (gFault) return;
        if (channel != CHANNEL || gPhase != "SCANNING" || llGetOwnerKey(source) != gUser) return;
        list fields = llParseStringKeepNulls(text, ["|"], []);
        integer capacity = llList2Integer(fields, 2);
        if (llGetListLength(fields) != 3 || llList2String(fields, 0) != "BLANK"
            || llList2Key(fields, 1) != source || capacity < 0 || (string)capacity != llList2String(fields, 2)) return;
        string entry = "ws:out:blank:" + (string)source;
        if (llLinksetDataRead(entry) == "") ++gBlankCount;
        write(entry, (string)capacity);
    }
    timer()
    {
        if (gFault) return;
        if (gPhase == "DONE")
        {
            list pending = llJson2List(llLinksetDataRead("ws:out:request"));
            list last = llJson2List(llLinksetDataRead("ws:out:receipt"));
            if (llList2Key(pending, 0) == gRun && llList2Key(pending, 1) != llList2Key(last, 1)) receipt("DISCARDED");
            return;
        }
        if (gPhase == "COOKING" && llGetUnixTime() >= gDeadline)
        {
            if (llGetSubString(gResult, 0, 0) == "2") { gPhase = "GIVING"; if (save()) step(); }
            else if (gChoice == "KEEP")
            { gPhase = "KEEPING"; if (save()) llMessageLinked(LINK_THIS, 970230, "KEEP", gRun); }
            else
            {
                gPhase = "WAIT_CONTAINER";
                if (save()) { ready(); notify("READY"); }
            }
        }
        else if (gPhase == "SCANNING" && llGetUnixTime() >= gDeadline)
        {
            gPhase = "DELIVERING";
            if (save()) step();
        }
    }
}
