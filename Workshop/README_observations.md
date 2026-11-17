# Cumulative observations

Workshop_Eval v0.9.1 provides an isolated, read-only local consultation entry point.
Transformation rule selection remains unchanged: most conditions wins, then
source order. Observation selection instead concatenates every matching
`observe` description in source order, with one space between descriptions.
All conditions of each observation must be true. Only configured station genres
participate. General and specific observations can both appear; there is no
automatic replacement or deduplication.

For example, the cauldron observations for simmering and a putrid smell can
produce:

```text
The mixture is gently simmering. It gives off a putrid smell.
```

## Local API

Send `llMessageLinked(LINK_THIS, 970204, snapshot, requestUUID)` from a cooperating
ROOT script. The snapshot format is the existing direct evaluator format:

```text
fab.thermal=12

Mint|1|mint|leaf|org.smell=5|86400|950|leaf
```

The optional first line is an action header using `^`-separated name=value pairs.
A blank line separates it from the ingredient groups. Each group has exactly
eight fields: name, count, taxonomy, stage, properties, lifetime, freshness and
organ. Groups are separated by line breaks. The caller must provide a validated,
consistent snapshot, use the existing grouping convention and map current inputs
according to bench_config. This API does not acquire a live HUD basket itself.

The reply uses linked message `970205` with the same non-null request UUID:

| Payload | Meaning |
|---|---|
| `OBSERVATIONS|<URL-escaped text>` | All matching descriptions joined together |
| `NO_OBSERVATIONS` | No matching descriptions, including an empty observation index |
| `ERROR|<reason>` | Invalid input, missing data, busy evaluator or oversized text |

Requests are accepted only from the same prim, after evaluator configuration is
ready and while no progressive craft evaluation is running. A missing observation
index is an explicit error. The reply contains at most 4095 UTF-8 bytes of decoded
description text; overflow returns an error instead of a partial description.
Any radio adapter must separately enforce its smaller wire-message limit or page
the text.

## Calculation and isolation

Consultation builds a temporary aggregate using the existing taxonomy, stage,
organ, numeric property and inert-axis semantics, then adds the supplied action
values. Duplicate-group coefficients use the midpoint of the configured batch
range and per-axis random variation is disabled. No random number is drawn.
Descriptions therefore report a deterministic nominal snapshot, not a guarantee
of the final randomized craft outcome.

Observation matching does not require a successful reaction or the reaction's
required-token gate: material can be described even when it cannot react.
It never applies `react`, `danger`, `yield` or transformation descriptions, writes
product or input records, changes stock, populates the final result cache, or
dispatches physical output. Temporary aggregates are cleared before returning.

## Integration status

### Owner reset

Touch the workshop as its owner and choose `RESET ALL`, then `ERASE ALL`.
The option is available during initialization, sessions, treatments and faults.
The confirmation expires after 60 seconds. Other users cannot invoke it.

Workshop_HUD v0.8.3 stops the other scripts in its ROOT inventory, clears all
linkset data (including workshop sessions, pending products and world records),
then resets and starts those scripts and itself. Notecards, scripts and other
inventory assets remain. The world loader reloads the world from inventory.
External HUD state and physical source stock are not cleared or reconciled;
reassociate a clean HUD after the workshop announces READY.

Install Workshop_Interface v0.9.2 for the menu, Workshop_HUD v0.8.3 for reset,
Workshop v0.9.6 and Workshop_Eval v0.9.5 for configuration revalidation after
world data becomes available. This reset does not repair the contents of a world
notecard or choose a different world notecard.

### Workshop startup status

Workshop v0.9.5 announces `[Workshop] READY: world, configuration and all modules
loaded. Observations available.` in owner chat once the world loader has reached
EOF without failed writes, bench_config is loaded, and all Workshop modules,
including Workshop_Observe, have acknowledged startup. While waiting it reports
`NOT READY` with the missing services. This reports initialization, not a free
crafting slot or a matching observation for every ingredient.

