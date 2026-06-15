extends RefCounted
# The living population: villagers age through life-stages, pair into couples, conceive
# and bear children (so population grows by BIRTH, capped by housing rooms), and die of
# old age. Pure data over the shared `citizens` array; ticked once per game-day from
# GameState. Genetics (skin/hair) are inherited from the parents. ~12.5 game-year lives
# (1 game-year = 48 game-days).

const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

# Life-stage boundaries, in game-days.
const AGE_CHILD: int      = 48     # 1 yr
const AGE_ADOLESCENT: int = 192    # 4 yr
const AGE_ADULT: int      = 288    # 6 yr
const AGE_MIDLIFE: int    = 432    # 9 yr
const AGE_OLD: int        = 528    # 11 yr
const AGE_DEATH: int      = 600    # ~12.5 yr (hard cap)
const GESTATION_DAYS: int = 24     # half a game-year in the womb

const PAIR_AGE_MIN: int   = 270    # late adolescent — old enough to wed
const PAIR_AGE_GAP: int   = 150    # couples within ~3 game-years of each other
const FERTILE_MIN: int    = AGE_ADULT
const FERTILE_MAX: int    = 504
const CONCEPTION_CHANCE: float = 0.05   # per fertile housed couple per day
const OLD_DEATH_CHANCE: float  = 0.02   # per day once OLD (variance around the cap)
const SAFETY_MAX_PEOPLE: int   = 150    # performance ceiling regardless of housing

# Housing the hall/keep itself provides before any hovel is built. Must comfortably
# exceed the STARTING villager count (~14) with a little headroom, or the founding
# village is overcrowded from day one and can NEVER grow until the player happens to
# build hovels — a silent dead-end. With headroom the village grows a little on its
# own, then hovels (rooms) carry it further. (See "Grow your village" objective.)
const BASE_HOUSING: int = 16
const HOME_TYPES: Array = ["hovel"]

# Skin spectrum: 0.0 = a light dark-brown, 1.0 = fair.
const SKIN_DARK := Color(0.50, 0.36, 0.26)
const SKIN_FAIR := Color(0.96, 0.82, 0.70)

# ── Queries ─────────────────────────────────────────────────────────────────────

static func age_of(c: Dictionary, day: int) -> int:
	return day - int(c.get("born_day", day))

static func stage_for(age: int) -> String:
	if age < AGE_CHILD:      return "baby"
	if age < AGE_ADOLESCENT: return "child"
	if age < AGE_ADULT:      return "adolescent"
	if age < AGE_MIDLIFE:    return "adult"
	if age < AGE_OLD:        return "midlife"
	return "old"

static func is_working_age(c: Dictionary, day: int) -> bool:
	var s := stage_for(age_of(c, day))
	return s == "adult" or s == "midlife"

static func living_count(citizens: Array) -> int:
	var n: int = 0
	for c in citizens:
		if c is Dictionary and c.get("is_alive", false):
			n += 1
	return n

static func housing_capacity(player: Dictionary) -> int:
	var cap: int = BASE_HOUSING
	for b in player.get("buildings", []):
		if not (b is Dictionary and b.get("built", true) and b.get("is_active", true)):
			continue
		cap += int(BuildingRegistry.lookup(b.get("type", "")).get("rooms", 0))
	return cap

static func skin_color(skin: float) -> Color:
	return SKIN_DARK.lerp(SKIN_FAIR, clampf(skin, 0.0, 1.0))

# ── Daily lifecycle ───────────────────────────────────────────────────────────────

# Ages everyone, resolves deaths/pairing/conception/births. Births append to `citizens`
# (capped by housing). Returns the updated next-citizen id.
static func tick_day(citizens: Array, player: Dictionary, rng: RandomNumberGenerator, day: int, next_id: int) -> int:
	# 1) Age → stage, and old-age death (widowing the survivor).
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		var age: int = age_of(c, day)
		c["stage"] = stage_for(age)
		if age >= AGE_DEATH or (age >= AGE_OLD and rng.randf() < OLD_DEATH_CHANCE):
			c["is_alive"] = false
			var pid: int = int(c.get("partner_id", -1))
			if pid >= 0:
				var sp := _find(citizens, pid)
				if not sp.is_empty():
					sp["partner_id"] = -1
			c["partner_id"] = -1

	# 2) Pair eligible singles into couples.
	_pair_singles(citizens, rng, day)

	var cap: int = housing_capacity(player)

	# 3) Births whose term is up (if there's a free room).
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if int(c.get("pregnant_until", -1)) >= 0 and day >= int(c["pregnant_until"]):
			c["pregnant_until"] = -1
			if living_count(citizens) < cap and citizens.size() < SAFETY_MAX_PEOPLE:
				next_id = _birth(c, citizens, rng, day, next_id)

	# 4) Conception — only while there's housing headroom for the child.
	if living_count(citizens) < cap:
		for c in citizens:
			if not (c is Dictionary and c.get("is_alive", false)):
				continue
			if c.get("sex", "") != "f" or int(c.get("pregnant_until", -1)) >= 0:
				continue
			var age: int = age_of(c, day)
			if age < FERTILE_MIN or age > FERTILE_MAX:
				continue
			var partner := _find(citizens, int(c.get("partner_id", -1)))
			if partner.is_empty() or not partner.get("is_alive", false):
				continue
			if rng.randf() < CONCEPTION_CHANCE:
				c["pregnant_until"] = day + GESTATION_DAYS

	# 5) Purge the dead so the array doesn't grow without bound.
	var alive: Array = []
	for c in citizens:
		if c is Dictionary and c.get("is_alive", false):
			alive.append(c)
	if alive.size() != citizens.size():
		citizens.clear()
		citizens.append_array(alive)
	return next_id

