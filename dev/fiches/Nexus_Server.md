# Fiche — Nexus_Server

*Dev & tracking fiche. See `CONVENTIONS.md` and `dev/stock-protocol.md`. File: `Server/nexus_server.lsl`.*

---

## Role

The single in-sim authority on ingredient/product **quantities**: registers SIDs, holds reservations (reserve/commit/release) on behalf of bench crafts, and recovers its ledger after restart.

## Current version

`v0.2.0 (SCRIPT_NAME "Nexus_Server")` — reserve/commit/release, **no TTL** (the bench owns the craft), declarative RESERVE.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | created — REGISTER/QTY, RESERVE/COMMIT/RELEASE (ticket, held-subtracted-at-reserve), DISCARD, DISCOVER, 30 s TTL sweep; `NULL_KEY` type fix |
| v0.2.0 | 2026-11-17 | temporal/pause review: **removed TTL + auto-release sweep** (reservation held by the bench until COMMIT/RELEASE); **RESERVE is now declarative** (set the ticket's held set = desired basket → idempotent, handles pick/unpick by delta); RELEASE = whole ticket; ticket record `state|pairs` (dropped the deadline field) |

## Dependencies

- **Scripts**: none in-linkset (standalone prim). Talks to `Component`/`Workshop` over region say.
- **Channel**: `NX_STOCK = -918280`.
- **LinksetData**: `sv:q:<sid>` (`avail|expiry|owner|dnaHash`), `sv:t:<ticket>` (`state|sid:u^…`, state R/C/X). Persistent.
- **Include**: `nexus_header.lsl`.

## Interfaces (messages)

| Dir | Verb | Payload | Effect |
|---|---|---|---|
| in | `REGISTER` | sid, owner, dnaHash, expiry, initQty | seed once / reconcile meta → `QTY` |
| out | `QTY` | sid, available | authoritative available (total − reserved), broadcast |
| in | `DISCOVER` | owner, name | → `SERVER` if match |
| in | `RESERVE` | ticket, `sid:u^…` | **declarative** set-reconcile → `RES_OK` / `RES_NO|sid:avail^…` |
| in | `COMMIT` | ticket [, `OUT` newSid qty hash] | finalize held + create output SID → `COMMIT_OK`/`COMMIT_NO` |
| in | `RELEASE` | ticket | return all held, mark X → `REL_OK` |
| in | `DISCARD` | sid | zero stock (owner-gated) → `QTY 0` |
| in | link `970290` | — | memory report |

## State & persistence

- Ledger (`sv:q:*`) and ticket holds (`sv:t:*`) in LinksetData → survive reset and take/re-rez.
- `avail` = total − units reserved across all tickets. Reserve subtracts (positive delta), unpick/release adds back; commit leaves avail as-is (units permanently gone).
- Ticket states: R reserved / C committed / X released — kept for idempotent replay.
- **No TTL / no timer**: a reservation lives until COMMIT or RELEASE. Boot announces `NX|SERVER`.
- Reconciliation: known SID → server avail wins; unknown → first-seed from NC.

## Open points / debt

- [ ] 2026-11-17 — **orphaned reservation if the bench is derezzed mid-craft** (no one to take/discard). Primary holder is the bench; a very long safety sweep could reclaim truly orphaned tickets later. Admin-level edge.
- [ ] 2026-11-17 — committed/released tickets (`sv:t` C/X) never pruned → add retention/GC before scaling.
- [ ] 2026-11-17 — `qWrite` result unchecked; clamp negatives; guard LinksetData-full.
- [ ] 2026-11-17 — REGISTER trusts NC `initQty` on first seed (seeding trust; bounded by next-owner perms).
- [ ] 2026-11-17 — COMMIT output SID gets placeholder owner/expiry (0) until the adopting blank REGISTERs.
- [ ] 2026-11-17 — DISCARD gated to the SID's stored owner (anti-grief); confirm intended.
- [ ] 2026-11-17 — `NX_STOCK` channel provisional; `dnaHash` stored but unused server-side (droppable); partitioning deferred.
- [ ] 2026-11-17 — rig (`Nexus_StockRig`) still uses the old atomic whole-basket RESERVE; re-point it at the declarative/no-TTL model when revalidating.
