# Fiche — NX_HudFace

*Dev & tracking fiche. See `CONVENTIONS.md` and `claude/socle-refonte-reseau.md` §4, §8. File: `Hud/NX_HudFace.lsl`.*

---

## Role

The worn HUD's thin face toward the bench. **Built so far:** provisioning probe answer (`NX|HUDA`) + bind to the bench at reservation (`OFFER`/`ACCEPT`/`BOUND`). First stones of the thin backend that replaces the old transactional stack (`MC_Workshop_Link` / `MC_Selected_Controller` / `MC_Transactions`). Runs in the worn HUD object.

## Current version

`v0.4.0 (SCRIPT_NAME "NX_HudFace")` — probe responder + bind handshake + `BIND_INFO` publish; **discard relay**: on local `918315/DISCARD|<started>` from NX_P1_Animation, forwards `NX|DISCARD|<session>|<started>` to the bound bench and fires `918317/DISCARD_DONE` to reset the HUD pages (does not clear the bind — the bench drives the refresh while bound).

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — socle §8: listen on `NX_HUD`, on `NX|HUDQ` reply `NX|HUDA|<model>|<version>`. Model+version parsed from own name `<model> v<X.Y.Z>`. Misnamed → stay silent. |
| v0.2.0 | 2026-11-18 | **bind** — ported `OFFER`/`ACCEPT`/`BOUND` from `docs/README_workshop_link.md` onto `NX_HUD`: on `NX\|OFFER` (speaker = named bench, kind = our model) store bench+session, reply `NX\|ACCEPT\|<session>\|<kind>`; on `NX\|BOUND` mark bound. One bench at a time (OFFERs from other benches ignored while bound); reset (re-wear) clears the bind. session = the bench lock (§8); single/keep carried but not stored yet. |
| v0.3.0 | 2026-11-19 | **unbind on detach**: `attach(NULL_KEY)` sends `NX\|UNBIND\|<session>` to the bound bench, so WS_Core can let another avatar take over (Force) when the HUD is removed but the holder stays in region. |
| v0.3.1 | 2026-11-19 | **publish the bind to the linkset**: on `NX\|BOUND`, broadcast `918260 BIND_INFO` = `<bench>\|<session>` to `LINK_SET` so the pick (`NX_Nearby_Controller`) and basket mirror (`NX_Selected_Controller`) learn the bound bench + session and can address it. |
| v0.4.0 | 2026-11-23 | **discard relay**: on local `918315 DISCARD` (`"DISCARD\|<started>"` from `NX_P1_Animation`'s `p1_action3`), forward `NX\|DISCARD\|<session>\|<started>` to the bound bench, then emit `918317 DISCARD_DONE` to `LINK_THIS` (P1 reset / P0 rotation / P4 close). **Bind is NOT cleared** here: the bench keeps the lock and (on consume) rotates to a new session + re-binds, so its session-gated refresh must still reach us. |

## Dependencies

- **Peer (other object)**: WS_Core on the bench — probes, then OFFERs the session; compares our `NX|HUDA` to its reference HUD (exact model+version) and gives only on absent/mismatch; confirms the bind with `NX|BOUND`.
- **Channels**: `NX_HUD = -918282` (bench ↔ worn HUD).
- **Identity**: this object's name must be `<model> v<X.Y.Z>` — the model is both the provisioning identity and the bind **kind** we accept.
- **Include**: `nexus_header` (no extension).

## Interfaces

| Dir | Verb / event | Payload | Effect |
|---|---|---|---|
| in | `NX\|HUDQ` (NX_HUD) | benchKey, model, version | provisioning probe from a bench |
| out | `NX\|HUDA` (NX_HUD, to benchKey) | own model, own version | report self; the bench decides the match |
| in | `NX\|OFFER` (NX_HUD) | benchKey, session, kind, single, keep | bind offer; accepted only if kind = our model and not bound elsewhere |
| out | `NX\|ACCEPT` (NX_HUD, to benchKey) | session, own model | accept the offer |
| in | `NX\|BOUND` (NX_HUD) | session | bench confirms → bound |
| out | link `918260 BIND_INFO` (LINK_SET) | `<bench>\|<session>` | on BOUND, tell the pick/basket scripts which bench is bound |
| in | link `918315 DISCARD` (LINK_THIS) | `"DISCARD\|<started>"` | from NX_P1_Animation's p1_action3 |
| out | `NX\|DISCARD` (NX_HUD, to bench) | session, started | relay the discard to the bound bench |
| out | link `918317 DISCARD_DONE` (LINK_THIS) | — | reset all HUD pages after a discard |
| in | `attach` / `on_rez` / `changed` | — | reset / re-parse / clear bind |
| in | link `970290` | — | memory report |

## Behaviour notes

- **Self identity**: `gModel`/`gVersion` parsed from `llGetObjectName()` split on `" v"`, mirroring WS_Core's `parseHud()`. The model doubles as our bind kind.
- **One bench**: once `BOUND`, OFFERs from a different bench are ignored; the same bench may refresh the session. The bind clears only on reset (re-wear) — no RELEASE round-trip yet.
- **Fail-safe**: name does not parse → warn owner once, answer nothing (no HUDA, no ACCEPT) → the bench re-provisions.

## Open points / debt

- [ ] 2026-11-18 — `single`/`keep` from the OFFER are not stored yet (no craft flow to use them).
- [x] 2026-11-23 — discard round-trip wired (`NX|DISCARD`). Note: the bind is intentionally not cleared on discard (bench keeps the lock); it self-heals via re-OFFER on the next bench touch. A full RELEASE/leave round-trip from the HUD is still TODO.
- [ ] 2026-11-18 — the real HUD↔WS_Core intents (pick/craft/observe/récipient) + repointing the kept visual pages are the next links; each waits on its bench subsystem (WS_Scan/Stock/Action/Output).

## Test (in-world)

1. Wear a correctly named HUD (`<model> v<X.Y.Z>`). Touch a FREE bench at OPR → "Bench reserved", HUD **not re-given**, then owner sees "HUD bound to the bench" / bench sees "HUD bound".
2. No HUD worn → touch → HUD delivered + "Wear the HUD, then touch the bench again" → wear → touch again → bound.
3. Rename the worn HUD to a non-matching version → touch → bench gives the reference HUD (mismatch); no bind.
4. Rename to drop the ` v…` token → owner sees the misname warning; touch → bench re-gives (fail-silent); no bind.
