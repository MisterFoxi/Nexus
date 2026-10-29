# P1 craft page - the same Selected basket

> P3 update: see [README_P3.md](README_P3.md) for current collection, player and closure protocols.
> Historical future-integration notes below are superseded by that guide.


Companion to `README_simple.md`. P0 remains the generic selection page: its
prims, rendering, and pagination are unchanged. The source relay and Component stock contract remain unchanged. The basket controller now handles Discard and a
craft-start flag; Workshop integration is active; P3 owns finished-product collection.

## Installation

In the HUD root prim only:

1. Replace `MC_Selected_Controller.lsl`: generic RETURN, Discard, and craft-start
   entry points. This controller remains the only basket writer.
2. Add `MC_P1_Controller.lsl` and `MC_Render_P1.lsl`.
3. Replace `MC_Turn_Z.lsl` to return to local Z = 0 after Discard. Keep P0's
   renderers, `MC_Transactions`, and FURWARE. Remove the DEV bridge
   `MC_Bench_Test_Bridge` as described in the active guide.

Buttons contain no scripts. Configure the FURWARE `P1_Table1` table beforehand
as **4 rows of 24 characters**, with the desired font and color. The renderer
sends text to this table; it does not create its FURWARE geometry.

Exact names, with n from 1 to 4:

| Element | Prim / table |
|---|---|
| Icon | `P1_Icon_n` |
| Return one unit | `P1_REMOVE_n` |
| Tens | `P1_TENS_n` |
| Units | `P1_UNIT_n` |
| Names | `P1_Table1` |
| Wraparound navigation | `P1_PREV`, `P1_NEXT` |
| Current page | `P1_ACTUAL` |
| Page count | `P1_TOTAL` |
| Abandon basket | `P1_DISCARD` |

The exact names are `P1_UNIT_n` (n from 1 to 4) and `P1_TOTAL`.
Faces are configurable at the top of `MC_Render_P1`: icons use **2**; quantities,
current page, and page count use **4** by default. Verify these faces in SL:
the HUD page number does not identify a prim's texture face. Use the
`medieval_digits_atlas_5x2` atlas, as on P0.

## Behavior

- Continue keeps the existing `918310 / CONTINUE` message, with a ticket in `id`.
  Only `MC_Turn_Z` performs the 180-degree local rotation.
- Each valid Continue opens P1 at Selected's current page. P1 arrows then
  navigate independently and never change P0's page.
- P1 rereads the same `mc:simple:row:SOURCE` records, one per event, retaining
  at most four UUIDs and four rows. It creates no second basket or persistent
  storage and sends no TAKE when opened.
- Before crafting starts, `REMOVE` requests RETURN of one unit from the P1
  row's source. Quantity decreases only after OK and persistence by Selected.
  Both views then update. Refusals, pending requests, and late replies retain
  the relay's existing rules, with no automatic resend.
- Uncertain rows remain visible, as in Selected. They have no distinct visual
  style; their source remains blocked against new requests.
- Empty rows clear names, icons, and digits. An empty basket displays 1/1.
  If the page count decreases, P1 clamps to the last valid page.
- Quantities above 99 and page indicators above 9 are hidden with an English
  diagnostic, as in the existing renderer. Stored data remains intact.
- After reset, P1 rebuilds its view and retrieves P0's page through the existing
  generic interface. P1's own pagination is not persisted.
- Visual Cut/Stop integration with the `P1_DISPLAY` atlas is described in
  `README_Atlas.md`: `MC_Atlas_Player`, `MC_P1_Animation`, `MC_Playback_Buttons`,
  plus MC_Chop_Progress and all three atlas textures belong in ROOT. STOP,
  Later and page navigation suspend without clearing progress or the used latch.
  Confirmed ingredient Discard or craft closure releases the preparation. Take submits to Workshop; P3 handles container output with its own selection buttons.

## Discard and the craft flag

`gCraftStarted` is false before crafting actually begins. Once set, it stays
true after Stop, Continue, and resets. It is saved in the small
`mc:simple:craft_started` value (0/1), without JSON or a global registry.

MC_P1_Animation now requests `918315 / CRAFT_STARTED`, with a UUID in `id`,
and waits for matching `918317 / CRAFT_STARTED` before starting playback and its
active-time clock. The basket controller persists the flag first. Subsequent CONT
never sends another start request. This does not add another source stock debit.

`P1_DISCARD` requests `918315 / DISCARD` with a ticket in `id`:

- **Flag false:** return every basket unit, across all pages, one at a time
  through the existing RETURN path. Every decrease waits for OK.
- **Flag true:** send `MC|COMMIT|source|request|heldQuantity` through the
  existing relay, one source at a time. Quantities decrease only after the matching
  OK and persistence. Ingredients are lost; stock is not debited again and no
  product is created. This is the Component v0.6 closure test path.
- With the flag true, missing/refused COMMIT replies retain quantities, the exact
  saved pending request and the used-preparation flag. Discard cannot finish until
  a matching OK arrives. Reset never resends; a late OK can finish closure.
  Other pre-existing pending operations also await their replies in this mode.
- **Before Start only**, Discard first clears existing pending requests, including invisible TAKEs
  with zero confirmed quantity. Each uncertain row is zeroed, its pending
  request and operation are cleared, and the relay is released. Remaining
  units from that source are abandoned without invented returns or resends.
