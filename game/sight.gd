class_name Sight
extends Node3D
## Optic mounted on a weapon: red dot (pistols), holographic (SMGs, shotgun), 3x prism (rifles), 8x scope (sniper).
## The mount point is found on the weapon mesh itself: the top surface over the receiver, measured from the right-hand grip.
## In first person the eyepiece is a live lens:
##   - collimators draw the reticle at infinity: it sits where the sight's axis points, the world is seen through the glass;
##   - magnified optics show a second camera's picture along the sight's axis, with the eye box (dark crescent when the eye
##     is off-axis), chromatic fringe at the rim and an etched / illuminated reticle.
## Weapon space: barrel along -Z, top along +Y (same as the models).

const REFLEX_SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 axis = vec3(0.0, 0.0, -1.0);
uniform int reticle = 0;
uniform vec3 tint : source_color = vec3(0.55, 0.85, 0.80);
uniform float on = 1.0;
void fragment() {
	vec3 v = normalize(VERTEX);
	vec3 ax = normalize(axis);
	float a = length(cross(v, ax));
	float front = step(0.0, dot(v, ax));
	float dotr = reticle == 0 ? 0.0034 : 0.0019;
	float d = 1.0 - smoothstep(dotr * 0.55, dotr, a);
	float ring = 0.0;
	if (reticle == 1) {
		float r0 = 0.0185;
		float w = 0.0012;
		ring = 1.0 - smoothstep(w * 0.45, w, abs(a - r0));
		// the four ticks of a holographic ring
		vec3 up = normalize(cross(ax, vec3(1.0, 0.0, 0.0)));
		vec3 rt = normalize(cross(up, ax));
		float x = dot(v, rt);
		float y = dot(v, up);
		float tick = max(1.0 - smoothstep(w * 0.45, w, abs(x)), 1.0 - smoothstep(w * 0.45, w, abs(y)));
		ring = max(ring, tick * step(r0, a) * step(a, r0 + 0.006));
	}
	float glow = exp(-a * a / (dotr * dotr * 7.0)) * 0.4;
	float ret = clamp(max(d, ring) + glow, 0.0, 1.0) * on * front;
	vec2 e = UV * 2.0 - 1.0;
	float edge = smoothstep(0.55, 1.0, max(abs(e.x), abs(e.y)));
	ALBEDO = mix(tint, vec3(1.0, 0.025, 0.015) * 1.5, ret);
	ALPHA = clamp(0.05 + 0.12 * edge + ret, 0.0, 1.0);
}"

const SCOPE_SHADER := "shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform sampler2D scope_tex : source_color, filter_linear, repeat_disable;
uniform float live = 0.0;
uniform vec2 shadow_off = vec2(0.0);
uniform int reticle = 0;
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.55, w, length(pa - ba * h));
}
float disc(vec2 p, vec2 c, float r) {
	return 1.0 - smoothstep(r * 0.7, r, length(p - c));
}
void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	float ca = 0.007 * r * r;
	vec3 img;
	img.r = texture(scope_tex, UV + vec2(dir.x, -dir.y) * ca).r;
	img.g = texture(scope_tex, UV).g;
	img.b = texture(scope_tex, UV - vec2(dir.x, -dir.y) * ca).b;
	float pupil = 1.0 - smoothstep(0.78, 1.0, length(p + shadow_off));
	float rim = 1.0 - smoothstep(0.88, 1.0, r);
	vec3 col = img * pupil * rim;
	float black = 0.0;
	float lit = 0.0;
	if (reticle == 0) {
		// prism sight: illuminated chevron, bullet-drop post and stadia
		lit = max(seg(p, vec2(-0.075, -0.08), vec2(0.0, 0.0), 0.013), seg(p, vec2(0.0, 0.0), vec2(0.075, -0.08), 0.013));
		black = seg(p, vec2(0.0, -0.10), vec2(0.0, -0.62), 0.007);
		for (int i = 1; i <= 4; i++) {
			float y = -0.10 - 0.11 * float(i);
			float w = 0.075 - 0.012 * float(i);
			black = max(black, seg(p, vec2(-w, y), vec2(w, y), 0.006));
		}
		black = max(black, seg(p, vec2(-1.0, 0.0), vec2(-0.55, 0.0), 0.012));
		black = max(black, seg(p, vec2(0.55, 0.0), vec2(1.0, 0.0), 0.012));
	} else {
		// sniper: fine crosshair, heavy posts, mil dots and an illuminated centre dot
		black = max(seg(p, vec2(-0.55, 0.0), vec2(0.55, 0.0), 0.0045), seg(p, vec2(0.0, -0.55), vec2(0.0, 0.55), 0.0045));
		black = max(black, max(seg(p, vec2(-1.0, 0.0), vec2(-0.55, 0.0), 0.022), seg(p, vec2(0.55, 0.0), vec2(1.0, 0.0), 0.022)));
		black = max(black, max(seg(p, vec2(0.0, -1.0), vec2(0.0, -0.55), 0.022), seg(p, vec2(0.0, 0.55), vec2(0.0, 1.0), 0.022)));
		for (int i = 1; i <= 4; i++) {
			float o = 0.11 * float(i);
			black = max(black, max(disc(p, vec2(o, 0.0), 0.011), disc(p, vec2(-o, 0.0), 0.011)));
			black = max(black, max(disc(p, vec2(0.0, o), 0.011), disc(p, vec2(0.0, -o), 0.011)));
		}
		lit = disc(p, vec2(0.0), 0.0075);
	}
	col = mix(col, vec3(0.0), black * 0.92);
	col = mix(col, vec3(1.0, 0.16, 0.06) * 1.6, lit * pupil);
	vec3 glass = vec3(0.012, 0.016, 0.024) + vec3(0.10, 0.15, 0.22) * pow(1.0 - clamp(r, 0.0, 1.0), 3.0) * 0.35;
	ALBEDO = mix(glass, col, live);
}"

