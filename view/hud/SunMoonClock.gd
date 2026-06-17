extends Control
# Day-cycle clock for the HUD. Tracks the ACTUAL light/dark cycle (SeasonSystem's
# day_night_phase / is_night, period DAY_NIGHT_TICKS — NOT the calendar day): the sun
# arcs across the sky through daylight and the moon arcs through night, in sync with the
# world's real lighting. Phase + season shown as text; the day number is in the tooltip.

var _f: float = 0.0        # 0..1 through the day/night cycle (0 = noon, 0.5 = midnight)
var _night: bool = false
var _phase: String = "Day"
var _season: String = "Spring"

# Sky tint per phase — subtle, behind the arc.
const _SKY: Dictionary = {
	"Dawn":  Color(0.45, 0.33, 0.40),
	"Day":   Color(0.26, 0.40, 0.52),
	"Dusk":  Color(0.45, 0.30, 0.22),
	"Night": Color(0.12, 0.13, 0.22),
}

# Night occupies the middle third of the cycle (centred on midnight, f = 0.5), matching
# SeasonSystem's NIGHT_HOME_THRESHOLD. Daylight is everything outside it (wraps past noon).
const NIGHT_START: float = 0.33
const NIGHT_END: float   = 0.67

func set_time(cycle_f: float, is_night: bool, phase: String, season: String, day_num: int) -> void:
	_f = clampf(cycle_f, 0.0, 1.0)
	_night = is_night
	_phase = phase
	_season = season
	tooltip_text = "Day %d · %s · %s" % [day_num, phase, season]
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var sky: Color = _SKY.get(_phase, _SKY["Day"])
	draw_rect(Rect2(0.0, 0.0, w, h), sky, true)
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.62, 0.49, 0.22, 0.6), false, 1.0)

	var horizon: float = h - 8.0
	draw_line(Vector2(4.0, horizon), Vector2(w - 4.0, horizon), Color(0.0, 0.0, 0.0, 0.35), 1.0)

	# Progress (0..1) across the CURRENTLY-VISIBLE body's span: the sun rises at the end of
	# night, peaks at noon, sets at the start of night; the moon spans the night third.
	var prog: float
	if _night:
		prog = clampf((_f - NIGHT_START) / (NIGHT_END - NIGHT_START), 0.0, 1.0)
	else:
		var day_span: float = (1.0 - NIGHT_END) + NIGHT_START   # daylight wraps through noon
		prog = clampf(fposmod(_f - NIGHT_END, 1.0) / day_span, 0.0, 1.0)

	var mx: float = lerpf(10.0, w - 10.0, prog)
	var my: float = horizon - sin(prog * PI) * (h * 0.5)
	if _night:
		draw_circle(Vector2(mx, my), 5.0, Color(0.90, 0.92, 1.0))      # moon
		draw_circle(Vector2(mx + 2.5, my - 1.0), 4.0, sky)            # crescent bite
	else:
		draw_circle(Vector2(mx, my), 7.0, Color(1.0, 0.82, 0.20, 0.30))  # halo
		draw_circle(Vector2(mx, my), 5.0, Color(1.0, 0.86, 0.28))        # sun

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(6.0, 13.0), "%s · %s" % [_phase, _season],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.97, 0.92, 0.78))
