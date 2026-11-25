# Fiche — WS_Stock

*Dev & tracking fiche. See `CONVENTIONS.md`, `dev/stock-protocol.md`, `claude/socle-refonte-reseau.md` §3-§4. File: `Workshop/WS_Stock.lsl`.*

---

## Role

Bench **stock client**: holds the craft basket and reserves it with the server. The HUD never talks to the server — it sends picks to WS_Stock over `NX_HUD`; WS_Stock reserves on `NX_STOCK` and pushes the basket back to the HUD (display + Continue gate).

## Current version

`v0.3.0` — pick/unpick → declarative RESERVE; basket persisted; push BASKET / PICKNO; NEARBY re-scan; discard closure; **take COMMIT|OUT** (forge the output SID, wait `COMMIT_OK` → `STOCK_COMMIT_DONE`) and **DISCARD** (purge a product SID on the server).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | created — the pick→reserve slice (socle option B). PICK/UNPICK from the HUD → declarative `RESERVE|<ticket>|sid:u^…` to the server; RES_OK → push BASKET; RES_NO → revert the pending pick + PICKNO; timeout (SRV_WAIT) → treat server as down, revert. RELEASE on WS_Core take/discard (`STOCK_RELEASE_REQ` link). Basket in `state:stock` survives reset/HUD loss (§8). |
| v0.1.1 | 2026-11-20 | **NEARBY availability fix**: on `RES_OK` / `RES_NO` / `REL_OK` send `NX\|RESCAN\|<session>` to the holder's HUD. The server has just changed availability, so the HUD re-reads the authoritative qty from a fresh scan rather than decrement locally. |
| v0.2.0 | 2026-11-23 | **discard closure** (from WS_Core). `STOCK_RELEASE_REQ` and `STOCK_COMMIT_REQ 918251` take `ticket` (payload) + `holder` (id) from the message (LSD already cleared, async). RELEASE → `NX\|RELEASE` + empty BASKET + RESCAN. COMMIT → `NX\|COMMIT` (no OUT). |
| v0.3.0 | 2026-11-25 | **take output**: `STOCK_COMMIT_REQ` extended — `ticket\|newSid\|qty\|dnaHash` → `NX\|COMMIT\|OUT\|…`, then on `COMMIT_OK` (matched vs `gCommitTicket`, not `state:session` which may have rotated) emit `STOCK_COMMIT_DONE 918431` to WS_Core so the récipient CONFIG follows the server. New `STOCK_DISCARD_REQ 918252` → `NX\|DISCARD\|<sid>` (purge a held product's stock). |

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
| out NX_HUD | `NX\|RESCAN\|<session>` | on RES_OK/RES_NO/REL_OK → holder's HUD re-scans NEARBY |
| out NX_STOCK | `NX\|RESERVE\|<ticket>\|sid:u^…` / `NX\|RELEASE\|<ticket>` | to the server |
| in NX_STOCK | `NX\|RES_OK` / `NX\|RES_NO\|…sid:avail^…` / `NX\|REL_OK` | server verdicts (our ticket only) |
| in link | `918250 STOCK_RELEASE_REQ` (ticket, holder) | discard-return: `NX\|RELEASE` + empty BASKET + RESCAN to holder |
| in link | `918251 STOCK_COMMIT_REQ` (`ticket` \| `ticket\|newSid\|qty\|dna`) | consume (no OUT) / take `COMMIT\|OUT`; on OK → `STOCK_COMMIT_DONE` |
| out link | `918431 STOCK_COMMIT_DONE` (ticket) | take COMMIT\|OUT confirmed → WS_Core CONFIGs the récipient |
| in link | `918252 STOCK_DISCARD_REQ` (sid) | purge a held product SID → `NX\|DISCARD\|<sid>` |
| in link | `970290` | memory report |

## Open points / debt

- [ ] 2026-11-19 — SRV_WAIT (3 s) timeout treats any missing reply as server-down; a slow server could drop a valid pick (redo on next pick).
- [ ] 2026-11-19 — RES_NO reverts only the last pending pick (one HUD per bench, no concurrent picks expected).
- [x] 2026-11-25 — **TAKE** `COMMIT|OUT` wired (forge output SID, wait COMMIT_OK → STOCK_COMMIT_DONE) + `STOCK_DISCARD_REQ`.
- [ ] 2026-11-19 — no explicit server discovery; relies on broadcast RESERVE + directed reply (+ timeout for degraded mode).

## Test (in-world)

1. Bound HUD, P0: Refresh → components appear. Click a `+` → WS_Stock reserves; the SELECTED panel shows it; Continue unblocks.
2. Over-pick beyond available → PICKNO, the pick is reverted.
3. Discard (holder release) → basket released on the server, SELECTED empties.
