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

---

## 2026-06-13 — Phase 5: Progression & Persistence

### Files Created

| File | Purpose |
|------|---------|
| `simulation/persistence/SaveManager.gd` | JSON save/load with version guard (SAVE_VERSION=1). `save()`, `load_save()`, `save_exists()`, `delete_save()`, `get_save_metadata()`. Version mismatch or corrupt JSON returns empty dict. |
| `simulation/tech/TechTree.gd` | Static registry of 20 techs across 5 branches. Prerequisite DAG: `can_research()` validates unlocks+prestige; `research()` deducts prestige and appends to player.tech_unlocks. `get_all_modifiers()` merges all stat bonuses from researched techs. |
| `simulation/tech/PrestigeSystem.gd` | Prestige generation per game-day: BASE (5) + food_variety × 2 + building_bonus, multiplied by popularity tier (0.3–1.5) and capital level (+0.1/level). `spend()`, `can_afford()`, `apply_defeat_loss()`. |
| `simulation/world/CapitalSystem.gd` | Shire capital upgrade system (levels 0–5). Donation tracking per player per resource. `can_upgrade()` checks if donated resources cover UPGRADE_COSTS[level]. `upgrade()` increases level and resets donations. `get_capital_buffs()` returns buff dict per level (prestige_mult, edict_tier_cap, mining/vision/border bonuses). |
| `simulation/edicts/EdictSystem.gd` | 20 Edicts (Economy ×7, Military ×5, Logistics ×5, plus extras). PASSIVE: permanent while slot occupied. ACTIVE: expires after duration_ticks, goes on cooldown. `activate()` deducts edict_points, starts timer. `tick()` expires stale actives. `get_active_modifiers()` merges modifier dicts. |
| `tests/TestPhase5.gd` | 98 headless unit tests — all passing. Covers all 5 systems and 5 GameState integration commands. |

### Files Modified

| File | Change |
|------|--------|
| `simulation/core/GameState.gd` | Added preloads for TechTree, PrestigeSystem, CapitalSystem, EdictSystem, SaveManager. Added PrestigeSystem.tick() at day boundaries, EdictSystem.tick() every tick. Added `_cmd_donate_to_capital()`, `_cmd_activate_edict()`, `_cmd_research_tech()` handlers. Fixed edict_activated signal to include duration_ticks parameter. |

### Architecture Decisions

- **TechTree uses DAG prerequisites:** `research()` enforces the full prerequisite chain. Building unlock requirements are already encoded in BuildingRegistry.requires_tech, so TechTree only needs to track player.tech_unlocks.
- **EdictSystem returns modifiers dict:** `get_active_modifiers()` merges all active edict modifiers into a flat dict. Game systems (ResourceTick, etc.) can query this in Phase 6+ to apply bonuses without knowing which specific edicts are active.
- **SaveManager wraps state in metadata envelope:** `{"save_version": 1, "saved_at": unix_time, "state": {...}}` — version check is the outermost guard so corrupt/old saves are rejected before any deserialization.
- **ACTIVATE_EDICT handles instant effects in GameState:** levy_summons summon_peasants, festival_decree instant_event, and diplomatic_tribute instant_gold_bonus are applied by `_cmd_activate_edict()`, not EdictSystem, keeping EdictSystem pure-functional.

---

## 2026-06-13 — Phase 6: AI & Entities

### Files Created

