# res://character_customizer.gd
class_name CharacterCustomizer
extends RefCounted

const PALETTE: Array[Color] = [
	Color("#f5cba7"), # 0: Peach Skin
	Color("#e0ac69"), # 1: Warm Tan Skin
	Color("#8d5524"), # 2: Deep Brown Skin
	Color("#e74c3c"), # 3: Coral Red
	Color("#e67e22"), # 4: Bright Orange
	Color("#f1c40f"), # 5: Sun Yellow
	Color("#2ecc71"), # 6: Emerald Green
	Color("#1abc9c"), # 7: Turquoise
	Color("#3498db"), # 8: Sky Blue
	Color("#9b59b6"), # 9: Royal Purple
	Color("#ff9ff3"), # 10: Bubblegum Pink
	Color("#34495e"), # 11:  Navy
	Color("#f5f6fa")  # 12: Pure White
]

const EYE_NAMES: Array[String] = [
	"Normal",
	"Happy ^_^",
	"Sleepy -_-",
	"Wink ^_-",
	"Cool Shades B-)",
	"Angry >_<",
	"Sparkle *_*",
	"Surprised O_O",
	"Derp O_o"
]

const MOUTH_NAMES: Array[String] = [
	"Smile :)",
	"Big Grin :D",
	"Silly Tongue :P",
	"Open Cheer :O",
	"Neutral :-|",
	"Mustache {;)",
	"Kitty :3",
	"Gasp :o"
]

const HAT_NAMES: Array[String] = [
	"None",
	"Baseball Cap",
	"Beanie",
	"Top Hat",
	"Rowing Headband",
	"Party Hat",
	"Captain's Hat",
	"Cowboy Hat",
	"Golden Crown"
]

static func get_default_customization(seat_idx: int = 0) -> Dictionary:
	var _default_shirt = PALETTE[3] # Red
	if seat_idx == 1: _default_shirt = PALETTE[8] # Blue
	elif seat_idx == 2: _default_shirt = PALETTE[6] # Green
	elif seat_idx == 3: _default_shirt = PALETTE[5] # Yellow
	elif seat_idx == 4: _default_shirt = PALETTE[9] # Purple
	elif seat_idx == 5: _default_shirt = PALETTE[7] # Teal

	return {
		"skin_idx": 1,         # Warm Tan
		"shirt_idx": seat_idx % PALETTE.size(),
		"pants_idx": 11,       # Charcoal
		"eyes_idx": 0,         # Normal
		"mouth_idx": 0,        # Smile
		"hat_idx": 0,          # None
		"hat_color_idx": (seat_idx + 3) % PALETTE.size()
	}

static func get_random_customization() -> Dictionary:
	return {
		"skin_idx": randi() % 3, # Realistic or fun skin
		"shirt_idx": randi() % PALETTE.size(),
		"pants_idx": randi() % PALETTE.size(),
		"eyes_idx": randi() % EYE_NAMES.size(),
		"mouth_idx": randi() % MOUTH_NAMES.size(),
		"hat_idx": randi() % HAT_NAMES.size(),
		"hat_color_idx": randi() % PALETTE.size()
	}

# --- Drawing Utilities for Face Texture ---

static func _set_pix(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, col)

