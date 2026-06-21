extends RefCounted
# Diplomacy resolution applied to the real GameState. Tribute demands come from
# AI factions (AshenBarony) via EventBus.ai_envoy_sent; the DiplomacyPanel calls
# these when the player Accepts (pays) or Refuses (consequences).

const AIFaction = preload("res://simulation/ai/AIFaction.gd")
const TICKS_PER_DAY: int = 240

# The tribute this faction still owes the player as a {resource: amount} map plus the earliest
# live deadline — counting only UNFULFILLED demands whose deadline has NOT passed. Used to
# RE-PRESENT a demand that arrived while the player was away from the seat (the envoy signal is a
# one-shot and the panel lives only in the city HUD), without resurrecting expired/answered ones.
# Returns {"demands": {...}, "deadline_tick": int}; demands is empty when nothing is owed.
static func owed_tribute(faction: Dictionary, player_id: int, now_tick: int) -> Dictionary:
	var demands_map: Dictionary = {}
	var deadline: int = 0
	for d in AIFaction.get_pending_demands(faction, player_id):
		if int(d.get("deadline_tick", 0)) < now_tick:
			continue   # already past its deadline — will be purged; don't resurrect it
		demands_map[d.get("resource", "")] = d.get("amount", 0)
		if deadline == 0:
			deadline = int(d.get("deadline_tick", 0))
	return {"demands": demands_map, "deadline_tick": deadline}

# How much of `res` the player holds (gold, a food, or a raw resource); 0 if untracked.
static func _player_stock(player: Dictionary, res) -> int:
	if res == "gold":
		return int(player.get("gold", 0))
	var food: Dictionary = player.get("food", {})
	if food.has(res):
		return int(food[res])
	var resources: Dictionary = player.get("resources", {})
	if resources.has(res):
		return int(resources[res])
	return 0

# True only if the player can pay EVERY demanded resource in full. Accepting a tribute
# you cannot afford must be impossible: paying part of a demand (or nothing) yet still
# buying peace was an exploit (free/cheap peace) and silently drained partial stock.
# The panel gates its Accept option on this; accept() re-checks it authoritatively.
static func can_afford(player: Dictionary, demands: Dictionary) -> bool:
	for res in demands:
		if _player_stock(player, res) < int(demands[res]):
			return false
	return true

# Accept: pay the demanded resources, mark demands fulfilled, and — crucially — BUY
# PEACE: a guaranteed no-siege window plus soothed grievance, so tribute actually
# keeps the wolves from the door for a while (the whole point of paying).
# Returns true only if the FULL tribute was paid; an unaffordable accept is a no-op
# (no resources spent, no peace, no grievance relief) so callers can react.
static func accept(player: Dictionary, demands: Dictionary, faction = null, tick: int = 0) -> bool:
	if not can_afford(player, demands):
		return false
	for res in demands:
		var amount: int = int(demands[res])
		if res == "gold":
			player["gold"] = maxi(0, int(player.get("gold", 0)) - amount)
		elif player.get("food", {}).has(res):
			player["food"][res] = maxi(0, player["food"][res] - amount)
		elif player.get("resources", {}).has(res):
			player["resources"][res] = maxi(0, player["resources"][res] - amount)
	if faction is Dictionary:
		var pid: int = player.get("id", 0)
		for d in faction.get("tribute_demands", []):
			if d is Dictionary and d.get("player_id", -1) == pid and not d.get("fulfilled", false):
				d["fulfilled"] = true
		if tick > 0:
			faction["tribute_peace_until"] = tick + AIFaction.TRIBUTE_PEACE_DAYS * TICKS_PER_DAY
		faction["grievance"] = maxf(0.0, faction.get("grievance", 0.0) - AIFaction.GRIEVANCE_ON_ACCEPT)
	return true

# Refuse: the populace grows uneasy, and the snubbed faction nurses a PERSISTENT
# grievance (escalating its threat toward a siege) plus a trade embargo.
static func refuse(player: Dictionary, faction) -> void:
	player["popularity"] = maxf(0.0, player.get("popularity", 50.0) - 5.0)
	if faction is Dictionary:
		faction["grievance"] = faction.get("grievance", 0.0) + AIFaction.GRIEVANCE_ON_REFUSE
		# Impose embargo: block the player from this faction's trade for future interactions.
		var pid: int = player.get("id", 0)
		var embargoed: Array = faction.get("embargoed_players", [])
		if pid not in embargoed:
			embargoed.append(pid)
		faction["embargoed_players"] = embargoed
		# Mark all pending demands for this player as fulfilled=true so the cooldown resets
		# and the next demand will arrive sooner at a higher scale.
		for d in faction.get("tribute_demands", []):
			if d is Dictionary and d.get("player_id", -1) == pid and not d.get("fulfilled", false):
				d["fulfilled"] = true

# Returns true if the player is embargoed by this faction (trade penalty applies).
static func is_embargoed(faction: Dictionary, player_id: int) -> bool:
	return player_id in faction.get("embargoed_players", [])
