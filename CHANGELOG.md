# CHANGELOG

---

## [Iteration 81] 2026-06-14 — Fix #037: weather popularity event mismatches (STORM too harsh, RAIN ignored)

- Delegated to: Supervisor
- What changed:
  - GameState.gd: match block for weather events — changed STORM→"blizzard" to STORM→"storm"; added RAIN→"rain" case
  - PopularityEngine.gd: added "storm": −2 and "rain": −1 to EVENT_POPULARITY_DELTA
- Before: STORM caused −5/day (2.5× too harsh); RAIN caused 0/day (should be −1). Both mismatches vs WeatherSystem.WEATHER_EFFECTS definitions.
- Scene test: ALL_SCENES_OK
- Issues resolved: #037
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 80] 2026-06-14 — Audit: full command handler payload audit — all clear

- Delegated to: Supervisor (STEP 3D — Audit)
- What changed: no code changes
- Audited all 17 implemented command handlers in GameState.apply_command() against their callers in PlayerInputHandler.gd, GameBootstrap.gd, CityViewScene.gd — all payload keys match
- UPGRADE_BUILDING and SET_TRADE_ROUTE are enum stubs with no callers — harmless, not bugs
- Confirmed #036 fix was the only payload key mismatch across all commands
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 79] 2026-06-14 — Fix #036: market trade silently broken — payload key mismatch

- Delegated to: Supervisor
- What changed: GameState.gd lines 635 and 648 — changed `payload.get("quantity", 0)` to `payload.get("amount", 0)` in _cmd_buy_resource() and _cmd_sell_resource(). Callers (GameBootstrap, CityViewScene) enqueue with key "amount"; GameState was reading key "quantity" (always returned 0). All market trades permanently did nothing — quantity 0 passed to MarketSystem silently.
- Scene test: ALL_SCENES_OK
- Issues resolved: #036
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 78] 2026-06-14 — Audit pass: cross-file constant and serialization checks

- Delegated to: Supervisor (STEP 3D — Audit)
- What changed: no code changes
- Cross-file checks: all 12 CT_ constants in PlayerInputHandler verified against CommandQueue enum (0-25, all correct); CT_ constants in GameBootstrap/CityViewScene also verified
- GameState.serialize()/deserialize() verified complete — includes all 10 fields (world, players, ai_factions, weather, active_edicts, server_config, milestones, clock, next_building_id, next_unit_id)
- EdictSystem.tick() → EventBus.edict_expired emit chain verified correct
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 77] 2026-06-14 — Audit pass: FULL CODEBASE AUDIT COMPLETE — all clear

- Delegated to: Supervisor (STEP 3D — Audit)
- What changed: no code changes
- Files audited: CityViewScene.gd, SimulationClock.gd, WorldMapScene.gd, MainMenuScene.gd
- Verified: GameState.server_config exists and is initialized; GameState.get_city() exists; EventBus.game_speed_changed matches SimulationClock.set_speed() emit
- All 67 GDScript files across simulation/ and view/ have now been explicitly audited over iterations 67–77. No open issues remain.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 76] 2026-06-14 — Audit pass: all clear, no new issues

- Delegated to: Supervisor (STEP 3D — Audit)
- What changed: no code changes
- Files audited: BuildingState.gd, DifficultySystem.gd, PlacementValidator.gd, BuildingRenderer.gd, WorldGrid (get_building_at), MainController.gd (dead code — not attached to Main.tscn), Pathfinder.gd, UnitRegistry.gd (can_recruit)
- Key findings: building IDs start at 1 (0 = empty, != 0 check correct); MainController.gd is dead code (not in scene, connects to signals that don't exist, but never instantiated); UnitRegistry correctly guards is_active on required buildings
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 75] 2026-06-14 — Audit pass: all clear, no new issues

- Delegated to: Supervisor (STEP 3D — Audit)
- What changed: no code changes
- Files audited: SaveManager.gd, TechTreePanelController.gd, DiplomacyPanel.gd, NotificationFeed.gd, GameBootstrap.gd
- All EventBus signal connections in GameBootstrap.gd verified against EventBus.gd (10 signals, all match)
- Tutorial logic in GameBootstrap._show_tutorial_prompt() confirmed correct (misleading comment, not a bug)
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 74] 2026-06-14 — Audit pass: all clear, no new issues

- Delegated to: Supervisor (STEP 3D — Audit)
- What changed: no code changes
- GDD spot-checks: DiseaseSystem (disease_active gated correctly), UnitState kill guard (is_alive check before unit_killed.emit), CapitalSystem upgrade wiring (_cmd_donate_to_capital), AudioManager signal connections (all 8 EventBus connections match declared signals) — all clean
- TODO/FIXME/HACK grep: nothing found across simulation/ and view/
- Scene test: CityViewScene.tscn and Main.tscn load OK (ALL_SCENES_OK)
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iterations 70-72] 2026-06-14 — Fix #032 #033 #034: deep audit bugs (demolished building production, weather display)

- Delegated to: Supervisor
- What changed:
  - #032 (iter 70): GameState._tick_player_economy() — added `or not building.get("is_active", true)` guard before calling ResourceTick.tick_building(). Buildings with hp=0 (demolished/on fire) were still producing resources.
  - #033 (iter 71): HUDNode._refresh_top_bar() and HUDController.get_hud_data() — replaced `weather.get("current_name", …)` with `WeatherSystem.weather_name(weather.get("current", 0))`. The weather dict never had a "current_name" key; WeatherSystem only stores the weather type as an int under "current". The HUD weather label was permanently stuck showing "Clear".
  - #034 (iter 72): HUDController.get_weather_tooltip() — fixed three key mismatches vs WeatherSystem.WEATHER_EFFECTS: "speed_modifier"→"movement_penalty", "farm_yield"→"farm_yield_mult", and `weather.get("popularity_delta")` → `weather["effects"].get("popularity_delta")`. All effects were invisible in the tooltip. Added WeatherSystem preload to both HUDNode.gd and HUDController.gd.
- Issues resolved: #032 #033 #034
- Issues discovered: none (full audit of all 67 GDScript files complete — EventBus signal consistency verified)

---

## [Iteration 69] 2026-06-14 — Fix #031: player shire_id never assigned

- Delegated to: Supervisor
- What changed: GameState._make_player() — added `"shire_ids": []` key. New `_assign_starting_shire()` function finds nearest unclaimed shire to player's start position, sets player["shire_id"] and player["shire_ids"] = [shire_id], marks shire["owner_id"] = player_id. Called from initialize_player(). Before this, shire_id was always -1: donations silently failed, PrestigeSystem capital multiplier always returned 0, TaxSystem shire modifier always returned 0, milestone "three_shires" could never trigger.
- Issues resolved: #031
- Issues discovered: none

---

## [Iterations 67-68] 2026-06-14 — Fix #023: unit movement never executes; commit 791 lines of phase work

- Delegated to: Supervisor
- What changed (iter 67): GameState._cmd_issue_move_order() now calls Pathfinder.find_path() and stores result in unit["move_path"]. New _tick_player_unit_movement() advances units along their path at speed-gated intervals (TICKS_PER_DAY / speed). Called from simulate_tick(). Previously, UnitState.issue_move_order() set order/target but no tick ever advanced position.
- What changed (iter 68): committed 791 lines of unstaged phase implementation work across 18 files (AudioManager UNIT_HIT/DEATH events; DiplomacySystem embargo; TutorialSystem persistence; SaveManager meta; HUDController tooltips; DiplomacyPanel threat bar; NotificationFeed fade animation; TechTreePanelController hints; GameBootstrap tutorial overlay; PlayerInputHandler set_building_layer; UnitLayer damage popups/death ring/hit flash/morale color shift; and more).
- Issues resolved: #023
- Issues discovered: #031 (during audit)

---

