extends Node
# Tutorial system (autoload). Guides new players through the core loop with brief
# contextual hints surfaced via the HUD notification feed. Self-contained: it holds
# its own progress and watches EventBus signals. A game session calls start().

signal tutorial_hint(message: String)

const STEP_PLACE_HALL       := 0
const STEP_PLACE_FARM       := 1
const STEP_BUILD_GRANARY    := 2
const STEP_OPEN_MARKET      := 3
const STEP_USE_EDICT        := 4
const STEP_DONE             := 99

var step: int = STEP_DONE  # inert until a game session calls start()
var _skipped: bool = false
var _last_edict_hint_tick: int = -999
var _defense_hint_given: bool = false  # the one-time "raise defences before the siege" warning

func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.edict_activated.connect(_on_edict_activated)
	EventBus.ai_envoy_sent.connect(_on_envoy_sent)
	EventBus.simulation_tick.connect(_on_tick)

func start() -> void:
	# Restore persisted step from world state if available
	var saved_step: int = GameState.world.get("tutorial_step", -1)
	if saved_step >= 0:
		step = saved_step
		return
	step = STEP_PLACE_HALL
	_save_step()
	tutorial_hint.emit("Welcome, commander. Open BUILD ▸ Civic and place your Village Hall to establish the settlement.")

func skip_tutorial() -> void:
	_skipped = true
	step = STEP_DONE
	_save_step()

func _save_step() -> void:
	GameState.world["tutorial_step"] = step

func _on_building_placed(_player_id: int, building_type: String, _gx: int, _gy: int, _bid: int) -> void:
	if _skipped: return
	match step:
		STEP_PLACE_HALL:
			if building_type in ["village_hall", "keep"]:
				step = STEP_PLACE_FARM
				_save_step()
				tutorial_hint.emit("Village Hall established. Now build Apple Orchards (BUILD ▸ Food) to feed the population — consumption is daily.")
		STEP_PLACE_FARM:
			if building_type in ["wheat_farm", "apple_orchard", "pig_farm", "dairy_farm"]:
				step = STEP_BUILD_GRANARY
				_save_step()
				tutorial_hint.emit("Good. Build a Granary next — food is only stored once you have storage for it.")
		STEP_BUILD_GRANARY:
			if building_type == "granary":
				step = STEP_OPEN_MARKET
				_save_step()
				tutorial_hint.emit("Food supply secured. Build a Market and open the trade panel (bottom bar) to buy and sell resources.")

func _on_gold_changed(_pid: int, _old: int, new_val: int) -> void:
	if _skipped or step != STEP_OPEN_MARKET: return
	# Any gold decrease after granary step = player bought something
	if new_val < _old:
		step = STEP_USE_EDICT
		_save_step()
		tutorial_hint.emit("Trade complete. Now issue an Edict (🏛 button) to boost the territory — Feast, Tax Holiday, or Morale campaign.")

func _on_edict_activated(_pid: int, _eid: String, _dur: int) -> void:
	if _skipped or step != STEP_USE_EDICT: return
	step = STEP_DONE
	_save_step()
	tutorial_hint.emit("Tutorial complete — you have the basics. Good luck, commander.")

func _on_envoy_sent(_fid: int, _demand: Dictionary) -> void:
	if _skipped or step != STEP_DONE: return
	tutorial_hint.emit("A rival faction is demanding tribute. Accept to maintain peace, or Refuse and prepare your defenses.")

func _on_tick(tick: int) -> void:
	if _skipped: return
	# Survival-critical and tutorial-step-independent: the original tutorial taught build/food/
	# market/edict but never DEFENCE, so a new player would reach the endgame siege undefended
	# (the seat is razed ~day 91). As the King's Peace nears its end, warn them — once — to raise
	# walls + a garrison while they still can.
	if not _defense_hint_given and not GameState.players.is_empty():
		var day: int = tick / 240
		if day >= 22 and not GameState.is_siege_ready(GameState.players[0]):
			_defense_hint_given = true
			tutorial_hint.emit("The ceasefire ends near Day 30 — after that, rival factions may move on your headquarters. Build walls and a watchtower (BUILD ▸ Defense) and station a garrison, or your base will fall.")
			return
	if step != STEP_DONE: return
	# Contextual edict hints every ~20 game-days (4800 ticks)
	if tick - _last_edict_hint_tick < 4800: return
	if GameState.players.is_empty(): return
	var p: Dictionary = GameState.players[0]
	var pop: float = p.get("popularity", 50.0)
	var diseased: bool = p.get("disease_active", false)
	var active_edict_ids: Array = []
	for ae in p.get("active_edicts", []):
		if ae is Dictionary: active_edict_ids.append(ae.get("id", ""))
	if pop < 35.0 and "festival_decree" not in active_edict_ids:
		tutorial_hint.emit("Approval is critically low. The Festival Decree gives an instant +8 popularity boost.")
		_last_edict_hint_tick = tick
	elif diseased:
		tutorial_hint.emit("An outbreak is spreading. Build more Apothecaries to increase coverage and contain it.")
		_last_edict_hint_tick = tick
