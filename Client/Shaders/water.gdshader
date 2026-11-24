shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 shallow_color : source_color = vec4(0.14, 0.46, 0.56, 0.86);
uniform vec4 deep_color : source_color = vec4(0.05, 0.18, 0.30, 0.95);
uniform vec4 foam_color : source_color = vec4(0.84, 0.94, 0.98, 0.9);
uniform float wave_speed : hint_range(0.1, 4.0) = 1.1;
uniform float wave_height : hint_range(0.0, 0.6) = 0.14;
uniform vec3 world_origin_offset = vec3(0.0, 0.0, 0.0);

varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + world_origin_offset;
	float w1 = sin(wp.x * 0.22 + TIME * wave_speed) * cos(wp.z * 0.19 - TIME * wave_speed * 0.8);
	float w2 = sin((wp.x - wp.z) * 0.35 + TIME * wave_speed * 1.4) * 0.5;
	VERTEX.y += (w1 + w2) * wave_height;
	world_pos = wp;
}

void fragment() {
	float ripple = sin(world_pos.x * 0.8 + TIME * 2.1) * cos(world_pos.z * 0.85 - TIME * 1.7);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, clamp(0.45 + ripple * 0.25 + fresnel * 0.5, 0.0, 1.0));
	float crest = smoothstep(0.68, 0.96, ripple * 0.5 + 0.5 + fresnel * 0.35);
	ALBEDO = mix(base, foam_color.rgb, crest * 0.28);
	ROUGHNESS = 0.14;
	METALLIC = 0.08;
	SPECULAR = 0.65;
	ALPHA = mix(shallow_color.a, deep_color.a, 1.0 - fresnel * 0.5);
}
