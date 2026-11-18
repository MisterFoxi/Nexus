# Fiche — Nexus_StockRig

*Dev & tracking fiche. Throwaway test tool for `Nexus_Server`. File: `dev/smoketest/Nexus_StockRig.lsl`. See `dev/stock-protocol.md`.*

---

## Role

Exercises `Nexus_Server` end-to-end over `NX_STOCK` (plays fake component + fake workshop), step by step on touch, logging each reply and ticking the expected one.

## Current version

`v0.1.0 (2026-11-17)` — throwaway (layer-B behavioral test rig).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | created — 9-step scenario: register/seed, reserve-OK, commit+output, reserve-insufficient, reserve/release restore, idempotent replay, discard |

## Dependencies

- **Server**: `Nexus_Server` rezzed in the same region.
- **Channel**: `NX_STOCK = -918280`.
- **Include**: `nexus_header.lsl`.

## Scenario (touch to advance)

| # | Action | Expect |
|---|---|---|
| 0 | REGISTER A seed 5 | `QTY A 5` |
| 1 | REGISTER B seed 3 | `QTY B 3` |
| 2 | RESERVE t1 A:2 B:1 | `RES_OK t1` (A→3, B→2) |
| 3 | COMMIT t1 +OUT C=4 | `COMMIT_OK t1` (C created=4) |
| 4 | RESERVE t2 A:10 | `RES_NO t2` (avail 3, nothing reserved) |
| 5 | RESERVE t3 A:1 | `RES_OK t3` (A→2) |
| 6 | RELEASE t3 | `REL_OK t3` (A→3) |
| 7 | RESERVE t1 again | `RES_OK t1` (idempotent replay) |
| 8 | DISCARD B | `QTY B 0` |

## Open points / debt

- [ ] 2026-11-17 — auto-check is prefix-match only; QTY broadcasts from COMMIT also arrive and are logged (info, not failures). Read the log in order.
- [ ] 2026-11-17 — no timeout/fail path: a missing reply just means no PASS line — watch for it.
- [ ] 2026-11-17 — confirms tickets must be UUIDs (server casts ticket→key); rig uses `llGenerateKey()`. Carry this into the real Workshop client.
