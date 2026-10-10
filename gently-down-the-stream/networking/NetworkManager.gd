# res://networking/NetworkManager.gd
extends Node

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 6

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal player_list_updated()
signal connection_ready()
signal connection_failed()
signal server_disconnected()

# Stores: { peer_id: { "name": String, "seat": int, "customization": Dictionary } }
# Seat mapping: -1 = Unassigned, 0 = Front-Left, 1 = Front-Right, 2 = Mid-Left, 3 = Mid-Right, 4 = Back-Left, 5 = Back-Right
var players: Dictionary = {}
var local_player_name: String = "Player"
var local_customization: Dictionary = {}

var peer: ENetMultiplayerPeer
var active_game_scene: String = ""
var loaded_game_peers: Dictionary = {}
var local_game_loaded: bool = false

func is_connection_ready() -> bool:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	var active_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return multiplayer.is_server() or active_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _ready() -> void:
	local_customization = CharacterCustomizer.get_default_customization(0)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- IP Helper for LAN / Same Network ---

func get_local_ip() -> String:
	# Prefer the adapter normally used for home/LAN play. Windows can return
	# VPN, Hyper-V, Docker, and loopback adapters before the real Wi-Fi address.
	var candidates: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address == "127.0.0.1" or address.begins_with("169.254."):
			continue
		# Common VirtualBox/VM host-only networks. These addresses are not
		# reachable by another computer on the household Wi-Fi.
		if address.begins_with("192.168.56.") or address.begins_with("192.168.99."):
			continue
		if address.begins_with("192.168."):
			return address
		if address.begins_with("10."):
			candidates.push_front(address)
		elif address.begins_with("172."):
			var parts = address.split(".")
			if parts.size() > 1 and parts[1].to_int() >= 16 and parts[1].to_int() <= 31:
				candidates.append(address)
	if not candidates.is_empty():
		return candidates[0]
	return "127.0.0.1"

# --- Hosting & Joining ---

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	peer = ENetMultiplayerPeer.new()
	# By default, Godot binds to 0.0.0.0 (all local network interfaces)
	var error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		print("Failed to host on port ", port, ": ", error)
		return error

	multiplayer.multiplayer_peer = peer
	players.clear()
	active_game_scene = ""
	loaded_game_peers.clear()
	# Host is always peer ID 1
	players[1] = {
		"name": local_player_name,
		"seat": -1,
		"customization": local_customization
	}
	player_list_updated.emit()
	print("Host started server on port ", port)
	return OK

