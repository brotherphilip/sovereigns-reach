extends VBoxContainer
# Stacking notification feed: shows up to MAX_ITEMS timed messages at once (newest
# at the bottom), each independently auto-removed. Replaces the old single-label
# notification so rapid events no longer clobber one another. View-only: call push().

const MAX_ITEMS := 5
const FADE_IN_DUR  := 0.25
const FADE_OUT_DUR := 0.4

func push(text: String, duration: float = 3.0, color: Color = Color.YELLOW) -> void:
	while get_child_count() >= MAX_ITEMS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var row := HBoxContainer.new()
	row.modulate.a = 0.0
	add_child(row)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var dismiss_btn := Button.new()
	dismiss_btn.text = "×"
	dismiss_btn.flat = true
	dismiss_btn.add_theme_font_size_override("font_size", 12)
	dismiss_btn.custom_minimum_size = Vector2(20, 0)
	dismiss_btn.pressed.connect(func(): _fade_out(row))
	row.add_child(dismiss_btn)
	create_tween().tween_property(row, "modulate:a", 1.0, FADE_IN_DUR)
	# Expire via a Timer parented to the row, so pruning/dismissing the row frees
	# the timer too. A SceneTreeTimer would outlive a freed row and fire its lambda
	# on a freed capture ("Lambda capture was freed" spam).
	var expire := Timer.new()
	expire.one_shot = true
	expire.wait_time = max(FADE_IN_DUR, duration - FADE_OUT_DUR)
	row.add_child(expire)
	expire.timeout.connect(func() -> void: _fade_out(row))
	expire.start()

func _fade_out(node: Control) -> void:
	if not is_instance_valid(node):
		return
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 0.0, FADE_OUT_DUR)
	tw.tween_callback(node.queue_free)
