shader_type canvas_item;
render_mode unshaded;

// Final grade for the 3D image: chromatic aberration, film grain, vignette,
// plus the two feedback effects that carry combat information -- a red damage
// wash and a low-health pulse.  Driven from PostFX.gd.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float vignette_amount : hint_range(0.0, 2.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.25) = 0.028;
uniform float aberration : hint_range(0.0, 0.01) = 0.0011;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float contrast_boost : hint_range(0.5, 2.0) = 1.0;
uniform vec4 damage_color : source_color = vec4(0.55, 0.05, 0.03, 1.0);
uniform float grain_enabled = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float r2 = dot(dir, dir);

	// --- chromatic aberration, stronger under stress -------------------
	float ab = aberration * (1.0 + damage * 3.0 + low_health * 2.5);
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ab).b;

	// --- contrast / saturation -----------------------------------------
	col = (col - 0.5) * contrast_boost + 0.5;
	if (desaturate > 0.001) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum), desaturate);
	}

	// --- film grain ----------------------------------------------------
	if (grain_enabled > 0.5 && grain_amount > 0.0001) {
		float g = hash12(uv * vec2(1920.0, 1080.0) + vec2(TIME * 37.0, TIME * 17.0)) - 0.5;
		col += g * grain_amount;
	}

	// --- vignette ------------------------------------------------------
	float vig = 1.0 - smoothstep(0.18, 0.95, r2 * (1.0 + vignette_amount));
	col *= mix(1.0, vig, clamp(vignette_amount, 0.0, 1.0));

	// --- combat feedback ----------------------------------------------
	if (damage > 0.001) {
		float edge = smoothstep(0.02, 0.75, r2 * 1.7);
		col = mix(col, damage_color.rgb, clamp(damage, 0.0, 1.0) * (0.30 + edge * 0.70));
	}
	if (low_health > 0.001) {
		float pulse = 0.50 + 0.50 * sin(TIME * 3.6);
		float edge = smoothstep(0.05, 0.80, r2 * 1.5);
		col = mix(col, vec3(0.34, 0.015, 0.02), low_health * pulse * edge * 0.85);
	}

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
