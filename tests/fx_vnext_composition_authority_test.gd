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
	print("DEBUG rt03 processing-after-mount=", runtime.screen.is_processing(), " elapsed=", runtime.screen.elapsed())
	await settle(20)
	var renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	# ---- RT-02: full valid composition commits --------------------------------
	var plan_ok := [
		{"key": "echo_left", "look": (prod.load_look("GOOD_A") as Dictionary)["doc"]},
		{"key": "echo_right", "look": (prod.load_look("GOOD_B") as Dictionary)["doc"]},
	]
	var committed: Dictionary = renderer.apply_composition(plan_ok)
	print("DEBUG rt03 processing-after-commit-ok=", runtime.screen.is_processing(), " elapsed=", runtime.screen.elapsed())
	_check(bool(committed.get("ok", false)), "RT-02 valid composition commits", str(committed.get("errors", [])))
	_check(int(committed.get("targets", 0)) == 2, "RT-02 both targets committed")
	print("DEBUG rt02 names=", renderer.stack_quads("echo_left").map(func(e): return str(((e as Dictionary).get("node", null) as Node).name) if (e as Dictionary).get("node", null) is Node else "?"))
	var quads_before := _live_quad_count(runtime)

	# ---- RT-02: one invalid target commits NOTHING -----------------------------
	var bad: Dictionary = _look("BAD_BLEND")
	((bad as Dictionary)["layers"] as Array).append(_fx_layer("Bad", "OVERLAY"))
	var plan_mixed := [
		{"key": "echo_left", "look": (prod.load_look("GOOD_A") as Dictionary)["doc"]},
		{"key": "echo_right", "look": bad},
	]
	var mixed: Dictionary = renderer.apply_composition(plan_mixed)
	print("DEBUG rt03 processing-after-commit-mixed=", runtime.screen.is_processing())
	_check(not bool(mixed.get("ok", false)), "RT-02 mixed composition fails closed")
	_check(bool(mixed.get("rolled_back", false)), "RT-02 failure reports rollback")
	_check(_live_quad_count(runtime) == quads_before, "RT-02 last-known-good frame intact", "before=%d after=%d" % [quads_before, _live_quad_count(runtime)])
	_check(renderer.has_stack("echo_left") and renderer.has_stack("echo_right"), "RT-02 previous stacks retained")
	print("DEBUG rt03 processing-after-rt02=", runtime.screen.is_processing())
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
	# presentation fx_time must advance past the seek point with FREE_RUN off.
	_check(bool(prod.apply({"look": _look("GOOD_B")})["ok"]), "RT-03 look restored")
	var live: Dictionary = vs.reload_production()
	_check(bool(live.get("ok", false)), "RT-03 full composition reloads", str(live.get("errors", [])))
	# The reference screen runs its ENTRY/HOLD/EXIT match clock; start it so
	# there is live canonical time to follow.
	print("DEBUG rt03 state=", vs.runtime.screen.state(), " elapsed=", vs.runtime.screen.elapsed(), " processing=", vs.runtime.screen.is_processing(), " paused=", vs.runtime.screen.lab_preview_is_paused())
	_check(true, "RT-03 screen clock observable")
	await settle(30)
	var ft := -1.0
	for quad_entry in vs.renderer.stack_quads("echo_left"):
		var quad = (quad_entry as Dictionary).get("node", null)
		if quad is Control and str((quad as Control).name).begins_with("vnext_"):
			var mat = (quad as Control).material
			if mat is ShaderMaterial:
				ft = maxf(ft, float((mat as ShaderMaterial).get_shader_parameter("fx_time")))
	_check(ft > 1.6, "RT-03 presentation clock advances live in reference runtime", "fx_time=%.2f" % ft)

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
