shader_type spatial;
render_mode cull_disabled;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 2.4 + TIME * 3.0) * 0.08;
}

void fragment() {
	float flow = UV.y * 95.0 - TIME * 9.0;
	float streak = sin(UV.x * 150.0 + sin(flow * 0.3) * 1.2);
	float spray = sin(flow + UV.x * 40.0) * sin(UV.x * 70.0 - TIME * 2.0);
	float froth = smoothstep(-0.4, 0.8, streak + spray * 0.7);
	ALBEDO = mix(vec3(0.18, 0.6, 0.78), vec3(0.95, 0.99, 1.0), froth);
	ROUGHNESS = 0.3;
	EMISSION = vec3(0.14, 0.2, 0.23) * froth;
}
