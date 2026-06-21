extends Node
# Autoload singleton. The single source of truth for ALL game state.

const BridgePlanner    = preload("res://simulation/world/BridgePlanner.gd")
const WeatherSystem    = preload("res://simulation/world/WeatherSystem.gd")
const PopularityEngine = preload("res://simulation/economy/PopularityEngine.gd")
const ResourceTick     = preload("res://simulation/economy/ResourceTick.gd")
const FoodSystem       = preload("res://simulation/economy/FoodSystem.gd")
const StorageSystem    = preload("res://simulation/economy/StorageSystem.gd")
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
const PeopleSystem     = preload("res://simulation/world/PeopleSystem.gd")
const NeedsSystem      = preload("res://simulation/world/NeedsSystem.gd")
const WorldEventSystem = preload("res://simulation/world/WorldEventSystem.gd")
const ObjectiveSystem  = preload("res://simulation/core/ObjectiveSystem.gd")
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
# Strategic / campaign layer — world-map kingdoms (city growth, building,
# armies, campaigns, diplomacy). See docs/STRATEGIC_AI_PLAN.md.
const StrategicSim     = preload("res://simulation/strategic/StrategicSim.gd")
const CampaignMap      = preload("res://simulation/strategic/CampaignMap.gd")
const KingdomEconomy   = preload("res://simulation/strategic/KingdomEconomy.gd")
const CampaignSystem   = preload("res://simulation/strategic/CampaignSystem.gd")
const FeudalRank       = preload("res://simulation/strategic/FeudalRank.gd")
const WorldMapData     = preload("res://simulation/world/WorldMapData.gd")
const CityGenerator    = preload("res://simulation/world/CityGenerator.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const ForestSystem     = preload("res://simulation/world/ForestSystem.gd")
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
var _forest_rng: RandomNumberGenerator = null
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

# Spectator view: when true, players[0] is a generated showcase of another faction's
# city (not the player's playable seat). Its economy is not ticked; it only grows
# as its strategic development rises. Transient — never serialized.
var spectator_mode: bool = false
var _spectator_city_id: int = -1
var _spectator_last_dev: int = -1
# While true (catch-up fast-forward on returning to your seat), simulate_tick advances ONLY
# your own economy/construction — not the strategic layer (it already advanced on the world
# map) and not enemy raiders (you weren't there to defend; war is the strategic layer's job).
var _catch_up_mode: bool = false
const CATCH_UP_MAX_DAYS: int = 120   # bound the on-return fast-forward so it can't freeze the game

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
	_forest_rng = RandomNumberGenerator.new()
	_forest_rng.seed = server_config["map_seed"] ^ 0xF0235711
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
	# Fresh local enemy roster each time the world is (re)built. CityViewScene calls
	# setup_world then add_ai_faction on every entry, so without this the raider factions
	# STACKED on each re-entry (2 → 4 → 6 …), piling on besiegers unfairly. (iter142 evidence.)
	ai_factions = []
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
	# Seed the living forest from the map's wooded tiles (all start as mature adults). init_from_grid
	# early-returns on the trees_init flag, so clear the forest state first — setup_world rebuilds the
	# GRID (new game / spectated city), so the forest must re-seed to match it instead of leaking the
	# previous grid's trees. (Targeted to forest keys only; seat-snapshot/world-map state is untouched,
	# so return-to-seat persistence is unaffected — see TestSeatPersistence.) RNG re-seeded per map.
	world.erase("trees")
	world.erase("trees_init")
	world.erase("tree_falls")
	if _forest_rng == null:
		_forest_rng = RandomNumberGenerator.new()
	_forest_rng.seed = seed_value ^ 0xF0235711
	ForestSystem.init_from_grid(world, _grid, _forest_rng)

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
		# Spawn EXACTLY the intended starting population (20 — matches AIFaction.START_WORKFORCE
		# symmetry and the "reach population 20" objective). Was 14, while population read 20, so
		# day-1 living_count sync dropped 20→14 — a phantom "6 villagers lost" on the first day.
		_next_citizen_id = CitizenSystem.spawn(
			citizens, 20, float(start_x), float(start_y), _citizen_rng, _next_citizen_id)
		_snap_citizens_to_grass()
		# Sync the headline population to the ACTUAL living villagers so it's consistent from day 0.
		players[player_id]["population"] = PeopleSystem.living_count(citizens)

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
		"gold": 400,             # doubled starting purse (the per-citizen needs system makes the
								 # opening days harsher — see _make_food_stores for the food cushion)
		"popularity": 80,        # 0–100; peasants revolt below ~20
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
		"wood": 200,             # doubled — more building stock before the economy is on its feet
		"stone": 0,
		"iron": 0,
		"pitch": 0,
		"hops": 0,
		"wheat": 0,
		"flour": 0,
		"leather": 0,
	}

