extends Node2D
# Renders & animates villager pawns from GameState.citizens. Procedural little
# people whose animation matches their state: walking gait, idle stand, builders
# hammering at a site, and — once assigned to a building — JOB WORKERS in their own
# outfit with their own tool and work animation (woodcutter chops, reaper scythes,
# miner picks, smith hammers with sparks, brewer stirs, priest prays, etc.).

const WorkerJobs = preload("res://simulation/world/WorkerJobs.gd")
const PeopleSystem = preload("res://simulation/world/PeopleSystem.gd")

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const SKIN  := Color(0.86, 0.70, 0.55)   # fallback for profile-less pawns
const STEEL := Color(0.74, 0.77, 0.82)
const WOOD  := Color(0.45, 0.30, 0.16)

# Global pawn scale: people are drawn a little smaller so buildings read at a
# realistic scale next to them (a house should dwarf a person).
const PAWN_SCALE: float = 0.82

# Per-person look: body scale by life-stage, sex, skin tone (spectrum), hair colour.
func _appearance(c: Dictionary) -> Dictionary:
	var stage: String = c.get("stage", "adult")
	var s: float = 1.0
	match stage:
		"baby":       s = 0.42
		"child":      s = 0.62
		"adolescent": s = 0.82
		"old":        s = 0.92
		_:            s = 1.0
	s *= PAWN_SCALE
	var skin: Color = PeopleSystem.skin_color(float(c.get("skin", 0.6))) if c.has("skin") else SKIN
	var hair: Color = c.get("hair_color", Color(0.22, 0.14, 0.08))
	if stage == "old":
		hair = hair.lerp(Color(0.84, 0.84, 0.88), 0.7)   # greys with age
	return {"scale": s, "female": c.get("sex", "m") == "f", "skin": skin, "hair": hair, "stage": stage}

# Hair drawn on the head: a coloured cap; women get long side strands, babies a wisp.
func _draw_hair(head: Vector2, r: float, ap: Dictionary) -> void:
	var hair: Color = ap.hair
	if ap.stage == "baby":
		draw_arc(head + Vector2(0, -r * 0.4), r * 0.6, PI * 1.1, TAU * 0.95, 6, hair, maxf(1.0, r * 0.5))
		return
	# Cap over the crown.
	draw_arc(head + Vector2(0, -r * 0.15), r * 1.05, PI * 0.92, TAU * 1.03, 9, hair, maxf(1.6, r * 1.0))
	if ap.female:
		draw_line(head + Vector2(-r * 0.95, -r * 0.2), head + Vector2(-r * 0.95, r * 2.4), hair, maxf(1.4, r * 0.7))
		draw_line(head + Vector2(r * 0.95, -r * 0.2), head + Vector2(r * 0.95, r * 2.4), hair, maxf(1.4, r * 0.7))

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for c in GameState.citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if c.get("state", "") == "inside":
			continue   # gone in through a door (e.g. asleep at home) — not on the street
		var sx: float = (c["x"] - c["y"]) * HALF_W
		var sy: float = (c["x"] + c["y"]) * HALF_H
		if c.get("role", "") == "worker":
			_draw_worker(sx, sy, c)
		else:
			_draw_citizen(sx, sy, c)

# ── Villagers & builders (unchanged behaviour) ──────────────────────────────────

