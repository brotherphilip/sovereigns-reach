extends Node
# City simulation scene. Reads selected_city_id from GameState.world to
# configure seed and starting position. Adds "World Map" return button.
# Replaces GameBootstrap as the runtime entry for city play.

const PLAYER_NAME:          String = "Your Lord"
const DEFAULT_SEED:         int    = 42
const DEFAULT_SHIRE_COUNT:  int    = 4
const DEFAULT_KEEP_X:       int    = 100
const DEFAULT_KEEP_Y:       int    = 100
const STARTING_AREA_RADIUS: int    = 8

const CT_RESEARCH_TECH  = 25
const CT_ACTIVATE_EDICT = 16
const CT_BUY_RESOURCE   = 5
const CT_SELL_RESOURCE  = 6

const AIFactionRef = preload("res://simulation/ai/AIFaction.gd")
const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")
const EdictSystemRef = preload("res://simulation/edicts/EdictSystem.gd")

var _keep_x: int = DEFAULT_KEEP_X
var _keep_y: int = DEFAULT_KEEP_Y
var _map_seed: int = DEFAULT_SEED

var _camera:        Camera2D    = null
var _world_root:    Node2D      = null
var _iso_grid:      Node2D      = null
var _decor_layer:   Node2D      = null
var _bld_layer:     Node2D      = null
var _unit_layer:    Node2D      = null
var _animal_layer:  Node2D      = null
var _citizen_layer: Node2D      = null
var _hud:           CanvasLayer = null
var _macro_view:    CanvasLayer = null
var _input_handler: Node        = null
var _spectator:     bool        = false  # viewing another faction's city (read-only)

func _ready() -> void:
	_resolve_city()
	_init_simulation()
	_build_scene()
	_connect_signals()
	# No auto-placed buildings: the player must build a Hall (anywhere free) to begin.
	SimulationClock.set_speed(SimulationClock.SPEED_NORMAL)
	# Onboarding + King's Peace intro (only on your own seat, not when spectating a rival).
	if not _spectator:
		# Dev/headless hook: skip onboarding and lay down a basic food economy, then run at
		# top speed — an unattended on-screen survival run with real telemetry (pairs with
		# SR_TELEMETRY/SR_SHOT). Mirrors the headless TestSurvival economy on the real scene.
		if OS.get_environment("SR_AUTOPLAY") != "":
			_dev_autoplay()
		else:
			_hud.show_notification("⚜ A King's Peace shields your realm for %d days — raise farms and walls before rival houses march." % AIFactionRef.PLAYER_GRACE_DAYS, 10.0)
			_show_tutorial_choice()
	print("[CityView] Game initialized. Player: %s at (%d,%d)" % [PLAYER_NAME, _keep_x, _keep_y])

# ── City resolution ───────────────────────────────────────────────────────────

func _resolve_city() -> void:
	var city_id: int = GameState.world.get("selected_city_id", -1)
	if city_id < 0:
		return
	var city: Dictionary = GameState.get_city(city_id)
	if city.is_empty():
		return
	# Use city position (world map coords 0–1600 × 0–900) mapped to sim grid (0–200)
	# Map: world_x/MAP_WIDTH * grid_width (both default to 200)
	const WM_W: float = 1600.0; const WM_H: float = 900.0
	const SIM_W: float = 200.0; const SIM_H: float = 200.0
	_keep_x = int(clampf(city.get("pos_x", WM_W * 0.5) / WM_W * SIM_W, 10, 190))
	_keep_y = int(clampf(city.get("pos_y", WM_H * 0.5) / WM_H * SIM_H, 10, 190))
	# Each city gets a unique seed based on its id
	_map_seed = DEFAULT_SEED + city.get("id", 0) * 7

# ── Simulation init ───────────────────────────────────────────────────────────

func _init_simulation() -> void:
	var sel: int = GameState.world.get("selected_city_id", -1)
	var seat: int = GameState.world.get("player_seat_city_id", -1)
	var has_wm: bool = GameState.world.has("world_map")
	var spectating: bool = sel >= 0 and seat >= 0 and sel != seat and has_wm

	# ── Spectating a rival city: it OVERWRITES players[0] with a showcase, so first save our
	# live seat (it keeps catching up later). The seat is "displaced" until we return to it. ──
	if spectating:
		GameState.stash_seat_snapshot()
		GameState.spectator_mode = false
		_spectator = true
		GameState.setup_world(_map_seed, DEFAULT_SHIRE_COUNT)
		_snap_keep_to_buildable()
		GameState.initialize_player(0, PLAYER_NAME, _keep_x, _keep_y)
		GameState.enter_spectator_city(sel, _keep_x, _keep_y, _map_seed)
		GameState.world["seat_displaced"] = true
		return

	# ── Our own seat. ──
	GameState.spectator_mode = false
	_spectator = false

	# Returning to an established seat. The single autoload clock never pauses now, so while we
	# were on the world map the seat kept ticking LIVE in the background — just keep it. The
	# ONLY time it needs restoring is after a spectator detour displaced players[0].
	if GameState.world.get("seat_established", false):
		if GameState.world.get("seat_displaced", false):
			GameState.restore_seat_snapshot()
			GameState.world["seat_displaced"] = false
		var rp: Dictionary = GameState.players[0]
		_keep_x = int(rp.get("keep_x", _keep_x))
		_keep_y = int(rp.get("keep_y", _keep_y))
		return

	# ── First entry: build the seat from scratch. ──
	GameState.setup_world(_map_seed, DEFAULT_SHIRE_COUNT)
	# No cleared "starting zone": just spawn the player on nearby buildable land so
	# their first Hall can be placed. No terrain is altered.
	_snap_keep_to_buildable()
	GameState.initialize_player(0, PLAYER_NAME, _keep_x, _keep_y)
	# Lean start: you begin a small village and must EARN materials before you can build
	# much (gather/trade first). Enough for the Village Hall + a first food building only.
	var p: Dictionary = GameState.players[0]
	p["gold"]                   = 120
	p["prestige"]               = 0
	p["resources"]["wood"]      = 60
	p["resources"]["stone"]     = 15
	p["resources"]["iron"]      = 0
	p["food"]["apples"]         = 90    # a few days' buffer — set up food before it runs out
	p["population"]             = 20
	if seat < 0 and sel >= 0 and has_wm:
		GameState.world["player_seat_city_id"] = sel
	# Your own seat: rival raiders may still threaten it.
	GameState.add_ai_faction("bandit_king",   20,  20)
	GameState.add_ai_faction("ashen_barony", 180, 180)
	# Guarantee timber near the seat so the tutorial's gated step-1 Woodcutter's Camp
	# (which needs forest terrain) is always buildable, whatever the seed rolled.
	GameState.ensure_forest_near(_keep_x, _keep_y)
	GameState.world["seat_established"] = true
	GameState.world["seat_displaced"] = false

