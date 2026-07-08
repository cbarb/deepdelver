# Deep Delver — Session Handoff

Context brief so a fresh Claude Code session (or a human) can continue this project on another machine. **Start there:** open in Godot 4.6, then tell Claude *"read HANDOFF.md and continue."*

---

## What this is
A **2.5D incremental mining game** in **Godot 4.6**. Side-view; every mineable tile is a real 3D block viewed with an orthographic camera. 60-second runs → return to a surface hub → spend resources/coins/skill points on upgrades → dig deeper next run. Three co-equal mining styles: **Pickaxes (manual)**, **Golems (auto units)**, **Machinery (infrastructure)**.

- **Full design spec:** `Deep Delver Game Design.docx` (in repo root). This is the source of truth for intended design; read it for the golem/pickaxe/machinery tiers, skill tree, and specializations.
- **Prototype status notes / milestones:** `README.md`.

## How to run & verify
- Open the folder in **Godot 4.6**, press **F5** (main scene `Main.tscn`).
- **Headless verification (important):** Godot is on PATH as `godot` (symlinked from `~/Downloads/Godot.app`; on a new machine, re-point it or add an alias). I develop by writing throwaway test harnesses and running headless — no GUI needed:
  - Compile check: `godot --headless --editor --quit-after 2 2>&1 | grep -iE 'SCRIPT ERROR|Parse|Compile|Failed'`
  - Behavior test: write a temp `TestX.gd`+`.tscn`, run `godot --headless --quit-after <frames> res://TestX.tscn`, grep prints, then delete the temp files.
  - Headless can't render pixels — visual issues (layout, colors) must be checked in the real editor. Several bugs so far were visual (UI collapse, draw order) and needed the user to screenshot.
- **GDScript 4.6 gotcha hit repeatedly:** `var x := dict.get(...) == y` fails type inference — use explicit `var x: bool = ...`.

## Architecture (`scripts/`, all built in code from a 1-line `Main.tscn`)
| File | Role |
|---|---|
| `GameData.gd` *(autoload)* | ALL definition data: resources, biomes, pickaxes, golems, machines, skill tree (generated), tile textures, biome bgs, pickaxe cursors |
| `GameState.gd` *(autoload)* | Persistent progression + `get_effective_stats()` (folds pickaxe/upgrades/skills) + buying + leveling + save/load (JSON at `user://deepdelver_save.json`) |
| `Main.gd` | State machine: swaps Surface ↔ Mine |
| `MineController.gd` | Builds world/camera/lights/backdrop, mouse mining, golem AI, machines, overflow splash, round timer, run summary |
| `MineGenerator.gd` | Chunked procedural grid + ore veins |
| `TileBlock.gd` | One 3D block: textured cube, hover outline, damage/break FX, scanner marker |
| `HUD.gd` | In-run HUD; hides OS cursor & owns the `CursorRing` |
| `CursorRing.gd` | Software cursor: draws equipped pickaxe sprite + cooldown ring, follows mouse |
| `SurfaceUI.gd` | Surface hub: run summary, stockpile+crusher, upgrade shops (pickaxe/golem/machinery/etc.), skill-tree launcher, start button |
| `SkillTreePanel.gd` | Full-screen radial 100+ node skill tree (custom-drawn, pan/zoom, click-to-buy) |

## Core systems (implemented)
- **Mining rules:** click a tile (3 hits base, 0.7s cooldown); tile mineable only if ≥1 cardinal neighbour is air (surface = air). Filler vs resource tiles; EXP always, resources on resource tiles.
- **10 biomes** with per-biome fillers/resources/colors/health scaling, ore **veins**. Tile faces use `assets/tile_materials/tile_r<row>_c<col>.png` on all cube sides. Biome **backdrops** (`assets/biome_bg/`, note biome 4 = `b4.png`) cross-fade behind blocks per biome.
- **Lighting:** dark scene + a warm **mouse torch** (OmniLight follows cursor).
- **Overflow splash:** when a hit exceeds a tile's HP, the excess is split **evenly across the 8 surrounding blocks** (`_overflow_splash`). The earlier **chain-reaction** mechanic is **shelved but kept** (`_overflow_chain`/`_process_chains`, `SHELVED` comment) — re-enable by swapping the call in `_damage_tile`.
- **Economy:** filler drops **Rubble**; resources go to stockpile (not auto-sold). **Coins** come from the **Crusher** (surface: Rubble→Coins). Coins are spendable (cost dicts accept a `"coins"` key).