func _draw_citizen(sx: float, sy: float, c: Dictionary) -> void:
	var st: String = c.get("state", "idle")
	var face: float = c.get("facing", 1.0)
	var builder: bool = c.get("role", "") == "builder"
	var t: float = Time.get_ticks_msec() * 0.001
	var vmoving: bool = absf(c.get("vx", 0.0)) + absf(c.get("vy", 0.0)) > 0.002
	var moving: bool = st == "walk" or st == "wander" or vmoving

	var ap := _appearance(c)
	var s: float = ap.scale
	var skin: Color = ap.skin
	# Builders blue; women warm dress-tones; men earthy.
	var tunic: Color = Color(0.30, 0.42, 0.55) if builder else (Color(0.60, 0.34, 0.42) if ap.female else Color(0.44, 0.40, 0.26))
	var dark: Color = tunic.darkened(0.3)

	var gait: float = (sin(t * 9.0) if moving else 0.0)
	var bob: float = (abs(sin(t * 9.0)) * 1.2 if moving else 0.0) * s
	var gy: float = sy
	var hip: float = gy - 7.0 * s - bob
	var shoulder: float = gy - 13.0 * s - bob
	var head := Vector2(sx, shoulder - 3.0 * s)
	var head_r: float = 3.0 * s

	draw_circle(Vector2(sx, gy + 1.0), 4.5 * s, Color(0, 0, 0, 0.18))
	# Lower body: women in a dress (skirt), men with legs + tunic.
	if ap.female:
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx - 2.2 * s, shoulder), Vector2(sx + 2.2 * s, shoulder),
			Vector2(sx + 4.2 * s, gy), Vector2(sx - 4.2 * s, gy)]), tunic)
	else:
		draw_line(Vector2(sx, hip), Vector2(sx - 2.0 * s + gait * 2.5, gy), dark, 1.8 * s)
		draw_line(Vector2(sx, hip), Vector2(sx + 2.0 * s - gait * 2.5, gy), dark, 1.8 * s)
		draw_line(Vector2(sx, hip), Vector2(sx, shoulder), tunic, 4.0 * s)

	if st == "build":
		var swing: float = sin(t * 10.0) * 0.9
		var hand := Vector2(sx + face * (4.0 + 2.0 * swing), shoulder - 4.0 + swing * 6.0)
		draw_line(Vector2(sx, shoulder), hand, skin, 1.8)
		draw_line(hand, hand + Vector2(face * 5.0, -3.0), Color(0.4, 0.28, 0.16), 1.6)
		draw_rect(Rect2(hand.x + face * 4.0 - 2.0, hand.y - 4.5, 4.0, 4.0), Color(0.55, 0.55, 0.6))
	else:
		var arm_swing: float = gait * 2.0
		draw_line(Vector2(sx, shoulder), Vector2(sx + face * 3.0 * s + arm_swing, hip + 1.0), skin, 1.6 * s)
		if builder:
			draw_line(Vector2(sx, shoulder), Vector2(sx - face * 3.0, shoulder - 6.0), Color(0.4, 0.28, 0.16), 1.6)
			draw_rect(Rect2(sx - face * 3.0 - 2.0, shoulder - 8.5, 4.0, 3.5), Color(0.55, 0.55, 0.6))

	draw_circle(head, head_r, skin)
	_draw_hair(head, head_r, ap)
	# A beard on a fraction of grown men.
	if not ap.female and ap.stage in ["adult", "midlife", "old"] and int(c.get("id", 0)) % 5 < 2:
		draw_circle(head + Vector2(0, head_r * 0.75), head_r * 0.72, skin.darkened(0.22))

# ── Job workers ─────────────────────────────────────────────────────────────────