func _make_food_stores() -> Dictionary:
	# Food is the real survival blocker now that each villager eats from the larder (NeedsSystem):
	# a 20-strong founding village drains the old 50 apples in ~2–3 days, before the player can
	# stand up any food production (especially mid-tutorial). Start with a fat larder — apples
	# tripled, plus a bread reserve (a second food type also grants the variety popularity bonus).
	return {
		"apples": 140,
		"cheese": 0,
		"meat": 0,
		"bread": 60,
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

# A path-site that builders have finished becomes a ROAD tile; the placeholder
# "path" building is then removed (no structure remains, just the paved terrain).
func _convert_finished_paths(player: Dictionary) -> void:
	var blds: Array = player.get("buildings", [])
	var remaining: Array = []
	var converted: bool = false
	for b in blds:
		if b is Dictionary and BuildingRegistry.is_path(b.get("type", "")) and b.get("built", false):
			var gx: int = b.get("grid_x", 0)
			var gy: int = b.get("grid_y", 0)
			if _grid != null:
				_grid.set_building_at(gx, gy, 0)
				_grid.set_terrain(gx, gy, WorldGrid.Terrain.ROAD)
			EventBus.terrain_painted.emit(gx, gy)
			converted = true
		else:
			remaining.append(b)
	if converted:
		player["buildings"] = remaining

func _tick_player_economy(player: Dictionary, tick: int) -> void:
	# Seat repair (once per game-day): a PREPARED realm (siege-ready — walls + a garrison) shores up its
	# hall/keep between strikes, so a well-defended realm out-lasts a relentless siege (see
	# KEEP_REPAIR_PER_DAY). Gated on is_siege_ready so an UNDEFENDED seat gets NO repair and still falls —
	# defending remains the thing that decides the endgame. A razed seat (hp 0) is NOT repaired.
	if tick % SimulationClock.TICKS_PER_GAME_DAY == 0 and int(player.get("population", 0)) > 0 and is_siege_ready(player):
		for _b in player.get("buildings", []):
			if _b is Dictionary and _b.get("built", false) and String(_b.get("type", "")) in ["village_hall", "keep"]:
				if int(_b.get("hp", 0)) > 0 and int(_b.get("hp", 0)) < int(_b.get("max_hp", 0)):
					BuildingState.repair(_b, KEEP_REPAIR_PER_DAY)
				break

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

	# Phase 2: resource production from all buildings. Chain buildings (gather/process
	# producers) no longer auto-produce here — their output is credited only when a
	# hauler physically delivers it (see CitizenSystem). Non-chain income (trading_post)
	# still ticks here.
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		if ResourceTick.is_chain(building.get("type", "")):
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
		var _plague_was_active: bool = player.get("disease_active", false)
		var disease_events: Array = DiseaseSystem.tick(player, _disease_rng, tick, weather)
		events.append_array(disease_events)
		# A plague that JUST broke out got no clear alert — only a passive HUD label while it
		# silently killed villagers and sank popularity. Tell the player (toast + herald VO) and
		# how to respond. One-shot on the not-active → active transition; player seat only.
		if int(player.get("id", -1)) == 0 and not _plague_was_active and player.get("disease_active", false):
			EventBus.realm_notice.emit("☠ A plague has broken out — build an Apothecary to cure it; wells and varied food keep the people hale.", "bad")
			EventBus.plague_outbreak.emit(0)
		elif int(player.get("id", -1)) == 0 and _plague_was_active and not player.get("disease_active", false):
			# Closure for the iter267 outbreak alert: tell the player the plague has lifted (the
			# "Plague! X%" HUD label just vanished otherwise) so the scare has a clear end.
			EventBus.realm_notice.emit("✦ The plague has run its course — your people recover.", "good")

		# Siege morale penalty — if any AI faction is actively besieging this player.
		# A realm that readied its defences (walls/towers + a garrison) keeps its nerve:
		# the lighter "defended" penalty rewards preparation (the iter-9 objective).
		var pid: int = player.get("id", -1)
		for faction in ai_factions:
			if faction is Dictionary and not faction.get("siege_assembly", {}).is_empty():
				if faction["siege_assembly"].get("target_player_id", -1) == pid:
					events.append("active_siege_defended" if is_siege_ready(player) else "active_siege")
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

		# Population is now driven by the living-citizen lifecycle (births/aging/death —
		# see the day-boundary people tick), not migration. Desertion still thins the army.
		if PopularityEngine.is_desertion_risk(player):
			_apply_desertion(player)

		# Phase 5: Prestige generation
		var prestige_result: Dictionary = PrestigeSystem.tick(player, world, tick)
		if not prestige_result.is_empty():
			EventBus.prestige_changed.emit(player["id"], prestige_result["old_prestige"], prestige_result["new_prestige"])

		# Edict points regeneration (GDD §7.1.2): +2/day, cap rises with prestige
		var ep_cap: int = mini(20, 10 + int(player.get("prestige", 0.0)) / 100)
		if player.get("edict_points", 0) < ep_cap:
			player["edict_points"] = mini(ep_cap, player.get("edict_points", 0) + 2)

		# Milestones (GDD §1.4.3): check once per day, emit per newly earned.
		# Suppressed during the tutorial so its gated steps aren't interrupted by milestone toasts/VO.
		if not _ai_paused():
			var ms_day: int = tick / SimulationClock.TICKS_PER_CALENDAR_DAY   # reign milestones are in calendar days
			var new_milestones: Array = MilestoneSystem.check(player, world, milestones, player.get("active_edicts", []), ms_day)
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

# How far an idle/patrolling unit will notice and engage an enemy.
const AGGRO_RADIUS: int = 9
# How far a HOLDING unit will chase an auto-acquired foe from the post it was left on
# before breaking off and returning. Keeps placed troops predictable — they defend
# their ground instead of running off across the map after every passing enemy.
const LEASH_RADIUS: int = 13

# Generic per-force unit tick. `owner` is the player or AI-faction dict that owns
# the units; `enemies` is the precomputed list of hostile unit dicts; `rally` is
# where idle units should advance to (AI raiders) or Vector2i(-1,-1) to hold.
func _tick_force_units(owner: Dictionary, units: Array, enemies: Array, tick: int, rally: Vector2i) -> void:
	const TPD: int = SimulationClock.TICKS_PER_GAME_DAY
	# PERF (opt pass): index live enemies by id ONCE per force-tick so each attacker's target
	# lookup is O(1). Was a linear _find_in scan per attacker per tick → O(units×enemies) across
	# an engaged army (a hidden O(n²) that bites at tens of thousands of units).
	var by_id: Dictionary = {}
	for e in enemies:
		if e is Dictionary:
			by_id[int(e.get("id", -1))] = e
	for unit in units:
		if not (unit is Dictionary and unit.get("is_alive", false)):
			continue
		# Auto-unstick: a unit standing on a now-blocked or built-over tile (or one
		# that's wedged and can't path) relocates to the nearest open cell instead
		# of freezing in place.
		if _tile_blocked_for_foot(unit.get("pos_x", 0), unit.get("pos_y", 0)):
			_unstick(owner, unit)
			continue
		match unit.get("order", ""):
			UnitState.ORDER_MOVE:
				_tick_unit_move(owner, unit, tick, TPD)
			UnitState.ORDER_ATTACK:
				_tick_unit_attack(owner, unit, tick, TPD, enemies, by_id)
			UnitState.ORDER_PATROL:
				_tick_unit_patrol(owner, unit, tick, TPD, enemies)
			UnitState.ORDER_TRAINING:
				_tick_unit_training(owner, unit)
			_:
				_tick_unit_idle(owner, unit, tick, TPD, enemies, rally)

# Backward-compatible shim (player units, hold position, defend if attacked).
func _tick_player_unit_movement(player: Dictionary, tick: int) -> void:
	_tick_force_units(player, player.get("units", []),
		_enemies_of_player(player.get("id", -1)), tick, Vector2i(-1, -1))

# ── Enemy resolution ─────────────────────────────────────────────────────────

# Human-readable name for an AI faction id (e.g. "The Ashen Barony") for notifications.
# Falls back to a generic title so the player is never shown a raw numeric id.
func get_faction_display_name(faction_id: int) -> String:
	for f in ai_factions:
		if f is Dictionary and int(f.get("id", -1)) == faction_id:
			var nm: String = String(f.get("name", ""))
			if nm != "":
				return nm
	return "A rival lord"

# Whether a realm has readied meaningful defences against a siege: built defensive
# structures (walls/towers/gatehouse) plus a standing garrison. Used to soften the
# siege morale penalty so a prepared ruler's people keep their nerve. Threshold 3 =
# e.g. a short wall + a tower, or a few mustered soldiers.
const SIEGE_READY_THRESHOLD: int = 3
# Damage a single siege strike deals to the seat. Both are well below the Village Hall's
# 500 HP, so ONE strike can never destroy the seat — the player always gets several
# strikes' worth of days (with cooldowns + the pre-siege warning) to break the assault.
# A prepared ruler (walls/garrison) takes a third of the damage of an undefended one.
# Tuned from a live capstone playtest (iter118): the real game spawns TWO besiegers
# (bandit_king + ashen_barony), so a defended seat takes ~8 strikes over 100 days. At 75 that
# was 600 > 500 HP — a fully siege-ready seat still fell ~day 91 (the taught "build defences"
# strategy couldn't reach the 20-min goal). At 50, two factions deal ~400 < 500, so a prepared
# ruler survives Day 100 with margin, while an undefended seat (150) still falls ~day 91.
const SIEGE_DAMAGE_DEFENDED: int = 32     # smaller attacks (was 50) — a prepared seat shrugs them off more easily
const SIEGE_DAMAGE_UNDEFENDED: int = 110  # still punishing if you never defend (was 150)
# A living realm patches its seat between assaults (builders shore up the keep). Tuned (iter120)
# so a DEFENDED seat under the live two-faction siege (≈5.3 dmg/day at 50/strike) RECOVERS and can
# hold indefinitely with good play, while an UNDEFENDED seat (≈15.8/day at 150) still falls — so
# late-game survival is about MAINTAINING defences+economy, not an inevitable death clock. A razed
# seat (hp 0) stays razed (game over preserved). Headless repro: lifts the defended ceiling past Day 150.
const KEEP_REPAIR_PER_DAY: int = 6
func is_siege_ready(player: Dictionary) -> bool:
	var points: int = 0
	for b in player.get("buildings", []):
		if not b is Dictionary or not b.get("built", false):
			continue
		if int(BuildingRegistry.lookup(b.get("type", "")).get("category", -1)) == BuildingRegistry.Category.DEFENSE:
			points += 1
	for u in player.get("units", []):
		if u is Dictionary and u.get("is_alive", false):
			points += 1
		if points >= SIEGE_READY_THRESHOLD:
			return true
	return points >= SIEGE_READY_THRESHOLD

# True when the player has buildings under construction but NObody free to build them —
# every working-age villager is locked into a job. Builders are only ever drawn from
# idle/wandering villagers (job-workers are never pulled off), so a fully-employed
# workforce leaves new works stalled. Used to warn the player (the iter-28 contention,
# now player-facing). Returns false the moment a builder exists or one could be tasked.
func has_stalled_construction(player: Dictionary) -> bool:
	var has_sites: bool = false
	for b in player.get("buildings", []):
		if b is Dictionary and CitizenSystem.is_site(b):
			has_sites = true
			break
	if not has_sites:
		return false
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if c.get("role", "") == "builder":
			return false  # someone is already building
		var st: String = String(c.get("state", ""))
		if (st == CitizenSystem.STATE_IDLE or st == CitizenSystem.STATE_WANDER) and CitizenSystem._is_working_age(c):
			return false  # an idle villager can be tasked to build
	return true

# True if the player has a built building that produces a raw (stockpile-stored) good —
# i.e. something whose output is blocked when the raw pool is full. Used to gate the
# stores-full warning so it only fires when production is actually being throttled.
func _has_raw_producer(player: Dictionary) -> bool:
	for b in player.get("buildings", []):
		if not (b is Dictionary) or not b.get("built", true) or not b.get("is_active", true):
			continue
		var outs: Dictionary = ResourceTick.PRODUCTION_OUTPUTS.get(b.get("type", ""), {})
		for g in outs:
			if StorageSystem.store_for(g) == "stockpile":
				return true
	return false

# All hostile deployable units a given player can fight (AI factions + rivals).
func _enemies_of_player(pid: int) -> Array:
	var out: Array = []
	for fac in ai_factions:
		if fac is Dictionary and fac.get("is_alive", false):
			for u in fac.get("units", []):
				if u is Dictionary and u.get("is_alive", false) and UnitState.is_deployable(u):
					out.append(u)
	for p in players:
		if p is Dictionary and p.get("id", -1) != pid:
			for u in p.get("units", []):
				if u is Dictionary and u.get("is_alive", false) and UnitState.is_deployable(u):
					out.append(u)
	return out

# All hostile deployable player units an AI faction can fight.
func _enemies_of_faction() -> Array:
	var out: Array = []
	for p in players:
		if p is Dictionary and p.get("is_alive", false):
			for u in p.get("units", []):
				if u is Dictionary and u.get("is_alive", false) and UnitState.is_deployable(u):
					out.append(u)
	return out

func _find_in(units: Array, target_id: int) -> Dictionary:
	if target_id < 0:
		return {}
	for u in units:
		if u is Dictionary and u.get("id", -1) == target_id and u.get("is_alive", false):
			return u
	return {}

# Nearest live enemy within `radius` tiles (Chebyshev via squared compare), or {}.
func _nearest_enemy(ux: int, uy: int, enemies: Array, radius: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d: int = radius * radius + 1
	for e in enemies:
		var dx: int = e.get("pos_x", 0) - ux
		var dy: int = e.get("pos_y", 0) - uy
		var d: int = dx * dx + dy * dy
		if d <= radius * radius and d < best_d:
			best_d = d
			best = e
	return best

# ── Idle / patrol behaviour ──────────────────────────────────────────────────

# Idle combat units defend themselves: they auto-acquire a nearby foe, resume a
# patrol route, or (AI raiders) march on their rally point.
func _tick_unit_idle(owner: Dictionary, unit: Dictionary, tick: int, tpd: int, enemies: Array, rally: Vector2i) -> void:
	if tick % maxi(1, tpd / 4) != 0:
		return
	# A holding unit (no rally) remembers the post it was left on and defends THAT,
	# so placed troops stay put and predictable instead of wandering the map.
	var holding: bool = rally.x < 0
	if holding and not unit.has("guard_x"):
		unit["guard_x"] = unit.get("pos_x", 0)
		unit["guard_y"] = unit.get("pos_y", 0)
	if unit.get("attack", 0) > 0:
		var tgt: Dictionary = _nearest_enemy(unit.get("pos_x", 0), unit.get("pos_y", 0), enemies, AGGRO_RADIUS)
		if not tgt.is_empty():
			UnitState.issue_attack_order(unit, tgt.get("pos_x", 0), tgt.get("pos_y", 0), tgt.get("id", -1))
			# GUARD-stance holding units are LEASHED to their post; AGGRESSIVE units (and
			# rallying raiders) pursue freely.
			unit["auto_aggro"] = holding and unit.get("stance", UnitState.STANCE_GUARD) == UnitState.STANCE_GUARD
			return
	if unit.has("patrol_a"):
		unit["order"] = UnitState.ORDER_PATROL
		return
	# Rally march (AI raiders advancing on the enemy seat). Each unit gets its own
	# spot in a ring around the rally point so the warband fans out instead of
	# stacking on a single tile.
	if rally.x >= 0 and _grid != null:
		var goal: Vector2i = _rally_goal(rally, unit)
		var dd: int = maxi(absi(goal.x - unit.get("pos_x", 0)), absi(goal.y - unit.get("pos_y", 0)))
		if dd > 1:
			var path: Array = Pathfinder.find_path(_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), goal.x, goal.y)
			if not path.is_empty():
				unit["order"] = UnitState.ORDER_MOVE
				unit["move_path"] = path
				unit["target_x"] = goal.x
				unit["target_y"] = goal.y

# A distinct staging tile in a ring around the rally point (keyed by unit id) so a
# rallying force spreads out instead of piling onto one square.
func _rally_goal(rally: Vector2i, unit: Dictionary) -> Vector2i:
	var uid: int = unit.get("id", 0)
	var a: float = float(uid) * 2.39996323
	for rad in [2, 3, 4, 5, 1]:
		var gx: int = clampi(rally.x + int(round(cos(a) * float(rad))), 0, 199)
		var gy: int = clampi(rally.y + int(round(sin(a) * float(rad))), 0, 199)
		if _grid.in_bounds(gx, gy) and _grid.is_passable(gx, gy, WorldGrid.PASSABLE_FOOT) \
				and _grid.get_building_at(gx, gy) == 0:
			return Vector2i(gx, gy)
	return rally

# Patrol between two waypoints; break off to fight any foe that wanders too close.
func _tick_unit_patrol(owner: Dictionary, unit: Dictionary, tick: int, tpd: int, enemies: Array) -> void:
	var tgt: Dictionary = _nearest_enemy(unit.get("pos_x", 0), unit.get("pos_y", 0), enemies, AGGRO_RADIUS)
	if not tgt.is_empty():
		# Keep patrol_a/b so the idle tick resumes the route after the kill.
		UnitState.issue_attack_order(unit, tgt.get("pos_x", 0), tgt.get("pos_y", 0), tgt.get("id", -1))
		return
	var to_b: bool = unit.get("patrol_to_b", true)
	var wp: Array = unit.get("patrol_b", []) if to_b else unit.get("patrol_a", [])
	if wp.size() < 2:
		unit["order"] = UnitState.ORDER_IDLE
		return
	var wx: int = wp[0]
	var wy: int = wp[1]
	if maxi(absi(wx - unit.get("pos_x", 0)), absi(wy - unit.get("pos_y", 0))) == 0:
		unit["patrol_to_b"] = not to_b
		return
	if _grid == null:
		return
	unit["target_x"] = wx
	unit["target_y"] = wy
	# PERF (opt pass): only A* on the step tick — patrol re-pathed every tick before, discarding
	# it while on the move cooldown (same waste as the attack path).
	if int(unit.get("step_cd", 0)) > 0:
		unit["step_cd"] = int(unit["step_cd"]) - 1
		return
	var path: Array = Pathfinder.find_path(_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), wx, wy)
	if not path.is_empty():
		_advance_step(owner, unit, path[0][0], path[0][1], tpd)
	else:
		# Waypoint unreachable: throttle the retry to the step cadence so a blocked patroller
		# doesn't re-run the whole-map A* every tick (same guard as the attack-move path).
		unit["step_cd"] = _unit_step_ticks(owner, unit, tpd)

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

# Terrain speed multiplier for the tile being entered: water crawls (×5), forest
# slows (×2), roads speed up (×0.5). Clamped so blocked tiles (×99) don't appear.
func _terrain_factor(x: int, y: int) -> float:
	if _grid == null:
		return 1.0
	return clampf(_grid.get_move_cost(x, y), 0.4, 8.0)

# Cooldown-based step. Honors per-unit speed AND the entered tile's terrain cost,
# so a single mover slows down in forest/water without changing the tick cadence
# elsewhere. Returns true on the tick it actually moves.
func _advance_step(owner: Dictionary, unit: Dictionary, nx: int, ny: int, tpd: int) -> bool:
	var cd: int = unit.get("step_cd", 0)
	if cd > 0:
		unit["step_cd"] = cd - 1
		return false
	unit["pos_x"] = nx
	unit["pos_y"] = ny
	var base: int = _unit_step_ticks(owner, unit, tpd)
	var eff: int = maxi(1, int(round(float(base) * _terrain_factor(nx, ny))))
	unit["step_cd"] = eff - 1
	return true

# True if foot units cannot stand on (x,y): out of bounds, impassable terrain
# (mountain/rock), or occupied by a building.
func _tile_blocked_for_foot(x: int, y: int) -> bool:
	if _grid == null:
		return false
	if not _grid.in_bounds(x, y):
		return true
	if not _grid.is_passable(x, y, WorldGrid.PASSABLE_FOOT):
		return true
	return _grid.get_building_at(x, y) != 0

# Spiral out for the nearest open, walkable, unbuilt cell; (-1,-1) if none near.
func _nearest_free_cell(x: int, y: int) -> Vector2i:
	if _grid == null:
		return Vector2i(x, y)
	for r in range(1, 24):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if not _tile_blocked_for_foot(x + dx, y + dy):
					return Vector2i(x + dx, y + dy)
	return Vector2i(-1, -1)

# Free a trapped unit by sending it to the nearest open cell. A unit standing ON a
# blocked tile is moved there immediately (otherwise the per-tick stuck check would
# loop forever); a unit that simply can't path to its goal walks there normally.
func _unstick(owner: Dictionary, unit: Dictionary) -> void:
	var here_blocked: bool = _tile_blocked_for_foot(unit.get("pos_x", 0), unit.get("pos_y", 0))
	var fc: Vector2i = _nearest_free_cell(unit.get("pos_x", 0), unit.get("pos_y", 0))
	if fc.x < 0:
		return
	unit["target_id"] = -1
	unit["step_cd"] = 0
	if here_blocked:
		# Immediate escape — can't safely path out of an impassable cell.
		unit["pos_x"] = fc.x
		unit["pos_y"] = fc.y
		unit["order"] = UnitState.ORDER_IDLE
		unit["move_path"] = []
		return
	if _grid != null:
		var path: Array = Pathfinder.find_path(_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), fc.x, fc.y)
		if not path.is_empty():
			unit["order"] = UnitState.ORDER_MOVE
			unit["move_path"] = path
			unit["target_x"] = fc.x
			unit["target_y"] = fc.y
			return
	unit["pos_x"] = fc.x
	unit["pos_y"] = fc.y
	unit["order"] = UnitState.ORDER_IDLE
	unit["move_path"] = []

func _tick_unit_move(owner: Dictionary, unit: Dictionary, tick: int, ticks_per_day: int) -> void:
	var path: Array = unit.get("move_path", [])
	if path.is_empty():
		# Reached the goal, or couldn't get anywhere. If not at the target and
		# currently wedged, unstick; otherwise settle to idle.
		if (unit.get("pos_x", 0) != unit.get("target_x", 0) or unit.get("pos_y", 0) != unit.get("target_y", 0)) \
				and _tile_blocked_for_foot(unit.get("pos_x", 0), unit.get("pos_y", 0)):
			_unstick(owner, unit)
			return
		_arrive_and_hold(unit)
		return
	if _advance_step(owner, unit, path[0][0], path[0][1], ticks_per_day):
		path.remove_at(0)
		unit["move_path"] = path
		if path.is_empty():
			_arrive_and_hold(unit)

# A unit that finishes a move settles into IDLE and adopts its arrival tile as the
# post it will defend -- so "move here" reliably means "go here and hold here".
func _arrive_and_hold(unit: Dictionary) -> void:
	unit["order"] = UnitState.ORDER_IDLE
	unit["guard_x"] = unit.get("pos_x", 0)
	unit["guard_y"] = unit.get("pos_y", 0)
	unit["auto_aggro"] = false

