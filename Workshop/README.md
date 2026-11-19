# Workshop (bench) — network refonte

> **Status (18 nov. 2026): under rebuild.** The old 7–8 script MCW coordinator
> (`Workshop`, `Workshop_Config`, `Workshop_Interface`, `Workshop_HUD`,
> `Workshop_Eval`, `Workshop_Output`, `Workshop_Storage`, `Workshop_Observe`) is
> **superseded**. It implemented distributed, HUD-mirrored stock over a hand-rolled
> reliable-whisper (MCW) — the exact machinery the refonte removes. Decision record:
> `claude/socle-refonte-reseau.md` (project doc). This README describes the **new**
> bench; the legacy scripts remain in git history and in `old/` only as salvage
> reference.

## What the bench is now

Authority moved out of the bench and into an in-sim **server** (`Server/nexus_server.lsl`):
- **Stock** (quantities) → server, authoritative (`reserve/commit/release`, no TTL; the
  bench holds the reservation for the whole craft). Spec: `dev/stock-protocol.md`.
- **World** (compiled `monde.nc` dictionaries) → server, versioned, pulled + cached by
  the bench at boot.
- **Identity/DNA/freshness** stays in the Component objects (`Component/nexus_component.lsl`).

The bench is decomposed **one script per function** (socle §7). Each boundary is a
documented message contract; see the per-script fiches in `dev/fiches/`.

| Script | Role | State |
|---|---|---|
| `WS_Boot` | World/OPR gate: `HELLO`→server, cache+version, write physics to LSD, go OPR; reads `bench_config` (type = `Genre`) | **built** v0.2.2 |
| `WS_Core` | Bench state machine: reservation lock + HUD provisioning + contention/force; later the craft phases | **built** v0.1.0 (lock+provisioning slice) |
| `WS_Stock` | Server client: `RESERVE`/`COMMIT`/`RELEASE`/`DISCARD`, forges output SIDs | todo |
| `WS_Scan` | `PING`/`HERE`/`BLANK`, basket build (DNA + SID) | todo |
| `WS_Action` | Temporal pausable action (grind/heat/elapsed), local observation (`consult`) | todo |
| `Workshop_Eval` | The evaluator — **kept as-is** (pure, no stock/session) | kept |
| `WS_Output` | Recipient `CONFIG` with the output SID; `CUT`/`GIVE` | todo |
| `WS_HMI` | `llSetText` status + touch menu + dialogs (UI layer) | todo |

## Boot & lifecycle

1. **Boot** (`WS_Boot`): `NX|HELLO|<wsKey>|<cachedVer>|<type>` on `NX_STOCK` (-918280). Server
   replies `WORLD_OK` (cache valid) or streams `WORLD_BEGIN/CHUNK/END`; bench writes the
   `tok:/tax:/law:/idx:/dom:` realms to LinksetData, caches `ws:worldver`, goes **OPR**.
   `WORLD_BUMP` (auto on re-ingest, or on server owner-touch) → re-sync.
2. **Reserve** (`WS_Core`): player touches the bench → exclusive lock (OPR+free), persisted
   in `state:lock`. The bench provisions the player's HUD over `NX_HUD` (-918282): probe
   `NX|HUDQ`, worn HUD answers `NX|HUDA|model|version`; give the reference HUD if
   absent/mismatched. Contention: holder present → "in use"; holder out-of-region → Force.
3. **Craft** (todo): select components (reserve) → temporal action → evaluate (local) →
   take (COMMIT) or discard (RELEASE). Lock frees only on take/discard.

## Channels

`NX_STOCK = -918280` (stock + world), `NX_SCAN = -918281` (component scan),
`NX_HUD = -918282` (bench ↔ worn HUD).

## Conventions

Every script: boot banner `[Nexus] <name> v<x.y.z> (<date>) | heap <b> | lsd <b> free`,
SemVer, a fiche in `dev/fiches/`, `#include "nexus_header"` (**no extension**). See
`CONVENTIONS.md`.
