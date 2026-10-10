# res://river.gd
extends Node3D

# --- River Course Settings ---
const RIVER_WIDTH: float = 18.0 # From X = -9.0 to +9.0
const RIVER_LENGTH: float = 1000.0 # 1000 meters to finish line
const OBSTACLE_SEED: int = 42819
const WATERFALL_Z: float = -1018.0
@export var preview_mode: bool = false
var victory_elapsed: float = 0.0
var victory_start_x: float = 0.0
var victory_title: Label
var game_over_description: Label

enum GameState { PLAYING, WON, SUNK }
var game_state: GameState = GameState.PLAYING

# --- Gameplay Stats ---
var boat_health: float = 100.0
var max_health: float = 100.0
var distance_traveled: float = 0.0
var sync_combos: int = 0
var elapsed_time: float = 0.0

# --- References ---
@onready var boat: CharacterBody3D = $Boat
@onready var camera: Camera3D = $Boat/Camera3D
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D

# Camera Shake
var shake_intensity: float = 0.0
var cam_base_pos: Vector3 = Vector3(0, 2.5, 3.8)

# UI Elements (built dynamically in _create_hud)
var hud_layer: CanvasLayer
var health_bar: ProgressBar
var health_label: Label
var distance_bar: ProgressBar
var distance_label: Label
var speed_label: Label
var notification_banner: PanelContainer
var notification_label: Label
var notif_timer: float = 0.0
var seat_cards: Array[PanelContainer] = []
var game_over_panel: PanelContainer
var victory_panel: PanelContainer
var damage_flash_rect: ColorRect

# Damage cooldown
var damage_cooldown: float = 0.0
var damaged_objects: Dictionary = {}
const OBJECT_DAMAGE_INTERVAL: float = 2.0

func _ready() -> void:
	_create_environment()
	_create_river_bed_and_water()
	_create_river_banks()
	_create_mountain_backdrop()
	_generate_obstacles()
	_decorate_banks()
	if preview_mode:
		boat.set_physics_process(false)
		camera.set_as_top_level(true)
		camera.global_position = Vector3(7, 4.5, 9)
		camera.look_at(Vector3(0, 0.7, -22), Vector3.UP)
		return
	_create_start_banner()
	_create_finish_line()
	_create_waterfall()
	_create_hud()
	var wildlife = Node3D.new()
	wildlife.name = "RiverWildlife"
	wildlife.set_script(load("res://river_wildlife.gd"))
	add_child(wildlife)
	var hazards = Node3D.new()
	hazards.name = "RiverHazards"
	hazards.set_script(load("res://river_hazards.gd"))
	add_child(hazards)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.call_deferred("notify_game_loaded")

	# Connect boat sync and damage events
	if boat.has_signal("sync_row_achieved"):
		boat.sync_row_achieved.connect(_on_boat_sync_row)

	# Camera initial setup
	if camera != null:
		cam_base_pos = camera.position

func _create_environment() -> void:
	# Use the imported cloud/sky package for a softly moving daylight sky.
	var env_node: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		var env: Environment = Environment.new()
		
		var sky: Sky = Sky.new()
		sky.sky_material = load("res://river_sky.tres")
		sky.process_mode = Sky.PROCESS_MODE_REALTIME
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		env.background_mode = Environment.BG_SKY
		env.sky = sky

		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.58
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.fog_enabled = true
		env.fog_light_color = Color("#9fc9d0")
		env.fog_density = 0.0012
		env.fog_height = 2.0
		env.fog_height_density = 0.018
		# Fog may soften distant scenery without replacing the cloud sky.
		env.fog_sky_affect = 0.0
		env_node.environment = env
		add_child(env_node)
	if env_node.environment == null:
		env_node.environment = Environment.new()

	# Always apply the restrained river look, including when the scene already
	# contains a WorldEnvironment resource.
	var active_env: Environment = env_node.environment
	var muted_sky: Sky = Sky.new()
	muted_sky.sky_material = load("res://river_sky.tres")
	muted_sky.process_mode = Sky.PROCESS_MODE_REALTIME
	muted_sky.radiance_size = Sky.RADIANCE_SIZE_128
	active_env.background_mode = Environment.BG_SKY
	active_env.sky = muted_sky
	active_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	active_env.ambient_light_energy = 0.38
	active_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	active_env.tonemap_exposure = 0.72
	active_env.fog_enabled = true
	active_env.fog_light_color = Color("#87979a")
	active_env.fog_density = 0.0025
	active_env.fog_sky_affect = 0.0

	if directional_light != null:
		directional_light.light_color = Color("#fff8e7")
		directional_light.light_energy = 0.65
		directional_light.shadow_enabled = true
		directional_light.rotation_degrees = Vector3(-45, -30, 0)

func _create_mountain_backdrop() -> void:
	var mountains = Node3D.new()
	mountains.name = "MountainBackdrop"
	add_child(mountains)
	var random = RandomNumberGenerator.new()
	random.seed = 91735
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	for side in [-1, 1]:
		for layer in range(2):
			for index in range(16):
				var height = random.randf_range(22, 38) if layer == 0 else random.randf_range(38, 64)
				var radius = random.randf_range(28, 42) if layer == 0 else random.randf_range(45, 65)
				var surface = SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				var rings: Array = []
				for tier in range(4):
					var ring: Array[Vector3] = []
					var tier_radius = [1.0, 0.52, 0.2, 0.0][tier]
					var tier_height = [0.0, 0.5, 0.82, 1.0][tier]
					for point in range(10):
						var angle = TAU * point / 10.0
						var width = radius * tier_radius * random.randf_range(0.85, 1.15)
						ring.append(Vector3(cos(angle) * width + tier * 1.5, height * tier_height, sin(angle) * width))
					rings.append(ring)
				for tier in range(3):
					for point in range(10):
						var next = (point + 1) % 10
						var faces = [[rings[tier][point], rings[tier + 1][point], rings[tier][next]], [rings[tier][next], rings[tier + 1][point], rings[tier + 1][next]]]
						for face in faces:
							for vertex in face:
								var lower_color = Color("#587754") if layer == 0 else Color("#607d87")
								var upper_color = Color("#8c9690") if layer == 0 else Color("#c4ccc7")
								surface.set_color(lower_color.lerp(upper_color, vertex.y / height))
								surface.add_vertex(vertex)
				surface.generate_normals()
				var mountain = MeshInstance3D.new()
				mountain.mesh = surface.commit()
				mountain.material_override = material
				mountain.position = Vector3(side * random.randf_range(70 + layer * 70, 85 + layer * 70), 0.0, 130.0 - index * 90.0 + random.randf_range(-15, 15))
				mountains.add_child(mountain)

