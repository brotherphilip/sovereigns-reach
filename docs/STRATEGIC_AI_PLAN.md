# Strategic AI & Campaign System — Plan

Goal: give the **other cities/factions full AI parity with the player** — city
growth, economic management, building/development, army-raising, **campaigns**
(marching armies and capturing cities) and diplomacy. Everything the player can
do at the strategic scale, the enemies can do too, and vice-versa. Prove it all
works together with a headless launcher.

## 1. Where "the other cities" actually live

| Layer | Today | Gap |
|-------|-------|-----|
| **World map** (`world.world_map`): 55 cities, 5 factions, roads, deposits | Static data — a *city picker* only. No simulation. | This is where "other cities" exist. It needs a living strategic simulation. |
| **City view** (one 200×200 grid, the city the player is in) | Full economy + 2 abstract "raider" AI factions (`ai_factions[]`) that only assemble sieges. | Raiders don't grow real cities/build/research. Secondary. |

The headline gap — and the only place "the other cities" actually are — is the
**world map**. So the primary work is a **strategic campaign layer** that makes
all 5 factions (including the player's) living competitors. The player is *one*
kingdom among them; the player's strategic actions go through the **same code
path** as the AI's, guaranteeing symmetry.

Design constraints (MFA architecture, already in this codebase):
- All state = plain `Dictionary`/`Array`/`int`/`float`/`bool` (JSON/save-safe).
- Deterministic: every random draw uses an RNG seeded from `tick` + ids.
- Ticked on the **game-day boundary** inside `GameState.simulate_tick`, exactly
  like the existing `ai_factions` loop.
- View layer never mutates state; it reads + emits commands.

## 2. State model (stored under `world.world_map`)

### Per-city strategic fields (added by `ensure_initialized`)
- `owner_faction_id: int` — current owner (starts = `faction_id`; changes on capture).
- `garrison: int` — defenders stationed (seeded from `troop_count`).
- `development: int` (0–10) — **city growth/management/building** proxy. Higher dev →
  more production, higher garrison cap, higher visual `tier`.
- `gold_income`, `material_income` — derived from tier + development + nearby deposits.
- `unrest: float` — rises right after a capture (occupation), decays over time.

### Per-faction kingdom record (`world.world_map.kingdoms[]`)
- `id`, `name`, `color_hex`, `is_player: bool`, `is_alive: bool`
- `treasury: int` (gold), `resources: {wood,stone,iron,food}`
- `armies: []` — field armies: `{id, size, location_city_id, dest_city_id,
  path:[city_ids], progress_days, owner_faction_id}`
- `personality: {aggression, expansion, economy, defense}` — weights derived
  from the faction/archetype (Crimson=aggressive, Azure=economic, etc.)
- `relations: {other_faction_id: stance}` — stance ∈ {war, neutral, truce}
- `at_war_with: []`, `tribute_cooldown_until: int`

### Player ↔ kingdom mapping
The player's start city's `faction_id` is the player's kingdom; that kingdom gets
`is_player=true`. Player strategic commands operate on it.

## 3. New modules (`simulation/strategic/`)

1. **`CampaignMap.gd`** — pure helpers: `ensure_initialized(world, players)`,
   `cities(world)`, `city_by_id`, `neighbors(city)` (via `connected_to`),
   `frontier_targets(world, faction_id)` (enemy/neutral cities adjacent to owned
   ones), `bfs_path(world, from_id, to_id)`, `kingdoms(world)`, `kingdom_by_id`,
   `set_owner`, `faction_city_count`.

2. **`KingdomEconomy.gd`** — `tick_day(world, kingdom, tick)`:
   income from owned cities → treasury/resources; minus army upkeep;
   **development investment**: spend resources to raise the dev level of the
   kingdom's lowest-developed city (this is the build/grow/manage pillar — each
   dev level costs gold+wood+stone and raises that city's production & garrison
   cap and bumps its `tier`). Returns events (`city_developed`, etc).

