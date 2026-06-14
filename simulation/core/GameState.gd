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
const WildlifeSystem   = preload("res://simulation/world/WildlifeSystem.gd")
const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
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
const DiplomacySystem  = preload("res://simulation/ai/DiplomacySystem.gd")
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
var _social_rng: RandomNumberGenerator = null
var _grid: Object = null       # WorldGrid instance
var _shire_map: Object = null  # ShireMap instance
var _next_building_id: int = 1
var _next_unit_id: int = 1     # Phase 6: monotonically increasing unit id

# Wildlife (deer herds) — serializable animal dicts roaming the world.
var wildlife: Array = []
var _next_animal_id: int = 1
var _wildlife_rng: RandomNumberGenerator = null
# Transient (not serialized): a cursor position (grid coords) the deer flee from
# while the player is tracking one. Vector2.INF = no cursor threat.
var wildlife_cursor_threat: Vector2 = Vector2.INF

# Citizens (animated villager pawns; player 0 only).
var citizens: Array = []
var _next_citizen_id: int = 1
var _citizen_rng: RandomNumberGenerator = null

# Campfire — lit once the village hall is built. Villagers gather around it and
# new recruits muster there. Serializable: {"active": bool, "x": float, "y": float}.
var campfire: Dictionary = {"active": false}

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
	_social_rng = RandomNumberGenerator.new()
	_social_rng.seed = server_config["map_seed"] ^ 0xBEEF1234
	_wildlife_rng = RandomNumberGenerator.new()
	_wildlife_rng.seed = server_config["map_seed"] ^ 0x0DEE12
	wildlife = []
	_next_animal_id = 1
	_citizen_rng = RandomNumberGenerator.new()
	_citizen_rng.seed = server_config["map_seed"] ^ 0xC1721E
	citizens = []
	campfire = {"active": false}
	_next_citizen_id = 1
	weather = WeatherSystem.make_state()
	milestones = {}
	_next_building_id = 1

# Creates a procedural world grid and shire map, stores serialized data in world{}
func setup_world(seed_value: int = 12345, shire_count: int = 8) -> void:
	server_config["map_seed"] = seed_value
	_weather_rng.seed = seed_value
	_disease_rng.seed = seed_value ^ 0xDEADBEEF
	_fire_rng.seed = seed_value ^ 0xCAFEBABE
	_social_rng.seed = seed_value ^ 0xBEEF1234

	_grid = WorldGrid.new(server_config["map_width"], server_config["map_height"])
	_grid.generate(seed_value, shire_count)

	_shire_map = ShireMap.new()
	# Derive the shire layout from the world seed so capitals vary per game
	# (offset keeps it distinct from the terrain RNG stream). See audit S13.
	_shire_map.generate_default(server_config["map_width"], server_config["map_height"], shire_count, seed_value ^ 0x51932)

	world["grid"] = _grid.serialize()
	world["shires"] = _shire_map.serialize().get("shires", [])
	MarketSystem.initialize_prices(world)
	_spawn_wildlife(seed_value)

# Scatter a few deer herds across open grass/valley terrain.
func _spawn_wildlife(seed_value: int) -> void:
	_wildlife_rng.seed = seed_value ^ 0x0DEE12
	wildlife = []
	_next_animal_id = 1
	var herds: int = 5
	var w: int = server_config["map_width"]
	var h: int = server_config["map_height"]
	for herd_id in range(herds):
		# Find an open spot for the herd centre.
		var cx: float = 0.0
		var cy: float = 0.0
		for _attempt in range(20):
			var tx: int = _wildlife_rng.randi_range(15, w - 15)
			var ty: int = _wildlife_rng.randi_range(15, h - 15)
			var t: int = _grid.get_terrain(tx, ty)
			if t == WorldGrid.Terrain.GRASS or t == WorldGrid.Terrain.VALLEY:
				cx = float(tx); cy = float(ty)
				break
		if cx == 0.0:
			continue
		var count: int = _wildlife_rng.randi_range(4, 6)
		_next_animal_id = WildlifeSystem.spawn_herd(
			wildlife, herd_id, cx, cy, count, _wildlife_rng, _next_animal_id)

# Positions (grid coords) the deer treat as threats: deployed units of any side,
# plus the tracked cursor (set by the view for testing).
func _gather_wildlife_threats() -> Array:
	var threats: Array = []
	for p in players:
		if not (p is Dictionary):
			continue
		for u in p.get("units", []):
			if u is Dictionary and UnitState.is_deployable(u):
				threats.append({"x": float(u.get("pos_x", 0)), "y": float(u.get("pos_y", 0))})
	for f in ai_factions:
		if not (f is Dictionary and f.get("is_alive", false)):
			continue
		for u in f.get("units", []):
			if u is Dictionary and u.get("is_alive", false):
				threats.append({"x": float(u.get("pos_x", 0)), "y": float(u.get("pos_y", 0))})
	if wildlife_cursor_threat != Vector2.INF:
		threats.append({"x": wildlife_cursor_threat.x, "y": wildlife_cursor_threat.y})
	return threats

# --- Player initialization ---

