extends RefCounted
# Procedural, animated body art for every unit type. Pure draw helpers — given a
# CanvasItem, a feet position, a unit dict, team color and a time value, it renders
# a distinct, animated little figure (or war machine) for that type.
#
# Animation is driven by the unit's `order` (idle / walk / attack) plus a per-unit
# phase offset so a crowd never marches in lockstep. Facing flips on the X axis
# from the unit's movement/target direction.
#
# Design goals: each type reads at a glance (silhouette + weapon + armor), limbs
# actually swing, archers draw their bows, melee troops swing, polearms bristle,
# and siege engines look like machines, not men.

const UnitState = preload("res://simulation/units/UnitState.gd")

const SKIN      := Color(0.86, 0.70, 0.55)
const SKIN_DARK := Color(0.62, 0.46, 0.34)
const STEEL     := Color(0.74, 0.77, 0.82)
const STEEL_DK  := Color(0.42, 0.45, 0.52)
const WOOD      := Color(0.47, 0.32, 0.17)
const WOOD_DK   := Color(0.33, 0.22, 0.12)
const LEATHER   := Color(0.42, 0.29, 0.17)
const CLOTH_OFF := Color(0.80, 0.78, 0.70)

# ── Entry point ──────────────────────────────────────────────────────────────

# pos = feet/ground point (screen space). team = faction tint. t = seconds.
static func draw_unit(ci: CanvasItem, pos: Vector2, unit: Dictionary, team: Color,
		t: float, flash: float = 0.0) -> void:
	var utype: String = unit.get("type", "")
	var order: String = unit.get("order", UnitState.ORDER_IDLE)
	var uid: int = unit.get("id", 0)
	var phase: float = t * 8.0 + float(uid) * 0.7
	var facing: float = _facing(unit)
	var st: String = _anim_state(order)

	# Soft ground shadow.
	ci.draw_circle(pos + Vector2(0, 1.0), 5.0, Color(0, 0, 0, 0.22))

	match utype:
		"battering_ram":  _siege_ram(ci, pos, team, phase, st, facing)
		"catapult":       _siege_catapult(ci, pos, team, phase, st, facing)
		"trebuchet":      _siege_trebuchet(ci, pos, team, phase, st, facing)
		"siege_tower":    _siege_tower(ci, pos, team, phase, facing)
		"mantlet":        _siege_mantlet(ci, pos, team, facing)
		_:               _draw_person(ci, pos, utype, team, phase, st, facing, flash)

# ── Animation helpers ────────────────────────────────────────────────────────

static func _anim_state(order: String) -> String:
	match order:
		UnitState.ORDER_MOVE, UnitState.ORDER_PATROL: return "walk"
		UnitState.ORDER_ATTACK: return "attack"
	return "idle"

static func _facing(unit: Dictionary) -> float:
	var dx: int = unit.get("target_x", unit.get("pos_x", 0)) - unit.get("pos_x", 0)
	if dx > 0: return 1.0
	if dx < 0: return -1.0
	return 1.0

# Per-type humanoid styling.
static func _style(utype: String) -> Dictionary:
	match utype:
		"peasant":       return {"cloth": Color(0.55,0.42,0.26), "helm":"none", "plate":false, "weapon":"hoe", "shield":"none"}
		"scout":         return {"cloth": Color(0.36,0.47,0.32), "helm":"hood", "plate":false, "weapon":"none", "shield":"none", "cloak":Color(0.30,0.40,0.27)}
		"monk":          return {"cloth": Color(0.42,0.34,0.24), "helm":"hood", "plate":false, "weapon":"staff", "shield":"none", "robe":true}
		"merchant":      return {"cloth": Color(0.55,0.30,0.42), "helm":"cap", "plate":false, "weapon":"pouch", "shield":"none", "robe":true}
		"settler":       return {"cloth": Color(0.58,0.50,0.34), "helm":"cap", "plate":false, "weapon":"pack", "shield":"none"}
		"armed_peasant": return {"cloth": Color(0.50,0.40,0.26), "helm":"none", "plate":false, "weapon":"club", "shield":"none"}
		"archer":        return {"cloth": Color(0.40,0.46,0.28), "helm":"cap", "plate":false, "weapon":"bow", "shield":"none", "quiver":true}
		"ladderman":     return {"cloth": Color(0.52,0.42,0.28), "helm":"cap", "plate":false, "weapon":"ladder", "shield":"none"}
		"tunneler":      return {"cloth": Color(0.46,0.38,0.28), "helm":"cap", "plate":false, "weapon":"pick", "shield":"none"}
		"militia":       return {"cloth": Color(0.45,0.40,0.30), "helm":"cap", "plate":false, "weapon":"spear", "shield":"round"}
		"crossbowman":   return {"cloth": Color(0.40,0.40,0.46), "helm":"iron", "plate":true, "weapon":"crossbow", "shield":"none", "quiver":true}
		"pikeman":       return {"cloth": Color(0.40,0.40,0.46), "helm":"iron", "plate":true, "weapon":"pike", "shield":"none"}
		"swordsman":     return {"cloth": Color(0.40,0.40,0.46), "helm":"iron", "plate":true, "weapon":"sword", "shield":"kite"}
		"captain":       return {"cloth": Color(0.45,0.42,0.50), "helm":"plume", "plate":true, "weapon":"sword", "shield":"kite", "banner":true}
		"halberdier":    return {"cloth": Color(0.40,0.40,0.46), "helm":"iron", "plate":true, "weapon":"halberd", "shield":"none"}
	return {"cloth": Color(0.5,0.4,0.3), "helm":"none", "plate":false, "weapon":"none", "shield":"none"}

