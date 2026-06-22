extends SceneTree
# Headless autoplayer — plays a FULL Sovereign's Reach campaign through the same
# player-parity strategic API the world-map UI calls (develop / raise army / launch
# campaign / diplomacy), from a lone Reeve village all the way to King (the win).
# It narrates a new-player play-by-play and records the friction/issues it hits.
# Run: godot --headless --script tools/PlayBot.gd   (optional SEED=<int>)

const WorldMapData   = preload("res://simulation/world/WorldMapData.gd")
const CampaignMap    = preload("res://simulation/strategic/CampaignMap.gd")
const CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")
const KingdomEconomy = preload("res://simulation/strategic/KingdomEconomy.gd")
const StrategicSim   = preload("res://simulation/strategic/StrategicSim.gd")
const FeudalRank     = preload("res://simulation/strategic/FeudalRank.gd")

const TICKS_PER_DAY := 240
const MAX_DAYS := 8000
const GPS := 5   # CampaignSystem.GOLD_PER_SOLDIER

var gs
var pfid: int = -1
var log_lines: Array = []
var issues: Array = []

# --- bookkeeping for issue detection ---
var first_army_day: int = -1
var first_capture_day: int = -1
var max_treasury_seen: int = 0
var captures: int = 0
var losses: int = 0
var stuck_days: int = 0
var last_holdings: int = 1

func _init() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: GameState autoload missing"); quit(1); return
	var seed_v: int = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 909090
	_play(seed_v)
	quit(0)

func note(s: String) -> void:
	log_lines.append(s)
	print(s)

func issue(s: String) -> void:
	if not issues.has(s):
		issues.append(s)
		print("  ⚠ ISSUE: " + s)

func _pk() -> Dictionary:
	return CampaignMap.kingdom_by_id(gs.world, pfid)

func _treasury() -> int:
	return int(_pk().get("treasury", 0))

func _holdings() -> Array:
	return CampaignMap.faction_city_ids(gs.world, pfid)

# All enemy/independent cities I could beat with `size`, weakest first. Combat rolls each
# side ×[0.85,1.25]; require size ≥ defense×1.6 so a launched assault reliably wins.
func _targets_for(size: int) -> Array:
	var out: Array = []
	for c in CampaignMap.cities(gs.world):
		if CampaignMap.owner_of(c) == pfid:
			continue
		var d: int = CampaignMap.city_defense(c)
		if float(size) >= float(d) * 1.6:
			out.append({"id": int(c.get("id", -1)), "def": d, "indep": CampaignMap.owner_of(c) < 0})
	out.sort_custom(func(a, b): return a["def"] < b["def"])
	return out

func _play(seed_v: int) -> void:
	# --- Bootstrap the campaign exactly as the world-map entry does ---
	gs.world = {}
	gs.world["world_map"] = WorldMapData.generate(seed_v)
	gs.players = []
	CampaignMap.ensure_initialized(gs.world, gs.players)
	pfid = CampaignMap.player_faction_id(gs.world)
	var seat: int = -1
	var mine: Array = _holdings()
	if mine.is_empty():
		print("FATAL: player owns no city after init"); return
	seat = int(mine[0])
	gs.world["player_seat_city_id"] = seat
	gs.world["selected_city_id"] = seat

	var total_cities: int = CampaignMap.cities(gs.world).size()
	note("════════════════════════════════════════════════════════════")
	note("SOVEREIGN'S REACH — autoplay  (seed %d)" % seed_v)
	note("Start: title=%s, holdings=1/%d, treasury=%d gold" % [
		FeudalRank.title_name(FeudalRank.current_index(gs.world, gs.players)), total_cities, _treasury()])
	note("Win at: %s (domain score ≥ %d). Each held city = 1 + its development." % [
		FeudalRank.title_name(FeudalRank.king_index()), FeudalRank.TITLES[FeudalRank.king_index()]["min_score"]])
	note("────────────────────────────────────────────────────────────")

	if _treasury() < 16 * GPS:
		issue("New player can't afford even a small army (16 soldiers = %d gold) on day 0 with starting treasury %d — the first move requires waiting/saving, with no in-game hint of how long." % [16 * GPS, _treasury()])

	var won: bool = false
	for day in range(1, MAX_DAYS + 1):
		var tick: int = day * TICKS_PER_DAY
		StrategicSim.tick_day(gs.world, gs.players, tick)

		# Promotion check (mirrors what the world-map HUD does each day).
		var promoted: int = FeudalRank.check_promotion(gs.world, gs.players)
		if promoted >= 0:
			note("Day %d: ★ promoted to %s  (holdings=%d, score=%d)" % [
				day, FeudalRank.title_name(promoted), _holdings().size(),
				FeudalRank.domain_score(gs.world, pfid, float(_pk().get("prestige", 0.0)))])

		# Track gains/losses of territory.
		var hc: int = _holdings().size()
		if hc > last_holdings:
			captures += (hc - last_holdings)
			if first_capture_day < 0:
				first_capture_day = day
			note("Day %d: ⚔ captured territory — now hold %d cities (treasury %d)" % [day, hc, _treasury()])
			stuck_days = 0
		elif hc < last_holdings:
			losses += (last_holdings - hc)
			note("Day %d: ✖ lost %d city(ies) to a rival — now hold %d" % [day, last_holdings - hc, hc])
		last_holdings = hc

		max_treasury_seen = maxi(max_treasury_seen, _treasury())

		# Win?
		if FeudalRank.current_index(gs.world, gs.players) >= FeudalRank.king_index():
			won = true
			note("────────────────────────────────────────────────────────────")
			note("Day %d: 👑 CROWNED KING — game won. Holdings=%d/%d, score=%d." % [
				day, hc, total_cities, FeudalRank.domain_score(gs.world, pfid, float(_pk().get("prestige", 0.0)))])
			break

		_manage(day)

		# Periodic status + stall detection.
		if day % 100 == 0:
			note("Day %d: %s · %d cities · %d gold · armies=%d" % [
				day, FeudalRank.title_name(FeudalRank.current_index(gs.world, gs.players)),
				hc, _treasury(), _pk().get("armies", []).size()])
		stuck_days += 1
		if stuck_days >= 800:
			issue("Expansion stalled for 800 days with no new capture (held %d cities, treasury %d) — the campaign can soft-stall with no guidance on what to do next." % [hc, _treasury()])
			break

	_report(won)

