# HUD (worn) — network refonte

> **Status (18 nov. 2026): being rebuilt as a thin face of the bench.** The old HUD
> owned the basket (`mc:simple:row`), ran per-unit `TAKE/RETURN/COMMIT` on `-918274`,
> and streamed rows up to the bench via stop-and-wait **MCW** on `-918275`
> (`MC_Selected_Controller`, `MC_Transactions`, `MC_Workshop_Link`). That backend is
> **superseded**: stock is server-authoritative, the basket + evaluation live in the
> **bench**, and the HUD only sends intents and renders. Decision record:
> `claude/socle-refonte-reseau.md` §4 (generic HUD) and §8 (reservation/provisioning).

## Keep vs replace

**Keep — the visual layer** (the real asset):
- Page rotation: P0 selection 0°, P1 craft −90°, P4 observation +90°, P3 recipient 180°
  (`MC_Turn_Z`).
- FURWARE tables + atlases + renderers (`MC_Render*`, `MC_Atlas_Player`, `MC_P1_Animation`,
  `MC_Playback_Buttons`, `MC_Chop_Progress`), button mapping, prim naming
  (`P1_Icon_n`, `P1_REMOVE_n`, `P4_Table1`, `P1_PROGRESS`, …).
- Page controllers' UX: P1 (CUT/CONT, PAUSE→P4, DISCARD + active clock), P4 (read-only
  observation), P3 (recipient), P0 (pick list).

**Replace — the backend**: `MC_Selected_Controller`, `MC_Transactions`, `MC_Workshop_Link`
and the `-918274`/`-918275` protocols. The new HUD is a thin client of `WS_Core`:
it sends picks/craft/observe/recipient intents and shows what the bench returns.

## Provisioning contract (built, bench side = WS_Core v0.1.0)

The bench gives the HUD on reservation if the player lacks it. The worn HUD **must**
answer the bench probe on `NX_HUD = -918282`:
- bench → avatar: `NX|HUDQ|<benchKey>|<model>|<version>`
- worn HUD → bench: `NX|HUDA|<model>|<version>`

The reference HUD object lives in the bench inventory, named `<model> v<X.Y.Z>`; the worn
HUD reports the same model + its own SemVer. Exact match → not re-given.

## Next steps

1. Minimal worn-HUD responder (`NX|HUDA`) so provisioning stops re-giving.
2. Thin HUD↔`WS_Core` session/intents contract (bind on reservation; pick/craft/observe/recipient).
3. Repoint the kept visual pages onto that contract.

Legacy docs for the old pages remain under `docs/` (P1/P3/P4/simple, workshop_link) as
UX/asset reference; their MCW/stock protocol sections are superseded.
