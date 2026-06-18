extends Node
# Tutorial system (autoload). A data-driven curriculum that walks a new commander through
# the full core loop: settle → feed → store → grow population → trade → health → military →
# defense → policy → research, then points them at the world map to expand. Each step names
# the exact thing to do; the HUD greys everything else and highlights the target (see
# current_target()). While the tutorial is active, enemy AI is paused (GameState._ai_paused).

signal tutorial_hint(message: String)
signal tutorial_step_changed(step_index: int)   # HUD re-gates / re-highlights on this

const STEP_DONE: int = 99

# Build category ints — match BuildingRegistry.Category and the HUD build tabs
# (["Civic","Harvest","Food","Military","Defense"]).
const CAT_CIVIC: int    = 0
const CAT_HARVEST: int  = 1
const CAT_FOOD: int     = 2
const CAT_MILITARY: int = 3
const CAT_DEFENSE: int  = 4

# The curriculum. kind: "build" (place `build` in tab `cat`) | "edict" | "research".
const STEPS: Array = [
	{"kind": "build", "cat": CAT_CIVIC, "build": "village_hall",
		"hint": "Welcome, my lord. Open the Build menu, the Civic tab, and place your Village Hall to found your settlement."},
	{"kind": "build", "cat": CAT_HARVEST, "build": "woodcutter_camp",
		"hint": "Wood builds everything. Open the Harvest tab and raise a Woodcutter's Camp — without timber flowing in, your works will stall."},
	{"kind": "build", "cat": CAT_FOOD, "build": "apple_orchard",
		"hint": "Now feed your people. Build an Apple Orchard from the Food tab — your people eat every day."},
	{"kind": "build", "cat": CAT_FOOD, "build": "granary",
		"hint": "Now store your food: build a Granary. Food only keeps once you have somewhere to put it."},
	{"kind": "build", "cat": CAT_CIVIC, "build": "hovel",
		"hint": "Grow your people: build a Hovel from the Civic tab. Homes and spare food let new folk be born to work your land."},
	{"kind": "build", "cat": CAT_CIVIC, "build": "market",
		"hint": "Trade with your neighbours: build a Market, then use the trade panel below to buy and sell goods."},
	{"kind": "build", "cat": CAT_CIVIC, "build": "apothecary",
		"hint": "Guard your people's health: build an Apothecary from the Civic tab to treat sickness before it spreads."},
	{"kind": "build", "cat": CAT_MILITARY, "build": "barracks",
		"hint": "Raise fighting men: build a Barracks from the Military tab to train soldiers and a guard."},
	{"kind": "build", "cat": CAT_DEFENSE, "build": "lookout_tower",
		"hint": "Fortify your hall: build a Watchtower from the Defence tab. Rival houses will march on you once the peace ends."},
	{"kind": "edict",
		"hint": "Proclaim a decree from the policy button to aid your realm — choose a Feast, a Tax Holiday, or a call to raise spirits."},
	{"kind": "research",
		"hint": "Seek new learning: open the Tech tree and study an advance to unlock stronger buildings and boons."},
]

var index: int = -1            # -1 inert; 0..STEPS.size()-1 active; STEP_DONE complete
var _skipped: bool = false
var _research_baseline: int = -1
var _last_edict_hint_tick: int = -999
var _defense_hint_given: bool = false

func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.edict_activated.connect(_on_edict_activated)
	EventBus.ai_envoy_sent.connect(_on_envoy_sent)
	EventBus.simulation_tick.connect(_on_tick)

# ── Lifecycle ───────────────────────────────────────────────────────────────────

func start() -> void:
	var saved: int = GameState.world.get("tutorial_index", -999)
	if saved != -999 and saved != -1:
		index = saved
		if index != STEP_DONE:
			GameState.world["tutorial_active"] = true
		return
	index = 0
	_skipped = false
	GameState.world["tutorial_index"] = index
	GameState.world["tutorial_active"] = true   # freeze enemy AI while learning
	_emit_step()

func skip_tutorial() -> void:
	_skipped = true
	index = STEP_DONE
	GameState.world["tutorial_index"] = STEP_DONE
	GameState.world["tutorial_active"] = false   # resume enemy AI
	tutorial_step_changed.emit(STEP_DONE)

func is_active() -> bool:
	return not _skipped and index >= 0 and index != STEP_DONE

# What the player must do NOW, for the HUD to gate/highlight. {} when inactive.
func current_target() -> Dictionary:
	if not is_active() or index >= STEPS.size():
		return {}
	var s: Dictionary = STEPS[index]
	return {"kind": String(s.get("kind", "")), "cat": int(s.get("cat", -1)), "build": String(s.get("build", ""))}

# ── Step flow ───────────────────────────────────────────────────────────────────

func _emit_step() -> void:
	if index < 0 or index >= STEPS.size():
		return
	if String(STEPS[index].get("kind", "")) == "research":
		_research_baseline = _player_tech_count()
	tutorial_hint.emit(String(STEPS[index]["hint"]))
	tutorial_step_changed.emit(index)

