extends SceneTree
# Gold production roundtrip gate. This is the evidence authority for the
# persistence_proven/runtime_observable registry claims: canonical authoring,
# Production JSON commit, fresh load, fresh renderer, and semantic uniform
# mount are all exercised in one run.

const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

const GOLD_IDS := ["KINETIC_RUSH", "PATTERN_CUT", "LIVING_CONTOUR", "SIGNAL_MELT", "VACUUM_CLASH", "CLASH_OVERDRIVE"]
const FINAL_IDS := ["KINETIC_RUSH", "PATTERN_CUT", "VACUUM_CLASH", "CLASH_OVERDRIVE"]

var checks := 0
var failures := 0
var runtime
var host: Control
var host_root: Node
var production
var data_dir := ""
var runtime_mounts := 0
var runtime_cleanups := 0
var production_sessions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	data_dir = "user://fx_gold_roundtrip_%d_%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]
	for recipe_id in GOLD_IDS:
		await _roundtrip_recipe(recipe_id)
	_check(runtime_mounts == GOLD_IDS.size(), "Gold creates one fresh screen runtime per recipe", str(runtime_mounts))
	_check(runtime_cleanups == GOLD_IDS.size(), "Gold destroys each screen runtime after its recipe", str(runtime_cleanups))
	_check(production_sessions == GOLD_IDS.size(), "Gold creates one fresh production session per recipe", str(production_sessions))
	print("[FX-GOLD-ROUNDTRIP] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _mount_runtime() -> bool:
	host = Control.new()
	host.size = Vector2(1280, 720)
	host_root = Node.new()
	host_root.name = "RoundtripHost"
	get_root().add_child(host_root)
	host_root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	runtime_mounts += 1
	container.add_child(runtime.subvp)
	await process_frame
	var mounted: bool = runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	_check(mounted, "fresh runtime mounts")
	return mounted

func _destroy_runtime() -> void:
	if runtime == null:
		return
	runtime.free_screen()
	if host_root != null and is_instance_valid(host_root):
		host_root.free()
	runtime = null
	host = null
	host_root = null
	runtime_cleanups += 1

func _roundtrip_recipe(recipe_id: String) -> void:
	production = FxProductionScript.new()
	production_sessions += 1
	production.data_dir = data_dir + "_" + recipe_id.to_lower()
	production.ensure_dirs()
	var source_result: Dictionary = FxRecipesScript.instantiate_look(recipe_id, "ROUNDTRIP_%s" % recipe_id, recipe_id, "roundtrip")
	_check(bool(source_result.get("ok", false)), "%s canonical source instantiates" % recipe_id, str(source_result.get("errors", [])))
	if not bool(source_result.get("ok", false)):
		return
	var source: Dictionary = source_result["look"]
	var source_composition: Dictionary = {}
	if FINAL_IDS.has(recipe_id):
		source_composition = (source_result.get("composition", {}) as Dictionary).get("doc", {})
		source_composition["status"] = "PRODUCTION"
		source_composition["revision"] = 1
	var apply_plan: Dictionary = {"composition": source_composition} if FINAL_IDS.has(recipe_id) else {"look": source}
	var applied: Dictionary = production.apply(apply_plan)
	_check(bool(applied.get("ok", false)), "%s Production Apply commits" % recipe_id, str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var loaded: Dictionary = production.load_composition() if FINAL_IDS.has(recipe_id) else production.load_look(str(source.get("look_id", "")))
	_check(bool(loaded.get("ok", false)), "%s persisted document reloads" % recipe_id, str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var persisted: Dictionary = loaded["doc"]
	var canonical_expected: Dictionary
	if FINAL_IDS.has(recipe_id):
		canonical_expected = FxCompositionScript.materialize(source_composition)
	else:
		canonical_expected = FxLookScript.materialize(source)
	_check(FxLookScript.equivalent(canonical_expected, persisted), "%s exact canonical semantics survive Save/Load" % recipe_id)
	var runtime_ready := await _mount_runtime()
	if not runtime_ready:
		_destroy_runtime()
		production = null
		return
	_check(runtime.last_mount_ok and runtime.last_mount_label.begins_with("live"), "%s runtime completion marker is live" % recipe_id, runtime.last_mount_label)
	_check(runtime.registry != null, "%s fresh runtime owns a fresh target registry" % recipe_id)
	var renderer := FxLayerRendererScript.new(runtime.screen, runtime.registry)
	var plan: Array
	if FINAL_IDS.has(recipe_id):
		plan = []
	else:
		var target := "echo_left" if recipe_id == "SIGNAL_MELT" else "primary_left"
		plan = [{"key": target, "look": persisted}]
	var render_options: Dictionary = {"anchor_target_key": "primary_left"}
	if FINAL_IDS.has(recipe_id):
		render_options["composition"] = persisted
	var mounted: Dictionary = renderer.apply_composition(plan, render_options)
	_check(bool(mounted.get("ok", false)), "%s fresh renderer mounts persisted semantics" % recipe_id, str(mounted.get("errors", [])))
	if FINAL_IDS.has(recipe_id):
		var expected_anchor := "TARGET_CENTER" if recipe_id == "KINETIC_RUSH" else "VS_MARK"
		var resolved: Vector2 = runtime.registry.resolve_anchor(expected_anchor, "primary_left")
		_check(resolved != Vector2(0.5, 0.5), "%s resolves a live semantic anchor" % recipe_id, str(resolved))
	if FINAL_IDS.has(recipe_id):
		var expected_passes := 0
		for raw_pass in persisted.get("final_passes", []):
			if str((raw_pass as Dictionary).get("operator", "NONE")) != "NONE" and bool((raw_pass as Dictionary).get("enabled", true)):
				expected_passes += 1
		_check(int(mounted.get("final_composite", 0)) == expected_passes, "%s fresh runtime exposes ordered final passes" % recipe_id)
	else:
		_check(renderer.has_stack("echo_left" if recipe_id == "SIGNAL_MELT" else "primary_left"), "%s fresh runtime exposes target-local stack" % recipe_id)
	renderer.clear_all()
	_destroy_runtime()
	_check(runtime == null, "%s runtime teardown completion marker" % recipe_id)
	production = null

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
	else:
		print("[CHECK] PASS  ", label)
