extends SceneTree
# vNext ACTUAL VS runtime check (Round-2 Finding 1, Pflichtbeweis):
# A Production look is written to disk; a FRESH instance of the real runtime
# scene (res://scenes/nrcu_vs_runtime.tscn — no Lab, no session, no editor
# state) loads it, resolves every target through the shared resolver and
# renders through the shared composition renderer.
# Windowed: needs rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")
const RuntimeScene := preload("res://scenes/nrcu_vs_runtime.tscn")

var checks: Array = []
var failures: int = 0
var out_dir: String
var data_dir: String

func _init() -> void:
	root.size = Vector2i(1280, 720)
	await settle(10)
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/runtime")
	DirAccess.make_dir_recursive_absolute(out_dir)
	data_dir = out_dir.path_join("production_data")
	_wipe_dir(data_dir)
	DirAccess.make_dir_recursive_absolute(data_dir)
	OS.set_environment("NRCU_FX_DATA_DIR", data_dir)

	# ---- 1. runtime WITHOUT production ------------------------------------------
	var runtime1 = RuntimeScene.instantiate()
	root.add_child(runtime1)
	await settle(90)
	_pause_and_seek(runtime1, 0.3)
	await settle(10)
	var baseline: Image = await capture_root("runtime_no_production")
	_check(runtime1.renderer != null and runtime1.renderer.get("_stacks") != null, "runtime scene boots with the shared renderer")
	var keys: Array = runtime1.runtime.registry.keys()
	_check(keys.size() > 0, "runtime mounts the canonical VS composition", "keys=%d" % keys.size())
	runtime1.queue_free()
	await settle(6)

	# ---- 2. write Production authority to disk -----------------------------------
	var prod := FxProductionScript.new()
	prod.data_dir = data_dir
	var echo_look: Dictionary = FxLookScript.new_look("ICE_MAGE_ECHO_LEFT", "Ice Echo", "PRODUCTION");
	echo_look["layers"].append(_fx_layer("Echo rgb", {"rgb": 2.5, "intensity": 1.5, "rgb_shift_amount": 40.0}))
	var mark_look: Dictionary = FxLookScript.new_look("DOGE_MAN_MARK", "Doge Mark", "PRODUCTION");
	mark_look["layers"].append(_fx_layer("Mark fringe", {"fringe": 2.5, "intensity": 1.6, "edge_width": 20.0, "wind_reach": 40.0, "wind_trail": 0.8}))
	var applied: Dictionary = prod.apply({"look": echo_look})
	_check(bool(applied["ok"]), "production accepts echo look", str(applied.get("errors", [])))
	applied = prod.apply({"look": mark_look})
	_check(bool(applied["ok"]), "production accepts mark look", str(applied.get("errors", [])))

	# selectors from the real mounted context of a probe mount
	var probe = FxScreenRuntimeScript.new()
	root.add_child(probe.subvp)
	await settle(30)
	probe.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(30)
	var doc: Dictionary = FxResolverScript.new_assignments()
	var sel_echo := FxResolverScript.normalize_selector(probe.registry.context_for_key("echo_left"))
	var sel_mark := FxResolverScript.normalize_selector(probe.registry.context_for_key("mark"))
	FxResolverScript.upsert_binding(doc, sel_echo, "ICE_MAGE_ECHO_LEFT", "")
	FxResolverScript.upsert_binding(doc, sel_mark, "DOGE_MAN_MARK", "")
	applied = prod.apply({"assignments": doc})
	_check(bool(applied["ok"]), "production accepts assignments", str(applied.get("errors", [])))
	probe.subvp.queue_free()
	await settle(6)

	# ---- 3. FRESH runtime instance: production look must appear ------------------
	var runtime2 = RuntimeScene.instantiate()
	root.add_child(runtime2)
	await settle(90)
	_pause_and_seek(runtime2, 0.3)
	runtime2.reload_production()
	await settle(10)
	var styled: Image = await capture_root("runtime_with_production")
	var styled_again: Image = await capture_root("runtime_with_production_later")
	_check(_mean_abs_diff(styled, styled_again) < 0.0005, "runtime frame is frozen and deterministic", "mean=%.6f" % _mean_abs_diff(styled, styled_again))
	var summary: Dictionary = runtime2.last_summary
	_check(int(summary.get("styled_targets", -1)) == 2, "runtime resolves both production looks", str(summary))
	var delta := _mean_abs_diff(baseline, styled)
	var roi_delta := _mean_abs_diff_targets(baseline, styled, runtime2, ["echo_left", "mark"])
	_check(roi_delta > 0.004, "stored production looks appear in the actual VS runtime", "mean=%.5f roi=%.5f" % [delta, roi_delta])

	# ---- 4. same semantics as the shared composition renderer --------------------
	var mount2 = FxScreenRuntimeScript.new()
	root.add_child(mount2.subvp)
	await settle(30)
	mount2.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(60)
	mount2.screen.lab_preview_pause()
	mount2.seek(0.3)
	await settle(10)
	var renderer2 = FxLayerRendererScript.new(mount2.screen, mount2.registry)
	renderer2.set_event_marks(mount2.event_marks())
	var plan: Array = []
	var direct_ids: Array = []
	var asg_doc: Dictionary = prod.load_assignments()["doc"]
	for key in mount2.registry.keys():
		var key_str := str(key)
		var res: Dictionary = FxResolverScript.resolve(asg_doc, mount2.registry.context_for_key(key_str))
		if str(res.get("status", "")) not in ["ASSIGNED", "AMBIGUOUS"]:
			continue
		var loaded: Dictionary = prod.load_look(str(res["look_id"]))
		if bool(loaded.get("ok", false)):
			plan.append({"key": key_str, "look": loaded["doc"]})
			direct_ids.append("%s:%s:r%d" % [key_str, str(res["look_id"]), int((loaded["doc"] as Dictionary).get("revision", 0))])
	print("[RUNTIME] runtime plan: %s" % str(runtime2.last_summary.get("plan_ids", [])))
	print("[RUNTIME] direct plan:  %s" % str(direct_ids))
	_check(str(runtime2.last_summary.get("plan_ids", [])) == str(direct_ids), "both paths resolve the same plan", "")
	renderer2.apply_composition(plan)
	renderer2.set_time(0.3)
	await settle(10)
	# Styled looks carry no motion tracks here: freeze both paths at the same
	# clock so the comparison is composition, not transport.
	runtime2.seek(0.3)
	await settle(10)
	var direct: Image = await capture_root("runtime_direct_composition")
	var direct_again: Image = await capture_root("runtime_direct_later")
	_check(_mean_abs_diff(direct, direct_again) < 0.0005, "shared renderer frame is frozen and deterministic", "mean=%.6f" % _mean_abs_diff(direct, direct_again))
	var pair_delta := _mean_abs_diff(styled, direct)
	_check(pair_delta < 0.0005, "runtime output equals the shared composition renderer", "mean=%.6f" % pair_delta)

	runtime2.queue_free()
	mount2.subvp.queue_free()
	await settle(6)

	var f := FileAccess.open(out_dir.path_join("summary_runtime_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL", "styled_targets": int(summary.get("styled_targets", -1)), "styled_delta": delta, "pair_delta": pair_delta}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[RUNTIME] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _fx_layer(name: String, fx: Dictionary) -> Dictionary:
	var layer: Dictionary = FxLookScript.new_layer("FX", name)
	layer["fx"] = fx
	return layer

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture_root(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _pause_and_seek(rt, t: float) -> void:
	if rt.runtime.screen != null and rt.runtime.screen.has_method("lab_preview_pause"):
		rt.runtime.screen.lab_preview_pause()
	rt.seek(t)

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

func _mean_abs_diff_targets(a: Image, b: Image, rt, keys: Array) -> float:
	# Styled-target union ROI: full-frame means dilute localized FX with
	# identical background; the bar stays 0.004, the measured area changes.
	var union := Rect2()
	var first := true
	for key in keys:
		var node = rt.runtime.registry.target_node(str(key))
		if node == null:
			continue
		var r: Rect2 = FxTargetsScript.presentation_rect(node)
		if first:
			union = r
			first = false
		else:
			union = union.merge(r)
	if first:
		return _mean_abs_diff(a, b)
	var x0 := clampi(int(union.position.x), 0, a.get_width() - 1)
	var y0 := clampi(int(union.position.y), 0, a.get_height() - 1)
	var x1 := clampi(int(union.end.x), x0 + 1, a.get_width())
	var y1 := clampi(int(union.end.y), y0 + 1, a.get_height())
	var total := 0.0
	var count := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
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
