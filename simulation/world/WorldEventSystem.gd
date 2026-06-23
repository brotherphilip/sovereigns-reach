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

# Events are paced in SUN CYCLES (the visible day↔night cycle), not economic-days. One
# sun cycle = SeasonSystem.DAY_NIGHT_TICKS (18000t) = 75 economic-days = 5 on-screen
# calendar days. The old 45-day cooldown + 0.05 chance fired roughly once PER sun cycle
# (≈ "every 5 days" as the player saw it). Target now: one event every 3–5 sun cycles.
#   COOLDOWN = 3 sun cycles (225 economic-days) hard floor between events; then a small
#   per-day chance adds ~1 more sun cycle on average, landing the cadence at ~3–5 cycles.
const COOLDOWN_DAYS: int = 225   # = 3 sun cycles (3 × 75 economic-days) — hard minimum gap
const DAILY_CHANCE: float = 0.013 # per-day chance once off cooldown (~1 extra sun cycle mean)
# First-event grace (iter252): with the calm cadence above, the FIRST event takes ~77 econ-days on
# average, so ~27% of a 100-day single life saw NO realm event at all (the whole rich catalogue
# invisible that life — measured iter246/251). A player should MEET the event system once, early.
# So until the realm's first event has fired, use a higher per-day chance (mean ≈ 10 days once the
# early min_day events are eligible) — then the normal calm cadence resumes. This does NOT raise the
# realm's overall busyness (still ~1 event per 20-min life); it only guarantees that one lands early
# instead of maybe-never. Calm-realm directive preserved.
const FIRST_EVENT_CHANCE: float = 0.10

# Choice events (the agency-rich DILEMMAS — a Baron's loan, refugees at the gate, a feast) used to
# share the calm 225-day cooldown above with ambient flavour events, so in a ~100-day life a player
# saw at most ONE, and ~30 hand-written dilemmas sat unseen. They now run on their OWN, much faster
# track so a real decision lands every few minutes, drawn WITHOUT replacement so the catalogue cycles
# (~4 per life vs ~0-1). Ambient flavour stays calm. (iter354)
const CHOICE_COOLDOWN_DAYS: int = 16
const CHOICE_DAILY_CHANCE: float = 0.12
const FIRST_CHOICE_CHANCE: float = 0.22

