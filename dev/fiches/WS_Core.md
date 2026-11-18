# Fiche — WS_Core

*Dev & tracking fiche. See `CONVENTIONS.md` and `claude/socle-refonte-reseau.md` §7-§8. File: `Workshop/WS_Core.lsl`.*

---

## Role

The bench-side state machine. **First slice:** occupancy lock (reservation) + HUD provisioning + contention/force. Craft phases (select → action → commit, take/discard of a left craft) come later. Runs in the bench linkset; shares LinksetData with WS_Boot.

## Current version

`v0.1.0 (SCRIPT_NAME "WS_Core")` — reservation lock (= craft lifetime, no TTL, persisted), HUD probe/give on `NX_HUD`, "in use"/force contention, release stand-in.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — socle §8: touch→lock when OPR & free; probe worn HUD (`NX|HUDQ`→`NX|HUDA`) and give the reference HUD if absent/mismatched; holder present→"in use", holder out-of-region→Force dialog (keeps pending craft); locker re-touch→Release stand-in. Lock persisted in `state:lock`/`state:lockname`/`state:craft`. OPR gate via `WS_OPR` link + `ws:worldver` fallback |

## Dependencies

- **Scripts (same linkset)**: WS_Boot (consumes its `WS_OPR = 970110` "OPR|<ver>" link; reads `ws:worldver`). Later: WS_Stock (COMMIT/RELEASE), WS_Scan, WS_Action.
- **Channels**: `NX_HUD = -918282` (bench ↔ worn HUD). Dialog on a random negative channel.
- **Inventory**: the reference HUD object, named **`<model> v<X.Y.Z>`** (model + expected version). Given via `llGiveInventory` when the player lacks it.
- **LinksetData**: `state:lock` (holder avatar key, "" = free), `state:lockname` (legible name), `state:craft` ("0"/"1" pending craft). Persistent.
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | `touch_start` | avatar | free→acquire; self→release menu; other present→"in use"; other away→Force dialog |
| out | `NX|HUDQ` (NX_HUD, to avatar) | benchKey, model, version | probe the worn HUD |
| in | `NX|HUDA` (NX_HUD, from worn HUD) | model, version | match → player has the HUD (no give) |
| out | `llGiveInventory` | reference HUD | deliver HUD on absent/mismatch |
| in | link `WS_OPR` (970110) | `OPR\|<ver>` | mark ready (accept reservations) |
| in | link `970290` | — | memory report |

## Behaviour notes

- **Lock = craft lifetime**: acquired on touch (OPR+free), released only by take (COMMIT) / discard (RELEASE). `release()` is a stand-in until the craft flow exists.
- **Force**: offered only when the holder is out of region (`llGetAgentList(AGENT_LIST_REGION)`); transfers the lock and **keeps** any pending craft (`state:craft`) for the new player to take/discard. Never auto-discards.
- **Provisioning**: exact model+version match. Probe window `PROBE_WAIT = 2.5 s`; no answer → give.
- **OPR gate**: `WS_OPR` link sets ready; a lone WS_Core reset infers readiness from `ws:worldver != ""`.

## Open points / debt

- [ ] 2026-11-18 — version match is exact; a semver `>=` compare would avoid re-giving a newer HUD.
- [ ] 2026-11-18 — `llSetText` shared with WS_Boot (socle §6); WS_HMI will own the text layer.
- [ ] 2026-11-18 — `release()` is a stand-in; wire COMMIT/RELEASE to WS_Stock with the craft flow.
- [ ] 2026-11-18 — one probe at a time (single timer); fine until concurrent reservations exist.
- [ ] 2026-11-18 — worn-HUD responder (`NX|HUDA`) not built yet → provisioning always gives until the HUD exists.

## Test (in-world)

1. Bench at OPR. Touch (no HUD worn) → "Bench reserved" + HUD delivered.
2. Touch again (holder) → Release dialog → Release → bench FREE.
3. Second avatar touches while you hold it and are present → "in use by <you>".
4. Leave the region; second avatar touches → Force dialog → Force → they become holder.
