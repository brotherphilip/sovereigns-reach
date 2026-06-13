extends VBoxContainer
# Stacking notification feed: shows up to MAX_ITEMS timed messages at once (newest
# at the bottom), each independently auto-removed. Replaces the old single-label
# notification so rapid events no longer clobber one another. View-only: call push().

const MAX_ITEMS := 5

func push(text: String, duration: float = 3.0, color: Color = Color.YELLOW) -> void:
	while get_child_count() >= MAX_ITEMS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 15)
	add_child(lbl)
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free()
	)
