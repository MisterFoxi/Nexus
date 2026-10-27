# Workshop v0.7: separated subsystems

Install these five scripts together in the same ROOT prim of an idle workshop:

| Script | Owns |
|---|---|
| Workshop | Configuration, player/HUD lease, current treatment phase |
| Workshop_HUD | MCW radio endpoint, durable input rows, derived evaluation groups |
| Workshop_Eval | Existing aggregation, rule resolution, yield and product calculation |
| Workshop_Output | Product pending delivery, container discovery, CONFIG and CUT/GIVE, sounds/particles |
| Workshop_Storage | Kept products, expiry, progressive migration/read access |

Replace Workshop and Workshop_Eval; add the other three. Keep bench_config,
compiled tok:/tax:/law:/idx: data and inventory objects/sounds. Do not run an old
Workshop coordinator beside the new one. Field keeps its existing Eval request
in its own linkset. No HUD script, Component or compiler source changes are part
of this split.

## Memory ownership

Workshop no longer owns gIng, gPicks, gCons, gRec, gKept, output DNA, ingredient
menus or the action stepper. Selection, gesture and source-stock transactions
are owned by the HUD. The coordinator's only growing list is its configured
action names; it never receives a complete serialized basket.

Workshop_HUD saves one incoming source per ws:in:row:N key. Stop-and-wait ROW
acknowledgements are sent only after persistence. Duplicates must match the
saved row exactly. On END, one event processes one source to create stored
evaluation groups. This preserves the old Workshop name/stage batch grouping,
first source's metadata for that group, and first group's role as principal.
Every raw source's metadata remains in the spool for physical output. This
split does not redefine ingredient identity or recipe/yield arithmetic.

Workshop_Eval reads one stored group per event. Its accumulator and first group
stay in Eval; the complete flattened groups list is not constructed for the
Workshop path. Output uses the same calculation functions as before. The old
direct request used by Field remains available. No new recipe or legacy stock
protocol has been added.

Output keeps only its current product in script memory. Blank containers are
stored one per key and consumed one per event. Storage keeps one product per
record and returns one record per page request. The former state:kept is
imported with deterministic keys and deleted only after all rows were copied.

Source size is not a Mono memory measurement. The coordinator source shrank
from about 35.5 kB to about 13.6 kB; actual free memory must be checked in-world,
including Eval with the loaded world rules. Rule lookup/aggregation still run
in Eval and retain their existing vocabulary-dependent cost.

## Configuration

The existing bench_config remains valid. Existing Genre, Action, GrindScale,
GrindMax, CookTime, ShowHover and sound fields are retained. Numeric evaluator
configuration (MaxEffect, FluxAbs, Batch, NMax, SpoilMin/Max) is still read by Eval.

Additional optional fields, owned by the coordinator:

```
HUDKind = cutting_board
SingleIngredient = 1
AllowKeep = 0
DEV = 1
# HUDObject = inventory object name, required when DEV=0
```

HUDKind defaults to the first Genre. The dedicated HUD's HUD_KIND must match it.
SingleIngredient defaults to 1. AllowKeep defaults to 0 and is always forced to
0 for cutting_board. DEV defaults to 1: use the already worn development HUD.
With DEV=0 the coordinator rezzes the configured HUDObject; its MC_Workshop_Link
handles attach permission/temporary attach. Provisioning, permissions and
inventory copying still require in-world validation.

Action names/configuration are not inferred from the obsolete cutting-board
laws. As before, configured action values use round(activeSeconds * GrindScale)
bounded to 0..GrindMax. No Action means an empty action header. Laws and
compiler/axes.src are unchanged by this segmentation.

The current MCW/HUD/Component access policy is same owner. This is not a change
to shared-station authorization.

## Session and physical output

The workshop takes its lease before OFFER and accepts one dedicated HUD. It
keeps that lease across preparations. Workshop_HUD implements the documented
MCW contract in Hud/docs/README_workshop_link.md on whisper channel -918275.
The coordinator rejects unrelated senders, sessions and treatments. The existing
physical Component protocol remains on -918273; the HUD stock relay remains
on its existing channel.

BEGIN/ROW/END spool the confirmed basket and gesture. Eval stores its result
before sending its reference to the coordinator. The coordinator passes only
the run UUID/choice/player to Output; product DNA is read there. No source
TAKE, RETURN or COMMIT is sent by any Workshop subsystem.