# ── Humanoid figure ──────────────────────────────────────────────────────────

static func _draw_person(ci: CanvasItem, pos: Vector2, utype: String, team: Color,
		phase: float, st: String, facing: float, flash: float) -> void:
	var s: Dictionary = _style(utype)
	# Cloth is tinted toward the team color so allegiance reads clearly.
	var cloth: Color = (s["cloth"] as Color).lerp(team, 0.45)
	var plate: bool = s.get("plate", false)
	if flash > 0.0:
		cloth = cloth.lerp(Color.WHITE, flash)

	var walk: bool = st == "walk"
	var atk: bool = st == "attack"
	var bob: float = (abs(sin(phase)) * 1.6) if walk else (sin(phase * 0.25) * 0.4)
	var cx: float = pos.x
	var feet: float = pos.y
	var hip := Vector2(cx, feet - 7.0 - bob)
	var sh := Vector2(cx, feet - 15.0 - bob)
	var head := Vector2(cx, feet - 19.5 - bob)

	# Legs (swing while walking).
	var swing: float = sin(phase) * 3.2 if walk else 0.0
	var leg_col: Color = STEEL_DK if plate else cloth.darkened(0.4)
	_limb(ci, hip, Vector2(cx - 1.2 + swing, feet), leg_col, 2.4)
	_limb(ci, hip, Vector2(cx + 1.2 - swing, feet), leg_col, 2.4)

	# Cloak (behind torso) for scouts.
	if s.has("cloak"):
		var cl: Color = s["cloak"]
		var sway: float = swing * 0.6
		ci.draw_colored_polygon(PackedVector2Array([
			sh + Vector2(-facing * 1.0, -1.0), sh + Vector2(facing * 3.0, -1.0),
			Vector2(cx + facing * 4.0 - sway, feet - 2.0), Vector2(cx - facing * 2.0 - sway, feet - 1.0),
		]), cl.lerp(team, 0.3))

	# Robe (long skirt) for monk/merchant instead of separate legs feel.
	if s.get("robe", false):
		ci.draw_colored_polygon(PackedVector2Array([
			sh + Vector2(-3.0, 0), sh + Vector2(3.0, 0),
			Vector2(cx + 4.0, feet), Vector2(cx - 4.0, feet),
		]), cloth)

	# Torso.
	var torso_col: Color = STEEL if plate else cloth
	_limb(ci, hip, sh, torso_col, 5.2 if plate else 4.2)
	if plate:
		# Pauldron highlights.
		ci.draw_circle(sh + Vector2(-2.6, 0), 1.6, STEEL.lightened(0.12))
		ci.draw_circle(sh + Vector2(2.6, 0), 1.6, STEEL.lightened(0.12))
		_limb(ci, hip + Vector2(0,-1), sh, STEEL_DK, 1.0)  # chest seam

	# Arms + weapon. The weapon arm animates for attacks.
	var atk_cycle: float = (sin(phase * 0.9) * 0.5 + 0.5) if atk else 0.0  # 0..1
	_draw_arms_and_weapon(ci, sh, hip, feet, facing, s, cloth, plate, walk, atk, atk_cycle, phase)

	# Shield on the off-hand.
	if s.get("shield", "none") != "none":
		_draw_shield(ci, sh, hip, facing, s["shield"], team)

	# Head + helm.
	ci.draw_circle(head, 3.0, SKIN)
	_draw_helm(ci, head, s.get("helm", "none"), team, facing)

	# Quiver on the back.
	if s.get("quiver", false):
		_limb(ci, sh + Vector2(-facing*1.5, -0.5), sh + Vector2(-facing*3.5, -5.0), LEATHER, 1.8)
		for i in range(3):
			_limb(ci, sh + Vector2(-facing*3.0 + i*0.6*facing, -4.0), sh + Vector2(-facing*3.4 + i*0.6*facing, -6.5), Color(0.9,0.9,0.8), 0.7)

	# Banner pole (captain) — waving pennant.
	if s.get("banner", false):
		var bx: float = cx - facing * 3.5
		var top := Vector2(bx, feet - 30.0 - bob)
		_limb(ci, Vector2(bx, feet - 4.0), top, WOOD_DK, 1.3)
		var wave: float = sin(phase * 0.5) * 1.5
		ci.draw_colored_polygon(PackedVector2Array([
			top, top + Vector2(facing * 7.0 + wave, 2.0), top + Vector2(0, 5.0),
		]), team.lerp(Color(0.9,0.2,0.2), 0.4))

