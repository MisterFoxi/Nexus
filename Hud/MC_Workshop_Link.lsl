// ROOT. HUD-only Workshop endpoint. MCW contract: docs/README_workshop_link.md.
// Basket/stock belongs to Selected; active time belongs to MC_P1_Animation.
integer CHANNEL = -918275;
string HUD_KIND = "cutting_board";
string STORE = "mc:workshop:session";
key gBench = NULL_KEY;
key gSession = NULL_KEY;
key gRun = NULL_KEY;
integer gSingle;
integer gKeep;
integer gTemporary;
string gPhase;
string gChoice;
string gGesture;
integer gOffset;
integer gSequence;
string gWire;
integer gDeadline;
integer gFault;

integer validKey(key value)
{
    if (value) return TRUE;
    return FALSE;
}

integer save()
{
    integer result = llLinksetDataWrite(STORE, llList2Json(JSON_ARRAY,
        [llGetKey(), gBench, gSession, gSingle, gKeep, gPhase, gRun,
        gChoice, gGesture, gOffset, gSequence, gWire, gTemporary]));
    if (result == 0 || result == 5) return TRUE;
    gFault = TRUE;
    llOwnerSay("[Workshop HUD] Cannot save session. Actions locked.");
    return FALSE;
}

announce()
{
    llMessageLinked(LINK_THIS, 918371, gPhase, gSession);
}

string header(string verb)
{
    return "MCW|" + verb + "|" + (string)gBench + "|" + (string)gSession + "|" + (string)gRun;
}

integer send(string wire, string phase)
{
    // Whisper payload limit is bytes; base64 length gives an upper bound for UTF-8.
    if (llStringLength(llStringToBase64(wire)) > 1364)
    { llOwnerSay("[Workshop HUD] Source metadata exceeds one whisper. Nothing truncated."); return FALSE; }
    gWire = wire; gPhase = phase;
    if (!save()) return FALSE;
    llWhisper(CHANNEL, wire);
    gDeadline = llGetUnixTime() + 15;
    announce();
    return TRUE;
}

releaseGesture()
{
    llMessageLinked(LINK_THIS, 918372, "UNFREEZE", gRun);
    llMessageLinked(LINK_THIS, 918380, "CANCEL", gRun);
}

abort(string reason)
{
    // Only before END / on an explicit refusal: no successful output is inferred.
    llWhisper(CHANNEL, header("ABORT"));
    releaseGesture();
    gPhase = "IDLE"; gWire = "";
    if (save()) announce();
    llOwnerSay("[Workshop HUD] " + reason + " Ingredients retained.");
}

choose(string choice)
{
    if (gFault) return;
    if (gSession == NULL_KEY)
    { llOwnerSay("[Workshop HUD] Touch the workshop to associate this HUD first."); return; }
    if (gPhase != "IDLE")
    {
        // An explicit retry repeats the SAME envelope; the workshop must deduplicate it.
        if (choice == "RETRY" && gWire != "")
        { llWhisper(CHANNEL, gWire); gDeadline = llGetUnixTime() + 15; }
        else llOwnerSay("[Workshop HUD] Treatment pending. No new treatment sent.");
        return;
    }
    if (choice == "EXIT")
    {
        gRun = llGenerateKey(); gPhase = "EXITING"; gWire = "";
        if (save())
        { announce(); llMessageLinked(LINK_THIS, 918315, "DISCARD", gRun); }
        return;
    }
    if (choice != "CONTAINER" && choice != "KEEP") return;
    if (choice == "KEEP" && (!gKeep || HUD_KIND == "cutting_board"))
    { llOwnerSay("[Workshop HUD] Keeping output is not allowed at this workshop."); return; }
    gRun = llGenerateKey(); gChoice = choice; gPhase = "GESTURE";
    gGesture = ""; gOffset = 0; gSequence = 0; gWire = "";
    gDeadline = llGetUnixTime() + 5;
    if (save())
    { announce(); llMessageLinked(LINK_THIS, 918372, "SNAPSHOT", gRun); }
}