func _advance() -> void:
	index += 1
	GameState.world["tutorial_index"] = index
	GameState.world["tutorial_awaiting_build"] = false
	if index >= STEPS.size():
		index = STEP_DONE
		GameState.world["tutorial_index"] = STEP_DONE
		GameState.world["tutorial_active"] = false   # resume enemy AI
		tutorial_hint.emit("The lesson is done. Your settlement stands. To grow your realm, open the World Map, develop your village, raise an army, and take a neighbouring village — climb from Reeve to King. Good fortune, my lord.")
		tutorial_step_changed.emit(STEP_DONE)
		return
	_emit_step()

func _expects(kind: String) -> bool:
	return is_active() and index < STEPS.size() and String(STEPS[index].get("kind", "")) == kind

# ── Completion triggers ─────────────────────────────────────────────────────────

# Does `building_type` satisfy the current build step? Forgiving: any farm for the food
# step, any seat for the hall, any wall/tower for the defence step.
func _matches_want(building_type: String) -> bool:
	var want: String = String(STEPS[index].get("build", ""))
	if building_type == want:
		return true
	if want == "apple_orchard" and building_type in ["apple_orchard", "wheat_farm", "pig_farm", "dairy_farm"]:
		return true
	if want == "village_hall" and building_type in ["village_hall", "keep"]:
		return true
	if want == "lookout_tower" and building_type in ["lookout_tower", "watchtower", "great_tower", "wooden_palisade", "stone_wall", "gatehouse"]:
		return true
	return false

# True once a matching building exists AND is fully raised (not just placed).
func _want_is_built() -> bool:
	if GameState.players.is_empty():
		return false
	for b in GameState.players[0].get("buildings", []):
		if b is Dictionary and b.get("built", false) and _matches_want(String(b.get("type", ""))):
			return true
	return false

func _on_building_placed(_pid: int, building_type: String, _gx: int, _gy: int, _bid: int) -> void:
	# Placement no longer advances the lesson — the next step waits until this building is
	# fully BUILT (see _on_tick). On a correct placement, nudge the player to let it rise.
	if not _expects("build") or not _matches_want(building_type):
		return
	if not bool(GameState.world.get("tutorial_awaiting_build", false)):
		GameState.world["tutorial_awaiting_build"] = true
		tutorial_hint.emit("Good — now let your builders raise it. Fetch the timber, stack it, and build. The next task waits until it stands.")

func _on_gold_changed(_pid: int, _old_v: int, _new_v: int) -> void:
	pass  # trade is taught in the Market step's hint; no separate gate

func _on_edict_activated(_pid: int, _eid: String, _dur: int) -> void:
	if _expects("edict"):
		_advance()

func _player_tech_count() -> int:
	if GameState.players.is_empty():
		return 0
	return int(GameState.players[0].get("tech_unlocks", []).size())

func _on_envoy_sent(_fid: int, _demand: Dictionary) -> void:
	# Don't interrupt the guided sequence; the post-tutorial player still gets the warning.
	if is_active():
		return
	tutorial_hint.emit("A rival house demands tribute. Pay to keep the peace, or refuse and ready your walls.")

func _on_tick(tick: int) -> void:
	# Build steps advance only once the placed structure is fully RAISED — so each prompt
	# (woodcutter, food, …) is held back until the prior building finishes building.
	if _expects("build") and _want_is_built():
		_advance()
		return
	# Research step has no dedicated signal — detect a newly-unlocked tech.
	if _expects("research") and _research_baseline >= 0 and _player_tech_count() > _research_baseline:
		_advance()
		return
	# Contextual hints only fire OUTSIDE the guided sequence (after done/skip).
	if is_active():
		return
	if not _defense_hint_given and not GameState.players.is_empty():
		var day: int = tick / SimulationClock.TICKS_PER_CALENDAR_DAY
		if day >= 3 and not GameState.is_siege_ready(GameState.players[0]):
			_defense_hint_given = true
			tutorial_hint.emit("The peace ends near Day 4 — after that, rival houses may march on your hall. Build walls and a watchtower (Build, Defence) and station a guard, or your hall will fall.")
			return
	if tick - _last_edict_hint_tick < 4800:
		return
	if GameState.players.is_empty():
		return
	var p: Dictionary = GameState.players[0]
	var pop: float = p.get("popularity", 50.0)
	var diseased: bool = p.get("disease_active", false)
	var active_edict_ids: Array = []
	for ae in p.get("active_edicts", []):
		if ae is Dictionary: active_edict_ids.append(ae.get("id", ""))
	if pop < 35.0 and "festival_decree" not in active_edict_ids:
		tutorial_hint.emit("Your people's faith is dangerously low. The Festival Decree will lift their spirits at once (+8).")
		_last_edict_hint_tick = tick
	elif diseased:
		tutorial_hint.emit("A sickness is spreading. Build more Apothecaries to widen your care and contain it.")
		_last_edict_hint_tick = tick
