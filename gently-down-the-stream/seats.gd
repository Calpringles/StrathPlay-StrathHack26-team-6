extends Node3D

@export var row_spacing: float = 1.2
@export var seat_spacing: float = 0.9
@export var seat_height: float = 0.35
@export var seat_size: Vector3 = Vector3(0.65, 0.12, 0.65)

# Moves all seats forwards or backwards inside the boat.
@export var centre_z: float = 0.0


func _ready() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#965d35")

	for row in range(3):
		for column in range(2):
			var player_index: int = row * 2 + column
			var side: float = -1.0 if column == 0 else 1.0

			# Each marker also provides a position for a future player model.
			var seat: Marker3D = Marker3D.new()
			seat.name = "Seat%d" % (player_index + 1)
			seat.position = Vector3(
				side * seat_spacing / 2.0,
				seat_height,
				centre_z + (row - 1) * row_spacing
			)
			add_child(seat)

			var platform: MeshInstance3D = MeshInstance3D.new()
			platform.name = "Platform"

			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = seat_size

			platform.mesh = mesh
			platform.material_override = material

			# The marker sits on the seat's upper surface.
			platform.position.y = -seat_size.y / 2.0
			seat.add_child(platform)