func _create_river_bed_and_water() -> void:
	# 1. Flowing Realistic River Water Surface
	var water_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	water_mesh_inst.name = "RiverWater"
	var water_plane: PlaneMesh = PlaneMesh.new()
	water_plane.size = Vector2(RIVER_WIDTH, 100.0 - WATERFALL_Z)
	water_plane.subdivide_width = 16
	water_plane.subdivide_depth = 160
	water_mesh_inst.mesh = water_plane

	# Apply Realistic Water Shader with Procedural Normal Maps
	var water_shader = load("res://realistic_water.gdshader")
	if water_shader:
		var water_mat: ShaderMaterial = ShaderMaterial.new()
		water_mat.shader = water_shader

		# Procedural Normal Map 1
		var n1 = FastNoiseLite.new()
		n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n1.frequency = 0.035
		var tex1 = NoiseTexture2D.new()
		tex1.width = 256
		tex1.height = 256
		tex1.seamless = true
		tex1.as_normal_map = true
		tex1.bump_strength = 2.5
		tex1.noise = n1
		water_mat.set_shader_parameter("texture_normal1", tex1)

		# Procedural Normal Map 2
		var n2 = FastNoiseLite.new()
		n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n2.frequency = 0.05
		var tex2 = NoiseTexture2D.new()
		tex2.width = 256
		tex2.height = 256
		tex2.seamless = true
		tex2.as_normal_map = true
		tex2.bump_strength = 2.0
		tex2.noise = n2
		water_mat.set_shader_parameter("texture_normal2", tex2)

		water_mat.set_shader_parameter("shallow_color", Color(0.22, 0.65, 0.76, 0.65))
		water_mat.set_shader_parameter("deep_color", Color(0.04, 0.22, 0.36, 0.94))
		water_mat.set_shader_parameter("foam_color", Color(0.92, 0.96, 1.0, 1.0))
		water_mat.set_shader_parameter("wave_speed1", Vector2(0.015, 0.08))
		water_mat.set_shader_parameter("wave_speed2", Vector2(-0.02, 0.05))
		water_mat.set_shader_parameter("wave_scale", 0.06)
		water_mat.set_shader_parameter("wave_strength", 0.4)
		water_mat.set_shader_parameter("depth_distance", 2.5)
		water_mat.set_shader_parameter("foam_distance", 0.35)
		water_mat.set_shader_parameter("fresnel_power", 3.5)

		water_mesh_inst.material_override = water_mat
	else:
		var water_mat: StandardMaterial3D = StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.14, 0.48, 0.68, 0.85)
		water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_mesh_inst.material_override = water_mat

	water_mesh_inst.position = Vector3(0.0, 0.0, (100.0 + WATERFALL_Z) / 2.0)
	add_child(water_mesh_inst)

	# 2. River Bed (bottom under water)
	var bed_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	bed_mesh_inst.name = "RiverBed"
	var bed_plane: PlaneMesh = PlaneMesh.new()
	bed_plane.size = Vector2(RIVER_WIDTH + 2.0, 100.0 - WATERFALL_Z)
	bed_mesh_inst.mesh = bed_plane

	var bed_mat: StandardMaterial3D = StandardMaterial3D.new()
	bed_mat.albedo_color = Color("#2a3b2c") # Dark mossy river bottom
	bed_mat.roughness = 0.95
	bed_mesh_inst.material_override = bed_mat
	bed_mesh_inst.position = Vector3(0.0, -1.8, (100.0 + WATERFALL_Z) / 2.0)
	add_child(bed_mesh_inst)

# Mathematical terrain height function so trees, props, and ground mesh share the EXACT same elevation
func get_ground_height(x: float, _z: float) -> float:
	var dist_from_river = absf(x) - (RIVER_WIDTH / 2.0)
	if dist_from_river <= 0.0:
		return 0.0 # River channel stays level with water surface

	# The surrounding banks are intentionally one continuous, flat grass plane.
	# Keeping this function shared means every decoration is placed on exactly
	# the same level as the terrain mesh.
	return 0.12

func _create_river_banks() -> void:
	var bank_mat: StandardMaterial3D = StandardMaterial3D.new()
	bank_mat.albedo_color = Color("#42732e") # Lush green grassy landscape
	bank_mat.roughness = 0.88

	var bank_half_x: float = RIVER_WIDTH / 2.0 # 9.0
	const TERRAIN_WIDTH: float = 250.0          # 250m of flat grassland on each side
	const TERRAIN_X_STEPS: int = 8
	const TERRAIN_Z_STEPS: int = 80
	var z_total_len: float = 50.0 - WATERFALL_Z

	# 1. Low shoreline collision boundary so the boat physically stays contained in the river
	var bank_thickness: float = 4.0
	var bank_height: float = 0.8
	for side in [-1.0, 1.0]:
		var bank_body: StaticBody3D = StaticBody3D.new()
		bank_body.name = "Bank_Collider_Left" if side < 0 else "Bank_Collider_Right"
		bank_body.position = Vector3(side * (bank_half_x + bank_thickness / 2.0), 0.0, (50.0 + WATERFALL_Z) / 2.0)
		add_child(bank_body)

		var col: CollisionShape3D = CollisionShape3D.new()
		var col_box: BoxShape3D = BoxShape3D.new()
		col_box.size = Vector3(bank_thickness, bank_height, z_total_len)
		col.shape = col_box
		bank_body.add_child(col)

	# 2. Procedural continuous rolling terrain meshes on Left and Right sides
	for side in [-1.0, 1.0]:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(bank_mat)

		for zi in range(TERRAIN_Z_STEPS):
			var z0 = 50.0 - (float(zi) / float(TERRAIN_Z_STEPS)) * z_total_len
			var z1 = 50.0 - (float(zi + 1) / float(TERRAIN_Z_STEPS)) * z_total_len

			for xi in range(TERRAIN_X_STEPS):
				var tx0 = float(xi) / float(TERRAIN_X_STEPS)
				var tx1 = float(xi + 1) / float(TERRAIN_X_STEPS)

				var x0_dist = bank_half_x + tx0 * TERRAIN_WIDTH
				var x1_dist = bank_half_x + tx1 * TERRAIN_WIDTH

				var p0_x = side * x0_dist
				var p1_x = side * x1_dist

				var p00 = Vector3(p0_x, get_ground_height(p0_x, z0), z0)
				var p10 = Vector3(p1_x, get_ground_height(p1_x, z0), z0)
				var p01 = Vector3(p0_x, get_ground_height(p0_x, z1), z1)
				var p11 = Vector3(p1_x, get_ground_height(p1_x, z1), z1)

				var uv00 = Vector2(tx0, z0 * 0.05)
				var uv10 = Vector2(tx1, z0 * 0.05)
				var uv01 = Vector2(tx0, z1 * 0.05)
				var uv11 = Vector2(tx1, z1 * 0.05)

				if side > 0.0:
					st.set_uv(uv00); st.add_vertex(p00)
					st.set_uv(uv10); st.add_vertex(p10)
					st.set_uv(uv01); st.add_vertex(p01)

					st.set_uv(uv10); st.add_vertex(p10)
					st.set_uv(uv11); st.add_vertex(p11)
					st.set_uv(uv01); st.add_vertex(p01)
				else:
					st.set_uv(uv10); st.add_vertex(p10)
					st.set_uv(uv00); st.add_vertex(p00)
					st.set_uv(uv01); st.add_vertex(p01)

					st.set_uv(uv11); st.add_vertex(p11)
					st.set_uv(uv10); st.add_vertex(p10)
					st.set_uv(uv01); st.add_vertex(p01)

		st.generate_normals()
		var terrain_mesh = st.commit()
		var terrain_inst = MeshInstance3D.new()
		terrain_inst.name = "Terrain_Left" if side < 0 else "Terrain_Right"
		terrain_inst.mesh = terrain_mesh
		terrain_inst.material_override = bank_mat
		add_child(terrain_inst)

		# Solid flat grass slab. This guarantees the extended bank is visible
		# from every camera angle, including from below the one-sided terrain
		# surface generated above.
		var flat_ground := MeshInstance3D.new()
		flat_ground.name = "FlatGrassPlane_Left" if side < 0 else "FlatGrassPlane_Right"
		var flat_mesh := BoxMesh.new()
		flat_mesh.size = Vector3(TERRAIN_WIDTH, 0.24, z_total_len)
		flat_ground.mesh = flat_mesh
		flat_ground.material_override = bank_mat
		flat_ground.position = Vector3(
			side * (bank_half_x + TERRAIN_WIDTH * 0.5),
			0.0,
			(50.0 + WATERFALL_Z) / 2.0
		)
		add_child(flat_ground)

		# Match physics to the generated terrain so props and the boat never pass
		# through a flat invisible plane beneath the hills.
		var terrain_body := StaticBody3D.new()
		terrain_body.name = "TerrainCollision_Left" if side < 0 else "TerrainCollision_Right"
		var terrain_shape := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(terrain_mesh.get_faces())
		terrain_shape.shape = concave
		terrain_body.add_child(terrain_shape)
		add_child(terrain_body)

