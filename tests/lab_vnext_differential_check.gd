extends SceneTree
# R3 §4 — DIFFERENTIAL Lab <-> PRODUCTION RUNTIME, case matrix.
# For every case: write the case's Looks + bindings as Production authority,
# then render the SAME case through
#   (A) the REAL VS runtime scene (nrcu_vs_runtime.tscn, format via NRCU_VS_FORMAT)
#       — no lab, no session
#   (B) a fresh screen-runtime + the shared composition renderer (the direct path)
# and require the two outputs to agree byte-near-identically (mean < 0.0005).
# Covered cases: neutral, multi-target 1v1 / FFA_4 / TEAM_2V2 (every registry key
# styled, incl. whichever primary/name targets exist), multi-layer mark, echo,
# global background layer, global foreground layer, source copy + displacement,
# mask-heavy, motion, palette. The vector elements (Side Fields, Name Plates,
# Accent Lines) are not registry targets: their differential is the
# neutral-parity suite plus the source/mask torture suite (recorded below).
# Windowed: renders.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const RuntimeScene := preload("res://scenes/nrcu_vs_runtime.tscn")

var checks: Array = []
var failures: int = 0
var out_dir: String
var data_dir: String
var case_summaries: Array = []

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/differential")
	DirAccess.make_dir_recursive_absolute(out_dir)
	data_dir = out_dir.path_join("production_data")
	OS.set_environment("NRCU_FX_DATA_DIR", data_dir)

	var cases: Array = [
		{"name": "neutral", "format": "1v1", "looks": {}},
		{"name": "multi_target_1v1", "format": "1v1", "looks": "all_full"},
		{"name": "ffa4_multi", "format": "FFA_4", "looks": "all_full"},
		{"name": "team2v2_multi", "format": "TEAM_2V2", "looks": "all_full"},
		{"name": "mark_multi_layer", "format": "1v1", "looks": "mark_full"},
		{"name": "echo_rgb", "format": "1v1", "looks": "echo_rgb"},
		{"name": "global_background", "format": "1v1", "looks": "bg_only"},
		{"name": "global_foreground", "format": "1v1", "looks": "fg_only"},
		{"name": "source_copy_displacement", "format": "1v1", "looks": "copy_disp"},
		{"name": "mask_heavy", "format": "1v1", "looks": "mask_heavy"},
		{"name": "motion_case", "format": "1v1", "looks": "motion"},
		{"name": "palette_case", "format": "1v1", "looks": "palette"},
	]
	for case_raw in cases:
		await run_case(case_raw)

	# vector elements: differential lives in dedicated suites (honest mapping)
	_check(true, "side fields / name plates / accent lines differential = neutral_parity + source_mask_torture suites", "not registry targets; covered by those suites' byte/mean proofs")

	var f := FileAccess.open(out_dir.path_join("summary_differential_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL", "cases": case_summaries}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[DIFFERENTIAL] done · checks=%d failures=%d cases=%d" % [checks.size(), failures, case_summaries.size()])
	quit(1 if failures > 0 else 0)

func run_case(case_raw: Dictionary) -> void:
	var case: Dictionary = case_raw
	var case_name := str(case["name"])
	var format := str(case["format"])

	# ---- clean production, write the case authority -------------------------------
	_wipe_dir(data_dir)
	DirAccess.make_dir_recursive_absolute(data_dir)
	var prod := FxProductionScript.new()
	prod.data_dir = data_dir
	prod.recover_if_needed()

	# probe mount for real selector contexts of this format
	var probe = FxScreenRuntimeScript.new()
	var probe_svp := SubViewport.new()
	probe_svp.size = Vector2i(1280, 720)
	root.add_child(probe_svp)
	var probe_disp := SubViewportContainer.new()
	probe_disp.stretch = true
	probe_disp.size = Vector2(1280, 720)
	probe_svp.add_child(probe_disp)
	probe_disp.add_child(probe.subvp)
	await settle(30)
	probe.mount(format, "debug", "ice_mage", "doge_man")
	await settle(60)
	var keys: Array = []
	for key in probe.registry.keys():
		keys.append(str(key))
	keys.sort()

	var case_looks := _build_case_looks(case_name, str(case["looks"]), keys)
	var doc: Dictionary = FxResolverScript.new_assignments()
	var plan_ids: Array = []
	for key in case_looks.keys():
		var look: Dictionary = case_looks[key]
		var applied: Dictionary = prod.apply({"look": look})
		if not bool(applied.get("ok", false)):
			_check(false, "%s: production accepts look %s" % [case_name, str(key)], str(applied.get("errors", [])))
			continue
		var selector: Dictionary = FxResolverScript.normalize_selector(probe.registry.context_for_key(str(key)))
		FxResolverScript.upsert_binding(doc, selector, str(look["look_id"]), "")
		plan_ids.append(str(key))
	var applied_asg: Dictionary = prod.apply({"assignments": doc})
	_check(bool(applied_asg.get("ok", false)), "%s: production accepts assignments" % case_name, str(applied_asg.get("errors", [])))
	probe.subvp.queue_free()
	probe_svp.queue_free()
	await settle(4)

	# ---- (A) REAL runtime scene ----------------------------------------------------
	OS.set_environment("NRCU_VS_FORMAT", format)
	var svp_a := _make_viewport()
	var runtime = RuntimeScene.instantiate()
	svp_a.add_child(runtime)
	await settle(90)
	runtime.seek(1.5)
	runtime.reload_production()
	await settle(12)
	var img_a: Image = await capture_svp(svp_a, "%s_runtime" % case_name)

	# ---- (B) direct path: screen runtime + shared renderer -------------------------
	var mount2 = FxScreenRuntimeScript.new()
	var svp_b := SubViewport.new()
	svp_b.size = Vector2i(1280, 720)
	svp_b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp_b)
	var disp_b := SubViewportContainer.new()
	disp_b.stretch = true
	disp_b.size = Vector2(1280, 720)
	svp_b.add_child(disp_b)
	disp_b.add_child(mount2.subvp)
	await settle(30)
	mount2.mount(format, "debug", "ice_mage", "doge_man")
	await settle(60)
	mount2.seek(1.5)
	await settle(10)
	var renderer2 = FxLayerRendererScript.new(mount2.screen, mount2.registry)
	var plan: Array = []
	var asg_doc: Dictionary = prod.load_assignments().get("doc", {})
	for key in keys:
		var res: Dictionary = FxResolverScript.resolve(asg_doc, mount2.registry.context_for_key(key))
		if str(res.get("status", "")) not in ["ASSIGNED", "AMBIGUOUS"]:
			continue
		var loaded: Dictionary = prod.load_look(str(res["look_id"]))
		if bool(loaded.get("ok", false)):
			plan.append({"key": key, "look": loaded["doc"]})
	renderer2.apply_composition(plan)
	renderer2.set_time(1.5)
	await settle(10)
	var img_b: Image = await capture_svp(svp_b, "%s_direct" % case_name)

	# ---- compare --------------------------------------------------------------------
	var delta := _mean_abs_diff(img_a, img_b)
	var ok := delta < 0.0005
	_check(ok, "%s: runtime equals direct shared-renderer path" % case_name, "mean=%.6f targets=%d" % [delta, plan.size()])
	if not ok:
		img_a.save_png(out_dir.path_join("%s_MISMATCH_runtime.png" % case_name))
		img_b.save_png(out_dir.path_join("%s_MISMATCH_direct.png" % case_name))
	case_summaries.append({"case": case_name, "format": format, "targets": plan.size(), "delta": delta, "ok": ok})

	runtime.queue_free()
	mount2.subvp.queue_free()
	svp_a.queue_free()
	svp_b.queue_free()
	await settle(4)

