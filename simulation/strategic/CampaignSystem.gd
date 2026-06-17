extends RefCounted
# Strategic military layer: raise field armies, march them along the road network,
# assault enemy/neutral cities, and capture them. The shared primitives
# (raise_army / launch_campaign) are called by both the AI brain and the player's
# RAISE_ARMY / LAUNCH_CAMPAIGN commands, so campaigns are fully symmetric.
#
# Deterministic: every battle RNG is seeded from tick + army id + city id.
# Pure simulation — operates on world.world_map dicts; no Godot scene imports.

const CampaignMap   = preload("res://simulation/strategic/CampaignMap.gd")
const KingdomEconomy = preload("res://simulation/strategic/KingdomEconomy.gd")

const GOLD_PER_SOLDIER: int = 5
const MAX_ARMY_SIZE: int = 40

# Strategic march speed in map-pixels per game-day. The world map is 1600×900 with
# cities ≥120px apart, so a neighbouring hop is ~1 day and a long leg costs several —
# armies take *real time* to cross the map proportional to the actual distance.
const MARCH_SPEED_PX: float = 180.0

# How many game-days it takes to march the road leg between two adjacent cities,
# scaled by their geographic separation (minimum one day).
static func hop_days(world: Dictionary, from_id: int, to_id: int) -> int:
	var a: Dictionary = CampaignMap.city_by_id(world, from_id)
	var b: Dictionary = CampaignMap.city_by_id(world, to_id)
	if a.is_empty() or b.is_empty():
		return 1
	var pa := Vector2(a.get("pos_x", 0.0), a.get("pos_y", 0.0))
	var pb := Vector2(b.get("pos_x", 0.0), b.get("pos_y", 0.0))
	return maxi(1, int(ceil(pa.distance_to(pb) / MARCH_SPEED_PX)))

# (Re)initialise the per-hop travel clock for an army's CURRENT leg (path[0]).
static func _begin_hop(world: Dictionary, army: Dictionary) -> void:
	var path: Array = army.get("path", [])
	if path.is_empty():
		army["hop_total_days"] = 0
		army["hop_elapsed"] = 0
		army["march_frac"] = 0.0
		return
	army["hop_total_days"] = hop_days(world, army.get("location_city_id", -1), path[0])
	army["hop_elapsed"] = 0
	army["march_frac"] = 0.0

# Total game-days remaining until an army reaches the end of its current path,
# counting the partially-travelled current leg. Used for the player's ETA readout.
static func days_to_destination(world: Dictionary, army: Dictionary) -> int:
	var path: Array = army.get("path", [])
	if path.is_empty():
		return 0
	# Current leg: remaining days from where we are toward path[0].
	var total: int = army.get("hop_total_days", hop_days(world, army.get("location_city_id", -1), path[0]))
	var elapsed: int = army.get("hop_elapsed", 0)
	var days: int = maxi(0, total - elapsed)
	# Remaining legs, chained city-to-city.
	for i in range(path.size() - 1):
		days += hop_days(world, path[i], path[i + 1])
	return maxi(1, days)

# ── Raising armies ─────────────────────────────────────────────────────────────

static func can_raise_army(world: Dictionary, kingdom: Dictionary, city_id: int, size: int) -> bool:
	if size <= 0:
		return false
	var c: Dictionary = CampaignMap.city_by_id(world, city_id)
	if c.is_empty() or CampaignMap.owner_of(c) != kingdom.get("id", -1):
		return false
	return kingdom.get("treasury", 0) >= size * GOLD_PER_SOLDIER

# Raise (levy) a new field army at an owned city. Costs gold. If a friendly army
# is already stationed there it merges instead, to keep the army list compact.
# Returns the army id on success, or -1.
static func raise_army(world: Dictionary, kingdom: Dictionary, city_id: int, size: int) -> int:
	size = clampi(size, 1, MAX_ARMY_SIZE)
	if not can_raise_army(world, kingdom, city_id, size):
		return -1
	kingdom["treasury"] = kingdom.get("treasury", 0) - size * GOLD_PER_SOLDIER

	# Merge into an existing idle army at the same city.
	for a in kingdom.get("armies", []):
		if a is Dictionary and a.get("location_city_id", -1) == city_id and a.get("path", []).is_empty():
			a["size"] = a.get("size", 0) + size
			return a.get("id", -1)

	var aid: int = kingdom.get("next_army_id", kingdom.get("id", 0) * 100000 + 1)
	kingdom["next_army_id"] = aid + 1
	var army: Dictionary = {
		"id": aid,
		"owner_faction_id": kingdom.get("id", -1),
		"size": size,
		"location_city_id": city_id,
		"dest_city_id": -1,
		"path": [],
	}
	kingdom.get("armies", []).append(army)
	return aid

