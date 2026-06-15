extends Control
# A decision popup for World Events that carry choices (see WorldEventSystem).
# Mirrors DiplomacyPanel: hidden until a choice-event arrives on EventBus.world_event,
# then shows the event's title/text and a button per option. Picking one routes through
# the CommandQueue (deterministic) as RESOLVE_EVENT_CHOICE.

const CT_RESOLVE_EVENT_CHOICE := 31   # CommandQueue.CommandType.RESOLVE_EVENT_CHOICE

var _panel: Panel = null
var _title: Label = null
var _body: RichTextLabel = null
var _btn_box: VBoxContainer = null
var _current_id: String = ""
var _prev_speed: int = 1   # speed to restore after the player decides

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(360, 0)

	_panel = Panel.new()
	_panel.size = Vector2(360, 150)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.14, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.82, 0.70, 0.35)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 10)
	vb.custom_minimum_size = Vector2(336, 0)
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vb.add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(330, 40)
	_body.add_theme_color_override("default_color", Color(0.92, 0.9, 0.85))
	vb.add_child(_body)

	_btn_box = VBoxContainer.new()
	_btn_box.add_theme_constant_override("separation", 4)
	vb.add_child(_btn_box)

	EventBus.world_event.connect(_on_world_event)

func _on_world_event(ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	if not (choices is Array) or choices.is_empty():
		return   # plain events are handled by the notification feed, not this panel
	_current_id = ev.get("id", "")
	_title.text = "⚜  " + String(ev.get("title", "A Decision"))
	_body.text = "[i]%s[/i]" % String(ev.get("text", ""))

	for c in _btn_box.get_children():
		c.queue_free()
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var idx: int = i
		var btn := Button.new()
		btn.text = String(choice.get("label", "Choose"))
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _choose(idx))
		_btn_box.add_child(btn)

	# Size the panel to its content and reveal it.
	_panel.size.y = 96.0 + choices.size() * 30.0
	visible = true
	# A decree deserves the lord's full attention: hold time while you decide (and
	# restore the prior speed afterwards) so a decision is never missed at fast-forward.
	_prev_speed = SimulationClock.game_speed
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)

func _choose(index: int) -> void:
	CommandQueue.enqueue(CT_RESOLVE_EVENT_CHOICE, {
		"event_id": _current_id,
		"choice_index": index,
	}, 0)
	visible = false
	# Resume the realm at whatever speed it was running before the decree.
	SimulationClock.set_speed(_prev_speed if _prev_speed > 0 else SimulationClock.SPEED_NORMAL)
