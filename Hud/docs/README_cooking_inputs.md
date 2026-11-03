# Independent preparation inputs and future product consultation — v0.9.0

This release carries heat intensity and active duration independently through
the existing HUD -> Workshop -> evaluator path. It also reserves an authenticated,
read-only consultation interface. It does not yet evaluate an intermediate product.

## Installation

Update these ROOT scripts together in an idle HUD/station:

- HUD: MC_P1_Animation and MC_Workshop_Link.
- Workshop v0.9.1: replace Workshop and add Workshop_Config plus
  Workshop_Interface in ROOT. HUD, Eval, Output and Storage retain their revisions.
World data, monde.nc, vocabulary, token IDs, and compiled recipes are unchanged.
This release adds no axis and requires no compilation or world-data loading.

No reset, stock clear, automatic delivery, or notecard replacement is performed
by the source update. bench_config_cooking.txt is an example, not an automatic
replacement for the active mortar/cutting-board configuration.

## Inputs

Heat intensity is an integer from 0 to 30 in the evaluator's gameplay units.
These values are not physical degrees or power. fab.thermal already maps its
physical authored ranges into 0..30. There is no thermal simulation in this release.

Select heat before START. Heat is fixed for that preparation, including pauses;
changing it during activity would require a history model instead of retroactively
applying the final setting to all elapsed time. Discard/completion clears it.

Optional owner-operated prims are P1_HEAT_PLUS and P1_HEAT_MINUS. Their presence
does not affect existing HUD geometry. They adjust heat by one unit and report
the value in owner chat. The UI builder may instead send a ROOT link message:

| Request | Payload | Reply (same non-null ticket) |
|---|---|---|
| 918395 | SET\|18 | 918396 / HEAT\|18 or ERROR\|reason |
| 918395 | GET | 918396 / HEAT\|value (-1 means unselected) |

The clock remains owned by MC_P1_Animation: START/CONT accumulate active seconds,
STOP/PAUSE and resets suspend it. A reset restores both elapsed time and heat;
offline time is excluded. Old three-field mc:chop:session records remain readable;
new records append heat as a fourth field.

For a two-input station, add to bench_config:

```
HeatAction = fab.thermal
# Optional: DurationAction = an existing numeric axis from your world
DurationScale = 1.0
DurationMax = 3600
InspectHandler = 0
```

HeatAction receives selected heat. DurationAction receives round(activeSeconds *
DurationScale), bounded to 0..DurationMax. DurationAction is optional: it names an
existing numeric axis supplied by the user's world. No duration axis is invented
or added by this code update. Even without an evaluator mapping, raw duration
and heat are independently transmitted, saved, and available to the test adapter.
As with the existing evaluator, injected fab.thermal participates in its existing
axis aggregation; this update does not redefine thermal material properties.

The configured axes must exist in the loaded world. They must be distinct and
must not also appear as legacy Action entries. Legacy Action/GrindScale/GrindMax
retain their existing behavior. No cooking law is changed: the current cauldron
laws gate on heat only; any later change to vocabulary/recipe conditions is a
separate task requiring the user's instruction.
Declaring an input does not automatically make every existing recipe use it.

The two-input wire is:

```
MCW|BEGIN|bench|session|treatment|CONTAINER/KEEP|activeSeconds|0|heatIntensity
```

The final 0 is the existing not-spoiled flag, not heat. Without selected heat,
the HUD retains the old eight-field BEGIN. A station with HeatAction requires
the ninth field and refuses missing/malformed heat before accepting ingredients.
ws:inputs stores [treatment, rawActiveSeconds, heat] before the BEGIN ACK;
the existing durable ws:core action header retains the evaluator values on reset.

## Consultation extension point (step 3; step 1 remains to implement)

An optional P1_TEST prim sends 918397 / TEST with a fresh UUID. A UI script can
send the same message directly. The result is 918398 with that same UUID.
MC_P1_Animation reads live inputs without pausing its clock or finalizing the basket.

```
HUD -> WS: MCW|INSPECT|bench|session|requestUUID|activeSeconds|heatIntensity
WS -> HUD: MCW|INSPECT_REPLY|hud|session|requestUUID|escapedResult
```

Only the associated HUD/session is accepted, while the station is BOUND and the
HUD is IDLE with a started, usable preparation. This request UUID is independent
from treatment UUIDs. No BEGIN/END, ingredient COMMIT/RETURN, evaluation, output
creation, or physical sampling occurs. Test requests are transient and never
replayed on reset or timeout. Late/foreign responses are ignored.

With InspectHandler=0, the reply is NOT_IMPLEMENTED. This is intentional: it is
not a fabricated preview. To connect a future consultation adapter in WS ROOT,
set InspectHandler=1 and implement:

| Direction | Link message | Payload | id |
|---|---|---|---|
| WS -> adapter | 970240 | INPUTS\|activeSeconds\|heatIntensity | requestUUID |
| Adapter -> WS | 970241 | result text (WS escapes it on radio) | same requestUUID |

One request can be pending at a time. Missing adapter response returns UNAVAILABLE
after about 10 seconds (checked on Config's 5-second timer); the HUD has its
own 15-second timeout. A real adapter must obtain a non-destructive basket snapshot
and run an isolated consultation calculation. It must not reuse the final evaluator
cache, draw away the final treatment's random outcome, mutate product/stock, or
pause the live clock. These are the requirements for the later product-state view.

## Validation

The standard HUD/Workshop check runners include test_cooking_inputs.py. They
exercise real parsed LSL scripts with mocked SL services: independent axes and
law conditions, invalid/missing heat, resets, legacy behavior, owner controls,
authenticated consultation, timeouts and unchanged stock during tests.
Visual geometry, in-world Mono memory, and the future product-state display still
require Second Life validation.