3. **`CampaignSystem.gd`** — military layer:
   - `raise_army(world, kingdom, city_id, size)` — spend gold → new army at a city
     (also draws from that city's garrison cap).
   - `tick_armies(world, kingdom, players, tick)` — advance each army one step
     along its `path` per day; on arrival at a hostile/neutral city → `resolve_siege`.
   - `resolve_siege(...)` — battle: attacker `size` vs `garrison + city_defense`
     (defense from development/tier), seeded RNG; on win → `set_owner`, install
     occupation garrison, set `unrest`; on loss → attacker army destroyed/retreats.
   - Kingdom defeat → `is_alive=false` when it owns 0 cities.
   - Emits `army_raised`, `campaign_launched`, `city_captured`, `battle_resolved`,
     `kingdom_defeated`.

4. **`KingdomAI.gd`** — `decide(world, kingdom, players, tick)` per AI kingdom:
   - **Economy**: if treasury healthy, invest in development (via KingdomEconomy).
   - **Military**: maintain army strength ∝ aggression; `raise_army` at frontier
     cities when affordable.
   - **Campaigns**: pick the weakest `frontier_targets` (garrison+defense lowest),
     `bfs_path` to it, launch (set army dest/path). Expansion weight gates how
     aggressively it grabs neutral cities vs. attacking rivals.
   - **Diplomacy**: occasionally demand tribute from / make truce with a rival,
     weighted by personality + relative strength.

5. **`StrategicCommands` (in `GameState`)** — new `CommandType`s so the **player**
   does exactly what the AI does:
   - `DEVELOP_CITY {city_id}` → `KingdomEconomy.develop_city`
   - `RAISE_ARMY {city_id, size}` → `CampaignSystem.raise_army`
   - `LAUNCH_CAMPAIGN {army_id, target_city_id}` → set path/dest
   - `STRATEGIC_DIPLOMACY {faction_id, action}` → truce/tribute
   Routed through `GameState.apply_command` → CampaignSystem, same as AI calls.

## 4. Integration points

- **`CommandQueue.CommandType`**: append `DEVELOP_CITY, RAISE_ARMY,
  LAUNCH_CAMPAIGN, STRATEGIC_DIPLOMACY` (appended at the end → existing integer
  values unchanged → no save/test breakage).
- **`EventBus`**: add signals `city_captured, army_raised, campaign_launched,
  battle_resolved, kingdom_defeated, city_developed` (additive).
- **`GameState.simulate_tick`**: on the day boundary, after the existing
  `ai_factions` loop, call `CampaignSystem.tick_strategic(world, players, tick)`
  which runs, for every alive kingdom: KingdomEconomy.tick_day →
  (AI only) KingdomAI.decide → CampaignSystem.tick_armies → defeat checks.
- **Init**: call `CampaignMap.ensure_initialized` when `world_map` is generated
  (`WorldMapScene`) and lazily at the top of `tick_strategic` (so headless tests
  and loaded saves are covered).
- **Serialize**: strategic state lives inside `world.world_map`, which is already
  inside `world` → already serialized/saved. No new save plumbing needed.

## 5. Headless proof (`tests/TestStrategicAI.gd`, `extends SceneTree`)

Run: `godot --headless --script tests/TestStrategicAI.gd`

Generates a world map (fixed seed), `ensure_initialized`, snapshots, then
simulates ~500 game-days by calling the strategic tick directly. Asserts:

1. **Economy grows** — ≥1 AI kingdom's treasury and total resources rise over time.
2. **City growth / building** — total city `development` across the map increases
   (cities are being built up / managed).
3. **Armies raised** — total field-army count goes from ~0 to >0; armies move.
4. **Campaigns capture cities** — ≥1 city changes `owner_faction_id` (conquest).
5. **Kingdoms can fall** — at least one kingdom loses cities; defeat path reachable.
6. **Player parity** — drive the *player* kingdom via `DEVELOP_CITY`, `RAISE_ARMY`,
   `LAUNCH_CAMPAIGN` through the command pipeline and assert the player develops a
   city and captures a target (ownership flips to the player kingdom).
7. **Diplomacy** — a relation/tribute state change occurs.
8. **Determinism** — same seed run twice → identical end-state fingerprint.
9. **No regressions** — re-run `TestPhase1..14`; all still pass.

Success = every assertion passes headlessly + existing suites green.

## 6. Out of scope (intentional, keeps it provable)

- No literal 200×200 tile grid per AI city (cities are simulated abstractly at the
  strategic scale — the correct granularity for "other cities").
- No new rendering; the world-map view can later read the new fields (owner colors,
  garrisons, marching armies). This plan delivers + proves the **simulation**.
