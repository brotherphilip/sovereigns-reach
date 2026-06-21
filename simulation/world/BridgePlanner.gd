extends RefCounted
# Plans a bridge crossing for a hovered cell. Shared by the placement preview (view),
# the place-bridge command (sim) and the AI, so all three agree on exactly which cells a
# bridge would occupy.
#
# Rule (from design): the bridge is anchored on the LAND cell next to a river edge, runs
# straight across the water, and ends on the land cell next to the river's far edge. The
# planner finds that span automatically and reports whether it's a legal crossing.

const WorldGrid = preload("res://simulation/world/WorldGrid.gd")

const MAX_WATER: int = 14   # widest river a single bridge may span (keeps it sane)

# Cells that block a land anchor (you can't start/end a bridge on these).
const _BLOCKING := [
	WorldGrid.Terrain.RIVER, WorldGrid.Terrain.MOUNTAIN, WorldGrid.Terrain.ROCK,
]

static func _is_river(grid, x: int, y: int) -> bool:
	return grid.in_bounds(x, y) and grid.get_terrain(x, y) == WorldGrid.Terrain.RIVER

static func _is_land_anchor(grid, x: int, y: int) -> bool:
	# A valid anchor is in-bounds buildable land with no building on it.
	if not grid.in_bounds(x, y):
		return false
	if grid.get_terrain(x, y) in _BLOCKING:
		return false
	if grid.get_building_at(x, y) != 0:
		return false
	return true

# Plan a bridge for hovered cell (gx, gy). Returns:
#   { ok, cells:Array[Vector2i] (water→bridge), deck:Array[Vector2i] (anchor..anchor),
#     start:Vector2i, end:Vector2i, dir:Vector2i, reason:String }
static func plan(grid, gx: int, gy: int) -> Dictionary:
	var fail := func(reason: String, deck: Array) -> Dictionary:
		return {"ok": false, "cells": [], "deck": deck, "start": Vector2i(gx, gy),
			"end": Vector2i(gx, gy), "dir": Vector2i.ZERO, "reason": reason}

	if grid == null or not grid.in_bounds(gx, gy):
		return fail.call("Out of bounds", [])
	if not _is_land_anchor(grid, gx, gy):
		return fail.call("Anchor the bridge on open ground beside the water", [Vector2i(gx, gy)])

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var best: Dictionary = {}
	var red_deck: Array = [Vector2i(gx, gy)]   # best-effort span to show when nothing is valid

	for d in dirs:
		if not _is_river(grid, gx + d.x, gy + d.y):
			continue   # this side isn't water — not a crossing direction
		var water: Array = []
		var cx: int = gx + d.x
		var cy: int = gy + d.y
		var over_run := false
		while _is_river(grid, cx, cy):
			if water.size() >= MAX_WATER:
				over_run = true
				break
			if grid.get_building_at(cx, cy) != 0:
				break   # something already occupies the channel here
			water.append(Vector2i(cx, cy))
			cx += d.x
			cy += d.y
		# Track the longest attempted span for the red preview, even if it fails.
		if water.size() + 1 > red_deck.size():
			red_deck = [Vector2i(gx, gy)] + water + [Vector2i(cx, cy)]
		if over_run or water.is_empty():
			continue
		# The cell past the last water tile must be a legal far-bank anchor.
		if not _is_land_anchor(grid, cx, cy):
			continue
		if best.is_empty() or water.size() < int(best["len"]):
			best = {"len": water.size(), "water": water, "end": Vector2i(cx, cy), "dir": d}

	if best.is_empty():
		return fail.call("No clear crossing from here", red_deck)

	var water: Array = best["water"]
	var deck: Array = [Vector2i(gx, gy)] + water + [best["end"]]
	return {"ok": true, "cells": water, "deck": deck, "start": Vector2i(gx, gy),
		"end": best["end"], "dir": best["dir"], "reason": ""}

# AI helper: does a river block the straight route from (fx,fy) toward (tx,ty), and if so,
# where should a bridge be built? Returns a plan dict (ok=true) for the first river crossing
# encountered marching from the source toward the target, or {ok:false} if no river is in
# the way. The AI uses this to build bridges ONLY when a crossing is actually needed.
static func plan_towards(grid, fx: int, fy: int, tx: int, ty: int) -> Dictionary:
	if grid == null:
		return {"ok": false}
	# Step from source toward target; when we first hit water, anchor a bridge on the last
	# dry cell and span across in the dominant travel direction.
	var x: float = float(fx)
	var y: float = float(fy)
	var dx: int = signi(tx - fx)
	var dy: int = signi(ty - fy)
	if dx == 0 and dy == 0:
		return {"ok": false}
	var steps: int = abs(tx - fx) + abs(ty - fy)
	var stepx: float = float(tx - fx) / float(steps)
	var stepy: float = float(ty - fy) / float(steps)
	var last := Vector2i(fx, fy)
	for _i in range(steps):
		x += stepx
		y += stepy
		var cx: int = roundi(x)
		var cy: int = roundi(y)
		if not grid.in_bounds(cx, cy):
			break
		if grid.get_terrain(cx, cy) == WorldGrid.Terrain.RIVER:
			# Anchor on the last dry cell and plan the crossing from there.
			var p: Dictionary = plan(grid, last.x, last.y)
			if p.get("ok", false):
				return p
			return {"ok": false}
		if grid.get_terrain(cx, cy) not in _BLOCKING:
			last = Vector2i(cx, cy)
	return {"ok": false}
