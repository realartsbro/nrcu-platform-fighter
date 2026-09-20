shader_type canvas_item;
render_mode unshaded;

// NRCU FX Lab vNext — explicit final-composite pass.
//
// BackBufferCopy captures the already-composited canvas before this quad is
// drawn. The default amount is exactly neutral: the captured pixel is returned
// without a blend or color change. A non-zero amount applies one deterministic
// tint/scan operator whose phase is driven only by supplied clocks.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float final_tint_amount = 0.0;
uniform vec4 final_tint_color : source_color = vec4(1.0);
uniform float presentation_time = 0.0;
uniform float free_run_time = 0.0;
uniform float final_time_source = 0.0; // 0 = presentation, 1 = free-run
uniform float final_operator_event_start = 0.0;
uniform float final_operator_duration = 0.5;
uniform float final_operator_mode = 0.0; // 0 tint, 1 speedlines_field
uniform float final_operator_secondary_mode = 0.0;
uniform float final_operator_strength = 0.0;
uniform float final_operator_scale = 1.0;
uniform float final_operator_speed = 1.0;
uniform float final_operator_softness = 0.12;
uniform float final_operator_pattern_mode = 0.0;
uniform float final_operator_pattern_family = 0.0;
uniform float final_operator_distortion = 0.0;
uniform vec4 final_operator_color_a : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform vec4 final_operator_color_b : source_color = vec4(1.0, 0.35, 0.82, 1.0);

const float FINAL_PI = 3.14159265359;

// Dedicated Gold operator. This is intentionally not a fringe/RGB/dither
// reuse: it samples the composed screen and overlays a radial line field in
// presentation space, with phase supplied by the renderer clocks.
vec3 speedlines_field(vec2 uv, float clock, float strength, float scale) {
	vec2 p = (uv - vec2(0.5)) * vec2(1.7777778, 1.0);
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float rays = abs(sin(angle * (28.0 + 10.0 * clamp(scale, 0.25, 4.0)) + clock * 1.7));
	if (final_operator_pattern_mode > 0.5) {
		float planar = dot(uv - vec2(0.5), normalize(vec2(0.85, 0.18))) * (42.0 + 16.0 * scale) + clock * 2.4;
		rays = abs(sin(planar));
	}
	float streak = pow(clamp(1.0 - rays, 0.0, 1.0), 18.0);
	float radial = final_operator_pattern_mode > 0.5 ? smoothstep(0.04, 0.92, abs(uv.y - 0.5)) : smoothstep(0.08, 0.95, radius) * smoothstep(1.15, 0.52, radius);
	float taper = smoothstep(0.02, 0.20, abs(sin(angle * 3.0 + clock * 0.35)));
	float coverage = clamp(streak * radial * (0.45 + 0.55 * taper) * strength, 0.0, 1.0);
	return mix(final_operator_color_b.rgb, final_operator_color_a.rgb, clamp(0.5 + 0.5 * sin(angle * 2.0), 0.0, 1.0)) * coverage;
}

// Dedicated geometric transition over the resolved BackBufferCopy input.
vec4 pattern_transition(vec2 uv, vec4 captured, float clock, float strength, float scale) {
	vec2 cell = floor(uv * vec2(18.0, 10.0) * max(scale, 0.25));
	float pattern = fract(sin(dot(cell, vec2(12.9898, 78.233)) + clock * 0.8) * 43758.5453);
	float band = 0.5 + 0.5 * sin((uv.x + uv.y * 0.35) * 42.0 * max(scale, 0.25) - clock * 3.0);
	if (final_operator_pattern_family > 0.5 && final_operator_pattern_family < 1.5) {
		pattern = 0.5 + 0.5 * sin((uv.x * 0.9 + uv.y * 1.7) * 34.0 * max(scale, 0.25) - clock * 2.0);
	} else if (final_operator_pattern_family >= 1.5) {
		vec2 dot_cell = fract(uv * vec2(13.0, 9.0) * max(scale, 0.25)) - vec2(0.5);
		pattern = smoothstep(0.30, 0.08, length(dot_cell));
	}
	float coverage = smoothstep(0.25, 0.75, mix(pattern, band, 0.35));
	float cut = smoothstep(1.0 - clamp(strength, 0.0, 1.0), 1.0, coverage);
	vec3 graphic = mix(final_operator_color_b.rgb, final_operator_color_a.rgb, coverage);
	return vec4(mix(captured.rgb, graphic, cut * 0.8), captured.a);
}