default
{
    state_entry()
    {
        llListen(CHANNEL, "", NULL_KEY, "");
        llSetTimerEvent(2.0);
        string stored = llLinksetDataRead(STORE);
        if (stored == "") return;
        list data = llJson2List(stored);
        if (llGetListLength(data) != 13 || llList2Key(data, 0) != llGetKey()
            || !validKey(llList2Key(data, 1)) || !validKey(llList2Key(data, 2)))
        { gFault = TRUE; llOwnerSay("[Workshop HUD] Invalid saved identity/session. Actions locked."); return; }
        gBench = llList2Key(data, 1); gSession = llList2Key(data, 2);
        gSingle = llList2Integer(data, 3); gKeep = llList2Integer(data, 4);
        gPhase = llList2String(data, 5); gRun = llList2Key(data, 6);
        gChoice = llList2String(data, 7); gGesture = llList2String(data, 8);
        gOffset = llList2Integer(data, 9); gSequence = llList2Integer(data, 10);
        gWire = llList2String(data, 11); gTemporary = llList2Integer(data, 12);
        if (HUD_KIND == "cutting_board") gKeep = FALSE;
        // Local-only preflight can be safely cancelled. Never replay a radio command on reset.
        if (gPhase == "GESTURE" || gPhase == "SNAPSHOT") abort("Interrupted local preparation.");
        else if (gPhase == "ROWS") llMessageLinked(LINK_THIS, 918380, "NEXT|" + (string)gOffset, gRun);
        else if (gPhase != "IDLE")
            llOwnerSay("[Workshop HUD] Session restored with a pending treatment. Waiting; nothing resent.");
        announce();
    }
    on_rez(integer parameter) { llResetScript(); }
    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber() || gFault) return;
        if (number == 918370) { choose(text); return; }
        if (number == 918373 && gPhase == "GESTURE" && ticket == gRun)
        {
            list result = llParseStringKeepNulls(text, ["|"], []);
            if (llGetListLength(result) != 3 || llList2String(result, 0) != "OK"
                || (float)llList2String(result, 1) < 0.0 || llList2Integer(result, 2))
            { abort("No usable gesture. Start the preparation, or discard a spoiled one."); return; }
            gGesture = llList2String(result, 1) + "|0";
            gPhase = "SNAPSHOT";
            gDeadline = llGetUnixTime() + 15;
            if (save()) llMessageLinked(LINK_THIS, 918380, "EXPORT", gRun);
            return;
        }
        if (number == 918381 && ticket == gRun)
        {
            list fields = llParseStringKeepNulls(text, ["|"], []);
            string verb = llList2String(fields, 0);
            if (verb == "ERROR" && (gPhase == "SNAPSHOT" || gPhase == "ROWS"))
            { abort(llList2String(fields, 1)); return; }
            if (text == "BEGIN" && gPhase == "SNAPSHOT")
            {
                if (!send(header("BEGIN") + "|" + gChoice + "|" + gGesture, "WAIT_BEGIN"))
                    abort("Cannot send preparation.");
                return;
            }
            if (gPhase != "ROWS") return;
            if (verb == "ROW" && llGetListLength(fields) == 5)
            {
                gOffset = llList2Integer(fields, 1);
                if (!send(header("ROW") + "|" + (string)gSequence + "|"
                    + llDumpList2String(llList2List(fields, 2, 4), "|"), "WAIT_ROW"))
                    abort("Cannot send source metadata.");
                return;
            }
            if (text == "END") send(header("END") + "|" + (string)gSequence, "WAIT_RESULT");
            return;
        }
        if (number == 918317)
        {
            if (text == "CRAFT_DONE" && ticket == gRun && gPhase == "SETTLING")
            {
                gPhase = "IDLE"; gWire = "";
                if (save()) { announce(); llWhisper(CHANNEL, header("CLOSED")); }
                return;
            }
            if (text == "DISCARD_DONE" && gPhase == "EXITING" && ticket == gRun)
            { send(header("EXIT"), "RELEASING"); return; }
            if (text == "DISCARD_DONE" && gPhase == "IDLE")
                llWhisper(CHANNEL, "MCW|DISCARDED|" + (string)gBench + "|" + (string)gSession + "|" + (string)ticket);
        }
    }
    listen(integer channel, string name, key source, string text)
    {
        if (channel != CHANNEL || gFault || llGetOwnerKey(source) != llGetOwner()) return;
        list fields = llParseStringKeepNulls(text, ["|"], []);
        if (llGetListLength(fields) < 5 || llList2String(fields, 0) != "MCW") return;
        string verb = llList2String(fields, 1);
        if (verb == "OFFER")
        {
            if (llGetListLength(fields) != 9 || llList2Key(fields, 2) != llGetOwner()
                || !validKey(llList2Key(fields, 3)) || llList2Key(fields, 4) != NULL_KEY
                || llList2String(fields, 5) != HUD_KIND) return;
            if (gSession != NULL_KEY)
            {
                // Only repeat the association response to the very same pending offer.
                if (source == gBench && llList2Key(fields, 3) == gSession && gPhase == "BINDING")
                    llWhisper(CHANNEL, gWire);
                return;
            }
            integer single = llList2Integer(fields, 6);
            integer keep = llList2Integer(fields, 7);
            integer temporary = llList2Integer(fields, 8);
            if ((single != 0 && single != 1) || (keep != 0 && keep != 1)
                || (temporary != 0 && temporary != 1)) return;
            gBench = source; gSession = llList2Key(fields, 3); gRun = NULL_KEY;
            gSingle = single; gKeep = keep; gTemporary = temporary;
            if (HUD_KIND == "cutting_board") gKeep = FALSE;
            send(header("ACCEPT") + "|" + (string)llGetOwner() + "|" + HUD_KIND, "BINDING");
            return;
        }
        if (source != gBench || llList2Key(fields, 2) != llGetKey()
            || llList2Key(fields, 3) != gSession || gSession == NULL_KEY) return;
        if (verb == "EXIT_REQUEST" && llList2Key(fields, 4) == NULL_KEY)
        {
            if (gPhase == "IDLE") choose("EXIT");
            else llOwnerSay("[Workshop HUD] Exit waits for the current treatment or stock closure.");
            return;
        }
        if (verb == "BOUND" && gPhase == "BINDING" && llList2Key(fields, 4) == NULL_KEY)
        {
            gPhase = "IDLE"; gWire = "";
            if (!save()) return;
            announce();
            llOwnerSay("[Workshop HUD] Associated with workshop.");
            if (gTemporary && !llGetAttached()) llRequestPermissions(llGetOwner(), PERMISSION_ATTACH);
            return;
        }
        if (llList2Key(fields, 4) != gRun || gRun == NULL_KEY) return;
        if (verb == "ACK")
        {
            string part = llList2String(fields, 5);
            if ((gPhase == "WAIT_BEGIN" && part == "BEGIN")
                || (gPhase == "WAIT_ROW" && part == "ROW" && llGetListLength(fields) == 7
                    && llList2Integer(fields, 6) == gSequence))
            {
                if (gPhase == "WAIT_ROW") ++gSequence;
                gPhase = "ROWS"; gWire = "";
                gDeadline = llGetUnixTime() + 5;
                if (save()) llMessageLinked(LINK_THIS, 918380, "NEXT|" + (string)gOffset, gRun);
            }
            return;
        }
        if (verb == "RESULT" && gPhase == "WAIT_RESULT")
        {
            string status = llList2String(fields, 5);
            if (status == "NO") { abort(llUnescapeURL(llList2String(fields, 6))); return; }
            if (status != "OK") return;
            gPhase = "SETTLING"; gWire = "";
            if (save()) { announce(); llMessageLinked(LINK_THIS, 918315, "COMPLETE", gRun); }
            return;
        }
        if (verb == "RELEASED" && gPhase == "RELEASING")
        {
            integer result = llLinksetDataDelete(STORE);
            if (result != 0 && result != 4) { gFault = TRUE; return; }
            gSession = NULL_KEY; gBench = NULL_KEY; gPhase = ""; gWire = "";
            announce();
            if (gTemporary && llGetAttached())
            {
                if (llGetPermissions() & PERMISSION_ATTACH) llDetachFromAvatar();
                else llRequestPermissions(llGetOwner(), PERMISSION_ATTACH);
            }
        }
    }
    run_time_permissions(integer permissions)
    {
        if (!(permissions & PERMISSION_ATTACH) || !gTemporary) return;
        if (gSession == NULL_KEY) { if (llGetAttached()) llDetachFromAvatar(); }
        else if (!llGetAttached()) llAttachToAvatarTemp(ATTACH_HUD_TOP_LEFT);
    }
    timer()
    {
        // These local requests are idempotent. Source operations are NEVER resent here.
        if (gFault) return;
        if ((gPhase == "GESTURE" || gPhase == "SNAPSHOT" || gPhase == "ROWS")
            && gDeadline && llGetUnixTime() >= gDeadline)
        { abort("Local HUD response timed out."); return; }
        if (gPhase == "SETTLING") llMessageLinked(LINK_THIS, 918315, "COMPLETE", gRun);
        else if (gPhase == "EXITING") llMessageLinked(LINK_THIS, 918315, "DISCARD", gRun);
        if (gDeadline && llGetUnixTime() >= gDeadline && gWire != "")
        {
            gDeadline = 0;
            llOwnerSay("[Workshop HUD] No workshop reply. Session retained; no new treatment or source request sent.");
        }
    }
}
