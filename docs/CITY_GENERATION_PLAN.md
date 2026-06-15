# City Generation — Scope

Goal: **every** world-map city is viewable as a real, living town (not a fresh
empty field), and each town **grows dynamically** as its strategic `development`
rises (driven by the campaign layer we just built). One coherent generator drives
both the player's seat and every rival/neutral city.

## 1. Where we are today

- Clicking a city → `setup_world(seed)` regenerates that city's terrain from
  `seed = 42 + city_id*7`, then `initialize_player(0,…)` gives a **fresh empty
  start** (you hand-build the Hall). The city's strategic state (owner,
  development, population, garrison) is ignored.
- Only one city is instantiated at a time, in `players[0]`. Switching cities
  re-inits from scratch. No spectator view, no per-city town persistence.
- Renderer reads `players[0].buildings` / `GameState.citizens`; the existing
  `CitizenSystem` already walks builders to raise `built=false` buildings via
  `build_progress` — we reuse that to animate growth.

## 2. Core idea: a town is a deterministic function of its strategic state

`CityGenerator.layout(city, grid, rng)` → an **ordered** list of building
placements `[{type, gx, gy}]`, where the order is stable and the town reveals the
first **K** buildings, with K scaling from the city's `development` (0–10).

Key property — **accretive growth**: the full build sequence for a town is fixed
by its seed; raising development only increases K, so new buildings *append*
rather than reshuffle. Growth then looks like a town gaining a market, then walls,
then a church… deterministically, with no heavy per-city storage (we already store
`development` in the strategic state).

Development → town profile (illustrative):
| dev | adds |
|----|------|
| 0–1 | village hall, 2–3 hovels, apple orchard, woodcutter |
| 2–3 | market, more hovels, wheat farm, stockpile |
| 4–5 | barracks, granary, church, stone quarry/iron mine, more houses |
| 6–7 | palisade ring + towers, blacksmith, fletcher, more farms |
| 8–10| stone walls, keep, cathedral, many houses — a capital |

Placement: spiral/ring outward from the town center on buildable tiles
(grass/valley), honoring footprints via the existing `PlacementValidator` rules;
defensive walls placed as a ring at the appropriate dev tiers.

## 3. Viewing any city

`WorldMapScene` city-click sets `selected_city_id` → `CityViewScene`, which
branches:

- **Playable** (your seat): the existing interactive sim — you build/manage; town
  persists in `players[0]` + save. (Onboarding "build your Hall" preserved.)
- **Spectator** (any other city): `CityViewScene` calls `CityGenerator.layout`
  for that city's current development and loads it into a read-only render slot.
  Build controls hidden; a banner shows "*City — Faction · Development N · ⚔ garrison*".
  Ambient villagers/builders bring it to life (reuse `CitizenSystem`); the
  garrison shows as a few stationed units.

This satisfies "all cities viewable" without a full multi-city economy.

## 4. Dynamic growth

- The campaign layer already raises `development` over game-days. On entry — and
  while spectating — the view compares the town's rendered building count to the
  count implied by current development; when development has risen, the **new**
  buildings are appended as `built=false` and the builder pawns construct them in
  real time. You literally watch the town grow.
- **Feedback loop (player's seat):** periodically map the player's built-up city
  (building count/value) back to its strategic `development`, so playing your city
  advances you on the world map and rivals you've out-built fall behind. Closes
  the loop between the two layers.

## 5. Persistence

- Player seat: `players[0]` + save (unchanged).
- All other cities: regenerated on demand from `(seed, development)` — only
  `development` is stored (already in strategic state). Conquest/sacking adjusts
  development (capture already lowers population; can drop a dev level), so a
  razed city visibly shrinks next time you look.

## 6. New / changed modules

- **`simulation/world/CityGenerator.gd`** (new, pure): `layout(city, grid, rng)`
  → ordered building list; `buildings_for_development(dev)` → target set; helper
  to diff old→new for growth. Headless-testable.
- **`CityViewScene.gd`**: playable-vs-spectator branch; populate buildings from
  the generator for spectator/owned-non-seat cities; banner UI; hide build input
  in spectator.
- **`GameState`**: a render/spectator slot (or transient player entry) the
  existing layers can read; `develop`-feedback from the player's seat; a
  `regenerate_city_view(city_id)` helper.
- **Strategic layer**: optional dev-drop on sacking (small tweak to capture).

## 7. Headless proof (`tests/TestCityGeneration.gd`)

- `layout` is deterministic (same seed+dev → identical placements).
- Building count rises monotonically with development; dev N+1 is a **superset**
  of dev N (accretive growth).
- All placements are on buildable terrain and non-overlapping (footprint-valid).
- Capitals/high-dev towns include walls + a keep; low-dev are hamlets.
- Growth diff: raising development yields only *appended* `built=false` buildings.
- Integration: entering a non-seat city populates a viewable town from its
  development; raising development then adds buildings.

## 8. Decisions to confirm (see question)

- **Viewing depth** for non-seat cities: spectator (recommended) vs fully
  playable everywhere (much larger — multi-city economy).
- **Player's own city**: keep hand-built-from-scratch (recommended) vs also
  auto-generate it from development.