func initialize_player(player_id: int, player_name: String, start_x: int, start_y: int) -> void:
	while players.size() <= player_id:
		players.append({})
	players[player_id] = _make_player(player_id, player_name, start_x, start_y)
	_assign_starting_shire(player_id, start_x, start_y)
	# Spawn a handful of animated villager pawns around the player's keep.
	if player_id == 0:
		if _citizen_rng == null:
			_citizen_rng = RandomNumberGenerator.new()
			_citizen_rng.seed = server_config.get("map_seed", 12345) ^ 0xC1721E
		citizens = []
		_next_citizen_id = 1
		_next_citizen_id = CitizenSystem.spawn(
			citizens, 8, float(start_x), float(start_y), _citizen_rng, _next_citizen_id)
		_snap_citizens_to_grass()

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
			shire["owner_is_player"] = true
			# Grant the free level-0→1 capital so the claimed shire provides its
			# baseline buffs immediately (the 0→1 upgrade has no resource cost).
			if shire.get("capital_level", 0) < 1:
				shire["capital_level"] = 1
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

		# Faith (GDD §3.3) — accumulates from churches/cathedrals/monks; spent on Blessings
		"faith": 0.0,
		"faith_cap": 0.0,
		"blessing_until": 0,

		# Public health (GDD §3.5.3) — sanitation-driven score; disease carries severity
		"health": 100.0,
		"disease_active": false,
		"disease_severity": 0.0,

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
	# Resolve shire biome production bonuses once per player per tick (GDD §1.2.1).
	var _biome_farm_bonus: float = 0.0
	var _biome_mine_bonus: float = 0.0
	var _biome_trade_bonus: float = 0.0
	var _pid_shire_id: int = player.get("shire_id", -1)
	if _pid_shire_id >= 0:
		for _s in world.get("shires", []):
			if _s is Dictionary and _s.get("id", -1) == _pid_shire_id:
				_biome_farm_bonus  = _s.get("farm_yield_bonus", 0.0)
				_biome_mine_bonus  = _s.get("mining_speed_bonus", 0.0)
				_biome_trade_bonus = _s.get("trade_fee_bonus", 0.0)
				break

	# Phase 2: resource production from all buildings
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		var changes: Dictionary = ResourceTick.tick_building(building, player, tick)
		if not changes.is_empty():
			# Apply iron_mining_bonus from capital level (GDD §7.5 level 3 Grand Forge)
			if building.get("type", "") == "iron_mine" and changes.has("iron"):
				var iron_bonus: float = _get_player_capital_buff(player).get("iron_mining_bonus", 0.0)
				if iron_bonus > 0.0:
					changes["iron"] = int(ceil(float(changes["iron"]) * (1.0 + iron_bonus)))
			# Apply weather farm_yield_mult to raw crop and animal farm outputs (GDD §1.1.3).
			# Drought and snow suppress production to 0; rain gives +10% bonus.
			const FARM_TYPES: Array = ["apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm"]
			var btype: String = building.get("type", "")
			if btype in FARM_TYPES:
				var farm_mult: float = weather.get("effects", {}).get("farm_yield_mult", 1.0)
				if farm_mult != 1.0:
					for res in changes.keys():
						if changes[res] > 0:
							changes[res] = int(ceil(float(changes[res]) * farm_mult))
			# Apply shire biome bonuses (ShireMap biome traits, GDD §1.2.1).
			if _biome_farm_bonus > 0.0 and btype in FARM_TYPES:
				for res in changes.keys():
					if changes[res] > 0:
						changes[res] = int(ceil(float(changes[res]) * (1.0 + _biome_farm_bonus)))
			if _biome_mine_bonus > 0.0 and btype in ["iron_mine", "stone_quarry"]:
				for res in changes.keys():
					if changes[res] > 0:
						changes[res] = int(ceil(float(changes[res]) * (1.0 + _biome_mine_bonus)))
			if _biome_trade_bonus > 0.0 and btype == "trading_post" and changes.has("gold"):
				changes["gold"] = int(ceil(float(changes["gold"]) * (1.0 + _biome_trade_bonus)))
			ResourceTick.apply_changes(player, changes)

	# Fire damage tick — applies each game-tick for burning buildings
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		if BuildingState.tick_fire(building):
			building["is_on_fire"] = false  # extinguish so ruin doesn't render as burning
			PrestigeSystem.apply_defeat_loss(player)
			EventBus.building_destroyed.emit(player.get("id", 0), building.get("id", -1), "fire")

	# Phase 4: update live coverage values every tick (needed by PopularityEngine)
	var _ale_result: Dictionary = AleSystem.tick(player, tick)
	# If ale stock ran short, scale inn_coverage by the delivery ratio so the shortage
	# reduces the ΔA popularity term proportionally (shortage > 0 only on day boundaries).
	var _ale_shortage: int = _ale_result.get("ale_shortage", 0)
	if _ale_shortage > 0:
		var _ale_consumed: int = _ale_result.get("ale_consumed", 0)
		var _ale_total: int = _ale_consumed + _ale_shortage
		if _ale_total > 0:
			player["inn_coverage"] = player.get("inn_coverage", 0.0) * float(_ale_consumed) / float(_ale_total)
	ReligionSystem.tick(player)     # updates religion_coverage

	# Everything below only fires at day boundaries
	if tick > 0 and tick % SimulationClock.TICKS_PER_GAME_DAY == 0:
		# Purge dead units so the array doesn't grow unbounded over long campaigns
		var live_units: Array = []
		for u in player.get("units", []):
			if u is Dictionary and u.get("is_alive", false):
				live_units.append(u)
			elif u is Dictionary and u.get("type", "") == "armed_peasant":
				player["military_strength"] = maxi(0, player.get("military_strength", 0) - 1)
		player["units"] = live_units

		# Weather events for popularity
		var events: Array = []
		var weather_pop_delta: float = WeatherSystem.get_popularity_delta(weather)
		if weather_pop_delta != 0:
			match weather["current"]:
				WeatherSystem.WeatherType.SNOW:    events.append("blizzard")
				WeatherSystem.WeatherType.DROUGHT: events.append("drought")
				WeatherSystem.WeatherType.STORM:   events.append("storm")
				WeatherSystem.WeatherType.RAIN:    events.append("rain")

		# Phase 4: disease events
		var disease_events: Array = DiseaseSystem.tick(player, _disease_rng, tick, weather)
		events.append_array(disease_events)

		# Siege morale penalty — if any AI faction is actively besieging this player
		var pid: int = player.get("id", -1)
		for faction in ai_factions:
			if faction is Dictionary and not faction.get("siege_assembly", {}).is_empty():
				if faction["siege_assembly"].get("target_player_id", -1) == pid:
					events.append("active_siege")
					break

		# Wedding events from churches (GDD §3.3 — "Marriage events give popularity spikes")
		# Chance scales with coverage above 30% threshold; max ~7%/day at full coverage.
		var church_coverage: float = player.get("religion_coverage", 0.0)
		if church_coverage >= 0.3 and _social_rng.randf() < (church_coverage - 0.3) * 0.1:
			events.append("wedding_event")

		# Faith accrual + Blessing (GDD §3.3). Churches, cathedrals and monks build
		# Faith; at the threshold a Blessing fires a popularity spike and grants a
		# window of divine fire protection (applied in the ignition loop below).
		var _faith_result: Dictionary = ReligionSystem.tick_faith(player, tick)
		if _faith_result.get("blessing", false):
			events.append("blessing")
			EventBus.blessing_bestowed.emit(player.get("id", 0), _faith_result.get("spent", 0.0))

		# Fire ignition from weather (DROUGHT / STORM have fire_risk > 0)
		var fire_risk: float = weather.get("effects", {}).get("fire_risk", 0.0)
		if fire_risk > 0.0:
			var _fire_edict_mods: Dictionary = EdictSystem.get_active_modifiers(player)
			fire_risk = maxf(0.0, fire_risk * (1.0 - _fire_edict_mods.get("fire_risk_reduction", 0.0)))
			# Divine fire protection from an active Blessing.
			if ReligionSystem.is_blessing_active(player, tick):
				fire_risk = maxf(0.0, fire_risk * (1.0 - ReligionSystem.BLESSING_FIRE_REDUCTION))
		if fire_risk > 0.0:
			for building in player.get("buildings", []):
				if not building is Dictionary or not building.get("is_active", true):
					continue
				if building.get("is_on_fire", false):
					continue
				# Scale ignition chance by per-building flammability (0.04 = hovel baseline).
				# Buildings with fire_risk=0.0 (stone) are immune; pitch_rig (0.12) is 3× more likely.
				var per_bld_risk: float = BuildingRegistry.lookup(building.get("type", "")).get("fire_risk", 0.0)
				if per_bld_risk == 0.0:
					continue
				if _fire_rng.randf() < fire_risk * (per_bld_risk / 0.04):
					BuildingState.ignite(building)

		# Phase 2 food consumption (ResourceTick handles production quantities)
		var food_changes: Dictionary = ResourceTick.tick_food_consumption(player, tick)
		if not food_changes.is_empty():
			ResourceTick.apply_changes(player, food_changes)

		# Extra food drain from severe weather (GDD §1.1.3 — snow/storm/drought increase demand).
		# food_drain is an additional consumption multiplier on top of base daily demand.
		var food_drain: float = weather.get("effects", {}).get("food_drain", 0.0)
		if food_drain > 0.0:
			var population: int = player.get("population", 0)
			var extra: int = maxi(0, int(float(population) * food_drain))
			if extra > 0:
				var food_dict: Dictionary = player.get("food", {})
				for food_type in ["apples", "bread", "cheese", "meat"]:  # cheapest first — GDD §3.1.2
					if extra <= 0:
						break
					var available: int = food_dict.get(food_type, 0)
					if available <= 0:
						continue
					var consumed: int = mini(available, extra)
					food_dict[food_type] = available - consumed
					extra -= consumed

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

		# S4: population growth/decline (uses the freshly-updated popularity)
		var pre_population: int = player.get("population", 0)
		_tick_population_growth(player)
		# S5: desertion — at rock-bottom popularity, soldiers and peasants flee.
		if PopularityEngine.is_desertion_risk(player):
			_apply_desertion(player)
		if player.get("population", 0) != pre_population:
			EventBus.population_changed.emit(player["id"], pre_population, player.get("population", 0))

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

