#define SCRIPT_NAME    "NX_HudFace"
#define SCRIPT_VERSION "v0.5.0"
#include "nexus_header"

// NX_HudFace — the worn HUD's thin face toward the bench.
//   v0.1: provisioning responder (NX|HUDQ -> NX|HUDA) so WS_Core stops re-giving.
//   v0.2: bind to the bench at reservation — the OFFER/ACCEPT/BOUND handshake of
//         docs/README_workshop_link.md "Association and lock", ported onto NX_HUD;
//         session = the bench lock (socle §8), kind = our own model.
// First stones of the thin backend that replaces MC_Workshop_Link / MC_Selected_Controller / MC_Transactions.
//
// Identity (single source of truth) = this object's name "<model> v<X.Y.Z>" (socle §8). The model
// doubles as our HUD kind: we accept an OFFER only when its kind is our model.
//   provisioning : bench -> av   NX|HUDQ|<bench>|<model>|<version>
//                  av(HUD)-> bench NX|HUDA|<model>|<version>
//   bind         : bench -> av    NX|OFFER|<bench>|<session>|<kind>|<single>|<keep>
//                  av(HUD)-> bench NX|ACCEPT|<session>|<kind>
//                  bench -> av     NX|BOUND|<session>
//
// One bench at a time: once bound, OFFERs from OTHER benches are ignored (the current bench releases on
// take/discard; that RELEASE round-trip is wired with the craft flow, later). A reset (re-wear) clears the bind.
// Fail-safe: a name that does not parse -> silent (no HUDA, no ACCEPT) so the bench re-provisions.

integer NX_HUD = -918282;              // bench <-> worn HUD
integer BIND_INFO = 918260;            // -> HUD linkset: "<bench>|<session>" so pick/basket scripts know the bench
integer DISCARD_REQ  = 918315;         // <- NX_P1_Animation (P1 DISCARD button): "DISCARD"
integer DISCARD_DONE = 918317;         // -> HUD linkset: "DISCARD_DONE" closes every page

string  gModel;                        // parsed model (name before " v") = our kind
string  gVersion;                      // parsed version ("vX.Y.Z")
// --- bind state ---
key     gBench   = NULL_KEY;           // bench we are bound (or binding) to
string  gSession = "";                 // the bench session (lock) we accepted
integer gBound;                        // BOUND confirmed by the bench

// Parse our own object name the same way WS_Core parses the reference HUD inventory name.
parseSelf(){
    gModel = ""; gVersion = "";
    string nm = llGetObjectName();
    integer p = llSubStringIndex(nm, " v");
    if(p > 0){
        string tail = llGetSubString(nm, p + 1, -1);       // "vX.Y.Z"
        if(llGetSubString(tail, 0, 0) == "v"){
            gModel   = llStringTrim(llGetSubString(nm, 0, p - 1), STRING_TRIM);
            gVersion = tail;
            return;
        }
    }
    llOwnerSay("[Nexus] " + SCRIPT_NAME + ": my name '" + nm
        + "' is not '<model> v<X.Y.Z>' - I won't answer the bench until renamed.");
}

default
{
    state_entry()
    {
        nexusBoot();
        llListen(NX_HUD, "", NULL_KEY, "");
        gBench = NULL_KEY; gSession = ""; gBound = FALSE;
        parseSelf();
    }

    attach(key id)
    {
        if(id != NULL_KEY){ llResetScript(); return; }     // worn: (re)read name + clear bind
        // detached: tell our bench we're gone so another avatar can take over (WS_Core Force, craft kept)
        if(gBench != NULL_KEY && gSession != "")
            llRegionSayTo(gBench, NX_HUD, "NX|UNBIND|" + gSession);
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c)
    {
        if(c & CHANGED_OWNER){ llResetScript(); return; }
        if(c & CHANGED_INVENTORY) parseSelf();              // renamed / re-saved
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(s != llGetLinkNumber()) return;
        if(num == DISCARD_REQ && llGetSubString(str, 0, 6) == "DISCARD")
        {
            // Player DISCARD on P1. str = "DISCARD|<started>". Forward to the bench with the started flag:
            // the bench RETURNs (not started) or CONSUMEs (started) the reserved units, keeps the lock, and
            // on a consume rotates to a fresh session and re-binds us. We only close the HUD pages here.
            if(gBench != NULL_KEY && gSession != "")
            {
                string started = llList2String(llParseStringKeepNulls(str, ["|"], []), 1);
                llRegionSayTo(gBench, NX_HUD, "NX|DISCARD|" + gSession + "|" + started);
            }
            llMessageLinked(LINK_THIS, DISCARD_DONE, "DISCARD_DONE", llGenerateKey());
            return;
        }
    }

    listen(integer chan, string nm, key id, string msg)
    {
        if(chan != NX_HUD) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);
        if(gVersion == "") return;                          // misnamed: stay silent -> bench re-provisions

        if(verb == "HUDQ"){                                 // provisioning probe
            key bench = (key)llList2String(f, 2);
            if(bench == NULL_KEY) return;
            llRegionSayTo(bench, NX_HUD, "NX|HUDA|" + gModel + "|" + gVersion);
            return;
        }

        if(verb == "OFFER"){                                // bind offer
            key bench = (key)llList2String(f, 2);
            if(bench == NULL_KEY || id != bench) return;     // the speaker must be the named bench
            if(gBound && bench != gBench) return;            // bound elsewhere: ignore other benches
            string session = llList2String(f, 3);
            if(llList2String(f, 4) != gModel) return;        // not an offer for our kind
            gBench = bench; gSession = session;              // (single=f[5], keep=f[6] stored with the craft flow, later)
            llRegionSayTo(bench, NX_HUD, "NX|ACCEPT|" + session + "|" + gModel);
            return;
        }

        if(verb == "BOUND"){                                // bench confirms
            if(id != gBench || gSession == "") return;
            if(llList2String(f, 2) != gSession) return;
            gBound = TRUE;
            llMessageLinked(LINK_SET, BIND_INFO, (string)gBench + "|" + gSession, NULL_KEY);
            llOwnerSay("[Nexus] HUD bound to the bench.");
            return;
        }

        if(verb == "TAKEDONE"){                             // craft finished on the bench (product delivered)
            if(id != gBench) return;
            // Reset P1 to a fresh preparation; the bench re-binds us (new session) via OFFER right after.
            llMessageLinked(LINK_THIS, DISCARD_DONE, "CRAFT_DONE", llGenerateKey());
            return;
        }
    }
}
// REVIEW: 2026-11-18 — we report our own model+version and let the bench compare (exact match in WS_Core).
// REVIEW: 2026-11-18 — single/keep from the OFFER are not stored yet (no craft flow to use them).
// REVIEW: 2026-11-18 — RELEASE is not wired: the bind clears only on reset (re-wear). Wire with the craft flow.
