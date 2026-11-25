# Fiche — WS_Eval

*Dev & tracking fiche. See `CONVENTIONS.md`, `Workshop/README_observations.md`, `claude/socle-refonte-reseau.md`. File: `Workshop/WS_Eval.lsl`.*

---

## Role

Bench-local **observation engine** (observe-only). Reads the cached world + bench genre/config from the shared LinksetData, aggregates an observation snapshot, matches the `observe_when` rules of this bench's genre, and returns the concatenated descriptions. No transformation, no stock, no output. The **transformation** path now lives in its own script, `WS_Take` (they were split because observe+transform in one script overran the 64 KB Mono budget → stack-heap collision at boot).

## Current version

`v0.2.1` — observe-only; transform extracted to `WS_Take`. Batch curve is CONFIG, not baked (empty default = ×1.0).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-23 | created — observe-only extraction of `Workshop_Eval`. `llListen` first in `state_entry`. |
| v0.2.0 | 2026-11-25 | (transient) added the transformation path — overran 64 KB → stack-heap collision. |
| v0.2.1 | 2026-11-25 | reverted to observe-only (transform moved to `WS_Take`). `BATCH_MULT=[]` by default (no genre data baked in); `batchMult` returns 1000 (×1.0) when no `ws:cfg:Batch`. |

## Dependencies

- **HUD peer** (`NX_HUD` -918282): in `NX|OBSERVE`, out `NX|OBSERVED`.
- **Same linkset**: WS_Boot (world + `ws:genre`/`ws:cfg:*`), WS_Core (`state:session`, `state:lock`).
- **LinksetData (read)**: `tok:*`, `tax:*`, `law:observations:*`, `law:<genre>:*:observe_when|description`, `ws:genre`, `ws:cfg:Batch`/`NMax`, `state:session`, `state:lock`.
- **Include**: `nexus_header`.

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in NX_HUD | `NX\|OBSERVE\|<session>\|<nameEsc>\|<snapshotEsc>` | validate session+holder → `consult()` → reply |
| out NX_HUD | `NX\|OBSERVED\|<session>\|OK\|<descEsc>\|<nameEsc>` / `NONE\|\|<nameEsc>` / `ERR\|<reasonEsc>\|` | |
| in link | `970290` | memory report |

## Snapshot & conditions

- Snapshot = `"<actionHeader>\n\n<group>…"`, group (8) = `taxonomy\|count\|use\|stage\|props\|life\|eff\|organ`.
- Observe aggregate: batch **midpoint**, **no random flux** (a consultation must not spend the craft's randomness).
- `evalWhen`: `tok=val` membership/presence, `tok~lo~hi`, `tok>=k`/`tok<=k`; numeric on an **absent or inert** axis fails; `*` always matches.

## Open points / debt

- [ ] 2026-11-25 — validate on mortar/cauldron observe rules when they exist.
- [ ] `nexus_header` included without extension (consistent with the rest).
