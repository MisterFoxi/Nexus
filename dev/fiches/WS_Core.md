# Fiche — WS_Core

*Dev & tracking fiche. See `CONVENTIONS.md` and `claude/socle-refonte-reseau.md` §7-§8. File: `Workshop/WS_Core.lsl`.*

---

## Role

The bench-side state machine. **First slice:** occupancy lock (reservation) + HUD provisioning + contention/force + bind. Craft phases (select → action → commit, take/discard of a left craft) come later. Runs in the bench linkset; shares LinksetData with WS_Boot.

## Current version

`v0.3.1 (SCRIPT_NAME "WS_Core")` — reservation lock (= craft lifetime, no TTL, persisted), HUD probe/give on `NX_HUD`, bind (`OFFER`/`ACCEPT`/`BOUND`), "in use"/force contention, release stand-in.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — socle §8: touch→lock when OPR & free; probe worn HUD (`NX|HUDQ`→`NX|HUDA`) and give the reference HUD if absent/mismatched; holder present→"in use", holder out-of-region→Force dialog (keeps pending craft); locker re-touch→Release stand-in. Lock persisted in `state:lock`/`state:lockname`/`state:craft`. OPR gate via `WS_OPR` link + `ws:worldver` fallback |
| v0.2.0 | 2026-11-18 | **bind** (ported from `docs/README_workshop_link.md` "Association and lock"): on a successful probe (HUD present) `OFFER` the session; on `NX\|ACCEPT` from the holder's HUD, confirm `NX\|BOUND`. Session minted at `acquire()` (`state:session`), kept across Force, cleared at release. kind/single/keep read from the bench config (WS_Boot → `ws:genre` / `ws:cfg:*`). Holder re-touch while not bound → re-probe (handles wearing a just-given HUD); after give, prompt "wear it and touch again" |
| v0.3.0 | 2026-11-19 | **takeover when HUD gone**: handle `NX\|UNBIND` from the holder's detaching HUD (sets `gHudGone`); a newcomer touching now gets the Force dialog even if the holder is still in region (message "has no HUD"). `gHudGone` cleared on acquire / force / bind (ACCEPT). Craft still kept on force (§8). |
| v0.3.1 | 2026-11-19 | HUD-gone detection made reliable: a `llRegionSayTo` in the HUD's detach event is not reliably delivered, so WS_Core now **pings the holder's HUD** when a 2nd avatar contends an in-region holder; no `HUDA` in `PROBE_WAIT` → treat as HUD-gone → Force. The `NX\|UNBIND` path stays as a best-effort fast-path. |

## Dependencies

- **Scripts (same linkset)**: WS_Boot (consumes its `WS_OPR = 970110` "OPR|<ver>" link; reads `ws:worldver`, `ws:genre`, `ws:cfg:*`). Later: WS_Stock (COMMIT/RELEASE), WS_Scan, WS_Action.
- **Peer (other object)**: the worn HUD (`NX_HudFace`) — answers `NX|HUDA`, accepts the `OFFER`.
- **Channels**: `NX_HUD = -918282` (bench ↔ worn HUD). Dialog on a random negative channel.
- **Inventory**: the reference HUD object, named **`<model> v<X.Y.Z>`**. Given via `llGiveInventory` when the player lacks it.
- **LinksetData**: `state:lock` (holder avatar key, "" = free), `state:lockname` (legible name), `state:craft` ("0"/"1" pending craft), `state:session` (bind/craft session, minted at acquire). Config (from WS_Boot): `ws:genre`, `ws:cfg:HUDKind`, `ws:cfg:SingleIngredient`, `ws:cfg:AllowKeep`. Persistent.
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | `touch_start` | avatar | free→acquire; self (bound)→release menu; self (not bound)→re-probe; other present→"in use"; other away→Force dialog |
| out | `NX\|HUDQ` (NX_HUD, to avatar) | benchKey, model, version | probe the worn HUD |
| in | `NX\|HUDA` (NX_HUD, from worn HUD) | model, version | match → HUD present → OFFER |
| out | `NX\|OFFER` (NX_HUD, to avatar) | benchKey, session, kind, single, keep | bind offer |
| in | `NX\|ACCEPT` (NX_HUD, from worn HUD) | session, kind | from the holder + session match → confirm BOUND |
| out | `NX\|BOUND` (NX_HUD, to avatar) | session | confirm the bind |
| out | `llGiveInventory` | reference HUD | deliver HUD on absent/mismatch |
| in | link `WS_OPR` (970110) | `OPR\|<ver>` | mark ready (accept reservations) |
| in | link `970290` | — | memory report |

## Behaviour notes

- **Lock = craft lifetime**: acquired on touch (OPR+free), released only by take (COMMIT) / discard (RELEASE). `release()` is a stand-in until the craft flow exists.
- **Session**: minted at `acquire()` as `state:session` (the craft ticket), kept across Force (pending craft inherited), cleared at release. It keys the bind and will key the stock reservation (stock-protocol §4).
- **Bind timing**: the OFFER fires on a successful probe (HUD present). If the HUD had to be given, the holder re-touches after wearing it → re-probe → OFFER. `gBound` is runtime; a reset re-binds via the holder's next touch.
- **Force**: offered only when the holder is out of region; transfers the lock and **keeps** any pending craft + session. Never auto-discards.
- **Provisioning**: exact model+version match. Probe window `PROBE_WAIT = 2.5 s`; no answer → give + prompt.
- **OPR gate**: `WS_OPR` link sets ready; a lone WS_Core reset infers readiness from `ws:worldver != ""`.

## Open points / debt

- [ ] 2026-11-18 — version match is exact; a semver `>=` compare would avoid re-giving a newer HUD.
- [ ] 2026-11-18 — `llSetText` shared with WS_Boot (socle §6); WS_HMI will own the text layer.
- [ ] 2026-11-18 — `release()` is a stand-in; wire COMMIT/RELEASE to WS_Stock with the craft flow.
- [ ] 2026-11-18 — the bind has no RELEASE round-trip to the HUD; the HUD clears its bind on re-wear. Wire with take/discard.
- [ ] 2026-11-18 — `gBound` is not persisted; a WS_Core reset drops it and relies on the holder's re-touch to re-bind.
- [ ] 2026-11-18 — one probe at a time (single timer); fine until concurrent reservations exist.

## Test (in-world)

1. Bench at OPR. Touch (HUD worn, correct name) → "Bench reserved", HUD not re-given, then "HUD bound" (owner + bench).
2. Touch (no HUD worn) → HUD delivered + "wear it and touch again" → wear → touch → bound.
3. Touch again (holder, bound) → Release dialog → Release → bench FREE (session cleared).
4. Second avatar touches while you hold it and are present → "in use by <you>".
5. Leave the region; second avatar touches → Force dialog → Force → they become holder, pending craft + session kept, then re-bind to their HUD.
