# Fiche — NX_Render_P3_NEAR

*Dev & tracking fiche. See `NX_Render.md`. File: `Hud/NX_Render_P3_NEAR.lsl`.*

---

## Role

Rendering instance of the shared `NX_Render` logic, preset to **`PANEL = "P3_NEAR"`** — the available-containers table of the récipient page (P3). Install in HUD ROOT beside FURWARE and `NX_P3_Controller`.

## Current version

`v0.1.2` — copy of `NX_Render` v0.1.2 with `SCRIPT_NAME`/`PANEL` fixed.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.2 | 2026-11-25 | created — one-file-per-instance convention (like `NX_Render_Selected`). Renders `P3_Table1` + `P3_QTY_*`/`P3_Icon_*`, controls `P2_TITLE`/`P2_ACTION1`/`P2_ACTION2`. |

## Dependencies

- `VIEW 918290` ("P3_NEAR") from `NX_P3_Controller`; `RENDER_READY 918291`; FURWARE (`fw_conf`/`fw_data`).
- **Include**: `nexus_header`.

## Notes

All panel logic lives in `NX_Render`; this file only pins `PANEL`. See `NX_Render.md` for the view format (18 fields) and atlas handling.
