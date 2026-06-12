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

---

## 2026-06-12 — Phase 3: The Player Controller

### Files Created

| File | Purpose |
|------|---------|
| `simulation/buildings/BuildingRegistry.gd` | Static registry of 30+ building types (GDD §5). Definitions include category, dimensions (1×1 to 4×4), costs, terrain bitmask requirements, tech requirements, HP, fire risk, production/consumption, coverage radii. |
| `simulation/buildings/BuildingState.gd` | Per-building runtime instance factory. `create()` returns a serializable Dictionary. `take_damage()`, `repair()`, `ignite()`, `tick_fire()`, `worker_efficiency()` for combat and fire spread. |
| `simulation/buildings/PlacementValidator.gd` | Validates PLACE_BUILDING commands before state mutation: bounds check, occupancy (all tiles of multi-tile buildings), terrain bitmask match, tech requirements, resource costs, shire influence radius. |
| `simulation/player/WorkerSystem.gd` | Peasant ↔ job assignment. `assign_workers()`, `auto_assign()` (food → harvesting → civic priority), `levy_peasants()` (GDD §7.3.2 edict), `calculate_inn_coverage()`, `calculate_religion_coverage()`. |
| `tests/TestPhase3.gd` | 89 headless unit tests — all passing. Covers BuildingRegistry, BuildingState, PlacementValidator, WorkerSystem, and GameState Phase 3 commands. |

### Files Modified

| File | Change |
|------|--------|
| `simulation/core/GameState.gd` | Added preloads for BuildingRegistry, BuildingState, PlacementValidator, WorkerSystem, WorldGrid, ShireMap. Added `_grid`, `_shire_map`, `_next_building_id` runtime vars. Added `setup_world()`. Added `_cmd_place_building()`, `_cmd_demolish_building()`, `_cmd_set_building_workers()` handlers. Added `find_building()`. Updated `serialize()`/`deserialize()` with grid round-trip and building_id repopulation. Added `population` and `military_strength` to `_make_player()`. |
| `simulation/core/EventBus.gd` | Added `building_placement_failed` signal. |

### Bugs Fixed

- `BuildingRegistry.get()` conflicted with `Object.get()` built-in (same class as Phase 2's `WeatherSystem.get_name()` bug). Renamed to `lookup()` throughout.
- `await process_frame` omitted in TestPhase3 `_init()`: autoloads returned null because they weren't yet in the scene tree. Added consistent with Phase 2 pattern.
- `PlacementValidator` tests used single tile for 2×2 quarry terrain check — all footprint tiles must match terrain_req bitmask.
- Out-of-bounds test used (9,9) on 10×10 grid which is valid for a 1×1 building — corrected to (10,9).

### Architecture Decisions

- **`lookup()` not `get()`:** GDScript's `Object.get(prop)` built-in shadows any user-defined static `get()` function when called on a preloaded GDScript object. Named all registry accessors differently from Object methods.
- **Buildings stored as Dicts in player.buildings:** `ResourceTick` and `GameState` iterate `player["buildings"]` expecting Dictionaries, not IDs. All building state lives directly in the array, no separate lookup map needed for Phase 3.
- **Grid occupancy repopulated on deserialize:** WorldGrid's `_building_id` and `_unit_id` PackedArrays are not serialized (they're reconstructed from player building state), keeping save files lean.

---

### Architecture Decisions

- **Autoload order:** EventBus → CommandQueue → SimulationClock → GameState → InputSetup.
  Each layer depends only on earlier-loaded singletons at runtime.
- **No Godot objects in state:** All `GameState` fields use plain Dictionary/Array/int/float/bool.
  `Vector2i` replaced with `keep_x`/`keep_y` for JSON safety.
- **CommandType as enum in CommandQueue:** Tests mirror the enum order as constants to avoid
  compile-time autoload resolution failures in `--script` mode.
- **SimulationClock drives everything:** `_advance_tick()` is the single authority that drains
  CommandQueue, applies commands, ticks GameState, and emits `simulation_tick`.

---

## 2026-06-12 — Phase 4: Core Gameplay Loop