# S4: village hall / keep baseline housing. Hovels add their population_cap on top.
const BASE_POPULATION_CAP: int = 50

# Maximum population the village can house: baseline (if a hall/keep exists) plus
# every active building's population_cap output (hovels grant 8 each).
func _get_population_cap(player: Dictionary) -> int:
	var cap: int = 0
	var has_hall: bool = false
	for b in player.get("buildings", []):
		if not (b is Dictionary and b.get("is_active", true) and b.get("built", true)):
			continue
		var t: String = b.get("type", "")
		if t == "village_hall" or t == "keep":
			has_hall = true
		cap += int(BuildingRegistry.lookup(t).get("produces", {}).get("population_cap", 0))
	if has_hall:
		cap += BASE_POPULATION_CAP
	return cap

# S4: population growth at day boundaries. A content (popularity >= 50), fed
# village attracts migrants up to its housing cap. Population loss is handled
# separately by disease (DiseaseSystem) and military desertion, so this only
# ever adds peasants — never removes them.
func _tick_population_growth(player: Dictionary) -> void:
	if FoodSystem.get_total_food(player) <= 0:
		return  # a hungry village attracts no newcomers
	if player.get("popularity", 50.0) < 50.0:
		return  # discontent halts immigration
	var cap: int = _get_population_cap(player)
	var pop: int = player.get("population", 0)
	if pop < cap:
		var growth: int = 2 if player.get("popularity", 50.0) >= 75.0 else 1
		player["population"] = mini(cap, pop + growth)

