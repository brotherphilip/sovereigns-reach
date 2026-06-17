extends RefCounted
# Lightweight, data-driven realm events — the moment-to-moment life of the territory.
# Each game-day, after a cooldown, there's a chance an event befalls the realm: a trade
# convoy, a foraging surplus, a predator raid on the pens. Each applies a small effect
# and a line of report, surfaced to the player via the notification feed.
#
# Design goals:
#  - DATA-DRIVEN: a new event is just a dict in EVENTS — content compounds over time.
#  - FORGIVING: effects are bounded and clamped; an event never directly ends a run
#    (no effect can drop a resource below 0 or popularity into instant-revolt).
#  - POSITIVE-LEANING: good/neutral events outweigh bad ones, so the territory feels alive
#    and rewarding to manage rather than punishing.
#
# Tone note: the report text reads as a modern command/administrative briefing (enemy
# forces, supply routes, reserves, readiness, the population) rather than medieval flavour.
#
# A future iteration can add a "choices" array to any event for player-driven decisions
# (the framework returns the whole event dict, so a choice popup can be layered on later).

const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")
const SeasonSystem  = preload("res://simulation/world/SeasonSystem.gd")

const COOLDOWN_DAYS: int = 5     # minimum days between events
const DAILY_CHANCE: float = 0.34 # per-day chance an event fires once off cooldown

