extends SceneTree
## Bakes the imported weapon sources (_src_pubg, FBX) into game weapon scenes: res://assets/arsenal/<id>.scn
## Same layout as the original weapons:  <id> / <id>_root / { <id>_body, mv_bolt, mv_mag, p_grip_r, p_grip_l, p_muzzle, ... }
##   - skinned meshes are baked in their rest pose; triangles go to the part of their dominant bone
##     (bolt / charging handle → mv_bolt, stripper clips and loose rounds → dropped);
##   - axes: barrel along -Z, top +Y, right +X; scaled to the real rifle's overall length;
##   - hand, muzzle, magazine and stock points are measured on the mesh, with per-weapon corrections in FIX.
## Run (needs a display for the skeleton pose):  xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/arsenal/bake.gd
## Optional env BAKE_SHOTS=<dir> renders a side view of each weapon with its points.

const SRC := "res://_src_pubg"
const OUT := "res://assets/arsenal"
const BOLT := ["gun_bolt", "gun_bolt_02", "gun_charginghandle", "gun_boltrotation"]
const DROP := ["mag_root", "gun_ammo01", "gun_ammo02", "gun_ammo03", "gun_ammo04", "gun_ammo05", "clip", "gun_sightb", "gun_sightf"]

# len: overall length in metres; add: extra meshes (first one ending in _Mag becomes mv_mag); socket: bone the magazine hangs from
const LIST := {
	"akm": {"dir": "AKM", "sk": "SK_WEP_AK47", "add": ["ST_WEP_AK47_Mag"], "len": 0.88},
	"m416": {"dir": "M416", "sk": "SK_WEP_M416", "add": ["ST_WEP_M416_Mag", "ST_WEP_M416_Stoke"], "len": 0.86},
	"scar": {"dir": "SCAR-L", "sk": "SK_WEP_SCAR", "add": ["ST_WEP_SCAR_Mag"], "len": 0.89},
	"m16": {"dir": "M16A4", "sk": "SK_WEP_M16", "add": ["ST_WEP_M16_Mag"], "len": 1.00},
	"aug": {"dir": "AUG", "sk": "SK_WEP_AUG", "add": ["ST_WEP_AUG_Mag"], "len": 0.79, "bullpup": true},
	"groza": {"dir": "Groza", "sk": "SK_WEP_Groza", "add": ["ST_WEP_GROZA_Mag"], "len": 0.62, "bullpup": true},
	"sks": {"dir": "SKS", "sk": "SK_WEP_SKS", "add": ["ST_WEP_SKS_Mag"], "len": 1.02},
	"mini14": {"dir": "Mini14", "sk": "SK_WEP_Mini14", "add": ["ST_WEP_Mini14_Mag"], "len": 0.95},
	"slr": {"dir": "SLR", "sk": "SK_WEP_SLR", "add": ["ST_WEP_SLR_Mag"], "len": 1.09, "socket": "gun_magazinesocket"},
	"mk14": {"dir": "MK14", "sk": "SK_WEP_MK14", "add": ["ST_WEP_MK14_Mag"], "len": 0.89},
	"vss": {"dir": "VSS", "sk": "SK_WEP_VSS", "add": ["ST_WEP_VSS_Mag"], "len": 0.89},
	"awm": {"dir": "AWM", "sk": "SK_WEP_AWM", "add": ["ST_WEP_AWM_Mag"], "len": 1.20},
	"m24": {"dir": "M24", "sk": "SK_WEP_M24", "add": ["ST_WEP_M24_Mag"], "len": 1.09},
	"k98": {"dir": "K98k", "sk": "SK_WEP_98k", "add": [], "len": 1.11},
	"win94": {"dir": "Win1894", "sk": "SK_WEP_Win1894", "add": [], "len": 0.96},
}
# per-weapon points measured on side views of the baked models (game space, metres):
#   mag — where the magazine's top front corner sits in the magazine well (the sources do not carry the socket),
#   stock_dy — lift of a separate stock onto the receiver; the rest are the marker points themselves
const FIX := {
	"akm": {"mag": Vector3(0, 0.039, -0.195), "p_grip_r": Vector3(0, -0.006, -0.035), "p_grip_l": Vector3(0, 0.065, -0.333), "p_eject": Vector3(0.02, 0.08, -0.15)},
	"m416": {"mag": Vector3(0, 0.018, -0.176), "stock_dy": 0.076, "p_grip_r": Vector3(0, -0.0165, -0.0315), "p_grip_l": Vector3(0, 0.075, -0.301), "p_eject": Vector3(0.02, 0.083, -0.146)},
	"scar": {"mag": Vector3(0, 0.029, -0.194), "p_grip_r": Vector3(0, -0.001, -0.0385), "p_grip_l": Vector3(0, 0.084, -0.32), "p_eject": Vector3(0.02, 0.10, -0.16)},
	"m16": {"mag": Vector3(0, 0.026, -0.196), "p_grip_r": Vector3(0, 0.0086, -0.031), "p_grip_l": Vector3(0, 0.081, -0.347), "p_eject": Vector3(0.02, 0.091, -0.157)},
	"aug": {"p_grip_r": Vector3(0, -0.007, -0.093), "p_grip_l": Vector3(0, 0.064, -0.30), "p_eject": Vector3(0.03, 0.09, 0.045)},
	"groza": {"mag": Vector3(0, 0.0375, -0.031), "p_grip_r": Vector3(0, 0.007, -0.157), "p_grip_l": Vector3(0, 0.061, -0.282), "p_eject": Vector3(0.02, 0.09, -0.03)},
	"sks": {"mag": Vector3(0, 0.036, -0.131), "p_grip_r": Vector3(0, 0.0034, 0.0207), "p_grip_l": Vector3(0, 0.067, -0.373), "p_eject": Vector3(0.02, 0.107, -0.139)},
	"mini14": {"mag": Vector3(0, 0.044, -0.205), "p_grip_r": Vector3(0, 0.001, -0.045), "p_grip_l": Vector3(0, 0.061, -0.352), "p_eject": Vector3(0.02, 0.088, -0.197)},
	"slr": {"p_grip_r": Vector3(0, 0.0206, -0.023), "p_grip_l": Vector3(0, 0.084, -0.4015), "p_eject": Vector3(0.02, 0.104, -0.199)},
	"mk14": {"mag": Vector3(0, 0.0427, -0.267), "p_grip_r": Vector3(0, 0.002, -0.0597), "p_grip_l": Vector3(0, 0.057, -0.375), "p_eject": Vector3(0.02, 0.084, -0.211)},
	"vss": {"mag": Vector3(0, 0.0417, -0.1936), "p_grip_r": Vector3(0, 0.0114, -0.0405), "p_grip_l": Vector3(0, 0.066, -0.2585), "p_eject": Vector3(0.02, 0.089, -0.155)},
	"awm": {"mag": Vector3(0, 0.0316, -0.203), "p_grip_r": Vector3(0, -0.0053, -0.0305), "p_grip_l": Vector3(0, 0.045, -0.348), "p_eject": Vector3(0.02, 0.0965, -0.106)},
	"m24": {"mag": Vector3(0, 0.0043, -0.162), "p_grip_r": Vector3(0, -0.0115, -0.0209), "p_grip_l": Vector3(0, 0.021, -0.32), "p_eject": Vector3(0.02, 0.053, -0.162)},
	"k98": {"p_mag": Vector3(0, 0.001, -0.1316), "p_grip_r": Vector3(0, -0.005, -0.0106), "p_grip_l": Vector3(0, 0.027, -0.32), "p_eject": Vector3(0.02, 0.059, -0.158)},
	"win94": {"p_mag": Vector3(0, 0.085, -0.1667), "p_grip_r": Vector3(0, 0.0377, -0.0542), "p_grip_l": Vector3(0, 0.0827, -0.3485), "p_eject": Vector3(0.02, 0.1155, -0.1927)},
}