# Move the start position to the nearest buildable (grass/valley) tile so the
# player's first Hall can be placed there — without clearing any terrain.
func _snap_keep_to_buildable() -> void:
	const GRASS := 0
	const VALLEY := 7
	if GameState.get_terrain_at(_keep_x, _keep_y) in [GRASS, VALLEY]:
		return
	for radius in range(1, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue   # ring only
				var x: int = _keep_x + dx
				var y: int = _keep_y + dy
				if GameState.grid_in_bounds(x, y) and GameState.get_terrain_at(x, y) in [GRASS, VALLEY]:
					_keep_x = x
					_keep_y = y
					return

# ── Scene tree ────────────────────────────────────────────────────────────────

func _build_scene() -> void:
	_camera = preload("res://view/micro/CameraController.gd").new()
	_camera.name     = "Camera"
	_camera.position = _iso_origin(_keep_x, _keep_y)
	add_child(_camera)

	_world_root = Node2D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)

	_iso_grid = preload("res://view/micro/IsometricGrid.gd").new()
	_iso_grid.name = "IsometricGrid"
	_world_root.add_child(_iso_grid)
	_iso_grid.set_camera(_camera)

	# Animated river/water surface (light GPU-driven flow shader over water tiles).
	var water_layer := preload("res://view/micro/WaterFlowLayer.gd").new()
	water_layer.name = "WaterFlowLayer"
	_world_root.add_child(water_layer)

	# Terrain decoration layer (trees, rocks, water ripples)
	_decor_layer = preload("res://view/micro/TerrainDecorationLayer.gd").new()
	_decor_layer.name = "DecorationLayer"
	_world_root.add_child(_decor_layer)
	_decor_layer.set_camera(_camera)

	_bld_layer = preload("res://view/micro/BuildingLayer.gd").new()
	_bld_layer.name = "BuildingLayer"
	_world_root.add_child(_bld_layer)

	_unit_layer = preload("res://view/micro/UnitLayer.gd").new()
	_unit_layer.name = "UnitLayer"
	_world_root.add_child(_unit_layer)

	# Arrows/bolts/stones fly over the units when ranged troops loose a volley.
	var projectile_layer := preload("res://view/micro/ProjectileLayer.gd").new()
	projectile_layer.name = "ProjectileLayer"
	_world_root.add_child(projectile_layer)

	_animal_layer = preload("res://view/micro/AnimalLayer.gd").new()
	_animal_layer.name = "AnimalLayer"
	_world_root.add_child(_animal_layer)

	var campfire_layer := preload("res://view/micro/CampfireLayer.gd").new()
	campfire_layer.name = "CampfireLayer"
	_world_root.add_child(campfire_layer)

	_citizen_layer = preload("res://view/micro/CitizenLayer.gd").new()
	_citizen_layer.name = "CitizenLayer"
	_world_root.add_child(_citizen_layer)

	# Day/night lighting — drawn last so it sits over the world. The darkening wash first,
	# then the ADDITIVE building lights on top so lamps genuinely brighten the night.
	var night_layer := preload("res://view/micro/NightLayer.gd").new()
	night_layer.name = "NightLayer"
	_world_root.add_child(night_layer)
	var lamp_layer := preload("res://view/micro/NightLampLayer.gd").new()
	lamp_layer.name = "NightLampLayer"
	_world_root.add_child(lamp_layer)

	_hud = preload("res://view/hud/HUDNode.gd").new()
	_hud.name  = "HUD"
	_hud.layer = 10
	add_child(_hud)

	_add_minimap()

	_macro_view = CanvasLayer.new()
	_macro_view.name  = "MacroView"
	_macro_view.layer = 5
	add_child(_macro_view)
	var macro_ctrl := preload("res://view/macro/MacroMapView.gd").new()
	macro_ctrl.name = "MacroMapControl"
	macro_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	macro_ctrl.visible = false
	_macro_view.add_child(macro_ctrl)

	_input_handler = preload("res://view/main/PlayerInputHandler.gd").new()
	_input_handler.name = "InputHandler"
	add_child(_input_handler)
	_input_handler.setup(_iso_grid, _camera, _unit_layer)
	# Spectator view is read-only: no building placement.
	if not _spectator:
		_input_handler.set_building_layer(_bld_layer)
	_input_handler.set_animal_layer(_animal_layer)

	# "World Map" return button (added to a small persistent overlay)
	_add_world_map_button()

	if _spectator:
		_add_spectator_banner()

	# Dev/headless hook: spawn a showcase army + an approaching enemy warband to
	# verify unit bodies, animations, pathfinding and auto-combat in the real game.
	if OS.get_environment("SR_SPAWN_UNITS") != "":
		_dev_spawn_units()
	# Dev/headless hook: a staffed town to verify job workers walking to buildings.
	if OS.get_environment("SR_WORKERS") != "":
		_dev_spawn_workers()
	# Dev hook: pop the "20 minutes reached" reign-milestone overlay shortly after boot.
	if OS.get_environment("SR_REIGN") != "":
		_dev_reign_preview()
	var SeasonRef = preload("res://simulation/world/SeasonSystem.gd")
	# Dev hook: jump the calendar to a chosen season (0=spring 1=summer 2=autumn 3=winter).
	# Sets the live season DIRECTLY + repaints — the preview clock may not advance a whole
	# game-day, so the simulate_tick season-propagation (GameState) wouldn't otherwise fire.
	# Also parks current_tick at noon of that season's first day so the HUD/sim agree.
	if OS.get_environment("SR_SEASON") != "":
		var s: int = clampi(int(OS.get_environment("SR_SEASON")), 0, SeasonRef.SEASON_COUNT - 1)
		SimulationClock.current_tick = s * SeasonRef.DAY_NIGHT_TICKS * SeasonRef.SKY_DAYS_PER_SEASON
		GameState.world["season"] = s
		GameState.world["season_day"] = SeasonRef.sky_day_of(SimulationClock.current_tick)
		GameState.world.erase("calendar_offset_ticks")
		if EventBus.has_signal("season_changed"):
			EventBus.season_changed.emit(s, SeasonRef.season_name(s))
	# Dev hook: jump the time-of-day to deepest night (for lighting previews). 1.0 = midnight.
	# Preserves the season set above by moving only WITHIN the current day.
	if OS.get_environment("SR_NIGHT") != "":
		var nf: float = clampf(float(OS.get_environment("SR_NIGHT")), 0.0, 1.0)
		var day_start: int = (SimulationClock.current_tick / SeasonRef.DAY_NIGHT_TICKS) * SeasonRef.DAY_NIGHT_TICKS
		SimulationClock.current_tick = day_start + int(round(nf * 0.5 * SeasonRef.DAY_NIGHT_TICKS))
	# Dev hook: append a real game-state telemetry row (~1/sec) to the SR_TELEMETRY CSV, so a
	# live playtest yields an HONEST state-over-time capture (day, popularity, gold, food, unit
	# & building counts, FPS) read straight from the running sim — not guessed from screenshots.
	if OS.get_environment("SR_TELEMETRY") != "":
		_dev_telemetry(OS.get_environment("SR_TELEMETRY"))
	# Dev hook: render for SR_SHOT_DELAY seconds then save a PNG to SR_SHOT and quit.
	if OS.get_environment("SR_SHOT") != "":
		_dev_screenshot(OS.get_environment("SR_SHOT"))

