shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.94, 0.55, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.36, 0.06, 1.0);
uniform float flow_speed : hint_range(1.0, 12.0) = 5.5;
uniform float flicker_strength : hint_range(0.0, 0.4) = 0.14;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
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
	float turb = sin(TIME * 14.0 + VERTEX.z * 4.0 + VERTEX.y * 6.0) * flicker_strength;
	VERTEX += NORMAL * turb;
}

void fragment() {
	vec2 uv = UV * vec2(3.0, 5.0) + vec2(0.0, -TIME * flow_speed);
	float n1 = noise2d(uv);
	float n2 = noise2d(uv * 2.1 + vec2(TIME * 2.0, -TIME * 3.0));
	float fire = clamp(n1 * 0.65 + n2 * 0.45, 0.0, 1.0);
	float edge_fade = clamp(1.0 - abs(UV.y - 0.5) * 1.6, 0.0, 1.0);
	vec3 col = mix(flame_color.rgb, core_color.rgb, smoothstep(0.35, 0.85, fire));
	ALBEDO = col * (1.4 + fire * 1.2);
	ALPHA = clamp(fire * edge_fade * 0.95, 0.0, 0.95);
}
