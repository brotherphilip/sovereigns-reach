extends RefCounted
# Shared celebratory overlay for a FEUDAL PROMOTION (Reeve → … → Duke) — the core long-term reward
# of the campaign. Built the same way from both the city view and the world map (like GameOverOverlay),
# so ranking up feels momentous wherever the player is when it happens. King is NOT handled here — that
# is the victory screen. Held, animated, auto-dismissing (and click-to-skip, since promotions recur).
#
#   PromotionOverlay.build(host, title_index, title_name)
#
# `host` is the scene that owns the overlay (it gets the CanvasLayer as a child and drives the tweens).

const FeudalRank = preload("res://simulation/strategic/FeudalRank.gd")

static func _article(title_name: String) -> String:
	return ("an " if title_name.substr(0, 1) in "AEIOU" else "a ") + title_name

static func build(host: Node, title_index: int, title_name: String) -> void:
	var prev_speed: int = SimulationClock.game_speed
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)
	NarrationPlayer.say("title_promoted")   # grim-herald VO (audio/narration/title_promoted.wav — TODO)

	var overlay := CanvasLayer.new()
	overlay.name = "PromotionCelebration"
	overlay.layer = 22
	host.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.0
	overlay.add_child(dim)

	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.86, 0.44, 0.42)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(flash)

	var bw: float = 660.0
	var bh: float = 232.0
	var banner := Panel.new()
	banner.size = Vector2(bw, bh)
	banner.position = Vector2((1280.0 - bw) * 0.5, (720.0 - bh) * 0.5)
	banner.pivot_offset = Vector2(bw * 0.5, bh * 0.5)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.09, 0.05, 0.97)
	st.set_border_width_all(3)
	st.border_color = Color(0.95, 0.80, 0.32)
	st.set_corner_radius_all(12)
	st.shadow_color = Color(0, 0, 0, 0.6); st.shadow_size = 18
	banner.add_theme_stylebox_override("panel", st)
	overlay.add_child(banner)

	var header := Label.new()
	header.text = "⚜   E N N O B L E D   ⚜"
	header.position = Vector2(0, 24); header.size = Vector2(bw, 26)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 17)
	header.add_theme_color_override("font_color", Color(0.92, 0.78, 0.42))
	banner.add_child(header)

	var titlelbl := Label.new()
	titlelbl.text = title_name
	titlelbl.position = Vector2(0, 58); titlelbl.size = Vector2(bw, 72)
	titlelbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titlelbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titlelbl.add_theme_font_size_override("font_size", 54)
	titlelbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40))
	titlelbl.pivot_offset = Vector2(bw * 0.5, 36.0)
	banner.add_child(titlelbl)

	var steps_left: int = FeudalRank.king_index() - title_index
	var hint: String = "The crown is within your grasp." if steps_left <= 1 else ("%d steps from the crown." % steps_left)
	var sub := Label.new()
	sub.text = "The realm bends knee — you are now %s.\n%s" % [_article(title_name), hint]
	sub.position = Vector2(20, 150); sub.size = Vector2(bw - 40, 60)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.90, 0.88, 0.80))
	banner.add_child(sub)

	# Click anywhere to dismiss early (promotions recur, so never force the player to wait it out).
	var skip := Button.new()
	skip.flat = true
	skip.focus_mode = Control.FOCUS_NONE
	skip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(skip)

	var state := {"closing": false}
	var close := func() -> void:
		if state["closing"]:
			return
		state["closing"] = true
		var to := host.create_tween()
		to.tween_property(dim, "modulate:a", 0.0, 0.4)
		to.parallel().tween_property(banner, "modulate:a", 0.0, 0.4)
		to.tween_callback(func() -> void:
			if is_instance_valid(overlay):
				overlay.queue_free()
			SimulationClock.set_speed(prev_speed if prev_speed > 0 else SimulationClock.SPEED_NORMAL))
	skip.pressed.connect(close)

	# Flare in: dim + banner fade up, gold flash decays, banner and title scale in with a flourish.
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.86, 0.86)
	titlelbl.scale = Vector2(0.4, 0.4)
	var tin := host.create_tween()
	tin.set_parallel(true)
	tin.tween_property(dim, "modulate:a", 1.0, 0.35)
	tin.tween_property(flash, "modulate:a", 0.0, 0.6)
	tin.tween_property(banner, "modulate:a", 1.0, 0.35)
	tin.tween_property(banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tin.tween_property(titlelbl, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	# Hold, then auto-dismiss (real-time tween, so the sim pause doesn't stall it).
	var hold := host.create_tween()
	hold.tween_interval(3.4)
	hold.tween_callback(close)
