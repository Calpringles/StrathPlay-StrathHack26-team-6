extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var river = load("res://river.tscn").instantiate()
	root.add_child(river)
	await process_frame
	river.set_process(false)
	river.set_physics_process(false)
	var boat = river.get_node("Boat")
	boat.set_physics_process(false)
	var chase = river.get_node("RiverChase")
	chase.set_physics_process(false)
	chase.set_process(false)
	chase.clock = 0.0
	assert(chase.crocodiles.size() == 9, "Crocodile asset must load")
	assert(boat.current_speed > 0.0, "Current must be enabled")
	assert(river.camera.position.is_equal_approx(Vector3(0, 3.5, 5.2)), "Close camera must be restored")
	assert(chase.find_children("*", "SubViewport", true, false).is_empty(), "Rear-view camera must be removed")
	assert(chase.fish_schools.size() == 7, "Fish schools must load")
	chase._physics_process(600.0)
	assert(river.game_state == 0, "There must be no flood deadline")
	assert(is_zero_approx(chase.water.position.y), "Water must stay at its original level")
	assert(is_equal_approx(boat.current_speed, 0.8), "Current must stay steady")
	chase._process(0.0)
	assert(chase.warning_panel.get_child_count() == 1, "Only the asset credit should remain in the former countdown panel")
	var school = chase.fish_schools[0]
	var school_x = school.position.x
	chase.clock += 2.0
	chase._update_fish_shadows()
	assert(not is_equal_approx(school.position.x, school_x), "Fish must move across the water")
	var croc = chase.crocodiles[0]
	boat.position = Vector3(0, 0.2, -85)
	boat.velocity = Vector3(0, 0, -5)
	croc.set_meta("activated_at", chase.clock - (PI / 2.0) * chase.CROCODILE_PATROL_WIDTH / chase.crocodile_speed)
	chase._update_crocodiles(true)
	assert(is_equal_approx(river.boat_health, 88.0), "Crocodile collision must damage hull")
	assert(boat.velocity.length() < 5.0, "Crocodile collision must slow boat")
	chase._update_crocodiles(true)
	assert(is_equal_approx(river.boat_health, 88.0), "One crossing must not repeatedly damage hull")
	var half_crossing = (PI / 2.0) * chase.CROCODILE_PATROL_WIDTH / chase.crocodile_speed
	chase.clock += half_crossing
	chase._update_crocodiles(true)
	assert(croc.visible and is_equal_approx(croc.position.x, chase.CROCODILE_PATROL_WIDTH), "Crocodile must stay visible at the bank")
	chase.clock += half_crossing
	chase._update_crocodiles(true)
	assert(croc.visible and absf(croc.position.x) < 0.01, "Crocodile must swim back across the river")
	assert(is_equal_approx(river.boat_health, 76.0), "Returning crocodile may damage the boat after separating")
	chase.clock += 20.0 * PI * chase.CROCODILE_PATROL_WIDTH / chase.crocodile_speed
	chase._update_crocodiles(false)
	assert(croc.visible and absf(croc.position.x) <= chase.CROCODILE_PATROL_WIDTH, "Patrol must continue after many crossings")
	river._apply_damage(100.0, "Test collision")
	assert(river.game_state == river.GameState.SUNK, "Hull damage must still sink boat")
	var y = boat.position.y
	chase._physics_process(1.0)
	assert(boat.position.y < y, "Sunk boat must descend into water")
	boat._physics_process(0.1)
	assert(boat.velocity == Vector3.ZERO, "Game over must stop rowing physics")
	river.game_state = river.GameState.PLAYING
	chase._sync_chase(30.0, 76.0, river.GameState.WON, [20.0])
	assert(river.game_state == river.GameState.WON and river.victory_panel.visible, "Host snapshot must reproduce victory")
	assert(is_equal_approx(river.boat_health, 76.0), "Host snapshot must reproduce hull damage")
	assert(is_equal_approx(float(croc.get_meta("activated_at")), 20.0), "Host snapshot must reproduce crossing timing")
	assert(river.victory_title.text == "Congratulations!", "Victory banner must use the requested title")
	assert(river.victory_title.get_theme_font_size("font_size") >= 54, "Victory title must be larger")
	assert(river.get_node("FinishWaterfall") != null, "Finish must have a waterfall")
	assert(not chase.warning_panel.visible, "Chase warnings must disappear during celebration")
	river._update_victory_ending(3.0)
	assert(is_equal_approx(boat.position.z, river.WATERFALL_Z), "Boat must reach the waterfall lip before dropping")
	assert(boat.position.y > 0.0, "Boat must remain afloat before the drop")
	river._update_victory_ending(1.0)
	assert(boat.position.y < -3.0, "Boat must descend over the waterfall")
	river._update_victory_ending(5.0)
	assert(is_equal_approx(boat.position.y, -17.8), "Boat must land at the lower pool")
	assert(river.game_state == river.GameState.WON, "Waterfall ending must preserve the win")
	assert(river.camera.is_set_as_top_level(), "Ending camera must not tumble with boat")
	# Reaching the finish must still win after the previous time limit.
	var second_river = load("res://river.tscn").instantiate()
	root.add_child(second_river)
	var second_chase = second_river.get_node("RiverChase")
	second_chase.clock = 600.0
	second_river.boat.position.z = -second_river.RIVER_LENGTH
	second_chase._physics_process(1.0)
	assert(second_river.game_state == second_river.GameState.WON, "Reaching safety must win without a deadline")
	print("PASS: calm water, no flood deadline, fish movement, repeated crocodile patrols and collisions, snapshots and waterfall victory")
	quit(0)
