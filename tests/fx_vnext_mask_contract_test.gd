# MK-01..MK-05 — mask contract regression (model level, headless).
# Validate rules, harvest coverage, renderer construct fail-closed, influence
# uniform wiring. Pixel semantics (influence gating, RT-05 blends, LG visual)
# are proven by the windowed readback suite.
extends SceneTree

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")

var checks := 0
var failures := 0

func _init() -> void:
	_mk_validate_custom_requires_asset()
	_mk_validate_none_enabled_rejected()
	_mk_validate_effect_requires_treatment()
	_mk_validate_edge_path_rejected()
	_mk_validate_edge_mode_range()
	_mk_validate_influence_custom_requires_asset()
	_mk_harvest_imports_treatment_and_influence()
	_mk_production_rejects_missing_custom_mask()
	_mk_production_rejects_effect_without_asset()
	_mk_production_rejects_edge_path()
	print("[FX-MASK-CONTRACT] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		failures += 1
		print("[CHECK] FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")

func _doc1() -> Dictionary:
	var doc := FxLookScript.new_look("MK", "Mask contract")
	var fx: Dictionary = FxLookScript.new_layer("FX", "m")
	doc["layers"].append(fx)
	return doc

func _fx_of(doc: Dictionary) -> Dictionary:
	return (doc["layers"] as Array)[1]

func _mk_validate_custom_requires_asset() -> void:
	var doc := _doc1()
	(_fx_of(doc)["mask"] as Dictionary)["enabled"] = true
	(_fx_of(doc)["mask"] as Dictionary)["source"] = "CUSTOM_MASK"
	(_fx_of(doc)["mask"] as Dictionary)["region"] = "FULL"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "MK-03 enabled CUSTOM without asset rejected", str(res.get("errors", [])))

func _mk_validate_none_enabled_rejected() -> void:
	var doc := _doc1()
	(_fx_of(doc)["mask"] as Dictionary)["enabled"] = true
	(_fx_of(doc)["mask"] as Dictionary)["source"] = "NONE"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(bool(res.get("ok", false)), "MK-01 enabled NONE source validates as documented no-op", str(res.get("errors", [])))

func _mk_validate_effect_requires_treatment() -> void:
	var doc := _doc1()
	(_fx_of(doc)["fx"] as Dictionary)["effect_mask_enabled"] = true
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "MK-02 effect mask without treatment asset rejected", str(res.get("errors", [])))

func _mk_validate_edge_path_rejected() -> void:
	# CT-06 (missing-asset fail-closed incl. edge path): the unwired custom
	# edge slot cannot even be published, which eliminates the hazard class.
	var doc := _doc1()
	(_fx_of(doc)["fx"] as Dictionary)["edge_mask_path"] = "res://assets/vs/generated/accent_left_mask.png"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "MK-02 custom edge path rejected as unwired", str(res.get("errors", [])))

func _mk_validate_edge_mode_range() -> void:
	var doc := _doc1()
	(_fx_of(doc)["fx"] as Dictionary)["edge_source_mode"] = 3.0
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "MK-02 edge mode 3 rejected (procedural 0/1/2 only)")

func _mk_validate_influence_custom_requires_asset() -> void:
	var doc := _doc1()
	var infl := { "enabled": true, "source": "CUSTOM_MASK", "region": "FULL", "space": "LAYER_SPACE", "expand_contract_px": 0.0, "width_px": 0.0, "feather_px": 0.0, "invert": false, "custom_mask": null }
	(_fx_of(doc)["displacement"] as Dictionary)["influence_mask"] = infl
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "MK-05 influence CUSTOM without asset rejected", str(res.get("errors", [])))

func _write_user_png(path: String) -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	img.save_png(ProjectSettings.globalize_path(path))

func _wipe_dir(abs_path: String) -> void:
	if DirAccess.dir_exists_absolute(abs_path):
		for entry in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(entry))
		for sub in DirAccess.get_directories_at(abs_path):
			_wipe_dir(abs_path.path_join(sub))
			DirAccess.remove_absolute(abs_path.path_join(sub))
	else:
		DirAccess.make_dir_recursive_absolute(abs_path)

