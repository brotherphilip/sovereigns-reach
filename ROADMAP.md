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

## PHASE 3: The Player Controller ⬜ NEXT
**Goal:** Building placement validation, worker assignment, camera control commands, selection system.

- [ ] `simulation/buildings/BuildingRegistry.gd` — All building types, costs, footprints, worker slots
- [ ] `simulation/buildings/BuildingState.gd` — Per-building runtime data (hp, workers, production)
- [ ] `simulation/buildings/PlacementValidator.gd` — Grid checks, terrain rules, spacing rules
- [ ] `simulation/player/WorkerSystem.gd` — Peasant → job assignment logic
- [ ] `view/micro/CameraController.gd` — View-layer camera (reads view commands, not direct input)

---

## PHASE 4: Core Gameplay Loop ⬜
**Goal:** Full Popularity Engine running per game-day tick, all economic chains, disease, weather penalties.

- [ ] `simulation/economy/FoodSystem.gd` — Rations, granary distribution, food variety bonuses
- [ ] `simulation/economy/AleSystem.gd` — Hops → brewery → inn AoE distribution
- [ ] `simulation/economy/ReligionSystem.gd` — Church/Cathedral radius, blessing rates
- [ ] `simulation/economy/TaxSystem.gd` — Daily tax tick, gold ledger, bribe mechanics
- [ ] `simulation/economy/DiseaseSystem.gd` — Crowding → disease spread, apothecary cure radius
- [ ] `simulation/economy/MarketSystem.gd` — Fluctuating server-wide prices, cart generation

---

## PHASE 5: Progression & Persistence ⬜
**Goal:** Save/load to JSON, tech tree with 5 branches, prestige accumulation, Shire Capital upgrades, Royal Edicts.

- [ ] `simulation/persistence/SaveManager.gd` — JSON save/load with versioning
- [ ] `simulation/tech/TechTree.gd` — 5 branches (Agriculture, Industry, Military, Statecraft, Prestige)
- [ ] `simulation/tech/PrestigeSystem.gd` — Points/min, multipliers, decay, spending
- [ ] `simulation/world/CapitalSystem.gd` — Donation tracking, upgrades, server-wide buffs
- [ ] `simulation/edicts/EdictSystem.gd` — All 20 Edicts (Economy/Military/Logistics/Capital)

---

## PHASE 6: AI & Entities ⬜
**Goal:** Unit state machines, A* pathfinding, all 4 AI archetypes with distinct behaviors, siege assembly system.

- [ ] `simulation/units/UnitRegistry.gd` — All unit types, base stats, equipment requirements
- [ ] `simulation/units/UnitState.gd` — Per-unit serializable state (position, hp, orders, faction)
- [ ] `simulation/pathfinding/Pathfinder.gd` — A* on WorldGrid with terrain costs
- [ ] `simulation/ai/AIFaction.gd` — Base AI class (economy sim, logistics, diplomacy)
- [ ] `simulation/ai/BanditKing.gd` — Archetype 1: swarm harasser, wooden forts
- [ ] `simulation/ai/MerchantPrince.gd` — Archetype 2: economic defender, elite units
- [ ] `simulation/ai/Ironhand.gd` — Archetype 3: late-game industrial fortress
- [ ] `simulation/ai/AshenBarony.gd` — Archetype 4: Lord Malakor, Highwatch capital
- [ ] `simulation/combat/CombatSystem.gd` — Damage calc, armor, siege targeting priorities
- [ ] `tests/TestPhase6.gd`

---

## PHASE 7: UI & View Integration ⬜
**Goal:** Isometric micro view, macro world map, HUD panels all wired to GameState. No logic here — view reads state only.

- [ ] `view/micro/MicroView.tscn` — Isometric tilemap, 4-way rotation
- [ ] `view/macro/MacroView.tscn` — World map with army banners, shire colors, trade routes
- [ ] `view/hud/HUD.tscn` — Popularity gauge, gold, prestige, ration sliders, tax slider
- [ ] `view/hud/TechTreePanel.tscn` — Research panel
- [ ] `view/hud/EdictPanel.tscn` — Edict cards with cooldown hourglass
- [ ] `view/micro/BuildingRenderer.gd` — State → visual mapping (dark=empty, animated=working)
- [ ] `view/micro/UnitRenderer.gd` — Unit state → sprite + animation
- [ ] `view/main/Main.tscn` — Root scene, view mode switching
