extends SceneTree
# King-climb grader (iter153). Proves the NEXT BAR is reachable: a competent player,
# starting from ONE village, can climb Reeve → … → King within a campaign by fielding
# properly-sized hosts and developing holdings — using ONLY the public player command
# surface (no backend var manipulation). One seed per isolated process, so there is no
# in-process GameState leak between seeds (the multi-seed-runner hazard noted in iter141).
#
# Why a host > 40: MAX_ARMY_SIZE caps a single levy *batch* at 40, but raise_army MERGES
# repeated levies at the same city, so stacking builds a host big enough to crack defended
# cities. The earlier "stuck at Earl" finding was a grader that only ever fielded 40 (a
# harness-competence artifact, not a balance bug) — this test encodes competent play.
#
# Run one seed:   godot --headless --script tests/TestKingClimb.gd
# Run a seed set:  for s in 12345 4242 999; do SR_SEED=$s godot --headless --script tests/TestKingClimb.gd; done

const CM = preload("res://simulation/strategic/CampaignMap.gd")
const FR = preload("res://simulation/strategic/FeudalRank.gd")
const CMS = preload("res://simulation/strategic/CampaignSystem.gd")
const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const GOLD_PER: int = 5
const DEADLINE_DAYS: int = 200   # all 5 verified seeds reach King inside this (≤113 days, iter154)
const HOLD_DAYS: int = 100        # days to keep playing after King to prove the endgame is durable (iter156)

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: GameState autoload not found"); quit(1); return
	var env_seed: String = OS.get_environment("SR_SEED")
	var seed: int = int(env_seed) if env_seed != "" else 12345

	gs.world = {}; gs.players = []; gs.ai_factions = []
	gs.world["world_map"] = WorldMapData.generate(seed)
	gs.ensure_strategic_initialized()
	var pfid: int = CM.player_faction_id(gs.world)
	var home: int = CM.faction_city_ids(gs.world, pfid)[0]
	gs.world["player_seat_city_id"] = home
	var k: Dictionary = CM.kingdom_by_id(gs.world, pfid)

	var peak_title: int = 0
	var king_day: int = -1
	for day in range(1, DEADLINE_DAYS + 1):
		gs.advance_strategic_day()
		var idx: int = FR.title_index_for(FR.domain_score(gs.world, pfid, 0.0))
		if idx > peak_title:
			peak_title = idx
		if peak_title >= FR.king_index():
			king_day = day
			break
		_play_turn(gs, k, pfid, home)

	var pass_count: int = 0
	var fail_count: int = 0
	var reached: bool = peak_title >= FR.king_index()
	if reached: pass_count += 1; print("  PASS: seed %d reached King (day %d, holdings %d)" % [seed, king_day, CM.faction_city_ids(gs.world, pfid).size()])
	else: fail_count += 1; print("  FAIL: seed %d stuck at %s (score %d) after %d days" % [seed, FR.title_name(peak_title), FR.domain_score(gs.world, pfid, 0.0), DEADLINE_DAYS])

	# Post-King DURABILITY (iter156): keep playing HOLD_DAYS after coronation and confirm the
	# LIVE realm (not the never-demoting peak title) holds King-tier standing under continued AI
	# pressure — i.e. the endgame doesn't collapse. Verified ≥88 across seeds; assert ≥ Duke (62).
	if reached:
		var min_live: int = FR.domain_score(gs.world, pfid, 0.0)
		for _d in range(HOLD_DAYS):
			gs.advance_strategic_day()
			min_live = mini(min_live, FR.domain_score(gs.world, pfid, 0.0))
			_play_turn(gs, k, pfid, home)
		var duke: int = int(FR.TITLES[FR.king_index() - 1]["min_score"])
		if min_live >= duke: pass_count += 1; print("  PASS: seed %d held >= Duke for %d days post-King (min live score %d)" % [seed, HOLD_DAYS, min_live])
		else: fail_count += 1; print("  FAIL: seed %d realm collapsed post-King (min live score %d < Duke %d)" % [seed, min_live, duke])

	print("\n=== KingClimb (seed %d): %d passed, %d failed ===" % [seed, pass_count, fail_count])
	quit(0 if fail_count == 0 else 1)

# Competent player turn. King's score (88) is driven mostly by DEVELOPMENT, not raw
# holding count (≈14 holdings × several dev levels), so a player who only conquers and
# never builds churns at the border forever. So: develop whenever affordable (keeping a
# gold reserve for one host), and expand only while the realm is still small enough to be
# worth widening — past a defensible size, pour everything into development.
const KEEP_RESERVE: int = 250          # gold kept back for raising a defensive host
const EXPAND_UNTIL_HOLDINGS: int = 16  # beyond this, develop rather than over-extend

func _play_turn(gs, k: Dictionary, pfid: int, home: int) -> void:
	# DEVELOP (does not need the field army home) — the primary engine of title score.
	var low: int = gs.player_lowest_dev_city()
	if low >= 0 and gs.can_player_develop_city(low) and int(k.treasury) > KEEP_RESERVE:
		gs.player_develop_city(low)
	# EXPAND opportunistically while small; field a host sized to the weakest target.
	if CMS.total_army_size(k) == 0 and CM.faction_city_ids(gs.world, pfid).size() < EXPAND_UNTIL_HOLDINGS:
		var best: int = -1
		var bd: int = 1 << 30
		for t in CM.frontier_targets(gs.world, pfid):
			var tc: Dictionary = CM.city_by_id(gs.world, t)
			if CM.owner_of(tc) == pfid:
				continue
			var dd: int = CM.city_defense(tc)
			if dd < bd:
				bd = dd; best = t
		if best >= 0:
			var want: int = maxi(40, int(ceil(float(bd) * 1.7)))
			var host: int = mini(want, int(k.treasury) / GOLD_PER)
			if host >= int(ceil(float(bd) * 1.1)):
				while CMS.total_army_size(k) < host and int(k.treasury) >= GOLD_PER * 40:
					gs.player_raise_army(home, mini(40, host - CMS.total_army_size(k)))
				var aid: int = gs.player_army_at_city(home)
				if aid >= 0:
					gs.player_launch_campaign(aid, best)
