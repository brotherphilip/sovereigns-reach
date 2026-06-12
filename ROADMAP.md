# SOVEREIGN'S REACH — DEVELOPMENT ROADMAP

> **Engine:** Godot 4.6.3 (GDScript)
> **Architecture:** Multiplayer-First Architecture (MFA) — Simulation/State strictly separated from View
> **GDD:** `GAME DESIGN DOC.md`
> Last updated: 2026-06-12

---

## PHASE 1: Core Architecture & Input ✅ COMPLETE
**Goal:** Event bus, command queue, serializable game state, fixed-timestep simulation clock, input → command mapper.

- [x] `project.godot` — Godot 4 project config, 5 autoloads registered
- [x] `simulation/core/EventBus.gd` — Global signal hub (all game events)
- [x] `simulation/core/CommandQueue.gd` — Intent queue; all player input becomes typed Commands
- [x] `simulation/core/SimulationClock.gd` — 20 Hz fixed timestep; PAUSED/NORMAL/FAST/FASTEST speeds
- [x] `simulation/core/GameState.gd` — Root serializable state (players, world, weather, edicts)
- [x] `simulation/core/InputSetup.gd` — Programmatic input action registration
- [x] `simulation/core/InputMapper.gd` — Godot Input → CommandQueue boundary (only file using Input API)
- [x] `tests/TestPhase1.gd` — Headless unit tests

---

## PHASE 2: The Simulation Loop ✅ COMPLETE
**Goal:** Grid math, terrain types, building footprints, resource production tick, weather system, and the full Popularity Engine formula.

- [x] `simulation/world/WorldGrid.gd` — 200×200 tile grid, terrain enum, passability masks, seeded procedural gen
- [x] `simulation/world/ShireMap.gd` — Shire borders, ownership, capital upgrades (5 levels), donation tracking
- [x] `simulation/economy/PopularityEngine.gd` — P = ΔF + ΔA + ΔR − T ± E, full formula with all modifiers
- [x] `simulation/economy/ResourceTick.gd` — 15 building types, production intervals, input/output chains
- [x] `simulation/world/WeatherSystem.gd` — 6 weather states, probability transitions, all GDD §1.1.3 effects
- [x] `tests/TestPhase2.gd` — 90 tests, all passing

**Key fix:** `preload()` is the correct pattern for non-autoload simulation classes in `--script` mode. `class_name` is NOT reliably available at parse time.

---

## PHASE 3: The Player Controller ✅ COMPLETE
**Goal:** Building placement validation, worker assignment, camera control commands, selection system.

- [x] `simulation/buildings/BuildingRegistry.gd` — 30+ building types with full metadata (GDD §5)
- [x] `simulation/buildings/BuildingState.gd` — Per-building runtime data (hp, workers, fire, production)
- [x] `simulation/buildings/PlacementValidator.gd` — Grid checks, terrain rules, tech requirements, border enforcement
- [x] `simulation/player/WorkerSystem.gd` — Peasant → job assignment, auto-assign priority, levy, inn/church coverage
- [x] `GameState.apply_command()` — PLACE_BUILDING, DEMOLISH_BUILDING, SET_BUILDING_WORKERS handlers wired
- [x] `tests/TestPhase3.gd` — 89 tests, all passing

**Key fix:** `BuildingRegistry.get()` conflicts with `Object.get()` built-in — renamed to `BuildingRegistry.lookup()`.
**Key fix:** `await process_frame` required in `_init()` before autoload resolution (same as Phase 2 pattern).

---

## PHASE 4: Core Gameplay Loop ✅ COMPLETE
**Goal:** Full Popularity Engine running per game-day tick, all economic chains, disease, weather penalties.

- [x] `simulation/economy/FoodSystem.gd` — Rations, granary cap enforcement, food variety, starvation flag
- [x] `simulation/economy/AleSystem.gd` — Inn coverage (per-tick), ale consumption at day boundaries
- [x] `simulation/economy/ReligionSystem.gd` — Church/Cathedral coverage → religion_coverage → ΔR
- [x] `simulation/economy/TaxSystem.gd` — Daily gold with shire modifier; replaced GameState._collect_taxes
- [x] `simulation/economy/DiseaseSystem.gd` — Crowding thresholds, apothecary coverage, outbreak/death/cure
- [x] `simulation/economy/MarketSystem.gd` — BUY/SELL commands, buy price markup (ceili 20%), price fluctuation
- [x] `GameState.gd` — Wired all 6 systems into _tick_player_economy; added BUY/SELL command handlers
- [x] `tests/TestPhase4.gd` — 60 tests, all passing

