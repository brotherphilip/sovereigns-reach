extends RefCounted
# Difficulty scaling. A preloaded static-state class (NOT an autoload): the static
# simulation helpers (AIFaction, TaxSystem, FoodSystem) read it via preload + static
# call, which is safe under headless --script tests — referencing an autoload from a
# static RefCounted is not. Set DifficultySystem.current from the main menu; the value
# (a static var) is shared across every preload of this script and persists across scenes.

enum Level { PEACEFUL, NORMAL, HARD, SIEGE_LORD }

static var current: int = Level.NORMAL

const _MODIFIERS := {
	Level.PEACEFUL:   {"ai_threat": 0.3, "tax_income": 1.3, "food_consumption": 0.7,  "needs_burn": 0.7},
	Level.NORMAL:     {"ai_threat": 1.0, "tax_income": 1.0, "food_consumption": 1.0,  "needs_burn": 1.0},
	Level.HARD:       {"ai_threat": 1.6, "tax_income": 0.85, "food_consumption": 1.25, "needs_burn": 1.3},
	Level.SIEGE_LORD: {"ai_threat": 2.5, "tax_income": 0.7, "food_consumption": 1.5,  "needs_burn": 1.6},
}

static func get_mod(key: String) -> float:
	return _MODIFIERS[current].get(key, 1.0)

static func level_name(lvl: int) -> String:
	return Level.keys()[lvl].capitalize()

# One-line, player-facing description of what each difficulty actually changes (derived from the
# modifiers above) — so the menu choice that shapes the whole run isn't made blind. (iter356)
const _BLURBS := {
	Level.PEACEFUL:   "Gentle: rivals rarely march, coffers flow, your folk are hardy. To learn the realm.",
	Level.NORMAL:     "Balanced: a fair test for a rising sovereign.",
	Level.HARD:       "Harsh: bolder rivals, leaner taxes, hungrier and colder people.",
	Level.SIEGE_LORD: "Brutal: relentless sieges; every winter and coin bites deep. For veterans.",
}

static func level_blurb(lvl: int) -> String:
	return _BLURBS.get(lvl, "")
