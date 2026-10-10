extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lobby = load("res://networking/Lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	var viewport = lobby.get_node("RiverBackground/SceneryViewport")
	var scenery = viewport.get_node("River")
	assert(viewport.own_world_3d and scenery.preview_mode, "Menu must render an isolated actual-game river background")
	assert(scenery.process_mode == Node.PROCESS_MODE_DISABLED, "Menu scenery must not run gameplay")
	assert(scenery.get_node_or_null("Boat/MultiplayerSynchronizer") == null, "Menu boat must not participate in network session")
	assert(scenery.get_node_or_null("HUD") == null, "Preview must not show gameplay HUD")
	assert(lobby.connect_panel.visible and not lobby.room_panel.visible, "Connect form must remain usable")
	assert(lobby.get_node("Background").color.a < 0.3, "River background must remain visible through the overlay")
	lobby._rotate_preview(30.0)
	assert(is_equal_approx(lobby.preview_rower.rotation_degrees.y, 210.0), "Character rotation must still work")
	lobby.queue_free()
	await process_frame
	var river = load("res://river.tscn").instantiate()
	root.add_child(river)
	assert(river.get_node("WaterfallRainbow").mesh != null, "Waterfall must have a visible rainbow mesh")
	assert(river.get_node("WaterfallMist").emitting, "Waterfall must have mist")
	assert(river.get_node("WaterfallSpray").emitting, "Waterfall must have falling spray")
	print("PASS: actual river menu background, isolated preview, usable form, character rotation, rainbow, mist and waterfall spray")
	quit()
