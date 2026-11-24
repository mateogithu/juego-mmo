shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 sand_color : source_color = vec4(0.62, 0.56, 0.42, 1.0);
uniform vec4 grass_color : source_color = vec4(0.22, 0.39, 0.19, 1.0);
uniform vec4 grass_alt_color : source_color = vec4(0.29, 0.44, 0.21, 1.0);
uniform vec4 rock_color : source_color = vec4(0.36, 0.35, 0.37, 1.0);
uniform vec4 snow_color : source_color = vec4(0.88, 0.91, 0.96, 1.0);
uniform vec3 world_origin_offset = vec3(0.0, 0.0, 0.0);

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + world_origin_offset;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n_macro = vnoise(world_pos.xz * 0.045);
	float n_micro = vnoise(world_pos.xz * 0.38);
	float height = world_pos.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	vec3 grass = mix(grass_color.rgb, grass_alt_color.rgb, n_macro);
	vec3 col = mix(sand_color.rgb, grass, smoothstep(-2.4, 0.6, height));

	float rock_mask = clamp(smoothstep(0.24, 0.48, slope) + smoothstep(14.0, 22.0, height) * 0.7, 0.0, 1.0);
	col = mix(col, rock_color.rgb * (0.85 + n_micro * 0.3), rock_mask);

	float snow_mask = smoothstep(24.0, 32.0, height) * smoothstep(0.55, 0.2, slope);
	col = mix(col, snow_color.rgb, snow_mask);

	// Subtle path rings around central Order Valley
	float dist = length(world_pos.xz);
	float road_ring = exp(-pow((dist - 24.0) / 2.2, 2.0));
	col = mix(col, sand_color.rgb * 0.85, road_ring * 0.55);

	ALBEDO = col * (0.9 + n_micro * 0.16);
	ROUGHNESS = mix(0.88, 0.68, snow_mask);
	METALLIC = 0.0;
}
