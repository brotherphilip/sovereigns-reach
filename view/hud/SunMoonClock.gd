extends Control
# Day-cycle clock for the HUD. Tracks the ACTUAL light/dark cycle (SeasonSystem's
# day_night_phase / is_night, period DAY_NIGHT_TICKS — NOT the calendar day): the sun
# arcs across the sky through daylight and the moon arcs through night, in sync with the
# world's real lighting. Only the phase ("Day"/"Night"/…) is shown as text — the SEASON
# lives in the HUD weather label, so it is NOT repeated here (only in this clock's tooltip).

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

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

	# Night window in cycle-fraction terms comes from SeasonSystem (the SAME curve that
	# drives the world darkening and the "Night" label) so the moon icon shows exactly when
	# the world is dark and the label reads "Night" — they can never disagree.
	var nw: Vector2 = SeasonSystem.night_window()
	var night_start: float = nw.x
	var night_end: float = nw.y

	# Progress (0..1) across the CURRENTLY-VISIBLE body's span: the sun rises at the end of
	# night, peaks at noon, sets at the start of night; the moon spans the night window.
	var prog: float
	if _night:
		prog = clampf((_f - night_start) / maxf(0.001, night_end - night_start), 0.0, 1.0)
	else:
		var day_span: float = (1.0 - night_end) + night_start   # daylight wraps through noon
		prog = clampf(fposmod(_f - night_end, 1.0) / maxf(0.001, day_span), 0.0, 1.0)

	var mx: float = lerpf(10.0, w - 10.0, prog)
	var my: float = horizon - sin(prog * PI) * (h * 0.5)
	if _night:
		draw_circle(Vector2(mx, my), 5.0, Color(0.90, 0.92, 1.0))      # moon
		draw_circle(Vector2(mx + 2.5, my - 1.0), 4.0, sky)            # crescent bite
	else:
		draw_circle(Vector2(mx, my), 7.0, Color(1.0, 0.82, 0.20, 0.30))  # halo
		draw_circle(Vector2(mx, my), 5.0, Color(1.0, 0.86, 0.28))        # sun

	# Phase only — the season is shown in the HUD weather label (no duplicate "Spring").
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(6.0, 13.0), _phase,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.97, 0.92, 0.78))
