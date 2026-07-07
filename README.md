# Deep Delver — 2.5D Incremental Mining Prototype (Godot 4.6)

A side-view incremental mining game where every mineable tile is a real 3D
block viewed through an orthographic camera. Mine down through 10 biomes in
60-second runs, then spend resources & EXP at the surface to go deeper next time.

## How to run
1. Open the project in **Godot 4.6** (this folder — `project.godot`).
2. Press **F5** (main scene is `Main.tscn`).

## Controls
- **Left-click** a block to mine it (3 hits by default, 0.7s cooldown).
- **Hover** shows a green outline if mineable, red if blocked (fully surrounded).
- **Mouse wheel** zooms the camera.
- On the surface: click upgrade / skill buttons, then **START MINING RUN**.

## Core rules implemented
- A tile is mineable only if at least one cardinal neighbour (up/down/left/right)
  is open air. The surface (row 0) counts as air, so digging starts from the top.
- Tiles have health (clicks-to-break) that scales per biome; click damage,
  cooldown, resource yield, EXP, crit and depth bonuses are all upgrade-driven.
- Breaking a tile grants EXP always; resource tiles also drop resources + coins.
- 60-second timer → automatic return to the surface with a run summary.

## Systems
- **10 biomes** (Shallow Dirtworks → The Living Core) with distinct fillers,
  resources, colours, health scaling and ore **veins/clusters** (not evenly
  scattered). Colours match the `tile_atlas/` art palette.
- **Upgrades** (resource-cost): pickaxe damage, quick swing, lucky strike,
  deep miner, backpack, scholar's lamp, hire AI miner, miner speed/strength,
  basic drill, drill speed/power.
- **Skill tree** (EXP-cost) with 3 build paths: Manual, AI, Machinery.
- **AI miners** and **Basic Drills** auto-mine exposed tiles during a run
  (AI prefers resource tiles).
- **Save/load** to `user://deepdelver_save.json` between runs.

## Architecture (`scripts/`)
| File | Role |
|------|------|
| `GameData.gd` *(autoload)* | All definition data: resources, biomes, upgrades, skills |
| `GameState.gd` *(autoload)* | Persistent progression, effective-stat computation, buying, save/load |
| `MineGenerator.gd` | Chunk-based procedural grid + ore veins |
| `TileBlock.gd` | One 3D block: mesh, material, hover outline, damage/break feedback |
| `MineController.gd` | Builds the world/camera, mouse mining, AI/drills, round timer, summary |
| `HUD.gd` | In-run heads-up display |
| `SurfaceUI.gd` | Surface hub: summary, stockpile, upgrades, skill tree, start button |
| `Main.gd` | State machine swapping Surface ↔ Mine |

Everything is built in code from `Main.tscn`, so scenes are easy to regenerate.
Balancing lives in dictionaries in `GameData.gd` — add biomes/resources/upgrades
/skills there without touching gameplay code.

## Milestone status
- **M1** (grid, 2.5D blocks, mouse mining, open-side rule, 3-hit/0.7s, timer,
  resources, EXP, return to surface) — ✅
- **M2** (surface upgrades: damage, click speed, resource mult; run summary) — ✅
- **M3** (AI miner, Basic Drill, 3-path skill tree) — ✅
- **M4** (biome visuals/colours, rarity, ore veins, richer HUD/feedback) — partial ✅

## Next steps / ideas
- Swap flat cube colours for the textured `tile_atlas` (map atlas cells to
  `StandardMaterial3D.uv1_scale/uv1_offset` per tile).
- Ore Scanner upgrade (highlight nearby resources), machinery fuel (coal),
  Night Shift passive income, Explorer & Resource-Tycoon skill paths.
- Rolling despawn of far-above rows for very deep runs.
