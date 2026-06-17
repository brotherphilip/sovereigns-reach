extends Node
# Background-music playlist. Scans audio/Music/ and plays every track on a loop, kept low
# in the mix so it underscores rather than overwhelms. Two design requirements (user, iter164):
#
#  1. AUTO-UPDATING PLAYLIST. Tracks are loaded from their raw bytes at runtime (like the
#     narration WAVs), so dropping a new song into audio/Music/ makes it play WITHOUT an
#     editor reimport. The folder is re-scanned every time the playlist wraps, so songs added
#     mid-session are picked up on the next loop.
#
#  2. "DISTANT / LOW-FIDELITY / OLD" treatment. All music routes through a dedicated "Music"
#     audio bus carrying a high-pass + low-pass (muffled, far-away, small-speaker), a subtle
#     LoFi bitcrush (aged-record character) and a light reverb (sense of space). The bus sits
#     well below the master so it never competes with SFX/narration.
#
# Pure runtime — no scene/.import dependency; safe in headless (AudioServer has a dummy driver).

const WavLoad = preload("res://simulation/audio/WavLoad.gd")

const MUSIC_DIR: String = "res://audio/Music/"
const MUSIC_BUS: String = "Music"
const MUSIC_BUS_DB: float = -13.0          # the whole music bed sits here — gentle, not overwhelming
const EXTS: PackedStringArray = [".mp3", ".ogg", ".wav"]

var _player: AudioStreamPlayer = null
var _playlist: PackedStringArray = []
var _pos: int = 0

func _ready() -> void:
	_setup_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "MusicStream"
	_player.bus = MUSIC_BUS
	_player.process_mode = Node.PROCESS_MODE_ALWAYS   # keep playing while the game is paused
	_player.finished.connect(_on_finished)
	add_child(_player)
	_rescan()
	_play_next(true)

# ── The "old / distant / low-fi" bus ────────────────────────────────────────────
func _setup_bus() -> void:
	var idx: int = AudioServer.get_bus_index(MUSIC_BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MUSIC_BUS)
		AudioServer.set_bus_send(idx, "Master")
	# Idempotent: clear any effects we may have added on a previous run.
	while AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.remove_bus_effect(idx, 0)
	AudioServer.set_bus_volume_db(idx, MUSIC_BUS_DB)

	# 1) High-pass — thin out the bass like a small, old speaker / distant source.
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 220.0
	AudioServer.add_bus_effect(idx, hp)
	# 2) Low-pass — roll off the highs so it reads muffled / far away / aged.
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3000.0
	AudioServer.add_bus_effect(idx, lp)
	# 3) LoFi bitcrush — subtle sample/bit reduction for an old-record grain.
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_LOFI
	dist.pre_gain = -2.0
	dist.drive = 0.18
	dist.post_gain = -2.0
	dist.keep_hf_hz = 2800.0
	AudioServer.add_bus_effect(idx, dist)
	# 4) Light reverb — a touch of space so the music feels set back behind the world.
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.5
	rev.damping = 0.6
	rev.wet = 0.18
	rev.dry = 0.85
	AudioServer.add_bus_effect(idx, rev)

# ── Playlist ─────────────────────────────────────────────────────────────────────
# Re-scan audio/Music/ for playable tracks (sorted, stable order).
func _rescan() -> void:
	var found: PackedStringArray = []
	var d := DirAccess.open(MUSIC_DIR)
	if d != null:
		d.list_dir_begin()
		var fn: String = d.get_next()
		while fn != "":
			if not d.current_is_dir():
				var low: String = fn.to_lower()
				for ext in EXTS:
					if low.ends_with(ext):
						found.append(MUSIC_DIR + fn)
						break
			fn = d.get_next()
		d.list_dir_end()
	found.sort()
	_playlist = found

# Advance to the next track. Re-scans the folder whenever the playlist wraps so songs added
# while the game is running get folded in on the next loop.
func _play_next(rescan_first: bool = false) -> void:
	if rescan_first:
		_rescan()
		_pos = 0
	if _playlist.is_empty():
		return
	if _pos >= _playlist.size():
		_rescan()           # wrapped — pick up any newly-added songs
		_pos = 0
		if _playlist.is_empty():
			return
	var path: String = _playlist[_pos]
	_pos += 1
	var stream: AudioStream = _load_stream(path)
	if stream != null:
		_player.stream = stream
		_player.play()
	else:
		# Skip an unreadable file rather than stalling the playlist.
		if _pos < _playlist.size():
			_play_next(false)

func _on_finished() -> void:
	_play_next(false)

# Load a track from its raw bytes — no editor import needed (newly-dropped files just work).
func _load_stream(path: String) -> AudioStream:
	var low: String = path.to_lower()
	if low.ends_with(".mp3"):
		if not FileAccess.file_exists(path):
			return null
		var s := AudioStreamMP3.new()
		s.data = FileAccess.get_file_as_bytes(path)
		return s
	elif low.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	elif low.ends_with(".wav"):
		return WavLoad.load_wav(path)
	return null

# ── Public controls (for an options menu later) ──────────────────────────────────
func set_music_volume_db(db: float) -> void:
	var idx: int = AudioServer.get_bus_index(MUSIC_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func track_count() -> int:
	return _playlist.size()
