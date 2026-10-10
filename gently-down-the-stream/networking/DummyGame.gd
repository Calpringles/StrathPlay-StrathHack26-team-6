# res://networking/DummyGame.gd
extends Control

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var players_list: VBoxContainer = $VBoxContainer/PlayersList
@onready var leave_button: Button = $VBoxContainer/LeaveButton

const SEAT_NAMES = [
	"Front-Left Oar", "Front-Right Oar",
	"Mid-Left Oar", "Mid-Right Oar",
	"Back-Left Oar", "Back-Right Oar"
]

func _ready() -> void:
	leave_button.pressed.connect(_on_leave_pressed)
	NetworkManager.player_list_updated.connect(update_roster)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	update_roster()

func update_roster() -> void:
	for child in players_list.get_children():
		child.queue_free()

	var my_id = multiplayer.get_unique_id()
	status_label.text = "Game Started! You are Peer ID: %d (%s)" % [
		my_id,
		"HOST / SERVER" if multiplayer.is_server() else "CLIENT"
	]

	for peer_id in NetworkManager.players:
		var p_data = NetworkManager.players[peer_id]
		var seat_idx = p_data.get("seat", -1)
		var seat_text = SEAT_NAMES[seat_idx] if seat_idx >= 0 and seat_idx < SEAT_NAMES.size() else "Spectator (No Seat)"
		var is_you = " [YOU]" if peer_id == my_id else ""
		
		var lbl = Label.new()
		lbl.text = "• %s%s (ID: %d) -> Seat: %s" % [p_data.get("name", "Unknown"), is_you, peer_id, seat_text]
		players_list.add_child(lbl)

func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://networking/Lobby.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://networking/Lobby.tscn")
