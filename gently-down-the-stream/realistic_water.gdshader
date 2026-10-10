shader_type spatial;
render_mode depth_draw_always, cull_back;

// Water Color Palette
uniform vec4 shallow_color : source_color = vec4(0.22, 0.65, 0.76, 0.65);
uniform vec4 deep_color : source_color = vec4(0.04, 0.22, 0.36, 0.94);
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);

// Wave Normals & Animation
uniform sampler2D texture_normal1 : hint_normal;
uniform sampler2D texture_normal2 : hint_normal;
uniform vec2 wave_speed1 = vec2(0.015, 0.08);
uniform vec2 wave_speed2 = vec2(-0.02, 0.05);
uniform float wave_scale : hint_range(0.01, 1.0) = 0.06;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.65;

// Depth Absorption & Edge Foam
uniform float depth_distance : hint_range(0.1, 10.0) = 2.5;
uniform float foam_distance : hint_range(0.0, 2.0) = 0.35;
uniform float fresnel_power : hint_range(1.0, 10.0) = 3.5;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.12;

// Surface Shininess Controls
uniform float water_roughness : hint_range(0.0, 1.0) = 0.32;
uniform float water_specular : hint_range(0.0, 1.0) = 0.25;

// Godot 4 Depth and Screen Textures
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void vertex() {
	// Subtle physical surface undulation
	float wave = sin(VERTEX.x * 1.5 + TIME * 1.8) * cos(VERTEX.z * 0.8 + TIME * 2.2);
	VERTEX.y += wave * 0.04;
}

void fragment() {
	// Dual procedural normal maps flowing downstream (-Z direction)
	vec2 uv_wave1 = UV * wave_scale + wave_speed1 * TIME;
	vec2 uv_wave2 = UV * wave_scale * 1.4 + wave_speed2 * TIME;

	vec3 n1 = texture(texture_normal1, uv_wave1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(texture_normal2, uv_wave2).rgb * 2.0 - 1.0;
	vec3 blended_normal = normalize(n1 + n2);

	NORMAL = normalize(mix(NORMAL, blended_normal, wave_strength));

	// Linear depth calculation for water absorption and shoreline foam
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float scene_depth = -view_pos.z;
	float water_depth = -VERTEX.z;
	float depth_diff = clamp(scene_depth - water_depth, 0.0, 10.0);

	// 1. Water color gradient (shallow translucent -> deep river navy)
	float depth_factor = clamp(depth_diff / depth_distance, 0.0, 1.0);
	vec4 water_col = mix(shallow_color, deep_color, depth_factor);

	// 2. Dynamic shoreline foam against riverbanks and boat hull
	float foam_factor = clamp(1.0 - (depth_diff / foam_distance), 0.0, 1.0);
	foam_factor = pow(foam_factor, 1.6);

	// 3. Fresnel reflection (clear looking down, reflective toward the horizon)
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// Combine colors
	// Combine colors with soft, natural glint
	vec3 final_color = mix(water_col.rgb, foam_color.rgb, foam_factor);
	final_color = mix(final_color, vec3(0.75, 0.88, 0.95), fresnel * fresnel_strength);

	ALBEDO = final_color;
	ALPHA = clamp(water_col.a + fresnel * 0.15 + foam_factor, 0.0, 1.0);
	ROUGHNESS = mix(water_roughness, 0.6, foam_factor);
	METALLIC = 0.0;
	SPECULAR = water_specular;
}