# S5: desertion at desertion-risk popularity (< 20). Each affected day one
# trained non-hero soldier abandons the army and a disillusioned peasant
# leaves the village. Heroes (the Captain) stay loyal.
func _apply_desertion(player: Dictionary) -> void:
	var units: Array = player.get("units", [])
	for i in range(units.size()):
		var u = units[i]
		if not (u is Dictionary and UnitState.is_deployable(u)):
			continue
		if UnitRegistry.lookup(u.get("type", "")).get("is_hero", false):
			continue
		if u.get("type", "") == "armed_peasant":
			player["military_strength"] = maxi(0, player.get("military_strength", 0) - 1)
		EventBus.unit_killed.emit(u.get("id", -1), player.get("id", 0), "desertion")
		units.remove_at(i)
		break
	if player.get("population", 0) > 0:
		player["population"] = player.get("population", 0) - 1

func _get_player_capital_buff(player: Dictionary) -> Dictionary:
	var shire_id: int = player.get("shire_id", -1)
	for shire in world.get("shires", []):
		if shire.get("id", -1) == shire_id:
			return CapitalSystem.get_capital_buffs(shire)
	return {}

func _tick_player_unit_movement(player: Dictionary, tick: int) -> void:
	const TICKS_PER_DAY: int = SimulationClock.TICKS_PER_GAME_DAY
	for unit in player.get("units", []):
		if not (unit is Dictionary and unit.get("is_alive", false)):
			continue
		match unit.get("order", ""):
			UnitState.ORDER_MOVE:
				_tick_unit_move(player, unit, tick, TICKS_PER_DAY)
			UnitState.ORDER_ATTACK:
				_tick_unit_attack(player, unit, tick, TICKS_PER_DAY)
			UnitState.ORDER_TRAINING:
				_tick_unit_training(player, unit)

# S2: advance a unit's barracks training. Required time scales down with the
# training_rate_bonus tech modifier (GDD §7.3 / training_speed tech). On
# completion the unit graduates to IDLE and becomes deployable.
func _tick_unit_training(player: Dictionary, unit: Dictionary) -> void:
	var base_ticks: int = UnitRegistry.lookup(unit.get("type", "")).get("train_ticks", 0)
	var rate_bonus: float = TechTree.get_all_modifiers(player).get("training_rate_bonus", 0.0)
	var required: int = maxi(0, int(round(float(base_ticks) / (1.0 + maxf(0.0, rate_bonus)))))
	unit["ticks_in_training"] = unit.get("ticks_in_training", 0) + 1
	if unit["ticks_in_training"] >= required:
		unit["ticks_in_training"] = 0
		unit["order"] = UnitState.ORDER_IDLE
		EventBus.unit_spawned.emit(unit)

# How many ticks elapse between single-tile steps for this unit, given speed
# modifiers (edicts, tech, weather). Lower = faster. Shared by move + attack-move.
func _unit_step_ticks(player: Dictionary, unit: Dictionary, ticks_per_day: int) -> int:
	var speed: int = UnitRegistry.lookup(unit.get("type", "")).get("speed", 3)
	var army_speed_mult: float = EdictSystem.get_active_modifiers(player).get("army_speed_multiplier", 1.0)
	var tech_speed_bonus: float = TechTree.get_all_modifiers(player).get("army_move_speed_bonus", 0.0)
	var weather_penalty: float = weather.get("effects", {}).get("movement_penalty", 1.0)
	# Mud Roads edict (rain_movement_penalty: 0.0) negates rain movement penalty
	if weather.get("current", -1) == WeatherSystem.WeatherType.RAIN:
		if EdictSystem.get_active_modifiers(player).get("rain_movement_penalty", 1.0) <= 0.0:
			weather_penalty = 1.0
	var effective_speed: float = float(maxi(1, speed)) * (1.0 + tech_speed_bonus) * maxf(0.1, army_speed_mult) * maxf(0.1, weather_penalty)
	return maxi(1, int(float(ticks_per_day) / effective_speed))

