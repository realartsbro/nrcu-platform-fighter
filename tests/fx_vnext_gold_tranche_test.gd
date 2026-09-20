extends SceneTree
## Gold tranche behavioral gate: the operator/recipe vertical slice must be real,
## reachable through canonical data, and backed by a dedicated shader branch.

const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxEvidenceScript := preload("res://scripts/fx_vnext/fx_evidence.gd")

var checks := 0
var failures := 0
var evidence_dir := ""

func _init() -> void:
	_speedlines_field_is_a_real_supported_operator()
	_kinetic_rush_is_a_gold_recipe_with_speedlines()
	_gold_operator_registry_is_complete()
	_gold_recipe_registry_is_exact_and_categorized()
	_gold_contract_rejects_wrong_lanes_and_pairs()
	await _runtime_output_is_observable()
	print("[FX-GOLD-TRANCHE] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _speedlines_field_is_a_real_supported_operator() -> void:
	var entry: Dictionary = FxOperatorsScript.operator_entry("speedlines_field")
	_check(not entry.is_empty(), "speedlines_field is registered")
	_check(str(entry.get("status", "")) in ["ADAPTER_ONLY", "SUPPORTED"], "speedlines_field has an implemented status", str(entry))
	_check(bool(entry.get("authoring_reachable", false)), "speedlines_field is authoring reachable")
	_check(bool(entry.get("persistence_proven", false)), "speedlines_field persistence is proven")
	_check(bool(entry.get("runtime_observable", false)), "speedlines_field runtime output is observable")
	_check(str(entry.get("lane", "")) == "FINAL_COMPOSITE", "speedlines_field uses the final-composite lane")
	var shader_text := _read_text("res://shaders/nrcu_fx_vnext_final_composite.gdshader")
	_check(shader_text.find("speedlines_field") >= 0, "final shader contains a dedicated speedlines_field branch")

func _kinetic_rush_is_a_gold_recipe_with_speedlines() -> void:
	_check(FxRecipesScript.has_recipe("KINETIC_RUSH"), "KINETIC_RUSH is in the recipe library")
	var recipe: Dictionary = FxRecipesScript.get_recipe("KINETIC_RUSH")
	_check(str(recipe.get("category", "")) == "Gold Recipe", "KINETIC_RUSH is categorized as Gold Recipe", str(recipe))
	_check((recipe.get("operator_ids", []) as Array).has("speedlines_field"), "KINETIC_RUSH names speedlines_field")
	var result: Dictionary = FxRecipesScript.instantiate("KINETIC_RUSH", "red-test")
	_check(bool(result.get("ok", false)), "KINETIC_RUSH instantiates through the canonical recipe path", str(result.get("errors", [])))
	if bool(result.get("ok", false)):
		var look := FxLookScript.new_look("GOLD_RED", "Gold Red")
		(look["layers"] as Array).append_array(result.get("layers", []))
		look = FxLookScript.materialize(look)
		_check(bool(FxLookScript.validate_input(look).get("ok", false)), "KINETIC_RUSH produces a canonical valid Look")
		var found_final := false
		for raw in result.get("layers", []):
			var layer: Dictionary = raw
			found_final = found_final or str(layer.get("lane", "")) == "FINAL_COMPOSITE"
		_check(found_final, "KINETIC_RUSH reaches FINAL_COMPOSITE through explicit layer metadata")

func _gold_operator_registry_is_complete() -> void:
	for operator_id in ["pattern_transition", "noise_erosion_border", "pixel_sort_smear", "vacuum_burst"]:
		var entry: Dictionary = FxOperatorsScript.operator_entry(operator_id)
		_check(not entry.is_empty(), "%s is registered" % operator_id)
		_check(bool(entry.get("authoring_reachable", false)), "%s is authoring reachable" % operator_id)
		_check(bool(entry.get("persistence_proven", false)), "%s persistence is proven" % operator_id)
		_check(bool(entry.get("runtime_observable", false)), "%s runtime output is observable" % operator_id)
	var expected_lanes := {
		"pattern_transition": "FINAL_COMPOSITE",
		"noise_erosion_border": "TARGET_LOCAL",
		"pixel_sort_smear": "TARGET_LOCAL",
		"vacuum_burst": "FINAL_COMPOSITE",
	}
	for operator_id in expected_lanes.keys():
		_check(str(FxOperatorsScript.operator_entry(str(operator_id)).get("lane", "")) == str(expected_lanes[operator_id]), "%s has its normative lane" % operator_id)

func _gold_recipe_registry_is_exact_and_categorized() -> void:
	var expected := ["KINETIC_RUSH", "PATTERN_CUT", "LIVING_CONTOUR", "SIGNAL_MELT", "VACUUM_CLASH", "CLASH_OVERDRIVE"]
	var expected_groups := {"KINETIC_RUSH": "MOTION / IMPACT", "PATTERN_CUT": "GRAPHIC TRANSITION", "LIVING_CONTOUR": "CHARACTER", "SIGNAL_MELT": "CHARACTER", "VACUUM_CLASH": "MOTION / IMPACT", "CLASH_OVERDRIVE": "SIGNATURE"}
	for recipe_id in expected:
		_check(FxRecipesScript.has_recipe(recipe_id), "%s is in the recipe library" % recipe_id)
		var recipe: Dictionary = FxRecipesScript.get_recipe(recipe_id)
		_check(str(recipe.get("category", "")) == "Gold Recipe", "%s is categorized as Gold Recipe" % recipe_id)
		_check(str(recipe.get("library_group", "")) == str(expected_groups[recipe_id]), "%s has an artist-facing library group" % recipe_id)
		_check(bool(recipe.get("advanced_access", false)), "%s exposes Advanced access" % recipe_id)
		_check(not (recipe.get("operator_ids", []) as Array).is_empty(), "%s names at least one real operator" % recipe_id)
		var result: Dictionary = FxRecipesScript.instantiate(recipe_id, "gold-registry")
		_check(bool(result.get("ok", false)), "%s instantiates through the canonical path" % recipe_id, str(result.get("errors", [])))
		if bool(result.get("ok", false)):
			var look := FxLookScript.new_look("GOLD_%s" % recipe_id, recipe_id)
			(look["layers"] as Array).append_array(result.get("layers", []))
			var canonical := FxLookScript.materialize(look)
			_check(bool(FxLookScript.validate_input(canonical).get("ok", false)), "%s produces a valid canonical Look" % recipe_id)
			for layer_index in range((recipe.get("layers", []) as Array).size()):
				var authored_fields: Dictionary = ((recipe["layers"] as Array)[layer_index] as Dictionary).get("authored_fields", {})
				var instantiated_fx: Dictionary = ((result["layers"] as Array)[layer_index] as Dictionary).get("fx", {})
				for field_key in ["fx.operator", "fx.operator_secondary", "fx.operator_center_x", "fx.operator_center_y", "fx.operator_progress", "fx.operator_polarity", "fx.operator_mix_mode", "fx.operator_axis_x", "fx.operator_axis_y", "fx.operator_threshold", "fx.operator_time_source"]:
					if authored_fields.has(field_key):
						var fx_key := str(field_key).trim_prefix("fx.")
						_check(instantiated_fx.get(fx_key, null) == authored_fields[field_key], "%s preserves %s through materialization" % [recipe_id, fx_key])

func _gold_contract_rejects_wrong_lanes_and_pairs() -> void:
	var wrong_final := FxLookScript.new_look("WRONG_FINAL", "Wrong final lane")
	var final_layer: Dictionary = FxLookScript.new_layer("FX", "Speedlines local")
	(final_layer["fx"] as Dictionary)["operator"] = "speedlines_field"
	final_layer["lane"] = "TARGET_LOCAL"
	(wrong_final["layers"] as Array).append(final_layer)
	_check(not bool(FxLookScript.validate_input(FxLookScript.materialize(wrong_final)).get("ok", false)), "Gold final operator cannot silently run on TARGET_LOCAL")
	var wrong_local := FxLookScript.new_look("WRONG_LOCAL", "Wrong local lane")
	var local_layer: Dictionary = FxLookScript.new_layer("FX", "Contour final")
	(local_layer["fx"] as Dictionary)["operator"] = "noise_erosion_border"
	local_layer["lane"] = "FINAL_COMPOSITE"
	(wrong_local["layers"] as Array).append(local_layer)
	_check(not bool(FxLookScript.validate_input(FxLookScript.materialize(wrong_local)).get("ok", false)), "Gold local operator cannot silently run on FINAL_COMPOSITE")
	var wrong_pair := FxLookScript.new_look("WRONG_PAIR", "Wrong operator pair")
	var pair_layer: Dictionary = FxLookScript.new_layer("FX", "Unsupported pair")
	(pair_layer["fx"] as Dictionary)["operator"] = "pattern_transition"
	(pair_layer["fx"] as Dictionary)["operator_secondary"] = "vacuum_burst"
	pair_layer["lane"] = "FINAL_COMPOSITE"
	(wrong_pair["layers"] as Array).append(pair_layer)
	_check(not bool(FxLookScript.validate_input(FxLookScript.materialize(wrong_pair)).get("ok", false)), "Unsupported Gold operator pair fails closed")
	var clash := FxRecipesScript.instantiate("CLASH_OVERDRIVE", "gold-contract")
	_check(bool(clash.get("ok", false)), "CLASH_OVERDRIVE keeps its supported speedlines-plus-vacuum pair")

func _runtime_output_is_observable() -> void:
	evidence_dir = ProjectSettings.globalize_path(OS.get_environment("FXLAB_EVIDENCE_DIR")) if OS.get_environment("FXLAB_EVIDENCE_DIR") != "" else ProjectSettings.globalize_path("user://fx_evidence/gold_tranche")
	var output_size := Vector2(1280, 720)
	var size_token := OS.get_environment("FX_GOLD_OUTPUT_SIZE").strip_edges()
	if size_token == "1920x1080":
		output_size = Vector2(1920, 1080)
		evidence_dir = evidence_dir.path_join("gold_recipe_review_1920x1080")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var host := Control.new()
	host.size = output_size
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = output_size != Vector2(1280, 720)
	container.size = output_size
	host.add_child(container)
	var runtime := FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "gold runtime mounts a real screen")
	for i in 8:
		await process_frame
	var renderer := FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_clocks(1.5, 1.5)
	var neutral := FxLookScript.materialize(FxLookScript.new_look("GOLD_NEUTRAL", "Gold neutral"))
	var base_result: Dictionary = renderer.apply_composition([{"key": "echo_left", "look": neutral}])
	_check(bool(base_result.get("ok", false)), "gold runtime commits the neutral baseline", str(base_result.get("errors", [])))
	var readback_enabled := OS.get_environment("FX_GOLD_READBACK") != ""
	var baseline: Image = null
	var diffs := {}
	if readback_enabled:
		await process_frame
		baseline = host.get_viewport().get_texture().get_image()
		FxEvidenceScript.save_png(baseline, evidence_dir.path_join("gold_baseline.png"))
	for operator_id in ["speedlines_field", "pattern_transition", "vacuum_burst", "noise_erosion_border", "pixel_sort_smear"]:
		print("[GOLD-RUNTIME] applying ", operator_id)
		var target_key := "primary_left" if operator_id in ["noise_erosion_border", "pixel_sort_smear"] else "echo_left"
		var comparison: Image = baseline
		if readback_enabled:
			var neutral_result: Dictionary = renderer.apply_composition([{"key": target_key, "look": neutral}])
			_check(bool(neutral_result.get("ok", false)), "%s commits a controlled neutral comparison" % operator_id, str(neutral_result.get("errors", [])))
			renderer.set_clocks(1.5, 1.5)
			await process_frame
			await process_frame
			comparison = host.get_viewport().get_texture().get_image()
			FxEvidenceScript.save_png(comparison, evidence_dir.path_join("neutral_" + operator_id + ".png"))
		var layer := FxLookScript.new_layer("FX", "Gold %s" % operator_id)
		var fx: Dictionary = layer["fx"]
		fx["operator"] = operator_id
		fx["operator_strength"] = 0.9
		fx["operator_scale"] = 1.0
		fx["operator_speed"] = 1.2
		fx["operator_time_source"] = "PRESENTATION_TIME"
		if operator_id in ["speedlines_field", "pattern_transition", "vacuum_burst"]:
			layer["lane"] = "FINAL_COMPOSITE"
			layer["plane"] = "TARGET_OVERLAY"
		var look := FxLookScript.new_look("GOLD_%s" % operator_id, operator_id)
		(look["layers"] as Array).append(layer)
		var result: Dictionary = renderer.apply_composition([{"key": target_key, "look": FxLookScript.materialize(look)}])
		_check(bool(result.get("ok", false)), "%s commits through the live renderer" % operator_id, str(result.get("errors", [])))
		_renderer_set_operator_time(renderer, target_key)
		if readback_enabled:
			await process_frame
			await process_frame
			var active: Image = host.get_viewport().get_texture().get_image()
			var diff := _mean_abs_diff(comparison, active)
			diffs[operator_id] = diff
			_check(diff > 0.0005, "%s changes rendered pixels" % operator_id, "mean_abs_diff=%.6f" % diff)
			FxEvidenceScript.save_png(active, evidence_dir.path_join(operator_id + ".png"))
			if target_key == "echo_left":
				renderer.set_clocks(1.5, 1.5)
				await process_frame
				await process_frame
				var after: Image = host.get_viewport().get_texture().get_image()
				var after_diff := _mean_abs_diff(comparison, after)
				var active_after_diff := _mean_abs_diff(active, after)
				_check(after_diff < 0.03 and active_after_diff > 0.0005, "%s returns to neutral after its event window" % operator_id, "neutral_delta=%.6f active_delta=%.6f" % [after_diff, active_after_diff])
				FxEvidenceScript.save_png(after, evidence_dir.path_join("after_" + operator_id + ".png"))
		else:
			_check(true, "%s live output readback is opt-in for headless contract runs" % operator_id)
	if readback_enabled:
		await _write_gold_operator_semantics(host, renderer)
		await _write_gold_recipe_evidence(host, runtime, renderer)
	FxEvidenceScript.write_json(evidence_dir.path_join("gold_tranche_summary.json"), {"checks": checks, "failures": failures, "operators": ["speedlines_field", "pattern_transition", "vacuum_burst", "noise_erosion_border", "pixel_sort_smear"], "readback_enabled": readback_enabled, "mean_abs_diff": diffs})

