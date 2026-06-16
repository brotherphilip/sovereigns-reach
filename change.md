# change.md — Sovereign's Reach playtest loop

**Loop goal:** a real human can sit down, start a new game, and *play for 20 uninterrupted
minutes in a single life* — having fun, understanding what's happening, and never hitting a
wall that ends or stalls the run before then.

**Time math:** 1 game-day = 240 ticks = **12 real seconds** at NORMAL speed.
→ **20 real minutes = 100 game-days survived in one life.**

**Loss conditions (what ends a life):**
1. Village Hall / Keep destroyed (siege).
2. Popularity < 10 (revolt).
3. (Soft) Starvation → health collapse → popularity collapse → revolt.

**Method:** launch the *real* game into `CityViewScene` on an isolated Xvfb display (`:99`),
drive it with actual mouse/keyboard via `xdotool`, screenshot with `import`, read the pixels.
Pause the sim (speed 0) while reading/analysing so real-time doesn't bleed away during study.

Harness quick-ref:
```
Xvfb via: xvfb-run -n 99 -s "-screen 0 1280x720x24 -ac" env LIBGL_ALWAYS_SOFTWARE=1 \
  godot --rendering-driver opengl3 --resolution 1280x720 res://view/cityview/CityViewScene.tscn
input:  DISPLAY=:99 xdotool mousemove X Y click 1   (UI laid out in 1920x1080 → screen = UI*0.667)
shot:   DISPLAY=:99 import -window root /tmp/shot.png
```

---

## Iteration 28 — 2026-06-16  (BUG from a live observation: AI towns couldn't finish new buildings)

### Source
A direct human observation while spectating an AI city: it **placed 2 churches that never got built** —
"the builders either did not build it, or ran out of supplies… no stockpile? no woodcutters? both?"

### Answer to the question + root cause — [BUG] labour starvation, not supplies
AI construction needs **no materials at all** — `build_progress += BUILD_RATE` is pure builder labour
(CitizenSystem); stockpiles/woodcutters are irrelevant to *raising* a building. The real cause:
**the AI town had no free villagers to act as builders.** `GameState._auto_manage_ai_town` (runs daily
while you watch a town) staffed **every** built job to its `max_workers`, consuming the entire
workforce. Builders are only ever drawn from **IDLE/WANDER** villagers (job-workers in `STATE_WORK`
are never pulled off) — so once every job was filled, a freshly-grown building (the churches) got
**zero builders and stalled forever**. The bigger/busier the town, the more reliably new construction
froze.

### Change made
- **`_auto_manage_ai_town`**: when any building is under construction, **reserve a builder pool**
  before staffing jobs — `~2 villagers per unfinished site`, capped at half the workforce. Jobs are then
  funded from the remaining budget, leaving the reserve idle so CitizenSystem turns them into builders.
  Once construction finishes, the reserve returns to jobs naturally next day.

### Verified
- **Probe** (real GameState + CitizenSystem): an AI town with 8 woodcutters (16 job slots > 14
  villagers) + 2 unbuilt churches. Before: all 14 → jobs, 0 builders, churches stuck at 0. After:
  **10 → jobs, 4 reserved as builders → both churches build to 100/100 (built=true).**
- **Regression test** (TestCityGeneration, +3 → 25/0): with slots deliberately exceeding villagers and
  construction pending, the town now holds back ≥1 builder (`job_workers < workforce`).
- Full suite green (24/24 suites). Live boot clean.

### Post-mortem
- **Failure point:** AI towns visibly stuck with permanent under-construction buildings — breaks the
  "the world feels alive" illusion when spectating, and would stall an AI faction's growth.
- **Why missed:** headless tests staffed/built in isolation; only *watching a populous AI town grow*
  surfaced the workforce-vs-construction contention. Exactly the kind of bug live observation catches.

### Backlog / next
- The same labour-contention could in principle affect the **player** if they manually staff every job
  with no idle villagers — worth a future check / a "need builders" hint.
- Strategic/world-map actions as the human — largest unexercised area.

## Iteration 27 — 2026-06-16  (make the defended-siege mechanic legible — the warning adapts)

### Heuristic focus
The directive's **UX/feedback** axis: iter 26 made siege morale depend on readiness, but the relief was
**invisible** — a player who walled up had no way to *know* it helped. A mechanic the player can't
perceive isn't engaging. So this round surfaces it where attention already is: the siege telegraph.

### Change made
- **`GameState.is_siege_ready(player)`** promoted from private (`_is_siege_ready`) to a **public query**
  (the view needs it; tests + the day-boundary call updated to match).
- **Adaptive siege telegraph** (`_on_ai_siege_assembling`, both `CityViewScene` and `GameBootstrap`):
  the iter-23 warning now reads the realm's actual readiness and changes its tone + advice:
  - **Unready** (orange): "⚠ <Kingdom> is marshalling a siege … ~N days. **Raise walls, towers and a
    garrison before it lands!**" (the call to action)
  - **Ready** (gold): "⚠ <Kingdom> is marshalling a siege … ~N days. **Your walls and garrison steady
    the people's nerve.**" (confirms the iter-26 morale relief is in effect)
  So the same alert that warns you also *teaches* the mechanic and rewards preparation in words.

### Verified
- **Probe** (real `is_siege_ready`, mirroring the handler) prints both end-to-end:
  - `… Raise walls, towers and a garrison before it lands!` (no defences)
  - `… Your walls and garrison steady the people's nerve.` (walls + tower + gatehouse)
- Headless: full suite green (24/24); the renamed `is_siege_ready` test cases still pass (TestPhase6).
- **Live (Xvfb)**: clean boot, no script/parse errors — both refactored handlers wire up.

### Post-mortem
- **Failure point:** none.
- **Fun/UX:** closes the loop opened in iter 26 — the player now *sees* that readying defences calmed
  the realm, so the reward is felt, not just simulated. The siege beat reads as a clear
  prepare-and-be-rewarded arc.

### Backlog / next
- Optional: a persistent HUD "defence readiness" pip so it's legible even outside a siege alert.
- Strategic/world-map actions as the human — largest unexercised area; a future deep-dive.
- Building-specific events / multi-step decisions; a fresh-eyes onboarding pass.

## Iteration 26 — 2026-06-16  (defense-dependent siege morale — preparation now pays off)

### Heuristic focus
The directive's **Fun/engagement** axis ("challenges fair but demanding", satisfying reward loops):
build on iter 25 by making the siege morale penalty **depend on whether the player readied defences**.
Before, the hit was a flat constant regardless of preparation — so the iter-9 "Ready your defences"
objective had no morale payoff, only HP. Now preparation visibly steadies the realm.

### Change made
- **PopularityEngine**: new event `active_siege_defended` = **−3** (vs the unready `active_siege` = −8).
- **GameState**: when a faction is besieging the player, the day-boundary now picks the event by
  `_is_siege_ready(player)` — true when the realm has **≥3 "defence points"** = built DEFENSE-category
  structures (palisade/stone wall/gatehouse/towers) + living garrison units (counted together, so a
  short wall *or* a few soldiers qualifies). New `SIEGE_READY_THRESHOLD = 3`.
- Rationale: an unready realm panics under a looming siege (−0.4/day smoothed); a prepared one trusts
  its walls (−0.15/day) and rides the war out near-steadily.