# ── Launching campaigns ────────────────────────────────────────────────────────

static func find_army(kingdom: Dictionary, army_id: int) -> Dictionary:
	for a in kingdom.get("armies", []):
		if a is Dictionary and a.get("id", -1) == army_id:
			return a
	return {}

# Order an army to march to (and assault, if hostile) a target city. Returns true
# if a valid road path exists.
static func launch_campaign(world: Dictionary, kingdom: Dictionary, army_id: int, target_city_id: int) -> bool:
	var army: Dictionary = find_army(kingdom, army_id)
	if army.is_empty():
		return false
	var from_id: int = army.get("location_city_id", -1)
	if from_id < 0 or target_city_id < 0 or from_id == target_city_id:
		return false
	var path: Array = CampaignMap.bfs_path(world, from_id, target_city_id)
	if path.is_empty():
		return false
	army["dest_city_id"] = target_city_id
	army["path"] = path
	_begin_hop(world, army)  # start the travel clock for the first leg
	return true

# ── Marching + battles (daily) ─────────────────────────────────────────────────

# Advance every army of this kingdom one hop along its path. Friendly hops just
# move; a hostile next-hop triggers an assault. Idle armies sitting on an owned
# city fold back into its garrison. Returns event strings.
static func tick_armies(world: Dictionary, kingdom: Dictionary, _players: Array, tick: int) -> Array:
	var events: Array = []
	var fid: int = kingdom.get("id", -1)
	var armies: Array = kingdom.get("armies", [])

	for army in armies:
		if not army is Dictionary or army.get("size", 0) <= 0:
			continue
		var path: Array = army.get("path", [])
		if path.is_empty():
			continue
		var next_id: int = path[0]
		var next_city: Dictionary = CampaignMap.city_by_id(world, next_id)
		if next_city.is_empty():
			army["path"] = []
			continue

		# Distance-scaled travel: each leg takes hop_total_days; the army only
		# *arrives* once it has marched the whole leg. Until then it creeps along
		# the road (march_frac drives the world-map animation).
		if not army.has("hop_total_days"):
			_begin_hop(world, army)  # legacy/in-flight army: start its clock
		army["hop_elapsed"] = army.get("hop_elapsed", 0) + 1
		var total_days: int = maxi(1, army.get("hop_total_days", 1))
		army["march_frac"] = clampf(float(army["hop_elapsed"]) / float(total_days), 0.0, 1.0)
		if army["hop_elapsed"] < total_days:
			continue  # still on the road this leg

		if CampaignMap.owner_of(next_city) == fid:
			# Friendly territory: march through, then start the next leg's clock.
			army["location_city_id"] = next_id
			path.remove_at(0)
			army["path"] = path
			_begin_hop(world, army)
		else:
			# Hostile city on the path: assault it now.
			var outcome: Dictionary = _resolve_assault(world, kingdom, army, next_city, tick)
			events.append(outcome)
			if outcome.get("captured", false):
				army["location_city_id"] = next_id
			# Win or lose, the campaign halts at the contested city.
			army["path"] = []
			army["dest_city_id"] = -1
			army["hop_total_days"] = 0
			army["hop_elapsed"] = 0
			army["march_frac"] = 0.0

	# Recycle idle armies sitting on an owned city into its garrison, and purge
	# destroyed armies. Keeps the army list bounded over long campaigns.
	var survivors: Array = []
	for army in armies:
		if not army is Dictionary or army.get("size", 0) <= 0:
			continue
		if army.get("path", []).is_empty():
			var here: Dictionary = CampaignMap.city_by_id(world, army.get("location_city_id", -1))
			if not here.is_empty() and CampaignMap.owner_of(here) == fid:
				var cap: int = CampaignMap.garrison_cap(here)
				here["garrison"] = mini(cap, here.get("garrison", 0) + army.get("size", 0))
				continue  # army absorbed into garrison
			# Idle on a non-owned (enemy/neutral) tile — a defeated host that halted at the
			# contested city. Order it to retreat to the nearest owned city instead of
			# stranding there forever (it would pay upkeep, never regroup, and a human would
			# have to micro it home). Symmetric for AI and player. If nothing is reachable,
			# the army simply remains (it has nowhere to fall back to).
			var retreat_to: int = _nearest_owned_city(world, fid, army.get("location_city_id", -1))
			if retreat_to >= 0:
				var path: Array = CampaignMap.bfs_path(world, army.get("location_city_id", -1), retreat_to)
				if not path.is_empty():
					army["path"] = path
					army["dest_city_id"] = retreat_to
					_begin_hop(world, army)
		survivors.append(army)
	kingdom["armies"] = survivors
	return events

