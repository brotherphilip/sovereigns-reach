extends RefCounted
# A four-season calendar layered on top of the day counter (240 ticks = 1 day).
# Pure static math + small helper tables — no node, headless-safe, deterministic.
# Seasons drive: orchard/farm tree lifecycle visuals, harvest gating in ResourceTick,
# and terrain re-tinting in the city view. Weather (WeatherSystem) is independent and
# stacks on top (drought/snow still zero out yields regardless of season).

enum Season {
	SPRING = 0,
	SUMMER = 1,
	AUTUMN = 2,
	WINTER = 3,
}

const DAYS_PER_SEASON: int = 12
const SEASON_COUNT: int = 4
const DAYS_PER_YEAR: int = DAYS_PER_SEASON * SEASON_COUNT   # 48
const TICKS_PER_DAY: int = 240
const TICKS_PER_YEAR: int = DAYS_PER_YEAR * TICKS_PER_DAY

# Which seasons each producer actually HARVESTS in (full yield). Outside these
# seasons the field is tended but yields ~nothing. Animal/industry buildings that
# are not listed produce year-round.
const HARVEST_SEASONS: Dictionary = {
	"apple_orchard": [Season.AUTUMN],
	"wheat_farm":    [Season.SUMMER, Season.AUTUMN],
	"hops_farm":     [Season.AUTUMN],
}

# Season name for HUD / logging.
static func season_name(season: int) -> String:
	match season:
		Season.SPRING: return "Spring"
		Season.SUMMER: return "Summer"
		Season.AUTUMN: return "Autumn"
		Season.WINTER: return "Winter"
		_: return "Unknown"

# Day index (0-based) from a raw tick counter.
static func day_of(tick: int) -> int:
	return tick / TICKS_PER_DAY

# Current season index for a given game-day.
static func current_season(day: int) -> int:
	return (day / DAYS_PER_SEASON) % SEASON_COUNT

# Season index directly from a tick counter.
static func season_at_tick(tick: int) -> int:
	return current_season(day_of(tick))

# ── Day / night cycle ──────────────────────────────────────────────────────────
# DECOUPLED from the game-day so the sky doesn't strobe: one full day↔night spans
# DAY_NIGHT_TICKS (≈ 60 real seconds at NORMAL speed), opening at noon. Daytime is the
# long stretch; night is a shorter window in the middle (a power curve skews the cycle
# toward daylight). Drives the city-view lighting overlay, building lamps, and citizens
# returning home to sleep at night. (The numeric Day counter still advances per
# game-day; this is purely the felt time-of-day.)
const DAY_NIGHT_TICKS: int = 1200          # ~5 game-days; ~60s/cycle at NORMAL speed
const NIGHT_SKEW: float = 2.2              # >1 → daytime dominates, night is shorter
const NIGHT_HOME_THRESHOLD: float = 0.6    # darkness past which folk head home to sleep

# 0.0 = full daylight … 1.0 = deepest midnight.
static func night_factor(tick: int) -> float:
	var f: float = float((tick % DAY_NIGHT_TICKS + DAY_NIGHT_TICKS) % DAY_NIGHT_TICKS) / float(DAY_NIGHT_TICKS)
	var dark: float = 0.5 - 0.5 * cos(f * TAU)   # 0 at f=0 (noon), 1 at f=0.5 (midnight)
	return clampf(pow(dark, NIGHT_SKEW), 0.0, 1.0)

# True once it's dark enough that folk head home to sleep (dusk through dawn).
static func is_night(tick: int) -> bool:
	return night_factor(tick) >= NIGHT_HOME_THRESHOLD

# Fraction (0..1) through the current day/night cycle (0 = noon).
static func day_night_phase(tick: int) -> float:
	return float((tick % DAY_NIGHT_TICKS + DAY_NIGHT_TICKS) % DAY_NIGHT_TICKS) / float(DAY_NIGHT_TICKS)

# Human-readable phase for the HUD clock.
static func phase_name(tick: int) -> String:
	var n: float = night_factor(tick)
	if n < 0.12:
		return "Day"
	elif n < NIGHT_HOME_THRESHOLD:
		return "Dusk" if day_night_phase(tick) < 0.5 else "Dawn"  # darkening before midnight, brightening after
	return "Night"

# 0..1 progress through the current season (0 = first day, ~1 = last day).
static func season_progress(day: int) -> float:
	return float(day % DAYS_PER_SEASON) / float(maxi(1, DAYS_PER_SEASON - 1))

# Harvest seasons for a building type (empty = produces year-round).
static func harvest_seasons(building_type: String) -> Array:
	return HARVEST_SEASONS.get(building_type, [])

# Whether a producer is in its harvest window this season. Year-round producers
# (not in the table) always return true.
static func is_harvest_time(building_type: String, season: int) -> bool:
	var windows: Array = HARVEST_SEASONS.get(building_type, [])
	if windows.is_empty():
		return true
	return season in windows

# Yield multiplier for a producer given the season: 1.0 in-window, a real trickle
# off-season (so the no-tech orchard — "must feed the early village" — still yields
# something in spring/summer instead of nothing, and the bulk still comes at harvest).
# Year-round producers (not in the table) are unaffected (1.0).
# NOTE: this used to return 0.0 off-season, which made the only no-tech food building
# produce nothing for 3 of every 4 seasons → guaranteed early starvation. The trickle
# is what the comment always promised; harvest seasons remain the bumper crop.
const OFF_SEASON_YIELD_MULT: float = 0.6
static func harvest_yield_mult(building_type: String, season: int) -> float:
	var windows: Array = HARVEST_SEASONS.get(building_type, [])
	if windows.is_empty():
		return 1.0
	return 1.0 if season in windows else OFF_SEASON_YIELD_MULT

# Orchard/crop growth stage (0..3) for a season, used by the building art:
#   WINTER → 0 BARE, SPRING → 1 BUDDING, SUMMER → 2 LEAFY, AUTUMN → 3 FRUITING.
static func growth_stage(season: int) -> int:
	match season:
		Season.WINTER: return 0
		Season.SPRING: return 1
		Season.SUMMER: return 2
		Season.AUTUMN: return 3
	return 2

# A canopy/foliage tint for the season, blended from a base green. Reused by both
# the orchard art and the terrain tinting so the whole map agrees on the palette.
static func foliage_tint(season: int) -> Color:
	match season:
		Season.SPRING: return Color(0.45, 0.74, 0.32)   # fresh bright green
		Season.SUMMER: return Color(0.27, 0.55, 0.24)   # deep summer green
		Season.AUTUMN: return Color(0.72, 0.52, 0.18)   # gold / russet
		Season.WINTER: return Color(0.62, 0.64, 0.60)   # desaturated grey-green
	return Color(0.30, 0.55, 0.28)

# A ground/grass tint multiplier for the season (multiplied over a base terrain
# colour). Spring/summer lush, autumn golden, winter pale.
static func ground_tint(season: int) -> Color:
	match season:
		Season.SPRING: return Color(0.96, 1.05, 0.90)
		Season.SUMMER: return Color(1.00, 1.00, 0.92)
		Season.AUTUMN: return Color(1.06, 0.94, 0.72)
		Season.WINTER: return Color(0.88, 0.92, 0.98)
	return Color(1.0, 1.0, 1.0)
