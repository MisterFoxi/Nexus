# Fiche — Nexus_Component

*Dev & tracking fiche. See `CONVENTIONS.md` and `dev/stock-protocol.md`. File: `Component/nexus_component.lsl`.*

---

## Role

A component object (ingredient / intermediate / potion / blank container): holds its own identity, DNA and freshness locally, and acts as the stock **client** of `Nexus_Server` — registers a stable SID and reflects the server's authoritative quantity. Never decrements itself.

## Current version

`v0.2.0 (2026-11-17)` — full component (NC + blank + CONFIG + harvest), server-authoritative stock.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-17 | pass 1 — NC identity + SID + REGISTER + QTY + freshness + die |
| v0.2.0 | 2026-11-17 | full port: blank→product `CONFIG` adopting the server SID, harvest `GIVE`/`CUT`, icon/mesh/organ/MED, KVP restore, browse scan `HERE` (now carries SID), expiry→`DISCARD`. Old ledger/MC/DEV_CHANNEL dropped. |

## Dependencies

- **Server**: `Nexus_Server` — `NX_STOCK (-918280)`: out `REGISTER`, in `QTY`, out `DISCARD` on expiry.
- **Workshop** (future): `NX_SCAN (-918281)`: `PING`→`HERE`/`BLANK`, `CONFIG`, `CUT`, `GIVE`, `HOVER`, `GONE`.
- **LinksetData**: `rz_sid` (stable SID) + `rz_*` identity mirror (survive take/re-rez).
- **Include**: `nexus_header.lsl`.

## Interfaces (messages)

| Dir | Chan | Verb | Payload |
|---|---|---|---|
| out | STOCK | `REGISTER` | sid, owner, dnaHash, expiry, ncQty |
| in | STOCK | `QTY` | sid, qty → adopt; `die` window if 0 |
| out | STOCK | `DISCARD` | sid (on local expiry) |
| in | SCAN | `PING` | → `HERE` (ready) or `BLANK` |
| out | SCAN | `HERE` | objkey, sid, name, qty, use, life, taxonomy, stage, props, eff, mesh, organ[, icon] |
| out | SCAN | `BLANK` | objkey, capacity[, icon] |
| in | SCAN | `CONFIG` | objkey, **sid**, name, use, life, taxonomy, stage, props, med[, eff[, expiry]] → blank becomes product, adopts SID, registers |
| in | SCAN | `CUT` / `GIVE` | record recipient / give Mesh(es) |
| in | SCAN | `HOVER` | 0/1 |
| out | SCAN | `GONE` | objkey (on die) |
| in | link | `970290` | memory report |

## State & persistence

- `gSid` persisted in `rz_sid`; server keys stock by it. `gQty` is a cache (-1 until first `QTY`); `gNcQty` is a seed hint only.
- Identity/DNA/freshness persisted in `rz_*` → survive take/re-rez.
- `die` on server-reported 0 or local expiry, with a 2 s window held open while a harvest `GIVE` is pending (`gCutter`).
- Blank container: no NC (or `Capacity` NC) → advertises `BLANK`, awaits `CONFIG`.

## Open points / debt

- [ ] 2026-11-17 — no `NX|SERVER` announce handling: REGISTER retries 6×/5 s then stops; if the server rezzes later the component stays silent. Add: re-register on a server announce.
- [ ] 2026-11-17 — CONFIG field-count / identity / positive-qty-use / lifetime not validated (carried from old REVIEW).
- [ ] 2026-11-17 — KVP write results unchecked; `rz_ready` not an atomic commit marker (carried from old REVIEW).
- [ ] 2026-11-17 — expiry→`DISCARD` then `die`; if the server is unreachable the DISCARD is lost (server keeps stale stock until its own policy prunes). Acceptable? revisit.
- [ ] 2026-11-17 — `dnaHash` sent but unused server-side so far.
- [ ] 2026-11-17 — not yet exercised in-world (v0.2.0). Pass-1 register/QTY path was validated conceptually via the rig; blank/CONFIG/harvest need the Workshop (or a manual CONFIG) to test.
