shader_type spatial;
// Trees, cacti and rocks (vertex coloured) with wind sway that grows with height.
render_mode cull_disabled;
uniform float wind = 0.3;
uniform float sway = 1.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float hgt = max(VERTEX.y, 0.0);
	float k = hgt * hgt * 0.004 * sway * (0.25 + wind);
	float ph = wp.x * 0.13 + wp.z * 0.11;
	VERTEX.x += sin(TIME * 1.3 + ph) * k;
	VERTEX.z += cos(TIME * 1.1 + ph * 1.3) * k * 0.7;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