func _tick_unit_move(player: Dictionary, unit: Dictionary, tick: int, ticks_per_day: int) -> void:
	var path: Array = unit.get("move_path", [])
	if path.is_empty():
		unit["order"] = UnitState.ORDER_IDLE
		return
	if tick % _unit_step_ticks(player, unit, ticks_per_day) != 0:
		return
	unit["pos_x"] = path[0][0]
	unit["pos_y"] = path[0][1]
	path.remove_at(0)
	unit["move_path"] = path
	if path.is_empty():
		unit["order"] = UnitState.ORDER_IDLE

# S1: ORDER_ATTACK execution. The unit chases its target_id; once within weapon
# range it strikes on a fixed cadence, and the target retaliates. Resolves to
# IDLE when the target dies or can no longer be found.
func _tick_unit_attack(player: Dictionary, unit: Dictionary, tick: int, ticks_per_day: int) -> void:
	var target: Dictionary = _find_enemy_unit_by_id(player.get("id", -1), unit.get("target_id", -1))
	if target.is_empty() or not target.get("is_alive", false):
		unit["order"] = UnitState.ORDER_IDLE
		unit["target_id"] = -1
		return
	var tx: int = target.get("pos_x", unit.get("pos_x", 0))
	var ty: int = target.get("pos_y", unit.get("pos_y", 0))
	unit["target_x"] = tx
	unit["target_y"] = ty
	# Chebyshev distance (8-directional grid). Melee (range 0) engages adjacent.
	var dist: int = maxi(absi(tx - unit.get("pos_x", 0)), absi(ty - unit.get("pos_y", 0)))
	var engage_dist: int = maxi(1, unit.get("range", 0))
	if dist > engage_dist:
		# Out of range: step toward the target's live position.
		if tick % _unit_step_ticks(player, unit, ticks_per_day) != 0 or _grid == null:
			return
		var path: Array = Pathfinder.find_path(_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), tx, ty)
		if not path.is_empty():
			unit["pos_x"] = path[0][0]
			unit["pos_y"] = path[0][1]
		return
	# In range: strike on a steady cadence (~8 strikes per game-day).
	if tick % maxi(1, ticks_per_day / 8) != 0:
		return
	var result: Dictionary = CombatSystem.calculate_damage(unit, target)
	if result.get("killed", false):
		EventBus.unit_killed.emit(target.get("id", -1), player.get("id", 0), "combat")
		player["total_kills"] = player.get("total_kills", 0) + 1
		unit["order"] = UnitState.ORDER_IDLE
		unit["target_id"] = -1
		return
	# Surviving target retaliates — but only if the attacker is within ITS reach.
	# This lets ranged units (e.g. archers) safely strike melee targets from afar.
	var target_reach: int = maxi(1, target.get("range", 0))
	if target.get("attack", 0) > 0 and dist <= target_reach:
		var retal: Dictionary = CombatSystem.calculate_damage(target, unit)
		if retal.get("killed", false):
			EventBus.unit_killed.emit(unit.get("id", -1), target.get("owner_id", -1), "combat")

