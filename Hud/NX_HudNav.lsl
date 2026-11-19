#define SCRIPT_NAME    "NX_HudNav"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// NX_HudNav — the HUD-side navigation hub: detect player actions, drive page rotation.
// Takes over the navigation role the removed MC_Selected_Controller / MC_Workshop_Link used to play.
// Rotation itself stays in MC_Turn_Z (the dumb executor); this script only decides transitions and feeds it.
//
// This slice (navigation-pure, no craft/basket yet): P0 -> P1 on the Continue button.
//   - P0 Continue = prim "p0_action2" -> emit 918310 CONTINUE (fresh ticket) -> MC_Turn_Z rotates to P1.
//     No basket gate here: in the old code MC_Selected_Controller gated on available ingredients; that
//     gating returns with the scan/stock flow. For now Continue always turns to P1.
//   - Return to P0 (discard) is already owned by MC_Turn_Z (the P1_DISCARD touch) + the basket controller.
//   - P1<->P4 (PAUSE/observe) and P1->P3 (TAKE/recipient) are craft-coupled (clock / evaluation) and are
//     wired when the craft flow exists. See docs/README_P4.md, docs/README_P3.md and the fiche.
//
// Install in HUD ROOT. It replaces MC_Selected_Controller's p0_action2 -> 918310 navigation emit; remove
// that old controller in-world so the Continue button is not driven twice.

integer TURN_CONTINUE = 918310;        // -> MC_Turn_Z: "CONTINUE" (ticket) rotates to P1

default
{
    state_entry(){ nexusBoot(); }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    touch_start(integer n)
    {
        integer i;
        for(i = 0; i < n; ++i){
            if(llDetectedKey(i) == llGetOwner()){
                string name = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM));
                if(name == "p0_action2")                    // Continue -> craft page
                    llMessageLinked(LINK_THIS, TURN_CONTINUE, "CONTINUE", llGenerateKey());
            }
        }
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT) nexusMemReport();
    }
}
// REVIEW: 2026-11-18 — navigation-pure slice: only P0->P1 is wired. P4 (PAUSE/observe) and P3 (TAKE) are
//   craft-coupled and wait on the craft flow; the Continue basket gate also returns then.