func join_game(ip_address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	peer = ENetMultiplayerPeer.new()
	var clean_ip = ip_address.strip_edges()
	if clean_ip == "" or clean_ip.to_lower() == "localhost":
		clean_ip = "127.0.0.1"

	var error = peer.create_client(clean_ip, port)
	if error != OK:
		print("Failed to create client connection: ", error)
		return error

	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to ", clean_ip, ":", port)
	return OK

func disconnect_game() -> void:
	active_game_scene = ""
	loaded_game_peers.clear()
	local_game_loaded = false
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()

# --- Callbacks ---

func _on_peer_connected(id: int) -> void:
	print("Peer connected with ID: ", id)
	player_list_updated.emit()

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected with ID: ", id)
	if multiplayer.is_server():
		loaded_game_peers.erase(id)
		players.erase(id)
		_sync_players_to_clients.rpc(players)
		player_disconnected.emit(id)
		player_list_updated.emit()

func _on_connected_to_server() -> void:
	print("Successfully connected to host!")
	_register_player.rpc_id(1, local_player_name, local_customization)
	connection_ready.emit()

func _on_connection_failed() -> void:
	active_game_scene = ""
	loaded_game_peers.clear()
	local_game_loaded = false
	print("Failed to connect to host.")
	multiplayer.multiplayer_peer = null
	peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	active_game_scene = ""
	loaded_game_peers.clear()
	local_game_loaded = false
	print("Host disconnected.")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()

# --- RPCs ---

@rpc("any_peer", "reliable")
func _register_player(player_name: String, custom_data: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id <= 1 or players.has(sender_id):
		return
	players[sender_id] = {
		"name": player_name,
		"seat": -1,
		"customization": custom_data,
		"ready": false
	}
	if active_game_scene != "":
		players[sender_id]["seat"] = find_free_seat()
	_sync_players_to_clients.rpc(players)
	player_connected.emit(sender_id, players[sender_id])
	player_list_updated.emit()
	if active_game_scene != "":
		_load_game_scene.rpc_id(sender_id, active_game_scene)

@rpc("authority", "call_local", "reliable")
func _sync_players_to_clients(updated_players: Dictionary) -> void:
	players = updated_players
	player_list_updated.emit()

@rpc("any_peer", "call_local", "reliable")
func request_customization(custom_data: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if not multiplayer.is_server():
		request_customization.rpc_id(1, custom_data)
		return
	if players.has(sender_id):
		players[sender_id]["customization"] = custom_data
		_sync_players_to_clients.rpc(players)

func set_local_customization(custom_data: Dictionary) -> void:
	local_customization = custom_data
	var my_id = multiplayer.get_unique_id() if (multiplayer != null and multiplayer.has_multiplayer_peer()) else 1
	if players.has(my_id):
		players[my_id]["customization"] = custom_data
	if is_connection_ready():
		if multiplayer.is_server():
			_sync_players_to_clients.rpc(players)
		else:
			request_customization.rpc_id(1, custom_data)
	player_list_updated.emit()

@rpc("any_peer", "call_local", "reliable")
func request_seat(seat_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id() # Host is peer ID 1

	# Check if seat is already occupied by someone else
	for id in players:
		if players[id].get("seat", -1) == seat_index and id != sender_id:
			return # Taken
	if players.has(sender_id):
		if players[sender_id].get("seat", -1) != seat_index:
			players[sender_id]["ready"] = false
		players[sender_id]["seat"] = seat_index
		_sync_players_to_clients.rpc(players)

# --- Start Game Scene Sync ---

@rpc("any_peer", "reliable")
func request_player_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id <= 1 or not players.has(sender_id):
		return
	if is_ready and players[sender_id].get("seat", -1) < 0:
		return
	players[sender_id]["ready"] = is_ready
	_sync_players_to_clients.rpc(players)

func can_start_game() -> bool:
	if not players.has(1):
		return false
	var has_seated_player = false
	for id in players:
		has_seated_player = has_seated_player or players[id].get("seat", -1) >= 0
		if id != 1 and not players[id].get("ready", false):
			return false
	# A connected peer still registering must also block the start.
	for id in multiplayer.get_peers():
		if not players.has(id):
			return false
	return has_seated_player

func start_game(scene_path: String) -> void:
	if not multiplayer.is_server() or not can_start_game():
		return
	# Ensure every peer has the final names, seats, and customization data
	# before the river scene is created on each machine.
	_sync_players_to_clients.rpc(players)
	active_game_scene = scene_path
	loaded_game_peers.clear()
	_load_game_scene.rpc(scene_path)

@rpc("authority", "call_local", "reliable")
func _load_game_scene(scene_path: String) -> void:
	active_game_scene = scene_path
	local_game_loaded = false
	get_tree().change_scene_to_file(scene_path)

func find_free_seat() -> int:
	for seat in range(MAX_PLAYERS):
		var taken = false
		for info in players.values():
			if info.get("seat", -1) == seat:
				taken = true
				break
		if not taken:
			return seat
	return -1

func notify_game_loaded() -> void:
	if not is_connection_ready():
		return
	if multiplayer.is_server():
		local_game_loaded = true
	else:
		_report_game_loaded.rpc_id(1)

@rpc("any_peer", "reliable")
func _report_game_loaded() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not players.has(sender) or sender <= 1:
		return
	var scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != active_game_scene or not scene.has_method("send_initial_state"):
		return
	scene.send_initial_state(sender)
	loaded_game_peers[sender] = true

func get_loaded_game_peers() -> Array:
	var result: Array = []
	for id in multiplayer.get_peers():
		if loaded_game_peers.has(id):
			result.append(id)
	return result
