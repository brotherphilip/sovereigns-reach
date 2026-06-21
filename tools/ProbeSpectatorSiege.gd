extends SceneTree
# DIAGNOSTIC: replicate TestSpectatorTroops' besieged-spectator setup and log the force state
# over the sim so we can see WHERE the live battle stalls (positions, orders, targets, min gap).
# Run: godot --headless --script tools/ProbeSpectatorSiege.gd

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const CampaignMap  = preload("res://simulation/strategic/CampaignMap.gd")

var _gs: Node = null
var _sc: Node = null

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	if _gs == null or _sc == null:
		print("FATAL: autoloads not found"); quit(1); return
	_run()
	quit(0)

func _living(arr: Array) -> int:
	var n := 0
	for u in arr:
		if u is Dictionary and u.get("is_alive", false): n += 1
	return n

func _besiegers() -> Array:
	var out := []
	for f in _gs.ai_factions:
		for u in f.get("units", []):
			out.append(u)
	return out

func _min_gap() -> float:
	var best := 1e9
	for b in _besiegers():
		if not b.get("is_alive", false): continue
		for d in _gs.players[0].get("units", []):
			if not d.get("is_alive", false): continue
			var dx: float = float(b.get("pos_x", 0) - d.get("pos_x", 0))
			var dy: float = float(b.get("pos_y", 0) - d.get("pos_y", 0))
			best = minf(best, sqrt(dx * dx + dy * dy))
	return best

func _orders() -> Dictionary:
	var counts := {}
	for b in _besiegers():
		if not b.get("is_alive", false): continue
		var o := String(b.get("order", "?"))
		counts[o] = counts.get(o, 0) + 1
	return counts

func _run() -> void:
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Watcher", 50, 50)
	_gs.world["world_map"] = WorldMapData.generate(12345)
	_gs.ensure_strategic_initialized()
	var cid: int = -1
	for c in _gs.world.get("world_map", {}).get("cities", []):
		if c is Dictionary: cid = int(c.get("id", -1)); break
	var city: Dictionary = CampaignMap.city_by_id(_gs.world, cid)
	city["garrison"] = 8
	_gs.enter_spectator_city(cid, 100, 100, 12345)
	var owner: int = CampaignMap.owner_of(city)
	for k in CampaignMap.kingdoms(_gs.world):
		if k is Dictionary and int(k.get("id", -1)) != owner:
			k["armies"] = k.get("armies", [])
			k["armies"].append({"id": 1, "size": 40, "dest_city_id": cid, "location_city_id": -1})
			break
	_gs.enter_spectator_city(cid, 100, 100, 12345)

	print("spectator_mode=%s  ai_factions=%d  players_alive=%s  player0_is_alive=%s" % [
		str(_gs.spectator_mode), _gs.ai_factions.size(),
		str(not _gs.players.is_empty()), str(_gs.players[0].get("is_alive", "MISSING"))])
	var bes := _besiegers()
	var defs: Array = _gs.players[0].get("units", [])
	print("besiegers=%d (alive %d)  defenders=%d (alive %d)" % [bes.size(), _living(bes), defs.size(), _living(defs)])
	if bes.size() > 0:
		print("  sample besieger: pos=(%d,%d) attack=%d range=%d order=%s stance=%s" % [
			bes[0].get("pos_x",-9), bes[0].get("pos_y",-9), bes[0].get("attack",-9),
			bes[0].get("range",-9), str(bes[0].get("order","?")), str(bes[0].get("stance","?"))])
	if defs.size() > 0:
		print("  sample defender: pos=(%d,%d) hp=%d defense=%d is_alive=%s" % [
			defs[0].get("pos_x",-9), defs[0].get("pos_y",-9), defs[0].get("hp",-9),
			defs[0].get("defense",-9), str(defs[0].get("is_alive","?"))])
	print("  keep=(%s,%s)  initial min_gap=%.1f" % [
		str(_gs.players[0].get("keep_x","?")), str(_gs.players[0].get("keep_y","?")), _min_gap()])

	print("\n--- ticking 20 game-days ---")
	for tk in range(1, 20 * 240 + 1):
		_sc.current_tick = tk
		_gs.simulate_tick(tk)
		if tk % 240 == 0:
			print("day %2d: besiegers_alive=%d defenders_alive=%d min_gap=%.1f orders=%s" % [
				tk / 240, _living(_besiegers()), _living(_gs.players[0].get("units", [])),
				_min_gap(), str(_orders())])