func _dev_telemetry(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[CityView] SR_TELEMETRY: cannot open %s" % path)
		return
	f.store_line("real_s,game_day,popularity,gold,food,units,buildings,fps,siege_ready,hall_hp,defense_built,population")
	f.flush()
	var HUDCtl = preload("res://view/hud/HUDController.gd")
	var BReg = preload("res://simulation/buildings/BuildingRegistry.gd")
	var t0: int = Time.get_ticks_msec()
	var timer := Timer.new()
	timer.name = "SR_TelemetryTimer"
	timer.wait_time = 1.0
	timer.one_shot = false
	add_child(timer)
	timer.timeout.connect(func() -> void:
		if GameState.players.is_empty():
			return
		var p: Dictionary = GameState.players[0]
		var real_s: float = float(Time.get_ticks_msec() - t0) / 1000.0
		var hall_hp: int = 0
		var defense_built: int = 0
		for b in p.get("buildings", []):
			if not b is Dictionary:
				continue
			var bt: String = String(b.get("type", ""))
			if bt in ["village_hall", "keep"]:
				hall_hp = maxi(hall_hp, int(b.get("hp", 0)))
			if b.get("built", false) and int(BReg.lookup(bt).get("category", -1)) == BReg.Category.DEFENSE:
				defense_built += 1
		var siege_ready: int = 1 if GameState.is_siege_ready(p) else 0
		f.store_line("%.1f,%d,%.1f,%d,%d,%d,%d,%.0f,%d,%d,%d,%d" % [
			real_s, SimulationClock.game_day(),
			float(p.get("popularity", 50.0)), int(p.get("gold", 0)),
			HUDCtl.get_total_food(p), (p.get("units", []) as Array).size(),
			(p.get("buildings", []) as Array).size(), Engine.get_frames_per_second(),
			siege_ready, hall_hp, defense_built, int(p.get("population", 0))])
		f.flush()
	)
	timer.start()
	print("[CityView] SR_TELEMETRY writing to %s" % path)

func _dev_reign_preview() -> void:
	await get_tree().create_timer(2.0).timeout
	_show_reign_milestone(12)

func _dev_screenshot(path: String) -> void:
	var delay: float = 12.0
	if OS.get_environment("SR_SHOT_DELAY") != "":
		delay = float(OS.get_environment("SR_SHOT_DELAY"))
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[CityView] screenshot saved: %s" % path)
	get_tree().quit()

# Dev-only: lay down a hall + basic food economy (built, grid-registered, staffed) around
# the keep and run at top speed, so the real CityViewScene survives unattended on-screen
# (verify the view/HUD/sim loop, not just the headless logic in TestSurvival).
func _dev_autoplay() -> void:
	var BState = preload("res://simulation/buildings/BuildingState.gd")
	var BReg = preload("res://simulation/buildings/BuildingRegistry.gd")
	GameState.prepare_starting_area(_keep_x, _keep_y, 16)
	# Hall (the seat) + a food economy that the headless 100-day test proved sustains a realm.
	var plan := [
		["village_hall", 0, 0], ["granary", -3, 0],
		["apple_orchard", 3, 0], ["apple_orchard", 3, 2], ["apple_orchard", 3, -2],
		["wheat_farm", -3, 3], ["woodcutter_camp", 0, 4],
	]
	for item in plan:
		var defn: Dictionary = BReg.lookup(item[0])
		var gx: int = clampi(_keep_x + int(item[1]), 2, 196)
		var gy: int = clampi(_keep_y + int(item[2]), 2, 196)
		var b: Dictionary = BState.create(item[0], 0, gx, gy, GameState._next_building_id)
		if b.is_empty():
			continue
		GameState._next_building_id += 1
		b["built"] = true
		b["workers"] = defn.get("max_workers", 1)
		GameState.players[0]["buildings"].append(b)
		var w: int = defn.get("width", 1); var h: int = defn.get("height", 1)
		var field: bool = defn.get("field", false)
		for dy in range(h):
			for dx in range(w):
				if GameState._grid != null:
					GameState._grid.set_building_at(gx + dx, gy + dy, b["id"])
					GameState._grid.set_field_at(gx + dx, gy + dy, field)
	# Initial stockpile beside the hall (iter183) + a regular one, and some raw stock so the
	# pile visuals (iter184) are visible for inspection.
	GameState._spawn_initial_stockpile(GameState.players[0], _keep_x, _keep_y)
	var sx2: int = clampi(_keep_x - 6, 2, 196); var sy2: int = clampi(_keep_y + 2, 2, 196)
	var sb2: Dictionary = BState.create("stockpile", 0, sx2, sy2, GameState._next_building_id)
	GameState._next_building_id += 1
	sb2["built"] = true
	GameState.players[0]["buildings"].append(sb2)
	if GameState._grid != null:
		GameState._grid.set_building_at(sx2, sy2, sb2["id"])
	GameState.players[0]["resources"]["wood"] = 250
	GameState.players[0]["resources"]["stone"] = 120
	# A standing garrison so the realm can survive the post-grace sieges (a food-only,
	# defenceless seat loses its keep ~day 72 — verified iter158; defenders are needed).
	var US = preload("res://simulation/units/UnitState.gd")
	var garrison := ["swordsman", "swordsman", "archer", "archer", "pikeman", "militia",
		"swordsman", "archer", "pikeman", "militia", "crossbowman", "captain"]
	for i in garrison.size():
		var gx: int = clampi(_keep_x - 3 + (i % 4) * 2, 2, 196)
		var gy: int = clampi(_keep_y - 3 + (i / 4) * 2, 2, 196)
		GameState.players[0]["units"].append(US.create(garrison[i], 0, gx, gy, GameState._next_unit_id))
		GameState._next_unit_id += 1
	SimulationClock.set_speed(SimulationClock.SPEED_FASTEST)
	print("[CityView] SR_AUTOPLAY: seeded economy + %d-unit garrison, running at top speed" % garrison.size())

func _dev_spawn_workers() -> void:
	var BState = preload("res://simulation/buildings/BuildingState.gd")
	var BReg = preload("res://simulation/buildings/BuildingRegistry.gd")
	GameState.prepare_starting_area(_keep_x, _keep_y, 16)
	# A ring of staffed worker-buildings of varied trades around the keep. Includes the
	# civic "hero" types (hall/keep/inn/mill) so the design-overhaul pass can inspect them.
	var types := ["apple_orchard", "wheat_farm", "woodcutter_camp", "blacksmith",
		"brewery", "bakery", "church", "watchtower", "iron_mine", "market",
		"village_hall", "keep", "inn", "mill"]
	var n := types.size()
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		var defn: Dictionary = BReg.lookup(types[i])
		var gx: int = clampi(_keep_x + int(round(cos(ang) * 12.0)), 2, 196)
		var gy: int = clampi(_keep_y + int(round(sin(ang) * 12.0)), 2, 196)
		var b: Dictionary = BState.create(types[i], 0, gx, gy, GameState._next_building_id)
		GameState._next_building_id += 1
		b["built"] = true
		b["workers"] = defn.get("max_workers", 1)
		GameState.players[0]["buildings"].append(b)
		var w: int = defn.get("width", 1); var h: int = defn.get("height", 1)
		var field: bool = defn.get("field", false)
		for dy in range(h):
			for dx in range(w):
				if GameState._grid != null:
					GameState._grid.set_building_at(gx + dx, gy + dy, b["id"])
					GameState._grid.set_field_at(gx + dx, gy + dy, field)
	# Three ADJACENT orchards (the reported glitch scenario) to verify workers
	# path around the cluster and don't jam on the shared edges.
	for k in range(3):
		var ogx: int = clampi(_keep_x - 12 + k * 2, 2, 196)
		var ogy: int = clampi(_keep_y + 6, 2, 196)
		var ob: Dictionary = BState.create("apple_orchard", 0, ogx, ogy, GameState._next_building_id)
		GameState._next_building_id += 1
		ob["built"] = true
		ob["workers"] = 2
		GameState.players[0]["buildings"].append(ob)
		for dy in range(2):
			for dx in range(2):
				if GameState._grid != null:
					GameState._grid.set_building_at(ogx + dx, ogy + dy, ob["id"])
					GameState._grid.set_field_at(ogx + dx, ogy + dy, true)
	# Plenty of villager stock to staff them all.
	GameState.citizens = []
	GameState._next_citizen_id = 1
	GameState._next_citizen_id = preload("res://simulation/world/CitizenSystem.gd").spawn(
		GameState.citizens, 40, float(_keep_x), float(_keep_y), GameState._citizen_rng, GameState._next_citizen_id)

func _dev_spawn_units() -> void:
	var US = preload("res://simulation/units/UnitState.gd")
	GameState.prepare_starting_area(_keep_x, _keep_y, 18)
	var types := [
		"peasant","scout","monk","merchant","settler",
		"armed_peasant","archer","ladderman","tunneler","militia",
		"crossbowman","pikeman","swordsman","captain","halberdier",
		"battering_ram","catapult","trebuchet","siege_tower","mantlet",
	]
	# Tidy 5-wide block of every type, west of the keep.
	for i in types.size():
		var gx: int = _keep_x - 10 + (i % 5) * 2
		var gy: int = _keep_y - 4 + (i / 5) * 2
		var u: Dictionary = US.create(types[i], 0, gx, gy, GameState._next_unit_id)
		GameState._next_unit_id += 1
		GameState.players[0]["units"].append(u)
	# A small enemy warband to the east — they will deploy, march in and be fought.
	if GameState.ai_factions.is_empty():
		GameState.add_ai_faction("bandit_king", _keep_x + 14, _keep_y)
	var fac: Dictionary = GameState.ai_factions[0]
	for j in range(6):
		var ex: int = _keep_x + 13 + (j % 3)
		var ey: int = _keep_y - 2 + (j / 3) * 2
		var foe_type: String = ["armed_peasant", "archer", "militia"][j % 3]
		fac["units"].append(US.create(foe_type, fac.get("id", 0), ex, ey, fac.get("id", 0) * 10000 + 500 + j))
	# SR_SPAWN_UNITS=march → send the showcase on a long cross-terrain march so we
	# can watch them wade water, slow through forest, route around mountains, and
	# never freeze (auto-unstick). Formation spread fans them out.
	if OS.get_environment("SR_SPAWN_UNITS") == "march":
		var tgtx: int = clampi(_keep_x + 30, 2, 197)
		var tgty: int = clampi(_keep_y + 24, 2, 197)
		for u in GameState.players[0].get("units", []):
			GameState._cmd_issue_move_order({"player_id": 0, "payload":
				{"unit_id": u.get("id"), "target_x": tgtx, "target_y": tgty}})

func _add_spectator_banner() -> void:
	var overlay := CanvasLayer.new()
	overlay.name  = "SpectatorBanner"
	overlay.layer = 11
	add_child(overlay)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO: vp = Vector2(1280, 720)

	var city: Dictionary = GameState.get_city(GameState.world.get("selected_city_id", -1))
	var wm: Dictionary = GameState.world.get("world_map", {})
	var owner_fid: int = city.get("owner_faction_id", city.get("faction_id", -1))
	var fac_name: String = "Unclaimed"
	var fac_col := Color(0.85, 0.78, 0.55)
	for f in wm.get("factions", []):
		if f is Dictionary and f.get("id", -1) == owner_fid:
			fac_name = f.get("name", fac_name)
			fac_col = Color.from_string(f.get("color_hex", "#888888"), fac_col)
			break
	var dev: int = int(city.get("development", city.get("tier", 0)))
	var garrison: int = int(city.get("garrison", 0))

	var panel := Panel.new()
	panel.position = Vector2(vp.x * 0.5 - 230, 8)
	panel.size     = Vector2(460, 40)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.10, 0.07, 0.9)
	sty.set_border_width_all(2)
	sty.border_color = fac_col
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	overlay.add_child(panel)

	var lbl := Label.new()
	lbl.text = "👁 Viewing %s — %s  ·  Development %d  ·  ⚔ %d garrison" % [
		city.get("name", "City"), fac_name, dev, garrison]
	lbl.position = Vector2(0, 0)
	lbl.size     = Vector2(460, 40)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.93, 0.86, 0.64))
	panel.add_child(lbl)

	# Under-siege strip: if a hostile host is at this city's gates (besiegers spawned in
	# GameState._spawn_spectator_military), call it out so the visible attackers make sense.
	if bool(GameState.world.get("spectator_under_siege", false)):
		var besiegers: int = 0
		for f in GameState.ai_factions:
			besiegers += f.get("units", []).size()
		var siege_panel := Panel.new()
		siege_panel.position = Vector2(vp.x * 0.5 - 230, 50)
		siege_panel.size     = Vector2(460, 30)
		var ssty := StyleBoxFlat.new()
		ssty.bg_color = Color(0.16, 0.05, 0.04, 0.92)
		ssty.set_border_width_all(2)
		ssty.border_color = Color(0.85, 0.32, 0.22)
		ssty.set_corner_radius_all(6)
		siege_panel.add_theme_stylebox_override("panel", ssty)
		overlay.add_child(siege_panel)
		var slbl := Label.new()
		slbl.text = "⚔ Under siege by %s — %d besiegers at the gates!" % [
			String(GameState.world.get("spectator_besieger_name", "a rival host")), besiegers]
		slbl.size = Vector2(460, 30)
		slbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		slbl.add_theme_font_size_override("font_size", 13)
		slbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
		siege_panel.add_child(slbl)

