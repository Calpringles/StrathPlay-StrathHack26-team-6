extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var river = load("res://river.tscn").instantiate()
	root.add_child(river)
	await process_frame
	var boat = river.boat
	var wildlife = river.get_node("RiverWildlife")
	var hazards = river.get_node("RiverHazards")
	for node in [river, boat, wildlife, hazards]:
		node.set_process(false)
		node.set_physics_process(false)
	wildlife.clock = 0.0
	assert(hazards.trees.size() == 12 and hazards.trees.back().position.z <= -950.0, "Trees must span the full course")
	assert(hazards.whirlpools.size() == 9, "Whirlpools must span the course")
	var whirl_start = hazards.whirlpools[0].position
	wildlife.clock = 8.0
	hazards.update_whirlpools()
	assert(not hazards.whirlpools[0].position.is_equal_approx(whirl_start), "Whirlpools must move")
	wildlife.clock = 0.0
	hazards.update_whirlpools()
	assert(hazards.get_node_or_null("FinaleBuoy0_-1") == null, "Finale must have no yellow buoys")
	var corridor_rocks = 0
	var rock_assets = {}
	for obstacle in river.get_node("Obstacles").get_children():
		if obstacle.has_meta("corridor_centre"):
			corridor_rocks += 1
			var inner_edge = absf(obstacle.position.x - float(obstacle.get_meta("corridor_centre"))) - float(obstacle.get_meta("rock_width")) / 2.0
			assert(inner_edge >= 4.19, "Rock walls must leave eight metres of clear water")
			rock_assets[obstacle.get_meta("rock_asset")] = true
			var visible_bounds: AABB = wildlife._mesh_bounds(obstacle.get_child(0))
			assert(visible_bounds.size.x <= float(obstacle.get_meta("rock_width")) + 0.01, "Visible rock must fit the clear passage")
	assert(corridor_rocks >= 90, "Finale must have rocks along both sides of the passage")
	assert(rock_assets.size() >= 5, "Finale must use varied scenery models")
	river._create_finish_firework(1)
	assert(river.get_node("FinishFirework").emitting, "Finish celebration must emit fireworks")
	river._show_notification("Test warning", Color.RED, 2.0)
	assert(not river.notification_banner.visible, "Gameplay text warnings must stay hidden")
	var environment = river.get_node("WorldEnvironment").environment
	assert(is_zero_approx(environment.fog_sky_affect), "Fog must not wash out the sky")
	assert(environment.sky.sky_material.shader.resource_path.ends_with("SourceCode/shader/main.gdshader"), "Sky must use the imported cloud package")
	assert(environment.sky.sky_material.get_shader_parameter("cloud_tex_01") != null, "Cloud textures must be assigned")
	var tree = hazards.trees[0]
	var scenery_tree = tree.get_node("FallingTree0/SceneryTree")
	assert(scenery_tree.scene_file_path.ends_with(".fbx"), "Falling trees must use scenery models")
	var tree_bounds = wildlife._mesh_bounds(scenery_tree)
	assert(is_equal_approx(tree_bounds.size.y, hazards.TREE_LENGTH), "Scenery tree must match falling collider height")
	assert(absf(tree_bounds.position.y) < 0.001, "Falling tree must pivot at its base")
	boat.position = Vector3(-6.0, 0.2, tree.position.z + 20.0)
	boat.velocity = Vector3(0, 0, -4)
	hazards.update_trees(true)
	assert(is_equal_approx(float(tree.get_meta("triggered_at")), 0.0), "Approaching tree must trigger warning")
	assert(tree.get_node_or_null("Warning") == null, "Tree must not display warning text")
	assert(absf(tree.get_node("FallingTree0").rotation.z) < 0.1, "Warning must precede the fall")
	wildlife.clock = hazards.TREE_WARNING + hazards.TREE_FALL_TIME
	hazards.update_trees(true)
	assert(is_equal_approx(absf(tree.get_node("FallingTree0").rotation.z), PI / 2.0), "Tree must fall across river")
	assert(river.boat_health == 100.0, "Clear lane must avoid damage")
	var times = hazards.get_tree_activation_times()
	times[1] = 2.0
	wildlife._sync_game_state(wildlife.clock, 100.0, river.GameState.PLAYING, [], 0.0, 0.0, times)
	assert(is_equal_approx(float(hazards.trees[1].get_meta("triggered_at")), 2.0), "Snapshots must reproduce tree timing")
	var second_tree = hazards.trees[1]
	boat.position = Vector3(0, 0.2, second_tree.position.z)
	wildlife.clock = 2.0 + hazards.TREE_WARNING + hazards.TREE_FALL_TIME * 0.95
	river.damage_cooldown = 0.0
	hazards.update_trees(true)
	assert(is_equal_approx(river.boat_health, 82.0), "Falling tree must damage a boat in its path")
	hazards.update_whirlpools()
	var whirl = hazards.whirlpools[0]
	boat.position = whirl.position + Vector3(1.0, 0.2, 0)
	boat.velocity = Vector3.ZERO
	boat.turn_speed = 0.0
	hazards.apply_whirlpool_forces(0.2)
	assert(boat.velocity.x < 0.0 and absf(boat.velocity.z) > 0.0, "Whirlpool must pull inward and around its centre")
	assert(absf(boat.turn_speed) > 0.0, "Whirlpool must turn boat")
	assert(hazards.get_turbulence_at(boat.position) > 0.0, "Whirlpool must rock nearby boat")
	boat.position = Vector3(0, 0.2, -10)
	boat.velocity = Vector3(0, 0, -3)
	var clear_velocity = boat.velocity
	hazards.apply_whirlpool_forces(0.2)
	assert(boat.velocity == clear_velocity and is_zero_approx(hazards.get_turbulence_at(boat.position)), "Clear water must have no whirlpool effects")
	river.boat_health = 100.0
	hazards.update_leaks()
	assert(not hazards.leak_nodes[0].visible and not hazards.bilge.visible, "Healthy hull must be dry")
	river.boat_health = 80.0
	hazards.update_leaks()
	assert(hazards.leak_nodes[0].visible and not hazards.leak_nodes[1].visible, "Light damage must show first leak")
	assert(hazards.leak_nodes[0].position.y > hazards.HULL_FLOOR_Y, "Cracks must be visible on the interior floor")
	assert(absf(hazards.leak_nodes[0].position.x) < 0.5, "Cracks must be inside the boat")
	assert(hazards.bilge.position.y > hazards.HULL_FLOOR_Y, "Water must pool above the floor at rower feet")
	assert(boat.get_node_or_null("Wood_BoatV1") == null, "Duplicate legacy hull must not hide floor damage")
	river.boat_health = 15.0
	hazards.update_leaks()
	assert(hazards.leak_nodes[3].visible and hazards.bilge.visible, "Heavy damage must show more leaks and pooled water")
	wildlife.clock = 6.5
	hazards.update_jumping_fish()
	assert(hazards.jumping_fish[0].visible and hazards.jumping_fish[0].position.y > 0.5, "Fish must jump above surface")
	wildlife.clock = 9.0
	hazards.update_jumping_fish()
	assert(not hazards.jumping_fish[0].visible, "Fish must return underwater")
	wildlife.clock = 23.2
	hazards.update_jumping_fish()
	assert(hazards.jumping_fish[0].visible, "Fish jumps must repeat occasionally")
	river.boat_health = 100.0
	var object = Node3D.new()
	river.add_child(object)
	assert(river.apply_object_damage(object, 15.0, "Test rock"), "First object hit must apply its original damage")
	assert(is_equal_approx(river.boat_health, 85.0), "Rock damage must remain 15 points")
	assert(not river.apply_object_damage(object, 15.0, "Test rock"), "Repeated contact with same object must be ignored")
	assert(is_equal_approx(river.boat_health, 85.0), "Repeated contact must not drain health")
	var other_object = Node3D.new()
	river.add_child(other_object)
	assert(river.apply_object_damage(other_object, 10.0, "Test log"), "Different object must still penalise boat")
	assert(is_equal_approx(river.boat_health, 75.0), "Log damage must remain 10 points")
	river.elapsed_time += 1.99
	assert(not river.apply_object_damage(object, 15.0, "Test rock"), "Same object must wait the full two seconds")
	river.elapsed_time += 0.02
	assert(river.apply_object_damage(object, 15.0, "Test rock"), "Same object must damage again after two seconds")
	assert(is_equal_approx(river.boat_health, 60.0), "Repeated damage must preserve original amount")
	assert(not river.apply_object_damage(object, 15.0, "Test rock"), "Cooldown must restart after each damage tick")
	print("PASS: course-wide trees, warning and fall timing, clear lane, tree damage, snapshots, local whirlpool forces, leak stages and occasional fish jumps")
	quit(0)
