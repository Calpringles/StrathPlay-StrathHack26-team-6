shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float spin_direction = 1.0;

void vertex() {
	float radius = length(UV * 2.0 - 1.0);
	VERTEX.y += sin(radius * 22.0 - TIME * 4.0) * 0.035 * (1.0 - smoothstep(0.65, 1.0, radius));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float edge = 1.0 - smoothstep(0.72, 1.0, radius);
	float spiral = sin(atan(p.y, p.x) * 3.0 + radius * 25.0 - TIME * 3.0 * spin_direction);
	float foam = smoothstep(0.65, 1.0, spiral);
	ALBEDO = mix(vec3(0.02, 0.23, 0.32), vec3(0.68, 0.9, 0.94), foam * 0.75);
	ALPHA = edge * 0.75;
}
