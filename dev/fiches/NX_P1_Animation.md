# Fiche — NX_P1_Animation

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, `Hud/docs/README_Atlas.md`, `README_chop_progress.md`, `README_P4.md`. File: `Hud/NX_P1_Animation.lsl`.*

---

## Role

ROOT script of the worn HUD: P1 **playback + active-time clock**, and **bring-up of the P1 visuals** (chop atlas, button textures, progress). Loads the button/atlas/progress renderers at boot and drives button state. Migrated into the refonte from the legacy v0.10.0.

## Current version

`v0.2.2` — local START; owns `craft_started`; `p1_action3` DISCARD → `918315`; TAKE (paused) → `918370 CONTAINER`; **first Cut → `918318 CRAFTSTART`** (bench marks the prep started); **`attach` (re-wear) = RAZ** (clears the persisted cut session so the HUD opens clean).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.10.0 | 2026-11-16 | legacy (pre-refonte): START sent `918315 CRAFT_STARTED` and waited for the basket's `918317 CRAFT_STARTED` before running the clock. |
| v0.1.0 | 2026-11-18 | **migrated** (define restarted from legacy v0.10.0): added `nexus_header` (banner + mem report), SemVer. **START authorized locally** — removed the `918315/918317 CRAFT_STARTED` handshake (the removed backend never answered, so CUT used to time out). This script now **owns `mc:simple:craft_started`** (writes it on start, clears it on DISCARD_DONE). Visual/clock/observation (SNAPSHOT, PAUSE→P4) kept intact. |
| v0.2.0 | 2026-11-23 | **DISCARD split**: `p1_action3` emits `918315 DISCARD\|<gStarted>`; `p1_later` keeps the pause. Local reset on the returning `918317 DISCARD_DONE`. |
| v0.2.1 | 2026-11-25 | **re-wear RAZ**: `attach(id != NULL)` deletes `mc:chop:session` + `mc:simple:craft_started` then `llResetScript` → the HUD opens clean instead of restoring a stale cut. (LSD persists otherwise so a sim restart keeps the prep; only a re-wear forces the RAZ.) |
| v0.2.2 | 2026-11-25 | **CRAFTSTART**: the first Cut (`startPreparation`) emits `918318 CRAFTSTART` (NX_HudFace → `NX\|CRAFTSTART` → bench `state:craft="1"`), so the bench knows the prep is started (no refund on a started discard/leave). |

## Dependencies

- **Peers (same ROOT)**: `NX_Playback_Buttons` (button textures: LOAD 918340 / STATE 918342 / STATUS 918343), `NX_Atlas_Player` (chop animation: 918330–918336), `NX_Chop_Progress` (progress: 918350/918351/918353). Later: WS_Stock (will re-gate START), the craft/eval flow (918372 SNAPSHOT, 918371 finalize).
- **Buttons (no script)**: `p1_action1` (CUT/CONT), `p1_action2` (PAUSE/TAKE), `p1_action3` (**DISCARD** → `918315`), `p1_later` (pause/suspend), `p1_heat_plus/minus`, `p1_test`.
- **Peer (same ROOT)**: `NX_HudFace` consumes `918315 DISCARD`; `NX_Nearby_Controller` queries `918372 INSPECT` (observation gesture).
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
| out | 918315 DISCARD\|<started> | p1_action3 → NX_HudFace (relayed to bench) |
| out | 918370 CONTAINER | TAKE (paused) → NX_Nearby assembles `NX\|TAKE` to the bench |
| out | 918318 CRAFTSTART | first Cut → NX_HudFace → bench marks prep started |
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
- [x] 2026-11-25 — `918317 DISCARD_DONE`/`CRAFT_DONE` now emitted (NX_HudFace, on discard and on bench `NX|TAKEDONE`); `918371/918372 SNAPSHOT` legacy paths still unused.
- [ ] 2026-11-25 — re-wear RAZ clears the local cut; a cut-in-progress is not resumable after a re-wear (grind is HUD-local). The bench re-drives the right page on re-bind (held → P3).
- [ ] 2026-11-18 — `gStartTicket`/`gStartAt` now unused by START (kept for state resets); prune when the craft flow is finalized.

## Test (in-world)

1. HUD worn. At boot: banner `[Nexus] NX_P1_Animation v0.2.0 ...`; P1 buttons show their atlas textures (STOPPED state).
2. On P1, click CUT (`p1_action1`) → clock runs, button goes to PLAYING, progress advances. (No 5s "start not confirmed" timeout.)
3. Click PAUSE (`p1_action2`) → suspends and opens P4; BACK returns paused.
4. Click DISCARD (`p1_action3`) → emits `918315 DISCARD|<started>`; on the bench's `918317 DISCARD_DONE` the preparation resets and `mc:simple:craft_started` is cleared. (`p1_later` only pauses.)