# Send a leashed defender back to its guard post (after a kill or an over-long chase).
func _return_to_guard(owner: Dictionary, unit: Dictionary) -> void:
	var gx: int = unit.get("guard_x", unit.get("pos_x", 0))
	var gy: int = unit.get("guard_y", unit.get("pos_y", 0))
	unit["target_id"] = -1
	if (unit.get("pos_x", 0) == gx and unit.get("pos_y", 0) == gy) or _grid == null:
		unit["order"] = UnitState.ORDER_IDLE
		return
	var gpath: Array = Pathfinder.find_path(_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), gx, gy)
	if gpath.is_empty():
		unit["order"] = UnitState.ORDER_IDLE
		return
	unit["order"] = UnitState.ORDER_MOVE
	unit["move_path"] = gpath
	unit["target_x"] = gx
	unit["target_y"] = gy

# S1: ORDER_ATTACK execution. The unit chases its target_id; once within weapon
# range it strikes on a fixed cadence, and the target retaliates. Resolves to
# IDLE when the target dies or can no longer be found.
func _tick_unit_attack(owner: Dictionary, unit: Dictionary, tick: int, ticks_per_day: int, enemies: Array, by_id: Dictionary = {}) -> void:
	# O(1) target lookup via the per-tick id index (falls back to a scan if not provided).
	var target: Dictionary = by_id.get(int(unit.get("target_id", -1)), {})
	if not (target is Dictionary and target.get("is_alive", false)):
		target = _find_in(enemies, unit.get("target_id", -1))
	# Auto-acquired (leashed) defenders return to their post when the fight ends or
	# the chase strays too far — player-issued attacks (auto_aggro=false) pursue freely.
	var auto: bool = unit.get("auto_aggro", false) and unit.has("guard_x")
	if target.is_empty():
		unit["target_id"] = -1
		unit["auto_aggro"] = false
		if auto:
			_return_to_guard(owner, unit)   # foe down — march back to the post
		else:
			unit["order"] = UnitState.ORDER_IDLE
		return
	if auto:
		var sdx: int = maxi(absi(unit.get("pos_x", 0) - unit.get("guard_x", 0)), absi(unit.get("pos_y", 0) - unit.get("guard_y", 0)))
		if sdx > LEASH_RADIUS:
			unit["auto_aggro"] = false
			_return_to_guard(owner, unit)
			return
	var tx: int = target.get("pos_x", unit.get("pos_x", 0))
	var ty: int = target.get("pos_y", unit.get("pos_y", 0))
	unit["target_x"] = tx
	unit["target_y"] = ty
	var ux: int = unit.get("pos_x", 0)
	var uy: int = unit.get("pos_y", 0)
	var dist: int = maxi(absi(tx - ux), absi(ty - uy))
	var rng: int = unit.get("range", 0)
	var engage_dist: int = maxi(1, rng)

	# Ranged kiting: if a melee foe closes to point-blank, back off one tile while
	# still loosing a shot, so archers/crossbowmen don't get pinned in melee.
	if rng >= 2 and dist <= 1 and target.get("range", 0) == 0:
		var rx: int = ux + signi(ux - tx)
		var ry: int = uy + signi(uy - ty)
		if not _tile_blocked_for_foot(rx, ry):
			if _advance_step(owner, unit, rx, ry, ticks_per_day):
				dist = maxi(absi(tx - rx), absi(ty - ry))
	elif dist > engage_dist:
		# Out of range: step toward the target's live position on the move cooldown.
		# PERF (opt pass): a unit can only move once per step-cooldown, so only run the
		# (expensive) A* on the tick it actually steps — otherwise we'd recompute a full
		# path every tick and discard it ~98% of the time (this was the #1 combat hotspot:
		# thousands of attackers each A*-ing per tick). Same cadence/behaviour, far less work.
		if _grid == null:
			return
		if int(unit.get("step_cd", 0)) > 0:
			unit["step_cd"] = int(unit["step_cd"]) - 1
			return
		var path: Array = Pathfinder.find_path(_grid, ux, uy, tx, ty)
		if not path.is_empty():
			_advance_step(owner, unit, path[0][0], path[0][1], ticks_per_day)
		else:
			# Target UNREACHABLE (e.g. walled off behind buildings): a successful step sets the
			# move cooldown, but a FAILED pathfind doesn't — so without this the unit re-runs the
			# whole-map A* EVERY tick, a real hotspot when a force is blocked from its target
			# (iter263 spectator-siege slowdown). Throttle the retry to the normal step cadence.
			unit["step_cd"] = _unit_step_ticks(owner, unit, ticks_per_day)
		return

	# In range: strike on a steady cadence (~8 strikes per game-day).
	if tick % maxi(1, ticks_per_day / 8) != 0:
		return
	# Ranged units loose a visible projectile from their tile to the target's; the
	# damage still resolves this tick (kept deterministic) — the arrow is the visual.
	if rng >= 2:
		var kind: String = "arrow"
		if unit.get("attack_type", "") == UnitRegistry.ATTACK_SIEGE:
			kind = "stone"
		elif rng >= 10:
			kind = "bolt"
		EventBus.projectile_fired.emit(ux, uy, tx, ty, kind)
	var result: Dictionary = CombatSystem.calculate_damage(unit, target)
	if result.get("killed", false):
		EventBus.unit_killed.emit(target.get("id", -1), owner.get("id", 0), "combat")
		owner["total_kills"] = owner.get("total_kills", 0) + 1
		unit["order"] = UnitState.ORDER_IDLE
		unit["target_id"] = -1
		return
	# Surviving target retaliates — but only if the attacker is within ITS reach,
	# so ranged units can safely strike melee targets from afar.
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
		CommandQueue.CommandType.DEVELOP_CITY:
			success = _cmd_develop_city(command)
		CommandQueue.CommandType.RAISE_ARMY:
			success = _cmd_raise_army(command)
		CommandQueue.CommandType.LAUNCH_CAMPAIGN:
			success = _cmd_launch_campaign(command)
		CommandQueue.CommandType.STRATEGIC_DIPLOMACY:
			success = _cmd_strategic_diplomacy(command)
		CommandQueue.CommandType.RESOLVE_EVENT_CHOICE:
			success = _cmd_resolve_event_choice(command)
		CommandQueue.CommandType.SET_UNIT_STANCE:
			success = _cmd_set_unit_stance(command)
		CommandQueue.CommandType.SAVE_GAME:
			EventBus.save_requested.emit()
			success = true
		_:
			success = true
	EventBus.command_processed.emit(command, success)