# One day of player decisions, in priority order: launch ready armies, raise a fresh
# host when affordable, then invest surplus into development (which also raises score).
func _manage(day: int) -> void:
	var mine: Array = _holdings()
	# 1) Launch any idle army that can take a target.
	for cid in mine:
		var aid: int = gs.player_army_at_city(int(cid))
		if aid < 0:
			continue
		var size: int = gs.player_army_size(aid)
		var launched: bool = false
		for t in _targets_for(size):
			if gs.player_launch_campaign(aid, int(t["id"])):
				note("Day %d: marched %d soldiers from city %d on %s city %d (def %d)" % [
					day, size, int(cid), ("independent" if t["indep"] else "rival"), int(t["id"]), int(t["def"])])
				launched = true
				break
		if not launched and size > 0 and not _targets_for(9999).is_empty():
			# There ARE cities, but none are road-reachable from where this host stands.
			issue("A raised army was stranded — no road-reachable target it could assault (size %d). Road connectivity from holdings can leave a host with nowhere to go." % size)

	# 2) Raise a fresh host at the seat when affordable and not already over-committed.
	var armies_active: int = 0
	for a in _pk().get("armies", []):
		if a is Dictionary and int(a.get("size", 0)) > 0:
			armies_active += 1
	var treas: int = _treasury()
	if armies_active < 2 and treas >= 16 * GPS:
		var size: int = clampi(int(treas / GPS / 2), 16, 70)  # spend ~half the treasury
		if gs.can_player_raise_army(seat_city(), size):
			if gs.player_raise_army(seat_city(), size):
				if first_army_day < 0:
					first_army_day = day
					note("Day %d: levied my first host (%d soldiers, %d gold)" % [day, size, size * GPS])
				# Try to march it out immediately.
				var aid: int = gs.player_army_at_city(seat_city())
				if aid >= 0:
					for t in _targets_for(gs.player_army_size(aid)):
						if gs.player_launch_campaign(aid, int(t["id"])):
							break

	# 3) Invest surplus into development (raises domain score and city defense/income).
	if _treasury() > 220:
		var dc: int = gs.player_lowest_dev_city()
		if dc >= 0 and gs.can_player_develop_city(dc):
			gs.player_develop_city(dc)

func seat_city() -> int:
	# Prefer the seat; fall back to any held city (seat could, in theory, be lost).
	var seat: int = int(gs.world.get("player_seat_city_id", -1))
	var mine: Array = _holdings()
	if mine.has(seat):
		return seat
	return int(mine[0]) if not mine.is_empty() else -1

func _report(won: bool) -> void:
	note("\n══════════════════ PLAYTEST SUMMARY ══════════════════")
	note("Outcome: %s" % ("WON (King)" if won else "did NOT reach King within %d days" % MAX_DAYS))
	note("Holdings: %d / %d cities" % [_holdings().size(), CampaignMap.cities(gs.world).size()])
	note("Captures: %d   Cities lost to rivals: %d" % [captures, losses])
	note("First host raised: day %s   First capture: day %s" % [
		str(first_army_day) if first_army_day > 0 else "—",
		str(first_capture_day) if first_capture_day > 0 else "—"])
	note("Peak treasury: %d gold" % max_treasury_seen)
	if not won:
		issue("Could not reach King via the strategic layer within %d days — verify the title climb is actually completable by a player from a single village." % MAX_DAYS)
	note("\n────────────── ISSUES / FRICTION (%d) ──────────────" % issues.size())
	if issues.is_empty():
		note("  (none detected by the bot on this run)")
	for i in range(issues.size()):
		note("  %d. %s" % [i + 1, issues[i]])
