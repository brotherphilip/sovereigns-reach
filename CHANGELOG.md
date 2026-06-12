# CHANGELOG

---

## 2026-06-12 — Phase 1: Core Architecture & Input

### Files Created

| File | Purpose |
|------|---------|
| `project.godot` | Godot 4.6 project config. 5 autoloads registered in dependency order. |
| `ROADMAP.md` | Full 7-phase development plan derived from GDD. |
| `CHANGELOG.md` | This file. |
| `systems_bibliography.html` | Living codebase encyclopedia. |
| `simulation/core/EventBus.gd` | Global signal hub (all game events, no logic). |
| `simulation/core/CommandQueue.gd` | Typed intent queue with 25 CommandTypes covering all player actions. |
| `simulation/core/SimulationClock.gd` | 20 Hz fixed-timestep loop, 4 speed modes (PAUSED/1×/2×/5×). |
| `simulation/core/GameState.gd` | Root serializable state: players, world, weather, edicts, AI factions. |
| `simulation/core/InputSetup.gd` | Programmatic input action registration (no complex project.godot serialization). |
| `simulation/core/InputMapper.gd` | View-layer boundary: Godot Input → CommandQueue. Only file using Input API. |
| `tests/TestPhase1.gd` | 69 headless unit tests — all passing. |

---

## 2026-06-12 — Phase 2: The Simulation Loop

### Files Created

| File | Purpose |
|------|---------|
| `simulation/world/WorldGrid.gd` | 200×200 tile grid. 11 terrain types with passability masks (foot/cavalry/cart/siege), movement costs, farm yield multipliers. Seeded procedural map generation (rivers, mountains, forests, ore veins, marshes, valleys). serialize/deserialize via base64 PackedArrays. |
| `simulation/world/ShireMap.gd` | Shire ownership and capital system. 5 biome traits. Capital upgrades (0–5 levels, grants prestige buffs). Donation tracking per player per resource. Tax rate modifiers. |
| `simulation/economy/PopularityEngine.gd` | Full P = ΔF + ΔA + ΔR − T ± E formula. Food variety bonuses, starvation detection, ale coverage scaling, 12 external event modifiers, prestige multiplier tiers. Static functions only. |
| `simulation/economy/ResourceTick.gd` | 15 building types with production intervals and input/output chains (mill→flour, bakery→bread, brewery→ale, blacksmith→swords). Worker-scaled output, terrain yield multipliers, food consumption on day boundaries. |
| `simulation/world/WeatherSystem.gd` | 6 weather states (clear/rain/drought/snow/fog/storm). Weighted probability transition table. Duration ranges per state. Effects: movement penalty, farm yield multiplier, food drain, popularity delta, fog_army_ui flag. |
| `tests/TestPhase2.gd` | 90 headless tests, all passing. Uses preload() for all simulation class references. |

### Files Modified

| File | Change |
|------|--------|
| `simulation/core/GameState.gd` | Added WeatherSystem/PopularityEngine/ResourceTick as preload constants. `_init_default_state` initializes weather via WeatherSystem. `simulate_tick` now ticks weather, resource production, food consumption, popularity, and tax collection. Added `_tick_player_economy` and `_collect_taxes`. |

### Bugs Fixed

- `BiomeTrait.VALLEY` didn't exist in ShireMap enum (removed stray case)
- PopularityEngine double-negation: `- tax_delta` was wrong; `TAX_POPULARITY_DELTA` already carries sign
- `WeatherSystem.get_name()` conflicted with GDScript built-in — renamed to `weather_name()`
- ResourceTick produced at tick 0 (0 % interval = 0); added `current_tick == 0` guard

### Architecture Decisions

- **Autoload order:** EventBus → CommandQueue → SimulationClock → GameState → InputSetup.
  Each layer depends only on earlier-loaded singletons at runtime.
- **No Godot objects in state:** All `GameState` fields use plain Dictionary/Array/int/float/bool.
  `Vector2i` replaced with `keep_x`/`keep_y` for JSON safety.
- **CommandType as enum in CommandQueue:** Tests mirror the enum order as constants to avoid
  compile-time autoload resolution failures in `--script` mode.
- **SimulationClock drives everything:** `_advance_tick()` is the single authority that drains
  CommandQueue, applies commands, ticks GameState, and emits `simulation_tick`.
