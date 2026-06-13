extends PanelContainer
# Player-facing diplomacy: when an AI faction demands tribute (EventBus.ai_envoy_sent),
# show the demand with Accept / Refuse choices and apply the outcome via DiplomacySystem.

const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")

# Archetype-specific opening lines for tribute demands
const ARCH_FLAVOR: Dictionary = {
	"bandit_king":    [
		"You will pay — or burn.",
		"Taxes are just the cost of not dying.",
		"Hand it over. I've got men to feed and patience is not among the menu.",
	],
	"merchant_prince": [
		"Consider this an investment in continued peace.",
		"A trifling sum — surely you can afford goodwill?",
		"Business demands balance. This is your invoice.",
	],
	"ironhand":       [
		"The Iron Hand does not ask twice.",
		"Resistance is an expense your walls cannot afford.",
		"Tribute is owed. Settle the debt.",
	],
	"ashen_barony":   [
		"Lord Malakor's patience wears thin. Pay, or face Highwatch's wrath.",
		"The Barony's coffers are hungry. Feed them, or feed our siege engines.",
		"Our envoy carries a demand, not a request. Choose carefully.",
	],
}

var _label:         RichTextLabel
var _threat_bar:    ProgressBar
var _threat_label:  Label
var _history_label: RichTextLabel
var _current:       Dictionary = {}
var _history:       Array      = []  # last 3 interactions for display

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(340, 0)
	var vb := VBoxContainer.new()
	add_child(vb)

	# Threat level display
	var threat_hb := HBoxContainer.new()
	vb.add_child(threat_hb)
	_threat_label = Label.new()
	_threat_label.text = "Threat:"
	_threat_label.add_theme_font_size_override("font_size", 10)
	threat_hb.add_child(_threat_label)
	_threat_bar = ProgressBar.new()
	_threat_bar.min_value = 0.0
	_threat_bar.max_value = 100.0
	_threat_bar.value = 0.0
	_threat_bar.custom_minimum_size = Vector2(160, 12)
	_threat_bar.show_percentage = false
	threat_hb.add_child(_threat_bar)

	# Main demand text
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(300, 60)
	vb.add_child(_label)

	# Accept / Refuse buttons
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

	# Interaction history
	_history_label = RichTextLabel.new()
	_history_label.bbcode_enabled = true
	_history_label.fit_content = true
	_history_label.custom_minimum_size = Vector2(300, 0)
	vb.add_child(_history_label)

	EventBus.ai_envoy_sent.connect(_on_envoy)

func _on_envoy(_faction_id: int, demand: Dictionary) -> void:
	if demand.get("player_id", -1) != 0:
		return
	_current = demand

	# Threat bar
	var threat: float = demand.get("threat_level", 0.0)
	_threat_bar.value = threat
	var threat_col: Color = Color.GREEN.lerp(Color.RED, threat / 100.0)
	_threat_bar.modulate = threat_col
	_threat_label.text = "Threat: %.0f/100" % threat

	# Flavor text by archetype
	var arch: String = demand.get("archetype", "")
	var flavors: Array = ARCH_FLAVOR.get(arch, ["Pay or face consequences."])
	var flavor: String = flavors[randi() % flavors.size()]

	# Demand list
	var parts: Array = []
	for res in demand.get("demands", {}):
		parts.append("%d %s" % [demand["demands"][res], res])
	var faction_name: String = demand.get("faction_name", "A rival lord")
	_label.text = "[i]%s[/i]\n\n[b]%s[/b] demands tribute: %s." % [flavor, faction_name, ", ".join(parts)]

	# History + active agreements
	_refresh_history()
	visible = true

func _get_active_agreement_lines() -> Array:
	var lines: Array = []
	for f in GameState.ai_factions:
		if not (f is Dictionary and f.get("is_alive", false)):
			continue
		for d in f.get("tribute_demands", []):
			if d.get("player_id", -1) == 0 and not d.get("fulfilled", false):
				lines.append("[color=#ffaa44]Active demand from %s: %d %s[/color]" % [
					f.get("name", "?"), d.get("amount", 0), d.get("resource", "?")])
	return lines

func _on_accept() -> void:
	if GameState.players.size() > 0:
		DiplomacySystem.accept(GameState.players[0], _current.get("demands", {}))
		_record_history("accept", _current)
	visible = false

func _on_refuse() -> void:
	if GameState.players.size() > 0:
		var faction = null
		for f in GameState.ai_factions:
			if f is Dictionary and f.get("id", -1) == _current.get("faction_id", -1):
				faction = f
		DiplomacySystem.refuse(GameState.players[0], faction)
		_record_history("refuse", _current)
		var fname: String = _current.get("faction_name", "The faction")
		var hud = get_parent()
		if hud and hud.has_method("show_notification"):
			hud.show_notification(
				"%s refused — trade embargo imposed. Market prices rise. Expect retaliation." % fname,
				5.0, Color(1.0, 0.55, 0.1))
	visible = false

func _record_history(outcome: String, demand: Dictionary) -> void:
	var parts: Array = []
	for res in demand.get("demands", {}):
		parts.append("%d %s" % [demand["demands"][res], res])
	_history.append({
		"faction": demand.get("faction_name", "?"),
		"demands": ", ".join(parts),
		"outcome": outcome,
	})
	if _history.size() > 3:
		_history = _history.slice(_history.size() - 3)

func _refresh_history() -> void:
	var lines: Array = []
	var active: Array = _get_active_agreement_lines()
	if not active.is_empty():
		lines.append("[color=#aaaaaa][i]Active tribute demands:[/i][/color]")
		lines.append_array(active)
	if not _history.is_empty():
		lines.append("[color=#aaaaaa][i]Recent interactions:[/i][/color]")
		for entry in _history:
			var col: String = "#66ff88" if entry["outcome"] == "accept" else "#ff6666"
			lines.append("[color=%s]%s: %s (%s)[/color]" % [col, entry["faction"], entry["demands"], entry["outcome"]])
	_history_label.text = "\n".join(lines)
