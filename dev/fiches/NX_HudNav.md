# Fiche — NX_HudNav

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, and `Hud/docs/README_P1.md` / `README_P4.md` / `README_P3.md` / `README_simple.md`. File: `Hud/NX_HudNav.lsl`.*

---

## Role

The HUD-side **navigation hub + global FURWARE init**: detect player actions and drive page rotation, and own the single FURWARE reset for the whole HUD. Takes over the navigation role the removed `MC_Selected_Controller` / `MC_Workshop_Link` used to play. Rotation itself stays in `NX_Turn_Z` (dumb executor); this script decides transitions and feeds it. Runs in the HUD ROOT.

## Current version

`v0.3.0 (SCRIPT_NAME "NX_HudNav")` — navigation (P0 → P1 on Continue) with the basket gate restored (`CANCONT`), plus the **single global FURWARE reset** issued once at install.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — navigation-pure: owner touch on `p0_action2` (Continue) → `918310 CONTINUE` (fresh ticket) → NX_Turn_Z rotates to P1. No basket gate yet. P4/P3 left out (craft-coupled). |
| v0.2.0 | 2026-11-19 | **Continue basket gate restored**: reads the basket count on `918261 CANCONT` (from `NX_Selected_Controller`); Continue is blocked (owner warning "select at least one component first") while the count is 0. |
| v0.3.0 | 2026-11-19 | **centralized FURWARE reset** (part of the display fix "Fixing tables cleaning"): a single `fw_reset` is broadcast to `LINK_SET` once at `state_entry` and on `attach` (= install), replacing the per-renderer resets. A global reset makes FURWARE re-read the box layout and re-emit `fw_ready`, on which every renderer repaints; doing it once avoids the stale/garbled tables caused by concurrent per-script resets. |

## Dependencies

- **Peer (same ROOT)**: `NX_Turn_Z` — consumes `918310 CONTINUE` and rotates to P1.
- **Peers (all renderers, same ROOT)**: every `NX_Render*` listens for the `fw_reset` broadcast + FURWARE's `fw_ready`; NX_HudNav is the sole issuer of `fw_reset`.
- **Peer (same ROOT)**: `NX_Selected_Controller` → `918261 CANCONT` (basket count for the Continue gate).
- **Buttons (no script)**: `p0_action2` (the P0 Continue prim).
- **Include**: `nexus_header` (no extension).
- **Replaces**: `MC_Selected_Controller`'s navigation emit (`p0_action2` → `918310`) and its per-renderer FURWARE resets. Remove that old controller in-world so Continue is not double-driven.

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | `touch_start` | owner touch on `p0_action2` | emit Continue (if basket not empty) |
| out | link `918310` | `CONTINUE` (ticket) | NX_Turn_Z → P1 |
| out | link `0` / id `fw_reset` (LINK_SET) | — | one global FURWARE reset at install |
| in | link `918261 CANCONT` | `<count>` | basket size → Continue gate |
| in | link `970290` | — | memory report |

## Behaviour notes

- **One FURWARE reset, globally**: `fw_reset` is expensive (FURWARE unavailable a few seconds) and global, so it is issued once here — at `state_entry` and on wear (`attach != NULL_KEY`) — never per-renderer. After it, FURWARE emits `fw_ready` and every renderer repaints (empty).
- **Navigation-pure**: only P0 → P1 is wired. Return to P0 is owned by NX_Turn_Z (P1_DISCARD touch) + the basket controller.
- **Continue gate**: Continue turns to P1 only when `gCanCount > 0`; otherwise the owner is told to select a component first.

## Open points / debt

- [ ] 2026-11-18 — P1↔P4 (PAUSE/observe) and P1→P3 (TAKE/recipient) are craft-coupled (clock state / evaluation): wire when the craft flow / WS_Action exist (docs/README_P4.md, README_P3.md).
- [ ] 2026-11-19 — coexistence: while `MC_Selected_Controller` is still installed it also drives `p0_action2` and may issue its own FURWARE reset; remove it so Continue is single-driven and only NX_HudNav resets FURWARE.

## Test (in-world)

1. Wear the HUD → single FURWARE reset; after `fw_ready` every panel repaints blank (no stale rows).
2. HUD worn, on P0 (local Z = 0), basket empty → touch `p0_action2` (Continue) → warning, no rotation.
3. Pick a component (basket count > 0) → touch Continue → HUD rotates to P1 (−90°).
4. On P1, touch `P1_DISCARD` (`p1_action3`) → HUD returns to P0 (handled by NX_Turn_Z).
