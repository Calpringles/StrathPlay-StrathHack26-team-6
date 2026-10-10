extends CharacterBody3D

# Which player this computer controls when playing solo/offline without networking.
@export_range(1, 6) var player_number: int = 1

@export var stroke_power: float = 1.0
@export var turn_power: float = 0.35
@export var water_drag: float = 0.8
@export var turn_drag: float = 3.0
@export var current_speed: float = 1.5
@export_range(0.1, 2.0) var stroke_duration: float = 0.45

var turn_speed: float = 0.0

var oars: Array[Node3D] = []
var stroke_timers: Array[float] = []

# Negative X is left. Negative Z is the front of the boat.
# Matches NetworkManager seat indices 0 to 5:
const OAR_POSITIONS: Array[Vector3] = [
	Vector3(-0.85, 0.0, -1.0), # Seat 0: Front-Left
	Vector3(0.85, 0.0, -1.0),  # Seat 1: Front-Right
	Vector3(-0.85, 0.0, 0.0),   # Seat 2: Mid-Left
	Vector3(0.85, 0.0, 0.0),    # Seat 3: Mid-Right
	Vector3(-0.85, 0.0, 1.0),   # Seat 4: Back-Left
	Vector3(0.85, 0.0, 1.0)     # Seat 5: Back-Right
]

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	# Clean up any leftover placeholder oars in the scene
	for old_name in ["LeftOar", "RightOar"]:
		var old_oar: Node = get_node_or_null(NodePath(old_name))
		if old_oar != null:
			remove_child(old_oar)
			old_oar.queue_free()

	# Create dynamic container for up to 6 oars
	var container: Node3D = Node3D.new()
	container.name = "Oars"
	add_child(container)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#965d35")

	for index in range(OAR_POSITIONS.size()):
		var pivot: Node3D = Node3D.new()
		pivot.name = "Oar%d" % (index + 1)
		pivot.position = OAR_POSITIONS[index]
		container.add_child(pivot)

		var mesh_node: MeshInstance3D = MeshInstance3D.new()
		mesh_node.name = "Mesh"

		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(1.8, 0.1, 0.18)

		mesh_node.mesh = mesh
		mesh_node.material_override = material

		# Extend the oar outwards from its pivot
		var side: float = signf(OAR_POSITIONS[index].x)
		mesh_node.position.x = side * 0.9
		pivot.add_child(mesh_node)

		oars.append(pivot)
		stroke_timers.append(0.0)

func _physics_process(delta: float) -> void:
	# 1. Update stroke timers on all peers for smooth animation
	for index in range(stroke_timers.size()):
		stroke_timers[index] = maxf(0.0, stroke_timers[index] - delta)

	# 2. Animate oar rotations on all peers
	for index in range(oars.size()):
		var side: float = signf(OAR_POSITIONS[index].x)
		oars[index].rotation.y = side * stroke_angle(stroke_timers[index])

	# 3. Check for local player's input (Mouse click or row action)
	if Input.is_action_just_pressed("row"):
		_on_local_row_pressed()

	# 4. SERVER AUTHORITY: Only the host calculates boat physics and collision.
	# Connected clients receive synced position and rotation from MultiplayerSynchronizer.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Server / Singleplayer physics calculation
	var current: Vector3 = Vector3(0.0, 0.0, -current_speed)
	velocity = current + (velocity - current) * exp(-water_drag * delta)
	velocity.y = 0.0

	rotate_y(turn_speed * delta)
	turn_speed *= exp(-turn_drag * delta)

	move_and_slide()
	global_position.x = clampf(global_position.x, -8.0, 8.0)

func _on_local_row_pressed() -> void:
	var my_seat: int = -1

	# In multiplayer, retrieve assigned seat from NetworkManager
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var my_id: int = multiplayer.get_unique_id()
		if NetworkManager.players.has(my_id):
			my_seat = NetworkManager.players[my_id].get("seat", -1)
	else:
		# Fallback when testing solo/offline without network
		my_seat = player_number - 1

	if my_seat >= 0 and my_seat < oars.size():
		if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			if multiplayer.is_server():
				server_row_oar(my_seat)
			else:
				request_row.rpc_id(1, my_seat)
		else:
			server_row_oar(my_seat)

# RPC called by clients to request a row stroke on their assigned seat
@rpc("any_peer", "reliable")
func request_row(seat_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	# Verify sender actually owns this seat
	if NetworkManager.players.has(sender_id):
		if NetworkManager.players[sender_id].get("seat", -1) == seat_index:
			server_row_oar(seat_index)

# Server authoritative execution of rowing physics and broadcasting animation
func server_row_oar(index: int) -> void:
	if index < 0 or index >= oars.size():
		return

	if stroke_timers[index] > 0.0:
		return

	var forward: Vector3 = -global_transform.basis.z
	var side: float = signf(OAR_POSITIONS[index].x)

	velocity += forward * stroke_power

	# Left oars turn right; right oars turn left.
	turn_speed += side * turn_power

	# Broadcast animation to all peers (including host)
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		sync_stroke.rpc(index)
	else:
		sync_stroke(index)

# Broadcasted to all peers so the oar stroke animation plays simultaneously
@rpc("authority", "call_local", "reliable")
func sync_stroke(index: int) -> void:
	if index >= 0 and index < stroke_timers.size():
		stroke_timers[index] = stroke_duration

func stroke_angle(timer: float) -> float:
	if timer <= 0.0:
		return 0.0

	var progress: float = 1.0 - timer / stroke_duration
	return sin(progress * PI) * 0.8
