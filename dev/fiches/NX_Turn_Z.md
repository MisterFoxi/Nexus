# Fiche — NX_Turn_Z

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, and `Hud/docs/README_P4.md` / `README_P3.md`. File: `Hud/NX_Turn_Z.lsl`.*

---

## Role

ROOT **page-rotation executor** for the worn HUD — kept visual-layer script, adapted to the refonte. Dumb rotator: turns the root prim's local Z to a page, preserving X/Y. Navigation LOGIC lives in `NX_HudNav`; this script only reacts to rotation triggers. Pages: P0 = 0°, P1 = −90°, P4 = +90°, P3 = 180°.

## Current version

`v0.1.4 (SCRIPT_NAME "NX_Turn_Z")` — legacy rotator brought onto the convention (header/banner/SemVer); dead-store P4 gate removed.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | refonte adoption of the kept legacy rotator: added `nexus_header` (banner + mem report), SemVer. **Removed** the `918410 OPEN` gate that read the now-dead store `mc:workshop:session` (gating moves to the craft flow). Rotation behaviour otherwise unchanged. |
| v0.1.1 | 2026-11-19 | **default page P0**: force `pageZero()` + clear page flags at `state_entry`, `attach` (wear) and `on_rez`, so the worn HUD never opens on a stale page (bug: opened on P4). |
| v0.1.2 | 2026-11-19 | P0 reset made robust on wear: the `attach` rotation was clobbered by the viewer, so a one-shot timer re-applies `pageZero()` ~0.3 s after attach/rez/boot. |
| v0.1.3 | 2026-11-19 | **absolute 2D rotations**: pages are absolute local Z rotations (X/Y = 0), P0 = `ZERO_ROTATION`. Stopped reading `llGetLocalRot()` and preserving X/Y — stale/attach-time X/Y noise was offsetting the page (HUD opened on P4). |
| v0.1.4 | 2026-11-19 | **correct page angles**: P0 home = 270, P1 cut = 180, P3 transfer = 90, P4 observation = 0 (absolute). The earlier P0=0 was wrong — Z=0 is observation, which is why the HUD opened on P4. Dropped the attach-timer (the reset applies fine; the bug was the angle, not a clobber). |

## Dependencies

- **Peer (same ROOT)**: `NX_HudNav` (sends `918310 CONTINUE`); later the craft/output scripts for `918410`, `918391`, `918317`.
- **Buttons (no script)**: owns the owner touch on `p1_action3` (P1_DISCARD) → P0.
- **Prims**: rotates `LINK_ROOT`.
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | link `918310` | `CONTINUE` (ticket) | rotate to P1 (−90°) |
| in | link `918410` | `OPEN` / `BACK` | rotate to P4 (+90°) / back to P1 |
| in | link `918391` | `WAIT_CONTAINER` / `CLOSED` / `RELEASED` (\|…) | P3 (180°) / P0 |
| in | link `918317` | `DISCARD_DONE` / `CRAFT_DONE` (ticket) | P0 (once per ticket) |
| in | `touch_start` | owner touch `p1_action3` | P0 directly (when not on the product page) |
| out | link `918390` | `STATUS` | ask the output state at boot |
| in | link `970290` | — | memory report |

## Behaviour notes

- **Dumb executor**: holds no craft/session state of its own beyond last-ticket dedup and two page flags (`gProductPage`, `gObservationPage`).
- **P4 gate removed**: `918410 OPEN` no longer reads `mc:workshop:session` (dead store); with the backend gone the gate was already a no-op. Craft-state gating for observation now belongs to the craft flow.
- Product page (P3) and discard-to-P0 behaviour unchanged from the legacy script.

## Open points / debt

- [ ] 2026-11-18 — only the most recent Continue ticket is remembered; a delayed replay of an older ticket can rotate again (carried over from legacy).
- [ ] 2026-11-18 — `918410` / `918391` are not yet fed by any refonte script (craft/output not built); only `918310` from NX_HudNav drives it today.
- [ ] 2026-11-18 — `llSetText`/floating-text ownership: not used here, but the shared-text consolidation (WS_HMI analogue) is a HUD-side concern later.

## Test (in-world)

1. HUD worn on P0. `918310 CONTINUE` (via NX_HudNav / Continue button) → rotate to P1.
2. Touch `p1_action3` on P1 → back to P0.
3. Banner at boot: `[Nexus] NX_Turn_Z v0.1.0 (...) | heap … | lsd …`.
