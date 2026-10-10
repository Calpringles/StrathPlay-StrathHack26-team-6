# res://networking/Lobby.gd
extends Control

# Panels
@onready var connect_panel: PanelContainer = $CenterContainer/ConnectPanel
@onready var room_panel: PanelContainer = $CenterContainer/RoomPanel

# Connect Panel Nodes
@onready var name_input: LineEdit = $CenterContainer/ConnectPanel/VBox/NameInput
@onready var ip_input: LineEdit = $CenterContainer/ConnectPanel/VBox/IPInput
@onready var host_button: Button = $CenterContainer/ConnectPanel/VBox/ButtonRow/HostButton
@onready var join_button: Button = $CenterContainer/ConnectPanel/VBox/ButtonRow/JoinButton
@onready var connect_status_label: Label = $CenterContainer/ConnectPanel/VBox/StatusLabel

# Room Panel Nodes
@onready var room_title: Label = $CenterContainer/RoomPanel/VBox/RoomTitle
@onready var ip_info_box: HBoxContainer = $CenterContainer/RoomPanel/VBox/IPInfoBox
@onready var local_ip_label: Label = $CenterContainer/RoomPanel/VBox/IPInfoBox/LocalIPLabel
@onready var copy_ip_button: Button = $CenterContainer/RoomPanel/VBox/IPInfoBox/CopyIPButton
@onready var player_list_container: VBoxContainer = $CenterContainer/RoomPanel/VBox/PlayerListScroll/PlayerList
@onready var start_button: Button = $CenterContainer/RoomPanel/VBox/ControlRow/StartGameButton
@onready var leave_button: Button = $CenterContainer/RoomPanel/VBox/ControlRow/LeaveRoomButton

@onready var seat_buttons: Array[Button] = [
	$CenterContainer/RoomPanel/VBox/SeatGrid/Seat0,
	$CenterContainer/RoomPanel/VBox/SeatGrid/Seat1,
	$CenterContainer/RoomPanel/VBox/SeatGrid/Seat2,
	$CenterContainer/RoomPanel/VBox/SeatGrid/Seat3,
	$CenterContainer/RoomPanel/VBox/SeatGrid/Seat4,
	$CenterContainer/RoomPanel/VBox/SeatGrid/Seat5
]

const SEAT_NAMES = [
	"Front-Left Oar", "Front-Right Oar",
	"Mid-Left Oar", "Mid-Right Oar",
	"Back-Left Oar", "Back-Right Oar"
]
const TARGET_GAME_SCENE = "res://networking/DummyGame.tscn"

func _ready() -> void:
	connect_panel.visible = true
	room_panel.visible = false
	connect_status_label.text = ""

	# Button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_game_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	copy_ip_button.pressed.connect(_on_copy_ip_pressed)

	for i in range(seat_buttons.size()):
		var idx = i
		seat_buttons[i].pressed.connect(func(): _on_seat_selected(idx))

	# NetworkManager signals
	NetworkManager.player_list_updated.connect(_update_room_ui)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _get_player_name() -> String:
	var input_name = name_input.text.strip_edges()
	return input_name if input_name != "" else "Player_%d" % randi_range(100, 999)

func _on_host_pressed() -> void:
	connect_status_label.text = "Starting host..."
	var err = NetworkManager.host_game(_get_player_name())
	if err == OK:
		connect_panel.visible = false
		room_panel.visible = true
		
		# Show Host's Local LAN IP
		var local_ip = NetworkManager.get_local_ip()
		local_ip_label.text = "LAN IP for friends on your Wi-Fi: %s" % local_ip
		ip_info_box.visible = true
		_update_room_ui()
	else:
		connect_status_label.text = "Error hosting on port %d" % NetworkManager.DEFAULT_PORT

func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"

	connect_status_label.text = "Connecting to %s..." % ip
	var err = NetworkManager.join_game(ip, _get_player_name())
	if err == OK:
		connect_panel.visible = false
		room_panel.visible = true
		ip_info_box.visible = false
	else:
		connect_status_label.text = "Connection failed to start."

func _on_copy_ip_pressed() -> void:
	var local_ip = NetworkManager.get_local_ip()
	DisplayServer.clipboard_set(local_ip)
	copy_ip_button.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	copy_ip_button.text = "Copy IP"

func _on_seat_selected(seat_index: int) -> void:
	if multiplayer.is_server():
		NetworkManager.request_seat(seat_index)
	else:
		NetworkManager.request_seat.rpc_id(1, seat_index)

func _update_room_ui() -> void:
	var is_server = multiplayer.is_server()
	var my_id = multiplayer.get_unique_id()
	room_title.text = "Boat Staging Lobby (%s)" % ("HOST" if is_server else "CONNECTED CLIENT")

	# Refresh player list
	for child in player_list_container.get_children():
		child.queue_free()

	var seated_count = 0
	for peer_id in NetworkManager.players:
		var p_info = NetworkManager.players[peer_id]
		var seat_idx = p_info.get("seat", -1)
		var seat_str = SEAT_NAMES[seat_idx] if seat_idx >= 0 and seat_idx < SEAT_NAMES.size() else "Choosing oar..."
		if seat_idx >= 0:
			seated_count += 1
		var is_you = " [YOU]" if peer_id == my_id else ""
		
		var lbl = Label.new()
		lbl.text = "• %s%s  -->  %s" % [p_info.get("name", "Unknown"), is_you, seat_str]
		player_list_container.add_child(lbl)

	# Update seat buttons
	for i in range(seat_buttons.size()):
		var btn = seat_buttons[i]
		var occupied_by: String = ""
		var occupied_by_me = false

		for peer_id in NetworkManager.players:
			if NetworkManager.players[peer_id].get("seat", -1) == i:
				occupied_by = NetworkManager.players[peer_id].get("name", "Player")
				if peer_id == my_id:
					occupied_by_me = true
				break

		if occupied_by_me:
			btn.text = "%s [YOU]" % SEAT_NAMES[i]
			btn.disabled = true
		elif occupied_by != "":
			btn.text = "%s [%s]" % [SEAT_NAMES[i], occupied_by]
			btn.disabled = true
		else:
			btn.text = "%s (Pick)" % SEAT_NAMES[i]
			btn.disabled = false

	# Host controls
	start_button.visible = is_server
	start_button.disabled = not is_server or seated_count == 0

func _on_start_game_pressed() -> void:
	NetworkManager.start_game(TARGET_GAME_SCENE)

func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	room_panel.visible = false
	connect_panel.visible = true
	connect_status_label.text = "Disconnected."

func _on_connection_failed() -> void:
	connect_status_label.text = "Failed to connect to host. Check IP & port."
	room_panel.visible = false
	connect_panel.visible = true

func _on_server_disconnected() -> void:
	connect_status_label.text = "Host closed the server."
	room_panel.visible = false
	connect_panel.visible = true