# per optic: optical-axis height over the base, eyepiece z, lens radius, footprint length, mount offset from the grip
const SPEC := {
	"rmr": {"h": 0.016, "lens_z": -0.012, "r": 0.0095, "len": 0.046, "fwd": 0.006},
	"holo": {"h": 0.034, "lens_z": 0.0, "r": 0.015, "len": 0.096, "fwd": 0.075},
	"acog": {"h": 0.040, "lens_z": 0.0752, "r": 0.0148, "len": 0.15, "fwd": 0.10},
	"sniper": {"h": 0.048, "lens_z": 0.1805, "r": 0.0178, "len": 0.36, "fwd": 0.11},
}
const SHOTGUN_FWD := 0.12

static var _mounts := {}
static var _builtins := {}

var kind := ""
var spec: Dictionary
var zoom := 1.0
var relief := 0.3
var lens: MeshInstance3D
var lens_mat: ShaderMaterial
var first_person := false
var builtin := false            # the model has its own scope: only the live lens is added at its eyepiece

static func _rel(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != root and x != null:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

static func _mount(weapon: Node3D, wid: String, kind: String) -> Dictionary:
	## top surface of the weapon over the receiver: (x, y, z) in weapon space; cached per weapon.
	## Rays are cast straight down onto the mesh triangles along the optic's footprint (flat receiver tops of
	## low-poly models have no vertices in the middle, so vertex heights alone would miss them).
	if _mounts.has(wid):
		return _mounts[wid]
	var grip := Vector3.ZERO
	var g := weapon.find_child("p_grip_r", true, false)
	if g:
		grip = _rel(weapon, g).origin
	var fwd: float = SHOTGUN_FWD if wid == "shotgun" else float(SPEC[kind]["fwd"])
	var mz := grip.z - fwd
	var half: float = float(SPEC[kind]["len"]) * 0.5
	var tris := PackedVector3Array()
	var xmin := INF
	var xmax := -INF
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _rel(weapon, m)
		var f := m.mesh.get_faces()
		for i in range(0, f.size() - 2, 3):
			var a := xf * f[i]
			var b := xf * f[i + 1]
			var c := xf * f[i + 2]
			if maxf(a.z, maxf(b.z, c.z)) < mz - half or minf(a.z, minf(b.z, c.z)) > mz + half:
				continue
			tris.append(a)
			tris.append(b)
			tris.append(c)
			for v in [a, b, c]:
				xmin = minf(xmin, v.x)
				xmax = maxf(xmax, v.x)
	var cx := (xmin + xmax) * 0.5 if xmin < xmax else grip.x
	# only triangles that cross the strip under the optic's base take part in the rays
	var near := PackedVector3Array()
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		if maxf(a.x, maxf(b.x, c.x)) < cx - 0.008 or minf(a.x, minf(b.x, c.x)) > cx + 0.008:
			continue
		near.append(a)
		near.append(b)
		near.append(c)
	var top := -INF
	for k in 9:
		var z := mz - half + half * 2.0 * k / 8.0
		for dx in [-0.006, 0.0, 0.006]:
			var from := Vector3(cx + dx, 1.0, z)
			for i in range(0, near.size() - 2, 3):
				var a2 := near[i]
				var b2 := near[i + 1]
				var c2 := near[i + 2]
				if maxf(a2.z, maxf(b2.z, c2.z)) < z or minf(a2.z, minf(b2.z, c2.z)) > z:
					continue
				var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, a2, b2, c2)
				if hit != null and (hit as Vector3).y > top:
					top = (hit as Vector3).y
	if top == -INF:
		top = grip.y + 0.06
	var r := {"pos": Vector3(cx, top, mz), "grip": grip, "tris": tris.size() / 3}
	_mounts[wid] = r
	return r