static func _draw_thick_line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, thickness: int = 2) -> void:
	var dx = absi(x1 - x0)
	var dy = -absi(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	var r: int = int(thickness / 2.0)
	while true:
		for ox in range(-r, r + 1):
			for oy in range(-r, r + 1):
				_set_pix(img, x0 + ox, y0 + oy, col)
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

static func _draw_circle_filled(img: Image, cx: int, cy: int, radius: int, col: Color) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				_set_pix(img, cx + x, cy + y, col)

static func _draw_rect_filled(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_set_pix(img, x, y, col)

static func _draw_arc_line(img: Image, cx: int, cy: int, rx: float, ry: float, start_a: float, end_a: float, col: Color, thick: int = 2, steps: int = 24) -> void:
	var prev_x: int = -1
	var prev_y: int = -1
	for s in range(steps + 1):
		var t = float(s) / float(steps)
		var a = lerpf(start_a, end_a, t)
		var px = int(cx + cos(a) * rx)
		var py = int(cy + sin(a) * ry)
		if s > 0:
			_draw_thick_line(img, prev_x, prev_y, px, py, col, thick)
		prev_x = px
		prev_y = py

# --- Procedural Skribbl Face Generator ---

static func create_face_texture(eyes_idx: int, mouth_idx: int) -> ImageTexture:
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # Transparent background

	var ink = Color(0.12, 0.12, 0.14, 1.0) # Soft comic black
	var white = Color(1.0, 1.0, 1.0, 1.0)
	var pink = Color(0.96, 0.45, 0.58, 1.0)

	# --- Eyes at (44, 46) and (84, 46) ---
	match eyes_idx:
		0: # Normal cute dots with shine
			_draw_circle_filled(img, 44, 46, 9, ink)
			_draw_circle_filled(img, 84, 46, 9, ink)
			_draw_circle_filled(img, 41, 43, 3, white)
			_draw_circle_filled(img, 81, 43, 3, white)
		1: # Happy ^_^
			_draw_thick_line(img, 34, 52, 44, 40, ink, 4)
			_draw_thick_line(img, 44, 40, 54, 52, ink, 4)
			_draw_thick_line(img, 74, 52, 84, 40, ink, 4)
			_draw_thick_line(img, 84, 40, 94, 52, ink, 4)
		2: # Sleepy -_-
			_draw_thick_line(img, 34, 46, 54, 46, ink, 5)
			_draw_thick_line(img, 74, 46, 94, 46, ink, 5)
		3: # Wink ^_-
			_draw_thick_line(img, 34, 52, 44, 40, ink, 4)
			_draw_thick_line(img, 44, 40, 54, 52, ink, 4)
			_draw_circle_filled(img, 84, 46, 9, ink)
			_draw_circle_filled(img, 81, 43, 3, white)
		4: # Cool Shades B-)
			_draw_rect_filled(img, 30, 38, 28, 18, ink)
			_draw_rect_filled(img, 70, 38, 28, 18, ink)
			_draw_thick_line(img, 56, 42, 72, 42, ink, 4) # Bridge
			# White specular diagonal shine
			_draw_thick_line(img, 34, 42, 42, 50, white, 2)
			_draw_thick_line(img, 74, 42, 82, 50, white, 2)
		5: # Angry >_<
			_draw_thick_line(img, 34, 40, 54, 50, ink, 4)
			_draw_thick_line(img, 34, 50, 54, 40, ink, 4)
			_draw_thick_line(img, 74, 50, 94, 40, ink, 4)
			_draw_thick_line(img, 74, 40, 94, 50, ink, 4)
		6: # Sparkle / Big Anime
			_draw_circle_filled(img, 44, 46, 13, ink)
			_draw_circle_filled(img, 84, 46, 13, ink)
			_draw_circle_filled(img, 41, 41, 5, white)
			_draw_circle_filled(img, 81, 41, 5, white)
			_draw_circle_filled(img, 48, 52, 3, white)
			_draw_circle_filled(img, 88, 52, 3, white)
		7: # Surprised O_O
			_draw_circle_filled(img, 44, 46, 12, ink)
			_draw_circle_filled(img, 84, 46, 12, ink)
			_draw_circle_filled(img, 44, 46, 7, white)
			_draw_circle_filled(img, 84, 46, 7, white)
			_draw_circle_filled(img, 44, 46, 3, ink)
			_draw_circle_filled(img, 84, 46, 3, ink)
		8: # Derp O_o
			_draw_circle_filled(img, 44, 46, 13, ink)
			_draw_circle_filled(img, 41, 43, 4, white)
			_draw_circle_filled(img, 84, 48, 7, ink)
			_draw_circle_filled(img, 82, 46, 2, white)

	# --- Mouths at (64, 88) ---
	match mouth_idx:
		0: # Smile :)
			_draw_arc_line(img, 64, 76, 22, 16, 0.2 * PI, 0.8 * PI, ink, 4)
		1: # Big Grin :D
			_draw_circle_filled(img, 64, 86, 18, ink)
			_draw_rect_filled(img, 40, 72, 48, 14, Color(0, 0, 0, 0)) # Erase upper half
			_draw_thick_line(img, 44, 86, 84, 86, white, 4) # Teeth
		2: # Tongue out :P
			_draw_arc_line(img, 64, 78, 20, 14, 0.2 * PI, 0.8 * PI, ink, 4)
			_draw_circle_filled(img, 64, 98, 9, pink)
			_draw_thick_line(img, 64, 90, 64, 102, ink, 2)
		3: # Open cheer :O
			_draw_circle_filled(img, 64, 90, 12, ink)
			_draw_circle_filled(img, 64, 92, 7, pink)
		4: # Neutral :-|
			_draw_thick_line(img, 48, 90, 80, 90, ink, 4)
		5: # Mustache {;)
			_draw_arc_line(img, 52, 92, 14, 8, 0.9 * PI, 1.8 * PI, ink, 5)
			_draw_arc_line(img, 76, 92, 14, 8, 1.2 * PI, 2.1 * PI, ink, 5)
			_draw_circle_filled(img, 64, 88, 5, ink)
		6: # Kitty :3
			_draw_arc_line(img, 54, 86, 11, 8, 0.1 * PI, 0.9 * PI, ink, 4)
			_draw_arc_line(img, 74, 86, 11, 8, 0.1 * PI, 0.9 * PI, ink, 4)
		7: # Gasp :o
			_draw_circle_filled(img, 64, 90, 8, ink)

	return ImageTexture.create_from_image(img)

# --- Apply Customization to 3D Rower Node ---

static func apply_to_rower(rower_node: Node3D, data: Dictionary) -> void:
	if rower_node == null:
		return

	var skin_col = PALETTE[data.get("skin_idx", 1) % PALETTE.size()]
	var shirt_col = PALETTE[data.get("shirt_idx", 0) % PALETTE.size()]
	var pants_col = PALETTE[data.get("pants_idx", 11) % PALETTE.size()]
	var hat_col = PALETTE[data.get("hat_color_idx", 3) % PALETTE.size()]
	var eyes_idx = data.get("eyes_idx", 0)
	var mouth_idx = data.get("mouth_idx", 0)
	var hat_idx = data.get("hat_idx", 0)

	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = skin_col
	skin_mat.roughness = 0.75

	var shirt_mat = StandardMaterial3D.new()
	shirt_mat.albedo_color = shirt_col
	shirt_mat.roughness = 0.65

	var pants_mat = StandardMaterial3D.new()
	pants_mat.albedo_color = pants_col
	pants_mat.roughness = 0.85

	var shoes_mat = StandardMaterial3D.new()
	shoes_mat.albedo_color = Color("#e0e0e0")
	shoes_mat.roughness = 0.55

	# Style rower body meshes
	var head_node: MeshInstance3D = null
	for mesh_inst in rower_node.find_children("*", "MeshInstance3D", true, false):
		var m_name = mesh_inst.name.to_lower()
		if m_name == "head":
			head_node = mesh_inst
			mesh_inst.material_override = skin_mat
		elif m_name.contains("torso") or m_name.contains("upperarm"):
			mesh_inst.material_override = shirt_mat
		elif m_name.contains("neck") or m_name.contains("hand") or m_name.contains("forearm"):
			mesh_inst.material_override = skin_mat
		elif m_name.contains("thigh") or m_name.contains("shin"):
			mesh_inst.material_override = pants_mat
		elif m_name.contains("foot"):
			mesh_inst.material_override = shoes_mat
		elif m_name != "facedecal":
			mesh_inst.material_override = shirt_mat

	# Attach Face Decal Quad
	if head_node != null:
		var face_quad: MeshInstance3D = head_node.get_node_or_null("FaceDecal")
		if face_quad == null:
			face_quad = MeshInstance3D.new()
			face_quad.name = "FaceDecal"
			var qm = QuadMesh.new()
			qm.size = Vector2(0.26, 0.26)
			face_quad.mesh = qm
			# The head front is at -Z (z ~ -0.20), face center is y ~ 0.82
			face_quad.position = Vector3(0.0, 0.82, -0.205)
			# Face outwards towards -Z
			face_quad.rotation_degrees.y = 180.0
			head_node.add_child(face_quad)

		var face_mat = StandardMaterial3D.new()
		face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face_mat.albedo_texture = create_face_texture(eyes_idx, mouth_idx)
		face_quad.material_override = face_mat

		# Attach / Replace Hat
		var old_hat = head_node.get_node_or_null("CustomHat")
		if old_hat != null:
			old_hat.queue_free()

		if hat_idx > 0:
			var hat_root = _build_hat(hat_idx, hat_col)
			hat_root.name = "CustomHat"
			head_node.add_child(hat_root)

# --- 3D Hat Builder ---

static func _build_hat(hat_type: int, hat_color: Color) -> Node3D:
	var root = Node3D.new()
	var hat_mat = StandardMaterial3D.new()
	hat_mat.albedo_color = hat_color
	hat_mat.roughness = 0.6

	var dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.12, 0.14, 0.18)
	dark_mat.roughness = 0.5

	var gold_mat = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.95, 0.78, 0.15)
	gold_mat.metallic = 0.85
	gold_mat.roughness = 0.3

	var white_mat = StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.95, 0.95, 0.98)
	white_mat.roughness = 0.7

	match hat_type:
		1: # Baseball Cap
			var dome = MeshInstance3D.new()
			var sm = SphereMesh.new()
			sm.radius = 0.20
			sm.height = 0.22
			dome.mesh = sm
			dome.material_override = hat_mat
			dome.position = Vector3(0, 1.02, -0.02)
			root.add_child(dome)

			var visor = MeshInstance3D.new()
			var bm = BoxMesh.new()
			bm.size = Vector3(0.22, 0.02, 0.16)
			visor.mesh = bm
			visor.material_override = hat_mat
			visor.position = Vector3(0, 0.98, -0.24)
			visor.rotation_degrees.x = -12.0
			root.add_child(visor)

		2: # Beanie
			var dome = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.20
			cm.height = 0.18
			dome.mesh = cm
			dome.material_override = hat_mat
			dome.position = Vector3(0, 1.05, -0.01)
			root.add_child(dome)

			var pompom = MeshInstance3D.new()
			var sm = SphereMesh.new()
			sm.radius = 0.05
			sm.height = 0.10
			pompom.mesh = sm
			pompom.material_override = white_mat
			pompom.position = Vector3(0, 1.18, -0.01)
			root.add_child(pompom)

		3: # Top Hat
			var brim = MeshInstance3D.new()
			var bm_cyl = CylinderMesh.new()
			bm_cyl.top_radius = 0.26
			bm_cyl.bottom_radius = 0.26
			bm_cyl.height = 0.02
			brim.mesh = bm_cyl
			brim.material_override = dark_mat
			brim.position = Vector3(0, 1.00, -0.01)
			root.add_child(brim)

			var crown = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.16
			cm.height = 0.22
			crown.mesh = cm
			crown.material_override = dark_mat
			crown.position = Vector3(0, 1.12, -0.01)
			root.add_child(crown)

			var ribbon = MeshInstance3D.new()
			var rm = CylinderMesh.new()
			rm.top_radius = 0.165
			rm.bottom_radius = 0.165
			rm.height = 0.04
			ribbon.mesh = rm
			ribbon.material_override = hat_mat
			ribbon.position = Vector3(0, 1.03, -0.01)
			root.add_child(ribbon)

		4: # Rowing Headband
			var band = MeshInstance3D.new()
			var tm = TorusMesh.new()
			tm.inner_radius = 0.18
			tm.outer_radius = 0.21
			band.mesh = tm
			band.material_override = hat_mat
			band.position = Vector3(0, 0.94, -0.01)
			root.add_child(band)

		5: # Party Hat
			var cone = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.14
			cm.height = 0.28
			cone.mesh = cm
			cone.material_override = hat_mat
			cone.position = Vector3(0, 1.14, -0.01)
			root.add_child(cone)

			var pompom = MeshInstance3D.new()
			var sm = SphereMesh.new()
			sm.radius = 0.04
			sm.height = 0.08
			pompom.mesh = sm
			pompom.material_override = gold_mat
			pompom.position = Vector3(0, 1.30, -0.01)
			root.add_child(pompom)

		6: # Captain's Hat
			var crown = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.23
			cm.bottom_radius = 0.19
			cm.height = 0.08
			crown.mesh = cm
			crown.material_override = white_mat
			crown.position = Vector3(0, 1.04, -0.02)
			root.add_child(crown)

			var brim = MeshInstance3D.new()
			var bm = BoxMesh.new()
			bm.size = Vector3(0.22, 0.02, 0.14)
			brim.mesh = bm
			brim.material_override = dark_mat
			brim.position = Vector3(0, 0.99, -0.22)
			brim.rotation_degrees.x = -14.0
			root.add_child(brim)

			var badge = MeshInstance3D.new()
			var bgm = CylinderMesh.new()
			bgm.top_radius = 0.03
			bgm.bottom_radius = 0.03
			bgm.height = 0.01
			badge.mesh = bgm
			badge.material_override = gold_mat
			badge.position = Vector3(0, 1.04, -0.20)
			badge.rotation_degrees.x = 90.0
			root.add_child(badge)

		7: # Cowboy Hat
			var brim = MeshInstance3D.new()
			var bm_cyl = CylinderMesh.new()
			bm_cyl.top_radius = 0.30
			bm_cyl.bottom_radius = 0.30
			bm_cyl.height = 0.02
			brim.mesh = bm_cyl
			brim.material_override = hat_mat
			brim.position = Vector3(0, 1.01, -0.01)
			root.add_child(brim)

			var crown = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.15
			cm.bottom_radius = 0.18
			cm.height = 0.16
			crown.mesh = cm
			crown.material_override = hat_mat
			crown.position = Vector3(0, 1.09, -0.01)
			root.add_child(crown)

		8: # Golden Crown
			var band = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.20
			cm.bottom_radius = 0.19
			cm.height = 0.12
			band.mesh = cm
			band.material_override = gold_mat
			band.position = Vector3(0, 1.06, -0.01)
			root.add_child(band)

			for p in range(5):
				var spike = MeshInstance3D.new()
				var sm = CylinderMesh.new()
				sm.top_radius = 0.0
				sm.bottom_radius = 0.03
				sm.height = 0.08
				spike.mesh = sm
				spike.material_override = gold_mat
				var angle = p * (TAU / 5.0)
				spike.position = Vector3(cos(angle) * 0.19, 1.15, sin(angle) * 0.19)
				root.add_child(spike)

	return root
