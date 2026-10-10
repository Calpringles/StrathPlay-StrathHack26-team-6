# res://networking/NetworkManager.gd
extends Node

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 6

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal player_list_updated()
signal connection_failed()
signal server_disconnected()

# Stores: { peer_id: { "name": String, "seat": int } }
# Seat mapping: -1 = Unassigned, 0 = Front-Left, 1 = Front-Right, 2 = Mid-Left, 3 = Mid-Right, 4 = Back-Left, 5 = Back-Right
var players: Dictionary = {}
var local_player_name: String = "Player"

var peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- IP Helper for LAN / Same Network ---

func get_local_ip() -> String:
	# Searches local network adapters for a standard private IPv4 (e.g. 192.168.x.x, 10.x.x.x)
	for address in IP.get_local_addresses():
		if address.contains(":"):
			continue # Ignore IPv6
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var parts = address.split(".")
			if parts.size() > 1:
				var second_octet = parts[1].to_int()
				if second_octet >= 16 and second_octet <= 31:
					return address
	return "127.0.0.1"

# --- Hosting & Joining ---

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	peer = ENetMultiplayerPeer.new()
	# By default, Godot binds to 0.0.0.0 (all local network interfaces)
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Failed to host on port ", port, ": ", error)
		return error

	multiplayer.multiplayer_peer = peer
	# Host is always peer ID 1
	players[1] = {
		"name": local_player_name,
		"seat": -1
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
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()

# --- Callbacks ---

func _on_peer_connected(id: int) -> void:
	print("Peer connected with ID: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected with ID: ", id)
	if multiplayer.is_server():
		players.erase(id)
		_sync_players_to_clients.rpc(players)
		player_disconnected.emit(id)
		player_list_updated.emit()

func _on_connected_to_server() -> void:
	print("Successfully connected to host!")
	_register_player.rpc_id(1, local_player_name)

func _on_connection_failed() -> void:
	print("Failed to connect to host.")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("Host disconnected.")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()

# --- RPCs ---

@rpc("any_peer", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = {
		"name": player_name,
		"seat": -1
	}
	_sync_players_to_clients.rpc(players)
	player_connected.emit(sender_id, players[sender_id])
	player_list_updated.emit()

@rpc("authority", "call_local", "reliable")
func _sync_players_to_clients(updated_players: Dictionary) -> void:
	players = updated_players
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
		players[sender_id]["seat"] = seat_index
		_sync_players_to_clients.rpc(players)

# --- Start Game Scene Sync ---

func start_game(scene_path: String) -> void:
	if not multiplayer.is_server():
		return
	_load_game_scene.rpc(scene_path)

@rpc("authority", "call_local", "reliable")
func _load_game_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
