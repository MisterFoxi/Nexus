# Fiche — MC_P1_Animation

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, `Hud/docs/README_Atlas.md`, `README_chop_progress.md`, `README_P4.md`. File: `Hud/MC_P1_Animation.lsl`.*

---

## Role

ROOT script of the worn HUD: P1 **playback + active-time clock**, and **bring-up of the P1 visuals** (chop atlas, button textures, progress). Loads the button/atlas/progress renderers at boot and drives button state. Migrated into the refonte from the legacy v0.10.0.

## Current version

`v0.11.0 (SCRIPT_NAME "MC_P1_Animation")` — refonte migration: convention header/banner; craft START authorized locally (no removed-backend ACK); owns the `craft_started` flag.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.10.0 | 2026-11-16 | legacy (pre-refonte): START sent `918315 CRAFT_STARTED` and waited for the basket's `918317 CRAFT_STARTED` before running the clock. |
| v0.11.0 | 2026-11-18 | **migrated**: added `nexus_header` (banner + mem report), SemVer. **START authorized locally** — removed the `918315/918317 CRAFT_STARTED` handshake (the removed backend never answered, so CUT used to time out). This script now **owns `mc:simple:craft_started`** (writes it on start, clears it on DISCARD_DONE). Visual/clock/observation (SNAPSHOT, PAUSE→P4) kept intact. |

## Dependencies

- **Peers (same ROOT)**: `MC_Playback_Buttons` (button textures: LOAD 918340 / STATE 918342 / STATUS 918343), `MC_Atlas_Player` (chop animation: 918330–918336), `MC_Chop_Progress` (progress: 918350/918351/918353). Later: WS_Stock (will re-gate START), the craft/eval flow (918372 SNAPSHOT, 918371 finalize).
- **Buttons (no script)**: `p1_action1` (CUT/CONT), `p1_action2` (PAUSE/TAKE), `p1_action3`/`p1_later` (suspend), `p1_heat_plus/minus`, `p1_test`.
- **LinksetData**: `mc:chop:session` (own clock/heat state), `mc:simple:craft_started` (now owned here). Still reads the dead `mc:workshop:session` in the craft-flow paths (debt).
- **Include**: `nexus_header` (no extension).

## Interfaces (main)

| Dir | Code | Meaning |
|---|---|---|
| in | touch `p1_action1/2/3`, heat, test | player actions |
| out | 918330/918331/918332/918334/918335 | atlas player LOAD/PLAY/REST/PAUSE/RESUME |
| out | 918340 / 918342 | buttons LOAD / STATE |
| out | 918350 / 918351 | progress LOAD / show |
| out | 918411 OPEN | ask P4 observation (on PAUSE) |
| out | 918370 CONTAINER | TAKE (paused) → output path |
| out | 918394 | cosmetic activity flag 0/1 |
| in | 918360 START/CONT/STOP | explicit action requests |
| in | 918310 CONTINUE | navigation → suspend (not a new prep) |
| in | 918317 DISCARD_DONE/CRAFT_DONE | reset the preparation, clear the flag |
| in | 918372 SNAPSHOT/INSPECT/UNFREEZE | craft-flow eval interface (kept for later) |
| in | link 970290 | memory report |

## Behaviour notes

- **Buttons textured at boot**: `state_entry` → `loadAtlas()` + `loadButtons()` + `loadProgress()`; independent of any craft. Installing this script is what gives the P1 buttons their textures.
- **Local START** (refonte): CUT starts the clock immediately — no basket ACK. `gStarted` + `mc:chop:session` persist the preparation; `mc:simple:craft_started` is set here.
- **PAUSE** (p1_action2 while active) checkpoints the clock and opens P4 (918411); TAKE (paused) sends CONTAINER on the output path.

## Open points / debt

- [ ] 2026-11-18 — START has no stock gate yet; WS_Stock must re-gate it (reserve/commit) when the stock flow exists. Today START always succeeds locally.
- [ ] 2026-11-18 — still reads the dead store `mc:workshop:session` in the SNAPSHOT/finalize paths; harmless (empty → not finalizing) but to be repointed with the craft/eval flow.
- [ ] 2026-11-18 — `918317 DISCARD_DONE` / `918371 finalize` / `918372 SNAPSHOT` have no refonte emitter yet (craft/output not built); kept for when that flow is wired.
- [ ] 2026-11-18 — `gStartTicket`/`gStartAt` now unused by START (kept for state resets); prune when the craft flow is finalized.

## Test (in-world)

1. HUD worn. At boot: banner `[Nexus] MC_P1_Animation v0.11.0 ...`; P1 buttons show their atlas textures (STOPPED state).
2. On P1, click CUT (`p1_action1`) → clock runs, button goes to PLAYING, progress advances. (No 5s "start not confirmed" timeout.)
3. Click PAUSE (`p1_action2`) → suspends and opens P4; BACK returns paused.
4. Click DISCARD (`p1_action3`) → preparation resets, `mc:simple:craft_started` cleared.