# tone: "good" | "bad" | "neutral" — drives the notification colour.
# effect keys: food, gold, wood, stone, iron, popularity, prestige (signed deltas);
#              spawn_citizens (int, handled by GameState — a new arrival joins the settlement).
# OPTIONAL "season" key (int SeasonSystem.Season, or an Array of them): the event is
# only eligible during that season — seasonal events tied to the visible calendar.
# Events with no "season" key fire year-round (back-compatible).
const EVENTS: Array = [
	{
		"id": "wandering_merchant", "tone": "good", "weight": 12, "min_day": 2,
		"title": "Trade Convoy Arrives",
		"text": "A trade convoy has stopped at the perimeter to do business, exchanging goods for hard currency.",
		"effect": {"gold": 60},
	},
	{
		"id": "bountiful_foraging", "tone": "good", "weight": 12, "min_day": 1,
		"title": "Foraging Surplus",
		"text": "Foraging teams returned from the woodland with a large haul of provisions for the reserves.",
		"effect": {"food": 50},
	},
	{
		"id": "traveling_minstrels", "tone": "good", "weight": 10, "min_day": 2,
		"title": "Morale Event",
		"text": "A travelling entertainment troupe passed through and lifted spirits across the settlement.",
		"effect": {"popularity": 6},
	},
	{
		"id": "lost_traveler", "tone": "good", "weight": 8, "min_day": 3,
		"title": "New Arrival",
		"text": "A displaced traveller has requested to settle here and taken up vacant housing.",
		"effect": {"spawn_citizens": 1},
	},
	{
		"id": "timber_windfall", "tone": "good", "weight": 9, "min_day": 2,
		"title": "Salvageable Timber",
		"text": "Overnight winds brought down old-growth trees — usable timber, free for the hauling.",
		"effect": {"wood": 45},
	},
	{
		"id": "wild_boar_hunt", "tone": "good", "weight": 9, "min_day": 3,
		"title": "Successful Hunt",
		"text": "A hunting party brought down a large boar; the food reserves are well stocked.",
		"effect": {"food": 35},
	},
	{
		"id": "good_omen", "tone": "neutral", "weight": 7, "min_day": 4,
		"title": "Public Confidence Rising",
		"text": "A wave of optimism is spreading through the population, and confidence in your leadership grows.",
		"effect": {"prestige": 20, "popularity": 2},
	},
	{
		"id": "wedding_feast", "tone": "good", "weight": 8, "min_day": 5,
		"title": "Community Celebration",
		"text": "Two local families marked a union, and the whole settlement turned out to celebrate.",
		"effect": {"popularity": 5},
	},
	{
		"id": "wolves_in_the_night", "tone": "bad", "weight": 7, "min_day": 6,
		"title": "Predator Raid",
		"text": "A wolf pack breached the livestock pens overnight; part of the food reserves were lost.",
		"effect": {"food": -25},
	},
	{
		"id": "cart_mishap", "tone": "bad", "weight": 6, "min_day": 4,
		"title": "Transport Breakdown",
		"text": "A supply vehicle broke down on the road; a load of timber was scattered and spoiled.",
		"effect": {"wood": -20},
	},
	{
		"id": "petty_theft", "tone": "bad", "weight": 5, "min_day": 6,
		"title": "Theft Reported",
		"text": "A thief worked the market and got away with a sum of currency before security responded.",
		"effect": {"gold": -30},
	},
	{
		"id": "minor_quarrel", "tone": "bad", "weight": 5, "min_day": 7,
		"title": "Civil Dispute",
		"text": "A feud between two families spilled into the central square and soured the public mood.",
		"effect": {"popularity": -4},
	},

	# ── Choice events ─────────────────────────────────────────────────────────────
	# These carry a `choices` array instead of an `effect`; the realm waits on YOUR
	# decision (a popup) and the chosen option's effect is applied via a command.
	{
		"id": "barons_loan", "tone": "neutral", "weight": 7, "min_day": 6,
		"title": "Financing Offer",
		"text": "A neighbouring power offers a line of credit — useful funds now, but it leaves you indebted to them.",
		"choices": [
			{"label": "Accept the credit (+150 gold, −6 popularity)", "effect": {"gold": 150, "popularity": -6}},
			{"label": "Decline — stay independent (+10 prestige)", "effect": {"prestige": 10}},
		],
	},
	{
		"id": "bandit_toll", "tone": "bad", "weight": 7, "min_day": 8,
		"title": "Supply Route Ambushed",
		"text": "Armed raiders have blocked the eastern supply route and are demanding 40 in currency to let your convoys through.",
		"choices": [
			{"label": "Pay the toll (−40 gold)", "effect": {"gold": -40}},
			{"label": "Clear them by force (−20 food, +6 popularity)", "effect": {"food": -20, "popularity": 6}},
		],
	},
	{
		"id": "refugees_at_gate", "tone": "neutral", "weight": 7, "min_day": 5,
		"title": "Refugees at the Border",
		"text": "A group fleeing a destroyed settlement is requesting asylum inside your perimeter.",
		"choices": [
			{"label": "Grant asylum (+2 population, −25 food, +6 popularity)", "effect": {"spawn_citizens": 2, "food": -25, "popularity": 6}},
			{"label": "Turn them away (−4 popularity)", "effect": {"popularity": -4}},
		],
	},
	{
		"id": "traveling_scholar", "tone": "good", "weight": 6, "min_day": 7,
		"title": "Visiting Specialist",
		"text": "A travelling specialist offers technical knowledge in exchange for accommodation.",
		"choices": [
			{"label": "Host the specialist (−25 gold, +25 prestige)", "effect": {"gold": -25, "prestige": 25}},
			{"label": "Decline the offer", "effect": {}},
		],
	},
	{
		"id": "mysterious_relic", "tone": "neutral", "weight": 5, "min_day": 9,
		"title": "Suspicious Vendor",
		"text": "An unlicensed vendor is selling a 'miracle' supplement he claims will boost food yields — for a price.",
		"choices": [
			{"label": "Buy the supplement (−35 gold, +40 food)", "effect": {"gold": -35, "food": 40}},
			{"label": "Refuse the scam (+4 popularity)", "effect": {"popularity": 4}},
		],
	},
	{
		"id": "master_mason", "tone": "neutral", "weight": 6, "min_day": 8,
		"title": "Construction Supplier",
		"text": "A contractor offers a shipment of cut stone at a fair price — useful for fortifications before hostile forces advance.",
		"choices": [
			{"label": "Buy the stone (−40 gold, +60 stone)", "effect": {"gold": -40, "stone": 60}},
			{"label": "Pass for now", "effect": {}},
		],
	},
	{
		"id": "war_deserters", "tone": "neutral", "weight": 6, "min_day": 12,
		"title": "Enemy Defectors",
		"text": "Soldiers who abandoned a rival's army are requesting to settle here and stand down.",
		"choices": [
			{"label": "Take them in (+3 population, −22 food, +3 popularity)", "effect": {"spawn_citizens": 3, "food": -22, "popularity": 3}},
			{"label": "Send them on — avoid the conflict (+6 prestige)", "effect": {"prestige": 6}},
		],
	},
	{
		"id": "saints_relic", "tone": "good", "weight": 5, "min_day": 10,
		"title": "Cultural Artifact",
		"text": "A traveller is carrying a revered artifact. Put it on public display for morale, or sell it for funds?",
		"choices": [
			{"label": "Put it on display (−25 gold, +7 popularity, +15 prestige)", "effect": {"gold": -25, "popularity": 7, "prestige": 15}},
			{"label": "Sell it to a collector (+55 gold, −4 popularity)", "effect": {"gold": 55, "popularity": -4}},
		],
	},
	{
		"id": "midwinter_want", "tone": "bad", "weight": 7, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Winter Shortage",
		"text": "The cold has hit hard and the poorest are going hungry. Open the food reserves to them, or hold them against a longer winter?",
		"choices": [
			{"label": "Open the reserves (−28 food, +9 popularity)", "effect": {"food": -28, "popularity": 9}},
			{"label": "Hold the reserves (−6 popularity)", "effect": {"popularity": -6}},
		],
	},
	{
		"id": "spring_lambs", "tone": "good", "weight": 8, "min_day": 2,
		"season": SeasonSystem.Season.SPRING,
		"title": "Spring Livestock",
		"text": "The spring season brought a strong birth of livestock — fresh provisions for the settlement.",
		"effect": {"food": 30},
	},

	# ── Seasonal events ─────────────────────────────────────────────────────────────
	# Gated to a season (see the "season" key) so the realm's situation turns with the
	# calendar: markets in spring, peak yields in summer, the harvest in autumn, supply
	# strain in winter. Positive-leaning, bounded — content that compounds per season.
	{
		"id": "spring_fair", "tone": "good", "weight": 8, "min_day": 2,
		"season": SeasonSystem.Season.SPRING,
		"title": "Spring Market",
		"text": "Traders and crowds arrived with the thaw; the central market filled with activity and trade.",
		"effect": {"popularity": 5, "gold": 25},
	},
	{
		"id": "long_summer_days", "tone": "good", "weight": 8, "min_day": 12,
		"season": SeasonSystem.Season.SUMMER,
		"title": "Peak Growing Season",
		"text": "Long days and strong sun have the fields thriving; the population is well-fed and productive.",
		"effect": {"food": 30, "popularity": 3},
	},
	{
		"id": "summer_dry_spell", "tone": "bad", "weight": 6, "min_day": 12,
		"season": SeasonSystem.Season.SUMMER,
		"title": "Drought Warning",
		"text": "Weeks without rain have dried the ground; water is running low and some crops are failing.",
		"effect": {"food": -22},
	},
	{
		"id": "harvest_home", "tone": "good", "weight": 11, "min_day": 24,
		"season": SeasonSystem.Season.AUTUMN,
		"title": "Harvest Complete",
		"text": "The final harvest is in and the reserves are full ahead of winter. The settlement stands down to celebrate.",
		"effect": {"food": 40, "popularity": 6},
	},
	{
		"id": "hearth_tales", "tone": "good", "weight": 9, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Winter Gathering",
		"text": "The cold drew people together indoors for warmth and company through the long nights.",
		"effect": {"popularity": 5},
	},
	{
		"id": "deep_frost", "tone": "bad", "weight": 6, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Hard Freeze",
		"text": "A severe freeze hit the storage facilities; part of the winter reserves were lost to the cold.",
		"effect": {"food": -22},
	},
	{
		"id": "harvest_moon", "tone": "good", "weight": 8, "min_day": 24,
		"season": SeasonSystem.Season.AUTUMN,
		"title": "Strong Harvest Outlook",
		"text": "Clear autumn conditions have the population optimistic about the incoming yield.",
		"effect": {"popularity": 5},
	},
	{
		"id": "first_snow", "tone": "neutral", "weight": 6, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "First Snowfall",
		"text": "The season's first snow settled over the settlement; a brief lift in spirits, the children especially.",
		"effect": {"popularity": 3},
	},

	# ── More year-round happenings (content density) ────────────────────────────────
	{
		"id": "starlit_night", "tone": "neutral", "weight": 7, "min_day": 2,
		"title": "Quiet Night",
		"text": "Clear skies and calm conditions; the night watch reports an uneventful, steady shift.",
		"effect": {"popularity": 3},
	},
	{
		"id": "traveling_healer", "tone": "good", "weight": 6, "min_day": 4,
		"title": "Medical Outreach",
		"text": "A travelling medic treated the sick and trained local caregivers before moving on.",
		"effect": {"popularity": 5},
	},
	{
		"id": "river_bounty", "tone": "good", "weight": 8, "min_day": 3,
		"title": "Fishing Surplus",
		"text": "Heavy fish runs in the shallows let the crews bring in a major catch for the reserves.",
		"effect": {"food": 30},
	},
	{
		"id": "chimney_fire", "tone": "bad", "weight": 5, "min_day": 7,
		"title": "Structure Fire",
		"text": "A hearth fire spread to a roof; crews contained it, but some timber was lost.",
		"effect": {"wood": -18},
	},
	{
		"id": "master_craftsman", "tone": "good", "weight": 6, "min_day": 5,
		"title": "Skilled Worker Relocates",
		"text": "A renowned craftsman has relocated to your settlement, drawing trade and raising its profile.",
		"effect": {"prestige": 15, "gold": 30},
	},
	{
		"id": "knight_errant", "tone": "neutral", "weight": 6, "min_day": 8,
		"title": "Veteran Officer Available",
		"text": "A veteran fighter offers his service and reputation to your command for a season — at a price.",
		"choices": [
			{"label": "Bring him on (−80 gold, +18 prestige)", "effect": {"gold": -80, "prestige": 18}},
			{"label": "Decline the offer (+2 popularity)", "effect": {"popularity": 2}},
		],
	},
	{
		"id": "poachers_caught", "tone": "neutral", "weight": 6, "min_day": 7,
		"title": "Poaching Arrest",
		"text": "Patrols caught people illegally taking game from your land. The ruling is yours to make.",
		"choices": [
			{"label": "Make an example of them (−3 popularity, +10 prestige)", "effect": {"popularity": -3, "prestige": 10}},
			{"label": "Show leniency — they were starving (+6 popularity)", "effect": {"popularity": 6}},
		],
	},

	# ── Stone & iron happenings (close the materials gap — these feed fortifications &
	#    arms, the prep that lets a territory endure the hostile sieges) ───────────────
	{
		"id": "quarry_seam", "tone": "good", "weight": 8, "min_day": 4,
		"title": "Quarry Find",
		"text": "Crews hit a clean seam of building stone — easy to extract and transport.",
		"effect": {"stone": 45},
	},
	{
		"id": "iron_vein", "tone": "good", "weight": 7, "min_day": 5,
		"title": "Iron Deposit",
		"text": "Diggers located a solid iron ore deposit in the hill workings; the forges will put it to use.",
		"effect": {"iron": 30},
	},
	{
		"id": "mine_cave_in", "tone": "bad", "weight": 5, "min_day": 9,
		"title": "Mine Collapse",
		"text": "A shaft collapsed overnight; cut stone was buried and a week of work was lost.",
		"effect": {"stone": -18},
	},
	{
		"id": "traveling_smith", "tone": "good", "weight": 6, "min_day": 6,
		"title": "Visiting Engineer",
		"text": "A skilled metalworker offers to process your iron before moving on. Set the priority.",
		"choices": [
			{"label": "Tools for agriculture (−20 iron, +30 food, +4 popularity)", "effect": {"iron": -20, "food": 30, "popularity": 4}},
			{"label": "Equipment for the troops (−20 iron, +15 prestige)", "effect": {"iron": -20, "prestige": 15}},
		],
	},

	# ── More decisions (variety over the 100-day run) ────────────────────────────────
	{
		"id": "grand_tourney", "tone": "good", "weight": 6, "min_day": 14,
		"title": "Public Games Proposed",
		"text": "There's demand to host a large public competition. It would boost morale, but the budget would feel it.",
		"choices": [
			{"label": "Host the games (−60 gold, +8 popularity, +12 prestige)", "effect": {"gold": -60, "popularity": 8, "prestige": 12}},
			{"label": "Hold the budget", "effect": {}},
		],
	},
	{
		"id": "marriage_alliance", "tone": "neutral", "weight": 6, "min_day": 18,
		"title": "Strategic Alliance",
		"text": "A neighbouring power proposes a formal alliance to bind your interests. Their cooperation is valuable — and they expect a payment.",
		"choices": [
			{"label": "Pay for the alliance (−70 gold, +20 prestige, +4 popularity)", "effect": {"gold": -70, "prestige": 20, "popularity": 4}},
			{"label": "Decline the alliance", "effect": {}},
		],
	},
	{
		"id": "neighbours_plea", "tone": "neutral", "weight": 6, "min_day": 10,
		"title": "Aid Request",
		"text": "A neighbouring settlement hit by fire is requesting food aid. Help them, or conserve your own reserves?",
		"choices": [
			{"label": "Send aid (−25 food, +6 popularity, +8 prestige)", "effect": {"food": -25, "popularity": 6, "prestige": 8}},
			{"label": "Refuse — our own first (−3 popularity)", "effect": {"popularity": -3}},
		],
	},

	# ── Mid/late-game decisions (keep the long middle fresh) ─────────────────────────
	{
		"id": "master_builders_plan", "tone": "neutral", "weight": 5, "min_day": 30,
		"title": "Major Public Works",
		"text": "A lead engineer has proposed a landmark construction project to define your administration — expensive, but it would be remembered for years.",
		"choices": [
			{"label": "Fund the project (−80 gold, −40 stone, +30 prestige, +5 popularity)", "effect": {"gold": -80, "stone": -40, "prestige": 30, "popularity": 5}},
			{"label": "Other priorities for now", "effect": {}},
		],
	},
	{
		"id": "wandering_chronicler", "tone": "good", "weight": 6, "min_day": 25,
		"title": "Press Coverage",
		"text": "A chronicler wants to document your administration for the record. Favourable coverage is never free.",
		"choices": [
			{"label": "Grant access (−30 gold, +25 prestige)", "effect": {"gold": -30, "prestige": 25}},
			{"label": "Decline the request", "effect": {}},
		],
	},
	{
		"id": "border_skirmish", "tone": "bad", "weight": 6, "min_day": 35,
		"title": "Border Incursion",
		"text": "Raiders are probing the edge of your territory. Meet them in the field, or pay them off and keep personnel home?",
		"choices": [
			{"label": "Deploy the patrol (−12 food, +8 prestige, +4 popularity)", "effect": {"food": -12, "prestige": 8, "popularity": 4}},
			{"label": "Pay them off (−40 gold, −2 popularity)", "effect": {"gold": -40, "popularity": -2}},
		],
	},
]

