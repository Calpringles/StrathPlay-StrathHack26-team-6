shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float soft = 1.0 - smoothstep(0.1, 0.5, distance(UV, vec2(0.5)));
	ALBEDO = vec3(0.9, 0.97, 1.0);
	ALPHA = soft * COLOR.a * 0.45;
}