func _add_minimap() -> void:
	var overlay := CanvasLayer.new()
	overlay.name  = "MinimapLayer"
	overlay.layer = 9
	add_child(overlay)
	var minimap := preload("res://view/micro/Minimap.gd").new()
	minimap.name = "Minimap"
	minimap.position = Vector2(4, 4)
	minimap.set_camera(_camera)
	overlay.add_child(minimap)

func _add_world_map_button() -> void:
	var overlay := CanvasLayer.new()
	overlay.name  = "WorldMapOverlay"
	overlay.layer = 8
	add_child(overlay)
	var btn := Button.new()
	btn.text     = "World Map"
	btn.position = Vector2(4, 200)
	btn.size     = Vector2(90, 28)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_on_return_to_world_map)
	overlay.add_child(btn)

func _iso_origin(gx: int, gy: int) -> Vector2:
	return Vector2((gx - gy) * 32.0, (gx + gy) * 16.0)

# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_hud.build_requested.connect(_input_handler.enter_build_mode)
	_hud.tax_changed.connect(_input_handler.set_tax_rate)
	_hud.food_ration_changed.connect(_input_handler.set_food_ration)
	_hud.ale_ration_changed.connect(_input_handler.set_ale_ration)
	_hud.speed_changed.connect(_input_handler.set_game_speed)
	_hud.save_requested.connect(_input_handler.save_game)
	_hud.recruit_requested.connect(_input_handler.recruit_unit)
	_hud.macro_view_toggled.connect(_toggle_macro_view)
	_hud.tech_research_requested.connect(_on_research_tech)
	_hud.edict_activate_requested.connect(_on_activate_edict)
	_hud.trade_buy_requested.connect(_on_trade_buy)
	_hud.trade_sell_requested.connect(_on_trade_sell)

	_input_handler.build_mode_changed.connect(_hud.set_build_mode_display)
	_input_handler.placement_failed.connect(func(r): _hud.show_notification("Cannot build: " + r))
	_input_handler.entity_selected.connect(_on_entity_selected)
	_input_handler.entity_deselected.connect(func(): _hud.clear_selection())

	EventBus.weather_changed.connect(func(name, _d): _hud.show_notification("Weather: " + name, 4.0))
	EventBus.building_placement_failed.connect(func(_p, _b, _gx, _gy, reason): _hud.show_notification(reason, 3.0))
	EventBus.ai_siege_assembling.connect(_on_ai_siege_assembling)
	EventBus.ai_siege_struck.connect(_on_ai_siege_struck)
	EventBus.unit_killed.connect(_on_unit_killed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.ai_faction_defeated.connect(_on_ai_faction_defeated)
	EventBus.popularity_changed.connect(_on_popularity_changed)
	EventBus.edict_activated.connect(_on_edict_activated)
	EventBus.edict_expired.connect(_on_edict_expired)
	EventBus.save_requested.connect(_do_save)
	EventBus.load_requested.connect(_do_load)

	# Onboarding hints (the real runtime entry — GameBootstrap is unused here).
	TutorialSystem.tutorial_hint.connect(func(msg: String): _hud.show_notification("📖 " + msg, 9.0))
	# Realm events — flavourful daily happenings surfaced in the notification feed.
	# (Choice events are handled by the EventChoicePanel instead; see _on_world_event.)
	EventBus.world_event.connect(_on_world_event)
	# The 20-minute goal reached — a triumphant (dismissible) moment.
	EventBus.sovereign_reign_reached.connect(_show_reign_milestone)
	# Feudal climb: each promotion is a beat; reaching King wins the game.
	EventBus.title_promoted.connect(_on_title_promoted)
	# Strategic defeat: driven from your last holding.
	EventBus.player_realm_lost.connect(func():
		_show_game_over(false, "Your last holding has fallen. Your domain is no more."))
	EventBus.realm_notice.connect(func(text: String, tone: String):
		var c: Color = Color(0.55, 0.9, 0.45) if tone == "good" else (Color(1.0, 0.5, 0.4) if tone == "bad" else Color(0.95, 0.85, 0.45))
		_hud.show_notification("📜 " + text, 7.0, c))
	# A unit that finished its training at the barracks is now ready for battle.
	EventBus.unit_spawned.connect(func(unit: Dictionary):
		if unit.get("owner_id", -1) == 0:
			var nm: String = UnitRegistry.lookup(unit.get("type", "")).get("name", unit.get("type", "soldier"))
			_hud.show_notification("⚔ %s is trained and ready for battle." % nm, 5.0, Color(0.6, 0.85, 1.0)))

	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_macro_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()

var _pause_menu: CanvasLayer = null
var _speed_before_pause: int = SimulationClock.SPEED_NORMAL

# ESC pause menu: pauses the sim and offers Resume / Save / World Map / Main Menu / Quit.
func _toggle_pause_menu() -> void:
	if _pause_menu != null:
		_close_pause_menu()
		return
	_speed_before_pause = SimulationClock.game_speed
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)
	_pause_menu = CanvasLayer.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.layer = 50
	add_child(_pause_menu)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(490, 140)
	panel.size = Vector2(300, 450)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.10, 0.07, 0.98)
	sty.set_border_width_all(2)
	sty.border_color = Color(0.62, 0.49, 0.22, 0.95)
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	_pause_menu.add_child(panel)
	var title := Label.new()
	title.text = "⚔  Paused"
	title.position = Vector2(0, 16); title.size = Vector2(300, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.97, 0.85, 0.42))
	panel.add_child(title)
	# Audio mixer (persists via MusicPlayer settings) — Master / Music / SFX, so the player
	# tunes the whole mix to taste (the user's "not overwhelming" requirement, in their hands).
	var mp = get_node_or_null("/root/MusicPlayer")
	var sy: float = 52.0
	if mp != null:
		var rows: Array = [
			["⚙ Master", mp.get_master_volume_db(), func(db): mp.set_master_volume_db(db)],
			["♪ Music",  mp.get_music_volume_db(),  func(db): mp.set_music_volume_db(db)],
			["⚔ SFX",    mp.get_sfx_volume_db(),    func(db): mp.set_sfx_volume_db(db)],
		]
		for row in rows:
			var lbl := Label.new()
			lbl.position = Vector2(40, sy); lbl.size = Vector2(220, 18)
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color(0.86, 0.82, 0.62))
			var cur: float = clampf(float(row[1]), mp.MUSIC_DB_MIN, 0.0)
			lbl.text = "%s: %s" % [row[0], ("Off" if cur <= mp.MUSIC_DB_MIN + 0.5 else "%d dB" % int(round(cur)))]
			panel.add_child(lbl)
			var sl := HSlider.new()
			sl.position = Vector2(40, sy + 18.0); sl.size = Vector2(220, 16)
			sl.min_value = mp.MUSIC_DB_MIN; sl.max_value = 0.0; sl.step = 1.0
			sl.value = cur
			var setter: Callable = row[2]
			var name0: String = row[0]
			sl.value_changed.connect(func(v: float):
				setter.call(mp.MUTE_DB if v <= mp.MUSIC_DB_MIN + 0.5 else v)
				lbl.text = "%s: %s" % [name0, ("Off" if v <= mp.MUSIC_DB_MIN + 0.5 else "%d dB" % int(round(v)))])
			panel.add_child(sl)
			sy += 40.0
	var items: Array = [
		["Resume", func(): _close_pause_menu()],
		["Save Game", func(): _do_save(); _hud.show_notification("Game saved.", 3.0, Color(0.6, 0.9, 0.5)); _close_pause_menu()],
		["World Map", func(): _close_pause_menu(); _on_return_to_world_map()],
		["Main Menu", func(): get_tree().change_scene_to_file("res://view/menu/MainMenuScene.tscn")],
		["Quit Game", func(): get_tree().quit()],
	]
	var y: float = sy + 8.0
	for it in items:
		var b := Button.new()
		b.text = String(it[0])
		b.position = Vector2(40, y); b.size = Vector2(220, 38)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(it[1])
		panel.add_child(b)
		y += 46.0

