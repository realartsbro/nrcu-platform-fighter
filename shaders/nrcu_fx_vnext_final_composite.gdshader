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

const float FINAL_PI = 3.14159265359;

void fragment() {
	vec4 captured = texture(screen_tex, SCREEN_UV);
	float amount = clamp(final_tint_amount, 0.0, 1.0);
	if (amount <= 0.00001) {
		COLOR = captured;
	} else {
		float supplied_clock = mix(presentation_time, free_run_time, clamp(final_time_source, 0.0, 1.0));
		float scan = 0.5 + 0.5 * sin(UV.y * 720.0 * FINAL_PI + supplied_clock * 2.0);
		float strength = amount * (0.75 + 0.25 * scan);
		vec3 tinted = mix(captured.rgb, captured.rgb * final_tint_color.rgb, strength);
		COLOR = vec4(tinted, captured.a);
	}
}
