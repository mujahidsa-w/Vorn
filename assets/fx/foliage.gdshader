shader_type spatial;
// Map foliage (trees, bushes, hedges) with wind sway. Leaves are cut out with alpha scissor
// so they sort correctly and render fast; non-green parts of the atlas (fences, walls) stay still.
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float wind = 0.3;
uniform float alpha_cut = 0.42;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 avg = textureLod(albedo_tex, UV, 4.0);
	float g = smoothstep(0.015, 0.09, avg.g - max(avg.r, avg.b));
	float t = TIME;
	vec3 off = vec3(sin(t * 1.4 + wp.x * 0.31 + wp.z * 0.17), 0.0, cos(t * 1.1 + wp.z * 0.27 + wp.x * 0.11)) * (0.03 + 0.2 * wind);
	off += vec3(sin(t * 5.1 + wp.y * 2.3 + wp.x * 1.7), sin(t * 3.9 + wp.z * 1.9) * 0.5, cos(t * 4.6 + wp.y * 1.7 + wp.z)) * 0.03 * wind;
	off *= g;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
