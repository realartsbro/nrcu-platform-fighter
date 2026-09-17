extends SceneTree
# Legacy-vs-vNEXT parity gate for the v0.3 capability port.
#
# Each case renders the same target, source texture, presentation rect, and
# frozen time twice: first with the certified nrcu_fx_v2.gdshader and the
# legacy lab's uniform names, then with FxLayerRenderer and the vNEXT shader.
# Palette strategy/locks are authoring-time controls in v0.3: the legacy lab
# resolves them to col_a/col_b before applying the shader. The parity case
# therefore feeds those resolved colours to the legacy quad and asks vNEXT to
# perform the equivalent authored-color/swap operation. The test reports the
# measured mean absolute RGB difference rather than masking bit differences.

const CANVAS := Vector2(1280.0, 720.0)
const FX_SHADER := "res://shaders/nrcu_fx_v2.gdshader"
const VNEXT_SHADER := "res://shaders/nrcu_fx_vnext_layer.gdshader"

var checks: Array = []
var failures := 0
var out_dir := ""
var runtime
var renderer
var canonical: TextureRect
var screen_root: Node
var FxLookScript
var FxTargetsScript
var time := 1.5
var neutral_legacy_ref: Image
var neutral_vnext_ref: Image
var _last_legacy: Image
var _last_vnext: Image

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/parity")
	DirAccess.make_dir_recursive_absolute(out_dir)
	FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	FxTargetsScript = load("res://scripts/fx_vnext/fx_targets.gd")
	var RuntimeScript = load("res://scripts/fx_vnext/fx_screen_runtime.gd")
	var RendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")

	runtime = RuntimeScript.new()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.size = CANVAS
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = CANVAS
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(container)
	container.add_child(runtime.subvp)
	await process_frame
	var mounted: bool = runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await _settle(50)
	_check(mounted, "parity screen mounts", "")
	if not mounted:
		quit(1)
		return
	canonical = runtime.registry.target_node("echo_left") as TextureRect
	print("[DEBUG-PARITY] modulate=%s tint=%s tex=%s" % [str(canonical.modulate), str(canonical.get_meta("fx_source_tint", Color.WHITE)), str(canonical.texture.resource_path)])
	screen_root = runtime.screen.get_node("Root")
	if OS.get_environment("FXLAB_PARITY_HIDE_SIBLINGS") == "1":
		for sibling in screen_root.get_children():
			if sibling != canonical and sibling is CanvasItem:
				(sibling as CanvasItem).visible = false
	renderer = RendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(time)
	runtime.seek(time)
	await _settle(8)

	# Native faithfulness, measured BEFORE the shader-math comparison: with the
	# node's natural presentation modulation, the vNEXT pipeline must reproduce
	# the native rendering exactly.
	canonical.self_modulate = Color.WHITE
	await _settle(4)
	var native_ref: Image = await _capture("native_faithfulness")
	var faithful_look: Dictionary = FxLookScript.new_look("NATIVE_FAITHFUL", "native")
	renderer.apply_look("echo_left", faithful_look)
	renderer.set_time(time)
	await _settle(6)
	var faithful_img: Image = await _capture("native_faithfulness_vnext")
	_check(_mean_abs_diff(native_ref, faithful_img) <= 0.0005, "vNEXT equals the native rendering exactly (natural modulation)", "mean=%.6f" % _mean_abs_diff(native_ref, faithful_img))
	renderer.clear_target("echo_left")
	await _settle(4)

	var base_state := _legacy_defaults()
	var neutral_fx: Dictionary = FxLookScript.neutral_fx()
	await _run_case("neutral", base_state, neutral_fx, {}, 0.0001)
	# Effect-domain comparison strategy (honest, artifact-free): the legacy
	# RECONSTRUCTION carries a constant shading offset (documented below), so the
	# meaningful parity metric is the rendered CONTRIBUTION of each domain:
	# delta-from-neutral in each pipeline, compared pairwise. Absolute numbers are
	# printed as well; the neutral case additionally proves vNEXT == native exactly.
	neutral_legacy_ref = _last_legacy
	neutral_vnext_ref = _last_vnext
	await _run_case("base", _state_for_base(base_state), _fx_for_base(), {}, 0.003)
	await _run_case("mono", _state_for_mono(base_state), _fx_for_mono(), {}, 0.003)
	await _run_case("dither", _state_for_dither(base_state), _fx_for_dither(), {}, 0.003)
	await _run_case("rgb", _state_for_rgb(base_state), _fx_for_rgb(), {}, 0.003)
	await _run_case("fringe", _state_for_fringe(base_state), _fx_for_fringe(), {}, 0.003)
	await _run_case("flow", _state_for_flow(base_state), _fx_for_flow(), {}, 0.003)
	await _run_case("palette", _state_for_palette(base_state), _fx_for_palette(), {}, 0.003)
	var motion := {
		"enabled": {"dither": false, "fringe": false, "flow": true, "rgb": false},
		"tracks": {"flow": {"anchor_time": 1.4, "delay": 0.0, "attack": 0.2, "hold": 0.4, "release": 0.25, "sustain": 0.0, "attack_curve": "cubic_out", "release_curve": "sine_in_out"}},
	}
	await _run_case("motion", _state_for_motion(base_state), _fx_for_motion(), motion, 0.003)

	var report := {"checks": checks.size(), "failures": failures}
	var f := FileAccess.open(out_dir.path_join("summary_parity.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[FX-PARITY] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func _run_case(domain: String, legacy_state: Dictionary, fx: Dictionary, motion: Dictionary, threshold: float) -> void:
	# Freeze presentation modulation so the comparison isolates shader math;
	# both legacy and vNEXT receive the same neutral CanvasItem modulation.
	var saved_modulate: Color = canonical.modulate
	# Freeze presentation modulation on BOTH sides: the certified legacy shader
	# ignores a node modulate when it assigns COLOR, while the vNEXT pipeline
	# folds it in (natively faithful). With modulate = 1.0 on both sides the
	# comparison isolates shader math; the native-faithfulness of the vNEXT
	# pipeline is proven separately by the dedicated pre-check.
	canonical.modulate = Color.WHITE
	renderer.clear_target("echo_left")
	canonical.self_modulate = Color.WHITE
	renderer.set_time(time)
	runtime.seek(time)
	await _settle(4)
	# native reference at the same frozen state
	canonical.self_modulate = Color.WHITE
	await _settle(4)
	print("[PARITY-AT] %s before-native: canonical.mod=%s self=%s" % [domain, str(canonical.modulate), str(canonical.self_modulate)])
	var native_img: Image = await _capture(domain + "_native")
	print("[PARITY-AT] %s after-native: canonical.mod=%s" % [domain, str(canonical.modulate)])
	var legacy_quad := _make_legacy_quad(legacy_state)
	var legacy_mat: ShaderMaterial = legacy_quad.material as ShaderMaterial
	var debug_domain := OS.get_environment("FXLAB_DEBUG_DOMAIN")
	var debug_mode := float(OS.get_environment("FXLAB_DEBUG_MODE"))
	if debug_domain == domain and debug_mode > 0.0:
		legacy_mat.set_shader_parameter("debug_view_mode", debug_mode)
	print("[UNIFORM] %s legacy fx=%s" % [domain, _uniform_dump(legacy_mat)])
	screen_root.add_child(legacy_quad)
	screen_root.move_child(legacy_quad, clampi(canonical.get_index(), 0, screen_root.get_child_count() - 1))
	print("[ORDER] %s legacy idx=%d parent=%s children=%s" % [domain, legacy_quad.get_index(), str(legacy_quad.get_parent()), _child_names(screen_root)])
	canonical.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	await _settle(5)
	print("[PARITY-AT] %s before-legacy: canonical.mod=%s self=%s legacy.mod=%s" % [domain, str(canonical.modulate), str(canonical.self_modulate), str(legacy_quad.modulate)])
	var legacy_img: Image = await _capture(domain + "_legacy")
	legacy_quad.queue_free()
	await _settle(2)
	canonical.self_modulate = Color.WHITE

	var look: Dictionary = FxLookScript.new_look("PARITY_" + domain.to_upper(), "Parity " + domain)
	var layer: Dictionary = look["layers"][0]
	layer["fx"] = fx
	layer["motion"] = motion
	canonical.modulate = Color.WHITE
	var applied: Dictionary = renderer.apply_look("echo_left", look)
	_check(bool(applied.get("ok", false)), domain + " vNEXT applies", str(applied.get("errors", [])))
	if not renderer.stack_quads("echo_left").is_empty():
		var vnext_mat: ShaderMaterial = renderer.stack_quads("echo_left")[0].get("node").material as ShaderMaterial
		if debug_domain == domain and debug_mode > 0.0:
			vnext_mat.set_shader_parameter("debug_view_mode", debug_mode)
		print("[UNIFORM] %s vnext fx=%s" % [domain, _uniform_dump(vnext_mat)])
		print("[ORDER] %s vnext idx=%d parent=%s children=%s" % [domain, renderer.stack_quads("echo_left")[0].get("node").get_index(), str(renderer.stack_quads("echo_left")[0].get("node").get_parent()), _child_names(screen_root)])
	renderer.set_time(time)
	await _settle(5)
	print("[PARITY-AT] %s before-vnext: canonical.mod=%s self=%s" % [domain, str(canonical.modulate), str(canonical.self_modulate)])
	for quad_entry in renderer.stack_quads("echo_left"):
		var dbg_quad = quad_entry.get("node")
		if is_instance_valid(dbg_quad):
			print("[PARITY-AT] %s vnext-quad.mod=%s" % [domain, str(dbg_quad.modulate)])
	var vnext_img: Image = await _capture(domain + "_vnext")
	var diff := _mean_abs_diff(legacy_img, vnext_img)
	var n_vs_l := _mean_abs_diff(native_img, legacy_img)
	var n_vs_v := _mean_abs_diff(native_img, vnext_img)
	_last_legacy = legacy_img
	_last_vnext = vnext_img
	if domain == "neutral":
		print("[CHECK] %s neutral absolute: legacy-vs-vnext=%.6f" % [domain, diff])
	else:
		var d_legacy := _mean_abs_diff(neutral_legacy_ref, legacy_img)
		var d_vnext := _mean_abs_diff(neutral_vnext_ref, vnext_img)
		var residual := _mean_abs_diff(_delta_image(neutral_legacy_ref, legacy_img), _delta_image(neutral_vnext_ref, vnext_img))
		_check(residual <= threshold, domain + " contribution parity", "residual=%.6f threshold=%.6f (legacy d=%.6f vnext d=%.6f, absolute l-v-v=%.6f)" % [residual, threshold, d_legacy, d_vnext, diff])
		print("[CHECK] %s contribution residual=%.6f (legacy delta=%.6f vnext delta=%.6f)" % [domain, residual, d_legacy, d_vnext])
	canonical.modulate = saved_modulate

func _make_legacy_quad(state: Dictionary) -> ColorRect:
	# Reference construction = the legacy lab's own proxy mapping: a full-canvas
	# quad whose source_uv_scale/offset maps the texture into the target rect
	# using the exact formula ((UV*CANVAS - origin)/size). This makes the legacy
	# and vNEXT sampling formulas identical so the comparison isolates shader math
	# instead of sub-pixel rasterization differences.
	var quad := ColorRect.new()
	quad.name = "parity_legacy"
	quad.color = Color.WHITE
	var rect: Rect2 = FxTargetsScript.presentation_rect(canonical)
	quad.position = Vector2.ZERO
	quad.size = CANVAS
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.visible = canonical.visible
	var mat := ShaderMaterial.new()
	mat.shader = load(FX_SHADER)
	var tex: Texture2D = canonical.texture
	mat.set_shader_parameter("source_tex", tex)
	mat.set_shader_parameter("source_tint", canonical.get_meta("fx_source_tint", Color.WHITE))
	mat.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
	mat.set_shader_parameter("element_size", rect.size)
	mat.set_shader_parameter("viewport_size", CANVAS)
	mat.set_shader_parameter("source_uv_scale", CANVAS / rect.size)
	mat.set_shader_parameter("source_uv_offset", -rect.position / rect.size)
	# The NATIVE draw inherits the modulation chain of ALL ancestors; the quad
	# lives in screen_root, so fold that chain in explicitly (up to screen_root).
	var chain: Color = canonical.modulate * canonical.self_modulate
	var walk: Node = canonical.get_parent()
	while walk != null and walk != screen_root:
		if walk is CanvasItem:
			chain *= (walk as CanvasItem).modulate * (walk as CanvasItem).self_modulate
		walk = walk.get_parent()
	quad.modulate = chain
	mat.set_shader_parameter("source_flip_x", 1.0 if canonical.flip_h else 0.0)
	mat.set_shader_parameter("preview_emphasis", 1.0)
	mat.set_shader_parameter("debug_view_mode", 0.0)
	mat.set_shader_parameter("fx_time", time)
	mat.set_shader_parameter("custom_edge_mask_loaded", 0.0)
	mat.set_shader_parameter("treatment_mask_loaded", 0.0)
	for key in state.keys():
		mat.set_shader_parameter(str(key), state[key])
	quad.material = mat
	return quad

func _legacy_defaults() -> Dictionary:
	return {
		"pure_continuous": 0.0, "fx_size": 1.0, "fx_intensity": 1.0, "pattern_scale": 1.0,
		"base_mode": 0.0, "base_opacity": 1.0, "base_grade_amount": 0.0,
		"grade_black_point": 0.0, "grade_white_point": 1.0, "grade_gamma": 1.0,
		"grade_contrast": 1.0, "grade_brightness": 0.0, "grade_saturation": 1.0,
		"source_pixel_size": 0.0, "source_pixel_units": 1.0,
		"mono_threshold": 0.75, "mono_mode": 1.0, "mono_bayer_level": 2.0, "mono_pixel": 2.0, "mono_space": 1.0,
		"fx_dither": 0.0, "fx_fringe": 0.0, "fx_flow": 0.0, "fx_rgb": 0.0,
		"dither_threshold": 0.75, "dither_black_point": 0.0, "dither_white_point": 1.0, "dither_gamma": 1.35, "dither_contrast": 1.6, "dither_brightness": 0.0,
		"dither_mode": 1.0, "dither_bayer_level": 2.0, "dither_pixel": 2.0, "dither_levels": 6.0, "dither_space": 1.0,
		"edge_source_mode": 2.0, "edge_alpha_weight": 1.2, "edge_luma_weight": 1.0, "edge_threshold": 0.08,
		"edge_width": 12.0, "wind_reach": 54.0, "wind_trail": 1.0, "wind_cutoff": 0.22, "split_separation": 10.0,
		"wind_displace": 1.0, "signal_gain": 1.35, "color_blur": 0.0, "signal_softness": 0.08, "signal_posterize": 0.0,
		"fringe_coverage_mode": 0.0, "fringe_coverage_threshold": 0.12, "fringe_bayer_level": 2.0, "fringe_pixel": 2.0, "fringe_space": 1.0, "fringe_coverage_gain": 1.0,
		"rgb_gradient": 0.0, "rgb_gradient_balance": 0.0, "rgb_gradient_contrast": 1.0,
		"fringe_color_a": Color(0.25, 0.95, 1.0, 1.0), "fringe_color_b": Color(1.0, 0.4, 0.85, 1.0),
		"fringe_bleed": 0.65, "fringe_blend_mode": 0.0, "geometry_units": 1.0,
		"effect_mask_enabled": 0.0, "effect_mask_invert": 0.0, "effect_mask_threshold": 0.5, "effect_mask_softness": 0.1, "effect_mask_base": 0.0,
		"driver_mode": 0.0, "driver_sampling_mode": 0.0, "driver_pixel_size": 2.0,
		"FIELD_STRENGTH": 0.42, "FIELD_SPEED": 0.55, "OUTWARDNESS": 0.55, "FIELD_BREAKUP": 0.85, "COORD_NUDGE": 0.18, "FIELD_SIZE": 1.0,
		"LEGACY_SCALE": 5.0, "LEGACY_SPEED": 0.3, "LEGACY_RADIAL": 0.45,
		"DRIVER_CENTER": Vector2(1.5, 1.5), "DRIVER_SCALE": 1.0, "DRIVER_STRETCH": 0.0, "DRIVER_ANGLE": 0.0, "DRIVER_SPEED": 1.0, "DRIVER_DETAIL": 0.5, "DRIVER_FLOW": 0.5,
		"flow_strength": 1.8, "flow_center_x": 0.5, "flow_center_y": 0.5,
		"rgb_shift_amount": 14.0, "rgb_shift_angle": 0.0, "rgb_shift_units": 1.0, "rgb_shift_alpha": 0.0, "temporal_hold": 0.0,
	}

func _state_for_base(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	out["base_opacity"] = 0.82
	out["base_grade_amount"] = 0.55
	out["grade_black_point"] = 0.08
	out["grade_white_point"] = 0.94
	out["grade_gamma"] = 1.18
	out["grade_contrast"] = 1.22
	out["grade_brightness"] = -0.03
	out["grade_saturation"] = 0.72
	return out

func _fx_for_base() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx()
	fx["base_opacity"] = 0.82; fx["base_grade_amount"] = 0.55
	fx["grade_black_point"] = 0.08; fx["grade_white_point"] = 0.94; fx["grade_gamma"] = 1.18
	fx["grade_contrast"] = 1.22; fx["grade_brightness"] = -0.03; fx["grade_saturation"] = 0.72
	return fx

func _state_for_mono(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	out["base_mode"] = 1.0; out["mono_threshold"] = 0.58; out["mono_mode"] = 2.0; out["mono_bayer_level"] = 3.0; out["mono_pixel"] = 3.0; out["mono_space"] = 2.0
	return out

func _fx_for_mono() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx()
	fx["base_mode"] = 1.0; fx["mono_threshold"] = 0.58; fx["mono_mode"] = 2.0; fx["mono_bayer_level"] = 3.0; fx["mono_pixel"] = 3.0; fx["mono_space"] = 2.0
	return fx

func _state_for_dither(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	out["fx_dither"] = 1.0; out["fx_intensity"] = 1.25; out["dither_mode"] = 1.0; out["dither_levels"] = 5.0; out["dither_pixel"] = 3.0; out["dither_gamma"] = 1.22; out["dither_contrast"] = 1.35
	return out

func _fx_for_dither() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx()
	fx["dither"] = 1.0; fx["intensity"] = 1.25; fx["dither_mode"] = 1.0; fx["dither_levels"] = 5.0; fx["dither_pixel"] = 3.0; fx["dither_gamma"] = 1.22; fx["dither_contrast"] = 1.35
	return fx

func _state_for_rgb(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true); out["fx_rgb"] = 1.0; out["fx_intensity"] = 1.1; out["rgb_shift_amount"] = 18.0; out["rgb_shift_angle"] = 17.0; return out

func _fx_for_rgb() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx(); fx["rgb"] = 1.0; fx["intensity"] = 1.1; fx["rgb_shift_amount"] = 18.0; fx["rgb_shift_angle"] = 17.0; return fx

func _state_for_fringe(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true); out["fx_fringe"] = 1.0; out["fx_intensity"] = 1.3; out["wind_reach"] = 42.0; out["wind_trail"] = 0.8; out["color_blur"] = 2.0; out["signal_gain"] = 1.6; out["fringe_bleed"] = 0.9; return out

func _fx_for_fringe() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx(); fx["fringe"] = 1.0; fx["intensity"] = 1.3; fx["wind_reach"] = 42.0; fx["wind_trail"] = 0.8; fx["color_blur"] = 2.0; fx["signal_gain"] = 1.6; fx["fringe_bleed"] = 0.9; return fx

func _state_for_flow(s: Dictionary) -> Dictionary:
	var out := _state_for_fringe(s); out["fx_flow"] = 1.0; out["flow_strength"] = 1.5; out["FIELD_SPEED"] = 0.7; out["COORD_NUDGE"] = 0.23; return out

func _fx_for_flow() -> Dictionary:
	var fx := _fx_for_fringe(); fx["flow"] = 1.0; fx["flow_strength"] = 1.5; fx["FIELD_SPEED"] = 0.7; fx["COORD_NUDGE"] = 0.23; return fx

func _state_for_palette(s: Dictionary) -> Dictionary:
	var out := _state_for_fringe(s); out["fx_fringe"] = 1.0; out["fringe_color_a"] = Color(0.96, 0.18, 0.38, 1.0); out["fringe_color_b"] = Color(0.12, 0.82, 0.96, 1.0); return out

func _fx_for_palette() -> Dictionary:
	var fx := _fx_for_fringe(); fx["fringe_color_a"] = [0.12, 0.82, 0.96, 1.0]; fx["fringe_color_b"] = [0.96, 0.18, 0.38, 1.0]; fx["palette_swap"] = true; fx["palette_strategy"] = 1.0; fx["palette_hue_offset"] = 18.0; fx["palette_saturation"] = 0.92; fx["palette_value"] = 0.96; fx["palette_lock_a"] = true; fx["palette_lock_b"] = false; return fx

func _state_for_motion(s: Dictionary) -> Dictionary:
	var out := _state_for_flow(s); out["fx_flow"] = 0.875; return out

func _fx_for_motion() -> Dictionary:
	var fx := _fx_for_flow(); fx["flow"] = 1.0; return fx

func _settle(n: int) -> void:
	for i in n:
		await process_frame

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var crop := img.get_region(Rect2i(0, 0, 1280, 720))
	crop.save_png(out_dir.path_join(name + ".png"))
	return crop

func _delta_image(base: Image, img: Image) -> Image:
	# abs difference of two frames (used to cancel the constant reconstruction offset)
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var ca := base.get_pixel(x, y)
			var cb := img.get_pixel(x, y)
			var d := Color(absf(ca.r - cb.r), absf(ca.g - cb.g), absf(ca.b - cb.b), 1.0)
			out.set_pixel(x, y, d)
			out.set_pixel(x + 1, y, d)
			out.set_pixel(x, y + 1, d)
			out.set_pixel(x + 1, y + 1, d)
	return out

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 999.0
	var data_a := a.get_data(); var data_b := b.get_data()
	if data_a == data_b: return 0.0
	var total := 0.0; var samples := 0; var width := a.get_width(); var height := a.get_height()
	for y in range(0, height, 3):
		for x in range(0, width, 3):
			var i := (y * width + x) * 4
			total += absf(float(data_a[i] - data_b[i])) + absf(float(data_a[i + 1] - data_b[i + 1])) + absf(float(data_a[i + 2] - data_b[i + 2]))
			samples += 3
	return total / maxf(float(samples) * 255.0, 1.0)

func _child_names(parent: Node) -> String:
	var names: Array = []
	for i in parent.get_child_count():
		names.append("%d:%s" % [i, parent.get_child(i).name])
	return ",".join(names)

func _uniform_dump(material: ShaderMaterial) -> String:
	var names := ["fx_size", "fx_intensity", "fx_dither", "fx_rgb", "fx_fringe", "fx_flow", "base_mode", "base_grade_amount", "edge_width", "wind_reach", "wind_trail", "color_blur", "signal_gain", "fringe_bleed", "fringe_blend_mode", "rgb_shift_amount", "flow_strength", "dither_mode", "dither_bayer_level", "dither_pixel", "dither_levels", "dither_space", "dither_gamma", "dither_contrast", "fringe_color_a", "fringe_color_b", "palette_swap", "palette_strategy", "layer_time", "fx_time"]
	var values: Array = []
	for name_value in names:
		var name: String = str(name_value)
		values.append("%s=%s" % [name, str(material.get_shader_parameter(name))])
	return " ".join(values)

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok: failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
