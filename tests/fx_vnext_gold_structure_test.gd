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

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