func _draw_worker(sx: float, sy: float, c: Dictionary) -> void:
	var style: Dictionary = WorkerJobs.style(c.get("job_type", ""))
	var ap := _appearance(c)
	var anim: String = c.get("work_anim", style.get("anim", "carry"))
	var tunic: Color = style.get("tunic", Color(0.5, 0.4, 0.28))
	var face: float = c.get("facing", 1.0)
	var st: String = c.get("state", "idle")
	var phase: String = c.get("work_phase", "")
	var hauling: bool = phase == "haul_in" or phase == "haul_out"
	# Haulers move while in the "work" state, so drive the walk from actual velocity.
	var vmoving: bool = absf(c.get("vx", 0.0)) + absf(c.get("vy", 0.0)) > 0.002
	var working: bool = st == "work" and not hauling and not vmoving
	var moving: bool = st == "walk" or st == "wander" or vmoving
	var t: float = Time.get_ticks_msec() * 0.001 + float(c.get("id", 0)) * 0.6

	var dark: Color = tunic.darkened(0.32)
	var gait: float = (sin(t * 9.0) if moving else 0.0)
	var bob: float = (abs(sin(t * 9.0)) * 1.2 if moving else 0.0)
	var gy: float = sy
	var hip: float = gy - 7.0 - bob
	var shoulder: float = gy - 13.0 - bob
	var head := Vector2(sx, shoulder - 3.0)

	draw_circle(Vector2(sx, gy + 1.0), 4.5, Color(0, 0, 0, 0.18))

	# Legs (robes draw a skirt instead of bare legs).
	if style.get("robe", false):
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx - 2.5, shoulder), Vector2(sx + 2.5, shoulder),
			Vector2(sx + 3.5, gy), Vector2(sx - 3.5, gy)]), tunic)
	else:
		draw_line(Vector2(sx, hip), Vector2(sx - 2.0 + gait * 2.5, gy), dark, 1.8)
		draw_line(Vector2(sx, hip), Vector2(sx + 2.0 - gait * 2.5, gy), dark, 1.8)
	# Torso.
	draw_line(Vector2(sx, hip), Vector2(sx, shoulder), tunic, 4.0)

	# Work animation (stationary), hauling a load, or carry-the-tool walk.
	if working:
		_draw_job(sx, shoulder, hip, gy, face, anim, style, t)
	elif hauling:
		# Both hands clutch a load carried at the chest.
		draw_line(Vector2(sx, shoulder), Vector2(sx + face * 3.0, hip + 1.0), SKIN, 1.6)
		_draw_carry_load(sx, shoulder, c.get("carry", ""))
	else:
		# Walking/idle: one arm swings, the tool is shouldered so the job still reads.
		draw_line(Vector2(sx, shoulder), Vector2(sx + face * 3.0 + gait * 2.0, hip + 1.0), SKIN, 1.6)
		_draw_shouldered_tool(sx, shoulder, face, anim, style)

	# Head: the worker's own skin tone; hair shows unless a helmet/hood covers it.
	draw_circle(head, 3.0, ap.skin)
	if style.get("helmet", false):
		draw_arc(head + Vector2(0, -0.5), 3.2, PI, TAU, 7, STEEL, 1.4)
		draw_circle(head + Vector2(face * 1.2, -1.2), 0.9, Color(1.0, 0.95, 0.5))  # lamp
	elif style.get("robe", false):
		draw_colored_polygon(PackedVector2Array([
			head + Vector2(-3.2, 1.2), head + Vector2(3.2, 1.2),
			head + Vector2(2.0, -3.0), head + Vector2(-2.0, -3.0)]), tunic.darkened(0.1))
	else:
		_draw_hair(head, 3.0, ap)

