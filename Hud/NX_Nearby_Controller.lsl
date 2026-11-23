#define SCRIPT_NAME    "NX_Nearby_Controller"
#define SCRIPT_VERSION "v0.2.1"
#include "nexus_header"

// Nearby data and independent pagination controller. Install in ROOT with NX_Render.
// Replaces MC_Nearby_Display; never install both controllers together.
// All physical buttons are script-free; root receives their touch events.
string PREV_NAME = "P0_PREV";
string NEXT_NAME = "P0_NEXT";
integer VIEW = 918290;
integer RENDER_READY = 918291;
integer ADD = 918300;
integer TX_STATE = 918302;
integer STOCK = 918305;
integer REFRESH_REQUEST = 918287;
integer NX_HUD = -918282;              // pick -> bench
integer BIND_INFO = 918260;            // <- NX_HudFace: "<bench>|<session>"
key gBench = NULL_KEY;
string gSession = "";
// Verify these names against the physical '+' buttons before installation.
string ADD_PREFIX = "P0_ADD_";
integer gTxBusy = TRUE;
integer gRescan;
integer gPreserveNextScan;
integer gKeepPage;
integer SCAN_REFRESH = 918270;
// NX_Scan_Refresh relays SCAN_* messages with code + 10, same text/request.
integer DISPLAY_BEGIN = 918281;
integer DISPLAY_ITEM  = 918282;
integer DISPLAY_BLANK = 918283;
integer DISPLAY_END   = 918284;
integer DISPLAY_ABORT = 918285;

integer gPage; // zero-based, displayed one-based
integer gWaiting;
integer gReceiving;
integer gRefreshLink;
integer gBlankCount;
key gRequest;
// Stride 3: full name, source UUID, complete original HERE message.
list gRows;
// REVIEW: both snapshots retain complete HERE messages without a size/count budget; many sources or large payloads can exhaust script memory.
list gPending;

// --- observation assembly (feeds P4 via NX_Eval; see docs) ---
integer OBS_REQ = 918420;        // <- NX_P4_Controller: assemble a snapshot and observe
integer OBS_RESULT = 918421;     // -> NX_P4_Controller: "<name>|<escaped description>" or "ERROR|<reason>"
integer INSPECT = 918372;        // -> NX_P1_Animation: "INSPECT" (read the live cut gesture)
integer INSPECT_REPLY = 918399;  // <- NX_P1_Animation: "OK|<elapsed>|<heat>" or "NO"
float   CHOP_FULL = 10.0;        // active seconds for a full cut; fab.grind = round(elapsed) capped here (per Workshop_Config)
list    gBasket;                 // stride 2: sid, qty  — the picked set (mirrored from NX|BASKET)
string  gBasketName;             // first picked source's display name
key     gObsTicket = NULL_KEY;   // pending INSPECT for an in-flight observation assembly

integer pageCount()
{
    integer count = (llGetListLength(gRows) / 3 + 3) / 4;
    if (count < 1) count = 1;
    return count;
}

string packView(list view)
{
    // Only the visible page: 18 bounded fields, never the basket.
    string text = "";
    integer i;
    for (i = 0; i < 18; ++i)
    {
        if (i) text += "|";
        text += llEscapeURL(llList2String(view, i));
    }
    return text;
}

render()
{
    integer total = pageCount();
    if (gPage >= total) gPage = total - 1;
    if (gPage < 0) gPage = 0;
    list view = [gPage + 1, total];
    integer row;
    for (row = 0; row < 4; ++row)
    {
        integer index = (gPage * 4 + row) * 3;
        if (index >= llGetListLength(gRows)) view += ["", 0, "", 0];
        else
        {
            list fields = llParseStringKeepNulls(llList2String(gRows, index + 2), ["|"], []);
            view += [llList2String(gRows, index), llList2Integer(fields, 4),
                llList2String(fields, 13), 1];
        }
    }
    llMessageLinked(LINK_THIS, VIEW, packView(view), (key)"NEARBY");
}

navigate(integer direction)
{
    integer total = pageCount();
    gPage = (gPage + direction + total) % total;
    render();
}


button(string name)
{
    if (name == llToLower(PREV_NAME)) { navigate(-1); return; }
    if (name == llToLower(NEXT_NAME)) { navigate(1); return; }
    integer row;
    for (row = 0; row < 4; ++row)
        if (name == llToLower(ADD_PREFIX) + (string)row)
        {
            if (gBench == NULL_KEY || gSession == "") { llOwnerSay("[Nearby] HUD not bound to a bench yet."); return; }
            integer index = (gPage * 4 + row) * 3;
            if (index >= llGetListLength(gRows)) return;
            key source = llList2Key(gRows, index + 1);
            if (!llGetListLength(llGetObjectDetails(source, [OBJECT_NAME])))
            {
                gRows = llDeleteSubList(gRows, index, index + 2);
                gPending = [];
                render();
                llOwnerSay("[Nearby] Source missing: row removed.");
                llMessageLinked(LINK_THIS, REFRESH_REQUEST, "KEEP_PAGE", NULL_KEY);
                return;
            }
            // pick -> bench: NX|PICK|<session>|<sid>|1|<name>|<icon>  (sid=field 2, name=3, icon=13 of HERE)
            list h = llParseStringKeepNulls(llList2String(gRows, index + 2), ["|"], []);
            string picon = "";
            if (llGetListLength(h) > 13) picon = llList2String(h, 13);
            llRegionSayTo(gBench, NX_HUD, "NX|PICK|" + gSession + "|" + llList2String(h, 2) + "|1|" + llList2String(h, 3) + "|" + picon);
            return;
        }
}

