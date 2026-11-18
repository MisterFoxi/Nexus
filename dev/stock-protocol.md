# Nexus — Stock protocol (Model 1: physical objects + server referee)

*Repo spec, amendable. The hot "stock" plane of the network rebuild. High-level rationale in the project doc `socle-refonte-reseau.md`. Model: **reserve / commit / release**, the reservation held by the bench for the whole craft. Rewritten 2026-11-17 (temporal/pause review — see §8).*

---

## 1. Principles

- **Server is the authority on quantities** (the referee). Components stay physical objects carrying their own DNA / identity / freshness; they only cache their count.
- **Evaluation is local and free.** The Workshop holds the selected basket's DNA (from the scan) and runs the engine (`Workshop_Eval`) itself. Deciding *what* a basket produces needs no stock and no server call.
- **Stock is reserved at selection, consumed at commit, released on discard.** Picking a component reserves it immediately (nobody else can take it); the reservation is **held by the bench** for the whole, possibly paused, craft; `COMMIT` consumes, `RELEASE` returns.
- **A craft lives in the bench.** Its reserved stock + state persist (LinksetData) and survive the player leaving or the HUD crashing. The reservation is freed by a **human act** (the next player at the bench chooses *take* or *discard* → discard = `RELEASE`) or by `COMMIT` — **not** by a keep-alive or an arbitrary timeout.
- **Authorization = validity, not ownership, not presence.** A component's *available* count (total minus what's reserved) is consumable by anyone — "abandoned" = exists on the server and not discarded, regardless of whether its object is rezzed or put away. Reserved units are held by a bench's craft until that craft commits or is discarded.
- **Redo on loss.** No bespoke reliable transport; a dropped message = the actor repeats the same op-id; the server deduplicates.

---

## 2. Actors & roles

| Link | Role |
|---|---|
| **Component ↔ Server** | registers its SID + reports validity; receives its authoritative count back |
| **Workshop ↔ Server** | `RESERVE` (at pick) / `RELEASE` (at unpick/discard/inert) / `COMMIT` (at take), all keyed by the bench craft's ticket |
| **HUD ↔ Workshop** | selects (which SIDs, how many) and drives the temporal action; never talks to the server |

The whole pausable craft — selection, the temporal action (grind / heat / elapsed), and the **observation / quality-control** read while paused — is **local to the Workshop**. Observation is a local `Workshop_Eval` consult over the current basket + current action axes: no server, no `INSPECT`, no basket hashing. (The old HUD-resident basket + `INSPECT`/MD5 transport, and `Workshop_Observe`, are gone — the basket lives in the Workshop.) The reservation is orthogonal: it only holds the stock while the craft exists.

---

## 3. Identity — SID (stable across re-rez)

- Each component mints a **SID** (`llGenerateKey`) once, at first boot, stored in `rz_sid` (survives take/re-rez). The volatile SL object key is **not** the identity.
- The server indexes stock **by SID**.
- A **blank that becomes a product** gets a fresh SID **minted by the Workshop** at `COMMIT` (the product is a new thing). The Workshop passes that SID both to the server (`OUT`) and to the blank (in `CONFIG`); the blank adopts it and registers.

### Seeding & anti-reseed

- First-ever `REGISTER` of a SID seeds the count from the NC's declared `Quantity`.
- A known SID is **never re-seeded** (repeat `REGISTER` only reconciles the cache and refreshes metadata).
- Physical copies (each a new SID) each seed once — bounded by next-owner perms, not the server.

---

## 4. Messages

Region say, pipe-delimited, envelope `NX|<VERB>|…`. Channel: `NX_STOCK` (provisional `-918280`). `<ticket>` = the bench craft (one at a time per bench); it keys the held reservation set. All mutating ops idempotent by ticket (+ op-id where needed).

### 4.1 Component ↔ Server

```
Component -> Server : NX|REGISTER|<sid>|<owner>|<dnaHash>|<expiryUnix>|<initQty>
Server -> *         : NX|QTY|<sid>|<available>         ; authoritative AVAILABLE count (total − reserved)
Component -> Server : NX|DISCARD|<sid>                 ; on local expiry; owner-gated
```

- `available` = total minus units currently reserved by any bench. Pushed after any change so caches refresh (a component at 0 available advertises nothing; at 0 total it dies).

### 4.2 Workshop ↔ Server (reserve / release / commit)

