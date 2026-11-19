# Fiche — NX_Nearby_Controller

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4. File: `Hud/NX_Nearby_Controller.lsl`.*

---

## Role

ROOT controller for the P0 **nearby/available** zone: holds the scanned rows, paginates (`P0_PREV`/`P0_NEXT`), builds the page view for `NX_Render`, and handles the `P0_ADD_<n>` pick buttons. Kept legacy script, migrated onto the convention.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_Nearby_Controller")` — refonte adoption (header/banner/SemVer + mem report); logic unchanged.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Nearby_Controller`: added `nexus_header`, SemVer, renamed `NX_`. No behaviour change. |

## Dependencies

- **Peers (same ROOT)**: `NX_Scan_Refresh` (DISPLAY_* 918281–284), `NX_Render` (VIEW 918290 / RENDER_READY 918291).
- **Buttons**: `P0_PREV`, `P0_NEXT`, `P0_ADD_0..3`.
- **Include**: `nexus_header`.
- **Removed peers (refonte)**: the pick (`ADD` 918300) and the `TX_STATE` (918302) / `STOCK` (918305) feedback came from `MC_Transactions` / `MC_Selected_Controller` (removed). Those replace with the bench pick→stock flow (WS_Stock).

## Interfaces

| Dir | Code | Effect |
|---|---|---|
| in | 918281–284 DISPLAY_* | build/refresh the nearby rows |
| in | touch `P0_PREV`/`P0_NEXT` | paginate |
| in | touch `P0_ADD_<n>` | pick → emit `ADD` (918300) |
| out | 918290 VIEW (NEARBY) | page view to NX_Render |
| in | 918302 TX_STATE / 918305 STOCK | (legacy backend; no producer in refonte) |
| in | link 970290 | memory report |

## Open points / debt

- [ ] 2026-11-19 — **pick blocked**: `gTxBusy` starts TRUE and is only cleared by `TX_STATE=IDLE`, which came from the removed transaction backend. Until WS_Stock sends it, `P0_ADD_<n>` answers "wait for the transaction manager". Scan + display still work.
- [ ] 2026-11-19 — `ADD` (918300) has no consumer in the refonte; it becomes the bench pick→RESERVE intent (socle §4, stock-protocol) when WS_Stock exists.
- [ ] 2026-11-19 — REVIEW (legacy): unbounded retained HERE payloads; no sender validation on scan requests.

## Test (in-world)

1. Boot banner `[Nexus] NX_Nearby_Controller v0.1.0 …`.
2. After a refresh, the nearby components appear on P0; PREV/NEXT paginate.
3. `P0_ADD_<n>` → "wait for the transaction manager" (expected until WS_Stock).
