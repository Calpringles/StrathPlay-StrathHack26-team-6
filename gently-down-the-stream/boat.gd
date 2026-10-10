extends CharacterBody3D

# Which player this computer controls.
@export_range(1, 4) var player_number: int = 1

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
const OAR_POSITIONS: Array[Vector3] = [
	Vector3(-0.75, 0.0, -0.8), # Player 1: front left
	Vector3(0.75, 0.0, -0.8),  # Player 2: front right
	Vector3(-0.75, 0.0, 0.8),  # Player 3: rear left
	Vector3(0.75, 0.0, 0.8)    # Player 4: rear right
]


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	# Replace the previous two oars, including their child meshes.
	for old_name in ["LeftOar", "RightOar"]:
		var old_oar: Node = get_node_or_null(NodePath(old_name))
		if old_oar != null:
			remove_child(old_oar)
			old_oar.queue_free()

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
		mesh.size = Vector3(2.0, 0.1, 0.2)

		mesh_node.mesh = mesh
		mesh_node.material_override = material

		# Extend the oar outwards from its pivot.
		var side: float = signf(OAR_POSITIONS[index].x)
		mesh_node.position.x = side
		pivot.add_child(mesh_node)

		oars.append(pivot)
		stroke_timers.append(0.0)


func _physics_process(delta: float) -> void:
	for index in range(stroke_timers.size()):
		stroke_timers[index] = maxf(
			0.0, stroke_timers[index] - delta
		)

	# This computer's mouse controls its assigned oar.
	if Input.is_action_just_pressed("row"):
		row_oar(player_number - 1)

	# Water resistance and downstream current.
	var current: Vector3 = Vector3(0.0, 0.0, -current_speed)
	velocity = current + (velocity - current) * exp(-water_drag * delta)
	velocity.y = 0.0

	rotate_y(turn_speed * delta)
	turn_speed *= exp(-turn_drag * delta)

	move_and_slide()
	global_position.x = clampf(global_position.x, -8.0, 8.0)

	# Each oar animates independently.
	for index in range(oars.size()):
		var side: float = signf(OAR_POSITIONS[index].x)
		oars[index].rotation.y = (
			side * stroke_angle(stroke_timers[index])
		)


func row_oar(index: int) -> void:
	if index < 0 or index >= oars.size():
		return

	if stroke_timers[index] > 0.0:
		return

	var forward: Vector3 = -global_transform.basis.z
	var side: float = signf(OAR_POSITIONS[index].x)

	velocity += forward * stroke_power

	# Left oars turn right; right oars turn left.
	turn_speed += side * turn_power
	stroke_timers[index] = stroke_duration


func stroke_angle(timer: float) -> float:
	if timer <= 0.0:
		return 0.0

	var progress: float = 1.0 - timer / stroke_duration
	return sin(progress * PI) * 0.8
