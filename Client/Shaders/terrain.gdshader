shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap, repeat_enable;

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap, repeat_enable;

uniform vec4 snow_color : source_color = vec4(0.91, 0.94, 0.98, 1.0);
uniform float uv_scale : hint_range(0.02, 0.5) = 0.085;
uniform vec3 world_origin_offset = vec3(0.0, 0.0, 0.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + world_origin_offset;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 tiled_uv = world_pos.xz * uv_scale;
	float height = world_pos.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	vec3 g_col = texture(grass_albedo, tiled_uv).rgb * 0.92;
	vec3 d_col = texture(dirt_albedo, tiled_uv * 0.85).rgb;
	vec3 r_col = texture(rock_albedo, tiled_uv * 0.65).rgb;

	vec3 g_nrm = texture(grass_normal, tiled_uv).rgb;
	vec3 d_nrm = texture(dirt_normal, tiled_uv * 0.85).rgb;
	vec3 r_nrm = texture(rock_normal, tiled_uv * 0.65).rgb;

	float g_rgh = texture(grass_roughness, tiled_uv).r;
	float r_rgh = texture(rock_roughness, tiled_uv * 0.65).r;

	// Riverbank dirt -> lush meadow grass
	float grass_mask = smoothstep(-1.5, 1.2, height);
	vec3 col = mix(d_col, g_col, grass_mask);
	vec3 nrm = mix(d_nrm, g_nrm, grass_mask);
	float rgh = mix(0.92, g_rgh, grass_mask);

	// Steep cliffs & mountain ridges -> 1K PBR rock
	float rock_mask = clamp(smoothstep(0.2, 0.42, slope) + smoothstep(13.5, 22.5, height) * 0.72, 0.0, 1.0);
	col = mix(col, r_col, rock_mask);
	nrm = mix(nrm, r_nrm, rock_mask);
	rgh = mix(rgh, r_rgh, rock_mask);

	// High-altitude snow peaks
	float snow_mask = smoothstep(23.5, 32.0, height) * smoothstep(0.5, 0.18, slope);
	col = mix(col, snow_color.rgb, snow_mask);
	rgh = mix(rgh, 0.52, snow_mask);

	// Capital sanctuary cobblestone tint around (0,0) and Chaos Citadel (260,260)
	float dist_order = length(world_pos.xz);
	float dist_chaos = length(world_pos.xz - vec2(260.0, 260.0));
	float plaza_mask = smoothstep(35.0, 26.0, min(dist_order, dist_chaos));
	col = mix(col, mix(d_col, r_col, 0.55), plaza_mask * 0.55);

	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 0.85;
	ROUGHNESS = clamp(rgh, 0.35, 0.98);
	METALLIC = 0.0;
}
