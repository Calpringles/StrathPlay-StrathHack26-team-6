# res://boat.gd
extends CharacterBody3D

signal sync_row_achieved(seat_a: int, seat_b: int)

# Which seat (0 to 5) this computer controls when not in networked session.
# Seat mapping:
# 0 = Front-Left,  1 = Front-Right
# 2 = Mid-Left,    3 = Mid-Right
# 4 = Back-Left,   5 = Back-Right
@export_range(0, 5) var local_seat: int = 0

@export_group("Rowing Physics")
@export var stroke_power: float = 2.8
@export var turn_power: float = 0.85
@export var current_speed: float = 0.8
@export var water_drag_longitudinal: float = 0.65
@export var water_drag_lateral: float = 4.2
@export var turn_drag: float = 2.0
@export_range(0.1, 2.0) var stroke_duration: float = 0.55
@export var sync_window: float = 0.22
@export var sync_boost: float = 0.25

@export_group("River Boundaries")
@export var min_x: float = -8.0
@export var max_x: float = 8.0

# 6 Seat configurations matching NetworkManager:
# 0: Front-Left, 1: Front-Right, 2: Mid-Left, 3: Mid-Right, 4: Back-Left, 5: Back-Right
const SEAT_NAMES: Array[String] = [
	"Front-Left Oar",
	"Front-Right Oar",
	"Mid-Left Oar",
	"Mid-Right Oar",
	"Back-Left Oar",
	"Back-Right Oar"
]

const OAR_CONFIGS: Array[Dictionary] = [
	{"name": "Front-Left",  "pos": Vector3(-0.68, 0.30, -0.82), "side": -1.0, "torque_factor": 1.25, "thrust_factor": 0.95},
	{"name": "Front-Right", "pos": Vector3(0.68, 0.30, -0.82),  "side": 1.0,  "torque_factor": 1.25, "thrust_factor": 0.95},
	{"name": "Mid-Left",    "pos": Vector3(-0.72, 0.30, 0.0),   "side": -1.0, "torque_factor": 0.70, "thrust_factor": 1.15},
	{"name": "Mid-Right",   "pos": Vector3(0.72, 0.30, 0.0),    "side": 1.0,  "torque_factor": 0.70, "thrust_factor": 1.15},
	{"name": "Back-Left",   "pos": Vector3(-0.68, 0.30, 0.82),  "side": -1.0, "torque_factor": 1.15, "thrust_factor": 0.95},
	{"name": "Back-Right",  "pos": Vector3(0.68, 0.30, 0.82),   "side": 1.0,  "torque_factor": 1.15, "thrust_factor": 0.95}
]

const SEAT_POSITIONS: Array[Vector3] = [
	Vector3(-0.31, 0.22, -0.82), # Seat 0: Front-Left
	Vector3(0.31, 0.22, -0.82),  # Seat 1: Front-Right
	Vector3(-0.31, 0.22, 0.0),   # Seat 2: Mid-Left
	Vector3(0.31, 0.22, 0.0),    # Seat 3: Mid-Right
	Vector3(-0.31, 0.22, 0.82),  # Seat 4: Back-Left
	Vector3(0.31, 0.22, 0.82)   # Seat 5: Back-Right
]

const BENCH_Z: Array[float] = [-0.82, 0.0, 0.82]
const BENCH_WIDTHS: Array[float] = [1.15, 1.25, 1.15]

const SEAT_COLORS: Array[Color] = [
	Color("#e74c3c"), # Front-Left (Coral Red)
	Color("#3498db"), # Front-Right (Ocean Blue)
	Color("#2ecc71"), # Mid-Left (Emerald Green)
	Color("#f39c12"), # Mid-Right (Warm Gold)
	Color("#9b59b6"), # Back-Left (Royal Purple)
	Color("#1abc9c")  # Back-Right (Turquoise)
]

var turn_speed: float = 0.0
var visual_tilt: Vector3 = Vector3.ZERO
var ambient_timer: float = 0.0
var water_turbulence: float = 0.0

var oars: Array[Node3D] = []
var rowers: Array[Node3D] = []
var stroke_timers: Array[float] = []
var stroke_is_reverse: Array[bool] = []
var last_stroke_times: Array[float] = []
var seat_labels: Array[Label3D] = []