Install World_Loader v0.6, Workshop v0.9.5, Workshop_Eval v0.9.2 and
Workshop_Observe v0.1.2 together. World reloads invalidate readiness until
completion. An evaluator configuration reload also invalidates its acknowledgement.
The world loader answers status requests after loading, so restarting the
coordinator does not require reloading the world. Repeated identical ready
notifications do not print another READY message or restart a treatment.

Live consultation is connected. PAUSE opens P4, which requests the current
preparation's observations. REFRESH repeats the read-only request. BACK cancels
it locally and releases the Workshop request; it never submits a craft.

### Installation

In the Workshop ROOT, add `Workshop_Observe.lsl` and replace `Workshop.lsl`,
`Workshop_Config.lsl` and `Workshop_Eval.lsl`. Keep the other Workshop scripts.
In the HUD ROOT, replace `MC_Workshop_Link.lsl` and `MC_P4_Controller.lsl`.
Keep the existing three-button P1 mapping and P4 tables.

Load world data compiled from laws.src containing `observe`/`describe` rules and
the `law:observations:*` index. The current upload artifact is `monde.nc`;
the root, compiler and observation-specific copies are synchronized.
In bench_config, use `InspectHandler = 1`, or omit it (now enabled by default).
An existing explicit `InspectHandler = 0` still disables consultation.
Use the same Genre/Action/HeatAction/DurationAction configuration as the craft.
Only descriptions defined for that Genre can appear; no match is reported
explicitly instead of generating invented text.

### Snapshot transport

Config reuses the final craft's pure input mapping and sends
`970240 / INPUTS|seconds|heat|escapedActionHeader` with the request UUID.
Workshop_Observe v0.1.1 acknowledges receipt on `970242 / STARTED`.
Workshop_Config v0.10.1 refuses after three seconds if this acknowledgement is
missing. After acknowledgement its fallback deadline is later than Observe's
ten-second deadline, so it cannot mask the specific basket, verification or
evaluator timeout. Install these two versions together.
Workshop_Observe asks the authenticated HUD for one held source at a time.
The HUD reads existing basket records without changing them. A second progressive
pass recomputes a fingerprint of all basket rows before evaluation: changed rows,
new/removed rows and unresolved source requests cause an explicit refusal.
The coordinator forwards only authenticated inspection replies while BOUND.

The MCW messages are INSPECT_NEXT, INSPECT_ROW, INSPECT_END, INSPECT_VERIFY,
INSPECT_VERIFIED, INSPECT_ERROR and INSPECT_CANCEL, using the existing target,
session and request UUID envelope. Foreign senders, sessions and requests are
ignored. Transmission does not use BEGIN/ROW/END craft submission messages.
MC_Workshop_Link v0.10.2 and Workshop_HUD v0.8.2 send observation messages
directly to the associated object's UUID with llRegionSayTo, including replies
and cancellation. They no longer depend on local whisper reach. Both endpoints
still authenticate the actual speaker, target, session and request.
Workshop v0.9.4 explicitly refuses a stale session from its known HUD;
Workshop_Config v0.10.2 explicitly refuses configuration reloads, unavailable
treatment phases and invalid inputs instead of silently dropping the request.
Install these four updated scripts together; no P4 layout changes are needed.

Workshop_Observe groups the transient rows using the same name/stage and
first-source metadata convention as the final craft, then calls the existing
970204 evaluator. Its data is held only in the new script's temporary memory;
no input spool, final evaluator cache, output record or basket record is written.
Config returns descriptions and the first source's name to P4. Finalized product
properties are not predicted or created.

Snapshots are limited to 4095 UTF-8 bytes to bound temporary memory use. Replies
must fit the existing radio message limit; oversized descriptions return an
explicit error asking the author to shorten the observation text. No metadata or
description is silently truncated. Requests time out without replay, and resets
discard transient consultation data. Missing modules/rules are reported through
the existing refusal/timeout flow. These limits do not change crafting limits.

The standard Workshop check runner includes `tests/test_observations.py` and
`tests/test_observation_transport.py`, covering the actual HUD-to-Workshop-to-P4
path, compiled laws, cancellation, mutation, timeouts and subsequent crafting.
Tests execute the actual LSL AST; Second Life Mono compilation, free memory and
UI checks remain separate in-world validation.
