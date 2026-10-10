extends SceneTree
func _init() -> void:
	for path in ["res://SourceCode/shader/main.gdshader.uid", "res://SourceCode/shader/util/triplanar.gdshaderinc.uid"]:
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))
		file.close()
	quit()
