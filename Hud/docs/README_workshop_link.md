# HUD endpoint for Workshop

> P3 update: see [README_P3.md](README_P3.md) for current collection, player and closure protocols.
> Historical future-integration notes below are superseded by that guide.


The five-script Workshop counterpart now implements MCW; see
[Workshop installation and memory checks](../../Workshop/README.md).
In-world memory and physical delivery still need verification. No product law
or evaluation lives in the HUD.

## Installation

In the HUD ROOT, replace MC_Selected_Controller, MC_P1_Controller,
MC_P1_Animation and MC_Turn_Z. Add MC_Workshop_Link. Keep MC_Transactions,
scan/render scripts, FURWARE, atlas player, button library and textures.
Remove the obsolete MC_Bench_Test_Bridge from the in-world HUD.

No prim, face, texture or table is added or renamed. P1_TAKE opens recipient
selection on P3 locally; P3_ACTION submits container output after selection.
P1_LATER requests Keep. Keep is rejected for HUD_KIND=cutting_board,
even if an offered configuration enables it. P1_DISCARD retains its existing
stock rules and is blocked during a submitted treatment. EXIT and RETRY are
available through the linked API; optional existing prims named P1_EXIT and
P1_RETRY are also recognized, but this change adds no UI geometry.

Without a Workshop association, the existing DEV selection, gesture and Discard
remain usable. Take reports that an association is required. The stock relay
still uses its existing -918274 channel. MCW uses a separate -918275 whisper
channel. MCW binds the touched player and their HUD; source stock operations retain their same-owner policy.

## Association and lock

All messages are whispers. Common envelope:

`MCW|VERB|targetUUID|sessionUUID|treatmentUUID[|fields...]`

The receiver must check the actual speaker UUID, target, session and treatment.
The HUD remembers one workshop and rejects other offers until RELEASED. The
workshop must implement its own exclusive player lock before offering a session.
HUD-side association alone does not implement the workshop's lock.

- Workshop -> HUD: `MCW|OFFER|avatarUUID|sessionUUID|NULL_KEY|cutting_board|singleType|allowKeep|temporary`
- HUD -> Workshop: `MCW|ACCEPT|benchUUID|sessionUUID|NULL_KEY|avatarUUID|cutting_board`
- Workshop -> HUD: `MCW|BOUND|hudUUID|sessionUUID|NULL_KEY`

OFFER flags are 0/1. NULL_KEY is the full zero UUID. HUD_KIND is a constant in
MC_Workshop_Link; each dedicated HUD sets its own kind. A single ingredient type
means equal name, taxonomy, stage and organ; stock, properties, freshness and
source UUID may differ. Existing baskets are checked again before transmission.
Multiple units and source UUIDs are allowed. The check traverses saved records
one per event and does not maintain another ingredient list.

If temporary=1 and the HUD is rezzed, after BOUND it requests its owner's attach
permission and temporarily attaches at ATTACH_HUD_TOP_LEFT. Already attached
HUDs are left in place. Provisioning is implemented by Workshop; see README_P3.md for owner/visitor behavior. Temporary attach/detach still needs in-world testing.

## Treatment: stop-and-wait transmission

The HUD freezes/saves the existing active clock. It sends the measured active
seconds and spoiled flag, not a recipe or new law. Workshop feeds its action configuration and evaluator input from these values.

1. HUD -> Workshop: `MCW|BEGIN|bench|session|treatment|CONTAINER/KEEP|activeSeconds|0`
2. Workshop -> HUD: `MCW|ACK|hud|session|treatment|BEGIN`
3. HUD -> Workshop: `MCW|ROW|bench|session|treatment|sequence|sourceUUID|heldQuantity|escapedHERE`
4. Workshop -> HUD: `MCW|ACK|hud|session|treatment|ROW|sequence`
5. Repeat ROW/ACK, then HUD -> Workshop: `MCW|END|bench|session|treatment|rowCount`
6. Workshop -> HUD: `MCW|RESULT|hud|session|treatment|OK` or `...|NO|escapedReason`
7. After matching OK, Selected closes the existing held balances through the
   unchanged COMMIT relay. Only matching source OK replies reduce the basket.
