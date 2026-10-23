# Atlas player in the root prim

`MC_Atlas_Player.lsl` and textures belong in the **root**. The player locates
**P1_DISPLAY** by name and writes to its `FACE` (**2 by default in the current
script**). P1_DISPLAY requires no script or atlas in its own inventory.

## HUD installation

1. Name the display prim `P1_DISPLAY`, unique within the linkset.
2. Put `MC_Atlas_Player`, `MC_P1_Animation`, `MC_Playback_Buttons`, and both atlas textures in the root.
3. Set the player's `FACE` to P1_DISPLAY's visible face.
4. Set `ATLAS` in `MC_P1_Animation` to the exact root-inventory texture name;
   the default is `atlas_chop`.
5. Buttons are `P1_CUT` and `P1_STOP`, with no scripts. These names are
   configurable in the animation controller.
6. Import the button atlas as `atlas_buttons` in ROOT and set the button faces in `MC_Playback_Buttons`. See `README_playback_buttons.md`.
7. Remove `MC_Chop_Atlas_Test` and `MC_Atlas_Touch_Test` from the HUD.

The first left-button click requests the existing basket's CRAFT_STARTED
commitment before starting A/B playback. The left button then permanently becomes
CONT for that preparation. The right button suspends; CONT resumes without
resetting active time. Later and ingredient-page navigation also suspend.
Only a confirmed DISCARD_DONE permits a fresh preparation. An explicit new
START on an already used preparation spoils it. No button, controller reset or
player reset returns the same used preparation to START.

Install `MC_Chop_Progress` and texture `atlas_progress` in ROOT to drive the
P1_PROGRESS prim. Its active-time progression reaches Over the top at 10 seconds
by default, excluding interruptions. Configure the visible face in that renderer.
See `README_chop_progress.md` for thresholds, persistence and the preparation API.

The player below remains a generic visual library: PLAY can reset its own session
clock, but cannot authorize a new preparation or reset the controller's progress.
Stock reservation and final discard remain owned by the basket/transaction scripts.
Take/output crafting behavior is still separate.

## API from another root script

| Code | Text | Effect |
|---|---|---|
| 918330 | Exact atlas name | Load from root inventory and show rest |
| 918331 | Empty | Start looping; reset elapsedTime when starting from rest or pause |
| 918332 | Empty | Stop, show rest, and retain the final elapsedTime |
| 918333 | Status | Player response |
| 918334 | Empty | Pause, preserving the current frame and active time |
| 918335 | Empty | Resume without resetting active time |
| 918336 | Empty | Read elapsedTime in seconds, excluding pauses |

```lsl
llMessageLinked(LINK_THIS, 918330, "atlas_chop", loadTicket);
// Wait for 918333 / LOADED with the same ticket before PLAY.
llMessageLinked(LINK_THIS, 918331, "", playTicket);
llMessageLinked(LINK_THIS, 918334, "", pauseTicket);
llMessageLinked(LINK_THIS, 918335, "", resumeTicket);
llMessageLinked(LINK_THIS, 918336, "", elapsedTicket);
// Reply: 918333 / ELAPSED:<seconds>, echoing elapsedTicket in id.
llMessageLinked(LINK_THIS, 918332, "", restTicket);
```

LOADED, PLAYING, REST, PAUSED, ELAPSED:seconds, and ERROR:reason replies retain the received ticket in
`id`. The player accepts calls only from the same root prim. The atlas name
is not hardcoded in the player.

An invalid LOAD is intended to preserve the previous atlas and playback.
Repeated PLAY does not restart the loop. A valid LOAD returns to rest. Missing
or duplicate prim names produce an error, with no fallback to the root. The
player resolves link numbers on load and restarts after relinking.

`elapsedTime` starts at zero and accumulates active playback only. PAUSE freezes
the timer and displayed frame; RESUME continues from that frame, with the next
frame due after one full period (1 / FPS). REST freezes the final duration until
the next PLAY. PLAY while paused starts a new session; PLAY while already running
does not reset the counter. Repeated PAUSE while paused and RESUME while running
are idempotent. PAUSE or RESUME from rest returns ERROR without starting playback.
REST while paused ends the session, so RESUME then returns ERROR.

A valid LOAD or texture removal ends the session and retains its final duration.
A script reset clears elapsedTime. ELAPSED can be queried even before LOAD and
returns `ELAPSED:<seconds>` on 918333 with the request ticket in `id`.
Timing uses differences of [llGetTime](https://wiki.secondlife.com/wiki/LlGetTime),
independently of animation ticks. The HUD controller uses PAUSE/RESUME for interruptions, reserves REST for visual
cleanup, and keeps the preparation clock and used-component latch separately.

At startup, the player announces `918333 / READY` with null id in the root.
The controller resends LOAD. If the texture disappears from root inventory,
the player stops its timer and announces UNLOADED; the face retains its last
image until the next valid LOAD. Restore the atlas, then press Cut.

## Format

Defaults: 3 columns, 1 row; rest = 0; sequence = 1 then 2; 4 frames per second.
COLUMNS, ROWS, REST_FRAME, FIRST_FRAME, FRAME_COUNT, and FPS are configurable
in the player. Indices are zero-based, left to right, then top to bottom.
Interchangeable atlases must follow these same settings.

The player uses direct UV changes and its own script timer, as in the validated
test. It applies white, full opacity, and fullbright to the chosen face and
disables P1_DISPLAY's native texture animation. No other script should modify
that face's UVs. SL timer timing varies with load; this animation is not the
crafting engine's clock.

## Optional standalone test

`../tools/MC_Atlas_Touch_Test.lsl` remains available for an isolated assembly:
put it in the root with the player and textures, plus a child named P1_DISPLAY.
Do not run it with MC_P1_Animation: every owner touch in this assembly toggles
playback/rest.

## Verification

Syntax/type analysis reported no errors. Sixteen
scenarios run against actual ASTs cover targeting a child from root, Cut/Stop,
the A/B loop, Stop during LOAD, Discard/Later/Continue, ownership, player reset,
missing or duplicate targets, missing atlas, and changed link numbers. These
checks also cover multiple pauses, frame preservation, repeated commands, stopping
while paused, restarting, and ELAPSED response tickets. They do not replace Mono
compilation and visual verification in SL.

The validated graphic is `../assets/atlas_chop_fond_fixe_v3.png`. After import
into SL, its inventory name must match ATLAS in the controller.

## Review notes

The previous French guide incorrectly stated face 0; this translation matches
the current `FACE = 2` setting. No script setting was changed.
`loadAtlas` assigns `gDisplayLink` before completing validation. A failed LOAD
can therefore alter the target used by existing playback; target changes should
be committed only after all checks succeed. The animation controller has no
LOAD-response timeout, so an absent or stopped player can leave a load pending
until another READY message or reset. These are annotated, not fixed.
