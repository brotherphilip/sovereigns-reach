extends PanelContainer
# Player-facing diplomacy: when an AI faction demands tribute (EventBus.ai_envoy_sent),
# show the demand with Accept / Refuse choices and apply the outcome via DiplomacySystem.

const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")

var _label: RichTextLabel
var _current: Dictionary = {}

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(320, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(300, 60)
	vb.add_child(_label)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var accept_btn := Button.new()
	accept_btn.text = "Accept (pay)"
	accept_btn.pressed.connect(_on_accept)
	hb.add_child(accept_btn)
	var refuse_btn := Button.new()
	refuse_btn.text = "Refuse"
	refuse_btn.pressed.connect(_on_refuse)
	hb.add_child(refuse_btn)
	EventBus.ai_envoy_sent.connect(_on_envoy)

func _on_envoy(_faction_id: int, demand: Dictionary) -> void:
	if demand.get("player_id", -1) != 0:
		return
	_current = demand
	var parts: Array = []
	for res in demand.get("demands", {}):
		parts.append("%d %s" % [demand["demands"][res], res])
	_label.text = "[b]%s[/b] demands tribute: %s. Refuse and risk their wrath." % [demand.get("faction_name", "A rival lord"), ", ".join(parts)]
	visible = true

func _on_accept() -> void:
	if GameState.players.size() > 0:
		DiplomacySystem.accept(GameState.players[0], _current.get("demands", {}))
	visible = false

func _on_refuse() -> void:
	if GameState.players.size() > 0:
		var faction = null
		for f in GameState.ai_factions:
			if f is Dictionary and f.get("id", -1) == _current.get("faction_id", -1):
				faction = f
		DiplomacySystem.refuse(GameState.players[0], faction)
	visible = false
