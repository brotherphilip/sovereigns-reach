extends RefCounted
# Per-citizen survival needs: each villager carries their own HP, FOOD and WARMTH (each 0–100).
# The two needs fall a little every game-day at a difficulty-scaled BURN rate; a villager tops
# them back up by going indoors (their allotted home, or the village hall) — warmth from the
# hearth, food from the larder (gated on the realm actually HAVING food in store). When a need
# bottoms out the villager loses HP; when HP hits 0 they die (of hunger or of the cold). Perks
# (cloaks, trades…) can later modify these rates — for now they're flat per difficulty.
#
# Pure data over the shared `citizens` array — no node, headless-safe. The decay/HP/death pass
# (tick_day) runs once per game-day from GameState; the indoor top-up (recover_inside) is called
# per-tick by CitizenSystem while a pawn is STATE_INSIDE.

const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")
const FoodSystem       = preload("res://simulation/economy/FoodSystem.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")

const NEED_MAX: float = 100.0
const HP_MAX: float   = 100.0
const COMFORT: float  = 50.0    # at/above this on BOTH needs, the villager mends (HP regen)
const LOW: float      = 35.0    # below this on either need, an idle villager runs a home errand
const START_MIN: float = 75.0   # founders/newborns begin comfortably provided for
const START_MAX: float = 100.0

# Per game-day decay (before the difficulty multiplier). A full-to-empty fall takes ~12 days,
# so a fed, housed realm tops up unhurriedly while a cut-off villager visibly wastes away.
const FOOD_BURN: float   = 8.0
const WARMTH_BURN: float = 6.0
# The cold bites harder as the year turns — warmth drains faster in autumn, far faster in winter.
const AUTUMN_WARMTH_MULT: float = 1.4
const WINTER_WARMTH_MULT: float = 2.5

# HP, per game-day.
const HP_DAMAGE: float = 15.0   # lost per EMPTY need per day (so hunger AND cold together = 2×)
const HP_REGEN: float  = 8.0    # mended per day while both needs sit at/above COMFORT

# Indoor top-up, per tick (so "popping in to warm up for a bit" is a few seconds, not a chore).
const WARMTH_RECOVER: float = 2.0
const FOOD_RECOVER: float   = 2.5

# Founding family names. Founders are dealt DISTINCT names from this pool (shuffled) so the
# village starts as a spread of households, not a town full of one surname; children then inherit
# their father's name (see PeopleSystem), so lineages form and some lines naturally die out.
const SURNAMES: Array = [
	"Mason", "Cooper", "Fletcher", "Carter", "Baker", "Turner", "Walker", "Thatcher",
	"Miller", "Tanner", "Webber", "Sawyer", "Shepherd", "Carver", "Potter", "Wright",
	"Brewer", "Fowler", "Hayward", "Underwood", "Blackwood", "Hale", "Stone", "Fenn",
	"Brook", "Ashby", "Holt", "Marsh", "Reeve", "Combe",
]

# ── Field setup / queries ───────────────────────────────────────────────────────────

# Backfill needs fields on a citizen that predates this system (old saves) or a sparse profile.
static func ensure(c: Dictionary) -> void:
	if not c.has("hp"):      c["hp"] = HP_MAX
	if not c.has("food"):    c["food"] = START_MAX
	if not c.has("warmth"):  c["warmth"] = START_MAX
	if not c.has("surname"): c["surname"] = ""

static func is_hungry(c: Dictionary) -> bool:
	return float(c.get("food", NEED_MAX)) < LOW

static func is_cold(c: Dictionary) -> bool:
	return float(c.get("warmth", NEED_MAX)) < LOW

# "Aldric Mason" — first name plus family name (just the first name if unnamed-line).
static func full_name(c: Dictionary) -> String:
	var n: String = String(c.get("name", "A villager"))
	var s: String = String(c.get("surname", ""))
	return "%s %s" % [n, s] if s != "" else n

# A deterministic shuffle of the surname pool (Fisher–Yates over the passed rng), so founder
# households are reproducible per seed.
static func shuffled_surnames(rng: RandomNumberGenerator) -> Array:
	var pool: Array = SURNAMES.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = pool[i]; pool[i] = pool[j]; pool[j] = t
	return pool

# ── Per-tick indoor recovery (called from CitizenSystem while INSIDE) ────────────────

# Warmth from the hearth always recovers indoors; food only if the larder isn't bare.
static func recover_inside(c: Dictionary, has_food: bool) -> void:
	ensure(c)
	c["warmth"] = minf(NEED_MAX, float(c["warmth"]) + WARMTH_RECOVER)
	if has_food:
		c["food"] = minf(NEED_MAX, float(c["food"]) + FOOD_RECOVER)

# True when the realm has food in store for villagers to eat (gates indoor food recovery).
static func realm_has_food(player: Dictionary) -> bool:
	return FoodSystem.get_total_food(player) > 0

# ── Daily decay + HP + death ─────────────────────────────────────────────────────────

# Decays needs, applies HP damage/regen, kills the spent. Returns an Array of
# {"name", "cause"} for villagers who died THIS day (so the caller can announce them).
static func tick_day(citizens: Array, player: Dictionary, season: int, _rng: RandomNumberGenerator) -> Array:
	var burn: float = DifficultySystem.get_mod("needs_burn")
	var warmth_mult: float = 1.0
	match season:
		SeasonSystem.Season.AUTUMN: warmth_mult = AUTUMN_WARMTH_MULT
		SeasonSystem.Season.WINTER: warmth_mult = WINTER_WARMTH_MULT
	var dead: Array = []
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		ensure(c)
		c["food"]   = clampf(float(c["food"])   - FOOD_BURN   * burn,               0.0, NEED_MAX)
		c["warmth"] = clampf(float(c["warmth"]) - WARMTH_BURN * burn * warmth_mult, 0.0, NEED_MAX)
		var hp: float = float(c["hp"])
		var dmg: float = 0.0
		if float(c["food"])   <= 0.0: dmg += HP_DAMAGE
		if float(c["warmth"]) <= 0.0: dmg += HP_DAMAGE
		if dmg > 0.0:
			hp -= dmg
		elif float(c["food"]) >= COMFORT and float(c["warmth"]) >= COMFORT:
			hp = minf(HP_MAX, hp + HP_REGEN)
		c["hp"] = hp
		if hp <= 0.0:
			c["hp"] = 0.0
			c["is_alive"] = false
			# Cause: whichever need is the more wretched (ties → hunger).
			var cause: String = "hunger" if float(c["food"]) <= float(c["warmth"]) else "the cold"
			_widow(citizens, c)
			dead.append({"name": full_name(c), "cause": cause})
	return dead

# Unlink a dead villager from their partner so the survivor can re-pair.
static func _widow(citizens: Array, c: Dictionary) -> void:
	var pid: int = int(c.get("partner_id", -1))
	if pid >= 0:
		for o in citizens:
			if o is Dictionary and int(o.get("id", -1)) == pid:
				o["partner_id"] = -1
				break
	c["partner_id"] = -1
