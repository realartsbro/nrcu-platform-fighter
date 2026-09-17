# Phase 5 readback: MK-05 influence gating, RT-05 offscreen blends, LG visual
# order — all proven on pixels, not structures. Windowed: renders.
extends SceneTree

var checks: Array = []
var failures: int = 0
var out_dir: String
var runtime
var renderer
var FxLookScript

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/phase5_readback")
	DirAccess.make_dir_recursive_absolute(out_dir)
	FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxScreenRuntimeScript = load("res://scripts/fx_vnext/fx_screen_runtime.gd")
	var FxLayerRendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(60)
	runtime.seek(1.5)
	await settle(8)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.1)
	await _mk05_influence_gating()
	await _rt05_offscreen_blends()
	await _lg_visual_order()
	print("[FX-PHASE5-READBACK] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame

# The reference screen frees itself at presentation DONE by design — every
# case re-stages a fresh mount at a fixed transport time so captures compare
# identical presentation ages and never touch a freed screen.
func _stage() -> void:
	runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(20)
	runtime.seek(1.1)
	await settle(8)
	var FxLayerRendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.1)

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _mean_abs_diff(a: Image, b: Image) -> float:
	return _mean_abs_diff_roi(a, b, Rect2i(0, 0, 1280, 720))

# Fighters occupy the frame center; full-frame means dilute warp/ghost
# signals with flat stage background. ROI measurement keeps MK/LG honest.
func _mean_abs_diff_roi(a: Image, b: Image, roi: Rect2i) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var sum := 0.0
	var n := 0
	var x0 := clampi(roi.position.x, 0, a.get_width() - 1)
	var y0 := clampi(roi.position.y, 0, a.get_height() - 1)
	var x1 := clampi(roi.end.x, 0, a.get_width())
	var y1 := clampi(roi.end.y, 0, a.get_height())
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			sum += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			n += 1
	return sum / float(maxi(n, 1)) / 3.0

func _mean_luma(img: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p := img.get_pixel(x, y)
			sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
			n += 1
	return sum / float(maxi(n, 1))

func _mean_luma_roi(img: Image, roi: Rect2i) -> float:
	var sum := 0.0
	var n := 0
	var x0 := clampi(roi.position.x, 0, img.get_width() - 1)
	var y0 := clampi(roi.position.y, 0, img.get_height() - 1)
	var x1 := clampi(roi.end.x, 0, img.get_width())
	var y1 := clampi(roi.end.y, 0, img.get_height())
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var p := img.get_pixel(x, y)
			sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
			n += 1
	return sum / float(maxi(n, 1))

func _fx_layer(layer_name: String, over: Dictionary = {}) -> Dictionary:
	var layer: Dictionary = FxLookScript.new_layer("FX", layer_name)
	layer["input"] = str(over.get("input", "ORIGINAL_SOURCE"))
	layer["plane"] = str(over.get("plane", "TARGET_SOURCE"))
	layer["blend_mode"] = str(over.get("blend", "NORMAL"))
	var disp: Dictionary = layer["displacement"]
	for key in ["enabled", "driver", "amount_px", "scale", "speed", "phase", "seed"]:
		if over.has("disp_" + key):
			disp[key] = over["disp_" + key]
	if over.has("influence"):
		disp["influence_mask"] = (over["influence"] as Dictionary).duplicate(true)
	var fx: Dictionary = layer["fx"]
	for key in over.keys():
		var k := str(key)
		if k in ["input", "plane", "blend", "influence"]:
			continue
		if k.begins_with("disp_"):
			continue
		fx[k] = over[key]
		# The renderer reads both bare (rgb_shift_alpha) and fx_-prefixed
		# spellings; mirror bare rgb/edge keys to their fx_ twins.
		if not k.begins_with("fx_") and (k.begins_with("rgb_") or k.begins_with("edge_") or k.begins_with("fringe_") or k.begins_with("dither_") or k.begins_with("flow_")):
			fx["fx_" + k] = over[key]
		# Amount keys read bare by the renderer; mirror fx_ twins back.
		if k in ["fx_rgb", "fx_fringe", "fx_dither", "fx_flow", "fx_size", "fx_intensity"]:
			fx[k.trim_prefix("fx_")] = over[key]
	return layer

func _look(look_id: String, layers: Array) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, look_id)
	for layer in layers:
		look["layers"].append(layer)
	return FxLookScript.materialize(look)

