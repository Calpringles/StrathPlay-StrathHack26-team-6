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

# Room Panel Left Column Nodes
@onready var room_title: Label = $CenterContainer/RoomPanel/MainHBox/LeftVBox/RoomTitle
@onready var ip_info_box: HBoxContainer = $CenterContainer/RoomPanel/MainHBox/LeftVBox/IPInfoBox
@onready var local_ip_label: Label = $CenterContainer/RoomPanel/MainHBox/LeftVBox/IPInfoBox/LocalIPLabel
@onready var copy_ip_button: Button = $CenterContainer/RoomPanel/MainHBox/LeftVBox/IPInfoBox/CopyIPButton
@onready var player_list_container: VBoxContainer = $CenterContainer/RoomPanel/MainHBox/LeftVBox/PlayerListScroll/PlayerList
@onready var start_button: Button = $CenterContainer/RoomPanel/MainHBox/LeftVBox/ControlRow/StartGameButton
@onready var leave_button: Button = $CenterContainer/RoomPanel/MainHBox/LeftVBox/ControlRow/LeaveRoomButton

@onready var seat_buttons: Array[Button] = [
	$CenterContainer/RoomPanel/MainHBox/LeftVBox/SeatGrid/Seat0,
	$CenterContainer/RoomPanel/MainHBox/LeftVBox/SeatGrid/Seat1,
	$CenterContainer/RoomPanel/MainHBox/LeftVBox/SeatGrid/Seat2,
	$CenterContainer/RoomPanel/MainHBox/LeftVBox/SeatGrid/Seat3,
	$CenterContainer/RoomPanel/MainHBox/LeftVBox/SeatGrid/Seat4,
	$CenterContainer/RoomPanel/MainHBox/LeftVBox/SeatGrid/Seat5
]

# Room Panel Customization Right Column Nodes
@onready var preview_viewport: SubViewport = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/PreviewCenter/PreviewContainer/SubViewport
@onready var random_button: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/RandomButton
@onready var rotate_left_button: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/RotationControls/RotateLeft
@onready var rotate_right_button: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/RotationControls/RotateRight

@onready var prev_eyes_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/EyesControl/PrevBtn
@onready var eyes_label: Label = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/EyesControl/ValueLabel
@onready var next_eyes_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/EyesControl/NextBtn

@onready var prev_mouth_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/MouthControl/PrevBtn
@onready var mouth_label: Label = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/MouthControl/ValueLabel
@onready var next_mouth_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/MouthControl/NextBtn

@onready var prev_hat_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/HatControl/PrevBtn
@onready var hat_label: Label = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/HatControl/ValueLabel
@onready var next_hat_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/HatControl/NextBtn

@onready var prev_skin_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/SkinControl/PrevBtn
@onready var skin_color_rect: ColorRect = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/SkinControl/ColorBox
@onready var next_skin_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/SkinControl/NextBtn

@onready var prev_shirt_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/ShirtControl/PrevBtn
@onready var shirt_color_rect: ColorRect = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/ShirtControl/ColorBox
@onready var next_shirt_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/ShirtControl/NextBtn

@onready var prev_pants_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/PantsControl/PrevBtn
@onready var pants_color_rect: ColorRect = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/PantsControl/ColorBox
@onready var next_pants_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/PantsControl/NextBtn

@onready var prev_hat_col_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/HatColorControl/PrevBtn
@onready var hat_color_rect: ColorRect = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/HatColorControl/ColorBox
@onready var next_hat_col_btn: Button = $CenterContainer/RoomPanel/MainHBox/CustomizationVBox/OptionsGrid/HatColorControl/NextBtn

const SEAT_NAMES = [
	"Front-Left Oar", "Front-Right Oar",
	"Mid-Left Oar", "Mid-Right Oar",
	"Back-Left Oar", "Back-Right Oar"
]
const TARGET_GAME_SCENE = "res://river.tscn"

var current_customization: Dictionary = {}
var preview_rower: Node3D = null

func _ready() -> void:
	connect_panel.visible = true
	room_panel.visible = false
	connect_status_label.text = ""

	current_customization = CharacterCustomizer.get_default_customization(0)
	if NetworkManager != null and not NetworkManager.local_customization.is_empty():
		current_customization = NetworkManager.local_customization.duplicate()

	# Connect Panel Button signals
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
	NetworkManager.connection_ready.connect(_on_network_ready)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Setup 3D preview rower
	_setup_preview_rower()

	# Customization Controls signals
	random_button.pressed.connect(_on_randomize_pressed)
	rotate_left_button.pressed.connect(func(): _rotate_preview(-30.0))
	rotate_right_button.pressed.connect(func(): _rotate_preview(30.0))

	prev_eyes_btn.pressed.connect(func(): _cycle_option("eyes_idx", -1, CharacterCustomizer.EYE_NAMES.size()))
	next_eyes_btn.pressed.connect(func(): _cycle_option("eyes_idx", 1, CharacterCustomizer.EYE_NAMES.size()))

	prev_mouth_btn.pressed.connect(func(): _cycle_option("mouth_idx", -1, CharacterCustomizer.MOUTH_NAMES.size()))
	next_mouth_btn.pressed.connect(func(): _cycle_option("mouth_idx", 1, CharacterCustomizer.MOUTH_NAMES.size()))

	prev_hat_btn.pressed.connect(func(): _cycle_option("hat_idx", -1, CharacterCustomizer.HAT_NAMES.size()))
	next_hat_btn.pressed.connect(func(): _cycle_option("hat_idx", 1, CharacterCustomizer.HAT_NAMES.size()))

	prev_skin_btn.pressed.connect(func(): _cycle_option("skin_idx", -1, CharacterCustomizer.PALETTE.size()))
	next_skin_btn.pressed.connect(func(): _cycle_option("skin_idx", 1, CharacterCustomizer.PALETTE.size()))

	prev_shirt_btn.pressed.connect(func(): _cycle_option("shirt_idx", -1, CharacterCustomizer.PALETTE.size()))
	next_shirt_btn.pressed.connect(func(): _cycle_option("shirt_idx", 1, CharacterCustomizer.PALETTE.size()))

	prev_pants_btn.pressed.connect(func(): _cycle_option("pants_idx", -1, CharacterCustomizer.PALETTE.size()))
	next_pants_btn.pressed.connect(func(): _cycle_option("pants_idx", 1, CharacterCustomizer.PALETTE.size()))

	prev_hat_col_btn.pressed.connect(func(): _cycle_option("hat_color_idx", -1, CharacterCustomizer.PALETTE.size()))
	next_hat_col_btn.pressed.connect(func(): _cycle_option("hat_color_idx", 1, CharacterCustomizer.PALETTE.size()))

	_update_customization_ui()

