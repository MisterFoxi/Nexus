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

Live consultation is connected. PAUSE opens P4, which requests the current
preparation's observations. REFRESH repeats the read-only request. BACK cancels
it locally and releases the Workshop request; it never submits a craft.

### Installation

In the Workshop ROOT, add `Workshop_Observe.lsl` and replace `Workshop.lsl`,
`Workshop_Config.lsl` and `Workshop_Eval.lsl`. Keep the other Workshop scripts.
In the HUD ROOT, replace `MC_Workshop_Link.lsl` and `MC_P4_Controller.lsl`.
Keep the existing three-button P1 mapping and P4 tables.

Load world data compiled from laws.src containing `observe`/`describe` rules and
the `law:observations:*` index, such as `compiler/monde_observations.nc`.
The existing monde.nc files are not overwritten by this update.
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
