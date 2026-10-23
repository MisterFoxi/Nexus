# Atlas player in the root prim

`MC_Atlas_Player.lsl` and textures belong in the **root**. The player locates
**P1_DISPLAY** by name and writes to its `FACE` (**2 by default in the current
script**). P1_DISPLAY requires no script or atlas in its own inventory.

## HUD installation

1. Name the display prim `P1_DISPLAY`, unique within the linkset.
2. Put `MC_Atlas_Player`, `MC_P1_Animation`, and the texture in the root.
3. Set the player's `FACE` to P1_DISPLAY's visible face.
4. Set `ATLAS` in `MC_P1_Animation` to the exact root-inventory texture name;
   the default is `atlas_chop`.
5. Buttons are `P1_CUT` and `P1_STOP`, with no scripts. These names are
   configurable in the animation controller.
6. Remove `MC_Chop_Atlas_Test` and `MC_Atlas_Touch_Test` from the HUD.

Cut starts the A/B sequence. Stop, Discard, Later, Continue, and DISCARD_DONE
restore the rest frame. Other users' clicks and unrelated buttons are ignored.
A player reset reloads the atlas and reapplies the latest requested visual
state; a controller reset returns to rest. Stop takes priority over a Cut
waiting for loading.

This step connects animation only. It changes neither the basket, stock,
`craft_started` flag, finesse, nor output. Later/Take crafting behavior remains
to be implemented. The future crafting engine must wait for the
`918317 / CRAFT_STARTED` acknowledgement before actually starting. The supplied
visual controller will then need integration with that crafting cycle.

## API from another root script

| Code | Text | Effect |
|---|---|---|
| 918330 | Exact atlas name | Load from root inventory and show rest |
| 918331 | Empty | Play the sequence in a loop |
| 918332 | Empty | Stop and show rest |
| 918333 | Status | Player response |

```lsl
llMessageLinked(LINK_THIS, 918330, "atlas_chop", loadTicket);
// Wait for 918333 / LOADED with the same ticket before PLAY.
llMessageLinked(LINK_THIS, 918331, "", playTicket);
llMessageLinked(LINK_THIS, 918332, "", restTicket);
```

LOADED, PLAYING, REST, and ERROR:reason replies retain the received ticket in
`id`. The player accepts calls only from the same root prim. The atlas name
is not hardcoded in the player.

An invalid LOAD is intended to preserve the previous atlas and playback.
Repeated PLAY does not restart the loop. A valid LOAD returns to rest. Missing
or duplicate prim names produce an error, with no fallback to the root. The
player resolves link numbers on load and restarts after relinking.

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

Syntax/type analysis reported no errors in the existing validation. Nine
scenarios run against actual ASTs cover targeting a child from root, Cut/Stop,
the A/B loop, Stop during LOAD, Discard/Later/Continue, ownership, player reset,
missing or duplicate targets, missing atlas, and changed link numbers. These
checks do not replace Mono compilation and visual verification in SL.

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
