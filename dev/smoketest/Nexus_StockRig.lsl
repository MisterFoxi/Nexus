#define SCRIPT_NAME    "Nexus_StockRig"
#define SCRIPT_VERSION "v0.1.1"
#include "nexus_header.lsl"

// Test rig for Nexus_Server (dev/stock-protocol.md). Throwaway, no production use.
// Plays both roles (fake component + fake workshop) over NX_STOCK. Rez this next to the
// server (same region). Touch = fire the next step; the rig logs every reply and ticks
// a line when it matches the expected prefix. Replies come to us via the server's RegionSayTo,
// so no DISCOVER needed — all traffic is on the shared channel.
//
// NOTE: tickets are UUIDs (the server casts the ticket field to key), hence llGenerateKey().

integer NX_STOCK = -918280;

key A; key B; key C;        // SIDs: two inputs + one crafted output
key T1; key T2; key T3;     // tickets (must be valid keys)
list gSteps;                // "label=message=expectedPrefix"
integer gStep;
string  gExpect;

logm(string m){ llOwnerSay("[rig] " + m); }

build()
{
    key o = llGetOwner();
    string sA = (string)A; string sB = (string)B; string sC = (string)C;
    string sO = (string)o;
    // field separator is '~' (absent from labels, messages and expected prefixes)
    gSteps = [
      "REGISTER A seed 5~NX|REGISTER|" + sA + "|" + sO + "|h|0|5~NX|QTY|" + sA + "|5",
      "REGISTER B seed 3~NX|REGISTER|" + sB + "|" + sO + "|h|0|3~NX|QTY|" + sB + "|3",
      "RESERVE t1 A:2 B:1~NX|RESERVE|" + (string)T1 + "|" + sA + ":2^" + sB + ":1~NX|RES_OK|" + (string)T1,
      "COMMIT t1 + OUT C qty4~NX|COMMIT|" + (string)T1 + "|OUT|" + sC + "|4|h~NX|COMMIT_OK|" + (string)T1,
      "RESERVE t2 A:10 (expect NO)~NX|RESERVE|" + (string)T2 + "|" + sA + ":10~NX|RES_NO|" + (string)T2,
      "RESERVE t3 A:1~NX|RESERVE|" + (string)T3 + "|" + sA + ":1~NX|RES_OK|" + (string)T3,
      "RELEASE t3 (A back to 3)~NX|RELEASE|" + (string)T3 + "~NX|REL_OK|" + (string)T3,
      "RESERVE t1 again (idempotent)~NX|RESERVE|" + (string)T1 + "|" + sA + ":2^" + sB + ":1~NX|RES_OK|" + (string)T1,
      "DISCARD B (expect QTY 0)~NX|DISCARD|" + sB + "~NX|QTY|" + sB + "|0"
    ];
    logm("SIDs  A=" + sA + "  B=" + sB + "  C(out)=" + sC);
    logm("touch to run " + (string)(llGetListLength(gSteps)) + " steps");
}

default
{
    state_entry()
    {
        nexusBoot();
        A = llGenerateKey(); B = llGenerateKey(); C = llGenerateKey();
        T1 = llGenerateKey(); T2 = llGenerateKey(); T3 = llGenerateKey();
        gStep = 0; gExpect = "";
        llListen(NX_STOCK, "", NULL_KEY, "");
        build();
    }

    touch_start(integer n)
    {
        if (gStep >= llGetListLength(gSteps)) { logm("-- sequence complete; touch to replay --"); gStep = 0; return; }
        list p = llParseStringKeepNulls(llList2String(gSteps, gStep), ["~"], []);
        logm("STEP " + (string)gStep + ": " + llList2String(p, 0));
        gExpect = llList2String(p, 2);
        llRegionSay(NX_STOCK, llList2String(p, 1));
        gStep++;
    }

    listen(integer chan, string nm, key who, string msg)
    {
        if (chan != NX_STOCK) return;
        logm("RECV " + msg);
        if (gExpect != "" && llSubStringIndex(msg, gExpect) == 0)
        {
            logm("   PASS (matched " + gExpect + ")");
            gExpect = "";
        }
    }

    on_rez(integer p) { llResetScript(); }
}
