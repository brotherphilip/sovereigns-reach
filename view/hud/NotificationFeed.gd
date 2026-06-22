extends Panel
# Docked, live event feed (left side, under the World Map button). Newest message sits at the
# BOTTOM; the panel keeps a rolling history the player can scroll. A header toggle DROPS the panel
# down to a taller box so past messages can be read, then collapses it back to a compact strip.
# Replaces the old top-of-screen toast stack. View-only: call push().

const WIDTH: float        = 330.0
const COLLAPSED_H: float  = 132.0   # compact strip — shows the few most recent events
const EXPANDED_H: float   = 360.0   # dropped-down — scroll back through history
const MAX_HISTORY: int    = 200
const FADE_IN_DUR: float  = 0.25

const DEDUPE_WINDOW_SEC: float = 6.0   # drop a message identical to the last within this window

var _log: VBoxContainer = null
var _scroll: ScrollContainer = null
var _toggle: Button = null
var _expanded: bool = false
var _last_text: String = ""
var _last_text_time: float = -1000.0

func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, COLLAPSED_H)
	size = Vector2(WIDTH, COLLAPSED_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 6; root.offset_top = 6
	root.offset_right = -6; root.offset_bottom = -6
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	# Header: title + the expand/collapse ("History") toggle.
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 18)
	root.add_child(header)
	var title := Label.new()
	title.text = "EVENTS"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_toggle = Button.new()
	_toggle.flat = true
	_toggle.text = "▼ History"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.add_theme_font_size_override("font_size", 10)
	_toggle.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	_toggle.pressed.connect(_on_toggle)
	header.add_child(_toggle)

	# Scrollable message log (newest appended at the bottom).
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_constant_override("separation", 5)   # gap between posts
	_scroll.add_child(_log)

# Add a message at the TOP; older posts slide down beneath it. `duration` is kept for call-site
# compatibility but the feed is now a persistent log (messages stay so the player can scroll back),
# so it is ignored. Each post sits in its own panel with a faint alternating tint for definition.
func push(text: String, _duration: float = 3.0, color: Color = Color.YELLOW) -> void:
	if _log == null:
		return
	# Spam guard: ignore a message identical to the most recent one if it arrives within a
	# few seconds, so no channel (weather, etc.) can flood the feed with repeats.
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if text == _last_text and (now - _last_text_time) < DEDUPE_WINDOW_SEC:
		return
	_last_text = text
	_last_text_time = now
	while _log.get_child_count() >= MAX_HISTORY:
		var oldest := _log.get_child(_log.get_child_count() - 1)   # oldest is at the bottom now
		_log.remove_child(oldest)
		oldest.queue_free()
	var row := PanelContainer.new()
	row.modulate.a = 0.0
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	_log.add_child(row)
	_log.move_child(row, 0)         # newest at the top
	_restripe()                     # re-tint so the zebra stays aligned to position, not age
	create_tween().tween_property(row, "modulate:a", 1.0, FADE_IN_DUR)
	# Newest is at the top, so keep the view pinned there (max isn't valid until laid out).
	call_deferred("_scroll_to_top")

# Re-apply the alternating row tint by current position (top row = index 0). Done on every insert
# because prepending shifts every row's parity.
func _restripe() -> void:
	for i in _log.get_child_count():
		var row := _log.get_child(i)
		if row is PanelContainer:
			row.add_theme_stylebox_override("panel", _row_style(i % 2 == 0))

func _row_style(even: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	# Faint shift over the panel's parchment-dark bg — just enough to bound each post.
	s.bg_color = Color(0.20, 0.16, 0.11, 0.45) if even else Color(0.10, 0.08, 0.06, 0.45)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	return s

func _on_toggle() -> void:
	_expanded = not _expanded
	var h: float = EXPANDED_H if _expanded else COLLAPSED_H
	size = Vector2(WIDTH, h)
	custom_minimum_size = Vector2(WIDTH, h)
	_toggle.text = "▲ Hide" if _expanded else "▼ History"
	call_deferred("_scroll_to_top")

func _scroll_to_top() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0

func _apply_style() -> void:
	# Matches the HUD's parchment-dark + gold-trim panels (see HUDNode._make_panel).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.10, 0.07, 0.94)
	style.set_corner_radius_all(7)
	style.set_border_width_all(2)
	style.border_color = Color(0.74, 0.57, 0.26, 0.95)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 7
	add_theme_stylebox_override("panel", style)