func _write_gold_operator_semantics(host: Control, renderer) -> void:
	var semantics_dir := evidence_dir.path_join("operator_semantics")
	DirAccess.make_dir_recursive_absolute(semantics_dir)
	var speed_base := {"operator_strength": 1.0, "operator_scale": 1.1, "operator_speed": 1.0, "operator_pattern_mode": 0.0, "operator_mix_mode": 0.0, "operator_distortion": 1.0, "operator_duration": 0.0}
	var speed_left := await _render_operator_variant(host, renderer, "echo_left", "speedlines_field", speed_base.merged({"operator_center_x": 0.24, "operator_center_y": 0.5}, true), 0.32, semantics_dir.path_join("speed_center_left.png"))
	var speed_right := await _render_operator_variant(host, renderer, "echo_left", "speedlines_field", speed_base.merged({"operator_center_x": 0.76, "operator_center_y": 0.5}, true), 0.32, semantics_dir.path_join("speed_center_right.png"))
	_check(_mean_abs_diff(speed_left, speed_right) > 0.001, "speedlines center changes the focal field", "left_vs_right=%.6f" % _mean_abs_diff(speed_left, speed_right))
	var speed_lines := await _render_operator_variant(host, renderer, "echo_left", "speedlines_field", speed_base.merged({"operator_mix_mode": 0.0}, true), 0.32, semantics_dir.path_join("speed_lines_only.png"))
	var speed_distortion := await _render_operator_variant(host, renderer, "echo_left", "speedlines_field", speed_base.merged({"operator_mix_mode": 1.0}, true), 0.32, semantics_dir.path_join("speed_distortion_only.png"))
	var speed_combined := await _render_operator_variant(host, renderer, "echo_left", "speedlines_field", speed_base.merged({"operator_mix_mode": 2.0}, true), 0.32, semantics_dir.path_join("speed_combined.png"))
	_check(_mean_abs_diff(speed_lines, speed_distortion) > 0.001, "speedlines lines-only and distortion-only are distinct")
	_check(_mean_abs_diff(speed_combined, speed_lines) > 0.001 and _mean_abs_diff(speed_combined, speed_distortion) > 0.001, "speedlines combined mode composes both mechanisms")

	var pattern_base := {"operator_strength": 1.0, "operator_scale": 1.0, "operator_speed": 1.0, "operator_progress": 0.5, "operator_axis_x": 1.0, "operator_axis_y": 0.2, "operator_softness": 0.08, "operator_duration": 0.0}
	var pattern_stripes := await _render_operator_variant(host, renderer, "echo_left", "pattern_transition", pattern_base.merged({"operator_pattern_family": 0.0}, true), 0.4, semantics_dir.path_join("pattern_stripes.png"))
	var pattern_dots := await _render_operator_variant(host, renderer, "echo_left", "pattern_transition", pattern_base.merged({"operator_pattern_family": 1.0}, true), 0.4, semantics_dir.path_join("pattern_dots.png"))
	var pattern_angular := await _render_operator_variant(host, renderer, "echo_left", "pattern_transition", pattern_base.merged({"operator_pattern_family": 2.0}, true), 0.4, semantics_dir.path_join("pattern_angular.png"))
	_check(_mean_abs_diff(pattern_stripes, pattern_dots) > 0.001 and _mean_abs_diff(pattern_dots, pattern_angular) > 0.001, "pattern families produce distinct reveal geometry")
	var pattern_start := await _render_operator_variant(host, renderer, "echo_left", "pattern_transition", pattern_base.merged({"operator_pattern_family": 1.0, "operator_progress": 0.0}, true), 0.4, semantics_dir.path_join("pattern_progress_0.png"))
	var pattern_end := await _render_operator_variant(host, renderer, "echo_left", "pattern_transition", pattern_base.merged({"operator_pattern_family": 1.0, "operator_progress": 1.0}, true), 0.4, semantics_dir.path_join("pattern_progress_1.png"))
	_check(_mean_abs_diff(pattern_start, pattern_end) > 0.001, "pattern transition has distinct defined endpoints")

	var vacuum_base := {"operator_strength": 0.92, "operator_scale": 1.0, "operator_speed": 1.2, "operator_duration": 0.0}
	var vacuum_left := await _render_operator_variant(host, renderer, "echo_left", "vacuum_burst", vacuum_base.merged({"operator_center_x": 0.25, "operator_center_y": 0.5, "operator_polarity": 0.0}, true), 0.36, semantics_dir.path_join("vacuum_center_left_pull.png"))
	var vacuum_right := await _render_operator_variant(host, renderer, "echo_left", "vacuum_burst", vacuum_base.merged({"operator_center_x": 0.75, "operator_center_y": 0.5, "operator_polarity": 0.0}, true), 0.36, semantics_dir.path_join("vacuum_center_right_pull.png"))
	var vacuum_push := await _render_operator_variant(host, renderer, "echo_left", "vacuum_burst", vacuum_base.merged({"operator_center_x": 0.5, "operator_center_y": 0.5, "operator_polarity": 1.0}, true), 0.36, semantics_dir.path_join("vacuum_center_push.png"))
	_check(_mean_abs_diff(vacuum_left, vacuum_right) > 0.001, "vacuum center changes radial origin")
	_check(_mean_abs_diff(vacuum_left, vacuum_push) > 0.001, "vacuum polarity changes warp geometry")

	var signal_base := {"operator_strength": 0.95, "operator_scale": 2.4, "operator_threshold": 0.46, "operator_softness": 0.12, "operator_speed": 1.0, "operator_duration": 0.0}
	var signal_horizontal := await _render_operator_variant(host, renderer, "primary_left", "pixel_sort_smear", signal_base.merged({"operator_axis_x": 1.0, "operator_axis_y": 0.0}, true), 0.44, semantics_dir.path_join("signal_horizontal.png"))
	var signal_vertical := await _render_operator_variant(host, renderer, "primary_left", "pixel_sort_smear", signal_base.merged({"operator_axis_x": 0.0, "operator_axis_y": 1.0}, true), 0.44, semantics_dir.path_join("signal_vertical.png"))
	var signal_threshold := await _render_operator_variant(host, renderer, "primary_left", "pixel_sort_smear", signal_base.merged({"operator_axis_x": 1.0, "operator_axis_y": 0.0, "operator_threshold": 0.95, "operator_softness": 0.03}, true), 0.44, semantics_dir.path_join("signal_threshold_high.png"))
	_check(_mean_abs_diff(signal_horizontal, signal_vertical) > 0.001, "pixel sort direction changes smear geometry")
	_check(_mean_abs_diff(signal_horizontal, signal_threshold) > 0.001, "pixel sort threshold changes selected luminance regions")

