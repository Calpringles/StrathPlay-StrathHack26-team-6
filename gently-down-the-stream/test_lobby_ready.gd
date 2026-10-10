extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var manager = root.get_node("NetworkManager")
	manager.players = {1: {"name": "Host", "seat": 0}}
	assert(manager.can_start_game(), "Host must not need to ready up")
	manager.players[2] = {"name": "Guest", "seat": 1, "ready": false}
	assert(not manager.can_start_game(), "Unready guest must block start")
	manager.start_game("res://river.tscn")
	assert(current_scene == null, "Server must enforce ready gate even outside the UI")
	manager.players[2]["ready"] = true
	assert(manager.can_start_game(), "Ready guest must allow start")
	manager.players[3] = {"name": "New guest", "seat": -1, "ready": false}
	assert(not manager.can_start_game(), "New guest must block start")
	manager.players.erase(3)
	assert(manager.can_start_game(), "Departed guest must stop blocking start")
	manager.players[2]["ready"] = false
	assert(not manager.can_start_game(), "Unready toggle must block start again")
	manager.players.clear()
	var lobby = load("res://networking/Lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	assert(lobby.ready_button != null, "Ready button must be present")
	print("PASS: host exemption, ready gate, new joins, departures, unready and lobby loading")
	quit()