- Before crafting, other confirmed rows are returned normally. If a new RETURN
  receives no reply, the relay's usual timeout (about 15 seconds) expires and
  the row is abandoned. NO also abandons the rest of that row and continues
  Discard. An absent source cannot block completion indefinitely.
- A late reply to a cleared request is ignored: its UUID no longer matches
  a saved request. It cannot recreate the basket or block it again.
- Manual additions and removals are blocked during Discard. After crafting
  starts, additions and returns remain blocked until the basket is discarded.
- Discard mode (0 inactive, 1 return, 2 commit used units) is saved in `mc:simple:discard`
  so an interrupted traversal can resume after reset. No second basket,
  history, or automatic resend is created.
- Once all rows are returned/abandoned before Start, or confirmed committed after Start, reset the craft flag,
  emit `918317 / DISCARD_DONE`, clear names, and hide P1 icons, digits, and
  counters. The renderer preserves this cleared state after `fw_ready`.
- `MC_Turn_Z` receives the owner's `P1_DISCARD` touch directly and immediately
  sets **local Z = 0**, preserving local Euler X/Y angles. It reapplies that
  position idempotently on `DISCARD_DONE`. The visual return to page 0 is
  independent of source exchanges; cleanup and returns continue to completion.
- An empty basket, including one emptied by abandoning pending requests,
  finishes Discard even without a relay IDLE message. Confirmed RETURN and
  COMMIT requests both use the relay. A pending COMMIT is never abandoned.

User messages are in English. The chop progress display is now reset on confirmed
DISCARD_DONE; no additional result display is cleared:
there is currently no visual crafting table.

### Former Discard blocking behavior

The old `Discard blocked:` message and unlimited wait have been removed.
Replace `MC_Selected_Controller` and `MC_Turn_Z`: persistent mode restarts
traversal and abandons old pending requests; Discard directly returns the HUD
to page 0. P1 scripts subsequently receive `DISCARD_DONE`.
Ordinary resets preserve pending requests. The old uncertainty-abandonment
rule now applies only to Discard before Start. After Start, confirmed Component
COMMIT closure takes precedence and unresolved requests remain recorded.

## Local messages

- **918312**, text `RETURN`, `id` = source UUID: generic basket entry point.
  Selected checks quantity, pending state, and relay state, then uses the
  existing RETURN path. The caller supplies neither quantity nor stored data.
- **918313**: internal incremental P1 traversal, with render token in `id`.
- **918314**, `id` = `P1`: the same 18 escaped fields used by Selected views.
- **918291**, text `P1`: P1 renderer requests its view from the P1 controller.
  At startup, the controller also requests the generic `SELECTED` view to
  discover P0's current page without changing it.
- **918305**: after Selected persists a result, P1 rereads the basket.
- **918309**: memory measurement, also supported by the P1 controller.
- **918315**: `DISCARD` or `CRAFT_STARTED` request; UUID ticket in `id`.
- **918316**: internal incremental Discard traversal, one record per event.
- **918317**: `CRAFT_STARTED` or `DISCARD_DONE`; ticket in `id`.
- **918314 / CLEAR**, `id` = `P1`: completely clear the craft-page rendering.

These exchanges are between scripts in the same root prim. No JSON, TX2,
global registry, second debit, or new radio operation is involved: Discard
before crafting uses only existing RETURN requests.

## Verification

`../tests/run_hud_checks.ps1` includes P1 syntax checks, `../tests/test_hud_p1.py`,
and `../tests/test_hud_discard.py`. See the root README for its missing optional
memory-probe dependency.
Tests execute ASTs of actual scripts, checking Continue without a debit,
independent pagination, correct removal UUIDs, lost then late replies, empty
baskets, reduced page counts, and resets. The tooling uses the LSL parser
already installed in VS Code; it does not use the project's `compiler` folder.

In Second Life, compile in Mono and check faces, the atlas, FURWARE, page
inheritance after Continue, independent navigation, REMOVE, Discard before/after
start, and delayed replies. Also verify local Z = 0 and cleared counters. Reset
Selected, the relay, both P1 scripts, and FURWARE separately. Measure script
memory in SL, especially after several pages and removals. Local tests cannot
validate the 64 KiB Mono limit per script.

## Review notes

`REVIEW` comments mark unresolved limits without changing behavior: Discard and
craft flags are written separately, views share persistent records without a
snapshot transaction, and P1's closed state is not persisted. Pending rows are
intentionally visible without a distinct uncertainty indicator. The animation requests and waits for the persisted CRAFT_STARTED handshake.

## Playback controls, progress and used preparations

`MC_P1_Animation` connects the player, button library and progress renderer in ROOT.
P1_CUT becomes CONT immediately after the first committed start and never reverts
to START for that preparation. P1_STOP suspends, including repeated clicks. CONT
resumes the same active time. Later and page CONTINUE navigation also suspend.
Confirmed DISCARD_DONE or CRAFT_DONE clears the used latch. Explicit restart marks Spoiled.
Import `atlas_buttons` and `atlas_progress` into ROOT, configure visible faces,
and use the unique prim P1_PROGRESS. Full timing/installation details are in
`README_chop_progress.md`; its default duration to Over the top is 10 active seconds.
