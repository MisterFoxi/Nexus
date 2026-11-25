# Fiche — WS_Core

*Dev & tracking fiche. See `CONVENTIONS.md` and `claude/socle-refonte-reseau.md` §7-§8. File: `Workshop/WS_Core.lsl`.*

---

## Role

The bench-side state machine. **Current slice:** occupancy lock (reservation) + HUD provisioning + contention/force + bind + a periodic heartbeat that frees the bench when the holder's HUD disappears, and releases the reserved basket on take/discard. Craft phases (select → action → commit) come later. Runs in the bench linkset; shares LinksetData with WS_Boot.

## Current version

`v0.5.0 (SCRIPT_NAME "WS_Core")` — reservation lock + HUD provisioning/bind + heartbeat + contention/force; **HUD discard wired**: `NX|DISCARD|<session>|<started>` → `discardCraft(started)` (not started → RELEASE/return; started → COMMIT/consume + fresh session + re-bind, lock kept); `release()` (leave-bench dialog) passes ticket+holder to WS_Stock.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — socle §8: touch→lock when OPR & free; probe worn HUD (`NX|HUDQ`→`NX|HUDA`) and give the reference HUD if absent/mismatched; holder present→"in use", holder out-of-region→Force dialog (keeps pending craft); locker re-touch→Release stand-in. Lock persisted in `state:lock`/`state:lockname`/`state:craft`. OPR gate via `WS_OPR` link + `ws:worldver` fallback |
| v0.2.0 | 2026-11-18 | **bind** (ported from `docs/README_workshop_link.md` "Association and lock"): on a successful probe (HUD present) `OFFER` the session; on `NX\|ACCEPT` from the holder's HUD, confirm `NX\|BOUND`. Session minted at `acquire()` (`state:session`), kept across Force, cleared at release. kind/single/keep read from the bench config (WS_Boot → `ws:genre` / `ws:cfg:*`) |
| v0.3.0 | 2026-11-19 | **takeover when HUD gone**: handle `NX\|UNBIND` from the holder's detaching HUD; a newcomer touching gets the Force dialog even if the holder is still in region. Craft kept on force (§8). |
| v0.3.1 | 2026-11-19 | HUD-gone detection made reliable via a contention-time ping (detach `llRegionSayTo` is not reliably delivered). |
| v0.4.0 | 2026-11-19 | **periodic heartbeat**: while locked, ping the holder's HUD every HEARTBEAT (5 s); MISS_MAX (3) unanswered pings → HUD gone → frees the lock on its own. The heartbeat also provisions (gives the HUD once) and binds (OFFER on first answer). Replaces the on-touch contention probe and `gHudGone`. |
| v0.5.0 | 2026-11-23 | **discard flow** (HUD `p1_action3`): inbound `NX\|DISCARD\|<session>\|<started>`. `discardCraft(started)` **keeps the lock & heartbeat**: not started → `STOCK_RELEASE_REQ` (server RELEASE, stock returned, session kept); started → `STOCK_COMMIT_REQ 918251` (server COMMIT, stock consumed, no product) + rotate `state:session` + re-bind (`gBound=FALSE; offerHud`) since the committed server ticket is frozen (`C`). `release()` (Release dialog = leave bench) captures ticket+holder before clearing and passes them in `STOCK_RELEASE_REQ` (link_message is async, LSD already cleared). |
| v0.4.2 | 2026-11-19 | **heartbeat detection refined** (commits "change the heartbeat detection" / "HB fixed once more"): `gPingAck`/`gMisses` reset at (re)arm, HUD given once while unbound (`gGiven`), holder re-touch while unbound re-pings ("Linking your HUD…") instead of re-probing. **`release()` wired to WS_Stock**: take/discard now emits `918250 STOCK_RELEASE_REQ` so WS_Stock releases the reserved basket. |

## Dependencies

- **Scripts (same linkset)**: WS_Boot (consumes its `WS_OPR = 970110` "OPR|<ver>" link; reads `ws:worldver`, `ws:genre`, `ws:cfg:*`); **WS_Stock** (take/discard → `918250 STOCK_RELEASE_REQ`). Later: WS_Scan, WS_Action.
- **Peer (other object)**: the worn HUD (`NX_HudFace`) — answers `NX|HUDA`, accepts the `OFFER`.
- **Channels**: `NX_HUD = -918282` (bench ↔ worn HUD). Dialog on a random negative channel.
- **Inventory**: the reference HUD object, named **`<model> v<X.Y.Z>`**. Given via `llGiveInventory` when the holder lacks it.
- **LinksetData**: `state:lock` (holder avatar key, "" = free), `state:lockname`, `state:craft` ("0"/"1" pending craft), `state:session` (bind/craft session, minted at acquire). Config (from WS_Boot): `ws:genre`, `ws:cfg:HUDKind`, `ws:cfg:SingleIngredient`, `ws:cfg:AllowKeep`. Persistent.
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
- [x] 2026-11-23 — discard modelled (RELEASE vs COMMIT + session rotation). **TAKE** (craft output COMMIT with `OUT|sid|qty|dna`) still to wire.
- [ ] 2026-11-19 — `freeLock` keeps a pending craft+session; `acquire()` does not yet prompt take/discard for an inherited craft (no craft tracking on the bench yet).
- [ ] 2026-11-19 — `gBound` is not persisted; a WS_Core reset drops it and the heartbeat re-binds on the holder's next `HUDA`.

## Test (in-world)

1. Bench at OPR. Touch (HUD worn, correct name) → "Bench reserved"; within a heartbeat → "HUD bound" (owner + bench).
2. Touch (no HUD worn) → HUD delivered once; wear it → next heartbeat binds (no re-touch needed).
3. Touch again (holder, bound) → Release dialog → Release → bench FREE (session cleared, WS_Stock basket released).
4. Remove the HUD → within ~15 s the bench frees itself (pending craft kept).
5. Second avatar touches while you hold it and are present → "in use by <you>"; leave the region → Force → they become holder, pending craft + session kept, then re-bind.
