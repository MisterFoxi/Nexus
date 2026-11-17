# Descriptions and observations in laws.src

The compiler supports `describe` and `observe`. Neither keyword allocates an
identifier in `ids.lock`. Write descriptions, documentation and future HUD text
in English.

A transformation may have an optional description:

```text
law chop
    when meta.taxonomy is leaf_plant
    when meta.stage is leaf
    react
    set meta.stage = chopped
    scale qty x5
    describe "The leaves are chopped."
```

An observation uses the same conditions without changing the material:

```text
@cauldron
law observe_boiling
    when fab.thermal is boiling
    observe
    describe "The mixture is boiling."
```

Descriptions are JSON strings enclosed in double quotes on a single line.
Unicode, apostrophes and `#` inside the string are preserved. A `#` comment may
follow the closing quote. Use JSON escapes for embedded quotes. Empty descriptions,
line breaks and control characters are rejected.

An observation requires a description. Transformation actions (`set`, `scale`,
`give`, `add`, `remove`, `keep`, `pass`) and `cap` are forbidden. Law names must
be unique within a station, including observation names.

The generated notecard contains:

```text
law:cauldron:observe_boiling:observe_when = <tokenized conditions>
law:cauldron:observe_boiling:observe_seq = <observation order>
law:cauldron:observe_boiling:description = The mixture is boiling.
```

Transformation descriptions also use `:description`, alongside the existing
fields. Observations have no `:when`, `:verdict`, `:do` or recipe index, so the
current evaluator ignores them. Transformation sequence numbers and crafting
reports remain independent of observations. The existing world loader accepts
these records in its `law:` namespace.

All matching observations accumulate in source order, separated by a space.
They do not compete by condition count: a general and a specific observation
will both appear if both match. Write complementary descriptions to avoid
repetition. All conditions within a single observation must match.

The compiler also emits `law:observations:count` and an ordered
`law:observations:N = station|law_name` index. A condition-free observation uses
`*` as its condition, preserving its meaning through the notecard loader.

Workshop_Eval implements the local consultation API documented in
`Workshop/README_observations.md`. Workshop_Observe now connects the P4 INSPECT
request and a verified live basket snapshot to the calculation API. A transformation description
describes its result, not automatically its state before transformation. Hidden
properties are not revealed unless the author explicitly writes an observation
for them.

Generate from the compiler directory:

```text
python -X utf8 compiler.py axes.src taxonomy.src laws.src > monde.nc
```

`monde.nc` at the repository root and `compiler/monde.nc` now contain the same
current compiled world as `compiler/monde_observations.nc`. Use `monde.nc` as the
normal upload artifact. These files include 26 cutting-board observations,
four cauldron observations and the description for `chop`. They are generated
from the current sources; no separate older world should be uploaded alongside
them. Installation in Second Life remains manual.

Workshop_Config v0.10.5 supplies the cutting degree directly on the existing
`fab.grind` fineness axis. No new bench_config entries are required. Active
seconds are rounded to an integer and capped at 10. Descriptions follow the
axis bands: light 0..2, coarse 3..4, fine 5..6, extra 7..8, over 9..10.
Texture-frame thresholds are not used. Paused time does not count. An explicit Action
mapping, when present, retains its existing behavior. Already chopped leaves start
at chopped and can become finely chopped or finely minced; minced leaves remain
minced. Smell descriptions accumulate with the cutting description. Observation
does not write product stages; TAKE retains the existing transformation rules.
Workshop_Eval v0.9.4 requires an actually present numeric axis for observation
comparisons. A missing degree no longer matches the light band as an implicit
zero; an explicitly transmitted zero remains valid. Legacy recipe matching is
unchanged.

Validate from the repository root:

```text
python -m unittest discover -s compiler/tests -v
```