func _settle_decoration(inst: Node3D, x: float, z: float) -> void:
	# Asset pivots are inconsistent: some are at the feet, others at the
	# mesh centre. Imported FBX files also contain nested transforms, so the
	# bounds must be measured in world space rather than by local offsets.
	var lowest := INF
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh != null:
				var aabb := mesh_node.get_aabb()
				# Test all eight corners because imported meshes may be rotated.
				for corner in [
					Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
					Vector3(aabb.end.x, aabb.position.y, aabb.position.z),
					Vector3(aabb.position.x, aabb.end.y, aabb.position.z),
					Vector3(aabb.end.x, aabb.end.y, aabb.position.z),
					Vector3(aabb.position.x, aabb.position.y, aabb.end.z),
					Vector3(aabb.end.x, aabb.position.y, aabb.end.z),
					Vector3(aabb.position.x, aabb.end.y, aabb.end.z),
					Vector3(aabb.end.x, aabb.end.y, aabb.end.z)
				]:
					lowest = minf(lowest, (mesh_node.global_transform * corner).y)
		for child in node.get_children():
			stack.append(child)
	if lowest == INF:
		lowest = 0.0
	# The asset is initially placed at the terrain height. Move its lowest
	# world-space point onto that same height, leaving a tiny safety margin.
	inst.position.y += get_ground_height(x, z) - lowest + 0.02

func _decorate_banks() -> void:
	const ASSET_BASE = "res://Game-Assets/GameWorld-Assets/fbx/"
	const DECO_SEED: int = 77341

	# --- Asset lists by category ---
	var tree_assets: Array[String] = [
		"Tree_1_A_Color1.fbx", "Tree_1_B_Color1.fbx", "Tree_1_C_Color1.fbx",
		"Tree_2_A_Color1.fbx", "Tree_2_B_Color1.fbx", "Tree_2_C_Color1.fbx",
		"Tree_2_D_Color1.fbx", "Tree_3_A_Color1.fbx", "Tree_3_B_Color1.fbx",
		"Tree_4_A_Color1.fbx", "Tree_4_B_Color1.fbx",
		"Tree_Bare_1_A_Color1.fbx", "Tree_Bare_1_B_Color1.fbx",
		"Tree_Bare_2_A_Color1.fbx", "Tree_Bare_2_B_Color1.fbx",
	]
	var bush_assets: Array[String] = [
		"Bush_1_A_Color1.fbx", "Bush_1_B_Color1.fbx", "Bush_1_C_Color1.fbx",
		"Bush_1_D_Color1.fbx", "Bush_2_A_Color1.fbx", "Bush_2_B_Color1.fbx",
		"Bush_3_A_Color1.fbx", "Bush_3_B_Color1.fbx",
		"Bush_4_A_Color1.fbx", "Bush_4_B_Color1.fbx",
	]
	var rock_assets: Array[String] = [
		"Rock_1_A_Color1.fbx", "Rock_1_B_Color1.fbx", "Rock_1_C_Color1.fbx",
		"Rock_1_D_Color1.fbx", "Rock_2_A_Color1.fbx", "Rock_2_B_Color1.fbx",
		"Rock_2_C_Color1.fbx", "Rock_3_A_Color1.fbx", "Rock_3_B_Color1.fbx",
		"Rock_3_C_Color1.fbx",
	]
	var grass_assets: Array[String] = [
		"Grass_1_A_Color1.fbx", "Grass_1_B_Color1.fbx",
		"Grass_2_A_Color1.fbx", "Grass_2_B_Color1.fbx",
	]

	# Pre-load all assets that actually exist on disk
	var loaded: Dictionary = {}
	for asset_list in [tree_assets, bush_assets, rock_assets, grass_assets]:
		for filename in asset_list:
			var path = ASSET_BASE + filename
			if not loaded.has(filename) and ResourceLoader.exists(path):
				loaded[filename] = load(path)

	if loaded.is_empty():
		push_warning("_decorate_banks: No GameWorld-Assets found at %s" % ASSET_BASE)
		return

	var deco_root: Node3D = Node3D.new()
	deco_root.name = "BankDecoration"
	add_child(deco_root)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = DECO_SEED

	# River half-width is 9m. Banks start just outside that.
	# Left bank is at X < -9, Right bank is at X > 9
	# We place decoration in rows stepping down Z (downstream = -Z)
	const BANK_START_X: float = 10.5    # Edge of water channel
	const BANK_NEAR_X: float = 14.0     # Close shoreline strip (bushes/grass/small rocks)
	const BANK_MID_X: float = 22.0      # Mid-bank (main trees and rocks)
	const BANK_FAR_X: float = 36.0      # Far hillside (tall trees)
	const Z_START: float = 20.0         # Start decorating 20m in front of spawn
	const Z_STEP_NEAR: float = 8.0      # Spacing for close shoreline items
	const Z_STEP_MID: float = 14.0      # Spacing for mid-bank trees
	const Z_STEP_FAR: float = 22.0      # Spacing for far hill trees

	for side_sign in [-1.0, 1.0]:
		var z: float = -Z_START

		# --- NEAR SHORELINE: grass tufts and small rocks hugging the water ---
		z = -Z_START
		while z > -(RIVER_LENGTH - 30.0):
			var category = rng.randi_range(0, 2)
			var asset_name: String = ""
			if category == 0:
				# Grass tuft
				asset_name = grass_assets[rng.randi_range(0, grass_assets.size() - 1)]
			elif category == 1:
				# Small bush right at the waterline
				asset_name = bush_assets[rng.randi_range(0, 3)]  # Bush_1 variety
			else:
				# Small shoreline rock
				asset_name = rock_assets[rng.randi_range(0, rock_assets.size() - 1)]

			if loaded.has(asset_name):
				var inst: Node3D = (loaded[asset_name] as PackedScene).instantiate()
				var x_pos = side_sign * rng.randf_range(BANK_START_X, BANK_NEAR_X)
				var ground_y = get_ground_height(x_pos, z)
				inst.position = Vector3(x_pos, ground_y, z)
				inst.rotation_degrees.y = rng.randf_range(0.0, 360.0)
				var asset_scale = rng.randf_range(0.55, 1.0)
				inst.scale = Vector3(asset_scale, asset_scale, asset_scale)
				deco_root.add_child(inst)
				_settle_decoration(inst, x_pos, z)

			z -= Z_STEP_NEAR + rng.randf_range(-2.0, 2.0)

		# --- MID BANK: main trees, larger bushes, and boulders ---
		z = -Z_START
		while z > -(RIVER_LENGTH - 30.0):
			var category = rng.randi_range(0, 3)
			var asset_name: String = ""
			if category == 0 or category == 1:
				# Leafy tree (most common)
				asset_name = tree_assets[rng.randi_range(0, tree_assets.size() - 1)]
			elif category == 2:
				# Dense bush cluster
				asset_name = bush_assets[rng.randi_range(0, bush_assets.size() - 1)]
			else:
				# Mid-size boulder
				asset_name = rock_assets[rng.randi_range(0, rock_assets.size() - 1)]

			if loaded.has(asset_name):
				var inst: Node3D = (loaded[asset_name] as PackedScene).instantiate()
				var x_pos = side_sign * rng.randf_range(BANK_NEAR_X, BANK_MID_X)
				var ground_y = get_ground_height(x_pos, z)
				inst.position = Vector3(x_pos, ground_y, z)
				inst.rotation_degrees.y = rng.randf_range(0.0, 360.0)
				var asset_scale = rng.randf_range(0.9, 1.5)
				inst.scale = Vector3(asset_scale, asset_scale, asset_scale)
				deco_root.add_child(inst)
				_settle_decoration(inst, x_pos, z)

			# Occasionally add a second tree right next to the first (tree cluster)
			if rng.randf() < 0.35:
				var twin_name = tree_assets[rng.randi_range(0, tree_assets.size() - 1)]
				if loaded.has(twin_name):
					var twin: Node3D = (loaded[twin_name] as PackedScene).instantiate()
					var twin_z = z + rng.randf_range(-4.0, 4.0)
					var x_twin = side_sign * rng.randf_range(BANK_NEAR_X + 2.0, BANK_MID_X + 4.0)
					var twin_ground_y = get_ground_height(x_twin, twin_z)
					twin.position = Vector3(x_twin, twin_ground_y, twin_z)
					twin.rotation_degrees.y = rng.randf_range(0.0, 360.0)
					var secondary_scale = rng.randf_range(0.8, 1.3)
					twin.scale = Vector3(secondary_scale, secondary_scale, secondary_scale)
					deco_root.add_child(twin)
					_settle_decoration(twin, x_twin, twin_z)

			z -= Z_STEP_MID + rng.randf_range(-3.0, 3.0)

		# --- FAR HILLSIDE: tall trees creating a dense horizon silhouette ---
		z = -Z_START * 0.5
		while z > -(RIVER_LENGTH - 20.0):
			var asset_name = tree_assets[rng.randi_range(0, tree_assets.size() - 1)]
			if loaded.has(asset_name):
				var inst: Node3D = (loaded[asset_name] as PackedScene).instantiate()
				var x_pos = side_sign * rng.randf_range(BANK_MID_X, BANK_FAR_X)
				var ground_y = get_ground_height(x_pos, z)
				inst.position = Vector3(x_pos, ground_y, z)
				inst.rotation_degrees.y = rng.randf_range(0.0, 360.0)
				var asset_scale = rng.randf_range(1.4, 2.2)
				inst.scale = Vector3(asset_scale, asset_scale, asset_scale)
				deco_root.add_child(inst)
				_settle_decoration(inst, x_pos, z)

			z -= Z_STEP_FAR + rng.randf_range(-4.0, 4.0)

