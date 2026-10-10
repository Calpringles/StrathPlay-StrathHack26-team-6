extends Node3D

# All hazard timing and damage are owned by the host. Clients render snapshots.
@export var crocodile_speed: float = 1.7
const CROCODILE_PATROL_WIDTH: float = 7.2

var river: Node3D
var boat: CharacterBody3D
var clock: float = 0.0
var snapshot_timer: float = 0.0
var crocodiles: Array[Node3D] = []
var water: MeshInstance3D
var fish_schools: Array[Node3D] = []

func _ready() -> void:
	river = get_parent()
	boat = river.get_node("Boat")
	water = river.get_node("RiverWater")
	_create_crocodiles()
	_create_fish_shadows()
	# Restore the close, forward-facing camera from the original river scene.
	river.camera.position = Vector3(0, 3.5, 5.2)
	river.camera.rotation_degrees.x = -20.0
	river.camera.fov = 75.0
	river.cam_base_pos = river.camera.position

func _mesh_bounds(node: Node3D, transform_so_far: Transform3D = Transform3D.IDENTITY) -> AABB:
	var accumulated = transform_so_far * node.transform
	var bounds = AABB()
	if node is MeshInstance3D and node.mesh != null:
		bounds = accumulated * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds = _mesh_bounds(child, accumulated)
			if child_bounds.size.length_squared() > 0.0:
				bounds = child_bounds if bounds.size.length_squared() == 0.0 else bounds.merge(child_bounds)
	return bounds

func _create_crocodiles() -> void:
	var scene: PackedScene = load("res://stylized_low_poly_crocodile/scene.gltf")
	if scene == null:
		return
	for i in range(9):
		var croc = Node3D.new()
		croc.name = "CrossingCrocodile%d" % i
		add_child(croc)
		var model: Node3D = scene.instantiate()
		var pivot = Node3D.new()
		croc.add_child(pivot)
		pivot.add_child(model)
		var bounds = _mesh_bounds(model)
		var length = maxf(bounds.size.x, bounds.size.z)
		if length > 0.0:
			var factor = 2.8 / length
			model.scale *= factor
			model.position = -bounds.get_center() * factor
			# Align the longest horizontal axis with the crossing direction.
			if bounds.size.z > bounds.size.x:
				pivot.rotation.y = PI / 2.0
		for animation_node in model.find_children("*", "AnimationPlayer", true, false):
			var animator: AnimationPlayer = animation_node
			if animator.has_animation("Idle"):
				animator.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
				animator.play("Idle")
		croc.set_meta("course_z", -85.0 - i * 100.0)
		croc.set_meta("activated_at", -1.0)
		croc.position = Vector3(-CROCODILE_PATROL_WIDTH, -0.12, float(croc.get_meta("course_z")))
		crocodiles.append(croc)
		# A surface wake makes the submerged animal readable from the camera.
		var wake = MeshInstance3D.new()
		var wake_mesh = TorusMesh.new()
		wake_mesh.inner_radius = 0.75
		wake_mesh.outer_radius = 0.85
		wake.mesh = wake_mesh
		wake.scale = Vector3(1.8, 0.15, 0.7)
		wake.position.y = 0.17
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.95, 0.94, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wake.material_override = mat
		croc.add_child(wake)

func _physics_process(delta: float) -> void:
	if river.game_state != river.GameState.PLAYING:
		if river.game_state == river.GameState.SUNK:
			boat.position.y = move_toward(boat.position.y, water.position.y - 1.8, delta * 0.65)
		_send_snapshot(delta)
		return
	if river._is_game_authority():
		clock += delta
		if boat.position.z <= -river.RIVER_LENGTH:
			river._trigger_victory()
		_update_crocodiles(true)
		_send_snapshot(delta)

func _send_snapshot(delta: float) -> void:
	if not river._is_game_authority() or not NetworkManager.is_connection_ready():
		return
	snapshot_timer += delta
	if snapshot_timer >= 0.1:
		snapshot_timer = 0.0
		var activation_times: Array = []
		for croc in crocodiles:
			activation_times.append(croc.get_meta("activated_at"))
		var hazards = river.get_node_or_null("RiverHazards")
		var tree_times: Array = hazards.get_tree_activation_times() if hazards != null else []
		for id in NetworkManager.get_loaded_game_peers():
			_sync_game_state.rpc_id(id, clock, river.boat_health, river.game_state, activation_times, river.victory_elapsed, river.victory_start_x, tree_times)

