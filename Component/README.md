# Component v0.6 — HUD source migration

The component retains its stock, notecard identity, original lifetime/expiry,
container CONFIG behavior and CUT/GIVE mesh delivery. Product evaluation stays
in Workshop_Eval. Axis names follow `compiler/axes.src`.

## HUD protocol

Discovery uses the existing `PING`, `HERE` (proto 4), `BLANK` and `GONE` formats.
Production listens on **-918273**; **-918274** supports the current development
HUD without modifying it. Component replies use **llWhisper**, on the request
channel. MC requests follow the current HUD's same-owner access policy.

```
MC|TAKE|sourceUUID|requestUUID|1
MC|RETURN|sourceUUID|requestUUID|1
MC|COMMIT|sourceUUID|requestUUID|units
MC|RESULT|sourceUUID|requestUUID|TAKE/RETURN/COMMIT|OK/NO|remainingStock
```

TAKE immediately removes one available unit and records it as held by the
speaking HUD object. RETURN restores one unit held by that same object.
COMMIT closes a positive number of that object's held units without debiting
stock again; used or discarded units must be committed. Unused units must be
returned. Other clients cannot return or commit these held units.

Stock, held balances and the latest reply per client are saved together in
`mc:component:stock` before a reply is sent. Existing `rz_qty` initializes the
migration and remains a compatibility mirror. Reset restores the authoritative
record; it does not refill stock or renew lifetime. A failed authoritative
write applies no mutation and sends no acknowledgement.

Repeating the **latest** identical request from a client repeats its saved
reply without mutating stock. Conflicting reuse of that UUID is ignored.
This is not a historical replay journal: older request IDs must not be resent
after another request. Client records are retained for that latest receipt;
the linkset-data per-value limit bounds their total capacity. A full record
fails closed through the checked write, with a diagnostic.

## Lifetime and craft closure

The original expiry continues advancing during a craft. Expired sources are
not offered by discovery and refuse new TAKEs. RETURN, COMMIT and existing mesh
delivery remain available to finish the engaged operation. An engaged source
is not destroyed by either expiry or an empty-stock timeout, including after
reset. Once all clients have closed their held units, a zero-stock or expired
source calls `die()` on the next timer (the existing two-second mesh-delivery
window is retained). A nonexpired source with remaining stock stays available.
An expired source with no craft in progress still dies normally.

Legacy production CONSUME/REFUND/COMMIT remain supported using the same stock
and held balances, keyed by the actual sending workshop object. REFUND cannot
restore more than that workshop holds. Legacy requests have no request UUID.
Replacing the script during an already-open legacy reservation cannot recover
the old reservation owner: migrate components with no craft in progress.

## Remaining integration

The HUD relay now whispers TAKE, RETURN and COMMIT. For a component-only
test, use the existing P1 Discard button after Start: Selected commits all held
units per source and waits for OK before clearing those units. Before Start,
Discard continues to RETURN unused units. No product is created by this test.
Missing/refused COMMIT replies retain the saved request and block completion;
no request is automatically resent, including after reset. A late OK can finish
closure. The same-owner policy and development channel remain unchanged.
The full Workshop/product-output integration is still pending.

Local verification uses Tailslide syntax/type checking and deterministic tests
executing the actual Component LSL AST. These do not replace Mono compilation,
memory measurements or in-world verification.