# Whether an event waits on a player decision (has choices) rather than auto-resolving.
static func has_choices(event: Dictionary) -> bool:
	return event.has("choices") and event["choices"] is Array and not event["choices"].is_empty()

# Whether an event is eligible in the given season. Events without a "season" key fire
# year-round; otherwise the key may be a single Season int or an Array of them.
static func _event_in_season(event: Dictionary, season: int) -> bool:
	if not event.has("season"):
		return true
	var s = event["season"]
	if s is Array:
		return season in s
	return int(s) == season

# Look up an event definition by id (for resolving a deferred choice).
static func event_by_id(event_id: String) -> Dictionary:
	for e in EVENTS:
		if e.get("id", "") == event_id:
			return e
	return {}

# Apply the chosen option of a choice-event. Returns {"summary": String,
# "spawn_citizens": int, "tone": String} for the caller to surface / enact.
static func resolve(player: Dictionary, event_id: String, choice_index: int) -> Dictionary:
	var ev: Dictionary = event_by_id(event_id)
	if ev.is_empty() or not has_choices(ev):
		return {}
	var choices: Array = ev["choices"]
	if choice_index < 0 or choice_index >= choices.size():
		return {}
	var choice: Dictionary = choices[choice_index]
	var effect: Dictionary = choice.get("effect", {})
	var summary: String = _apply_effect(player, effect)
	return {
		"summary": summary,
		"spawn_citizens": int(effect.get("spawn_citizens", 0)),
		"tone": ev.get("tone", "neutral"),
		"label": choice.get("label", ""),
	}

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

	# Weighted pick among events eligible at this day AND this season. Seasons key off the
	# day/night calendar now, so convert this game-day to a tick for the lookup.
	var season: int = SeasonSystem.season_at_tick(day * SeasonSystem.TICKS_PER_DAY)
	var pool: Array = []
	var total: int = 0
	for e in EVENTS:
		if day >= int(e.get("min_day", 0)) and _event_in_season(e, season):
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
	var result: Dictionary = chosen.duplicate(true)
	# Choice events defer their effect until the player decides (via resolve()); plain
	# events apply immediately and carry a "+50 food" summary for the notification.
	if not has_choices(chosen):
		result["summary"] = _apply_effect(player, chosen.get("effect", {}))
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
				parts.append("+%d population" % amount)
			_:
				pass
	return ", ".join(parts)
