extends RefCounted
# Load a 16-bit PCM WAV from disk into an AudioStreamWAV at runtime — no editor import
# step required (narration files are dropped in directly). Returns null on any problem.

static func load_wav(path: String) -> AudioStreamWAV:
	if not FileAccess.file_exists(path):
		return null
	var b: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var sr: int = 24000
	var channels: int = 1
	var pcm: PackedByteArray = PackedByteArray()
	var pos: int = 12   # skip RIFF(4) size(4) WAVE(4)
	while pos + 8 <= b.size():
		var cid: String = b.slice(pos, pos + 4).get_string_from_ascii()
		var csz: int = b.decode_u32(pos + 4)
		var payload: int = pos + 8
		if cid == "fmt ":
			channels = b.decode_u16(payload + 2)
			sr = b.decode_u32(payload + 4)
		elif cid == "data":
			pcm = b.slice(payload, mini(payload + csz, b.size()))
		pos = payload + csz + (csz & 1)   # chunks are word-aligned
	if pcm.is_empty():
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = channels == 2
	w.data = pcm
	return w