## [Iteration 66] 2026-06-14 — Fix #030: MacroMapView shire flash animation never fires — wrong dict key

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: MacroMapView._draw_shires() line 79: changed `shire.get("shire_id", -1)` to `shire.get("id", -1)`. The render dict from MacroViewController.get_shire_render_list() uses key "id", not "shire_id" — so every comparison returned -1 and the flash condition was never true.
- Issues resolved: #030 (shire capture flash never shown)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 65] 2026-06-14 — Fix #029: MacroViewController shows player color for AI-captured shires

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: MacroViewController.get_shire_color() rewritten. Previous logic checked `owner_id < 0` for AI factions (dead code — AI IDs are non-negative), then returned SHIRE_COLORS[owner_id] for positive IDs — showing player 0's blue for bandit king (id=0) and player 1's green for ashen barony (id=1). New logic: returns NEUTRAL_COLOR for negative owner, then scans ai_factions for a match first, then falls back to SHIRE_COLORS for players. Removed dead `owner_id in fac["shire_ids"]` inner check.
- Issues resolved: #029 (AI-captured shires show wrong color)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 64] 2026-06-14 — Fix #027 #028: CityViewScene save path invalid + build ghost missing

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: CityViewScene.gd — (1) `_do_save()` now saves to `SM.DEFAULT_SAVE_PATH` ("user://sovereign_save.json") instead of bare `"save_slot_1"` which was not a valid writable path on any platform; also added meta dict (game_day, shire_count, difficulty) matching GameBootstrap. (2) `_build_scene()` now calls `_input_handler.set_building_layer(_bld_layer)` after setup(), same as GameBootstrap; without this, `PlayerInputHandler._bld_layer` was null, causing `_update_ghost()` to return early — build placement ghost preview was never shown.
- Issues resolved: #027 (saves always fail in CityViewScene), #028 (build ghost not shown in CityViewScene)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 63] 2026-06-14 — Fix #026: Population count never shown in HUD — orphan label stub

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: HUDNode.gd — added `_pop_count_label: Label` member var. `_build_right_panel()` now assigns the return value of the "Population:" `_add_label()` call to `_pop_count_label` (previously discarded). `_refresh_right_panel()` now updates `_pop_count_label.text = "Pop: %d"` from `player["population"]` each refresh cycle. Population count is now visible in the right panel alongside tax, rations, and food variety.
- Issues resolved: #026 (population count never displayed)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 62] 2026-06-14 — Fix #025: WorldMapScene has_method("server_config") always false — world always seed 42

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: WorldMapScene._init_and_build() seed_val calculation simplified from a ternary with `GameState.has_method("server_config")` to a direct `GameState.server_config.get("map_seed", 42)`. Also updated TestPhase6.gd and TestPhase7.gd building fixtures from `is_operational` to `is_active` key for consistency with BuildingState.
- Issues resolved: #025 (world map always seeds from 42)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 61] 2026-06-14 — Fix #024: BuildingRenderer/BuildingLayer wrong field names — buildings always empty

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: BuildingRenderer.get_visual_state() changed `building.get("is_operational", false)` to `building.get("is_active", true)`. BuildingLayer._on_tick() changed `b.get("state", "") == "fire"` to `b.get("is_on_fire", false)`. Both bugs used wrong field names (is_operational never written; "state" exists in view-state dicts but not raw simulation building dicts). Buildings now correctly show "working" animation when staffed, and fire animation redraws per-frame when any building is on fire.
- Issues resolved: #024 (buildings always rendered as empty)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 60] 2026-06-14 — Fix #022: UnitRegistry.can_recruit() checked wrong field — all units unrecruitable

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: UnitRegistry.can_recruit() line 325 changed from `b.get("is_operational", false)` to `b.get("is_active", true)`. BuildingState uses `"is_active"` (never writes `"is_operational"`). The wrong default of `false` meant the required-building check always failed for every unit type, making the entire unit recruitment system permanently locked. All units — peasants, scouts, military infantry, siege — require a specific building (village_hall, barracks, armory, etc.) and were all blocked.
- Issues resolved: #022 (military system permanently locked)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 59] 2026-06-14 — Fix #021: first_edict milestone inner check used non-existent player_id field

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: MilestoneSystem.check() `first_edict` inner condition changed from `e.get("player_id", -1) == pid` to `e is Dictionary and e.has("id")`. EdictSystem.activate() stores entries without a player_id field; since iter 54 already ensures we iterate the correct player's own active_edicts, the player_id check was both wrong and unreachable. Also fixed test fixture in TestPhase7.gd: shire dict changed from `"level": 2` to `"capital_level": 2` to match the MacroViewController key fix (iter 57).
- Issues resolved: #021 (first_edict milestone still unreachable after iter 54 partial fix)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 58] 2026-06-14 — Fix #020: is_starving never set — prestige starvation gate bypassed

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: Added starvation flag update in GameState._tick_player_economy() after FoodSystem.apply_granary_cap(): `player["is_starving"] = FoodSystem.get_total_food(player) <= 0 and player.get("population", 0) > 0`. FoodSystem.tick() (which previously set this flag) was never called; ResourceTick.tick_food_consumption() handled deduction but not the flag. PrestigeSystem now correctly halts prestige generation during famine.
- Issues resolved: #020 (starvation no longer halts prestige)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 57] 2026-06-14 — Fix #019: Capital auto-upgrade and MacroViewController key mismatch

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: `GameState._cmd_donate_to_capital()` now calls `CapitalSystem.can_upgrade(shire, world)` after `record_donation()` and triggers `upgrade()` if donations meet the threshold. Capital level now advances automatically (and PrestigeSystem._capital_multiplier() gains +10–50% per level). MacroViewController.gd fixed from `shire.get("level", 0)` to `shire.get("capital_level", 0)` so macro map capital display reflects actual level.
- Issues resolved: #019 (capital never upgrades; macro view always shows level 0)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 56] 2026-06-14 — Fix #018: Edict passive modifiers never applied — edict effects now live

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: All active edict modifiers now affect the simulation. Five systems wired: (1) ResourceTick.tick_building() applies food_production_bonus (+100% food output for great_harvest edict) to bread, meat, cheese, wheat, hops, flour, apples. (2) ResourceTick.tick_food_consumption() reduces daily_demand by food_consumption_reduction (10%) for rationing/frugal_feasts edicts. (3) TaxSystem.calculate_daily_gold() applies tax_multiplier (2×) from tax_levy_multiplier edict before difficulty scaling. (4) MarketSystem.sell() applies market_sell_price_bonus (+50%) from merchant_favoritism edict. (5) GameState fire ignition loop applies fire_risk_reduction (100%) from fire_warden edict. Also fixed two instant-effect gaps in _cmd_activate_edict(): wall_repair_amount now calls BuildingState.repair() on all buildings; popularity_delta now applies for non-summon edicts (e.g. tax_levy_multiplier). Deferred modifiers (movement speeds, training times, storage caps, wall armor, shire radius) require dedicated system hookpoints not yet established.
- Issues resolved: #018 (edict modifiers entirely inert)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 55] 2026-06-14 — Fix #017: edict_points daily regeneration — Royal Edict system unlocked

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: GameState._tick_player_economy() now generates +2 edict_points per game-day at the day boundary, capped at min(20, 10 + int(prestige)//100). edict_points was initialized to 0 and never incremented anywhere, making all 20 Royal Edicts permanently inaccessible despite a complete EdictSystem, UI panel, 20 edict definitions, and cost/cooldown logic. Players now reach the cheapest edict (cost 2) after 1 game-day; the cap grows from 10 to 20 as prestige accumulates, per GDD §7.1.2.
- Issues resolved: #017 (edict system entirely blocked by zero edict_points)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 54] 2026-06-14 — Fix #016: MilestoneSystem passed wrong active_edicts — "first_edict" unreachable

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: GameState._tick_player_economy() now passes `player.get("active_edicts", [])` to MilestoneSystem.check() instead of `active_edicts` (the server-level var which EdictSystem never populates — edicts live in player["active_edicts"]). The "first_edict" milestone now correctly fires the first time a player activates any Royal Edict.
- Issues resolved: #016 (wrong active_edicts reference kills first_edict milestone)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 53] 2026-06-14 — Fix #015: apply prestige defeat loss on building destruction

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: GameState.gd now calls PrestigeSystem.apply_defeat_loss(player) immediately before emitting EventBus.building_destroyed at both destruction sites — fire (in the per-tick fire damage loop) and siege (in the siege_assembled handler). Players lose 50 prestige per building destroyed. PrestigeSystem.apply_defeat_loss() was previously only called in unit tests.
- Issues resolved: #015 (defeat prestige loss never applied)
- Issues discovered: none
- Supervisor correction: Fixed indentation on fire site (first attempt produced 4 tabs, corrected to 3).

---

## [Iteration 52] 2026-06-14 — Fix #014: setup_world() now re-seeds all three RNGs from map_seed

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: GameState.setup_world() now adds `_disease_rng.seed = seed_value ^ 0xDEADBEEF` and `_fire_rng.seed = seed_value ^ 0xCAFEBABE` immediately after the existing `_weather_rng.seed = seed_value` line. Previously only the weather RNG was re-seeded on world setup, leaving disease and fire randomness pinned to the default 12345 seed regardless of the map_seed argument.
- Issues resolved: #014 (disease/fire RNGs not re-seeded on setup_world)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 51] 2026-06-14 — Fix #013: fire state key mismatch — view reads wrong dict key

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: BuildingRenderer.gd:23 changed from `building.get("on_fire", false)` to `building.get("is_on_fire", false)`. HUDNode.gd:568 same fix. TestPhase7.gd test fixture dicts updated from "on_fire" key to "is_on_fire" to match the canonical state shape used by simulation (BuildingState.ignite(), tick_fire(), TestPhase3.gd). Fire visuals (orange tint, fire overlay, HP bar in BuildingLayer) and the HUD "Fire: YES" indicator now correctly reflect when a building has caught fire.
- Issues resolved: #013 (fire state key mismatch)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 50] 2026-06-14 — Fix #012: wire fire mechanic — weather ignition and per-tick damage

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: GameState.gd now fully activates the fire mechanic. (1) Added `_fire_rng` (RandomNumberGenerator seeded map_seed ^ 0xCAFEBABE) to keep fire randomness independent from disease/weather streams. (2) Per-tick fire damage loop added in `_tick_player_economy()` after the production loop — calls BuildingState.tick_fire() for each building; emits EventBus.building_destroyed(..., "fire") if returned true. (3) Day-boundary weather ignition check: reads weather.effects.fire_risk (0.02 DROUGHT, 0.05 STORM); rolls _fire_rng per active non-burning building and calls BuildingState.ignite() on a hit. BuildingState.ignite() and tick_fire() were fully coded but unreachable before this fix.
- Issues resolved: #012 (fire mechanic completely disconnected)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 49] 2026-06-14 — Audit: all-clear

- Delegated to: Supervisor (Omniscience unavailable — Ollama HTTP 500)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags in simulation/ and view/. (2) GDD spot-checks — PrestigeSystem.tick() called daily at GameState:231, TechTree.research() deducts prestige at TechTree:238, DiseaseSystem and FoodSystem both fully implemented with starvation/outbreak logic. (3) CHANGELOG spot-checks — MilestoneSystem.gd exists, AIFaction.last_siege_player_id at line 82, mid-siege combat block in GameState all confirmed present. (4) building_production_tick signal is a defined stub (not emitted, not connected) consistent with iter 46 finding. (5) prestige_changed not emitted on research spend — acceptable because HUD polls prestige each tick via _refresh_top_bar(). No genuine issues found.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 48] 2026-06-14 — Fix #011: add prestige balance label to HUD top bar

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: HUDNode.gd top bar now displays the player's prestige balance. Added `_prestige_label: Label` variable. `_build_top_bar()` creates an amber "Prestige: 0" label after the weather label (x += 160 gap). `_refresh_top_bar()` updates it each simulation_tick from `player["prestige"]`. Players can now track prestige accumulation from milestones and know their balance before opening the tech panel.
- Issues resolved: #011 (prestige balance never shown in HUD)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 47] 2026-06-14 — Fix #010: wire CombatSystem into mid-siege battle loop

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: GameState AI day-boundary tick now runs a mid-siege combat round each game-day while any faction's siege_assembly is non-empty. Snapshots alive unit IDs on both sides, calls CombatSystem.resolve_combat(attacker_units, defender_units, rng) where rng is seeded deterministically from tick ^ (faction_id * 7919). After resolution, emits EventBus.unit_killed per newly dead unit on both sides. faction defeat check (iter 40 — all units dead → ai_faction_defeated) is now reachable: a player with enough military can repel a siege by killing all attacking units before siege_assembly completes. CombatSystem, UnitState, and unit_killed are now fully active in the game loop.
- Issues resolved: #010 (CombatSystem.resolve_combat() never called — unit combat loop not wired)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 46] 2026-06-14 — Audit: #010 logged (unit combat loop not wired)

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags. (2) building "id" field confirmed present in BuildingState.create() — building_destroyed emit correct. (3) unit_killed: connected in GameBootstrap, CityViewScene, AudioManager, but CombatSystem.resolve_combat() is never called from anywhere in simulation/. UnitState.apply_damage() sets is_alive=false on kill but nothing invokes combat rounds. Logged as #010 (Low — requires battle invocation loop design, out of scope). (4) resource_changed, fog_of_war_updated, trade_route_updated — not emitted anywhere, no handlers connected either — confirmed as stubs defined for future use.
- Issues resolved: none
- Issues discovered: #010 (unit combat loop not wired — CombatSystem.resolve_combat() never called)
- Supervisor correction: none

