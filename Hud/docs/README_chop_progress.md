# Chopping progression — current atlas v2

Use **atlas_chop_progress_v2.png** with the current **MC_Chop_Progress.lsl**.
Version 1 is retained as historical artwork and uses a different frame order.
Do not pair the new renderer with the v1 texture.

| Frame | Label | Active time | Position |
|---|---|---|---|
| 0 | Empty board, no text/value/gauge | Before first Start / after confirmed Discard | Top left |
| 1 | Light | 0 to under 2.5 s | Top middle |
| 2 | Coarse | 2.5 to under 5 s | Top right |
| 3 | Fine | 5 to under 7.5 s | Bottom left |
| 4 | Extra | 7.5 to under 10 s | Bottom middle |
| 5 | Over the top | 10 s and above | Bottom right |

FULL_SECONDS remains 10.0 in the renderer; changing it scales the four interval
boundaries. IDLE selects frame 0. Numeric 0 selects frame 1 (Light) after the
first confirmed start. Spoiled selects the empty board with red floating text.
Exact UV coordinates are in ../assets/chop_progress_v2.json; the row boundary
is y=496 and there are 28 unused pixels below the lower row. Preserve the aspect
ratio when importing. Canvas: 1536 x 1024, opaque RGB.

## Install/update in SL

1. Import **atlas_chop_progress_v2.png** and put it in ROOT inventory under the
   name **atlas_progress**, replacing the old atlas_progress texture. Alternatively
   keep its exact v2 exported name; both with and without .png are accepted.
2. Replace/compile **MC_Chop_Progress.lsl** in ROOT. P1_PROGRESS must be a unique
   prim in the linkset. Its visible face is configured as **FACE = 2**.
3. The renderer initializes independently, restoring a saved preparation's grade
   or showing the empty board for an unused preparation. It prints an Initialized
   message on success and reports missing texture/target/invalid face directly.

The controller, elapsed-time behavior and button click handlers are unchanged by
this atlas update. Stop/Cont preserves active time; Start is never reoffered for
a used preparation. The controller requests the persisted CRAFT_STARTED basket
ack before first playback. Only confirmed Discard releases the latch; an explicit
second Start spoils the preparation. Controller reset restores the last successful
checkpoint and remains suspended; offline time is not added.

The renderer API remains 918350 LOAD, 918351 SHOW (seconds, IDLE or SPOILED), and
918353 status. The controller loads it automatically and retries an unanswered
load. ./tests/run_playback_buttons_checks.ps1 checks parsing and behavior against
actual LSL ASTs, including the empty initial frame, active thresholds and stop/cont.
Visual verification in Second Life is still required.

Edited with the built-in image_gen tool. Prompt: ../assets/sources/chop_progress_prompt_v2.txt.
