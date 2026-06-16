extends SceneTree
# Proof harness for the seasonal calendar: season indexing, harvest-window gating,
# growth stages, and that ResourceTick zeroes crop output off-season while leaving
# year-round producers alone. Run: godot --headless --script tests/TestSeasons.gd

const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const ResourceTick     = preload("res://simulation/economy/ResourceTick.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_season_indexing()
	_test_growth_stage()
	_test_harvest_windows()
	_test_resourcetick_gating()
	print("\n=== Season Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _player() -> Dictionary:
	return {"resources": {}, "food": {}, "armory": {}, "gold": 0,
		"active_edicts": [], "tech_unlocks": []}

func _building(btype: String, workers: int) -> Dictionary:
	return {"id": 1, "type": btype, "built": true, "is_active": true,
		"workers": workers, "terrain_yield": 1.0}

# Production amount for one production tick of `btype` in a given season.
func _yield_in_season(btype: String, season: int, res: String) -> int:
	var interval: int = ResourceTick.PRODUCTION_INTERVALS.get(btype, 1)
	# Pick a tick solidly inside `season` (seasons now key off the day/night calendar).
	var season_ticks: int = SeasonSystem.DAY_NIGHT_TICKS * SeasonSystem.SKY_DAYS_PER_SEASON
	var base_tick: int = season * season_ticks + season_ticks / 2  # mid-season
	var t: int = base_tick - (base_tick % interval) + interval  # next boundary in-season
	var changes: Dictionary = ResourceTick.tick_building(_building(btype, 1), _player(), t)
	return int(changes.get(res, 0))

func _test_season_indexing() -> void:
	print("\n[Season indexing]")
	ok("day 0 is Spring", SeasonSystem.current_season(0) == SeasonSystem.Season.SPRING)
	ok("day 12 is Summer", SeasonSystem.current_season(12) == SeasonSystem.Season.SUMMER)
	ok("day 24 is Autumn", SeasonSystem.current_season(24) == SeasonSystem.Season.AUTUMN)
	ok("day 36 is Winter", SeasonSystem.current_season(36) == SeasonSystem.Season.WINTER)
	ok("year wraps back to Spring at day 48", SeasonSystem.current_season(48) == SeasonSystem.Season.SPRING)
	# season_at_tick keys off the day/night calendar (2 sky-days/season): season 2 = Autumn.
	var _stk: int = SeasonSystem.DAY_NIGHT_TICKS * SeasonSystem.SKY_DAYS_PER_SEASON
	ok("season_at_tick: mid season-2 is Autumn", SeasonSystem.season_at_tick(2 * _stk + _stk / 2) == SeasonSystem.Season.AUTUMN)
	ok("season_at_tick: start is Spring", SeasonSystem.season_at_tick(0) == SeasonSystem.Season.SPRING)
	ok("season_at_tick: year wraps (season 4 → Spring)", SeasonSystem.season_at_tick(4 * _stk) == SeasonSystem.Season.SPRING)
	ok("progress 0 at season start", is_equal_approx(SeasonSystem.season_progress(12), 0.0))

func _test_growth_stage() -> void:
	print("\n[Growth stage]")
	ok("winter → bare (0)", SeasonSystem.growth_stage(SeasonSystem.Season.WINTER) == 0)
	ok("spring → budding (1)", SeasonSystem.growth_stage(SeasonSystem.Season.SPRING) == 1)
	ok("summer → leafy (2)", SeasonSystem.growth_stage(SeasonSystem.Season.SUMMER) == 2)
	ok("autumn → fruiting (3)", SeasonSystem.growth_stage(SeasonSystem.Season.AUTUMN) == 3)

func _test_harvest_windows() -> void:
	print("\n[Harvest windows]")
	ok("orchard harvests in autumn", SeasonSystem.is_harvest_time("apple_orchard", SeasonSystem.Season.AUTUMN))
	ok("orchard idle in winter", not SeasonSystem.is_harvest_time("apple_orchard", SeasonSystem.Season.WINTER))
	ok("wheat harvests in summer", SeasonSystem.is_harvest_time("wheat_farm", SeasonSystem.Season.SUMMER))
	ok("pig farm is year-round", SeasonSystem.is_harvest_time("pig_farm", SeasonSystem.Season.WINTER))
	ok("year-round yield mult is 1.0", is_equal_approx(SeasonSystem.harvest_yield_mult("pig_farm", SeasonSystem.Season.WINTER), 1.0))

func _test_resourcetick_gating() -> void:
	print("\n[ResourceTick seasonal gating]")
	var autumn_apples: int = _yield_in_season("apple_orchard", SeasonSystem.Season.AUTUMN, "apples")
	ok("orchard yields full apples in autumn", autumn_apples > 0)
	# The no-tech staple must feed the village year-round, so off-season is a reduced
	# trickle (NOT zero — that caused guaranteed early starvation), with autumn the bumper.
	var winter_apples: int = _yield_in_season("apple_orchard", SeasonSystem.Season.WINTER, "apples")
	var spring_apples: int = _yield_in_season("apple_orchard", SeasonSystem.Season.SPRING, "apples")
	ok("orchard yields a winter trickle (>0, < autumn)", winter_apples > 0 and winter_apples < autumn_apples)
	ok("orchard yields a spring trickle (>0, < autumn)", spring_apples > 0 and spring_apples < autumn_apples)
	ok("pig farm yields meat year-round (winter)", _yield_in_season("pig_farm", SeasonSystem.Season.WINTER, "meat") > 0)
	ok("woodcutter unaffected by season (winter)", _yield_in_season("woodcutter_camp", SeasonSystem.Season.WINTER, "wood") > 0)
	_test_snow_is_winter_only()

func _test_snow_is_winter_only() -> void:
	print("\n[Snow only falls in winter]")
	const WeatherSystem = preload("res://simulation/world/WeatherSystem.gd")
	# Force a state that always rolls snow next, then transition in each season.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var saw_snow_out_of_winter := false
	var saw_snow_in_winter := false
	for season in range(4):
		for _i in range(60):
			var w := {"current": WeatherSystem.WeatherType.SNOW, "ticks_remaining": 0,
				"duration_ticks": 0, "effects": {}, "is_army_ui_hidden": false}
			WeatherSystem.tick(w, rng, season)
			if int(w["current"]) == WeatherSystem.WeatherType.SNOW:
				if season == SeasonSystem.Season.WINTER: saw_snow_in_winter = true
				else: saw_snow_out_of_winter = true
	ok("snow never falls outside winter", not saw_snow_out_of_winter)
	ok("snow can still fall in winter", saw_snow_in_winter)
