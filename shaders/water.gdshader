shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Flood water.  Two counter-scrolling layers of a procedural normal map give
// the surface motion; a Fresnel term (computed in the vertex stage, since
// Godot has no FRESNEL built-in) mixes deep/shallow/horizon colour so the
// water reads as reflective at grazing angles.  Pairs with the screen-space
// reflections enabled in the Environment.

uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec4 deep_color : source_color = vec4(0.010, 0.028, 0.038, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.055, 0.105, 0.125, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.150, 0.205, 0.240, 1.0);

uniform float normal_strength : hint_range(0.0, 2.0) = 0.9;
uniform float scroll_speed : hint_range(0.0, 0.2) = 0.022;
uniform float uv_scale : hint_range(0.5, 60.0) = 7.0;
uniform float wave_height : hint_range(0.0, 0.6) = 0.05;
uniform float wave_frequency : hint_range(1.0, 200.0) = 44.0;
uniform float roughness_min : hint_range(0.0, 0.4) = 0.05;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.35;
uniform float emission_amount : hint_range(0.0, 1.0) = 0.0;

varying float fres;

void vertex() {
	// Ripple displacement, driven by UV so it is resolution-independent.
	float w = sin(UV.x * wave_frequency + TIME * 0.75)
			* cos(UV.y * wave_frequency * 1.27 - TIME * 0.52);
	VERTEX.y += w * wave_height;

	// Fresnel from world-space geometry.
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world.xyz);
	fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 n1 = texture(ripple_normal, uv + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.55)).rgb;
	vec3 n2 = texture(ripple_normal, uv * 1.70 - vec2(TIME * scroll_speed * 0.65, TIME * scroll_speed)).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), (n1 + n2) * 0.5, normal_strength);
	NORMAL_MAP_DEPTH = 1.0;

	vec3 water = mix(deep_color.rgb, shallow_color.rgb, 0.30 + 0.70 * (1.0 - fres));
	water = mix(water, horizon_color.rgb, fres * 0.60);

	ALBEDO = water;
	ROUGHNESS = mix(roughness_min, roughness_min + 0.10, fres);
	METALLIC = metallic_amount;
	SPECULAR = 0.85;
	EMISSION = water * emission_amount;
}
