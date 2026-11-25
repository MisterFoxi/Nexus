# Fiche — NX_P3_Controller

*Dev & tracking fiche. See `CONVENTIONS.md`, `Hud/docs/README_P3.md`. File: `Hud/NX_P3_Controller.lsl`.*

---

## Role

HUD **récipient-selection page** (P3) of the refonte take flow. Opens when the bench signals a product ready for collection, scans empty containers, lets the player pick one, and sends the choice to the bench. Replaces `MC_P3_Controller` (no `mc:workshop:session`, no 918390/918391/918392 MCW transfer — a single `NX|CONTAINER`).

## Current version

`v0.1.0` — open on `NX|OUTPUT WAIT_CONTAINER`, scan BLANKs, single-container selection, `NX|CONTAINER` to bench, close on `NX|TAKEDONE`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-25 | created — refonte-native P3 controller; renders via two NX_Render instances (`P3_NEAR`/`P3_SEL`), scans NX_SCAN via NX_Scan, rotation via 918391 (NX_Turn_Z). |

## Dependencies

- **Install**: HUD ROOT, beside FURWARE, `NX_Render_P3_NEAR`, `NX_Render_P3_SEL`, `NX_Scan`, `NX_Turn_Z`.
- **Bench** (`NX_HUD` -918282): in `NX|OUTPUT`, `NX|TAKEDONE`; out `NX|CONTAINER`.
- **HUD links**: `BIND_INFO 918260` (bench+session), `VIEW 918290`/`RENDER_READY 918291` (renderers), `SCAN_REFRESH 918270`→`SCAN_BEGIN/ITEM/BLANK/END 918271-4` (NX_Scan), `OUTPUT_PHASE 918391` (NX_Turn_Z rotation).
- **Include**: `nexus_header`.

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in NX_HUD | `NX\|OUTPUT\|<session>\|WAIT_CONTAINER\|<qty>` | open P3: emit 918391 WAIT_CONTAINER (rotate), scan |
| in NX_HUD | `NX\|TAKEDONE\|<newSession>\|<note>` | close P3: emit 918391 CLOSED (rotate to P0) |
| out NX_HUD | `NX\|CONTAINER\|<session>\|<containerKey>` | the chosen récipient → WS_Core collects the held product into it |
| out link | `SCAN_REFRESH 918270` ("" = NX_SCAN) | scan for BLANK containers |
| out link | `VIEW 918290` ("P3_NEAR"/"P3_SEL") | render available / selected |
| out link | `OUTPUT_PHASE 918391` | WAIT_CONTAINER→P3 / CLOSED→P0 (NX_Turn_Z) |

## Buttons

`p3_action1`/`p3_refresh` = rescan ; `p3_action2`/`p3_action` = transfer (send chosen container) ; `p3_sel_0..3` = select a NEAR row (single selection) ; `p3_sel_rem_0` = deselect ; `p3_near_prev`/`p3_near_next` = page.

## Behaviour notes

- Scan keeps only `BLANK` replies (owner-matched); ignores HERE (ingredients).
- V1 = single container per take (the SID is the stock identity; splitting across containers is a later feature).
- `gBusy` guards against a double transfer; cleared on open/close.

## Open points / debt

- [ ] 2026-11-25 — on a fresh re-bind (resume "Keep"), a tiny race between `BIND_INFO` and `NX|OUTPUT` is possible; a second Take re-opens P3 via the bench's held-guard.
- [ ] 2026-11-25 — shares NX_Scan with NEARBY (different request UUIDs); they don't scan simultaneously in practice.
