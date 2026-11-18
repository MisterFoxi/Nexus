# Fiche — WS_Boot

*Dev & tracking fiche. See `CONVENTIONS.md` and `claude/socle-refonte-reseau.md` §7. File: `Workshop/WS_Boot.lsl`.*

---

## Role

The Workshop's **world/OPR gate**. Pulls the compiled world into this linkset's LinksetData (cached, versioned) from the server, verifies it, and declares the bench **OPR**. Counterpart of `Nexus_Server`'s world plane. It does not craft, scan or evaluate.

## Current version

`v0.1.0 (SCRIPT_NAME "WS_Boot")` — HELLO + cache; WORLD_OK (boot from LSD) / BEGIN·CHUNK·END (wipe realm, write physics, line-count check, cache, OPR); WORLD_WAIT retry; WORLD_BUMP resync.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-18 | created — world handshake against server v0.3.0: `HELLO|wsKey|cachedVer`; handles `WORLD_OK`/`WORLD_BEGIN`/`WORLD_CHUNK`/`WORLD_END`/`WORLD_WAIT`/`WORLD_BUMP`; opaque `\n`-packed chunks; line-count validation at END → re-HELLO on mismatch; version cached in `ws:worldver`; `llSetText` status; touch info dialog; `WS_OPR` link broadcast |

## Dependencies

- **Scripts**: talks to `Nexus_Server` (v0.3.0+) over region say. Broadcasts `WS_OPR` to the rest of the WS (not yet consumed).
- **Channel**: `NX_STOCK = -918280` (shared cold+hot for now).
- **Link code**: `WS_OPR = 970110` → `link_message(LINK_SET, 970110, "OPR|<ver>", NULL_KEY)` once world ready. Mem report `970290`.
- **LinksetData written**: the physics realms `tok:/tax:/law:/idx:/dom:` (the world itself), and `ws:worldver` (cached version, persistent). Live state `state:/rz_` untouched.
- **Include**: `nexus_header.lsl`.

## Interfaces (messages)

| Dir | Verb | Payload | Effect |
|---|---|---|---|
| out | `HELLO` | wsKey, cachedVer | ask the server to sync the world |
| in | `WORLD_OK` | ver | cache valid → OPR, no transfer |
| in | `WORLD_BEGIN` | ver, n | wipe realm, arm transfer (expect n lines) |
| in | `WORLD_CHUNK` | ver, seq, payload | write `\n`-split physics lines (payload opaque) |
| in | `WORLD_END` | ver, nChunks | n match → OPR; mismatch → re-HELLO |
| in | `WORLD_WAIT` | — | server ingesting; timer re-HELLOs |
| in | `WORLD_BUMP` | ver | world republished → drop OPR, resync |
| in | `SERVER` | srvKey | note server key (info menu) |
| out | link `WS_OPR` (970110) | `OPR\|<ver>` | tell the WS the bench is ready |
| in | link `970290` | — | memory report |

## State & persistence

- `ws:worldver` persists across reset/re-rez → a reboot that finds a current cache gets `WORLD_OK` and skips transfer.
- The physics realms persist too; `WORLD_OK` trusts them. A fresh stream wipes them first (`WORLD_BEGIN`).
- Retry timer (`RETRY = 10 s`) re-HELLOs while not OPR — covers "server not up yet" and "still ingesting".
- Reliability is consumer-side: a dropped `WORLD_CHUNK` surfaces as a line-count mismatch at `WORLD_END` → full re-pull. No reliable transport, no ACK.

## Open points / debt

- [ ] 2026-11-18 — world pull has no per-chunk ACK; drop detection is the END line-count check → whole-world re-pull. Fine for a cold path; revisit if the world grows large.
- [ ] 2026-11-18 — HELLO is broadcast and trusts the first answering server; multi-server sims need owner/name targeting (DISCOVER) before trusting a reply.
- [ ] 2026-11-18 — `writeLine` has no LinksetData-full guard; a full linkset would silently under-count (then trigger a re-pull loop).
- [ ] 2026-11-18 — line-count equality assumes server lines map 1:1 to distinct keys; duplicate keys in the world would make counts diverge. Compiler emits unique keys today.
- [ ] 2026-11-18 — OPR is announced on `WS_OPR`; no consumer yet (WS_Core). Wire when built.

## Test (in-world, against server v0.3.0)

1. Drop `monde.nc` in the **server** prim, reset it → `server world ready: <n> lines, ver sig-…`.
2. Reset the **WS_Boot** prim → status `boot…` then `sync monde …` then `PRÊT (OPR) • monde sig-…`; owner chat shows the OPR line with the observations count.
3. Reset WS_Boot again (cache warm) → should get `WORLD_OK`, go OPR with no transfer.
4. Re-drop `monde.nc` on the server → `WORLD_BUMP` → WS_Boot resyncs to the new version.