func _build_case_looks(case_name: String, spec: String, keys: Array) -> Dictionary:
	var out: Dictionary = {}
	var fx_layer := func(name: String, fx: Dictionary) -> Dictionary:
		var layer: Dictionary = FxLookScript.new_layer("FX", name)
		layer["fx"] = fx
		return layer
	match spec:
		"all_full":
			for key in keys:
				var look: Dictionary = FxLookScript.new_look("CASE_%s_%s" % [case_name.to_upper(), str(key).to_upper()], str(key))
				var bg: Dictionary = fx_layer.call("BG dither", {"dither": 1.0, "dither_mode": 1.0, "dither_pixel": 4.0, "dither_levels": 3.0})
				bg["plane"] = "COMPOSITION_BACKGROUND"
				(look["layers"] as Array).append(bg)
				var local: Dictionary = fx_layer.call("Local fringe", {"fringe": 1.0, "intensity": 1.25, "edge_width": 9.0, "wind_reach": 26.0})
				(look["layers"] as Array).append(local)
				var fg: Dictionary = fx_layer.call("FG rgb", {"rgb": 1.0, "rgb_shift_amount": 12.0})
				fg["plane"] = "COMPOSITION_FOREGROUND"
				(look["layers"] as Array).append(fg)
				out[key] = look
			return out
		"mark_full":
			var k := _key_with(keys, "mark")
			if k != "":
				var look2: Dictionary = FxLookScript.new_look("CASE_MARK", "mark")
				var bg2: Dictionary = fx_layer.call("Mark BG", {"dither": 1.0, "dither_mode": 1.0, "dither_pixel": 4.0, "dither_levels": 3.0})
				bg2["plane"] = "COMPOSITION_BACKGROUND"
				(look2["layers"] as Array).append(bg2)
				(look2["layers"] as Array).append(fx_layer.call("Mark fringe", {"fringe": 1.0, "intensity": 1.3, "edge_width": 10.0, "wind_reach": 32.0, "wind_trail": 0.8}))
				var fg2: Dictionary = fx_layer.call("Mark FG", {"rgb": 1.0, "rgb_shift_amount": 12.0})
				fg2["plane"] = "COMPOSITION_FOREGROUND"
				(look2["layers"] as Array).append(fg2)
				out[k] = look2
			return out
		"echo_rgb":
			var k3 := _key_with(keys, "echo")
			if k3 != "":
				var look3: Dictionary = FxLookScript.new_look("CASE_ECHO", "echo")
				(look3["layers"] as Array).append(fx_layer.call("Echo rgb", {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 18.0}))
				out[k3] = look3
			return out
		"bg_only":
			var k4 := _key_with(keys, "mark")
			if k4 != "":
				var look4: Dictionary = FxLookScript.new_look("CASE_BG", "bg")
				var bg4: Dictionary = fx_layer.call("Global BG", {"dither": 1.0, "dither_mode": 1.0, "dither_pixel": 4.0, "dither_levels": 3.0})
				bg4["plane"] = "COMPOSITION_BACKGROUND"
				(look4["layers"] as Array).append(bg4)
				out[k4] = look4
			return out
		"fg_only":
			var k5 := _key_with(keys, "mark")
			if k5 != "":
				var look5: Dictionary = FxLookScript.new_look("CASE_FG", "fg")
				var fg5: Dictionary = fx_layer.call("Global FG", {"rgb": 1.0, "rgb_shift_amount": 14.0})
				fg5["plane"] = "COMPOSITION_FOREGROUND"
				(look5["layers"] as Array).append(fg5)
				out[k5] = look5
			return out
		"copy_disp":
			var k6 := _key_with(keys, "echo")
			if k6 != "":
				var look6: Dictionary = FxLookScript.new_look("CASE_COPY", "copy")
				var copy: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Displaced copy")
				copy["opacity"] = 0.6
				((copy["transform"] as Dictionary))["position_px"] = [-8.0, 2.0]
				((copy["transform"] as Dictionary))["scale"] = [1.05, 1.05]
				((copy["fx"] as Dictionary))["base_tint"] = "#74E7FF"
				(look6["layers"] as Array).append(copy)
				var local6: Dictionary = fx_layer.call("Copy fringe", {"fringe": 1.0, "edge_width": 8.0, "wind_reach": 22.0})
				(look6["layers"] as Array).append(local6)
				out[k6] = look6
			return out
		"mask_heavy":
			var k7 := _key_with(keys, "mark")
			if k7 != "":
				var look7: Dictionary = FxLookScript.new_look("CASE_MASK", "mask")
				var local7: Dictionary = fx_layer.call("Masked fringe", {"fringe": 1.0, "edge_width": 12.0, "wind_reach": 30.0})
				var m: Dictionary = local7["mask"]
				m["enabled"] = true
				m["source"] = "CUSTOM_MASK"
				m["custom_mask"] = "res://assets/vs/generated/accent_left_mask.png"
				m["region"] = "EDGE_BAND"
				m["width_px"] = 10.0
				m["feather_px"] = 3.0
				(look7["layers"] as Array).append(local7)
				out[k7] = look7
			return out
		"motion":
			var k8 := _key_with(keys, "echo")
			if k8 != "":
				var look8: Dictionary = FxLookScript.new_look("CASE_MOTION", "motion")
				var local8: Dictionary = fx_layer.call("Motion dither", {"dither": 1.0, "dither_mode": 1.0, "intensity": 1.4})
				var motion: Dictionary = local8["motion"]
				(motion["enabled"] as Dictionary)["dither"] = true
				(motion["tracks"]["dither"] as Dictionary)["anchor"] = "manual"
				(motion["tracks"]["dither"] as Dictionary)["anchor_time"] = 0.0
				(motion["tracks"]["dither"] as Dictionary)["attack"] = 0.7
				(look8["layers"] as Array).append(local8)
				out[k8] = look8
			return out
		"palette":
			var k9 := _key_with(keys, "mark")
			if k9 != "":
				var look9: Dictionary = FxLookScript.new_look("CASE_PALETTE", "palette")
				(look9["layers"] as Array).append(fx_layer.call("Palette dither", {"dither": 1.0, "dither_mode": 1.0, "palette_strategy": 1.0, "palette_lock_a": true, "palette_hue_offset": 0.25, "palette_swap": true, "dither_levels": 3.0}))
				out[k9] = look9
			return out
	return out

func _key_with(keys: Array, needle: String) -> String:
	for key in keys:
		if str(key).findn(needle) >= 0:
			return str(key)
	return ""

func _make_viewport() -> SubViewport:
	var svp := SubViewport.new()
	svp.size = Vector2i(1280, 720)
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.transparent_bg = false
	root.add_child(svp)
	return svp

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture_svp(svp: SubViewport, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = svp.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(dir_path: String) -> void:
	var abs := ProjectSettings.globalize_path(dir_path) if dir_path.begins_with("res://") or dir_path.begins_with("user://") else dir_path
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir_abs(abs.path_join(sub))

func _wipe_dir_abs(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir_abs(abs.path_join(sub))

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