func _generate_obstacles() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = OBSTACLE_SEED

	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = Color("#4a4742") # Grey river stone
	rock_mat.roughness = 0.85

	var log_mat: StandardMaterial3D = StandardMaterial3D.new()
	log_mat.albedo_color = Color("#543821") # Dark wet log
	log_mat.roughness = 0.8

	var obstacles_container: Node3D = Node3D.new()
	obstacles_container.name = "Obstacles"
	add_child(obstacles_container)

	# Generate obstacle rows every 28 to 35 meters along the river
	var current_z: float = -45.0
	while current_z > -(RIVER_LENGTH - 60.0):
		if current_z < -720.0:
			break # The finale uses a deliberate course instead of random rows.
		var pattern = rng.randi_range(0, 3)

		if pattern == 0:
			# Single big boulder in mid-left or mid-right
			var pos_x = rng.randf_range(-5.5, 5.5)
			_spawn_rock(obstacles_container, Vector3(pos_x, 0.2, current_z), rng.randf_range(1.6, 2.4), rock_mat)

		elif pattern == 1:
			# Split boulders: forces players to steer through center or sides
			_spawn_rock(obstacles_container, Vector3(-4.8, 0.2, current_z), 2.0, rock_mat)
			_spawn_rock(obstacles_container, Vector3(4.8, 0.2, current_z), 2.0, rock_mat)

		elif pattern == 2:
			# Driftwood log blocking partial river lane
			var log_x = rng.randf_range(-3.5, 3.5)
			var log_len = rng.randf_range(5.0, 7.5)
			_spawn_log(obstacles_container, Vector3(log_x, 0.05, current_z), log_len, log_mat)

		elif pattern == 3:
			# Rapids / Fast water stretch: 3 scattered small rocks
			var x1 = rng.randf_range(-6.0, -1.5)
			var x2 = rng.randf_range(1.5, 6.0)
			_spawn_rock(obstacles_container, Vector3(x1, 0.1, current_z), 1.5, rock_mat)
			_spawn_rock(obstacles_container, Vector3(x2, 0.1, current_z + 8.0), 1.5, rock_mat)

		current_z -= rng.randf_range(30.0, 42.0)

func _spawn_rock(parent: Node3D, pos: Vector3, radius: float, mat: Material) -> void:
	var rock: StaticBody3D = StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("river_damage_obstacle")
	rock.collision_layer = 1
	rock.collision_mask = 1
	rock.position = pos
	parent.add_child(rock)

	var col: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius * 0.95
	col.shape = sphere
	rock.add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.6
	mesh_inst.mesh = mesh
	mesh_inst.material_override = mat
	mesh_inst.scale = Vector3(1.1, 0.75, 1.2)
	rock.add_child(mesh_inst)

func _spawn_log(parent: Node3D, pos: Vector3, length: float, mat: Material) -> void:
	var log_body: StaticBody3D = StaticBody3D.new()
	log_body.name = "Log"
	log_body.add_to_group("river_damage_obstacle")
	log_body.collision_layer = 1
	log_body.collision_mask = 1
	log_body.position = pos
	parent.add_child(log_body)

	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(length, 0.6, 0.8)
	col.shape = box
	log_body.add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = length
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.rotation_degrees.z = 90.0 # Lay horizontal across river
	log_body.add_child(mesh_inst)

