# res://river.gd
extends Node3D

# --- River Course Settings ---
const RIVER_WIDTH: float = 18.0 # From X = -9.0 to +9.0
const RIVER_LENGTH: float = 1000.0 # 1000 meters to finish line
const OBSTACLE_SEED: int = 42819

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
var cam_base_pos: Vector3 = Vector3(0, 3.5, 5.2)

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

func _ready() -> void:
	_create_environment()
	_create_river_bed_and_water()
	_create_river_banks()
	_generate_obstacles()
	_create_finish_line()
	_create_hud()

	# Connect boat sync and damage events
	if boat.has_signal("sync_row_achieved"):
		boat.sync_row_achieved.connect(_on_boat_sync_row)

	# Camera initial setup
	if camera != null:
		cam_base_pos = camera.position

func _create_environment() -> void:
	# Add WorldEnvironment with river procedural sky/fog if not already present
	var env_node: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		var env: Environment = Environment.new()
		
		# Procedural daylight sky
		var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.38, 0.64, 0.90, 1.0)
		sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.84, 1.0)
		sky_mat.ground_bottom_color = Color(0.18, 0.22, 0.18, 1.0)
		sky_mat.ground_horizon_color = Color(0.68, 0.78, 0.84, 1.0)
		var sky: Sky = Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky

		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.85
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.fog_enabled = true
		env.fog_light_color = Color(0.70, 0.82, 0.88, 1.0)
		env.fog_density = 0.002
		env_node.environment = env
		add_child(env_node)

	if directional_light != null:
		directional_light.light_color = Color("#fff8e7")
		directional_light.light_energy = 1.2
		directional_light.shadow_enabled = true
		directional_light.rotation_degrees = Vector3(-45, -30, 0)

func _create_river_bed_and_water() -> void:
	# 1. Flowing Realistic River Water Surface
	var water_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	water_mesh_inst.name = "RiverWater"
	var water_plane: PlaneMesh = PlaneMesh.new()
	water_plane.size = Vector2(RIVER_WIDTH, RIVER_LENGTH + 200.0)
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

	water_mesh_inst.position = Vector3(0.0, 0.0, -(RIVER_LENGTH / 2.0))
	add_child(water_mesh_inst)

	# 2. River Bed (bottom under water)
	var bed_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	bed_mesh_inst.name = "RiverBed"
	var bed_plane: PlaneMesh = PlaneMesh.new()
	bed_plane.size = Vector2(RIVER_WIDTH + 2.0, RIVER_LENGTH + 200.0)
	bed_mesh_inst.mesh = bed_plane

	var bed_mat: StandardMaterial3D = StandardMaterial3D.new()
	bed_mat.albedo_color = Color("#2a3b2c") # Dark mossy river bottom
	bed_mat.roughness = 0.95
	bed_mesh_inst.material_override = bed_mat
	bed_mesh_inst.position = Vector3(0.0, -1.8, -(RIVER_LENGTH / 2.0))
	add_child(bed_mesh_inst)

func _create_river_banks() -> void:
	# Left and Right canyon banks with colliders
	var bank_mat: StandardMaterial3D = StandardMaterial3D.new()
	bank_mat.albedo_color = Color("#3e4a36") # Rocky mossy cliffs
	bank_mat.roughness = 0.9

	var bank_half_x: float = RIVER_WIDTH / 2.0 # 9.0
	var bank_thickness: float = 6.0
	var bank_height: float = 4.0

	for side in [-1.0, 1.0]:
		var bank_body: StaticBody3D = StaticBody3D.new()
		bank_body.name = "Bank_Left" if side < 0 else "Bank_Right"
		bank_body.position = Vector3(side * (bank_half_x + bank_thickness / 2.0), bank_height / 2.0 - 0.5, -(RIVER_LENGTH / 2.0))
		add_child(bank_body)

		var col: CollisionShape3D = CollisionShape3D.new()
		var col_box: BoxShape3D = BoxShape3D.new()
		col_box.size = Vector3(bank_thickness, bank_height, RIVER_LENGTH + 200.0)
		col.shape = col_box
		bank_body.add_child(col)

		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = Vector3(bank_thickness, bank_height, RIVER_LENGTH + 200.0)
		mesh_inst.mesh = box_mesh
		mesh_inst.material_override = bank_mat
		bank_body.add_child(mesh_inst)

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
	banner_mat.albedo_color = Color("#ffd700") # Gold celebratory banner

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
	ban_mesh.size = Vector3(12.0, 1.4, 0.1)
	banner.mesh = ban_mesh
	banner.material_override = banner_mat
	banner.position = Vector3(0.0, 5.8, 0.0)
	finish_node.add_child(banner)

	# 3D Label
	var finish_lbl: Label3D = Label3D.new()
	finish_lbl.text = "★ CALM WATERS - SAFE HARBOR ★\nFINISH LINE"
	finish_lbl.font_size = 36
	finish_lbl.modulate = Color(0.1, 0.1, 0.1)
	finish_lbl.position = Vector3(0.0, 5.8, 0.08)
	finish_node.add_child(finish_lbl)

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
	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 24
	top_bar.offset_top = 16
	top_bar.offset_right = -24
	top_bar.offset_bottom = 64
	top_bar.add_theme_constant_override("separation", 24)
	root_control.add_child(top_bar)

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
	hint_lbl.text = "• Left Click: Row Forward | Right Click: Backwater/Turn | Keys 1-6: Row Any Seat (Offline) | Call timing in Discord for Sync Surge!"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 14)
	hint_lbl.modulate = Color(0.9, 0.9, 0.9, 0.8)
	bottom_vbox.add_child(hint_lbl)

	# 5. Game Over Panel (Modal)
	game_over_panel = PanelContainer.new()
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
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
	retry_btn.pressed.connect(_on_retry_pressed)
	go_btn_row.add_child(retry_btn)

	var go_lobby_btn = Button.new()
	go_lobby_btn.text = "Return to Lobby"
	go_lobby_btn.pressed.connect(_on_return_to_lobby_pressed)
	go_btn_row.add_child(go_lobby_btn)

	# 6. Victory Panel (Modal)
	victory_panel = PanelContainer.new()
	victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	victory_panel.custom_minimum_size = Vector2(420, 260)
	victory_panel.visible = false
	root_control.add_child(victory_panel)

	var vic_vbox = VBoxContainer.new()
	vic_vbox.add_theme_constant_override("separation", 16)
	victory_panel.add_child(vic_vbox)

	var vic_title = Label.new()
	vic_title.text = "RIVER CONQUERED!"
	vic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vic_title.add_theme_font_size_override("font_size", 34)
	vic_title.modulate = Color(1.0, 0.85, 0.2)
	vic_vbox.add_child(vic_title)

	var vic_desc = Label.new()
	vic_desc.text = "You reached the safe harbor!\nGreat communication and teamwork on the oars."
	vic_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vic_vbox.add_child(vic_desc)

	var vic_btn_row = HBoxContainer.new()
	vic_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vic_btn_row.add_theme_constant_override("separation", 20)
	vic_vbox.add_child(vic_btn_row)

	var play_again_btn = Button.new()
	play_again_btn.text = "Play Again"
	play_again_btn.pressed.connect(_on_retry_pressed)
	vic_btn_row.add_child(play_again_btn)

	var vic_lobby_btn = Button.new()
	vic_lobby_btn.text = "Return to Lobby"
	vic_lobby_btn.pressed.connect(_on_return_to_lobby_pressed)
	vic_btn_row.add_child(vic_lobby_btn)

