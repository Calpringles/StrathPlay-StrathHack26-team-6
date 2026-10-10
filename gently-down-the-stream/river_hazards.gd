extends Node3D

const TREE_WARNING: float = 3.0
const TREE_FALL_TIME: float = 1.4
const TREE_LENGTH: float = 9.0
const HULL_FLOOR_Y: float = 0.331
const WHIRL_RADIUS: float = 3.0

var river: Node3D
var boat: CharacterBody3D
var wildlife: Node3D
var trees: Array[Node3D] = []
var whirlpools: Array[MeshInstance3D] = []
var leak_nodes: Array[Node3D] = []
var bilge: MeshInstance3D
var jumping_fish: Array[Node3D] = []

func _ready() -> void:
	river = get_parent()
	boat = river.boat
	wildlife = river.get_node("RiverWildlife")
	_create_trees()
	_create_whirlpools()
	_clear_tree_lanes()
	_create_finale()
	_create_approach_debris()
	_create_leaks()
	_create_jumping_fish()

func _clear_tree_lanes() -> void:
	# Trees replace nearby static obstacle rows so their escape lane stays open.
	var obstacles = river.get_node_or_null("Obstacles")
	if obstacles == null:
		return
	for obstacle in obstacles.get_children():
		for tree in trees:
			if absf(obstacle.position.z - tree.position.z) < 8.0:
				obstacle.queue_free()
				break

func _material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat

