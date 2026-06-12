extends Node
# Autoload singleton. Drives the entire simulation at a fixed 20 Hz tick rate.
# This is the heartbeat of the MFA architecture:
#   _process accumulates real time → fires _advance_tick at fixed intervals →
#   drains CommandQueue → applies commands to GameState → ticks GameState economy.
#
# Game logic NEVER reads delta time from _process directly.
# All time-dependent math uses tick counts.

const TICK_RATE: float = 20.0
const TICK_INTERVAL: float = 1.0 / TICK_RATE

# One game day = 240 ticks at NORMAL speed (12 real seconds per game-day)
const TICKS_PER_GAME_DAY: int = 240

const SPEED_PAUSED: int = 0
const SPEED_NORMAL: int = 1
const SPEED_FAST: int = 2
const SPEED_FASTEST: int = 3

const SPEED_MULTIPLIERS: Dictionary = {
	SPEED_PAUSED: 0.0,
	SPEED_NORMAL: 1.0,
	SPEED_FAST: 2.0,
	SPEED_FASTEST: 5.0,
}

var current_tick: int = 0
var game_speed: int = SPEED_NORMAL
var _accumulator: float = 0.0

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	var multiplier: float = SPEED_MULTIPLIERS.get(game_speed, 1.0)
	if multiplier == 0.0:
		return
	_accumulator += delta * multiplier
	while _accumulator >= TICK_INTERVAL:
		_accumulator -= TICK_INTERVAL
		_advance_tick()

func _advance_tick() -> void:
	current_tick += 1
	var commands: Array[Dictionary] = CommandQueue.dequeue_all()
	for cmd in commands:
		GameState.apply_command(cmd)
	GameState.simulate_tick(current_tick)
	EventBus.simulation_tick.emit(current_tick)

func set_speed(speed: int) -> void:
	var old_speed: int = game_speed
	game_speed = clampi(speed, SPEED_PAUSED, SPEED_FASTEST)
	if old_speed != game_speed:
		EventBus.game_speed_changed.emit(SPEED_MULTIPLIERS.get(game_speed, 1.0))

func pause() -> void:
	set_speed(SPEED_PAUSED)

func resume() -> void:
	if game_speed == SPEED_PAUSED:
		set_speed(SPEED_NORMAL)

func is_paused() -> bool:
	return game_speed == SPEED_PAUSED

func game_day() -> int:
	return current_tick / TICKS_PER_GAME_DAY

func ticks_into_current_day() -> int:
	return current_tick % TICKS_PER_GAME_DAY

func serialize() -> Dictionary:
	return {
		"current_tick": current_tick,
		"game_speed": game_speed,
	}

func deserialize(data: Dictionary) -> void:
	current_tick = data.get("current_tick", 0)
	game_speed = data.get("game_speed", SPEED_NORMAL)
	_accumulator = 0.0