### The three shops (all data-driven; internal golem stat keys are still `ai_*` — a display-only rename, restructure later if desired)
- **Pickaxe Shop** (`GameData.PICKAXES`, 11 entries, index=tier, 0=starter): one-time craft, unlocks by reaching its biome, sets **base click damage** + a unique manual effect (shatter/instant/dup/refund/depth/filler-exp). Equipped pickaxe folds into `get_effective_stats()` and drives the **cursor sprite**.
- **Golem Workshop** (`GameData.GOLEMS`, 10 tiers): a **roster** — own many of each tier (`GameState.golems` tier→count), escalating cost per tier. Golems are **gravity-bound agents** (`_process_miner`): they fall, never jump, walk to the nearest block, mine adjacent tiles, and **claim targets so no two share a block**. Global buffs: `ai_damage` (+add), `ai_interval` (×mult), `ai_resource_bonus`.
- **Machinery** (`GameData.MACHINES` + `buy_*` upgrades): Basic Drill (flying), **Auto-Hammer** (area splash), **Line Drill** (column pierce), **Deep Bore** (auto downward shaft), **Conveyor** (resource_mult), **Ore Scanner** (marks resource tiles), **Fuel Engine** (burns coal to speed machines), **Crusher**. Shared stats `machine_damage`/`machine_speed`. Deferred: **Refinery, Core Extractor** (need a refined-crafting/prestige layer).

### Skill system
- **Leveling:** mining grants EXP → levels (`25·level^1.5` per level) → **1 skill point/level**. `GameState.level_progress()`, `skill_points_available/total/spent()`.
- **Radial tree:** `GameData._build_skill_tree()` generates **102 nodes** (34 per section: Manual/Golem/Machinery), rings 1–9, sizes small→medium→large→capstone (cost 1/2/3/5, maxlvl 5/3/2/1), each connects to a parent in the prior ring. Effects reuse the stat system. Opened via "OPEN SKILL TREE" → `SkillTreePanel`.

## Save format (`user://deepdelver_save.json`)
`resources, money, exp, lifetime_exp, upgrade_levels, skill_levels, max_depth, pickaxe_tier, golems`. Note: golem/skill/upgrade **ids are keys** — renaming ids orphans old saves (fine in dev; `GameState.reset_progress()` wipes).

## Specializations (built)
Implemented. 3 specializations — **Striker** (manual), **Stonewarden** (golem), **Engineer** (machinery), each with **7 unique skills, pick only 4**. **Spec points** are earned at biome milestones (reach biome 3/5/7/9 = 4 pts total; `GameState.spec_points_total()` from `max_depth`). Picking the first skill in a path **locks in** that specialization and locks out the other two paths' skills (normal tree nodes stay open). Respec deferred but `GameState.clear_specialization()` exists (used by the Debug menu).
- **Data:** `GameData.SPECIALIZATIONS` (display: name/style/color/blurb + 7 skills each) + `SPEC_MILESTONE_BIOMES` / `SPEC_MAX_PICKS`. Numeric effects live in `GameState._apply_specialization()` (keyed by skill id), folded into `get_effective_stats()` after the general tree. New effective-stat fields (`manual_frenzy`, `golem_prefer_resource`, `golem_unique_mult`, `golem_active_bonus`, `machine_resource_bonus`, `machine_deep_bonus`, `fuel_bonus`, `machine_aftershift`) are read by `MineController` at runtime.
- **UI:** `SpecializationPanel.gd` (3-column chooser), opened via the **SPECIALIZE** button in the surface Skill Book. Debug menu can auto-pick a full spec or clear it.
- **Simplifications:** Synchronized Strike → flat golem-damage bonus (golems still claim unique tiles, so no true co-targeting); Focus Orders does resource-priority only (not damaged-tile priority).

## NEXT STEP (open)
Refinery + Core Extractor machines (need a refined-crafting/prestige layer), endless game modes (stubbed on the descent screen), and a paid respec for specializations.

## Honest scope / simplifications to revisit
- Skill tree **large/capstone nodes are big stat boosts**, not yet bespoke "mechanic-changing" uniques (doc examples like "every 10th click = shockwave").
- Some tier sub-effects simplified: Ember "burn" & Titanium "consecutive-click ramp" → splash/depth; Mycelium/Spore "charge meter" → per-hit chance; golem "lock-on"/Relic EXP bonus deferred; pickaxe "reveal rare" = Ore Scanner's job.
- Fuel boosts timer-machines (hammer/line/bore); Basic Drill uses `machine_speed` but not live fuel.
- Ore Scanner reveals all resource tiles at any level.
- Radial tree is functional, not art-polished. Surface UI is functional/plain.

## Assets
- `assets/tile_materials/tile_r{1..10}_c{1..7}.png` — cube face textures (row=biome).
- `assets/biome_bg/` — backdrops (`bg1..bg10`, biome 4 = `b4.png`).
- `assets/pickaxes2/pickaxe_{01..11}.png` — cursor sprites (01=starter … 11=Core).
- `tile_atlas/` — the original sprite atlas (unused by the game now; kept for reference).