@rpc("authority", "unreliable_ordered")
func _sync_game_state(time: float, health: float, state: int, activation_times: Array, ending_time: float = 0.0, ending_x: float = 0.0, tree_times: Array = []) -> void:
	clock = time
	river.boat_health = health
	var hazards = river.get_node_or_null("RiverHazards")
	if hazards != null:
		hazards.set_tree_activation_times(tree_times)
	for i in range(mini(activation_times.size(), crocodiles.size())):
		crocodiles[i].set_meta("activated_at", activation_times[i])
	if state != river.game_state:
		if state == river.GameState.SUNK:
			river._trigger_game_over("The boat took too much hull damage.\nSteer around rocks, logs and crocodiles!")
		elif state == river.GameState.WON:
			river._trigger_victory()
	if state == river.GameState.WON:
		river.victory_elapsed = ending_time
		river.victory_start_x = ending_x

func _update_crocodiles(authority: bool) -> void:
	for i in range(crocodiles.size()):
		var croc = crocodiles[i]
		var z = float(croc.get_meta("course_z"))
		var activated = float(croc.get_meta("activated_at"))
		if authority and activated < 0.0 and boat.position.z - z < 28.0:
			activated = clock
			croc.set_meta("activated_at", activated)
		var progress = maxf(0.0, clock - activated) * crocodile_speed / CROCODILE_PATROL_WIDTH if activated >= 0.0 else 0.0
		var phase = progress - PI / 2.0
		var initial_direction = 1.0 if i % 2 == 0 else -1.0
		croc.position = Vector3(sin(phase) * CROCODILE_PATROL_WIDTH * initial_direction, water.position.y - 0.12 + sin(clock * 2.0 + i) * 0.035, z)
		# Ease into each bank turn instead of vanishing at the edge.
		var heading = smoothstep(-0.15, 0.15, cos(phase) * initial_direction)
		croc.rotation.y = lerpf(PI, 0.0, heading)
		croc.visible = true
		if authority and river.game_state == river.GameState.PLAYING:
			var touching = absf(boat.position.x - croc.position.x) < 2.1 and absf(boat.position.z - z) < 2.6
			if touching and river.apply_object_damage(croc, 12.0, "Crocodile! Keep rowing!"):
				boat.velocity *= 0.55

func _process(delta: float) -> void:
	if not river._is_game_authority() and river.game_state == river.GameState.PLAYING:
		clock += delta
	_update_crocodiles(false)
	_update_fish_shadows()

func _create_fish_shadows() -> void:
	var material = ShaderMaterial.new()
	material.shader = load("res://fish_shadow.gdshader")
	material.set_shader_parameter("water_center_z", water.position.z)
	var rng = RandomNumberGenerator.new()
	rng.seed = 81642
	for school_index in range(7):
		var school = Node3D.new()
		school.name = "FishSchool%d" % school_index
		school.set_meta("offset_z", -float(school_index) * 13.0 - 7.0)
		school.set_meta("phase", rng.randf_range(0.0, TAU))
		add_child(school)
		fish_schools.append(school)
		for fish_index in range(4):
			var fish = MeshInstance3D.new()
			var plane = PlaneMesh.new()
			plane.size = Vector2(rng.randf_range(0.7, 1.1), 0.4)
			fish.mesh = plane
			fish.material_override = material
			# Project soft silhouettes onto the surface so opaque deep water
			# cannot hide them. They follow the same waves as the river shader.
			fish.position = Vector3(rng.randf_range(-1.0, 1.0), 0.012, fish_index * 0.65)
			fish.set_meta("base_x", fish.position.x)
			fish.set_meta("phase", rng.randf_range(0.0, TAU))
			fish.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			school.add_child(fish)

func _update_fish_shadows() -> void:
	for school in fish_schools:
		var phase = float(school.get_meta("phase"))
		var t = clock * 0.22 + phase
		# Recycle only after a school has passed behind the camera.
		var z = float(school.get_meta("offset_z"))
		if z > boat.position.z + 14.0:
			z = boat.position.z - 70.0
			school.set_meta("offset_z", z)
		school.position = Vector3(sin(t) * 6.2, water.position.y, z)
		school.rotation.y = 0.0 if cos(t) >= 0.0 else PI
		for fish in school.get_children():
			fish.position.x = float(fish.get_meta("base_x")) + sin(clock * 2.8 + float(fish.get_meta("phase"))) * 0.12