const CACHE := "user://sight_mounts.json"
const CACHE_VER := 3

static func precompute() -> void:
	## mount points for every weapon with an optic, while the loading screen is up; measured once per install
	_load_cache()
	var changed := false
	for wid in DB.W:
		var d: Dictionary = DB.W[wid]
		if not d.has("sight") or (_mounts.has(wid) and (d["sight"] != "sniper" or _builtins.has(wid))):
			continue
		var path := "res://assets/models/weapons/%s.scn" % wid
		if not ResourceLoader.exists(path):
			continue
		var w := (load(path) as PackedScene).instantiate() as Node3D
		_mount(w, wid, String(d["sight"]))
		if d["sight"] == "sniper":
			_builtin_scope(w, wid)
		w.free()
		changed = true
	if changed:
		_save_cache()

static func _v3(a) -> Array:
	return [a.x, a.y, a.z]

static func _save_cache() -> void:
	var out := {"ver": CACHE_VER, "mounts": {}, "builtins": {}}
	for k in _mounts:
		var m: Dictionary = _mounts[k]
		out["mounts"][k] = {"pos": _v3(m["pos"]), "grip": _v3(m["grip"])}
	for k in _builtins:
		var b: Dictionary = _builtins[k]
		out["builtins"][k] = {} if b.is_empty() else {"pos": _v3(b["pos"]), "r": b["r"]}
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))

static func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if not (d is Dictionary) or int(d.get("ver", 0)) != CACHE_VER:
		return
	for k in d.get("mounts", {}):
		var m: Dictionary = d["mounts"][k]
		var p: Array = m["pos"]
		var g: Array = m["grip"]
		_mounts[k] = {"pos": Vector3(p[0], p[1], p[2]), "grip": Vector3(g[0], g[1], g[2])}
	for k in d.get("builtins", {}):
		var b: Dictionary = d["builtins"][k]
		if b.is_empty():
			_builtins[k] = {}
		else:
			var bp: Array = b["pos"]
			_builtins[k] = {"pos": Vector3(bp[0], bp[1], bp[2]), "r": float(b["r"])}

