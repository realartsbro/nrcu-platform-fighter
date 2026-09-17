extends SceneTree
# Researcher E: enum indices must visibly discriminate — each authorable mode
# renders observably different output (no dead options, no hidden capability).
# Direct ScreenRuntime + shared renderer (no shell), paused deterministic
# screen, window capture (the proven readback path).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")

var checks: Array = []
var failures := 0
var out_dir: String
var rt
var renderer

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
	await _family_mono()
	await _family_dither()
	await _family_fringe()
	await _family_bayer()
	print("[FX-MODE-DISCRIMINATION] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _base_fx() -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx()
	fx["intensity"] = 1.5
	return fx

func _look_with(patch: Dictionary) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look("DISC_%d" % int(Time.get_unix_time_from_system() * 1000.0) % 100000, "disc")
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

func _family_mono() -> void:
	# base_mode=1 (MONO STAMP) isolates mono; other families stay neutral.
	var p0 := {"base_mode": 1.0, "mono_threshold": 0.5, "mono_mode": 0.0}
	var p1 := {"base_mode": 1.0, "mono_threshold": 0.5, "mono_mode": 1.0}
	var p5 := {"base_mode": 1.0, "mono_threshold": 0.5, "mono_mode": 5.0}
	var a := await _shot("mono_hard", p0)
	var b := await _shot("mono_bayer", p1)
	var c := await _shot("mono_invhalf", p5)
	_check(_diff(a, b) > 0.001, "E mono HARD vs BAYER discriminates", "mean=%.5f" % _diff(a, b))
	_check(_diff(b, c) > 0.001, "E mono BAYER vs mode-5 discriminates", "mean=%.5f" % _diff(b, c))

func _family_dither() -> void:
	# Coarse 32px blocks: HARD quantizes uniformly while BAYER offsets each
	# block coherently — block tones must differ visibly.
	var p0 := {"dither": 4.0, "dither_levels": 2.0, "dither_pixel": 32.0, "dither_mode": 0.0}
	var p1 := {"dither": 4.0, "dither_levels": 2.0, "dither_pixel": 32.0, "dither_mode": 1.0}
	var a := await _shot("dither_hard", p0)
	var b := await _shot("dither_bayer", p1)
	var b2 := await _shot("dither_bayer_again", p1)
	var floor := _diff(b, b2)
	_check(floor < 0.0002, "E readback floor is quiet", "mean=%.6f" % floor)
	# Researcher-sanctioned ROI: the styled target's own rect (global means
	# dilute localized FX on dark content; the target ROI does not).
	var roi := _diff_target(a, b, "echo_left")
	_check(roi > 0.001 and roi > floor * 5.0, "E dither HARD vs BAYER discriminates on target", "roi=%.5f floor=%.6f" % [roi, floor])

func _family_fringe() -> void:
	var p0 := {"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 0.0}
	var p4 := {"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 4.0}
	var a := await _shot("fringe_smooth", p0)
	var b := await _shot("fringe_checker", p4)
	_check(_diff(a, b) > 0.001, "E fringe SMOOTH vs CHECKER discriminates", "mean=%.5f" % _diff(a, b))

func _family_bayer() -> void:
	# Levels share early_bayer_level() across mono/dither/fringe. The dither
	# path sits on dark content (few quantization borderlines), so the level
	# proof rides the strong fringe signal: BAYER coverage with level 1 vs 5.
	var p1 := {"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 1.0, "fringe_bayer_level": 1.0}
	var p5 := {"fringe": 2.5, "edge_width": 12.0, "fringe_coverage_mode": 1.0, "fringe_bayer_level": 5.0}
	var a := await _shot("bayer_l1", p1)
	var b := await _shot("bayer_l5", p5)
	_check(_diff(a, b) > 0.001, "E bayer level 1 vs 5 discriminates", "mean=%.5f" % _diff(a, b))

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