var boat_visual_root: Node3D = null

func _find_asset_path(filename: String) -> String:
	for prefix in [
		"res://Game-Assets/boatassets/",
		"res://boatassets/"
	]:
		var full_path = prefix + filename
		if ResourceLoader.exists(full_path):
			return full_path
	return ""

func _find_rower_path() -> String:
	for p in [
		"res://seated-rower.glb",
		"res://Game-Assets/boatassets/seated-rower.glb",
		"res://boatassets/seated-rower.glb"
	]:
		if ResourceLoader.exists(p):
			return p
	return ""

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	# Clean up any legacy placeholder oar nodes
	for old_name in ["LeftOar", "RightOar", "Oars", "BoatVisual", "Hull", "Wood_BoatV1"]:
		var old_node: Node = get_node_or_null(NodePath(old_name))
		if old_node != null:
			remove_child(old_node)
			old_node.queue_free()

	_build_boat_visuals()
	_setup_collision()

	# Initialize timers
	stroke_timers.clear()
	stroke_is_reverse.clear()
	last_stroke_times.clear()
	for i in range(OAR_CONFIGS.size()):
		stroke_timers.append(0.0)
		stroke_is_reverse.append(false)
		last_stroke_times.append(-999.0)

	_update_seat_labels()
	# Scene changes can arrive immediately after the roster RPC. Refresh once
	# deferred so all synced player data is available before showing rowers.
	call_deferred("_update_seat_labels")

	# Listen for network roster updates if NetworkManager is active
	if is_inside_tree():
		var nm = get_node_or_null("/root/NetworkManager")
		if nm != null and nm.has_signal("player_list_updated"):
			nm.player_list_updated.connect(_update_seat_labels)

func _setup_collision() -> void:
	collision_layer = 1
	collision_mask = 1
	var col_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col_shape == null:
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"
		add_child(col_shape)
	
	if col_shape.shape == null:
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(1.4, 0.6, 4.3)
		col_shape.shape = box
		col_shape.position = Vector3(0.0, 0.25, 0.0)

