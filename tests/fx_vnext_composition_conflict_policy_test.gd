extends SceneTree
# Product-level diagnostic proof: once composition.json is active, a persisted
# legacy target-owned FINAL_COMPOSITE layer is surfaced before render.

const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var production = FxProductionScript.new()
	production.data_dir = "user://fx_vnext_conflict_policy_test"
	_wipe_dir(ProjectSettings.globalize_path(production.data_dir))
	production.ensure_dirs()
	var legacy := FxLookScript.new_look("LEGACY_FINAL", "Legacy Final")
	var layer := FxLookScript.new_layer("FX", "Legacy Final Operator")
	layer["lane"] = "FINAL_COMPOSITE"
	layer["authority"] = "TARGET"
	(layer["fx"] as Dictionary)["operator"] = "speedlines_field"
	(legacy["layers"] as Array).append(layer)
	var file := FileAccess.open(production.look_path("LEGACY_FINAL"), FileAccess.WRITE)
	file.store_string(FxLookScript.to_json(legacy))
	file.close()
	var composition: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.KINETIC_RUSH, "conflict-policy").get("doc", {})
	var applied: Dictionary = production.apply({"composition": composition})
	_check(bool(applied.get("ok", false)), "explicit composition persists for conflict policy fixture", str(applied.get("errors", [])))
	var state: Dictionary = production.production_state()
	var conflicts: Array = state.get("composition_conflicts", [])
	_check(not bool(state.get("ok", true)), "production health fails closed on mixed authority")
	_check(conflicts.size() == 1, "production health reports one explicit composition conflict", str(conflicts))
	if conflicts.size() == 1:
		var conflict: Dictionary = conflicts[0]
		_check(str(conflict.get("look_id", "")) == "LEGACY_FINAL", "conflict identifies offending Look")
		_check(str(conflict.get("layer_id", "")) != "", "conflict identifies offending layer")
		_check(str(conflict.get("operator", "")) == "speedlines_field", "conflict identifies offending operator")
		_check(str(conflict.get("recommended_action", "")).contains("migrate"), "conflict includes migration action")
	var diagnostic_found := false
	for raw_error in state.get("errors", []):
		if str(raw_error).contains("MIGRATION_REVIEW_REQUIRED"):
			diagnostic_found = true
	_check(diagnostic_found, "production errors carry MIGRATION_REVIEW_REQUIRED diagnostic")
	_wipe_dir(ProjectSettings.globalize_path(production.data_dir))
	print("[FX-COMPOSITION-CONFLICT-POLICY] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)

func _wipe_dir(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	for file_name in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs_path):
		_wipe_dir(abs_path.path_join(sub))
		DirAccess.remove_absolute(abs_path.path_join(sub))