func _rotate_preview(degrees: float) -> void:
	if preview_rower != null:
		preview_rower.rotation_degrees.y += degrees

func _setup_preview_rower() -> void:
	if preview_viewport == null:
		return

	var rower_path = "res://seated-rower.glb"
	if ResourceLoader.exists(rower_path):
		var rower_scene: PackedScene = load(rower_path)
		preview_rower = rower_scene.instantiate()
		preview_rower.name = "PreviewRower"
		preview_rower.scale = Vector3(0.85, 0.85, 0.85)
		preview_rower.position = Vector3(0, 0, 0)
		preview_rower.rotation_degrees.y = 180.0 # Face the preview camera.
		preview_viewport.add_child(preview_rower)
		CharacterCustomizer.apply_to_rower(preview_rower, current_customization)

func _cycle_option(key: String, delta: int, max_count: int) -> void:
	var cur = current_customization.get(key, 0)
	cur = (cur + delta + max_count) % max_count
	current_customization[key] = cur
	_update_customization_ui()

func _on_randomize_pressed() -> void:
	current_customization = CharacterCustomizer.get_random_customization()
	_update_customization_ui()

func _update_customization_ui() -> void:
	eyes_label.text = CharacterCustomizer.EYE_NAMES[current_customization.get("eyes_idx", 0) % CharacterCustomizer.EYE_NAMES.size()]
	mouth_label.text = CharacterCustomizer.MOUTH_NAMES[current_customization.get("mouth_idx", 0) % CharacterCustomizer.MOUTH_NAMES.size()]
	hat_label.text = CharacterCustomizer.HAT_NAMES[current_customization.get("hat_idx", 0) % CharacterCustomizer.HAT_NAMES.size()]

	skin_color_rect.color = CharacterCustomizer.PALETTE[current_customization.get("skin_idx", 1) % CharacterCustomizer.PALETTE.size()]
	shirt_color_rect.color = CharacterCustomizer.PALETTE[current_customization.get("shirt_idx", 0) % CharacterCustomizer.PALETTE.size()]
	pants_color_rect.color = CharacterCustomizer.PALETTE[current_customization.get("pants_idx", 11) % CharacterCustomizer.PALETTE.size()]
	hat_color_rect.color = CharacterCustomizer.PALETTE[current_customization.get("hat_color_idx", 3) % CharacterCustomizer.PALETTE.size()]

	if preview_rower != null:
		CharacterCustomizer.apply_to_rower(preview_rower, current_customization)

	# Keep customization local while connecting. It is sent once by
	# _on_network_ready after the ENet handshake completes.
	if NetworkManager != null and NetworkManager.is_connection_ready():
		NetworkManager.set_local_customization(current_customization)

func _on_network_ready() -> void:
	if NetworkManager != null:
		NetworkManager.set_local_customization(current_customization)
	connect_status_label.text = "Connected to host."

func _get_player_name() -> String:
	var input_name = name_input.text.strip_edges()
	return input_name if input_name != "" else "Player_%d" % randi_range(100, 999)

func _on_host_pressed() -> void:
	connect_status_label.text = "Starting host..."
	var err = NetworkManager.host_game(_get_player_name())
	if err == OK:
		connect_panel.visible = false
		room_panel.visible = true
		
		var local_ip = NetworkManager.get_local_ip()
		local_ip_label.text = "LAN IP for friends on your Wi-Fi: %s" % local_ip
		ip_info_box.visible = true
		_update_room_ui()
		_update_customization_ui()
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
		_update_customization_ui()
	else:
		connect_status_label.text = "Connection failed to start."

func _on_copy_ip_pressed() -> void:
	var local_ip = NetworkManager.get_local_ip()
	DisplayServer.clipboard_set(local_ip)
	copy_ip_button.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	copy_ip_button.text = "Copy IP"

func _on_seat_selected(seat_index: int) -> void:
	# The lobby can be visible while a client is still connecting. Do not send
	# RPCs until ENet has completed its handshake.
	if NetworkManager == null or not NetworkManager.is_connection_ready():
		connect_status_label.text = "Still connecting — please try again in a moment."
		return
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
	connect_panel.visible = true
	room_panel.visible = false
	connect_status_label.text = "Could not connect. Check the host IP and Windows Firewall."
	connect_status_label.text = "Failed to connect to host. Check IP & port."
	room_panel.visible = false
	connect_panel.visible = true

func _on_server_disconnected() -> void:
	connect_status_label.text = "Host closed the server."
	room_panel.visible = false
	connect_panel.visible = true
