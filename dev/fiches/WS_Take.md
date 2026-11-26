# Fiche — WS_Take

*Dev & tracking fiche. See `CONVENTIONS.md`, `claude/socle-refonte-reseau.md`. File: `Workshop/WS_Take.lsl`.*

---

## Role

Bench-local **transformation engine**. Resolves the react/yield laws of this bench's genre against a TAKE snapshot and builds the product DNA. Split out of `WS_Eval` for Mono memory (observe + transform in one script overran 64 KB). Pure evaluation: it does not touch stock or output — it hands the result to `WS_Core`, which drives `COMMIT|OUT` + the récipient CONFIG + closure.

## Current version

`v0.1.1` — full craft draw (random batch `m(n)` + natural flux + oversaturation spoil, unlike `WS_Eval`'s deterministic observe). Memory-bounded law scan (`llLinksetDataFindKeys` paged by 32). No genre data baked in (all from `ws:cfg:*`). Caches the snapshot on TAKE and can forge from the cache on `FORGE_CACHED` (validate-on-leave).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-25 | created — port of `Workshop_Eval`'s `resolve()`+`buildOutput()` with random flux/batch/spoil. `resolve()` reads law keys in pages of 32 (bounded heap regardless of law count). `BATCH_MULT`/`N_MAX`/`gMaxEffect`/`SPOIL_*`/`FLUX_ABS` all from `ws:cfg:*` with neutral fallbacks. |
| v0.1.1 | 2026-11-26 | **cache + forge-from-cache**: on TAKE, write `state:lastsnap`/`lastname`/`lastsrc`; new link handler `FORGE_CACHED 918432` reads the cache (`lastsnap`/`lastname`/`lastsrc`) and runs `takeEval` with the holder in `id` → lets WS_Core validate an abandoned started craft at its last known stage. |

## Dependencies

- **HUD peer** (`NX_HUD` -918282): in `NX|TAKE`.
- **WS_Core** (same linkset, link `EVAL_TAKE_RES 918430` out, `FORGE_CACHED 918432` in): out the result; holder key in `id`. `FORGE_CACHED` (id=holder) forges from the cached snapshot.
- **LinksetData (read)**: `tok:*`, `tok:#<id>`, `tax:*`, `law:<genre>:*:when|verdict|do|seq|cap`, `ws:genre`, `ws:cfg:Batch|NMax|MaxEffect|SpoilMin|SpoilMax|FluxAbs`, `state:session`, `state:lock`, `state:lastsnap`/`lastname`/`lastsrc` (on FORGE_CACHED). (write) `state:takesrc`, `state:lastsnap`/`lastname`/`lastsrc` (cache on TAKE).
- **Include**: `nexus_header`.

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in NX_HUD | `NX\|TAKE\|<session>\|<nameEsc>\|<snapshotEsc>\|<srcKeysEsc>` | validate session+holder → store `state:takesrc` + cache (`lastsnap`/`lastname`/`lastsrc`) → `takeEval` |
| in link | `FORGE_CACHED 918432` (id=holder) | forge from the cached snapshot (`lastsnap`/`lastname`/`lastsrc`) → `takeEval` → `EVAL_TAKE_RES` |
| out link | `EVAL_TAKE_RES 918430` (id=holder) | `1\|verdict\|name\|qty\|use\|life\|tax\|stage\|props\|med\|eff` / `2[\|leaf^root]` / `0` |
| in link | `970290` | memory report |

## Eval

- Snapshot parsed like observe; `name` (field 3) = product base name (basket name); `srcKeys` (field 5) = picked sources' object keys, stored in `state:takesrc` for the give path.
- Aggregate with **random** `batchMult` + `fluxAxis` + oversaturation spoil (`c>=N_MAX` → spoil draw).
- `resolve()`: required-token (`need`) gate first; then paged scan of `^law:<genre>:` (32/page), `evalWhen` (absent axis reads 0 for take, inert fails), most-terms-wins / seq tiebreak; yield (verdict 2, `give=<id>`) accumulated out of contest.
- `buildOutput()`: `eff*`/`qty*`/axis scaling/labels, `effMul *= spoil/1000`, clamp by `cap` (MaxEffect ∧ law cap; 0 = no cap), stage-suffix replacement on the name.
- Result codes: `1` reaction (product DNA) / `2[|organs]` give / `0` inert.

## Memory

- Split from `WS_Eval` precisely to fit 64 KB. `resolve()` paginates to keep the peak heap small whatever the genre's law count. Watch the boot banner heap.

## Open points / debt

- [ ] 2026-11-25 — action header (`fab.grind`) is board-shaped; generalize per genre (`ws:cfg:*` Action/Heat/Duration) with the HUD assembler.
- [ ] 2026-11-25 — `oMed` always "", `oUse` carried from source: vestigial, keep or prune later.
