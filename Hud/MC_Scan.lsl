// MC_Scan v1.0 - reusable companion script, no HUD dependency.
// Put in the SAME prim as its client. Only this script owns its timer/listen.
// Request: link_message 918270, str = optional chat channel, id = request UUID.
// Empty str uses production channel; test client explicitly uses -918274.
// Reply to requesting link only, echoing request UUID in id:
// 918271 BEGIN, 918272 ITEM (original HERE), 918273 BLANK (original BLANK),
// 918274 END (itemCount|blankCount).
// A new request replaces an unfinished scan; only the newest gets a result.
// Local request UUIDs are NOT transmitted by the existing PING/HERE protocol.

integer CRAFT_CHANNEL = -918273;
float SCAN_SECONDS = 2.0;
integer SCAN_REFRESH = 918270;
integer SCAN_BEGIN   = 918271;
integer SCAN_ITEM    = 918272;
integer SCAN_BLANK   = 918273;
integer SCAN_END     = 918274;

integer gListen;
integer gChannel;
integer gScanning;
integer gClientLink;
key gRequest;
float gDeadline;
// Stride 2: UUID, original payload. No application-level count limit.
// REVIEW: impose source-count and total-payload limits before retaining replies; scanning is currently unbounded.
list gItems;
list gBlanks;

integer findSource(list rows, key source)
{
    integer i;
    for (i = 0; i < llGetListLength(rows); i += 2)
        if (llList2Key(rows, i) == source) return i;
    return -1;
}

list upsert(list rows, key source, string payload)
{
    integer i = findSource(rows, source);
    if (i == -1) return rows + [source, payload];
    return llListReplaceList(rows, [source, payload], i, i + 1);
}

list removeSource(list rows, key source)
{
    integer i = findSource(rows, source);
    if (i == -1) return rows;
    return llDeleteSubList(rows, i, i + 1);
}

startScan(integer clientLink, key request, integer channel)
{
    llSetTimerEvent(0.0);
    gItems = [];
    gBlanks = [];
    gClientLink = clientLink;
    gRequest = request;
    gChannel = channel;
    gScanning = TRUE;
    gDeadline = llGetTime() + SCAN_SECONDS;
    gListen = llListen(gChannel, "", NULL_KEY, "");
    llSetTimerEvent(SCAN_SECONDS);
    llWhisper(gChannel, "PING");
}

finishScan()
{
    gScanning = FALSE;
    llSetTimerEvent(0.0);
    llListenRemove(gListen);
    // REVIEW: one linked message per source can overwhelm downstream event queues; large scans need flow control or bounded pages.
    integer itemCount = llGetListLength(gItems) / 2;
    integer blankCount = llGetListLength(gBlanks) / 2;
    llMessageLinked(gClientLink, SCAN_BEGIN, "", gRequest);
    integer i;
    for (i = 0; i < llGetListLength(gItems); i += 2)
        llMessageLinked(gClientLink, SCAN_ITEM, llList2String(gItems, i + 1), gRequest);
    for (i = 0; i < llGetListLength(gBlanks); i += 2)
        llMessageLinked(gClientLink, SCAN_BLANK, llList2String(gBlanks, i + 1), gRequest);
    llMessageLinked(gClientLink, SCAN_END,
        (string)itemCount + "|" + (string)blankCount, gRequest);
    gItems = [];
    gBlanks = [];
}

default
{
    state_entry()
    {
        gScanning = FALSE;
        llSetTimerEvent(0.0);
    }

    on_rez(integer parameter) { llResetScript(); }

    link_message(integer sender, integer number, string payload, key request)
    {
        if (number != SCAN_REFRESH || request == NULL_KEY) return;
        integer channel = CRAFT_CHANNEL;
        if (payload != "") channel = (integer)payload;
        if (channel == 0) return;
        if (gScanning) llListenRemove(gListen);
        startScan(sender, request, channel);
    }

    listen(integer channel, string name, key source, string payload)
    {
        if (!gScanning || channel != gChannel) return;
        // Ignore late events even when the timer event is still queued.
        if (llGetTime() >= gDeadline) return;
        list fields = llParseStringKeepNulls(payload, ["|"], []);
        integer count = llGetListLength(fields);
        if (count < 2 || source == NULL_KEY) return;
        // The advertised source must match the actual speaker. This validates identity, not ownership or eligibility.
        if (llList2Key(fields, 1) != source) return;
        string verb = llList2String(fields, 0);
        if (verb == "HERE")
        {
            // REVIEW: numeric fields and payload lengths are not fully validated; bound metadata before it enters the HUD snapshots.
            if (count < 10) return;
            if (llList2Integer(fields, 9) != 5) return;
            if (llList2Integer(fields, 3) <= 0)
                gItems = removeSource(gItems, source);
            else
                gItems = upsert(gItems, source, payload);
            gBlanks = removeSource(gBlanks, source);
        }
        else if (verb == "BLANK")
        {
            // Old BLANK|uuid is accepted too (capacity absent).
            gBlanks = upsert(gBlanks, source, payload);
            gItems = removeSource(gItems, source);
        }
        else if (verb == "GONE")
        {
            gItems = removeSource(gItems, source);
            gBlanks = removeSource(gBlanks, source);
        }
    }

    timer()
    {
        if (!gScanning) return;
        // A timer queued before a replacement Refresh must not finish it early.
        float remaining = gDeadline - llGetTime();
        if (remaining > 0.0) { llSetTimerEvent(remaining); return; }
        finishScan();
    }
}
