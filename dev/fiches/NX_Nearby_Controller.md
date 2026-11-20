# Fiche — NX_Nearby_Controller

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, `dev/stock-protocol.md`. File: `Hud/NX_Nearby_Controller.lsl`.*

---

## Role

ROOT controller for the P0 **nearby/available** zone: holds the scanned rows, paginates (`P0_PREV`/`P0_NEXT`), builds the page view for `NX_Render`, and turns the `P0_ADD_<n>` pick buttons into a pick sent to the bound bench. Kept legacy script, migrated onto the convention and rewired for the refonte pick flow.

## Current version

`v0.2.0 (SCRIPT_NAME "NX_Nearby_Controller")` — pick → bench (`NX|PICK` over `NX_HUD`, bench learned via `918260 BIND_INFO`); scan/display logic unchanged.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Nearby_Controller`: added `nexus_header`, SemVer, renamed `NX_`. No behaviour change (pick still went through the legacy transaction backend). |
| v0.2.0 | 2026-11-19 | **pick → bench wired** (refonte, socle §4): learns the bound bench + session from `918260 BIND_INFO` (emitted by `NX_HudFace` on BOUND); `P0_ADD_<n>` now sends `NX\|PICK\|<session>\|<sid>\|1\|<name>\|<icon>` to the bench over `NX_HUD` (refused with "HUD not bound" until bound). The legacy `TX_STATE` (918302) / `STOCK` (918305) gate is no longer on the pick path (those branches are vestigial — no producer in the refonte). |

## Dependencies

- **Peers (same ROOT)**: `NX_Scan_Refresh` (DISPLAY_* 918281–284), `NX_Render` (VIEW 918290 / RENDER_READY 918291), `NX_HudFace` (`918260 BIND_INFO` → bench + session).
- **Bench (other object, `NX_HUD` -918282)**: out `NX|PICK` on a pick; the bench's `WS_Stock` reserves and pushes the basket back.
- **Buttons**: `P0_PREV`, `P0_NEXT`, `P0_ADD_0..3`.
- **Include**: `nexus_header`.
- **Vestigial (refonte)**: `TX_STATE` (918302) and `STOCK` (918305) link handlers remain but have no producer; they came from the removed `MC_Transactions` / `MC_Selected_Controller`.

## Interfaces

| Dir | Code | Effect |
|---|---|---|
| in | 918281–284 DISPLAY_* | build/refresh the nearby rows |
| in | `918260 BIND_INFO` `<bench>\|<session>` | learn the bound bench (enables picks) |
| in | touch `P0_PREV`/`P0_NEXT` | paginate |
| in | touch `P0_ADD_<n>` | pick → `NX\|PICK` to the bench (if bound) |
| out | NX_HUD `NX\|PICK\|<session>\|<sid>\|1\|<name>\|<icon>` | pick to the bench (WS_Stock) |
| out | 918290 VIEW (NEARBY) | page view to NX_Render |
| in | 918302 TX_STATE / 918305 STOCK | legacy backend; no producer in refonte |
| in | link 970290 | memory report |

## Open points / debt

- [ ] 2026-11-19 — `ADD` (918300) legacy emit is dead; the pick intent is now `NX|PICK` to the bench. Remove the unused `ADD` code when the P0 flow is settled.
- [ ] 2026-11-19 — vestigial `TX_STATE`/`STOCK` branches + `gTxBusy` (initial TRUE) no longer gate the pick; prune them once the bench pick→stock round-trip is confirmed in-world.
- [ ] 2026-11-19 — REVIEW (legacy): unbounded retained HERE payloads; no sender validation on scan requests.

## Test (in-world)

1. Boot banner `[Nexus] NX_Nearby_Controller v0.2.0 …`.
2. After a refresh, the nearby components appear on P0; PREV/NEXT paginate.
3. HUD not yet bound → `P0_ADD_<n>` → "HUD not bound to a bench yet".
4. Bound HUD → `P0_ADD_<n>` → bench reserves (WS_Stock) and the SELECTED panel fills.
