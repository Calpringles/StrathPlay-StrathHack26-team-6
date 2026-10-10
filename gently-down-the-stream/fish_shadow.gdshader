shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float water_center_z = 0.0;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_position.x * 1.5 + TIME * 1.8) * cos((world_position.z - water_center_z) * 0.8 + TIME * 2.2);
	VERTEX.y += wave * 0.04;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float body = 1.0 - smoothstep(0.72, 1.0, length(vec2((p.x - 0.12) / 0.72, p.y / 0.48)));
	float tail = (1.0 - smoothstep(0.02, 0.12, abs(p.y) - (-p.x - 0.35) * 0.75)) * (1.0 - smoothstep(-0.38, -0.28, p.x));
	float silhouette = max(body, tail);
	ALBEDO = vec3(0.015, 0.09, 0.11);
	ALPHA = silhouette * 0.65;
}