static func _draw_arms_and_weapon(ci: CanvasItem, sh: Vector2, hip: Vector2, feet: float,
		facing: float, s: Dictionary, cloth: Color, plate: bool, walk: bool, atk: bool,
		atk_cycle: float, phase: float) -> void:
	var arm_col: Color = STEEL if plate else SKIN
	var weapon: String = s.get("weapon", "none")
	var arm_swing: float = sin(phase) * 2.4 if walk else 0.0
	# Off-hand (back arm) — simple swing.
	_limb(ci, sh, Vector2(sh.x - facing * 2.0 - arm_swing, hip.y + 1.0), arm_col, 1.9)

	# Weapon hand position; attacks raise/extend it.
	var hand := Vector2(sh.x + facing * 2.5, hip.y + 0.5)
	match weapon:
		"bow":
			# Draw arm bent; bow in front hand; arrow nocked, drawn on attack.
			var fronthand := Vector2(sh.x + facing * 5.0, sh.y + 1.5)
			var draw_back: float = atk_cycle * 3.0
			var nock := Vector2(sh.x + facing * (1.5 - draw_back), sh.y + 1.5)
			_limb(ci, sh, fronthand, arm_col, 1.9)         # bow arm extended
			_limb(ci, sh, nock, arm_col, 1.7)              # string arm
			# Bow stave.
			ci.draw_arc(fronthand, 6.0, -PI*0.55, PI*0.55, 9, WOOD, 1.6)
			# String + arrow.
			var top := fronthand + Vector2(0, -5.0)
			var bot := fronthand + Vector2(0, 5.0)
			ci.draw_line(top, nock, Color(0.92,0.9,0.8), 0.8)
			ci.draw_line(bot, nock, Color(0.92,0.9,0.8), 0.8)
			ci.draw_line(nock, fronthand + Vector2(facing*2.0,0), Color(0.85,0.82,0.7), 1.0)
		"crossbow":
			var fh := Vector2(sh.x + facing * 5.5, sh.y + 2.0)
			_limb(ci, sh, fh, arm_col, 2.0)
			ci.draw_line(fh + Vector2(-facing*2.0,0), fh + Vector2(facing*4.0,0), WOOD_DK, 2.0)   # stock
			ci.draw_line(fh + Vector2(facing*2.0,-3.0), fh + Vector2(facing*2.0,3.0), STEEL, 1.4) # bow limbs
			ci.draw_line(fh + Vector2(facing*2.0,-3.0), fh + Vector2(facing*2.0,3.0), STEEL, 1.0)
		"sword":
			var raise: float = atk_cycle * 7.0
			var hsword := Vector2(sh.x + facing * (3.0 + atk_cycle*2.0), sh.y - 2.0 - raise)
			_limb(ci, sh, hsword, arm_col, 2.0)
			# Blade + crossguard.
			var tip := hsword + Vector2(facing * (2.0 + atk_cycle*4.0), -8.0 + raise*1.2)
			ci.draw_line(hsword, tip, STEEL.lightened(0.1), 1.8)
			ci.draw_line(hsword + Vector2(-facing*1.5,0.5), hsword + Vector2(facing*1.5,0.5), WOOD_DK, 1.4)
		"halberd":
			var hh := Vector2(sh.x + facing * 3.5, sh.y - 1.0)
			_limb(ci, sh, hh, arm_col, 2.0)
			var btm := Vector2(hh.x - facing*1.0, feet - 1.0)
			var top := Vector2(hh.x + facing*1.5, sh.y - 16.0)
			ci.draw_line(btm, top, WOOD, 1.6)              # shaft
			ci.draw_line(top, top + Vector2(facing*4.0, 3.0), STEEL, 1.6)   # axe blade
			ci.draw_line(top, top + Vector2(0, -3.0), STEEL, 1.3)          # spike
		"pike":
			var hh2 := Vector2(sh.x + facing * 3.0, sh.y)
			_limb(ci, sh, hh2, arm_col, 2.0)
			var btm2 := Vector2(hh2.x - facing*1.0, feet)
			var top2 := Vector2(hh2.x + facing*2.0, sh.y - 26.0)   # very long
			ci.draw_line(btm2, top2, WOOD, 1.4)
			ci.draw_colored_polygon(PackedVector2Array([
				top2, top2 + Vector2(-facing*1.2, 3.0), top2 + Vector2(facing*1.2, 3.0)]), STEEL)
		"spear":
			var hh3 := Vector2(sh.x + facing * 3.0, sh.y)
			_limb(ci, sh, hh3, arm_col, 1.9)
			var btm3 := Vector2(hh3.x - facing*1.0, feet - 1.0)
			var top3 := Vector2(hh3.x + facing*1.5, sh.y - 14.0)
			ci.draw_line(btm3, top3, WOOD, 1.3)
			ci.draw_colored_polygon(PackedVector2Array([
				top3, top3 + Vector2(-facing*1.0, 2.5), top3 + Vector2(facing*1.0, 2.5)]), STEEL)
		"club":
			var raise2: float = atk_cycle * 6.0
			var hc := Vector2(sh.x + facing * 3.0, sh.y - 1.0 - raise2)
			_limb(ci, sh, hc, arm_col, 2.0)
			ci.draw_line(hc, hc + Vector2(facing*4.0, -4.0 + raise2), WOOD, 2.2)
		"hoe":
			var hh4 := Vector2(sh.x + facing * 3.0, sh.y + 1.0)
			_limb(ci, sh, hh4, arm_col, 1.9)
			var top4 := Vector2(hh4.x + facing*2.0, sh.y - 8.0)
			ci.draw_line(Vector2(hh4.x, feet-2.0), top4, WOOD, 1.3)
			ci.draw_line(top4, top4 + Vector2(facing*2.5, 0.5), STEEL_DK, 1.6)
		"pick":
			var hp := Vector2(sh.x + facing * 3.0, sh.y)
			_limb(ci, sh, hp, arm_col, 1.9)
			var topp := Vector2(hp.x + facing*1.0, sh.y - 7.0)
			ci.draw_line(Vector2(hp.x, feet-2.0), topp, WOOD, 1.3)
			ci.draw_arc(topp, 3.0, PI*0.9, PI*1.6, 6, STEEL_DK, 1.5)
		"staff":
			var hstaff := Vector2(sh.x + facing * 3.0, sh.y)
			_limb(ci, sh, hstaff, SKIN, 1.7)
			ci.draw_line(Vector2(hstaff.x, sh.y - 8.0), Vector2(hstaff.x, feet - 1.0), WOOD, 1.3)
		"pouch":
			_limb(ci, sh, hand, arm_col, 1.8)
			ci.draw_circle(hand + Vector2(0, 1.0), 1.8, Color(0.8,0.65,0.2))  # coin purse
		"pack":
			_limb(ci, sh, hand, arm_col, 1.8)
			ci.draw_rect(Rect2(sh.x - facing*4.5 - 1.5, sh.y - 1.0, 3.5, 5.0), LEATHER)  # backpack
		"ladder":
			_limb(ci, sh, hand, arm_col, 1.8)
			var lx: float = sh.x + facing * 1.0
			ci.draw_line(Vector2(lx-1.5, sh.y-6.0), Vector2(lx-1.5+facing*5.0, feet-2.0), WOOD, 1.2)
			ci.draw_line(Vector2(lx+1.5, sh.y-6.0), Vector2(lx+1.5+facing*5.0, feet-2.0), WOOD, 1.2)
			for i in range(3):
				var fr: float = float(i)/3.0
				ci.draw_line(Vector2(lx-1.5+facing*5.0*fr, sh.y-6.0+ (feet-2.0-(sh.y-6.0))*fr),
					Vector2(lx+1.5+facing*5.0*fr, sh.y-6.0+(feet-2.0-(sh.y-6.0))*fr), WOOD, 0.7)
		_:
			_limb(ci, sh, hand, arm_col, 1.8)