func _build_boat_visuals() -> void:
	boat_visual_root = Node3D.new()
	boat_visual_root.name = "BoatVisual"
	add_child(boat_visual_root)

	# 1. Instantiate Boat Hull from 3D model
	# Raw FBX has bow at +X, internal child has rot -90. Parent rot 180 results in net +90, pointing bow at -Z downriver!
	var hull_node: Node3D = null
	var boat_path = _find_asset_path("Wood_BoatV1.fbx")
	if boat_path != "":
		var boat_scene: PackedScene = load(boat_path)
		hull_node = boat_scene.instantiate()
		hull_node.name = "HullMesh"
		hull_node.rotation_degrees.y = 180.0 # Bow points along -Z forward into river
		hull_node.scale = Vector3(0.95, 0.82, 0.88)
		hull_node.position = Vector3(0.0, 0.0, 0.0)
		boat_visual_root.add_child(hull_node)

	var wood_material: StandardMaterial3D = StandardMaterial3D.new()
	wood_material.albedo_color = Color("#5a3418")
	wood_material.roughness = 0.65

	var cushion_material: StandardMaterial3D = StandardMaterial3D.new()
	cushion_material.albedo_color = Color("#2e2620")
	cushion_material.roughness = 0.8

	# Load generic rower model
	var rower_packed: PackedScene = null
	var rower_path = _find_rower_path()
	if rower_path != "":
		rower_packed = load(rower_path)

	# 2. Attach cross-benches, seat platforms, and Rower characters to Seats
	rowers.clear()
	seat_labels.clear()

	var existing_seats = get_node_or_null("Seats")
	if existing_seats != null:
		# Reparent to boat_visual_root so seats, rowers, and labels sway and bob with the boat hull!
		if existing_seats.get_parent() != boat_visual_root:
			existing_seats.reparent(boat_visual_root)

		# Add cross-benches spanning the boat hull
		for i in range(BENCH_Z.size()):
			var bench_name = "Bench%d" % i
			if existing_seats.get_node_or_null(bench_name) == null:
				var bench_mesh_inst: MeshInstance3D = MeshInstance3D.new()
				bench_mesh_inst.name = bench_name
				var bench_mesh: BoxMesh = BoxMesh.new()
				bench_mesh.size = Vector3(BENCH_WIDTHS[i], 0.06, 0.26)
				bench_mesh_inst.mesh = bench_mesh
				bench_mesh_inst.material_override = wood_material
				bench_mesh_inst.position = Vector3(0.0, 0.22, BENCH_Z[i])
				existing_seats.add_child(bench_mesh_inst)

		for s_idx in range(6):
			var seat_node_name = "Seat%d" % (s_idx + 1)
			var marker: Node3D = existing_seats.get_node_or_null(seat_node_name) as Node3D
			if marker == null:
				marker = Marker3D.new()
				marker.name = seat_node_name
				marker.position = SEAT_POSITIONS[s_idx]
				existing_seats.add_child(marker)

			# Instantiate Rower Character
			var rower_inst: Node3D = null
			if rower_packed != null:
				rower_inst = rower_packed.instantiate()
				rower_inst.name = "Rower"
				rower_inst.scale = Vector3(0.68, 0.68, 0.68)
				rower_inst.position = Vector3.ZERO
				var side = OAR_CONFIGS[s_idx].side
				rower_inst.rotation.y = side * deg_to_rad(8.0) # Angle slightly towards oar
				CharacterCustomizer.apply_to_rower(rower_inst, CharacterCustomizer.get_default_customization(s_idx))
				marker.add_child(rower_inst)
			rowers.append(rower_inst)

			var lbl: Label3D = Label3D.new()
			lbl.name = "Label"
			lbl.text = SEAT_NAMES[s_idx]
			lbl.font_size = 18
			lbl.modulate = Color(1.0, 0.95, 0.8, 0.9)
			lbl.outline_modulate = Color(0, 0, 0, 0.8)
			lbl.outline_size = 4
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.position = Vector3(0.0, 0.88, 0.0) # Hover above rower's head
			marker.add_child(lbl)
			seat_labels.append(lbl)
	else:
		var seats_container: Node3D = Node3D.new()
		seats_container.name = "Seats"
		boat_visual_root.add_child(seats_container)

		for i in range(BENCH_Z.size()):
			var bench_mesh_inst: MeshInstance3D = MeshInstance3D.new()
			bench_mesh_inst.name = "Bench%d" % i
			var bench_mesh: BoxMesh = BoxMesh.new()
			bench_mesh.size = Vector3(BENCH_WIDTHS[i], 0.06, 0.26)
			bench_mesh_inst.mesh = bench_mesh
			bench_mesh_inst.material_override = wood_material
			bench_mesh_inst.position = Vector3(0.0, 0.22, BENCH_Z[i])
			seats_container.add_child(bench_mesh_inst)

		for s_idx in range(SEAT_POSITIONS.size()):
			var seat_marker: Marker3D = Marker3D.new()
			seat_marker.name = "SeatMarker%d" % s_idx
			seat_marker.position = SEAT_POSITIONS[s_idx]
			seats_container.add_child(seat_marker)

			var cushion_node: MeshInstance3D = MeshInstance3D.new()
			cushion_node.name = "Cushion%d" % s_idx
			var cushion_mesh: BoxMesh = BoxMesh.new()
			cushion_mesh.size = Vector3(0.32, 0.04, 0.24)
			cushion_node.mesh = cushion_mesh
			cushion_node.material_override = cushion_material
			cushion_node.position = Vector3(0.0, 0.03, 0.0)
			seat_marker.add_child(cushion_node)

			var rower_inst: Node3D = null
			if rower_packed != null:
				rower_inst = rower_packed.instantiate()
				rower_inst.name = "Rower"
				rower_inst.scale = Vector3(0.68, 0.68, 0.68)
				rower_inst.position = Vector3.ZERO
				var side = OAR_CONFIGS[s_idx].side
				rower_inst.rotation.y = side * deg_to_rad(8.0)
				CharacterCustomizer.apply_to_rower(rower_inst, CharacterCustomizer.get_default_customization(s_idx))
				seat_marker.add_child(rower_inst)
			rowers.append(rower_inst)

			var lbl: Label3D = Label3D.new()
			lbl.name = "Label%d" % s_idx
			lbl.text = SEAT_NAMES[s_idx]
			lbl.font_size = 18
			lbl.modulate = Color(1.0, 0.95, 0.8, 0.9)
			lbl.outline_modulate = Color(0, 0, 0, 0.8)
			lbl.outline_size = 4
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.position = Vector3(0.0, 0.88, 0.0)
			seat_marker.add_child(lbl)
			seat_labels.append(lbl)

	# 3. Build 6 Oars with Paddles
	var oars_container: Node3D = Node3D.new()
	oars_container.name = "Oars"
	boat_visual_root.add_child(oars_container)

	oars.clear()
	var paddle_packed: PackedScene = null
	var paddle_path = _find_asset_path("Paddle.fbx")
	if paddle_path != "":
		paddle_packed = load(paddle_path)

	var brass_mat: StandardMaterial3D = StandardMaterial3D.new()
	brass_mat.albedo_color = Color("#b8860b") # Brass oarlock
	brass_mat.metallic = 0.8
	brass_mat.roughness = 0.3

	for index in range(OAR_CONFIGS.size()):
		var cfg = OAR_CONFIGS[index]
		var pivot: Node3D = Node3D.new()
		pivot.name = "Oar%d" % index
		pivot.position = cfg.pos
		oars_container.add_child(pivot)

		# Brass Oarlock Mount
		var oarlock: MeshInstance3D = MeshInstance3D.new()
		oarlock.name = "Oarlock"
		var ring: CylinderMesh = CylinderMesh.new()
		ring.top_radius = 0.04
		ring.bottom_radius = 0.04
		ring.height = 0.08
		oarlock.mesh = ring
		oarlock.material_override = brass_mat
		pivot.add_child(oarlock)

		# Paddle / Oar Mesh
		var side: float = cfg.side # -1 for left, +1 for right
		var paddle_pivot_offset: Node3D = Node3D.new()
		paddle_pivot_offset.name = "PaddleOffset"
		pivot.add_child(paddle_pivot_offset)

		if paddle_packed != null:
			var paddle_instance: Node3D = paddle_packed.instantiate()
			paddle_instance.name = "PaddleMesh"
			# Paddle handle is at -Z, blade at +Z.
			# For right oar (+1): rotate +90 to point blade to +X into water.
			# For left oar (-1): rotate -90 to point blade to -X into water.
			var resting_yaw = 90.0 if side > 0.0 else -90.0
			paddle_instance.rotation_degrees = Vector3(10.0, resting_yaw, 0.0)
			paddle_instance.scale = Vector3(0.68, 0.68, 0.68)
			paddle_pivot_offset.add_child(paddle_instance)
		else:
			# Fallback box oar
			var mesh_node: MeshInstance3D = MeshInstance3D.new()
			mesh_node.name = "Mesh"
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(1.6, 0.08, 0.12)
			mesh_node.mesh = mesh
			mesh_node.material_override = wood_material
			mesh_node.position.x = side * 0.8
			paddle_pivot_offset.add_child(mesh_node)

		oars.append(pivot)

