#define SCRIPT_NAME    "WS_Boot"
#define SCRIPT_VERSION "v0.1.1"
#include "nexus_header"

// WS_Boot — the Workshop's world/OPR gate. Counterpart of Nexus_Server's world plane.
// Single responsibility: get the compiled world into this linkset's LinksetData (cached, versioned),
// then declare the bench OPR. It does NOT craft, scan or evaluate.
//
// Boot sequence:
//   1. HELLO the server with the cached world version.
//   2a. WORLD_OK  -> world already in LSD and current -> OPR, no transfer.
//   2b. WORLD_BEGIN/CHUNK/END -> wipe the world realm, write the physics lines, verify the line count,
//       cache the new version, OPR. Count mismatch -> re-HELLO (consumer-side redo; no reliable transport).
//   WORLD_WAIT  -> server still ingesting; the retry timer re-HELLOs.
//   WORLD_BUMP  -> world republished; re-HELLO to resync (even once OPR).
//
// Wire (region say on NX_STOCK, server side in Server/nexus_server.lsl):
//   ws -> srv : NX|HELLO|<wsKey>|<cachedVer>
//   srv -> ws : NX|WORLD_OK|<ver> | NX|WORLD_BEGIN|<ver>|<n> | NX|WORLD_CHUNK|<ver>|<seq>|<payload>
//               NX|WORLD_END|<ver>|<nChunks> | NX|WORLD_WAIT | (broadcast) NX|WORLD_BUMP|<ver>
//   payload is OPAQUE: world lines joined by "\n". Re-split on "\n" only.

integer NX_STOCK = -918280;              // same channel as the server for now (stock-protocol §7)
integer WS_OPR   = 970110;               // link_message to the rest of the WS: "OPR|<ver>" once world is ready
float   RETRY    = 10.0;                  // re-HELLO cadence while not OPR (or awaiting the server)
string  WORLD_RE = "^(tok|tax|law|idx|dom):";   // world-knowledge realms (wiped before a fresh stream)
string  VER_KEY  = "ws:worldver";         // cached world version, persists across reset/re-rez

integer gOpr;                             // TRUE once the world is ready and OPR announced
key     gServer;                          // last server that answered (for the info menu)
// --- streaming state ---
string  gPendVer;                         // version of the stream in progress
integer gExpectN;                         // line count announced by WORLD_BEGIN
integer gWritten;                         // physics lines written so far
integer gChunks;                          // chunks received

setStatus(string s){ llSetText("Nexus • " + s, <1.0,1.0,1.0>, 1.0); }

helloNow(){
    string cached = llLinksetDataRead(VER_KEY);
    llRegionSay(NX_STOCK, "NX|HELLO|" + (string)llGetKey() + "|" + cached);
}

// wipe the world realms (never touches live state: state:/rz_/ws:)
wipeWorld(){
    list keys = llLinksetDataFindKeys(WORLD_RE, 0, 256);
    integer guard = 0;
    while(llGetListLength(keys) > 0 && guard < 20000){
        integer L = llGetListLength(keys); integer i;
        for(i = 0; i < L; ++i) llLinksetDataDelete(llList2String(keys, i));
        guard += L;
        keys = llLinksetDataFindKeys(WORLD_RE, 0, 256);
    }
}

// one "key = value" physics line -> LinksetData (same parse as the legacy World_Loader)
writeLine(string line){
    line = llStringTrim(line, STRING_TRIM);
    if(line == "" || llGetSubString(line, 0, 0) == "#") return;
    integer sep = llSubStringIndex(line, "=");
    if(sep <= 0) return;
    string k = llStringTrim(llGetSubString(line, 0, sep - 1), STRING_TRIM);
    string v = "";
    if(sep + 1 < llStringLength(line)) v = llStringTrim(llGetSubString(line, sep + 1, -1), STRING_TRIM);
    if(v == "") v = "1";                                  // idx: presence sentinel
    if(llLinksetDataWrite(k, v) == LINKSETDATA_OK) ++gWritten;
}