// Dedicated screen-space vacuum burst: inward warp plus a moving radial ring.
vec4 vacuum_burst(vec2 uv, float clock, float strength, float scale, vec4 captured) {
	vec2 p = (uv - vec2(0.5)) * vec2(1.7777778, 1.0);
	float radius = length(p);
	vec2 inward = normalize(p + vec2(0.0001));
	float pull = sin(clock * 4.0 - radius * 18.0) * smoothstep(1.0, 0.05, radius) * strength * 0.018;
	vec2 warped_uv = clamp(uv - inward * pull * max(scale, 0.25), vec2(0.0), vec2(1.0));
	vec4 warped = texture(screen_tex, warped_uv);
	float ring = exp(-abs(radius - (0.22 + 0.04 * sin(clock * 2.0))) * 34.0) * strength;
	vec3 burst = mix(final_operator_color_b.rgb, final_operator_color_a.rgb, smoothstep(0.0, 0.7, radius));
	return vec4(clamp(mix(warped.rgb, burst, ring * 0.42), vec3(0.0), vec3(1.0)), warped.a);
}
float final_event_envelope(float clock) {
	float duration = final_operator_duration;
	if (duration <= 0.0001) { return 1.0; }
	float p = (clock - final_operator_event_start) / duration;
	if (p <= 0.0 || p >= 1.0) { return 0.0; }
	if (p < 0.16) { return smoothstep(0.0, 1.0, p / 0.16); }
	if (p < 0.64) { return 1.0; }
	return 1.0 - smoothstep(0.0, 1.0, (p - 0.64) / 0.36);
}

void fragment() {
	vec4 captured = texture(screen_tex, SCREEN_UV);
	float amount = clamp(final_tint_amount, 0.0, 1.0);
	float operator_strength = clamp(final_operator_strength, 0.0, 1.0);
	float supplied_clock = mix(presentation_time, free_run_time, clamp(final_time_source, 0.0, 1.0));
	operator_strength *= final_event_envelope(supplied_clock);
	if (final_operator_mode > 3.5 && final_operator_mode < 4.5) {
		vec3 lines = speedlines_field(SCREEN_UV, supplied_clock * max(final_operator_speed, 0.0), operator_strength, final_operator_scale);
		vec4 vacuum = vacuum_burst(SCREEN_UV, supplied_clock, operator_strength, final_operator_scale, captured);
		COLOR = vec4(clamp(vacuum.rgb + lines * 0.72, vec3(0.0), vec3(1.0)), vacuum.a);
	} else if (final_operator_mode > 2.5 && final_operator_mode < 3.5) {
		COLOR = vacuum_burst(SCREEN_UV, supplied_clock, operator_strength, final_operator_scale, captured);
	} else if (final_operator_mode > 1.5 && final_operator_mode < 2.5) {
		COLOR = pattern_transition(SCREEN_UV, captured, supplied_clock, operator_strength, final_operator_scale);
	} else if (final_operator_mode > 0.5 && final_operator_mode < 1.5) {
		vec3 lines = speedlines_field(SCREEN_UV, supplied_clock * max(final_operator_speed, 0.0), operator_strength, final_operator_scale);
		COLOR = vec4(clamp(captured.rgb + lines * (0.35 + 0.65 * operator_strength), vec3(0.0), vec3(1.0)), captured.a);
	} else if (amount <= 0.00001) {
		COLOR = captured;
	} else {
		float scan = 0.5 + 0.5 * sin(UV.y * 720.0 * FINAL_PI + supplied_clock * 2.0);
		float strength = amount * (0.75 + 0.25 * scan);
		vec3 tinted = mix(captured.rgb, captured.rgb * final_tint_color.rgb, strength);
		COLOR = vec4(tinted, captured.a);
	}
}