```
Workshop -> Server : NX|RESERVE|<ticket>|<sid>:<u>           ; a pick: hold u of sid under the bench ticket
Server -> Workshop : NX|RES_OK|<ticket>|<sid>|<remaining>
                   | NX|RES_NO|<ticket>|<sid>|<available>    ; not enough; nothing held for this pick

Workshop -> Server : NX|RELEASE|<ticket>[|<sid>:<u>]         ; unpick (sid:u) OR whole-ticket release (no sid) = discard/abort/inert
Server -> Workshop : NX|REL_OK|<ticket>

Workshop -> Server : NX|COMMIT|<ticket>[|OUT|<newSid>|<qty>|<dnaHash>]
Server -> Workshop : NX|COMMIT_OK|<ticket>                    ; consumes all held under ticket; creates output SID when OUT present
                   | NX|COMMIT_NO|<ticket>
```

- **Pick = `RESERVE` one line.** Incremental: each pick adds its units to the ticket's held set and subtracts from the SID's available. Unpick = `RELEASE` with that `sid:u`.
- **Discard / abort / inert verdict = `RELEASE <ticket>`** (no sid) → all units held under the ticket return to their SIDs; the bench goes FREE.
- **Take → `COMMIT`.** Consumes everything held under the ticket (already subtracted at reserve time) and, with `OUT`, creates the product SID — even if no blank is present (pending product; a blank adopts it later via `CONFIG`).
- **Idempotency.** The server keys state by `<ticket>` and dedups replays (a re-sent `RESERVE`/`RELEASE`/`COMMIT` returns the stored outcome). The reservation has **no TTL**: it lives until `COMMIT` or `RELEASE`.

### 4.3 Discovery

```
Workshop/Component -> all : NX|DISCOVER|<owner>|<name>
Server -> requester        : NX|SERVER|<serverKey>
```

Server found by **owner + name**, not key. Requesters re-discover on failure.

---

## 5. Free exploration

Design §9 keeps "nothing reacted → matter returned". The verdict depends on the final action axes, known only at the end of the temporal action. So the Workshop evaluates locally at the take; an **inert** verdict → `RELEASE <ticket>` (reserved matter returned, nothing consumed). A consuming verdict → `COMMIT`.

---

## 6. Degraded mode

Server unreachable → picks can't reserve (the HUD reports "stock server unreachable") and commit can't consume. No local decrement, no fork of authority. An in-flight bench craft persists; it resolves (take/discard) once the server is back.

---

## 7. Open points

**Resolved**
- [x] Authorization = server-side validity only, presence-independent (available = total − reserved; unreserved is consumable).
- [x] Reservation lifetime (temporal + pausable craft): **no TTL / no keep-alive**. The craft lives in the bench; the next player's *take* (`COMMIT`) or *discard* (`RELEASE`) frees it. See §8.
- [x] Server persistence/restart: ledger (`sv:q:<sid>`) + ticket holds (`sv:t:<ticket>`) in LinksetData; on boot announce `NX|SERVER`; known SID → server qty wins, unknown → first-seed from NC; wiped ledger reseeds to NC (admin-level).

**Still open**
- [ ] **Orphaned reservation if the bench itself is derezzed mid-craft** (no one left to take/discard). Primary mechanism is the bench; a very long server-side safety sweep can reclaim truly orphaned tickets. Admin-level edge, don't over-engineer.
- [ ] **Ticket GC** for committed/released tickets (`sv:t:*` must not grow unbounded).
- [ ] **Incremental-pick wiring**: the server currently reserves a whole basket in one `RESERVE`; the pick-by-pick flow above needs the per-line add/sub. Settle when wiring the Workshop.
- [ ] **Partitioning** (~128 KB/linkset) and **`dnaHash`** (stored, unused server-side → droppable) — defer to scaling.
- [ ] **Exact `NX_STOCK` channel constant** and cold/hot split.

---

## 8. Design note — the temporal/pause review (2026-11-17)

The craft is **temporal and pausable**: the player applies action axes over time (`fab.grind`, `fab.thermal`, `meta.elapsed_time` …), can **pause**, and the HUD **describes the current situation** at the pause (read-only observation of the state so far). A pause has no bound.

The concern was: a reservation held across an indefinite, pausable craft needs a keep-alive (a crashed HUD would otherwise lock stock forever) or a TTL (which would kill a paused craft). **Neither is needed**, because the craft is **owned by the bench**: its reserved stock and state persist in the bench's LinksetData and survive the player leaving. Abandonment is resolved socially/physically — the next player at the bench chooses **take** (`COMMIT`) or **discard** (`RELEASE`). So the reservation simply lives until a human resolves the bench's craft or it commits.

What the review *did* settle, and keeps: the **basket lives in the Workshop** (not the HUD), so observation is a local `consult()` and `Workshop_Observe` + the entire `INSPECT`/basket-hash transport are dropped.

---

*Reliability model = reserve at pick, hold in the bench, commit or release by a human act, redo on loss. The reservation has no timer: the bench is the holder, the next player is the release valve.*