# Finds a living enemy unit by id across AI factions and rival players.
# Unit dicts are returned by reference so callers mutate the live state.
func _find_enemy_unit_by_id(attacker_pid: int, target_id: int) -> Dictionary:
	if target_id < 0:
		return {}
	for faction in ai_factions:
		if not (faction is Dictionary and faction.get("is_alive", false)):
			continue
		for u in faction.get("units", []):
			if u is Dictionary and u.get("id", -1) == target_id and u.get("is_alive", false):
				return u
	for p in players:
		if not (p is Dictionary) or p.get("id", -1) == attacker_pid:
			continue
		for u in p.get("units", []):
			if u is Dictionary and u.get("id", -1) == target_id and u.get("is_alive", false):
				return u
	return {}

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
		CommandQueue.CommandType.DIPLOMACY_RESPONSE:
			success = _cmd_diplomacy_response(command)
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

	# Wildlife roams every tick (smooth) and flees nearby units / the tracked cursor.
	if not wildlife.is_empty():
		_next_animal_id = WildlifeSystem.tick(
			wildlife, _gather_wildlife_threats(), _grid, _wildlife_rng, tick, _next_animal_id)

	# Villager pawns wander and build placed structures (player 0).
	if not citizens.is_empty() and not players.is_empty():
		CitizenSystem.tick(citizens, players[0].get("buildings", []), _citizen_rng, tick, _grid)
	# Once the hall is built, a campfire lights up out front; villagers gather
	# around it and new recruits muster there.
	_update_campfire()

	# Phase 6: tick AI factions each game-day
	if tick > 0 and tick % SimulationClock.TICKS_PER_GAME_DAY == 0:
		VisibilitySystem.recompute(self)
		if not players.is_empty():
			players[0]["fog_of_war"] = visibility.duplicate()
			EventBus.fog_of_war_updated.emit(0, visibility.keys())
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
							if tgt.get("shire_id", -1) == captured_id:
								tgt["shire_id"] = tgt_shires[0] if not tgt_shires.is_empty() else -1
							for shire in world.get("shires", []):
								if shire.get("id", -1) == captured_id:
									var old_owner: int = shire.get("owner_id", -1)
									shire["owner_id"] = faction.get("id", -1)
									shire["owner_is_player"] = false
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
					# Only deployable (trained) defenders take the field; units still
					# in the barracks queue do not fight. See audit item S2.
					var defender_active: Array = []
					var def_before: Array = []
					for u in defender_p.get("units", []):
						if u is Dictionary and UnitState.is_deployable(u):
							defender_active.append(u)
							def_before.append(u.get("id", -1))
					if not atk_before.is_empty() and not def_before.is_empty():
						var combat_rng := RandomNumberGenerator.new()
						combat_rng.seed = tick ^ (faction.get("id", 0) * 7919)
						CombatSystem.resolve_combat(
							faction.get("units", []), defender_active, combat_rng)
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

	# Apply wall_hp_bonus from advanced_masonry tech to defense structures.
	var _placed_defn: Dictionary = BuildingRegistry.lookup(btype)
	if _placed_defn.get("is_wall", false) or _placed_defn.get("is_tower", false):
		var _wall_bonus: float = TechTree.get_all_modifiers(player).get("wall_hp_bonus", 0.0)
		if _wall_bonus > 0.0:
			var _boosted_hp: int = int(ceil(float(building["max_hp"]) * (1.0 + _wall_bonus)))
			building["hp"] = _boosted_hp
			building["max_hp"] = _boosted_hp

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

	# Placed unbuilt — villagers must raise it. build_progress accrues per builder
	# (see CitizenSystem); the structure isn't functional until built. Bigger
	# footprints take more work.
	var _cdefn: Dictionary = BuildingRegistry.lookup(btype)
	building["built"] = false
	building["build_progress"] = 0.0
	building["build_required"] = float(maxi(1, _cdefn.get("width", 1) * _cdefn.get("height", 1))) * 100.0
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
	var old_gold: int = players[pid].get("gold", 0)
	var result: Dictionary = MarketSystem.buy(
		players[pid],
		payload.get("resource", ""),
		payload.get("amount", 0),
		world
	)
	if result.get("ok", false):
		EventBus.gold_changed.emit(pid, old_gold, players[pid].get("gold", 0))
		return true
	return false