func _render_operator_variant(host: Control, renderer, target_key: String, operator_id: String, fields: Dictionary, clock: float, output_path: String) -> Image:
	var layer := FxLookScript.new_layer("FX", "Semantic %s" % operator_id)
	var fx: Dictionary = layer["fx"]
	fx["operator"] = operator_id
	for key in fields.keys():
		fx[str(key)] = fields[key]
	if operator_id in ["speedlines_field", "pattern_transition", "vacuum_burst"]:
		layer["lane"] = "FINAL_COMPOSITE"
		layer["plane"] = "TARGET_OVERLAY"
	else:
		layer["lane"] = "TARGET_LOCAL"
		layer["plane"] = "TARGET_OVERLAY"
	var look := FxLookScript.new_look("SEMANTICS_%s" % operator_id, operator_id)
	(look["layers"] as Array).append(layer)
	var canonical := FxLookScript.materialize(look)
	var result: Dictionary = renderer.apply_composition([{"key": target_key, "look": canonical}])
	_check(bool(result.get("ok", false)), "%s semantic variant applies" % operator_id, str(result.get("errors", [])))
	renderer.set_clocks(clock, clock)
	await process_frame
	await process_frame
	var image: Image = host.get_viewport().get_texture().get_image()
	FxEvidenceScript.save_png(image, output_path)
	return image

