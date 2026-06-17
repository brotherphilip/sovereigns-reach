extends SceneTree
# Proof harness for the "start as a village, work your way up" redesign.
# Run: godot --headless --script tests/TestFeudalRank.gd
#
# Covers: derived feudal title thresholds + non-demotion, the player starting as ONE
# small independent village, capture adding holdings (and promoting the title), the
# King win threshold, and the 0-holdings loss condition.

const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const CampaignMap  = preload("res://simulation/strategic/CampaignMap.gd")
const FeudalRank   = preload("res://simulation/strategic/FeudalRank.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_thresholds()
	_test_start_single_village()
	_test_capture_and_promotion()
	_test_king_and_loss()
	print("\n=== FeudalRank Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		print("  FAIL: ", label)

# ── Title thresholds + non-demotion ─────────────────────────────────────────────
func _test_thresholds() -> void:
	print("\n[A] Title thresholds")
	ok("score 0 → Reeve (index 0)", FeudalRank.title_index_for(0) == 0)
	ok("score 5 → still Reeve", FeudalRank.title_index_for(5) == 0)
	ok("score 6 → Bailiff (index 1)", FeudalRank.title_index_for(6) == 1)
	ok("score 88 → King (top)", FeudalRank.title_index_for(88) == FeudalRank.king_index())
	ok("huge score → still King (capped)", FeudalRank.title_index_for(100000) == FeudalRank.king_index())
	ok("title name for King", FeudalRank.title_name(FeudalRank.king_index()) == "King")

	# Non-demotion: once promoted, losing standing does not lower the stored title.
	var world := {"player_title_index": 3}
	# Build a tiny world where the player holds nothing (score 0 → would be Reeve).
	world["world_map"] = {"cities": [], "kingdoms": [{"id": CampaignMap.PLAYER_FACTION_ID, "is_player": true}],
		"player_faction_id": CampaignMap.PLAYER_FACTION_ID}
	var promo := FeudalRank.check_promotion(world, [])
	ok("no promotion when standing fell", promo == -1)
	ok("title never demotes (stays Baron index 3)", int(world.get("player_title_index", 0)) == 3)

# ── Player starts as ONE small independent village ──────────────────────────────
func _test_start_single_village() -> void:
	print("\n[B] Single-village start")
	var world := {}
	world["world_map"] = WorldMapData.generate(42)
	CampaignMap.ensure_initialized(world, [])
	var pfid: int = CampaignMap.player_faction_id(world)
	ok("player faction is the dedicated PLAYER faction", pfid == CampaignMap.PLAYER_FACTION_ID)
	ok("player holds exactly ONE village at start", CampaignMap.faction_city_count(world, pfid) == 1)

	# That village is the marked player-start, small (dev 0), owned by the player.
	var held: Array = CampaignMap.faction_city_ids(world, pfid)
	var seat: Dictionary = CampaignMap.city_by_id(world, held[0]) if held.size() > 0 else {}
	ok("the held village is the player-start", not seat.is_empty() and seat.get("is_player_start", false))
	ok("the start village is small (development 0)", int(seat.get("development", 9)) == 0)
	ok("player title at start is Reeve", FeudalRank.title_name(FeudalRank.current_index(world, [])) == "Reeve")

	# There is a sea of independents and a few great houses.
	var independents := 0
	var house_owned := 0
	for c in CampaignMap.cities(world):
		var o: int = CampaignMap.owner_of(c)
		if o == CampaignMap.INDEPENDENT_FACTION_ID: independents += 1
		elif o >= 0: house_owned += 1
	ok("many independent villages exist", independents >= 10)
	ok("great houses hold some cities", house_owned >= 4)

# ── Capture adds a holding and can promote the title ────────────────────────────
func _test_capture_and_promotion() -> void:
	print("\n[C] Capture → holdings + promotion")
	var world := {}
	world["world_map"] = WorldMapData.generate(42)
	CampaignMap.ensure_initialized(world, [])
	var pfid: int = CampaignMap.player_faction_id(world)
	FeudalRank.check_promotion(world, [])  # seed player_title_index from the 1-village start

	var before: int = CampaignMap.faction_city_count(world, pfid)
	# Capture several independent villages (as a player campaign would) and develop them.
	var taken := 0
	for c in CampaignMap.cities(world):
		if taken >= 12: break
		if CampaignMap.owner_of(c) == CampaignMap.INDEPENDENT_FACTION_ID:
			CampaignMap.set_owner(world, c.get("id", -1), pfid)
			c["development"] = 4
			taken += 1
	ok("capturing flips ownership to the player", CampaignMap.faction_city_count(world, pfid) == before + taken)
	var promo: int = FeudalRank.check_promotion(world, [])
	ok("expanding promotes the player's title", promo > 0)

# ── King win threshold + 0-holdings loss ────────────────────────────────────────
func _test_king_and_loss() -> void:
	print("\n[D] King win + realm-lost")
	var world := {}
	world["world_map"] = WorldMapData.generate(42)
	CampaignMap.ensure_initialized(world, [])
	var pfid: int = CampaignMap.player_faction_id(world)
	# Hand the player a large, developed domain → should reach King.
	for c in CampaignMap.cities(world):
		CampaignMap.set_owner(world, c.get("id", -1), pfid)
		c["development"] = 6
	ok("a dominant domain reaches the King title",
		FeudalRank.current_index(world, []) == FeudalRank.king_index())

	# 0-holdings loss: strip every holding from the player.
	for c in CampaignMap.cities(world):
		CampaignMap.set_owner(world, c.get("id", -1), CampaignMap.INDEPENDENT_FACTION_ID)
	ok("player driven to zero holdings (loss condition)",
		CampaignMap.faction_city_count(world, pfid) == 0)
