extends Node
## GPS check: graph, routing to places, big map and minimap pictures, re-routing.
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)
func _w(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
func run() -> void:
	world.hud.show_help = false
	world.sky.set_hour(14.0)
	world.sky.set_weather(1)
	await _w(2.0)
	var g = world.gps
	var edges := 0
	for a in g.adj:
		edges += a.size()
	print("GPS nodes ", g.nodes.size(), " edges ", edges / 2, " places ", g.places.size())
	for nm in ["RADIO TOWER", "SANDY RANCH", "PINE VALLEY GAS", "UNION BANK", "BLUE LAKE PIER", "RIDGE LOOKOUT"]:
		var r: Array = g.search(nm)
		var t0 := Time.get_ticks_usec()
		g.set_destination(r[0].pos, r[0].name, false)
		print("route to ", nm, ": ", g.path.size(), " nodes, ", int(g.remaining), " m, eta car ", int(g.eta(true)), " s, turn ", g.turn_dir, " ", int(g.turn_dist), "  (", (Time.get_ticks_usec() - t0) / 1000.0, " ms)")
	var r2: Array = g.search("RADIO TOWER")
	g.set_destination(r2[0].pos, r2[0].name, false)
	await _w(1.5)
	await _shot("g1_minimap_route")
	world.hud._toggle_map()
	await _w(0.5)
	await _shot("g2_bigmap")
	world.hud.bigmap.zoom = 0.9
	world.hud.bigmap._center_on_player()
	await _w(0.3)
	await _shot("g3_bigmap_zoom")
	# click somewhere on the map (east desert road)
	var bm = world.hud.bigmap
	bm.zoom = 0.12
	bm.center = Vector2(1500, -900)
	await _w(0.3)
	bm._click(bm.w2s(Vector2(1980, -1150)))
	print("clicked dest ", g.dest.round(), " path ", g.path.size(), " remaining ", int(g.remaining))
	await _w(0.3)
	await _shot("g4_bigmap_click")
	world.hud._toggle_map()
	# re-route: teleport the player elsewhere
	world.player.global_position = world.route[200] + Vector3(0, 1, 0)
	await _w(2.5)
	print("after move: remaining ", int(g.remaining), " path ", g.path.size(), " zone ", g.zone, " street ", g.street)
	await _shot("g5_reroute")
	get_tree().quit()
