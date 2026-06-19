extends SceneTree
# Probe: run the STRATEGIC sim headless and dump one AI kingdom's stores + growth over
# time, to verify the user's report (AI gets food/iron "for free"; do they keep growing?).
# Run: godot --headless --script tools/ProbeAIEconomy.gd
const WorldMapData  = preload("res://simulation/world/WorldMapData.gd")
const CampaignMap   = preload("res://simulation/strategic/CampaignMap.gd")
const StrategicSim  = preload("res://simulation/strategic/StrategicSim.gd")
const KingdomEconomy = preload("res://simulation/strategic/KingdomEconomy.gd")

const TPD: int = 240

func _init() -> void:
	var world: Dictionary = {"world_map": WorldMapData.generate(4242)}
	CampaignMap.ensure_initialized(world, [])
	var fid: int = 0   # watch faction 0 (Crimson Throne, aggressive)
	print("day | cities | totaldev | gold | wood | stone | iron | food | army")
	for day in range(1, 201):
		StrategicSim.tick_day(world, [], day * TPD)
		if day % 20 == 0 or day == 1:
			var k: Dictionary = CampaignMap.kingdom_by_id(world, fid)
			if k.is_empty() or not k.get("is_alive", false):
				print("%4d | (faction %d dead)" % [day, fid]); continue
			var r: Dictionary = k.get("resources", {})
			var army: int = 0
			for a in k.get("armies", []):
				if a is Dictionary: army += int(a.get("size", 0))
			print("%4d | %6d | %8d | %4d | %4d | %5d | %4d | %4d | %4d" % [
				day, CampaignMap.faction_city_count(world, fid),
				KingdomEconomy.total_development(world, fid),
				int(k.get("treasury", 0)), int(r.get("wood", 0)), int(r.get("stone", 0)),
				int(r.get("iron", 0)), int(r.get("food", 0)), army])
	# Summary across all living kingdoms
	print("\n--- final, all kingdoms ---")
	for k in CampaignMap.kingdoms(world):
		if not (k is Dictionary): continue
		var alive: bool = k.get("is_alive", false)
		var kfid: int = k.get("id", -1)
		var r: Dictionary = k.get("resources", {})
		print("fac %d %-16s alive=%s cities=%d dev=%d food=%d iron=%d" % [
			kfid, k.get("name",""), str(alive),
			CampaignMap.faction_city_count(world, kfid),
			KingdomEconomy.total_development(world, kfid),
			int(r.get("food", 0)), int(r.get("iron", 0))])
	quit(0)
