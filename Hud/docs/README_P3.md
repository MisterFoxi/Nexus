# P3 — finished product collection

Take submits the preparation from P1; P3 opens only for evaluated container output. Ingredient
selection, recipe evaluation, KEEP and mesh/organ CUT/GIVE retain their existing owners.
Install the updated scripts together on an idle station/HUD; do not mix old MCW endpoints.

## Scripts and geometry

Workshop ROOT: replace Workshop.lsl, Workshop_HUD.lsl and Workshop_Output.lsl.
HUD ROOT: replace MC_P1_Controller.lsl, MC_Workshop_Link.lsl and MC_Turn_Z.lsl; add/update MC_P3_Controller.lsl,
MC_Render_P3_NEAR.lsl and MC_Render_P3_SEL.lsl. Keep MC_Scan, P0/P1 controllers,
renderers, animation, stock relay and FURWARE.

Apply the existing assets/Hud-p3.png to the P3 panel. There is no P3 Discard button or product Discard protocol. Buttons have no scripts; touches reach ROOT.
The script files cannot create or verify the in-world HUD assembly.

Physical rows are indexed n=0..3. Names follow the enumerated HUD assembly:

| Purpose | Prim/table |
|---|---|
| Nearby names, Selected names | P3_Table1, P3_Table2 (FURWARE: 4 rows x 24 characters) |
| Icons | P3_Near_Icon_n, P3_Selected_Icon_n |
| Capacity digits | P3_Near_Tens_n / P3_Near_Unit_n; P3_Selected_Tens_n / P3_Selected_Unit_n |
| Pagination | P3_Near_PREV, P3_Near_NEXT, P3_Near_Actual, P3_Near_Pages; P3_Selected_PREV, P3_Selected_Next, P3_Selected_Actual, P3_Selected_Total |
| Add/remove recipient | P3_Near_Remove_n (+ selects), P3_Selected_Remove_n (X removes) |
| Commands | P3_REFRESH, P3_ACTION (Transfer) |
| Optional explicit retry | P3_RETRY |

All UI surfaces use face 1. MC_Turn_Z has a P3_Z
installation constant defaulting to PI_BY_TWO (90 degrees); set it to the actual
mesh orientation before installing. P1 Take no longer rotates immediately to P0.
P1 Take submits for evaluation; authenticated WAIT_CONTAINER opens P3.
Ingredient CRAFT_DONE cannot rotate it away.
P3 closes after OUTPUT_CLOSED/RELEASED.

## Take evaluates before selecting containers

P1_ACTION2 or the compatible P1_TAKE name (Prendre) sends the existing CONTAINER
choice directly to MC_Workshop_Link. The existing gesture snapshot, progressive
ingredient upload, rule evaluation and refusal handling run while P1 stays visible.
No pre-evaluation container scan or SELECTING page is opened.

For rule output `give` or `give=<organ>`, Workshop_Output dispatches CUT/GIVE.
After that completes, Workshop returns optional success detail `RESULT|...|OK|GIVE`.
The HUD announces `Objet remis dans votre inventaire.`, closes ingredient commitments
through the existing COMPLETE path and returns to P0. No container selection or
Transfer click is needed. Replayed results cannot redispatch GIVE; a refused recipe
keeps the preparation and stays on P1.

For transformed output, authenticated WAIT_CONTAINER opens P3 and starts discovery.
Used ingredient commitments close independently of collection, as before.
If discovery finds no recipients, the nearby table displays:

```text
Aucun conteneur vide.
Placez-en a proximite
puis cliquez Actualiser.
```

These informational rows remain unoccupied: icons/quantities stay hidden and clicking
them cannot select an object. During discovery the table instead shows a search
message. Once every available container is selected, it prompts Transfer.
P3_ACTION1 refreshes; P3_ACTION2 fills only explicitly selected recipient UUIDs.
P3 Transfer never submits a new preparation. Terminal closure clears the table and
returns to P0. Product status/selection recovery never replays physical delivery.

