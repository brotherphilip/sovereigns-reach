Tier 0 — "This looks broken" (cheap to fix, worst first-impression damage)

  These read as bugs/unfinished code leaking to the player. Fix these before anything cosmetic.

  ┌─────┬─────────────┬──────────────────────────────────────────────────┬──────────────────────────────────┐
  │  #  │    Where    │                What a player sees                │               Fix                │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤
  │ 1   │ w9 event    │ Literal DEBUG: simulation at x20 speed. printed  │ Gate behind a debug flag; never  │ 
  │     │ log         │ in the player-facing feed                        │ log to the player feed           │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤
  │     │ w3,w4,w5    │ Lock reasons are raw snake_case: needs           │ Map IDs → human strings          │ 
  │ 2   │ build bar   │ advanced_masonry, needs transport_logist…, needs │ ("Requires Advanced Masonry")    │ 
  │     │             │  crop_tiers                                      │                                  │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤
  │ 3   │ w9 top bar  │ Header says "Night" but the scene is full bright │ Sync the day/night tint to the   │ 
  │     │             │  daylight — label contradicts the render         │ clock (or the label)             │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤
  │ 4   │ w2 names    │ "Ironpeak 2", "Frostgate 2", "Fenwallow 2" — and │ De-duplicate the name generator; │ 
  │     │             │  both a "Frostgate" seat and a "Frostgate 2"     │  never emit  2 suffixes          │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤ 
  │     │             │ Every villager holds a flat grey square in front │ Fix/remove the held-item sprite  │
  │ 5   │ w8 citizens │  of their face — reads as a missing-texture      │ (it's hiding the head)           │ 
  │     │             │ error                                            │                                  │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤
  │ 6   │ w5          │ Construction label reads 0% · 0/8 mist — "mist"  │ Fix the string (timber/mortar?)  │ 
  │     │ footprint   │ is a truncated/typo'd resource word              │ and the truncation               │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤ 
  │     │             │ Strings clipped mid-sentence: tutorial body      │ Widen panels / wrap text; no     │
  │ 7   │ w3 / w6     │ "…building, growth, defense and" and toast "Too  │ string should end on a dangling  │ 
  │     │             │ close to another building —"                     │ word/dash                        │ 
  ├─────┼─────────────┼──────────────────────────────────────────────────┼──────────────────────────────────┤
  │     │             │ A giant pure-black triangle fills the            │ Fill off-map with a styled       │
  │ 8   │ w10         │ bottom-right (off-map void) with a hard aliased  │ border/fog, not black            │
  │     │             │ seam — reads as a render bug                     │                                  │
  └─────┴─────────────┴──────────────────────────────────────────────────┴──────────────────────────────────┘

  ---
  Tier 1 — Biggest aesthetic problems (the game looks unfinished)

  1. Buildings are flat untextured shapes (w5, w6, w7, w8, w9, w10 — the single most-cited theme)
  Every structure is a flat colored diamond/prism: the hall is a plain red roof-plane with no walls, hovels are
  grey boxes, the Keep is a translucent ghost. No tiles, thatch, planks, doors, trim, or shadow grounding them —
  they decal onto the grass with a hard seam. Your painted-building-sprite track isn't showing in any of these
  shots. This is what makes it read as programmer-art. Prioritize getting real building art (and contact shadows)
  into the common buildings.

  2. Empty, lifeless fields (w3–w10)
  ~70–80% of every gameplay screen is one flat speckled-green carpet — no paths, dirt, tufts, rocks, elevation,
  or color zones. Nothing happens in it: no animals, no carts, no birds, barely any peasants. The wildlife system
  you built (deer/boar/fox/rabbit) is invisible here — spawn it into view. Add worn paths between buildings,
  ground variation, and ambient props/critters.

  3. Cloned everything (w3, w4, w8, w9, w10)
  Every tree is the identical lollipop sprite in grid-ish clumps; citizens are near-identical pawns standing in a
  blob; w5's lanterns are stamped clones. Add size/species/rotation/tint variation to trees and pawn idle
  variety.

  4. Night is unreadably dark (w6, w7) — flagged "hate" by multiple critics
  At night the whole field crushes to muddy near-black: you can't tell roof from ground, and citizens vanish 
  entirely (no rim light). The "lights" are flat radial-gradient circles that look like Photoshop glow brushes —
  no flicker, no warm core, no cast light. Lift the night floor (deeper blue ambient, not brown murk), add
  rim-light to pawns/buildings, and shape the torch glow.

  5. Flat blocky water (w3–w10) — the lake is a solid-blue blob with a hard pixelated edge; the w9/w10 river is a
  stair-stepped ribbon. No shoreline, depth, or motion. Soften edges, add a shoreline transition and gentle
  animated ripple.

  6. World map is a muddy blur (w2) — an out-of-focus olive smear with no legible coastlines/mountains/forests;
  the only high-contrast things are harsh aliased faction borders that "scream." Town labels have no backing
  plate and smear into the noise. Give it real readable terrain and soften/anti-alias the borders.

  7. Placement ghosts look like editor gizmos (w5) — footprints are flat diamonds with red dashed outlines +
  slanted in-world text + white ^ scribbles for orchard trees. Reads as a debug overlay. Use a proper translucent
  building preview with a clean tint and upright label.

  ---
  Tier 2 — UX friction & screen clutter

  - Unlabeled resource bar (w3–w8) — seven bare numbers (120 60 15 0 75/500 …) with tiny icons, no labels, no
  visible tooltips, several reading 0 like placeholders. Add labels/tooltips.
  - "Nothing selected" dead panel (w3–w10) — a large dark inspector is docked bottom-right in every screenshot
  showing nothing. Collapse it when empty, or fill it with a default summary.
  - Weather-log spam (w6, w7, w9, w10) — the feed is Weather: Clear / Weather: Clear / Weather: Clear. The one
  information channel is pure noise. Only log weather changes, and dedupe repeats.
  - Duplicated season readout (w3–w7) — "Day · Spring" chip sits right next to "Spring · Clear". The word Spring
  appears twice, back to back. Merge them.
  - World-map hint pile-up (w2) — four overlapping semi-transparent instruction banners, repeating "click your
  village to enter & rule it" in three places. Consolidate into one dismissible hint.
  - Cryptic build costs (w3, w5) — 20wd 10g, 6wd 4st with no spacing and unexplained units. Space them and use
  clear icons/units.
  - Main-menu "Difficulty: Normal" (w1) — a value-cycling toggle styled identically to New Game/Load/Quit,
  sitting below Quit. Move difficulty into New Game flow or make it a visibly different selector.
  - Mixed resolution (w2–w7 are soft/blurry vs crisp w1/w8) — capture/render the city + world views at full res;
  the softness alone makes it look cheap.
  - Spectator mode (w8–w10) — only context is one thin centered line; the ✕ 0 garrison glyph looks like a close
  button, and there's no visible "stop spectating / claim city" control.

  ---
  Tier 3 — Boredom / lifelessness

  - w9 ≈ w10 are near-identical frames — same hamlet, same buildings, same tree cluster; the only delta is the
  weather-log text. Spectating an AI town shows a static diorama. Add visible activity (workers moving, smoke,
  construction progress).
  - Population looks deserted — a handful of tiny pawns clustered in one spot; a "kingdom-builder" with no
  visible crowd.
  - Towns have no identity — every settlement (player, Farrow, Azure Dominion) is the same few hut/hall shapes on
  flat green with a road stub. No walls, town square, market stalls, or faction/cultural variation.
  - Orchards/farms read as empty selection rectangles (w5, w7) — flat tan parallelograms with sparse white
  sprout-marks; no rows, growth stages, or harvest life.

  ---
  Tier 4 — Title screen (w1)

  Polished enough to ship, but several "cheap" tells: the title is plain gold text with no logo/crest; the
  firework is a symmetric wireframe ring that looks like a debug spinner/loading gizmo; lanterns are ~12 crude 
  cloned sprites (a brown circle with a tan square — barely reads as a lantern) despite the "festival of
  lanterns" caption; the campfire is pixelated and style-mismatched; v2.0 is clipped into the corner over the
  border; the full-screen gold border duplicates the panel's outline; buttons have no hierarchy or icons (New
  Game looks identical to Quit). Give the title a crest/treatment, animate + vary the lanterns, replace the
  firework, and make New Game the dominant button.

  ---
  The 8 highest-ROI quick wins

  1. Kill the DEBUG: log line (#1) and the snake_case lock strings (#2).
  2. Dedupe weather-log spam → log changes only.
  3. Fix the "Night" label vs daylight contradiction (#3).
  4. Strip the  2 name suffixes (#4).
  5. Fix the grey-square-on-face citizen sprite (#5).
  6. Collapse the empty "Nothing selected" panel.
  7. Lift the night floor + add pawn rim-light so you can see at night.
  8. Label the resource bar.