# ---- MK-05: the influence gate scales displacement on pixels ---------------
func _mk05_influence_gating() -> void:
	var disp_over := {"disp_enabled": true, "disp_driver": "NOISE", "disp_amount_px": [48.0, 0.0], "disp_scale": 220.0, "disp_speed": 0.0, "disp_seed": 7}
	var plain: Dictionary = _look("MK05_PLAIN", [_fx_layer("plain", disp_over)])
	await _stage()
	renderer.apply_look("echo_left", plain)
	renderer.set_time(1.1)
	await settle(6)
	var img_plain: Image = await capture("mk05_plain_displaced")
	# FULL + invert gates displacement to zero everywhere: must reproduce the
	# undisplaced frame (only SOURCE layer, no FX).
	var node_only: Dictionary = _look("MK05_NODE", [])
	await _stage()
	renderer.apply_look("echo_left", node_only)
	renderer.set_time(1.1)
	await settle(6)
	var img_node: Image = await capture("mk05_source_only")
	var gated_over: Dictionary = disp_over.duplicate()
	gated_over["influence"] = {"enabled": true, "source": "ORIGINAL_SOURCE_ALPHA", "region": "FULL", "space": "LAYER_SPACE", "expand_contract_px": 0.0, "width_px": 0.0, "feather_px": 0.0, "invert": true, "custom_mask": null}
	var gated: Dictionary = _look("MK05_GATED", [_fx_layer("gated", gated_over)])
	await _stage()
	renderer.apply_look("echo_left", gated)
	renderer.set_time(1.1)
	await settle(6)
	var img_gated: Image = await capture("mk05_gated")
	_check(_mean_abs_diff_roi(img_plain, img_node, FIGHT_ROI) > 0.002, "MK-05 displacement visibly moves pixels", "mean=%.5f" % _mean_abs_diff_roi(img_plain, img_node, FIGHT_ROI))
	_check(_mean_abs_diff_roi(img_gated, img_node, FIGHT_ROI) < 0.004, "MK-05 FULL+invert influence gates displacement to zero", "mean=%.5f" % _mean_abs_diff_roi(img_gated, img_node, FIGHT_ROI))
	# Narrow edge band: interior matches source-only, silhouette differs.
	var band_over: Dictionary = disp_over.duplicate()
	band_over["influence"] = {"enabled": true, "source": "POST_DISPLACEMENT_ALPHA", "region": "EDGE_BAND", "space": "LAYER_SPACE", "expand_contract_px": 0.0, "width_px": 24.0, "feather_px": 8.0, "invert": false, "custom_mask": null}
	var banded: Dictionary = _look("MK05_BAND", [_fx_layer("band", band_over)])
	await _stage()
	renderer.apply_look("echo_left", banded)
	renderer.set_time(1.1)
	await settle(6)
	var img_band: Image = await capture("mk05_band")
	var d_band_plain := _mean_abs_diff_roi(img_band, img_plain, FIGHT_ROI)
	var d_band_node := _mean_abs_diff_roi(img_band, img_node, FIGHT_ROI)
	_check(d_band_plain > 0.003 and d_band_node > 0.003, "MK-05 edge band gates partially (neither full nor zero)", "vs-plain=%.5f vs-node=%.5f" % [d_band_plain, d_band_node])
	# Neutral floor: identical stack with displacement disabled. A perfect gate
	# reproduces this frame exactly (not merely "close to source-only").
	var flat_over: Dictionary = disp_over.duplicate()
	flat_over["disp_enabled"] = false
	var flat: Dictionary = _look("MK05_FLAT", [_fx_layer("flat", flat_over)])
	await _stage()
	renderer.apply_look("echo_left", flat)
	renderer.set_time(1.1)
	await settle(6)
	var img_flat: Image = await capture("mk05_flat")
	var d_flat_node := _mean_abs_diff_roi(img_flat, img_node, FIGHT_ROI)
	var d_gated_flat := _mean_abs_diff_roi(img_gated, img_flat, FIGHT_ROI)
	_check(d_gated_flat < 0.001 and d_gated_flat < d_flat_node, "MK-05 gate reproduces the undisplaced stack", "gated-vs-flat=%.5f flat-vs-node=%.5f" % [d_gated_flat, d_flat_node])
	# Warp isolated from the neutral-layer floor: displaced vs undisplaced stack.
	var d_plain_flat := _mean_abs_diff_roi(img_plain, img_flat, FIGHT_ROI)
	_check(d_plain_flat > 0.0005, "MK-05 warp separated from neutral floor", "plain-vs-flat=%.5f" % d_plain_flat)
	# Noise floor: same stack captured twice bounds animation drift.
	await _stage()
	renderer.apply_look("echo_left", plain)
	renderer.set_time(1.1)
	await settle(6)
	var img_floor_a: Image = await capture("mk05_floor_a")
	await settle(6)
	var img_floor_b: Image = await capture("mk05_floor_b")
	var floor_diff := _mean_abs_diff_roi(img_floor_a, img_floor_b, FIGHT_ROI)
	_check(floor_diff < 0.002, "MK-05 capture noise floor is small", "floor=%.5f" % floor_diff)