Update together in HUD ROOT: MC_P1_Controller.lsl, MC_P3_Controller.lsl,
MC_Render_P3_NEAR.lsl, MC_Workshop_Link.lsl and MC_Turn_Z.lsl. Update
Workshop.lsl in Workshop ROOT. Existing component icons and transfer validation stay
in place. `Hud/tests/run_take_routing_checks.ps1` analyzes the scripts and executes
the real routing ASTs with simulated SL services. Verify the visible messages,
inventory receipt and rotations in Second Life after installation.

Legacy four-, six- and seven-field selection records remain readable. Obsolete
preselection/submission flags are ignored. A pending real container output is
recovered from its matching persisted/authenticated output state.

## Scan, selection and transfer

P3 uses the existing MC_Scan API directly: 918270 with channel -918273; responses
918271..918274 with the matching scan UUID. P0's Refresh adapter keeps -918274.
The shared scanner has one active request: concurrent Refresh replaces a scan;
an interrupted P3 scan keeps the last complete view and reports its timeout.

BLANK|UUID|capacity with an optional final icon UUID, a nonnegative integer capacity
and the HUD owner's object are selectable. Object name plus resolved icon UUID defines the displayed group; raw UUIDs remain individual transfer destinations.
Capacity 0 retains the existing unlimited meaning (digits are hidden). Quantities
above 99 and page counters above 9 retain the P0 renderer's hiding behavior.

The nearby table has four rows; the selected table has one grouped row. Each has its own wrapping page cursor. Plus selects a unique
container UUID; X removes it. Neither operation touches the ingredient basket.
Refresh removes recipients no longer present in its completed snapshot.
Selections and the current pending request survive resets; automatic batch traversal
does not resume after reset. Use explicit Retry for an unanswered saved request.

Transfer walks selected recipients in selection order, one request/reply at a time.
Workshop_Output revalidates each selected UUID through production PING/BLANK,
checks recipient ownership against the current player, and sends CONFIG only to
that UUID. Filled recipients leave the selection. A missing/foreign recipient stops
the batch without consuming product. The Workshop owns all product metadata,
capacity arithmetic and remaining quantity. No destination is inferred from a
HUD-supplied capacity, and no unselected container is filled.

## Protocol

Existing MCW envelope and channel -918275 remain:
MCW|verb|targetUUID|sessionUUID|productRunUUID|fields...

| Direction | Verb and fields |
|---|---|
| Workshop → HUD | OFFER gains optional final OUTPUT for a collection-only association |
| Workshop → HUD | OUTPUT_STATE|outputPhase|remaining|escapedProductName |
| HUD → Workshop | OUTPUT_STATUS |
| HUD → Workshop | TRANSFER|operationUUID|containerUUID |
| Workshop → HUD | OUTPUT_REPLY|TRANSFERRED/TRANSFER_NO/TRANSFER_EXPIRED|operationUUID|remaining |
| Workshop → HUD | OUTPUT_CLOSED |

Existing ACCEPT/BOUND establish the collection association. Actual speaker UUID,
target, session, run and collector HUD are checked. The latest exact operation
receipt can answer an explicit retry without repeating CONFIG. Requests are
serialized; starting another command while a reply is pending is blocked.

HUD linked API: 918390 TRANSFER|containerUUID (id=operation UUID), or
STATUS; 918391 outputPhase|remaining|escapedName (id=product run); 918392
status|operationUUID|remaining (id=product run). Renderers reuse 918290/918291 and
the 18 escaped fields with panel identities P3_NEAR and P3_SEL.

## Ingredient closure and product closure

Immediately after valid container product creation, Output persists WAIT_CONTAINER
and reports READY internally. The existing RESULT OK then starts the original HUD's
COMPLETE/COMMIT path immediately, without waiting for collection. It produces no
second user-facing craft-completion notification.