After the existing cook delay, CONTAINER scans empty recipients and opens the
existing collection popup for the recorded player. Collect fills recipients;
partial collection retains the remaining quantity. Touching the station with
the same player scans again. Keep is a HUD choice and is delegated to Storage
where permitted. Mesh/organ output uses the existing CUT/GIVE flow for each
held source unit.

Only completed output/Keep sends RESULT OK to the HUD. The HUD then COMMITs
its held sources and sends CLOSED after the matching stock acknowledgements.
Only CLOSED opens the next preparation. Missing containers keep the treatment
and player lease pending. An inert/invalid evaluation returns NO and leaves
the confirmed basket with the HUD.

Exit is accepted after the HUD's own stock cleanup. The release receipt is
stored before clearing the lease, allowing an exact duplicate EXIT to receive
RELEASED again. No timeout guesses that held stock or a pending output is gone.

When the recorded player touches an associated workshop with no submitted
treatment (BOUND), a Resume/Exit menu is offered. Resume retains the same
session. Exit sends an authenticated MCW EXIT_REQUEST with NULL_KEY as run;
the idle HUD performs its normal cleanup before requesting release. Replace
both Workshop.lsl and MC_Workshop_Link.lsl for this menu. A stale menu cannot
release a treatment that has since begun. Other active phases are reported by
name instead of being mislabeled as another user's session.

CONFIG and GIVE remain the existing one-way physical messages. This split
does not claim a new Component delivery acknowledgement. Output writes a
dispatch boundary before those calls. Reset at an uncertain boundary enters
HOLD, retains the session and reports the ambiguity without automatically
repeating delivery. Such a HOLD needs an in-world check of the physical result;
no destructive recovery/purge command is provided here.

## Persistence and reset

Each subsystem owns its namespace:

| Namespace | Owner |
|---|---|
| ws:core, ws:released | Coordinator |
| ws:input, ws:in:* | HUD input |
| ws:eval:result | Eval |
| ws:output, ws:product, ws:out:blank:* | Output |
| ws:kept:*, ws:storage:* | Storage |

Input groups/label indexes are derived caches. A reset during grouping clears
only those caches and rebuilds from the durable raw source rows. Completed
evaluation is cached by run UUID, so retries return the same result. Output's
DONE state acknowledges a repeated START without producing again. Pending
container output and Keep survive subsystem resets.

Storage exposes an internal progressive PAGE API. Publication of multiple kept
lots as sources compatible with the current HUD scan/stock protocol is a
separate remaining hookup; no virtual object UUID is fabricated by this split.

## Internal linked messages

All five scripts are in ROOT. Large input/output data is referenced through
owned records; all treatment messages carry their run UUID in id.

| Code | Purpose |
|---|---|
| 970210 / 970211 | MCW inbound control / outbound wire |
| 970213 / 970214 / 970215 | Input command / progressive step / status |
| 970202 / 970203 / 970201 | Stored-input evaluation / step / result reference |
| 970220 / 970221 / 970222 / 970223 | Output command / outcome / config / step |
| 970230 / 970231 / 970232 | Storage KEEP or PAGE / reply / import step |
| 970298 / 970299 | Subsystem availability query/reply |
| 970290 | Report each subsystem's current llGetFreeMemory |

Send `llMessageLinked(LINK_THIS, 970290, "", NULL_KEY);` from a diagnostic script
in ROOT to request the five memory reports. Measure after reset, input, Eval,
partial delivery, closure and a second preparation. No sixth runtime script is
required for the five production responsibilities.

## Verification

Run `Workshop/tests/run_workshop_split_checks.ps1`. The runner uses the installed
Tailslide parser and exercises the actual script ASTs, including the actual HUD
endpoint, basket and stock relay. Test doubles provide LSL services, containers
and source replies. The before-split Eval fixture is used only for arithmetic
and rule-resolution parity tests, with synthetic laws; it is not an installation
script or a reference for current cutting-board recipes.

These tests do not replace Mono compilation, memory measurements, permissions
or inventory-delivery checks in Second Life. The scripts report existing
persistent errors instead of dropping products or silently retrying dispatch.
