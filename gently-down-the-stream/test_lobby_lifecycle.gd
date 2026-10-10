extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var manager = root.get_node("NetworkManager")
	for attempt in range(2):
		var lobby = load("res://networking/Lobby.tscn").instantiate()
		root.add_child(lobby)
		await process_frame
		assert(manager.host_game("Lifecycle host", 18913) == OK)
		lobby._update_room_ui()
		manager.disconnect_game()
		root.remove_child(lobby)
		assert(not manager.player_list_updated.is_connected(lobby._update_room_ui), "Old lobby must unsubscribe before rejoining")
		manager.player_list_updated.emit()
		lobby._update_room_ui()
		lobby.free()
	print("PASS: leaving, detached lobby updates and hosting again")
	quit()