// Keep source UUID as identity even when two sources share the same displayed name.
addPending(string payload)
{
    list fields = llParseStringKeepNulls(payload, ["|"], []);
    if (llGetListLength(fields) < 13 || llList2String(fields, 0) != "HERE") return;
    key source = llList2Key(fields, 1);
    if (source == NULL_KEY || llList2Integer(fields, 4) <= 0) return;
    integer i;
    for (i = 0; i < llGetListLength(gPending); i += 3)
        if (llList2Key(gPending, i + 1) == source) return;
    gPending += [llList2String(fields, 3), source, payload];   // display name = field 3
}

// Find the complete HERE payload of a scanned source by its stable sid (HERE field 2); "" if absent.
string obsHere(string sid)
{
    integer r;
    for (r = 0; r < llGetListLength(gRows); r += 3)
    {
        list h = llParseStringKeepNulls(llList2String(gRows, r + 2), ["|"], []);
        if (llList2String(h, 2) == sid) return llList2String(gRows, r + 2);
    }
    return "";
}

// Build the eval snapshot: "fab.grind=N" + blank line + groups "taxonomy|count|use|stage|props|life|eff|organ",
// grouped by taxonomy/stage, joining the picked basket with the live scan metadata.
string obsSnapshot(integer grind)
{
    list labels;
    list groups;
    integer i;
    for (i = 0; i < llGetListLength(gBasket); i += 2)
    {
        string sid = llList2String(gBasket, i);
        integer qty = llList2Integer(gBasket, i + 1);
        string here = obsHere(sid);
        if (here != "")
        {
            list h = llParseStringKeepNulls(here, ["|"], []);
            string label = llList2String(h, 7) + "/" + llList2String(h, 8);   // taxonomy/stage
            integer fi = llListFindList(labels, [label]);
            if (fi == -1)
            {
                labels += [label];
                groups += [llList2String(h, 7) + "|" + (string)qty + "|" + llList2String(h, 5)
                    + "|" + llList2String(h, 8) + "|" + llList2String(h, 9) + "|" + llList2String(h, 6)
                    + "|" + llList2String(h, 10) + "|" + llList2String(h, 12)];
            }
            else
            {
                list g = llParseStringKeepNulls(llList2String(groups, fi), ["|"], []);
                g = llListReplaceList(g, [(integer)llList2String(g, 1) + qty], 1, 1);
                groups = llListReplaceList(groups, [llDumpList2String(g, "|")], fi, fi);
            }
        }
    }
    return "fab.grind=" + (string)grind + "\n\n" + llDumpList2String(groups, "\n");
}

