extends RefCounted
# Maps every worker-employing building to a job: the worker's title, work animation
# archetype, tunic colour, tool, and (for smiths) whether the work throws sparks.
# Pure data — shared by the simulation (CitizenSystem assigns the job) and the view
# (CitizenLayer draws the outfit/tool/animation).
#
# Animation archetypes (drawn in CitizenLayer):
#   chop   — horizontal axe swing            mine  — overhead pick, swing down
#   scythe — low sweeping cut                pick  — reach up to a tree/vine
#   hammer — overhead hammer (sparks=metal)  stir  — paddle/stir in front
#   tend   — crouch to feed/milk             serve — hold an item out, bob
#   pray   — arms raised, sway               guard — stand at arms, scan
#   carry  — sack on the shoulder

const JOBS: Dictionary = {
	# ── Harvesting ──────────────────────────────────────────────────────────
	"woodcutter_camp": {"job": "Woodcutter",  "anim": "chop",  "tunic": Color(0.35, 0.46, 0.28), "tool": "axe"},
	"stone_quarry":    {"job": "Quarryman",   "anim": "mine",  "tunic": Color(0.55, 0.55, 0.58), "tool": "pick"},
	"iron_mine":       {"job": "Miner",       "anim": "mine",  "tunic": Color(0.30, 0.31, 0.36), "tool": "pick", "helmet": true},
	"pitch_rig":       {"job": "Pitchman",    "anim": "stir",  "tunic": Color(0.28, 0.24, 0.20), "tool": "paddle"},
	# ── Food ────────────────────────────────────────────────────────────────
	"apple_orchard":   {"job": "Orchardist",  "anim": "pick",  "tunic": Color(0.40, 0.55, 0.30), "tool": "basket"},
	"pig_farm":        {"job": "Swineherd",   "anim": "tend",  "tunic": Color(0.50, 0.40, 0.26), "tool": "staff"},
	"dairy_farm":      {"job": "Dairymaid",   "anim": "tend",  "tunic": Color(0.85, 0.82, 0.72), "tool": "pail"},
	"wheat_farm":      {"job": "Reaper",      "anim": "scythe","tunic": Color(0.70, 0.60, 0.35), "tool": "scythe"},
	"hops_farm":       {"job": "Hop-picker",  "anim": "pick",  "tunic": Color(0.45, 0.50, 0.25), "tool": "basket"},
	"mill":            {"job": "Miller",      "anim": "carry", "tunic": Color(0.82, 0.80, 0.74), "tool": "sack"},
	"bakery":          {"job": "Baker",       "anim": "stir",  "tunic": Color(0.80, 0.74, 0.62), "tool": "paddle"},
	"brewery":         {"job": "Brewer",      "anim": "stir",  "tunic": Color(0.45, 0.32, 0.20), "tool": "paddle"},
	"inn":             {"job": "Innkeeper",   "anim": "serve", "tunic": Color(0.55, 0.28, 0.28), "tool": "mug"},
	"granary":         {"job": "Granary-keeper","anim": "carry","tunic": Color(0.62, 0.54, 0.36), "tool": "sack"},
	# ── Civic ───────────────────────────────────────────────────────────────
	"market":          {"job": "Marketeer",   "anim": "serve", "tunic": Color(0.55, 0.35, 0.55), "tool": "goods"},
	"apothecary":      {"job": "Apothecary",  "anim": "stir",  "tunic": Color(0.45, 0.32, 0.55), "tool": "mortar"},
	"guildhall":       {"job": "Clerk",       "anim": "serve", "tunic": Color(0.32, 0.40, 0.58), "tool": "scroll"},
	"church":          {"job": "Priest",      "anim": "pray",  "tunic": Color(0.22, 0.20, 0.26), "tool": "book", "robe": true},
	"cathedral":       {"job": "Priest",      "anim": "pray",  "tunic": Color(0.20, 0.18, 0.24), "tool": "book", "robe": true},
	"trading_post":    {"job": "Trader",      "anim": "serve", "tunic": Color(0.58, 0.46, 0.22), "tool": "coin"},
	# ── Military / workshops ────────────────────────────────────────────────
	"fletcher":        {"job": "Fletcher",    "anim": "hammer","tunic": Color(0.46, 0.36, 0.24), "tool": "knife"},
	"poleturner":      {"job": "Poleturner",  "anim": "hammer","tunic": Color(0.48, 0.38, 0.26), "tool": "pole"},
	"blacksmith":      {"job": "Blacksmith",  "anim": "hammer","tunic": Color(0.26, 0.24, 0.26), "tool": "hammer", "sparks": true},
	"tannery":         {"job": "Tanner",      "anim": "stir",  "tunic": Color(0.44, 0.32, 0.22), "tool": "scraper"},
	"armorer":         {"job": "Armorer",     "anim": "hammer","tunic": Color(0.28, 0.28, 0.32), "tool": "hammer", "sparks": true},
	"crossbow_workshop":{"job": "Bowyer",     "anim": "hammer","tunic": Color(0.46, 0.36, 0.24), "tool": "knife"},
	"siege_workshop":  {"job": "Engineer",    "anim": "hammer","tunic": Color(0.44, 0.36, 0.26), "tool": "hammer"},
	"watchtower":      {"job": "Watchman",    "anim": "guard", "tunic": Color(0.40, 0.42, 0.48), "tool": "spear"},
}

const DEFAULT: Dictionary = {"job": "Laborer", "anim": "carry", "tunic": Color(0.50, 0.40, 0.28), "tool": "sack"}

# Job style for a building type, or {} if that building employs no workers.
static func for_building(btype: String) -> Dictionary:
	return JOBS.get(btype, {})

# Style for a job_type previously stored on a citizen (or DEFAULT).
static func style(job_type: String) -> Dictionary:
	for key in JOBS:
		if JOBS[key]["job"] == job_type:
			return JOBS[key]
	return DEFAULT

static func employs_workers(btype: String) -> bool:
	return JOBS.has(btype)
