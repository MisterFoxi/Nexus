#define SCRIPT_NAME    "NX_HudNav"
#define SCRIPT_VERSION "v0.3.0"
#include "nexus_header"

// NX_HudNav — the HUD-side navigation hub: detect player actions, drive page rotation.
// Takes over the navigation role the removed MC_Selected_Controller / MC_Workshop_Link used to play.
// Rotation itself stays in NX_Turn_Z (the dumb executor); this script only decides transitions and feeds it.
//
// This slice (navigation-pure, no craft/basket yet): P0 -> P1 on the Continue button.
//   - P0 Continue = prim "p0_action2" -> emit 918310 CONTINUE (fresh ticket) -> NX_Turn_Z rotates to P1.
//     No basket gate here: in the old code MC_Selected_Controller gated on available ingredients; that
//     gating returns with the scan/stock flow. For now Continue always turns to P1.
//   - Return to P0 (discard) is already owned by NX_Turn_Z (the P1_DISCARD touch) + the basket controller.
//   - P1<->P4 (PAUSE/observe) and P1->P3 (TAKE/recipient) are craft-coupled (clock / evaluation) and are
//     wired when the craft flow exists. See docs/README_P4.md, docs/README_P3.md and the fiche.
//
// Install in HUD ROOT. It replaces MC_Selected_Controller's p0_action2 -> 918310 navigation emit; remove
// that old controller in-world so the Continue button is not driven twice.

integer TURN_CONTINUE = 918310;        // -> NX_Turn_Z: "CONTINUE" (ticket) rotates to P1
integer CANCONT = 918261;              // <- NX_Selected_Controller: current basket count
integer gCanCount;                     // basket size (0 = nothing selected -> Continue blocked)

// Single FURWARE init for the whole HUD: a full reset re-reads the box layout and clears stale content,
// then FURWARE emits fw_ready and every renderer repaints (empty). Expensive (FURWARE unavailable a few
// seconds) and GLOBAL, so it is issued once, here, at install — never per-renderer.
fwReset()
{
    llMessageLinked(LINK_SET, 0, "", "fw_reset");
}

default
{
    state_entry(){ nexusBoot(); fwReset(); }
    attach(key id){ if (id != NULL_KEY) fwReset(); }   // wear = install: re-init FURWARE once
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    touch_start(integer n)
    {
        integer i;
        for(i = 0; i < n; ++i){
            if(llDetectedKey(i) == llGetOwner()){
                string name = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM));
                if(name == "p0_action2"){                   // Continue -> craft page (only with a selection)
                    if(gCanCount <= 0){ llRegionSayTo(llGetOwner(), 0, "[Nexus] Select at least one component first."); }
                    else llMessageLinked(LINK_THIS, TURN_CONTINUE, "CONTINUE", llGenerateKey());
                }
            }
        }
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT){ nexusMemReport(); return; }
        if(num == CANCONT) gCanCount = (integer)str;
    }
}
// REVIEW: 2026-11-18 — navigation-pure slice: only P0->P1 is wired. P4 (PAUSE/observe) and P3 (TAKE) are
//   craft-coupled and wait on the craft flow; the Continue basket gate also returns then.