func _cmd_sell_resource(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var old_gold: int = players[pid].get("gold", 0)
	var result: Dictionary = MarketSystem.sell(
		players[pid],
		payload.get("resource", ""),
		payload.get("amount", 0),
		world
	)
	if result.get("ok", false):
		EventBus.gold_changed.emit(pid, old_gold, players[pid].get("gold", 0))
		return true
	return false

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
	# Find the player's shire BEFORE deducting — prevents resource drain when shire_id == -1
	var shire_id: int = player.get("shire_id", -1)
	var target_shire: Dictionary = {}
	for shire in world.get("shires", []):
		if shire.get("id", -1) == shire_id:
			target_shire = shire
			break
	if target_shire.is_empty():
		return false
	var old_gold: int = player.get("gold", 0)
	# Deduct resource from player (gold is a special field, not in resources)
	if resource == "gold":
		if player.get("gold", 0) < amount:
			return false
		player["gold"] = player.get("gold", 0) - amount
	else:
		var has: int = player.get("resources", {}).get(resource, 0)
		if has < amount:
			return false
		player["resources"][resource] = has - amount
	CapitalSystem.record_donation(player, target_shire, resource, amount)
	# Auto-upgrade capital when cumulative donations meet the threshold.
	# Skip levels whose upgrade cost is empty (the free 0→1 step) so a fresh
	# donation isn't immediately consumed by a no-cost upgrade — that step is
	# granted on shire claim instead. See audit item: donation persistence.
	var _cap_level: int = target_shire.get("capital_level", 0)
	var _has_real_cost: bool = _cap_level < CapitalSystem.UPGRADE_COSTS.size() \
		and not CapitalSystem.UPGRADE_COSTS[_cap_level].is_empty()
	if _has_real_cost and CapitalSystem.can_upgrade(target_shire, world)["ok"]:
		CapitalSystem.upgrade(target_shire, world)
	if resource == "gold":
		EventBus.gold_changed.emit(pid, old_gold, player.get("gold", 0))
	return true

# S14: every player may enact edicts up to BASE_EDICT_TIER; a developed shire
# capital (edict_tier_cap buff) unlocks the higher tiers. Edict tier derives
# from its cost_points.
const BASE_EDICT_TIER: int = 2

func _edict_tier_for(cost_points: int) -> int:
	if cost_points <= 2:
		return 1
	if cost_points <= 4:
		return 2
	if cost_points <= 6:
		return 3
	return 4

func _cmd_activate_edict(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var edict_id: String = cmd["payload"].get("edict_id", "")
	# S14: enforce the capital's edict tier cap before spending points.
	var _edict_tier: int = _edict_tier_for(EdictSystem.lookup(edict_id).get("cost_points", 0))
	var _max_tier: int = BASE_EDICT_TIER + int(_get_player_capital_buff(players[pid]).get("edict_tier_cap", 0))
	if _edict_tier > _max_tier:
		return false
	var result: Dictionary = EdictSystem.activate(players[pid], edict_id, SimulationClock.current_tick)
	if result.get("ok", false):
		# Handle instant effects
		var mods: Dictionary = result.get("modifiers", {})
		if mods.has("instant_event"):
			var events: Array = [mods["instant_event"]]
			PopularityEngine.apply_tick(players[pid], events)
		if mods.has("summon_peasants"):
			var _sp_count: int = mods["summon_peasants"]
			var _sp_kx: int = players[pid].get("keep_x", 0)
			var _sp_ky: int = players[pid].get("keep_y", 0)
			var _sp_levied: int = WorkerSystem.levy_peasants(_sp_count, players[pid])
			for _sp_i in range(_sp_levied):
				var _sp_uid: int = _next_unit_id
				_next_unit_id += 1
				players[pid]["units"].append(UnitState.create("armed_peasant", pid, _sp_kx, _sp_ky, _sp_uid))
			players[pid]["popularity"] = maxf(0.0, players[pid].get("popularity", 50.0) + mods.get("popularity_delta", 0))
		elif mods.has("popularity_delta"):
			players[pid]["popularity"] = maxf(0.0, players[pid].get("popularity", 50.0) + mods["popularity_delta"])
		if mods.has("instant_gold_bonus"):
			players[pid]["gold"] = players[pid].get("gold", 0) + mods["instant_gold_bonus"]
		if mods.has("wall_repair_amount"):
			var repair_amt: int = mods["wall_repair_amount"]
			for bld in players[pid].get("buildings", []):
				if bld is Dictionary:
					var bcat: int = BuildingRegistry.lookup(bld.get("type", "")).get("category", -1)
					if bcat == BuildingRegistry.Category.DEFENSE:
						BuildingState.repair(bld, repair_amt)
		var dur: int = EdictSystem.lookup(edict_id).get("duration_ticks", 0)
		EventBus.edict_activated.emit(pid, edict_id, dur)
	return result.get("ok", false)

# S9: resolve a player's response to an AI tribute demand through the
# deterministic command pipeline (was previously mutated directly by the panel).
func _cmd_diplomacy_response(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var faction_id: int = payload.get("faction_id", -1)
	var faction = null
	for f in ai_factions:
		if f is Dictionary and f.get("id", -1) == faction_id:
			faction = f
			break
	if payload.get("accept", false):
		DiplomacySystem.accept(players[pid], payload.get("demands", {}), faction)
	else:
		DiplomacySystem.refuse(players[pid], faction)
	return true

func _cmd_research_tech(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var tech_id: String = cmd["payload"].get("tech_id", "")
	var result: Dictionary = TechTree.research(players[pid], tech_id)
	return result.get("ok", false)

# Places each starting villager on a distinct empty grass/valley tile near the keep
# (the random spawn offset can otherwise land them on water, forest or rock).
func _snap_citizens_to_grass() -> void:
	if _grid == null:
		return
	var used: Dictionary = {}
	for c in citizens:
		if not (c is Dictionary):
			continue
		var spot: Vector2i = _nearest_empty_grass(int(round(c["x"])), int(round(c["y"])), used)
		c["x"] = float(spot.x); c["y"] = float(spot.y)
		c["hx"] = float(spot.x); c["hy"] = float(spot.y)
		c["tx"] = float(spot.x); c["ty"] = float(spot.y)
		used["%d,%d" % [spot.x, spot.y]] = true

# Spiral-search outward for the nearest in-bounds, unbuilt grass/valley tile not
# already claimed by another villager.
func _nearest_empty_grass(cx: int, cy: int, used: Dictionary) -> Vector2i:
	for r in range(0, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # only the current ring
				var x: int = cx + dx
				var y: int = cy + dy
				if not _grid.in_bounds(x, y):
					continue
				var key: String = "%d,%d" % [x, y]
				if used.has(key):
					continue
				var t: int = _grid.get_terrain(x, y)
				if (t == WorldGrid.Terrain.GRASS or t == WorldGrid.Terrain.VALLEY) \
						and _grid.get_building_at(x, y) == 0:
					return Vector2i(x, y)
	return Vector2i(cx, cy)

# Lights / moves the campfire to sit just in front of the player's built hall, and
# re-homes the villagers in a ring around it the moment it first appears.
func _update_campfire() -> void:
	if players.is_empty():
		return
	var hall: Dictionary = {}
	for b in players[0].get("buildings", []):
		if b is Dictionary and b.get("type", "") in ["village_hall", "keep"] and b.get("built", true):
			hall = b
			break
	if hall.is_empty():
		if campfire.get("active", false):
			campfire = {"active": false}
		return
	var defn: Dictionary = BuildingRegistry.lookup(hall.get("type", ""))
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)
	var fx: float = float(hall.get("grid_x", 0)) + w * 0.5
	var fy: float = float(hall.get("grid_y", 0)) + h + 0.5
	if not campfire.get("active", false) \
			or absf(float(campfire.get("x", 0.0)) - fx) > 0.01 \
			or absf(float(campfire.get("y", 0.0)) - fy) > 0.01:
		campfire = {"active": true, "x": fx, "y": fy}
		_gather_citizens_at_fire(fx, fy)

# Re-home villagers around the campfire so they idle/wander in a loose ring.
func _gather_citizens_at_fire(fx: float, fy: float) -> void:
	for i in range(citizens.size()):
		var c = citizens[i]
		if not (c is Dictionary):
			continue
		var idx: int = int(c.get("id", i))
		var a: float = float(idx) * 2.39996323  # golden angle → even spread
		var r: float = 1.8 + float(idx % 3) * 0.6
		c["hx"] = fx + cos(a) * r
		c["hy"] = fy + sin(a) * r

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
	# S7: hero units (the Captain) are unique per army — reject if one already lives.
	if defn.get("is_hero", false):
		for u in player.get("units", []):
			if u is Dictionary and u.get("is_alive", false) \
					and UnitRegistry.lookup(u.get("type", "")).get("is_hero", false):
				return false
	var cost_gold: int = defn.get("cost_gold", 0)
	var recruit_reduction: float = EdictSystem.get_active_modifiers(player).get("recruitment_cost_reduction", 0.0)
	if recruit_reduction > 0.0:
		cost_gold = maxi(0, int(floor(float(cost_gold) * (1.0 - recruit_reduction))))
	if player.get("gold", 0) < cost_gold:
		return false
	if not UnitRegistry.has_equipment(unit_type, player):
		return false
	# Check raw material availability (has_equipment skips these)
	var raw_cost: Dictionary = defn.get("cost_resources", {})
	for item in raw_cost:
		var needed: int = raw_cost[item]
		if not player.get("armory", {}).has(item):
			if player.get("resources", {}).get(item, 0) < needed:
				return false
	# Deduct costs
	player["gold"] = player.get("gold", 0) - cost_gold
	for item in raw_cost:
		var needed: int = raw_cost[item]
		if player.get("armory", {}).has(item):
			player["armory"][item] = maxi(0, player["armory"].get(item, 0) - needed)
		elif player.get("resources", {}).has(item):
			player["resources"][item] = maxi(0, player["resources"].get(item, 0) - needed)
	var uid: int = _next_unit_id
	_next_unit_id += 1
	# New recruits muster around the campfire (once lit); otherwise at the keep tile.
	var sx: int = player.get("keep_x", 0)
	var sy: int = player.get("keep_y", 0)
	if pid == 0 and campfire.get("active", false):
		var a: float = float(uid) * 2.39996323
		var r: float = 1.5 + float(uid % 3) * 0.7
		sx = int(round(float(campfire.get("x", sx)) + cos(a) * r))
		sy = int(round(float(campfire.get("y", sy)) + sin(a) * r))
	var unit: Dictionary = UnitState.create(unit_type, pid, sx, sy, uid)
	# Apply unit_armor_rating from armor_forging tech: boosts defense by the rated fraction.
	var _armor_bonus: float = TechTree.get_all_modifiers(player).get("unit_armor_rating", 0.0)
	if _armor_bonus > 0.0 and unit.has("defense"):
		unit["defense"] = unit["defense"] + int(float(unit["defense"]) * _armor_bonus)
	# S2: units with a training time enter the barracks queue (ORDER_TRAINING) and
	# only become deployable once trained. Units with train_ticks==0 (e.g. peasants)
	# are available immediately.
	if defn.get("train_ticks", 0) > 0:
		unit["order"] = UnitState.ORDER_TRAINING
		unit["ticks_in_training"] = 0
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
			if not UnitState.is_deployable(unit):
				return false  # units still in the barracks queue can't take orders
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
			if not UnitState.is_deployable(unit):
				return false  # units still in the barracks queue can't take orders
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
			if units[i].get("type", "") == "armed_peasant":
				players[pid]["military_strength"] = maxi(0, players[pid].get("military_strength", 0) - 1)
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
		"wildlife": wildlife.duplicate(true),
		"next_animal_id": _next_animal_id,
		"citizens": citizens.duplicate(true),
		"next_citizen_id": _next_citizen_id,
		"campfire": campfire.duplicate(true),
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
	wildlife = data.get("wildlife", [])
	_next_animal_id = data.get("next_animal_id", 1)
	citizens = data.get("citizens", [])
	_next_citizen_id = data.get("next_citizen_id", 1)
	campfire = data.get("campfire", {"active": false})
	# Re-seed RNGs from the loaded map_seed so random events use the correct seed
	var loaded_seed: int = server_config.get("map_seed", 12345)
	_weather_rng.seed = loaded_seed
	_disease_rng.seed = loaded_seed ^ 0xDEADBEEF
	_fire_rng.seed = loaded_seed ^ 0xCAFEBABE
	_social_rng.seed = loaded_seed ^ 0xBEEF1234
	if _wildlife_rng == null:
		_wildlife_rng = RandomNumberGenerator.new()
	_wildlife_rng.seed = loaded_seed ^ 0x0DEE12
	if _citizen_rng == null:
		_citizen_rng = RandomNumberGenerator.new()
	_citizen_rng.seed = loaded_seed ^ 0xC1721E
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
