extends RefCounted
# Diplomacy resolution applied to the real GameState. Tribute demands come from
# AI factions (AshenBarony) via EventBus.ai_envoy_sent; the DiplomacyPanel calls
# these when the player Accepts (pays) or Refuses (consequences).

const AIFaction = preload("res://simulation/ai/AIFaction.gd")
const TICKS_PER_DAY: int = 240

# Accept: pay the demanded resources, mark demands fulfilled, and — crucially — BUY
# PEACE: a guaranteed no-siege window plus soothed grievance, so tribute actually
# keeps the wolves from the door for a while (the whole point of paying).
static func accept(player: Dictionary, demands: Dictionary, faction = null, tick: int = 0) -> void:
	for res in demands:
		var amount: int = demands[res]
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