default
{
    state_entry() { nexusBoot(); llListen(NX_HUD, "", NULL_KEY, ""); render(); }

    on_rez(integer parameter) { llResetScript(); }

    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
        {
            if (llDetectedKey(i) == llGetOwner())
            {
                string name = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM));
                button(name);
            }
        }
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if (chan != NX_HUD) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if (llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);
        if (gSession == "" || llList2String(f, 2) != gSession) return;          // only our bound session
        if (gBench != NULL_KEY && who != NULL_KEY && llGetOwnerKey(who) != llGetOwnerKey(gBench)) return;
        if (verb == "RESCAN")
        {
            llMessageLinked(LINK_SET, REFRESH_REQUEST, "KEEP_PAGE", NULL_KEY);   // server qty changed -> fresh scan, keep page
            return;
        }
        if (verb == "BASKET")
        {
            // Mirror the picked set (sid+qty) for observation assembly; the SELECTED display stays NX_Selected's job.
            gBasket = [];
            gBasketName = "";
            list rows = llParseStringKeepNulls(llList2String(f, 4), ["^"], []);
            integer i;
            for (i = 0; i < llGetListLength(rows); ++i)
            {
                list e = llParseStringKeepNulls(llList2String(rows, i), ["~"], []);  // sid~name~qty~icon
                gBasket += [llList2String(e, 0), (integer)llList2String(e, 2)];
                if (i == 0) gBasketName = llList2String(e, 1);
            }
            return;
        }
        if (verb == "OBSERVED")
        {
            // NX|OBSERVED|ticket|STATUS|descEsc|nameEsc  ->  P4 as  STATUS|nameEsc|descEsc
            llMessageLinked(LINK_THIS, OBS_RESULT, llList2String(f, 3) + "|" + llList2String(f, 5) + "|" + llList2String(f, 4), NULL_KEY);
            return;
        }
    }

    link_message(integer sender, integer number, string payload, key request)
    {
        if (number == NEXUS_MEM_REPORT) { nexusMemReport(); return; }
        if (number == BIND_INFO) { list bi = llParseStringKeepNulls(payload, ["|"], []); gBench = (key)llList2String(bi, 0); gSession = llList2String(bi, 1); return; }
        if (number == OBS_REQ && sender == llGetLinkNumber())
        {
            gObsTicket = llGenerateKey();
            llMessageLinked(LINK_THIS, INSPECT, "INSPECT", gObsTicket);   // fetch the live cut gesture first
            return;
        }
        if (number == INSPECT_REPLY && request == gObsTicket && gObsTicket != NULL_KEY)
        {
            gObsTicket = NULL_KEY;
            integer grind = 0;
            list parts = llParseStringKeepNulls(payload, ["|"], []);
            if (llList2String(parts, 0) == "OK")
            {
                // Match Workshop_Config.actionHeader exactly: fab.grind = round(elapsed), capped at CHOP_FULL.
                float e = (float)llList2String(parts, 1);
                grind = (integer)CHOP_FULL;
                if (e < CHOP_FULL) grind = llRound(e);
                if (grind < 0) grind = 0;
            }
            if (gBench != NULL_KEY && gSession != "")
                llRegionSayTo(gBench, NX_HUD, "NX|OBSERVE|" + gSession + "|"
                    + llEscapeURL(gBasketName) + "|" + llEscapeURL(obsSnapshot(grind)));
            return;
        }
        if (sender == llGetLinkNumber() && number == REFRESH_REQUEST)
        { gPreserveNextScan = payload == "KEEP_PAGE"; return; }
        if (sender == llGetLinkNumber() && number == TX_STATE)
        {
            integer wasBusy = gTxBusy;
            gTxBusy = payload != "IDLE";
            if (gTxBusy)
            {
                // A scan begun before a stock mutation must never overwrite its result.
                if (!wasBusy) { gWaiting = FALSE; gReceiving = FALSE; gPending = []; }
                gRescan = TRUE;
            }
            else if (gRescan)
            {
                gRescan = FALSE;
                llMessageLinked(LINK_THIS, REFRESH_REQUEST, "KEEP_PAGE", NULL_KEY);
            }
            return;
        }
        if (sender == llGetLinkNumber() && number == STOCK)
        {
            list stock = llParseStringKeepNulls(payload, ["|"], []);
            if (llGetListLength(stock) != 2) return;
            key source = llList2Key(stock, 0);
            integer quantity = llList2Integer(stock, 1);
            // A stock check during an unknown operation may have preceded its application.
            gWaiting = FALSE; gReceiving = FALSE; gPending = [];
            integer i;
            for (i = 0; i < llGetListLength(gRows); i += 3)
                if (llList2Key(gRows, i + 1) == source)
                {
                    if (quantity <= 0) gRows = llDeleteSubList(gRows, i, i + 2);
                    else
                    {
                        list here = llParseStringKeepNulls(llList2String(gRows, i + 2), ["|"], []);
                        here = llListReplaceList(here, [quantity], 3, 3);
                        gRows = llListReplaceList(gRows, [llDumpList2String(here, "|")], i + 2, i + 2);
                    }
                    jump stockApplied;
                }
            @stockApplied;
            render(); return;
        }
        if (number == RENDER_READY && sender == llGetLinkNumber() && payload == "NEARBY") { render(); return; }
        // REVIEW: this branch accepts scan requests from any link; enforce the intended root/client link if child scripts are not trusted.
        if (number == SCAN_REFRESH && request != NULL_KEY)
        {
            gKeepPage = gPreserveNextScan;
            gPreserveNextScan = FALSE;
            gRequest = request;
            gRefreshLink = sender;
            gWaiting = TRUE;
            gReceiving = FALSE;
            gPending = [];
            gBlankCount = 0;
            return;
        }
        if (!gWaiting || request != gRequest || sender != gRefreshLink) return;
        if (number == DISPLAY_ABORT)
        {
            gWaiting = FALSE;
            gReceiving = FALSE;
            gPending = [];
            return; // keep last completed snapshot
        }
        if (number == DISPLAY_BEGIN)
        {
            gPending = [];
            gBlankCount = 0;
            gReceiving = TRUE;
            return;
        }
        if (!gReceiving) return;
        if (number == DISPLAY_ITEM) addPending(payload);
        else if (number == DISPLAY_BLANK) ++gBlankCount;
        else if (number == DISPLAY_END)
        {
            list counts = llParseStringKeepNulls(payload, ["|"], []);
            if (llList2Integer(counts, 0) == llGetListLength(gPending) / 3
                && llList2Integer(counts, 1) == gBlankCount)
            {
                gRows = llListSort(gPending, 3, TRUE);
                if (!gKeepPage) gPage = 0;
                render();
            }
            else llOwnerSay("[Nearby] Incomplete scan result. Press Refresh again.");
            gPending = [];
            gWaiting = FALSE;
            gReceiving = FALSE;
        }
    }
}