func _is_multiplayer_active() -> bool:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	var active_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	# A peer object can exist while a client is still connecting or after a
	# failed attempt. Only treat the game as multiplayer after the handshake.
	return multiplayer.is_server() or active_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _is_server() -> bool:
	return not _is_multiplayer_active() or (multiplayer != null and multiplayer.is_server())

func _update_seat_labels() -> void:
	if not is_inside_tree():
		return
	var nm = get_node_or_null("/root/NetworkManager")
	var is_mp = _is_multiplayer_active() and nm != null
	var my_id = multiplayer.get_unique_id() if is_mp else 1

	for s_idx in range(seat_labels.size()):
		var occupant_name = ""
		var is_local = false
		var occupant_customization: Dictionary = {}

		if is_mp and nm.players.size() > 0:
			for p_id in nm.players:
				if nm.players[p_id].get("seat", -1) == s_idx:
					occupant_name = nm.players[p_id].get("name", "Player")
					occupant_customization = nm.players[p_id].get("customization", {})
					if p_id == my_id:
						is_local = true
						local_seat = s_idx
					break

			if occupant_name != "":
				seat_labels[s_idx].text = "%s\n[%s%s]" % [
					SEAT_NAMES[s_idx],
					occupant_name,
					" (YOU)" if is_local else ""
				]
				seat_labels[s_idx].modulate = Color(0.4, 1.0, 0.5) if is_local else Color(1.0, 0.85, 0.4)
				if s_idx < rowers.size() and rowers[s_idx] != null:
					rowers[s_idx].visible = true
					if not occupant_customization.is_empty():
						CharacterCustomizer.apply_to_rower(rowers[s_idx], occupant_customization)
			else:
				seat_labels[s_idx].text = "%s\n[Empty]" % SEAT_NAMES[s_idx]
				seat_labels[s_idx].modulate = Color(0.8, 0.8, 0.8, 0.6)
				if s_idx < rowers.size() and rowers[s_idx] != null:
					rowers[s_idx].visible = false
		else:
			# Single-player / offline mode: show all crew rowers
			if s_idx < rowers.size() and rowers[s_idx] != null:
				rowers[s_idx].visible = true
				if nm != null and nm.get("local_customization") != null and s_idx == local_seat:
					CharacterCustomizer.apply_to_rower(rowers[s_idx], nm.local_customization)

			if s_idx == local_seat:
				seat_labels[s_idx].text = "%s\n[YOU - Space / Click to Row]" % SEAT_NAMES[s_idx]
				seat_labels[s_idx].modulate = Color(0.4, 1.0, 0.5)
			else:
				seat_labels[s_idx].text = "%s\n[Press %d to Row]" % [SEAT_NAMES[s_idx], s_idx + 1]
				seat_labels[s_idx].modulate = Color(1.0, 0.95, 0.8, 0.9)

