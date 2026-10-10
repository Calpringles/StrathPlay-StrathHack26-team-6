shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform float damage : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	VERTEX.y += sin(VERTEX.z * 8.0 + TIME * 3.0) * sin(VERTEX.x * 12.0 - TIME * 2.0) * 0.004;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float width = mix(0.72, 1.0, 1.0 - pow(abs(p.y), 4.0));
	float edge = 1.0 - smoothstep(width - 0.08, width, abs(p.x));
	float ripple = sin(UV.y * 50.0 + TIME * 3.0 + sin(UV.x * 20.0)) * 0.5 + 0.5;
	ALBEDO = mix(vec3(0.07, 0.45, 0.6), vec3(0.38, 0.8, 0.87), ripple * 0.3);
	ALPHA = edge * mix(0.38, 0.58, damage);
	ROUGHNESS = 0.28;
	SPECULAR = 0.35;
}
