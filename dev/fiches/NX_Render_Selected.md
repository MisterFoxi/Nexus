# Fiche — NX_Render_Selected

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_product_icons.md`. File: `Hud/NX_Render_Selected.lsl`.*

---

## Role

ROOT renderer for the P0 **basket (SELECTED)** zone — same shared code as `NX_Render` with `PANEL = "SELECTED"` (tables `P0_Table2`, prims `P0_SEL_*`). Kept legacy script (`MC_Render_Selected`), migrated onto the convention.

## Current version

`v0.1.1 (SCRIPT_NAME "NX_Render_Selected")` — refonte adoption + empty-view boot init; FURWARE reset centralized in `NX_HudNav`, repaint on `fw_ready`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Render_Selected`: added `nexus_header`, SemVer, renamed `NX_`. **Empty-view boot init** so the basket table/icons start blank. No other behaviour change. |
| v0.1.1 | 2026-11-19 | **FURWARE reset centralized** (display fix): no longer issues its own `fw_reset`; relies on `NX_HudNav`'s single global reset and repaints on `fw_ready`. |

## Dependencies

- **Driver (same ROOT)**: the basket producer (VIEW 918290 / RENDER_READY 918291 with `panel == "SELECTED"`). In the refonte that producer is the **bench pick→basket flow (WS_Stock)**, not yet built — so for now the zone renders **empty** at boot and stays empty.
- **FURWARE**: `P0_Table2`. **Prims**: `P0_SEL_QTY_0..3`, `P0_SEL_ICON_0..3`, `P0_SEL_PAGE`, `P0_SEL_PREV/NEXT`.
- **Textures**: `atlas-quantites-fleches-v2`.
- **Include**: `nexus_header`.

## Open points / debt

- [ ] 2026-11-19 — no VIEW producer in the refonte (the HUD basket is gone; the basket lives in the bench). Zone stays empty until the bench pick/stock flow drives it (or the basket display is re-sited).

## Test (in-world)

1. Boot banner `[Nexus] NX_Render_Selected v0.1.0 …`; the P0 basket table is **blank**, no stray icons.
