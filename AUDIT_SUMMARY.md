# Sovereign's Reach — Comprehensive Audit Summary

**Status:** All audit parts complete. Full test suite green (8 suites + new
TestPhase10; 0 failures) and the project boots headless without error.

## Completed Work

### Part 1: Click-Through UI Fix (`ec4924a`)
- `_input → _unhandled_input` for PlayerInputHandler / CameraController / Minimap
- Minimap unit fields, TerrainDecorationLayer wiring, minimap camera.

### Part 4: Dead Code Deletion (`395c109`)
- Removed orphaned MainController, placeholder Minimap.gd/.tscn.

### Test suite green baseline
Fixed every red/broken suite (the prior "clean audit" was masked: TestPhase7
never compiled, hiding three failures). Root causes fixed in code where the
implementation was wrong (MarketSystem autoload ref / S12, festival_decree
modifier, capital donation auto-upgrade eating the first donation); stale test
fixtures corrected elsewhere.

### Part 3: Simulation Gaps (S1–S16) — all done
| # | Fix |
|---|-----|
| S1 | Attack orders execute — chase, strike on cadence, retaliate, resolve to IDLE |
| S2 | Barracks training queue (ORDER_TRAINING) + training_rate_bonus wired |
| S3 | Armorer / tannery / crossbow_workshop buildings; pig farms yield leather |
| S4 | Population growth toward housing cap (hovel population_cap now consumed) |
| S5 | Desertion triggers at desertion-risk popularity |
| S6 | `keep` building registered (unique, fortified hall upgrade) |
| S7 | Captain (hero) uniqueness enforced on recruit |
| S8 | `three_shires` milestone now evaluated |
| S9 | Tribute responses routed through CommandQueue (DIPLOMACY_RESPONSE) |
| S10 | Dead `storage_capacity_bonus` removed (granary bonus already worked) |
| S11 | PlacementValidator enforces `unique` (UNIQUE_EXISTS) |
| S12 | MarketSystem no longer references GameState autoload at compile time |
| S13 | ShireMap seeded from world seed (was hardcoded 42) |
| S14 | Edict tier cap enforced via capital edict_tier_cap |
| S15 | Ashen Barony supply lines cut when a player's army outvalues theirs |
| S16 | SaveManager migrates old saves (v1→v2 backfill) instead of rejecting |

Also revived the other dead modifier (`cart_capacity_bonus` → trade income).

### Part 5: Consolidations
- Embargo checks unified through `DiplomacySystem.is_embargoed`
  (MerchantPrince + MarketSystem delegate to it).
- Remaining duplications (screen_to_grid variants, ShireMap.upgrade_capital vs
  CapitalSystem, coverage calcs) left as-is: they are tested legacy paths with
  divergent semantics where merging carries regression risk and no functional
  gain.

### Part 7: Project Configuration
- `config/features` corrected "Forward Plus" → "GL Compatibility".
- Added `icon.svg` and wired `config/icon`.
- `.gitignore` already excludes `__pycache__/`.

## Additional bugs found & fixed (beyond the original audit)
- Ordering a unit still in the training queue cancelled its training and
  deployed it instantly (queue skip) — now rejected.
- Ranged attackers took melee retaliation from out-of-reach targets — retaliation
  now requires the attacker to be within the target's reach (kiting works).
- AI unit ids were derived from `units.size()` and reused after the dead-unit
  purge — replaced with a monotonic per-faction `next_unit_id`.

## Test coverage
`tests/TestPhase10.gd` (new) covers S1–S16, the dead modifiers, and the three
extra bugs above (63 assertions), including a full serialize → JSON → deserialize
round-trip. Run any suite with:
```bash
godot --headless --script tests/TestPhase<N>.gd
```

## Known content gaps (not bugs — require assets/design, deferred)
- Audio is silent (no sound assets); UI theme uses Godot defaults.
- No export presets yet.
- A few duplicate-logic consolidations intentionally left (see Part 5).