### Files Created

| File | Purpose |
|------|---------|
| `simulation/economy/FoodSystem.gd` | Granary capacity enforcement (sum of `storage_max` across granary buildings, default 200). Food consumption at day boundaries in `FOOD_CONSUMPTION_ORDER` (apples→bread→cheese→meat). Starvation flag, shortage tracking, `apply_granary_cap()` spills cheapest food first. |
| `simulation/economy/AleSystem.gd` | Inn coverage ratio (staffed inns × 4 / hovel count, clamped 0–1). Updates `player.inn_coverage` on every tick. Consumes ale at day boundaries per inn per day scaled by ale_ration. |
| `simulation/economy/ReligionSystem.gd` | Church (radius 12) and Cathedral (radius 30) coverage. `coverage_sum / tiles_per_hovel / hovel_count`, clamped 0–1. Updates `player.religion_coverage` every tick. `coverage_to_popularity_delta` scales to MAX 10.0. |
| `simulation/economy/TaxSystem.gd` | Replaces `GameState._collect_taxes`. Daily gold = `abs(tax_rate) × 0.5 × population × shire_modifier`. Negative rates deduct gold (bribe). Gold floored at 0. |
| `simulation/economy/DiseaseSystem.gd` | Crowding threshold: 5+ hovels with apothecary coverage < 0.5. `OUTBREAK_PROBABILITY` = 8%/day. Active disease kills 2 peasants/day. High coverage (≥ 0.8) cures disease. Returns `["disease_outbreak"]` event string for PopularityEngine. |
| `simulation/economy/MarketSystem.gd` | `initialize_prices()` populates `world["market_prices"]`. Buy price = `ceili(base × 1.2)`, sell price = base. `tick_prices()` fluctuates ±30% every 10 game-days. `buy()`/`sell()` require a market building and check gold/stock. |
| `tests/TestPhase4.gd` | 60 headless unit tests — all passing. Covers all 6 systems and 6 GameState integration commands. |

### Files Modified

| File | Change |
|------|--------|
| `simulation/core/GameState.gd` | Added preloads for all Phase 4 systems. Added `_disease_rng`. `setup_world()` now calls `MarketSystem.initialize_prices()`. `_tick_player_economy()` rewritten: AleSystem/ReligionSystem every tick; DiseaseSystem, FoodSystem.apply_granary_cap, TaxSystem, MarketSystem.tick_prices, PopularityEngine at day boundaries. Added `_cmd_buy_resource()` and `_cmd_sell_resource()` handlers. Removed `_collect_taxes()`. |
| `simulation/economy/MarketSystem.gd` | `get_buy_price` changed from `int(base × 1.2)` to `ceili(base × 1.2)` to guarantee buy > sell for all base prices including cheap items (e.g. wood=3: int(3.6)=3=sell; ceili(3.6)=4>3). |

### Bugs Fixed

- `MarketSystem.get_buy_price` used `int()` truncation: for wood (base=3), int(3×1.2)=int(3.6)=3 equals sell price. Fixed to `ceili()`.
- `CommandQueue.CommandType.BUY_RESOURCE` reference in test caused compile-time reload of CommandQueue.gd, which fails because `SimulationClock` isn't available then — corrupting the autoload node. Used integer constants instead (CT_BUY_RESOURCE=5, CT_SELL_RESOURCE=6).

### Architecture Decisions

- **Coverage values updated every tick:** `AleSystem.tick()` and `ReligionSystem.tick()` run on every tick (not just day boundaries) so `PopularityEngine` always reads fresh `inn_coverage` / `religion_coverage` on the day boundary where it runs.
- **TaxSystem replaces GameState._collect_taxes():** Phase 4 moves all gold collection into TaxSystem.tick() to keep GameState thin. Same tick-boundary guard: `tick > 0 and tick % 240 == 0`.
- **DiseaseSystem returns events array:** Instead of directly modifying popularity, DiseaseSystem returns `["disease_outbreak"]` which GameState passes to PopularityEngine via the events array, keeping the popularity delta logic in one place.
