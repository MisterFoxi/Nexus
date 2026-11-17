# P4 observation page

The action buttons use the exact inventory texture name `Atlas_obs`.
All UI text is in English.

## Installation

Install `MC_P4_Controller.lsl` in ROOT beside FURWARE. Replace
`MC_P1_Animation.lsl`, `MC_P1_Controller.lsl` and `MC_Playback_Buttons.lsl` together.
Keep the current `MC_Turn_Z.lsl` and `MC_Workshop_Link.lsl` with P4 navigation and
inspection support. Keep all P0/P3 scripts. No script is required inside buttons.
Put the uploaded action atlas in ROOT inventory as `Atlas_obs`.
Apply `HUD_P4.png` manually to the support and face of your choice. The controller
does not name, require or repaint a background prim, and does not require the
background texture in inventory.

Create or name these linked prims:

| Name | Role | Default face |
|---|---|---:|
| `P4_ACTION1` | BACK button | 1 |
| `P4_ACTION2` | REFRESH button | 1 |

`P4_BACK` and `P4_REFRESH` are accepted aliases for the two P4 action buttons.
Use one name per role and unique prim names. Change `FACE` and
the prim-name settings in MC_P4_Controller if the physical assembly differs.
The script paints only the configured face, never every face of a prim.

Create these FURWARE tables in the blank background fields:

| Table | Size | Placement |
|---|---|---|
| `P4_Name` | 1 row x 40 columns | Small field below the title |
| `P4_Table1` | 24 rows x 40 columns | Main description field, required |
| `P4_Status` | 1 row x 64 columns | Bottom status strip |

Use a readable cream font. Configure FURWARE geometry and colors in-world; the
controller sends text but does not build table meshes. The name field currently
reads `Current preparation` until the Workshop returns the ingredient name with
the observation. The name and status tables are optional, but recommended.

P4 occupies the remaining side of the vertical HUD: local Z = +90 degrees.
P1 remains at -90, P3 at 180 and P0 at 0. Rotation preserves local X/Y. Adjust
`P4_Z` in MC_Turn_Z if the P4 panel is assembled on a different side.

## Atlas sampling

The atlas uses a 2 x 2 grid: OBSERVE at top left, BACK at top right and REFRESH
at bottom left. The OBSERVE tile and the fourth cell are unused by this flow.
The existing P1 atlas provides CUT/CONT, PAUSE/TAKE and DISCARD.
The controller crops around the visible
plaques so the large transparent tile margins do not shrink the button labels.

| Button | Repeats | Offset U | Offset V |
|---|---|---:|---:|
| BACK | 0.47, 0.19 | +0.25 | +0.2385 |
| REFRESH | 0.47, 0.19 | -0.25 | -0.2615 |

These values match the current Atlas_Obs.png. They assume standard, unrotated
UVs. Missing textures, prims, invalid faces or missing description geometry are
reported in owner chat; inventory and link changes trigger configuration again.

## Behavior

P1 has exactly three action buttons. No P1_ACTION4 is required or inspected.

| State | P1_ACTION1 | P1_ACTION2 | P1_ACTION3 |
|---|---|---|---|
| Before starting | CUT | TAKE (inactive) | DISCARD |
| Working | CONT (inactive) | PAUSE | DISCARD |
| Paused | CONT | TAKE | DISCARD |

PAUSE checkpoints the active clock and opens P4 through local 918411/OPEN.
P4 requests a read-only observation through 918397 TEST / 918398 response.
REFRESH requests a new observation after the previous request finishes.
BACK cancels the local consultation and returns to P1 while remaining paused.
CONT resumes the same preparation without restarting its clock or touching stock.
TAKE submits the paused preparation for evaluation using the existing output path.
Repeated PAUSE clicks cannot accidentally submit TAKE while P4 is open.

P4 acknowledges OPEN with 918412/OPENED and reports 918412/CLOSED on exit,
using the same navigation ticket. A missing P4 script times out after five seconds
and leaves the preparation paused with CONT/TAKE available. A P4 reset returns
to P1 and releases the local navigation gate without resuming work.

The controller checks response UUIDs. The existing Workshop endpoint checks the
actual radio speaker, target and session. Late or unrelated responses are ignored.
Closing a page sends the new local `918397 / CANCEL` for that request only; it
does not cancel a craft or perform any ingredient transaction. A page timeout also
releases the local request. Output collection takes priority and opens P3; delayed
P4 navigation cannot rotate away from the active output page.

Responses handled by P4:

| Result | Display |
|---|---|
| `OBSERVATIONS\|<URL-escaped text>` | Decoded cumulative descriptions |
| `NO_OBSERVATIONS` | No observations for the preparation |
| `NOT_IMPLEMENTED` | Workshop observation service not connected |
| `BUSY` | Workshop busy; try REFRESH |
| `ERROR\|reason` | Explicit error reason |
| Other refusal or timeout | Start/check the preparation and retry |

Descriptions wrap at 40 characters with FURWARE tags disabled. The controller
retains all text and supports optional `P4_NEXT` / `P4_PREV` prims for descriptions
exceeding 24 wrapped lines. These optional navigation prims have no supplied atlas
artwork. Install them if your descriptions can exceed one text page.

## Workshop connection

Workshop_Observe now connects the live basket snapshot to Workshop_Eval.
See `Workshop/README_observations.md` for the required scripts, compiled world
data and InspectHandler setting. Descriptions are returned together with the
first source's name. No observation modifies stock or creates a product.
A disabled handler returns NOT_IMPLEMENTED; missing modules time out explicitly.
Large baskets or description replies are refused with a readable error.

## Checks

`tests/test_p1_three_buttons.py` runs the actual P1 animation/player, button atlas,
basket, stock relay, P4 and endpoint ASTs through owner touches.
`tests/test_p4.py` runs the actual P4, navigation and Workshop endpoint ASTs.
It checks texture selection and UVs, owner touches, rotation, cancellation,
timeouts, stale/foreign replies, text wrapping, P3 priority and unchanged stock.
The observation service in these tests is a radio stub. Validate Mono memory,
panel orientation, face selection, alpha blending and FURWARE layout in-world.