static func _pair_singles(citizens: Array, rng: RandomNumberGenerator, day: int) -> void:
	var men: Array = []
	var women: Array = []
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if int(c.get("partner_id", -1)) >= 0:
			continue
		var age: int = age_of(c, day)
		if age < PAIR_AGE_MIN or age >= AGE_OLD:
			continue
		if c.get("sex", "") == "m":
			men.append(c)
		else:
			women.append(c)
	for m in men:
		var best: Dictionary = {}
		var best_gap: int = PAIR_AGE_GAP + 1
		for w in women:
			if int(w.get("partner_id", -1)) >= 0:
				continue
			var gap: int = absi(age_of(m, day) - age_of(w, day))
			if gap <= PAIR_AGE_GAP and gap < best_gap:
				best_gap = gap
				best = w
		if not best.is_empty():
			m["partner_id"] = int(best["id"])
			best["partner_id"] = int(m["id"])

static func _birth(mother: Dictionary, citizens: Array, rng: RandomNumberGenerator, day: int, next_id: int) -> int:
	var father := _find(citizens, int(mother.get("partner_id", -1)))
	var m_skin: float = float(mother.get("skin", 0.5))
	var f_skin: float = float(father.get("skin", m_skin)) if not father.is_empty() else m_skin
	var prof: Dictionary = {
		"sex": "m" if rng.randf() < 0.5 else "f",
		"born_day": day,
		"stage": "baby",
		"skin": inherit_skin(m_skin, f_skin, rng),
		"hair_color": _inherit_hair(mother, father, rng),
		"hair_style": rng.randi_range(0, 2),
		"mother_id": int(mother.get("id", -1)),
		"father_id": int(father.get("id", -1)) if not father.is_empty() else -1,
	}
	var hx: float = float(mother.get("hx", mother.get("x", 100.0)))
	var hy: float = float(mother.get("hy", mother.get("y", 100.0)))
	citizens.append(CitizenSystem.make_citizen(next_id, hx, hy, rng, day, prof))
	return next_id + 1

# ── Genetics ──────────────────────────────────────────────────────────────────────

# Child skin: a blend weighted toward one (dominant) parent, with a small chance to
# fall OUTSIDE the parents' range (darker than the darker, or fairer than the fairer).
static func inherit_skin(a: float, b: float, rng: RandomNumberGenerator) -> float:
	var mid: float = (a + b) * 0.5
	var dom: float = a if rng.randf() < 0.5 else b
	var base: float = lerpf(mid, dom, 0.6) + rng.randf_range(-0.04, 0.04)
	if rng.randf() < 0.08:
		if rng.randf() < 0.5:
			base = minf(a, b) - rng.randf_range(0.05, 0.15)
		else:
			base = maxf(a, b) + rng.randf_range(0.05, 0.15)
	return clampf(base, 0.0, 1.0)

static func _inherit_hair(mother: Dictionary, father: Dictionary, rng: RandomNumberGenerator) -> Color:
	if father.is_empty() or rng.randf() < 0.1:
		return CitizenSystem.HAIR_COLORS[rng.randi_range(0, CitizenSystem.HAIR_COLORS.size() - 1)]
	return mother.get("hair_color", Color(0.2, 0.14, 0.08)) if rng.randf() < 0.5 \
		else father.get("hair_color", Color(0.2, 0.14, 0.08))

static func _find(citizens: Array, id: int) -> Dictionary:
	if id < 0:
		return {}
	for c in citizens:
		if c is Dictionary and int(c.get("id", -1)) == id:
			return c
	return {}