goOpr(string ver){
    gOpr = TRUE;
    llLinksetDataWrite(VER_KEY, ver);
    llSetTimerEvent(0.0);
    setStatus("Ready (OPR) • World " + ver);
    llOwnerSay("[Nexus] WS_Boot OPR — monde " + ver + " (" + llLinksetDataRead("law:observations:count") + " observations)");
    llMessageLinked(LINK_SET, WS_OPR, "OPR|" + ver, NULL_KEY);
}

default
{
    state_entry()
    {
        nexusBoot();
        gOpr = FALSE; gPendVer = ""; gExpectN = 0; gWritten = 0; gChunks = 0;
        llListen(NX_STOCK, "", NULL_KEY, "");
        setStatus("boot — Looking for server…");
        helloNow();
        llSetTimerEvent(RETRY);
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    timer(){ if(!gOpr) helloNow(); }      // keep knocking until the server answers / sync completes

    touch_start(integer n)
    {
        string info = "Nexus — WS_Boot " + SCRIPT_VERSION + "\n"
            + "State : " + (string)llList2String(["SYNC/attente","OPR"], gOpr) + "\n"
            + "World : " + llLinksetDataRead(VER_KEY) + "\n"
            + "Server : " + (string)gServer + "\n"
            + "Mem free : " + (string)llGetFreeMemory() + " o"
            + " | lsd " + (string)llLinksetDataAvailable() + " b free";
        llDialog(llDetectedKey(0), info, ["OK"], -1);
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_STOCK) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);

        if(verb == "SERVER"){ gServer = who; return; }     // presence announce / DISCOVER reply

        if(verb == "WORLD_OK"){                            // cache valid: world already in LSD
            gServer = who;
            goOpr(llList2String(f, 2));
            return;
        }
        if(verb == "WORLD_WAIT"){ gServer = who; setStatus("server getting ready…"); return; }

        if(verb == "WORLD_BEGIN"){                         // start of a fresh transfer
            gServer = who;
            gPendVer = llList2String(f, 2);
            gExpectN = (integer)llList2String(f, 3);
            gWritten = 0; gChunks = 0;
            wipeWorld();
            setStatus("sync " + gPendVer + " — 0/" + (string)gExpectN);
            return;
        }
        if(verb == "WORLD_CHUNK"){
            if(llList2String(f, 2) != gPendVer) return;    // stale/other stream
            string payload = llDumpList2String(llList2List(f, 4, -1), "|");   // rejoin: payload may hold '|'
            list lines = llParseStringKeepNulls(payload, ["\n"], []);
            integer i;
            for(i = 0; i < llGetListLength(lines); ++i) writeLine(llList2String(lines, i));
            ++gChunks;
            setStatus("sync  " + gPendVer + " — " + (string)gWritten + "/" + (string)gExpectN);
            return;
        }
        if(verb == "WORLD_END"){
            if(llList2String(f, 2) != gPendVer) return;
            if(gWritten == gExpectN) goOpr(gPendVer);      // complete
            else {                                          // dropped chunk: redo the whole pull
                setStatus("sync failed (" + (string)gWritten + "/" + (string)gExpectN + ") — retry");
                helloNow();
            }
            return;
        }
        if(verb == "WORLD_BUMP"){                          // world republished -> resync even if OPR
            gServer = who;
            setStatus("Wolrd updated — resync…");
            if(gOpr){ gOpr = FALSE; llSetTimerEvent(RETRY); }
            helloNow();
            return;
        }
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT) nexusMemReport();
    }
}
// REVIEW: 2026-11-18 — world pull has no per-chunk ACK; a dropped CHUNK is caught only at WORLD_END by the
//   line-count check, which triggers a full re-pull. Fine for a cold path; revisit if the world grows large.
// REVIEW: 2026-11-18 — HELLO is broadcast and accepts the first answering server; multi-server sims need
//   owner/name targeting (DISCOVER) before trusting a reply.
// REVIEW: 2026-11-18 — writeLine ignores LinksetData write failures beyond the OK check (no LSD-full guard).
