shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 root_color : source_color = vec4(0.11, 0.24, 0.09, 1.0);
uniform vec4 tip_color : source_color = vec4(0.36, 0.56, 0.2, 1.0);
uniform float wind_speed : hint_range(0.5, 6.0) = 2.1;
uniform float wind_strength : hint_range(0.0, 0.6) = 0.22;

varying float blade_height_t;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	blade_height_t = clamp(VERTEX.y, 0.0, 1.0);
	float sway = sin(TIME * wind_speed + wp.x * 0.45 + wp.z * 0.38) * 0.65
		+ cos(TIME * wind_speed * 1.6 + wp.x * 0.9 - wp.z * 0.7) * 0.35;
	VERTEX.x += sway * wind_strength * blade_height_t * blade_height_t;
	VERTEX.z += sway * wind_strength * 0.5 * blade_height_t * blade_height_t;
}

void fragment() {
	ALBEDO = mix(root_color.rgb, tip_color.rgb, blade_height_t);
	ROUGHNESS = 0.78;
	METALLIC = 0.0;
	BACKLIGHT = vec3(0.24, 0.36, 0.12);
}
