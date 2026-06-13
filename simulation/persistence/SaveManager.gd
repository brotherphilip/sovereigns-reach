extends RefCounted
# GDD §1.5.4 — Save States
# Handles serialization to/from JSON files. All data must be JSON-serializable
# (the MFA constraint guarantees this for GameState).

const SAVE_VERSION: int = 1
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
	if data.get("save_version", 0) != SAVE_VERSION:
		return {}
	return data.get("state", {})

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
		"valid": data.get("save_version", 0) == SAVE_VERSION,
		"game_day": meta.get("game_day", 0),
		"shire_count": meta.get("shire_count", 0),
		"difficulty": meta.get("difficulty", "Normal"),
		"playtime_days": meta.get("game_day", 0),
	}
