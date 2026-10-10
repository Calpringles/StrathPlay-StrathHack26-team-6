shader_type spatial;
render_mode cull_disabled;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 2.4 + TIME * 3.0) * 0.08;
}

void fragment() {
	float streak = sin(UV.x * 180.0 + sin(UV.y * 12.0 - TIME * 6.0) * 2.0);
	float froth = smoothstep(0.15, 0.8, streak);
	ALBEDO = mix(vec3(0.08, 0.5, 0.65), vec3(0.92, 0.98, 1.0), froth);
	ROUGHNESS = 0.3;
	EMISSION = vec3(0.08, 0.13, 0.15) * froth;
}
