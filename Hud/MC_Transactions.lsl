// ROOT. Simple source relay; filename retained for installation compatibility.
// No TX2, session, journal, automatic retry, basket or craft operation.
integer CHANNEL = -918274;
key gRequest = NULL_KEY;
integer gUntil;
integer gMinFree = 65536;

integer validKey(key value)
{
    if (value) return TRUE;
    return FALSE;
}

announce()
{
    string status = "IDLE";
    if (gRequest != NULL_KEY) status = "BUSY";
    llMessageLinked(LINK_THIS, 918302, status, NULL_KEY);
    integer free = llGetFreeMemory();
    if (free < gMinFree) gMinFree = free;
}

default
{
    state_entry()
    {
        llListen(CHANNEL, "", NULL_KEY, "");
        llSetTimerEvent(2.0); announce();
    }
    on_rez(integer parameter) { llResetScript(); }
    link_message(integer sender, integer number, string text, key request)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == 918309)
        {
            llOwnerSay("[Source relay] Free Mono memory: " + (string)llGetFreeMemory()
                + " bytes; observed minimum: " + (string)gMinFree + "."); return;
        }
        if (number == 918304 && request == gRequest)
        { gRequest = NULL_KEY; announce(); return; }
        if (number != 918301 || !validKey(request) || gRequest != NULL_KEY) return;
        if (llLinksetDataRead("mc:simple:ready") != "1"
            || llLinksetDataRead("mc:simple:owner") != (string)llGetKey()) return;
        list fields = llParseStringKeepNulls(text, ["|"], []);
        string verb = llList2String(fields, 0);
        key source = llList2Key(fields, 1);
        if (llGetListLength(fields) != 3 || (verb != "TAKE" && verb != "RETURN")
            || !validKey(source) || llList2String(fields, 2) != "1") return;
        // Only transmit the exact request already saved by Selected.
        list row = llParseStringKeepNulls(llLinksetDataRead("mc:simple:row:" + (string)source), ["|"], []);
        if (llGetListLength(row) != 6 || llList2Key(row, 2) != request
            || llList2String(row, 3) != verb || llList2Integer(row, 4) != 1) return;
        // Set the transport lock only after matching the exact persisted request; timeouts never resend it.
        gRequest = request;
        gUntil = llGetUnixTime() + 15;
        announce();
        llRegionSayTo(source, CHANNEL, "MC|" + verb + "|" + (string)source + "|" + (string)request + "|1");
    }
    listen(integer channel, string name, key source, string text)
    {
        // REVIEW: same-owner sources only. A production/shared-workshop deployment needs an explicit access policy and a compatible protocol.
        if (channel != CHANNEL || llGetOwnerKey(source) != llGetOwner()) return;
        list fields = llParseStringKeepNulls(text, ["|"], []);
        if (llGetListLength(fields) != 7 || llList2String(fields, 0) != "MC"
            || llList2String(fields, 1) != "RESULT" || llList2Key(fields, 2) != source) return;
        key request = llList2Key(fields, 3);
        string verb = llList2String(fields, 4);
        string status = llList2String(fields, 5);
        integer stock = llList2Integer(fields, 6);
        if (!validKey(request) || (verb != "TAKE" && verb != "RETURN") || (status != "OK" && status != "NO")
            || stock < 0 || (string)stock != llList2String(fields, 6)) return;
        // Selected performs pending UUID/verb matching; forwarding a late reply does not confirm it by itself.
        // Late replies can resolve a saved row, including after a script reset.
        llMessageLinked(LINK_THIS, 918303, verb + "|" + (string)source + "|" + status + "|" + (string)stock, request);
    }
    timer()
    {
        if (gRequest != NULL_KEY && llGetUnixTime() >= gUntil)
        {
            llOwnerSay("[Source relay] No confirmed reply. This source remains pending; nothing resent.");
            gRequest = NULL_KEY;
        }
        announce();
    }
}