# Animated tool + arms for each job archetype. (sh=shoulder y, hip, gy=feet y)
func _draw_job(sx: float, sh: float, hip: float, gy: float, face: float, anim: String, style: Dictionary, t: float) -> void:
	match anim:
		"chop":
			var sw: float = sin(t * 7.0)
			var hand := Vector2(sx + face * (3.0 + sw * 2.0), sh + 1.0 + sw * 2.0)
			draw_line(Vector2(sx, sh), hand, SKIN, 1.7)
			var head_p := hand + Vector2(face * (5.0 + sw * 3.0), -2.0 + sw * 3.0)
			draw_line(hand, head_p, WOOD, 1.4)                       # haft
			draw_line(head_p, head_p + Vector2(face * 2.0, 1.5), STEEL, 2.0)  # blade
		"mine":
			var dn: float = (sin(t * 6.0) * 0.5 + 0.5)              # 0 up .. 1 down
			var hand2 := Vector2(sx + face * 3.0, sh - 3.0 + dn * 7.0)
			draw_line(Vector2(sx, sh), hand2, SKIN, 1.7)
			var tip := hand2 + Vector2(face * 4.0, -5.0 + dn * 9.0)
			draw_line(hand2, tip, WOOD, 1.4)
			draw_arc(tip, 3.0, PI * 0.8, PI * 1.7, 6, STEEL, 1.6)   # pick head
		"scythe":
			var sweep: float = sin(t * 4.0)
			var grip := Vector2(sx + face * 3.0, sh + 2.0)
			draw_line(Vector2(sx, sh), grip, SKIN, 1.7)
			var sc_end := grip + Vector2(face * (6.0 + sweep * 3.0), 5.0)
			draw_line(grip, sc_end, WOOD, 1.4)
			draw_arc(sc_end, 4.0, -PI * 0.2 + sweep * 0.5, PI * 0.6 + sweep * 0.5, 7, STEEL, 1.4)
		"pick":  # reach up to harvest (orchard/hops)
			var up: float = (sin(t * 4.5) * 0.5 + 0.5)
			var hand3 := Vector2(sx + face * 2.5, sh - 2.0 - up * 6.0)
			draw_line(Vector2(sx, sh), hand3, SKIN, 1.7)
			draw_circle(hand3, 1.3, Color(0.85, 0.2, 0.18))          # fruit picked
			draw_rect(Rect2(sx - face * 3.5 - 2.0, hip - 3.0, 4.0, 4.0), WOOD)  # basket
		"hammer":
			var dn2: float = (sin(t * 8.0) * 0.5 + 0.5)
			var anvil := Vector2(sx + face * 5.0, hip + 1.0)
			draw_rect(Rect2(anvil.x - 2.5, anvil.y - 2.0, 5.0, 2.5), Color(0.3, 0.3, 0.34))  # anvil
			var hand4 := Vector2(sx + face * 3.5, sh - 4.0 + dn2 * 6.0)
			draw_line(Vector2(sx, sh), hand4, SKIN, 1.7)
			draw_line(hand4, hand4 + Vector2(face * 2.0, -3.0 + dn2 * 4.0), WOOD, 1.3)
			draw_rect(Rect2(hand4.x + face * 1.0, hand4.y - 4.0 + dn2 * 4.0, 3.0, 2.4), STEEL)
			if style.get("sparks", false) and dn2 > 0.8:
				for k in range(3):
					draw_line(anvil + Vector2(0, -2), anvil + Vector2(face * (k - 1) * 2.0, -5.0 - k), Color(1.0, 0.8, 0.2), 0.8)
		"stir":
			var a: float = t * 5.0
			var bowl := Vector2(sx + face * 4.0, hip)
			draw_circle(bowl, 2.6, Color(0.36, 0.28, 0.2))          # vat/bowl
			var hand5 := bowl + Vector2(cos(a) * 1.6, -3.0 + sin(a) * 1.0)
			draw_line(Vector2(sx, sh), hand5, SKIN, 1.7)
			draw_line(hand5, bowl + Vector2(cos(a) * 1.2, 0), WOOD, 1.2)  # paddle
		"tend":  # crouch to feed/milk
			var bobv: float = sin(t * 4.0) * 1.5
			var hand6 := Vector2(sx + face * 4.0, hip + 2.0 + bobv)
			draw_line(Vector2(sx, sh), hand6, SKIN, 1.7)
			draw_rect(Rect2(hand6.x - 1.5, hand6.y, 3.0, 3.0), Color(0.7, 0.7, 0.72))  # pail
		"serve":
			var bobv2: float = sin(t * 3.0) * 1.2
			var hand7 := Vector2(sx + face * 5.0, sh + 1.0 + bobv2)
			draw_line(Vector2(sx, sh), hand7, SKIN, 1.6)
			draw_rect(Rect2(hand7.x - 1.0, hand7.y - 2.0, 2.5, 3.0), Color(0.8, 0.66, 0.3))  # mug/goods
		"pray":
			var sway: float = sin(t * 2.0) * 0.6
			draw_line(Vector2(sx, sh), Vector2(sx + 3.0 + sway, sh - 5.0), SKIN, 1.5)
			draw_line(Vector2(sx, sh), Vector2(sx - 3.0 + sway, sh - 5.0), SKIN, 1.5)
			draw_rect(Rect2(sx - 1.5, sh + 1.0, 3.0, 2.2), Color(0.7, 0.6, 0.3))  # book
		"guard":
			var look: float = sin(t * 1.2)
			draw_line(Vector2(sx, sh), Vector2(sx + face * 2.0, hip), SKIN, 1.6)
			draw_line(Vector2(sx + face * 3.0, gy), Vector2(sx + face * 3.0, sh - 9.0), WOOD, 1.3)  # spear
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx + face * 3.0, sh - 9.0), Vector2(sx + face * 2.0, sh - 7.0),
				Vector2(sx + face * 4.0, sh - 7.0)]), STEEL)
			# subtle head turn handled by facing; look unused beyond liveliness
			head_dummy(look)
		_:  # carry — sack on the shoulder
			draw_line(Vector2(sx, sh), Vector2(sx + face * 2.5, hip + 1.0), SKIN, 1.6)
			draw_rect(Rect2(sx - face * 3.5 - 1.5, sh - 1.0, 4.0, 5.0), Color(0.62, 0.50, 0.30))