# Phase 2: economy + weather tick
func simulate_tick(tick: int) -> void:
	var weather_event: Dictionary = WeatherSystem.tick(weather, _weather_rng, SeasonSystem.season_at_tick(tick))
	if not weather_event.is_empty():
		EventBus.weather_changed.emit(
			WeatherSystem.weather_name(weather_event["new_weather"]),
			weather_event["duration_ticks"]
		)

	# Seasons advance with the calendar (240 ticks/day). Track the index and announce
	# transitions so the view can re-tint terrain and the orchard art shifts stage.
	# A dev calendar offset (set via the SR_SEASON hook) lets us preview any season.
	# Seasons key off the day/night calendar now (see SeasonSystem). A dev offset (set via
	# the SR_SEASON hook, in ticks) lets us preview any season.
	var cal_tick: int = tick + int(world.get("calendar_offset_ticks", 0))
	var season_now: int = SeasonSystem.season_at_tick(cal_tick)
	if season_now != int(world.get("season", -1)):
		world["season"] = season_now
		world["season_day"] = SeasonSystem.sky_day_of(cal_tick)
		EventBus.season_changed.emit(season_now, SeasonSystem.season_name(season_now))

	# The living forest grows once per calendar day: saplings mature, stumps regrow,
	# adults seed neighbours, and a rare new sapling sprouts somewhere fresh.
	if _grid != null and tick % SimulationClock.TICKS_PER_CALENDAR_DAY == 0:
		if _forest_rng == null:
			_forest_rng = RandomNumberGenerator.new()
			_forest_rng.seed = int(server_config.get("map_seed", 1)) ^ 0xF0235711
		ForestSystem.tick(world, _grid, _forest_rng)

	for player in players:
		if not player.get("is_alive", false):
			continue
		# EVERY town lives by the SAME simulated economy — the player's seat AND any spectated AI
		# town. Both run the full production/food/tax/popularity tick here, the identical physical
		# citizen economy (CitizenSystem, below) and the same survival needs (NeedsSystem, below).
		# A spectated rival is a FRESH founding realm (stash_seat_snapshot saved ours; then
		# initialize_player re-stocked player 0 before enter_spectator_city swapped in the rival's
		# buildings & people) — so it is a real, self-sufficient economic actor, never a showcase.
		_tick_player_economy(player, tick)
		_tick_player_unit_movement(player, tick)

	# AI-faction units act on the grid. They hold at their camp normally and only
	# MARCH on the player's seat once they've assembled a siege against them — so
	# the early game isn't swarmed by raiders that wipe freshly-recruited units.
	# (They still defend themselves via auto-aggro if the player attacks.)
	if not spectator_mode and not _catch_up_mode and not ai_factions.is_empty() and not _ai_paused():
		var keep := Vector2i(-1, -1)
		if not players.is_empty():
			keep = Vector2i(players[0].get("keep_x", 100), players[0].get("keep_y", 100))
		var player_enemies: Array = _enemies_of_faction()
		for fac in ai_factions:
			if not (fac is Dictionary and fac.get("is_alive", false)):
				continue
			var sieging: bool = not fac.get("siege_assembly", {}).is_empty() \
				and int(fac["siege_assembly"].get("target_player_id", -1)) == 0
			var rally := keep if sieging else Vector2i(-1, -1)
			_tick_force_units(fac, fac.get("units", []), player_enemies, tick, rally)
	elif spectator_mode and not ai_factions.is_empty() and not players.is_empty():
		# Spectating a besieged city: the attackers (the only AI faction here is the display
		# besieger force from _spawn_spectator_military) MARCH on the town centre and the
		# defenders auto-aggro back — so the player watches a live battle, not a tableau.
		var ctr := Vector2i(int(players[0].get("keep_x", 100)), int(players[0].get("keep_y", 100)))
		var defenders: Array = _enemies_of_faction()
		var besieger_units: Array = []
		for fac in ai_factions:
			if fac is Dictionary and fac.get("is_alive", false):
				_tick_force_units(fac, fac.get("units", []), defenders, tick, ctr)
				besieger_units.append_array(fac.get("units", []))
		# The garrison auto-aggros the attackers BACK (rally=-1 → leashed hold + auto-acquire any
		# attacker inside the aggro radius), so it SALLIES to meet the charge instead of standing as
		# passive statues that merely retaliated — the clash reads as a real two-sided engagement.
		# This is what the comment above always promised; only besieger-ticking was wired before.
		# The iter264 failing-A* guard keeps it cheap even when a foe is briefly unreachable.
		_tick_force_units(players[0], defenders, besieger_units, tick, Vector2i(-1, -1))

	# Wildlife roams every tick (smooth) and flees nearby units / the tracked cursor.
	if not wildlife.is_empty():
		_next_animal_id = WildlifeSystem.tick(
			wildlife, _gather_wildlife_threats(), _grid, _wildlife_rng, tick, _next_animal_id)

	# Villager pawns wander, build placed structures, and run the gather→process→deliver
	# economy for player 0. Felled/spent resource tiles come back so we repaint them.
	if not citizens.is_empty() and not players.is_empty():
		var farm_mult: float = weather.get("effects", {}).get("farm_yield_mult", 1.0)
		var felled: Array = CitizenSystem.tick(citizens, players[0], _citizen_rng, tick, _grid, farm_mult, true, world)
		for t in felled:
			EventBus.terrain_painted.emit(t.x, t.y)
		# A finished path-site becomes ROAD terrain and the placeholder building is removed.
		_convert_finished_paths(players[0])
	# Once the hall is built, a campfire lights up out front; villagers gather
	# around it and new recruits muster there.
	_update_campfire()

	# The villagers ARE the population: each game-day they age, pair off, bear children
	# (capped by housing rooms) and die of old age. player.population mirrors the living
	# count so food/popularity/AI keep working.
	if tick > 0 and tick % SimulationClock.TICKS_PER_GAME_DAY == 0 and not players.is_empty():
		var day: int = tick / SimulationClock.TICKS_PER_GAME_DAY
		var cal_day: int = tick / SimulationClock.TICKS_PER_CALENDAR_DAY   # sun-aligned, player-facing
		# Each villager's own needs (food/warmth) ebb a little today; the unfed and the frozen
		# sicken and, if it isn't put right, die by name. Runs BEFORE the lifecycle pass so the
		# day's dead are purged with the old-age dead in one sweep. Runs for EVERY town, the
		# player's seat and any spectated rival alike — now that the spectated town runs its full
		# economy (above), its larder is genuinely produced/consumed, so its people live or die by it.
		var needs_season: int = int(world.get("season", SeasonSystem.Season.SUMMER))
		for gone in NeedsSystem.tick_day(citizens, players[0], needs_season, _citizen_rng):
			EventBus.realm_notice.emit("%s has died of %s." % [gone["name"], gone["cause"]], "bad")
		_next_citizen_id = PeopleSystem.tick_day(citizens, players[0], _citizen_rng, day, _next_citizen_id)
		var living: int = PeopleSystem.living_count(citizens)
		if players[0].get("population", 0) != living:
			var prev: int = players[0].get("population", 0)
			players[0]["population"] = living
			EventBus.population_changed.emit(0, prev, living)
		# An AI-run town (the one being spectated) manages its own labour: it staffs its
		# buildings from its workforce and raises hovels when it needs more workers — so
		# its villagers visibly work, just like the player's.
		if spectator_mode:
			_auto_manage_ai_town()
			# …and it manages its own LAND like the player would: if a building is cut off by a
			# river it raises a bridge to reach it (BridgePlanner), or — if no crossing is possible
			# — tears the stranded building down so its workers stop milling at the bank. Throttled
			# (one crossing decision every few days) since the cut-off test is a full path-scan.
			if day % 3 == 0:
				_ai_manage_crossings(players[0])

		# The 20-minute goal: reaching Day 100 alive is the whole point of a "life". Mark
		# the achievement once — a triumphant moment + a fame reward — then let the
		# sovereign keep ruling (this is NOT a game-over; the realm endures).
		if not spectator_mode and cal_day >= 12 and not world.get("reign_celebrated", false):
			world["reign_celebrated"] = true
			players[0]["prestige"] = float(players[0].get("prestige", 0.0)) + 200.0
			EventBus.sovereign_reign_reached.emit(cal_day)

		# Standing objectives — the player's running sense of direction toward Day 100.
		# Suppressed during the tutorial (its steps ARE the objective; no competing prompts).
		if not spectator_mode and not _ai_paused():
			var obj: Dictionary = ObjectiveSystem.evaluate(players[0], world, cal_day)
			for done_o in obj.get("newly_completed", []):
				EventBus.realm_notice.emit("✓ Objective complete: " + String(done_o.get("text", "")), "good")
			if not obj.get("newly_completed", []).is_empty() or day == 1:
				EventBus.objective_updated.emit(int(obj["index"]), int(obj["total"]), String(obj["text"]))

		# Telegraph the end of the establishment grace (King's Peace) so the player has
		# fair warning to raise defences before rival lords are free to march on them.
		if not spectator_mode and not _ai_paused() and day == AIFaction.PLAYER_GRACE_DAYS:
			EventBus.realm_notice.emit(
				"⚔ The King's Peace has ended — rival lords may now march on your realm. Raise walls and a garrison while you can.",
				"bad")

		# Restless-people warning: popularity erodes in the late game (war, a growing
		# town outpacing its churches/inns). Tell the player HOW to lift spirits once,
		# when it crosses below the threshold, and re-arm only after it recovers — so a
		# slow drift toward revolt is never silent.
		if not spectator_mode and not _ai_paused():
			var pop_now: float = float(players[0].get("popularity", 50.0))
			if pop_now < 35.0 and not world.get("restless_warned", false):
				world["restless_warned"] = true
				EventBus.realm_notice.emit(
					"⚠ Your people grow restless — proclaim a Village Feast (Edicts), lower taxes, or raise a Church or Inn to lift their spirits.",
					"bad")
			elif pop_now >= 45.0 and world.get("restless_warned", false):
				world["restless_warned"] = false

			# Construction-stall hint: works are pending but every villager is locked into
			# a job, so there's nobody left to build (the iter-28 contention, player-facing
			# — the player controls labour manually). Warn once; re-arm when it clears.
			var stalled: bool = has_stalled_construction(players[0])
			if stalled and not world.get("builders_warned", false):
				world["builders_warned"] = true
				EventBus.realm_notice.emit(
					"⚠ No free hands to build — every villager is working a job, so your works are stalled. Free up labour: lower a building's workers, or raise a Hovel for more people.",
					"bad")
			elif not stalled and world.get("builders_warned", false):
				world["builders_warned"] = false

			# Low-food warning: a drought or off-season can drain the granary toward
			# starvation. Warn once while there's still a buffer to act on (rations/farms),
			# re-arm only after it recovers — so a famine is never silent until it's too late
			# (is_starving only flips at food 0). Threshold scales with population + ration.
			var ration: int = int(players[0].get("food_ration", 2))
			var rmult: float = float(ResourceTick.RATION_CONSUMPTION_MULTIPLIERS.get(ration, 1.0))
			var daily_need: float = maxf(1.0, float(players[0].get("population", 0)) * ResourceTick.FOOD_CONSUMPTION_PER_PEASANT_PER_DAY * rmult)
			var total_food: int = FoodSystem.get_total_food(players[0])
			if total_food > 0 and float(total_food) < daily_need * 3.0 and not world.get("food_low_warned", false):
				world["food_low_warned"] = true
				EventBus.realm_notice.emit(
					"⚠ Your stores run low — lower your food Ration, proclaim Frugal Tables (Edicts), or raise more Orchards/Farms until the harvest recovers.",
					"bad")
			elif float(total_food) >= daily_need * 6.0 and world.get("food_low_warned", false):
				world["food_low_warned"] = false

			# Stores-full warning: the raw pool (wood/stone/ore/intermediates) is shared, so
			# once it fills, gatherers can't deposit and freeze CARRYING their load — the
			# woodcutter keeps cutting but the realm gets no more wood, with no obvious cause.
			# Warn once (telling the player to build a Stockpile) while there's still a raw
			# producer being throttled; re-arm only after room opens back up. (iter204 — fixes
			# the reported "woodcutters keep cutting but I get no more wood".)
			if StorageSystem.room(players[0]) <= 0 and _has_raw_producer(players[0]):
				if not world.get("stores_full_warned", false):
					world["stores_full_warned"] = true
					EventBus.realm_notice.emit(
						"⚠ Your stores are full — wood, stone and ore have nowhere to go, so your woodcutters and miners stand idle. Build a Stockpile (or process raw goods, e.g. a Windmill for wheat) to keep production flowing.",
						"bad")
			elif StorageSystem.room(players[0]) > int(float(StorageSystem.get_capacity(players[0])) * 0.1) \
					and world.get("stores_full_warned", false):
				world["stores_full_warned"] = false

		# Realm events: a flavourful daily happening (merchant, foraging, wolves…) that
		# keeps the kingdom alive between the big beats. Player's own seat only.
		if not spectator_mode and not _ai_paused():
			var revent: Dictionary = WorldEventSystem.tick(players[0], world, _social_rng, day, day < AIFaction.PLAYER_GRACE_DAYS)
			if not revent.is_empty():
				var spawn_n: int = int(revent.get("effect", {}).get("spawn_citizens", 0))
				if spawn_n > 0:
					_next_citizen_id = CitizenSystem.spawn(citizens, spawn_n,
						float(players[0].get("keep_x", 100)), float(players[0].get("keep_y", 100)),
						_citizen_rng, _next_citizen_id)
					_snap_citizens_to_grass()
					players[0]["population"] = PeopleSystem.living_count(citizens)
				# A CHOICE event's effect is applied on RESOLVE, not here — record it as pending so
				# _cmd_resolve_event_choice stays idempotent (a resolve only lands once, against an
				# actually-pending event; a stray/duplicate command can't re-bank the reward).
				if not (revent.get("choices", []) as Array).is_empty():
					var _pce: Array = world.get("pending_choice_events", [])
					_pce.append(String(revent.get("id", "")))
					world["pending_choice_events"] = _pce
				EventBus.world_event.emit(revent)

	# Phase 6: tick AI factions each game-day
	if tick > 0 and tick % SimulationClock.TICKS_PER_GAME_DAY == 0:
		VisibilitySystem.recompute(self)
		if not players.is_empty():
			players[0]["fog_of_war"] = visibility.duplicate()
			EventBus.fog_of_war_updated.emit(0, visibility.keys())
		for faction in ai_factions:
			if not (faction is Dictionary and faction.get("is_alive", false)):
				continue
			if _ai_paused():
				continue  # tutorial: enemy lords take no daily actions
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
						# Siege damage to the seat. A PREPARED ruler (walls/towers/garrison)
						# blunts the assault badly; an undefended seat is gutted — so the
						# pre-siege warning is actionable and defending genuinely pays off.
						var defended_seat: bool = is_siege_ready(tgt)
						var siege_dmg: int = SIEGE_DAMAGE_DEFENDED if defended_seat else SIEGE_DAMAGE_UNDEFENDED
						EventBus.ai_siege_struck.emit(faction.get("id", -1), target_pid, defended_seat, siege_dmg)
						for bld in tgt.get("buildings", []):
							if not bld is Dictionary:
								continue
							if bld.get("type", "") in ["village_hall", "keep"]:
								if BuildingState.take_damage(bld, siege_dmg):
									PrestigeSystem.apply_defeat_loss(tgt)
									EventBus.building_destroyed.emit(tgt.get("id", 0), bld.get("id", -1), "siege")
								break
				if ev in ["bandit_raid_started", "ironhand_siege_started", "ashen_siege_started", "merchant_siege_started"]:
					var asm: Dictionary = faction.get("siege_assembly", {})
					EventBus.ai_siege_assembling.emit(
						faction.get("id", -1),
						asm.get("target_player_id", -1),
						AIFaction.SIEGE_ASSEMBLY_TICKS)
					# Make the assault VISIBLE: stage a warband near the player's seat that
					# marches in and fights, instead of an off-screen abstract strike.
					if int(asm.get("target_player_id", -1)) == 0 and not spectator_mode:
						_spawn_seat_attackers(faction)
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

			# NOTE: the old "mid-siege abstract combat" (an instant off-grid battle
			# each day that wiped the player's units from across the map with no
			# visible attacker) was removed. Besieging raiders now physically march
			# to the keep and fight on the grid (see the AI-faction unit tick), so
			# units only die to enemies that have actually reached them.

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

		# Strategic / campaign layer: the world-map kingdoms grow, build, raise
		# armies, wage campaigns and conduct diplomacy each game-day. Paused during
		# the tutorial so the great houses don't expand while the player learns.
		if not _ai_paused() and not _catch_up_mode:
			_tick_strategic_layer()

		# City generation feedback: a spectated town gains buildings as its strategic
		# development rises; the player's own seat feeds its built-up state back to
		# the world map so playing it advances the realm.
		if spectator_mode:
			_tick_spectator_growth()
		elif world.has("world_map") and not world["world_map"].is_empty():
			_update_seat_development()

# Advance the world-map strategic simulation one game-day and forward outcomes to
# EventBus. Driven both by the in-city day boundary (above) and by the world-map
# "watch the campaign" view (advance_strategic_day) — a single strategic_day
# counter keeps the RNG seed consistent no matter which path advances time.
func advance_strategic_day() -> void:
	_tick_strategic_layer()

# Lazily promote the static world map into a living strategic state. Safe to call
# repeatedly; returns true once a world map exists and is initialised.
func ensure_strategic_initialized() -> bool:
	return CampaignMap.ensure_initialized(world, players)

func strategic_day() -> int:
	return world.get("world_map", {}).get("strategic_day", 0)

# --- City generation: spectator towns + seat feedback ---

# Populate players[0] with a generated showcase of another faction's city, sized
# to its current strategic development. Called by CityViewScene when viewing a
# city that is not the player's playable seat. center_x/center_y is the (snapped)
# town centre on the freshly-generated city grid; seed_val matches that grid.
func enter_spectator_city(city_id: int, center_x: int, center_y: int, seed_val: int) -> void:
	spectator_mode = true
	_spectator_city_id = city_id
	ensure_strategic_initialized()
	var city: Dictionary = CampaignMap.city_by_id(world, city_id)
	var dev: int = int(city.get("development", city.get("tier", 0)))
	_spectator_last_dev = dev
	# Generate the town fully standing (prev_dev == dev → all built).
	var res: Dictionary = CityGenerator.building_dicts(
		center_x, center_y, _grid, seed_val, dev, 0, _next_building_id, dev)
	var blds: Array = res["buildings"]
	_next_building_id = res["next_id"]
	if not players.is_empty():
		players[0]["buildings"] = blds
	_register_buildings_in_grid(blds)
	# Re-people the town: more souls for a bigger settlement.
	var count: int = clampi(8 + dev * 2, 8, 30)
	citizens = []
	_next_citizen_id = 1
	if _citizen_rng == null:
		_citizen_rng = RandomNumberGenerator.new()
		_citizen_rng.seed = server_config.get("map_seed", 12345) ^ 0xC1721E
	_next_citizen_id = CitizenSystem.spawn(
		citizens, count, float(center_x), float(center_y), _citizen_rng, _next_citizen_id)
	_snap_citizens_to_grass()
	_spawn_spectator_military(city, center_x, center_y)   # make the city's troops VISIBLE
	_auto_manage_ai_town()   # staff the buildings immediately so it's alive on arrival

# Spectated cities used to show only villagers — their garrison was a number in the banner
# and a besieging army was purely abstract, so a city you were told was "under attack" looked
# empty of soldiers. Spawn a VISIBLE representative force: the home garrison as defenders, and,
# if a hostile strategic army targets this city, the besiegers drawn up at the gates. These are
# display-only (AI factions aren't ticked in spectator_mode) so the snapshot stays a snapshot.
func _spawn_spectator_military(city: Dictionary, cx: int, cy: int) -> void:
	if players.is_empty():
		return
	# Town centre = the rally the besiegers march on (and the defenders hold) for the live battle.
	players[0]["keep_x"] = cx
	players[0]["keep_y"] = cy
	var owner_fid: int = CampaignMap.owner_of(city)
	# Detect a besieging army FIRST so the garrison can form up to meet it.
	ai_factions = []
	var siege: Dictionary = _find_besieging_army(city.get("id", -1), owner_fid)
	var besieged: bool = not siege.is_empty()
	# ── Home garrison → visible defenders (rendered as the town's own units). ──
	# When besieged they muster FORWARD on OPEN ground toward the attackers (snapped to a free,
	# unbuilt cell) rather than buried in the building-packed centre — otherwise the melee besiegers
	# can't path the last few tiles in and the "live battle" stalls as a tableau (iter263/264).
	# Otherwise they stand near the town centre.
	var garrison: int = int(city.get("garrison", 0))
	var n_def: int = clampi(garrison / 4, 0, 12)
	var defenders: Array = []
	for i in range(n_def):
		var dx: int = cx - 3 + (i % 4) * 2
		var dy: int = cy - 2 + (i / 4) * 2
		if besieged:
			var fwd := _nearest_free_cell(cx + 5 - 2 + (i % 4) * 2, cy + 3 - 1 + (i / 4) * 2)
			if fwd.x >= 0:
				dx = fwd.x; dy = fwd.y
		var u: Dictionary = UnitState.create("militia", 0, dx, dy, _next_unit_id)
		if not u.is_empty():
			_next_unit_id += 1
			defenders.append(u)
	players[0]["units"] = defenders
	# ── A hostile army targeting this city → visible besiegers at the gates. ──
	if besieged:
		var army: Dictionary = siege["army"]
		var kingdom: Dictionary = siege["kingdom"]
		var n_atk: int = clampi(int(army.get("size", 0)) / 4, 1, 12)
		var foe_units: Array = []
		for j in range(n_atk):
			var ax: int = cx + 7 + (j % 4) * 2
			var ay: int = cy + 4 + (j / 4) * 2
			var fu: Dictionary = UnitState.create("armed_peasant", 90, ax, ay, _next_unit_id)
			if not fu.is_empty():
				_next_unit_id += 1
				foe_units.append(fu)
		ai_factions.append({
			"id": 90, "name": kingdom.get("name", "A rival host"),
			"archetype": "", "is_alive": true, "units": foe_units,
		})
		world["spectator_under_siege"] = true
		world["spectator_besieger_name"] = kingdom.get("name", "A rival host")
	else:
		world["spectator_under_siege"] = false

