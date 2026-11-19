# Fiche — NX_Chop_Progress

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_chop_progress.md`. File: `Hud/NX_Chop_Progress.lsl`.*

---

## Role

ROOT **progress-cursor renderer** for P1 (`P1_CURSOR`): moves the cursor along the gradient to reflect active seconds. Self-initializing; timing belongs to `NX_P1_Animation`. Kept legacy visual script, migrated onto the convention.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_Chop_Progress")` — refonte adoption (header/banner/SemVer + mem report); logic unchanged from the legacy `MC_Chop_Progress`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Chop_Progress`: added `nexus_header` (banner + 970290 mem report), SemVer, renamed `NX_`. No behaviour change. |

## Dependencies

- **Driver (same ROOT)**: `NX_P1_Animation` (LOAD 918350 / SHOW 918351; STATUS 918353 back).
- **Prim**: `P1_CURSOR` (face 1).
- **Texture (ROOT inv)**: `curseur-progression-p1-v1`.
- **Include**: `nexus_header`.
- **Tunable**: `FULL_SECONDS = 10.0` (full-scale time).

## Interfaces

| Dir | Code | Payload | Effect |
|---|---|---|---|
| in | 918350 LOAD | texture name or "" | init cursor surface (default texture) |
| in | 918351 SHOW | seconds / IDLE / SPOILED | move cursor (fraction of FULL_SECONDS) |
| out | 918353 STATUS | READY/LOADED/SHOWN/UNLOADED/ERROR | echo to driver |
| in | link 970290 | — | memory report |

## Open points / debt

- [ ] 2026-11-19 — `FULL_SECONDS` is a fixed visual scale; the real craft duration model is defined elsewhere (craft flow).

## Test (in-world)

1. In ROOT with `NX_P1_Animation`: boot banner `[Nexus] NX_Chop_Progress v0.1.0 …`; cursor sits at IDLE (zero).
2. During a running craft the cursor advances; DISCARD → IDLE.