static func _draw_shield(ci: CanvasItem, sh: Vector2, hip: Vector2, facing: float, kind: String, team: Color) -> void:
	var cx: float = sh.x - facing * 3.2
	var cy: float = (sh.y + hip.y) * 0.5
	var col: Color = team.lerp(Color(0.85,0.82,0.7), 0.25)
	if kind == "round":
		ci.draw_circle(Vector2(cx, cy), 3.2, col)
		ci.draw_arc(Vector2(cx, cy), 3.2, 0, TAU, 12, WOOD_DK, 0.8)
		ci.draw_circle(Vector2(cx, cy), 0.9, STEEL)
	else:  # kite
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(cx-2.6, cy-3.0), Vector2(cx+2.6, cy-3.0),
			Vector2(cx+2.0, cy+1.5), Vector2(cx, cy+4.5), Vector2(cx-2.0, cy+1.5)]), col)
		ci.draw_line(Vector2(cx, cy-3.0), Vector2(cx, cy+4.0), team.darkened(0.3), 0.8)

static func _draw_helm(ci: CanvasItem, head: Vector2, kind: String, team: Color, facing: float) -> void:
	match kind:
		"cap":
			ci.draw_colored_polygon(PackedVector2Array([
				head + Vector2(-3.0, -0.5), head + Vector2(3.0, -0.5), head + Vector2(0, -3.5)]), LEATHER)
		"hood":
			ci.draw_colored_polygon(PackedVector2Array([
				head + Vector2(-3.4, 1.5), head + Vector2(3.4, 1.5),
				head + Vector2(2.2, -3.0), head + Vector2(-2.2, -3.0)]), team.lerp(Color(0.3,0.3,0.3),0.5))
		"iron":
			ci.draw_circle(head + Vector2(0, -0.6), 3.2, STEEL)
			ci.draw_arc(head + Vector2(0,-0.6), 3.2, PI, TAU, 8, STEEL_DK, 0.8)
			ci.draw_line(head + Vector2(0,-0.6), head + Vector2(0, 2.5), STEEL_DK, 0.7)  # nasal
		"plume":
			ci.draw_circle(head + Vector2(0, -0.6), 3.3, STEEL.lightened(0.05))
			ci.draw_arc(head + Vector2(0,-0.6), 3.3, PI, TAU, 8, STEEL_DK, 0.8)
			# crest plume
			for i in range(4):
				ci.draw_line(head + Vector2(0, -3.5 + i*0.2), head + Vector2(-facing*1.0, -6.5 + i*0.2),
					Color(0.9,0.2,0.2), 1.0)

