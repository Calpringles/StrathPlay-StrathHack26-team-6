extends SceneTree

func _init():
	print("--- Running Complete Game & Lobby Test ---")
	
	# 1. Test Lobby
	print("1. Loading Lobby.tscn...")
	var lobby_scene = load("res://networking/Lobby.tscn")
	if lobby_scene == null:
		print("FAILED: Cannot load Lobby.tscn")
		quit(1)
		return
	var lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	await process_frame
	print("Lobby loaded successfully.")
	
	# Simulate entering room panel & cycling customizations
	lobby.get_node("CenterContainer/ConnectPanel").visible = false
	lobby.get_node("CenterContainer/RoomPanel").visible = true
	lobby._on_randomize_pressed()
	print("Lobby customization randomized successfully. Data: ", lobby.current_customization)
	
	# 2. Test River & Boat
	print("2. Loading river.tscn...")
	var river_scene = load("res://river.tscn")
	if river_scene == null:
		print("FAILED: Cannot load river.tscn")
		quit(1)
		return
	var river = river_scene.instantiate()
	root.add_child(river)
	await process_frame
	
	var boat = river.get_node("Boat")
	if boat == null:
		print("FAILED: Boat not in river.tscn")
		quit(1)
		return
		
	var hull = boat.get_node("BoatVisual/HullMesh")
	print("Boat hull found. Rotation: ", hull.rotation_degrees, " Scale: ", hull.scale)
	print("Rowers count: ", boat.rowers.size())
	
	# Test stroke
	boat.row_oar(0, false)
	boat.row_oar(1, false)
	print("Oar strokes triggered successfully.")
	
	for i in range(10):
		await process_frame
		
	print("--- Complete Game & Lobby Test Passed! ---")
	quit(0)