func _close_pause_menu() -> void:
	if _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null
		SimulationClock.set_speed(_speed_before_pause)

func _toggle_macro_view() -> void:
	var ctrl := _macro_view.get_node_or_null("MacroMapControl")
	if ctrl: ctrl.visible = not ctrl.visible

func _on_world_event(ev: Dictionary) -> void:
	# Choice events are shown by the EventChoicePanel as a decision popup, not here.
	if ev.get("choices", []) is Array and not (ev.get("choices", []) as Array).is_empty():
		return
	var tone: String = ev.get("tone", "neutral")
	var col: Color = Color(0.55, 0.9, 0.45) if tone == "good" else (Color(1.0, 0.5, 0.4) if tone == "bad" else Color(0.95, 0.85, 0.45))
	var icon: String = "✨" if tone == "good" else ("⚠" if tone == "bad" else "🕊")
	var summary: String = ev.get("summary", "")
	var tail: String = ("  (%s)" % summary) if summary != "" else ""
	_hud.show_notification("%s %s — %s%s" % [icon, ev.get("title", "An event"), ev.get("text", ""), tail], 8.0, col)

func _on_entity_selected(entity_type: String, entity_data: Dictionary) -> void:
	match entity_type:
		"building": _hud.show_selected_building(entity_data)
		"unit":     _hud.show_selected_unit(entity_data)

