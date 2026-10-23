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

Use START when stopped, PAUSE while running, and CONT while paused. STOP ends
the current session. CONT here means resume playback; it is distinct from the
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
or pass its exact inventory name to LOAD. No script is needed inside buttons.
The library has no timer and sends no craft, animation, or navigation commands.
It changes only the explicitly selected face's texture, UVs, color/opacity,
fullbright, and native texture animation. Alpha rendering mode remains a mesh
assembly setting; choose an appropriate mode for the transparent margins.

| Code | Name | Text | Reply on 918343 |
|---|---|---|---|
| 918340 | LOAD | Exact inventory texture name, or empty for default | LOADED |
| 918341 | SHOW | JSON `["primName", face, "label"]` | SHOWN:label |
| 918342 | STATE | STOPPED, PLAYING, or PAUSED | STATE:state |
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
| PLAYING | START | PAUSE |
| PAUSED | CONT | STOP |

`MC_P1_Animation` now loads this atlas at startup using an empty LOAD name,
which uses the library's DEFAULT_ATLAS (`atlas_buttons`). On LOADED, the controller
replays the latest confirmed player state. It requests STATE after REST, PLAYING,
or PAUSED acknowledgements; speculative clicks do not update button textures.
The left button starts from rest and resumes from pause. The right button pauses
while playing and stops while paused. START while already playing is idempotent.
Discard, Later, CONTINUE navigation, and DISCARD_DONE stop the session.
Commands are serialized, retaining the latest intent while awaiting an ack.
Stop during initial LOAD cancels a pending Start.

The texture library remains visual-only and does not consume 918333 messages
itself; the controller performs that connection. SHOW remains available for custom
arrangements. Use the same button prim names in the library and controller.
A button-library reset reloads and redraws the current state without restarting
playback. A player reset starts a new session if playing was requested; a paused
session returns to STOPPED because its frame/time no longer exists. A controller
reset starts from STOPPED. Button-atlas errors are logged independently and do
not stop the animation. Restore a missing button atlas to ROOT inventory to retry
its load automatically.

At script startup/reset or owner/link change, READY is sent with null id; reload
the texture and replay the desired display. Texture removal sends UNLOADED with
null id and leaves the last images visible. Further SHOW/STATE commands fail
until a texture is loaded again. All unsolicited statuses are root-local.

## Library verification

Run `./tests/run_playback_buttons_checks.ps1` from the Hud directory. The runner
parses `MC_Playback_Buttons.lsl`, `MC_Atlas_Player.lsl`, and `MC_P1_Animation.lsl`
and executes their real ASTs with deterministic UV,
inventory, and link-message mocks. The parser and bundled runtime paths match
this development machine. Twelve tests cover all four UV cells, state pairs,
request tickets, face isolation, invalid inputs, duplicate/missing targets,
failed LOAD, texture removal, custom faces, relinking, and caller filtering.
Ten additional integration tests cover startup loading, the full Start/Pause/Cont/Stop
click cycle, elapsed time excluding pauses, queued clicks, library reset, texture
restoration, navigation/discard, external player commands, and acknowledgement
ordering. These checks do not replace Mono compilation and visual validation in SL.