func _physics_process(delta: float) -> void:
	ambient_timer += delta

	# Process stroke cooldown timers
	for index in range(stroke_timers.size()):
		stroke_timers[index] = maxf(0.0, stroke_timers[index] - delta)

	# Handle input for local player
	if get_parent().get("game_state") != null and get_parent().game_state != 0:
		velocity = Vector3.ZERO
		return
	_handle_local_input()

	# Physics simulation (server authority or local offline)
	if _is_server():
		_process_boat_physics(delta)
		if _is_multiplayer_active() and multiplayer.is_server():
			_sync_boat_state.rpc(global_position, rotation.y, velocity, turn_speed)

	# Update visual animations (oar strokes, boat roll/pitch sway)
	_update_visuals(delta)

func _handle_local_input() -> void:
	# Primary row action (Space or left click)
	if Input.is_action_just_pressed("row"):
		_request_stroke(local_seat, false)

	# Secondary reverse stroke / backwater (Right click or "row_reverse")
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.is_action_just_pressed("ui_cancel") == false:
		# Check if right click was just pressed this frame
		if Input.is_action_just_pressed("row_reverse") or _is_mouse_button_just_pressed(MOUSE_BUTTON_RIGHT):
			_request_stroke(local_seat, true)

	# Single-player / offline testing shortcuts: keys 1 to 6 trigger seats 0 to 5
	if not _is_multiplayer_active():
		for key_idx in range(6):
			var key_code = KEY_1 + key_idx
			if Input.is_key_pressed(key_code) and Input.is_physical_key_pressed(key_code):
				if stroke_timers[key_idx] <= 0.0:
					_request_stroke(key_idx, false)

var _prev_rmb_pressed: bool = false
func _is_mouse_button_just_pressed(button: MouseButton) -> bool:
	var pressed = Input.is_mouse_button_pressed(button)
	var just_pressed = pressed and not _prev_rmb_pressed
	_prev_rmb_pressed = pressed
	return just_pressed

func _request_stroke(seat_index: int, is_reverse: bool) -> void:
	if seat_index < 0 or seat_index >= oars.size():
		return

	if _is_multiplayer_active():
		if multiplayer.is_server():
			row_oar(seat_index, is_reverse)
			_broadcast_oar_stroke.rpc(seat_index, is_reverse)
		else:
			_server_request_row.rpc_id(1, seat_index, is_reverse)
	else:
		row_oar(seat_index, is_reverse)