| File | Purpose |
|------|---------|
| `simulation/units/UnitRegistry.gd` | Static registry of 20 unit types (GDD §6): 5 civilian, 5 light infantry, 5 heavy infantry, 5 siege. Each definition includes max_hp, attack, defense, attack_type (none/melee/pierce/siege), armor_type (none/light/heavy/structure), range, speed, cost_gold, equipment costs, requires_tech, requires_building, train_ticks, morale_buff. `can_recruit()` checks tech + building gate. `has_equipment()` validates armory. |
| `simulation/units/UnitState.gd` | Per-unit serializable state factory. `create()` returns a plain Dictionary. `apply_damage()` uses the attack_type × armor_type multiplier table (pierce×1.5 vs unarmored, siege×3.0 vs structure, melee×0.5 vs heavy). `issue_move_order()`, `issue_attack_order()`, `advance_along_path()`. Units are killed when hp ≤ 0. |
| `simulation/pathfinding/Pathfinder.gd` | A* on WorldGrid. Two variants: `find_path()` for WorldGrid instances, `find_path_dict()` for test Dictionary grids. 4-directional movement with terrain cost weights (road=0.5, forest=2.5, mountain=3.0, river=99.0). Passability masks: PASS_FOOT/PASS_CAVALRY/PASS_CART/PASS_SIEGE. Impassable target returns []. |
| `simulation/ai/AIFaction.gd` | Base AI state factory (`make_faction()`). Shared logic: `tick()` handles economy simulation and day increments, `should_attack()` compares threat_level vs archetype threshold, `start_siege()` begins 48-day tent assembly, `recruit_unit()`, `send_tribute_demand()`, `get_pending_demands()`. Threat level = army_value/10 + gold/100 + days/5. |
| `simulation/ai/BanditKing.gd` | Archetype 1. Swarm harasser. Large wood income, ignores stone. 50% armed_peasant + 40% archer + 10% militia army. Threshold 15 threat; attacks early and often. |
| `simulation/ai/MerchantPrince.gd` | Archetype 2. Economic defender. 80 gold/day income, hoards 2000 gold reserve. Elite crossbowman/swordsman/pikeman army. Threshold 60 threat; rarely attacks. Embargoes players with gold ≤ 50. |
| `simulation/ai/Ironhand.gd` | Archetype 3. Late-game industrial fortress. 25 iron/day + 200 gold/day. Tech: unit_unlocks + armor_forging + siege_engines. Swordsman/pikeman/trebuchet/ram/tunneler mix. Threshold 50; recruits to 50-unit army before attacking. |
| `simulation/ai/AshenBarony.gd` | Archetype 4 (Lord Malakor). Capital: Highwatch. Sends tribute demands (50 ale + 30 iron) every 14 game-days with 7-day deadline. Supply lines provide bonus wood income; cutting them (GDD §8.4.4) stops wall repairs. Swordsman/pikeman/trebuchet/ram/crossbowman mix. Threshold 40. |
| `simulation/combat/CombatSystem.gd` | `calculate_damage()`: applies anti-armor bonus (halberdier +25% vs heavy); immune_to_arrows blocks pierce on battering_ram; delegates to UnitState.apply_damage for multiplier table. `get_morale_attack_bonus()`: captain grants +10 attack to all allies. `resolve_combat()`: each alive attacker deals damage to random alive defender and vice versa; returns {attacker_casualties, defender_casualties}. `get_siege_priority()`: GDD §2.5.2 target mapping (ram→gatehouse, trebuchet→great_tower, swordsman→keep, etc.). |
| `tests/TestPhase6.gd` | 81 headless unit tests — all passing. Covers UnitRegistry (14), UnitState (12), Pathfinder (11), CombatSystem (14), AI Factions (21), GameState integration (9). |

### Files Modified

| File | Change |
|------|--------|
| `simulation/core/GameState.gd` | Added Phase 6 preloads: UnitRegistry, UnitState, AIFaction, BanditKing, MerchantPrince, Ironhand, AshenBarony, CombatSystem. Added `_next_unit_id` field. Added RECRUIT_UNIT, ISSUE_MOVE_ORDER, ISSUE_ATTACK_ORDER, DISBAND_UNIT command handlers. Added `add_ai_faction()` factory. `simulate_tick()` now ticks all ai_factions at day boundaries (dispatches to archetype tick). Updated serialize/deserialize to include next_unit_id. |

### Bugs Fixed

