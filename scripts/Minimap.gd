extends Control

# Minimap control for city scenes
# This script creates an interactive minimap that shows the player's position
# and allows for navigation by clicking on the minimap

@export var map_size: Vector2 = Vector2(200, 200)
@export var player_icon: Texture2D
@export var map_background: Texture2D

# References to the main scene elements
var player: Node2D
var camera: Camera2D
var map_container: Control
var player_marker: TextureRect

# Map data
var map_scale: float = 1.0
var map_offset: Vector2 = Vector2.ZERO

func _ready():
	# Set up the minimap UI
	setup_minimap()
	
	# Connect to scene signals if needed
	if get_parent() is Node2D:
		# Try to find player and camera in the scene
		find_scene_elements()

func setup_minimap():
	# Create the minimap container
	map_container = Control.new()
	map_container.size = map_size
	map_container.position = Vector2(20, 20)
	map_container.name = "MinimapContainer"
	
	# Create background
	var background = TextureRect.new()
	background.texture = map_background
	background.size = map_size
	background.position = Vector2.ZERO
	background.name = "MinimapBackground"
	
	# Create player marker
	player_marker = TextureRect.new()
	player_marker.texture = player_icon
	player_marker.size = Vector2(10, 10)
	player_marker.position = Vector2(0, 0)
	player_marker.name = "PlayerMarker"
	
	# Add to container
	map_container.add_child(background)
	map_container.add_child(player_marker)
	
	# Add to scene
	add_child(map_container)
	
	# Make it interactive
	map_container.mouse_filter = Control.MOUSE_FILTER_STOP
	map_container.connect("gui_input", Callable(self, "_on_minimap_gui_input"))

func find_scene_elements():
	# Try to find player and camera in the scene
	if get_parent().has_node("Player"):
		player = get_parent().get_node("Player")
	elif get_parent().has_node("player"):
		player = get_parent().get_node("player")
	
	if get_parent().has_node("Camera2D"):
		camera = get_parent().get_node("Camera2D")
	elif get_parent().has_node("camera"):
		camera = get_parent().get_node("camera")

func _process(delta):
	# Update player position on minimap
	update_player_position()

func update_player_position():
	if player and player_marker:
		# Get player position in world coordinates
		var player_pos = player.global_position
		
		# Convert world position to minimap coordinates
		# This is a simplified version - in a real implementation,
		# you'd need to know the map bounds and scale
		var minimap_pos = convert_world_to_minimap(player_pos)
		player_marker.position = minimap_pos

func convert_world_to_minimap(world_pos: Vector2) -> Vector2:
	# This is a placeholder - in a real implementation, you'd need to:
	# 1. Know the bounds of your city map
	# 2. Scale world coordinates to minimap coordinates
	# 3. Handle offset and scaling properly
	
	# For now, we'll just return a proportional position
	# This would need to be customized for your specific map
	var map_bounds = Vector2(1000, 1000)  # Example bounds
	var scale = map_size.x / map_bounds.x
	
	var minimap_x = world_pos.x * scale
	var minimap_y = world_pos.y * scale
	
	# Adjust for centering
	minimap_x -= map_size.x / 2
	minimap_y -= map_size.y / 2
	
	return Vector2(minimap_x, minimap_y)

func _on_minimap_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Convert click position to world coordinates
			var click_pos = event.position
			var world_pos = convert_minimap_to_world(click_pos)
			
			# Move player to clicked position
			if player:
				player.global_position = world_pos

func convert_minimap_to_world(minimap_pos: Vector2) -> Vector2:
	# Convert minimap click position to world coordinates
	# This is a simplified version - in a real implementation,
	# you'd need to know the actual map bounds and scale
	var map_bounds = Vector2(1000, 1000)  # Example bounds
	var scale = map_bounds.x / map_size.x
	
	var world_x = minimap_pos.x * scale
	var world_y = minimap_pos.y * scale
	
	# Adjust for offset (this would need to be more sophisticated)
	world_x += map_bounds.x / 2
	world_y += map_bounds.y / 2
	
	return Vector2(world_x, world_y)
