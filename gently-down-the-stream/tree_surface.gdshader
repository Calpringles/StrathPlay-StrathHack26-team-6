shader_type spatial;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white;
uniform bool use_texture = false;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	vec3 original = base_color.rgb;
	if (use_texture) { original *= texture(base_texture, UV).rgb; }
	float detail = sin(local_position.x * 19.0 + local_position.y * 7.0) * sin(local_position.z * 23.0 - local_position.y * 11.0);
	ALBEDO = original * (0.98 + detail * 0.045);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