func _mk_harvest_imports_treatment_and_influence() -> void:
	var dir := "user://fx_mask_harvest"
	_wipe_dir(ProjectSettings.globalize_path(dir))
	_write_user_png("user://mk_treatment.png")
	_write_user_png("user://mk_influence.png")
	var prod = FxProductionScript.new()
	prod.data_dir = dir
	var doc := _doc1()
	# Absolute OS paths are EXTERNAL: harvest must import them project-local
	# (this is the real rewrite path; user:// refs are app-local kept as-is).
	var ext_treatment := ProjectSettings.globalize_path("user://mk_treatment.png")
	var ext_influence := ProjectSettings.globalize_path("user://mk_influence.png")
	(_fx_of(doc)["fx"] as Dictionary)["effect_mask_enabled"] = true
	(_fx_of(doc)["fx"] as Dictionary)["treatment_mask_path"] = ext_treatment
	var infl := { "enabled": true, "source": "CUSTOM_MASK", "region": "FULL", "space": "LAYER_SPACE", "expand_contract_px": 0.0, "width_px": 0.0, "feather_px": 0.0, "invert": false, "custom_mask": ext_influence }
	(_fx_of(doc)["displacement"] as Dictionary)["influence_mask"] = infl
	var res: Dictionary = prod.apply({"look": doc})
	_check(bool(res.get("ok", false)), "MK-04 external treatment+influence assets harvest into Production", str(res.get("errors", [])))
	if bool(res.get("ok", false)):
		var stored: Dictionary = prod.load_look("MK")
		var sfx: Dictionary = (stored["doc"]["layers"] as Array)[1]
		var treat := str((sfx["fx"] as Dictionary).get("treatment_mask_path", ""))
		var infl_got := str((((sfx["displacement"] as Dictionary)["influence_mask"]) as Dictionary).get("custom_mask", ""))
		_check(treat.begins_with("user://fx_mask_harvest/assets/") and FileAccess.file_exists(treat), "MK-04 treatment harvested into this Production", treat)
		_check(infl_got.begins_with("user://fx_mask_harvest/assets/") and FileAccess.file_exists(infl_got), "MK-04 influence harvested into this Production", infl_got)

func _mk_production_rejects_missing_custom_mask() -> void:
	var dir := "user://fx_mask_reject"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var prod = FxProductionScript.new()
	prod.data_dir = dir
	var doc := _doc1()
	(_fx_of(doc)["mask"] as Dictionary)["enabled"] = true
	(_fx_of(doc)["mask"] as Dictionary)["source"] = "CUSTOM_MASK"
	(_fx_of(doc)["mask"] as Dictionary)["region"] = "FULL"
	(_fx_of(doc)["mask"] as Dictionary)["custom_mask"] = "res://assets/vs/generated/does_not_exist_mk.png"
	var res: Dictionary = prod.apply({"look": doc})
	_check(not bool(res.get("ok", true)), "MK-03 missing custom asset fails Production apply", str(res.get("errors", [])))

func _mk_production_rejects_effect_without_asset() -> void:
	var dir := "user://fx_mask_reject2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var prod = FxProductionScript.new()
	prod.data_dir = dir
	var doc := _doc1()
	(_fx_of(doc)["fx"] as Dictionary)["effect_mask_enabled"] = true
	var res: Dictionary = prod.apply({"look": doc})
	_check(not bool(res.get("ok", true)), "MK-02 effect without asset fails Production apply")

func _mk_production_rejects_edge_path() -> void:
	var dir := "user://fx_mask_reject3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var prod = FxProductionScript.new()
	prod.data_dir = dir
	var doc := _doc1()
	(_fx_of(doc)["fx"] as Dictionary)["edge_mask_path"] = "res://assets/vs/generated/accent_left_mask.png"
	var res: Dictionary = prod.apply({"look": doc})
	_check(not bool(res.get("ok", true)), "MK-02 edge path fails Production apply")
