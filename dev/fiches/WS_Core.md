# Fiche — WS_Core

*Dev & tracking fiche. See `CONVENTIONS.md` and `claude/socle-refonte-reseau.md` §7-§8. File: `Workshop/WS_Core.lsl`.*

---

## Role

The bench-side state machine. **Current slice:** occupancy lock (reservation) + HUD provisioning + contention/force + bind + a periodic heartbeat that frees the bench when the holder's HUD disappears, and releases the reserved basket on take/discard. Craft phases (select → action → commit) come later. Runs in the bench linkset; shares LinksetData with WS_Boot.

## Current version

`v0.8.1` — the bench is now an **explicit FSM**: a persisted `state:phase` (FREE/RESERVED/CRAFTING/FORGING/COLLECTING/HELD) and a single `transition(event, phase)` point that validates the event, runs the primitive, writes the phase and redraws once; the handlers only translate to events. Same behaviour as v0.7.11 (lock + provisioning/bind + heartbeat + contention/force + take flow forge→held→collect + discard/restitution + validate-on-leave + `NX|HERE` auto-resume), with the §57 floating-text lag fixed.

**Chain (validated in-world):** craft **not started** (no cut) → passive leave restitutes (RELEASE), discard button restitutes; craft **started** (`state:craft="1"`, set by `CRAFTSTART`) → ingredients committed, **no refund** — passive leave **validates** it (forge from the cached last stage → becomes a held product) if a stage is known, else consumes it; discard button consumes; **forged product** (`state:held`) → kept until collected or purged.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — socle §8: touch→lock when OPR & free; probe worn HUD (`NX|HUDQ`→`NX|HUDA`) and give the reference HUD if absent/mismatched; holder present→"in use", holder out-of-region→Force dialog (keeps pending craft); locker re-touch→Release stand-in. Lock persisted in `state:lock`/`state:lockname`/`state:craft`. OPR gate via `WS_OPR` link + `ws:worldver` fallback |
| v0.2.0 | 2026-11-18 | **bind** (ported from `docs/README_workshop_link.md` "Association and lock"): on a successful probe (HUD present) `OFFER` the session; on `NX\|ACCEPT` from the holder's HUD, confirm `NX\|BOUND`. Session minted at `acquire()` (`state:session`), kept across Force, cleared at release. kind/single/keep read from the bench config (WS_Boot → `ws:genre` / `ws:cfg:*`) |
| v0.3.0 | 2026-11-19 | **takeover when HUD gone**: handle `NX\|UNBIND` from the holder's detaching HUD; a newcomer touching gets the Force dialog even if the holder is still in region. Craft kept on force (§8). |
| v0.3.1 | 2026-11-19 | HUD-gone detection made reliable via a contention-time ping (detach `llRegionSayTo` is not reliably delivered). |
| v0.4.0 | 2026-11-19 | **periodic heartbeat**: while locked, ping the holder's HUD every HEARTBEAT (5 s); MISS_MAX (3) unanswered pings → HUD gone → frees the lock on its own. The heartbeat also provisions (gives the HUD once) and binds (OFFER on first answer). Replaces the on-touch contention probe and `gHudGone`. |
| v0.5.0 | 2026-11-23 | **discard flow** (HUD `p1_action3`): inbound `NX\|DISCARD\|<session>\|<started>`. `discardCraft(started)` **keeps the lock & heartbeat**: not started → `STOCK_RELEASE_REQ` (server RELEASE, stock returned, session kept); started → `STOCK_COMMIT_REQ 918251` (server COMMIT, stock consumed, no product) + rotate `state:session` + re-bind (`gBound=FALSE; offerHud`) since the committed server ticket is frozen (`C`). `release()` (Release dialog = leave bench) captures ticket+holder before clearing and passes them in `STOCK_RELEASE_REQ` (link_message is async, LSD already cleared). |
| v0.4.2 | 2026-11-19 | **heartbeat detection refined**: `gPingAck`/`gMisses` reset at (re)arm, HUD given once while unbound (`gGiven`), holder re-touch while unbound re-pings instead of re-probing. **`release()` wired to WS_Stock** (`918250`). |
| v0.6.0 | 2026-11-25 | **TAKE flow**: `EVAL_TAKE_RES 918430` from WS_Take → `takeResult` (code 1 forge / 2 give / 0 inert). Forge-then-collect model: `COMMIT|OUT` (via `STOCK_COMMIT_REQ` extended) → `STOCK_COMMIT_DONE 918431` → `openCollect` (NX\|OUTPUT → P3) → `NX\|CONTAINER` → `collectInto` (`OUTPUT_CONFIG 918440` → WS_Output) → `OUTPUT_DONE 918441` → close (rotate session + re-bind + `NX\|TAKEDONE`). give → `OUTPUT_GIVE 918442`. held-product dialog on touch of a free held bench. |
| v0.7.0-0.7.6 | 2026-11-25 | **held/reprise + restitution rule**: `state:held`(+`state:heldby`) persists the forged product; `freeLock`/`release` keep it (leave ≠ purge). `CRAFTSTART`→`state:craft="1"`; `freeLock` restitutes only an unstarted, un-forged basket. Resume dialogs **Discard/Keep** (held: Keep→P3) and **Keep/Discard** (started prep). `STOCK_DISCARD_REQ 918252` purges a held SID. English in-world strings. |
| v0.7.7-0.7.8 | 2026-11-25 | discard button: **consume only if started** (COMMIT, no refund + rotate + re-bind); **not started → release** (restitute). |
| v0.7.9 | 2026-11-26 | **validate-on-leave**: `freeLock` rewritten — held→kept; started+`state:lastsnap`≠""→`FORGE_CACHED 918432` (forge from cache → held, session kept); started+no snapshot→consume (no refund); unstarted→release. `CRAFTSTART` clears the cache (scoped to this craft). `EVAL_TAKE_RES` no longer checks the lock (forge-on-leave has none). `release()`→`freeLock`. Removed the resume dialog + `discardPending`. |
| v0.7.10 | 2026-11-26 | **auto-resume**: `NX\|HERE` handler (before the holder guard) — a free bench holding a product `acquire`s the announcing avatar → bind → `openCollect` → P3. Floating text simplified to "product waiting". |
| v0.7.11 | 2026-11-26 | **removed `state:heldby`** (no reader left after dropping the name from the text and the held dialog). |
| v0.8.0 | 2026-11-26 | **FSM groundwork**: explicit persisted `state:phase` + boot derivation from the legacy `(lock, craft, held)` tuple (migrates live benches); `transition()` added but unwired. Heap 23590→20518 b (≈3 KB). |
| v0.8.1 | 2026-11-26 | **FSM wired**: every handler (touch / listen / link_message / timer + dialogs) folds onto `transition()`; primitives kept (it calls them). `derivePhase()` covers settled tuples, `FORGING` set explicitly (no stable tuple). **§57 fixed** (FORGING branch in `status()` → "product waiting", no more "bench FREE" flash on forge-on-leave). Removed `release()` (→ `leave`). Confirmed in-world: finishing/discarding a craft **keeps the lock** (→ RESERVED, idle); the bench frees only on leave. |

