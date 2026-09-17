extends SceneTree
# vNext composition test (Round-2 Finding 1) — the composition renderer must
# produce ONE canonical global order regardless of plan/call order, and must
# composite background/foreground layers from multiple targets together.
# Windowed: needs rendering.

var checks: Array = []
var failures: int = 0
var out_dir: String
var runtime
var renderer

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/composition")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
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
	renderer.set_time(1.5)

	# ---- looks for two targets ---------------------------------------------------
	var echo_look: Dictionary = FxLookScript.new_look("C_ECHO", "Echo")
	var echo_bg: Dictionary = FxLookScript.new_layer("FX", "Echo BG dither")
	echo_bg["plane"] = "COMPOSITION_BACKGROUND"
	echo_bg["fx"] = {"dither": 1.0, "intensity": 1.4, "dither_levels": 3.0, "dither_pixel": 4.0}
	echo_look["layers"].append(echo_bg)
	var echo_fx: Dictionary = FxLookScript.new_layer("FX", "Echo rgb")
	echo_fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 16.0}
	echo_look["layers"].append(echo_fx)

	var mark_look: Dictionary = FxLookScript.new_look("C_MARK", "Mark")
	var mark_fx: Dictionary = FxLookScript.new_layer("FX", "Mark fringe")
	mark_fx["fx"] = {"fringe": 1.0, "intensity": 1.3, "edge_width": 10.0, "wind_reach": 32.0, "wind_trail": 0.8}
	mark_look["layers"].append(mark_fx)
	var mark_fg: Dictionary = FxLookScript.new_layer("FX", "Mark FG rgb")
	mark_fg["plane"] = "COMPOSITION_FOREGROUND"
	mark_fg["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 12.0}
	mark_look["layers"].append(mark_fg)

	# ---- baseline: no styles -----------------------------------------------------
	var empty_img: Image = await capture("composition_none")

	# ---- both targets, order A ---------------------------------------------------
	var applied: Dictionary = renderer.apply_composition([
		{"key": "echo_left", "look": echo_look},
		{"key": "mark", "look": mark_look},
	])
	_check(bool(applied["ok"]), "composition applies two targets", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(8)
	var order_a: Image = await capture("composition_order_a")

	# ---- both targets, order B (reversed plan) -----------------------------------
	applied = renderer.apply_composition([
		{"key": "mark", "look": mark_look},
		{"key": "echo_left", "look": echo_look},
	])
	_check(bool(applied["ok"]), "composition applies reversed plan", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(8)
	var order_b: Image = await capture("composition_order_b")
	_check(order_a.get_data() == order_b.get_data(), "apply order does not change the output (byte-identical)")

	# ---- styled vs unstyled --------------------------------------------------------
	var both_delta := _mean_abs_diff(empty_img, order_a)
	_check(both_delta > 0.004, "composition renders both targets", "mean=%.5f" % both_delta)

	# echo only
	renderer.apply_composition([{"key": "echo_left", "look": echo_look}])
	renderer.set_time(1.5)
	await settle(8)
	var echo_only: Image = await capture("composition_echo_only")
	# mark only
	renderer.apply_composition([{"key": "mark", "look": mark_look}])
	renderer.set_time(1.5)
	await settle(8)
	var mark_only: Image = await capture("composition_mark_only")
	_check(_mean_abs_diff(echo_only, mark_only) > 0.004, "targets render differently", "mean=%.5f" % _mean_abs_diff(echo_only, mark_only))

	# ---- background layers from two targets together -------------------------------
	var bg_delta := _mean_abs_diff(echo_only, order_a)
	_check(bg_delta > 0.002, "second target contributes (its background + mark fx)", "mean=%.5f" % bg_delta)
	# mark background specifically: give mark its own background and compare
	var mark_bg_look: Dictionary = mark_look.duplicate(true)
	var mark_bg: Dictionary = FxLookScript.new_layer("FX", "Mark BG dither")
	mark_bg["plane"] = "COMPOSITION_BACKGROUND"
	mark_bg["fx"] = {"dither": 1.0, "intensity": 1.3, "dither_levels": 3.0, "dither_pixel": 4.0}
	(mark_bg_look["layers"] as Array).insert(0, mark_bg)
	renderer.apply_composition([
		{"key": "echo_left", "look": echo_look},
		{"key": "mark", "look": mark_bg_look},
	])
	renderer.set_time(1.5)
	await settle(8)
	var two_bg: Image = await capture("composition_two_backgrounds")
	# Position-true proof: the added mark-background must change pixels exactly in
	# the mark presentation rect (534,222)-(745,446) and nowhere else.
	var mark_region_mean := _region_abs_diff(order_a, two_bg, Rect2i(534, 222, 211, 224))
	var outside_mean := _outside_region_abs_diff(order_a, two_bg, Rect2i(534, 222, 211, 224))
	_check(mark_region_mean > 0.0002, "second target background composites in its own rect", "region=%.5f" % mark_region_mean)
	_check(outside_mean < 0.0001, "second target background leaks nowhere else", "outside=%.5f" % outside_mean)

	# ---- cleanup -------------------------------------------------------------------
	renderer.clear_all()
	await settle(6)
	var cleared: Image = await capture("composition_cleared")
	_check(_mean_abs_diff(empty_img, cleared) < 0.002, "clear restores the canonical composition", "mean=%.5f" % _mean_abs_diff(empty_img, cleared))

	var f := FileAccess.open(out_dir.path_join("summary_composition_check.json"), FileAccess.WRITE)
	var summary := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("[COMPOSITION] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _region_abs_diff(a: Image, b: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y, 2):
		for x in range(rect.position.x, rect.position.x + rect.size.x, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(max(count, 1))

func _outside_region_abs_diff(a: Image, b: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			if rect.has_point(Vector2i(x, y)):
				continue
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(max(count, 1))

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(max(count, 1))
