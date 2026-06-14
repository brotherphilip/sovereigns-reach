extends RefCounted
# GDD §2.3.3 — Building visual state mapper (View layer, read-only from simulation).
# Pure static functions: BuildingState dict → visual data dict.
# The actual rendering (TileMap, AnimationPlayer, etc.) reads from these dicts.
# No Node inheritance; no scene tree. All methods are safe to call in headless tests.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

# Returns a visual-state dict for one building:
#   state       : String  — "empty" | "working" | "fire" | "damaged" | "under_construction"
#   animation   : String  — animation key for the building's animated sprite
#   color_tint  : String  — CSS-style hint for the renderer ("normal", "dark", "fire_orange", "damaged_gray")
#   show_fire   : bool    — whether to overlay a fire particle effect
#   hp_bar      : float   — 0.0–1.0; hidden when 1.0
#   label       : String  — display name from BuildingRegistry
#   workers     : int     — current worker count (for capacity display)
#   max_workers : int
static func get_visual_state(building: Dictionary) -> Dictionary:
	var btype: String         = building.get("type", "")
	var defn: Dictionary      = BuildingRegistry.lookup(btype)
	var is_op: bool           = building.get("is_active", true)
	var workers: int          = building.get("workers", 0)
	var on_fire: bool         = building.get("is_on_fire", false)
	var hp: int               = building.get("hp", 1)
	var max_hp: int           = defn.get("hp", 100) if not building.has("max_hp") else building.get("max_hp", 1)
	if max_hp <= 0:
		max_hp = 1
	var hp_ratio: float       = float(hp) / float(max_hp)
	var name_str: String      = defn.get("name", btype)

	if on_fire:
		return {
			"state": "fire", "animation": "fire", "color_tint": "fire_orange",
			"show_fire": true, "hp_bar": hp_ratio, "label": name_str,
			"workers": workers, "max_workers": defn.get("max_workers", 0),
		}
	if hp_ratio < 0.3:
		return {
			"state": "damaged", "animation": "idle", "color_tint": "damaged_gray",
			"show_fire": false, "hp_bar": hp_ratio, "label": name_str,
			"workers": workers, "max_workers": defn.get("max_workers", 0),
		}
	if not is_op or workers == 0:
		return {
			"state": "empty", "animation": "idle", "color_tint": "dark",
			"show_fire": false, "hp_bar": hp_ratio, "label": name_str,
			"workers": workers, "max_workers": defn.get("max_workers", 0),
		}
	return {
		"state": "working", "animation": "work", "color_tint": "normal",
		"show_fire": false, "hp_bar": hp_ratio, "label": name_str,
		"workers": workers, "max_workers": defn.get("max_workers", 0),
	}

# Returns 0.0–1.0 HP bar ratio for a building dict.
static func get_hp_bar(building: Dictionary) -> float:
	var hp: int    = building.get("hp", 1)
	var defn: Dictionary = BuildingRegistry.lookup(building.get("type", ""))
	var max_hp: int = building.get("max_hp", defn.get("hp", 100))
	if max_hp <= 0:
		return 1.0
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)

# Returns true if this building type should show a production-progress indicator.
# Any building that has a produces dict (non-empty) gets a progress bar.
static func has_progress_bar(building_type: String) -> bool:
	var defn: Dictionary = BuildingRegistry.lookup(building_type)
	return not (defn.get("produces", {}) as Dictionary).is_empty()

# Maps building category to a tilemap layer index for the isometric renderer.
static func get_tile_layer(building_type: String) -> int:
	var defn: Dictionary = BuildingRegistry.lookup(building_type)
	var cat = defn.get("category", -1)
	match cat:
		BuildingRegistry.Category.FOOD:      return 0
		BuildingRegistry.Category.HARVESTING: return 1
		BuildingRegistry.Category.MILITARY:  return 2
		BuildingRegistry.Category.CIVIC:     return 3
		BuildingRegistry.Category.DEFENSE:   return 4
	return 0
