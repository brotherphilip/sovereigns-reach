extends PanelContainer
# Player-facing diplomacy: when an AI faction demands tribute (EventBus.ai_envoy_sent),
# show the demand with Accept / Refuse choices. The outcome is applied through the
# deterministic command pipeline (CommandQueue → GameState._cmd_diplomacy_response).

const CT_DIPLOMACY_RESPONSE = 26  # CommandQueue.CommandType.DIPLOMACY_RESPONSE
const ModalGate = preload("res://view/hud/ModalGate.gd")
const AIFaction = preload("res://simulation/ai/AIFaction.gd")
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
var _accept_btn:    Button
var _threat_bar:    ProgressBar
var _threat_label:  Label
var _history_label: RichTextLabel
var _current:       Dictionary = {}
var _history:       Array      = []  # last 3 interactions for display
var _pending:       Array      = []  # demands queued behind another open modal

func _ready() -> void:
	visible = false
	add_to_group(ModalGate.GROUP)
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
	_accept_btn = accept_btn
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

func _on_envoy(faction_id: int, demand: Dictionary) -> void:
	if demand.get("player_id", -1) != 0:
		return
	# Only one blocking modal at a time — queue behind any open popup.
	if visible or ModalGate.other_visible(self):
		demand["__fid"] = faction_id
		_pending.append(demand)
		return
	_present(faction_id, demand)

func _present(faction_id: int, demand: Dictionary) -> void:
	_current = demand
	var _fid: int = int(demand.get("faction_id", faction_id))

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
	# Standing readout: the faction's current grievance, so the choice's stakes are clear.
	var fac = _live_faction(_fid)
	var grievance: float = float(fac.get("grievance", 0.0)) if fac != null else 0.0
	var standing: String = "wary"
	if grievance >= 30.0:
		standing = "[color=#ff6644]seething[/color]"
	elif grievance >= 12.0:
		standing = "[color=#ffaa44]aggrieved[/color]"
	else:
		standing = "[color=#cfc488]wary[/color]"
	# Refuse consequence is grace-aware: while the King's Peace holds (the rival's
	# establishment window), refusing deepens the grievance but they CANNOT march yet —
	# so don't threaten a siege the rules won't allow. Once grace lapses, they can march.
	var days_alive: int = int(fac.get("days_alive", 9999)) if fac != null else 9999
	var grace_left: int = AIFaction.PLAYER_GRACE_DAYS - days_alive
	var refuse_tail: String
	if grace_left > 0:
		refuse_tail = "grievance deepens (now %s); the King's Peace stays their hand ~%d days more." % [standing, grace_left]
	else:
		refuse_tail = "grievance deepens (now %s) & they may march." % standing
	# Affordability gate: you can only Accept a tribute you can pay IN FULL. Paying part
	# (or nothing) yet still buying peace was an exploit, so when the coffers fall short
	# the Accept option is disabled and the player must Refuse (or gather goods & wait).
	var can_pay: bool = false
	if GameState.players.size() > 0:
		can_pay = DiplomacySystem.can_afford(GameState.players[0], demand.get("demands", {}))
	_accept_btn.disabled = not can_pay
	_accept_btn.text = "Accept (pay)" if can_pay else "Accept — can't afford"
	_accept_btn.tooltip_text = "" if can_pay else \
		"You lack the goods to pay this tribute in full. Refuse, or gather the resources before the next envoy."
	var afford_tail: String = "" if can_pay else \
		"\n\n[color=#ff8866]Your coffers cannot meet this demand in full — you must Refuse, or pay once you can.[/color]"

	_label.text = ("[i]%s[/i]\n\n[b]%s[/b] demands tribute: %s.\n\n" +
		"[color=#9fe08a]Pay[/color] → they hold the peace ~14 days.    " +
		"[color=#ffaa66]Refuse[/color] → %s%s") % [
		flavor, faction_name, ", ".join(parts), refuse_tail, afford_tail]

	# History + active agreements
	_refresh_history()
	visible = true

# The live faction dict (for grievance/peace standing) by id, or null.
func _live_faction(fid: int):
	for f in GameState.ai_factions:
		if f is Dictionary and int(f.get("id", -1)) == fid:
			return f
	return null

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
		# Re-check affordability at click time (the button is disabled when short, but
		# stocks can drift between presenting and clicking). If we can't pay in full,
		# don't claim tribute was paid — the command would no-op authoritatively anyway.
		if not DiplomacySystem.can_afford(GameState.players[0], _current.get("demands", {})):
			var hud0 = get_parent()
			if hud0 and hud0.has_method("show_notification"):
				hud0.show_notification(
					"Your coffers cannot meet that tribute — the demand still stands.",
					5.0, Color(1.0, 0.55, 0.1))
			return
		CommandQueue.enqueue(CT_DIPLOMACY_RESPONSE, {
			"faction_id": _current.get("faction_id", -1),
			"accept": true,
			"demands": _current.get("demands", {}),
		}, 0)
		_record_history("accept", _current)
		var aname: String = _current.get("faction_name", "The faction")
		var hud = get_parent()
		if hud and hud.has_method("show_notification"):
			hud.show_notification(
				"Tribute paid to %s — appeased, they hold the peace for ~14 days." % aname,
				5.0, Color(0.6, 0.9, 0.5))
	visible = false
	_after_close()

func _on_refuse() -> void:
	if GameState.players.size() > 0:
		CommandQueue.enqueue(CT_DIPLOMACY_RESPONSE, {
			"faction_id": _current.get("faction_id", -1),
			"accept": false,
		}, 0)
		_record_history("refuse", _current)
		var fname: String = _current.get("faction_name", "The faction")
		var hud = get_parent()
		if hud and hud.has_method("show_notification"):
			hud.show_notification(
				"%s refused — trade embargo imposed. Market prices rise. Expect retaliation." % fname,
				5.0, Color(1.0, 0.55, 0.1))
	visible = false
	_after_close()

# On close, present our own next queued demand, else hand off to another modal type.
func _after_close() -> void:
	if not _pending.is_empty():
		var d: Dictionary = _pending.pop_front()
		_present(int(d.get("__fid", d.get("faction_id", -1))), d)
	else:
		ModalGate.advance(self)

# Called by ModalGate when a different modal closes and we have something waiting.
func show_if_queued() -> bool:
	if _pending.is_empty():
		return false
	var d: Dictionary = _pending.pop_front()
	_present(int(d.get("__fid", d.get("faction_id", -1))), d)
	return true

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