## Dependencies

- **Scripts (same linkset)**: WS_Boot (consumes its `WS_OPR = 970110` "OPR|<ver>" link; reads `ws:worldver`, `ws:genre`, `ws:cfg:*`); **WS_Stock** (take/discard → `918250 STOCK_RELEASE_REQ`). Later: WS_Scan, WS_Action.
- **Peer (other object)**: the worn HUD (`NX_HudFace`) — answers `NX|HUDA`, accepts the `OFFER`.
- **Channels**: `NX_HUD = -918282` (bench ↔ worn HUD). Dialog on a random negative channel.
- **Inventory**: the reference HUD object, named **`<model> v<X.Y.Z>`**. Given via `llGiveInventory` when the holder lacks it.
- **LinksetData**: `state:phase` (the FSM phase; derived once at boot from the legacy tuple if absent), `state:lock` (holder avatar key, "" = free), `state:lockname`, `state:craft` ("0"/"1" pending craft), `state:session` (bind/craft session, minted at acquire), `state:held` (forged product tenu), `state:stock`/`state:takesrc`, and the validate-on-leave cache `state:lastsnap`/`lastname`/`lastsrc` (written by WS_Eval/WS_Take, read by `FORGE_CACHED`, cleared by `CRAFTSTART`/`closeTake`). Config (from WS_Boot): `ws:genre`, `ws:cfg:HUDKind`, `ws:cfg:SingleIngredient`, `ws:cfg:AllowKeep`. Persistent. *(`state:heldby` removed in v0.7.11.)*
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | `touch_start` | avatar | free→acquire; self (bound)→release menu; self (not bound)→re-ping; other present→"in use"; other away→Force dialog |
| out | `NX\|HUDQ` (NX_HUD, to holder) | benchKey, model, version | heartbeat probe of the worn HUD |
| in | `NX\|HUDA` (NX_HUD, from worn HUD) | model, version | match → ack heartbeat; if unbound → OFFER |
| out | `NX\|OFFER` (NX_HUD, to holder) | benchKey, session, kind, single, keep | bind offer |
| in | `NX\|ACCEPT` (NX_HUD, from worn HUD) | session, kind | session match → confirm BOUND |
| out | `NX\|BOUND` (NX_HUD, to holder) | session | confirm the bind |
| in | `NX\|UNBIND` (NX_HUD, from worn HUD) | session | best-effort fast free on detach |
| in | `NX\|HERE` (NX_HUD, region-wide) | model | free bench holding a product → `acquire` the announcer → bind → P3 (handled before the holder guard) |
| out | link `FORGE_CACHED 918432` (to WS_Take, id=holder) | — | validate a started prep on leave: forge from the cached snapshot |
| in | `NX\|DISCARD` (NX_HUD, from worn HUD) | session, started | discard the craft: RELEASE (not started) / COMMIT + new session (started); lock kept |
| out | `llGiveInventory` | reference HUD | deliver HUD on absent/mismatch (once, while unbound) |
| out | link `918250 STOCK_RELEASE_REQ` / `918251 STOCK_COMMIT_REQ` | ticket, holder | discard-return / discard-consume → WS_Stock |
| in | link `WS_OPR` (970110) | `OPR\|<ver>` | mark ready (accept reservations) |
| in | link `970290` | — | memory report |

