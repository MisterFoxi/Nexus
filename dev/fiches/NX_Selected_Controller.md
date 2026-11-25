# Fiche — NX_Selected_Controller

*Dev & tracking fiche. See `CONVENTIONS.md`, `dev/stock-protocol.md`. File: `Hud/NX_Selected_Controller.lsl`.*

---

## Role

HUD **basket mirror** (P0 SELECTED panel). The basket lives in the bench now; this script only reflects it: receives `NX|BASKET` from the bound bench, drives `NX_Render_Selected` (VIEW, panel "SELECTED"), paginates, sends unpicks, and reports the basket count to `NX_HudNav` for the Continue gate. Replaces the *display* half of the removed `MC_Selected_Controller` (its storage half moved to the bench's WS_Stock).

## Current version

`v0.2.0 (SCRIPT_NAME "NX_Selected_Controller")` — BASKET → SELECTED view + CANCONT; pagination; P0_SEL_DEL → UNPICK; empties the basket on a **session change** (fresh bind after a consume-discard), not only on unbind.

## Changelog

| Version | Date | Change |
|---|---|---|
| v0.1.0 | 2026-11-19 | created — the HUD side of the pick→reserve slice (option B). |
| v0.2.0 | 2026-11-23 | **clear on session change**: `BIND_INFO` now empties the basket when the new session differs from the current one (or is empty/unbound), not only on unbind. Needed because a consume-discard rotates the bench to a fresh session + re-binds — SELECTED must start empty for the new craft. |

## Dependencies

- **Bench** (`NX_HUD`): in `NX|BASKET`; out `NX|UNPICK` (to the bound bench on P0_SEL_DEL_n).
- **Same linkset**: `NX_HudFace` (`918260 BIND_INFO` → bench+session), `NX_Render_Selected` (`918290 VIEW` panel "SELECTED"), `NX_HudNav` (`918261 CANCONT` count).
- **Buttons**: `P0_SEL_PREV`, `P0_SEL_NEXT`, `p0_sel_del_0..3`.
- **Include**: `nexus_header`.

## Interfaces

| Dir | Msg | Effect |
|---|---|---|
| in link | `918260 BIND_INFO` `<bench>\|<session>` | learn the bench; unbound OR new (different) session → empty basket |
| in NX_HUD | `NX\|BASKET\|<session>\|<count>\|sid~name~qty~icon^…` | mirror the basket |
| out link | `918290 VIEW` (key "SELECTED") | render the SELECTED panel |
| out link | `918261 CANCONT` `<count>` | Continue gate to NX_HudNav |
| out NX_HUD | `NX\|UNPICK\|<session>\|<sid>` | remove a line (bench re-pushes BASKET) |
| in | touch P0_SEL_PREV/NEXT/p0_sel_del_n | paginate / unpick |

## Open points / debt

- [ ] 2026-11-19 — prim names P0_SEL_PREV/NEXT and p0_sel_del_0..3 assumed from the legacy layout; confirm in-world.
- [ ] 2026-11-19 — display only; the authoritative basket + reservation are in the bench (WS_Stock).

## Test (in-world)

1. Pick components on P0 → they appear in the SELECTED panel; Continue unblocks.
2. `p0_sel_del_n` → line removed (bench unreserves), SELECTED + Continue update.
