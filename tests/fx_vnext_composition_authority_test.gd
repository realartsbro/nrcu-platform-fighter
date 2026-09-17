extends SceneTree
# Phase 3 renderer authority regressions (headless-safe, no readback):
# RT-01 missing effective Look fails the runtime summary;
# RT-02 one invalid target never partially commits (last-known-good kept).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const ScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const VsRuntimeScript := preload("res://scripts/fx_vnext/vs_runtime.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	var prod_dir := "user://vnext_test_composition_authority"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	prod.ensure_dirs()
	_check(bool(prod.apply({"look": _look("GOOD_A")})["ok"]), "RT seed: good look A stored")
	_check(bool(prod.apply({"look": _look("GOOD_B")})["ok"]), "RT seed: good look B stored")
	var asg: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(asg, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "GOOD_A", "")
	FxResolverScript.upsert_binding(asg, {"fighter_id": "doge_man", "element_role": "echo", "visual_side": "right"}, "GOOD_B", "")
	_check(bool(prod.apply({"assignments": asg})["ok"]), "RT seed: assignments stored")

	var runtime = ScreenRuntimeScript.new()
	root.add_child(runtime.subvp)
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "RT seed: runtime mounts")
	await settle(20)
	var renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	# ---- RT-02: full valid composition commits --------------------------------
	var plan_ok := [
		{"key": "echo_left", "look": (prod.load_look("GOOD_A") as Dictionary)["doc"]},
		{"key": "echo_right", "look": (prod.load_look("GOOD_B") as Dictionary)["doc"]},
	]
	var committed: Dictionary = renderer.apply_composition(plan_ok)
	_check(bool(committed.get("ok", false)), "RT-02 valid composition commits", str(committed.get("errors", [])))
	_check(int(committed.get("targets", 0)) == 2, "RT-02 both targets committed")
	var quads_before := _live_quad_count(runtime)

	# ---- RT-02: one invalid target commits NOTHING -----------------------------
	var bad: Dictionary = _look("BAD_BLEND")
	((bad as Dictionary)["layers"] as Array).append(_fx_layer("Bad", "OVERLAY"))
	var plan_mixed := [
		{"key": "echo_left", "look": (prod.load_look("GOOD_A") as Dictionary)["doc"]},
		{"key": "echo_right", "look": bad},
	]
	var mixed: Dictionary = renderer.apply_composition(plan_mixed)
	_check(not bool(mixed.get("ok", false)), "RT-02 mixed composition fails closed")
	_check(bool(mixed.get("rolled_back", false)), "RT-02 failure reports rollback")
	_check(_live_quad_count(runtime) == quads_before, "RT-02 last-known-good frame intact", "before=%d after=%d" % [quads_before, _live_quad_count(runtime)])
	_check(renderer.has_stack("echo_left") and renderer.has_stack("echo_right"), "RT-02 previous stacks retained")
	# Two renderers share one screen in this test: retire the local stacks so
	# the vs_runtime section below places without name collisions.
	renderer.clear_all()

	# ---- RT-01: missing effective Look fails the runtime summary ----------------
	# A look file lost AFTER binding (external deletion/corruption) must fail
	# closed, never render ok=true with a silent hole.
	var vs = VsRuntimeScript.new()
	root.add_child(vs)
	await settle(5)
	vs.production = FxProductionScript.new()
	vs.production.data_dir = prod_dir
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vs.production.look_path("GOOD_B")))
	vs.runtime = runtime
	vs.renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	var summary: Dictionary = vs.reload_production()
	_check((summary.get("missing_looks", []) as Array).has("GOOD_B"), "RT-01 missing look reported", str(summary.get("missing_looks", [])))
	_check(not bool(summary.get("ok", false)), "RT-01 missing look fails summary ok")

	# ---- RT-03: reference runtime proves live animation ------------------------------
	# Re-store GOOD_B (deleted for the RT-01 repro), reload, let frames run:
	# presentation fx_time must advance monotonically with FREE_RUN off.
	_check(bool(prod.apply({"look": _look("GOOD_B")})["ok"]), "RT-03 look restored")
	var live: Dictionary = vs.reload_production()
	_check(bool(live.get("ok", false)), "RT-03 full composition reloads", str(live.get("errors", [])))
	var ft0 := _stack_fx_time(vs, "echo_left")
	_check(ft0 >= 0.0, "RT-03 mounted stack carries clock uniforms")
	await settle(30)
	var ft := _stack_fx_time(vs, "echo_left")
	_check(ft > ft0 + 0.05, "RT-03 presentation clock advances live in reference runtime", "fx_time=%.2f -> %.2f" % [ft0, ft])
	# Acceptance 4+5: pause freezes, resume continues without a jump.
	vs.runtime.screen.lab_preview_pause()
	await settle(10)
	var frozen := _stack_fx_time(vs, "echo_left")
	_check(absf(frozen - ft) < 0.001, "RT-03 pause freezes the presentation clock", "fx_time=%.3f" % frozen)
	vs.runtime.screen.lab_preview_resume()
	await settle(10)
	var resumed := _stack_fx_time(vs, "echo_left")
	_check(resumed > frozen, "RT-03 resume continues the clock", "fx_time=%.2f -> %.2f" % [frozen, resumed])
	# Acceptance 6: seek sets canonical presentation + renderer together.
	vs.seek(1.0)
	await settle(4)
	_check(absf(_stack_fx_time(vs, "echo_left") - 1.0) < 0.12 and absf(vs.runtime.elapsed() - 1.0) < 0.12, "RT-03 seek syncs canonical and renderer clocks")
	# Acceptance 7: FREE_RUN stays independent and opt-in (env unset here).
	_check(_stack_free_time(vs, "echo_left") == 0.0, "RT-03 free clock untouched without opt-in")
	# Acceptance 8: reload keeps the running clock (no rewind to build time).
	var before_reload := _stack_fx_time(vs, "echo_left")
	_check(bool(vs.reload_production().get("ok", false)), "RT-03 reload for clock continuity")
	_check(_stack_fx_time(vs, "echo_left") >= before_reload - 0.01, "RT-03 reload does not rewind the clock")
	# Acceptance 9: a failed fail-closed commit keeps the running clock too.
	var bad_layer: Dictionary = FxLookScript.new_layer("FX", "Bad blend")
	bad_layer["input"] = "ORIGINAL_SOURCE"
	bad_layer["blend_mode"] = "OVERLAY"
	var bad_doc: Dictionary = FxLookScript.new_look("BAD_BLEND", "Bad")
	(bad_doc as Dictionary)["layers"].append(bad_layer)
	var bad_plan := [{"key": "echo_right", "look": bad_doc}]
	var failed: Dictionary = vs.renderer.apply_composition(bad_plan)
	_check(not bool(failed.get("ok", false)), "RT-03 invalid plan fails closed")
	await settle(10)
	_check(_stack_fx_time(vs, "echo_left") >= before_reload - 0.01, "RT-03 failed commit keeps last-known-good clock")

	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	print("[FX-COMPOSITION-AUTHORITY] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _look(look_id: String) -> Dictionary:
	var doc: Dictionary = FxLookScript.new_look(look_id, look_id)
	doc["status"] = "PRODUCTION"
	doc["layers"].append(_fx_layer("Good", "ADD"))
	return doc

func _fx_layer(layer_name: String, blend: String) -> Dictionary:
	var layer: Dictionary = FxLookScript.new_layer("FX", layer_name)
	layer["input"] = "ORIGINAL_SOURCE"
	(layer["fx"] as Dictionary)["rgb"] = 1.0
	layer["blend_mode"] = blend
	return layer

func _live_quad_count(runtime) -> int:
	var root_node: Node = runtime.screen.get_node_or_null("Root")
	if root_node == null:
		return -1
	var count := 0
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != root_node and str(node.name).begins_with("vnext_"):
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count

func _stack_fx_time(vs, key: String) -> float:
	var ft := -1.0
	for quad_entry in vs.renderer.stack_quads(key):
		var quad = (quad_entry as Dictionary).get("node", null)
		if quad is Control and str((quad as Control).name).begins_with("vnext_"):
			var mat = (quad as Control).material
			if mat is ShaderMaterial:
				ft = maxf(ft, float((mat as ShaderMaterial).get_shader_parameter("fx_time")))
	return ft

func _stack_free_time(vs, key: String) -> float:
	var ft := -1.0
	for quad_entry in vs.renderer.stack_quads(key):
		var quad = (quad_entry as Dictionary).get("node", null)
		if quad is Control and str((quad as Control).name).begins_with("vnext_"):
			var mat = (quad as Control).material
			if mat is ShaderMaterial:
				ft = maxf(ft, float((mat as ShaderMaterial).get_shader_parameter("free_time")))
	return ft

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
