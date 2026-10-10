extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var manager = root.get_node("NetworkManager")
	var server = "server" in OS.get_cmdline_user_args()
	if server:
		assert(manager.host_game("Host", 18912) == OK)
		manager.players[1]["seat"] = 0
		manager.active_game_scene = "res://river.tscn"
		var river = load("res://river.tscn").instantiate()
		root.add_child(river)
		current_scene = river
		for node in [river, river.boat, river.get_node("RiverWildlife"), river.get_node("RiverHazards")]:
			node.set_process(false)
			node.set_physics_process(false)
		river.boat.position = Vector3(2, 0.2, -780)
		river.boat_health = 73
		river.elapsed_time = 40
		river.get_node("RiverWildlife").clock = 40
		var times = river.get_node("RiverHazards").get_tree_activation_times()
		times[0] = 31.0
		river.get_node("RiverHazards").set_tree_activation_times(times)
	else:
		assert(manager.join_game("127.0.0.1", "Late guest", 18912) == OK)
	var deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if server and not manager.loaded_game_peers.is_empty():
			await create_timer(3.0).timeout
			print("PASS: server accepted late join and sent initial state")
			quit()
			return
		if not server and manager.local_game_loaded and current_scene != null:
			assert(current_scene.scene_file_path == "res://river.tscn", "Late guest must enter active game")
			assert(current_scene.boat.position.distance_to(Vector3(2, 0.2, -780)) < 0.1, "Late guest must receive boat position")
			assert(is_equal_approx(current_scene.boat_health, 73.0), "Late guest must receive hull health")
			assert(current_scene.get_node("RiverWildlife").clock >= 40.0, "Late guest must receive hazard clock")
			assert(is_equal_approx(float(current_scene.get_node("RiverHazards").trees[0].get_meta("triggered_at")), 31.0), "Late guest must receive fallen tree state")
			assert(manager.players[manager.multiplayer.get_unique_id()].seat == 1, "Late guest must get free seat")
			print("PASS: late guest loaded active scene, free seat, boat, health, clock and trees")
			quit()
			return
	push_error("Late join test timed out")
	quit(1)
