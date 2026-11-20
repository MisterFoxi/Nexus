# Fiche — NX_Scan_Refresh

*Dev & tracking fiche. See `CONVENTIONS.md`. File: `Hud/NX_Scan_Refresh.lsl`.*

---

## Role

ROOT bridge for the P0 Refresh button: a touch on `P0_ACTION1` (or a `REFRESH_REQUEST`) starts a scan via `NX_Scan`, relays its `SCAN_*` replies to `NX_Nearby_Controller` as `DISPLAY_*` (code + 10), and aborts after a 10 s timeout. Kept legacy script, migrated onto the convention.

## Current version

`v0.1.1 (SCRIPT_NAME "NX_Scan_Refresh")` — scan channel aligned to `NX_SCAN -918281`; relay logic unchanged.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Scan_Refresh`: added `nexus_header` + a `state_entry(){ nexusBoot(); }`, SemVer, renamed `NX_`. No behaviour change. |
| v0.1.1 | 2026-11-19 | **scan channel fixed**: the channel passed to `NX_Scan` is now `NX_SCAN -918281` (was `-918274`), matching `NX_Scan` — part of the empty-list / display fix. |

## Dependencies

- **Peers (same ROOT)**: `NX_Scan` (SCAN_REFRESH 918270 → SCAN_BEGIN/ITEM/BLANK/END 918271–274); `NX_Nearby_Controller` (receives DISPLAY_BEGIN/ITEM/BLANK/END 918281–284, i.e. SCAN_* + 10).
- **Button**: `P0_ACTION1` (Refresh).
- **Scan channel**: `NX_SCAN -918281` (passed to NX_Scan).
- **Include**: `nexus_header`.

## Interfaces

| Dir | Code | Effect |
|---|---|---|
| in | touch `P0_ACTION1` / link 918287 REFRESH_REQUEST | start a refresh |
| out | 918270 SCAN_REFRESH | ask NX_Scan |
| in | 918271–274 (from NX_Scan) | relay as 918281–284 to the controller |
| out | 918285 DISPLAY_ABORT | on 10 s timeout |
| in | link 970290 | memory report |

## Open points / debt

- [ ] 2026-11-19 — REVIEW (legacy): a matching ticket alone is trusted; sender link not validated.

## Test (in-world)

1. Boot banner `[Nexus] NX_Scan_Refresh v0.1.0 …`.
2. Touch `P0_ACTION1` → scan runs; if no complete result in 10 s → owner warning.
