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
uniform vec2 final_operator_center = vec2(0.5, 0.5);
uniform vec2 final_operator_axis = vec2(1.0, 0.0);
uniform float final_operator_progress = 0.5;
uniform float final_operator_polarity = 0.0; // 0 pull, 1 push
uniform float final_operator_mix_mode = 0.0; // speedlines: 0 lines, 1 distortion, 2 combined
uniform vec4 final_operator_color_a : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform vec4 final_operator_color_b : source_color = vec4(1.0, 0.35, 0.82, 1.0);
const float EPS = 0.0001;

const float FINAL_PI = 3.14159265359;

// Dedicated Gold operators. These are full-frame primitives over the captured
// composition, with explicit center/axis/progress controls and supplied clocks.
float speedline_coverage(vec2 uv, float clock, float strength, float scale) {
    vec2 aspect = vec2(1.7777778, 1.0);
    vec2 centered = (uv - final_operator_center) * aspect;
    float radius = length(centered);
    float angle = atan(centered.y, centered.x);
    vec2 axis = normalize(final_operator_axis + vec2(EPS));
    float axis_value = dot(uv - final_operator_center, axis);
    float rays = abs(sin(angle * (28.0 + 10.0 * clamp(scale, 0.25, 4.0)) + clock * 1.7));
    if (final_operator_pattern_mode > 0.5) {
        rays = abs(sin(axis_value * (42.0 + 16.0 * scale) + clock * 2.4));
    }
    float streak = pow(clamp(1.0 - rays, 0.0, 1.0), 18.0);
    float falloff = final_operator_pattern_mode > 0.5
        ? smoothstep(0.04, 0.92, abs(axis_value) * 2.0)
        : smoothstep(0.08, 0.95, radius) * smoothstep(1.15, 0.52, radius);
    return clamp(streak * falloff * strength, 0.0, 1.0);
}

vec3 speedlines_field(vec2 uv, float clock, float strength, float scale) {
    vec2 centered = (uv - final_operator_center) * vec2(1.7777778, 1.0);
    float angle = atan(centered.y, centered.x);
    float coverage = speedline_coverage(uv, clock, strength, scale);
    return mix(final_operator_color_b.rgb, final_operator_color_a.rgb,
        clamp(0.5 + 0.5 * sin(angle * 2.0), 0.0, 1.0)) * coverage;
}

vec2 speedline_offset(vec2 uv, float clock, float strength, float scale) {
    vec2 centered = (uv - final_operator_center) * vec2(1.7777778, 1.0);
    vec2 radial_dir = normalize(centered + vec2(EPS));
    vec2 planar_dir = normalize(final_operator_axis + vec2(EPS));
    vec2 direction = final_operator_pattern_mode > 0.5 ? planar_dir : radial_dir;
    float coverage = speedline_coverage(uv, clock, strength, scale);
    float wave = sin(dot(uv - final_operator_center, planar_dir) * 48.0 + clock * 3.0);
    return direction * wave * coverage * final_operator_distortion * 0.12;
}

vec4 speedlines_composite(vec2 uv, vec4 captured, float clock, float strength, float scale) {
    vec3 lines = speedlines_field(uv, clock, strength, scale);
    vec2 offset = speedline_offset(uv, clock, strength, scale);
    vec4 warped = texture(screen_tex, clamp(uv + offset, vec2(0.0), vec2(1.0)));
    if (final_operator_mix_mode < 0.5) {
        return vec4(clamp(captured.rgb + lines, vec3(0.0), vec3(1.0)), captured.a);
    }
    if (final_operator_mix_mode < 1.5) {
        return warped;
    }
    return vec4(clamp(mix(warped.rgb, captured.rgb + lines, 0.65), vec3(0.0), vec3(1.0)), captured.a);
}

