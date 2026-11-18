# Fiche — Nexus_Component

*Dev & tracking fiche. See `CONVENTIONS.md` and `dev/stock-protocol.md`. File: `Component/nexus_component.lsl`.*

---

## Role

A component object: holds its own identity/DNA/freshness locally and acts as the stock **client** of `Nexus_Server` — registers a stable SID and reflects the server's authoritative quantity. Never decrements itself.

## Current version

`v0.1.0 (2026-11-17)` — pass 1 (registrable component). Testable against `Nexus_Server`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | created (pass 1) — NC identity + stable SID + REGISTER + QTY cache + freshness + die; old stock ledger / MC protocol / DEV_CHANNEL dropped |

## Scope

- **Pass 1 (this):** no-mod NC identity (Name/Taxonomy/Stage/Quantity/Use/Lifetime/Axis), stable SID in `rz_sid`, `REGISTER` on ready, `QTY` listener → cache, freshness (`effPerMille`/expiry/hover), `die` on depleted/expired.
- **Pass 2 (deferred):** blank→product `CONFIG` adopting the server-minted SID; harvest `GIVE`/`CUT`; icon/mesh/organ/MED fields; the browse scan the HUD/Workshop reads for selection.

## Dependencies

- **Server**: `Nexus_Server` (same region) — `REGISTER` → `QTY`.
- **Channel**: `NX_STOCK = -918280`.
- **LinksetData**: `rz_sid` (stable SID). (Old `rz_*` identity mirror + `mc:component:stock` no longer used.)
- **Include**: `nexus_header.lsl`.

## Interfaces (messages)

| Dir | Verb | Payload | Effect |
|---|---|---|---|
| out | `REGISTER` | sid, owner, dnaHash, expiry, ncQty | register/seed; retried until a QTY arrives |
| in | `QTY` | sid, qty | adopt authoritative count; `die` if ≤ 0 |

## State & persistence

- `gSid` persisted in `rz_sid` → survives take/re-rez; the server keys stock by it.
- `gQty` is a cache (-1 until first QTY); `gNcQty` is only a first-seed hint (server ignores it for a known SID).
- Identity/DNA (`gName/gTaxonomy/gStage/gProps/gUse/gLifeSecs/gExpiry`) parsed from the no-mod NC at boot.

## Memory

- `free` at boot: TBD (read the banner).
- notes: lighter than the old Component (ledger and MC protocol removed).

## Open points / debt

- [ ] 2026-11-17 — pass-2 features not implemented (CONFIG blank→product + SID adoption, harvest GIVE/CUT, icon/mesh/organ/MED, browse scan).
- [ ] 2026-11-17 — REGISTER retry is a fixed 6× on a 5 s timer; no server-presence announce handling yet (if the server rezzes later, the component only retries 6×). Consider reacting to `NX|SERVER` (re-register on announce).
- [ ] 2026-11-17 — `die()` on server-reported 0 is immediate; no pending-GIVE window (harvest not in pass 1 yet — revisit when GIVE returns).
- [ ] 2026-11-17 — NC validation still light (duplicate axes, malformed durations) — carried over from old Component REVIEWs.
- [ ] 2026-11-17 — dnaHash sent but not yet used by the server for anything; keep until a use is defined.
