extends SceneTree
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxCostScript := preload("res://scripts/fx_vnext/fx_cost.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_test_recipe_documents()
	_test_fail_closed_ownership()
	_test_order_is_authored()
	_test_cost_boundary()
	print("[FX-COMPOSITION-CONTRACT] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _test_recipe_documents() -> void:
	for recipe_id in [FxRecipesScript.KINETIC_RUSH, FxRecipesScript.PATTERN_CUT, FxRecipesScript.VACUUM_CLASH, FxRecipesScript.CLASH_OVERDRIVE]:
		var result: Dictionary = FxRecipesScript.instantiate_composition(recipe_id, "contract")
		_check(bool(result.get("ok", false)), "%s instantiates composition" % recipe_id)
		var doc: Dictionary = result.get("doc", {})
		var validation: Dictionary = FxCompositionScript.validate(doc)
		_check(bool(validation.get("ok", false)), "%s validates" % recipe_id)
		_check(not (doc.get("final_passes", []) as Array).is_empty(), "%s has ordered passes" % recipe_id)
	_check((FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {}).get("final_passes", []) as Array).size() == 4, "clash has terminal identity pass")
	var clash: Array = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {}).get("final_passes", [])
	_check(str(clash[0].get("operator", "")) == "vacuum_burst", "clash stage 0 vacuum")
	_check(str(clash[1].get("operator", "")) == "speedlines_field", "clash stage 1 speedlines")
	_check(str(clash[2].get("operator", "")) == "pattern_transition", "clash stage 2 pattern")
	_check(str(clash[3].get("operator", "")) == "NONE", "clash stage 3 identity")

func _test_fail_closed_ownership() -> void:
	var valid: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {})
	var forged: Dictionary = valid.duplicate(true)
	(forged["final_passes"] as Array)[0]["authority"] = "PRIMARY"
	var bad_authority: Dictionary = FxCompositionScript.validate(forged)
	_check(not bool(bad_authority.get("ok", false)), "wrong authority rejected")
	forged = valid.duplicate(true)
	(forged["final_passes"] as Array)[0]["lane"] = "TARGET_LOCAL"
	var bad_lane: Dictionary = FxCompositionScript.validate(forged)
	_check(not bool(bad_lane.get("ok", false)), "wrong lane rejected")
	forged = valid.duplicate(true)
	(forged["final_passes"] as Array)[1]["pass_id"] = str((forged["final_passes"] as Array)[0].get("pass_id", ""))
	var duplicate_id: Dictionary = FxCompositionScript.validate(forged)
	_check(not bool(duplicate_id.get("ok", false)), "duplicate pass id rejected")

func _test_order_is_authored() -> void:
	var source: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {})
	var reversed: Dictionary = source.duplicate(true)
	(reversed["final_passes"] as Array).reverse()
	var original_validation: Dictionary = FxCompositionScript.validate(source)
	var reversed_validation: Dictionary = FxCompositionScript.validate(reversed)
	_check(bool(original_validation.get("ok", false)) and bool(reversed_validation.get("ok", false)), "both authored orders validate")
	_check(str((reversed["final_passes"] as Array)[0].get("operator", "")) == "NONE", "reverse preserves explicit first entry")
	_check(str((source["final_passes"] as Array)[0].get("operator", "")) == "vacuum_burst", "source preserves authored first entry")

func _test_cost_boundary() -> void:
	var doc: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "contract").get("doc", {})
	var cost: Dictionary = FxCostScript.composition_cost(doc)
	_check(cost.get("errors", []).is_empty(), "composition cost validates")
	_check(int((cost.get("passes", []) as Array).size()) == 3, "identity pass is not charged")
	_check(float(cost.get("total", 0.0)) > 0.0, "full-frame composition cost is visible")
