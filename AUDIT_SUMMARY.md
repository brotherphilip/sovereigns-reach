# Sovereign's Reach — Comprehensive Audit Summary

**Date:** 2026-06-14 | **Status:** Part 1–4 Complete, Parts 5–7 Remaining

## Completed Work

✅ **Part 1: Click-Through UI Fix** (committed `ec4924a`)
- `PlayerInputHandler._input → _unhandled_input` + gui_is_hovered() guard
- `CameraController._input → _unhandled_input`
- `Minimap._input → _unhandled_input`
- Fixed minimap unit position fields: grid_x/grid_y → pos_x/pos_y
- Added missing TerrainDecorationLayer to scene tree
- Wired minimap camera and positioned in HUD

✅ **Part 4: Dead Code Deletion** (committed `395c109`)
- Removed `scripts/Minimap.gd` (placeholder, superseded)
- Removed `scenes/Minimap.tscn` (orphaned reference)
- Removed `view/main/MainController.gd` (never instantiated)

## Remaining Critical Work

### Part 3: Simulation Gaps (HIGH → LOW severity)

| # | Location | Issue | Status |
|---|---|---|---|
| **S1** | GameState._tick_player_unit_movement | Attack orders (`ORDER_ATTACK`) never execute | **PENDING** |
| **S2** | GameState._cmd_recruit_unit | Training queue absent — units spawn instantly | **PENDING** |
| **S3** | BuildingRegistry | No `leather_armor`/`plate_armor`/`crossbows` production | **PENDING** |
| **S4** | GameState | Population never grows (stuck at 50) | **PENDING** |
| S5 | GameState._tick_player_economy | Desertion never triggers | **PENDING** |
| S6 | GameState + BuildingRegistry | `"keep"` building unregistered but referenced | **PENDING** |
| S7 | GameState._cmd_recruit_unit | Captain uniqueness not enforced | **PENDING** |
| S8 | MilestoneSystem | `three_shires` milestone never fires | **PENDING** |
| S9 | DiplomacySystem | Player can't respond to tribute demands | **PENDING** |
| S10 | EdictSystem | `storage_capacity_bonus` never consumed | **PENDING** |
| S11 | PlacementValidator | `unique: true` flag not enforced | **PENDING** |
| S12 | MarketSystem | Direct autoload reference (test safety) | **PENDING** |
| S13 | ShireMap | Hardcoded RNG seed 42 | **PENDING** |
| S14 | CapitalSystem | `edict_tier_cap` not enforced | **PENDING** |
| S15 | AshenBarony | Supply line cut mechanic missing | **PENDING** |
| S16 | SaveManager | No save version migration | **PENDING** |

### Part 5: System Consolidations (reduce duplication)

| Duplicate pair | Winner | Status |
|---|---|---|
| AleSystem vs WorkerSystem coverage | AleSystem | **PENDING** |
| ReligionSystem vs WorkerSystem coverage | ReligionSystem | **PENDING** |
| FoodSystem.tick() vs ResourceTick | FoodSystem | **PENDING** |
| 3x embargo checkers | DiplomacySystem | **PENDING** |
| 2x screen_to_grid | MicroViewController | **PENDING** |
| 2x capital upgrade | CapitalSystem | **PENDING** |

### Part 6: Content Additions

**Simulation:**
- Armorer building (leather_armor + plate_armor production)
- Crossbow workshop (crossbows production)
- `keep` building (late-game village_hall upgrade)
- Static emplacements (ballista, mangonel, etc.)
- More milestones (combat victory, tech research, capital donation, siege survived)
- More difficulty modifiers (disease, fire, siege frequency)

**World:**
- Coastal terrain depth (1-tile → 2–3 tile strips)
- City name uniqueness

**UI/Content:**
- Game icon (project.godot)
- UI theme resources
- Audio files (currently all SFX silent)
- Font overrides (currently using Godot default)
- HUD layout fixes (hardcoded offsets → HBoxContainer)

**Code:**
- TestPhase8 (missing test suite)
- TestPhase10 (missing test suite)
- Build Omniscience RAG index
- Export presets (distribution builds)

### Part 7: Project Configuration

- Fix features tag: "Forward Plus" → "GL Compatibility"
- Add project icon
- Disable/condition file logging for release
- Add `__pycache__/` to .gitignore

## Recommended Execution Order

1. **S1** (Attack orders) — foundational combat mechanic
2. **S2** (Training queue) — core unit system
3. **S3** (Armor/crossbow production) — builds on S2
4. **S4** (Population growth) — economy mechanic
5. Consolidations (reduce code duplication)
6. **S5–S11** (Medium-severity fixes)
7. **S12–S16** (Low-severity fixes)
8. Part 6 (Content additions)
9. Part 7 (Config/deployment)

## Test Coverage

After each fix, run:
```bash
godot --headless --script tests/TestPhase[N].gd
```

Phases 1–7 and 9 exist. Phase 8 and 10 missing.