---

## [Iteration 45] 2026-06-14 — Fix #009: siege deals building damage, player defeat now functional

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: Audit found building_destroyed signal connected in GameBootstrap/CityViewScene for player defeat ("Your keep has fallen!") but BuildingState.take_damage() was never called anywhere. BuildingState already has full HP tracking (village_hall has 500 HP) and take_damage() returns true on destruction. GameState siege_assembled handler now also calls BuildingState.take_damage(village_hall_building, 150) after shire capture. On destruction emits EventBus.building_destroyed(player_id, building_id, "siege"). Player defeat condition is now fully functional: after 3-4 successful enemy sieges the village hall is destroyed and the game-over screen fires.
- Issues resolved: #009 (building_destroyed never emitted — siege damage not implemented)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 44] 2026-06-14 — Audit: ALL CLEAR

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags. (2) Full archetype event coverage audit: all 6 AI event strings (bandit_raid_started, ironhand_siege_started, ashen_siege_started, merchant_siege_started, ashen_tribute_demanded, siege_assembled) are handled in GameState's AI event loop — no gaps. (3) Spot-checked: shire capture bounds check (target_pid >= 0 and < players.size(), is_empty() guard), AshenBarony tribute deadline calc, AudioManager siege audio hook. All correct.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 43] 2026-06-14 — Fix #008: siege warning missing for AshenBarony and MerchantPrince

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: Audit found that iter 39's siege warning fix only covered "bandit_raid_started" and "ironhand_siege_started". AshenBarony emits "ashen_siege_started" and MerchantPrince emits "merchant_siege_started" — both were missing from the ev-in check. Added both strings to the list in GameState simulate_tick(). All 4 AI archetypes now emit ai_siege_assembling when starting a siege. Also confirmed: serialize/deserialize round-trips last_siege_player_id via ai_factions.duplicate(true). Shire capture works for all 4 factions.
- Issues resolved: #008 (ashen/merchant siege warning missing from emit check)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 42] 2026-06-14 — Audit: ALL CLEAR

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags. (2) Verified iter 40 defeat check (units.is_empty() guard, any_alive loop) and iter 41 siege_assembled handler (last_siege_player_id recovery, shire transfer logic) — both look correct in live code. (3) GDD spot-checked: WeatherSystem FOG type + transitions, TutorialSystem disease_active contextual hint, HUDController ALE_POP/TAX_POP popularity breakdown tooltip — all present.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 41] 2026-06-14 — Fix #007: shire capture wired to siege mechanic

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: (1) AIFaction.tick() now saves faction["last_siege_player_id"] from asm["target_player_id"] before clearing siege_assembly — target info survives the event dispatch. (2) GameState AI event loop now handles "siege_assembled": reads last_siege_player_id, removes first shire from target player's shire_ids array, updates world["shires"][id]["owner_id"] to faction id, emits EventBus.shire_ownership_changed(shire_id, old_owner, faction_id). MacroMapView's white arc flash animation (_shire_flashes) now fires on shire capture.
- Issues resolved: #007 (shire_ownership_changed never emitted — no shire capture mechanic)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 40] 2026-06-14 — Fix #006: faction defeat mechanic + win condition

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: GameState simulate_tick() now runs a defeat check after each day-boundary AI tick. For each alive faction with at least one recruited unit (units array non-empty), if all units have is_alive=false → sets faction["is_alive"]=false and emits EventBus.ai_faction_defeated. Both GameBootstrap and CityViewScene handlers already implement the full win flow: show "Enemy faction defeated" notification + check if all factions dead → victory screen "All enemies vanquished! Sovereign's Reach is yours!". The win condition is now fully functional end-to-end.
- Issues resolved: #006 (ai_faction_defeated never emitted — no defeat mechanic)
- Issues discovered: none (issue #007 shire_ownership_changed deferred — requires shire capture mechanic beyond current polish scope)
- Supervisor correction: none

---

## [Iteration 39] 2026-06-14 — Signal audit: fix #004 edict_expired + #005 ai_siege_assembling

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: Signal consistency audit comparing EventBus defined/emitted/connected sets. Found 4 signals with handlers but no emitters. Fixed 2: (1) GameState._tick_player_economy() now captures EdictSystem.tick() return value and emits EventBus.edict_expired(player_id, edict_id) per expired edict — "Edict expired" notifications now fire. (2) GameState simulate_tick() AI event loop now handles "bandit_raid_started" and "ironhand_siege_started" events, emitting ai_siege_assembling(faction_id, target_player_id, SIEGE_ASSEMBLY_TICKS) — siege warning HUD notifications and audio now fire.
- Issues resolved: #004 (edict_expired discarded), #005 (ai_siege_assembling not emitted)
- Issues discovered: #006 (ai_faction_defeated — no defeat mechanic, factions never die), #007 (shire_ownership_changed — no shire capture mechanic, ShireMap.set_owner never called)
- Supervisor correction: none

---

## [Iteration 38] 2026-06-14 — Audit: ALL CLEAR

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags. (2) Spot-checked: PrestigeSystem tick % 240 boundary, DiplomacyPanel all 4 ARCH_FLAVOR archetypes, MacroMapView _draw_faction_legend and ARCH_DISPLAY — all verified present. Project in clean steady state.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 37] 2026-06-14 — Audit: ALL CLEAR

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags. (2) Spot-checked: TutorialSystem tutorial_step persistence, SaveManager SAVE_VERSION + extra_meta, NotificationFeed HBoxContainer + dismiss button — all verified present in live code. Project remains in clean steady state.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 36] 2026-06-14 — Audit: ALL CLEAR

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags across simulation/ and view/. (2) Spot-checked 3 CHANGELOG items: MilestoneSystem.check() call (iter 35), fog_army_ui reads in MacroMapView (iter 34), is_embargoed + 1.40 markup in MarketSystem (iter 33) — all verified present in live code. (3) DiplomacySystem.refuse() embargo wiring verified. Project is in a clean steady state.
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 35] 2026-06-13 — Fix #003: MilestoneSystem implemented

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: (1) Created simulation/core/MilestoneSystem.gd: defines 5 milestones (first_woodcutter, first_farm, population_50, first_edict, three_shires), each granting +50 prestige. Static check() method mutates GameState.milestones dict in-place — acts as a one-way latch. (2) GameState.gd: added MilestoneSystem preload, calls MilestoneSystem.check() at each day boundary in _tick_player_economy(); emits EventBus.milestone_earned per newly-earned milestone. (3) EventBus.gd: added milestone_earned(player_id, milestone_id, prestige_bonus) signal. (4) HUDNode.gd: connects milestone_earned → _on_milestone_earned(); shows a gold 6s notification with milestone label and prestige bonus.
- Issues resolved: #003 (milestones dict stub — now live with 5 single-player milestones)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 34] 2026-06-13 — Audit + Fix #002: Fog weather hides army banners

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: (1) Audit found two pre-existing gaps: fog_army_ui effect unread in MacroMapView (medium), and milestones dict entirely unused (low, deferred). (2) Fixed #002: MacroMapView._draw_player_banners() now returns early when GameState.weather["effects"]["fog_army_ui"] is true. _draw_ai_banners() replaces full banners with a faint "?" circle during fog, correctly hiding army troop counts per GDD §1.1.3. Logged #003 (milestones stub) as a deferred low-priority item.
- Issues resolved: #002 (fog_army_ui not wired to MacroMapView)
- Issues discovered: #003 (milestones dict stub — deferred)
- Supervisor correction: none

