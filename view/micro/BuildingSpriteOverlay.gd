extends RefCounted
# Painted-sprite overlay for finished buildings (added iter203, promoted iter204).
# Renders a hand-painted PNG on TOP of the existing procedural model (BuildingModels),
# scaled & anchored to the iso footprint. The procedural building still draws underneath,
# so this is purely additive: a building with no sprite (or a failed load) falls back to the
# original procedural look automatically, and the whole feature can be removed by clearing
# SPRITES below. Only finished buildings get the overlay — under-construction scaffolding and
# damage states keep their procedural rendering.
#
# To add a building: paint an iso sprite on a solid-black background, drop it at
# res://Sprites/Buildings/<Name>.png, add the keyed export at
# res://view/micro/sprites/<btype>.png (or rely on the runtime black-key fallback), then add
# SPRITES/RAW_SOURCES/PLACEMENT entries here. _SpriteTrial.tscn renders a before/after to tune
# the PLACEMENT anchor & width_k.

# btype -> keyed sprite path (preferred) ; raw fallback handled below.
const SPRITES := {
	"village_hall": "res://view/micro/sprites/village_hall.png",
	"market":       "res://view/micro/sprites/market.png",
	"keep":         "res://view/micro/sprites/keep.png",
	"church":       "res://view/micro/sprites/church.png",
}
# Raw (black background) source, used only if the keyed file is missing.
const RAW_SOURCES := {
	"village_hall": "res://Sprites/Buildings/Village_Hall.png",
}

# ── Per-sprite placement tuning ───────────────────────────────────────────────
# Each sprite was painted with its grass plot filling most of the canvas. We map the
# image's ground-diamond centre (ANCHOR_U/V, as fractions of the image) onto the tile's
# footprint centre, and scale so the painted plot spans the footprint diamond width.
#   width_k : on-screen sprite width = footprint_diamond_width * width_k
#   anchor  : Vector2(u, v) ground-centre as a fraction of the source image
const PLACEMENT := {
	"village_hall": {"width_k": 1.30, "anchor": Vector2(0.500, 0.760)},
	"market":       {"width_k": 1.28, "anchor": Vector2(0.500, 0.730)},
	"keep":         {"width_k": 1.30, "anchor": Vector2(0.500, 0.760)},
	"church":       {"width_k": 1.26, "anchor": Vector2(0.500, 0.745)},
}

# Cache: btype -> Texture2D (keyed). Null entry = tried & failed (don't retry).
static var _cache: Dictionary = {}

static func has_sprite(btype: String) -> bool:
	return SPRITES.has(btype)

# Returns the keyed texture for a btype, loading (and keying a raw source if needed) once.
static func _texture(btype: String) -> Texture2D:
	if _cache.has(btype):
		return _cache[btype]
	var tex: Texture2D = null
	var keyed_path: String = SPRITES.get(btype, "")
	if keyed_path != "" and ResourceLoader.exists(keyed_path):
		tex = load(keyed_path) as Texture2D
	# Fallback: load the raw (black-bg) art and key the black to transparent at runtime.
	if tex == null:
		tex = _load_and_key(RAW_SOURCES.get(btype, ""))
	_cache[btype] = tex
	return tex

# Loads a black-background PNG and floods near-black edge pixels to transparent.
# Connected-component flood from the image border so the building's own dark areas stay opaque.
static func _load_and_key(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var src := load(path) as Texture2D
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var thresh := 0.06   # luminance below this is "black background"
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[int] = []
	# Seed the flood from every border pixel.
	for x in range(w):
		stack.append(x); stack.append((h - 1) * w + x)
	for y in range(h):
		stack.append(y * w); stack.append(y * w + (w - 1))
	while not stack.is_empty():
		var idx: int = stack.pop_back()
		if idx < 0 or idx >= w * h or visited[idx] != 0:
			continue
		visited[idx] = 1
		var px: int = idx % w
		var py: int = idx / w
		var c := img.get_pixel(px, py)
		if maxf(maxf(c.r, c.g), c.b) > thresh:
			continue   # hit the building — stop flooding here
		img.set_pixel(px, py, Color(0, 0, 0, 0))
		if px > 0:     stack.append(idx - 1)
		if px < w - 1: stack.append(idx + 1)
		if py > 0:     stack.append(idx - w)
		if py < h - 1: stack.append(idx + w)
	return ImageTexture.create_from_image(img)

# Draws the painted sprite on top of the procedural building, scaled & anchored to the
# footprint given by its iso corners (screen space).
static func draw(ci: CanvasItem, btype: String, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	var tex := _texture(btype)
	if tex == null:
		return
	var place: Dictionary = PLACEMENT.get(btype, {"width_k": 1.0, "anchor": Vector2(0.5, 0.8)})
	var anchor: Vector2 = place.get("anchor", Vector2(0.5, 0.8))
	var width_k: float = place.get("width_k", 1.0)
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var footprint_w: float = r.x - l.x                 # iso diamond width on screen
	var sprite_w: float = footprint_w * width_k
	var s: float = sprite_w / tw
	var ground_ctr: Vector2 = (t + b) * 0.5            # footprint centre on the ground
	# Place top-left so the image's anchor point lands on the footprint centre.
	var pos := Vector2(ground_ctr.x - anchor.x * tw * s, ground_ctr.y - anchor.y * th * s)
	ci.draw_texture_rect(tex, Rect2(pos, Vector2(tw, th) * s), false)
