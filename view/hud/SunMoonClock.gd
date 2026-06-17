extends Control
# Compact day-cycle clock for the HUD top bar. A sun (or moon at night) arcs across a
# tinted sky strip as the game-day progresses, so the passage of time reads continuously
# instead of a number that only jumps once per day. Phase + season shown as text; the raw
# day number lives in the tooltip (de-emphasised on purpose).

var _frac: float = 0.0          # 0..1 progress through the current game-day
var _phase: String = "Day"
var _season: String = "Spring"
var _night: bool = false

# Sky tint per phase — subtle, behind the arc.
const _SKY: Dictionary = {
	"Dawn":  Color(0.45, 0.33, 0.40),
	"Day":   Color(0.26, 0.40, 0.52),
	"Dusk":  Color(0.45, 0.30, 0.22),
	"Night": Color(0.12, 0.13, 0.22),
}

func set_time(frac: float, phase: String, season: String, day_num: int) -> void:
	_frac = clampf(frac, 0.0, 1.0)
	_phase = phase
	_season = season
	_night = (phase == "Night")
	tooltip_text = "Day %d · %s · %s" % [day_num, phase, season]
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# Sky strip.
	var sky: Color = _SKY.get(_phase, _SKY["Day"])
	draw_rect(Rect2(0.0, 0.0, w, h), sky, true)
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.62, 0.49, 0.22, 0.6), false, 1.0)

	# Horizon line.
	var horizon: float = h - 8.0
	draw_line(Vector2(4.0, horizon), Vector2(w - 4.0, horizon), Color(0.0, 0.0, 0.0, 0.35), 1.0)

	# Sun/moon arcs left→right, rising and setting (sin gives the dome height).
	var mx: float = lerpf(10.0, w - 10.0, _frac)
	var my: float = horizon - sin(_frac * PI) * (h * 0.5)
	if _night:
		# Moon: pale disc with a crescent bite.
		draw_circle(Vector2(mx, my), 5.0, Color(0.90, 0.92, 1.0))
		draw_circle(Vector2(mx + 2.5, my - 1.0), 4.0, sky)
	else:
		# Sun: bright disc with a soft halo.
		draw_circle(Vector2(mx, my), 7.0, Color(1.0, 0.82, 0.20, 0.30))
		draw_circle(Vector2(mx, my), 5.0, Color(1.0, 0.86, 0.28))

	# Phase + season caption (top-left).
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(6.0, 13.0), "%s · %s" % [_phase, _season],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.97, 0.92, 0.78))
