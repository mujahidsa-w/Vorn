shader_type sky;
// City sky: gradient, sun + glow, moon, stars and drifting clouds.
uniform vec3 top_col : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 hor_col : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground_col : source_color = vec3(0.2, 0.2, 0.25);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.8);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.5);
uniform float night = 0.0;
uniform float clouds = 0.3;
uniform float cloud_light = 1.0;
uniform vec2 cloud_off = vec2(0.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(hor_col, top_col, pow(clamp(h, 0.0, 1.0), 0.5));
	if (h < 0.0) {
		col = mix(hor_col, ground_col, clamp(-h * 5.0, 0.0, 1.0));
	}
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	float sun_up = smoothstep(-0.12, 0.05, sd.y);
	// horizon glow around the sun (sunrise / sunset)
	float hglow = pow(sdot, 6.0) * (1.0 - smoothstep(0.0, 0.5, sd.y)) * sun_up;
	col += sun_col * hglow * 0.55 * (1.0 - clouds * 0.6);
	col += sun_col * pow(sdot, 120.0) * 0.6 * sun_up;
	// stars
	if (AT_CUBEMAP_PASS == false && night > 0.01 && h > 0.0) {
		vec3 p = d * 260.0;
		vec3 id = floor(p);
		vec3 f = fract(p) - 0.5;
		float r = hash3(id);
		float star = step(0.9965, r) * smoothstep(0.32, 0.0, length(f));
		col += vec3(0.85, 0.9, 1.0) * star * night * smoothstep(0.0, 0.25, h) * (1.0 - clouds) * 1.6;
	}
	// moon
	vec3 md = normalize(moon_dir);
	float mdot = dot(d, md);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.99955, 0.9997, mdot) * night * 1.4 * (1.0 - clouds * 0.8);
	col += vec3(0.25, 0.3, 0.45) * pow(max(mdot, 0.0), 60.0) * night * 0.25;
	// clouds projected on a dome
	if (h > -0.02) {
		vec2 uv = d.xz / (h + 0.12) * 0.11 + cloud_off;
		float n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.7 + 0.37).r * 0.35;
		float cov = mix(0.72, 0.3, clouds);
		float c = smoothstep(cov, cov + 0.22, n) * smoothstep(-0.02, 0.18, h);
		float thick = smoothstep(cov, cov + 0.5, n);
		vec3 lit = mix(vec3(0.95, 0.96, 1.0), sun_col, 0.25 + hglow) * cloud_light;
		vec3 shade = mix(vec3(0.42, 0.45, 0.52), vec3(0.18, 0.19, 0.22), clouds) * cloud_light;
		vec3 cc = mix(lit, shade, thick * 0.85);
		cc += sun_col * pow(sdot, 8.0) * (1.0 - thick) * 0.6 * sun_up * cloud_light;
		col = mix(col, cc, c * 0.95);
		// overcast veil
		col = mix(col, shade * 1.1, clouds * clouds * 0.55 * smoothstep(-0.02, 0.3, h));
	}
	COLOR = col;
}
