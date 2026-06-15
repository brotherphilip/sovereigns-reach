extends RefCounted
# Lightweight, data-driven realm events — the moment-to-moment life of the kingdom.
# Each game-day, after a cooldown, there's a chance a flavourful event befalls the
# realm: a wandering merchant, a bountiful foraging, wolves in the night. Each applies
# a small effect and a line of story, surfaced to the player via the notification feed.
#
# Design goals:
#  - DATA-DRIVEN: a new event is just a dict in EVENTS — content compounds over time.
#  - FORGIVING: effects are bounded and clamped; an event never directly ends a run
#    (no effect can drop a resource below 0 or popularity into instant-revolt).
#  - POSITIVE-LEANING: good/neutral events outweigh bad ones, so the realm feels alive
#    and rewarding to tend rather than punishing.
#
# A future iteration can add a "choices" array to any event for player-driven decisions
# (the framework returns the whole event dict, so a choice popup can be layered on later).

const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")

const COOLDOWN_DAYS: int = 5     # minimum days between events
const DAILY_CHANCE: float = 0.34 # per-day chance an event fires once off cooldown

# tone: "good" | "bad" | "neutral" — drives the notification colour.
# effect keys: food, gold, wood, stone, iron, popularity, prestige (signed deltas);
#              spawn_citizens (int, handled by GameState — a wanderer joins the village).
const EVENTS: Array = [
	{
		"id": "wandering_merchant", "tone": "good", "weight": 12, "min_day": 2,
		"title": "A Wandering Merchant",
		"text": "A merchant caravan rests by your gate and trades its wares for coin.",
		"effect": {"gold": 60},
	},
	{
		"id": "bountiful_foraging", "tone": "good", "weight": 12, "min_day": 1,
		"title": "Bountiful Foraging",
		"text": "Your people return from the woods laden with berries, nuts and mushrooms.",
		"effect": {"food": 50},
	},
	{
		"id": "traveling_minstrels", "tone": "good", "weight": 10, "min_day": 2,
		"title": "Traveling Minstrels",
		"text": "Minstrels fill the evening with song; spirits in the village lift.",
		"effect": {"popularity": 6},
	},
	{
		"id": "lost_traveler", "tone": "good", "weight": 8, "min_day": 3,
		"title": "A Weary Traveler",
		"text": "A wanderer asks to settle in your village, and takes up an empty hovel.",
		"effect": {"spawn_citizens": 1},
	},
	{
		"id": "timber_windfall", "tone": "good", "weight": 9, "min_day": 2,
		"title": "Storm-Felled Timber",
		"text": "A night's gale topples old trees — good seasoned wood, there for the hauling.",
		"effect": {"wood": 45},
	},
	{
		"id": "wild_boar_hunt", "tone": "good", "weight": 9, "min_day": 3,
		"title": "A Fine Boar Hunt",
		"text": "Your huntsmen bring down a great boar; the larders are stocked with meat.",
		"effect": {"food": 35},
	},
	{
		"id": "good_omen", "tone": "neutral", "weight": 7, "min_day": 4,
		"title": "A Good Omen",
		"text": "A white hart is sighted in the dawn mist — the smallfolk take heart in your reign.",
		"effect": {"prestige": 20, "popularity": 2},
	},
	{
		"id": "wedding_feast", "tone": "good", "weight": 8, "min_day": 5,
		"title": "A Village Wedding",
		"text": "Two households are joined; the whole village feasts late into the night.",
		"effect": {"popularity": 5},
	},
	{
		"id": "wolves_in_the_night", "tone": "bad", "weight": 7, "min_day": 6,
		"title": "Wolves in the Night",
		"text": "A wolf pack raids the pens; some of the stores are lost to the dark.",
		"effect": {"food": -25},
	},
	{
		"id": "cart_mishap", "tone": "bad", "weight": 6, "min_day": 4,
		"title": "A Cart Overturns",
		"text": "A laden cart breaks its axle on the road; a load of timber is scattered and spoiled.",
		"effect": {"wood": -20},
	},
	{
		"id": "petty_theft", "tone": "bad", "weight": 5, "min_day": 6,
		"title": "Coin Goes Missing",
		"text": "A cutpurse works the market crowd before slipping away into the lanes.",
		"effect": {"gold": -30},
	},
	{
		"id": "minor_quarrel", "tone": "bad", "weight": 5, "min_day": 7,
		"title": "A Bitter Quarrel",
		"text": "A feud between two families spills into the square and sours the mood.",
		"effect": {"popularity": -4},
	},
]

# Roll for a daily event. Mutates `player` (resource/popularity/prestige deltas) and
# returns the chosen event dict (with an added "summary" line) for the view, or {} if
# nothing fired. `spawn_citizens` is returned untouched for GameState to enact.
static func tick(player: Dictionary, world: Dictionary, rng: RandomNumberGenerator, day: int) -> Dictionary:
	if day <= 0 or player.is_empty():
		return {}
	var last: int = int(world.get("last_event_day", -999))
	if day - last < COOLDOWN_DAYS:
		return {}
	if rng.randf() >= DAILY_CHANCE:
		return {}

	# Weighted pick among events eligible at this day.
	var pool: Array = []
	var total: int = 0
	for e in EVENTS:
		if day >= int(e.get("min_day", 0)):
			pool.append(e)
			total += int(e.get("weight", 1))
	if pool.is_empty() or total <= 0:
		return {}
	var roll: int = rng.randi_range(0, total - 1)
	var chosen: Dictionary = pool[0]
	var cumulative: int = 0
	for e in pool:
		cumulative += int(e.get("weight", 1))
		if roll < cumulative:
			chosen = e
			break

	world["last_event_day"] = day
	var summary: String = _apply_effect(player, chosen.get("effect", {}))
	var result: Dictionary = chosen.duplicate(true)
	result["summary"] = summary
	return result

# Applies the bounded stat deltas to the player and returns a short "+50 food" summary.
# spawn_citizens is left for GameState (it owns the citizen array / id counter).
static func _apply_effect(player: Dictionary, effect: Dictionary) -> String:
	var parts: Array = []
	for key in effect:
		var amount: int = int(effect[key])
		match key:
			"food":
				var f: Dictionary = player.get("food", {})
				f["apples"] = maxi(0, int(f.get("apples", 0)) + amount)
				player["food"] = f
				parts.append("%+d food" % amount)
			"gold":
				player["gold"] = maxi(0, int(player.get("gold", 0)) + amount)
				parts.append("%+d gold" % amount)
			"wood", "stone", "iron":
				var r: Dictionary = player.get("resources", {})
				r[key] = maxi(0, int(r.get(key, 0)) + amount)
				player["resources"] = r
				parts.append("%+d %s" % [amount, key])
			"popularity":
				player["popularity"] = clampf(float(player.get("popularity", 50.0)) + float(amount), 0.0, 100.0)
				parts.append("%+d popularity" % amount)
			"prestige":
				player["prestige"] = maxf(0.0, float(player.get("prestige", 0.0)) + float(amount))
				parts.append("%+d prestige" % amount)
			"spawn_citizens":
				parts.append("+%d villager" % amount)
			_:
				pass
	return ", ".join(parts)
