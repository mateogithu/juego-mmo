shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform vec4 mud_color : source_color = vec4(0.34, 0.28, 0.2, 1.0);
uniform vec4 sand_color : source_color = vec4(0.64, 0.57, 0.41, 1.0);
uniform vec4 grass_lush : source_color = vec4(0.18, 0.36, 0.14, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.34, 0.42, 0.18, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.26, 0.25, 0.28, 1.0);
uniform vec4 rock_light : source_color = vec4(0.45, 0.43, 0.42, 1.0);
uniform vec4 snow_color : source_color = vec4(0.91, 0.94, 0.98, 1.0);
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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * amp;
		p *= 2.13;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + world_origin_offset;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n_macro = fbm(world_pos.xz * 0.032);
	float n_mid = fbm(world_pos.xz * 0.18);
	float n_micro = vnoise(world_pos.xz * 1.15);
	float height = world_pos.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	// Riverbank mud -> sand -> rich varied valley meadow grass
	vec3 shore = mix(mud_color.rgb, sand_color.rgb, smoothstep(-3.2, -1.6, height));
	vec3 meadow = mix(grass_lush.rgb, grass_dry.rgb, clamp(n_macro * 1.2 - 0.1, 0.0, 1.0));
	meadow *= (0.86 + n_mid * 0.28);
	vec3 col = mix(shore, meadow, smoothstep(-1.4, 0.85, height));

	// Rugged striated mountain rock on cliffs and upper ridges
	float strata = sin(world_pos.y * 1.4 + n_mid * 4.0) * 0.5 + 0.5;
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, clamp(strata * 0.65 + n_micro * 0.35, 0.0, 1.0));
	float rock_mask = clamp(smoothstep(0.2, 0.42, slope) + smoothstep(13.5, 22.0, height) * 0.72, 0.0, 1.0);
	col = mix(col, rock, rock_mask);

	// High-altitude snow peaks
	float snow_mask = smoothstep(23.0, 31.5, height + n_macro * 4.5) * smoothstep(0.52, 0.18, slope);
	col = mix(col, snow_color.rgb, snow_mask);

	// Cobblestone-tinted sanctuary ring around valley settlement (0, 0)
	float dist_origin = length(world_pos.xz);
	float road_ring = exp(-pow((dist_origin - 19.0) / 3.0, 2.0));
	col = mix(col, sand_color.rgb * 0.78, road_ring * 0.65);

	ALBEDO = col * (0.9 + n_micro * 0.18);
	ROUGHNESS = mix(0.88, 0.55, snow_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.94, rock_mask * 0.5);
	METALLIC = 0.0;
}
