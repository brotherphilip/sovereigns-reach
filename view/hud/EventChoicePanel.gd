extends Control
# A decision popup for World Events that carry choices (see WorldEventSystem).
# Mirrors DiplomacyPanel: hidden until a choice-event arrives on EventBus.world_event,
# then shows the event's title/text and a button per option. Picking one routes through
# the CommandQueue (deterministic) as RESOLVE_EVENT_CHOICE.

const CT_RESOLVE_EVENT_CHOICE := 31   # CommandQueue.CommandType.RESOLVE_EVENT_CHOICE
const ModalGate = preload("res://view/hud/ModalGate.gd")

var _dim: ColorRect = null
var _panel: Panel = null
var _panel_style: StyleBoxFlat = null
var _title: Label = null
var _body: RichTextLabel = null
var _btn_box: VBoxContainer = null
var _current_id: String = ""
var _prev_speed: int = 1   # speed to restore after the player decides
var _pending: Array = []   # choice-events queued behind another open modal

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(360, 0)

	# Full-screen dim behind the panel so a decree reads as a STOP-AND-DECIDE moment, not a floating
	# note over a still-busy scene. Sized/placed in _present (it must cover the screen from this
	# Control's offset position). Added first → drawn behind the panel.
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.02, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks on the world behind the decree
	add_child(_dim)

	_panel = Panel.new()
	_panel.size = Vector2(360, 150)
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.12, 0.10, 0.14, 0.97)
	_panel_style.set_border_width_all(2)
	_panel_style.border_color = Color(0.82, 0.70, 0.35)
	_panel_style.set_corner_radius_all(8)
	_panel_style.shadow_color = Color(0, 0, 0, 0.6)
	_panel_style.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", _panel_style)
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

	add_to_group(ModalGate.GROUP)
	EventBus.world_event.connect(_on_world_event)

func _on_world_event(ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	if not (choices is Array) or choices.is_empty():
		return   # plain events are handled by the notification feed, not this panel
	# Autoplay/headless survival harness: there is no player to decide, so presenting the
	# modal would PAUSE the sim forever (the run freezes at the event's day). Auto-resolve
	# with the conservative LAST option (usually decline/pass — no resource drain) and keep
	# running, so unattended FLOOR runs survive a choice event instead of stalling.
	if OS.get_environment("SR_AUTOPLAY") != "" and OS.get_environment("SR_EVENTDEMO") == "":
		CommandQueue.enqueue(CT_RESOLVE_EVENT_CHOICE, {
			"event_id": ev.get("id", ""),
			"choice_index": maxi(0, choices.size() - 1),
		}, 0)
		return
	# Only one blocking modal at a time — queue behind any open popup.
	if visible or ModalGate.other_visible(self):
		_pending.append(ev)
		return
	_present(ev)

func _present(ev: Dictionary) -> void:
	var choices: Array = ev.get("choices", [])
	_current_id = ev.get("id", "")
	_title.text = "⚜  " + String(ev.get("title", "A Decision"))
	_body.text = "[i]%s[/i]" % String(ev.get("text", ""))
	# Dim the whole screen behind the modal (offset back to the screen origin from our position).
	_dim.position = -position
	_dim.size = get_viewport_rect().size
	# Tone-accent the frame: a hostile/bad decree is framed in danger-red, a boon in green, else gold.
	var tone: String = String(ev.get("tone", "neutral"))
	if ev.get("hostile", false) or tone == "bad":
		_panel_style.border_color = Color(0.88, 0.36, 0.30)
		_title.add_theme_color_override("font_color", Color(1.0, 0.66, 0.55))
	elif tone == "good":
		_panel_style.border_color = Color(0.58, 0.82, 0.42)
		_title.add_theme_color_override("font_color", Color(0.84, 1.0, 0.70))
	else:
		_panel_style.border_color = Color(0.82, 0.70, 0.35)
		_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))

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

	# Size the panel to its content and reveal it with a soft fade so the decree settles in.
	_panel.size.y = 96.0 + choices.size() * 30.0
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)
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
	_after_close()

# On close, present our own next queued event, else hand off to another modal type.
func _after_close() -> void:
	if not _pending.is_empty():
		_present(_pending.pop_front())
	else:
		ModalGate.advance(self)

# Called by ModalGate when a different modal closes and we have something waiting.
func show_if_queued() -> bool:
	if _pending.is_empty():
		return false
	_present(_pending.pop_front())
	return true
