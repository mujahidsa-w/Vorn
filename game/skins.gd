class_name Skins
extends RefCounted
## Скины оружия: краска поверх запечённых текстур, рисунок считается в координатах модели (полосы, блоки, камуфляж, линии).

const CODE := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.7, 0.6, 0.4);
uniform vec3 col_b : source_color = vec3(0.8, 0.6, 0.2);
uniform int kind = 0;
uniform float chips = 0.18;
varying vec3 opos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { opos = VERTEX; }
void fragment() {
	vec4 base = texture(albedo_tex, UV);
	vec3 orm = texture(orm_tex, UV).rgb;
	vec2 p = vec2(opos.z, opos.y) * 100.0 + vec2(0.0, opos.x * 35.0);
	float m = 0.0;
	if (kind == 0) { m = step(0.55, fract((p.x * 0.8 + p.y * 1.25) / 7.0)); }
	else if (kind == 1) { m = step(0.5, fract(p.x / 17.0 + 0.2)); m = mix(m, 1.0 - m, step(0.5, fract(p.y / 11.0))); }
	else if (kind == 2) { m = smoothstep(-2.0, 6.0, p.y) * 0.35; }
	else if (kind == 3) { m = step(0.52, hash(floor(p / 1.1)) * 0.55 + hash(floor(p / 3.3)) * 0.45); }
	else { m = step(0.93, fract((p.x * 0.6 + p.y * 1.7) / 4.6)); }
	vec3 paint = mix(col_a, col_b, m);
	float lum = dot(base.rgb, vec3(0.3, 0.59, 0.11));
	paint *= 0.72 + 0.55 * clamp(lum * 2.2, 0.0, 1.0);
	float n = noise(p * 0.9) * 0.6 + noise(p * 3.1) * 0.4;
	float worn = smoothstep(1.0 - chips, 1.0 - chips + 0.08, n);
	ALBEDO = mix(paint, base.rgb * 1.3, worn);
	ROUGHNESS = mix(kind == 2 ? 0.32 : 0.5, orm.g, worn);
	METALLIC = mix(kind == 2 ? 0.75 : 0.15, orm.b, worn);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
"""
static var _shader: Shader

static func apply(root: Node3D, wid: String, skin: String, layer := 0) -> void:
	if skin == "" or not DB.SKINS.has(skin):
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	var d: Dictionary = DB.SKINS[skin]
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			sm.set_shader_parameter("albedo_tex", base.albedo_texture)
			sm.set_shader_parameter("orm_tex", base.roughness_texture if base.roughness_texture else base.metallic_texture)
			sm.set_shader_parameter("normal_tex", base.normal_texture)
			sm.set_shader_parameter("col_a", d["a"])
			sm.set_shader_parameter("col_b", d["b"])
			sm.set_shader_parameter("kind", d["kind"])
			mi.set_surface_override_material(s, sm)
