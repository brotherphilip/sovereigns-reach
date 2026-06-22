extends Node2D
# Day/night DARKENING WASH for the city view (added to _world_root above the world).
# The warm building lights are a SEPARATE additive layer (NightLampLayer) drawn on top
# of this wash, so lamps genuinely brighten the night rather than just tint it.
# Self-driven from the simulation clock.

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

const MAX_DARK: float = 0.70        # deepest-night wash alpha — moonlit, not pitch-black (roofs/ground stay legible)
const NIGHT_TINT: Color = Color(0.12, 0.15, 0.27)   # deep moonlight blue (lifted floor — readable, not a cave)
const DUSK_TINT: Color  = Color(0.34, 0.15, 0.05)   # warm sunset/sunrise glow

var _night: float = 0.0

func _process(_delta: float) -> void:
	var n: float = SeasonSystem.night_factor(SimulationClock.current_tick)
	if n > 0.02 or _night > 0.02:
		_night = n
		queue_redraw()
	else:
		_night = n

func _draw() -> void:
	if _night < 0.03:
		return
	# Darkening wash over the whole iso map (huge rect; it pans/zooms with the world).
	# Hue grades warm (dusk/dawn) → cool moonlit blue (deep night).
	var grade: float = smoothstep(0.2, 0.7, _night)
	var tint: Color = DUSK_TINT.lerp(NIGHT_TINT, grade)
	draw_rect(Rect2(Vector2(-9000, -3000), Vector2(18000, 12000)),
		Color(tint.r, tint.g, tint.b, _night * MAX_DARK))
