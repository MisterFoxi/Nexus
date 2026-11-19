# Fiche — NX_Atlas_Player

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_Atlas.md`. File: `Hud/NX_Atlas_Player.lsl`.*

---

## Role

ROOT **frame-animation player** for the P1 chop display (`P1_CHOP_ATLAS`): cycles atlas cells for PLAY/PAUSE/REST and tracks active time. Driven by `NX_P1_Animation`. Kept legacy visual script, migrated onto the convention.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_Atlas_Player")` — refonte adoption (header/banner/SemVer + mem report); logic unchanged from the legacy `MC_Atlas_Player`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Atlas_Player`: added `nexus_header` (banner + 970290 mem report), SemVer, renamed `NX_`. No behaviour change. |

## Dependencies

- **Driver (same ROOT)**: `NX_P1_Animation` (LOAD 918330 / PLAY 918331 / REST 918332 / PAUSE 918334 / RESUME 918335 / ELAPSED 918336; STATUS 918333 back).
- **Prim**: `P1_CHOP_ATLAS` (face 1), grid 3×1, frames 1..2, 4 FPS.
- **Texture (ROOT inv)**: `atlas_chop`.
- **Include**: `nexus_header`.

## Interfaces

| Dir | Code | Payload | Effect |
|---|---|---|---|
| in | 918330 LOAD | texture name | bind the display, show REST frame |
| in | 918331/918332/918334/918335 | — | PLAY / REST / PAUSE / RESUME |
| in | 918336 ELAPSED | — | reply active seconds |
| out | 918333 STATUS | LOADED/PLAYING/PAUSED/REST/ELAPSED/ERROR | echo to driver |
| in | link 970290 | — | memory report |

## Open points / debt

- [ ] 2026-11-19 — REVIEW (carried from legacy): the active target changes before full validation; a failed LOAD can redirect existing playback.

## Test (in-world)

1. In ROOT with `NX_P1_Animation`: boot banner `[Nexus] NX_Atlas_Player v0.1.0 …`; chop display at REST frame.
2. CUT on P1 → frames cycle; PAUSE → freezes; DISCARD/REST → back to REST.