static func _builtin_scope(weapon: Node3D, wid: String) -> Dictionary:
	## A scope already modelled on the weapon (the AWP has one): a long raised run along the top, much higher than the
	## barrel. Returns its eyepiece centre and radius in weapon space, or {} when the model has none.
	if _builtins.has(wid):
		return _builtins[wid]
	var pts := PackedVector3Array()
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _rel(weapon, m)
		for v in m.mesh.get_faces():
			pts.append(xf * v)
	var res := {}
	if pts.size() > 0:
		var top := {}
		var zmin := INF
		var zmax := -INF
		# height of the top along the barrel, 1 cm bins; a triangle counts in every bin it spans
		# (long tubes and flat tops have vertices only at their ends)
		for i in range(0, pts.size() - 2, 3):
			var a := pts[i]
			var b := pts[i + 1]
			var c := pts[i + 2]
			var y := maxf(a.y, maxf(b.y, c.y))
			var k0 := int(floor(minf(a.z, minf(b.z, c.z)) / 0.01))
			var k1 := int(floor(maxf(a.z, maxf(b.z, c.z)) / 0.01))
			for k in range(k0, k1 + 1):
				top[k] = maxf(float(top.get(k, -INF)), y)
			zmin = minf(zmin, minf(a.z, minf(b.z, c.z)))
			zmax = maxf(zmax, maxf(a.z, maxf(b.z, c.z)))
		var front: Array = []
		for k in top:
			if float(k) * 0.01 < zmin + (zmax - zmin) * 0.15:
				front.append(top[k])
		front.sort()
		var barrel: float = front[front.size() / 2] if front.size() > 0 else 0.0
		var best_k := 0
		var ymax := -INF
		for k in top:
			if float(top[k]) > ymax:
				ymax = float(top[k])
				best_k = k
		if ymax - barrel > 0.05:
			var thr := barrel + 0.55 * (ymax - barrel)
			var rear := best_k
			var gap := 0
			var k2 := best_k
			while gap <= 2 and k2 < best_k + 200:
				k2 += 1
				if float(top.get(k2, -INF)) > thr:
					rear = k2
					gap = 0
				else:
					gap += 1
			var front_k := best_k
			gap = 0
			k2 = best_k
			while gap <= 2 and k2 > best_k - 200:
				k2 -= 1
				if float(top.get(k2, -INF)) > thr:
					front_k = k2
					gap = 0
				else:
					gap += 1
			if (rear - front_k) * 0.01 > 0.12:
				var z_r := (rear + 1) * 0.01
				var xmn := INF
				var xmx := -INF
				var ytop := -INF
				var zr := -INF
				for p in pts:
					if p.z > z_r - 0.04 and p.z < z_r + 0.005 and p.y > thr - 0.03:
						xmn = minf(xmn, p.x)
						xmx = maxf(xmx, p.x)
						ytop = maxf(ytop, p.y)
						zr = maxf(zr, p.z)
				var r := (xmx - xmn) * 0.5
				if r > 0.008 and r < 0.045:
					res = {"pos": Vector3((xmn + xmx) * 0.5, ytop - r, zr), "r": r, "barrel": barrel, "top": ymax, "run": [front_k * 0.01, rear * 0.01]}
	_builtins[wid] = res
	return res

static func attach(weapon: Node3D, wid: String, fp: bool) -> Sight:
	var d: Dictionary = DB.W.get(wid, {})
	if not d.has("sight"):
		return null
	var s := Sight.new()
	s.kind = String(d["sight"])
	s.first_person = fp
	s.spec = SPEC[s.kind]
	var sd: Dictionary = DB.SIGHTS[s.kind]
	s.zoom = float(sd["zoom"])
	s.relief = float(sd["relief"])
	s.name = "Sight"
	if s.kind == "sniper":
		var b := _builtin_scope(weapon, wid)
		if not b.is_empty():
			s.builtin = true
			s.spec = {"h": 0.0, "lens_z": 0.001, "r": float(b["r"]) * 0.86, "len": 0.0, "fwd": 0.0}
			weapon.add_child(s)
			s.transform = Transform3D(Basis.IDENTITY, b["pos"])
			s._mats()
			s._scope_lens()
			return s
	var m := _mount(weapon, wid, s.kind)
	# pistols: the red dot rides on the slide
	var host: Node3D = weapon
	var slide := weapon.find_child("mv_slide", true, false) as Node3D
	if s.kind == "rmr" and slide:
		host = slide
	host.add_child(s)
	var at: Transform3D = Transform3D(Basis.IDENTITY, m["pos"])
	s.transform = _rel(weapon, host).affine_inverse() * at
	s._build()
	return s

# ------------------------------------------------------------------ geometry
var _metal: StandardMaterial3D
var _rubber: StandardMaterial3D
var _coat: StandardMaterial3D

func _mats() -> void:
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.035, 0.037, 0.04)
	_metal.metallic = 0.55
	_metal.roughness = 0.42
	_rubber = StandardMaterial3D.new()
	_rubber.albedo_color = Color(0.018, 0.018, 0.02)
	_rubber.roughness = 0.92
	_coat = StandardMaterial3D.new()
	_coat.albedo_color = Color(0.05, 0.10, 0.12)
	_coat.metallic = 0.9
	_coat.roughness = 0.06
	_coat.emission_enabled = true
	_coat.emission = Color(0.05, 0.12, 0.10)
	_coat.emission_energy_multiplier = 0.4

func _mesh(m: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)
	return mi

func _box(size: Vector3, pos: Vector3, mat: Material = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, pos, mat if mat else _metal)

func _tube(r_front: float, r_back: float, length: float, z: float, y: float, mat: Material = null, open := false) -> MeshInstance3D:
	## cylinder along the barrel axis (front = -Z); open = no end caps (eyecups around the lens)
	var c := CylinderMesh.new()
	c.top_radius = r_front
	c.bottom_radius = r_back
	c.height = length
	c.radial_segments = 32
	c.rings = 1
	c.cap_top = not open
	c.cap_bottom = not open
	return _mesh(c, Vector3(0, y, z), mat if mat else _metal, Vector3(-PI / 2.0, 0, 0))