8. Once all source closures are confirmed, HUD -> Workshop:
   `MCW|CLOSED|bench|session|treatment`. The HUD keeps P3 active for container output. OUTPUT_CLOSED rearms
   the current collector for the next preparation; see README_P3.md.

sequence starts at 0. escapedHERE is llEscapeURL of the complete saved HERE v5;
it contains name, quantity at discovery, use, lifetime, taxonomy, stage, props,
protocol, freshness snapshot, mesh and organ. heldQuantity is authoritative for
the treatment; discovery quantity is not the selected quantity. Preserve source
metadata separately when converting rows to evaluator input.

The Workshop receiver must accept each sequence once, acknowledge exact
duplicates, validate the complete row count at END, and evaluate/produce once
per treatment UUID. RESULT OK means Workshop has accepted responsibility for
the successful treatment under its existing output flow. For CONTAINER, OK means the valid product is durably ready: missing containers
no longer delay ingredient closure. Product recovery has its own P3 outcome.

The HUD never commits on BEGIN, ACK or timeout. A NO retains the basket and
allows the paused gesture to resume. ABORT is sent for a failed local preflight
or an explicit refusal; it cancels an incomplete upload. No output may be made
from a partial upload before END. Oversized rows are rejected without truncation.

The current saved freshness is transmitted as-is. This HUD change does not
invent a new freshness rule. Workshop remains responsible for product handling.

## Discard, exit and recovery

Local Discard before Start returns units; after Start it closes used units with
COMMIT and waits for source acknowledgements. If bound and idle, completion also
sends `MCW|DISCARDED|bench|session|discardTicket`. No product is requested.

EXIT first uses this same Discard path, then sends
`MCW|EXIT|bench|session|exitTicket`. The HUD retains its association until the
workshop replies `MCW|RELEASED|hud|session|exitTicket`. Only then does it clear
the session and detach a temporary HUD, requesting permission if needed. A
temporary HUD with denied attach permission remains rezzed; use EXIT to release.

The session, current run, sequence, offset and last wire envelope persist in
mc:workshop:session. Pending source balances remain in Selected's existing rows.
Timeouts and resets do not resend radio requests. Local-only preflight is
cancelled; an acknowledged-row traversal can resume locally. Awaiting replies
keeps the treatment frozen. RETRY explicitly repeats the exact saved MCW
envelope, with its existing run/sequence; it never creates a new treatment or
repeats a source TAKE/RETURN/COMMIT. Source timeouts/refusals retain the existing
pending operation; a late matching OK may complete closure.

## Linked API

All messages are between cooperating ROOT scripts.

| Code | Request / response | id |
|---|---|---|
| 918370 | CONTAINER, KEEP, EXIT, RETRY -> link controller | caller ticket |
| 918371 | session phase announcement | session UUID |
| 918372 | SNAPSHOT / UNFREEZE -> gesture owner | treatment UUID |
| 918373 | OK\|seconds\|spoiled, or NO\|0\|0 | treatment UUID |
| 918380 | EXPORT / NEXT\|offset / CANCEL -> Selected | treatment UUID |
| 918381 | BEGIN, ROW\|nextOffset\|source\|qty\|escapedHERE, END, ERROR\|reason | treatment UUID |
| 918382 | internal progressive export | treatment UUID |
| 918384 | internal ingredient-type check | source UUID |
| 918315 | COMPLETE after matching Workshop success | treatment UUID |
| 918317 | CRAFT_DONE after confirmed stock closure | treatment UUID |

CRAFT_DONE resets the ingredient preparation. P3 remains visible until product closure. The public API
does not expose writes to basket records, an evaluator or a second source ledger.

## Verification

Run `Hud/tests/run_workshop_hud_checks.ps1`. It parses actual LSL sources with the
installed Tailslide parser and exercises the actual HUD ASTs. The Workshop side
and source balances in these new scenarios are explicit test doubles. Existing
button, gesture and progress tests also run. These checks do not establish Mono
memory use, inventory permissions, physical delivery or in-world operation.