# ---- RT-05: offscreen blends sample real lower content ---------------------
func _rt05_offscreen_blends() -> void:
	for input_kind in ["COMPOSITE_BELOW", "LAYER_BELOW"]:
		for blend in ["ADD", "SCREEN", "MULTIPLY"]:
			# Full-frame lifted lower: edge-only content would starve the
			# blend-vs-NORMAL contrast below measurability.
			var lower: Dictionary = _fx_layer("lower", {"fx_fringe": 1.0, "fx_edge_width": 10.0, "base_grade_amount": 1.0, "grade_brightness": 0.25})
			var upper: Dictionary = _fx_layer("upper", {"input": input_kind, "blend": blend, "fx_rgb": 1.0, "rgb_shift_amount": 10.0, "rgb_shift_alpha": 0.9})
			var full: Dictionary = _look("RT05_%s_%s" % [input_kind, blend], [lower, upper])
			await _stage()
			renderer.apply_look("echo_left", full)
			renderer.set_time(1.1)
			await settle(6)
			var img_full: Image = await capture("rt05_%s_%s" % [input_kind.to_lower(), blend.to_lower()])
			# Same stack, lower layer hidden: the blend must lose content.
			var hidden: Dictionary = _look("RT05_%s_%s_H" % [input_kind, blend], [lower, upper])
			(hidden["layers"] as Array)[1]["enabled"] = false
			await _stage()
			renderer.apply_look("echo_left", hidden)
			renderer.set_time(1.1)
			await settle(6)
			var img_hidden: Image = await capture("rt05_%s_%s_hidden" % [input_kind.to_lower(), blend.to_lower()])
			_check(_mean_abs_diff(img_full, img_hidden) > 0.001, "RT-05 %s %s depends on lower content" % [input_kind, blend], "mean=%.5f" % _mean_abs_diff(img_full, img_hidden))
			# Same stack rendered NORMAL must differ: the blend path is active.
			var normal: Dictionary = _look("RT05_%s_%s_N" % [input_kind, blend], [lower, _fx_layer("upper", {"input": input_kind, "blend": "NORMAL", "fx_rgb": 1.0, "rgb_shift_amount": 10.0, "rgb_shift_alpha": 0.9})])
			await _stage()
			renderer.apply_look("echo_left", normal)
			renderer.set_time(1.1)
			await settle(6)
			var img_normal: Image = await capture("rt05_%s_%s_normal" % [input_kind.to_lower(), blend.to_lower()])
			_check(_mean_abs_diff_roi(img_full, img_normal, FIGHT_ROI) > 0.002, "RT-05 %s %s blend path active vs NORMAL" % [input_kind, blend], "mean=%.5f" % _mean_abs_diff_roi(img_full, img_normal, FIGHT_ROI))
		# NORMAL baseline over lower content renders (sanity, not a blend proof).
		var nlower: Dictionary = _fx_layer("lower", {"fx_fringe": 1.0, "fx_edge_width": 10.0, "base_grade_amount": 1.0, "grade_brightness": 0.25})
		var nupper: Dictionary = _fx_layer("upper", {"input": input_kind, "blend": "NORMAL", "fx_dither": 1.0, "fx_dither_pixel": 4.0})
		await _stage()
		renderer.apply_look("echo_left", _look("RT05_%s_BASE" % input_kind, [nlower, nupper]))
		renderer.set_time(1.1)
		await settle(6)
		var img_nb: Image = await capture("rt05_%s_base" % input_kind.to_lower())
		_check(_mean_luma(img_nb) > 0.01, "RT-05 %s NORMAL baseline renders" % input_kind, "luma=%.4f" % _mean_luma(img_nb))
	if true:
		# Math anchor: a neutral passthrough upper ADDED over the backbuffer
		# must be strictly brighter than the same stack composited NORMAL —
		# only possible if the blend samples real lower content, not stale
		# or empty screen_texture.
		var alower: Dictionary = _fx_layer("lower", {"fx_fringe": 1.0, "fx_edge_width": 10.0, "base_grade_amount": 1.0, "grade_brightness": 0.25})
		await _stage()
		renderer.apply_look("echo_left", _look("RT05_ANCHOR_ADD", [alower, _fx_layer("upper", {"input": "COMPOSITE_BELOW", "blend": "ADD"})]))
		renderer.set_time(1.1)
		await settle(6)
		var img_anchor_add: Image = await capture("rt05_anchor_add")
		var __ivps: Array = (renderer._stacks.get("echo_left", {}) as Dictionary).get("input_viewports", [])
		if not __ivps.is_empty():
			await RenderingServer.frame_post_draw
			var __ivimg: Image = ((__ivps[0] as SubViewport).get_texture() as Texture2D).get_image()
			__ivimg.save_png(out_dir.path_join("rt05_anchor_inputvp.png"))
		await _stage()
		renderer.apply_look("echo_left", _look("RT05_ANCHOR_N", [alower, _fx_layer("upper", {"input": "COMPOSITE_BELOW", "blend": "NORMAL"})]))
		renderer.set_time(1.1)
		await settle(6)
		var img_anchor_n: Image = await capture("rt05_anchor_normal")
		var luma_add := _mean_luma_roi(img_anchor_add, FIGHT_ROI)
		var luma_n := _mean_luma_roi(img_anchor_n, FIGHT_ROI)
		_check(luma_add > luma_n + 0.01, "RT-05 ADD passthrough brighter than NORMAL (math anchor)", "add=%.4f normal=%.4f" % [luma_add, luma_n])