@rpc("any_peer", "call_local", "reliable")
func _server_request_row(seat_index: int, is_reverse: bool) -> void:
	if not is_inside_tree() or multiplayer == null or not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	# Verify sender owns this seat if registered
	var nm = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.players.has(sender_id):
		var assigned_seat = nm.players[sender_id].get("seat", -1)
		if assigned_seat >= 0 and assigned_seat != seat_index:
			return # Denied: player does not own this seat

	if stroke_timers[seat_index] <= 0.0:
		row_oar(seat_index, is_reverse)
		_broadcast_oar_stroke.rpc(seat_index, is_reverse)

@rpc("authority", "call_local", "unreliable")
func _broadcast_oar_stroke(seat_index: int, is_reverse: bool) -> void:
	if seat_index >= 0 and seat_index < oars.size():
		stroke_timers[seat_index] = stroke_duration
		stroke_is_reverse[seat_index] = is_reverse
	
@rpc("authority", "unreliable_ordered")
func _sync_boat_state(pos: Vector3, rot_y: float, vel: Vector3, t_speed: float) -> void:
	if not multiplayer.is_server():
		global_position = pos
		rotation.y = rot_y
		velocity = vel
		turn_speed = t_speed

func row_oar(index: int, is_reverse: bool = false) -> void:
	if index < 0 or index >= oars.size():
		return
	if stroke_timers[index] > 0.0:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	last_stroke_times[index] = current_time
	stroke_timers[index] = stroke_duration
	stroke_is_reverse[index] = is_reverse

	var cfg = OAR_CONFIGS[index]
	var forward: Vector3 = -global_transform.basis.z if is_inside_tree() else Vector3(0, 0, -1)
	var side: float = cfg.side # -1 for left, +1 for right

	# Check for synchronized rowing bonus across complementary oars!
	# Complementary oar on the opposite side:
	var opposite_idx = index ^ 1 # 0<->1, 2<->3, 4<->5
	var sync_multiplier: float = 1.0
	if absf(current_time - last_stroke_times[opposite_idx]) <= sync_window:
		sync_multiplier += sync_boost # Synchronized pair surge!
		sync_row_achieved.emit(index, opposite_idx)

	var thrust_dir = -1.0 if is_reverse else 1.0
	var impulse = forward * (stroke_power * cfg.thrust_factor * sync_multiplier * thrust_dir)
	velocity += impulse

	# Torque: Left oars turn right (-yaw in Godot), Right oars turn left (+yaw in Godot).
	# Reverse stroke reverses the turning direction (backwatering).
	var torque_dir = -1.0 if is_reverse else 1.0
	turn_speed += side * turn_power * cfg.torque_factor * torque_dir

func _process_boat_physics(delta: float) -> void:
	# 1. Downstream river current
	var current_vel: Vector3 = Vector3(0.0, 0.0, -current_speed)

	# 2. Hydrodynamic drag (anisotropic: high lateral resistance, low longitudinal resistance)
	var local_rel_vel: Vector3 = global_transform.basis.inverse() * (velocity - current_vel)
	local_rel_vel.x *= exp(-water_drag_lateral * delta)
	local_rel_vel.z *= exp(-water_drag_longitudinal * delta)
	local_rel_vel.y = 0.0

	velocity = current_vel + (global_transform.basis * local_rel_vel)
	velocity.y = 0.0
	var hazards = get_parent().get_node_or_null("RiverHazards")
	if hazards != null:
		hazards.apply_whirlpool_forces(delta)

	# 3. Angular turning with hydrodynamic resistance
	rotate_y(turn_speed * delta)
	turn_speed *= exp(-turn_drag * delta)

	# 4. Motion and River boundary clamping
	move_and_slide()
	global_position.x = clampf(global_position.x, min_x, max_x)

