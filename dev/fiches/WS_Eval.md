# Fiche — WS_Eval

*Dev & tracking fiche. See `CONVENTIONS.md`, `Workshop/README_observations.md`, `claude/socle-refonte-reseau.md`. File: `Workshop/WS_Eval.lsl`.*

---

## Role

Bench-local **observation engine**: observe-only port of the old `Workshop_Eval` consult path. Reads the cached world + bench genre/config from the shared LinksetData, aggregates an observation snapshot, matches the `observe_when` rules of this bench's genre, and returns the concatenated descriptions. No transformation, no stock mutation, no output — pure read-only consultation. Runs in the bench linkset (**`WS_` = bench**; it must NOT be installed in the HUD, or it won't hear bench-directed `NX|OBSERVE`).

## Current version

`v0.1.0 (SCRIPT_NAME "WS_Eval")` — `NX|OBSERVE` → aggregate (toks/traits/organs/axes, batch midpoint, no random flux) → match `observe_when` of `ws:genre` → `NX|OBSERVED|OK|desc|name` / `NONE` / `ERR`.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-23 | created — observe-only extraction of `Workshop_Eval` (`buildAggregate`/`addGroup`/`injectAction`/`evalWhen`/`consult`). Reads the world straight from LSD (`tok:`/`tax:`/`law:`, written verbatim by WS_Boot). Genre from `ws:genre`, batch curve from `ws:cfg:Batch`/`NMax`. `llListen` registered **first** in `state_entry` so a `loadCfg` fault can't kill the listen. First named `NX_Eval` → renamed `WS_Eval` (it's a bench script). |

## Dependencies

- **HUD peer** (`NX_HUD` -918282): in `NX|OBSERVE` (from `NX_Nearby_Controller`), out `NX|OBSERVED` to the holder.
- **Same linkset**: WS_Boot (writes the world + `ws:genre`/`ws:cfg:*` to LSD), WS_Core (`state:session` = ticket, `state:lock` = holder).
- **LinksetData (read)**: `tok:<name>`, `tok:#<id>`, `tax:<id>:toks|trait|inert|need|organ:<o>:tags|trait`, `law:observations:count`, `law:observations:<i>`, `law:<genre>:<name>:observe_when|description`, `ws:genre`, `ws:cfg:Batch`/`NMax`, `state:session`, `state:lock`.
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in NX_HUD | `NX\|OBSERVE\|<session>\|<nameEsc>\|<snapshotEsc>` | validate session+holder → `consult()` → reply |
| out NX_HUD | `NX\|OBSERVED\|<session>\|OK\|<descEsc>\|<nameEsc>` | matching descriptions joined by a space |
| out NX_HUD | `NX\|OBSERVED\|<session>\|NONE\|\|<nameEsc>` | no matching observation |
| out NX_HUD | `NX\|OBSERVED\|<session>\|ERR\|<reasonEsc>\|` | invalid snapshot / world not loaded |
| in link | `970290` | memory report |

## Snapshot & conditions

- **Snapshot** = `"<actionHeader>\n\n<group>\n<group>…"`. actionHeader = `axis=val^…` (e.g. `fab.grind=4`). group (8 fields) = `taxonomy\|count\|use\|stage\|props\|life\|eff\|organ`.
- **Aggregate**: per group, expand `tax:<id>:toks` (token set + `meta.taxonomy` membership), add `tax:<id>:trait` axes ×batch-midpoint, apply `props`, `stage`/`organ` + organ tags/traits; then merge the action header axes (no scaling). Observe mode = batch midpoint, **no random flux**.
- **`evalWhen`** (`^`-joined): `tok=val` → membership (`meta.taxonomy`/`stage`/`organ`) else presence; `tok~lo~hi` range; `tok>=k` / `tok<=k`. A numeric condition on an **absent or inert** axis fails. `*` = always match.
- **`consult`** iterates `law:observations:0..count`, keeps entries whose genre == `ws:genre`, matches `observe_when`, concatenates `description` in index order.

## Behaviour notes

- **Observe-only**: transformation laws (`do`/`react`/`yield`), the required-token (`need`) gate, stock writes and output are intentionally NOT ported — observation describes material even when it cannot react (per `README_observations.md`).
- **Listen-first**: `state_entry` registers `llListen(NX_HUD…)` before `nexusBoot`/`loadCfg`, so any later fault leaves the listen active.
- **Directed delivery**: `NX|OBSERVE` is `llRegionSayTo(bench, …)` from the HUD → only scripts in the bench hear it. (This is why installing WS_Eval in the HUD silently fails.)

## Open points / debt

- [ ] 2026-11-23 — V1 aggregation targets the cutting_board observe rules; it's the full taxonomy/stage/organ/axis semantics, but validate on mortar/cauldron genres when their flow exists.
- [ ] 2026-11-23 — batch midpoint is deterministic (correct for observation); the final craft draws a random `m(n)` — keep them conceptually aligned.
- [ ] 2026-11-23 — no OBSERVE size cap re-check here (the HUD snapshot is small); add a guard if snapshots grow.

## Test (in-world)

1. `WS_Eval` in the **bench** ROOT. Reset → banner `[Nexus] WS_Eval v0.1.0 …` (prefixed by the bench object, not the HUD).
2. pick a leaf → CUT → PAUSE → P4 shows the description; early cut → "The leaves are whole." / "…roughly chopped" (`fab.grind` 3-4) / "…finely chopped" (7-8).
3. REFRESH on P4 recomputes with the current `fab.grind`.