func _process(delta: float) -> void:
	if game_state == GameState.PLAYING:
		elapsed_time += delta
		damage_cooldown = maxf(0.0, damage_cooldown - delta)

		# Track distance
		if boat != null:
			distance_traveled = clampf(-boat.global_position.z, 0.0, RIVER_LENGTH)

			# Check Win Condition
			if -boat.global_position.z >= RIVER_LENGTH:
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
	if game_state != GameState.PLAYING or boat == null:
		return

	# Check boat collisions for damage
	if damage_cooldown <= 0.0 and boat.get_slide_collision_count() > 0:
		var collided_obstacle = false
		for i in range(boat.get_slide_collision_count()):
			var col = boat.get_slide_collision(i)
			var collider = col.get_collider()
			if collider != null:
				var col_name = collider.name
				var dmg = 0.0
				if col_name.begins_with("Rock"):
					dmg = 15.0
				elif col_name.begins_with("Log"):
					dmg = 10.0
				elif col_name.begins_with("Bank"):
					dmg = 6.0

				if dmg > 0.0:
					_apply_damage(dmg, "Collided with %s!" % col_name)
					collided_obstacle = true
					break

		if collided_obstacle:
			damage_cooldown = 0.6 # Damage immunity window

func _apply_damage(amount: float, reason: String) -> void:
	boat_health = maxf(0.0, boat_health - amount)
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

func _on_boat_sync_row(_seat_a: int, _seat_b: int) -> void:
	sync_combos += 1
	_show_notification("⚡ PERFECT SYNC! +25% SPEED SURGE!", Color(0.4, 1.0, 0.5), 1.5)

func _show_notification(text: String, col: Color, duration: float) -> void:
	if notification_banner != null and notification_label != null:
		notification_label.text = text
		notification_label.modulate = col
		notification_banner.visible = true
		notif_timer = duration

func _update_hud(_delta: float) -> void:
	if distance_bar != null:
		distance_bar.value = distance_traveled
	if distance_label != null:
		distance_label.text = " %dm / %dm" % [int(distance_traveled), int(RIVER_LENGTH)]

	if speed_label != null and boat != null:
		var spd = boat.velocity.length()
		speed_label.text = "Speed: %.1f m/s" % spd

	if health_bar != null:
		health_bar.value = boat_health
	if health_label != null:
		health_label.text = " %d%%" % int(boat_health)

func _trigger_game_over() -> void:
	game_state = GameState.SUNK
	shake_intensity = 0.8
	if game_over_panel != null:
		game_over_panel.visible = true
	# Slow boat to stop
	if boat != null:
		boat.velocity = Vector3.ZERO
		boat.current_speed = 0.0

func _trigger_victory() -> void:
	game_state = GameState.WON
	if victory_panel != null:
		victory_panel.visible = true
	if boat != null:
		boat.current_speed = 0.5

func _on_retry_pressed() -> void:
	get_tree().reload_current_scene()

func _on_return_to_lobby_pressed() -> void:
	var nm = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("disconnect_game"):
		nm.disconnect_game()
	get_tree().change_scene_to_file("res://networking/Lobby.tscn")
