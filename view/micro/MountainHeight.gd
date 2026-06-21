extends RefCounted
# Shared mountain terrace-height math, so the cliff renderer (DecorChunk) and the grass-blade
# overlay on the terrace tops (MountainGrassLayer) agree on exactly how high each tile sits.

const BASE_H: float = 22.0     # height of the OUTER cliff (rim → ground): a clear, tall drop
const STEP_H: float = 13.0     # extra height each terrace adds climbing toward the peak
const MAX_LEVEL: int = 3       # few, bold terraces (fewer rings reads as a hill, not a ziggurat)

# Screen height of a tile at a given terrace level: a tall base cliff (so the massif clearly
# rises off the ground and reads as a CLIFF) plus a step per terrace toward the peak.
static func elevation_for_level(lv: int) -> float:
	return 0.0 if lv <= 0 else BASE_H + float(lv - 1) * STEP_H

static func is_mountain(gx: int, gy: int) -> bool:
	return GameState.get_terrain_at(gx, gy) == 2   # WorldGrid.Terrain.MOUNTAIN

# Terrace level: chebyshev distance to the nearest non-mountain (capped), so rim tiles are
# level 1 and the heart of the massif is the tall peak. A sparse hash notch (matching
# DecorChunk._h with salt 71) keeps the contours from reading as perfect rings.
static func level(gx: int, gy: int) -> int:
	var lv: int = MAX_LEVEL
	for d in range(1, MAX_LEVEL + 1):
		var edge := false
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				if not is_mountain(gx + dx, gy + dy):
					edge = true
					break
			if edge:
				break
		if edge:
			lv = d
			break
	# Wobble the terrace boundaries with a smooth low-frequency field, so the contours meander
	# in irregular bays and spurs (a natural slope) instead of perfect concentric rings.
	var w: float = sin(float(gx) * 0.55 + 1.3) + sin(float(gy) * 0.61 + 2.7) + sin(float(gx + gy) * 0.37)
	if w > 1.1:
		lv += 1
	elif w < -1.1:
		lv -= 1
	return clampi(lv, 1, MAX_LEVEL)

static func level_or0(gx: int, gy: int) -> int:
	return level(gx, gy) if is_mountain(gx, gy) else 0

static func elevation(gx: int, gy: int) -> float:
	return elevation_for_level(level(gx, gy))