- A* `find_path_dict()` tested with a full-column river (all y) from (0,2) to (4,2): path was truly impossible. Fixed test to leave a gap at y=0 so a path exists.
- Halberdier anti-armor test used swordsman (defense=12) as target — defense cancelled bonus. Fixed to use zero-defense heavy-armored dummy.
- `AshenBarony` tribute demand check required 14 days; test only advanced 1 tick. Fixed test to loop 15 days.
- Integration tests used `_gs.simulate_tick()` which doesn't drain CommandQueue. Fixed to use `_sc._advance_tick()`.

### Architecture Decisions

- **Damage multiplier table in UnitState:** The attack_type × armor_type matrix lives in UnitState._damage_multiplier() so all code that applies damage uses a single path, whether it's player units, AI units, or CombatSystem.resolve_combat.
- **AI faction composition via static functions:** Each archetype file (BanditKing, MerchantPrince, etc.) has a `make()` factory and a `tick()` function. GameState.simulate_tick dispatches to the correct archetype file using a `match` on `faction["archetype"]`. No inheritance, no Node subclassing — pure composition.
- **Pathfinder carries its own passability/cost tables:** Constants duplicated from WorldGrid so Pathfinder is self-contained. A test-only `find_path_dict()` variant accepts a simple 2D tile array, avoiding the need to instantiate WorldGrid objects in unit tests.
- **SIEGE_PRIORITIES dict:** Rather than encoding target priorities as AI behavior, they're registered per unit type in CombatSystem.SIEGE_PRIORITIES so the View layer can also query them for HUD targeting indicators.

---

## 2026-06-13 — Phase 7: UI & View Integration

### Files Created

| File | Purpose |
|------|---------|
| `view/micro/BuildingRenderer.gd` | Pure static mapper: BuildingState dict → visual data dict (`state`, `animation`, `color_tint`, `show_fire`, `hp_bar`, `label`, `workers`). States: empty (no workers), working (staffed+operational), fire (on_fire flag), damaged (hp < 30%). `has_progress_bar()` checks produces dict; `get_tile_layer()` maps BuildingRegistry.Category enum to 0–4 layer index. |
| `view/micro/UnitRenderer.gd` | Pure static mapper: UnitState dict → sprite info dict (`animation`, `health_bar`, `color_tint`, `label`, `facing_dir`, `is_alive`). Dead units → `{animation:"die", color_tint:"dead"}`. Color tint encodes team as "player_N" or "enemy" (owner_id < 0). Facing derived from pos→target delta. |
| `view/micro/MicroViewController.gd` | Isometric coordinate system: 4-way rotation transforms (NW/NE/SE/SW); `grid_to_screen()` / `screen_to_grid()` round-trip. `get_build_preview()` delegates to PlacementValidator. `get_building_render_list()` and `get_unit_render_list()` extract full render arrays from player dict. |
| `view/hud/HUDController.gd` | `get_hud_data()` produces complete HUD dict (gold, prestige, popularity tier+color, tax/ration labels, food totals, weather, edict points, inn/religion coverage). `get_popularity_tier()` (revolt/poor/fair/good/excellent) and `get_popularity_color()` are testable in isolation. `format_tick_time()` converts ticks to "Day N (T/240)". |
| `view/hud/TechTreePanelController.gd` | `get_panel_data()` returns branches dict keyed by Branch enum (all 5 branches), prestige, unlocked_count. `get_tech_status()` returns `researched` / `available` / `unaffordable` / `locked`. `get_researchable_items()` returns only items TechTree.can_research() approves. |
| `view/hud/EdictPanelController.gd` | `get_panel_data()` returns `{active, available, locked, edict_points}`. Active cards include remaining_label. `format_ticks()` formats tick countdown as "Xd Y%" or "Ready". `get_remaining_ticks()` and `get_cooldown_remaining()` are separately queryable. |
| `view/macro/MacroViewController.gd` | `get_shire_render_list()` — shire id/owner/color/name/level. `get_player_army_banners()` — alive players with ≥1 alive unit. `get_ai_army_banners()` — alive AI factions. `get_siege_tent_data()` — active siege_assembly with 0–1 progress and eta_label. `is_tile_revealed()` / `get_revealed_tiles()` for fog-of-war queries. Color palettes: SHIRE_COLORS[8] for players, AI_COLORS per archetype. |
| `view/main/MainController.gd` | Root Node subclass. `ViewMode` enum: MICRO/MACRO/TECH_TREE/EDICTS. `switch_to_micro()`, `switch_to_macro()`, `toggle_tech_tree()`, `toggle_edicts()` set visibility on NodePath-referenced child scenes. Connects `EventBus.state_changed` → `_refresh_all()` which calls all panel controllers and applies data via `apply_hud_data()` / `apply_render_data()` / `apply_panel_data()` duck-typed calls. |
| `view/micro/MicroView.tscn` | Minimal valid Godot 4 scene — Node2D root, no script. Stub for isometric tile layer. |
| `view/macro/MacroView.tscn` | Minimal valid Godot 4 scene — Node2D root. Stub for macro world-map layer. |
| `view/hud/HUD.tscn` | CanvasLayer root with PopularityBar, GoldLabel, PrestigeLabel, DayLabel as overlay widgets. TechTreePanel and EdictPanel as hidden child Controls. |
| `view/hud/TechTreePanel.tscn` | Control root with VBoxContainer + per-branch HBoxContainers for tech card layout. |
| `view/hud/EdictPanel.tscn` | Control root with ActiveEdicts / AvailableEdicts / LockedEdicts HBoxContainers. |
| `view/main/Main.tscn` | Root scene: Main (Node + MainController.gd) → MacroView (Node2D) + MicroView (Node2D) + HUD (CanvasLayer → TechTreePanel + EdictPanel). NodePath exports wired so MainController can toggle visibility. |
| `tests/TestPhase7.gd` | 98 headless unit tests — all passing. Covers HUDController (20), TechTreePanelController (12), EdictPanelController (10), BuildingRenderer (13), UnitRenderer (11), MicroViewController (10), MacroViewController (12), MainController (5). |