---

## [Iteration 33] 2026-06-13 — Fix #001: Ashen Barony tribute refusal embargo

- Delegated to: Supervisor (Omniscience unavailable)
- What changed: (1) DiplomacySystem.refuse() now appends player_id to faction["embargoed_players"] on refusal and marks all pending demands for that player as fulfilled=true (so cooldown resets and future demands scale higher). Added static is_embargoed(faction, player_id) helper. (2) MarketSystem.gd gains is_embargoed(player) which checks GameState.ai_factions for any embargo; buy() applies a 40% price markup when embargoed. (3) DiplomacyPanel refusal notification updated: "trade embargo imposed. Market prices rise. Expect retaliation."
- Issues resolved: #001 (Ashen Barony embargo not implemented)
- Issues discovered: none
- Supervisor correction: none

---

## [Iteration 32] 2026-06-13 — Audit: ALL CLEAR

- Delegated to: Supervisor (Omniscience unavailable — Ollama 500 error)
- What changed: No code changes. Audit only.
- Audit results: (1) Zero TODO/FIXME/BUG/HACK/XXX flags across simulation/ and view/. (2) Spot-checked Phase 6 (ARCH_FLAVOR, DiplomacyPanel threat bar), Phase 8 (SaveManager extra_meta, auto-save), Phase 9 (TutorialSystem STEP_OPEN_MARKET, skip_tutorial), Phase 10 (hover_sty, _animate_panel_open) — all verified present. (3) GDD §8.4.2 describes "embargoes on refusal" for Ashen Barony — not implemented in AshenBarony.gd (MerchantPrince has embargo logic). Pre-existing gap, low priority.
- Issues resolved: none
- Issues discovered: Pre-existing gap — Ashen Barony embargo not implemented (GDD §8.4.2). Added to issue log.
- Supervisor correction: Ran audit manually (Omniscience offline)

---

## [Iteration 31] 2026-06-13 — Phase 10: UI Consistency & Micro Polish — ALL PHASES COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: (1) NotificationFeed notification text normalized to 12pt (was 15pt). (2) HUDNode._add_button() now sets a blue-tinted hover StyleBox (bg: 0.30/0.38/0.55, blue border) on every button produced by the helper — consistent hover feedback everywhere. (3) Build menu button tooltip_text extended to explain disable reason: "Requires: X tech" or "(Cannot afford)". (4) _toggle_tech_panel() and _toggle_edict_panel() now use _animate_panel_open (fade in 0.18s) and _animate_panel_close (fade to 0, then hide, 0.14s) instead of direct visible toggle. (5) Recruit button tooltips now show "Name · Cost: Xg · HP: Y · Atk: Z" for enabled state, appending the disable reason string for disabled state. (6) MainMenuScene._MenuBG now has a _process(delta) that advances _angle and calls queue_redraw(), plus draws an 8-spoke rotating decorative sigil ring (two arcs + radial lines) at screen center-top with parchment gold color at low opacity.
- Files changed: `view/hud/NotificationFeed.gd`, `view/hud/HUDNode.gd`, `view/menu/MainMenuScene.gd`
- Supervisor correction: none
- **POLISH CYCLE COMPLETE — All 10 phases implemented (Iterations 1–31)**

---