# Stage a VISIBLE besieging warband for `faction` a short march from the player's seat,
# so a siege is an army you can see coming and fight — not just abstract hall damage. The
# per-tick AI unit march (rally = keep while the siege is assembling) walks them in; the
# always-rendered enemy units make the attack plainly visible. Bounded: skip if the faction
# already has a live warband afield, so repeated sieges don't pile up endless units.
func _spawn_seat_attackers(faction: Dictionary) -> void:
	if players.is_empty():
		return
	var alive: int = 0
	for u in faction.get("units", []):
		if u is Dictionary and u.get("is_alive", false):
			alive += 1
	if alive >= 6:
		return  # a warband is already in the field
	var kx: int = int(players[0].get("keep_x", 100))
	var ky: int = int(players[0].get("keep_y", 100))
	# Stage ~14 tiles out, on the side toward the faction's home, so they march visibly in.
	var dir := Vector2(float(faction.get("capital_x", kx) - kx), float(faction.get("capital_y", ky) - ky))
	if dir.length() < 1.0:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var sx: int = clampi(kx + int(dir.x * 14.0), 2, 197)
	var sy: int = clampi(ky + int(dir.y * 14.0), 2, 197)
	var uid: int = int(faction.get("next_unit_id", faction.get("id", 0) * 10000 + 1))
	for j in range(8):
		var ax: int = clampi(sx + (j % 4) * 2 - 3, 2, 197)
		var ay: int = clampi(sy + (j / 4) * 2 - 2, 2, 197)
		var fu: Dictionary = UnitState.create("armed_peasant", int(faction.get("id", -1)), ax, ay, uid)
		if not fu.is_empty():
			uid += 1
			faction["units"].append(fu)
	faction["next_unit_id"] = uid

# The first hostile strategic army marching on (or sitting at) the given city, or {} if none.
func _find_besieging_army(city_id: int, owner_fid: int) -> Dictionary:
	if city_id < 0:
		return {}
	for k in CampaignMap.kingdoms(world):
		if not k is Dictionary or int(k.get("id", -1)) == owner_fid:
			continue
		for a in k.get("armies", []):
			if a is Dictionary and int(a.get("size", 0)) > 0 \
					and (int(a.get("dest_city_id", -1)) == city_id or int(a.get("location_city_id", -1)) == city_id):
				return {"army": a, "kingdom": k}
	return {}

# An AI town manages its own labour each day while it's being watched: it funds every
# worker-employing building from its workforce (so villagers walk in and physically
# work), and when it wants more workers than it can house it raises a hovel so the
# population can grow into the empty jobs.
func _auto_manage_ai_town() -> void:
	if players.is_empty():
		return
	var player: Dictionary = players[0]
	var slots: int = 0
	for b in player.get("buildings", []):
		if b is Dictionary and b.get("built", true) and b.get("is_active", true):
			slots += int(BuildingRegistry.lookup(b.get("type", "")).get("max_workers", 0))
	var living: int = PeopleSystem.living_count(citizens)
	var cap: int = PeopleSystem.housing_capacity(player)
	# Out of housing but short of workers → build a home so the town can grow.
	if living >= cap and living < slots and living < PeopleSystem.SAFETY_MAX_PEOPLE:
		_spectator_add_hovel(player)
	# Reserve a builder pool when construction is pending. Construction is pure labour
	# (builders are IDLE/WANDER villagers; job-workers are never pulled off to build), so
	# if we staffed EVERY job to max the whole workforce would be consumed and freshly
	# placed buildings (e.g. new churches) would never get raised. Hold back ~2 villagers
	# per unfinished site (capped at half the workforce) to keep construction moving.
	var unbuilt_sites: int = 0
	for b in player.get("buildings", []):
		if b is Dictionary and not b.get("built", true):
			unbuilt_sites += 1
	var workforce: int = PeopleSystem.living_count(citizens)
	var builder_reserve: int = 0
	if unbuilt_sites > 0:
		builder_reserve = clampi(unbuilt_sites * 2, 1, maxi(1, workforce / 2))
	var job_budget: int = maxi(0, workforce - builder_reserve)
	# Fund each building's worker slots from the budget; CitizenSystem walks pawns into
	# the jobs, and the reserved villagers stay idle and become builders.
	for b in player.get("buildings", []):
		if not (b is Dictionary and b.get("built", true) and b.get("is_active", true)):
			continue
		var maxw: int = int(BuildingRegistry.lookup(b.get("type", "")).get("max_workers", 0))
		if maxw <= 0:
			continue
		var give: int = mini(maxw, job_budget)
		b["workers"] = give
		job_budget -= give

# The AI town keeps its own settlement CONNECTED, like a player would: a building cut off from
# the town centre by a river gets a BRIDGE thrown to it; one that can't be reached at all (no
# crossing possible) is torn down so its would-be workers stop milling at the water's edge. One
# decision per call (the cut-off test is a full path-scan), and only when there's water about.
func _ai_manage_crossings(player: Dictionary) -> void:
	if _grid == null or player.is_empty():
		return
	var cx: int = int(player.get("keep_x", 100))
	var cy: int = int(player.get("keep_y", 100))
	if not _river_near(cx, cy, 22):
		return   # no water near this town — nothing to cross, skip the scan
	var pid: int = int(player.get("id", 0))
	for b in player.get("buildings", []).duplicate():
		if not (b is Dictionary and b.get("built", true)):
			continue
		var btype: String = String(b.get("type", ""))
		if BuildingRegistry.is_bridge(btype) or btype in ["village_hall", "keep"]:
			continue
		var defn: Dictionary = BuildingRegistry.lookup(btype)
		var spot: Vector2i = _free_tile_beside(int(b.get("grid_x", 0)), int(b.get("grid_y", 0)),
			defn.get("width", 1), defn.get("height", 1))
		if spot.x == -2147483648:
			continue
		# Reachable by land from the town centre? Then it's fine — leave it be.
		if not Pathfinder.find_path(_grid, cx, cy, spot.x, spot.y, 1, true).is_empty():
			continue
		# Cut off. Try to BRIDGE toward it; if a span is possible, raise it and we're done.
		var plan: Dictionary = BridgePlanner.plan_towards(_grid, cx, cy, spot.x, spot.y)
		if plan.get("ok", false) and _place_bridge(pid, player, int(plan["start"].x), int(plan["start"].y)):
			EventBus.realm_notice.emit("A bridge is raised to reach the %s across the water."
				% defn.get("name", "outpost"), "neutral")
			return
		# No crossing possible at all → demolish the stranded building (frees its workforce).
		_ai_demolish_building(player, pid, b)
		EventBus.realm_notice.emit("The stranded %s is pulled down — no way across the water."
			% defn.get("name", "building"), "neutral")
		return

