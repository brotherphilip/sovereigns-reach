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
const SeasonSystem  = preload("res://simulation/world/SeasonSystem.gd")

const COOLDOWN_DAYS: int = 5     # minimum days between events
const DAILY_CHANCE: float = 0.34 # per-day chance an event fires once off cooldown

# tone: "good" | "bad" | "neutral" — drives the notification colour.
# effect keys: food, gold, wood, stone, iron, popularity, prestige (signed deltas);
#              spawn_citizens (int, handled by GameState — a wanderer joins the village).
# OPTIONAL "season" key (int SeasonSystem.Season, or an Array of them): the event is
# only eligible during that season — seasonal flavour tied to the visible calendar.
# Events with no "season" key fire year-round (back-compatible).
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

	# ── Choice events ─────────────────────────────────────────────────────────────
	# These carry a `choices` array instead of an `effect`; the realm waits on YOUR
	# decision (a popup) and the chosen option's effect is applied via a command.
	{
		"id": "barons_loan", "tone": "neutral", "weight": 7, "min_day": 6,
		"title": "A Baron's Offer",
		"text": "A neighbouring baron offers a loan of coin — generous, but you would be beholden to him.",
		"choices": [
			{"label": "Accept the loan (+150 gold, −6 popularity)", "effect": {"gold": 150, "popularity": -6}},
			{"label": "Decline — we stand on our own (+10 prestige)", "effect": {"prestige": 10}},
		],
	},
	{
		"id": "bandit_toll", "tone": "bad", "weight": 7, "min_day": 8,
		"title": "Brigands on the Road",
		"text": "Brigands have blocked the trade road and demand 40 gold to let your carts pass.",
		"choices": [
			{"label": "Pay the toll (−40 gold)", "effect": {"gold": -40}},
			{"label": "Refuse and drive them off (−20 food, +6 popularity)", "effect": {"food": -20, "popularity": 6}},
		],
	},
	{
		"id": "refugees_at_gate", "tone": "neutral", "weight": 7, "min_day": 5,
		"title": "Refugees at the Gate",
		"text": "A band of folk fleeing a burned village beg shelter within your walls.",
		"choices": [
			{"label": "Welcome them (+2 villagers, −25 food, +6 popularity)", "effect": {"spawn_citizens": 2, "food": -25, "popularity": 6}},
			{"label": "Turn them away (−4 popularity)", "effect": {"popularity": -4}},
		],
	},
	{
		"id": "traveling_scholar", "tone": "good", "weight": 6, "min_day": 7,
		"title": "A Traveling Scholar",
		"text": "A learned scholar seeks your hospitality, offering rare knowledge in return.",
		"choices": [
			{"label": "Host the scholar (−25 gold, +25 prestige)", "effect": {"gold": -25, "prestige": 25}},
			{"label": "Send him on his way", "effect": {}},
		],
	},
	{
		"id": "mysterious_relic", "tone": "neutral", "weight": 5, "min_day": 9,
		"title": "A Hooded Stranger",
		"text": "A hooded pedlar offers a 'holy relic' said to bless the harvest — for a price.",
		"choices": [
			{"label": "Buy the relic (−35 gold, +40 food)", "effect": {"gold": -35, "food": 40}},
			{"label": "A swindle — refuse (+4 popularity)", "effect": {"popularity": 4}},
		],
	},
	{
		"id": "master_mason", "tone": "neutral", "weight": 6, "min_day": 8,
		"title": "A Master Mason",
		"text": "A travelling master mason offers a wagon of dressed stone at a fair price — good for walls before the warlords march.",
		"choices": [
			{"label": "Commission the stone (−40 gold, +60 stone)", "effect": {"gold": -40, "stone": 60}},
			{"label": "Not this season", "effect": {}},
		],
	},
	{
		"id": "war_deserters", "tone": "neutral", "weight": 6, "min_day": 12,
		"title": "Deserters from the War",
		"text": "Soldiers fleeing a rival lord's levy beg leave to settle and lay down their spears.",
		"choices": [
			{"label": "Take them in (+3 villagers, −22 food, +3 popularity)", "effect": {"spawn_citizens": 3, "food": -22, "popularity": 3}},
			{"label": "Send them on — we want no quarrel (+6 prestige)", "effect": {"prestige": 6}},
		],
	},
	{
		"id": "saints_relic", "tone": "good", "weight": 5, "min_day": 10,
		"title": "Relic of the Saint",
		"text": "A wandering friar bears a saint's relic. Enshrine it for the people's devotion, or sell it for coin?",
		"choices": [
			{"label": "Enshrine it (−25 gold, +7 popularity, +15 prestige)", "effect": {"gold": -25, "popularity": 7, "prestige": 15}},
			{"label": "Sell it to a collector (+55 gold, −4 popularity)", "effect": {"gold": 55, "popularity": -4}},
		],
	},
	{
		"id": "midwinter_want", "tone": "bad", "weight": 7, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Midwinter Want",
		"text": "The cold bites hard and the poorest go hungry. Open the granary to them, or hold the stores against a longer winter?",
		"choices": [
			{"label": "Open the granary (−28 food, +9 popularity)", "effect": {"food": -28, "popularity": 9}},
			{"label": "Hold the stores (−6 popularity)", "effect": {"popularity": -6}},
		],
	},
	{
		"id": "spring_lambs", "tone": "good", "weight": 8, "min_day": 2,
		"season": SeasonSystem.Season.SPRING,
		"title": "The Ewes Have Lambed",
		"text": "Spring brings a strong crop of lambs — fresh meat and milk for the village.",
		"effect": {"food": 30},
	},

	# ── Seasonal events ─────────────────────────────────────────────────────────────
	# Gated to a season (see the "season" key) so the realm's mood turns with the
	# calendar: blossom fairs in spring, the harvest feast in autumn, hearth-tales in
	# the deep of winter. Positive-leaning, bounded — content that compounds per season.
	{
		"id": "spring_fair", "tone": "good", "weight": 8, "min_day": 2,
		"season": SeasonSystem.Season.SPRING,
		"title": "The Spring Fair",
		"text": "Pedlars and players come with the thaw; the green fills with stalls and laughter.",
		"effect": {"popularity": 5, "gold": 25},
	},
	{
		"id": "long_summer_days", "tone": "good", "weight": 8, "min_day": 12,
		"season": SeasonSystem.Season.SUMMER,
		"title": "Long Summer Days",
		"text": "The fields stand high under a generous sun; the smallfolk work glad and well-fed.",
		"effect": {"food": 30, "popularity": 3},
	},
	{
		"id": "summer_dry_spell", "tone": "bad", "weight": 6, "min_day": 12,
		"season": SeasonSystem.Season.SUMMER,
		"title": "A Dry Spell",
		"text": "Weeks without rain crack the earth; the wells run low and some crops wilt.",
		"effect": {"food": -22},
	},
	{
		"id": "harvest_home", "tone": "good", "weight": 11, "min_day": 24,
		"season": SeasonSystem.Season.AUTUMN,
		"title": "Harvest Home",
		"text": "The last sheaf is brought in. The whole realm feasts the harvest long into the night.",
		"effect": {"food": 40, "popularity": 6},
	},
	{
		"id": "hearth_tales", "tone": "good", "weight": 9, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Hearth Tales",
		"text": "The cold draws folk to the longhouse fire, where old songs and tales warm the dark.",
		"effect": {"popularity": 5},
	},
	{
		"id": "deep_frost", "tone": "bad", "weight": 6, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "A Deep Frost",
		"text": "A hard frost grips the stores; some of the winter larder is lost to the cold.",
		"effect": {"food": -22},
	},
	{
		"id": "harvest_moon", "tone": "good", "weight": 8, "min_day": 24,
		"season": SeasonSystem.Season.AUTUMN,
		"title": "A Harvest Moon",
		"text": "A great amber moon hangs over the fields; folk linger late, hopeful for the reaping.",
		"effect": {"popularity": 5},
	},
	{
		"id": "first_snow", "tone": "neutral", "weight": 6, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "The First Snow",
		"text": "The year's first snow settles soft on the rooftops; the children are delighted.",
		"effect": {"popularity": 3},
	},

	# ── More year-round happenings (content density) ────────────────────────────────
	{
		"id": "starlit_night", "tone": "neutral", "weight": 7, "min_day": 2,
		"title": "A Starlit Night",
		"text": "Clear skies and a sea of stars; the night watch keeps cheerful vigil.",
		"effect": {"popularity": 3},
	},
	{
		"id": "traveling_healer", "tone": "good", "weight": 6, "min_day": 4,
		"title": "A Traveling Healer",
		"text": "A kindly healer tends the sick and teaches the goodwives her remedies before moving on.",
		"effect": {"popularity": 5},
	},
	{
		"id": "river_bounty", "tone": "good", "weight": 8, "min_day": 3,
		"title": "The River Runs Thick",
		"text": "Shoals crowd the shallows; the village hauls in baskets of silver fish.",
		"effect": {"food": 30},
	},
	{
		"id": "chimney_fire", "tone": "bad", "weight": 5, "min_day": 7,
		"title": "A Chimney Fire",
		"text": "A careless hearth sets a roof ablaze; neighbours beat it out, but timber is lost.",
		"effect": {"wood": -18},
	},
	{
		"id": "master_craftsman", "tone": "good", "weight": 6, "min_day": 5,
		"title": "A Master Craftsman",
		"text": "A renowned craftsman settles in your town, drawing trade and quiet renown.",
		"effect": {"prestige": 15, "gold": 30},
	},
	{
		"id": "knight_errant", "tone": "neutral", "weight": 6, "min_day": 8,
		"title": "A Knight Errant",
		"text": "A wandering knight offers his sword and his fame to your house for a season — at a price.",
		"choices": [
			{"label": "Take him into service (−80 gold, +18 prestige)", "effect": {"gold": -80, "prestige": 18}},
			{"label": "Thank him and decline (+2 popularity)", "effect": {"popularity": 2}},
		],
	},
	{
		"id": "poachers_caught", "tone": "neutral", "weight": 6, "min_day": 7,
		"title": "Poachers in the Wood",
		"text": "Your foresters have caught hungry poachers taking deer from your land. Justice is yours to give.",
		"choices": [
			{"label": "Hang them — let justice be seen (−3 popularity, +10 prestige)", "effect": {"popularity": -3, "prestige": 10}},
			{"label": "Show mercy — they were starving (+6 popularity)", "effect": {"popularity": 6}},
		],
	},

	# ── Stone & iron happenings (close the materials gap — these feed walls & arms,
	#    the prep that lets a seat endure the warlords' sieges) ───────────────────────
	{
		"id": "quarry_seam", "tone": "good", "weight": 8, "min_day": 4,
		"title": "A Rich Quarry Seam",
		"text": "Your masons strike a clean seam of building stone — easy to cut and haul.",
		"effect": {"stone": 45},
	},
	{
		"id": "iron_vein", "tone": "good", "weight": 7, "min_day": 5,
		"title": "A Vein of Iron",
		"text": "Diggers turn up good iron ore in the hill diggings; the smith will be glad of it.",
		"effect": {"iron": 30},
	},
	{
		"id": "mine_cave_in", "tone": "bad", "weight": 5, "min_day": 9,
		"title": "A Shaft Caves In",
		"text": "A digging collapses in the night; cut stone is buried and a week's labour is lost.",
		"effect": {"stone": -18},
	},
	{
		"id": "traveling_smith", "tone": "good", "weight": 6, "min_day": 6,
		"title": "A Master Smith Passes Through",
		"text": "A renowned smith offers to work your iron before he travels on. To what end shall he set his hammer?",
		"choices": [
			{"label": "Forge tools for the fields (−20 iron, +30 food, +4 popularity)", "effect": {"iron": -20, "food": 30, "popularity": 4}},
			{"label": "Forge arms for the watch (−20 iron, +15 prestige)", "effect": {"iron": -20, "prestige": 15}},
		],
	},

	# ── More decisions (iter84 — variety over the 100-day reign) ─────────────────────
	{
		"id": "grand_tourney", "tone": "good", "weight": 6, "min_day": 14,
		"title": "A Grand Tourney",
		"text": "Knights clamour to break lances in your honour. A tourney would gladden the realm — but the coffers would feel it.",
		"choices": [
			{"label": "Host the tourney (−60 gold, +8 popularity, +12 prestige)", "effect": {"gold": -60, "popularity": 8, "prestige": 12}},
			{"label": "A quiet season — keep the coin", "effect": {}},
		],
	},
	{
		"id": "marriage_alliance", "tone": "neutral", "weight": 6, "min_day": 18,
		"title": "A Marriage Alliance",
		"text": "A neighbouring house offers a marriage to bind your lines. Their friendship is worth much — and a dowry is expected.",
		"choices": [
			{"label": "Pay the dowry (−70 gold, +20 prestige, +4 popularity)", "effect": {"gold": -70, "prestige": 20, "popularity": 4}},
			{"label": "Decline the match", "effect": {}},
		],
	},
	{
		"id": "neighbours_plea", "tone": "neutral", "weight": 6, "min_day": 10,
		"title": "A Neighbour's Plea",
		"text": "A neighbouring village, struck by fire, begs grain to see them through. Charity, or do you husband your own stores?",
		"choices": [
			{"label": "Send grain (−25 food, +6 popularity, +8 prestige)", "effect": {"food": -25, "popularity": 6, "prestige": 8}},
			{"label": "Refuse — our own come first (−3 popularity)", "effect": {"popularity": -3}},
		],
	},

	# ── Mid/late-game decisions (iter99 — keep the long middle fresh) ────────────────
	{
		"id": "master_builders_plan", "tone": "neutral", "weight": 5, "min_day": 30,
		"title": "A Master Builder's Plan",
		"text": "A renowned builder lays out plans for a grand work to crown your reign — costly, but the realm would speak of it for years.",
		"choices": [
			{"label": "Fund the grand work (−80 gold, −40 stone, +30 prestige, +5 popularity)", "effect": {"gold": -80, "stone": -40, "prestige": 30, "popularity": 5}},
			{"label": "The realm has greater needs", "effect": {}},
		],
	},
	{
		"id": "wandering_chronicler", "tone": "good", "weight": 6, "min_day": 25,
		"title": "A Wandering Chronicler",
		"text": "A chronicler asks to set down the tale of your reign for the ages. A flattering history is never free.",
		"choices": [
			{"label": "Host the chronicler (−30 gold, +25 prestige)", "effect": {"gold": -30, "prestige": 25}},
			{"label": "Send him on his way", "effect": {}},
		],
	},
	{
		"id": "border_skirmish", "tone": "bad", "weight": 6, "min_day": 35,
		"title": "A Border Skirmish",
		"text": "Raiders test the edge of your lands. Meet them in the field, or buy them off and keep your folk home?",
		"choices": [
			{"label": "Send the watch (−12 food, +8 prestige, +4 popularity)", "effect": {"food": -12, "prestige": 8, "popularity": 4}},
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
				parts.append("+%d villager" % amount)
			_:
				pass
	return ", ".join(parts)
