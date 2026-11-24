shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

uniform vec4 outer_color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.78, 1.0);
uniform float pulse_speed : hint_range(1.0, 16.0) = 8.0;

void vertex() {
	float disp = sin(TIME * pulse_speed + VERTEX.x * 12.0 + VERTEX.y * 12.0) * 0.03;
	VERTEX += NORMAL * disp;
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float core = pow(ndv, 1.6);
	float pulse = 0.85 + 0.15 * sin(TIME * pulse_speed * 1.5);
	vec3 col = mix(outer_color.rgb, core_color.rgb, core);
	ALBEDO = col * 1.9 * pulse;
}
