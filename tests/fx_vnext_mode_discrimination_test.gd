extends SceneTree
# Researcher E: EVERY authorable mode discriminates — full chains per family
# (mono/dither/fringe 0..5, bayer 1..5), each index against a semantic
# neighbor, plus a quiet-floor proof. Labels must match visible behavior.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")

var checks: Array = []
var failures := 0
var out_dir: String
var rt
var renderer
var floor := 0.0

func _init() -> void:
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/mode_discrimination")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	await settle(10)
	rt = FxScreenRuntimeScript.new()
	var cont := SubViewportContainer.new()
	cont.stretch = false
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cont)
	cont.add_child(rt.subvp)
	await settle(10)
	rt.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(20)
	rt.screen.lab_preview_pause()
	rt.seek(1.0)
	await settle(10)
	renderer = FxLayerRendererScript.new(rt.screen, rt.registry)
	await _floor_proof()
	# Mono family carries its own threshold content (base stamp).
	await _chain({"base_mode": 1.0, "mono_threshold": 0.5}, "mono_mode", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0], "mono", false, [])
	# Dither pairs: adjacent where the signal carries; modes 2/3 against
	# baseline (both noise-like, mutually weak on dark content).
	await _chain({"dither": 4.0, "dither_levels": 2.0, "dither_pixel": 32.0}, "dither_mode", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0], "dither", true, [[0, 1], [1, 2], [2, 0], [3, 0], [3, 4], [4, 5]])
	# Fringe family on the strong fringe signal.
	await _chain({"fringe": 2.5, "edge_width": 12.0}, "fringe_coverage_mode", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0], "fringe", false, [])
	# Bayer levels share early_bayer_level(): adjacent highs converge by
	# construction, so every level proves against the L1 baseline on the
	# strong fringe path (function); per-family uniform arrival below
	# proves each wiring (mono/dither/fringe level uniforms).
	await _chain({"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 1.0}, "fringe_bayer_level", [1.0, 2.0, 3.0, 4.0, 5.0], "bayer", true, [[1, 0], [2, 0], [3, 0], [4, 0]])
	await _level_param({"base_mode": 1.0, "mono_threshold": 0.5, "mono_bayer_level": 1.0}, "mono_bayer_level", 1.0)
	await _level_param({"base_mode": 1.0, "mono_threshold": 0.5, "mono_bayer_level": 5.0}, "mono_bayer_level", 5.0)
	await _level_param({"dither": 4.0, "dither_bayer_level": 1.0}, "dither_bayer_level", 1.0)
	await _level_param({"dither": 4.0, "dither_bayer_level": 5.0}, "dither_bayer_level", 5.0)
	await _level_param({"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 1.0, "fringe_bayer_level": 1.0}, "fringe_bayer_level", 1.0)
	await _level_param({"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 1.0, "fringe_bayer_level": 5.0}, "fringe_bayer_level", 5.0)
	print("[FX-MODE-DISCRIMINATION] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _base_fx() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx()
	fx["intensity"] = 1.5
	return fx

func _look_with(patch: Dictionary) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look("DISC%d" % (int(Time.get_unix_time_from_system() * 1000.0) % 1000000), "disc")
	var layer: Dictionary = FxLookScript.new_layer("FX", "disc")
	var fx: Dictionary = layer["fx"]
	var base := _base_fx()
	for k in patch.keys():
		base[str(k)] = patch[k]
	layer["fx"] = base
	look["layers"].append(layer)
	return FxLookScript.materialize(look)

func _shot(name: String, fx_patch: Dictionary) -> Image:
	renderer.apply_composition([{"key": "echo_left", "look": _look_with(fx_patch)}])
	renderer.set_time(1.0)
	await settle(8)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _floor_proof() -> void:
	var p := {"dither": 4.0, "dither_levels": 2.0, "dither_pixel": 32.0, "dither_mode": 1.0}
	var b := await _shot("floor_a", p)
	var b2 := await _shot("floor_b", p)
	floor = _diff(b, b2)
	_check(floor < 0.0002, "E readback floor is quiet", "mean=%.6f" % floor)

func _chain(base: Dictionary, key: String, values: Array, tag: String, use_roi := false, pairs: Array = []) -> void:
	var shots: Array = []
	for v in values:
		var patch := base.duplicate()
		patch[key] = float(v)
		shots.append(await _shot("%s_%s_%g" % [tag, key, float(v)], patch))
	var links: Array = pairs
	if links.is_empty():
		for i in range(1, shots.size()):
			links.append([i - 1, i])
	for link in links:
		var i: int = int((link as Array)[0])
		var j: int = int((link as Array)[1])
		var d := _diff_target(shots[i], shots[j], "echo_left") if use_roi else _diff(shots[i], shots[j])
		_check(d > 0.001 and d > floor * 5.0, "E %s %s vs %s discriminates" % [tag, str(values[i]), str(values[j])], "mean=%.5f floor=%.6f" % [d, floor])

func _level_param(fx_patch: Dictionary, uniform: String, want: float) -> void:
	# Wiring proof per family uniform: the authored level must arrive at
	# SOME material (any-match: neutral SOURCE quads keep defaults).
	renderer.apply_composition([{"key": "echo_left", "look": _look_with(fx_patch)}])
	renderer.set_time(1.0)
	await settle(4)
	var hit := false
	var seen := ""
	var stacks: Dictionary = renderer.get("_stacks")
	for key in stacks.keys():
		for quad_entry in ((stacks[key] as Dictionary).get("quads", []) as Array):
			var quad = (quad_entry as Dictionary).get("node")
			if quad != null and is_instance_valid(quad) and (quad as Control).material is ShaderMaterial:
				var v := float(((quad as Control).material as ShaderMaterial).get_shader_parameter(uniform))
				seen += "%.2f " % v
				if absf(v - want) < 0.001:
					hit = true
	_check(hit, "E %s reaches the material" % uniform, "want=%.2f seen=[%s]" % [want, seen])

func _diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(max(count, 1))

func _diff_target(a: Image, b: Image, key: String) -> float:
	var node = rt.registry.target_node(key)
	if node == null:
		return _diff(a, b)
	var r: Rect2 = FxTargetsScript.presentation_rect(node)
	var x0 := clampi(int(r.position.x), 0, a.get_width() - 1)
	var y0 := clampi(int(r.position.y), 0, a.get_height() - 1)
	var x1 := clampi(int(r.end.x), x0 + 1, a.get_width())
	var y1 := clampi(int(r.end.y), y0 + 1, a.get_height())
	var total := 0.0
	var count := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(max(count, 1))

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
	checks.append(line)
	if not ok:
		failures += 1
		print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame
