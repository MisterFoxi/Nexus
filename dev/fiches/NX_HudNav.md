# Fiche — NX_HudNav

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, and `Hud/docs/README_P1.md` / `README_P4.md` / `README_P3.md` / `README_simple.md`. File: `Hud/NX_HudNav.lsl`.*

---

## Role

The HUD-side **navigation hub**: detect player actions and drive page rotation. Takes over the navigation role the removed `MC_Selected_Controller` / `MC_Workshop_Link` used to play. Rotation itself stays in `MC_Turn_Z` (dumb executor); this script decides transitions and feeds it. Runs in the HUD ROOT.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_HudNav")` — navigation-pure slice: P0 → P1 on Continue (`p0_action2` → `918310 CONTINUE`).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — navigation-pure: owner touch on `p0_action2` (Continue) → `918310 CONTINUE` (fresh ticket) → MC_Turn_Z rotates to P1. No basket gate yet (returns with scan/stock). P4/P3 left out (craft-coupled). |

## Dependencies

- **Peer (same ROOT)**: `MC_Turn_Z` — consumes `918310 CONTINUE` and rotates to P1.
- **Buttons (no script)**: `p0_action2` (the P0 Continue prim).
- **Include**: `nexus_header` (no extension).
- **Replaces**: `MC_Selected_Controller`'s navigation emit (`p0_action2` → `918310`). Remove that old controller in-world so Continue is not double-driven.

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | `touch_start` | owner touch on `p0_action2` | emit Continue |
| out | link `918310` | `CONTINUE` (ticket) | MC_Turn_Z → P1 |
| in | link `970290` | — | memory report |

## Behaviour notes

- **Navigation-pure**: only P0 → P1 is wired. Return to P0 is already owned by MC_Turn_Z (P1_DISCARD touch) + the basket controller.
- **No gate**: the old Continue gate (available ingredients, `gCanContinue` in MC_Selected_Controller) is dropped for now; Continue always turns to P1. The gate returns with the scan/stock flow.

## Open points / debt

- [ ] 2026-11-18 — P1↔P4 (PAUSE/observe) and P1→P3 (TAKE/recipient) are craft-coupled (clock state / evaluation): wire when the craft flow / WS_Action exist (docs/README_P4.md, README_P3.md).
- [ ] 2026-11-18 — Continue basket gate removed until the scan/stock flow brings the selected basket back.
- [ ] 2026-11-18 — coexistence: while `MC_Selected_Controller` is still installed it also drives `p0_action2`; MC_Turn_Z dedups by ticket (harmless double-turn to the same page) until the old controller is removed.

## Test (in-world)

1. HUD worn, on P0 (local Z = 0). Touch `p0_action2` (Continue) → HUD rotates to P1 (−90°).
2. On P1, touch `P1_DISCARD` (`p1_action3`) → HUD returns to P0 (handled by MC_Turn_Z).
3. Repeat Continue → still turns to P1 (fresh ticket each time).
