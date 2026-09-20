extends SceneTree
# P0/P1 Gold structure regressions. These tests intentionally describe the
# product contract rather than shader implementation details:
# composition authority, ordered recipe composition, event choreography,
# semantic anchors, and intent-level macro surfaces.

const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	_test_scene_recipe_ownership()
	_test_clash_is_an_ordered_three_stage_recipe()
	_test_pattern_has_progress_choreography()
	_test_scene_anchor_contract()
	_test_intent_macros()
	_test_macro_mapping_mutates_canonical_fields()
	_test_instance_scoped_gold_macro_engine()
	print("[FX-GOLD-STRUCTURE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _test_scene_recipe_ownership() -> void:
	for recipe_id in ["KINETIC_RUSH", "PATTERN_CUT", "VACUUM_CLASH", "CLASH_OVERDRIVE"]:
		var recipe: Dictionary = FxRecipesScript.get_recipe(recipe_id)
		var compat: Dictionary = recipe.get("target_compatibility", {})
		_check((compat.get("target_roles", []) as Array) == ["composition"], "%s owns composition authority" % recipe_id, str(compat))
		_check((compat.get("element_roles", []) as Array) == ["composition"], "%s resolves against composition role" % recipe_id, str(compat))
		_check((compat.get("allowed_planes", []) as Array) == ["COMPOSITION_FOREGROUND"], "%s uses final composition plane" % recipe_id, str(compat))
		var instantiated: Dictionary = FxRecipesScript.instantiate(recipe_id, "structure")
		_check(bool(instantiated.get("ok", false)), "%s instantiates" % recipe_id, str(instantiated.get("errors", [])))
		for raw_layer in instantiated.get("layers", []):
			var layer: Dictionary = raw_layer
			if str(layer.get("lane", "")) == "FINAL_COMPOSITE":
				_check(str(layer.get("authority", "")) == "COMPOSITION", "%s final layer is composition-owned" % recipe_id, str(layer))

func _test_clash_is_an_ordered_three_stage_recipe() -> void:
	var recipe: Dictionary = FxRecipesScript.get_recipe("CLASH_OVERDRIVE")
	_check(recipe.get("operator_ids", []) == ["vacuum_burst", "speedlines_field", "pattern_transition"], "Clash Overdrive operator order is vacuum → speedlines → pattern", str(recipe.get("operator_ids", [])))
	_check((recipe.get("layers", []) as Array).size() == 3, "Clash Overdrive has three explicit ordered passes", str(recipe.get("layers", [])))
	var inst: Dictionary = FxRecipesScript.instantiate("CLASH_OVERDRIVE", "structure")
	for raw_layer in inst.get("layers", []):
		var fx: Dictionary = (raw_layer as Dictionary).get("fx", {})
		_check(str(fx.get("operator_secondary", "NONE")) == "NONE", "Clash Overdrive has no magic secondary operator", str(fx))
	_check(str(recipe.get("source_semantics", {}).get("composition", "")) == "VACUUM_SPEEDLINES_PATTERN", "Clash semantics name all three stages")

func _test_pattern_has_progress_choreography() -> void:
	var recipe: Dictionary = FxRecipesScript.get_recipe("PATTERN_CUT")
	var fields: Dictionary = ((recipe.get("layers", []) as Array)[0] as Dictionary).get("authored_fields", {})
	_check(float(fields.get("fx.operator_progress_start", -1.0)) == 0.0, "Pattern Cut starts at captured endpoint")
	_check(float(fields.get("fx.operator_progress_end", -1.0)) == 1.0, "Pattern Cut ends at graphic endpoint")
	_check(str(fields.get("fx.operator_progress_mode", "")) == "EVENT_LINEAR", "Pattern Cut uses event progress mapping")

func _test_scene_anchor_contract() -> void:
	for recipe_id in ["KINETIC_RUSH", "VACUUM_CLASH", "CLASH_OVERDRIVE"]:
		var recipe: Dictionary = FxRecipesScript.get_recipe(recipe_id)
		var fields: Dictionary = ((recipe.get("layers", []) as Array)[0] as Dictionary).get("authored_fields", {})
		var expected := "TARGET_CENTER" if recipe_id == "KINETIC_RUSH" else "VS_MARK"
		_check(str(fields.get("fx.operator_anchor", "")) == expected, "%s resolves %s anchor" % [recipe_id, expected], str(fields))
		_check(fields.has("fx.operator_center_x") and fields.has("fx.operator_center_y"), "%s keeps advanced center override" % recipe_id)

func _test_intent_macros() -> void:
	var expected := {
		"KINETIC_RUSH": ["Energy", "Density", "Focus", "Direction", "Distortion", "Motion"],
		"PATTERN_CUT": ["Progress", "Pattern", "Direction", "Scale", "Feather", "Motion"],
		"LIVING_CONTOUR": ["Life", "Edge Depth", "Breakup", "Turbulence", "Drift", "Intensity"],
		"SIGNAL_MELT": ["Melt", "Threshold", "Softness", "Direction", "Turbulence", "Chromatic Split"],
		"VACUUM_CLASH": ["Strength", "Pull / Push", "Radius", "Wobble", "Duration"],
		"CLASH_OVERDRIVE": ["Impact", "Direction", "Graphic Breakup", "Distortion", "Duration"],
	}
	for recipe_id in expected.keys():
		var recipe: Dictionary = FxRecipesScript.get_recipe(str(recipe_id))
		var macros: Array = recipe.get("macros", [])
		var labels: Array = []
		for raw_macro in macros:
			labels.append(str((raw_macro as Dictionary).get("label", "")))
		_check(labels == expected[recipe_id], "%s exposes intent-level macros" % recipe_id, str(labels))
		for raw_macro in macros:
			var macro: Dictionary = raw_macro
			_check(macro.has("mapping") and macro.get("mapping", {}) is Dictionary and not (macro.get("mapping", {}) as Dictionary).is_empty(), "%s macro %s has explicit canonical mapping" % [recipe_id, str(macro.get("label", ""))])

func _test_macro_mapping_mutates_canonical_fields() -> void:
	var result: Dictionary = FxRecipesScript.instantiate_look("KINETIC_RUSH", "MACRO_LOOK", "Macro Look", "macro")
	_check(bool(result.get("ok", false)), "macro fixture instantiates", str(result.get("errors", [])))
	var doc: Dictionary = result.get("look", {})
	_check(FxRecipesScript.apply_macro(doc, "KINETIC_RUSH", "ENERGY", 1.0), "Energy macro applies")
	var fx: Dictionary = ((doc.get("layers", []) as Array)[1] as Dictionary).get("fx", {})
	_check(float(fx.get("operator_strength", 0.0)) > 0.7, "Energy maps to operator strength", str(fx.get("operator_strength", 0.0)))
	_check(FxRecipesScript.apply_macro(doc, "KINETIC_RUSH", "FOCUS", "VS_MARK"), "Focus macro applies semantic anchor")
	_check(str(fx.get("operator_anchor", "")) == "VS_MARK", "Focus maps to anchor field", str(fx.get("operator_anchor", "")))
	_check(FxRecipesScript.apply_macro(doc, "KINETIC_RUSH", "MOTION", "FREE_RUN"), "Motion macro applies selected clock")
	_check(str(fx.get("operator_time_source", "")) == "FREE_RUN", "Motion maps to clock field", str(fx.get("operator_time_source", "")))

func _test_instance_scoped_gold_macro_engine() -> void:
	var instance_a: Dictionary = FxRecipesScript.instantiate("KINETIC_RUSH", "macro-a")
	var instance_b: Dictionary = FxRecipesScript.instantiate("KINETIC_RUSH", "macro-b")
	_check(bool(instance_a.get("ok", false)) and bool(instance_b.get("ok", false)), "instance-scoped macro fixtures instantiate")
	_check((instance_a.get("membership", {}) as Dictionary).get("layer_ids", []).size() == 1, "recipe instance exposes canonical layer membership")
	_check((instance_a.get("membership", {}) as Dictionary).get("pass_ids", []).size() == 2, "composition recipe instance exposes canonical pass membership")
	_check(not (instance_a.get("membership", {}) as Dictionary).has("layers") and not (instance_a.get("membership", {}) as Dictionary).has("recipe_macros"), "recipe membership carries ids without creative duplicates")
	var doc: Dictionary = FxLookScript.new_look("MACRO_INSTANCES", "Macro Instances")
	doc["metadata"]["recipe_instances"] = [instance_a.get("membership", {}).duplicate(true), instance_b.get("membership", {}).duplicate(true)]
	doc["layers"].append_array(instance_a.get("layers", []))
	doc["layers"].append_array(instance_b.get("layers", []))
	var before_b: Dictionary = (instance_b.get("layers", []) as Array)[0].duplicate(true)
	_check(FxRecipesScript.apply_macro(doc, "KINETIC_RUSH", "macro-a", "ENERGY", 0.5), "explicit instance macro applies")
	var layer_a: Dictionary = FxLookScript.find_layer(doc, str((instance_a.get("layer_ids", []) as Array)[0]))
	var layer_b: Dictionary = FxLookScript.find_layer(doc, str((instance_b.get("layer_ids", []) as Array)[0]))
	var fx_a: Dictionary = layer_a.get("fx", {})
	_check(is_equal_approx(float(fx_a.get("operator_strength", -1.0)), 0.5), "instance macro maps exact strength value")
	_check(is_equal_approx(float(fx_a.get("operator_distortion", -1.0)), 0.225), "scale mapping multiplies the normalized value")
	_check(FxLookScript.equivalent(layer_b, before_b), "instance macro leaves sibling recipe instance unchanged")
	var composition_a: Dictionary = FxRecipesScript.instantiate_composition("KINETIC_RUSH", "macro-a", instance_a.get("layers", []))
	var composition_b: Dictionary = FxRecipesScript.instantiate_composition("KINETIC_RUSH", "macro-b", instance_b.get("layers", []))
	var pass_doc: Dictionary = {"final_passes": [], "metadata": {"recipe_instances": [instance_a.get("membership", {}).duplicate(true), instance_b.get("membership", {}).duplicate(true)]}}
	(pass_doc["final_passes"] as Array).append_array((composition_a.get("doc", {}) as Dictionary).get("final_passes", []))
	(pass_doc["final_passes"] as Array).append_array((composition_b.get("doc", {}) as Dictionary).get("final_passes", []))
	var before_pass_b: Dictionary = ((pass_doc["final_passes"] as Array)[2] as Dictionary).duplicate(true)
	_check(FxRecipesScript.apply_macro(pass_doc, "KINETIC_RUSH", "macro-a", "ENERGY", 0.25), "instance macro applies to composition pass")
	_check(FxLookScript.equivalent((pass_doc["final_passes"] as Array)[2], before_pass_b), "instance macro leaves sibling composition pass unchanged")
	_check(bool(composition_a.get("ok", false)) and bool(composition_b.get("ok", false)), "composition instances retain valid pass documents")
	_check(FxRecipesScript.apply_macro(doc, "KINETIC_RUSH", "macro-a", "DENSITY", 0.72), "threshold and min/max macro applies")
	fx_a = (FxLookScript.find_layer(doc, str((instance_a.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(fx_a.get("operator_scale", -1.0)), 1.94), "min/max mapping produces exact scale", str(fx_a.get("operator_scale", "")))
	_check(is_equal_approx(float(fx_a.get("operator_pattern_mode", -1.0)), 1.0), "threshold mapping switches at its declared boundary")
	_check(FxRecipesScript.apply_macro(doc, "KINETIC_RUSH", "macro-a", "DIRECTION", 0.25), "direction macro applies")
	fx_a = (FxLookScript.find_layer(doc, str((instance_a.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(fx_a.get("operator_axis_x", -1.0)), 0.0), "direction maps quarter turn x axis")
	_check(is_equal_approx(float(fx_a.get("operator_axis_y", -1.0)), 1.0), "direction maps quarter turn y axis")

	var pattern: Dictionary = FxRecipesScript.instantiate("PATTERN_CUT", "pattern-a")
	var pattern_doc: Dictionary = FxLookScript.new_look("PATTERN_MACRO", "Pattern Macro")
	pattern_doc["layers"].append_array(pattern.get("layers", []))
	_check(FxRecipesScript.apply_macro(pattern_doc, "PATTERN_CUT", "pattern-a", "PATTERN", "ANGULAR"), "pattern family option applies")
	var pattern_fx: Dictionary = (FxLookScript.find_layer(pattern_doc, str((pattern.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(pattern_fx.get("operator_pattern_family", -1.0)), 2.0), "pattern family ANGULAR maps to canonical 2")
	_check(FxRecipesScript.apply_macro(pattern_doc, "PATTERN_CUT", "pattern-a", "DIRECTION", 0.25), "pattern direction macro applies")
	pattern_fx = (FxLookScript.find_layer(pattern_doc, str((pattern.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(pattern_fx.get("operator_axis_x", -1.0)), 0.0) and is_equal_approx(float(pattern_fx.get("operator_axis_y", -1.0)), 1.0), "pattern direction never copies one scalar to both axes")

	var vacuum: Dictionary = FxRecipesScript.instantiate("VACUUM_CLASH", "vacuum-a")
	var vacuum_doc: Dictionary = FxLookScript.new_look("VACUUM_MACRO", "Vacuum Macro")
	vacuum_doc["layers"].append_array(vacuum.get("layers", []))
	_check(FxRecipesScript.apply_macro(vacuum_doc, "VACUUM_CLASH", "vacuum-a", "POLARITY", "PULL"), "vacuum PULL option applies")
	var vacuum_fx: Dictionary = (FxLookScript.find_layer(vacuum_doc, str((vacuum.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(vacuum_fx.get("operator_polarity", -1.0)), 0.0), "vacuum PULL maps to canonical 0")
	_check(FxRecipesScript.apply_macro(vacuum_doc, "VACUUM_CLASH", "vacuum-a", "POLARITY", "PUSH"), "vacuum PUSH option applies")
	vacuum_fx = (FxLookScript.find_layer(vacuum_doc, str((vacuum.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(vacuum_fx.get("operator_polarity", -1.0)), 1.0), "vacuum PUSH maps to canonical 1")

	var kinetic_mode_doc: Dictionary = FxLookScript.new_look("MODE_MACRO", "Mode Macro")
	kinetic_mode_doc["layers"].append_array(instance_a.get("layers", []))
	_check(FxRecipesScript.apply_macro(kinetic_mode_doc, "KINETIC_RUSH", "macro-a", "DISTORTION", "COMBINED"), "kinetic mode option applies")
	var mode_fx: Dictionary = (FxLookScript.find_layer(kinetic_mode_doc, str((instance_a.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(mode_fx.get("operator_mix_mode", -1.0)), 2.0), "kinetic COMBINED maps to canonical 2")

	var signal_recipe: Dictionary = FxRecipesScript.instantiate("SIGNAL_MELT", "signal-a")
	var signal_doc: Dictionary = FxLookScript.new_look("SIGNAL_MACRO", "Signal Macro")
	signal_doc["layers"].append_array(signal_recipe.get("layers", []))
	_check(FxRecipesScript.apply_macro(signal_doc, "SIGNAL_MELT", "signal-a", "CHROMATIC_SPLIT", "DISTORTION"), "signal mode option applies")
	var signal_fx: Dictionary = (FxLookScript.find_layer(signal_doc, str((signal_recipe.get("layer_ids", []) as Array)[0])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(signal_fx.get("operator_mix_mode", -1.0)), 1.0), "signal DISTORTION maps to canonical 1")

	var clash: Dictionary = FxRecipesScript.instantiate("CLASH_OVERDRIVE", "clash-a")
	var clash_doc: Dictionary = FxLookScript.new_look("CLASH_MACRO", "Clash Macro")
	clash_doc["layers"].append_array(clash.get("layers", []))
	_check(FxRecipesScript.apply_macro(clash_doc, "CLASH_OVERDRIVE", "clash-a", "GRAPHIC_BREAKUP", "DIAGONAL"), "clash pattern option applies")
	var clash_fx: Dictionary = (FxLookScript.find_layer(clash_doc, str((clash.get("layer_ids", []) as Array)[2])).get("fx", {}) as Dictionary)
	_check(is_equal_approx(float(clash_fx.get("operator_pattern_family", -1.0)), 1.0), "clash DIAGONAL maps to canonical 1")

	for direction_case in [["PATTERN_CUT", "pattern-a", "DIRECTION"], ["LIVING_CONTOUR", "living-a", "DRIFT"], ["SIGNAL_MELT", "signal-a", "DIRECTION"], ["CLASH_OVERDRIVE", "clash-a", "DIRECTION"]]:
		var direction_result: Dictionary = FxRecipesScript.instantiate(str(direction_case[0]), str(direction_case[1]))
		var direction_doc: Dictionary = FxLookScript.new_look("DIRECTION_MACRO", "Direction Macro")
		direction_doc["layers"].append_array(direction_result.get("layers", []))
		_check(FxRecipesScript.apply_macro(direction_doc, str(direction_case[0]), str(direction_case[1]), str(direction_case[2]), 0.25), "%s direction macro applies" % direction_case[0])
		var direction_layer: Dictionary = FxLookScript.find_layer(direction_doc, str((direction_result.get("layer_ids", []) as Array)[0]))
		var direction_fx: Dictionary = direction_layer.get("fx", {})
		_check(is_equal_approx(float(direction_fx.get("operator_axis_x", -1.0)), 0.0) and is_equal_approx(float(direction_fx.get("operator_axis_y", -1.0)), 1.0), "%s direction maps normalized control to cos/sin axes" % direction_case[0])

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
