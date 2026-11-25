# Fiche — NX_Render_P3_SEL

*Dev & tracking fiche. See `NX_Render.md`. File: `Hud/NX_Render_P3_SEL.lsl`.*

---

## Role

Rendering instance of the shared `NX_Render` logic, preset to **`PANEL = "P3_SEL"`** — the one-row selected-container table of the récipient page (P3). Install in HUD ROOT beside FURWARE and `NX_P3_Controller`.

## Current version

`v0.1.2` — copy of `NX_Render` v0.1.2 with `SCRIPT_NAME`/`PANEL` fixed.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.2 | 2026-11-25 | created — renders `P3_Table2` + `P3_Sel_QTY_*`/`P3_Sel_Icon_*` (first row only). |

## Dependencies

- `VIEW 918290` ("P3_SEL") from `NX_P3_Controller`; `RENDER_READY 918291`; FURWARE.
- **Include**: `nexus_header`.

## Notes

Panel logic in `NX_Render`; P3_SEL keeps only row 0. See `NX_Render.md`.
