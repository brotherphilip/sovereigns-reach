extends RefCounted
# Diplomacy resolution applied to the real GameState. Tribute demands come from
# AI factions (AshenBarony) via EventBus.ai_envoy_sent; the DiplomacyPanel calls
# these when the player Accepts (pays) or Refuses (consequences).

# Accept: pay the demanded resources. ale lives in player.food, iron in player.resources.
static func accept(player: Dictionary, demands: Dictionary) -> void:
	for res in demands:
		var amount: int = demands[res]
		if player.get("food", {}).has(res):
			player["food"][res] = maxi(0, player["food"][res] - amount)
		elif player.get("resources", {}).has(res):
			player["resources"][res] = maxi(0, player["resources"][res] - amount)

# Refuse: the populace grows uneasy and the snubbed faction grows more hostile.
static func refuse(player: Dictionary, faction) -> void:
	player["popularity"] = maxf(0.0, player.get("popularity", 50.0) - 5.0)
	if faction is Dictionary:
		faction["threat_level"] = minf(100.0, faction.get("threat_level", 0.0) + 15.0)