func _create_finish_line() -> void:
	var finish_z: float = -RIVER_LENGTH
	var finish_node: Node3D = Node3D.new()
	finish_node.name = "FinishLine"
	finish_node.position = Vector3(0.0, 0.0, finish_z)
	add_child(finish_node)

	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#8b5a2b")

	var banner_mat: StandardMaterial3D = StandardMaterial3D.new()
	banner_mat.albedo_color = Color("#176b70")

	# Archway Pillars
	for side in [-1.0, 1.0]:
		var pillar: MeshInstance3D = MeshInstance3D.new()
		var p_mesh: CylinderMesh = CylinderMesh.new()
		p_mesh.top_radius = 0.35
		p_mesh.bottom_radius = 0.4
		p_mesh.height = 7.0
		pillar.mesh = p_mesh
		pillar.material_override = wood_mat
		pillar.position = Vector3(side * 8.2, 3.5, 0.0)
		finish_node.add_child(pillar)

	# Crossbeam
	var beam: MeshInstance3D = MeshInstance3D.new()
	var b_mesh: BoxMesh = BoxMesh.new()
	b_mesh.size = Vector3(17.0, 0.5, 0.5)
	beam.mesh = b_mesh
	beam.material_override = wood_mat
	beam.position = Vector3(0.0, 6.8, 0.0)
	finish_node.add_child(beam)

	# Banner
	var banner: MeshInstance3D = MeshInstance3D.new()
	var ban_mesh: BoxMesh = BoxMesh.new()
	ban_mesh.size = Vector3(15.0, 2.0, 0.1)
	banner.mesh = ban_mesh
	banner.material_override = banner_mat
	banner.position = Vector3(0.0, 5.8, 0.0)
	finish_node.add_child(banner)
	var trim = MeshInstance3D.new()
	var trim_mesh = BoxMesh.new()
	trim_mesh.size = Vector3(15.5, 2.4, 0.08)
	trim.mesh = trim_mesh
	var trim_material = StandardMaterial3D.new()
	trim_material.albedo_color = Color("#e8bf72")
	trim.material_override = trim_material
	trim.position = Vector3(0, 5.8, -0.08)
	finish_node.add_child(trim)

	# 3D Label
	var finish_lbl: Label3D = Label3D.new()
	finish_lbl.text = "Congratulations!"
	finish_lbl.font_size = 96
	finish_lbl.pixel_size = 0.008
	var bold_font = SystemFont.new()
	bold_font.font_names = PackedStringArray(["Georgia", "DejaVu Serif"])
	bold_font.font_weight = 800
	finish_lbl.font = bold_font
	finish_lbl.modulate = Color("#fff1cc")
	finish_lbl.position = Vector3(0.0, 5.8, 0.08)
	finish_node.add_child(finish_lbl)

func _create_start_banner() -> void:
	var banner_root := Node3D.new()
	banner_root.name = "StartingBanner"
	banner_root.position = Vector3(0.0, 0.0, -13.0)
	add_child(banner_root)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#6b3f21")
	wood_mat.roughness = 0.86

	# Tall posts leave a generous opening for the boat and oars.
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.28
		post_mesh.bottom_radius = 0.38
		post_mesh.height = 6.2
		post.mesh = post_mesh
		post.material_override = wood_mat
		post.position = Vector3(side * 5.8, 3.1, 0.0)
		banner_root.add_child(post)

	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(12.4, 0.55, 0.55)
	beam.mesh = beam_mesh
	beam.material_override = wood_mat
	beam.position = Vector3(0.0, 6.35, 0.0)
	banner_root.add_child(beam)

	# Dark backing makes the supplied logo readable against the sky.
	var sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(7.2, 2.25, 0.16)
	sign.mesh = sign_mesh
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color("#3b2418")
	sign_mat.roughness = 0.9
	sign.material_override = sign_mat
	sign.position = Vector3(0.0, 5.10, -0.03)
	banner_root.add_child(sign)

	var banner_texture = load("res://Game-Assets/Banner/strathhack for banner.webp")
	if banner_texture != null:
		var logo := Sprite3D.new()
		logo.texture = banner_texture
		logo.pixel_size = 0.0075
		logo.shaded = false
		logo.no_depth_test = false
		# Put the logo on the camera-facing side of the wooden backing.
		logo.position = Vector3(0.0, 5.10, 0.13)
		logo.rotation_degrees.y = 0.0
		banner_root.add_child(logo)

func _create_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)

	var root_control: Control = Control.new()
	root_control.name = "RootUI"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(root_control)

	# 1. Damage Flash Overlay
	damage_flash_rect = ColorRect.new()
	damage_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash_rect.color = Color(1.0, 0.0, 0.0, 0.0)
	damage_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(damage_flash_rect)

	# 2. Top Status Bar Container
	var status_panel = PanelContainer.new()
	status_panel.name = "TopStatusPanel"
	status_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status_panel.offset_left = 16
	status_panel.offset_top = 12
	status_panel.offset_right = -16
	status_panel.offset_bottom = 76
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("#101e2e")
	panel_style.border_color = Color("#7194b5")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	status_panel.add_theme_stylebox_override("panel", panel_style)
	var status_theme = Theme.new()
	status_theme.set_color("font_color", "Label", Color.WHITE)
	status_theme.set_color("font_outline_color", "Label", Color.BLACK)
	status_theme.set_constant("outline_size", "Label", 2)
	status_panel.theme = status_theme
	root_control.add_child(status_panel)
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	status_panel.add_child(top_bar)

	# Health Container
	var health_box: HBoxContainer = HBoxContainer.new()
	health_box.custom_minimum_size = Vector2(240, 40)
	var h_title = Label.new()
	h_title.text = "Hull:"
	h_title.add_theme_font_size_override("font_size", 18)
	health_box.add_child(h_title)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(140, 24)
	health_bar.min_value = 0.0
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.show_percentage = false
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_status_progress(health_bar, Color("#50e3a4"))
	health_box.add_child(health_bar)

	health_label = Label.new()
	health_label.text = " 100%"
	health_label.add_theme_font_size_override("font_size", 16)
	health_box.add_child(health_label)
	top_bar.add_child(health_box)

	# Distance Container
	var dist_box: HBoxContainer = HBoxContainer.new()
	dist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d_title = Label.new()
	d_title.text = "River Progress:"
	d_title.add_theme_font_size_override("font_size", 18)
	dist_box.add_child(d_title)

	distance_bar = ProgressBar.new()
	distance_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	distance_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	distance_bar.custom_minimum_size = Vector2(180, 24)
	distance_bar.min_value = 0.0
	distance_bar.max_value = RIVER_LENGTH
	distance_bar.value = 0.0
	distance_bar.show_percentage = false
	_style_status_progress(distance_bar, Color("#ffc857"))
	dist_box.add_child(distance_bar)

	distance_label = Label.new()
	distance_label.text = " 0m / 1000m"
	distance_label.add_theme_font_size_override("font_size", 16)
	dist_box.add_child(distance_label)
	top_bar.add_child(dist_box)

	# Speed Container
	speed_label = Label.new()
	speed_label.text = "Speed: 1.6 m/s"
	speed_label.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(speed_label)

	# Leave Button
	var leave_btn = Button.new()
	leave_btn.text = "Leave to Lobby"
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("#284b68")
	button_style.border_color = Color("#a4c5e0")
	button_style.set_border_width_all(1)
	button_style.set_corner_radius_all(6)
	button_style.content_margin_left = 12
	button_style.content_margin_right = 12
	leave_btn.add_theme_stylebox_override("normal", button_style)
	var hover_style = button_style.duplicate()
	hover_style.bg_color = Color("#3b6586")
	leave_btn.add_theme_stylebox_override("hover", hover_style)
	leave_btn.add_theme_color_override("font_color", Color.WHITE)
	leave_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	leave_btn.pressed.connect(_on_return_to_lobby_pressed)
	top_bar.add_child(leave_btn)

	# 3. Notification Banner (Center Screen)
	notification_banner = PanelContainer.new()
	notification_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notification_banner.offset_top = 85.0
	notification_banner.visible = false
	notification_label = Label.new()
	notification_label.text = "PERFECT SYNC! +25% SPEED"
	notification_label.add_theme_font_size_override("font_size", 22)
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_banner.add_child(notification_label)
	root_control.add_child(notification_banner)

	# 4. Bottom Roster & Controls Panel
	var bottom_panel: PanelContainer = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 30
	bottom_panel.offset_right = -30
	bottom_panel.offset_bottom = -16
	root_control.add_child(bottom_panel)

	var bottom_vbox = VBoxContainer.new()
	bottom_panel.add_child(bottom_vbox)

	var hint_lbl = Label.new()
	hint_lbl.text = "• Space / Left Click: Row | Right Click: Backwater/Turn | Keys 1-6: Row Any Seat (Offline) | Time strokes together for Sync Surge!"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 14)
	hint_lbl.modulate = Color(0.9, 0.9, 0.9, 0.8)
	bottom_vbox.add_child(hint_lbl)

	# 5. Game Over Panel (Modal)
	game_over_panel = PanelContainer.new()
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_over_panel.offset_left = -200.0
	game_over_panel.offset_top = -120.0
	game_over_panel.offset_right = 200.0
	game_over_panel.offset_bottom = 120.0
	game_over_panel.custom_minimum_size = Vector2(400, 240)
	game_over_panel.visible = false
	root_control.add_child(game_over_panel)

	var go_vbox = VBoxContainer.new()
	go_vbox.add_theme_constant_override("separation", 16)
	game_over_panel.add_child(go_vbox)

	var go_title = Label.new()
	go_title.text = "BOAT SUNK!"
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_title.add_theme_font_size_override("font_size", 32)
	go_title.modulate = Color(1.0, 0.3, 0.3)
	go_vbox.add_child(go_title)

	var go_desc = Label.new()
	game_over_description = go_desc
	go_desc.text = "The boat took too much hull damage in the river.\nCoordinate your rowing calls to steer around obstacles!"
	go_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_vbox.add_child(go_desc)

	var go_btn_row = HBoxContainer.new()
	go_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	go_btn_row.add_theme_constant_override("separation", 20)
	go_vbox.add_child(go_btn_row)

	var retry_btn = Button.new()
	retry_btn.text = "Retry River"
	retry_btn.disabled = not _is_game_authority()
	retry_btn.pressed.connect(_on_retry_pressed)
	go_btn_row.add_child(retry_btn)

	var go_lobby_btn = Button.new()
	go_lobby_btn.text = "Return to Lobby"
	go_lobby_btn.pressed.connect(_on_return_to_lobby_pressed)
	go_btn_row.add_child(go_lobby_btn)

	# 6. Victory Panel (Modal)
	victory_panel = PanelContainer.new()
	victory_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	victory_panel.offset_left = -330
	victory_panel.offset_right = 330
	victory_panel.offset_top = 88
	victory_panel.offset_bottom = 250
	victory_panel.custom_minimum_size = Vector2(660, 162)
	var celebration_style = StyleBoxFlat.new()
	celebration_style.bg_color = Color(0.025, 0.09, 0.15, 0.92)
	celebration_style.border_color = Color(1, 0.8, 0.2)
	celebration_style.set_border_width_all(3)
	celebration_style.set_corner_radius_all(20)
	celebration_style.content_margin_left = 24
	celebration_style.content_margin_right = 24
	celebration_style.content_margin_top = 18
	celebration_style.content_margin_bottom = 18
	victory_panel.add_theme_stylebox_override("panel", celebration_style)
	victory_panel.visible = false
	root_control.add_child(victory_panel)

	var vic_vbox = VBoxContainer.new()
	vic_vbox.add_theme_constant_override("separation", 16)
	victory_panel.add_child(vic_vbox)

	var vic_title = Label.new()
	vic_title.text = "Congratulations!"
	vic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vic_title.add_theme_font_size_override("font_size", 54)
	var bold_font = SystemFont.new()
	bold_font.font_names = PackedStringArray(["Georgia", "DejaVu Serif"])
	bold_font.font_weight = 800
	vic_title.add_theme_font_override("font", bold_font)
	vic_title.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))
	vic_title.add_theme_constant_override("outline_size", 3)
	victory_title = vic_title
	vic_title.modulate = Color(1.0, 0.85, 0.2)
	vic_vbox.add_child(vic_title)

	var vic_btn_row = HBoxContainer.new()
	vic_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vic_btn_row.add_theme_constant_override("separation", 20)
	vic_vbox.add_child(vic_btn_row)

	var play_again_btn = Button.new()
	play_again_btn.text = "Play Again"
	play_again_btn.disabled = not _is_game_authority()
	play_again_btn.pressed.connect(_on_retry_pressed)
	vic_btn_row.add_child(play_again_btn)

	var vic_lobby_btn = Button.new()
	vic_lobby_btn.text = "Return to Lobby"
	vic_lobby_btn.pressed.connect(_on_return_to_lobby_pressed)
	vic_btn_row.add_child(vic_lobby_btn)