CRAFT_DONE still means confirmed ingredient stock closure, followed by CLOSED.
The Workshop records ws:closed and moves to PRODUCT while output remains. P1
Discard still means RETURN before Start or COMMIT after Start. P3 provides no product Discard command.

Touching a pending product selects the current player, then opens P3 on that
player's dedicated HUD. No reservation or handover command is introduced. Origin
identity in ws:core remains separate from ws:collector. Only the origin can close
its ingredient commitments. A different collector cannot COMMIT the origin's stock.

Transfer by another collector can finish even if the original HUD has
unconfirmed COMMIT replies. Another preparation remains blocked until those replies
arrive and CLOSED is recorded. Once both closures are confirmed, the collector's
session becomes BOUND/IDLE and the previous HUD is released. A missing origin HUD
or source acknowledgement is never assumed settled.

In DEV=1 the player wears their own dedicated HUD. In DEV=0 the station owner can
use existing rez/temporary attach; for another player, the station gives HUDObject
to their inventory and asks them to wear it. OFFER is repeated during association,
not stock commands. Inventory copy/transfer permissions and actual attachment must
be checked in Second Life. Merely rezzing a station-owned object cannot give a
different player an owned HUD. Ingredient stock access remains same-owner.

## Product lifetime and effects (Workshop 0.8.0)

Partial transfers share the lot's absolute expiry. Time waiting in the Workshop,
including offline time across resets, reduces its remaining lifetime. Output
retires an expired remainder and closes product output; it does not resend stock
operations. Recipient Component v0.7.3 honors the optional expiryUnix CONFIG field.
Old perishable pending products without an expiry are retained in HOLD for
inspection; no new age is invented. See Workshop/README.md for installation.

HUD MC_P1_Animation emits 918394 with 0/1 for the actual active clock.
MC_Workshop_Link sends authenticated MCW ACTIVITY while idle, and Workshop
forwards cosmetic state to Output. Smoke/CookSound follow activity; there is no
additional cooking duration. Ready and failure sounds and the component HOVER
menu are retained. Player information is informative and adds no reservation.

## Persistence and physical limits

New Workshop records: ws:collector (run, player, HUD, session), ws:closed (run),
ws:out:request and ws:out:receipt. The existing ws:output owns remaining quantity.
HUD records: mc:p3:output and mc:p3:selection; source balances stay in Selected.

CONFIG and GIVE still have no physical acknowledgement. DISPATCH_CONFIG/GIVE
restore as HOLD; the physical outcome must be checked in-world. RECEIPTING restores
the saved post-dispatch quantity and finishes the receipt without another CONFIG.
Reset never automatically resends a source operation or a transfer request.

## Verification

After authenticated OUTPUT_CLOSED or collector RELEASED, the HUD requests both P0
views again and starts the existing P0 Refresh (918287 / KEEP_PAGE). This rebuilds
Nearby through its normal scan and validates/renders Selected. P3 cancels its local
scan wait and ignores late results after closing. Duplicate OUTPUT_CLOSED while
already IDLE does not restart Refresh. While OUTPUT or WAIT_TRANSFER is pending,
MC_Workshop_Link asks OUTPUT_STATUS at most once per 10 seconds so the existing
Workshop finishProduct path can repeat a lost closure confirmation. It never
replays TRANSFER, CONFIG or an ingredient transaction for this recovery.

Run Workshop/tests/run_workshop_split_checks.ps1 and Hud/tests/run_workshop_hud_checks.ps1.
Tests include test_p3_take_sequence.py for Take without submission, required
recipient selection, delayed stock closure, refusal, duplicate clicks and resets.
They parse the actual scripts and execute AST scenarios for stock closure,
different owners, partial delivery, stale collectors, removed-Discard rejection, resets, selection,
independent pagination and request matching. These do not establish Mono compilation,
64 KiB memory use, mesh orientation, FURWARE geometry or inventory/attach permissions.