func _ring(r_in: float, r_out: float, z: float, y: float, mat: Material = null) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = 40
	t.ring_segments = 10
	return _mesh(t, Vector3(0, y, z), mat if mat else _metal, Vector3(PI / 2.0, 0, 0))

static func disc_mesh(r: float, seg := 48) -> ArrayMesh:
	## flat disc facing +Z with planar UVs (u right, v down)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for p in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:      # clockwise = front face
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 - p.y * 0.5))
			st.add_vertex(Vector3(p.x * r, p.y * r, 0))
	return st.commit()

func _build() -> void:
	_mats()
	var h: float = spec["h"]
	match kind:
		"rmr":
			_box(Vector3(0.025, 0.006, 0.044), Vector3(0, 0.003, 0))
			_box(Vector3(0.025, 0.008, 0.026), Vector3(0, 0.009, 0.007))
			# sloped hood: two posts and a top bar around the window
			_box(Vector3(0.0035, 0.020, 0.012), Vector3(-0.0108, 0.016, -0.013))
			_box(Vector3(0.0035, 0.020, 0.012), Vector3(0.0108, 0.016, -0.013))
			_box(Vector3(0.025, 0.0035, 0.014), Vector3(0, 0.0272, -0.012))
			_box(Vector3(0.003, 0.006, 0.008), Vector3(0.0135, 0.010, 0.008), _rubber)
			_lens_quad(Vector2(0.018, 0.0165), Vector3(0, h, spec["lens_z"]))
		"holo":
			_box(Vector3(0.034, 0.010, 0.094), Vector3(0, 0.005, 0))
			_box(Vector3(0.034, 0.016, 0.036), Vector3(0, 0.018, 0.029))
			_box(Vector3(0.005, 0.040, 0.056), Vector3(-0.0175, 0.034, -0.016))
			_box(Vector3(0.005, 0.040, 0.056), Vector3(0.0175, 0.034, -0.016))
			_box(Vector3(0.040, 0.005, 0.058), Vector3(0, 0.0535, -0.016))
			_box(Vector3(0.004, 0.008, 0.010), Vector3(0.0185, 0.018, 0.036), _rubber)
			_box(Vector3(0.004, 0.008, 0.010), Vector3(0.0185, 0.018, 0.022), _rubber)
			_lens_quad(Vector2(0.030, 0.026), Vector3(0, h, spec["lens_z"]))
			var front := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.030, 0.026)
			front.mesh = q
			front.position = Vector3(0, h, -0.043)
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.5, 0.8, 0.75, 0.08)
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			fm.metallic = 0.8
			fm.roughness = 0.05
			front.material_override = fm
			add_child(front)
		"acog":
			_box(Vector3(0.030, 0.014, 0.090), Vector3(0, 0.007, -0.005))
			_box(Vector3(0.024, 0.016, 0.050), Vector3(0, 0.020, -0.005))
			_box(Vector3(0.034, 0.030, 0.068), Vector3(0, h, -0.002))
			_tube(0.0205, 0.018, 0.058, -0.065, h)
			_ring(0.0195, 0.0225, -0.094, h)
			_tube(0.0155, 0.0175, 0.036, 0.050, h)
			_tube(0.0185, 0.0185, 0.008, 0.071, h, _rubber, true)
			var fiber := _box(Vector3(0.006, 0.004, 0.058), Vector3(0, h + 0.0165, -0.012))
			var fmat := StandardMaterial3D.new()
			fmat.albedo_color = Color(0.9, 0.5, 0.1)
			fmat.emission_enabled = true
			fmat.emission = Color(1.0, 0.45, 0.08)
			fmat.emission_energy_multiplier = 1.2
			fiber.material_override = fmat
			_mesh(disc_mesh(0.018), Vector3(0, h, -0.0945), _coat, Vector3(0, PI, 0))
			_scope_lens()
		"sniper":
			for z in [-0.075, 0.075]:
				_box(Vector3(0.022, 0.030, 0.022), Vector3(0, 0.015, z))
				_ring(0.0150, 0.0195, z, h)
			_tube(0.0152, 0.0152, 0.20, 0.0, h)
			_tube(0.0262, 0.0152, 0.045, -0.1225, h)
			_tube(0.0262, 0.0262, 0.050, -0.170, h)
			_ring(0.0245, 0.0285, -0.195, h)
			_tube(0.0152, 0.0200, 0.030, 0.115, h)
			_tube(0.0200, 0.0200, 0.048, 0.154, h)
			_tube(0.0212, 0.0212, 0.009, 0.1775, h, _rubber, true)
			var tc := CylinderMesh.new()
			tc.top_radius = 0.0115
			tc.bottom_radius = 0.0115
			tc.height = 0.024
			tc.radial_segments = 24
			_mesh(tc, Vector3(0, h + 0.026, 0.0), _metal)
			_mesh(tc, Vector3(0.026, h, 0.0), _metal, Vector3(0, 0, PI / 2.0))
			_mesh(disc_mesh(0.024), Vector3(0, h, -0.1955), _coat, Vector3(0, PI, 0))
			_scope_lens()
	if not first_person:
		for c in find_children("*", "GeometryInstance3D", true, false):
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _lens_quad(sz: Vector2, pos: Vector3) -> void:
	lens = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	lens.mesh = q
	lens.position = pos
	add_child(lens)
	if first_person:
		lens_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = REFLEX_SHADER
		lens_mat.shader = sh
		lens_mat.set_shader_parameter("reticle", 0 if kind == "rmr" else 1)
		lens.material_override = lens_mat
	else:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.55, 0.85, 0.8, 0.10)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.metallic = 0.7
		gm.roughness = 0.05
		lens.material_override = gm

