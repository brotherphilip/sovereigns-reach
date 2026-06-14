extends RefCounted
# GDD §1.5.4 — Save States
# Handles serialization to/from JSON files. All data must be JSON-serializable
# (the MFA constraint guarantees this for GameState).

const SAVE_VERSION: int = 2
const DEFAULT_SAVE_PATH: String = "user://sovereign_save.json"

# Writes a serialized GameState dict to a JSON file.
# Returns true on success. Pass extra_meta to include shire_count, game_day, difficulty etc.
static func save(state: Dictionary, file_path: String = DEFAULT_SAVE_PATH, extra_meta: Dictionary = {}) -> bool:
	if state.is_empty():
		return false
	var wrapped: Dictionary = {
		"save_version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"meta": extra_meta,
		"state": state,
	}
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(wrapped, "\t"))
	file.close()
	return true

# Reads and parses a save file. Returns empty dict if not found, corrupt, or version mismatch.
static func load_save(file_path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.get_data()
	if not data is Dictionary:
		return {}
	var version: int = int(data.get("save_version", 0))
	if version <= 0:
		return {}                      # missing/invalid version — unrecoverable
	var state: Dictionary = data.get("state", {})
	if version == SAVE_VERSION:
		return state
	if version > SAVE_VERSION:
		return {}                      # newer than this build can read — refuse
	# S16: older save — bring it forward through the migration chain.
	return _migrate(state, version)

# Sequentially upgrades a saved state from `from_version` to SAVE_VERSION.
# Returns {} if any step in the chain is unsupported.
static func _migrate(state: Dictionary, from_version: int) -> Dictionary:
	var migrated: Dictionary = state.duplicate(true)
	var v: int = from_version
	while v < SAVE_VERSION:
		match v:
			1: migrated = _migrate_v1_to_v2(migrated)
			_: return {}               # no migration path for this version
		v += 1
	return migrated

# v1 -> v2: Phase 6 added per-player military fields (units, armory, metrics)
# and the top-level ai_factions array. Backfill them so pre-Phase 6 saves load.
static func _migrate_v1_to_v2(state: Dictionary) -> Dictionary:
	for p in state.get("players", []):
		if not p is Dictionary:
			continue
		if not p.has("units"):
			p["units"] = []
		if not p.has("armory"):
			p["armory"] = {"bows": 0, "crossbows": 0, "pikes": 0,
				"swords": 0, "leather_armor": 0, "plate_armor": 0}
		if not p.has("total_kills"):
			p["total_kills"] = 0
		if not p.has("sieges_survived"):
			p["sieges_survived"] = 0
	if not state.has("ai_factions"):
		state["ai_factions"] = []
	return state

# Returns true if a save file exists at the given path.
static func save_exists(file_path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(file_path)

# Deletes a save file. Returns true if successful.
static func delete_save(file_path: String = DEFAULT_SAVE_PATH) -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	DirAccess.remove_absolute(file_path)
	return not FileAccess.file_exists(file_path)

# Returns the raw save metadata (version, saved_at) without loading full state.
# Returns empty dict if file unreadable or corrupt.
static func get_save_metadata(file_path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.get_data()
	if not data is Dictionary:
		return {}
	var meta: Dictionary = data.get("meta", {})
	return {
		"save_version": data.get("save_version", 0),
		"saved_at": data.get("saved_at", 0),
		# Loadable if it's the current version or an older one we can migrate.
		"valid": int(data.get("save_version", 0)) >= 1 and int(data.get("save_version", 0)) <= SAVE_VERSION,
		"game_day": meta.get("game_day", 0),
		"shire_count": meta.get("shire_count", 0),
		"difficulty": meta.get("difficulty", "Normal"),
		"playtime_days": meta.get("game_day", 0),
	}