func _process(delta: float) -> void:
	if game_state == GameState.WON:
		_update_victory_ending(delta)
	if game_state == GameState.PLAYING:
		elapsed_time += delta
		damage_cooldown = maxf(0.0, damage_cooldown - delta)

		# Track distance
		if boat != null:
			distance_traveled = clampf(-boat.global_position.z, 0.0, RIVER_LENGTH)

			# Check Win Condition
			if -boat.global_position.z >= RIVER_LENGTH and _is_game_authority():
				_trigger_victory()

		# Update UI
		_update_hud(delta)

	# Screen Shake Decay
	if shake_intensity > 0.0:
		shake_intensity = maxf(0.0, shake_intensity - delta * 4.0)
		if camera != null:
			var offset = Vector3(
				randf_range(-shake_intensity, shake_intensity),
				randf_range(-shake_intensity, shake_intensity) * 0.5,
				randf_range(-shake_intensity, shake_intensity) * 0.5
			)
			camera.position = cam_base_pos + offset
	elif camera != null:
		camera.position = cam_base_pos

	# Damage flash decay
	if damage_flash_rect != null and damage_flash_rect.color.a > 0.0:
		damage_flash_rect.color.a = maxf(0.0, damage_flash_rect.color.a - delta * 3.0)

	# Notification banner timeout
	if notif_timer > 0.0:
		notif_timer -= delta
		if notif_timer <= 0.0 and notification_banner != null:
			notification_banner.visible = false

func _physics_process(_delta: float) -> void:
	if game_state != GameState.PLAYING or boat == null or not _is_game_authority():
		return

	# Check boat collisions for damage
	if damage_cooldown <= 0.0 and boat.get_slide_collision_count() > 0:
		var collided_obstacle = false
		for i in range(boat.get_slide_collision_count()):
			var col = boat.get_slide_collision(i)
			var collider = col.get_collider()
			if collider != null:
				if not can_damage_from_object(collider):
					continue
				var col_name = collider.name
				var collision_damage = 0.0
				if collider.is_in_group("river_damage_obstacle") or col_name.begins_with("Rock"):
					collision_damage = 15.0
				elif col_name.begins_with("Log"):
					collision_damage = 10.0
				elif col_name.begins_with("Bank"):
					collision_damage = 6.0
				elif col_name.begins_with("FallingTree"):
					collision_damage = 18.0

				if collision_damage > 0.0:
					apply_object_damage(collider, collision_damage, "Collided with %s!" % col_name)
					collided_obstacle = true
					break

		if collided_obstacle:
			damage_cooldown = 0.6 # Damage immunity window

	# Fallback for low-speed contacts where CharacterBody3D does not report a
	# slide collision reliably. This also makes damage work consistently on the
	# authoritative host in multiplayer.
	if damage_cooldown <= 0.0:
		var obstacles := get_tree().get_nodes_in_group("river_damage_obstacle")
		for obstacle in obstacles:
			if is_instance_valid(obstacle) and can_damage_from_object(obstacle) and boat.global_position.distance_to(obstacle.global_position) < 2.6:
				var hit_damage := 10.0 if obstacle.name.begins_with("Log") else 15.0
				apply_object_damage(obstacle, hit_damage, "Collided with %s!" % obstacle.name)
				damage_cooldown = 0.6
				break

