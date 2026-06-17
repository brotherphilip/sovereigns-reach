extends SceneTree
# MusicPlayer regression (iter164). Guards the auto-playlist + "old/distant/lo-fi" bus:
#  - the Music bus exists with the 4-effect treatment (HP, LP, LoFi, reverb), below master;
#  - audio/Music/ is scanned into a non-empty playlist;
#  - tracks load from raw bytes at runtime (no editor import needed — new songs just work);
#  - the playlist wraps (rescans) rather than stalling at the end.
# Run: godot --headless --script tests/TestMusic.gd

const MusicPlayer = preload("res://simulation/audio/MusicPlayer.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var mp = root.get_node_or_null("MusicPlayer")
	if mp == null:
		print("FATAL: MusicPlayer autoload not found"); quit(1); return
	_run(mp)
	print("\n=== Music Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run(mp) -> void:
	print("\n[MusicPlayer — auto playlist + old/distant/lo-fi bus]")

	# The dedicated bus exists, sits below master, and carries the full treatment chain.
	var idx: int = AudioServer.get_bus_index(MusicPlayer.MUSIC_BUS)
	ok("Music bus created", idx >= 0)
	ok("Music bus sits below master (gentle, not overwhelming)", idx >= 0 and AudioServer.get_bus_volume_db(idx) <= -6.0)
	if idx >= 0:
		ok("bus has 4 effects (HP + LP + LoFi + reverb)", AudioServer.get_bus_effect_count(idx) == 4)
		var have := {"hp": false, "lp": false, "lofi": false, "reverb": false}
		for e in range(AudioServer.get_bus_effect_count(idx)):
			var fx = AudioServer.get_bus_effect(idx, e)
			if fx is AudioEffectHighPassFilter: have["hp"] = true
			elif fx is AudioEffectLowPassFilter: have["lp"] = true
			elif fx is AudioEffectReverb: have["reverb"] = true
			elif fx is AudioEffectDistortion and fx.mode == AudioEffectDistortion.MODE_LOFI: have["lofi"] = true
		ok("high-pass present (thins the lows — small/old speaker)", have["hp"])
		ok("low-pass present (muffled / distant / aged)", have["lp"])
		ok("LoFi bitcrush present (old-record grain)", have["lofi"])
		ok("reverb present (sense of distance)", have["reverb"])

	# The playlist scanned the real folder (two songs ship today).
	ok("playlist found tracks (>=1)", mp.track_count() >= 1)

	# Tracks load from raw bytes at runtime — no .import required for newly-dropped files.
	var dir := DirAccess.open(MusicPlayer.MUSIC_DIR)
	var first_mp3 := ""
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.to_lower().ends_with(".mp3"):
				first_mp3 = MusicPlayer.MUSIC_DIR + fn; break
			fn = dir.get_next()
		dir.list_dir_end()
	if first_mp3 != "":
		var stream = mp._load_stream(first_mp3)
		ok("runtime mp3 load yields an AudioStreamMP3 with data", stream is AudioStreamMP3 and stream.data.size() > 1000)
	else:
		ok("(no mp3 present to byte-load — skipped)", true)

	# Wrapping the playlist rescans instead of stalling: force past the end and advance.
	mp._pos = 100000
	mp._play_next(false)
	ok("playlist wraps without stalling (pos reset within range)", mp.track_count() == 0 or mp._pos <= mp.track_count())

	# Ducking: the music bed glides DOWN under narration and back UP afterwards (deterministic
	# glide, no real audio needed). Drive the helper directly with speaking on, then off.
	mp._base_db = MusicPlayer.MUSIC_BUS_DB
	mp._duck_cur = 0.0
	for _i in range(120):
		mp._tick_duck(true, 1.0 / 60.0)   # ~2s of "herald speaking"
	var ducked: float = mp._base_db + mp._duck_cur
	ok("music ducks under narration (>= ~10 dB drop)", mp._duck_cur <= MusicPlayer.DUCK_DB + 0.5)
	ok("ducked level is below the resting bed", ducked < mp._base_db - 8.0)
	for _i in range(120):
		mp._tick_duck(false, 1.0 / 60.0)  # ~2s after the herald stops
	ok("music restores to the resting bed after narration", absf(mp._duck_cur) < 0.5)

	# Volume setting persists across sessions (the pause-menu slider writes it).
	mp.set_music_volume_db(-24.0)
	ok("set_music_volume_db updates the resting level", absf(mp.get_music_volume_db() - (-24.0)) < 0.01)
	var cfg := ConfigFile.new()
	var loaded_ok: bool = cfg.load(MusicPlayer.SETTINGS_PATH) == OK
	ok("setting written to settings.cfg", loaded_ok and absf(float(cfg.get_value("audio", "music_db", 0.0)) - (-24.0)) < 0.01)
	mp._base_db = MusicPlayer.MUSIC_BUS_DB     # pretend a fresh session at default
	mp._load_settings()
	ok("setting reloads on next session", absf(mp.get_music_volume_db() - (-24.0)) < 0.01)
	mp.set_music_volume_db(MusicPlayer.MUSIC_BUS_DB)   # restore default for other runs
