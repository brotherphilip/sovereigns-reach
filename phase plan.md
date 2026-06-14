# Phase Plan — Sovereign's Reach Polish Cycle
## Created: 2026-06-13 | Iteration 1
## Focus: Polish and flesh out existing systems. No new systems.

---

## Phase 1 — Visual Feedback & Interaction Polish
**Goal:** Give every player action clear, immediate visual confirmation.
**Player feels:** My actions feel responsive and satisfying — the world reacts to what I do.
**Sub-tasks:**
- ✓ Add animated building placement preview ghost in BuildingLayer.gd
- ✓ Add tile highlight on hover during build mode (IsometricGrid.gd)
- ✓ Add hover highlight for buildable vs non-buildable tiles with color coding (IsometricGrid.gd)
- ✓ Animate the unit selection ring (pulse or glow) in UnitLayer.gd
- ✓ Add cursor shape changes for different interaction modes (PlayerInputHandler.gd)
- ✓ Add visual alert indicator when a resource is critically low (HUDController.gd → HUDNode.gd)
**Status:** Complete

---

## Phase 2 — HUD Clarity & Readability
**Goal:** Make every HUD panel communicate at a glance without clutter.
**Player feels:** I always know my situation — numbers tell a story, not just a value.
**Sub-tasks:**
- ✓ Add tooltips to all HUD buttons (HUDNode.gd)
- ✓ Show min/max tick-marks and a delta indicator (+/-) on rations and tax sliders (HUDNode.gd)
- ✓ Add color-coded status tinting to Popularity gauge (red → green by tier) (HUDNode.gd)
- ✓ Add brief gold-change flash animation (+N / -N) when gold changes (HUDNode.gd)
- ✓ Enhance NotificationFeed.gd with smooth fade-out animation on old entries
- ✓ Show food variety bonus visibly in the rations area (HUDController.gd)
- ✓ Add market price trend arrows (up/down) to the resource trade panel (HUDNode.gd)
**Status:** Complete

---

## Phase 3 — Building & Unit State Readability
**Goal:** Make the state of buildings and units immediately readable without selecting them.
**Player feels:** I can see at a glance which buildings are working, idle, damaged, or burning.
**Sub-tasks:**
- ✓ Improve HP bar color gradient (green → yellow → red) for buildings (BuildingLayer.gd)
- ✓ Improve HP bar color gradient for units (UnitLayer.gd)
- ✓ Add visible idle indicator (dim tint) for unstaffed buildings (BuildingLayer.gd)
- ✓ Add floating alert icon above buildings that run out of workers (BuildingLayer.gd)
- ✓ Add unit morale indicator (shield icon or colour tint) when morale is low (UnitLayer.gd)
- ✓ Enhance fire visual effect on burning buildings with animated flicker (BuildingLayer.gd)
- ✓ Show unit type icon in the selection panel when a unit is selected (HUDNode.gd)
**Status:** Complete

---

## Phase 4 — Combat Feedback Polish
**Goal:** Make combat feel weighty and readable — hits, deaths, and morale all visible.
**Player feels:** Combat is tense and legible; I feel the impact of every exchange.
**Sub-tasks:**
- ✓ Add combat damage number popups that float and fade above struck units (UnitLayer.gd)
- ✓ Add a brief hit-flash tint on units when they take damage (UnitLayer.gd)
- ✓ Add a death animation / collapse effect on unit death (UnitLayer.gd)
- ✓ Add combat audio cues for attack, hit, and death events (AudioManager.gd — add new SoundEvents)
- ✓ Improve AI targeting behaviour: prefer damaged units over fresh ones (AIFaction.gd)
- ✓ Add army route lines from AI faction capitals to siege targets on macro map (MacroMapView.gd)
**Status:** Complete

---

## Phase 5 — Economy Transparency
**Goal:** Make the economy legible — the player should understand why their gold and popularity change.
**Player feels:** Economic cause-and-effect is clear; I can trace why I'm winning or losing.
**Sub-tasks:**
- ✓ Show per-tick gold income/expense breakdown on hover (HUDController.gd + HUDNode.gd)
- ✓ Add starvation and disease alert banners with clear cause description (NotificationFeed.gd)
- ✓ Show current weather effect as an icon + modifier tooltip in the HUD weather area (HUDNode.gd)
- ✓ Clarify tax impact by showing tax-vs-popularity delta in the tax slider tooltip (HUDController.gd)
- ✓ Improve market panel: show price trend over last 5 days (MarketSystem.gd + HUDNode.gd)
- ✓ Add popularity breakdown tooltip showing each ΔF/ΔA/ΔR/T/E component (HUDNode.gd)
**Status:** Complete