## Behaviour notes

- **Lock = craft lifetime**: acquired on touch (OPR+free), released by take/discard (`release()`) **or** automatically when the holder's HUD stops answering the heartbeat (`freeLock`, which keeps a pending craft — §8, never auto-discards).
- **Heartbeat**: `HEARTBEAT = 5 s`, `MISS_MAX = 3` → ~15 s to free after the HUD is removed. While unbound the heartbeat also gives the HUD once (`gGiven`) and OFFERs on the first `HUDA`.
- **Session**: minted at `acquire()` as `state:session` (the craft ticket), kept across Force, cleared at release. Keys the bind and the stock reservation (stock-protocol §4).
- **Force**: offered only when the holder is out of region; transfers the lock and keeps any pending craft + session.
- **OPR gate**: `WS_OPR` link sets ready; a lone WS_Core reset infers readiness from `ws:worldver != ""` and resumes the heartbeat if `state:lock` is set.

## Open points / debt

- [ ] 2026-11-19 — version match is exact; a semver `>=` compare would avoid re-giving a newer HUD.
- [ ] 2026-11-19 — `llSetText` shared with WS_Boot (socle §6); WS_HMI will own the text layer.
- [x] 2026-11-25 — **TAKE** wired (forge `COMMIT|OUT` → held → collect into récipient → close).
- [x] 2026-11-26 — **floating text lag at validate-on-leave fixed** (v0.8.1): `status()` shows "product waiting" whenever `state:phase == FORGING`, so the forge-on-leave window no longer flashes "bench FREE".
- [ ] 2026-11-25 — after a **Keep** (held product), the reserved basket isn't re-pushed to SELECTED (HUD mirror empty on re-bind); add a basket re-sync from the bench.
- [x] 2026-11-26 — `release()` now delegates to `freeLock` (same restitution/validate rule).
- [ ] 2026-11-26 — a held product is **not person-locked**: any HUD of the right owner returning to range auto-resumes it (acceptable; storing the crafter key would reserve it to one person).
- [ ] 2026-11-19 — `freeLock` keeps a pending craft+session; `acquire()` does not yet prompt take/discard for an inherited craft (no craft tracking on the bench yet).
- [ ] 2026-11-19 — `gBound` is not persisted; a WS_Core reset drops it and the heartbeat re-binds on the holder's next `HUDA`.

## Test (in-world)

1. Bench at OPR. Touch (HUD worn, correct name) → "Bench reserved"; within a heartbeat → "HUD bound" (owner + bench).
2. Touch (no HUD worn) → HUD delivered once; wear it → next heartbeat binds (no re-touch needed).
3. Touch again (holder, bound) → Release dialog → Release → bench FREE (session cleared, WS_Stock basket released).
4. Remove the HUD → within ~15 s the bench frees itself (pending craft kept).
5. Second avatar touches while you hold it and are present → "in use by <you>"; leave the region → Force → they become holder, pending craft + session kept, then re-bind.
