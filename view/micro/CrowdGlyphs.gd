extends RefCounted
# Batched crowd renderer. Draws a large mass of small figures in a HANDFUL of draw calls
# via MultiMeshInstance2D — one MultiMesh per FIGURE MESH, with a per-instance transform and
# colour. A thousand units cost ~one draw call PER MESH, not per unit, so the layers can show
# armies of thousands once the full articulated art is dropped.
#
# Meshes carry VERTEX COLOURS (a little flat-shaded figure: skin head, cloth/steel body, a
# weapon), so each instance is a recognisable multi-colour soldier, not a flat blob. The
# per-instance colour MULTIPLIES the mesh — pass WHITE to keep the figure's own colours, or a
# tint (e.g. a team disc) to recolour a single-colour mesh. The owning layer calls
# begin() → push(key, ...) per visible figure → flush().

var _mmi: Dictionary = {}     # mesh key -> MultiMeshInstance2D
var _buf: Dictionary = {}     # mesh key -> Array of [Vector2 pos, float scale, Color col]

# meshes: { key: Mesh }. Created in dict order, so earlier keys draw UNDER later ones (use for
# a ground disc beneath the bodies). Parent must already be in the tree.
func setup(parent: Node2D, meshes: Dictionary, z_index: int = 0) -> void:
	for key in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = meshes[key]
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.z_index = z_index
		parent.add_child(mmi)
		_mmi[key] = mmi
		_buf[key] = []

func begin() -> void:
	for key in _buf:
		(_buf[key] as Array).clear()

func push(key: String, pos: Vector2, scale: float, col: Color) -> void:
	var b: Variant = _buf.get(key, null)
	if b != null:
		(b as Array).append([pos, scale, col])

func flush() -> void:
	for key in _mmi:
		var mm: MultiMesh = (_mmi[key] as MultiMeshInstance2D).multimesh
		var b: Array = _buf[key]
		mm.instance_count = b.size()
		for i in range(b.size()):
			var e: Array = b[i]
			mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(e[1], e[1]), 0.0, e[0]))
			mm.set_instance_color(i, e[2])

func clear() -> void:
	for key in _mmi:
		((_mmi[key] as MultiMeshInstance2D).multimesh as MultiMesh).instance_count = 0
	for key in _buf:
		(_buf[key] as Array).clear()

# ── Mesh builders ─────────────────────────────────────────────────────────────

# A single flat-coloured convex polygon (e.g. a ground disc to be team-tinted per instance).
static func poly_mesh(poly: PackedVector2Array, color: Color = Color.WHITE) -> ArrayMesh:
	return parts_mesh([[poly, color]])

# A figure assembled from coloured parts: parts = Array of [PackedVector2Array poly, Color].
# Each convex part is fan-triangulated; vertex colours bake the figure's look into the mesh.
static func parts_mesh(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for part in parts:
		var poly: PackedVector2Array = part[0]
		var c: Color = part[1]
		for i in range(1, poly.size() - 1):
			verts.append(Vector3(poly[0].x, poly[0].y, 0.0)); cols.append(c)
			verts.append(Vector3(poly[i].x, poly[i].y, 0.0)); cols.append(c)
			verts.append(Vector3(poly[i + 1].x, poly[i + 1].y, 0.0)); cols.append(c)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# Convenience: an axis-aligned rectangle polygon.
static func rect_poly(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

# Convenience: an n-gon (default hexagon) approximating an ellipse, centred at c.
static func ellipse_poly(rx: float, ry: float, c: Vector2 = Vector2.ZERO, n: int = 8) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return p