func _on_research_tech(tech_id: String) -> void:
	# Feedback comes from GameState on success (EventBus.realm_notice — readable name +
	# what it unlocked), so no redundant raw-id "Researching: crop_tiers" notice here.
	CommandQueue.enqueue(CT_RESEARCH_TECH, {"tech_id": tech_id}, 0)

func _on_activate_edict(edict_id: String) -> void:
	# Feedback comes from the authoritative EventBus.edict_activated (only fires on
	# success), so no optimistic raw-id notice here — see _on_edict_activated.
	CommandQueue.enqueue(CT_ACTIVATE_EDICT, {"edict_id": edict_id}, 0)

func _on_edict_activated(_pid: int, edict_id: String, _dur) -> void:
	var nm: String = EdictSystemRef.lookup(edict_id).get("name", edict_id)
	_hud.show_notification("📜 Edict proclaimed: " + nm, 3.0, Color(1.0, 0.9, 0.5))

func _on_edict_expired(_pid: int, edict_id: String) -> void:
	var nm: String = EdictSystemRef.lookup(edict_id).get("name", edict_id)
	_hud.show_notification("📜 Edict lapsed: " + nm, 3.0)

func _on_trade_buy(resource: String, amount: int) -> void:
	# Feedback comes from the authoritative EventBus.realm_notice (only after the trade is
	# actually resolved — success with the real cost, or the failure reason), so no optimistic
	# "Bought X" notice here that would lie when the buy is refused (embargo/no gold/no market).
	CommandQueue.enqueue(CT_BUY_RESOURCE, {"resource": resource, "amount": amount}, 0)

func _on_trade_sell(resource: String, amount: int) -> void:
	CommandQueue.enqueue(CT_SELL_RESOURCE, {"resource": resource, "amount": amount}, 0)

# ── Navigation ────────────────────────────────────────────────────────────────