func can_damage_from_object(object: Node) -> bool:
	return elapsed_time >= float(damaged_objects.get(object.get_instance_id(), -OBJECT_DAMAGE_INTERVAL))

func apply_object_damage(object: Node, amount: float, reason: String) -> bool:
	var object_id = object.get_instance_id()
	if not can_damage_from_object(object) or game_state != GameState.PLAYING or not _is_game_authority():
		return false
	damaged_objects[object_id] = elapsed_time + OBJECT_DAMAGE_INTERVAL
	_apply_damage(amount, reason)
	return true

func _style_status_progress(bar: ProgressBar, fill_color: Color) -> void:
	var track = StyleBoxFlat.new()
	track.bg_color = Color("#071019")
	track.border_color = Color("#819bb1")
	track.set_border_width_all(1)
	track.set_corner_radius_all(5)
	var fill = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)

func _apply_damage(amount: float, reason: String) -> void:
	var new_health = maxf(0.0, boat_health - amount)
	_apply_damage_state(new_health, amount, reason)
	# The host owns physics and damage. Mirror the resulting state so every
	# player sees the flash, notification, hull value, and game-over panel at
	# the same time.
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null and multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		for id in network_manager.get_loaded_game_peers():
			_sync_damage.rpc_id(id, new_health, amount, reason)

func _apply_damage_state(new_health: float, amount: float, reason: String) -> void:
	boat_health = new_health
	shake_intensity = 0.45
	if damage_flash_rect != null:
		damage_flash_rect.color.a = 0.45

	_show_notification("⚠️ -%d HP: %s" % [int(amount), reason], Color(1.0, 0.4, 0.4), 1.2)

	# Health threshold colors
	if health_label != null:
		health_label.text = " %d%%" % int(boat_health)
	if health_bar != null:
		health_bar.value = boat_health

	if boat_health <= 0.0:
		_trigger_game_over()

@rpc("authority", "call_remote", "reliable")
func _sync_damage(new_health: float, amount: float, reason: String) -> void:
	_apply_damage_state(new_health, amount, reason)

func _is_game_authority() -> bool:
	var network_manager = get_node_or_null("/root/NetworkManager")
	return network_manager == null or not network_manager.is_connection_ready() or (multiplayer != null and multiplayer.is_server())

func _on_boat_sync_row(_seat_a: int, _seat_b: int) -> void:
	sync_combos += 1
	_show_notification("⚡ PERFECT SYNC! +25% SPEED SURGE!", Color(0.4, 1.0, 0.5), 1.5)

func _show_notification(text: String, col: Color, duration: float) -> void:
	# Gameplay uses hull feedback and visible hazards, without text warnings.
	if notification_banner != null:
		notification_banner.hide()

func send_initial_state(peer_id: int) -> void:
	var wildlife = get_node("RiverWildlife")
	var activation_times: Array = []
	for croc in wildlife.crocodiles:
		activation_times.append(croc.get_meta("activated_at"))
	_receive_initial_state.rpc_id(peer_id, {
		"position": boat.position, "yaw": boat.rotation.y, "velocity": boat.velocity,
		"turn_speed": boat.turn_speed, "health": boat_health, "state": game_state,
		"elapsed": elapsed_time, "combos": sync_combos, "clock": wildlife.clock,
		"crocodiles": activation_times, "trees": get_node("RiverHazards").get_tree_activation_times(),
		"ending_time": victory_elapsed, "ending_x": victory_start_x
	})

@rpc("authority", "reliable")
func _receive_initial_state(state: Dictionary) -> void:
	boat.position = state.position
	boat.rotation.y = state.yaw
	boat.velocity = state.velocity
	boat.turn_speed = state.turn_speed
	elapsed_time = state.elapsed
	sync_combos = state.combos
	get_node("RiverWildlife")._sync_game_state(state.clock, state.health, state.state, state.crocodiles, state.ending_time, state.ending_x, state.trees)
	get_node("RiverHazards").update_trees(false)
	_update_hud(0.0)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.local_game_loaded = true

func _update_hud(_delta: float) -> void:
	if distance_bar != null:
		distance_bar.value = distance_traveled
	if distance_label != null:
		distance_label.text = " %dm / %dm" % [int(distance_traveled), int(RIVER_LENGTH)]

	if speed_label != null and boat != null:
		var speed = boat.velocity.length()
		speed_label.text = "Speed: %.1f m/s" % speed

	if health_bar != null:
		health_bar.value = boat_health
	if health_label != null:
		health_label.text = " %d%%" % int(boat_health)

func _trigger_game_over(reason: String = "The boat took too much hull damage in the river.\nCoordinate your rowing calls to steer around obstacles!") -> void:
	game_state = GameState.SUNK
	if game_over_description != null:
		game_over_description.text = reason
	shake_intensity = 0.8
	if game_over_panel != null:
		game_over_panel.visible = true
	# Slow boat to stop
	if boat != null:
		boat.velocity = Vector3.ZERO
		boat.current_speed = 0.0