static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, col, w)

# ── Siege engines ────────────────────────────────────────────────────────────

static func _wheels(ci: CanvasItem, pos: Vector2, span: float) -> void:
	for wx in [-span, span]:
		ci.draw_circle(pos + Vector2(wx, 0), 2.6, WOOD_DK)
		ci.draw_circle(pos + Vector2(wx, 0), 1.1, WOOD)

static func _siege_ram(ci: CanvasItem, pos: Vector2, team: Color, phase: float, st: String, facing: float) -> void:
	var feet: float = pos.y
	_wheels(ci, Vector2(pos.x, feet), 6.0)
	# Pitched roof shelter.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x-8, feet-6), Vector2(pos.x+8, feet-6),
		Vector2(pos.x+6, feet-12), Vector2(pos.x-6, feet-12)]), WOOD)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x-6, feet-12), Vector2(pos.x+6, feet-12), Vector2(pos.x, feet-15)]), team.lerp(WOOD_DK,0.5))
	# The ram log, sliding on attack.
	var slide: float = (sin(phase*0.8) * 3.0) if st == "attack" else 0.0
	var ry: float = feet - 7.0
	ci.draw_line(Vector2(pos.x-7+slide, ry), Vector2(pos.x+9+slide, ry), WOOD_DK, 3.0)
	ci.draw_circle(Vector2(pos.x+9+slide, ry), 2.2, STEEL_DK)  # iron head

