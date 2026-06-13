extends Node
# Tutorial system (autoload). Guides new players through the core loop with brief
# contextual hints surfaced via the HUD notification feed. Self-contained: it holds
# its own progress and watches EventBus.building_placed. A game session calls start().

signal tutorial_hint(message: String)

const STEP_PLACE_WOODCUTTER := 0
const STEP_PLACE_FARM := 1
const STEP_BUILD_GRANARY := 2
const STEP_DONE := 3

var step: int = STEP_DONE  # inert until a game session calls start()

func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)

func start() -> void:
	step = STEP_PLACE_WOODCUTTER
	tutorial_hint.emit("Welcome, my liege! Build a Woodcutter's Camp to gather wood.")

func _on_building_placed(_player_id: int, building_type: String, _grid_x: int, _grid_y: int, _building_id: int) -> void:
	match step:
		STEP_PLACE_WOODCUTTER:
			if building_type == "woodcutter_camp":
				step = STEP_PLACE_FARM
				tutorial_hint.emit("Good! Now build a Wheat Farm or Orchard to feed your peasants.")
		STEP_PLACE_FARM:
			if building_type in ["wheat_farm", "apple_orchard", "pig_farm", "dairy_farm"]:
				step = STEP_BUILD_GRANARY
				tutorial_hint.emit("Well done. Build a Granary to store food and raise your cap.")
		STEP_BUILD_GRANARY:
			if building_type == "granary":
				step = STEP_DONE
				tutorial_hint.emit("Tutorial complete — you know the basics. Rule well!")