---

## Phase 6 — Diplomacy & Faction Personality
**Goal:** Make AI factions feel distinct and diplomatic interactions feel meaningful.
**Player feels:** Each faction has a personality — tribute demands feel like character moments, not pop-ups.
**Sub-tasks:**
- ✓ Add faction-specific dialogue variations for tribute demands by archetype (DiplomacyPanel.gd + GameState.gd)
- ✓ Show diplomatic relationship history (last 3 interactions) in DiplomacyPanel.gd
- ✓ Add faction threat level bar to the diplomacy panel (DiplomacyPanel.gd)
- ✓ Highlight hostile factions on macro map with a red border or pulse (MacroMapView.gd)
- ✓ Add tribute refusal consequence message that names the faction and what it will do (DiplomacyPanel.gd)
- ✓ Show active tribute agreements in the diplomacy panel (DiplomacyPanel.gd)
**Status:** Complete

---

## Phase 7 — Macro Map Navigation & Polish
**Goal:** Make the strategic world map informative and pleasant to navigate.
**Player feels:** The macro map gives me a clear strategic picture at a glance.
**Sub-tasks:**
- ✓ Add faction legend to the macro map showing archetype name + colour (MacroMapView.gd)
- ✓ Add smooth camera transition (fade) when switching from world map to city view (WorldMapScene.gd)
- ✓ Show shire ownership change animations when territory is captured (MacroMapView.gd)
- ✓ Add player shire count and army size summary to the macro map top bar (MacroMapView.gd)
- ✓ Show city economic level as icon size variation on world map (WorldMapView.gd — tier-based scaling already in place via _draw_castle_icon)
- ✓ Add "Return to last city" quick button visible from world map (WorldMapScene.gd)
**Status:** Complete

---

## Phase 8 — Save/Load & Startup Polish
**Goal:** Make the save/load experience and game startup feel complete and trustworthy.
**Player feels:** Starting and returning to the game feels professional and welcoming.
**Sub-tasks:**
- ✓ Add save slot metadata display: date, playtime, shire count, difficulty (MainMenuScene.gd + SaveManager.gd)
- ✓ Add auto-save on exit with clear confirmation message (GameBootstrap.gd + SaveManager.gd)
- ✓ Add loading progress indicator (WorldMapScene.gd — deferred show_loading panel before world gen)
- ✓ Add version number display to the main menu title screen (MainMenuScene.gd — updated to v2.0)
- ✓ Add a "Resume last save" quick button if a save exists (MainMenuScene.gd)
- ✓ Show difficulty level on the save slot display (MainMenuScene.gd — included in metadata display)
**Status:** Complete

---

## Phase 9 — Tutorial & Onboarding Improvement
**Goal:** Make the tutorial smarter, less intrusive, and easier for new players.
**Player feels:** The game teaches me what I need exactly when I need it.
**Sub-tasks:**
- ✓ Extend TutorialSystem.gd with new trigger conditions for market purchase, diplomacy (envoy), and edict activation
- ✓ Add a dismiss [×] button to all notifications (NotificationFeed.gd)
- ✓ Add a "skip tutorial" option at game start (GameBootstrap.gd — Yes/Skip overlay)
- ✓ Add tech tree tooltip hints explaining research benefits in plain language (TechTreePanelController.gd + HUDNode.gd)
- ✓ Add contextual edict hints when popularity is low or disease is active (TutorialSystem.gd)
- ✓ Track tutorial completion state in save data via GameState.world["tutorial_step"] (TutorialSystem.gd — auto-persisted in world dict)
**Status:** Complete

---

## Phase 10 — UI Consistency & Micro Polish
**Goal:** Ensure every interactive element looks and behaves consistently across the whole UI.
**Player feels:** The interface feels finished — nothing looks out of place or placeholder.
**Sub-tasks:**
- ✓ Harmonise font sizes: notification feed normalized to 12pt (was 15pt), consistent with the rest of HUD (NotificationFeed.gd)
- ✓ Add consistent hover highlight (blue-tinted StyleBox) to all buttons via _add_button (HUDNode.gd)
- ✓ Build-menu buttons show WHY they're disabled (requires tech X / cannot afford) in tooltip (HUDNode.gd)
- ✓ Tech tree and edict panels animate open (fade in 0.18s) and close (fade out 0.14s → hide) (HUDNode.gd)
- ✓ Recruit buttons show stats tooltip (Cost/HP/Atk) + disable reason when cannot recruit (HUDNode.gd)
- ✓ Main menu animated background: slowly rotating decorative sigil ring (MainMenuScene.gd — _MenuBG._process)
**Status:** Complete