## [Iteration 30] 2026-06-13 — Phase 9: Tutorial & Onboarding — Phase 9 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: (1) TutorialSystem.gd fully rewritten: step flow now extends to STEP_OPEN_MARKET (build granary → hint about market), STEP_USE_EDICT (after any gold decrease from trading → hint about edicts), STEP_DONE (after first edict activation → completion message). Connects to gold_changed, edict_activated, ai_envoy_sent, simulation_tick signals. ai_envoy_sent triggers a one-time hint about diplomacy. Contextual edict hints fire every 20 game-days if popularity < 35 and "feast" not active, or if disease active and "sanitation_drive" not active. skip_tutorial() method added. Step is persisted to GameState.world["tutorial_step"] automatically (included in serialize via world.duplicate). (2) NotificationFeed.push() now creates an HBoxContainer with a Label + small [×] Button; dismiss immediately fades out the notification. _fade_out accepts Control instead of Label. (3) GameBootstrap._show_tutorial_prompt() shows a Yes/Skip overlay panel at game start (skips to TutorialSystem.skip_tutorial() if player declines). If tutorial was already completed (step == 99), the prompt is skipped silently. (4) TechTreePanelController.get_tech_hint_text(defn) generates a plain-language summary of unlocks_buildings and modifiers, plus requires. Used as tooltip in HUDNode tech Research button.
- Files changed: `simulation/core/TutorialSystem.gd`, `view/hud/NotificationFeed.gd`, `view/main/GameBootstrap.gd`, `view/hud/TechTreePanelController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 29] 2026-06-13 — Phase 8: Save/Load & Startup Polish — Phase 8 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: (1) SaveManager.save() gains optional `extra_meta` dict parameter; stores it as "meta" in the wrapper alongside "saved_at". get_save_metadata() now returns game_day, shire_count, difficulty from meta. (2) GameBootstrap._do_save() passes meta dict with game_day (SimulationClock.game_day()), shire_count (player shire_ids.size()), difficulty (DifficultySystem.level_name). (3) GameBootstrap.get_tree().set_auto_accept_quit(false) + _notification(NOTIFICATION_WM_CLOSE_REQUEST) → _auto_save_and_quit() which saves to DEFAULT_SAVE_PATH then calls quit(). (4) WorldMapScene now has _show_loading() called from _ready() which adds a full-screen dark overlay with "Generating world map…" label; then call_deferred("_init_and_build") defers real work one frame so the loading screen renders first. Loading overlay is queue_free'd after build completes. (5) MainMenuScene version label updated to "v2.0". (6) MainMenuScene._build_ui() checks save_exists and conditionally prepends "Resume Save" button that calls _load_slot(DEFAULT_SAVE_PATH) directly. (7) _show_load_overlay() now reads SaveManager.get_save_metadata() and shows saved date, game_day, shires, difficulty as a label above the Load button.
- Files changed: `simulation/persistence/SaveManager.gd`, `view/main/GameBootstrap.gd`, `view/worldmap/WorldMapScene.gd`, `view/menu/MainMenuScene.gd`
- Supervisor correction: none

---

## [Iteration 28] 2026-06-13 — Phase 7: Macro Map Navigation & Polish — Phase 7 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: (1) MacroMapView._draw_legend() now calls _draw_faction_legend() which renders a top-right panel listing each alive AI faction's archetype display name + threat level. (2) MacroMapView._draw_player_summary() draws a dark top bar over the macro overlay showing "Your realm: Shires: N | Army: N | Gold: N". (3) MacroMapView listens to EventBus.shire_ownership_changed → appends to _shire_flashes array; _draw_shires() draws a white fade-out arc ring around the affected shire for 1.2s; _process() triggers redraws while flashes are active. (4) WorldMapScene._on_city_clicked now calls _fade_to_scene() which adds a ColorRect overlay and tweens it to opaque black over 0.35s before changing scene (smooth fade-to-black). (5) WorldMapScene._build_scene() checks for a previously selected city (GameState.world["selected_city_id"]) and conditionally adds a "↩ Return to {name}" button near the Main Menu button. (6) WorldMapView city economic level was already implemented via tier-based _draw_castle_icon() scaling — marked complete.
- Files changed: `view/macro/MacroMapView.gd`, `view/worldmap/WorldMapScene.gd`
- Supervisor correction: none

---

## [Iteration 27] 2026-06-13 — Phase 6: Diplomacy & Faction Personality — Phase 6 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: (1) GameState.gd envoy emit now includes `archetype` and `threat_level` fields. (2) DiplomacyPanel.gd rewritten: ARCH_FLAVOR const provides 3 rotating lines per archetype (bandit_king, merchant_prince, ironhand, ashen_barony); flavor is shown as italic preface to the demand text. (3) Threat level shown as a ProgressBar (green→red by threat/100) with label above the demand text. (4) Interaction history stored as _history array (max 3 entries); accept/refuse are recorded and shown with green/red color coding when the panel next opens. (5) On refuse, calls `get_parent().show_notification()` with a consequence message naming the faction. (6) Active (unfulfilled) tribute demands are read from GameState.ai_factions and displayed in the history section. (7) MacroMapView._draw_ai_banners() draws an animated pulsing red circle outline around banners with threat_level > 60; _process() triggers per-frame redraws while any hostile faction exists and map is visible.
- Files changed: `simulation/core/GameState.gd`, `view/hud/DiplomacyPanel.gd`, `view/macro/MacroMapView.gd`
- Supervisor correction: none

---

## [Iteration 26] 2026-06-13 — Phase 5.5-5.6: Market price history + popularity breakdown — Phase 5 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: (1) MarketSystem.tick_prices() now records a rolling 5-entry price history in world["market_price_history"] (dict keyed by resource) before updating prices each 10-game-day tick. (2) HUDController gains `get_market_history_tooltip(resource, world)` — reads history array and formats "oldest→newest: ▲/─/▼Xg" trend bar with triangle direction vs base price. Market buy/sell button tooltips in HUDNode._add_market_actions() now append this history line. (3) HUDController gains `get_popularity_breakdown_tooltip(player)` — reads food_ration, ale_ration, tax_rate, religion_coverage and food variety, embeds FOOD_POP / ALE_POP / TAX_POP tables locally, returns multi-line breakdown of each Δ component and daily net. `_pop_label.tooltip_text` is set from this in `_refresh_right_panel()` each tick. Phase 5 (Economy Transparency) is now fully complete.
- Files changed: `simulation/economy/MarketSystem.gd`, `view/hud/HUDController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 25] 2026-06-13 — Phase 5.1-5.2: Gold breakdown tooltip + starvation/disease banners

- Delegated to: Supervisor (direct write)
- What changed: (1) HUDController.get_gold_tooltip() computes approximate daily tax income/expense (population × |tax_rate| × 0.5) and returns a multi-line tooltip; _gold_label.tooltip_text is set on every _refresh_top_bar() call. (2) HUDNode gains `_was_starving` and `_had_disease` bool members and a `_check_crisis_alerts()` method called from `_on_tick`. When `player["is_starving"]` or `player["disease_active"]` transitions from false→true, a colored alert banner is pushed to NotificationFeed (red for starvation with cause, orange for disease); recovery is also announced in green. `show_notification()` updated to accept an optional Color parameter (passed through to NotificationFeed.push which already supported it).
- Files changed: `view/hud/HUDController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 24] 2026-06-13 — Phase 5.3-5.4: Weather icon+tooltip + tax-popularity tooltip

- Delegated to: Supervisor (direct write)
- What changed: HUDController.gd gains three new static functions: `get_weather_icon(weather)` returns a text icon char per weather type (☼~△*≈!), `get_weather_tooltip(weather)` builds a multi-line tooltip from the effects dict (popularity_delta, food_drain, speed_modifier, farm_yield), and `get_tax_tooltip(tax_rate)` returns a label+delta string from the embedded TAX_POPULARITY_DELTA table. In HUDNode._refresh_top_bar(), the weather label now shows "{icon} {name}" and has tooltip_text set. In _refresh_right_panel(), _tax_label_disp.tooltip_text is set from get_tax_tooltip() each refresh; the tax_rate local var renamed _tr to avoid collision with the new block.
- Files changed: `view/hud/HUDController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 23] 2026-06-13 — Phase 4.6: Siege route lines on macro map — Phase 4 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: MacroViewController.get_siege_tent_data() now includes `capital_x/y` (AI faction home) alongside `target_x/y`. MacroMapView._draw() now calls `_draw_army_routes()` before banners. Route lines are drawn as dashed orange lines (draw_dashed_line, 2px, 12px dash) from faction capital to siege target, with a filled arrowhead triangle at the destination and a yellow progress marker (circle lerped along the line by assembly progress ratio). Legend updated. Phase 4 (Combat Feedback Polish) is now fully complete.
- Files changed: `view/macro/MacroViewController.gd`, `view/macro/MacroMapView.gd`
- Supervisor correction: none

---

## [Iteration 22] 2026-06-13 — Phase 4.5: AI targeting prefers damaged units

- Delegated to: Supervisor (direct write)
- What changed: Added `_pick_target(pool, rng)` static helper to CombatSystem.gd. It finds the unit with the lowest HP ratio in the pool; if any are below full HP that unit is returned (focus fire), otherwise falls back to random selection. Both the attacker→defender and defender→attacker target picks in `resolve_combat` now use `_pick_target` instead of raw `rng.randi() % size`. Note: the sub-task referenced AIFaction.gd but the targeting logic lives in CombatSystem — corrected accordingly.
- Files changed: `simulation/combat/CombatSystem.gd`
- Supervisor correction: filed against wrong file in plan; actual change was in CombatSystem.gd

---

## [Iteration 21] 2026-06-13 — Phase 4.4: Combat audio cues (UNIT_HIT + UNIT_DEATH)

- Delegated to: Supervisor (direct write)
- What changed: AudioManager.gd gains `UNIT_HIT` and `UNIT_DEATH` SoundEvent enum values and a `_check_combat_sounds()` method that connects to `simulation_tick`. Each tick it scans all player and AI unit dicts, compares `hp` against `_audio_prev_hp` dict. If HP dropped and unit is alive → plays `UNIT_HIT`; if HP dropped and unit died → plays `UNIT_DEATH`. This is self-contained (no EventBus changes, no static-function modification). Note: the existing `unit_killed` signal is defined but never emitted; `UNIT_KILLED` sound was already wired to it (no-op). The new `UNIT_DEATH` path actually fires.
- Files changed: `simulation/audio/AudioManager.gd`
- Supervisor correction: noted that unit_killed signal is never emitted; added UNIT_DEATH as the live death trigger instead of relying on the dead signal

