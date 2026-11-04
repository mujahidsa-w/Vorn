shader_type spatial;
// Countryside terrain: grass / rock / sand / snow blended by vertex weights,
// rock is triplanar so cliffs don't stretch; forest floors are darker; rain makes it wet.
render_mode cull_back;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wet = 0.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 w = COLOR;
	float dark = UV2.x;
	vec3 g = texture(grass_tex, wpos.xz / 9.0).rgb;
	g = mix(g, texture(grass_tex, wpos.xz / 47.0).rgb, 0.45);
	g *= mix(vec3(0.98, 1.0, 0.92), vec3(0.6, 0.7, 0.55), dark);
	vec3 bl = pow(abs(wnrm), vec3(4.0));
	bl /= (bl.x + bl.y + bl.z);
	vec3 r = texture(rock_tex, wpos.zy / 16.0).rgb * bl.x + texture(rock_tex, wpos.xz / 16.0).rgb * bl.y + texture(rock_tex, wpos.xy / 16.0).rgb * bl.z;
	vec3 s = texture(sand_tex, wpos.xz / 8.0).rgb;
	s = mix(s, texture(sand_tex, wpos.xz / 53.0).rgb, 0.4);
	vec3 sn = vec3(0.92, 0.94, 0.98) * (0.9 + 0.1 * texture(sand_tex, wpos.xz / 5.0).r);
	float tot = w.r + w.g + w.b + w.a + 0.0001;
	vec3 c = (g * w.r + r * w.g + s * w.b + sn * w.a) / tot;
	float wetk = wet * (1.0 - w.a / tot);
	ALBEDO = c * mix(1.0, 0.68, wetk);
	ROUGHNESS = mix(mix(0.95, 0.55, w.a / tot), 0.25, wetk);
	SPECULAR = mix(0.25, 0.6, wetk);
}
