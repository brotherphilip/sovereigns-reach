extends RefCounted
# Diplomacy resolution applied to the real GameState. Tribute demands come from
# AI factions (AshenBarony) via EventBus.ai_envoy_sent; the DiplomacyPanel calls
# these when the player Accepts (pays) or Refuses (consequences).

# Accept: pay the demanded resources and mark all pending demands fulfilled.
# gold is player.gold; food goods (ale, apples…) live in player.food; the rest
# (iron, wood, stone…) in player.resources.
static func accept(player: Dictionary, demands: Dictionary, faction = null) -> void:
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

# Refuse: the populace grows uneasy, the snubbed faction grows more hostile, and
# Ashen Barony (or any faction that tracks embargoes) imposes a trade embargo.
static func refuse(player: Dictionary, faction) -> void:
	player["popularity"] = maxf(0.0, player.get("popularity", 50.0) - 5.0)
	if faction is Dictionary:
		faction["threat_level"] = minf(100.0, faction.get("threat_level", 0.0) + 15.0)
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
