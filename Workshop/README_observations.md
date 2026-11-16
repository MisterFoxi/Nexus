# Cumulative observations

Workshop_Eval v0.9.0 adds an isolated, read-only local consultation entry point.
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

The compiler index and cumulative evaluator are implemented and tested. This
does not yet connect the existing `INSPECT`/970240 adapter, create a live basket
snapshot, or open/render P4. The local API is the calculation layer for that
integration. Install the generated observation world data with the evaluator
when connecting the later UI.

The standard Workshop check runner includes `tests/test_observations.py`.
Tests execute the actual LSL AST; Second Life Mono compilation, free memory and
UI checks remain separate in-world validation.