func _on_return_to_world_map() -> void:
	# If we were spectating a rival, restore our seat so it resumes ticking LIVE on the map
	# (players[0] is the showcase while spectating; the real seat is in the snapshot).
	if GameState.spectator_mode or GameState.world.get("seat_displaced", false):
		GameState.restore_seat_snapshot()
		GameState.world["seat_displaced"] = false
	GameState.spectator_mode = false
	# Do NOT pause: the single autoload clock keeps advancing the seat economy AND the
	# strategic layer in the background, so the world never freezes while you're on the map.
	SimulationClock.set_speed(SimulationClock.SPEED_NORMAL)
	get_tree().change_scene_to_file("res://view/worldmap/WorldMapScene.tscn")

# ── Combat / win-loss handlers ────────────────────────────────────────────────

func _on_ai_siege_assembling(faction_id: int, _target_player_id: int, eta_ticks: int) -> void:
	if _hud == null: return
	var who: String = GameState.get_faction_display_name(faction_id)
	var days: int = maxi(1, int(round(float(eta_ticks) / 240.0)))
	var ready: bool = GameState.players.size() > 0 and GameState.is_siege_ready(GameState.players[0])
	if ready:
		_hud.show_notification("⚠ %s is marshalling a siege against your seat — ready in ~%d days. Your walls and garrison steady the people's nerve." % [who, days], 9.0, Color(1.0, 0.8, 0.3))
	else:
		_hud.show_notification("⚠ %s is marshalling a siege against your seat — ready in ~%d days. Raise walls, towers and a garrison before it lands!" % [who, days], 9.0, Color(1.0, 0.55, 0.2))

# The siege lands. A prepared seat shrugs off most of it; an undefended one is gutted —
# loud, clear feedback so the player feels the payoff (or cost) of their defences.
func _on_ai_siege_struck(faction_id: int, _target_player_id: int, defended: bool, damage: int) -> void:
	if _hud == null: return
	var who: String = GameState.get_faction_display_name(faction_id)
	if defended:
		_hud.show_notification("🛡 %s's siege breaks on your walls — your seat holds (only %d damage)." % [who, damage], 7.0, Color(0.6, 0.9, 0.5))
	else:
		_hud.show_notification("💥 %s storms your undefended seat — %d damage! Raise walls and a garrison before the next assault." % [who, damage], 9.0, Color(1.0, 0.4, 0.3))

func _on_unit_killed(unit_id: int, _killer_id: int, cause: String) -> void:
	if GameState.players.size() == 0: return
	for unit in GameState.players[0].get("units", []):
		if unit is Dictionary and unit.get("id", -1) == unit_id:
			_hud.show_notification("Unit lost: %s (%s)" % [unit.get("type", "?"), cause], 3.0)
			return

func _on_building_destroyed(player_id: int, building_id: int, _cause: String) -> void:
	if player_id != 0 or GameState.players.size() == 0: return
	for bld in GameState.players[0].get("buildings", []):
		if bld is Dictionary and bld.get("id", -1) == building_id:
			var btype: String = bld.get("type", "")
			_hud.show_notification("Building destroyed: %s!" % btype, 4.0)
			if btype == "village_hall" or btype == "keep":
				_show_game_over(false, "Your keep has fallen! The realm is lost.")
			return

func _on_ai_faction_defeated(faction_id: int) -> void:
	var who: String = GameState.get_faction_display_name(faction_id)
	_hud.show_notification("⚔ %s has been vanquished!" % who, 6.0, Color(1.0, 0.85, 0.2))
	var all_dead: bool = true
	for fac in GameState.ai_factions:
		if fac is Dictionary and fac.get("is_alive", true):
			all_dead = false; break
	if all_dead and GameState.ai_factions.size() > 0:
		_show_game_over(true, "All enemies vanquished! Sovereign's Reach is yours!")

func _on_popularity_changed(_pid: int, _old: float, new_val: float) -> void:
	if new_val < 10.0:
		_show_game_over(false, "The people have revolted! Your reign is over.")

# The player's derived feudal title rose. Each step is a milestone toast; reaching the
# top title (King) is the victory condition for the "work your way up" campaign.
func _on_title_promoted(_title_index: int, title_name: String) -> void:
	if _hud != null:
		_hud.show_notification("👑 You have risen to %s!" % title_name, 7.0, Color(1.0, 0.85, 0.3))
	if title_name == "King":
		_show_game_over(true, "You have risen to KING — the realm is yours!")

var _game_over_shown: bool = false

var _reign_celebrated_shown: bool = false

# On entering your seat, offer a choice: take the guided tutorial (enemy AI paused) or
# skip straight to free play. Honours a decision already made in a prior session.
func _show_tutorial_choice() -> void:
	var saved: int = GameState.world.get("tutorial_index", -999)
	if saved != -999 and saved != -1:
		TutorialSystem.start()   # resume an in-progress/finished tutorial silently
		return
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)
	var overlay := CanvasLayer.new()
	overlay.name = "TutorialChoice"
	overlay.layer = 40
	add_child(overlay)
	var panel := Panel.new()
	panel.position = Vector2(440, 250)
	panel.size = Vector2(400, 178)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.10, 0.07, 0.97)
	sty.set_border_width_all(2)
	sty.border_color = Color(0.62, 0.49, 0.22, 0.95)
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	overlay.add_child(panel)
	var title := Label.new()
	title.text = "Begin the Tutorial?"
	title.position = Vector2(0, 18); title.size = Vector2(400, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.97, 0.85, 0.42))
	panel.add_child(title)
	var sub := Label.new()
	sub.text = "A guided walkthrough of building, growth, defense and expansion.\nEnemy forces stay paused while you learn."
	sub.position = Vector2(16, 54); sub.size = Vector2(368, 48)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	panel.add_child(sub)
	var yes := Button.new()
	yes.text = "Begin Tutorial"
	yes.position = Vector2(40, 122); yes.size = Vector2(150, 40)
	panel.add_child(yes)
	var no := Button.new()
	no.text = "Skip Tutorial"
	no.position = Vector2(210, 122); no.size = Vector2(150, 40)
	panel.add_child(no)
	yes.pressed.connect(func():
		overlay.queue_free()
		TutorialSystem.start()
		SimulationClock.set_speed(SimulationClock.SPEED_NORMAL))
	no.pressed.connect(func():
		overlay.queue_free()
		TutorialSystem.skip_tutorial()
		SimulationClock.set_speed(SimulationClock.SPEED_NORMAL))