static func _siege_catapult(ci: CanvasItem, pos: Vector2, team: Color, phase: float, st: String, facing: float) -> void:
	var feet: float = pos.y
	_wheels(ci, Vector2(pos.x, feet), 6.0)
	# Frame.
	ci.draw_line(Vector2(pos.x-6, feet), Vector2(pos.x-6, feet-7), WOOD, 2.0)
	ci.draw_line(Vector2(pos.x+5, feet), Vector2(pos.x+5, feet-5), WOOD, 2.0)
	ci.draw_line(Vector2(pos.x-7, feet-1), Vector2(pos.x+7, feet-1), WOOD_DK, 2.2)
	# Throwing arm — winds back then releases.
	var fire: float = (sin(phase*0.7)*0.5+0.5) if st == "attack" else 0.15
	var ang: float = lerp(-2.5, -0.6, fire) * facing
	var pivot := Vector2(pos.x-4, feet-6)
	var armend := pivot + Vector2(cos(ang), sin(ang)) * 11.0
	ci.draw_line(pivot, armend, WOOD, 2.0)
	ci.draw_circle(armend, 1.8, Color(0.4,0.36,0.3))  # payload bucket

static func _siege_trebuchet(ci: CanvasItem, pos: Vector2, team: Color, phase: float, st: String, facing: float) -> void:
	var feet: float = pos.y
	_wheels(ci, Vector2(pos.x, feet), 5.0)
	# A-frame tower.
	ci.draw_line(Vector2(pos.x-6, feet), Vector2(pos.x, feet-16), WOOD, 2.0)
	ci.draw_line(Vector2(pos.x+6, feet), Vector2(pos.x, feet-16), WOOD, 2.0)
	ci.draw_line(Vector2(pos.x-4, feet-8), Vector2(pos.x+4, feet-8), WOOD_DK, 1.4)
	# Long beam with counterweight, rotating on fire.
	var fire: float = (sin(phase*0.5)*0.5+0.5) if st == "attack" else 0.2
	var ang: float = lerp(0.5, 2.4, fire)
	var pivot := Vector2(pos.x, feet-15)
	var long_end := pivot + Vector2(cos(PI-ang)*facing, -sin(ang)) * 13.0
	var short_end := pivot - Vector2(cos(PI-ang)*facing, -sin(ang)) * 6.0
	ci.draw_line(short_end, long_end, WOOD.lightened(0.1), 1.8)
	ci.draw_rect(Rect2(short_end.x-2.0, short_end.y-2.0, 4.0, 4.0), STEEL_DK)  # counterweight
	ci.draw_line(long_end, long_end + Vector2(0, 4.0), Color(0.9,0.9,0.8), 0.7)  # sling

static func _siege_tower(ci: CanvasItem, pos: Vector2, team: Color, phase: float, facing: float) -> void:
	var feet: float = pos.y
	_wheels(ci, Vector2(pos.x, feet), 5.0)
	ci.draw_rect(Rect2(pos.x-6, feet-20, 12, 19), WOOD)
	ci.draw_rect(Rect2(pos.x-6, feet-20, 12, 19), WOOD_DK, false, 1.0)
	# Floor lines + crenellated top.
	for i in range(1, 3):
		ci.draw_line(Vector2(pos.x-6, feet-1-i*6), Vector2(pos.x+6, feet-1-i*6), WOOD_DK, 0.8)
	for mx in range(-6, 7, 3):
		ci.draw_rect(Rect2(pos.x+mx, feet-23, 2, 3), WOOD)
	# Drawbridge ramp + team pennant.
	ci.draw_line(Vector2(pos.x+6, feet-18), Vector2(pos.x+facing*11, feet-14), WOOD_DK, 1.6)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x, feet-23), Vector2(pos.x+facing*5, feet-22), Vector2(pos.x, feet-20)]), team)

static func _siege_mantlet(ci: CanvasItem, pos: Vector2, team: Color, facing: float) -> void:
	var feet: float = pos.y
	_wheels(ci, Vector2(pos.x, feet), 4.0)
	# Big wheeled pavise shield wall.
	ci.draw_rect(Rect2(pos.x-5, feet-12, 10, 11), WOOD)
	ci.draw_rect(Rect2(pos.x-5, feet-12, 10, 11), WOOD_DK, false, 1.0)
	for i in range(3):
		ci.draw_line(Vector2(pos.x-5, feet-3-i*4), Vector2(pos.x+5, feet-3-i*4), WOOD_DK, 0.7)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x-2, feet-12), Vector2(pos.x+2, feet-12), Vector2(pos.x, feet-14)]), team)