func _write_gold_recipe_evidence(host: Control, runtime, renderer) -> void:
	var specs := [
		{"id": "KINETIC_RUSH", "target": "echo_left", "kind": "EVENT"},
		{"id": "PATTERN_CUT", "target": "echo_left", "kind": "GRAPHIC_TRANSITION"},
		{"id": "LIVING_CONTOUR", "target": "primary_left", "kind": "TARGET_LOOK"},
		{"id": "SIGNAL_MELT", "target": "primary_left", "kind": "TARGET_LOOK"},
		{"id": "VACUUM_CLASH", "target": "echo_left", "kind": "EVENT"},
		{"id": "CLASH_OVERDRIVE", "target": "echo_left", "kind": "SIGNATURE"},
	]
	var peak_frames: Array = []
	var peak_ids: Array = []
	for raw_spec in specs:
		var spec: Dictionary = raw_spec
		var recipe_id := str(spec["id"])
		var target_key := str(spec["target"])
		var recipe := FxRecipesScript.get_recipe(recipe_id)
		var result := FxRecipesScript.instantiate(recipe_id, "gold-evidence")
		_check(bool(result.get("ok", false)), "%s evidence instantiates canonically" % recipe_id, str(result.get("errors", [])))
		if not bool(result.get("ok", false)):
			continue
		var look := FxLookScript.new_look("GOLD_EVIDENCE_%s" % recipe_id, str(recipe.get("name", recipe_id)))
		(look["layers"] as Array).append_array(result.get("layers", []))
		look = FxLookScript.materialize(look)
		var recipe_dir := evidence_dir.path_join("gold_recipe_review").path_join(recipe_id.to_lower())
		DirAccess.make_dir_recursive_absolute(recipe_dir)
		var is_event := str(spec["kind"]) in ["EVENT", "GRAPHIC_TRANSITION", "SIGNATURE"]
		var times: Array = [1.0, 1.2, 1.4, 1.6, 1.8]
		if is_event:
			times = [1.5, 0.10, 0.25, 0.40, 1.5]
		var names := ["before", "phase_a", "peak", "phase_b", "after"]
		var frames: Array = []
		for i in range(times.size()):
			var apply_result: Dictionary = renderer.apply_composition([{"key": target_key, "look": look}])
			_check(bool(apply_result.get("ok", false)), "%s evidence applies at %s" % [recipe_id, names[i]], str(apply_result.get("errors", [])))
			renderer.set_clocks(float(times[i]), float(times[i]))
			await process_frame
			await process_frame
			var frame: Image = host.get_viewport().get_texture().get_image()
			frames.append(frame)
			FxEvidenceScript.save_png(frame, recipe_dir.path_join(names[i] + ".png"))
		var contact := _contact_sheet(frames, 256, 144)
		contact.save_png(recipe_dir.path_join("contact_sheet.png"))
		var peak: Image = frames[2]
		var peak_small: Image = peak.duplicate()
		peak_small.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		peak_frames.append(peak_small)
		peak_ids.append(recipe_id)
		var recovery_diff := _mean_abs_diff(frames[0], frames[4]) if is_event else -1.0
		FxEvidenceScript.write_json(recipe_dir.path_join("metadata.json"), {
			"stable_id": recipe_id,
			"display_name": recipe.get("name", recipe_id),
			"category": recipe.get("category", "Gold Recipe"),
			"kind": spec["kind"],
			"target_key": target_key,
			"target_context": runtime.registry.context_for_key(target_key),
			"operator_ids": recipe.get("operator_ids", []),
			"source_semantics": recipe.get("source_semantics", {}),
			"macros": recipe.get("macros", []),
			"phase_times": {"before": times[0], "phase_a": times[1], "peak": times[2], "phase_b": times[3], "after": times[4]},
			"recovery_mean_abs_diff": recovery_diff,
			"evidence_authority": "windowed OpenGL readback PNG sequence; manual visual review remains authoritative",
		})
		# Exercise the opposite side/character anchor at the peak without pretending
		# that this is a second approval package.
		var right_key := "primary_right" if target_key == "primary_left" else "echo_right"
		var right_apply: Dictionary = renderer.apply_composition([{"key": right_key, "look": look}])
		_check(bool(right_apply.get("ok", false)), "%s cross-character/right target applies" % recipe_id, str(right_apply.get("errors", [])))
		renderer.set_clocks(float(times[2]), float(times[2]))
		await process_frame
		await process_frame
		var right_peak: Image = host.get_viewport().get_texture().get_image()
		FxEvidenceScript.save_png(right_peak, recipe_dir.path_join("cross_right_peak.png"))
	var all_contact := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	all_contact.fill(Color(0.03, 0.03, 0.04, 1.0))
	for i in range(peak_frames.size()):
		var col := i % 3
		var row := i / 3
		all_contact.blit_rect(peak_frames[i], Rect2i(0, 0, 640, 360), Vector2i(col * 640, row * 360))
	all_contact.save_png(evidence_dir.path_join("gold_recipe_review").path_join("ALL_GOLD_RECIPES_CONTACT_SHEET.png"))
	FxEvidenceScript.write_json(evidence_dir.path_join("gold_recipe_review").path_join("manifest.json"), {
		"status": "GOLD RECIPES READY FOR MANUAL VISUAL REVIEW",
		"recipes": peak_ids,
		"windowed_renderer": "OpenGL Compatibility",
		"primary_layout": "1280x720",
		"cross_target_proof": "left and right target captures per recipe",
		"note": "Non-canonical local evidence. Manual visual review remains the quality authority."
	})

func _contact_sheet(frames: Array, tile_w: int, tile_h: int) -> Image:
	var sheet := Image.create(tile_w * frames.size(), tile_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.03, 0.03, 0.04, 1.0))
	for i in range(frames.size()):
		var tile: Image = (frames[i] as Image).duplicate()
		tile.resize(tile_w, tile_h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(tile, Rect2i(0, 0, tile_w, tile_h), Vector2i(i * tile_w, 0))
	return sheet

func _renderer_set_operator_time(renderer, target_key: String) -> void:
	# Final-composite Gold operators are event-laned; local operators remain
	# observable at a stable supplied time for this focused operator gate.
	renderer.set_clocks(0.25 if target_key == "echo_left" else 1.5, 0.25 if target_key == "echo_left" else 1.5)

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 1
	return total / float(maxi(count, 1)) / 3.0

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
	else:
		print("[CHECK] PASS  ", label)