func _update_visuals(delta: float) -> void:
	# Animate each oar and rower based on their stroke phase
	for index in range(oars.size()):
		var timer = stroke_timers[index]
		var is_rev = stroke_is_reverse[index]
		var side = OAR_CONFIGS[index].side
		var rower = rowers[index] if index < rowers.size() else null

		if timer > 0.0:
			var progress = 1.0 - (timer / stroke_duration) # 0.0 to 1.0
			var sweep_angle: float
			var dip_angle: float

			if not is_rev:
				# Drive phase (0.0 to 0.55): blade submerged, sweeping backward
				if progress < 0.55:
					var p = progress / 0.55
					sweep_angle = sin(p * (PI * 0.5)) * 0.72 # Sweep back towards stern
					dip_angle = sin(p * PI) * -0.26 # Dip blade down into water
				# Recovery phase (0.55 to 1.0): blade lifted, returning forward
				else:
					var p = (progress - 0.55) / 0.45
					sweep_angle = (1.0 - p) * 0.72
					dip_angle = sin(p * PI) * 0.18 # Lift blade up above water
			else:
				# Backwater (reverse) stroke
				var p = sin(progress * PI)
				sweep_angle = -p * 0.65 # Sweep forward towards bow
				dip_angle = -p * 0.22

			# Apply rotation to oar pivot:
			oars[index].rotation.y = side * sweep_angle
			oars[index].rotation.z = side * dip_angle

			# Animate rower character stroke
			if rower != null and rower.visible:
				var target_pitch: float
				var target_yaw: float
				var target_roll: float
				var base_yaw: float = side * deg_to_rad(8.0)

				if not is_rev:
					if progress < 0.55:
						# Drive phase: Rower reaches forward at catch, pulls torso back
						var p = progress / 0.55
						target_pitch = lerpf(-0.14, 0.22, p)
						target_yaw = base_yaw + (side * sin(p * PI) * 0.16)
						target_roll = -side * sin(p * PI) * 0.06
					else:
						# Recovery phase: Smoothly return torso forward for next stroke
						var p = (progress - 0.55) / 0.45
						target_pitch = lerpf(0.22, -0.14, sin(p * (PI * 0.5)))
						target_yaw = lerpf(base_yaw + side * 0.16, base_yaw, p)
						target_roll = lerpf(-side * 0.06, 0.0, p)
				else:
					# Reverse backwater stroke: push torso forward
					var p = sin(progress * PI)
					target_pitch = -p * 0.18
					target_yaw = base_yaw - (side * p * 0.12)
					target_roll = 0.0

				rower.rotation.x = lerpf(rower.rotation.x, target_pitch, 16.0 * delta)
				rower.rotation.y = lerpf(rower.rotation.y, target_yaw, 16.0 * delta)
				rower.rotation.z = lerpf(rower.rotation.z, target_roll, 16.0 * delta)
		else:
			# Resting position with gentle water bobbing for oar
			var rest_bob = sin(ambient_timer * 2.5 + index * 0.6) * 0.03
			oars[index].rotation.y = lerpf(oars[index].rotation.y, 0.0, 12.0 * delta)
			oars[index].rotation.z = lerpf(oars[index].rotation.z, rest_bob, 8.0 * delta)

			# Resting rower with idle breathing sway
			if rower != null and rower.visible:
				var base_yaw: float = side * deg_to_rad(8.0)
				var breath_pitch = sin(ambient_timer * 1.8 + index * 0.8) * 0.02
				var breath_roll = cos(ambient_timer * 1.4 + index * 0.6) * 0.015

				rower.rotation.x = lerpf(rower.rotation.x, breath_pitch, 8.0 * delta)
				rower.rotation.y = lerpf(rower.rotation.y, base_yaw, 8.0 * delta)
				rower.rotation.z = lerpf(rower.rotation.z, breath_roll, 8.0 * delta)

	# Dynamic boat hull roll, pitch, and gentle wave sway
	if boat_visual_root != null:
		var target_roll = -turn_speed * 0.14 # Boat heels into turns
		var target_pitch = clampf(-velocity.length() * 0.015, -0.05, 0.05) # Bow lifts on acceleration

		# Ambient river water rocking
		var wave_roll = sin(ambient_timer * 2.2) * 0.02 + sin(ambient_timer * 8.0) * water_turbulence * 0.07
		var wave_pitch = cos(ambient_timer * 1.8) * 0.015 + cos(ambient_timer * 6.5) * water_turbulence * 0.04
		var wave_heave = sin(ambient_timer * 3.0) * 0.025 + sin(ambient_timer * 9.0) * water_turbulence * 0.045

		visual_tilt.x = lerpf(visual_tilt.x, target_pitch + wave_pitch, 8.0 * delta)
		visual_tilt.z = lerpf(visual_tilt.z, target_roll + wave_roll, 8.0 * delta)

		boat_visual_root.rotation.x = visual_tilt.x
		boat_visual_root.rotation.z = visual_tilt.z
		boat_visual_root.position.y = wave_heave
