# Fiche — NX_Playback_Buttons

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_Atlas.md`, `README_playback_buttons.md`. File: `Hud/NX_Playback_Buttons.lsl`.*

---

## Role

ROOT **button-texture library** for P1 (`atlas-p1-boutons-v2`): paints the CUT/CONT/PAUSE/TAKE/DISCARD plaques on their prim faces. Driven by `NX_P1_Animation`; owns no touches, playback, or timers. Kept legacy visual script, migrated onto the convention.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_Playback_Buttons")` — refonte adoption (header/banner/SemVer + mem report); rendering logic unchanged from the legacy `MC_Playback_Buttons`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Playback_Buttons`: added `nexus_header` (banner + 970290 mem report), SemVer, renamed `NX_`. No behaviour change. |

## Dependencies

- **Driver (same ROOT)**: `NX_P1_Animation` (LOAD 918340 / STATE 918342; STATUS 918343 back).
- **Prims**: `P1_ACTION1`/`P1_ACTION2`/`P1_ACTION3` (face 1), `P1_TITLE`.
- **Textures (ROOT inv)**: `atlas-p1-boutons-v2`, `atlas-hud-titres-v2`.
- **LinksetData**: reads `mc:chop:session` / `mc:simple:craft_started` (used-state at boot — owned by NX_P1_Animation).
- **Include**: `nexus_header`.

## Interfaces

| Dir | Code | Payload | Effect |
|---|---|---|---|
| in | 918340 LOAD | texture name or "" | set active atlas (default `atlas-p1-boutons-v2`) |
| in | 918341 SHOW | JSON [prim, face, label] | paint one button |
| in | 918342 STATE | STOPPED/PLAYING/PAUSED/USED/SPOILED… | paint the CUT/TAKE/DISCARD set |
| out | 918343 STATUS | READY/LOADED/SHOWN/STATE/UNLOADED/ERROR | echo to driver |
| in | link 970290 | — | memory report |
| listen | 918344 | "buttons" (owner) | diagnostic dump |

## Open points / debt

- [ ] 2026-11-19 — still reads the `mc:*` session keys for the used-state latch; harmless (NX_P1_Animation owns them), repoint names if the LSD keys are renamed later.

## Test (in-world)

1. In ROOT with `NX_P1_Animation`: boot banner `[Nexus] NX_Playback_Buttons v0.1.0 …`; P1 buttons show their plaques (STOPPED).
2. `/918344 buttons` in local chat (owner) → diagnostic lines for the three button prims.
