extends Node
# Autoload singleton. All player intent flows through here as typed Command dictionaries.
# Nothing in the simulation reads Input directly — PlayerInputHandler enqueues here,
# SimulationClock drains here at each fixed tick.

enum CommandType {
	# Economy
	SET_TAX_RATE,
	SET_RATION_FOOD,
	SET_RATION_ALE,
	DONATE_TO_CAPITAL,
	SET_TRADE_ROUTE,
	BUY_RESOURCE,
	SELL_RESOURCE,

	# Buildings
	PLACE_BUILDING,
	DEMOLISH_BUILDING,
	SET_BUILDING_WORKERS,
	UPGRADE_BUILDING,

	# Units
	RECRUIT_UNIT,
	ISSUE_MOVE_ORDER,
	ISSUE_ATTACK_ORDER,
	ISSUE_PATROL_ORDER,
	DISBAND_UNIT,

	# Edicts
	ACTIVATE_EDICT,

	# Selection / UI (view hints, processed but don't change sim state)
	SELECT_ENTITY,
	DESELECT,
	SET_BUILD_PREVIEW,

	# Simulation control
	SET_GAME_SPEED,
	TOGGLE_VIEW_MODE,
	ROTATE_VIEW,
	SAVE_GAME,
	LOAD_GAME,

	# Tech
	RESEARCH_TECH,

	# Diplomacy
	DIPLOMACY_RESPONSE,

	# Strategic / campaign layer (world-map kingdoms). Appended last so existing
	# CommandType integer values stay stable for saves & tests.
	DEVELOP_CITY,
	RAISE_ARMY,
	LAUNCH_CAMPAIGN,
	STRATEGIC_DIPLOMACY,
	RESOLVE_EVENT_CHOICE,   # player picked an option on a World Event (= int 31)
	SET_UNIT_STANCE,        # player set a unit's combat stance (guard/aggressive) (= int 32)
	DEBUG_SPAWN_ALL,        # dev cheat ('L'): muster a full army + max every stockpile (= int 33)
}

var _queue: Array[Dictionary] = []

func enqueue(cmd_type: CommandType, payload: Dictionary, player_id: int = 0) -> void:
	var command: Dictionary = {
		"type": cmd_type,
		"payload": payload,
		"player_id": player_id,
		"issued_at_tick": SimulationClock.current_tick,
	}
	_queue.append(command)
	EventBus.command_issued.emit(command)

func dequeue_all() -> Array[Dictionary]:
	var batch: Array[Dictionary] = _queue.duplicate()
	_queue.clear()
	return batch

func peek() -> Array[Dictionary]:
	return _queue.duplicate()

func clear() -> void:
	_queue.clear()

func serialize() -> Dictionary:
	return {"queue": _queue.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	_queue.clear()
	for item in data.get("queue", []):
		_queue.append(item)