func head_dummy(_v: float) -> void:
	pass

# Tool shouldered while walking, so the worker's trade reads en route.
# A load carried at the chest while hauling — coloured by the good (log/ore/sack).
func _draw_carry_load(sx: float, sh: float, good: String) -> void:
	var col: Color
	match good:
		"wood", "firewood", "raw": col = Color(0.50, 0.36, 0.20)   # logs
		"stone":                   col = Color(0.60, 0.60, 0.64)   # stone
		"iron", "ore":             col = Color(0.45, 0.40, 0.36)   # ore
		"apples", "wheat", "hops", "flour", "bread": col = Color(0.78, 0.66, 0.34)  # grain sack
		_:                         col = Color(0.66, 0.54, 0.34)   # generic sack
	var top := sh + 1.0
	draw_rect(Rect2(sx - 3.0, top, 6.0, 5.0), col)
	draw_rect(Rect2(sx - 3.0, top, 6.0, 5.0), col.darkened(0.3), false, 0.8)

func _draw_shouldered_tool(sx: float, sh: float, face: float, anim: String, style: Dictionary) -> void:
	match anim:
		"chop":
			draw_line(Vector2(sx - face * 2.0, sh + 2.0), Vector2(sx - face * 5.0, sh - 6.0), WOOD, 1.4)
			draw_line(Vector2(sx - face * 5.0, sh - 6.0), Vector2(sx - face * 6.5, sh - 5.0), STEEL, 2.0)
		"mine", "hammer":
			draw_line(Vector2(sx - face * 2.0, sh + 2.0), Vector2(sx - face * 5.0, sh - 6.0), WOOD, 1.4)
			draw_arc(Vector2(sx - face * 5.0, sh - 6.0), 2.4, PI * 0.7, PI * 1.6, 5, STEEL, 1.4)
		"scythe":
			draw_line(Vector2(sx - face * 2.0, sh + 2.0), Vector2(sx - face * 5.5, sh - 7.0), WOOD, 1.4)
			draw_arc(Vector2(sx - face * 5.5, sh - 7.0), 3.0, 0, PI * 0.8, 6, STEEL, 1.3)
		"pick", "carry":
			draw_rect(Rect2(sx - face * 3.5 - 2.0, sh - 1.0, 4.0, 4.5), Color(0.6, 0.48, 0.28))
		"guard":
			draw_line(Vector2(sx + face * 2.0, sh + 3.0), Vector2(sx + face * 2.0, sh - 9.0), WOOD, 1.3)
		_:
			pass