func _trigger_victory() -> void:
	if game_state == GameState.WON:
		return
	game_state = GameState.WON
	victory_elapsed = 0.0
	victory_start_x = boat.position.x
	if victory_panel != null:
		victory_panel.visible = true
		victory_panel.pivot_offset = victory_panel.size / 2.0
		victory_panel.scale = Vector2(0.72, 0.72)
		victory_panel.modulate.a = 0.0
		var entrance = create_tween().set_parallel(true)
		entrance.tween_property(victory_panel, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		entrance.tween_property(victory_panel, "modulate:a", 1.0, 0.45)
		var pulse = create_tween().set_loops()
		pulse.tween_property(victory_title, "modulate", Color(1, 0.98, 0.7), 0.8)
		pulse.tween_property(victory_title, "modulate", Color(1, 0.85, 0.2), 0.8)
	if boat != null:
		boat.current_speed = 0.0
		boat.velocity = Vector3.ZERO
	# Detach the camera so the boat can tumble without rolling the view.
	camera.set_as_top_level(true)
	camera.global_position = Vector3(20, 7, WATERFALL_Z + 12)
	camera.look_at(Vector3(0, -8, WATERFALL_Z - 5), Vector3.UP)
	cam_base_pos = camera.position

func _update_victory_ending(delta: float) -> void:
	var previous_burst = int(victory_elapsed / 0.8)
	victory_elapsed += delta
	if victory_elapsed < 12.0 and int(victory_elapsed / 0.8) > previous_burst:
		_create_finish_firework(int(victory_elapsed / 0.8))
	var travel = minf(victory_elapsed * 6.0, 44.0)
	boat.position.x = lerpf(victory_start_x, 0.0, clampf(victory_elapsed / 3.0, 0.0, 1.0))
	boat.position.z = -RIVER_LENGTH - travel
	var fall_time = maxf(0.0, victory_elapsed - 3.0)
	boat.position.y = maxf(-17.8, 0.2 - 3.5 * fall_time * fall_time)
	boat.rotation.x = lerpf(boat.rotation.x, deg_to_rad(-65.0) if boat.position.y > -17.7 and fall_time > 0.0 else 0.0, minf(1.0, delta * 3.0))
	boat.rotation.y = lerp_angle(boat.rotation.y, 0.0, minf(1.0, delta * 2.0))

func _create_finish_firework(index: int) -> void:
	var burst = CPUParticles3D.new()
	burst.name = "FinishFirework"
	burst.position = Vector3(-7.0 if index % 2 == 0 else 7.0, 8.0 + (index % 3) * 2.0, WATERFALL_Z - 4.0 - (index % 4) * 3.0)
	burst.amount = 85
	burst.lifetime = 2.2
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.initial_velocity_min = 3.5
	burst.initial_velocity_max = 6.5
	burst.gravity = Vector3(0, -2.4, 0)
	burst.scale_amount_min = 0.07
	burst.scale_amount_max = 0.13
	var spark = SphereMesh.new()
	spark.radius = 1.0
	spark.height = 2.0
	spark.radial_segments = 6
	spark.rings = 3
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	spark.material = material
	burst.mesh = spark
	var colors = [Color("#ffba52"), Color("#74e8ed"), Color("#ff83bd"), Color("#b9a0ff")]
	var gradient = Gradient.new()
	var color: Color = colors[index % colors.size()]
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	burst.color_ramp = gradient
	add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

func _create_waterfall() -> void:
	var falls = MeshInstance3D.new()
	falls.name = "FinishWaterfall"
	var curtain = PlaneMesh.new()
	curtain.size = Vector2(RIVER_WIDTH, 18.0)
	curtain.subdivide_width = 32
	curtain.subdivide_depth = 32
	falls.mesh = curtain
	falls.rotation_degrees.x = 90
	falls.position = Vector3(0, -9, WATERFALL_Z)
	var waterfall_material = ShaderMaterial.new()
	waterfall_material.shader = load("res://waterfall.gdshader")
	falls.material_override = waterfall_material
	add_child(falls)
	var crest = MeshInstance3D.new()
	crest.name = "WaterfallCrest"
	var crest_mesh = PlaneMesh.new()
	crest_mesh.size = Vector2(RIVER_WIDTH, 3.0)
	crest_mesh.subdivide_width = 32
	crest.mesh = crest_mesh
	crest.material_override = waterfall_material
	crest.position = Vector3(0, 0.1, WATERFALL_Z + 1.5)
	add_child(crest)
	var pool = MeshInstance3D.new()
	pool.name = "WaterfallPool"
	var pool_mesh = PlaneMesh.new()
	pool_mesh.size = Vector2(90, 100)
	pool.mesh = pool_mesh
	pool.position = Vector3(0, -18, WATERFALL_Z - 50)
	pool.material_override = get_node("RiverWater").material_override
	add_child(pool)
	var cliff_material = StandardMaterial3D.new()
	cliff_material.albedo_color = Color(0.23, 0.28, 0.25)
	cliff_material.roughness = 1.0
	for side in [-1, 1]:
		var cliff = MeshInstance3D.new()
		var cliff_mesh = BoxMesh.new()
		cliff_mesh.size = Vector3(250, 18, 8)
		cliff.mesh = cliff_mesh
		cliff.material_override = cliff_material
		cliff.position = Vector3(side * 134.0, -9, WATERFALL_Z + 4)
		add_child(cliff)
	var foam = MeshInstance3D.new()
	var foam_mesh = TorusMesh.new()
	foam_mesh.inner_radius = 3.5
	foam_mesh.outer_radius = 4.5
	foam.mesh = foam_mesh
	foam.scale = Vector3(2, 0.2, 0.6)
	foam.position = Vector3(0, -17.8, WATERFALL_Z - 2)
	var foam_material = StandardMaterial3D.new()
	foam_material.albedo_color = Color(0.9, 0.98, 1)
	foam.material_override = foam_material
	add_child(foam)
	_create_waterfall_rainbow()
	_create_waterfall_spray()

func _create_waterfall_rainbow() -> void:
	var rainbow = MeshInstance3D.new()
	rainbow.name = "WaterfallRainbow"
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors = [Color(1, 0.18, 0.15, 0.55), Color(1, 0.52, 0.1, 0.55), Color(1, 0.9, 0.16, 0.55), Color(0.25, 0.88, 0.38, 0.55), Color(0.15, 0.65, 1, 0.55), Color(0.35, 0.3, 0.9, 0.55), Color(0.72, 0.3, 0.9, 0.55)]
	for band in range(colors.size()):
		var outer = 18.0 - band * 0.5
		var inner = outer - 0.5
		for segment in range(64):
			var a = PI * segment / 64.0
			var b = PI * (segment + 1) / 64.0
			var points = [Vector3(cos(a) * outer, sin(a) * outer, 0), Vector3(cos(b) * outer, sin(b) * outer, 0), Vector3(cos(a) * inner, sin(a) * inner, 0), Vector3(cos(a) * inner, sin(a) * inner, 0), Vector3(cos(b) * outer, sin(b) * outer, 0), Vector3(cos(b) * inner, sin(b) * inner, 0)]
			for point in points:
				surface.set_color(colors[band])
				surface.set_normal(Vector3.FORWARD)
				surface.add_vertex(point)
	rainbow.mesh = surface.commit()
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rainbow.material_override = material
	rainbow.position = Vector3(0, 0.8, -RIVER_LENGTH + 8.0)
	add_child(rainbow)

func _create_waterfall_spray() -> void:
	var mist = CPUParticles3D.new()
	mist.name = "WaterfallMist"
	mist.position = Vector3(0, -17, WATERFALL_Z - 1.5)
	mist.amount = 150
	mist.lifetime = 3.5
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(8, 0.25, 1.5)
	mist.direction = Vector3(0, 1, -0.2)
	mist.spread = 35
	mist.initial_velocity_min = 2.5
	mist.initial_velocity_max = 4.5
	mist.gravity = Vector3(0, -0.5, 0)
	var puff = QuadMesh.new()
	puff.size = Vector2(1.5, 1.5)
	var material = ShaderMaterial.new()
	material.shader = load("res://waterfall_mist.gdshader")
	puff.material = material
	mist.mesh = puff
	var fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.35))
	fade.set_color(1, Color(1, 1, 1, 0))
	mist.color_ramp = fade
	add_child(mist)
	var lip_mist: CPUParticles3D = mist.duplicate()
	lip_mist.name = "WaterfallLipMist"
	lip_mist.position = Vector3(0, 0.5, WATERFALL_Z - 0.5)
	lip_mist.amount = 35
	lip_mist.lifetime = 2.0
	lip_mist.initial_velocity_min = 0.5
	lip_mist.initial_velocity_max = 1.0
	add_child(lip_mist)
	var spray = CPUParticles3D.new()
	spray.name = "WaterfallSpray"
	spray.position = Vector3(0, -0.25, WATERFALL_Z - 0.25)
	spray.amount = 180
	spray.lifetime = 2.0
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = Vector3(8.5, 0.15, 0.15)
	spray.direction = Vector3(0, -1, -0.12)
	spray.spread = 10
	spray.initial_velocity_min = 1.5
	spray.initial_velocity_max = 3.0
	spray.gravity = Vector3(0, -9, 0)
	var droplet = SphereMesh.new()
	droplet.radius = 0.07
	droplet.height = 0.22
	var droplet_material = StandardMaterial3D.new()
	droplet_material.albedo_color = Color(0.82, 0.95, 1)
	droplet.material = droplet_material
	spray.mesh = droplet
	add_child(spray)

func _on_retry_pressed() -> void:
	if not _is_game_authority():
		return
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.is_connection_ready():
		_restart_river.rpc()
	else:
		_restart_river()

@rpc("authority", "call_local", "reliable")
func _restart_river() -> void:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.loaded_game_peers.clear()
		network_manager.local_game_loaded = false
	get_tree().reload_current_scene()

func _on_return_to_lobby_pressed() -> void:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.has_method("disconnect_game"):
		network_manager.disconnect_game()
	get_tree().change_scene_to_file("res://networking/Lobby.tscn")