var shots := ""

func _initialize() -> void:
	shots = OS.get_environment("BAKE_SHOTS")
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("BAKE_ONLY")
	var report := {}
	for id in LIST:
		if only != "" and not (id in only.split(",")):
			continue
		var r: Dictionary = await _bake(id, LIST[id])
		report[id] = r
		print("BAKED %s %s" % [id, JSON.stringify(r)])
	if shots != "":
		await _shots(report)
	await _icons(report)
	quit(0)

## white side silhouettes for the HUD and menus, like the original icons: 720 x 238, muzzle to the right
func _icons(report: Dictionary) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1440, 476)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	for id in report:
		var w := (load("%s/%s.scn" % [OUT, id]) as PackedScene).instantiate() as Node3D
		vp.add_child(w)
		for c in w.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).material_override = white
		var ab: Array = report[id]["aabb"]
		var c0: Vector3 = ((ab[0] as Vector3) + (ab[1] as Vector3)) * 0.5
		cam.size = ((ab[1] as Vector3).z - (ab[0] as Vector3).z) / 3.025 * 1.25
		cam.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1.0, c0.y - 0.03, c0.z))
		for f in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		var used := img.get_used_rect()
		var cut := img.get_region(used)
		var k := minf(712.0 / cut.get_width(), 230.0 / cut.get_height())
		cut.resize(int(cut.get_width() * k), int(cut.get_height() * k), Image.INTERPOLATE_LANCZOS)
		var out := Image.create_empty(720, 238, false, Image.FORMAT_RGBA8)
		out.blit_rect(cut, Rect2i(Vector2i.ZERO, cut.get_size()), Vector2i((720 - cut.get_width()) / 2, (238 - cut.get_height()) / 2))
		out.save_png("res://assets/ui/icons/%s.png" % id)
		w.queue_free()
		await process_frame

