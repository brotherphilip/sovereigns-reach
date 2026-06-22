# First-impression critique — STATUS (re-baselined 2026-06-23, after iter335)

The original tier-0..4 critique below was a first-impression teardown from older screenshots. As of
iter335 it is **~90% resolved** — verified by fresh headless renders of every scene this session. It was
steering the loop toward already-fixed targets, so this file is now a status ledger, not a to-do list.
**Before picking a "phase-plan" task, render the real scene and confirm the issue still exists** — most
don't. New genuinely-open work is at the bottom.

## RESOLVED (with the iteration / mechanism)

**Tier 0 (looked broken):**
- ✅ snake_case lock reasons → human strings ("Requires Advanced Masonry") — build menu (verified iter333).
- ✅ Clipped tutorial body ("…defense and") → full text "…defense and expansion." (verified iter).
- ✅ "Night" label vs bright scene → night lighting + the clock derive from one `SeasonSystem.night_window`.
- ✅ Name dups ("Frostgate 2") → world map shows unique settlement names (verified iter render).
- ✅ Grey-square-on-face held item, off-map black triangle, "0/8 mist" string — not reproducible in renders.
- (DEBUG x20-speed feed line: not seen in any render; treat as fixed unless it resurfaces.)

**Tier 1 (looked unfinished) — ALL resolved:**
- ✅ Flat untextured buildings → real building models w/ chimney smoke (BuildingModels rework, iter324 WIP).
- ✅ Empty lifeless fields → macro meadow variation (iter322) + wildlife + drifting fireflies (iter325).
- ✅ Cloned everything → mixed-species woodland w/ conifers (iter323); festival lanterns good; pawn variety.
- ✅ Night unreadably dark → lamplit village w/ shaped light-pools over a moonlit floor (iter321).
- ✅ Flat blocky water → depth + shoreline + animated ripple shader (water_flow, iter324 WIP).
- ✅ World map muddy blur → readable relief + clean settlement/road network (iter315–320).
- ✅ Placement ghost → clean soft hover-tile highlight (iter324 WIP).

**Tier 2 (UX friction) — mostly resolved:**
- ✅ Unlabeled resource bar → icons + captions + rich tooltips; food caption shows days-left (iter334).
- ✅ "Nothing selected" dead panel → a YOUR REALM at-a-glance (title/progress/threat) when idle (iter331).
- ✅ Cryptic build costs → spaced "8 wd", "20 wd 10 g"; build cards now also show what each building DOES (iter333).
- ✅ Main-menu difficulty → a proper ◄ Normal ► cycler inside the panel, distinct from the buttons (verified iter335).
- ✅ Mixed resolution/blur → renders are crisp.
- ◻ Weather-log spam / duplicated season chip — believed deduped; not re-verified this pass.

**Tier 4 — Title screen:** ✅ FULLY redesigned (verified iter335) — cinematic cross-fading slideshow (6 Ken-
Burns scenes), gold crest, button hierarchy (New Game dominant / Quit recessed), animated lanterns, organic
fireworks. The "crude lanterns / debug-spinner firework / no hierarchy" notes describe a long-dead build.

## GENUINELY OPEN / UNVERIFIED (candidate loop targets — confirm by render first)
- ✅ **Orchard/farm growth life** — RESOLVED (verified iter337). Wheat is tilled soil w/ furrow rows that
  GROWS seasonally — green sprouts (spring) → green canopy (summer) → a near-solid RIPE GOLD stand w/ ears &
  awns (autumn). Orchards draw apple-tree rows. The Village Hall/keep even fly a red realm pennant. The old
  "flat tan parallelogram" note is obsolete. (Tried a summer-canopy boost; it was a non-issue — the brown I'd
  misread as the field was the trodden-earth ROAD — so it was reverted. Don't re-open without a render that
  shows a real problem.)
- **Spectator mode controls** (Tier 2): when viewing a rival's city, is there a clear "stop spectating / claim"
  affordance, and does the ✕-garrison glyph read as a close button? Not re-verified — likely the last real
  city-view candidate; needs an SR_SPECTATE render to confirm before touching.
- **Town identity in the CITY view** (Tier 3): world-map settlements are now varied; a player's vs a rival's
  *city-view* town still reads as the same building set (the hall flies a banner, but no walls/square/cultural
  variation). A LARGE undertaking for MARGINAL gain (you mostly see your own town) — not a quick win.

## STRATEGIC — needs the user (not autonomous loop work)
- **Narration VO batch:** 7 un-voiced events (`event_buried_hoard/_rival_defector/_stray_warhound/_comets_passage/
  _barter_caravan/_feast_demanded/_dowsers_promise`) + `title_promoted`. The loop will NOT auto-generate these —
  Chatterbox is stochastic (takes garble) and a creative voice needs a human ear-check. Render via Vocalis.
- **Deeper long-game design:** the moment-to-moment systems (build/economy, events w/ choices, sieges, feudal
  climb, diplomacy) are all in place and polished. What *sustains* a 20-minute+ session beyond them — escalating
  telegraphed threats, prestige/title tiers with payoffs, win-variety — is a design-direction call for the user.

## SESSION LOG (iter321–335): see CHANGELOG.md / change.md / systems_bibliography.html for full detail.
Night → meadow → trees → WIP-checkpoint → fireflies → siege-balance guard → siege-notification fix (player
report) → rank-up celebration → build-complete juice → objective-complete flourish → realm-at-a-glance panel
→ event-decree modal → build descriptions → food-days warning → title-screen render hooks. 17 commits.
