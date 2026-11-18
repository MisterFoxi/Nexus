# Fiche — Workshop (coordinator)

*Dev & tracking fiche. Describes the **current** code (pre-rebuild). File: `Workshop/Workshop.lsl`. One of several ROOT scripts of a bench; siblings get their own fiches.*

> **Status: legacy / pre-refonte.** This is the old MCW session coordinator. The network rebuild (`socle-refonte-reseau.md`, `dev/stock-protocol.md`) replaces its stock/session machinery with the `Nexus_Server` model (reserve/commit/release, basket in the Workshop, local observation). This fiche documents what the code does **today**, as the salvage/replacement reference.

---

## Role

Session & treatment **coordinator** for one bench. Sole writer of `ws:core` and `ws:collector`. Drives the craft state machine, brokers the HUD association (MCW), and orchestrates the sibling modules. Holds **no** ingredient / container / output-DNA / kept-source data itself — those live in the sibling scripts.

## Current version

`v0.9.6 (2026-11-17)` (banner `"Workshop v0.9.6"`). Not yet migrated to the rebuild.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.9.6 | 2026-11-17 | current legacy coordinator (as found; pre-refonte) |

## Dependencies

- **Sibling ROOT scripts** (same linkset, via `llMessageLinked`): `Workshop_Config`, `Workshop_Interface`, `Workshop_HUD`, `Workshop_Eval`, `Workshop_Output`, `Workshop_Storage`, `Workshop_Observe`.
- **World loader**: consumes `970100` (`WORLD_LOADED|n` / `WORLD_LOADING` / `WORLD_ERROR|`).
- **HUD** (worn, separate object): MCW wire protocol, relayed through the Interface/HUD endpoint.
- **LinksetData** (see State).
- **Config notecard** `bench_config` (read by `Workshop_Config`, not here).

## Interfaces

### MCW wire (HUD ⇄ Workshop), `"MCW|<verb>|<hud>|<session>|<run>[|<body>]"`
- out via link `970211` (`sendTo`/`reply`); in via link `970210` (`receiveControl`).
- Verbs out: `OFFER` (kind|single|keep|!dev[|OUTPUT]), `BOUND`, `RESULT`, `ACK`, `RELEASED`, `OUTPUT_CLOSED`, `EXIT_REQUEST`, `INSPECT_REPLY`.
- Verbs in: `ACCEPT`, `BEGIN`, `END`, `ABORT`, `CLOSED`, `EXIT`, `ACTIVITY|0/1`, `INSPECT`, `INSPECT_*`, `OUTPUT_STATUS`, `TRANSFER`.

### Link-message codes
| Code | Dir | Meaning |
|---|---|---|
| 970100 | in | world loaded/loading/error |
| 970210 | in | MCW control from HUD endpoint |
| 970211 | out | MCW to HUD endpoint |
| 970202 | out | request to `Workshop_Eval` (sends `gAction`) |
| 970201 | in | eval result (`STORED` / `ERROR|`) |
| 970213 | out | storage/build coordinator (`BEGIN`/`END|`/`CLEAN`/`STATUS`) |
| 970215 | in | build status (`BEGIN_READY`/`BUILD_STARTED`/`INPUT_READY`/`ERROR|`) |
| 970220 | out | output module (`START|`/`STATUS`/`INFO`/`ACTIVITY|`/`FAIL_SOUND`/`TRANSFER|`) |
| 970221 | in | output result (`READY`/`OK`/`TRANSFERRED|`/`TRANSFER_NO|`/`TRANSFER_EXPIRED|`/`ERROR|`) |
| 970247 / 970256 | out | observation/inspect forwarding |
| 970250 | out | config load; 970251 in | config result (JSON 7) / `RESET` |
| 970252 | out | hover config to output |
| 970254 | out | input-mapping request; 970255 in | input mapping (JSON 4: choice, seconds, count, action) or `NO|` |
| 970260 | out | interface (`INFO`/`MENU`/`PROVISION|`); 970261 in | menu result (`HOVER`/`Resume`/`Exit`) |
| 970290 | in | memory report |
| 970298 | out | `READY?` probe; 970299 in | module-ready bits (`HUD`/`EVAL`/`OUTPUT`/`STORAGE`/`INTERFACE`/`OBSERVE`/`EVAL_LOADING`) |

## State machine (`gPhase`)

`FREE → OFFERED → BOUND → RECEIVING → BUILDING → EVALUATING → OUTPUT → SETTLING → PRODUCT`

- **FREE**: idle; touch by a user → `OFFERED` (mints `gSession`, provisions, `offer()`).
- **OFFERED**: waits for HUD rez/`ACCEPT`.
- **BOUND**: HUD associated; accepts `BEGIN` (→ input mapping via 970254/970255 → `RECEIVING`), menu, inspect/observation, `EXIT`.
- **RECEIVING → BUILDING**: HUD uploads the basket (storage module); `INPUT_READY` → **EVALUATING** (sends `gAction` to Eval, 15 s deadline).
- **EVALUATING**: on eval `STORED` → **OUTPUT**.
- **OUTPUT**: output module builds the product; `READY` → **SETTLING** (result `OK`), `OK` → settle.
- **SETTLING / PRODUCT**: finished product; a **collector sub-session** (`gCollector*`) lets a second avatar (or the same) collect/transfer; `finishProduct` closes.

Pending product (`ws:output` state `WAIT_CONTAINER`, qty>0) = waiting for a fiole; `collectorOffer()` offers it to the next toucher.

## Persistence (LinksetData, this script is sole writer of ws:core / ws:collector)

- `ws:core` — JSON[13]: user, hud, session, run, phase, lastResult, choice, seconds, kind, single, keep, !dev, action.
- `ws:collector` — JSON[4]: run, collectorUser, collectorHUD, collectorSession.
- Read/observed: `ws:output`, `ws:released`, `ws:closed`, `ws:inputs`, `ws:hover`.
- Config (from 970251 JSON[7]): `gKind`, `gHudObject`, `gSingle`, `gKeep`, `gDev`, `gHover`.
- Readiness gate: `gReady == 31` (HUD1|EVAL2|OUTPUT4|STORAGE8|INTERFACE16) **and** `gConfigReady` **and** `gWorldReady` **and** `gObserveReady`.

## Memory

- `free` at boot: TBD. Split across 7 ROOT scripts precisely to fit Mono heaps; this coordinator holds only session state (no ingredient/DNA tables).

## Open points / debt

- [ ] 2026-11-18 — **Legacy**: the whole MCW mirror state machine + lease/collector is the half the rebuild drops (socle §3). Documented for salvage, not for extension.
- [ ] 2026-11-18 — `finishProduct` relies on two independently-persisted facts (`ws:output` DONE + `ws:closed`); a reset/write failure between related writes can leave partial state (`// REVIEW` in code).
- [ ] 2026-11-18 — storage fault (`gFault`) locks the session hard; recovery is manual.
- [ ] 2026-11-18 — many codes, phases and a parallel collector session: a single user action crosses several scripts and message hops — the debuggability problem the rebuild targets.
- [ ] 2026-11-18 — depends on `Workshop_Eval` 970201/970202 (stream path) which the rebuild keeps for the engine but rewires for the new flow.