func _src(dir: String, f: String) -> String:
	return "%s/%s/Mesh/FBX/%s.FBX" % [SRC, dir, f]

func _xf(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x := n
	while x != root and x != null:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

func _mat(id: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = id
	var t := "%s/tex/%s" % [OUT, id]
	m.albedo_texture = load(t + "_d.jpg")
	m.normal_enabled = true
	m.normal_texture = load(t + "_n.png")
	var rma := load(t + "_rma.jpg") as Texture2D
	m.roughness = 1.0
	m.roughness_texture = rma
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = 1.0
	m.metallic_texture = rma
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if id != "mk14":
		m.ao_enabled = true
		m.ao_texture = rma
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## a mesh made of the given triangles of the source arrays, vertices moved by xf and re-centred on `origin`
func _part_mesh(arrs: Array, tris: PackedInt32Array, xf: Transform3D, origin: Vector3, mat: Material) -> ArrayMesh:
	var src_v: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var src_t = arrs[Mesh.ARRAY_TANGENT]
	var src_uv: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var remap := {}
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	for i in tris:
		if not remap.has(i):
			remap[i] = v.size()
			v.append(xf * src_v[i] - origin)
			n.append((nb * src_n[i]).normalized())
			if src_t != null and (src_t as PackedFloat32Array).size() > 0:
				var tt := xf.basis * Vector3(src_t[i * 4], src_t[i * 4 + 1], src_t[i * 4 + 2])
				tt = tt.normalized()
				t.append_array([tt.x, tt.y, tt.z, src_t[i * 4 + 3]])
			uv.append(src_uv[i])
		idx.append(remap[i])
	# the axis change mirrors nothing (a rotation and a uniform scale), so the winding stays as it was
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	if t.size() > 0:
		a[Mesh.ARRAY_TANGENT] = t
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	am.surface_set_material(0, mat)
	return am

func _tri_list(arrs: Array) -> PackedInt32Array:
	if arrs[Mesh.ARRAY_INDEX] != null and (arrs[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		return arrs[Mesh.ARRAY_INDEX]
	var out := PackedInt32Array()
	for i in (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		out.append(i)
	return out

func _bake(id: String, cfg: Dictionary) -> Dictionary:
	var sk_scene := (load(_src(cfg["dir"], cfg["sk"])) as PackedScene).instantiate() as Node3D
	get_root().add_child(sk_scene)
	await process_frame
	await process_frame
	var mi: MeshInstance3D = null
	for c in sk_scene.find_children("*", "MeshInstance3D", true, false):
		mi = c
	var skel := sk_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var baked := mi.bake_mesh_from_current_skeleton_pose()
	var mi_xf := _xf(sk_scene, mi)
	# names of the skin binds
	var bind_names := []
	for b in mi.skin.get_bind_count():
		var nm := String(mi.skin.get_bind_name(b))
		if nm == "" and mi.skin.get_bind_bone(b) >= 0:
			nm = skel.get_bone_name(mi.skin.get_bind_bone(b))
		bind_names.append(nm.to_lower())
	# extra meshes in the weapon's source space
	var extras := []
	for e in cfg["add"]:
		var es := (load(_src(cfg["dir"], e)) as PackedScene).instantiate() as Node3D
		var emi := es.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var exf := _xf(es, emi)
		if String(e).ends_with("_Mag") and cfg.has("socket"):
			for bi in skel.get_bone_count():
				if skel.get_bone_name(bi).to_lower() == String(cfg["socket"]):
					exf = Transform3D(Basis.IDENTITY, skel.get_bone_global_rest(bi).origin) * exf
		extras.append({"name": e, "arrs": emi.mesh.surface_get_arrays(0), "xf": exf, "mag": String(e).ends_with("_Mag")})
		es.free()
	# overall source length along +X (body and stock)
	var xmin := INF
	var xmax := -INF
	for s in baked.get_surface_count():
		for p in (baked.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var q := mi_xf * p
			xmin = minf(xmin, q.x)
			xmax = maxf(xmax, q.x)
	for e in extras:
		if e["mag"]:
			continue
		for p in (e["arrs"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var q2: Vector3 = (e["xf"] as Transform3D) * p
			xmin = minf(xmin, q2.x)
			xmax = maxf(xmax, q2.x)
	var k := float(cfg["len"]) / (xmax - xmin)
	# source (+X forward, +Y up, +Z right) → game (-Z forward, +Y up, +X right)
	var G := Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * k), Vector3.ZERO)
	var mat := _mat(id)
	# split the triangles of the skinned mesh by dominant bone
	var body_parts := []
	var bolt_tris := {}
	var bolt_at := Vector3.ZERO
	var nbolt := 0
	var dropped := 0
	for s in baked.get_surface_count():
		var orig := mi.mesh.surface_get_arrays(s)
		var arrs := baked.surface_get_arrays(s)
		var bones = orig[Mesh.ARRAY_BONES]
		var weights = orig[Mesh.ARRAY_WEIGHTS]
		var per := 4
		if bones != null and (orig[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
			per = (bones as PackedInt32Array).size() / (orig[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var tl := _tri_list(arrs)
		var body := PackedInt32Array()
		var bolt := PackedInt32Array()
		for i in range(0, tl.size() - 2, 3):
			var vi := tl[i]
			var name := ""
			if bones != null and (bones as PackedInt32Array).size() > 0:
				var best := -1.0
				for j in per:
					var w: float = weights[vi * per + j]
					if w > best:
						best = w
						var bi: int = bones[vi * per + j]
						name = bind_names[bi] if bi < bind_names.size() else ""
			if name in DROP:
				dropped += 1
				continue
			var tgt := bolt if name in BOLT else body
			tgt.append(tl[i])
			tgt.append(tl[i + 1])
			tgt.append(tl[i + 2])
		for i in bolt:
			bolt_at += G * (mi_xf * (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i])
			nbolt += 1
		body_parts.append({"arrs": arrs, "body": body, "bolt": bolt})
	# scene
	var root := Node3D.new()
	root.name = id
	var wroot := Node3D.new()
	wroot.name = id + "_root"
	root.add_child(wroot)
	var body_mi := MeshInstance3D.new()
	body_mi.name = id + "_body"
	var body_mesh := ArrayMesh.new()
	for bp in body_parts:
		var pm := _part_mesh(bp["arrs"], bp["body"], G * mi_xf, Vector3.ZERO, mat)
		body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm.surface_get_arrays(0))
		body_mesh.surface_set_material(body_mesh.get_surface_count() - 1, mat)
	wroot.add_child(body_mi)
	var fix: Dictionary = FIX.get(id, {})
	var mag_origin := Vector3(0, -0.02, 0)
	var has_mag := false
	for e in extras:
		if e["mag"]:
			has_mag = true
			mag_origin = G * ((e["xf"] as Transform3D) * Vector3.ZERO)
			var mm := MeshInstance3D.new()
			mm.name = "mv_mag"
			mm.mesh = _part_mesh(e["arrs"], _tri_list(e["arrs"]), G * (e["xf"] as Transform3D), mag_origin, mat)
			if fix.has("mag"):
				mag_origin = fix["mag"]
			mm.position = mag_origin
			wroot.add_child(mm)
		else:
			var lift := Transform3D(Basis.IDENTITY, Vector3(0, float(fix.get("stock_dy", 0.0)), 0))
			var pm2 := _part_mesh(e["arrs"], _tri_list(e["arrs"]), lift * G * (e["xf"] as Transform3D), Vector3.ZERO, mat)
			body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm2.surface_get_arrays(0))
			body_mesh.surface_set_material(body_mesh.get_surface_count() - 1, mat)
	body_mi.mesh = body_mesh
	if nbolt > 0:
		bolt_at /= float(nbolt)
		var bm := MeshInstance3D.new()
		bm.name = "mv_bolt"
		var bolt_mesh := ArrayMesh.new()
		for bp in body_parts:
			if (bp["bolt"] as PackedInt32Array).is_empty():
				continue
			var pm3 := _part_mesh(bp["arrs"], bp["bolt"], G * mi_xf, bolt_at, mat)
			bolt_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm3.surface_get_arrays(0))
			bolt_mesh.surface_set_material(bolt_mesh.get_surface_count() - 1, mat)
		bm.mesh = bolt_mesh
		bm.position = bolt_at
		wroot.add_child(bm)
	sk_scene.queue_free()
	# measured points
	var pts := _points(body_mesh, mag_origin, has_mag, bool(cfg.get("bullpup", false)), bolt_at if nbolt > 0 else Vector3.INF)
	for key in fix:
		if String(key).begins_with("p_"):
			pts[key] = fix[key]
	for key in pts:
		var m := Node3D.new()
		m.name = key
		m.position = pts[key]
		wroot.add_child(m)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute(OUT)
	var err := ResourceSaver.save(ps, "%s/%s.scn" % [OUT, id], ResourceSaver.FLAG_COMPRESS)
	var ab := body_mesh.get_aabb()
	var r := {"scale": snappedf(k, 0.0001), "aabb": [ab.position.snapped(Vector3.ONE * 0.001), ab.end.snapped(Vector3.ONE * 0.001)], "bolt": nbolt / 3, "dropped": dropped, "save": err}
	for key in pts:
		r[key] = (pts[key] as Vector3).snapped(Vector3.ONE * 0.001)
	root.free()
	return r

func _own(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_own(c, o)

## lowest point of the body under the centre line in a slice of z
func _bottom(verts: PackedVector3Array, z0: float, z1: float) -> float:
	var lo := INF
	for p in verts:
		if p.z >= z0 and p.z <= z1 and absf(p.x) < 0.03:
			lo = minf(lo, p.y)
	return lo

func _points(body: ArrayMesh, mag: Vector3, has_mag: bool, bullpup: bool, bolt: Vector3) -> Dictionary:
	var verts := PackedVector3Array()
	for s in body.get_surface_count():
		verts.append_array(body.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	var zf := INF
	var zb := -INF
	for p in verts:
		zf = minf(zf, p.z)
		zb = maxf(zb, p.z)
	var yf := 0.0
	var nf := 0
	var yb := 0.0
	var nb := 0
	for p in verts:
		if p.z < zf + 0.012:
			yf += p.y
			nf += 1
		if p.z > zb - 0.02:
			yb += p.y
			nb += 1
	var pts := {}
	pts["p_muzzle"] = Vector3(0, yf / maxf(1, nf), zf)
	pts["p_shoulder"] = Vector3(0, yb / maxf(1, nb), zb)
	pts["p_mag"] = mag
	# the pistol grip: the lowest slice of the body near the magazine (behind it; in front of it on a bullpup)
	var best_z := mag.z + 0.12
	var best_y := INF
	var z := mag.z - 0.30
	while z <= mag.z + 0.26:
		var outside := absf(z - mag.z) > (0.06 if has_mag else 0.0)
		var ok := (z < mag.z) if bullpup else (z > mag.z)
		if outside and ok:
			var lo := _bottom(verts, z - 0.006, z + 0.006)
			if lo < best_y:
				best_y = lo
				best_z = z
		z += 0.01
	# top of the grip: the receiver bottom just above the grip
	var top := _bottom(verts, best_z - 0.06, best_z - 0.045)
	var gy := best_y + 0.055 if best_y < INF else -0.08
	if top < INF:
		gy = minf(gy, top - 0.03)
	pts["p_grip_r"] = Vector3(0, gy, best_z - 0.012)
	var zl: float = best_z - (0.24 if bullpup else 0.31)
	var ly := _bottom(verts, zl - 0.01, zl + 0.01)
	pts["p_grip_l"] = Vector3(0, (ly + 0.014) if ly < INF else -0.03, zl)
	pts["p_eject"] = Vector3(0.02, bolt.y, bolt.z) if bolt != Vector3.INF else Vector3(0.02, 0.0, mag.z - 0.04)
	return pts

# ------------------------------------------------------------------ side views for checking the points
func _shots(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	var vp := SubViewport.new()
	vp.size = Vector2i(1400, 520)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.80, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	vp.add_child(sun)
	sun.rotation_degrees = Vector3(-35, 60, 0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	for id in report:
		var w := (load("%s/%s.scn" % [OUT, id]) as PackedScene).instantiate() as Node3D
		vp.add_child(w)
		var r: Dictionary = report[id]
		var ab: Array = r["aabb"]
		var c: Vector3 = ((ab[0] as Vector3) + (ab[1] as Vector3)) * 0.5
		cam.size = maxf(0.45, ((ab[1] as Vector3).z - (ab[0] as Vector3).z) * 0.42)
		cam.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1.0, c.y, c.z))
		var marks := []
		for key in r:
			if not String(key).begins_with("p_"):
				continue
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.008
			sm.height = 0.016
			s.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.no_depth_test = true
			m.albedo_color = {"p_grip_r": Color.RED, "p_grip_l": Color.BLUE, "p_muzzle": Color.YELLOW, "p_mag": Color.GREEN, "p_shoulder": Color.MAGENTA, "p_eject": Color.CYAN}.get(key, Color.WHITE)
			s.material_override = m
			s.position = r[key]
			vp.add_child(s)
			marks.append(s)
		var grid := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(-12, 13):
			im.surface_add_vertex(Vector3(0.2, -0.3, i * 0.05))
			im.surface_add_vertex(Vector3(0.2, 0.3, i * 0.05))
		for j in range(-6, 7):
			im.surface_add_vertex(Vector3(0.2, j * 0.05, -0.6))
			im.surface_add_vertex(Vector3(0.2, j * 0.05, 0.6))
		im.surface_end()
		grid.mesh = im
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1, 1, 1, 0.35)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		grid.material_override = gm
		vp.add_child(grid)
		for f in 3:
			await process_frame
		vp.get_texture().get_image().save_png("%s/%s.png" % [shots, id])
		w.queue_free()
		grid.queue_free()
		for s2 in marks:
			s2.queue_free()
		await process_frame
