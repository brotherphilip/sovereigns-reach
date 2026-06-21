extends RefCounted
# Shared win/loss end-game overlay — gold "👑 VICTORY!" or dark-red "DEFEAT", a message, the day
# reached, and a centered row of buttons. Used by BOTH the city view (_show_game_over) and the world
# map (_show_endgame), which presented near-identical hand-built copies (iter270-273 added world-map
# parity, leaving the duplication as flagged tech-debt). This is the single source of truth; the
# caller still owns the re-entry guard + pausing the sim. (iter284)
#
# build(host, victory, message, buttons, layer):
#   host    – the scene node the overlay CanvasLayer is added to
#   buttons – Array of {text: String, action: Callable}; laid out centered, one row
#   layer   – CanvasLayer.layer (city view sits at 20, world map at 60 over its own chrome)

static func build(host: Node, victory: bool, message: String, buttons: Array, layer: int = 30) -> CanvasLayer:
	var overlay := CanvasLayer.new()
	overlay.name  = "GameOverOverlay"
	overlay.layer = layer
	host.add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(340, 215)
	panel.size     = Vector2(600, 270)
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.10, 0.12, 0.16, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color.GOLD if victory else Color.DARK_RED
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.5); style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "👑  VICTORY!" if victory else "DEFEAT"
	title.position = Vector2(20, 24); title.size = Vector2(560, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.GOLD if victory else Color.ORANGE_RED)
	panel.add_child(title)

	var msg := Label.new()
	msg.text = message; msg.position = Vector2(20, 90); msg.size = Vector2(560, 76)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_color_override("font_color", Color.WHITE_SMOKE)
	panel.add_child(msg)

	var day_lbl := Label.new()
	day_lbl.text = "Day %d reached." % SimulationClock.game_day()
	day_lbl.position = Vector2(20, 168); day_lbl.size = Vector2(560, 24)
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_lbl.add_theme_font_size_override("font_size", 13)
	day_lbl.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	panel.add_child(day_lbl)

	# Centered row of buttons (1..3): compute the start so the whole row is centred in the panel.
	var bw: float = 140.0
	var gap: float = 16.0
	var n: int = buttons.size()
	var total: float = n * bw + maxf(0.0, float(n - 1)) * gap
	var start_x: float = (panel.size.x - total) * 0.5
	for i in range(n):
		var spec: Dictionary = buttons[i]
		var btn := Button.new()
		btn.text = String(spec.get("text", "OK"))
		btn.position = Vector2(start_x + i * (bw + gap), 212)
		btn.size = Vector2(bw, 40)
		btn.add_theme_font_size_override("font_size", 14)
		var action = spec.get("action")
		if action is Callable:
			btn.pressed.connect(action)
		panel.add_child(btn)

	return overlay
