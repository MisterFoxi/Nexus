# Development HUD

The root contains only the **12 current HUD scripts**, to install in the linkset's root prim alongside FURWARE (supplied separately).

| Function | Scripts |
|---|---|
| Scanning | MC_Scan, MC_Scan_Refresh |
| Selection and basket | MC_Nearby_Controller, MC_Selected_Controller, MC_Transactions |
| Rendering | MC_Render, MC_Render_Selected, MC_Render_P1 |
| Craft page and rotation | MC_P1_Controller, MC_Turn_Z |
| Animation | MC_Atlas_Player, MC_P1_Animation |

## Current installation

- [Selection and basket](docs/README_simple.md)
- [Craft page, returns, and Discard](docs/README_P1.md)
- [Atlas player and Cut/Stop integration](docs/README_Atlas.md)

The atlas player and atlas texture belong in the root prim's inventory; the display prim is **P1_DISPLAY**. HUD buttons contain no scripts. Diagnostic scripts, fixtures, and old controllers are not part of this installation.

## Organization

- `assets/`: textures, including the validated `atlas_chop_fond_fixe_v3.png`, `hud_p2.png` (background without a central image), the digit atlas, and retained P0 variants.
- `assets/sources/`: prompts, layers, and the atlas build script.
- `docs/`: documentation for the current assembly.
- `tools/`: optional diagnostic tools and a standalone atlas test.
- `tests/fixtures/`: simulated sources, to install in separate objects.
- `tests/`: syntax checks and behavior scenarios.
- `archive/2026-10-23/`: superseded versions, old experiments, and duplicates. Its manifest records moves and file hashes; originals of adapted files are in `before_cleanup/`.

P0 texture variants are retained: the cleanup did not choose a different layout. No files were deleted during that cleanup. Historical archives retain their original language.

## Verification

From PowerShell, run `./tests/run_hud_checks.ps1`. It covers selection, the craft page, Discard, and atlas integration. AST tests do not replace Mono compilation and visual checks in Second Life.

**Review:** the runner currently references `../Tools/MC_Memory_Probe.lsl`, which is absent from this checkout. Restore that optional tool or remove its entry from the runner before using the complete command. The runtime paths and VS Code parser path are specific to the development machine.

Animation is visually connected; crafting consumption, finesse, and output still need implementation.