### Verified — A/B via `tools/ProbePopularity.gd` (new `SR_PROBE_DEFENDED=1` variant)
Same 100-day managed run, with vs without walls+tower:
| day | undefended (−8) | defended (−3) |
|----|----|----|
| 30 | 58.8 | 58.8 |
| 60 | 50.8 | 58.3 |
| 85 | 38.8 | **52.6** |
| min/final* | 28.1 | **45.6** |
*(the day-90+ dip is the probe's known food artifact, not the real game.)

A prepared realm barely dips through the entire war; an unready one still feels real morale pressure.
- Headless: full suite green; TestPhase2 → 94 (defended siege is negative *and* lighter than undefended);
  TestPhase6 → 87 (`_is_siege_ready`: walls/tower/gatehouse ✓, a 3-soldier garrison ✓, a *fallen*
  garrison ✗, bare hall ✗). Live boot clean.

### Post-mortem
- **Failure point:** none — survival never at risk.
- **Fun:** this is the satisfying half of iter 25. War still threatens the careless ruler, but now
  *preparation is rewarded* — building walls and mustering a garrison keeps your people confident,
  turning "Ready your defences" from a chore into a real strategic payoff. A genuine reward loop.

### Backlog / next
- Surface the why on-screen: a one-time "Your walls steady the people" notice when a siege looms and
  the realm is defended (so the player *learns* the mechanic), and/or a HUD readiness indicator.
- Strategic/world-map actions as the human — largest unexercised area.

## Iteration 25 — 2026-06-16  (late-game popularity smoothing — measured, then tuned)

### Heuristic focus
The headline remaining balance item (the directive's **Fun/engagement** axis): does the late game
**drift toward revolt**, making the back half of a 20-minute life a dispiriting slide? Deferred twice
for lack of a probe — so this round **built the probe**, measured, and tuned.

### New tool — `tools/ProbePopularity.gd` (reusable scaffolding)
A headless 100-day probe that drives the **real** `GameState` day boundary (world events, weather,
seasons, sieges, services) for a managed seat (Hall + Orchard + Granary + 2 Hovels) with two rival AI
factions for genuine war pressure, logging popularity every 5 days. Fills the "no reusable probe
scaffold" gap noted in memory. (Setup quirk: the orchard isn't hauling-credited without pawns/grid, so
the pre-stocked food buffer empties ~day 95 → a *probe-only* starvation crash in the last 5 days; the
days 30–85 drift is the faithful signal, since food is a solved problem in the real game.)

### Finding — the drift is real (war drag dominates)
Popularity climbs 50→58 in the peaceful early game, then **slides through the war**:
`58.8 (day30) → 44.8 (day60) → 27.8 (day85)`. Root cause: **`active_siege` = −12/day fires for the
entire 48-day siege *assembly*** (×0.05 smoothing ≈ −0.6/day → ≈ −29 over the window) — i.e. the full
"Being attacked" morale hit lands while the enemy is merely *mustering*, not yet storming. Seasonal
+pop events (iter 22) soften but don't reverse it; a real (food-solved) life ends ~22–25 popularity —
survivable but a grind toward discontent.

### Change made (measured, conservative)
- **PopularityEngine**: `active_siege` **−12 → −8** ("a siege looms — the people are fearful"). War
  still pressures morale (~−0.4/day, ≈ −19 over the assembly) so the tension and the restless-people
  warning remain meaningful, but a prepared ruler ends the life in a stable, holdable state. Early game
  untouched (no siege before the King's Peace lapses ~day 30); change can only *raise* popularity, so
  it never threatens the survival floor.

### Verified (same probe, before/after)
| day | 30 | 60 | 85 | (artifact→) 100 |
|----|----|----|----|----|
| before (−12) | 58.8 | 44.8 | 27.8 | 14.1 |
| after  (−8)  | 58.8 | 50.8 | **38.8** | 28.1 |

Day-85 popularity **+11** (27.8 → 38.8); the real (food-solved) day-100 ending rises from ~22–25
(poor/near-revolt) to ~**38–40 ("fair", holdable)**. Full suite green (24/24); the `active_siege`
popularity test still passes (asserts the delta is negative, which −8 satisfies). Live boot clean.

### Post-mortem
- **Failure point:** none — survival was never at risk; this targets *engagement* (a winnable-feeling
  back half rather than a slow loss of the realm's mood).
- **Fun:** the war is still felt (morale visibly dips, the levers matter) but no longer near-guarantees
  a slide to the brink by day 100. The 20-minute life now ends in a realm you're holding, not losing.

### Backlog / next
- A more *engaging* siege-morale model: make the penalty defense-dependent (walls/towers/garrison
  reduce the "fearful" hit) so preparation is rewarded — a richer future iteration.
- Strategic/world-map actions as the human — largest unexercised area.
- Make `ProbePopularity` faithful for food (register buildings/pawns) if a precise day-100 number is
  ever needed.

## Iteration 24 — 2026-06-16  (notification audit: stop leaking engine internals to the player)

### Heuristic focus
Followed iter-23's own backlog: a sweep of **every** `show_notification` call (the directive's UX
**feedback legibility** axis). Two more places leaked raw internals — including the game's *victory*
moment — plus a redundant double-notice. Same theme as iters 21 & 23: a player should never see an
id, a tick count, or an internal string.

### Findings (audit of all view-layer notifications)
- **[MAKES-NO-SENSE] The VICTORY notice showed a raw faction id.** `_on_ai_faction_defeated` printed
  **"Enemy faction 4 has been defeated!"** — the triumphant payoff of a whole war reduced to a debug
  number. (In both `CityViewScene` and the legacy `GameBootstrap`.)
- **[MAKES-NO-SENSE] Edict notices showed raw ids.** `EventBus.edict_activated`/`edict_expired`
  surfaced **"Edict in effect: festival_decree"** / **"Edict expired: festival_decree"** — the snake-
  case id, not "Festival Decree".
- **[REDUNDANT] Double edict notice.** Clicking Activate fired an *optimistic* "📜 Edict proclaimed:
  <name>" immediately (even if the command later failed for lack of edict points), and then the
  authoritative `edict_activated` event fired the raw-id one too — two notices for one action.

### Changes made
- **Victory notice** → "⚔ <Kingdom> has been vanquished!" (gold), via iter-23's
  `GameState.get_faction_display_name` (resolves the still-listed, is_alive=false faction). Both views.
- **Edict notices** → readable via `EdictSystem.lookup(id).name`: "📜 Edict proclaimed: Festival
  Decree" / "📜 Edict lapsed: Festival Decree". Converted `CityViewScene` to named handlers
  `_on_edict_activated` / `_on_edict_expired`; added the `EdictSystemRef` preload to `GameBootstrap`.
- **Killed the redundancy**: removed the optimistic click-time notice; the single source of truth is
  now the authoritative `edict_activated` event (fires only on success), so exactly one accurate,
  readable notice appears.

### Verified
- Headless: full suite green (24/24 suites; no new sim logic this round — `get_faction_display_name`
  was already unit-tested in iter 23).
- **Probe (real helpers)** prints what the player now sees: `⚔ The Ironhand Legion has been
  vanquished!` and `📜 Edict proclaimed: Festival Decree` / `Village Feast`.
- **Live (Xvfb)**: clean boot, no script/parse errors — refactored handlers in both view files wire up.

### Post-mortem (no failure — UX/legibility iteration)
- **Failure point:** n/a.
- **Fun/UX:** the victory screen-beat finally *names the foe you beat*; edicts read like decrees, not
  database rows; and a confusing double-toast is gone. With iters 21/23, the "no raw internals shown to
  the player" pass over notifications is now essentially complete.

### Backlog / next
- Late-game popularity smoothing — still the headline balance item; needs a 100-day managed probe to
  measure the day-60→100 drift now that seasonal +pop beats + morale levers exist (no reusable probe
  scaffold yet — would need to build one).
- Strategic/world-map actions as the human — largest unexercised area.
- (Legacy `GameBootstrap` mirrors fixes for consistency, though `CityViewScene` is the runtime entry.)

## Iteration 23 — 2026-06-16  (threat telegraph: the siege warning was unreadable gibberish)

### Heuristic focus
The directive's **UX feedback** + **threat telegraphing** axes (Phase 4.3/4.4). The single most
important warning in a castle-defence game — "a siege is coming" — was shown to the player as raw
engine internals. Survival is solved, but a warning the player *can't read* fails the engagement goal
at the exact moment stakes spike.

### Finding — [MAKES-NO-SENSE] the siege-assembling notification leaked internal ids and tick counts
On `ai_siege_assembling`, both the live entry scene (`CityViewScene`) and `GameBootstrap` showed:
**"⚠ AI faction 3 assembling siege! ETA: 11520 ticks"**. Two failures:
1. **"AI faction 3"** — a raw numeric id. The player has met "The Ashen Barony", not "faction 3".
2. **"ETA: 11520 ticks"** — `SIEGE_ASSEMBLY_TICKS = 240 × 48`, i.e. **48 days**. "11520 ticks" is
   meaningless to a human; it hides the (actually generous and reassuring) ~48-day window to prepare.
So the game's most critical telegraph named no enemy, gave no usable timeframe, and offered no advice.

### Changes made
- **GameState.get_faction_display_name(faction_id)** (new, unit-tested): resolves an AI-faction id to
  its name ("The Ashen Barony"); falls back to **"A rival lord"** so a raw number is *never* shown.
- **CityViewScene + GameBootstrap**: replaced the inline lambda with a named handler
  `_on_ai_siege_assembling(faction_id, _tpid, eta_ticks)` (more robust than a multi-line lambda),
  which now shows: **"⚠ <Kingdom> is marshalling a siege against your seat — ready in ~N days. Raise
  walls, towers and a garrison!"** — named threat, ETA in **days**, and clear advice. Longer dwell
  (9s) and an alarm-orange colour, fitting its importance.
- **TestPhase6**: +2 assertions (id→name resolves; unknown id → "A rival lord", never a number). 83/0.

### Verified
- Headless: full suite green (24/24 suites); TestPhase6 83/0.
- **Probe (real GameState helper + the exact handler format)** prints what the player now sees:
  `⚠ The Ashen Barony is marshalling a siege against your seat — ready in ~48 days. Raise walls,
  towers and a garrison!` and unknown-id → `A rival lord`.
- **Live (Xvfb)**: clean boot, no script/parse errors — the refactored view files + the new signal
  handler load and wire correctly.

### Post-mortem (no failure — UX/telegraph iteration)
- **Failure point:** n/a.
- **Fun/UX:** the defining tension beat of the game (incoming siege) now reads as drama, not a debug
  log: you know *who* is coming, *when* (~48 days — generous, so the warning empowers rather than
  panics), and *what to do*. Consistent with the iter-21 "stop leaking internals to the player" theme.
- **Content density:** unchanged; this sharpens an existing beat rather than adding one.

### Backlog / next
- Strategic/world-map actions as the human (develop city / raise army / campaign / diplomacy) — the
  largest unexercised area; a future deep-dive.
- Late-game popularity smoothing (measure the day-60→100 drift via a 100-day probe now that seasonal
  +pop beats exist; smooth only if it still trends to revolt).
- Audit other notifications for leaked internals (faction ids / tick counts / raw building ids).

## Iteration 22 — 2026-06-16  (content density: the realm's events now turn with the seasons)

### Heuristic focus
Survival is solved & celebrated; the remaining sim-correctness backlog item (worker labour cap)
turned out to be **narrow and harmless** on inspection (see note below). So this round serves the
directive's **Content Density** + **"makes sense"** axes: make `WorldEventSystem` — the data-driven
content-extension point — **season-aware**, so the 20-minute arc *feels* like it passes through
spring, summer, autumn and winter rather than a seasonless soup of generic events.

### Note — why the "worker labour cap" backlog item was downgraded, not fixed
The fear was "auto-staff sets workers=max even when villagers are scarce → buildings out-produce the
workforce." But **`ResourceTick.is_chain()` is true for every producer except `trading_post`** — and
chain producers (food/wood/stone/iron + all processed goods) are credited **only when a real hauler
pawn physically delivers**, so they're *already* labour-capped by the actual citizen count. The only
assigned-worker-scaled producer that ticks abstractly is the trading post (gold), and over-building
those merely earns a little phantom gold — it *helps* the player, never threatens the 20-min goal.
Not worth destabilising the tuned economy for. Logged as closed/low-value.

### Finding — [MAKES-NO-SENSE] seasonal-flavoured events fired in the wrong season
`spring_lambs` ("Spring brings a strong crop of lambs…") could fire in the dead of winter — the
event pool had **no season gating at all**, even though the game has a visible 4-season calendar
(`SeasonSystem`, 12 days/season → ~2 of each season per 100-day life).

### Changes made
- **WorldEventSystem**: events may now carry an optional **`season`** key (a `SeasonSystem.Season`
  int, or an Array of them). `tick()` computes `current_season(day)` and filters the eligible pool
  to year-round events + those whose season matches. Fully back-compatible (no key = any season).
  New tested helper `_event_in_season(event, season)`.
- **Fixed the sense bug**: `spring_lambs` is now gated to Spring.
- **+6 seasonal events** (bounded, positive-leaning, tied to the calendar): **Spring** — The Spring
  Fair (+pop/+gold); **Summer** — Long Summer Days (+food/+pop), A Dry Spell (−food); **Autumn** —
  Harvest Home, the great harvest feast (+food/+pop, the season's big beat); **Winter** — Hearth
  Tales (+pop), A Deep Frost (−food). Event pool 22 → 28.
- **TestWorldEvents**: +11 assertions (helper int/array/no-season cases; whole-season drives proving
  out-of-season events never surface, in-season ones do, year-round ones still fire). Suite 27 → 38/0.

### Verified
- Headless: all 11 new assertions pass; World Events 38/0. Only TestWorldEvents references the system,
  so the rest of the suite is unaffected.
- **Live (real game on Xvfb)**: booted clean — the new `SeasonSystem` preload + seasonal events +
  season filter load with **no script/parse errors** (game initialized, HUD rendered). Fast-forwarded
  at 5× and caught a live event toast in the feed — "Traveling Minstrels — Minstrels fill the evening
  with song…" — confirming `tick()` still fires & surfaces events end-to-end with the season filter
  (and that year-round events still fire). Food drew down 200→172 as expected, sim healthy.

### Post-mortem (no failure — engagement/content iteration)
- **Failure point:** n/a.
- **Fun/Content density:** the realm's mood now turns with the year — a harvest feast in autumn, tales
  by the winter fire — so the same 20 minutes reads as a passing year, not a static loop. Content
  compounds: each future season-keyed dict entry deepens the felt calendar at zero framework cost.
- **Makes-sense:** no more lambs in January; flavour matches the on-screen season tint.

### Backlog / next
- Strategic/world-map actions as the human (develop city / raise army / campaign / diplomacy) — the
  largest unexercised area; a future deep-dive.
- Late-game popularity smoothing (verify the seasonal +pop beats help the day-60→100 drift).
- More content: building-specific events, threat telegraphs, multi-step decisions; a fresh-eyes
  onboarding pass.

## Iteration 21 — 2026-06-16  (HUD honesty: the ale-ration row was lying to new players)

### Heuristic focus
Survival to Day 100 is solved and now *celebrated* (iter 20). So this round targets the directive's
**Human Experience (UX)** + **"makes sense"** axis: a long-standing backlog wart (flagged iters 4 & 7)
— the ale-ration display — finally chased to ground and fixed.

### Finding — [MAKES-NO-SENSE] the ale-ration HUD label promised a bonus that didn't exist
On the realm panel, the **Ale Ration** row showed an effect descriptor next to it. At the default
("Half", level 1) it read **"½ bonus"** in neutral grey — implying a half-strength popularity boost
from ale was active. It was a **double lie**:
1. **No inn → no effect.** `PopularityEngine._ale_score` multiplies the ration's base by
   `inn_coverage`, which is **0 until you build an Inn**. A fresh village (no inn, 0 ale) gets exactly
   **0** popularity from ale, no matter the ration — yet the HUD claimed "½ bonus".
2. **Level 1 is the neutral baseline anyway.** `ALE_RATION_POPULARITY[1] = 0` (Low = neutral). The
   real bonus only starts at Normal (level 2 = +5). So even *with* an inn, "½ bonus" at level 1 was
   wrong — it's 0.
The popularity *tooltip* (HUDController) already computed ΔAle = base × inn_coverage correctly, so the
inline row label silently contradicted the game's own breakdown. A new player tuning rations got false
feedback on a core morale lever.

### Changes made
- **HUDController.get_ale_ration_effect(ale_ration, inn_coverage) → {text, tone}** (new, testable):
  the honest descriptor. `inn_coverage <= 0` → **"no inn"** (neutral); else by the *actual* base —
  level 0 = "↓pop" (bad), level 1 = "neutral", level 2+ = "↑pop" (good).
- **HUDNode**: the ale-ration delta label now calls the helper (passing live `inn_coverage`) and maps
  tone→colour, instead of the old ration-level-only "↓pop / ½ bonus / ↑pop" guess.
- **TestPhase7**: +6 assertions — no-inn shows "no inn" at any ration; with an inn, level 0 hurts /
  level 1 neutral / level 2 helps. Suite now 99/0.

### Verified
- Headless: the 6 new assertions pass; TestPhase4 (popularity) unchanged 60/0; TestPhase7 99/0.
- **Live (real game on Xvfb)**: launched a fresh village, screenshotted the realm panel — the Ale
  Ration row now reads **"no inn"** in grey (was "½ bonus"), Food Ration "normal", Tax "neutral".
  The HUD no longer promises a morale bonus the player isn't receiving. The view code parses & renders
  clean (game initialized, HUD drew correctly).

### Post-mortem (no failure to analyse — survival is solved)
- **Failure point:** n/a — this is an engagement/legibility fix, not a survival blocker.
- **Fun/UX:** removes a small but corrosive trust-breaker — a HUD that lies about cause→effect makes
  every other readout suspect. Honest feedback on the ration levers makes the management loop legible.
- **Content density:** unchanged this round; the ale row now also *teaches* — "no inn" quietly points
  the player at the Inn as the prerequisite for the ale morale lever.

### Backlog / next
- Worker labour cap (auto-staff can exceed idle villagers) — last untouched sim-correctness backlog item.
- Strategic/world-map actions as the human (develop city / raise army / campaign / diplomacy) — still
  largely unexercised; a future deep-dive.
- More content (events/objectives); late-game popularity smoothing; a natural fresh-eyes onboarding pass.

## Iteration 20 — 2026-06-16  ⚜ THE GOAL HAS A PAYOFF NOW (Day-100 reign milestone)

### Finding
Reaching **Day 100 (20 minutes) — the entire point of "a life"** — had **no payoff**: just one of
six small objective-complete notices, then the game droned on. The only "VICTORY" screen is for
military conquest (vanquish all enemies). The achievement the whole loop is built around went
completely unrecognised.

### Change made (fitting for iteration 20)
- **GameState**: when the player reaches Day 100 alive (own seat, once), award **+200 prestige** and
  emit `EventBus.sovereign_reign_reached`. NOT a game-over — the realm endures.
- **CityViewScene**: a triumphant, gold-bordered, **dismissible** overlay — "⚜ A SOVEREIGN'S REIGN ⚜
  — One hundred days of unbroken rule, a full twenty minutes upon the throne… Long may you reign.
  (+200 prestige)" with a **"Continue Ruling"** button that resumes play. Holds time while shown.
- New `SR_REIGN` dev hook to preview the overlay on boot.

### Verified
- Probe: signal fires exactly once at Day 100; prestige jumps +200 (220→420). Suite green.
- Live (SR_REIGN): the overlay renders beautifully (title, message, Continue Ruling button).

### Milestone note (20 iterations)
From iter 1's "can't survive 5 minutes" to here: a 20-minute life is reachable, every core system
works through the real UI, and reaching the goal is now a celebrated moment. The loop did its job.

## Iteration 19 — 2026-06-16  (world map: city hover-details that actually show)

### Played (real clicks) — the strategic layer, finally
Launched from the **main menu** (lovely sunset title) → New Game → **World Map**. It renders richly: a
procedural biome continent, 5 competing kingdoms (legend: Crimson Throne, Azure Dominion, **Emerald
March (You)**, Violet Pact, Amber Hold — you hold 12 cities), city banners with garrison counts,
roads. Clicked a city → it **entered the CityViewScene** at that city's coords (the first city you
enter becomes your playable seat). Strategic→tactical bridge works.

### Finding
- **[MAKES-NO-SENSE] The city detail panel never shows anything.** The bottom panel said "Hover or
  click a city to see details", but hovering only **highlighted the city visually** — `WorldMapView`
  tracked `_hovered_city_id` and redrew, but never populated the InfoLabel. And clicking *enters* the
  city (doesn't show details). So "hover to see details" was a promise the game never kept, and the
  two on-screen hints contradicted each other.

### Changes made
- **WorldMapView**: new `city_hovered(city_id)` signal, emitted when the hovered city changes.
- **WorldMapScene**: `_on_city_hovered` populates the info panel with the city's **name, owner kingdom
  (in that kingdom's colour), development, and garrison** — and clears to a prompt when you leave.
  Verified live: hovering shows "Cresthollow — Emerald March · Development 2 · Garrison ⚔ 8" in green
  (so you can spot YOUR cities by colour).
- Fixed the contradictory hint text → "Hover a city to see details · Click it to enter and rule it".

Full suite green; world map renders + hover verified live.

### Backlog / next
- The strategic actions (develop city / raise army / launch campaign / diplomacy) as the human are
  still largely unexercised — a future deep-dive. More content; late-game popularity smoothing.

## Iteration 18 — 2026-06-16  (market/trade verified + clearer trade buttons)

### Checked + played
- First confirmed no OTHER panel shares the iter-14 refresh-before-visible bug — only Tech & Edicts
  had it (now fixed); trade lives in the always-visible selection panel.
- Played the untested **market/trade** path with real clicks: built a Hall + **Market** (animated
  stalls), selected it → Buy/Sell buttons per resource appeared. **Sold 10 wood → Wood 280→270,
  Gold 490→520** (+30, 3g each). Trade works end-to-end.

### Finding + change
- **[UX] Cryptic buy buttons.** The buy button read "→ WO" (price-trend glyph + 2-letter code) with
  no "Buy" — next to a "Sell" button, a player can't tell it's the buy action without hovering.
- **HUDNode**: relabeled to **"Buy WD ↑"** (explicit action + resource + price-trend glyph) and
  **"Sell WD"** (resource added for symmetry), with slightly wider buttons. The price trend (↑ pricey
  / ↓ cheap / → normal) is preserved for at-a-glance trading.

Full suite green; build renders clean.

### Status note (18 iterations in)
Core systems are now all verified working through the real UI: economy/food, housing/growth,
military (build/recruit/command/combat), tech research, edicts (incl. an early one), trade, events,
decisions, objectives. The 20-minute life is achievable and the systems are legible.

### Backlog / next
- A natural fresh-eyes full playthrough for remaining feel/onboarding gaps; late-game popularity
  smoothing; the world-map/strategic layer (largely unplayed as the human); more content.

## Iteration 17 — 2026-06-16  (an early morale edict — the Edicts panel finally does something)

### Finding
**Every one of the 20 edicts requires tech** (mostly Royal Edicts = 300+ prestige). So a new player's
Edicts panel is entirely **Locked** — the whole royal-decree fantasy is inaccessible for ~40 days,
and the restless-people advice ("hold a feast") can't be followed when it's actually needed.

### Changes made
- **New edict "Village Feast"** (EdictSystem): no tech, 2 edict points, 6-day cooldown, fires the new
  `feast` instant event for **+6 popularity now**. Available from day ~1 (points accrue +2/day).
- **PopularityEngine**: `feast` event = +6 (uses the iter-16 instant-event fix, so it lands in full).
- **Restless warning** now leads with the always-available Village Feast.
- **Notices made readable**: edict activation says "📜 Edict proclaimed: Village Feast" (not the raw
  id); the celebration line is generic ("🎉 Feasting fills the streets — popularity +6").

### Verified LIVE (real clicks)
Fast-forwarded a few days, opened Edicts → an **"Available Edicts" section with "Village Feast —
Activate (2P)"** (rest still Locked behind tech). Clicked Activate → "Edict proclaimed" + the feast
applied (+6, probe-confirmed: popularity 45→51). The Edicts panel is now useful from the start.

Full suite green.

### Backlog / next
- More no-tech basic edicts / content; the activate path is solid now.
- Late-game popularity smoothing; move-order feedback; more events/objectives.

## Iteration 16 — 2026-06-16  (the Festival barely worked — fixed the popularity lever)

### Finding (via probe — the Festival is 400-prestige-gated, impractical to reach by clicks)
Set up a player with Royal Edicts unlocked + edict points and activated **Festival Decree** — the
exact lever the iter-11 restless-people warning sends players to. Its description promises **+8
popularity**, but it delivered **+0.4**. Cause: `_cmd_activate_edict` routed the festival's
`instant_event` through `PopularityEngine.apply_tick`, which **scales the delta by ×0.05** (the
per-tick smoothing for *continuous* daily pressure). So a one-off decree of +8 became +0.4 — a
meaningless nudge. The morale lever I recommend was effectively broken.

### Changes made
- **PopularityEngine.apply_instant_event(player, event_id)**: applies an event's FULL one-off delta
  immediately (clamped), distinct from the ×0.05-smoothed `apply_tick`.
- **GameState._cmd_activate_edict**: instant-event edicts now use `apply_instant_event`, so a Festival
  lands its whole +8. Plus a "🎉 A Festival is decreed — the people rejoice (popularity +8)" notice.
- Verified via probe: Festival now moves popularity 45.0 → 53.1 (was → 45.4). Full suite green.

### Note
This closes the edict half of the progression loop (research → unlock → use): research works (iter
15), edicts now actually do what they say. Reaching the Festival in real play needs 400 prestige
(scouting_vision + royal_edicts) — steep; consider a cheaper early morale edict in a later round.

### Backlog / next
- A cheaper/earlier morale edict so the "hold a Festival" advice is reachable when restless (~day 75).
- More content/feel polish; late-game popularity smoothing; move-order feedback.

## Iteration 15 — 2026-06-16  (progression loop verified live + rewarding research feedback)

### Played (real clicks) — closing the loop on the iter-14 panel fix
Fast-forwarded to ~120 prestige, opened the now-working **Tech** panel, and clicked **Research** on
Crop Tiers (100P). End-to-end success, verified on the live HUD:
- "Researching: crop_tiers" fired, prestige dropped **127 → 34** (spent 100),
- and the Food build menu's **Wheat Farm and Hops Farm flipped from "Needs: crop_tiers" to buildable.**
So research → spend prestige → unlock new buildings works fully now that the panel populates. The
critical iter-14 fix is confirmed to enable real progression.

### Small improvement
- The research feedback was a raw, payoff-free "Researching: crop_tiers". Now **GameState fires a
  reward notice on success** — "🔬 Researched Crop Tiers — unlocked Wheat Farm, Hops Farm." (readable
  name + exactly what it unlocked) — and the redundant raw-id click notice was removed. Research now
  feels like progress. Verified via probe (prestige 300→200, correct notice).

Full suite green.

### Backlog / next
- Verify an edict activation end-to-end (needs royal_edicts tech first); more content/feel polish;
  late-game popularity smoothing; move-order feedback.

## Iteration 14 — 2026-06-16  ⚑ CRITICAL: Tech & Edicts panels were permanently blank

### What I played
Verified the unit-command loop first (select a Captain → info panel shows HP/Atk/Def/class; right-click
orders it to move/fight; auto-aggro engages — all working; enemy **red** team rings confirmed too).
Then opened the **Edicts** panel (the iter-11 restless warning sends players there) — and it was
**completely empty**.

### The bug (critical, pre-existing)
`_toggle_edict_panel` (and `_toggle_tech_panel`) called `_refresh_*_panel()` **before**
`_animate_panel_open` set the panel visible — but each refresh early-returns `if not panel.visible`.
So the refresh bailed every time and **both the Technology tree AND the Royal Edicts panels never
populated** — permanently blank. Two of the game's core progression systems (research, decrees) were
**inaccessible through their UI** for every player. (They worked via the command pipeline, which is
why automated tests/prior loops never caught it — only opening the panel as a human did.)

### Changes made
- **HUDNode**: open the panel (visible=true) BEFORE refreshing, for both Tech and Edicts. Verified
  live — the **Tech tree now lists every tech with its price** (Agriculture/Industry/Military/
  Statecraft) and the **Edicts panel lists every edict**.
- **Edicts panel content**: also render a **Locked Edicts** section (greyed, with the unlock reason,
  e.g. "Festival Decree — Requires tech: royal_edicts") and an **Edict Points** header — so the panel
  is legible even before anything is unlocked (was: show only active+available, both empty → blank).
- **Restless warning** reworded to lead with the always-available lever: "lower taxes, raise a Church
  or Inn, or proclaim a Festival (once Royal Edicts is researched)".

Full suite green; both panels verified populating live.

### Backlog / next
- Verify actually researching a tech / activating an edict from the (now-visible) panels end-to-end.
- Move-order feedback; punchier combat; more content. Late-game popularity smoothing.

## Iteration 13 — 2026-06-16  (the military loop, played — and silent recruiting fixed)

### Played (real clicks) — the hands-on military loop
Launched a real game, built a Hall + **Barracks** (grey keep with red banners), selected the barracks,
and recruited 3 Armed Peasants. It **works**: gold dropped correctly (500 → 475 = 10 barracks +
3×5 recruits), and the soldiers spawned as units with the iter-12 **blue team rings** by the campfire
muster point. The recruit→spawn→combat loop is functional and now legible.

### Finding
- **[UX] Recruiting is completely silent.** `_cmd_recruit_unit` appends the unit and returns — it
  emits **no signal and no notice**, and CityViewScene never wired `unit_spawned` to anything. You
  click "Recruit", gold drops, and… nothing. You have to hunt the map to find where your soldier
  appeared (the campfire, it turns out — not the barracks). No confirmation it even worked.

### Change made
- **GameState._cmd_recruit_unit**: on a player recruit, fire a `realm_notice` — "⚔ <Unit> mustered by
  the campfire — ready for your orders" (instant units) or "⚔ <Unit> began training at the barracks"
  (trained units). Verified via probe: recruiting an Armed Peasant fires the notice and deducts gold.
- **CityViewScene**: wire `unit_spawned` (fired when a unit finishes training) → "⚔ <Unit> is trained
  and ready for battle." So the player gets both the muster confirmation and the ready-for-war beat.

Full suite green.

### Backlog / next
- Test select→move→attack command of your soldiers, and whether auto-aggro defends the keep well.
- Punchier clash feedback; a recruited-unit rally flag at the campfire.
- Late-game popularity smoothing; tribute pause; more event/objective content.

## Iteration 12 — 2026-06-16  (combat readability: friend-or-foe at a glance)

### Why / what I played
Survival to Day 100 is solved, so the loop turns to *fun*. The biggest untested experience is
**combat** — and a siege *will* come. I launched with the `SR_SPAWN_UNITS` showcase (player army +
enemy warband) and watched a real battle on Xvfb.

### What I saw
- **Combat works**: units march and engage, **arrows fly** (projectile system), siege engines
  (catapult/ram/mantlet) render and animate. Mechanically sound.
- **[UX] You can't tell friend from foe.** Every unit's tunic is coloured by its TYPE (peasant brown,
  scout green, militia grey…); the team tint (blue=yours, red=enemy) was only a minor accent buried
  in the figure. In a melee you genuinely cannot tell your soldiers from raiders — a serious problem
  for a castle-defence game.

### Change made
- **UnitLayer**: draw a **team-coloured disc + ring under each unit's feet** — bright blue for your
  troops, red for the enemy (the standard RTS convention). Verified live with `SR_SPAWN_UNITS`: your
  units (soldiers + all three siege engines) now wear unmistakable blue rings; enemy units use the
  same draw with the red team colour. Battlefield is readable at a glance.

Full suite green (view-only change); build launched + rendered clean with the showcase.

### Backlog / next
- Try the real recruit→command→defend loop through the UI (barracks + soldiers vs the post-grace
  siege) and improve it if clunky.
- Combat feedback (clash flashes, casualty markers) could be punchier.
- Late-game popularity smoothing if the iter-11 warning proves insufficient; tribute pause; more
  event/objective content.

## Iteration 11 — 2026-06-16  ✅ 20-MINUTE LIFE CONFIRMED END-TO-END (incl. war)

### The headline
A **full-game probe** (real `GameState`, both AI factions, sieges, weather, events, objectives,
births) playing a managed game — Hall + Orchard + Granary + 2 Hovels — **survived all the way to
Day 100 (20 minutes) with the keep intact**:
- Keep HP 500 → 200 (the Ashen Barony's siege assembled ~Day 78 and landed a couple of 150-HP hits,
  but 3–4 are needed to fell it, so it held); no revolt, no starvation.
- Population grew **14 → 25** (the iter-10 housing fix carrying it past the "20 souls" objective).
- Food stayed healthy (189–195, dipping only in deep winter). **The loop's goal is met.**

### The remaining concern (and fix)
- **Late-game popularity erodes**: 52 (Day 40) → 23 (Day 100), driven by the war (siege/raid events)
  and a town outgrowing its services (no church/inn). It survives to Day 100 but would drift toward
  revolt beyond it, and nothing told the player how to arrest the slide.
- **Fix — a "restless people" warning**: when popularity crosses below 35, a one-time `realm_notice`
  fires — "⚠ Your people grow restless — hold a Festival (Edicts), lower taxes, or raise a Church or
  Inn to lift their spirits." Re-arms only after popularity recovers above 45, so a slow drift is
  never silent and the player knows the levers. (Verified firing in the full-game probe.)

Full suite green.

### Backlog / next
- Late-game popularity could also be eased structurally (slightly soften per-event siege popularity
  hits, or scale service expectations gentler) if the warning + player action proves insufficient.
- Pause/deadline-timer for tribute demands (like decisions). Worker labour cap. Build-mode eats HUD
  clicks. Keep adding event/objective content.

## Iteration 10 — 2026-06-16  (full-life attempt → fix: the village couldn't grow)

### Played (real clicks) — pushing for a full 20-minute life
Built Hall + Orchard + Granary through the UI, took a Knight Errant into service, **paid** an Ashen
Barony tribute of "30 gold, 12 iron" (iter-8 fix confirmed live — payable now, not ale), and
fast-forwarded to **Day 42**: thriving (Food 193–200/200, Prestige 455, Health 50). Survival is
robust hands-on. The objective panel had advanced to "(2/6) Grow your village to 20 souls."

### Why a 20-minute life stalls (the finding)
- **[MAKES-NO-SENSE BUG] The village can't grow.** At Day 42 population was still **14** — the
  starting count. Births gate purely on housing headroom (`living_count < cap`), and `BASE_HOUSING`
  was **8** while the village **starts with ~14 villagers** → overcrowded from day one, so it can
  NEVER grow until the player happens to build hovels. Nothing tells them this, and the "Grow to 20"
  objective gave no hint. A silent dead-end on a core progression path.
- (Minor) A tribute's 7-day deadline can lapse while you're busy, because the DiplomacyPanel doesn't
  pause like the EventChoicePanel does. Logged for later.

### Changes made this iteration
- **PeopleSystem.BASE_HOUSING 8 → 16**: the hall/keep now shelters the founding village (~14) with a
  little headroom, so it grows a little on its own; hovels (rooms) carry it further. Probe: population
  14 → 16 on base housing, → 19 by Day 60 with two hovels (cap 24). Steady, not glacial.
- **ObjectiveSystem**: "Grow your village to 20 souls" → "…— build Hovels to house new families" so
  the player knows HOW to grow past the base.
- `_get_population_cap` (the separate abstract cap used by TestPhase10) is independent of
  `BASE_HOUSING`, so nothing else shifted. Full suite green.

### Backlog / next
- Consider pausing (or a clear deadline timer) for tribute demands too, like decisions.
- Population growth is steady but slowish (~1 per 10–15 days) — fine for now; revisit if "grow to 20"
  feels long. Reach Day 100 in one continuous real session to fully close the loop.
- Worker labour cap; build-mode eats HUD clicks; more event content.

## Iteration 9 — 2026-06-16  (direction: a standing Objective tracker)

### Why
Across the playthroughs the realm survives and now has events/decisions, but a new player still
lacks a clear, *standing* answer to "what should I be doing, and where is this all going?" Milestones
fire and vanish; the tutorial's hints are sequential and transient. The 20-minute goal itself was
never shown. A persistent objective tracker gives constant direction — and naming "rule to Day 100"
as the final objective makes the loop's own goal legible to the player.

### What I added — ObjectiveSystem + HUD panel
- **`simulation/core/ObjectiveSystem.gd`**: an ordered, forward-looking objective list (distinct from
  backward-looking milestones), each with an `is_complete` check against live state:
  1. Found your seat — build a Village Hall  2. Feed your people — Orchard + Granary
  3. Grow your village to 20 souls  4. Weather your first winter (Day 48)
  5. Ready your defences — Barracks/Wall/Tower (← doubles as military onboarding)
  6. **Endure — rule your realm to Day 100 (20 minutes)** (the loop goal, made explicit).
  `evaluate()` tracks completion in `world["objectives_done"]`, reports newly-completed + the current.
- **GameState**: evaluates objectives each game-day; fires `EventBus.realm_notice` ("✓ Objective
  complete: …") per new completion and `EventBus.objective_updated(index,total,text)` on change.
- **HUDNode**: a persistent "OBJECTIVE (n/6)" panel below the realm panel, always showing the current
  goal; updates on `objective_updated`.
- **TestObjectives.gd** (22 tests): definitions, every completion check (incl. unbuilt sites don't
  count, military/defense both satisfy "ready_for_war"), and `evaluate()` progression/idempotency.

### Verified live (real clicks)
Opened the game → panel reads "OBJECTIVE — Found your seat — build a Village Hall." Built a Hall →
panel advanced to "OBJECTIVE **(1/6)** — Feed your people — build an Orchard and a Granary." End to
end on screen. Full suite green.

### Backlog / next
- More objectives / branching once the basics land; tie some to events.
- Military still has no hand-holding beyond the objective text — a barracks/recruit nudge could help.
- Worker labour cap; build-mode eats HUD clicks; more event content.

## Iteration 8 — 2026-06-16  (longer real playthrough → diplomacy that makes sense)

### Played (real clicks) — the LATE game I'd never reached
Built a real economy through the UI (Hall + **2 orchards** + Granary), declined a Knight Errant
decree (auto-pause held the moment), and fast-forwarded past the King's Peace to **Day 39**. Findings:
- **Survival is genuinely solid in real play.** By Day 39 the realm was *thriving*: Food capped at
  **200/200** (two buffed orchards over-feed it), Gold 560, Prestige 440, Health 50, no starvation.
  The 20-minute economy works hands-on, not just in the probe.
- **[MAKES-NO-SENSE BUG] Tribute is unpayable.** At Day 39 the Ashen Barony demanded **25 ale**
  ("Lord Malakor's patience wears thin. Pay, or face Highwatch's wrath", Threat 100/100). But ale is
  locked behind crop_tiers → hops_farm → brewery — unreachable for a young realm. So **every early/
  mid tribute is literally unpayable → a forced refuse every 14 days** (−popularity, +threat,
  embargo). A demand you can never satisfy is a tax, not a decision.
- **[UX] No warning when the grace ends.** The King's Peace silently expires (~day 30) and rivals can
  march, but the player gets no signal to prepare.

### Changes made this iteration
- **AshenBarony**: tribute now demanded in **gold (60×scale) + iron (25×scale)** — things a young
  realm actually has — instead of ale. Now you can *choose* to pay or refuse.
- **DiplomacySystem.accept**: handle `gold` (it only deducted food/resources before, so a gold tribute
  wouldn't have been paid). Verified: a demand of 30 gold + 12 iron deducts both (500→470, 50→38).
- **GameState**: emit a `realm_notice` telegraph the day the King's Peace ends — "⚔ The King's Peace
  has ended — rival lords may now march… Raise walls and a garrison." Fair warning before war.
  (Verified firing at day 30.)
- Full suite green; tribute tests (TestPhase6/10) still pass; no stale refs to the old constant.

### Backlog / next
- Visible objective/goal tracker (milestones are transient) — give the player standing direction.
- Military onboarding: the tutorial never mentions defence; after the Peace ends a new player has no
  army. Consider a hint to build a barracks/wall, or a gentle first-raid.
- Food over-caps at 200 with 2 buffed orchards (build more granaries to stockpile) — minor, by design.
- Worker labour cap; build-mode eats HUD clicks.

## Iteration 7 — 2026-06-16  (decision polish + more content; harness fixed; LIVE verified)

### Harness breakthrough
The interactive Xvfb path (real xdotool clicks) that kept dying in iters 5–6 was just **leftover
display state from rapid relaunch cycles**. With a full clean (`pkill godot+Xvfb`, remove the :99
lock, wait 2s) and a single launch per iteration, `DISPLAY=:99` is reliably drivable again. So this
round I **played for real** and visually verified iters 5–7 end-to-end.

### Played (real clicks) — what I confirmed live
- World Events fire and surface (saw "Wandering Merchant", events raised gold 500→620 over ~25 days).
- A **decision popup** appeared mid-fast-forward ("⚜ Brigands on the Road — 40 gold to let your carts
  pass" with two option buttons), and resolving one applied the effect + a "You decreed…" notice
  (clicked an option → gold −35 exactly, food +40, notice shown). Iters 5 & 6 = confirmed working.
- Health now reads **50** on a fresh village (iter-4 fix confirmed on the live HUD, not just tests).

### The gap I felt while playing → this iteration's fix
At 5× speed a decision popup is **easy to blow past** — the realm keeps moving while you're meant to
be deciding. A ruler's decree should command attention.
- **Auto-pause on decisions** (EventChoicePanel): when a choice event fires, hold time
  (`SimulationClock.set_speed(PAUSED)`); restore the prior speed when the player chooses. Events only
  fire on unpaused day-boundaries, so the captured speed is always valid to restore.
  **Verified live**: a "Knight Errant" decision froze the game at Day 9 across 24s of frames; clicking
  "Take him into service" applied −80 gold / +18 prestige and the game resumed (Day 9→11).
- **+4 events** (content compounds): The Ewes Have Lambed (+food), A Master Craftsman (+prestige/gold),
  A Knight Errant (hire vs decline), and **Poachers in the Wood** — a moral choice (hang them for
  +prestige/−popularity, or show mercy for +popularity). 21 events total now.

TestWorldEvents still 27/27; full suite green; build verified rendering + driven live.

### Note / non-issue
- The iter-4 "ale ration Half but 0 ale" worry is a **non-issue**: `_ale_score` is gated by
  `inn_coverage` (0 without an inn), so ale ration has zero popularity effect early. No fix needed.

### Backlog / next
- More content: seasonal-flavoured events, building/threat-tied events, multi-step decisions.
- Visible objective/goal tracker (milestones are transient); telegraph the post-grace first raid.
- Worker labour cap; build-mode eats HUD clicks.

## Iteration 6 — 2026-06-16  (content: World Events become DECISIONS)

### Why
Iter 5 gave the realm a pulse (auto-resolving events). The natural next beat for "more fun / more
human experience" is turning happenings *to* you into things you *decide* — the step from spectator
to ruler. The framework was already built to carry choices.

### What I added — player-choice events
- **WorldEventSystem**: events may now carry a `choices` array (each `{label, effect}`) instead of a
  flat `effect`. `tick()` defers a choice event's effect until the player decides; new helpers
  `has_choices()`, `event_by_id()`, and `resolve(player, id, index)` apply the chosen option.
  **5 decision events** with real trade-offs: A Baron's Offer (loan: +150 gold/−6 pop vs decline:
  +10 prestige), Brigands on the Road (pay toll vs drive off: −food/+pop), Refugees at the Gate
  (welcome: +2 villagers/−food/+pop vs turn away: −pop), A Traveling Scholar (host: −gold/+prestige),
  A Hooded Stranger (buy the 'relic': −gold/+food vs refuse: +pop).
- **Command-routed** for determinism (mirrors the tribute panel): new `CommandQueue.RESOLVE_EVENT_CHOICE`
  (=31, appended so existing values stay stable). `GameState._cmd_resolve_event_choice` applies the
  effect, enacts a villager spawn for "welcome refugees/wanderer", and emits `EventBus.realm_notice`.
- **EventChoicePanel.gd** (new HUD popup, modelled on DiplomacyPanel): hidden until a choice-event
  fires, shows the title/story + a button per option; a click enqueues the command and dismisses.
  The popup *persists* until you decide (won't vanish like a notification). Plain events still flow
  to the notification feed; `_on_world_event` skips choice events so the two never collide.
- **Tests**: TestWorldEvents extended to 27 (choice well-formedness, deferred effect, resolve applies
  the right option, invalid-resolve no-ops, refugees report spawn). Integration probe: the full
  command path works (refugees → +2 villagers, loan accept → +150 gold, realm_notice fired). Scene
  loads clean with the new panel (SR_SHOT, no parse errors). Full suite green.

### Note
Visual catch of the live popup was blocked by recurring Xvfb interactive flakiness (display dies on
launch), but the panel reuses the exact verified DiplomacyPanel pattern and the scene loads error-free.

### Backlog / next
- Auto-pause (or a soft timeout/default) when a decision popup is up, so it isn't missed at 5× speed.
- Keep adding events (seasonal, building-specific, threat telegraphs); more multi-step decisions.
- Still open: ale-ration-vs-0-ale mismatch; worker labour cap; build-mode eats HUD clicks.

## Iteration 5 — 2026-06-16  (content: World Events — the realm feels alive)

### Why
With survival to 20 min now solid *and* forgiving (iters 1–4), the loop pivots to the directive's
other axes — **more fun / more content / more sense**. The clearest gap I'd observed playing: the
early-to-mid game is **thin to *do*** — build three buildings, then watch meters. Milestones already
fire as notifications, but there was **no random-event system** at all; the only "events" were
weather, AI tribute and sieges. A management game lives on its moment-to-moment happenings.

### What I added — a data-driven World Events system
- **`simulation/world/WorldEventSystem.gd`**: each game-day, after a 5-day cooldown, a 34% chance a
  flavourful event befalls the realm — drawn from a weighted, `min_day`-gated pool. Effects are
  **bounded and clamped** (an event can never push a resource below 0 or popularity into instant
  revolt) and **lean positive** so the realm feels alive and rewarding to tend, not punished.
  Starter pack (12 events): Wandering Merchant (+gold), Bountiful Foraging / Boar Hunt (+food),
  Traveling Minstrels / Village Wedding (+popularity), A Weary Traveler (**a villager joins**),
  Storm-Felled Timber (+wood), A Good Omen (+prestige); and bounded setbacks — Wolves in the Night
  (−food), Cart Overturns (−wood), Coin Goes Missing (−gold), A Bitter Quarrel (−popularity).
  Each carries evocative title + story text. **Data-driven**: new events are one dict entry, so
  *content compounds* in future iterations — and the framework already returns the whole event dict,
  so a player-**choice** popup can be layered on later.
- **GameState**: ticks events on the day boundary (own seat only); a "wanderer joins" event spawns a
  real villager (snapped to grass, population re-synced). Emits `EventBus.world_event(event_data)`.
- **CityViewScene**: surfaces each event in the notification feed with tone-coloured text + icon
  (✨ good / ⚠ bad / 🕊 neutral) and the effect summary.
- **TestWorldEvents.gd** (14 tests): definitions valid, cooldown + boundary, fires & applies,
  effects bounded (no underflow / no instant-revolt), `min_day` gating. Plus an integration probe:
  8 events over 60 days in a real `GameState` run, good cadence, correct summaries. Full suite green.

### Backlog / next
- **Player-choice events**: layer an Accept/Decline-style popup (like DiplomacyPanel) onto select
  events for real decisions ("a baron offers a loan", "bandits demand a toll").
- Keep adding events each iteration (seasonal events, building-specific events, threat telegraphs).
- Still open: ale-ration-vs-0-ale mismatch; worker labour cap; build-mode eats HUD clicks.

## Iteration 4 — 2026-06-16  (real-click playthrough + forgiving food)

### What I did
Honoured the "play as a human" directive: a genuine **click-driven playthrough** on Xvfb (launch
once, keep alive; pause → build → resume in bursts). Built hall + orchard + granary entirely through
the real UI and fast-forwarded with the speed controls, watching the HUD.

### What I saw
- **Build loop works end-to-end on screen**: placed the Hall (campfire lit, villagers gathered),
  then an Apple Orchard (visible field of apple trees) and a Granary — all auto-staffed and producing
  (validates iter-3's sim fixes through the real input path).
- **BUT it slowly starved.** Food: 200 → 117 (day 11) → 80 (day 26) → 77 (day 38) → **22 (day 57,
  red)**, trending to 0 around day ~65. Popularity drifted 50 → 48.
- Root cause (confirmed with a spread-geometry probe): in the probe's *tight* cluster one orchard
  thrives (food ~180), but with **realistic spread placement** (orchard east, granary far SE — long
  hauls) the hauling throughput halves and **one orchard starves by day 50** (revolt ~day 90). A new
  player who builds one orchard and spreads buildings out slowly starves — punishing and non-obvious.

### Changes made this iteration
- **ResourceTick**: `apple_orchard` output **5 → 10**. Tuned empirically (spread-geometry probe: 8
  still touches 0; 10 holds min-food 107, food 114 & popularity 59 at day 100). One staffed orchard
  now reliably feeds the founding village regardless of how far the granary is placed.
- **DiseaseSystem**: fixed the alarming, unfixable **Health 25** on a fresh village. Base 40 → 50 and
  the malnutrition penalty now triggers only at **variety 0** (no food at all), not variety < 2 — a
  founding village living on a single staple (apples) is simple, not malnourished (every other food
  is tech-gated and unreachable on day 1). Fresh village now reads **~50** ("okay, improvable").
- **TestPhase12**: malnutrition test now uses variety 0; added a test that a single staple is NOT
  malnutrition. Full suite green (22 suites).

### Result
A managed game (hall + 1 orchard + granary) now survives 100 days **comfortably** even with sloppy
building placement — food holds a real buffer instead of bleeding to zero. Fresh-village health no
longer reads as a phantom crisis.

### Backlog / next
- **[UX] Ale ration defaults to "Half" but you produce 0 ale** (no brewery yet) → a standing
  mismatch that may nick popularity and confuse. Default ale ration to None until ale exists, or
  surface "no ale" clearly.
- **[FUN/CONTENT] The early game is thin to *do*** — build 3 buildings, then watch. Needs more
  moment-to-moment engagement: events/decisions, visible goals/milestones, a reason to keep acting.
- Worker labour cap (iter-3 backlog); build-mode eats HUD clicks (iter-2); deeper winter-at-scale.

## Iteration 3 — 2026-06-16  ⭐ 20-MINUTE GOAL REACHED (managed game)

### What I did
With pause/resume fixed, I drove a disciplined *managed-economy probe* (place hall+orchard+granary
via real commands, run 100 game-days, log the trajectory) to find why even a managed game starves.
Peeling the onion uncovered a **chain of three real bugs/flaws**, each hidden behind the previous:

1. **[BUG] New buildings are never staffed.** A freshly-built workplace defaults to
   `workers = 0`, and BOTH production (`ResourceTick`) and worker assignment
   (`CitizenSystem._reconcile_workers`) gate on `workers > 0`. So a player who builds an orchard
   and doesn't manually open it and click "+worker" gets **zero production → starves**. Auto-staffing
   was simply never wired for the player (the genre default is to auto-staff from the peasant pool).
2. **[BUG] The no-tech staple produces nothing 3 seasons of 4.** `apple_orchard` — commented as
   *"the no-tech staple — must feed the early village"* — only yields in **autumn**.
   `harvest_yield_mult`'s own comment promised *"a small trickle off-season"*, but the code returned
   **0.0**. So spring+summer (days 0–23, before the first autumn) had zero food production; the
   starting buffer drains at ~7/day and is gone by ~day 28 → starvation every game.
3. **[BUG/SENSE] Out-of-season blizzards wipe young villages.** Weather wasn't season-gated, so
   **SNOW struck in autumn** (and any season). SNOW = `food_drain 2.0/peasant` (5× total
   consumption) + zero farm yield + −5 popularity/day, lasting up to 7 days. For 14 pop that's
   −35 food/day — a single early snowfall drains the entire 200 buffer. Nonsensical (summer snow)
   *and* lethal.

### Changes made this iteration
- **CitizenSystem** (build completion): auto-staff a finished workplace to its `max_workers`
  (only if it employs workers and is still at 0). Player can still dial workers down to reallocate.
- **SeasonSystem.harvest_yield_mult**: off-season now returns a real **0.6 trickle** (was 0.0),
  honouring its own comment — the staple feeds the village year-round; autumn is still the bumper.
- **WeatherSystem + GameState**: weather is now season-aware — **snow only falls in winter**
  (a rolled snowfall out of winter becomes rain), and SNOW `food_drain 2.0 → 1.0` (still a real
  winter squeeze, no longer instant death). `WeatherSystem.tick` gained an optional `season` arg
  (back-compatible; GameState passes `SeasonSystem.season_at_tick(tick)`).
- **TestSeasons**: updated the two off-season assertions to expect the trickle (>0, < autumn) and
  added a new test that snow only falls in winter. Full suite green (22 suites).

### Result (managed-economy probe, 100 game-days)
Build **hall + 1 orchard + granary** → village now **survives all 100 days (20 min)**: food holds
153–193/200, popularity *climbs* 51 → 59, zero starvation. **The 20-minute goal is reachable in a
managed game for the first time.** (Unmanaged still dies ~day 56 — you must build food, which is
correct.)

### Backlog / next
- **Validate with REAL clicks**: the probe proves the sim; next do a human playthrough confirming the
  same survival via the actual UI (Xvfb flakiness on rapid relaunch cost time this round — launch once
  and keep alive).
- **Worker labour cap**: auto-staff sets `workers=max` even if villagers are scarce; production uses
  the assigned count, so many buildings could out-produce the actual workforce. Add a global labour
  cap so you can't staff more slots than you have idle villagers. (Backlog — not an early-game blocker.)
- Winter survival at scale: 12-day winters with no production + higher drain need real autumn
  stockpiling (multiple orchards/granaries). Verify the curve holds once population grows.
- Health still 25 from day 1 (malnutrition, from iter-1). Build-mode still eats HUD clicks (iter-2).

## Iteration 2 — 2026-06-16

### What happened when I played
- Re-launched fresh to do a *managed* playthrough. First confirmed the unmanaged baseline: the
  iter-1 game, left running ~20 min, ended **"The people have revolted! Day 56 reached"** — keep
  intact (King's Peace + 48-day siege assembly held), death by **starvation→popularity collapse**.
  Confirms the food/popularity spiral is the killer, not the siege.
- Tried to manage: clicked **Pause** first (to build without real-time bleeding during my slow tool
  calls)… then **could not un-pause by any means** — speed buttons, then keyboard 1/2/3, all dead.
  The sim sat frozen at Day 0 / Food 200 indefinitely.

### Why a 20-minute life doesn't happen — THE headline bug this iter
- **[CRITICAL BUG] Pausing softlocks the game.** Speed changes were routed through the CommandQueue
  (`PlayerInputHandler.set_game_speed` / `InputMapper._enqueue_speed` → `CT_SET_GAME_SPEED`). The
  queue is **only drained inside `SimulationClock._advance_tick`, which doesn't run while paused.**
  So Pause applies (a tick drains it → speed 0), but every subsequent Resume command sits in the
  queue forever — **no ticks, so it can never drain.** A player who pauses (the most natural action
  in a management game) can never resume → game bricked → 20-minute run impossible. This survived
  ~170 prior iterations because headless tests and the dev-screenshot path never pause-then-resume
  via the real input; only *actually playing as a human* surfaced it.

### Changes made this iteration
- **PlayerInputHandler.set_game_speed** and **InputMapper._enqueue_speed**: apply
  `SimulationClock.set_speed(speed)` **directly**, bypassing the tick-drained CommandQueue. Speed is
  a local presentation concern (real-time→tick mapping), not deterministic sim state, so direct
  application is architecturally correct. The `CT_SET_GAME_SPEED` command + handler stay intact for
  any direct enqueuers (TestPhase1 covers that path).

### Verified this iteration (real game on Xvfb :99)
- Pause at **Day 1** → click Resume (5×) → advanced to **Day 4**, Food 175→154. Pause/resume works.
- Full test suite still green (TestPhase1 queue→handler path intact, TestPhase7 HUD 93/0).

### Also observed / backlog refinement
- **[MODEL CORRECTION]** `population` syncs to the ~8 living villagers each day (the starting "50" is
  transient), so real food draw is ~4/day, not 25. One orchard (~8/day) over-feeds the village. The
  earlier "need 5-6 orchards" worry was wrong; feeding is easy. The **8-villager workforce vs the
  displayed population** is still a fiction/UX wart (HUD says "Pop: 50" then it visibly isn't).
- **[UX] Build mode eats clicks**: while placing, left-clicks on the speed bar are consumed as
  placement attempts — need to right-click/Esc to exit first. Minor, but a new player will be
  confused. Consider auto-exiting build mode when clicking HUD chrome, or a clearer build-mode
  indicator/cursor.
- Health still locked at 25 from day 1 (malnutrition, carried over from iter-1 backlog).

## Iteration 1 — 2026-06-15

### What happened when I played
- Launched fresh game. Spawn: 50 population, 8 visible villagers, **0 buildings**, Food 100/200,
  Gold 500, Wood 300. Sim runs immediately at NORMAL speed.
- Build menu is a bottom-left panel; defaults to the **Food** category. Village Hall lives under
  **Civic**. Clicking *Civic → Village Hall (free) → Build* enters placement mode. Input path works.
- While I studied the code, the sim kept running unmanaged → by **Day 21**: Food **0/200**,
  Health **25**, starving. An unmanaged settlement starves fast.
- A rival (**The Ashen Barony**) popup demanded tribute "25 ale, 15 iron" — but the player has
  **0 ale**, so the demand is literally unpayable; the only move is Refuse (popularity −5, threat
  +15, trade embargo).

### Why a 20-minute life doesn't happen (root causes)
1. **[BUG] No onboarding in the real game.** `TutorialSystem.start()` and the `tutorial_hint`→HUD
   wiring live only in `GameBootstrap.gd`, which is **not** the runtime entry. The real entry,
   `CityViewScene.gd`, never starts the tutorial nor shows its hints. New players get *zero*
   guidance. Worse, the tutorial copy is stale ("build a Woodcutter's Camp first") — the post-iter-169
   design requires a **Village Hall first**. → DONE this iter.
2. **[GAMEPLAY] Undefended-keep instakill.** All four AI archetypes route attacks through
   `AIFaction.should_attack`. `bandit_king` has attack threshold 15 ("attacks early and often") and
   the Ashen Barony starts with 1200 gold (≈12 base threat) recruiting ~300 gold/day of troops.
   Threat = army/10 + gold/100 + days/5. So a brand-new, wall-less, army-less settlement gets
   sieged within ~10–20 days and the keep falls → DEFEAT long before day 100. There is no
   establishment grace. → DONE this iter (King's Peace grace period).
3. **[GAMEPLAY] Early food clock is brutal.** 50 pop eat 25 food/day; start buffer is 100 (4 days).
   One apple_orchard yields only ~4.8 apples/day (3 per 150 ticks), and food only banks once a
   **Granary** exists and a hauler delivers — so realistically you need ~5–6 staffed orchards +
   builders + a granary online within 4 days or you starve. Not achievable for a new player.
   → DONE this iter (start at full 200 buffer + staple orchard buffed 3→5).

### Changes made this iteration
- **CityViewScene.gd**: start the tutorial for a fresh, non-spectator game and wire
  `tutorial_hint` → HUD notifications; show a "King's Peace" intro notification.
- **TutorialSystem.gd**: rewrote the new-player flow to be Hall-first
  (Hall → farm/orchard → granary → market → edict) with clearer copy.
- **AIFaction.gd**: added `PLAYER_GRACE_DAYS = 30`; `should_attack` returns no-attack while a
  faction's `days_alive < PLAYER_GRACE_DAYS` (≈ first 6 real minutes of a fresh game). This is the
  "King's Peace": time to build farms and defenses before the warlords march.
- **CityViewScene.gd**: starting `apples` 100 → 200 (full base granary cap = 8 days buffer).
- **ResourceTick.gd**: `apple_orchard` output 3 → 5 apples/cycle (≈8/day staffed) so 3–4 orchards
  can sustain the early village instead of 6.

### Refined understanding (from reading the siege path)
- **Siege assembly takes 48 game-days**, and the village hall only takes damage when a siege
  *assembles* (150 HP/hit, ~3–4 hits to fall). Raiders physically **march & skirmish** the moment a
  siege *starts* (not when it lands). So the keep itself is safe until ~day 58 even without grace —
  the true early-life killer is **starvation → −20 popularity → revolt**, plus raider skirmishing
  killing the starting villagers during build-up. My food + grace changes target exactly this:
  grace delays raider skirmishing AND pushes the first keep-hit from ~day 58 to ~day 78, while the
  bigger food buffer + orchard buff stop the starvation-revolt spiral.
- Updated `tests/TestUnitAI.gd` raider-march test to age the faction past the King's Peace (its
  precondition) — the march mechanic is still validated. Full suite green (21 suites, 1 expected
  test edit).

### Verified this iteration (real game on Xvfb :99)
- Fresh launch: no script errors; **Food now starts 200/200** (8-day buffer, confirmed on HUD).
- King's Peace grace gate proven headless: day-5 high-threat faction `should_attack=false`,
  day-35 `=true`. GRACE_DAYS=30.
- Onboarding wiring added to the real entry scene (was dead). Tutorial copy now Hall-first.

### NEW finding (live) — Health locked at 25 on a fresh village
- `compute_health = 40 base + 60·sanitation − 15 malnutrition(<2 food types)`. A brand-new village
  has 0 sanitation buildings and only apples (1 food type) → **health = 25 from day 1**, with no way
  to raise it yet. Not an immediate survival threat (disease needs 5+ hovels + low sanitation via
  `is_crowding_risk`, and popularity only reacts to `disease_outbreak`, not raw health) — but it
  reads alarmingly and "makes no sense" to a new player. Fix next iter: don't apply the malnutrition
  penalty before the settlement is established (e.g. gate on having a granary / >N population /
  buildings), or raise base health, or give a tiny passive sanitation floor for a small village.

### Backlog / findings for later iterations (not yet done)
- **[UX] Health 25 from day 1** (see NEW finding above) — top candidate for next iteration.
- **[GAMEPLAY] Tribute is unpayable early.** First Ashen demand (day 14) asks for ale the player
  can't have yet (0 ale, brewery not built). Either defer the first demand to the end of the
  King's Peace, scale it to what the player can actually pay, or let "Accept" pay partially. Needs
  TestPhase6 test-9 update if timing changes.
- **[FICTION] 50 population vs 8 visible villagers** is a mismatch — the food sim charges for 50
  mouths but only 8 pawns exist. Consider a smaller, growing start (~20) or spawn pawns to match.
- **[UX] Build menu discoverability.** Hall is hidden under the Civic tab while the menu defaults to
  Food; a brand-new player won't know to build a Hall first. Consider defaulting to Civic on a
  fresh game, or a glowing "Build your Hall here" affordance.
- **[UX] Speed/þause clarity, and a visible Day/clock + objective tracker.** A persistent
  "current objective" line would make the first 5 minutes legible.
- **[CONTENT] Long-term goals.** Beyond survival, what pulls a player through 20 minutes? Milestones,
  population/prestige tiers, escalating threats with telegraphing. To be fleshed out.
- Re-verify the food economy holds for the *full* 100 days (population growth raises demand).
