extends SceneTree
# Phase 7 recipe foundation: deterministic model/registry contract.
# This is intentionally headless; shell-level discoverability and undo proof is
# covered separately so registry failures remain cheap to diagnose.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var failures := 0
var checks := 0

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)

func _init() -> void:
	var recipes_script = load("res://scripts/fx_vnext/fx_recipes.gd")
	_check(recipes_script != null, "Phase 7 recipe registry loads")
	if recipes_script == null:
		print("[FX-RECIPES] done · checks=%d failures=%d" % [checks, failures])
		quit(1)
		return

	var ids: Array = recipes_script.recipe_ids()
	_check(ids.size() >= 5 and ids.has("PRIMARY_FLAME_ENERGY") and ids.has("ORGANIC_SIDE_FIELD") and ids.has("EDGE_HALO") and ids.has("RGB_TEAR") and ids.has("DITHER_TREATMENT"), "registry exposes Hero Recipes and curated starting points", str(ids))
	var registry_check: Dictionary = recipes_script.validate_registry()
	_check(bool(registry_check.get("ok", false)), "registry definitions validate", str(registry_check.get("errors", [])))
	var unknown: Dictionary = recipes_script.instantiate("UNKNOWN_RECIPE", "fixture-target")
	_check(not bool(unknown.get("ok", false)), "unknown recipe fails closed")
	var empty_key: Dictionary = recipes_script.instantiate("PRIMARY_FLAME_ENERGY", "   ")
	_check(not bool(empty_key.get("ok", false)), "empty instance key fails closed")

	for recipe_id in ids:
		var recipe: Dictionary = recipes_script.get_recipe(str(recipe_id))
		_check(str(recipe.get("stable_id", "")) == str(recipe_id), "%s has a stable id" % recipe_id)
		_check(str(recipe.get("description", "")) != "", "%s has a description" % recipe_id)
		_check(not (recipe.get("target_compatibility", {}) as Dictionary).is_empty(), "%s declares target compatibility" % recipe_id)
		_check(bool(recipe.get("advanced_access", false)), "%s exposes Advanced access" % recipe_id)
		var hero_recipe := str(recipe_id) in ["PRIMARY_FLAME_ENERGY", "ORGANIC_SIDE_FIELD"]
		_check((recipe.get("macros", []) as Array).size() >= (2 if hero_recipe else 1), "%s declares macro metadata" % recipe_id)
		_check((recipe.get("layers", []) as Array).size() >= (2 if hero_recipe else 1), "%s has an authorable layer stack" % recipe_id)

		var one: Dictionary = recipes_script.instantiate(str(recipe_id), "fixture-target")
		var two: Dictionary = recipes_script.instantiate(str(recipe_id), "fixture-target")
		_check(bool(one.get("ok", false)) and bool(two.get("ok", false)), "%s instantiates" % recipe_id, str(one.get("errors", [])))
		var one_layers: Array = one.get("layers", [])
		var two_layers: Array = two.get("layers", [])
		_check(FxLookScript.equivalent(one_layers, two_layers), "%s layer stack is deterministic for an instance key" % recipe_id)
		var other_key: Dictionary = recipes_script.instantiate(str(recipe_id), "fixture-target-other")
		var other_ids: Array = other_key.get("layer_ids", [])
		_check(other_ids != one.get("layer_ids", []), "%s instance key changes layer identity" % recipe_id)
		var ids_seen: Dictionary = {}
		for layer in one_layers:
			var layer_id := str((layer as Dictionary).get("layer_id", ""))
			_check(layer_id != "" and not ids_seen.has(layer_id), "%s layer ids are stable and unique" % recipe_id, layer_id)
			ids_seen[layer_id] = true
			_check(layer_id.begins_with("recipe-"), "%s layer id is recipe-instance based" % recipe_id, layer_id)

		var look: Dictionary = FxLookScript.new_look("RECIPE_%s" % recipe_id, str(recipe.get("name", recipe_id)))
		look["layers"].append_array(one_layers)
		look = FxLookScript.materialize(look)
		var validation: Dictionary = FxLookScript.validate_input(look)
		_check(bool(validation.get("ok", false)), "%s produces a normal canonical Look" % recipe_id, str(validation.get("errors", [])))
		_check(not (recipes_script.authored_field_paths(str(recipe_id)) as Array).is_empty(), "%s exposes authored canonical fields" % recipe_id)
		var authored_check: Dictionary = recipes_script.validate_authored_fields(str(recipe_id), one_layers)
		_check(bool(authored_check.get("ok", false)), "%s authored fields have no hidden values" % recipe_id, str(authored_check.get("errors", [])))

	var flame: Dictionary = recipes_script.instantiate("PRIMARY_FLAME_ENERGY", "primary-left")
	var flame_layers: Array = flame.get("layers", [])
	var flame_alpha := false
	var flame_fringe := false
	var flame_flow := false
	var flame_driver := false
	var flame_motion := false
	for raw in flame_layers:
		var layer: Dictionary = raw
		flame_alpha = flame_alpha or (bool((layer.get("mask", {}) as Dictionary).get("enabled", false)) and str((layer.get("mask", {}) as Dictionary).get("source", "")) == "ORIGINAL_SOURCE_ALPHA")
		var fx: Dictionary = layer.get("fx", {})
		flame_fringe = flame_fringe or float(fx.get("fringe", 0.0)) > 0.0
		flame_flow = flame_flow or float(fx.get("flow", 0.0)) > 0.0
		flame_driver = flame_driver or float(fx.get("driver_mode", 0.0)) > 0.0
		var motion: Dictionary = layer.get("motion", {})
		var enabled: Dictionary = motion.get("enabled", {}) if motion is Dictionary else {}
		flame_motion = flame_motion or bool(enabled.get("fringe", false)) or bool(enabled.get("flow", false))
		_check(str(layer.get("plane", "")) == "TARGET_UNDERLAY", "PRIMARY_FLAME_ENERGY stays behind the primary target")
	_check(flame_alpha and flame_fringe and flame_flow and flame_driver and flame_motion, "PRIMARY_FLAME_ENERGY authors alpha mask + fringe + flow + driver + motion")
	var flame_compat: Dictionary = recipes_script.get_recipe("PRIMARY_FLAME_ENERGY").get("target_compatibility", {})
	_check((flame_compat.get("target_roles", []) as Array).has("primary"), "PRIMARY_FLAME_ENERGY targets primary fighters")

	var organic: Dictionary = recipes_script.instantiate("ORGANIC_SIDE_FIELD", "field-left")
	var organic_layers: Array = organic.get("layers", [])
	var organic_alpha := false
	var organic_alpha_edge := false
	var organic_alpha_edge_mode := false
	var organic_radial_authored := false
	for raw in organic_layers:
		var layer: Dictionary = raw
		var mask: Dictionary = layer.get("mask", {})
		organic_alpha = organic_alpha or (bool(mask.get("enabled", false)) and str(mask.get("source", "")) == "ORIGINAL_SOURCE_ALPHA" and str(mask.get("space", "")) == "SOURCE_SPACE")
		organic_alpha_edge = organic_alpha_edge or str(mask.get("region", "")) == "EDGE_BAND"
		var fx: Dictionary = layer.get("fx", {})
		organic_alpha_edge_mode = organic_alpha_edge_mode or float(fx.get("edge_source_mode", -1.0)) == 0.0
	for path in recipes_script.authored_field_paths("ORGANIC_SIDE_FIELD"):
		var path_text := str(path)
		organic_radial_authored = organic_radial_authored or path_text.contains("FIELD_CENTER") or path_text.contains("LEGACY_RADIAL")
	_check(organic_alpha and organic_alpha_edge and organic_alpha_edge_mode, "ORGANIC_SIDE_FIELD follows actual irregular source alpha")
	_check(not organic_radial_authored, "ORGANIC_SIDE_FIELD does not author rectangle/radial approximation fields")
	var organic_compat: Dictionary = recipes_script.get_recipe("ORGANIC_SIDE_FIELD").get("target_compatibility", {})
	_check((organic_compat.get("target_roles", []) as Array).has("side_field"), "ORGANIC_SIDE_FIELD targets side-field elements")

	print("[FX-RECIPES] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
