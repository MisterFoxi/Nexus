# Fiche — NX_Render

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_product_icons.md`, `README_Atlas.md`. File: `Hud/NX_Render.lsl`.*

---

## Role

ROOT **shared panel renderer** (one instance per panel via the `PANEL` var: `NEARBY`, `SELECTED`, `P3_NEAR`, `P3_SEL`). Paints the FURWARE text rows + quantity/icon atlas cells + page/static controls for its panel. Installed beside FURWARE. Kept legacy script, migrated onto the convention. This migration covers the **NEARBY** instance (P0 available zone); the SELECTED/P3 instances are separate copies, migrated with their pages.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_Render")` — refonte adoption (header/banner/SemVer + mem report); rendering logic unchanged.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Render`: added `nexus_header`, SemVer, renamed `NX_`. No behaviour change. Set `PANEL = "NEARBY"` for the P0 available instance. |

## Dependencies

- **Driver (same ROOT)**: `NX_Nearby_Controller` (VIEW 918290 / RENDER_READY 918291) for the NEARBY instance.
- **FURWARE**: text tables `P0_Table1` (NEARBY) via `fw_conf:`/`fw_data:` link messages.
- **Prims**: `P0_QTY_0..3`, `P0_Icon_0..3`, `P0_PAGE`, `P0_PREV`, `P0_NEXT`, `P0_TITLE`, `P0_ACTION1/2`.
- **Textures (ROOT inv)**: `atlas-quantites-fleches-v2`, `atlas-hud-titres-v2`, `atlas-hud-actions-v2`; default icon key.
- **Include**: `nexus_header`.

## Interfaces

| Dir | Code | Effect |
|---|---|---|
| in | 918290 VIEW (matching PANEL) | paint the page (4 rows + page cell) |
| in | `fw_ready` | re-render after FURWARE is ready |
| out | `fw_conf:`/`fw_data:` | FURWARE table config + data |
| out | 918291 RENDER_READY | announce panel ready |
| in | link 970290 | memory report |

## Open points / debt

- [ ] 2026-11-19 — the SELECTED / P3_NEAR / P3_SEL instances are still the legacy `MC_Render_Selected` / `MC_Render_P3_*` copies; migrate with the basket (bench) and P3.
- [ ] 2026-11-19 — REVIEW (legacy): view decoding has no field-length budget; same-root producers must bound the payload.

## Test (in-world)

1. Boot banner `[Nexus] NX_Render v0.1.0 …`; P0 title/action cells painted, table present.
2. On VIEW from NX_Nearby_Controller, rows show names + quantity cells + icons; page cell reflects the current page.
