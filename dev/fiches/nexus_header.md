# Fiche — nexus_header

*Dev & tracking fiche. See `CONVENTIONS.md`. Shared include, not a standalone script.*

---

## Role

Shared `#include` providing the standard boot banner and the on-demand memory report for every Nexus script.

## Current version

`v0.1.0 (2026-11-17)` — preproc: host script defines `SCRIPT_NAME` / `SCRIPT_VERSION` / `SCRIPT_DATE` before including.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | created — banner + memory report + `#ifndef` guard |

## Dependencies

- **Scripts**: `#include`d by every Nexus script.
- **Channels**: none.
- **LinksetData keys** read / written: none.
- **Reserved link code**: `970290` = `NEXUS_MEM_REPORT` (on-demand memory report, whole linkset).

## Interfaces (messages)

| Dir | Code / verb | Payload | Trigger / effect |
|---|---|---|---|
| — | `nexusBoot()` | — | called first in `state_entry()`; prints boot banner |
| in | link `970290` | any | host routes it to `nexusMemReport()` → prints free + observed min |
| out | `llOwnerSay` | — | banner line (boot) and report line (on demand) |

## State & persistence

- Stateless helpers + one global `gNexusMinFree` (lowest free memory observed). Nothing persisted.

## Memory

- Negligible footprint; this file *is* the measurement tool (`nexusMem()`).

## Open points / debt

> Every `// REVIEW:` in the code is copied here, dated. Nothing gets lost.

- [x] 2026-11-17 — preprocessor + `#ifndef` guard confirmed supported by the official SL VSCode plugin (docs); include paths default to `.`, `./include/`, `**/include/`.
- [x] 2026-11-17 — canonical home set to `include/nexus_header.lsl` (resolves via default include paths).
- [x] 2026-11-17 — behavioral check still pending: run `dev/smoketest/Nexus_SmokeTest.lsl` in-world (banner prints, free sane, memory report on touch).
- [x] 2026-11-17 — remove the redundant copy at `dev/smoketest/nexus_header.lsl` once the canonical `include/` copy is in place.
