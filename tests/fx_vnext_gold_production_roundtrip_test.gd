extends SceneTree
# Gold production roundtrip gate. This is the evidence authority for the
# persistence_proven/runtime_observable registry claims: canonical authoring,
# Production JSON commit, fresh load, fresh renderer, and semantic uniform
# mount are all exercised in one run.

const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
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

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	data_dir = "user://fx_gold_roundtrip_%d" % Time.get_ticks_msec()
	production = FxProductionScript.new()
	production.data_dir = data_dir
	production.ensure_dirs()
	await _mount_runtime()
	for recipe_id in GOLD_IDS:
		await _roundtrip_recipe(recipe_id)
	print("[FX-GOLD-ROUNDTRIP] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _mount_runtime() -> void:
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
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "fresh runtime mounts")
	for _i in range(20):
		await process_frame

func _roundtrip_recipe(recipe_id: String) -> void:
	production = FxProductionScript.new()
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
	_check(_semantic_snapshot(source_composition if FINAL_IDS.has(recipe_id) else source) == _semantic_snapshot(persisted), "%s semantic operator fields survive Save/Load" % recipe_id)
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

func _semantic_snapshot(doc: Dictionary) -> Array:
	var out: Array = []
	if doc.has("final_passes"):
		for raw_pass in doc.get("final_passes", []):
			var composition_pass: Dictionary = raw_pass
			var pass_fx: Dictionary = composition_pass.get("fx", {})
			out.append({"pass_id": str(composition_pass.get("pass_id", "")), "operator": str(composition_pass.get("operator", "")), "event_start": float(composition_pass.get("event_start", 0.0)), "duration": float(composition_pass.get("duration", 0.0)), "anchor": str(pass_fx.get("operator_anchor", "")), "time_source": str(pass_fx.get("operator_time_source", "")), "strength": float(pass_fx.get("operator_strength", 0.0)), "progress_start": float(pass_fx.get("operator_progress_start", 0.0)), "progress_end": float(pass_fx.get("operator_progress_end", 0.0))})
		return out
	for raw_layer in doc.get("layers", []):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		var fx: Dictionary = layer.get("fx", {})
		out.append({
			"layer_id": str(layer.get("layer_id", "")),
			"lane": str(layer.get("lane", "")),
			"authority": str(layer.get("authority", "")),
			"operator": str(fx.get("operator", "")),
			"secondary": str(fx.get("operator_secondary", "")),
			"anchor": str(fx.get("operator_anchor", "")),
			"time_source": str(fx.get("operator_time_source", "")),
			"fields": {
				"strength": float(fx.get("operator_strength", 0.0)),
				"scale": float(fx.get("operator_scale", 0.0)),
				"speed": float(fx.get("operator_speed", 0.0)),
				"threshold": float(fx.get("operator_threshold", 0.0)),
				"axis_x": float(fx.get("operator_axis_x", 0.0)),
				"axis_y": float(fx.get("operator_axis_y", 0.0)),
				"center_x": float(fx.get("operator_center_x", 0.0)),
				"center_y": float(fx.get("operator_center_y", 0.0)),
				"progress": float(fx.get("operator_progress", 0.0)),
				"progress_start": float(fx.get("operator_progress_start", 0.0)),
				"progress_end": float(fx.get("operator_progress_end", 0.0)),
				"polarity": float(fx.get("operator_polarity", 0.0)),
				"event_start": float(fx.get("operator_event_start", 0.0)),
				"duration": float(fx.get("operator_duration", 0.0)),
			},
		})
	return out

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
	else:
		print("[CHECK] PASS  ", label)