---

## [Iteration 20] 2026-06-13 — Phase 4.3: Unit death collapse animation

- Delegated to: Supervisor (direct write)
- What changed: UnitLayer.gd now tracks unit alive-state transitions via `_prev_alive` dict. When a unit transitions from alive→dead, a death animation entry is spawned (`_death_anims`: pos + born_ms, lifetime 700ms). Drawn in `_draw()` as an expanding orange ring (radius grows from UNIT_RADIUS to +22px) with a translucent fill disc — both fade out over the animation lifetime. The static X-cross remains visible after the animation completes. `_process` redraws while any death anim is active.
- Files changed: `view/micro/UnitLayer.gd`
- Supervisor correction: none

---

## [Iteration 19] 2026-06-13 — Phase 4.1-4.2: Damage popups + hit-flash tint on units

- Delegated to: Supervisor (direct write)
- What changed: UnitLayer.gd now tracks per-unit HP each tick (`_prev_hp` dict). When HP drops and unit is alive, a floating popup is spawned (`_damage_popups` array: pos, text "-N", born_ms). Popups are drawn in `_draw()` after unit rendering — age-based fade (alpha 1→0) and upward float (26px over 1.4s), amber-yellow text. Hit-flash (`_hit_flash` dict: uid→born_ms) lerps unit fill color toward white over 220ms for a brief bright flash on damage. `_process` now triggers continuous redraws when popups or flashes are active. No EventBus changes needed — HP tracking is fully self-contained.
- Files changed: `view/micro/UnitLayer.gd`
- Supervisor correction: none

---

## [Iteration 18] 2026-06-13 — Phase 3.7: Unit type badge in selection panel — Phase 3 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: `show_selected_unit()` in HUDNode.gd now populates `_sel_workers_label` with a colored category+attack-type badge — e.g. `[HEAVY INF · MELEE]` in amber, `[LIGHT INF · PIERCE]` in green, `[SIEGE · SIEGE]` in red, `[CIVILIAN · -]` in gray. Maps UnitRegistry `category` and `attack_type` fields to display strings using const dictionaries. `clear_selection()` also calls `remove_theme_color_override("font_color")` so the badge color doesn't bleed into building selections. Phase 3 (Building & Unit State Readability) is now fully complete.
- Files changed: `view/hud/HUDNode.gd`
- Supervisor correction: added `clear_selection()` color cleanup (non-obvious, needed to prevent color bleed)

---

## [Iteration 17] 2026-06-13 — Phase 3.6: Animated fire flicker on burning buildings

- Delegated to: Supervisor (direct write)
- What changed: BuildingLayer.gd fire indicator replaced with a 4-layer animated flame using `Time.get_ticks_msec()`. Layers: outer glow (orange, large, slow flicker), main flame (orange, medium, wobbling x-offset), hot core (yellow-orange, smaller, offset), bright tip (pale yellow, tiny). Added `_has_fire: bool` member flag, updated `_on_tick` to scan buildings for fire state, and expanded `_process` to call `queue_redraw()` when `_has_fire` is true — enabling per-frame smooth animation without rebuilding lists.
- Files changed: `view/micro/BuildingLayer.gd`
- Supervisor correction: none

---

## [Iteration 16] 2026-06-13 — Phase 3.5: Unit morale indicator (blue tint + ↓ symbol)

- Delegated to: Supervisor (direct write)
- What changed: UnitLayer.gd now reads `morale` and `max_morale` from the unit dict for player units. When morale_ratio < 0.35 (critically low), the unit's fill color is lerped 38% toward a blue-grey (Color(0.30, 0.35, 0.82)) to give a visually distinct "demoralized" look. A blue `↓` symbol (font size 9, alpha 0.9) is also drawn above the unit, just above where the HP bar sits, as a clear at-a-glance alert. Enemy units are unaffected.
- Files changed: `view/micro/UnitLayer.gd`
- Supervisor correction: none

---

## [Iteration 15] 2026-06-13 — Phase 3.3-3.4: Unstaffed building dim tint and alert icon

- Delegated to: Supervisor (direct write)
- What changed: BuildingLayer.gd now checks `max_workers` (from building defn) and `workers` (from building dict). When a building has worker slots but none are assigned (and is in "working" state), two effects apply: (1) base_color is darkened by 0.30 to give a dim tint, (2) an orange `!` character (font size 11) is drawn above the building label as a floating alert. This makes unstaffed buildings immediately readable on the map.
- Files changed: `view/micro/BuildingLayer.gd`
- Supervisor correction: none

---

## [Iteration 14] 2026-06-13 — Phase 3.1-3.2: HP bar color gradients for buildings and units

- Delegated to: Supervisor (direct write — 2 targeted line changes)
- What changed: BuildingLayer.gd and UnitLayer.gd HP bars now use a 3-stop color gradient: green (>50% HP) → yellow (50%) → red (<50%). Implemented using `Color.lerp()` with two branches: above 50% lerps green→yellow, below 50% lerps yellow→red. Enemy units retain their flat orange bar (gradient only applies to friendly units).
- Files changed: `view/micro/BuildingLayer.gd`, `view/micro/UnitLayer.gd`
- Supervisor correction: none

---

## [Iteration 13] 2026-06-13 — Phase 2.7: Market price trend arrows — Phase 2 COMPLETE

- Delegated to: Supervisor (direct write)
- What changed: Added `get_market_trend(resource, world)` and `get_market_prices(resource, world)` static functions to HUDController.gd. Trend compares current price vs base (±10% threshold): ↑ above normal, ↓ below normal, → at normal. In `_add_market_actions()`: each buy button now shows "{trend} {res}" (e.g. "↑ WO"), tooltips show buy/sell price and trend interpretation ("good time to sell/buy"). Phase 2 (HUD Clarity & Readability) now fully complete.
- Files changed: `view/hud/HUDController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 12] 2026-06-13 — Phase 2.6: Food variety bonus display

- Delegated to: Supervisor (direct write)
- What changed: Added `get_food_variety_bonus(player)` and `get_food_variety_types(player)` static functions to HUDController.gd — mirrors PopularityEngine variety bonus logic (apples+2, cheese+3, meat+5, bread+8, max +18). Added `_food_variety_label` to HUDNode member vars. In `_build_right_panel()`: label at y=186, font 9, width 206. In `_refresh_right_panel()`: shows "Variety +N pop: bread, meat" in light-green when bonus > 0, or "Variety: none (diversify food for bonus)" in gray when no bonus types present. Also shifted orphan "Prestige:" and "Population:" labels down 10px to avoid overlap.
- Files changed: `view/hud/HUDController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 11] 2026-06-13 — Phase 2.5: NotificationFeed smooth fade-out

- Delegated to: Supervisor (direct rewrite — 22-line file)
- What changed: Added `FADE_IN_DUR = 0.25` and `FADE_OUT_DUR = 0.4` constants. Labels now start at `modulate.a = 0.0` and tween to 1.0 on creation (fade-in). Timer now fires at `duration - FADE_OUT_DUR` instead of `duration`, triggering `_fade_out(lbl)` which tweens alpha to 0 then queue_frees. MAX_ITEMS eviction remains instant (label already visible long enough). Added `_fade_out(lbl)` helper with `is_instance_valid` guard.
- Files changed: `view/hud/NotificationFeed.gd`
- Supervisor correction: none

---

## [Iteration 10] 2026-06-13 — Phase 2.4: Gold-change flash animation

