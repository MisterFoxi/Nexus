# Fiche — WS_Output

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md` (§7). File: `Workshop/WS_Output.lsl`.*

---

## Role

Bench **output face**: hands the forged product to a récipient by CONFIGuring it on `NX_SCAN` (a blank container adopts the output SID and becomes a product component), and hands source mesh(es) directly for the give/harvest path. Driven by `WS_Core`.

## Current version

`v0.1.0` — `OUTPUT_CONFIG` (CONFIG a récipient; auto-pick the first empty container if none given) + `OUTPUT_GIVE` (CUT/GIVE to sources).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-25 | created — CONFIG on NX_SCAN (NX_Component format), auto-pick blank fallback, give path. |

## Dependencies

- **WS_Core** (same linkset): in `OUTPUT_CONFIG 918440`, `OUTPUT_GIVE 918442`; out `OUTPUT_DONE 918441`.
- **Components** (`NX_SCAN` -918281): out `PING`, `CONFIG|…`, `CUT|…`, `GIVE|…`; in `BLANK|objkey|cap[|icon]` (auto-pick scan).
- **Include**: `nexus_header`.

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in link | `OUTPUT_CONFIG` = `container\|sid\|name\|use\|life\|tax\|stage\|props\|med\|eff` | container set → CONFIG it; container "" → PING, pick 1st BLANK, CONFIG |
| in link | `OUTPUT_GIVE` = `holder\|organs\|src^src…` | per source: `CUT\|src\|holder` + `GIVE\|src[\|organs]` |
| out NX_SCAN | `CONFIG\|container\|sid\|name\|use\|life\|taxonomy\|stage\|props\|med\|eff` | blank container adopts the product SID |
| out link | `OUTPUT_DONE` = `OK\|<container>` / `FAIL\|<reason>` | collection result → WS_Core |

## Ordering constraint

The server creates `sv:q:<newSid>` only on the `COMMIT|OUT` (and only if the sid does not yet exist). So the CONFIG (→ container REGISTERs the sid) must follow the COMMIT. WS_Core enforces this: `OUTPUT_CONFIG` is only sent after `STOCK_COMMIT_DONE`.

## Open points / debt

- [ ] 2026-11-25 — auto-pick takes the first BLANK owned by us; no capacity/split logic (one take = one container = one SID in V1).
- [ ] 2026-11-25 — give path is generic (any genre); the cutting_board has no give law.
