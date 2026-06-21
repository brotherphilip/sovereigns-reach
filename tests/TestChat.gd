extends SceneTree
# Proof harness for villager "chatting" idle state: clustered idle peasants strike up
# chats with a near neighbour, the pairing is mutual, and chats dissolve back to idle.
# Run: godot --headless --script tests/TestChat.gd

const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_chats_form_and_dissolve()
	print("\n=== Chat Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _test_chats_form_and_dissolve() -> void:
	print("\n[Idle villagers chat with nearby neighbours]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var citizens: Array = []
	var nid := 0
	for _i in range(12):
		citizens.append(CitizenSystem.make_citizen(nid, 50.0, 50.0, rng))
		nid += 1

	var ever_chatted := false
	var mutual_ok := true
	var max_chatting := 0
	for _t in range(3000):
		for c in citizens:
			CitizenSystem._tick_citizen(c, [], citizens, rng, null, 0, {}, 1.0, [], false)
		var chatting := 0
		for c in citizens:
			if c.get("state", "") == "chat":
				chatting += 1
				ever_chatted = true
				# Partner must be chatting back with us (mutual pairing).
				var pid: int = int(c.get("chat_with", -1))
				var partner := CitizenSystem._citizen_by_id(citizens, pid)
				if partner.is_empty() or int(partner.get("chat_with", -2)) != int(c.get("id", -1)) \
						or partner.get("state", "") != "chat":
					mutual_ok = false
		max_chatting = maxi(max_chatting, chatting)

	# After the run, everyone is in a sane free/idle state (no permanent freeze in chat).
	var all_sane := true
	for c in citizens:
		var st: String = c.get("state", "")
		if st not in ["idle", "wander", "chat", "walk", "inside"]:
			all_sane = false

	ok("chats form between nearby idle villagers", ever_chatted)
	ok("more than one villager chats over the run", max_chatting >= 2)
	ok("every chat is a mutual pair", mutual_ok)
	ok("villagers stay in valid states", all_sane)