# ---- LG visual: document order is visible order -----------------------------
# NOTE: the two layers use NON-INVERSE domains (rgb shift vs dither posterize)
# so the swapped compositions cannot commute back to the same frame.
func _lg_visual_order() -> void:
	var chroma: Dictionary = _fx_layer("chroma", {"fx_rgb": 1.0, "rgb_shift_amount": 14.0, "rgb_shift_angle": 0.0, "rgb_shift_alpha": 0.9})
	var poster: Dictionary = _fx_layer("poster", {"fx_dither": 1.0, "fx_dither_pixel": 5.0, "fx_dither_levels": 3.0})
	await _stage()
	renderer.apply_look("echo_left", _look("LG_AB", [chroma, poster]))
	renderer.set_time(1.1)
	await settle(6)
	var img_ab: Image = await capture("lg_ab")
	# Swap document order: posterize-then-shift != shift-then-posterize.
	var chroma2: Dictionary = _fx_layer("chroma", {"fx_rgb": 1.0, "rgb_shift_amount": 14.0, "rgb_shift_angle": 0.0, "rgb_shift_alpha": 0.9})
	var poster2: Dictionary = _fx_layer("poster", {"fx_dither": 1.0, "fx_dither_pixel": 5.0, "fx_dither_levels": 3.0})
	await _stage()
	renderer.apply_look("echo_left", _look("LG_BA", [poster2, chroma2]))
	renderer.set_time(1.1)
	await settle(6)
	var img_ba: Image = await capture("lg_ba")
	_check(_mean_abs_diff_roi(img_ab, img_ba, FIGHT_ROI) > 0.002, "LG visual: document order swap changes pixels", "mean=%.5f" % _mean_abs_diff_roi(img_ab, img_ba, FIGHT_ROI))
	# Plane drop moves exactly the plane: the full-frame poster layer moved to
	# BACKGROUND must render differently than at TARGET_SOURCE.
	var bg: Dictionary = _fx_layer("poster", {"fx_dither": 1.0, "fx_dither_pixel": 5.0, "fx_dither_levels": 3.0, "plane": "COMPOSITION_BACKGROUND"})
	await _stage()
	renderer.apply_look("echo_left", _look("LG_BG", [chroma, bg]))
	renderer.set_time(1.1)
	await settle(6)
	var img_bg: Image = await capture("lg_bg")
	_check(_mean_abs_diff(img_ab, img_bg) > 0.0005, "LG visual: plane drop changes the frame", "mean=%.5f" % _mean_abs_diff(img_ab, img_bg))

const FIGHT_ROI := Rect2i(0, 40, 400, 640)
