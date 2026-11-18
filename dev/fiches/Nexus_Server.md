# Fiche — Nexus_Server

*Dev & tracking fiche. See `CONVENTIONS.md` and `dev/stock-protocol.md`. File: `Server/nexus_server.lsl`.*

---

## Role

The single in-sim authority, over two planes on one prim:
- **STOCK (hot)** — ingredient/product **quantities**: registers SIDs, holds reservations (reserve/commit/release) on behalf of bench crafts, recovers its ledger after restart.
- **WORLD (cold)** — the compiled **dictionaries** (`monde.nc`): ingests them into LSD once, versions them, and streams them to benches on demand (pull + cache). WS_Boot's counterpart.

## Current version

`v0.3.2 (SCRIPT_NAME "Nexus_Server")` — stock plane (reserve/commit/release, no TTL, declarative RESERVE) **+ world plane** (ingest/version/stream, `HELLO`/`WORLD_*`) **+ owner-touch bench dump**.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | created — REGISTER/QTY, RESERVE/COMMIT/RELEASE (ticket, held-subtracted-at-reserve), DISCARD, DISCOVER, 30 s TTL sweep; `NULL_KEY` type fix |
| v0.2.0 | 2026-11-17 | temporal/pause review: **removed TTL + auto-release sweep** (reservation held by the bench until COMMIT/RELEASE); **RESERVE is now declarative** (set the ticket's held set = desired basket → idempotent, handles pick/unpick by delta); RELEASE = whole ticket; ticket record `state|pairs` (dropped the deadline field) |
| v0.3.0 | 2026-11-18 | **world plane added** (WS_Boot's counterpart): ingest `monde.nc`→LSD at boot and on `CHANGED_INVENTORY`; version = `ver =` header if present else folded-md5 `sig-…`; `HELLO` → `WORLD_OK` (cache hit) or `WORLD_BEGIN`/`WORLD_CHUNK`(opaque, `\n`-packed)/`WORLD_END`; `WORLD_WAIT` pre-ingest; `WORLD_BUMP` broadcast on version change; `sv:bench:*` info registry. Stock plane byte-unchanged |
| v0.3.1 | 2026-11-18 | fix: `reserveSet` local `state` renamed `tstate` (`state` is an LSL reserved word → strict parser rejected it; latent since v0.1.0). Include directive de-extensioned (`"nexus_header"`). No interface change |
| v0.3.2 | 2026-11-18 | admin: owner **touch** → `dumpBenches()` lists the `sv:bench:*` registry (each WS key + world version last served) with a world/stock header line. Read-only |

## Dependencies

- **Scripts**: none in-linkset (standalone prim). Talks to `Component`/`Workshop` over region say.
- **Channel**: `NX_STOCK = -918280` (both planes for now; cold+hot share one channel, cf. stock-protocol §7).
- **Inventory**: `monde.nc` (compiled world) must be dropped in the server prim; re-drop = re-ingest + BUMP.
- **LinksetData (stock)**: `sv:q:<sid>` (`avail|expiry|owner|dnaHash`), `sv:t:<ticket>` (`state|sid:u^…`, state R/C/X). Persistent.
- **LinksetData (world)**: `w:ver` (version token), `w:n` (line count), `w:<i>` (i-th world line, verbatim). Rebuilt each ingest.
- **LinksetData (registry)**: `sv:bench:<wsKey>` (last version served; info-only).
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
| in | `HELLO` | wsKey, cachedVer | register bench; cache hit → `WORLD_OK`; else stream; pre-ingest → `WORLD_WAIT` |
| out | `WORLD_OK` | ver | cached world valid → WS boots from LSD, no transfer |
| out | `WORLD_BEGIN` / `WORLD_CHUNK` / `WORLD_END` | ver, n / ver, seq, payload / ver, nChunks | directed stream; payload opaque, lines `\n`-joined |
| out | `WORLD_WAIT` | — | world not yet ingested; WS retries on `WORLD_BUMP`/shortly |
| out | `WORLD_BUMP` | ver | broadcast: world re-ingested with a new version → benches re-HELLO |
| in | owner `touch` | — | `dumpBenches()` → owner-say the `sv:bench:*` registry + world/stock header |
| in | link `970290` | — | memory report |

## State & persistence

- Ledger (`sv:q:*`) and ticket holds (`sv:t:*`) in LinksetData → survive reset and take/re-rez.
- `avail` = total − units reserved across all tickets. Reserve subtracts (positive delta), unpick/release adds back; commit leaves avail as-is (units permanently gone).
- Ticket states: R reserved / C committed / X released — kept for idempotent replay.
- **No TTL / no timer**: a reservation lives until COMMIT or RELEASE. Boot announces `NX|SERVER`.
- Reconciliation: known SID → server avail wins; unknown → first-seed from NC.
- **World**: ingested once into `w:*` at boot and on inventory drop; streamed synchronously from LSD (no dataserver multiplexing → concurrent HELLOs are safe). `ver =` header line is metadata (not stored as data); absent → folded-md5 of all lines, deterministic across servers loading the same NC.

## Open points / debt

- [ ] 2026-11-17 — **orphaned reservation if the bench is derezzed mid-craft** (no one to take/discard). Primary holder is the bench; a very long safety sweep could reclaim truly orphaned tickets later. Admin-level edge.
- [ ] 2026-11-17 — committed/released tickets (`sv:t` C/X) never pruned → add retention/GC before scaling.
- [ ] 2026-11-17 — `qWrite` result unchecked; clamp negatives; guard LinksetData-full.
- [ ] 2026-11-17 — REGISTER trusts NC `initQty` on first seed (seeding trust; bounded by next-owner perms).
- [ ] 2026-11-17 — COMMIT output SID gets placeholder owner/expiry (0) until the adopting blank REGISTERs.
- [ ] 2026-11-17 — DISCARD gated to the SID's stored owner (anti-grief); confirm intended.
- [ ] 2026-11-17 — `NX_STOCK` channel provisional; `dnaHash` stored but unused server-side (droppable); partitioning deferred.
- [ ] 2026-11-17 — rig (`Nexus_StockRig`) still uses the old atomic whole-basket RESERVE; re-point it at the declarative/no-TTL model when revalidating.
- [x] 2026-11-18 — **compiler contract DONE**: `compiler.py` now emits `ver = <md5(body)[:12]>` as the first line of `monde.nc` (computed on the `\n`-joined body → line-ending independent). Server uses it as authoritative; md5 fallback only if the line is missing. Rebuild + re-drop `monde.nc` for it to take effect.
- [x] 2026-11-18 — world stream reliability handled consumer-side: WS_Boot counts lines at `WORLD_END` and re-`HELLO`s on mismatch. (Still no per-chunk ACK — acceptable for the cold path.)
- [ ] 2026-11-18 — `w:*` doubles the world in the server's LSD (~17 KB); fine on a dedicated prim, watch the 128 KB cap as the world grows.
- [ ] 2026-11-18 — `sv:bench:*` registry info-only, never pruned; BUMP is a broadcast (registry not consulted).
