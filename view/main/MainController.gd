extends Node
# Root scene controller — manages view-mode switching and wires EventBus signals.
# MFA contract: this Node is pure VIEW glue. It reads from GameState via EventBus
# and issues Commands through CommandQueue. It never writes GameState directly.

# View mode enum
enum ViewMode { MACRO, MICRO, TECH_TREE, EDICTS }

# ── Child node paths (set in Main.tscn via @onready or assign in _ready) ───────
@export var macro_view_path: NodePath = NodePath("MacroView")
@export var micro_view_path: NodePath = NodePath("MicroView")
@export var hud_path:        NodePath = NodePath("HUD")
@export var tech_panel_path: NodePath = NodePath("HUD/TechTreePanel")
@export var edict_panel_path:NodePath = NodePath("HUD/EdictPanel")

# ── Runtime state ─────────────────────────────────────────────────────────────
var _current_mode: ViewMode = ViewMode.MICRO
var _player_id: int = 0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_bus()
	_apply_view_mode(_current_mode)

func _connect_bus() -> void:
	if not Engine.has_singleton("EventBus"):
		push_warning("MainController: EventBus not found — view updates disabled")
		return
	var bus = Engine.get_singleton("EventBus")
	if bus.has_signal("state_changed"):
		bus.state_changed.connect(_on_state_changed)
	if bus.has_signal("command_ack"):
		bus.command_ack.connect(_on_command_ack)

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_state_changed(snapshot: Dictionary) -> void:
	_refresh_all(snapshot)

func _on_command_ack(_cmd_type: int, _ok: bool, _reason: String) -> void:
	pass  # Future: show feedback popups

# ── View mode switching ───────────────────────────────────────────────────────

func switch_to_macro() -> void:
	_apply_view_mode(ViewMode.MACRO)

func switch_to_micro() -> void:
	_apply_view_mode(ViewMode.MICRO)

func toggle_tech_tree() -> void:
	if _current_mode == ViewMode.TECH_TREE:
		_apply_view_mode(ViewMode.MICRO)
	else:
		_apply_view_mode(ViewMode.TECH_TREE)

func toggle_edicts() -> void:
	if _current_mode == ViewMode.EDICTS:
		_apply_view_mode(ViewMode.MICRO)
	else:
		_apply_view_mode(ViewMode.EDICTS)

func _apply_view_mode(mode: ViewMode) -> void:
	_current_mode = mode
	_set_node_visible(macro_view_path, mode == ViewMode.MACRO)
	_set_node_visible(micro_view_path, mode == ViewMode.MICRO or mode == ViewMode.TECH_TREE or mode == ViewMode.EDICTS)
	_set_node_visible(tech_panel_path, mode == ViewMode.TECH_TREE)
	_set_node_visible(edict_panel_path, mode == ViewMode.EDICTS)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh_all(snapshot: Dictionary) -> void:
	var player: Dictionary = _get_player(snapshot)
	var weather: Dictionary = snapshot.get("weather", {})
	var tick: int = int(snapshot.get("tick", 0))
	var ai_factions: Array = snapshot.get("ai_factions", [])
	var world: Dictionary = snapshot.get("world", {})

	_refresh_hud(player, weather, tick)
	_refresh_micro(player)
	_refresh_macro(world, snapshot.get("players", []), ai_factions)
	_refresh_tech_panel(player)
	_refresh_edict_panel(player, tick)

func _refresh_hud(player: Dictionary, weather: Dictionary, tick: int) -> void:
	const HUDController = preload("res://view/hud/HUDController.gd")
	var hud_node = _get_node(hud_path)
	if hud_node == null:
		return
	var data: Dictionary = HUDController.get_hud_data(player, weather, tick)
	if hud_node.has_method("apply_hud_data"):
		hud_node.apply_hud_data(data)

func _refresh_micro(player: Dictionary) -> void:
	const MicroViewController = preload("res://view/micro/MicroViewController.gd")
	var micro_node = _get_node(micro_view_path)
	if micro_node == null:
		return
	var buildings: Array = MicroViewController.get_building_render_list(player)
	var units: Array = MicroViewController.get_unit_render_list(player)
	if micro_node.has_method("apply_render_data"):
		micro_node.apply_render_data({"buildings": buildings, "units": units})

func _refresh_macro(world: Dictionary, players: Array, ai_factions: Array) -> void:
	const MacroViewController = preload("res://view/macro/MacroViewController.gd")
	var macro_node = _get_node(macro_view_path)
	if macro_node == null:
		return
	var shires: Array    = MacroViewController.get_shire_render_list(world, players, ai_factions)
	var p_banners: Array = MacroViewController.get_player_army_banners(players)
	var ai_banners: Array = MacroViewController.get_ai_army_banners(ai_factions)
	var tents: Array     = MacroViewController.get_siege_tent_data(ai_factions)
	if macro_node.has_method("apply_render_data"):
		macro_node.apply_render_data({
			"shires": shires,
			"player_banners": p_banners,
			"ai_banners": ai_banners,
			"siege_tents": tents,
		})

func _refresh_tech_panel(player: Dictionary) -> void:
	const TechTreePanelController = preload("res://view/hud/TechTreePanelController.gd")
	var tech_node = _get_node(tech_panel_path)
	if tech_node == null:
		return
	var data: Dictionary = TechTreePanelController.get_panel_data(player)
	if tech_node.has_method("apply_panel_data"):
		tech_node.apply_panel_data(data)

func _refresh_edict_panel(player: Dictionary, tick: int) -> void:
	const EdictPanelController = preload("res://view/hud/EdictPanelController.gd")
	var edict_node = _get_node(edict_panel_path)
	if edict_node == null:
		return
	var data: Dictionary = EdictPanelController.get_panel_data(player, tick)
	if edict_node.has_method("apply_panel_data"):
		edict_node.apply_panel_data(data)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_player(snapshot: Dictionary) -> Dictionary:
	for p in snapshot.get("players", []):
		if p is Dictionary and p.get("id", -1) == _player_id:
			return p
	return {}

func _get_node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)

func _set_node_visible(path: NodePath, visible: bool) -> void:
	var n: Node = _get_node(path)
	if n != null and n.has_method("set_visible"):
		n.visible = visible
