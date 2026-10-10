extends CanvasLayer

@onready var player_info_label: Label = $MarginContainer/VBox/PlayerInfoLabel
@onready var distance_label: Label = $MarginContainer/VBox/DistanceLabel
@onready var leave_button: Button = $MarginContainer/VBox/LeaveButton
@onready var boat: Node3D = $"../Boat"

const SEAT_NAMES = [
	"Front-Left Oar", "Front-Right Oar",
	"Mid-Left Oar", "Mid-Right Oar",
	"Back-Left Oar", "Back-Right Oar"
]

func _ready() -> void:
	leave_button.pressed.connect(_on_leave_pressed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Setup local player HUD tag
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player_name = "Player"
	var seat_idx = -1

	if NetworkManager.players.has(my_id):
		player_name = NetworkManager.players[my_id].get("name", "Player")
		seat_idx = NetworkManager.players[my_id].get("seat", -1)

	var seat_str = SEAT_NAMES[seat_idx] if seat_idx >= 0 and seat_idx < SEAT_NAMES.size() else "Solo (Testing)"
	player_info_label.text = "You: %s | Role: %s" % [player_name, seat_str]

func _process(_delta: float) -> void:
	if boat:
		var distance = maxf(0.0, -boat.global_position.z)
		distance_label.text = "Distance: %d m" % int(distance)

func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://networking/Lobby.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://networking/Lobby.tscn")
