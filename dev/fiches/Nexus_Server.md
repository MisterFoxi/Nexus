# Fiche — Nexus_Server

*Dev & tracking fiche. See `CONVENTIONS.md` and `dev/stock-protocol.md`. File: `Server/nexus_server.lsl`.*

---

## Role

The single in-sim authority on ingredient/product **quantities**: registers SIDs, serves reservations/commits/releases, discards, and recovers its ledger after restart.

## Current version

`v0.1.0 (2026-11-17)` — `SCRIPT_NAME = "Nexus_Server"`. First ébauche: happy paths + idempotency + auto-release + reconciliation; edges flagged (Open points).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | created — REGISTER/QTY, RESERVE/COMMIT/RELEASE (ticket-idempotent), DISCARD, DISCOVER/SERVER, timeout sweep; `key`-vs-`!`/`&&` type fix (`NULL_KEY` compares); renamed → `nexus_server.lsl`, `SCRIPT_NAME` "Nexus_Server". Compiles. |

## Dependencies

- **Scripts**: none in-linkset (standalone prim). Talks to `Component` and `Workshop` over region say.
- **Channels**: `NX_STOCK = -918280` (cold + hot, single channel for now).
- **LinksetData keys**: `sv:q:<sid>` (ledger: `qty|expiry|owner|dnaHash`), `sv:t:<ticket>` (`state|deadline|pairs`). Authoritative, persistent.
- **Include**: `nexus_header.lsl`.

## Interfaces (messages)

| Dir | Verb | Payload | Effect |
|---|---|---|---|
| in | `REGISTER` | sid, owner, dnaHash, expiry, initQty | seed once / reconcile meta → `QTY` |
| out | `QTY` | sid, qty | authoritative count (broadcast) |
| in | `DISCOVER` | owner, name | → `SERVER` if match |
| in | `RESERVE` | ticket, `sid:u^…` | atomic hold → `RES_OK` / `RES_NO|sid:avail^…` |
| in | `COMMIT` | ticket [, `OUT` newSid qty hash] | finalize + create output SID → `COMMIT_OK`/`COMMIT_NO` |
| in | `RELEASE` | ticket | free hold → `REL_OK` |
| in | `DISCARD` | sid | zero stock (owner-gated) → `QTY 0` |
| in | link `970290` | — | memory report |

## State & persistence

- **Ledger** (`sv:q:*`) and **tickets** (`sv:t:*`) in LinksetData → survive script reset and take/re-rez.
- `qty` stored is **available** (reserved units already subtracted; restored on RELEASE/expiry).
- Ticket states: `R` reserved, `C` committed, `X` released/expired. Kept for idempotent replay.
- On boot: announce presence (`NX|SERVER`); clients re-DISCOVER on failure. Reconciliation: known SID → server qty wins; unknown → first-seed from NC.

## Memory

- `free` at boot: TBD (read it off the boot banner in-world).
- observed min under load: TBD.
- notes: script memory holds only transient per-request lists; the ledger is in LinksetData, not script heap. Sweep reads ≤64 ticket keys/pass.

## Open points / debt

> Every `// REVIEW:` in the code, dated.

- [ ] 2026-11-17 — `NX_STOCK` channel constant provisional; decide cold/hot split (stock-protocol §7).
- [ ] 2026-11-17 — `qWrite` result unchecked; clamp negatives; guard LinksetData-full.
- [ ] 2026-11-17 — REGISTER trusts NC `initQty` on first seed (seeding trust; limited by next-owner perms only).
- [ ] 2026-11-17 — COMMIT output SID created with placeholder owner/expiry (0) until the adopting blank REGISTERs with real meta.
- [ ] 2026-11-17 — DISCARD gated to the SID's stored owner (anti-grief); confirm this is the intended rule.
- [ ] 2026-11-17 — ticket sweep bounded to 64 keys/pass; heavy churn needs paging. Also: committed/released tickets are never pruned → `sv:t:*` grows unbounded. Add retention/GC.
- [ ] 2026-11-17 — input validation light (sid/qty well-formedness, duplicate SIDs in one RESERVE); harden.
- [ ] 2026-11-17 — DISCARD during an active reservation only zeroes *available*; reserved units still commit. Confirm desired.
- [x] 2026-11-17 — exercised in-world via `Nexus_StockRig` v0.1.1: all 9 steps PASS (seed, reserve, commit+output, atomic insufficiency, release/restore, idempotent replay, discard). Core stock plane validated.
