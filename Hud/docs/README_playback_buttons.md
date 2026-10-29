# Playback button textures

Asset: `atlas_playback_buttons_2x2_v1.png` (RGBA, transparent background).
Source size: 1774 x 887 pixels. The normalized grid is 2 columns x 2 rows.
The PNG is a generated source image; select an appropriate supported import
resolution in Second Life (for example 1024 x 512), preserving the 2:1 ratio.

| Frame | Label | Column | Row from top | UV repeats | UV offset | Player command |
|---|---|---|---|---|---|---|
| 0 | START | 0 | 0 | <0.5, 0.5, 0.0> | <-0.25, 0.25, 0.0> | 918331 PLAY |
| 1 | CONT | 1 | 0 | <0.5, 0.5, 0.0> | <0.25, 0.25, 0.0> | 918335 RESUME |
| 2 | PAUSE | 0 | 1 | <0.5, 0.5, 0.0> | <-0.25, -0.25, 0.0> | 918334 PAUSE |
| 3 | STOP | 1 | 1 | <0.5, 0.5, 0.0> | <0.25, -0.25, 0.0> | 918332 REST |

Use START only for an unused preparation. After first commitment, use CONT.
PAUSE and STOP both suspend the preparation without clearing elapsed time. CONT here means resume playback; it is distinct from the
ingredient page's CONTINUE navigation message (918310).

Visuals match `hud_p2.png`: beveled dark metal, bronze edges, ivory serif labels,
green START/CONT, amber PAUSE, red STOP. Each cell includes transparent margins.
The textures are assets ready for import. `MC_Playback_Buttons.lsl` manages their
UV selection through the API below. The controller remains responsible for clicks,
playback transitions, and calling the visual library after confirmed changes.

Generated with the built-in image_gen tool, using `hud_p2.png` as a style reference.
The complete generation prompt is in `playback_buttons_prompt_v1.txt`.

## Root visual library

Install `MC_Playback_Buttons.lsl` in the HUD root. Import the PNG and place the
texture in root inventory under `atlas_buttons` (no extension),
or pass its exact inventory name to LOAD. Empty LOAD also accepts
`atlas_playback_buttons_2x2_v1` and `atlas_playback_buttons_2x2_v1.png`,
matching the fallback used for confirmed player states. No script is needed inside buttons.
The library has no timer and sends no craft, animation, or navigation commands.
It changes only the explicitly selected face's texture, UVs, color/opacity,
fullbright, and native texture animation. Alpha rendering mode remains a mesh
assembly setting; choose an appropriate mode for the transparent margins.

| Code | Name | Text | Reply on 918343 |
|---|---|---|---|
| 918340 | LOAD | Exact inventory texture name, or empty for default | LOADED |
| 918341 | SHOW | JSON `["primName", face, "label"]` | SHOWN:label |
| 918342 | STATE | STOPPED, PLAYING, PAUSED, USED, or SPOILED | STATE:state |
| 918343 | STATUS | Library responses | READY, UNLOADED, or ERROR:reason |

All command responses echo the request ticket in `id`. The library accepts
same-prim calls only. Names are matched without case, trimming surrounding
spaces, and must be unique within the linkset. Labels and STATE values are also
case-insensitive. SHOW requires a JSON array with three correctly typed values;
face must be a nonnegative integer within that prim's face count. ALL_SIDES is
not accepted. A failed command leaves the display unchanged. Failed LOAD keeps
the previous atlas. LOAD does not draw: send SHOW or STATE after LOADED.

```lsl
// Send from the root and wait for 918343 / LOADED with loadTicket in id.
llMessageLinked(LINK_THIS, 918340, "atlas_buttons", loadTicket);

// After LOADED, draw an individual button (face 0 is an example).
llMessageLinked(LINK_THIS, 918341,
    llList2Json(JSON_ARRAY, ["P1_CUT", 0, "CONT"]), showTicket);

// Or update the configured pair together.
llMessageLinked(LINK_THIS, 918342, "PAUSED", stateTicket);
```

STATE uses `START_PRIM = "P1_CUT"`, `STOP_PRIM = "P1_STOP"`, `START_FACE = 0`,
and `STOP_FACE = 0`. Set both face constants to the visible faces of your actual
button meshes. Both targets and faces are validated before either is written.
The two commands must target different surfaces (two faces on one prim are also
supported by configuration).

| STATE | START_PRIM label | STOP_PRIM label |
|---|---|---|
| STOPPED | START | STOP |
| PLAYING | CONT | PAUSE |
| PAUSED | CONT | STOP |
| USED | CONT | STOP |
| SPOILED | CONT (dimmed) | STOP (dimmed) |

`MC_P1_Animation` loads this atlas at startup using an empty LOAD name,
which uses DEFAULT_ATLAS (`atlas_buttons`). It drives confirmed visual states
and replays them after library reset. STOPPED is only for an unused preparation;
after the first committed START, the controller sends PLAYING or USED, so START
cannot reappear. Both normal paused and stopped-used preparations display CONT.
The right button suspends playback; repeated STOP preserves active time.

Explicit START on an already used preparation spoils it. SPOILED draws dimmed
CONT/STOP; the preparation controller ignores resume attempts. Only confirmed
DISCARD_DONE or CRAFT_DONE unlocks a new preparation. Later/navigation/reset never unlock it.
The texture library remains visual-only; the preparation controller owns this
lifetime policy. SHOW remains available for custom arrangements.

Use the same button names in the library and controller. A library reset reloads
and redraws without resetting the preparation clock. Removing/restoring an atlas
retries loading without permitting a second preparation START. See
`README_chop_progress.md` for session timing, persistence and installation.

## Library verification

Run `./tests/run_playback_buttons_checks.ps1` from Hud. It parses the player,
controller, button library and progress renderer, then executes AST behavior
tests, including atlas-name fallback, missing button library, lost load replies and read-only diagnostics. See `README_chop_progress.md` for coverage and Second Life validation limits.

## Frozen button textures while the chop animation runs

Button texture loading is independent of animation loading. Empty LOAD previously
accepted only atlas_buttons, while the direct animation-state observer accepted
three inventory names. This could leave the preparation controller's visual
handshake incomplete, especially when restoring the atlas during active playback.
Both paths now use the same resolver. Explicit custom LOAD names still require an
exact inventory match and a failed LOAD preserves the prior atlas.

MC_P1_Animation retries only the local visual LOAD at two-second intervals, with
three attempts. It then reports No button renderer response instead of waiting
silently. A library READY or inventory change can recover the visual state without
restarting the preparation, resetting elapsed time or sending a source transaction.

For the actual in-world assembly, owner chat `/918344 buttons` prints the available
atlas, the active atlas, and the resolved P1_CUT/P1_STOP links, configured faces,
current textures and UV transforms. This diagnostic only reads state. Missing or
duplicate prims and invalid faces are named explicitly. No face is guessed or
changed automatically. If no diagnostic reply appears, that version of the button
library is not running in ROOT or the command was not issued by its owner.

Local tests reproduce the loading defects; they do not establish the actual face
visible on a particular in-world mesh, the scripts installed there, or whether
another in-world script overwrites a button's texture after it is drawn.
