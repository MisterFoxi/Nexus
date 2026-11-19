# Fiche — NX_Scan

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` §4. File: `Hud/NX_Scan.lsl`.*

---

## Role

ROOT **component scanner** (the HUD scans; socle §4). PINGs on the craft channel, collects `HERE`/`BLANK`/`GONE` replies over a short window, and reports the result to its client link. Kept legacy script (`MC_Scan v1.0`), migrated onto the convention.

## Current version

`v0.1.0 (SCRIPT_NAME "NX_Scan")` — refonte adoption (header/banner/SemVer + mem report); scan logic unchanged.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | migrated from legacy `MC_Scan`: added `nexus_header`, SemVer, renamed `NX_`. No behaviour change. |

## Dependencies

- **Client (same ROOT)**: `NX_Scan_Refresh` (sends SCAN_REFRESH 918270, relays the BEGIN/ITEM/BLANK/END back as DISPLAY_* to `NX_Nearby_Controller`).
- **Chat channel**: `CRAFT_CHANNEL = -918273` (PING → components reply `HERE|…`/`BLANK|…`). Test channel `-918274` via payload.
- **Window**: `SCAN_SECONDS = 2.0`.
- **Include**: `nexus_header`.

## Interfaces

| Dir | Code | Payload | Effect |
|---|---|---|---|
| in | 918270 SCAN_REFRESH | optional channel, id=request | start a scan |
| out | 918271/272/273/274 | BEGIN / ITEM(HERE) / BLANK / END(item\|blank) | result to client link |
| listen | CRAFT_CHANNEL | `HERE`/`BLANK`/`GONE` | collect sources |
| in | link 970290 | — | memory report |

## Open points / debt

- [ ] 2026-11-19 — REVIEW (legacy): no source-count / payload-size budget; many sources could exhaust memory.

## Test (in-world)

1. Boot banner `[Nexus] NX_Scan v0.1.0 …`.
2. Trigger a refresh (NX_Scan_Refresh) near rezzed components → BEGIN/ITEM…/END reach NX_Nearby_Controller; P0 list fills.