func _scope_lens() -> void:
	lens = MeshInstance3D.new()
	lens.mesh = disc_mesh(spec["r"])
	lens.position = Vector3(0, spec["h"], spec["lens_z"])
	add_child(lens)
	if first_person:
		lens_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SCOPE_SHADER
		lens_mat.shader = sh
		lens_mat.set_shader_parameter("reticle", 0 if kind == "acog" else 1)
		lens.material_override = lens_mat
	else:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.02, 0.03, 0.05)
		gm.metallic = 0.9
		gm.roughness = 0.05
		lens.material_override = gm

# ------------------------------------------------------------------ first person
func eye_local() -> Vector3:
	## where the eye sits when aiming through the optic (sight space)
	return Vector3(0, float(spec["h"]), float(spec["lens_z"]) + relief)

func magnified() -> bool:
	return zoom > 1.01

func lens_global() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, float(spec["h"]), float(spec["lens_z"])))

func update_fp(vm_cam: Camera3D, fov_w: float, fov_vm: float, live: float, scope_cam: Camera3D) -> void:
	## per frame: reticle direction (collimators) or the scope camera, its field of view and the eye box (magnified optics)
	if lens_mat == null:
		return
	var cam_xf := vm_cam.global_transform
	var axis_w := -global_transform.basis.z.normalized()
	if not magnified():
		lens_mat.set_shader_parameter("axis", (cam_xf.basis.inverse() * axis_w).normalized())
		return
	lens_mat.set_shader_parameter("live", live)
	if scope_cam == null:
		return
	var lx := lens_global()
	# the scope looks along its own axis from the eyepiece: sway and recoil move picture and reticle together
	scope_cam.global_transform = Transform3D(global_transform.basis.orthonormalized(), lx.origin)
	var c := cam_xf.affine_inverse() * lx.origin
	var dz := maxf(0.02, -c.z)
	var tan_vm := float(spec["r"]) / dz
	var tan_w := tan_vm * tan(deg_to_rad(fov_w) * 0.5) / tan(deg_to_rad(fov_vm) * 0.5)
	scope_cam.fov = clampf(rad_to_deg(2.0 * atan(tan_w / zoom)), 0.5, 60.0)
	# eye box: eye off the optical axis, or the axis turned away from the line of sight, darkens one side of the view
	var e := global_transform.affine_inverse() * cam_xf.origin
	var eye := eye_local()
	var off := Vector2(e.x - eye.x, e.y - eye.y) / 0.010
	var look := global_transform.basis.inverse() * (-cam_xf.basis.z)
	off += Vector2(look.x, look.y) * (relief / 0.010) * 0.8
	lens_mat.set_shader_parameter("shadow_off", off.limit_length(3.0))

func set_scope_texture(tex: Texture2D) -> void:
	if lens_mat and magnified():
		lens_mat.set_shader_parameter("scope_tex", tex)