- Delegated to: Supervisor (direct write)
- What changed: Replaced anonymous `gold_changed` lambda with `_on_gold_changed(player_id, old_amount, new_amount)` handler. It calls `_refresh_top_bar()` then computes `delta = new_amount - old_amount`. Added `_spawn_gold_flash(delta)`: creates a Label with "+N" (green) or "-N" (red), positions it above the gold label (y=38), and runs a parallel Tween that floats it up 32px and fades alpha to 0 over 1.4s, then queue_frees the label.
- Files changed: `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 9] 2026-06-13 — Phase 2.3: Popularity gauge color tinting

- Delegated to: Supervisor (direct write — 3-line change)
- What changed: Added `_pop_bar_fill: StyleBoxFlat` member var. In `_build_right_panel()`: create the StyleBoxFlat with a default green color and apply it as the ProgressBar's `"fill"` stylebox override. In `_refresh_right_panel()`: set `_pop_bar_fill.bg_color = col` where `col` is already computed from `HUDController.get_popularity_color(tier)`. The bar now transitions red (revolt) → orange (poor) → yellow (fair) → lime (good) → green (excellent) as popularity changes.
- Files changed: `view/hud/HUDNode.gd`
- Supervisor correction: none

---

## [Iteration 8] 2026-06-13 — Phase 2.2: Ration/tax tick-marks and delta indicators

- Delegated to: Supervisor (direct write)
- What changed: Added `_tax_delta_label`, `_food_ration_delta`, `_ale_ration_delta` member vars. In `_build_right_panel()`: added static range tick labels (◄Bribe Free Tax►, ◄None Norm Dbl►, ◄None Half Dbl►) to the right of each set of +/- buttons. Added dynamic delta labels (↑pop green / neutral gray / ↓pop red) alongside each value label. In `_refresh_right_panel()`: added 3 blocks that update delta label text and color based on current tax_rate, food_ration, ale_ration values.
- Files changed: `view/hud/HUDNode.gd`
- Supervisor correction: none — wrote directly

---

## [Iteration 7] 2026-06-13 — Phase 2.1: Tooltips on all HUD buttons

- Delegated to: Supervisor (direct write — large file with many callsites, Omniscience truncation risk too high)
- What changed: Added optional `tooltip: String = ""` param to `_add_button()`. Applied tooltips to: tax rate +/− buttons (describe income/popularity tradeoff), food ration +/− buttons, ale ration +/− buttons, build category tabs (Civic/Harvest/Food/Military/Defense), individual build buttons (name + cost), speed buttons (Pause/1×/2×/5×), Macro/Tech/Edicts/Save bottom bar buttons, market buy/sell buttons, tech Research button, edict Activate button.
- Files changed: `view/hud/HUDNode.gd`
- Supervisor correction: none — wrote directly

---

## [Iteration 6] 2026-06-13 — Phase 1.6: Critical resource alert — red label tinting

- Delegated to: Omniscience (partial) + Supervisor correction
- What changed: Added `get_critical_resources(player)` static fn to `HUDController.gd` (gold<50, wood<50, stone<20, iron<10, food<30). In `HUDNode._refresh_top_bar()`, added `add_theme_color_override("font_color", ...)` calls — labels flash red when their resource is critical, white otherwise. Phase 1 now COMPLETE.
- Files changed: `view/hud/HUDController.gd`, `view/hud/HUDNode.gd`
- Supervisor correction: Omniscience corrupted HUDController.gd (duplicate function, extra indentation, truncated new_text). Rewrote the file cleanly; wrote HUDNode change directly.

---

## [Iteration 5] 2026-06-13 — Phase 1.5: Cursor shape changes per interaction mode

- Delegated to: Omniscience (partial) + Supervisor correction
- What changed: Added `_update_cursor()` to `PlayerInputHandler.gd` — crosshair in build mode, move-arrow with unit selected, pointing hand with building selected, default arrow otherwise. Called from `enter_build_mode`, `_cancel_build`, `_select_unit`, `_select_building`, `_deselect`.
- Files changed: `view/main/PlayerInputHandler.gd`, `omniscience-cli.py`
- Supervisor correction: Omniscience wrote `_update_cursor()` correctly but (1) corrupted `_deselect()` by dropping lines, (2) used literal `\t` strings instead of real tabs, (3) never wired `_update_cursor()` calls into the 4 other functions. Root cause: bug in `_decode_escaped_whitespace()` — early return when `\n` present prevented `\t` → tab conversion. Fixed the decode bug in omniscience-cli.py. Restored `_deselect()` and added all 5 call sites.
- Issues resolved: none
- Issues discovered: omniscience-cli.py `_decode_escaped_whitespace` bug (now patched)

---

## [Iteration 4b] 2026-06-13 — Self-improvement: Omniscience system prompt + loop protocol patched

- What changed: After 3 consecutive Omniscience failures (explored but wrote no code), patched:
  (1) omniscience-cli.py — added MANDATORY ACTING RULES (ONE-READ RULE, 3-TURN WRITE RULE, NO BROAD EXPLORATION, COMPLETE THE FEATURE); sharpened nudge message from vague "Apply the fix" to explicit "emit replace_lines NOW".
  (2) sovereign-loop-prompt.md — added STEP 2 PRE-DELEGATION PREP (supervisor reads target file and includes code snippet in task prompt); added SELF-IMPROVEMENT CHECK to STEP 4 (track Omniscience performance, patch on consecutive failures).
- Supervisor correction: entire change

---

## [Iteration 4] 2026-06-13 — Phase 1.4: Pulsing unit selection ring

- Delegated to: Omniscience (partial) + Supervisor (Claude) correction
- What changed: `UnitLayer.gd` — replaced static yellow selection ring with an animated glow that pulses alpha (0.45–0.75) and radius (±2px) using `Time.get_ticks_msec()`. Added `_process()` to drive `queue_redraw()` only while a unit is selected. Omniscience added the `_pulse_time` var but left the implementation incomplete; supervisor replaced with `Time.get_ticks_msec()` approach (no delta tracking needed) and completed the draw call.
- Files changed: `view/micro/UnitLayer.gd`
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: removed unused `_pulse_time`, implemented pulse math in draw call

---

## [Iteration 3] 2026-06-13 — Phase 1.2–1.3: Tile hover highlight with valid/invalid color coding

- Delegated to: Supervisor (Claude) — Omniscience investigated but produced no code changes; implemented by supervisor directly
- What changed: Added `set_hover_tile(gx, gy, valid)` / `clear_hover_tile()` API and `_draw_hover_highlight()` to `IsometricGrid.gd`. Hover tile draws a semi-transparent diamond tinted green (valid) or red (invalid). Wired into `PlayerInputHandler._update_ghost()` and `_cancel_build()` — same mouse-motion event that drives the ghost now also updates the tile highlight.
- Files changed: `view/micro/IsometricGrid.gd`, `view/main/PlayerInputHandler.gd`
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: full implementation (Omniscience only ran shell recon)

---

## [Iteration 2] 2026-06-13 — Phase 1.1: Animated building placement ghost preview

- Delegated to: Supervisor (Claude) — Omniscience investigated but produced no code changes; implemented by supervisor directly
- What changed: Added `_draw_ghost()` to `BuildingLayer.gd` (pulsing isometric ghost silhouette, green when valid / red when invalid); added `set_ghost()` / `clear_ghost()` API; added `_process()` for animation loop. Added `InputEventMouseMotion` handling in `PlayerInputHandler.gd` to track cursor during build mode and keep ghost in sync. Wired via `set_building_layer()` call in `GameBootstrap.gd`.
- Files changed: `view/micro/BuildingLayer.gd`, `view/main/PlayerInputHandler.gd`, `view/main/GameBootstrap.gd`
- Issues resolved: none
- Issues discovered: none
- Supervisor correction: full implementation (Omniscience only ran shell recon)

---

## 2026-06-13 — v2.0: AI-Driven Improvements (Omniscience, 10 phases)

Ten improvement phases executed by the Omniscience AI assistant (qwen3-coder:30b, local) under guardian supervision. Each phase took a git snapshot, validated every edit with the Godot parser, and ran the headless test suites before committing.

| Phase | Improvement |
|-------|-------------|
| 1 | **Audio system** — `AudioManager` autoload maps 8 EventBus signals to sound triggers (drop-in `.ogg` ready). |
| 2 | **Stacking notification feed** — upgraded the single-label notification to a 5-message timed feed; added a popularity-critical alert. |
| 3 | **Adaptive AI** — `assess_player_strength()` drives targeting (fixed a latent bug: targeting had used a non-existent `military_strength` field, always 0); all 4 factions adapt aggression/embargo/tribute to real player strength. |
| 4 | **New buildings & tech** — Watchtower (vision), Trading Post (gold income), Siege Workshop, and a `trade_networks` tech; added gold-output support to `ResourceTick`. |
| 5 | **Tutorial system** — `TutorialSystem` autoload guides new players (Woodcutter's Camp -> farm -> Granary) via the notification feed. |
| 6 | **Fog of war (enemy fog)** — `VisibilitySystem` hides enemy units/buildings until within player vision; watchtowers give early warning. Terrain stays visible. |
| 7 | **Diplomacy** — player-facing Accept/Refuse UI for AI tribute demands, built on the existing tribute backend; refusal angers the faction. |
| 8 | **Difficulty scaling** — 4 levels (Peaceful->Siege Lord) scaling AI threat, tax income, and food pressure; main-menu selector. |
| 9 | **Performance** — camera-driven terrain redraw (was every tick) and dirty-flagged building-list rebuild. |

All 625 tests across the 9 phase suites pass. See `OMNISCIENCE_LOG.md` for the per-phase record.

---

## 2026-06-13 — Phase 9: Main Menu, World Map & Visual Overhaul

### Files Created

| File | Description |
|------|-------------|
| `simulation/world/WorldMapData.gd` | Procedural world map generator: Poisson-disc cities, k-means++ faction capitals, Prim's MST roads, resource deposits. Pure simulation, headless-safe. |
| `view/worldmap/WorldMapController.gd` | Static render-list extractors for WorldMapView (city, road, territory, deposit lists). |
| `view/worldmap/WorldMapView.gd` | Full `_draw()` strategic map: parchment background, faction territory circles, curved roads, 4 resource icons, 4-tier castle icons with battlements + flags, gold player ring. |
| `view/worldmap/WorldMapScene.gd` | Scene that generates/caches WorldMapData, hosts WorldMapView, wires city-click → CityViewScene. |
| `view/worldmap/WorldMapScene.tscn` | Minimal Node scene for WorldMapScene.gd. |
| `view/menu/MainMenuScene.gd` | Title screen with procedural dark-forest `_MenuBG` and three buttons (New Game / Load / Quit). Load picker uses `save_exists()`. |
| `view/menu/MainMenuScene.tscn` | Minimal Node scene; new `run/main_scene` entry point. |
| `view/cityview/CityViewScene.gd` | Refactored GameBootstrap: reads `selected_city_id` to set seed and grid position; "World Map" return button; game-over returns to Main Menu. |
| `view/cityview/CityViewScene.tscn` | Minimal Node scene for CityViewScene.gd. |
| `view/micro/TerrainDecorationLayer.gd` | Node2D inserted between IsometricGrid and BuildingLayer. Draws forest tree cones, mountain rocky peaks + snow cap, rock clusters, river ripples, coastal waves via `_draw()` with viewport culling. |
| `tests/TestPhase9.gd` | 40 headless tests covering WorldMapData (20), WorldMapController (15), ShireMap-60 (5). All passing. |

### Files Modified

| File | Change |
|------|--------|
| `simulation/world/ShireMap.gd` | `MAX_SHIRES` 16→60; name list expanded from 8 to 62 entries; TUNDRA added to biomes array |
| `simulation/core/GameState.gd` | Added `get_city(city_id) -> Dictionary` and `get_player_start_city_id() -> int` |
| `view/micro/BuildingLayer.gd` | 3D polygon upgrade: shadow + left wall + right wall + roof diamond + ridge triangle; depth-sorted by `grid_x+grid_y`; battlements (DEFENSE/MILITARY), circular window (CIVIC), flat ridge (FOOD) |
| `project.godot` | `run/main_scene` changed from `res://view/main/Main.tscn` to `res://view/menu/MainMenuScene.tscn` |
| `view/main/GameBootstrap.gd` | Fixed `border_width_all` → `set_border_width_all()` (Godot 4 StyleBoxFlat API) |
| `view/worldmap/WorldMapScene.gd` | Same `set_border_width_all()` fix |
| `view/menu/MainMenuScene.gd` | `list_saves()` → `save_exists()` inline check (SaveManager has no list_saves); `set_border_width_all()` fix |
| `view/cityview/CityViewScene.gd` | `set_border_width_all()` fix |