### Bugs Fixed

- `BuildingRenderer.get_tile_layer()` matched strings ("food", "military") against `BuildingRegistry.Category` which stores enum integers (CIVIC=0, HARVESTING=1, FOOD=2, MILITARY=3, DEFENSE=4). Fixed to match against `BuildingRegistry.Category.X` enum values.
- `BuildingRenderer.has_progress_bar()` checked `production_interval` field which doesn't exist in BuildingRegistry. Fixed to check `produces` dict non-empty (any building with output shows a progress bar).
- Test for `popularity_tier` at 62.0 expected "fair" (40–60 range) but 62 falls in "good" (60–80). Fixed expected value.

### Architecture Decisions

- **View layer is pure static functions:** All `*Controller.gd` files extend `RefCounted` with only static methods. Runtime signal connections live in `MainController.gd` (the one Node subclass). This keeps every controller 100% headless-testable without a scene tree.
- **No direct GameState reads in view controllers:** Controllers accept plain Dictionary arguments. The EventBus `state_changed` signal delivers a serialized snapshot. Controllers never hold references to live simulation nodes.
- **Duck-typed apply methods:** `MainController._refresh_*` calls `has_method("apply_X")` before invoking view node callbacks. This means scene children don't need to implement every interface — a missing method is silently skipped, not an error. Avoids tight coupling between Main.tscn and the controller logic.
- **`BuildingRenderer.get_tile_layer()` maps to render layers 0–4:** Layer ordering (food, harvesting, military, civic, defense) matches the intended Z-order for the isometric tilemap: food buildings at ground level, defensive structures at highest layer. HARVESTING maps to layer 1 (industry group) rather than a new entry to keep the layer count to 5.
