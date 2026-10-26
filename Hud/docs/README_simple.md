# Development HUD - simple Selected basket

Active guide. Crafting, Component, Workshop, and Workshop_Eval are unchanged.
Test channel: **-918274**. Keep this test on the test channel.

## Installation

In the root prim, replace `MC_Selected_Controller`, `MC_Transactions` (this
filename now refers to a simple relay), `MC_Nearby_Controller`, `MC_Render`,
`MC_Render_Selected`, and `MC_Turn_Z` together. Keep Scan, Scan_Refresh, and
FURWARE. Buttons contain no scripts.

Install `../tests/fixtures/MC_Transaction_Fixture.lsl` in each separate test source.
Stop old versions before loading new ones.
Remove the temporary `MC_Bench_Test_Bridge` from the HUD during this test: its
old Cancel/Commit decisions are no longer connected. Its file is archived in
`../archive/2026-10-23/scripts/`.

**Explicitly requested DEV cleanup:** on startup, Selected deletes only
`mc:selected2` and `mc:tx2`; the fixture deletes only `mc:fixture2` in its source.
The former assembly's basket and debts are neither imported nor refunded.
The new assembly starts with an empty basket; fixture profiles return to their
initial test stock. No other Linkset Data is deleted. Do not use MC_RAZ_HUD.
Once created, new data survives ordinary resets.

## Behavior

- `+` takes one unit from the source; Selected increases only after its OK reply.
- `X` returns one unit to that source; Selected decreases only after OK.
- Multiple additions from the same source share a row.
- Continue sends only `CONTINUE` on 918310 and rotates the HUD. The basket
  stays in Selected. There is no second debit, COMMIT, or manufacturing step.
- The choice to use or return ingredients from crafting will be connected later.
- An unanswered request is never resent automatically. After 15 seconds,
  other sources become accessible. The uncertain source remains blocked and
  its ingredients remain visible but excluded from the available basket.
- A reset preserves pending requests without resending them. A late reply can
  still confirm a request. There is no recovery button or invented refund.

**Explicit exception - P1 Discard before Start:** abandoning the basket clears
unresolved requests and abandons the units in those rows. They no longer prevent Discard
completion or the HUD's return to page 0. Late replies to cleared requests are
ignored. See `README_P1.md`. Ordinary resets outside Discard continue to preserve
pending requests.

## Storage and messages

LSL scripts use no JSON, session, individual-take ledger, TX2 journal, global
registry, or automatic basket settlement.

`mc:simple:row:SOURCE` contains six pipe-separated fields: confirmed quantity,
last applied request, pending request, TAKE/RETURN, requested amount, and HERE
escaped with llEscapeURL. Quantity updates and pending-request clearance are
written into the same value. Zero-quantity rows retain their small records.
Selected reads one record per event to count pages and keeps only four rows
in memory.

The fixture stores `mc:simple:source` (UUID, profile, base stock) and a small
`mc:simple:held:HUD` record per HUD (held quantity and latest reply). It gradually
recalculates stock from those balances at startup. This is not a journal: only
the last identifier per HUD detects an immediate repeat; no history is rebuilt.

Radio (whisper): `MC|TAKE|sourceUUID|requestUUID|1`,
`MC|RETURN|sourceUUID|requestUUID|1`, and after Start/Discard
`MC|COMMIT|sourceUUID|requestUUID|heldQuantity`;
reply: `MC|RESULT|sourceUUID|requestUUID|TAKE/RETURN/COMMIT|OK/NO|stock`.
Component v0.6 understands this format on the development channel. COMMIT closes
held units without a second debit. Selected clears them only after matching OK;
missing/refused COMMIT keeps the pending request and blocks Discard completion.

Linked messages: 918301 requests `TAKE/RETURN|source|1` or `COMMIT|source|heldQuantity`; 918302 reports BUSY/IDLE;
918303 returns `TAKE/RETURN/COMMIT|source|OK/NO|stock`; 918304 acknowledges persistence;
918305 reports `source|stock`. The request identifier is in id, except BUSY/IDLE.
918307 drives Selected's incremental traversal; 918308 drives fixture startup.
918309 requests memory measurements. 918311 is no longer handled.
918290 views retain 18 URL-escaped, pipe-separated fields.

## Verification

`../tests/run_hud_checks.ps1` checks syntax and executes scenarios against ASTs
of the actual scripts. JSON used by Python/Node AST tooling stays outside LSL.
See the root README for the runner's currently missing memory-probe dependency.

In Second Life, compile in Mono; check +, X, pagination, and Continue, then reset
Selected, the relay, and the fixture. Also test a suppressed reply
(`DROP_REPLY=TRUE`), a duplicate reply, and two HUDs sharing one source.

For memory measurements, temporarily install `../../Tools/MC_Memory_Probe.lsl`
in the HUD root, touch the root prim itself, and record Selected's and the
relay's free memory and observed minimum. This optional file is not present in
this checkout. Repeat after several pages, additions, removals, and waits. The
same tool works on a fixture; its profile may change if it has not yet received
a request. Remove the probe after measurement. Sampled counters cannot prove
the peak between samples. Local tests simulate memory and never validate Mono's
64 KiB limit.

## Review notes

`REVIEW` comments identify unresolved implementation limits without changing
behavior. Scan snapshots have no count or payload budget. Zero rows remain
persistent forever, eventually using storage and traversal time. Same-prim
linked messages assume trusted cooperating scripts. The source fixture only
deduplicates the most recent request per HUD; it is intended for development.