### Bugs Fixed

- `StyleBoxFlat.border_width_all` does not exist in Godot 4 — replaced with `set_border_width_all()` method call across all view files
- `SaveManager.list_saves()` did not exist — replaced with inline `save_exists()` check for the single default slot
- Poisson-disc city placement had a 3-pass fallback that reduced min_dist, causing some cities to be closer than 120px — fixed by removing the fallback and increasing attempt count to `CITY_COUNT * 80`

---

## 2026-06-13 — Phase 8: Full Game Integration

### Files Created

| File | Description |
|------|-------------|
| `view/micro/CameraController.gd` | Camera2D with WASD pan, scroll zoom, middle-mouse drag, `center_on()` |
| `view/micro/IsometricGrid.gd` | Node2D diamond-tile terrain renderer; viewport culling; `grid_to_screen()` / `screen_to_grid()` static |
| `view/micro/BuildingLayer.gd` | Draws player + AI faction buildings as colored iso-diamond polygons with HP bars and fire circle |
| `view/micro/UnitLayer.gd` | Draws player (blue) and AI (red) units as circles with HP bars, selection ring, dead-X |
| `view/macro/MacroMapView.gd` | Full-screen Control overlay: shire circles, army flag banners, siege tent arcs, legend |
| `view/main/PlayerInputHandler.gd` | Translates mouse/keyboard to CommandQueue; build mode, entity selection, right-click-to-move |
| `view/hud/HUDNode.gd` | CanvasLayer with all HUD panels built in code; tech/edict/selection/build/top/right/bottom panels |
| `view/main/GameBootstrap.gd` | Assembles scene tree, initializes simulation, wires all signals, places starting buildings, shows win/loss overlay |

### Files Modified

| File | Change |
|------|--------|
| `simulation/core/GameState.gd` | Added `get_terrain_at()`, `get_grid_size()`, `grid_in_bounds()`, `prepare_starting_area()` helpers |
| `simulation/units/UnitRegistry.gd` | Added `get_units_for_building(building_type)` helper — returns all unit types requiring that building |
| `view/main/Main.tscn` | Updated to minimal Node + GameBootstrap.gd (no scene tree .tscn complexity) |

### Gameplay Features Added

- **Isometric rendering**: Terrain tiles, building footprints, unit circles all visible on 200×200 grid with viewport culling
- **Camera**: WASD pan + scroll zoom + middle-mouse drag; starts centered on player keep
- **Player input**: Left-click places buildings (in build mode) or selects entities; right-click cancels build or issues move order to selected unit
- **HUD**: Resource top bar, popularity/tax/ration right panel, category build menu with afford check, speed controls, macro/tech/edict/save buttons
- **Selection panel**: Shows HP, description, worker buttons, recruit buttons (for military buildings), buy/sell buttons (for market/guildhall)
- **Tech tree panel**: Browsable by branch, Research buttons for available techs
- **Edict panel**: Active edicts with remaining time, Available edicts with Activate buttons
- **AI faction rendering**: Enemy units (red) and buildings (dark red) rendered on micro view
- **Win/loss overlay**: Defeat if keep destroyed or popularity < 10; Victory if all AI factions defeated; Restart/Quit buttons
- **All EventBus signals wired**: Unit killed, building destroyed, weather, siege assembly, edict activate/expire all show HUD notifications
- **Trade UI**: Buy/Sell 10× resource buttons shown when market or guildhall selected
- **Right-click-to-move**: Right-click with a unit selected issues move order to clicked grid cell

### Bugs Fixed

- `HUDNode._refresh_tech_panel` / `_refresh_edict_panel`: Used `get_node_or_null("ScrollContainer")` which fails since ScrollContainer has no explicit name. Fixed by storing `_tech_content` / `_edict_content` VBoxContainer references directly.
- `HUDNode._build_all_panels`: `get_viewport().get_visible_rect().size` returns (0,0) in headless mode. Added `if vp == Vector2.ZERO: vp = Vector2(1280, 720)` fallback.
- `show_selected_building`: `_add_label()` in an HBoxContainer sets `position` which is ignored by layout. Replaced with direct `Label.new()` + `add_child()` for inline labels.

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

---

## [Loop Iteration 1] 2026-06-13 — Phase plan created (10-phase polish cycle)
- No code changes this iteration — orientation and planning pass only
- Created: `loop state.md`, `issue log.md`, `phase plan.md`
- Omniscience (qwen3-coder:30b) drafted the phase plan; Claude reviewed and corrected 4 errors before committing:
  1. Removed "add building-placement sound" sub-task (AudioManager.gd already handles BUILDING_PLACED — line 28)
  2. Removed "add siege arc visualization" sub-task (MacroMapView.gd lines 84–86 already draw it)
  3. Corrected animation sub-task file targets from *Renderer.gd (pure static) to *Layer.gd (visual nodes)
  4. Replaced Phase 6 (fog-of-war polish) with Diplomacy & Faction Personality — fog of war is already fully implemented (VisibilitySystem.gd + MacroViewController)
- Issues resolved: none
- Issues discovered: none
- Next: Phase 1 — Visual Feedback & Interaction Polish