**Key fix:** `MarketSystem.get_buy_price` uses `ceili()` not `int()` to guarantee buy > sell for all base prices.
**Key fix:** Integer constants for CommandType (CT_BUY_RESOURCE=5, CT_SELL_RESOURCE=6) to avoid compile-time autoload resolution (same pattern as Phase 3).

---

## PHASE 5: Progression & Persistence ✅ COMPLETE
**Goal:** Save/load to JSON, tech tree with 5 branches, prestige accumulation, Shire Capital upgrades, Royal Edicts.

- [x] `simulation/persistence/SaveManager.gd` — JSON save/load with version guard; save/load/delete/metadata
- [x] `simulation/tech/TechTree.gd` — 20 techs across 5 branches; prerequisite chains; modifier stacking
- [x] `simulation/tech/PrestigeSystem.gd` — Food variety bonuses, popularity multiplier, capital multiplier, decay
- [x] `simulation/world/CapitalSystem.gd` — Donation tracking, 5 upgrade levels, server-wide buff dicts
- [x] `simulation/edicts/EdictSystem.gd` — 20 Edicts (Economy/Military/Logistics), active/passive, cooldowns, expiration
- [x] `GameState.gd` — Phase 5 preloads, PrestigeSystem/EdictSystem in tick loop, DONATE_TO_CAPITAL/ACTIVATE_EDICT handlers
- [x] `tests/TestPhase5.gd` — 98 tests, all passing

---

## PHASE 6: AI & Entities ✅ COMPLETE
**Goal:** Unit state machines, A* pathfinding, all 4 AI archetypes with distinct behaviors, siege assembly system.

- [x] `simulation/units/UnitRegistry.gd` — 20 unit types across 4 categories, full GDD §6 stats
- [x] `simulation/units/UnitState.gd` — Serializable unit state; attack_type × armor_type damage table
- [x] `simulation/pathfinding/Pathfinder.gd` — A* with terrain costs and passability masks; dict-grid test variant
- [x] `simulation/ai/AIFaction.gd` — Base AI: economy sim, threat level, siege assembly, tribute demands
- [x] `simulation/ai/BanditKing.gd` — Archetype 1: swarm harasser, 50% armed peasant + 40% archer
- [x] `simulation/ai/MerchantPrince.gd` — Archetype 2: hoards gold, elite crossbowmen, embargoes weak players
- [x] `simulation/ai/Ironhand.gd` — Archetype 3: iron/stone industrial, 50-unit army gate before attacking
- [x] `simulation/ai/AshenBarony.gd` — Archetype 4: Lord Malakor / Highwatch; 14-day tribute demand cycle
- [x] `simulation/combat/CombatSystem.gd` — Damage calc, anti-armor bonuses, captain morale, siege priorities
- [x] `tests/TestPhase6.gd` — 81 tests, all passing

---

## PHASE 7: UI & View Integration ⬜ NEXT
**Goal:** Isometric micro view, macro world map, HUD panels all wired to GameState. No logic here — view reads state only.

- [ ] `view/micro/MicroView.tscn` — Isometric tilemap, 4-way rotation
- [ ] `view/macro/MacroView.tscn` — World map with army banners, shire colors, trade routes
- [ ] `view/hud/HUD.tscn` — Popularity gauge, gold, prestige, ration sliders, tax slider
- [ ] `view/hud/TechTreePanel.tscn` — Research panel
- [ ] `view/hud/EdictPanel.tscn` — Edict cards with cooldown hourglass
- [ ] `view/micro/BuildingRenderer.gd` — State → visual mapping (dark=empty, animated=working)
- [ ] `view/micro/UnitRenderer.gd` — Unit state → sprite + animation
- [ ] `view/main/Main.tscn` — Root scene, view mode switching
