# Fiche — WS_Stock

*Dev & tracking fiche. See `CONVENTIONS.md`, `dev/stock-protocol.md`, `claude/socle-refonte-reseau.md` §3-§4. File: `Workshop/WS_Stock.lsl`.*

---

## Role

Bench **stock client**: holds the craft basket and reserves it with the server. The HUD never talks to the server — it sends picks to WS_Stock over `NX_HUD`; WS_Stock reserves on `NX_STOCK` and pushes the basket back to the HUD (display + Continue gate).

## Current version

`v0.1.0 (SCRIPT_NAME "WS_Stock")` — pick/unpick → declarative RESERVE; basket persisted (`state:stock`); push BASKET / PICKNO; release on take/discard; server-reply timeout.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | created — the pick→reserve slice (socle option B). PICK/UNPICK from the HUD → declarative `RESERVE|<ticket>|sid:u^…` to the server; RES_OK → push BASKET; RES_NO → revert the pending pick + PICKNO; timeout (SRV_WAIT) → treat server as down, revert. RELEASE on WS_Core take/discard (`STOCK_RELEASE_REQ` link). Basket in `state:stock` survives reset/HUD loss (§8). |

## Dependencies

- **Server** (other object, `NX_STOCK` -918280): `RESERVE`/`RES_OK`/`RES_NO`, `RELEASE`/`REL_OK`. Declarative set.
- **HUD** (other object, `NX_HUD` -918282): in `NX|PICK`/`NX|UNPICK` (from the holder's `NX_Nearby_Controller` / `NX_Selected_Controller`); out `NX|BASKET`/`NX|PICKNO` to the holder.
- **Same linkset**: WS_Core (shares `state:session` = ticket, `state:lock` = holder; sends `STOCK_RELEASE_REQ` 918250 on take/discard).
- **LinksetData**: `state:stock` = `sid~u~name~icon^…` (the basket, keyed by the session). Persistent.
- **Include**: `nexus_header`.

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in NX_HUD | `NX\|PICK\|<session>\|<sid>\|<u>\|<name>\|<icon>` | add to basket → RESERVE → BASKET (or PICKNO) |
| in NX_HUD | `NX\|UNPICK\|<session>\|<sid>` | remove → RESERVE → BASKET |
| out NX_HUD | `NX\|BASKET\|<session>\|<count>\|sid~name~qty~icon^…` | basket to the holder |
| out NX_HUD | `NX\|PICKNO\|<session>\|<sid>\|<avail>` | pick refused (avail, or `SRVDOWN`) |
| out NX_STOCK | `NX\|RESERVE\|<ticket>\|sid:u^…` / `NX\|RELEASE\|<ticket>` | to the server |
| in NX_STOCK | `NX\|RES_OK` / `NX\|RES_NO\|…sid:avail^…` / `NX\|REL_OK` | server verdicts (our ticket only) |
| in link | `918250 STOCK_RELEASE_REQ` | WS_Core take/discard → RELEASE + clear basket |
| in link | `970290` | memory report |

## Open points / debt

- [ ] 2026-11-19 — SRV_WAIT (3 s) timeout treats any missing reply as server-down; a slow server could drop a valid pick (redo on next pick).
- [ ] 2026-11-19 — RES_NO reverts only the last pending pick (one HUD per bench, no concurrent picks expected).
- [ ] 2026-11-19 — COMMIT (take) not wired yet; comes with the craft take/output flow. `freeLock` (HUD gone) keeps the basket; only take/discard releases.
- [ ] 2026-11-19 — no explicit server discovery; relies on broadcast RESERVE + directed reply (+ timeout for degraded mode).

## Test (in-world)

1. Bound HUD, P0: Refresh → components appear. Click a `+` → WS_Stock reserves; the SELECTED panel shows it; Continue unblocks.
2. Over-pick beyond available → PICKNO, the pick is reverted.
3. Discard (holder release) → basket released on the server, SELECTED empties.
