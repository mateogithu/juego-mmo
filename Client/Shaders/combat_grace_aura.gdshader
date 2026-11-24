shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 primary_color : source_color = vec4(1.0, 0.86, 0.28, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float intensity : hint_range(0.2, 4.0) = 1.65;
uniform float pulse_speed : hint_range(0.5, 8.0) = 3.0;
uniform float fresnel_power : hint_range(1.0, 6.0) = 2.4;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	float wave = sin(TIME * pulse_speed + VERTEX.y * 5.0 + VERTEX.x * 3.0) * 0.025;
	VERTEX += NORMAL * (0.04 + wave);
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float bands = 0.5 + 0.5 * sin(local_pos.y * 10.0 - TIME * pulse_speed * 2.2);
	float shimmer = 0.75 + 0.25 * sin(TIME * 6.0 + local_pos.x * 8.0 - local_pos.z * 8.0);
	vec3 col = mix(primary_color.rgb, secondary_color.rgb, bands * 0.65);
	ALBEDO = col * intensity * shimmer;
	ALPHA = clamp((fresnel * 0.85 + bands * 0.25) * 0.75, 0.0, 0.92);
}