# Reaching Day 100 (20 minutes) is the goal of a life — recognise it with a triumphant
# moment that HOLDS time, then lets the sovereign keep ruling (it is NOT game over).
func _show_reign_milestone(_day: int) -> void:
	if _reign_celebrated_shown: return
	_reign_celebrated_shown = true
	var prev_speed: int = SimulationClock.game_speed
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)

	var overlay := CanvasLayer.new()
	overlay.name  = "ReignMilestoneOverlay"
	overlay.layer = 21
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(320, 205)
	panel.size     = Vector2(640, 290)
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.13, 0.10, 0.06, 0.98)
	style.set_border_width_all(3)
	style.border_color = Color(0.95, 0.80, 0.32)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.6); style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "⚜  A SOVEREIGN'S REIGN  ⚜"
	title.position = Vector2(20, 26); title.size = Vector2(600, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.36))
	panel.add_child(title)

	var msg := Label.new()
	msg.text = "Twelve days of unbroken rule — a sovereign's reign upon the throne.\nYour people prosper, your walls stand, and your name will be remembered.\n\nLong may you reign.   (+200 prestige)"
	msg.position = Vector2(30, 90); msg.size = Vector2(580, 140)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color(0.93, 0.92, 0.85))
	panel.add_child(msg)

	var btn := Button.new()
	btn.text = "Continue Ruling"
	btn.position = Vector2(250, 234); btn.size = Vector2(140, 38)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func():
		overlay.queue_free()
		SimulationClock.set_speed(prev_speed if prev_speed > 0 else SimulationClock.SPEED_NORMAL))
	panel.add_child(btn)

func _show_game_over(victory: bool, message: String) -> void:
	if _game_over_shown: return
	_game_over_shown = true
	SimulationClock.set_speed(0)

	var overlay := CanvasLayer.new()
	overlay.name  = "GameOverOverlay"
	overlay.layer = 20
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(340, 220)
	panel.size     = Vector2(600, 260)
	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.10, 0.12, 0.16, 0.98)
	style.set_border_width_all(2)
	style.border_color     = Color.GOLD if victory else Color.DARK_RED
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "VICTORY!" if victory else "DEFEAT"
	title.position = Vector2(20, 20); title.size = Vector2(560, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.GOLD if victory else Color.ORANGE_RED)
	panel.add_child(title)

	var msg := Label.new()
	msg.text = message; msg.position = Vector2(20, 80); msg.size = Vector2(560, 80)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_color_override("font_color", Color.WHITE_SMOKE)
	panel.add_child(msg)

	var day_lbl := Label.new()
	day_lbl.text = "Day %d reached." % SimulationClock.game_day()
	day_lbl.position = Vector2(20, 160); day_lbl.size = Vector2(560, 24)
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_lbl.add_theme_font_size_override("font_size", 13)
	day_lbl.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	panel.add_child(day_lbl)

	var restart_btn := Button.new()
	restart_btn.text = "Play Again"; restart_btn.position = Vector2(80, 200)
	restart_btn.size = Vector2(140, 40)
	restart_btn.add_theme_font_size_override("font_size", 14)
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	panel.add_child(restart_btn)

	var map_btn := Button.new()
	map_btn.text = "World Map"; map_btn.position = Vector2(240, 200)
	map_btn.size = Vector2(140, 40)
	map_btn.add_theme_font_size_override("font_size", 14)
	map_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://view/worldmap/WorldMapScene.tscn"))
	panel.add_child(map_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Main Menu"; quit_btn.position = Vector2(400, 200)
	quit_btn.size = Vector2(120, 40)
	quit_btn.add_theme_font_size_override("font_size", 14)
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://view/menu/MainMenuScene.tscn"))
	panel.add_child(quit_btn)

# ── Starting buildings ────────────────────────────────────────────────────────

func _place_starting_buildings() -> void:
	var kx: int = _keep_x; var ky: int = _keep_y
	_force_place("village_hall", kx - 1, ky - 1)
	_force_place("hovel", kx + 2, ky - 1)
	_force_place("hovel", kx + 2, ky)
	_force_place("hovel", kx + 2, ky + 1)
	_force_place("hovel", kx - 2, ky - 1)
	_force_place("hovel", kx - 2, ky)
	_force_place("apple_orchard", kx + 4, ky)
	_auto_assign_workers()

func _force_place(btype: String, gx: int, gy: int) -> void:
	if not GameState.grid_in_bounds(gx, gy): return
	GameState.prepare_starting_area(gx, gy, 2)
	var player: Dictionary = GameState.players[0]
	var sw: int = player["resources"].get("wood", 0)
	var ss: int = player["resources"].get("stone", 0)
	var sg: int = player.get("gold", 0)
	player["resources"]["wood"]  = 9999
	player["resources"]["stone"] = 9999
	player["gold"]               = 9999
	CommandQueue.enqueue(7, {"building_type": btype, "grid_x": gx, "grid_y": gy}, 0)
	SimulationClock._advance_tick()
	player["resources"]["wood"]  = sw
	player["resources"]["stone"] = ss
	player["gold"]               = sg

func _auto_assign_workers() -> void:
	if GameState.players.size() == 0: return
	const WorkerSystem = preload("res://simulation/player/WorkerSystem.gd")
	WorkerSystem.auto_assign(GameState.players[0])

# ── Persistence ────────────────────────────────────────────────────────────────

func _do_save() -> void:
	const SM = preload("res://simulation/persistence/SaveManager.gd")
	const DiffSystem = preload("res://simulation/core/DifficultySystem.gd")
	var state: Dictionary = GameState.serialize()
	var p: Dictionary = GameState.players[0] if GameState.players.size() > 0 else {}
	var meta: Dictionary = {
		"game_day": SimulationClock.game_day(),
		"shire_count": p.get("shire_ids", []).size(),
		"difficulty": DiffSystem.level_name(DiffSystem.current),
	}
	var ok: bool = SM.save(state, SM.DEFAULT_SAVE_PATH, meta)
	if ok:
		_hud.show_notification("Game saved!", 2.0)
		EventBus.save_completed.emit(SM.DEFAULT_SAVE_PATH)
	else:
		_hud.show_notification("Save failed!", 2.0)

func _do_load(path: String) -> void:
	const SM = preload("res://simulation/persistence/SaveManager.gd")
	var data: Dictionary = SM.load_save(path)
	if data.is_empty():
		EventBus.load_completed.emit(false)
		return
	GameState.deserialize(data)
	EventBus.load_completed.emit(true)
	_hud.show_notification("Game loaded!", 2.0)
