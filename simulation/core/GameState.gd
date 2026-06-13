extends Node
# Autoload singleton. The single source of truth for ALL game state.

const WeatherSystem    = preload("res://simulation/world/WeatherSystem.gd")
const PopularityEngine = preload("res://simulation/economy/PopularityEngine.gd")
const ResourceTick     = preload("res://simulation/economy/ResourceTick.gd")
const FoodSystem       = preload("res://simulation/economy/FoodSystem.gd")
const AleSystem        = preload("res://simulation/economy/AleSystem.gd")
const ReligionSystem   = preload("res://simulation/economy/ReligionSystem.gd")
const TaxSystem        = preload("res://simulation/economy/TaxSystem.gd")
const DiseaseSystem    = preload("res://simulation/economy/DiseaseSystem.gd")
const MarketSystem     = preload("res://simulation/economy/MarketSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const VisibilitySystem = preload("res://simulation/world/VisibilitySystem.gd")
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")
const PlacementValidator = preload("res://simulation/buildings/PlacementValidator.gd")
const WorkerSystem     = preload("res://simulation/player/WorkerSystem.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const ShireMap         = preload("res://simulation/world/ShireMap.gd")
# Phase 5
const TechTree         = preload("res://simulation/tech/TechTree.gd")
const PrestigeSystem   = preload("res://simulation/tech/PrestigeSystem.gd")
const CapitalSystem    = preload("res://simulation/world/CapitalSystem.gd")
const EdictSystem      = preload("res://simulation/edicts/EdictSystem.gd")
const SaveManager      = preload("res://simulation/persistence/SaveManager.gd")
# Phase 6
const UnitRegistry     = preload("res://simulation/units/UnitRegistry.gd")
const UnitState        = preload("res://simulation/units/UnitState.gd")
const AIFaction        = preload("res://simulation/ai/AIFaction.gd")
const BanditKing       = preload("res://simulation/ai/BanditKing.gd")
const MerchantPrince   = preload("res://simulation/ai/MerchantPrince.gd")
const Ironhand         = preload("res://simulation/ai/Ironhand.gd")
const AshenBarony      = preload("res://simulation/ai/AshenBarony.gd")
const CombatSystem     = preload("res://simulation/combat/CombatSystem.gd")
const MilestoneSystem  = preload("res://simulation/core/MilestoneSystem.gd")
const Pathfinder       = preload("res://simulation/pathfinding/Pathfinder.gd")
# All fields are plain Dictionary/Array/int/float/bool — JSON-serializable.
# Never stores Godot objects (Vector2, Node, etc.) to ensure network/save readiness.
# The View layer reads from here; it never writes here directly.

var world: Dictionary = {}
var players: Array = []        # Array[Dictionary]
var ai_factions: Array = []    # Array[Dictionary]
var visibility: Dictionary = {}  # Phase 6 fog of war: "x,y" -> true (player 0 vision)
var weather: Dictionary = {}
var active_edicts: Array = []  # Array[Dictionary]
var server_config: Dictionary = {}
var milestones: Dictionary = {}

# Non-serialized runtime instances (reconstructed from world dict on deserialize)
var _weather_rng: RandomNumberGenerator = null
var _disease_rng: RandomNumberGenerator = null
var _fire_rng: RandomNumberGenerator = null
var _grid: Object = null       # WorldGrid instance
var _shire_map: Object = null  # ShireMap instance
var _next_building_id: int = 1
var _next_unit_id: int = 1     # Phase 6: monotonically increasing unit id

func _ready() -> void:
	_init_default_state()

func _init_default_state() -> void:
	server_config = {
		"version": 1,
		"tick_rate": SimulationClock.TICK_RATE,
		"map_width": 200,
		"map_height": 200,
		"max_players": 8,
		"difficulty": 1,
		"map_seed": 12345,
	}
	_weather_rng = RandomNumberGenerator.new()
	_weather_rng.seed = server_config["map_seed"]
	_disease_rng = RandomNumberGenerator.new()
	_disease_rng.seed = server_config["map_seed"] ^ 0xDEADBEEF
	_fire_rng = RandomNumberGenerator.new()
	_fire_rng.seed = server_config["map_seed"] ^ 0xCAFEBABE
	weather = WeatherSystem.make_state()
	milestones = {}
	_next_building_id = 1

# Creates a procedural world grid and shire map, stores serialized data in world{}
func setup_world(seed_value: int = 12345, shire_count: int = 8) -> void:
	server_config["map_seed"] = seed_value
	_weather_rng.seed = seed_value
	_disease_rng.seed = seed_value ^ 0xDEADBEEF
	_fire_rng.seed = seed_value ^ 0xCAFEBABE

	_grid = WorldGrid.new(server_config["map_width"], server_config["map_height"])
	_grid.generate(seed_value, shire_count)

	_shire_map = ShireMap.new()
	_shire_map.generate_default(server_config["map_width"], server_config["map_height"], shire_count)

	world["grid"] = _grid.serialize()
	world["shires"] = _shire_map.serialize().get("shires", [])
	MarketSystem.initialize_prices(world)

# --- Player initialization ---

func initialize_player(player_id: int, player_name: String, start_x: int, start_y: int) -> void:
	while players.size() <= player_id:
		players.append({})
	players[player_id] = _make_player(player_id, player_name, start_x, start_y)
	_assign_starting_shire(player_id, start_x, start_y)

func _assign_starting_shire(player_id: int, start_x: int, start_y: int) -> void:
	var best_id: int   = -1
	var best_d: float  = INF
	for shire in world.get("shires", []):
		if not shire is Dictionary or shire.get("owner_id", -1) != -1:
			continue
		var dx: float = float(shire.get("capital_x", 0) - start_x)
		var dy: float = float(shire.get("capital_y", 0) - start_y)
		var d: float  = sqrt(dx * dx + dy * dy)
		if d < best_d:
			best_d = d
			best_id = shire.get("id", -1)
	if best_id < 0:
		return
	players[player_id]["shire_id"]  = best_id
	players[player_id]["shire_ids"] = [best_id]
	for shire in world.get("shires", []):
		if shire is Dictionary and shire.get("id", -1) == best_id:
			shire["owner_id"] = player_id
			break

func _make_player(player_id: int, player_name: String, start_x: int, start_y: int) -> Dictionary:
	return {
		"id": player_id,
		"name": player_name,
		"is_alive": true,

		# Economy
		"gold": 200,
		"popularity": 50,        # 0–100; peasants revolt below ~20
		"prestige": 0,
		"prestige_per_tick": 0.0,

		# Sliders (GDD §3 — Popularity Engine inputs)
		"tax_rate": 0,           # -3 (bribe) to +3 (heavy tax)
		"food_ration": 2,        # 0=none, 1=low, 2=normal, 3=extra, 4=double
		"ale_ration": 1,         # 0=none to 4=double

		# Position (stored as plain ints, not Vector2i, for JSON safety)
		"keep_x": start_x,
		"keep_y": start_y,
		"shire_id":  -1,
		"shire_ids": [],

		# Raw material stockpile
		"resources": _make_resources(),

		# Processed food stores (tracked separately for granary logic)
		"food": _make_food_stores(),

		# Military
		"population": 50,        # Current peasant count
		"military_strength": 0,  # Peasants currently in military units
		"buildings": [],         # Array of building Dictionaries
		"units": [],             # Array of unit Dictionaries (Phase 6)
		"armory": _make_armory(),

		# Progression
		"tech_unlocks": [],
		"active_edicts": [],
		"edict_points": 0,

		# Vision
		"fog_of_war": {},        # "x,y" -> true for revealed tiles

		# Metrics
		"total_kills": 0,
		"sieges_survived": 0,
	}

func _make_resources() -> Dictionary:
	return {
		"wood": 100,
		"stone": 0,
		"iron": 0,
		"pitch": 0,
		"hops": 0,
		"wheat": 0,
		"flour": 0,
		"leather": 0,
	}

func _make_food_stores() -> Dictionary:
	return {
		"apples": 50,
		"cheese": 0,
		"meat": 0,
		"bread": 0,
		"ale": 0,
	}

func _make_armory() -> Dictionary:
	return {
		"bows": 0,
		"crossbows": 0,
		"pikes": 0,
		"swords": 0,
		"leather_armor": 0,
		"plate_armor": 0,
	}

func _tick_player_economy(player: Dictionary, tick: int) -> void:
	# Phase 2: resource production from all buildings
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		var changes: Dictionary = ResourceTick.tick_building(building, player, tick)
		if not changes.is_empty():
			ResourceTick.apply_changes(player, changes)

	# Fire damage tick — applies each game-tick for burning buildings
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		if BuildingState.tick_fire(building):
			PrestigeSystem.apply_defeat_loss(player)
			EventBus.building_destroyed.emit(player.get("id", 0), building.get("id", -1), "fire")

	# Phase 4: update live coverage values every tick (needed by PopularityEngine)
	AleSystem.tick(player, tick)    # updates inn_coverage, consumes ale at day boundaries
	ReligionSystem.tick(player)     # updates religion_coverage

	# Everything below only fires at day boundaries
	if tick > 0 and tick % SimulationClock.TICKS_PER_GAME_DAY == 0:
		# Weather events for popularity
		var events: Array = []
		var weather_pop_delta: float = WeatherSystem.get_popularity_delta(weather)
		if weather_pop_delta != 0:
			match weather["current"]:
				WeatherSystem.WeatherType.SNOW:    events.append("blizzard")
				WeatherSystem.WeatherType.DROUGHT: events.append("drought")
				WeatherSystem.WeatherType.STORM:   events.append("blizzard")

		# Phase 4: disease events
		var disease_events: Array = DiseaseSystem.tick(player, _disease_rng, tick)
		events.append_array(disease_events)

		# Fire ignition from weather (DROUGHT / STORM have fire_risk > 0)
		var fire_risk: float = weather.get("effects", {}).get("fire_risk", 0.0)
		if fire_risk > 0.0:
			var _fire_edict_mods: Dictionary = EdictSystem.get_active_modifiers(player)
			fire_risk = maxf(0.0, fire_risk * (1.0 - _fire_edict_mods.get("fire_risk_reduction", 0.0)))
		if fire_risk > 0.0:
			for building in player.get("buildings", []):
				if not building is Dictionary or not building.get("is_active", true):
					continue
				if building.get("is_on_fire", false):
					continue
				if _fire_rng.randf() < fire_risk:
					BuildingState.ignite(building)

		# Phase 2 food consumption (ResourceTick handles production quantities)
		var food_changes: Dictionary = ResourceTick.tick_food_consumption(player, tick)
		if not food_changes.is_empty():
			ResourceTick.apply_changes(player, food_changes)

		# Phase 4: FoodSystem granary cap enforcement
		FoodSystem.apply_granary_cap(player)

		# Update starvation flag — PrestigeSystem halts prestige if starving
		player["is_starving"] = FoodSystem.get_total_food(player) <= 0 and player.get("population", 0) > 0

		# Phase 4: TaxSystem (replaces GameState._collect_taxes)
		var tax_result: Dictionary = TaxSystem.tick(player, world, tick)
		if not tax_result.is_empty() and tax_result["old_gold"] != tax_result["new_gold"]:
			EventBus.gold_changed.emit(player["id"], tax_result["old_gold"], tax_result["new_gold"])

		# Phase 4: market price fluctuation (server-wide, driven by player 0 tick)
		if player.get("id", -1) == 0:
			MarketSystem.tick_prices(world, _disease_rng, tick)

		# Popularity update
		var old_pop: float = player.get("popularity", 50)
		var new_pop: float = PopularityEngine.apply_tick(player, events)
		if old_pop != new_pop:
			EventBus.popularity_changed.emit(player["id"], old_pop, new_pop)

		# Phase 5: Prestige generation
		var prestige_result: Dictionary = PrestigeSystem.tick(player, world, tick)
		if not prestige_result.is_empty():
			EventBus.prestige_changed.emit(player["id"], prestige_result["old_prestige"], prestige_result["new_prestige"])

		# Edict points regeneration (GDD §7.1.2): +2/day, cap rises with prestige
		var ep_cap: int = mini(20, 10 + int(player.get("prestige", 0.0)) / 100)
		if player.get("edict_points", 0) < ep_cap:
			player["edict_points"] = mini(ep_cap, player.get("edict_points", 0) + 2)

		# Milestones (GDD §1.4.3): check once per day, emit per newly earned
		var new_milestones: Array = MilestoneSystem.check(player, world, milestones, player.get("active_edicts", []))
		for ms_id in new_milestones:
			EventBus.milestone_earned.emit(player["id"], ms_id, MilestoneSystem.PRESTIGE_BONUS)

	# Phase 5: Edict expiration (every tick, not just day boundary)
	var expired_edicts: Array = EdictSystem.tick(player, tick)
	for eid in expired_edicts:
		EventBus.edict_expired.emit(player.get("id", 0), eid)

# _collect_taxes removed — logic migrated to TaxSystem.tick() (Phase 4)

func _tick_player_unit_movement(player: Dictionary, tick: int) -> void:
	const TICKS_PER_DAY: int = SimulationClock.TICKS_PER_GAME_DAY
	for unit in player.get("units", []):
		if not (unit is Dictionary and unit.get("is_alive", false)):
			continue
		if unit.get("order", "") != UnitState.ORDER_MOVE:
			continue
		var path: Array = unit.get("move_path", [])
		if path.is_empty():
			unit["order"] = UnitState.ORDER_IDLE
			continue
		var speed: int = UnitRegistry.lookup(unit.get("type", "")).get("speed", 3)
		var step_ticks: int = maxi(1, TICKS_PER_DAY / maxi(1, speed))
		if tick % step_ticks != 0:
			continue
		unit["pos_x"] = path[0][0]
		unit["pos_y"] = path[0][1]
		path.remove_at(0)
		unit["move_path"] = path
		if path.is_empty():
			unit["order"] = UnitState.ORDER_IDLE

# --- Command dispatch ---
# apply_command is called by SimulationClock._advance_tick() for every
# command dequeued from CommandQueue. Each handler returns bool success.

func apply_command(command: Dictionary) -> void:
	var success: bool = false
	match command["type"]:
		CommandQueue.CommandType.SET_TAX_RATE:
			success = _cmd_set_tax_rate(command)
		CommandQueue.CommandType.SET_RATION_FOOD:
			success = _cmd_set_food_ration(command)
		CommandQueue.CommandType.SET_RATION_ALE:
			success = _cmd_set_ale_ration(command)
		CommandQueue.CommandType.PLACE_BUILDING:
			success = _cmd_place_building(command)
		CommandQueue.CommandType.DEMOLISH_BUILDING:
			success = _cmd_demolish_building(command)
		CommandQueue.CommandType.SET_BUILDING_WORKERS:
			success = _cmd_set_building_workers(command)
		CommandQueue.CommandType.BUY_RESOURCE:
			success = _cmd_buy_resource(command)
		CommandQueue.CommandType.SELL_RESOURCE:
			success = _cmd_sell_resource(command)
		CommandQueue.CommandType.DONATE_TO_CAPITAL:
			success = _cmd_donate_to_capital(command)
		CommandQueue.CommandType.ACTIVATE_EDICT:
			success = _cmd_activate_edict(command)
		CommandQueue.CommandType.SET_GAME_SPEED:
			success = _cmd_set_game_speed(command)
		CommandQueue.CommandType.TOGGLE_VIEW_MODE:
			success = _cmd_toggle_view_mode(command)
		CommandQueue.CommandType.ROTATE_VIEW:
			success = _cmd_rotate_view(command)
		CommandQueue.CommandType.RECRUIT_UNIT:
			success = _cmd_recruit_unit(command)
		CommandQueue.CommandType.ISSUE_MOVE_ORDER:
			success = _cmd_issue_move_order(command)
		CommandQueue.CommandType.ISSUE_ATTACK_ORDER:
			success = _cmd_issue_attack_order(command)
		CommandQueue.CommandType.DISBAND_UNIT:
			success = _cmd_disband_unit(command)
		CommandQueue.CommandType.RESEARCH_TECH:
			success = _cmd_research_tech(command)
		CommandQueue.CommandType.SAVE_GAME:
			EventBus.save_requested.emit()
			success = true
		_:
			success = true
	EventBus.command_processed.emit(command, success)

# Phase 2: economy + weather tick
func simulate_tick(tick: int) -> void:
	var weather_event: Dictionary = WeatherSystem.tick(weather, _weather_rng)
	if not weather_event.is_empty():
		EventBus.weather_changed.emit(
			WeatherSystem.weather_name(weather_event["new_weather"]),
			weather_event["duration_ticks"]
		)

	for player in players:
		if not player.get("is_alive", false):
			continue
		_tick_player_economy(player, tick)
		_tick_player_unit_movement(player, tick)

	# Phase 6: tick AI factions each game-day
	if tick > 0 and tick % SimulationClock.TICKS_PER_GAME_DAY == 0:
		VisibilitySystem.recompute(self)
		for faction in ai_factions:
			if not (faction is Dictionary and faction.get("is_alive", false)):
				continue
			var arch: String = faction.get("archetype", "")
			var ai_events: Array = []
			match arch:
				AIFaction.ARCHETYPE_BANDIT:
					ai_events = BanditKing.tick(faction, players, world, tick)
				AIFaction.ARCHETYPE_MERCHANT:
					ai_events = MerchantPrince.tick(faction, players, world, tick)
				AIFaction.ARCHETYPE_IRONHAND:
					ai_events = Ironhand.tick(faction, players, world, tick)
				AIFaction.ARCHETYPE_ASHEN_BARONY:
					ai_events = AshenBarony.tick(faction, players, world, tick)
			for ev in ai_events:
				EventBus.command_processed.emit({"type": "ai_event", "event": ev}, true)
				if ev == "siege_assembled":
					var target_pid: int = faction.get("last_siege_player_id", -1)
					if target_pid >= 0 and target_pid < players.size():
						var tgt: Dictionary = players[target_pid]
						# Shire capture: take one shire from the defender
						var tgt_shires: Array = tgt.get("shire_ids", [])
						if not tgt_shires.is_empty():
							var captured_id: int = tgt_shires[0]
							tgt_shires.remove_at(0)
							tgt["shire_ids"] = tgt_shires
							for shire in world.get("shires", []):
								if shire.get("id", -1) == captured_id:
									var old_owner: int = shire.get("owner_id", -1)
									shire["owner_id"] = faction.get("id", -1)
									EventBus.shire_ownership_changed.emit(captured_id, old_owner, faction.get("id", -1))
									break
						# Siege damage: deal 150 HP to the village hall (defeat = 3-4 sieges)
						for bld in tgt.get("buildings", []):
							if not bld is Dictionary:
								continue
							if bld.get("type", "") in ["village_hall", "keep"]:
								if BuildingState.take_damage(bld, 150):
									PrestigeSystem.apply_defeat_loss(tgt)
									EventBus.building_destroyed.emit(tgt.get("id", 0), bld.get("id", -1), "siege")
								break
				if ev in ["bandit_raid_started", "ironhand_siege_started", "ashen_siege_started", "merchant_siege_started"]:
					var asm: Dictionary = faction.get("siege_assembly", {})
					EventBus.ai_siege_assembling.emit(
						faction.get("id", -1),
						asm.get("target_player_id", -1),
						AIFaction.SIEGE_ASSEMBLY_TICKS)
				if ev == "ashen_tribute_demanded":
					var pending: Array = AIFaction.get_pending_demands(faction, 0)
					var demands_map: Dictionary = {}
					for d in pending:
						demands_map[d.get("resource", "")] = d.get("amount", 0)
					EventBus.ai_envoy_sent.emit(faction.get("id", -1), {
						"player_id": 0,
						"faction_id": faction.get("id", -1),
						"faction_name": faction.get("name", "A rival lord"),
						"archetype": faction.get("archetype", ""),
						"threat_level": faction.get("threat_level", 0.0),
						"demands": demands_map,
						"deadline_tick": pending[0].get("deadline_tick", 0) if pending.size() > 0 else 0,
					})

			# Mid-siege combat: one battle round per game-day while siege is assembling.
			# Resolves CombatSystem for the first time; emits unit_killed per casualty.
			var siege_asm: Dictionary = faction.get("siege_assembly", {})
			if not siege_asm.is_empty():
				var s_pid: int = siege_asm.get("target_player_id", -1)
				if s_pid >= 0 and s_pid < players.size():
					var defender_p: Dictionary = players[s_pid]
					var atk_before: Array = []
					for u in faction.get("units", []):
						if u is Dictionary and u.get("is_alive", false):
							atk_before.append(u.get("id", -1))
					var def_before: Array = []
					for u in defender_p.get("units", []):
						if u is Dictionary and u.get("is_alive", false):
							def_before.append(u.get("id", -1))
					if not atk_before.is_empty() and not def_before.is_empty():
						var combat_rng := RandomNumberGenerator.new()
						combat_rng.seed = tick ^ (faction.get("id", 0) * 7919)
						CombatSystem.resolve_combat(
							faction.get("units", []), defender_p.get("units", []), combat_rng)
						for u in faction.get("units", []):
							if u is Dictionary and not u.get("is_alive", false) and u.get("id", -1) in atk_before:
								EventBus.unit_killed.emit(u.get("id", -1), defender_p.get("id", 0), "combat")
						for u in defender_p.get("units", []):
							if u is Dictionary and not u.get("is_alive", false) and u.get("id", -1) in def_before:
								EventBus.unit_killed.emit(u.get("id", -1), faction.get("id", -1), "combat")

		# Defeat check: faction is_alive → false when all recruited units are dead
		for faction in ai_factions:
			if not (faction is Dictionary and faction.get("is_alive", false)):
				continue
			var units: Array = faction.get("units", [])
			if units.is_empty():
				continue  # not yet recruited — not a defeat
			var any_alive: bool = false
			for u in units:
				if u is Dictionary and u.get("is_alive", false):
					any_alive = true
					break
			if not any_alive:
				faction["is_alive"] = false
				EventBus.ai_faction_defeated.emit(faction.get("id", -1))

# --- Command handlers ---

func _cmd_set_tax_rate(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var rate: int = clampi(cmd["payload"].get("rate", 0), -3, 3)
	players[pid]["tax_rate"] = rate
	return true

func _cmd_set_food_ration(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var level: int = clampi(cmd["payload"].get("level", 2), 0, 4)
	players[pid]["food_ration"] = level
	return true

func _cmd_set_ale_ration(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var level: int = clampi(cmd["payload"].get("level", 1), 0, 4)
	players[pid]["ale_ration"] = level
	return true

func _cmd_place_building(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var btype: String = payload.get("building_type", "")
	var gx: int = payload.get("grid_x", 0)
	var gy: int = payload.get("grid_y", 0)
	var player: Dictionary = players[pid]

	# Validate placement (requires grid if available)
	if _grid != null:
		var result: Dictionary = PlacementValidator.validate(btype, gx, gy, _grid, player, world)
		if not result["ok"]:
			EventBus.building_placement_failed.emit(pid, btype, gx, gy, result.get("message", ""))
			return false

	# Create building instance
	var bid: int = _next_building_id
	_next_building_id += 1
	var building: Dictionary = BuildingState.create(btype, pid, gx, gy, bid)
	if building.is_empty():
		return false

	# Set terrain yield
	if _grid != null:
		building["terrain_yield"] = PlacementValidator.get_terrain_yield(btype, gx, gy, _grid)

	# Deduct cost
	PlacementValidator.deduct_cost(btype, player)

	# Register in grid
	if _grid != null:
		var defn: Dictionary = BuildingRegistry.lookup(btype)
		var w: int = defn.get("width", 1)
		var h: int = defn.get("height", 1)
		for dy in range(h):
			for dx in range(w):
				_grid.set_building_at(gx + dx, gy + dy, bid)

	player["buildings"].append(building)
	EventBus.building_placed.emit(pid, btype, gx, gy, bid)
	return true

func _cmd_demolish_building(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var bid: int = cmd["payload"].get("building_id", -1)
	var player: Dictionary = players[pid]
	var buildings: Array = player.get("buildings", [])

	for i in range(buildings.size()):
		var building: Dictionary = buildings[i]
		if not building is Dictionary:
			continue
		if building.get("id", -1) != bid:
			continue

		# Clear grid cells
		if _grid != null:
			var btype: String = building.get("type", "")
			var defn: Dictionary = BuildingRegistry.lookup(btype)
			var w: int = defn.get("width", 1)
			var h: int = defn.get("height", 1)
			var gx: int = building.get("grid_x", 0)
			var gy: int = building.get("grid_y", 0)
			for dy in range(h):
				for dx in range(w):
					_grid.set_building_at(gx + dx, gy + dy, 0)

		# Unassign workers back to pool
		WorkerSystem.unassign_workers(building, player)

		buildings.remove_at(i)
		EventBus.building_demolished.emit(pid, bid)
		return true

	return false  # Building not found

func _cmd_set_building_workers(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var bid: int = payload.get("building_id", -1)
	var count: int = payload.get("workers", 0)
	var player: Dictionary = players[pid]

	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		if building.get("id", -1) != bid:
			continue
		WorkerSystem.assign_workers(building, count, player)
		EventBus.building_worker_assigned.emit(bid, building.get("workers", 0))
		return true

	return false  # Building not found

func _cmd_buy_resource(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var result: Dictionary = MarketSystem.buy(
		players[pid],
		payload.get("resource", ""),
		payload.get("amount", 0),
		world
	)
	return result.get("ok", false)

func _cmd_sell_resource(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var result: Dictionary = MarketSystem.sell(
		players[pid],
		payload.get("resource", ""),
		payload.get("amount", 0),
		world
	)
	return result.get("ok", false)

func _cmd_set_game_speed(cmd: Dictionary) -> bool:
	var speed: int = cmd["payload"].get("speed", SimulationClock.SPEED_NORMAL)
	SimulationClock.set_speed(speed)
	return true

func _cmd_toggle_view_mode(cmd: Dictionary) -> bool:
	var mode: String = cmd["payload"].get("mode", "micro")
	EventBus.view_mode_changed.emit(mode)
	return true

func _cmd_rotate_view(cmd: Dictionary) -> bool:
	var rotation_index: int = cmd["payload"].get("rotation_index", 0)
	EventBus.view_rotated.emit(rotation_index)
	return true

func _cmd_donate_to_capital(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var resource: String = payload.get("resource", "")
	var amount: int = payload.get("amount", 0)
	if amount <= 0 or resource == "":
		return false
	var player: Dictionary = players[pid]
	# Deduct resource from player
	var has: int = player.get("resources", {}).get(resource, 0)
	if has < amount:
		return false
	player["resources"][resource] = has - amount
	# Find the player's shire and record donation
	var shire_id: int = player.get("shire_id", -1)
	for shire in world.get("shires", []):
		if shire.get("id", -1) == shire_id:
			CapitalSystem.record_donation(player, shire, resource, amount)
			# Auto-upgrade capital when cumulative donations meet the threshold
			if CapitalSystem.can_upgrade(shire, world)["ok"]:
				CapitalSystem.upgrade(shire, world)
			return true
	return false

func _cmd_activate_edict(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var edict_id: String = cmd["payload"].get("edict_id", "")
	var result: Dictionary = EdictSystem.activate(players[pid], edict_id, SimulationClock.current_tick)
	if result.get("ok", false):
		# Handle instant effects
		var mods: Dictionary = result.get("modifiers", {})
		if mods.has("instant_event"):
			var events: Array = [mods["instant_event"]]
			PopularityEngine.apply_tick(players[pid], events)
		if mods.has("summon_peasants"):
			players[pid]["population"] = players[pid].get("population", 0) + mods["summon_peasants"]
			players[pid]["popularity"] = maxf(0.0, players[pid].get("popularity", 50.0) + mods.get("popularity_delta", 0))
		elif mods.has("popularity_delta"):
			players[pid]["popularity"] = maxf(0.0, players[pid].get("popularity", 50.0) + mods["popularity_delta"])
		if mods.has("instant_gold_bonus"):
			players[pid]["gold"] = players[pid].get("gold", 0) + mods["instant_gold_bonus"]
		if mods.has("wall_repair_amount"):
			var repair_amt: int = mods["wall_repair_amount"]
			for bld in players[pid].get("buildings", []):
				if bld is Dictionary:
					BuildingState.repair(bld, repair_amt)
		var dur: int = EdictSystem.lookup(edict_id).get("duration_ticks", 0)
		EventBus.edict_activated.emit(pid, edict_id, dur)
	return result.get("ok", false)

func _cmd_research_tech(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var tech_id: String = cmd["payload"].get("tech_id", "")
	var result: Dictionary = TechTree.research(players[pid], tech_id)
	return result.get("ok", false)

# Phase 6: unit command handlers

func _cmd_recruit_unit(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var unit_type: String = cmd["payload"].get("unit_type", "")
	var player: Dictionary = players[pid]
	var check: Dictionary = UnitRegistry.can_recruit(unit_type, player)
	if not check["ok"]:
		return false
	var defn: Dictionary = UnitRegistry.lookup(unit_type)
	var cost_gold: int = defn.get("cost_gold", 0)
	if player.get("gold", 0) < cost_gold:
		return false
	if not UnitRegistry.has_equipment(unit_type, player):
		return false
	# Deduct costs
	player["gold"] = player.get("gold", 0) - cost_gold
	var raw_cost: Dictionary = defn.get("cost_resources", {})
	for item in raw_cost:
		if item in player.get("resources", {}):
			player["resources"][item] = maxi(0, player["resources"].get(item, 0) - raw_cost[item])
	var uid: int = _next_unit_id
	_next_unit_id += 1
	var unit: Dictionary = UnitState.create(unit_type, pid, player.get("keep_x", 0), player.get("keep_y", 0), uid)
	player["units"].append(unit)
	return true

func _cmd_issue_move_order(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var uid: int = cmd["payload"].get("unit_id", -1)
	var tx: int  = cmd["payload"].get("target_x", 0)
	var ty: int  = cmd["payload"].get("target_y", 0)
	for unit in players[pid].get("units", []):
		if unit is Dictionary and unit.get("id", -1) == uid:
			UnitState.issue_move_order(unit, tx, ty)
			if _grid != null:
				unit["move_path"] = Pathfinder.find_path(
					_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), tx, ty)
			else:
				unit["move_path"] = []
			return true
	return false

func _cmd_issue_attack_order(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var uid: int     = cmd["payload"].get("unit_id", -1)
	var tx: int      = cmd["payload"].get("target_x", 0)
	var ty: int      = cmd["payload"].get("target_y", 0)
	var target_id: int = cmd["payload"].get("target_id", -1)
	for unit in players[pid].get("units", []):
		if unit is Dictionary and unit.get("id", -1) == uid:
			UnitState.issue_attack_order(unit, tx, ty, target_id)
			return true
	return false

func _cmd_disband_unit(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var uid: int = cmd["payload"].get("unit_id", -1)
	var units: Array = players[pid].get("units", [])
	for i in range(units.size()):
		if units[i] is Dictionary and units[i].get("id", -1) == uid:
			units.remove_at(i)
			return true
	return false

# Add AI faction to the world (called during game setup)
func add_ai_faction(archetype: String, capital_x: int, capital_y: int) -> int:
	var fid: int = ai_factions.size()
	var faction: Dictionary
	match archetype:
		AIFaction.ARCHETYPE_BANDIT:
			faction = BanditKing.make(fid, capital_x, capital_y)
		AIFaction.ARCHETYPE_MERCHANT:
			faction = MerchantPrince.make(fid, capital_x, capital_y)
		AIFaction.ARCHETYPE_IRONHAND:
			faction = Ironhand.make(fid, capital_x, capital_y)
		AIFaction.ARCHETYPE_ASHEN_BARONY:
			faction = AshenBarony.make(fid, capital_x, capital_y)
		_:
			faction = AIFaction.make_faction(fid, archetype, archetype, capital_x, capital_y)
	ai_factions.append(faction)
	return fid

# --- Accessors ---

func get_city(city_id: int) -> Dictionary:
	var wm: Dictionary = world.get("world_map", {})
	for c in wm.get("cities", []):
		if c.get("id", -1) == city_id:
			return c
	return {}

func get_player_start_city_id() -> int:
	return world.get("selected_city_id", -1)

func get_player(player_id: int) -> Dictionary:
	if _valid_player(player_id):
		return players[player_id]
	return {}

func get_resource(player_id: int, resource: String) -> int:
	if not _valid_player(player_id):
		return 0
	return players[player_id]["resources"].get(resource, 0)

func get_food(player_id: int, food_type: String) -> int:
	if not _valid_player(player_id):
		return 0
	return players[player_id]["food"].get(food_type, 0)

func find_building(player_id: int, building_id: int) -> Dictionary:
	if not _valid_player(player_id):
		return {}
	for building in players[player_id].get("buildings", []):
		if building is Dictionary and building.get("id", -1) == building_id:
			return building
	return {}

func _valid_player(pid: int) -> bool:
	return pid >= 0 and pid < players.size() and not players[pid].is_empty()

# --- View-layer helpers (read-only grid accessors for the renderer) ---

func get_terrain_at(x: int, y: int) -> int:
	if _grid == null:
		return WorldGrid.Terrain.GRASS
	return _grid.get_terrain(x, y)

func get_grid_size() -> Vector2i:
	if _grid == null:
		return Vector2i(server_config.get("map_width", 200), server_config.get("map_height", 200))
	return Vector2i(_grid.width, _grid.height)

func grid_in_bounds(x: int, y: int) -> bool:
	if _grid == null:
		return false
	return _grid.in_bounds(x, y)

# Clears impassable terrain in a square radius around (cx, cy) so the starting area is buildable.
func prepare_starting_area(cx: int, cy: int, radius: int) -> void:
	if _grid == null:
		return
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if _grid.in_bounds(x, y):
				var t: int = _grid.get_terrain(x, y)
				if t == WorldGrid.Terrain.MOUNTAIN or t == WorldGrid.Terrain.RIVER \
						or t == WorldGrid.Terrain.ROCK or t == WorldGrid.Terrain.MARSH:
					_grid.set_terrain(x, y, WorldGrid.Terrain.GRASS)

# --- Serialization ---

func serialize() -> Dictionary:
	return {
		"version": 1,
		"world": world.duplicate(true),
		"players": players.duplicate(true),
		"ai_factions": ai_factions.duplicate(true),
		"weather": weather.duplicate(true),
		"active_edicts": active_edicts.duplicate(true),
		"server_config": server_config.duplicate(true),
		"milestones": milestones.duplicate(true),
		"clock": SimulationClock.serialize(),
		"next_building_id": _next_building_id,
		"next_unit_id": _next_unit_id,
	}

func deserialize(data: Dictionary) -> void:
	world = data.get("world", {})
	players = data.get("players", [])
	ai_factions = data.get("ai_factions", [])
	weather = data.get("weather", {})
	active_edicts = data.get("active_edicts", [])
	server_config = data.get("server_config", {})
	milestones = data.get("milestones", {})
	_next_building_id = data.get("next_building_id", 1)
	_next_unit_id = data.get("next_unit_id", 1)
	if data.has("clock"):
		SimulationClock.deserialize(data["clock"])

	# Reconstruct runtime grid from serialized world data
	if world.has("grid"):
		_grid = WorldGrid.new()
		_grid.deserialize(world["grid"])
		# Repopulate building_id tiles from player building state
		for player in players:
			for building in player.get("buildings", []):
				if not building is Dictionary:
					continue
				var btype: String = building.get("type", "")
				var defn: Dictionary = BuildingRegistry.lookup(btype)
				var w: int = defn.get("width", 1)
				var h: int = defn.get("height", 1)
				var gx: int = building.get("grid_x", 0)
				var gy: int = building.get("grid_y", 0)
				var bid: int = building.get("id", 0)
				for dy in range(h):
					for dx in range(w):
						_grid.set_building_at(gx + dx, gy + dy, bid)

	if world.has("shires"):
		_shire_map = ShireMap.new()
		_shire_map.shires = world["shires"]