func _add_mesh_instance(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _create_sphere_mesh(radius: float) -> SphereMesh:
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere

func _create_trees() -> void:
	var tree_assets = ["Tree_1_A_Color1.fbx", "Tree_3_A_Color1.fbx", "Tree_Bare_2_A_Color1.fbx"]
	for i in range(12):
		var tree = Node3D.new()
		tree.name = "TreeHazard%d" % i
		var side = 1.0 if i % 2 == 0 else -1.0
		tree.position = Vector3(side * 9.4, 0.15, -70.0 - i * 80.0)
		if i >= 9:
			tree.position.z = [-755.0, -925.0, -960.0][i - 9]
		tree.set_meta("side", side)
		tree.set_meta("triggered_at", -1.0)
		tree.set_meta("hit", false)
		tree.set_meta("body_name", "FallingTree%d" % i)
		add_child(tree)
		trees.append(tree)
		var body = AnimatableBody3D.new()
		body.name = "FallingTree%d" % i
		body.sync_to_physics = false
		tree.add_child(body)
		var scene: PackedScene = load("res://Game-Assets/GameWorld-Assets/fbx/" + tree_assets[i % tree_assets.size()])
		var model: Node3D = scene.instantiate()
		model.name = "SceneryTree"
		body.add_child(model)
		model.rotation.y = i * 0.73
		var bounds: AABB = wildlife._mesh_bounds(model)
		var factor = TREE_LENGTH / maxf(bounds.size.y, 0.01)
		model.scale *= factor
		# Place the imported trunk base on the falling pivot rather than
		# rotating around the model's inconsistent original origin.
		model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
		for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
			for surface_index in range(mesh_node.mesh.get_surface_count()):
				var original = mesh_node.get_active_material(surface_index)
				if original is StandardMaterial3D:
					var detailed = ShaderMaterial.new()
					detailed.shader = load("res://tree_surface.gdshader")
					detailed.set_shader_parameter("base_color", original.albedo_color)
					detailed.set_shader_parameter("use_texture", original.albedo_texture != null)
					if original.albedo_texture != null:
						detailed.set_shader_parameter("base_texture", original.albedo_texture)
					mesh_node.set_surface_override_material(surface_index, detailed)
		var collider = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.38
		capsule.height = TREE_LENGTH
		collider.shape = capsule
		collider.position.y = TREE_LENGTH / 2.0
		body.add_child(collider)

func get_tree_activation_times() -> Array:
	var times: Array = []
	for tree in trees:
		times.append(tree.get_meta("triggered_at"))
	return times

func set_tree_activation_times(times: Array) -> void:
	for i in range(mini(times.size(), trees.size())):
		trees[i].set_meta("triggered_at", times[i])

func update_trees(authority: bool) -> void:
	for tree in trees:
		var triggered = float(tree.get_meta("triggered_at"))
		var distance = boat.position.z - tree.position.z
		var warning_distance = maxf(28.0, maxf(0.0, -boat.velocity.z) * 4.5)
		if authority and triggered < 0.0 and distance >= -3.0 and distance < warning_distance:
			triggered = wildlife.clock
			tree.set_meta("triggered_at", triggered)
		if triggered < 0.0:
			continue
		var elapsed = maxf(0.0, wildlife.clock - triggered)
		var side = float(tree.get_meta("side"))
		var fall = clampf((elapsed - TREE_WARNING) / TREE_FALL_TIME, 0.0, 1.0)
		var angle = side * (fall * fall * PI / 2.0)
		if elapsed < TREE_WARNING:
			angle = side * (0.04 + sin(elapsed * 11.0) * 0.025)
		tree.get_node(tree.get_meta("body_name")).rotation.z = angle
		# The falling trunk can strike the boat before slide collisions occur.
		if authority and fall > 0.8 and fall < 1.0 and not tree.get_meta("hit"):
			var tip_x = tree.position.x - side * TREE_LENGTH * sin(absf(angle))
			if absf(distance) < 2.7 and boat.position.x >= minf(tip_x, tree.position.x) - 0.8 and boat.position.x <= maxf(tip_x, tree.position.x) + 0.8:
				tree.set_meta("hit", true)
				if river.damage_cooldown <= 0.0:
					river.apply_object_damage(tree.get_node(tree.get_meta("body_name")), 18.0, "Falling tree!")
					river.damage_cooldown = 0.8
					boat.velocity *= 0.6

func _create_whirlpools() -> void:
	for i in range(9):
		var plane = PlaneMesh.new()
		plane.size = Vector2(WHIRL_RADIUS * 2.0, WHIRL_RADIUS * 2.0)
		plane.subdivide_width = 24
		plane.subdivide_depth = 24
		var material = ShaderMaterial.new()
		material.shader = load("res://whirlpool.gdshader")
		var direction = 1.0 if i % 2 == 0 else -1.0
		material.set_shader_parameter("spin_direction", direction)
		var whirl = _add_mesh_instance(self, plane, Vector3(direction * 4.3, 0.055, -115.0 - i * 100.0), material)
		whirl.name = "Whirlpool%d" % i
		if i >= 7:
			whirl.position = Vector3(0, 0.055, -910.0 - (i - 7) * 35.0)
		whirl.set_meta("base_position", whirl.position)
		whirl.set_meta("phase", i * 1.7)
		whirl.set_meta("direction", direction)
		whirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		whirlpools.append(whirl)

func update_whirlpools() -> void:
	for i in range(whirlpools.size()):
		var whirl = whirlpools[i]
		var base: Vector3 = whirl.get_meta("base_position")
		var phase = float(whirl.get_meta("phase"))
		var amplitude = 3.8 if i >= 7 else 1.0
		whirl.position = base + Vector3(sin(wildlife.clock * 0.25 + phase) * amplitude, 0, cos(wildlife.clock * 0.18 + phase) * 1.8)

func _create_finale() -> void:
	var obstacles = river.get_node("Obstacles")
	var rng = RandomNumberGenerator.new()
	rng.seed = 4817
	# Both walls follow three sweeping bends with the same clear gap.
	for row in range(32):
		var progress = float(row) / 31.0
		var z = -780.0 - progress * 110.0
		var centre_x = sin(progress * TAU * 1.5) * 3.8
		for side in [-1, 1]:
			for layer in range(2):
				var width = rng.randf_range(1.7, 2.7)
				var x = centre_x + side * (4.2 + width / 2.0 + layer * 2.3)
				var rock = _create_scenery_rock(obstacles, Vector3(x, -0.25, z + rng.randf_range(-0.3, 0.3)), Vector3(width, rng.randf_range(1.2, 3.6), rng.randf_range(2.4, 3.8)), rng)
				rock.set_meta("corridor_centre", centre_x)
				rock.set_meta("rock_width", width)

func _create_scenery_rock(parent: Node3D, position: Vector3, size: Vector3, rng: RandomNumberGenerator) -> StaticBody3D:
	var assets = ["Rock_1_A", "Rock_1_D", "Rock_2_B", "Rock_2_F", "Rock_3_C", "Rock_3_H", "Rock_3_N"]
	var asset: String = assets[rng.randi_range(0, assets.size() - 1)]
	var scene: PackedScene = load("res://Game-Assets/GameWorld-Assets/fbx/" + asset + "_Color1.fbx")
	var rock = StaticBody3D.new()
	rock.name = "RockScenery"
	rock.position = position
	rock.add_to_group("river_damage_obstacle")
	rock.set_meta("rock_asset", asset)
	parent.add_child(rock)
	var model: Node3D = scene.instantiate()
	rock.add_child(model)
	model.rotation.y = rng.randf_range(0.0, TAU)
	var bounds: AABB = wildlife._mesh_bounds(model)
	# Scale the rotated model in a wrapper so the visible rock fits its collision.
	var wrapper = Node3D.new()
	rock.add_child(wrapper)
	model.reparent(wrapper)
	wrapper.scale = size / bounds.size
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position.y = size.y / 2.0
	rock.add_child(collider)
	return rock

func _create_approach_debris() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 7193
	var obstacles = river.get_node("Obstacles")
	var wood = _material(Color(0.32, 0.19, 0.09))
	for i in range(16):
		var z = -520.0 - i * 15.0
		# Leave space around falling trees and alternate the open side.
		var near_tree = false
		for tree in trees:
			if absf(tree.position.z - z) < 10.0:
				near_tree = true
		if near_tree:
			continue
		var side = 1.0 if i % 2 == 0 else -1.0
		_create_scenery_rock(obstacles, Vector3(side * rng.randf_range(4.8, 7.4), -0.25, z), Vector3(rng.randf_range(1.3, 2.3), rng.randf_range(0.9, 2.2), rng.randf_range(1.6, 2.8)), rng)
		if i % 3 == 0:
			river._spawn_log(obstacles, Vector3(-side * 5.7, 0.05, z - 6.0), 2.6, wood)
			var branch: Node3D = obstacles.get_child(obstacles.get_child_count() - 1)
			branch.rotation.y = rng.randf_range(-0.9, 0.9)
			var twig = CylinderMesh.new()
			twig.top_radius = 0.04
			twig.bottom_radius = 0.12
			twig.height = 1.4
			var fork = _add_mesh_instance(branch, twig, Vector3(0.3, 0.08, 0.4), wood)
			fork.rotation = Vector3(0.9, 0, -0.8)

func get_turbulence_at(position: Vector3) -> float:
	var intensity = 0.0
	for whirl in whirlpools:
		var offset = Vector2(position.x - whirl.position.x, position.z - whirl.position.z)
		intensity = maxf(intensity, clampf(1.0 - offset.length() / WHIRL_RADIUS, 0.0, 1.0))
	return intensity

func apply_whirlpool_forces(delta: float) -> void:
	update_whirlpools()
	if river.game_state != river.GameState.PLAYING:
		return
	for whirl in whirlpools:
		var offset = whirl.position - boat.position
		offset.y = 0.0
		var distance = offset.length()
		if distance >= WHIRL_RADIUS:
			continue
		var intensity = 1.0 - distance / WHIRL_RADIUS
		var inward = offset.normalized()
		var direction = float(whirl.get_meta("direction"))
		var tangent = Vector3(-inward.z, 0, inward.x) * direction
		boat.velocity += (inward * 4.0 + tangent * 3.0) * intensity * delta
		boat.velocity *= exp(-0.18 * intensity * delta)
		boat.turn_speed += direction * 0.7 * intensity * delta

func _create_leaks() -> void:
	var water_material = ShaderMaterial.new()
	water_material.shader = load("res://bilge_water.gdshader")
	var pool = PlaneMesh.new()
	pool.size = Vector2(1.0, 2.5)
	bilge = _add_mesh_instance(boat.boat_visual_root, pool, Vector3(0, HULL_FLOOR_Y + 0.014, 0), water_material)
	bilge.name = "HullWater"
	bilge.visible = false
	var crack_material = _material(Color(0.06, 0.035, 0.02))
	for i in range(4):
		var side = 1.0 if i % 2 == 0 else -1.0
		var leak = Node3D.new()
		leak.name = "HullLeak%d" % i
		leak.position = Vector3(side * 0.28, HULL_FLOOR_Y + 0.006, -0.9 + i * 0.6)
		leak.visible = false
		boat.boat_visual_root.add_child(leak)
		leak_nodes.append(leak)
		for segment in range(3):
			var crack = BoxMesh.new()
			crack.size = Vector3(0.028, 0.004, 0.13)
			var instance = _add_mesh_instance(leak, crack, Vector3(sin(segment * 2.0) * 0.035, 0, segment * 0.10), crack_material)
			instance.rotation.y = 0.45 if segment % 2 == 0 else -0.45
		var particles = CPUParticles3D.new()
		particles.name = "WaterSpurt"
		particles.amount = 14
		particles.lifetime = 0.6
		particles.direction = Vector3(-side * 0.1, 1, 0)
		particles.spread = 18.0
		particles.initial_velocity_min = 0.25
		particles.initial_velocity_max = 0.55
		particles.gravity = Vector3(0, -3, 0)
		particles.mesh = _create_sphere_mesh(0.035)
		particles.mesh.material = _material(Color(0.65, 0.9, 1.0))
		particles.emitting = false
		leak.add_child(particles)

func update_leaks() -> void:
	var thresholds = [85.0, 65.0, 40.0, 20.0]
	for i in range(leak_nodes.size()):
		var active = river.boat_health <= thresholds[i]
		leak_nodes[i].visible = active
		leak_nodes[i].get_node("WaterSpurt").emitting = active and river.game_state == river.GameState.PLAYING
	var damage = clampf(1.0 - river.boat_health / river.max_health, 0.0, 1.0)
	bilge.visible = damage > 0.15
	bilge.position.y = HULL_FLOOR_Y + lerpf(0.014, 0.14, damage)
	bilge.material_override.set_shader_parameter("damage", damage)

func _create_jumping_fish() -> void:
	for i in range(2):
		var fish = Node3D.new()
		fish.name = "JumpingFish%d" % i
		fish.set_meta("cycle", -1)
		fish.set_meta("start", Vector3.ZERO)
		add_child(fish)
		jumping_fish.append(fish)
		var material = _material(Color(0.2, 0.65, 0.85) if i == 0 else Color(0.9, 0.6, 0.17))
		var body = _add_mesh_instance(fish, _create_sphere_mesh(0.18), Vector3.ZERO, material)
		body.scale.z = 2.7
		var fin = PrismMesh.new()
		fin.size = Vector3(0.4, 0.035, 0.32)
		_add_mesh_instance(fish, fin, Vector3(0, 0, -0.5), material)
		var dorsal = PrismMesh.new()
		dorsal.size = Vector3(0.04, 0.22, 0.25)
		_add_mesh_instance(fish, dorsal, Vector3(0, 0.2, 0), material)
		for side in [-1, 1]:
			_add_mesh_instance(fish, _create_sphere_mesh(0.035), Vector3(side * 0.15, 0.055, 0.25), _material(Color(0.015, 0.03, 0.04)))
		var splash = MeshInstance3D.new()
		splash.name = "Splash"
		var ring = TorusMesh.new()
		ring.inner_radius = 0.42
		ring.outer_radius = 0.5
		splash.mesh = ring
		splash.scale.y = 0.15
		splash.material_override = _material(Color(0.8, 0.96, 1))
		add_child(splash)
		fish.set_meta("splash", splash.get_path())

func update_jumping_fish() -> void:
	for i in range(jumping_fish.size()):
		var fish = jumping_fish[i]
		var time = maxf(0.0, wildlife.clock - (6.0 + i * 7.0))
		var cycle = int(time / 17.0)
		var local_time = fmod(time, 17.0)
		var active = wildlife.clock >= 6.0 + i * 7.0 and local_time < 1.5 and river.game_state == river.GameState.PLAYING
		if active and cycle != int(fish.get_meta("cycle")):
			fish.set_meta("cycle", cycle)
			fish.set_meta("start", Vector3(boat.position.x + (-3.0 if i == 0 else 3.0), 0, boat.position.z - 9.0))
		fish.visible = active
		var splash: MeshInstance3D = get_node(fish.get_meta("splash"))
		splash.visible = active and (local_time < 0.25 or local_time > 1.1)
		if active:
			var progress = local_time / 1.5
			var start: Vector3 = fish.get_meta("start")
			start.x = clampf(start.x, -6.0, 6.0)
			fish.position = start + Vector3(0, sin(progress * PI) * 1.3 - 0.1, -progress * 3.0)
			fish.rotation = Vector3(cos(progress * PI) * 0.8, PI, 0)
			splash.position = start + Vector3(0, 0.06, -3.0 if local_time > 1.1 else 0.0)
			var scale_amount = 0.5 + fmod(local_time, 0.3) * 3.0
			splash.scale = Vector3(scale_amount, 0.15, scale_amount)

func _physics_process(_delta: float) -> void:
	if river.game_state == river.GameState.PLAYING and river._is_game_authority():
		update_trees(true)

func _process(_delta: float) -> void:
	update_whirlpools()
	update_trees(false)
	update_leaks()
	update_jumping_fish()
	boat.water_turbulence = get_turbulence_at(boat.position) if river.game_state == river.GameState.PLAYING else 0.0