# tone: "good" | "bad" | "neutral" — drives the notification colour.
# effect keys: food, gold, wood, stone, iron, popularity, prestige (signed deltas);
#              spawn_citizens (int, handled by GameState — a new arrival joins the settlement).
# OPTIONAL "season" key (int SeasonSystem.Season, or an Array of them): the event is
# only eligible during that season — seasonal events tied to the visible calendar.
# Events with no "season" key fire year-round (back-compatible).
const EVENTS: Array = [
	{
		"id": "wandering_merchant", "tone": "good", "weight": 12, "min_day": 2,
		"title": "A Merchant's Caravan",
		"text": "A trader's caravan has stopped by the village to barter its wares for coin.",
		"effect": {"gold": 60},
	},
	{
		"id": "bountiful_foraging", "tone": "good", "weight": 12, "min_day": 1,
		"title": "A Good Foraging",
		"text": "The foragers came back from the woods with a heavy haul for the stores.",
		"effect": {"food": 50},
	},
	{
		"id": "traveling_minstrels", "tone": "good", "weight": 10, "min_day": 2,
		"title": "Travelling Minstrels",
		"text": "A band of players passed through and lifted the spirits of the whole village.",
		"effect": {"popularity": 6},
	},
	{
		"id": "lost_traveler", "tone": "good", "weight": 8, "min_day": 3,
		"title": "A New Arrival",
		"text": "A wanderer with nowhere to go asks to settle here, and takes up an empty home.",
		"effect": {"spawn_citizens": 1},
	},
	{
		"id": "timber_windfall", "tone": "good", "weight": 9, "min_day": 2,
		"title": "Fallen Timber",
		"text": "A night of strong wind brought down old trees, good timber there for the taking.",
		"effect": {"wood": 45},
	},
	{
		"id": "wild_boar_hunt", "tone": "good", "weight": 9, "min_day": 3,
		"title": "A Good Hunt",
		"text": "The hunters brought down a great boar, and the larder is well stocked.",
		"effect": {"food": 35},
	},
	{
		"id": "good_omen", "tone": "neutral", "weight": 7, "min_day": 4,
		"title": "Good Faith",
		"text": "A hopeful mood is spreading among the people, and their faith in you grows.",
		"effect": {"prestige": 20, "popularity": 2},
	},
	{
		"id": "wedding_feast", "tone": "good", "weight": 8, "min_day": 5,
		"title": "A Wedding Feast",
		"text": "Two families were joined today, and the whole village turned out to celebrate.",
		"effect": {"popularity": 5},
	},
	{
		"id": "wolves_in_the_night", "tone": "bad", "weight": 7, "min_day": 6,
		"title": "Wolves in the Night",
		"text": "A wolf pack broke into the pens overnight, and some of the stores were lost.",
		"effect": {"food": -25},
	},
	{
		"id": "cart_mishap", "tone": "bad", "weight": 6, "min_day": 4,
		"title": "A Broken Cart",
		"text": "A cart broke down on the road, and a load of timber was spilled and spoiled.",
		"effect": {"wood": -20},
	},
	{
		"id": "petty_theft", "tone": "bad", "weight": 5, "min_day": 6,
		"title": "A Theft",
		"text": "A thief worked the market and slipped away with a purse of coin before he was caught.",
		"effect": {"gold": -30},
	},
	{
		"id": "minor_quarrel", "tone": "bad", "weight": 5, "min_day": 7,
		"title": "A Quarrel",
		"text": "A feud between two families spilled into the square and soured the village mood.",
		"effect": {"popularity": -4},
	},

	# ── Choice events ─────────────────────────────────────────────────────────────
	# These carry a `choices` array instead of an `effect`; the realm waits on YOUR
	# decision (a popup) and the chosen option's effect is applied via a command.
	{
		"id": "barons_loan", "tone": "neutral", "weight": 7, "min_day": 6,
		"title": "A Baron's Offer",
		"text": "A neighbouring baron offers a loan of gold now, but it leaves you in his debt.",
		"choices": [
			{"label": "Accept the credit (+150 gold, −6 popularity)", "effect": {"gold": 150, "popularity": -6}},
			{"label": "Decline — stay independent (+10 prestige)", "effect": {"prestige": 10}},
		],
	},
	{
		"id": "bandit_toll", "tone": "bad", "weight": 7, "min_day": 8, "hostile": true,
		"title": "Bandits on the Road",
		"text": "Raiders have blocked the eastern road and demand forty gold to let your carts pass.",
		"choices": [
			{"label": "Pay the toll (−40 gold)", "effect": {"gold": -40}},
			{"label": "Clear them by force (−20 food, +6 popularity)", "effect": {"food": -20, "popularity": 6}},
		],
	},
	{
		"id": "refugees_at_gate", "tone": "neutral", "weight": 7, "min_day": 5,
		"title": "Refugees at the Gate",
		"text": "Folk fleeing a ruined village beg for shelter within your walls.",
		"choices": [
			{"label": "Grant asylum (+2 population, −25 food, +6 popularity)", "effect": {"spawn_citizens": 2, "food": -25, "popularity": 6}},
			{"label": "Turn them away (−4 popularity)", "effect": {"popularity": -4}},
		],
	},
	{
		"id": "traveling_scholar", "tone": "good", "weight": 6, "min_day": 7,
		"title": "A Travelling Scholar",
		"text": "A learned traveller offers his knowledge in trade for a roof and a meal.",
		"choices": [
			{"label": "Host the specialist (−25 gold, +25 prestige)", "effect": {"gold": -25, "prestige": 25}},
			{"label": "Decline the offer", "effect": {}},
		],
	},
	{
		"id": "mysterious_relic", "tone": "neutral", "weight": 5, "min_day": 9,
		"title": "A Suspect Pedlar",
		"text": "A pedlar hawks a miracle remedy he swears will swell your harvests, for a price.",
		"choices": [
			{"label": "Buy the supplement (−35 gold, +40 food)", "effect": {"gold": -35, "food": 40}},
			{"label": "Refuse the scam (+4 popularity)", "effect": {"popularity": 4}},
		],
	},
	{
		"id": "master_mason", "tone": "neutral", "weight": 6, "min_day": 8,
		"title": "A Mason's Wares",
		"text": "A mason offers a load of cut stone at a fair price, good for your walls before trouble comes.",
		"choices": [
			{"label": "Buy the stone (−40 gold, +60 stone)", "effect": {"gold": -40, "stone": 60}},
			{"label": "Pass for now", "effect": {}},
		],
	},
	{
		"id": "war_deserters", "tone": "neutral", "weight": 6, "min_day": 12,
		"title": "Deserters",
		"text": "Men who fled a rival's army ask to lay down their arms and settle here.",
		"choices": [
			{"label": "Take them in (+3 population, −22 food, +3 popularity)", "effect": {"spawn_citizens": 3, "food": -22, "popularity": 3}},
			{"label": "Send them on — avoid the conflict (+6 prestige)", "effect": {"prestige": 6}},
		],
	},
	{
		"id": "saints_relic", "tone": "good", "weight": 5, "min_day": 10,
		"title": "A Holy Relic",
		"text": "A traveller carries a revered relic. Display it for the people, or sell it for gold?",
		"choices": [
			{"label": "Put it on display (−25 gold, +7 popularity, +15 prestige)", "effect": {"gold": -25, "popularity": 7, "prestige": 15}},
			{"label": "Sell it to a collector (+55 gold, −4 popularity)", "effect": {"gold": 55, "popularity": -4}},
		],
	},
	# ── Expanded content (iter169): more decisions + flavour, modern admin tone ──────
	{
		"id": "veteran_officer", "tone": "good", "weight": 7, "min_day": 9,
		"title": "A Veteran Captain",
		"text": "A seasoned captain offers to drill your men and stiffen their discipline.",
		"choices": [
			{"label": "Take him on (−35 gold, +18 prestige, +3 popularity)", "effect": {"gold": -35, "prestige": 18, "popularity": 3}},
			{"label": "Decline — the levy will do", "effect": {}},
		],
	},
	{
		"id": "smugglers_cache", "tone": "good", "weight": 8, "min_day": 5,
		"title": "Smugglers Caught",
		"text": "The watch caught a band of smugglers and seized their goods for the treasury.",
		"effect": {"gold": 55},
	},
	{
		"id": "well_fouled", "tone": "bad", "weight": 6, "min_day": 10,
		"title": "A Fouled Well",
		"text": "The village well was fouled in the night, and the water drawn from it must be poured out.",
		"effect": {"food": -24},
	},
	{
		"id": "guild_petition", "tone": "neutral", "weight": 7, "min_day": 11,
		"title": "A Tradesmen's Petition",
		"text": "The tradesmen ask you to fund new works — costly now, but it would raise the people's faith in your rule.",
		"choices": [
			{"label": "Fund the works (−45 gold, +8 popularity)", "effect": {"gold": -45, "popularity": 8}},
			{"label": "Set it aside (−3 popularity)", "effect": {"popularity": -3}},
		],
	},
	{
		"id": "envoy_gift", "tone": "good", "weight": 6, "min_day": 14,
		"title": "A Neighbour's Gift",
		"text": "A neighbouring lord sent an envoy bearing a gift of grain and gold in friendship.",
		"effect": {"gold": 35, "food": 25},
	},

	{
		"id": "midwinter_want", "tone": "bad", "weight": 7, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Winter Want",
		"text": "The cold bites hard and the poor go hungry. Open the stores to them, or hold them against a longer winter?",
		"choices": [
			{"label": "Open the stores (−28 food, +9 popularity)", "effect": {"food": -28, "popularity": 9}},
			{"label": "Hold the stores (−6 popularity)", "effect": {"popularity": -6}},
		],
	},
	{
		"id": "spring_lambs", "tone": "good", "weight": 8, "min_day": 2,
		"season": SeasonSystem.Season.SPRING,
		"title": "Spring Lambs",
		"text": "The spring brought a strong birth of lambs, fresh food for the village.",
		"effect": {"food": 30},
	},

	# ── Seasonal events ─────────────────────────────────────────────────────────────
	# Gated to a season (see the "season" key) so the realm's situation turns with the
	# calendar: markets in spring, peak yields in summer, the harvest in autumn, supply
	# strain in winter. Positive-leaning, bounded — content that compounds per season.
	{
		"id": "spring_fair", "tone": "good", "weight": 8, "min_day": 2,
		"season": SeasonSystem.Season.SPRING,
		"title": "A Spring Fair",
		"text": "Traders and crowds came with the thaw, and the market filled with trade.",
		"effect": {"popularity": 5, "gold": 25},
	},
	{
		"id": "long_summer_days", "tone": "good", "weight": 8, "min_day": 12,
		"season": SeasonSystem.Season.SUMMER,
		"title": "Long Summer Days",
		"text": "Long days and strong sun have the fields thriving, and the people are well fed.",
		"effect": {"food": 30, "popularity": 3},
	},
	{
		"id": "summer_dry_spell", "tone": "bad", "weight": 6, "min_day": 12,
		"season": SeasonSystem.Season.SUMMER,
		"title": "A Dry Spell",
		"text": "Weeks without rain have parched the ground, the water runs low, and some crops fail.",
		"effect": {"food": -22},
	},
	{
		"id": "harvest_home", "tone": "good", "weight": 11, "min_day": 24,
		"season": SeasonSystem.Season.AUTUMN,
		"title": "Harvest Home",
		"text": "The last of the harvest is in and the stores are full before winter. The village celebrates.",
		"effect": {"food": 40, "popularity": 6},
	},
	{
		"id": "hearth_tales", "tone": "good", "weight": 9, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "Hearth Tales",
		"text": "The cold drew the people together by the fire for warmth and company through the long nights.",
		"effect": {"popularity": 5},
	},
	{
		"id": "deep_frost", "tone": "bad", "weight": 6, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "A Hard Frost",
		"text": "A bitter freeze struck the storehouse, and some of the winter stores were lost to the cold.",
		"effect": {"food": -22},
	},
	{
		"id": "harvest_moon", "tone": "good", "weight": 8, "min_day": 24,
		"season": SeasonSystem.Season.AUTUMN,
		"title": "A Fine Harvest Ahead",
		"text": "Clear autumn weather has the people hopeful for the coming harvest.",
		"effect": {"popularity": 5},
	},
	{
		"id": "first_snow", "tone": "neutral", "weight": 6, "min_day": 36,
		"season": SeasonSystem.Season.WINTER,
		"title": "First Snow",
		"text": "The season's first snow settled over the village, a small joy, the children most of all.",
		"effect": {"popularity": 3},
	},

	# ── More year-round happenings (content density) ────────────────────────────────
	{
		"id": "starlit_night", "tone": "neutral", "weight": 7, "min_day": 2,
		"title": "A Quiet Night",
		"text": "Clear skies and calm, and the night watch reports a still and easy watch.",
		"effect": {"popularity": 3},
	},
	{
		"id": "traveling_healer", "tone": "good", "weight": 6, "min_day": 4,
		"title": "A Travelling Healer",
		"text": "A wandering healer tended the sick and taught the village folk before moving on.",
		"effect": {"popularity": 5},
	},
	{
		"id": "river_bounty", "tone": "good", "weight": 8, "min_day": 3,
		"title": "A Bountiful River",
		"text": "The fish ran thick in the shallows, and the nets brought in a great catch for the stores.",
		"effect": {"food": 30},
	},
	{
		"id": "chimney_fire", "tone": "bad", "weight": 5, "min_day": 7,
		"title": "A Hearth Fire",
		"text": "A hearth fire caught a roof. The people put it out, but some timber was lost.",
		"effect": {"wood": -18},
	},
	{
		"id": "master_craftsman", "tone": "good", "weight": 6, "min_day": 5,
		"title": "A Master Craftsman",
		"text": "A renowned craftsman has settled in your village, drawing trade and raising its name.",
		"effect": {"prestige": 15, "gold": 30},
	},
	{
		"id": "knight_errant", "tone": "neutral", "weight": 6, "min_day": 8,
		"title": "A Knight Errant",
		"text": "A seasoned warrior offers his sword and his name to your service for a season, for a price.",
		"choices": [
			{"label": "Bring him on (−80 gold, +18 prestige)", "effect": {"gold": -80, "prestige": 18}},
			{"label": "Decline the offer (+2 popularity)", "effect": {"popularity": 2}},
		],
	},
	{
		"id": "poachers_caught", "tone": "neutral", "weight": 6, "min_day": 7,
		"title": "Poachers Caught",
		"text": "The watch caught folk taking game from your land. The judgement is yours.",
		"choices": [
			{"label": "Make an example of them (−3 popularity, +10 prestige)", "effect": {"popularity": -3, "prestige": 10}},
			{"label": "Show leniency — they were starving (+6 popularity)", "effect": {"popularity": 6}},
		],
	},

	# ── Stone & iron happenings (close the materials gap — these feed fortifications &
	#    arms, the prep that lets a territory endure the hostile sieges) ───────────────
	{
		"id": "quarry_seam", "tone": "good", "weight": 8, "min_day": 4,
		"title": "A Good Seam",
		"text": "The quarrymen struck a clean seam of building stone, easy to cut and cart away.",
		"effect": {"stone": 45},
	},
	{
		"id": "iron_vein", "tone": "good", "weight": 7, "min_day": 5,
		"title": "An Iron Vein",
		"text": "The diggers found a rich vein of iron ore in the hills, and the forges will put it to use.",
		"effect": {"iron": 30},
	},
	{
		"id": "mine_cave_in", "tone": "bad", "weight": 5, "min_day": 9,
		"title": "A Cave-In",
		"text": "A mine shaft collapsed in the night, cut stone was buried, and a week's work was lost.",
		"effect": {"stone": -18},
	},
	{
		"id": "traveling_smith", "tone": "good", "weight": 6, "min_day": 6,
		"title": "A Travelling Smith",
		"text": "A skilled smith offers to work your iron before he moves on. Set him to his task.",
		"choices": [
			{"label": "Tools for agriculture (−20 iron, +30 food, +4 popularity)", "effect": {"iron": -20, "food": 30, "popularity": 4}},
			{"label": "Equipment for the troops (−20 iron, +15 prestige)", "effect": {"iron": -20, "prestige": 15}},
		],
	},

	# ── More decisions (variety over the 100-day run) ────────────────────────────────
	{
		"id": "grand_tourney", "tone": "good", "weight": 6, "min_day": 14,
		"title": "A Grand Tourney",
		"text": "The people clamour for a great tourney. It would lift their spirits, though the treasury would feel it.",
		"choices": [
			{"label": "Host the games (−60 gold, +8 popularity, +12 prestige)", "effect": {"gold": -60, "popularity": 8, "prestige": 12}},
			{"label": "Hold the budget", "effect": {}},
		],
	},
	{
		"id": "marriage_alliance", "tone": "neutral", "weight": 6, "min_day": 18,
		"title": "A Marriage Alliance",
		"text": "A neighbouring house offers a marriage to bind your families. Their friendship is worth much, and they expect a gift.",
		"choices": [
			{"label": "Pay for the alliance (−70 gold, +20 prestige, +4 popularity)", "effect": {"gold": -70, "prestige": 20, "popularity": 4}},
			{"label": "Decline the alliance", "effect": {}},
		],
	},
	{
		"id": "neighbours_plea", "tone": "neutral", "weight": 6, "min_day": 10,
		"title": "A Neighbour's Plea",
		"text": "A neighbouring village struck by fire begs for food. Aid them, or keep your own stores?",
		"choices": [
			{"label": "Send aid (−25 food, +6 popularity, +8 prestige)", "effect": {"food": -25, "popularity": 6, "prestige": 8}},
			{"label": "Refuse — our own first (−3 popularity)", "effect": {"popularity": -3}},
		],
	},

	# ── Mid/late-game decisions (keep the long middle fresh) ─────────────────────────
	{
		"id": "master_builders_plan", "tone": "neutral", "weight": 5, "min_day": 30,
		"title": "A Grand Design",
		"text": "A master builder proposes a great work to mark your reign. Costly, but it would be remembered for years.",
		"choices": [
			{"label": "Fund the project (−80 gold, −40 stone, +30 prestige, +5 popularity)", "effect": {"gold": -80, "stone": -40, "prestige": 30, "popularity": 5}},
			{"label": "Other priorities for now", "effect": {}},
		],
	},
	{
		"id": "wandering_chronicler", "tone": "good", "weight": 6, "min_day": 25,
		"title": "A Wandering Chronicler",
		"text": "A chronicler wishes to set down the tale of your reign. A kind telling is never free.",
		"choices": [
			{"label": "Grant access (−30 gold, +25 prestige)", "effect": {"gold": -30, "prestige": 25}},
			{"label": "Decline the request", "effect": {}},
		],
	},
	{
		"id": "border_skirmish", "tone": "bad", "weight": 6, "min_day": 35,
		"title": "A Border Raid",
		"text": "Raiders are testing the edge of your land. Meet them in the field, or pay them off and keep your men home?",
		"choices": [
			{"label": "Deploy the patrol (−12 food, +8 prestige, +4 popularity)", "effect": {"food": -12, "prestige": 8, "popularity": 4}},
			{"label": "Pay them off (−40 gold, −2 popularity)", "effect": {"gold": -40, "popularity": -2}},
		],
	},

	# ── New surprises (iter313): rarer windfalls, emergent arrivals, and barter/feast/gamble
	# choices that nudge the player off the optimal build order — content compounds, play stays fresh.
	{
		"id": "buried_hoard", "tone": "good", "weight": 4, "min_day": 8,
		"title": "A Buried Hoard",
		"text": "Digging a new cellar, your folk strike a clay jar of old coins green with age — some long-dead miser's secret, yours now.",
		"effect": {"gold": 85, "prestige": 10},
	},
	{
		"id": "rival_defector", "tone": "good", "weight": 6, "min_day": 6,
		"title": "A Craftsman Defects",
		"text": "A skilled hand flees a rival lord's harsh rule and begs to settle under your banner. Their loss is your gain.",
		"effect": {"spawn_citizens": 1, "popularity": 3},
	},
	{
		"id": "stray_warhound", "tone": "good", "weight": 6, "min_day": 4,
		"title": "A Stray Hound",
		"text": "A great hunting hound, lost from some lord's pack, takes up at your gate and will not be shooed. The children adore it.",
		"effect": {"popularity": 4},
	},
	{
		"id": "comets_passage", "tone": "neutral", "weight": 5, "min_day": 10,
		"title": "A Comet's Passage",
		"text": "A comet drags its pale tail across the night sky. The old folk argue bitterly whether it bodes glory or ruin.",
		"effect": {"prestige": 8},
	},
	{
		"id": "barter_caravan", "tone": "neutral", "weight": 7, "min_day": 5,
		"title": "The Barter Caravan",
		"text": "A foreign caravan will trade what it carries for what you can spare. Their wares are strange, their prices stranger.",
		"choices": [
			{"label": "Sell surplus grain (−30 food, +50 gold)", "effect": {"food": -30, "gold": 50}},
			{"label": "Trade timber for iron (−30 wood, +14 iron)", "effect": {"wood": -30, "iron": 14}},
			{"label": "Wave them on", "effect": {}},
		],
	},
	{
		"id": "feast_demanded", "tone": "neutral", "weight": 6, "min_day": 12,
		"title": "The People Want a Feast",
		"text": "After a hard stretch the folk grumble for a feast. A full table buys their love; an empty one, their muttering.",
		"choices": [
			{"label": "Throw the feast (−30 food, −20 gold, +9 popularity, +4 prestige)", "effect": {"food": -30, "gold": -20, "popularity": 9, "prestige": 4}},
			{"label": "Make them wait (−4 popularity)", "effect": {"popularity": -4}},
		],
	},
	{
		"id": "dowsers_promise", "tone": "neutral", "weight": 5, "min_day": 18,
		"title": "The Dowser's Promise",
		"text": "A dowser swears a rich seam runs beneath your hills — for a fee paid up front, of course.",
		"choices": [
			{"label": "Fund the dig (−40 gold, +35 stone, +8 iron)", "effect": {"gold": -40, "stone": 35, "iron": 8}},
			{"label": "Send the charlatan packing", "effect": {}},
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
static func tick(player: Dictionary, world: Dictionary, rng: RandomNumberGenerator, day: int, in_peace: bool = false) -> Dictionary:
	if day <= 0 or player.is_empty():
		return {}
	# Before the realm's very first event, use the higher first-event chance so the player reliably
	# MEETS the event system early (instead of ~27% of lives seeing none); afterwards, calm cadence.
	# Seasons key off the day/night calendar; convert this game-day to a tick for the lookup.
	var season: int = SeasonSystem.season_at_tick(day * SeasonSystem.TICKS_PER_DAY)

	# ── CHOICE-EVENT track (fast) ── the dilemmas fire on their own short cooldown so the player
	# faces a real decision every few minutes. They defer their effect until resolve().
	var first_choice: bool = not world.has("last_choice_day")
	var last_ch: int = int(world.get("last_choice_day", -999))
	if day - last_ch >= CHOICE_COOLDOWN_DAYS \
			and rng.randf() < (FIRST_CHOICE_CHANCE if first_choice else CHOICE_DAILY_CHANCE):
		var cev: Dictionary = _pick_event(world, rng, day, season, in_peace, true)
		if not cev.is_empty():
			world["last_choice_day"] = day
			return cev.duplicate(true)

	# ── AMBIENT track (calm) ── the original cadence, now over NON-choice flavour events only.
	var first_event: bool = not world.has("last_event_day")
	var last: int = int(world.get("last_event_day", -999))
	if day - last < COOLDOWN_DAYS:
		return {}
	if rng.randf() >= (FIRST_EVENT_CHANCE if first_event else DAILY_CHANCE):
		return {}
	var aev: Dictionary = _pick_event(world, rng, day, season, in_peace, false)
	if aev.is_empty():
		return {}
	world["last_event_day"] = day
	var result: Dictionary = aev.duplicate(true)
	result["summary"] = _apply_effect(player, aev.get("effect", {}))
	return result

# Weighted pick of one eligible event (filtered by min_day, season, peace, and choice-vs-ambient).
# For choice events, prefer ids not yet seen this life so the catalogue CYCLES (without replacement),
# resetting once it has been exhausted.
static func _pick_event(world: Dictionary, rng: RandomNumberGenerator, day: int, season: int, in_peace: bool, want_choices: bool) -> Dictionary:
	var seen: Dictionary = world.get("seen_choice_ids", {}) if want_choices else {}
	var pool: Array = []
	var fresh: Array = []
	var total: int = 0
	var fresh_total: int = 0
	for e in EVENTS:
		if has_choices(e) != want_choices:
			continue
		if in_peace and bool(e.get("hostile", false)):
			continue
		if day < int(e.get("min_day", 0)) or not _event_in_season(e, season):
			continue
		var w: int = int(e.get("weight", 1))
		pool.append(e); total += w
		if want_choices and not seen.has(e.get("id", "")):
			fresh.append(e); fresh_total += w
	var use_pool: Array = fresh if (want_choices and not fresh.is_empty()) else pool
	var use_total: int = fresh_total if (want_choices and not fresh.is_empty()) else total
	if use_pool.is_empty() or use_total <= 0:
		return {}
	var roll: int = rng.randi_range(0, use_total - 1)
	var chosen: Dictionary = use_pool[0]
	var cumulative: int = 0
	for e in use_pool:
		cumulative += int(e.get("weight", 1))
		if roll < cumulative:
			chosen = e
			break
	if want_choices:
		seen[chosen.get("id", "")] = true
		# Whole catalogue cycled (this was the last fresh one) → reset so dilemmas can recur.
		if fresh.size() <= 1:
			seen = {}
		world["seen_choice_ids"] = seen
	return chosen

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