// Pattern families form the reveal mask; progress 0 is captured-only and
// progress 1 is graphic-only, so the transition has defined endpoints.
vec4 pattern_transition(vec2 uv, vec4 captured, float clock, float strength, float scale) {
    vec2 axis = normalize(final_operator_axis + vec2(EPS));
    vec2 cell = floor(uv * vec2(18.0, 10.0) * max(scale, 0.25));
    float family = final_operator_pattern_family;
    float pattern = 0.0;
    if (family < 0.5) {
        float stripe = dot(uv, axis) * (34.0 + 10.0 * scale) - clock * 1.5;
        pattern = 0.5 + 0.5 * sin(stripe);
    } else if (family < 1.5) {
        vec2 dot_cell = fract(uv * vec2(13.0, 9.0) * max(scale, 0.25)) - vec2(0.5);
        pattern = smoothstep(0.30, 0.08, length(dot_cell));
    } else {
        float checker = mod(cell.x + cell.y, 2.0);
        float angular = 0.5 + 0.5 * sin(dot(uv - vec2(0.5), axis) * 52.0 + clock * 2.0);
        pattern = mix(checker, angular, 0.42);
    }
    float threshold = 1.0 - clamp(final_operator_progress, 0.0, 1.0);
    float softness = max(final_operator_softness, 0.01);
    float reveal = smoothstep(threshold - softness, threshold + softness, pattern);
    if (final_operator_progress <= 0.001) { reveal = 0.0; }
    if (final_operator_progress >= 0.999) { reveal = 1.0; }
    float graphic_amount = reveal * clamp(strength, 0.0, 1.0);
    vec3 graphic = mix(final_operator_color_b.rgb, final_operator_color_a.rgb, pattern);
    return vec4(mix(captured.rgb, graphic, graphic_amount), captured.a);
}

// Dedicated screen-space vacuum burst: center-anchored pull/push warp plus a
// moving radial ring. Polarity is explicit instead of hidden in a sign.
vec4 vacuum_burst(vec2 uv, float clock, float strength, float scale, vec4 captured) {
    vec2 p = (uv - final_operator_center) * vec2(1.7777778, 1.0);
    float radius = length(p);
    vec2 outward = normalize(p + vec2(EPS));
    float wave = sin(clock * 4.0 - radius * 18.0);
    float warp_amount = wave * smoothstep(1.0, 0.05, radius) * strength * 0.018 * max(scale, 0.25);
    float polarity_sign = final_operator_polarity < 0.5 ? -1.0 : 1.0;
    vec2 warped_uv = clamp(uv + outward * warp_amount * polarity_sign, vec2(0.0), vec2(1.0));
    vec4 warped = texture(screen_tex, warped_uv);
    float ring_radius = 0.22 + 0.04 * sin(clock * 2.0);
    float ring = exp(-abs(radius - ring_radius) * 34.0) * strength;
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
		float p = final_operator_duration <= 0.0001 ? 1.0 : (supplied_clock - final_operator_event_start) / final_operator_duration;
		float vacuum_phase = smoothstep(0.04, 0.20, p) * (1.0 - smoothstep(0.58, 0.82, p));
		float lines_phase = smoothstep(0.16, 0.36, p) * (1.0 - smoothstep(0.76, 0.98, p));
		vec4 vacuum = vacuum_burst(SCREEN_UV, supplied_clock, operator_strength * vacuum_phase, final_operator_scale, captured);
		vec4 lines = speedlines_composite(SCREEN_UV, vacuum, supplied_clock * max(final_operator_speed, 0.0), operator_strength * lines_phase, final_operator_scale);
		COLOR = p <= 0.0 || p >= 1.0 ? captured : lines;
	} else if (final_operator_mode > 2.5 && final_operator_mode < 3.5) {
		COLOR = vacuum_burst(SCREEN_UV, supplied_clock, operator_strength, final_operator_scale, captured);
	} else if (final_operator_mode > 1.5 && final_operator_mode < 2.5) {
		COLOR = pattern_transition(SCREEN_UV, captured, supplied_clock, operator_strength, final_operator_scale);
	} else if (final_operator_mode > 0.5 && final_operator_mode < 1.5) {
		COLOR = speedlines_composite(SCREEN_UV, captured, supplied_clock * max(final_operator_speed, 0.0), operator_strength, final_operator_scale);
	} else if (amount <= 0.00001) {
		COLOR = captured;
	} else {
		float scan = 0.5 + 0.5 * sin(UV.y * 720.0 * FINAL_PI + supplied_clock * 2.0);
		float strength = amount * (0.75 + 0.25 * scan);
		vec3 tinted = mix(captured.rgb, captured.rgb * final_tint_color.rgb, strength);
		COLOR = vec4(tinted, captured.a);
	}
}
