extends RefCounted
# Builds a small, vertex-coloured figure mesh per unit type for the batched crowd renderer
# (CrowdGlyphs). It's a simplified, static cousin of UnitArt: a flat-shaded little soldier —
# skin head, cloth/plate body, a type-specific weapon and shield — recognisable by silhouette
# and palette at crowd scale, but renderable in ONE draw call for thousands via MultiMesh.
# Feet sit at the local origin (0,0); the body extends UP into negative Y.

const UnitArt = preload("res://view/micro/UnitArt.gd")
const CG = preload("res://view/micro/CrowdGlyphs.gd")

const SKIN     := Color(0.86, 0.70, 0.55)
const STEEL    := Color(0.74, 0.77, 0.82)
const STEEL_DK := Color(0.45, 0.47, 0.52)
const WOOD     := Color(0.47, 0.32, 0.17)
const WOOD_DK  := Color(0.33, 0.22, 0.12)

const SIEGE := ["battering_ram", "catapult", "trebuchet", "siege_tower", "mantlet"]

static func build(utype: String) -> ArrayMesh:
	if utype in SIEGE:
		return CG.parts_mesh(_siege_parts(utype))
	return CG.parts_mesh(_person_parts(utype))

static func _person_parts(utype: String) -> Array:
	var s: Dictionary = UnitArt._style(utype)
	var cloth: Color = s.get("cloth", Color(0.5, 0.4, 0.3))
	var plate: bool = s.get("plate", false)
	var torso: Color = STEEL if plate else cloth
	var legs: Color = STEEL_DK if plate else cloth.darkened(0.4)
	var parts: Array = []
	# Shield behind the body (drawn first) on the lead side.
	match String(s.get("shield", "none")):
		"kite":
			parts.append([PackedVector2Array([Vector2(-4.6,-11), Vector2(-2.2,-11.6),
				Vector2(-2.0,-5), Vector2(-3.4,-2.5), Vector2(-4.8,-5)]), cloth.darkened(0.18)])
		"round":
			parts.append([CG.ellipse_poly(2.2, 2.3, Vector2(-3.6,-7.5)), cloth.darkened(0.18)])
	# Legs.
	parts.append([CG.rect_poly(-2.1, -6.0, -0.3, 0.0), legs])
	parts.append([CG.rect_poly(0.3, -6.0, 2.1, 0.0), legs])
	# Torso (trapezoid: wider at the shoulders).
	parts.append([PackedVector2Array([Vector2(-2.4,-5.5), Vector2(2.4,-5.5),
		Vector2(2.9,-13.0), Vector2(-2.9,-13.0)]), torso])
	if String(s.get("shield", "none")) == "none" and not plate and s.get("robe", false):
		parts.append([PackedVector2Array([Vector2(-2.6,-5.5), Vector2(2.6,-5.5),
			Vector2(1.8,0.0), Vector2(-1.8,0.0)]), cloth.darkened(0.08)])   # cassock hem
	# Head + helmet/hat.
	parts.append([CG.ellipse_poly(2.2, 2.4, Vector2(0,-15.3), 7), SKIN])
	match String(s.get("helm", "none")):
		"iron", "plume":
			parts.append([PackedVector2Array([Vector2(-2.5,-15.6), Vector2(2.5,-15.6),
				Vector2(1.6,-18.4), Vector2(-1.6,-18.4)]), STEEL])
			if s.get("helm") == "plume":
				parts.append([CG.rect_poly(-0.6,-21.5,0.6,-18.0), Color(0.80,0.20,0.18)])  # crest
		"cap":
			parts.append([PackedVector2Array([Vector2(-2.4,-15.8), Vector2(2.4,-15.8),
				Vector2(0,-18.2)]), cloth.darkened(0.2)])
		"hood", "coif":
			parts.append([CG.ellipse_poly(2.7, 2.9, Vector2(0,-15.2), 7), cloth.darkened(0.14)])
	# Weapon on the lead (right) side.
	for p in _weapon_parts(String(s.get("weapon", "none"))):
		parts.append(p)
	return parts

static func _weapon_parts(weapon: String) -> Array:
	match weapon:
		"bow":
			return [[PackedVector2Array([Vector2(3.2,-17), Vector2(4.4,-12), Vector2(4.4,-6),
				Vector2(3.2,-1), Vector2(3.9,-1), Vector2(5.1,-6), Vector2(5.1,-12), Vector2(3.9,-17)]), WOOD]]
		"crossbow":
			return [[CG.rect_poly(2.6,-10.2,3.6,-2.5), WOOD], [CG.rect_poly(1.4,-9.6,5.0,-8.3), WOOD_DK]]
		"sword":
			return [[CG.rect_poly(3.0,-16.5,3.9,-6.5), STEEL], [CG.rect_poly(2.3,-7.4,4.6,-6.3), WOOD]]
		"pike", "halberd", "spear":
			var parts := [[CG.rect_poly(3.0,-22.0,3.7,-1.0), WOOD]]
			parts.append([PackedVector2Array([Vector2(2.5,-22.0), Vector2(4.2,-22.0), Vector2(3.35,-25.0)]), STEEL])
			if weapon == "halberd":
				parts.append([PackedVector2Array([Vector2(3.7,-20.5), Vector2(7.0,-19.0), Vector2(3.7,-17.0)]), STEEL])
			return parts
		"club", "hoe", "staff", "pitchfork", "ladder", "pick":
			return [[CG.rect_poly(3.0,-14.0,3.7,-2.0), WOOD]]
	return []

# A simple wheeled wooden war-machine silhouette shared by the siege types (distinct, big).
static func _siege_parts(utype: String) -> Array:
	var parts: Array = []
	parts.append([CG.ellipse_poly(3.0, 3.0, Vector2(-4.5,-3.0), 8), WOOD_DK])   # wheels
	parts.append([CG.ellipse_poly(3.0, 3.0, Vector2(4.5,-3.0), 8), WOOD_DK])
	parts.append([CG.rect_poly(-7.0,-10.0,7.0,-4.5), WOOD])                     # frame
	match utype:
		"catapult", "trebuchet":
			parts.append([CG.rect_poly(-1.0,-21.0,1.0,-9.0), WOOD])             # throwing arm
			parts.append([CG.ellipse_poly(2.0,2.0,Vector2(0,-21.5),7), STEEL])  # counterweight/sling
		"battering_ram":
			parts.append([CG.rect_poly(-8.0,-12.5,8.0,-10.0), WOOD_DK])         # roof
			parts.append([CG.rect_poly(-9.0,-7.5,9.0,-6.0), STEEL_DK])          # ram head bar
		"siege_tower":
			parts.append([CG.rect_poly(-6.5,-22.0,6.5,-10.0), WOOD])           # tall tower body
		"mantlet":
			parts.append([CG.rect_poly(-7.5,-16.0,7.5,-10.0), WOOD])          # tall shield wall
	return parts