# Nearest city (by road hops) owned by `fid`, searched outward from `from_id`. Returns the
# city id, or -1 if the faction owns no reachable city. Used to retreat stranded armies.
static func _nearest_owned_city(world: Dictionary, fid: int, from_id: int) -> int:
	var start: Dictionary = CampaignMap.city_by_id(world, from_id)
	if start.is_empty():
		return -1
	var visited: Dictionary = {from_id: true}
	var queue: Array = [from_id]
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var c: Dictionary = CampaignMap.city_by_id(world, cur)
		if cur != from_id and CampaignMap.owner_of(c) == fid:
			return cur
		for nid in CampaignMap.neighbor_ids(c):
			if not visited.has(nid):
				visited[nid] = true
				queue.append(nid)
	return -1

# Resolve one assault. Returns a result dict describing the outcome (and mutates
# state: ownership, garrisons, army size).
static func _resolve_assault(world: Dictionary, attacker: Dictionary, army: Dictionary, city: Dictionary, tick: int) -> Dictionary:
	var defender_fid: int = CampaignMap.owner_of(city)
	var atk: int = army.get("size", 0)
	var defense: int = CampaignMap.city_defense(city)

	var rng := RandomNumberGenerator.new()
	rng.seed = (tick * 1000003) ^ (army.get("id", 0) * 2654435761) ^ (city.get("id", 0) * 40503)

	var atk_roll: float = float(atk) * rng.randf_range(0.85, 1.25)
	var def_roll: float = float(defense) * rng.randf_range(0.85, 1.25)

	var result: Dictionary = {
		"event": "battle_resolved",
		"captured": false,
		"city_id": city.get("id", -1),
		"attacker_fid": attacker.get("id", -1),
		"defender_fid": defender_fid,
	}

	# The player's ACTIVELY-RULED seat can't fall to an abstract strategic assault — it
	# is defended through the tactical city view (its keep). The attack is turned back
	# here (the host bloodied), so you never lose the city you're personally holding to
	# an off-screen battle; only a tactical siege that fells the keep can take it.
	if city.get("id", -1) == int(world.get("player_seat_city_id", -1)):
		army["size"] = int(float(atk) * rng.randf_range(0.1, 0.4))
		result["repelled_seat"] = true
		return result

	if atk_roll > def_roll:
		# City falls. Attacker takes casualties proportional to the defence faced.
		var casualties: int = mini(atk - 1, int(float(defense) * rng.randf_range(0.4, 0.8)))
		var occupiers: int = maxi(1, atk - maxi(0, casualties))
		CampaignMap.set_owner(world, city.get("id", -1), attacker.get("id", -1))
		city["garrison"] = mini(CampaignMap.garrison_cap(city), occupiers)
		city["unrest"] = 0.6
		city["population"] = maxi(50, int(float(city.get("population", 100)) * 0.85))  # sacked
		army["size"] = 0  # the field army becomes the new garrison
		attacker["cities_captured"] = attacker.get("cities_captured", 0) + 1
		var dk: Dictionary = CampaignMap.kingdom_by_id(world, defender_fid)
		if not dk.is_empty():
			dk["cities_lost"] = dk.get("cities_lost", 0) + 1
		result["captured"] = true
		result["event"] = "city_captured"
	else:
		# Assault repelled. Defenders bleed; attacker retreats with heavy losses.
		var def_losses: int = int(float(atk) * rng.randf_range(0.3, 0.6))
		city["garrison"] = maxi(0, city.get("garrison", 0) - def_losses)
		army["size"] = int(float(atk) * rng.randf_range(0.1, 0.4))
	return result

# ── Telemetry helpers ──────────────────────────────────────────────────────────

static func total_army_size(kingdom: Dictionary) -> int:
	var s: int = 0
	for a in kingdom.get("armies", []):
		if a is Dictionary:
			s += a.get("size", 0)
	return s

static func armies_in_motion(kingdom: Dictionary) -> int:
	var n: int = 0
	for a in kingdom.get("armies", []):
		if a is Dictionary and not a.get("path", []).is_empty():
			n += 1
	return n