# True if any RIVER tile lies within `r` of (cx,cy). Cheap pre-filter so only water-side towns
# pay for the (expensive) cut-off path scans below.
func _river_near(cx: int, cy: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _grid.in_bounds(cx + dx, cy + dy) \
					and _grid.get_terrain(cx + dx, cy + dy) == WorldGrid.Terrain.RIVER:
				return true
	return false

# A free, passable tile on the perimeter of the footprint at (bx,by)+(w,h) — where a worker would
# actually stand. Returns (-2147483648, …) when none is open.
func _free_tile_beside(bx: int, by: int, w: int, h: int) -> Vector2i:
	for dy in range(-1, h + 1):
		for dx in range(-1, w + 1):
			if dx >= 0 and dx < w and dy >= 0 and dy < h:
				continue   # inside the footprint — skip
			var x: int = bx + dx
			var y: int = by + dy
			if _grid.in_bounds(x, y) and _grid.get_building_at(x, y) == 0 \
					and _grid.is_passable(x, y, 1):
				return Vector2i(x, y)
	return Vector2i(-2147483648, 0)

# Tear down one of the town's own buildings: clear its grid tiles and drop it from the roster.
func _ai_demolish_building(player: Dictionary, pid: int, b: Dictionary) -> void:
	if _grid != null:
		var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
		var bx: int = int(b.get("grid_x", 0))
		var by: int = int(b.get("grid_y", 0))
		var was_crop: bool = BuildingRegistry.field_crop(b.get("type", "")) != 0
		for dy in range(defn.get("height", 1)):
			for dx in range(defn.get("width", 1)):
				_grid.set_building_at(bx + dx, by + dy, 0)
				_grid.set_field_at(bx + dx, by + dy, false)
				if was_crop:
					_grid.set_field_crop_at(bx + dx, by + dy, 0)
					EventBus.terrain_painted.emit(bx + dx, by + dy)
	player.get("buildings", []).erase(b)
	EventBus.building_demolished.emit(pid, int(b.get("id", -1)))

func _spectator_add_hovel(player: Dictionary) -> void:
	if _grid == null:
		return
	var c: Vector2i = _spectator_center()
	var spot: Vector2i = CityGenerator._find_spot(c.x, c.y, 1, 1, _grid, {})
	if spot.x == -2147483648:
		return
	var h: Dictionary = BuildingState.create("hovel", 0, spot.x, spot.y, _next_building_id)
	_next_building_id += 1
	h["built"] = true
	player["buildings"].append(h)
	_register_buildings_in_grid([h])

func _register_buildings_in_grid(blds: Array) -> void:
	if _grid == null:
		return
	for b in blds:
		if not b is Dictionary:
			continue
		var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
		var w: int = defn.get("width", 1)
		var h: int = defn.get("height", 1)
		var gx: int = b.get("grid_x", 0)
		var gy: int = b.get("grid_y", 0)
		var bid: int = b.get("id", 0)
		var field: bool = defn.get("field", false)
		var crop: int = BuildingRegistry.field_crop(b.get("type", ""))
		for dy in range(h):
			for dx in range(w):
				_grid.set_building_at(gx + dx, gy + dy, bid)
				_grid.set_field_at(gx + dx, gy + dy, field)
				if crop != 0:
					_grid.set_field_crop_at(gx + dx, gy + dy, crop)

# While spectating, append newly-unlocked buildings (as UNBUILT) when the town's
# strategic development rises, so the builder pawns visibly raise them.
func _tick_spectator_growth() -> void:
	if _spectator_city_id < 0 or players.is_empty():
		return
	var city: Dictionary = CampaignMap.city_by_id(world, _spectator_city_id)
	if city.is_empty():
		return
	var dev: int = int(city.get("development", city.get("tier", 0)))
	if dev <= _spectator_last_dev:
		return
	# Regenerate and take only the buildings unlocked since the last dev level.
	var center: Vector2i = _spectator_center()
	var res: Dictionary = CityGenerator.building_dicts(
		center.x, center.y, _grid, server_config.get("map_seed", 12345),
		dev, 0, _next_building_id, _spectator_last_dev)
	var existing: Dictionary = {}
	for b in players[0].get("buildings", []):
		if b is Dictionary:
			existing["%d,%d" % [b.get("grid_x", 0), b.get("grid_y", 0)]] = true
	var added: Array = []
	for b in res["buildings"]:
		var key: String = "%d,%d" % [b.get("grid_x", 0), b.get("grid_y", 0)]
		if existing.has(key):
			continue
		if not b.get("built", true):  # only the freshly-unlocked, under-construction ones
			added.append(b)
	if added.is_empty():
		_spectator_last_dev = dev
		return
	# Re-id the added buildings off the live counter and register them.
	for b in added:
		b["id"] = _next_building_id
		_next_building_id += 1
		players[0]["buildings"].append(b)
	_register_buildings_in_grid(added)
	_spectator_last_dev = dev

func _spectator_center() -> Vector2i:
	# The village hall anchors the town centre.
	for b in players[0].get("buildings", []):
		if b is Dictionary and b.get("type", "") in ["village_hall", "keep"]:
			return Vector2i(b.get("grid_x", 100), b.get("grid_y", 100))
	if not players.is_empty():
		return Vector2i(players[0].get("keep_x", 100), players[0].get("keep_y", 100))
	return Vector2i(100, 100)

# The player's hand-built seat advances its world-map development from how built-up
# it is, so playing your city grows your standing in the wider campaign.
func _update_seat_development() -> void:
	if players.is_empty():
		return
	var seat_id: int = world.get("player_seat_city_id", -1)
	if seat_id < 0:
		return
	var built_count: int = 0
	for b in players[0].get("buildings", []):
		if b is Dictionary and b.get("built", true):
			built_count += 1
	var implied: int = CityGenerator.development_from_building_count(built_count)
	var city: Dictionary = CampaignMap.city_by_id(world, seat_id)
	if city.is_empty():
		return
	if implied > int(city.get("development", 0)):
		city["development"] = implied

# While the tutorial is active the player chose to learn first — freeze ALL enemy action
# (local raiders + strategic great houses) so the computer can't get ahead during it.
func _ai_paused() -> bool:
	return bool(world.get("tutorial_active", false))

func _tick_strategic_layer() -> void:
	if not world.has("world_map") or world["world_map"].is_empty():
		return
	var wm: Dictionary = world["world_map"]
	var sday: int = wm.get("strategic_day", 0) + 1
	wm["strategic_day"] = sday
	var results: Array = StrategicSim.tick_day(world, players, sday * SimulationClock.TICKS_PER_GAME_DAY)
	for r in results:
		if not r is Dictionary:
			continue
		var fid: int = r.get("faction_id", -1)
		for ev in r.get("events", []):
			match ev:
				"army_raised":     EventBus.army_raised.emit(fid, -1, 0)
				"campaign_launched": EventBus.campaign_launched.emit(fid, -1, -1)
				"city_developed":  EventBus.city_developed.emit(fid, -1, 0)
				"kingdom_defeated":
					EventBus.kingdom_defeated.emit(fid)
					# World news: a rival realm has been wiped from the map.
					EventBus.realm_notice.emit("⚑ %s has been wiped from the map." % _kingdom_name(fid), "neutral")
		for b in r.get("battles", []):
			if not b is Dictionary:
				continue
			var cid: int = b.get("city_id", -1)
			var afid: int = b.get("attacker_fid", -1)
			var dfid: int = b.get("defender_fid", -1)
			var captured: bool = b.get("captured", false)
			EventBus.battle_resolved.emit(cid, afid, dfid, captured)
			if captured:
				EventBus.city_captured.emit(cid, dfid, afid)
			# Surface the war to the player — these resolved silently before. Player-
			# relevant battles always notify; distant AI-vs-AI fights only when a city
			# actually changes hands (so the feed isn't spammed by border skirmishes).
			_announce_strategic_battle(cid, afid, dfid, captured)
			# Stamp a fading "recently contested" marker on the world map so the player
			# can SEE where the war is being fought when they open the map.
			_record_recent_battle(wm, cid, sday, captured)
	_prune_recent_battles(wm, sday)

	# Feudal-title progression: the player's title is derived from holdings + development
	# + prestige (pure expansion, no caps). A promotion fires a herald cue; reaching King
	# is the win. Strategic defeat = driven from the last holding. (Skip while spectating.)
	if not spectator_mode:
		var promoted: int = FeudalRank.check_promotion(world, players)
		if promoted >= 0:
			EventBus.title_promoted.emit(promoted, FeudalRank.title_name(promoted))
		var pfid: int = CampaignMap.player_faction_id(world)
		if CampaignMap.faction_city_count(world, pfid) == 0 and not world.get("player_realm_lost_emitted", false):
			world["player_realm_lost_emitted"] = true
			EventBus.player_realm_lost.emit()

# A contested-city marker lingers this many strategic days, fading out.
const BATTLE_MARK_DAYS: int = 6

# Record a "recently contested" marker for the world map. Latest battle at a city wins
# (so a capture overwrites a prior repulse at the same place).
func _record_recent_battle(wm: Dictionary, cid: int, day: int, captured: bool) -> void:
	if cid < 0:
		return
	var marks: Array = wm.get("recent_battles", [])
	for m in marks:
		if m is Dictionary and int(m.get("city_id", -1)) == cid:
			m["day"] = day
			m["captured"] = captured
			wm["recent_battles"] = marks
			return
	marks.append({"city_id": cid, "day": day, "captured": captured})
	wm["recent_battles"] = marks

# Drop markers older than BATTLE_MARK_DAYS so the list stays bounded over a long war.
func _prune_recent_battles(wm: Dictionary, day: int) -> void:
	var marks: Array = wm.get("recent_battles", [])
	if marks.is_empty():
		return
	var kept: Array = []
	for m in marks:
		if m is Dictionary and day - int(m.get("day", -999)) < BATTLE_MARK_DAYS:
			kept.append(m)
	wm["recent_battles"] = kept

func _kingdom_name(fid: int) -> String:
	var k: Dictionary = CampaignMap.kingdom_by_id(world, fid)
	return String(k.get("name", "A kingdom")) if not k.is_empty() else "A kingdom"

func _strategic_city_name(cid: int) -> String:
	var c: Dictionary = CampaignMap.city_by_id(world, cid)
	return String(c.get("name", "a city")) if not c.is_empty() else "a city"

# Turn a resolved strategic battle into a readable realm notice (city-view toast).
# Player-relevant fights always announce; AI-vs-AI only on a capture (no skirmish spam).
func _announce_strategic_battle(cid: int, afid: int, dfid: int, captured: bool) -> void:
	var pfid: int = CampaignMap.player_faction_id(world)
	var city: String = _strategic_city_name(cid)
	if afid == pfid:
		# The player's own campaign resolved.
		if captured:
			EventBus.realm_notice.emit("⚔ Your host has taken %s!" % city, "good")
		else:
			EventBus.realm_notice.emit("Your assault on %s was thrown back." % city, "bad")
	elif dfid == pfid:
		# Someone struck one of the player's cities.
		var attacker: String = _kingdom_name(afid)
		if captured:
			EventBus.realm_notice.emit("💥 %s has seized your city of %s!" % [attacker, city], "bad")
		else:
			EventBus.realm_notice.emit("🛡 Your garrison at %s held against %s." % [city, attacker], "good")
	elif captured:
		# Distant war news — only when a city actually changes hands.
		EventBus.realm_notice.emit("⚑ %s has captured %s from %s." % [_kingdom_name(afid), city, _kingdom_name(dfid)], "neutral")

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

	# Bridges span a river — a stretchable, multi-cell crossing, handled specially.
	if BuildingRegistry.is_bridge(btype):
		return _place_bridge(pid, player, gx, gy)

	# Validate placement (requires grid if available)
	if _grid != null:
		var result: Dictionary = PlacementValidator.validate(btype, gx, gy, _grid, player, world)
		if not result["ok"]:
			EventBus.building_placement_failed.emit(pid, btype, gx, gy, result.get("message", ""))
			return false

	# A gate raised over the player's OWN wall/fence REPLACES that segment — clear the overlapped
	# walls now so the gate can occupy the run (the validator permitted the overlap above).
	if _grid != null and BuildingRegistry.lookup(btype).get("is_gate", false):
		var _gdef: Dictionary = BuildingRegistry.lookup(btype)
		_replace_walls_in_footprint(player, pid, gx, gy, _gdef.get("width", 1), _gdef.get("height", 1))

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
		var field: bool = defn.get("field", false)
		var crop: int = BuildingRegistry.field_crop(btype)
		for dy in range(h):
			for dx in range(w):
				_grid.set_building_at(gx + dx, gy + dy, bid)
				_grid.set_field_at(gx + dx, gy + dy, field)
				if crop != 0:
					# Stamp the crop onto the REAL terrain so the ground itself renders as farmland
					# (TerrainChunk) — the field has no building floor of its own.
					_grid.set_field_crop_at(gx + dx, gy + dy, crop)
					EventBus.terrain_painted.emit(gx + dx, gy + dy)

	# Placed unbuilt — villagers must raise it. build_progress accrues per builder
	# (see CitizenSystem); the structure isn't functional until built. Bigger
	# footprints take more work.
	var _cdefn: Dictionary = BuildingRegistry.lookup(btype)
	building["built"] = false
	building["build_progress"] = 0.0
	# Paths are quick to pave; real structures scale with footprint.
	if _cdefn.get("is_path", false):
		building["build_required"] = 15.0
	else:
		building["build_required"] = float(maxi(1, _cdefn.get("width", 1) * _cdefn.get("height", 1))) * 100.0
	# Material hauling: builders fetch the physical materials (wood/stone/iron) from a
	# depot in batches; build progress is capped by how much has been DELIVERED, so a
	# structure cannot rise faster than its supplies arrive (cost already deducted above —
	# this paces construction and shows builders carrying the load). 0 = no haul (e.g. the
	# free Village Hall / paths) → labour only.
	var _mcost: Dictionary = _cdefn.get("cost", {})
	building["build_mat_total"] = int(_mcost.get("wood", 0)) + int(_mcost.get("stone", 0)) + int(_mcost.get("iron", 0))
	building["build_mat_delivered"] = 0
	player["buildings"].append(building)
	EventBus.building_placed.emit(pid, btype, gx, gy, bid)
	# Founding a hall lays down the realm's INITIAL stockpile beside it — a ready delivery
	# point so haulers (and the AI) know where to drop goods. It adds NO storage capacity
	# (the keep's base cellar already counts it) and is drawn larger to read as the main store.
	if btype == "village_hall" and not _has_initial_stockpile(player):
		_spawn_initial_stockpile(player, gx, gy)
	return true

# Lay a bridge across a river from the hovered land cell. The span is recomputed here from
# the live grid (authoritative — the client only sends the anchor), then the water cells it
# crosses become passable BRIDGE terrain. The bridge stands immediately (builders can't
# work mid-river); the deck is stored on the building so the view can draw it.
func _place_bridge(pid: int, player: Dictionary, gx: int, gy: int) -> bool:
	if _grid == null:
		return false
	var plan: Dictionary = BridgePlanner.plan(_grid, gx, gy)
	if not plan.get("ok", false):
		EventBus.building_placement_failed.emit(pid, "bridge", gx, gy, plan.get("reason", "Cannot bridge here"))
		return false
	# Affordability.
	var cost: Dictionary = BuildingRegistry.lookup("bridge").get("cost", {})
	for r in cost:
		var have: int = player.get("gold", 0) if r == "gold" else int(player.get("resources", {}).get(r, 0))
		if have < int(cost[r]):
			EventBus.building_placement_failed.emit(pid, "bridge", gx, gy, "Not enough %s" % r)
			return false
	PlacementValidator.deduct_cost("bridge", player)

	var bid: int = _next_building_id
	_next_building_id += 1
	var building: Dictionary = BuildingState.create("bridge", pid, gx, gy, bid)
	if building.is_empty():
		return false
	building["built"] = true
	building["build_progress"] = 1.0
	building["build_required"] = 0.0
	building["build_mat_total"] = 0
	building["build_mat_delivered"] = 0
	var deck_arr: Array = []
	for c in plan["deck"]:
		deck_arr.append([c.x, c.y])
	building["bridge_deck"] = deck_arr
	building["bridge_dir"] = [int(plan["dir"].x), int(plan["dir"].y)]
	# Convert the spanned water to passable BRIDGE terrain and mark it occupied by the bridge.
	# Mark the deck as a walkable "field" tile too: civilian A* (avoid_buildings) treats ANY
	# building tile as impassable UNLESS it's a field — so without this, pawns can't actually
	# cross the bridge (the whole point of building it). This fixes player bridges as well.
	for c in plan["cells"]:
		_grid.set_terrain(c.x, c.y, WorldGrid.Terrain.BRIDGE)
		_grid.set_building_at(c.x, c.y, bid)
		_grid.set_field_at(c.x, c.y, true)
	player["buildings"].append(building)
	EventBus.building_placed.emit(pid, "bridge", gx, gy, bid)
	return true

func _has_initial_stockpile(player: Dictionary) -> bool:
	for b in player.get("buildings", []):
		if b is Dictionary and b.get("type", "") == "stockpile" and b.get("initial", false):
			return true
	return false

# Place a pre-built INITIAL stockpile on the first free tile around the hall. Flagged
# "initial" (renderer draws it bigger) with storage_max 0 (no capacity added — RAW_BASE
# already covers the base cellar). It exists purely as the primary delivery point.
func _spawn_initial_stockpile(player: Dictionary, hx: int, hy: int) -> void:
	if _grid == null:
		return
	var hd: Dictionary = BuildingRegistry.lookup("village_hall")
	var hw: int = int(hd.get("width", 3))
	var hh: int = int(hd.get("height", 3))
	var cands: Array = []
	for dy in range(-1, hh + 1):
		cands.append(Vector2i(hx + hw, hy + dy))
		cands.append(Vector2i(hx - 1, hy + dy))
	for dx in range(0, hw):
		cands.append(Vector2i(hx + dx, hy + hh))
		cands.append(Vector2i(hx + dx, hy - 1))
	for c in cands:
		var sx: int = c.x
		var sy: int = c.y
		if sx < 2 or sy < 2 or sx > 197 or sy > 197:
			continue
		if _grid.get_building_at(sx, sy) != 0:
			continue
		if _grid.get_terrain(sx, sy) in [2, 3, 5, 8]:   # skip mountain/river/rock/coast
			continue
		var bid: int = _next_building_id
		_next_building_id += 1
		var sb: Dictionary = BuildingState.create("stockpile", int(player.get("id", 0)), sx, sy, bid)
		if sb.is_empty():
			return
		sb["built"] = true
		sb["build_progress"] = 100.0
		sb["build_required"] = 1.0
		sb["build_mat_total"] = 0
		sb["build_mat_delivered"] = 0
		sb["initial"] = true       # drawn larger; StorageSystem ignores its (0) capacity
		sb["storage_max"] = 0
		_grid.set_building_at(sx, sy, bid)
		player["buildings"].append(sb)
		EventBus.building_placed.emit(int(player.get("id", 0)), "stockpile", sx, sy, bid)
		return

# Remove the player's wall/fence segments that fall inside (gx,gy)+(w,h) — used when a gate is
# raised over a wall run, replacing those segments. Walls are 1×1, so a footprint test suffices.
func _replace_walls_in_footprint(player: Dictionary, pid: int, gx: int, gy: int, w: int, h: int) -> void:
	if _grid == null:
		return
	var kept: Array = []
	for b in player.get("buildings", []):
		var drop: bool = false
		if b is Dictionary and BuildingRegistry.lookup(b.get("type", "")).get("is_wall", false):
			var bx: int = int(b.get("grid_x", 0))
			var by: int = int(b.get("grid_y", 0))
			if bx >= gx and bx < gx + w and by >= gy and by < gy + h:
				_grid.set_building_at(bx, by, 0)
				EventBus.building_demolished.emit(pid, int(b.get("id", -1)))
				drop = true
		if not drop:
			kept.append(b)
	player["buildings"] = kept

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

		# The SEAT (village hall / keep) can't be razed by hand — losing it is a DEFEAT (siege),
		# not a build choice; demolishing it would leave a seat-less, half-broken realm without
		# even firing the loss screen (demolish emits building_demolished, not building_destroyed).
		# The HUD hides the Demolish button for the seat, but the Delete-key path didn't guard it —
		# so enforce it here, in the authoritative command, where EVERY path converges. (iter281)
		# A brief notice closes the feedback loop so a Delete-on-seat reads as "not allowed", not
		# an unresponsive game (the normal demolish already gives a sound + the building vanishing).
		if building.get("type", "") in ["village_hall", "keep"]:
			if pid == 0:
				EventBus.realm_notice.emit(
					"Your seat may not be razed by your own hand — to lose it would be a defeat, not a decree.", "bad")
			return false

		# Clear grid cells
		if _grid != null:
			var btype: String = building.get("type", "")
			var defn: Dictionary = BuildingRegistry.lookup(btype)
			var w: int = defn.get("width", 1)
			var h: int = defn.get("height", 1)
			var gx: int = building.get("grid_x", 0)
			var gy: int = building.get("grid_y", 0)
			var was_crop: bool = BuildingRegistry.field_crop(btype) != 0
			for dy in range(h):
				for dx in range(w):
					_grid.set_building_at(gx + dx, gy + dy, 0)
					_grid.set_field_at(gx + dx, gy + dy, false)
					if was_crop:
						_grid.set_field_crop_at(gx + dx, gy + dy, 0)   # back to plain ground
						EventBus.terrain_painted.emit(gx + dx, gy + dy)

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
		if pid == 0:
			EventBus.realm_notice.emit("Bought %d %s for %d gold." % [
				int(payload.get("amount", 0)), String(payload.get("resource", "")), int(result.get("cost", 0))], "good")
		return true
	if pid == 0:
		EventBus.realm_notice.emit("Trade failed: %s." % String(result.get("message", "the market refused")), "bad")
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
		if pid == 0:
			EventBus.realm_notice.emit("Sold %d %s for %d gold." % [
				int(payload.get("amount", 0)), String(payload.get("resource", "")), int(result.get("earned", 0))], "good")
		return true
	if pid == 0:
		EventBus.realm_notice.emit("Trade failed: %s." % String(result.get("message", "the market refused")), "bad")
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
			# Land the decree's FULL one-off effect (a Festival = +8 now), not the
			# ×0.05-smoothed per-tick version that made it a meaningless +0.4.
			var before_pop: float = players[pid].get("popularity", 50.0)
			var after_pop: float = PopularityEngine.apply_instant_event(players[pid], mods["instant_event"])
			if pid == 0 and after_pop != before_pop:
				EventBus.realm_notice.emit("🎉 Feasting fills the streets — the people rejoice (popularity %+d)." % int(round(after_pop - before_pop)), "good")
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
		var paid: bool = DiplomacySystem.accept(players[pid], payload.get("demands", {}), faction, SimulationClock.current_tick)
		if not paid:
			# Couldn't meet the tribute in full — nothing is paid and no peace is bought.
			# The demand stays active so the lord can gather the goods and accept later
			# (or refuse). Without this guard, accepting an unaffordable demand drained
			# whatever partial stock existed yet still bought peace for free.
			EventBus.realm_notice.emit("You cannot afford that tribute in full — the demand still stands.", "bad")
	else:
		DiplomacySystem.refuse(players[pid], faction)
	return true

# Player picked an option on a World Event (choice popup). Applies the chosen effect,
# enacts a "wanderer/refugees join" spawn if any, and announces the outcome.
func _cmd_resolve_event_choice(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var event_id: String = String(payload.get("event_id", ""))
	# Idempotency: only resolve an event that is actually PENDING (fired and unanswered), so a
	# duplicate/stray resolve command can't re-bank the choice's reward.
	var _pce: Array = world.get("pending_choice_events", [])
	if event_id not in _pce:
		return false
	var outcome: Dictionary = WorldEventSystem.resolve(
		players[pid], event_id, int(payload.get("choice_index", -1)))
	if outcome.is_empty():
		return false   # invalid choice — leave it pending so a valid retry still works
	# Consume it only once the choice landed.
	_pce.erase(event_id)
	world["pending_choice_events"] = _pce
	var spawn_n: int = int(outcome.get("spawn_citizens", 0))
	if spawn_n > 0 and pid == 0:
		_next_citizen_id = CitizenSystem.spawn(citizens, spawn_n,
			float(players[0].get("keep_x", 100)), float(players[0].get("keep_y", 100)),
			_citizen_rng, _next_citizen_id)
		_snap_citizens_to_grass()
		players[0]["population"] = PeopleSystem.living_count(citizens)
	# The choice label already describes the outcome ("Accept the loan (+150 gold…)"),
	# so the notice is just a confirmation of what the lord decreed.
	EventBus.realm_notice.emit("You decreed: " + String(outcome.get("label", "your will")), outcome.get("tone", "neutral"))
	return true

# Set a player unit's combat stance (guard ↔ aggressive). Guard units hold their post
# and return after a fight; aggressive units pursue any foe freely.
func _cmd_set_unit_stance(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var payload: Dictionary = cmd["payload"]
	var uid: int = int(payload.get("unit_id", -1))
	var stance: String = String(payload.get("stance", UnitState.STANCE_GUARD))
	if stance != UnitState.STANCE_GUARD and stance != UnitState.STANCE_AGGRESSIVE:
		return false
	for u in players[pid].get("units", []):
		if u is Dictionary and u.get("id", -1) == uid:
			u["stance"] = stance
			# Drop any active leash so the new stance takes effect on the current fight.
			u["auto_aggro"] = false
			return true
	return false

func _cmd_research_tech(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var tech_id: String = cmd["payload"].get("tech_id", "")
	var result: Dictionary = TechTree.research(players[pid], tech_id)
	# Reward feedback: announce the readable name AND what it just unlocked, so research
	# feels like progress (was a raw "Researching: crop_tiers" with no payoff).
	if result.get("ok", false) and pid == 0:
		var node: Dictionary = TechTree.lookup(tech_id)
		var unlocked: Array = []
		unlocked.append_array(node.get("unlocks_buildings", []))
		unlocked.append_array(node.get("unlocks_units", []))
		unlocked.append_array(node.get("unlocks_edicts", []))
		var names: Array = []
		for u in unlocked:
			names.append(String(u).capitalize())
		var tail: String = (" — unlocked %s" % ", ".join(names)) if not names.is_empty() else ""
		EventBus.realm_notice.emit("🔬 Researched %s%s." % [node.get("name", tech_id), tail], "good")
	return result.get("ok", false)

# --- Strategic / campaign command handlers (player parity) ---
# These let the human player do, on the world map, exactly what the AI kingdoms
# do — develop cities, raise armies, launch campaigns, conduct diplomacy — by
# routing through the same shared primitives (CampaignSystem / KingdomEconomy).

# The kingdom the human player commands (their faction on the world map).
func _player_kingdom() -> Dictionary:
	if not world.has("world_map") or world["world_map"].is_empty():
		return {}
	CampaignMap.ensure_initialized(world, players)
	return CampaignMap.kingdom_by_id(world, CampaignMap.player_faction_id(world))

func _cmd_develop_city(cmd: Dictionary) -> bool:
	return player_develop_city(cmd["payload"].get("city_id", -1))

# The player's feudal title — the PEAK earned (titles don't demote when you lose land, like
# a real peerage). check_promotion stores the never-demote max in world.player_title_index;
# fall back to the live index if it hasn't been computed yet.
func player_title_name() -> String:
	if not world.has("world_map") or world["world_map"].is_empty():
		return FeudalRank.title_name(0)
	var live: int = FeudalRank.current_index(world, players)
	var peak: int = int(world.get("player_title_index", 0))
	return FeudalRank.title_name(maxi(live, peak))

# How many villages the player currently holds.
func player_holdings_count() -> int:
	if not world.has("world_map") or world["world_map"].is_empty():
		return 0
	return CampaignMap.faction_city_count(world, CampaignMap.player_faction_id(world))

# ── Player strategic actions (shared by the command path AND the world-map UI) ──
# The world map advances the strategic layer directly with the clock paused, so the
# command queue isn't drained there — the WorldMap HUD calls these directly.

# Invest in one of the player's own cities, spending the realm's treasury/resources to
# raise its development by one. Returns true on success. Mirrors the AI's own growth.
func player_develop_city(city_id: int) -> bool:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return false
	if KingdomEconomy.develop_city(world, k, city_id):
		var c: Dictionary = CampaignMap.city_by_id(world, city_id)
		EventBus.city_developed.emit(k.get("id", -1), city_id, c.get("development", 0))
		return true
	return false

# Can the player afford to develop the given city right now?
func can_player_develop_city(city_id: int) -> bool:
	var k: Dictionary = _player_kingdom()
	return not k.is_empty() and KingdomEconomy.can_develop(world, k, city_id)

# Does the player's faction own this city? (For per-city world-map actions.)
func is_player_city(city_id: int) -> bool:
	if not world.has("world_map") or world["world_map"].is_empty():
		return false
	var c: Dictionary = CampaignMap.city_by_id(world, city_id)
	if c.is_empty():
		return false
	return CampaignMap.owner_of(c) == CampaignMap.player_faction_id(world)

# The player's least-developed owned city (the natural next investment), or -1.
func player_lowest_dev_city() -> int:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return -1
	return KingdomEconomy.lowest_dev_city(world, k)

# The gold/wood/stone cost to develop a city at its current level (for UI display).
func develop_city_cost(city_id: int) -> Dictionary:
	var c: Dictionary = CampaignMap.city_by_id(world, city_id)
	if c.is_empty():
		return {}
	return KingdomEconomy.development_cost(c.get("development", c.get("tier", 0)))

# The player realm's strategic stores (treasury + wood/stone/iron/food), for the
# world-map HUD so the player can plan investments. Empty {} if no player kingdom.
func player_realm_stores() -> Dictionary:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return {}
	var res: Dictionary = k.get("resources", {})
	return {
		"treasury": int(k.get("treasury", 0)),
		"wood":  int(res.get("wood", 0)),
		"stone": int(res.get("stone", 0)),
		"iron":  int(res.get("iron", 0)),
		"food":  int(res.get("food", 0)),
		"cities": CampaignMap.faction_city_count(world, CampaignMap.player_faction_id(world)),
	}

# The player's armies currently on the march — for a persistent world-map readout so
# you always know where your hosts are and roughly when they arrive (1 hop ≈ 1 day).
# Returns Array of {size, dest_name, eta_days}.
func player_marching_armies() -> Array:
	var out: Array = []
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return out
	for a in k.get("armies", []):
		if not (a is Dictionary) or int(a.get("size", 0)) <= 0:
			continue
		var path: Array = a.get("path", [])
		if path.is_empty():
			continue
		var dest_id: int = int(a.get("dest_city_id", path[path.size() - 1]))
		var dest: Dictionary = CampaignMap.city_by_id(world, dest_id)
		out.append({
			"size": int(a.get("size", 0)),
			"dest_name": String(dest.get("name", "enemy lands")) if not dest.is_empty() else "enemy lands",
			"eta_days": CampaignSystem.days_to_destination(world, a),
		})
	return out

func _cmd_raise_army(cmd: Dictionary) -> bool:
	return player_raise_army(cmd["payload"].get("city_id", -1), cmd["payload"].get("size", 0))

# Levy a field army at one of the player's own cities (shared by the command path and
# the world-map UI — clock-independent). Spends treasury; merges into an idle army
# already stationed there. Returns true on success.
func player_raise_army(city_id: int, size: int) -> bool:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return false
	var aid: int = CampaignSystem.raise_army(world, k, city_id, size)
	if aid >= 0:
		EventBus.army_raised.emit(k.get("id", -1), city_id, size)
		return true
	return false

# Can the player afford to levy `size` soldiers at this owned city right now?
func can_player_raise_army(city_id: int, size: int) -> bool:
	var k: Dictionary = _player_kingdom()
	return not k.is_empty() and CampaignSystem.can_raise_army(world, k, city_id, size)

# Gold cost to levy `size` soldiers (for UI display).
func raise_army_cost(size: int) -> int:
	return size * CampaignSystem.GOLD_PER_SOLDIER

# The id of the player's idle field army stationed at this city (or -1). For the
# world-map "March" order — you can only send an army that's standing in a city.
func player_army_at_city(city_id: int) -> int:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return -1
	for a in k.get("armies", []):
		if a is Dictionary and int(a.get("location_city_id", -1)) == city_id \
				and int(a.get("size", 0)) > 0 and a.get("path", []).is_empty():
			return int(a.get("id", -1))
	return -1

# The soldier count of one of the player's armies (for UI labels), or 0.
func player_army_size(army_id: int) -> int:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return 0
	return int(CampaignSystem.find_army(k, army_id).get("size", 0))

# Order a player army to march on (and assault, if hostile) a target city. Shared by
# the command path and the world-map UI (clock-independent). True if a road path exists.
func player_launch_campaign(army_id: int, target_city_id: int) -> bool:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return false
	if CampaignSystem.launch_campaign(world, k, army_id, target_city_id):
		EventBus.campaign_launched.emit(k.get("id", -1), army_id, target_city_id)
		return true
	return false

func _cmd_launch_campaign(cmd: Dictionary) -> bool:
	return player_launch_campaign(cmd["payload"].get("army_id", -1), cmd["payload"].get("target_city_id", -1))

# Count of the player's real, deployable (alive, not still training) soldiers standing in
# their seat — the host they could march RIGHT NOW. (UI label + march gating.)
func player_field_strength() -> int:
	if players.is_empty():
		return 0
	var n: int = 0
	for u in players[0].get("units", []):
		if u is Dictionary and UnitState.is_deployable(u):
			n += 1
	return n

# March the player's REAL trained troops out of their seat to assault a target city. This
# is the layer fusion (Phase 1): the army that crosses the map and fights is literally the
# units you trained — they are pulled out of the city, packed into a world-map field army by
# identity, and sent down the road. No gold cost (you paid to train them). `max_units` caps
# how many to send (-1 = all). Returns true if a road path exists and at least one marched.
func player_march_units(from_city_id: int, target_city_id: int, max_units: int = -1) -> bool:
	var k: Dictionary = _player_kingdom()
	if k.is_empty() or players.is_empty():
		return false
	var player: Dictionary = players[0]
	var pool: Array = []
	for u in player.get("units", []):
		if u is Dictionary and UnitState.is_deployable(u):
			pool.append(u)
	if pool.is_empty():
		return false
	if max_units > 0 and pool.size() > max_units:
		pool = pool.slice(0, max_units)
	var aid: int = CampaignSystem.create_unit_army(world, k, from_city_id, pool)
	if aid < 0:
		return false
	if not CampaignSystem.launch_campaign(world, k, aid, target_city_id):
		# No road to the target — undo: hand the troops back to the city, drop the army.
		var army: Dictionary = CampaignSystem.find_army(k, aid)
		k["armies"].erase(army)
		return false
	# Remove the marched units from the seat now that the campaign is underway.
	var marched := {}
	for u in pool:
		marched[u.get("id", -1)] = true
	var remaining: Array = []
	for u in player.get("units", []):
		if not (u is Dictionary and marched.has(u.get("id", -1))):
			remaining.append(u)
	player["units"] = remaining
	EventBus.campaign_launched.emit(k.get("id", -1), aid, target_city_id)
	return true

func _cmd_strategic_diplomacy(cmd: Dictionary) -> bool:
	return player_set_diplomacy(cmd["payload"].get("faction_id", -1), cmd["payload"].get("action", ""))

# Set the player realm's relation with another kingdom ("truce" | "war"), mutually.
# Shared by the command path and the world-map UI (clock-independent). A truce is
# honoured by AI attack targeting (KingdomAI._best_target), so it actually buys peace.
func player_set_diplomacy(faction_id: int, action: String) -> bool:
	var k: Dictionary = _player_kingdom()
	if k.is_empty() or action == "":
		return false
	var other: Dictionary = CampaignMap.kingdom_by_id(world, faction_id)
	if other.is_empty() or faction_id == k.get("id", -1):
		return false
	k.get("relations", {})[str(faction_id)] = action
	other.get("relations", {})[str(k.get("id", -1))] = action
	return true

# The player realm's current relation with another kingdom: "neutral" | "truce" | "war".
func player_relation_with(faction_id: int) -> String:
	var k: Dictionary = _player_kingdom()
	if k.is_empty():
		return "neutral"
	return String(k.get("relations", {}).get(str(faction_id), "neutral"))

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

# Spawn a couple of fresh villagers each day (near the campfire/keep) until the
# visible stock reaches a population-scaled target — the labour pool that workers
# are drawn from.
func _grow_citizen_stock() -> void:
	if players.is_empty():
		return
	var target: int = clampi(players[0].get("population", 0) / 3, 8, CitizenSystem.MAX_CITIZENS)
	if citizens.size() >= target:
		return
	var hx: float = float(players[0].get("keep_x", 100))
	var hy: float = float(players[0].get("keep_y", 100))
	if campfire.get("active", false):
		hx = float(campfire.get("x", hx))
		hy = float(campfire.get("y", hy))
	if _citizen_rng == null:
		_citizen_rng = RandomNumberGenerator.new()
		_citizen_rng.seed = server_config.get("map_seed", 12345) ^ 0xC1721E
	var add: int = mini(2, target - citizens.size())
	_next_citizen_id = CitizenSystem.spawn(citizens, add, hx, hy, _citizen_rng, _next_citizen_id)

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
		var r: float = 2.4 + float(idx % 4) * 0.7
		var hx: int = int(round(fx + cos(a) * r))
		var hy: int = int(round(fy + sin(a) * r))
		# Keep homes off the hall/other buildings so pawns don't gather on a wall.
		var spot := _nearest_empty_grass(hx, hy, {})
		c["hx"] = float(spot.x)
		c["hy"] = float(spot.y)

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
	# Feedback: recruiting was silent (no signal, no notice) so the player couldn't tell
	# it worked or where the soldier appeared. Tell them, and where to find them.
	if pid == 0:
		var uname: String = defn.get("name", unit_type)
		if defn.get("train_ticks", 0) > 0:
			EventBus.realm_notice.emit("⚔ %s began training at the barracks." % uname, "neutral")
		else:
			EventBus.realm_notice.emit("⚔ %s mustered by the campfire — ready for your orders." % uname, "good")
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
			# Formation spread: if another of this player's units already sits on or
			# is heading to the target tile, fan out to the nearest free one so a
			# group doesn't pile onto a single square.
			var dest: Vector2i = _spread_target(pid, tx, ty, uid)
			UnitState.issue_move_order(unit, dest.x, dest.y)
			if _grid != null:
				unit["move_path"] = Pathfinder.find_path(
					_grid, unit.get("pos_x", 0), unit.get("pos_y", 0), dest.x, dest.y)
			else:
				unit["move_path"] = []
			return true
	return false

# Find the nearest tile to (tx,ty) not already occupied or targeted by another of
# this player's units — spreads a moving group into a loose formation.
func _spread_target(pid: int, tx: int, ty: int, mover_uid: int) -> Vector2i:
	var claimed: Dictionary = {}
	for u in players[pid].get("units", []):
		if not (u is Dictionary and u.get("is_alive", false)):
			continue
		if u.get("id", -1) == mover_uid:
			continue
		claimed["%d,%d" % [u.get("pos_x", 0), u.get("pos_y", 0)]] = true
		if u.get("order", "") == UnitState.ORDER_MOVE:
			claimed["%d,%d" % [u.get("target_x", 0), u.get("target_y", 0)]] = true
	if not claimed.has("%d,%d" % [tx, ty]):
		return Vector2i(tx, ty)
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x: int = tx + dx
				var y: int = ty + dy
				if claimed.has("%d,%d" % [x, y]):
					continue
				if _grid != null and (not _grid.in_bounds(x, y) \
						or not _grid.is_passable(x, y, WorldGrid.PASSABLE_FOOT) \
						or _grid.get_building_at(x, y) != 0):
					continue
				return Vector2i(x, y)
	return Vector2i(tx, ty)

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

# Crop stamped on this tile by a field building (0 none, 1 wheat, 2 orchard, 3 pasture, 4 mud,
# 5 hops) — so the TERRAIN renderer can paint the real ground as farmland.
func get_field_crop_at(x: int, y: int) -> int:
	return _grid.get_field_crop_at(x, y) if _grid != null else 0

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

# --- Seat persistence across scene changes ------------------------------------
# GameState is an autoload, but CityViewScene._init_simulation used to rebuild the world
# (setup_world + initialize_player) on EVERY entry — so leaving for the world map (or
# spectating a rival city, which overwrites players[0]) wiped your hand-built seat. These
# snapshot the seat's living state on leave and restore it on return, so your city is
# exactly as you left it. The grid TERRAIN is saved; building/field occupancy is rederived
# from the buildings list via _register_buildings_in_grid.

func stash_seat_snapshot() -> void:
	# Never overwrite the seat with a spectator showcase (players[0] is the rival town then).
	if spectator_mode or players.is_empty() or _grid == null:
		return
	world["seat_snapshot"] = {
		"grid": _grid.serialize(),
		"player": players[0].duplicate(true),
		"citizens": citizens.duplicate(true),
		"ai_factions": ai_factions.duplicate(true),
		"wildlife": wildlife.duplicate(true),
		"campfire": campfire.duplicate(true),
		"next_building_id": _next_building_id,
		"next_unit_id": _next_unit_id,
		"next_citizen_id": _next_citizen_id,
		"next_animal_id": _next_animal_id,
		"seat_city_id": int(world.get("player_seat_city_id", -1)),
		"left_at_tick": SimulationClock.current_tick,
		"left_at_day": strategic_day(),
	}

func has_seat_snapshot_for(city_id: int) -> bool:
	var s = world.get("seat_snapshot", null)
	return s is Dictionary and not s.is_empty() and int(s.get("seat_city_id", -2)) == city_id

func restore_seat_snapshot() -> bool:
	var s = world.get("seat_snapshot", null)
	if not (s is Dictionary and not s.is_empty()):
		return false
	spectator_mode = false
	_grid = WorldGrid.new(server_config["map_width"], server_config["map_height"])
	_grid.deserialize(s["grid"])
	# Shire map is deterministic from the seed; rebuild only if this fresh session lost it.
	if _shire_map == null:
		_shire_map = ShireMap.new()
		_shire_map.generate_default(server_config["map_width"], server_config["map_height"],
			8, server_config.get("map_seed", 12345) ^ 0x51932)
	while players.size() < 1:
		players.append({})
	players[0]   = (s["player"] as Dictionary).duplicate(true)
	citizens     = (s["citizens"] as Array).duplicate(true)
	ai_factions  = (s["ai_factions"] as Array).duplicate(true)
	wildlife     = (s["wildlife"] as Array).duplicate(true)
	campfire     = (s["campfire"] as Dictionary).duplicate(true)
	_next_building_id = int(s["next_building_id"])
	_next_unit_id     = int(s["next_unit_id"])
	_next_citizen_id  = int(s["next_citizen_id"])
	_next_animal_id   = int(s["next_animal_id"])
	_register_buildings_in_grid(players[0].get("buildings", []))
	world["grid"] = _grid.serialize()

	# Catch the seat up: while you were away the micro clock was paused, but the world-map
	# strategic clock advanced. Fast-forward your economy/construction by the days elapsed so
	# half-built works finish and the town isn't frozen at the frame you left. (Strategic layer
	# + raiders are suppressed via _catch_up_mode — they're handled by the world map.)
	var left_tick: int = int(s.get("left_at_tick", SimulationClock.current_tick))
	var elapsed_days: int = maxi(0, strategic_day() - int(s.get("left_at_day", strategic_day())))
	_catch_up_seat(left_tick, elapsed_days)
	return true

# Advance ONLY the player's seat by `elapsed_days` game-days from `start_tick`, restoring a
# continuous micro timeline for the city (independent of any spectator-clock drift). Bounded
# by CATCH_UP_MAX_DAYS so a very long absence can't lock the game on the loading frame.
func _catch_up_seat(start_tick: int, elapsed_days: int) -> void:
	SimulationClock.current_tick = start_tick
	if elapsed_days <= 0:
		return
	elapsed_days = mini(elapsed_days, CATCH_UP_MAX_DAYS)
	var total: int = elapsed_days * SimulationClock.TICKS_PER_GAME_DAY
	_catch_up_mode = true
	for i in range(1, total + 1):
		simulate_tick(start_tick + i)
	_catch_up_mode = false
	SimulationClock.current_tick = start_tick + total

# Guarantee timber within reach of the player's seat. The Woodcutter's Camp is the
# tutorial's gated step-1 build but it REQUIRES forest terrain, and forest placement is
# random — an unlucky seed could leave the start with no nearby trees, hard-stalling the
# tutorial. If the seat has too little forest within reach, plant a small grove on grass
# just outside the keep footprint so the first woodcutter is always buildable. (iter186)
func ensure_forest_near(cx: int, cy: int, reach: int = 14, want: int = 8) -> void:
	if _grid == null:
		return
	if _grid.count_terrain_in_radius(cx, cy, reach, WorldGrid.Terrain.FOREST) >= want:
		return
	# Find a grass anchor a few tiles out (clear of the 3×3 hall footprint), nearest-first.
	for r in range(4, reach + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # ring only
				var ax: int = cx + dx
				var ay: int = cy + dy
				if not _grid.in_bounds(ax, ay):
					continue
				if _grid.get_terrain(ax, ay) != WorldGrid.Terrain.GRASS:
					continue
				# Plant a compact grove around the anchor on grass tiles only.
				var planted: int = 0
				for gy in range(-2, 3):
					for gx in range(-2, 3):
						var tx: int = ax + gx
						var ty: int = ay + gy
						if _grid.in_bounds(tx, ty) and _grid.get_terrain(tx, ty) == WorldGrid.Terrain.GRASS:
							_grid.set_terrain(tx, ty, WorldGrid.Terrain.FOREST)
							# Register the new tile as a mature tree so the living forest (and the
							# woodcutter, which only fells ADULTS) recognises it.
							if _forest_rng == null:
								_forest_rng = RandomNumberGenerator.new()
							if not world.has("trees"):
								world["trees"] = {}
							world["trees"][ForestSystem.key_for(_grid, tx, ty)] = \
								[ForestSystem.ADULT, 1.0, _forest_rng.randf_range(ForestSystem.GROW_MIN, ForestSystem.GROW_MAX), 0]
							planted += 1
				if planted >= want:
					return

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
	# JSON encodes PackedByteArray/PackedFloat32Array as base64 Strings, which corrupts the
	# world_map biome (tiles/elev/territory) on load. The biome is deterministic static terrain,
	# so regenerate it from the saved seed while keeping the mutated cities/factions/kingdoms
	# (ownership/development) intact. (iter151: save/load round-trip was broken.)
	if world.has("world_map") and world["world_map"] is Dictionary and world["world_map"].has("seed"):
		var _wm: Dictionary = world["world_map"]
		var _fresh: Dictionary = WorldMapData.generate(int(_wm["seed"]))
		_wm["biome"] = _fresh["biome"]
		world["world_map"] = _wm
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
	var loaded_seed: int = int(server_config.get("map_seed", 12345))   # JSON loads ints as floats; XOR needs int
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
				var field: bool = defn.get("field", false)
				for dy in range(h):
					for dx in range(w):
						_grid.set_building_at(gx + dx, gy + dy, bid)
						_grid.set_field_at(gx + dx, gy + dy, field)

	if world.has("shires"):
		_shire_map = ShireMap.new()
		_shire_map.shires = world["shires"]
