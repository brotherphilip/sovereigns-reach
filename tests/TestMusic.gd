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
