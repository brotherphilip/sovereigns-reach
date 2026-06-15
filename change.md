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
