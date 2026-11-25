# Fiche — NX_P4_Controller

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_P4.md`. File: `Hud/NX_P4_Controller.lsl`.*

---

## Role

ROOT script of the worn HUD's **P4 Observation page**: handles the P1↔P4 rotation gate, requests an observation of the current preparation, and renders the result. Read-only — no stock, no craft submission. Portage of the legacy `MC_P4_Controller`, then rewired for the refonte observation flow (`WS_Eval` via `NX_Nearby_Controller`).

## Current version

`v0.2.0 (SCRIPT_NAME "NX_P4_Controller")` — rotation `918410/918411/918412`; content via `OBS_REQ`/`OBS_RESULT`; tables **`P4_Table1` = name, `P4_Table2` = description (4 rows)**; old `mc:workshop:session`/`918397/918398` path removed.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-23 | created — portage of `MC_P4_Controller` onto the convention (`nexus_header`/`nexusBoot`/`NEXUS_MEM_REPORT`). Protocol kept identical (`918411 OPEN` in → `918410 OPEN/BACK` to NX_Turn_Z + `918412 OPENED/CLOSED` to NX_P1_Animation). This restored the PAUSE→P4 **rotation** (the emitter of `918410` was missing after the MC scripts were pulled). Observation DATA still pointed at the removed `MC_Workshop_Link`. |
| v0.2.0 | 2026-11-23 | **refonte observation content**: layout → `P4_Table1` (name) / `P4_Table2` (desc, 4 rows). On open/REFRESH emit `OBS_REQ 918420` → `NX_Nearby_Controller` assembles a snapshot and asks `WS_Eval`; result arrives as `OBS_RESULT 918421` (`STATUS\|nameEsc\|descEsc`) → render. Old `mc:workshop:session` gate + `918397 TEST`/`918398` + refresh/cancel/timer dropped. |

## Dependencies

- **Same ROOT**: `NX_Turn_Z` (consumes `918410 OPEN/BACK`), `NX_P1_Animation` (sends `918411 OPEN` on PAUSE, consumes `918412`), `NX_Nearby_Controller` (`OBS_REQ 918420` → / `OBS_RESULT 918421` ←), FURWARE (text tables).
- **Channels**: none directly (all link messages; the bench round-trip is owned by NX_Nearby).
- **Prims / tables**: action prims `P4_ACTION1` (BACK) / `P4_ACTION2` (REFRESH) (aliases `P4_BACK`/`P4_REFRESH`), atlas texture `Atlas_obs`; FURWARE tables `P4_Table1` (1 row) + `P4_Table2` (4 rows × 40). Optional `P4_NEXT`/`P4_PREV` for description paging.
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Code | Effect |
|---|---|---|
| in | `918411 OPEN` (from NX_P1_Animation) | open P4: rotate + ack + request an observation |
| out | `918410 OPEN` / `BACK` (to NX_Turn_Z) | pivot P1↔P4 |
| out | `918412 OPENED` / `CLOSED` / `RESET` (to NX_P1_Animation) | navigation gate |
| out | `918420 OBS_REQ` (to NX_Nearby) | assemble a snapshot and observe |
| in | `918421 OBS_RESULT` `STATUS\|nameEsc\|descEsc` | render name (P4_Table1) + description (P4_Table2) |
| in | `918371` phase != IDLE | close (treatment started) |
| in | `918317 DISCARD_DONE`/`CRAFT_DONE` | close |
| in | `918391` output phase (`WAIT_CONTAINER`/`CLOSED`/`RELEASED`) | product page priority: set/clear `gProductPage`, close |
| in | touch `p4_action1`/`p4_back` | BACK → close + rotate back |
| in | touch `p4_action2`/`p4_refresh` | re-observe |
| in | touch `p4_next`/`p4_prev` | page the description |
| in | link `970290` | memory report |

## Behaviour notes

- **Rotation vs content are independent**: the pivot works as soon as this script runs (it emits `918410`); the content needs `NX_Nearby` + `WS_Eval` on the bench.
- **Product page priority**: `918391 WAIT_CONTAINER` sets `gProductPage` and closes P4 so a delayed observation can't rotate away from the active output page.
- Default texts: name "Current preparation", body "Open observation from the preparation page."; while waiting, "Observing the current preparation…".

## Open points / debt

- [ ] 2026-11-23 — description paging (`P4_NEXT`/`P4_PREV`) supported but those prims have no supplied atlas art; install only if descriptions exceed 4 lines.
- [ ] 2026-11-23 — `918391` output-phase handling kept from the port; validate once the NX craft output (P3) flow is wired.

## Test (in-world)

1. `P4_Table1` (1 row) + `P4_Table2` (4 rows) tables + `Atlas_obs` + `P4_ACTION1/2` present. Boot → `[Nexus] NX_P4_Controller v0.2.0 …`, no `[Observation setup]` error.
2. pick → CUT → PAUSE → P4 rotates in, `P4_Table1` = component name, `P4_Table2` = description (varies with `fab.grind`).
3. REFRESH recomputes; BACK rotates back to P1 (still paused).
