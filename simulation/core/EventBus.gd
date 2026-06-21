extends Node
# Autoload singleton. All game-wide signals are defined here.
# No logic lives here — this is a pure signal hub.
# Consumers connect to these signals; emitters call emit() on them.

# --- Command pipeline ---
signal command_issued(command: Dictionary)
signal command_processed(command: Dictionary, success: bool)

# --- Simulation clock ---
signal simulation_tick(tick: int)
signal game_speed_changed(multiplier: float)

# --- View layer ---
signal view_mode_changed(mode: String)   # "macro" | "micro"
signal view_rotated(rotation_index: int) # 0–3 clockwise 90° steps

# --- Economy ---
signal popularity_changed(player_id: int, old_value: float, new_value: float)
signal population_changed(player_id: int, old_value: int, new_value: int)
signal blessing_bestowed(player_id: int, faith_spent: float)
signal gold_changed(player_id: int, old_amount: int, new_amount: int)
signal prestige_changed(player_id: int, old_value: float, new_value: float)

# --- Buildings ---
signal building_placed(player_id: int, building_type: String, grid_x: int, grid_y: int, building_id: int)
signal building_placement_failed(player_id: int, building_type: String, grid_x: int, grid_y: int, reason: String)
signal building_demolished(player_id: int, building_id: int)
signal building_destroyed(player_id: int, building_id: int, cause: String)
signal building_worker_assigned(building_id: int, worker_count: int)

# --- Units ---
signal unit_spawned(unit_data: Dictionary)
signal unit_killed(unit_id: int, killer_id: int, cause: String)
# A ranged unit loosed a projectile (arrow/bolt/stone) — the view animates the flight.
signal projectile_fired(from_x: int, from_y: int, to_x: int, to_y: int, kind: String)

# --- AI ---
signal ai_siege_assembling(faction_id: int, target_player_id: int, eta_ticks: int)
signal ai_siege_struck(faction_id: int, target_player_id: int, defended: bool, damage: int)
signal ai_envoy_sent(faction_id: int, demand: Dictionary)
signal ai_faction_defeated(faction_id: int)

# --- Strategic / campaign layer (world-map kingdoms) ---
signal city_captured(city_id: int, old_faction_id: int, new_faction_id: int)
signal city_developed(faction_id: int, city_id: int, new_level: int)
signal army_raised(faction_id: int, city_id: int, size: int)
signal campaign_launched(faction_id: int, army_id: int, target_city_id: int)
signal battle_resolved(city_id: int, attacker_faction_id: int, defender_faction_id: int, captured: bool)
signal kingdom_defeated(faction_id: int)

# --- Weather ---
signal weather_changed(new_weather: String, duration_ticks: int)

# --- Seasons / calendar ---
# Fired on the game-day the season index changes (spring/summer/autumn/winter).
signal season_changed(season: int, season_name: String)

# --- Realm events ---
# A flavourful daily event befell the realm (see WorldEventSystem). Carries the full
# event dict: id, title, text, tone ("good"/"bad"/"neutral"), summary ("+50 food").
# Choice events carry a "choices" array and wait on the player's decision.
signal world_event(event_data: Dictionary)
# The outcome of a player's decision on a choice-event — a one-off notification line.
signal realm_notice(text: String, tone: String)
# A plague has just broken out in a realm (severity 0 → active). One-shot per outbreak; drives
# the herald VO + a toast so the player is alerted (it silently killed villagers + sank popularity).
signal plague_outbreak(player_id: int)
# Standing objective changed (player's current goal). index/total for "(3/6)" display.
signal objective_updated(index: int, total: int, text: String)
# The player has ruled to Day 100 — twenty unbroken minutes, the loop's goal. Fired once.
signal sovereign_reign_reached(day: int)
# The player's derived feudal title rose (Reeve → … → King). Reaching King is the win.
signal title_promoted(title_index: int, title_name: String)
# The player lost their last holding (the realm has fallen) — strategic defeat.
signal player_realm_lost()

# --- World ---
signal shire_ownership_changed(shire_id: int, old_owner: int, new_owner: int)
# A terrain tile was repainted at runtime (e.g. a path laid) — chunks repaint.
signal terrain_painted(x: int, y: int)

# --- Edicts ---
signal edict_activated(player_id: int, edict_id: String, duration_ticks: int)
signal edict_expired(player_id: int, edict_id: String)

# --- Milestones ---
signal milestone_earned(player_id: int, milestone_id: String, prestige_bonus: float)

# --- Persistence ---
signal save_requested()
signal save_completed(path: String)
signal load_requested(path: String)
signal load_completed(success: bool)
