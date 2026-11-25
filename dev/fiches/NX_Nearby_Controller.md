# Fiche — NX_Nearby_Controller

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4, `dev/stock-protocol.md`. File: `Hud/NX_Nearby_Controller.lsl`.*

---

## Role

ROOT controller for the P0 **nearby/available** zone: holds the scanned rows, paginates (`P0_PREV`/`P0_NEXT`), builds the page view for `NX_Render`, and turns the `P0_ADD_<n>` pick buttons into a pick sent to the bound bench. Kept legacy script, migrated onto the convention and rewired for the refonte pick flow.

## Current version

`v0.4.0` — pick → bench (`NX|PICK`); NEARBY re-scan; observation assembler (`NX|OBSERVE`); **TAKE assembler**: on `918370 CONTAINER` (P1 TAKE while paused) reuses the same INSPECT+snapshot assembly and sends `NX|TAKE` (+ the picked sources' object keys `srcKeys`, for the bench give path).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Nearby_Controller`: added `nexus_header`, SemVer, renamed `NX_`. No behaviour change (pick still went through the legacy transaction backend). |
| v0.2.0 | 2026-11-19 | **pick → bench wired** (refonte, socle §4): learns the bound bench + session from `918260 BIND_INFO` (emitted by `NX_HudFace` on BOUND); `P0_ADD_<n>` now sends `NX\|PICK\|<session>\|<sid>\|1\|<name>\|<icon>` to the bench over `NX_HUD` (refused with "HUD not bound" until bound). The legacy `TX_STATE` (918302) / `STOCK` (918305) gate is no longer on the pick path (those branches are vestigial — no producer in the refonte). |
| v0.2.1 | 2026-11-20 | **NEARBY availability fix**: on `NX\|RESCAN\|<session>` emit `REFRESH_REQUEST "KEEP_PAGE"` → fresh scan refreshes the shown qty (the displayed number came from the scan snapshot and was never updated). Re-scan, not local decrement — only a scan reads the authoritative server qty. |
| v0.3.0 | 2026-11-23 | **observation assembler** (P4 content). Mirrors the picked set from `NX\|BASKET`. On `OBS_REQ 918420` → `918372 INSPECT`; on `918399 OK\|elapsed\|heat`, `fab.grind = llRound(elapsed)` capped 10, joins basket sids with live `HERE` scan into the snapshot, sends `NX\|OBSERVE`. Relays `NX\|OBSERVED` to P4 as `OBS_RESULT 918421`. |
| v0.4.0 | 2026-11-25 | **TAKE assembler**: `918370 CONTAINER` (from NX_P1_Animation, TAKE while paused) sets take-mode and runs the same INSPECT → snapshot assembly, then sends `NX\|TAKE\|<session>\|<nameEsc>\|<snapshotEsc>\|<srcKeysEsc>` to the bench (WS_Take). `srcKeys` = the picked sources' object keys (HERE field 1), carried alongside the aggregated snapshot for the give/harvest path. OBSERVE path unchanged. |

## Dependencies

- **Peers (same ROOT)**: `NX_Scan_Refresh` (DISPLAY_* 918281–284), `NX_Render` (VIEW 918290 / RENDER_READY 918291), `NX_HudFace` (`918260 BIND_INFO` → bench + session), `NX_P4_Controller` (`OBS_REQ 918420` → / `OBS_RESULT 918421` ←), `NX_P1_Animation` (`918372 INSPECT` → / `918399` ← for the cut gesture).
- **Bench peer (`NX_HUD`)**: `WS_Eval` — out `NX|OBSERVE`, in `NX|OBSERVED`.
- **Bench (other object, `NX_HUD` -918282)**: out `NX|PICK` on a pick; in `NX|RESCAN` (from `WS_Stock` after a server availability change) → re-scan NEARBY. The bench's `WS_Stock` reserves and pushes the basket back.
- **Buttons**: `P0_PREV`, `P0_NEXT`, `P0_ADD_0..3`.
- **Include**: `nexus_header`.
- **Vestigial (refonte)**: `TX_STATE` (918302) and `STOCK` (918305) link handlers remain but have no producer; they came from the removed `MC_Transactions` / `MC_Selected_Controller`.

## Interfaces

| Dir | Code | Effect |
|---|---|---|
| in | 918281–284 DISPLAY_* | build/refresh the nearby rows |
| in | `918260 BIND_INFO` `<bench>\|<session>` | learn the bound bench (enables picks) |
| in | NX_HUD `NX\|RESCAN\|<session>` | server qty changed → emit `REFRESH_REQUEST KEEP_PAGE` (fresh scan) |
| in | NX_HUD `NX\|BASKET\|<session>\|…` | mirror the picked set (sid+qty) for the snapshot |
| in | link `918420 OBS_REQ` | P4 asks to observe → INSPECT the gesture, then assemble + send `NX\|OBSERVE` |
| out | link `918372 INSPECT` / in `918399` | read elapsed/heat from NX_P1_Animation |
| out | NX_HUD `NX\|OBSERVE\|<session>\|<nameEsc>\|<snapshotEsc>` | snapshot to WS_Eval |
| in | NX_HUD `NX\|OBSERVED\|<session>\|<STATUS>\|<descEsc>\|<nameEsc>` | result from WS_Eval |
| out | link `918421 OBS_RESULT` (`STATUS\|nameEsc\|descEsc`) | result to P4 |
| in | touch `P0_PREV`/`P0_NEXT` | paginate |
| in | link `918370 CONTAINER` | P1 TAKE (paused) → take-mode INSPECT + assemble → `NX\|TAKE` |
| out | NX_HUD `NX\|TAKE\|<session>\|<nameEsc>\|<snapshotEsc>\|<srcKeysEsc>` | snapshot + source keys to WS_Take |
| in | touch `P0_ADD_<n>` | pick → `NX\|PICK` to the bench (if bound) |
| out | NX_HUD `NX\|PICK\|<session>\|<sid>\|1\|<name>\|<icon>` | pick to the bench (WS_Stock) |
| out | 918290 VIEW (NEARBY) | page view to NX_Render |
| in | 918302 TX_STATE / 918305 STOCK | legacy backend; no producer in refonte |
| in | link 970290 | memory report |

## Open points / debt

- [ ] 2026-11-19 — `ADD` (918300) legacy emit is dead; the pick intent is now `NX|PICK` to the bench. Remove the unused `ADD` code when the P0 flow is settled.
- [ ] 2026-11-19 — vestigial `TX_STATE`/`STOCK` branches + `gTxBusy` (initial TRUE) no longer gate the pick; prune them once the bench pick→stock round-trip is confirmed in-world.
- [ ] 2026-11-19 — REVIEW (legacy): unbounded retained HERE payloads; no sender validation on scan requests.
- [ ] 2026-11-23 — the observation action header is `fab.grind` hardcoded (cutting_board). For mortar/cauldron, derive the axis from the bench's `Action`/`HeatAction`/`DurationAction` (`ws:cfg:*`) like `Workshop_Config`.
- [ ] 2026-11-23 — snapshot joins basket sids with the current scan; a picked component out of scan range yields no group for it (edge case).

## Test (in-world)

1. Boot banner `[Nexus] NX_Nearby_Controller v0.2.0 …`.
2. After a refresh, the nearby components appear on P0; PREV/NEXT paginate.
3. HUD not yet bound → `P0_ADD_<n>` → "HUD not bound to a bench yet".
4. Bound HUD → `P0_ADD_<n>` → bench reserves (WS_Stock) and the SELECTED panel fills.
