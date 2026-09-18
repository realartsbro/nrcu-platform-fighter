extends SceneTree

# UI-07/08 headless gate: central dependency truth, harvest rewrite and
# validation gates as pure data logic (no shell, no rendering). The windowed
# behavioral suite proves the same states through real UI actions.
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")

var checks: Array = []
var failures := 0
var stage_dir := ""
var data_dir := ""

func _init() -> void:
	data_dir = str(OS.get_environment("NRCU_FX_DATA_DIR"))
	if data_dir == "":
		data_dir = "user://fx_asset_headless"
	_stage_files()
	_truth()
	_harvest()
	_validation()
	_atomicity()
	print("[FX-ASSET-TRUTH] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
	checks.append(line)
	if not ok:
		failures += 1
		print(line)

func _stage_files() -> void:
	stage_dir = ProjectSettings.globalize_path("user://fx_asset_stage")
	DirAccess.make_dir_recursive_absolute(stage_dir)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.save_png(stage_dir.path_join("ok.png"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var corrupt := PackedByteArray()
	for i in 128:
		corrupt.append(rng.randi() & 0xFF)
	var c := FileAccess.open(stage_dir.path_join("corrupt.png"), FileAccess.WRITE)
	c.store_buffer(corrupt)
	c.close()
	var t := FileAccess.open(stage_dir.path_join("note.txt"), FileAccess.WRITE)
	t.store_string("not a texture")
	t.close()

func _upath(n: String) -> String:
	return ProjectSettings.globalize_path("user://fx_asset_stage/" + n)

func _layer_with(driver_mode: String, path) -> Dictionary:
	var layer: Dictionary = FxLookScript.new_layer("FX", "truth")
	(layer["displacement"] as Dictionary)["driver"] = driver_mode
	(layer["displacement"] as Dictionary)["custom_texture"] = path
	return layer

func _truth() -> void:
	var layer: Dictionary = FxLookScript.new_layer("FX", "truth")
	_check(str((FxAssetsScript.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "NOT_REQUIRED", "truth procedural not-required")
	layer = _layer_with("CUSTOM_TEXTURE", null)
	_check(str((FxAssetsScript.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "MISSING", "truth empty missing")
	layer = _layer_with("CUSTOM_TEXTURE", _upath("ghost.png"))
	_check(str((FxAssetsScript.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "MISSING", "truth ghost missing")
	layer = _layer_with("CUSTOM_TEXTURE", _upath("corrupt.png"))
	_check(str((FxAssetsScript.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "UNLOADABLE", "truth corrupt unloadable")
	layer = _layer_with("CUSTOM_TEXTURE", _upath("note.txt"))
	_check(str((FxAssetsScript.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "WRONG_TYPE", "truth txt wrong-type")
	layer = _layer_with("CUSTOM_TEXTURE", _upath("ok.png"))
	var h: Dictionary = FxAssetsScript.dependency_status("displacement.custom_texture", layer, data_dir)
	_check(str(h.get("state", "")) == "COMPLETE" and bool(h.get("needs_harvest", false)), "truth staged complete+harvest", str(h))
	# imported project texture: COMPLETE, never harvested
	var ri: Dictionary = FxAssetsScript.dependency_status("displacement.custom_texture", _layer_with("CUSTOM_TEXTURE", "res://assets/elements/fighter_beauty_test.png"), data_dir)
	_check(str(ri.get("state", "")) == "COMPLETE" and not bool(ri.get("needs_harvest", false)), "truth res-imported complete", str(ri))
	# directory: INVALID (never a texture)
	var rd: Dictionary = FxAssetsScript.dependency_status("displacement.custom_texture", _layer_with("CUSTOM_TEXTURE", "user://fx_asset_stage"), data_dir)
	_check(str(rd.get("state", "")) == "INVALID", "truth directory invalid", str(rd))
	# mask + influence + treatment requirement mapping
	var m: Dictionary = FxLookScript.new_layer("FX", "m")
	(m["mask"] as Dictionary)["enabled"] = true
	(m["mask"] as Dictionary)["source"] = "CUSTOM_MASK"
	_check(str((FxAssetsScript.dependency_status("mask.custom_mask", m, data_dir) as Dictionary).get("state", "")) == "MISSING", "truth mask required")
	(m["mask"] as Dictionary)["source"] = "FULL"
	_check(str((FxAssetsScript.dependency_status("mask.custom_mask", m, data_dir) as Dictionary).get("state", "")) == "NOT_REQUIRED", "truth mask full not-required")
	var f: Dictionary = FxLookScript.new_layer("FX", "f")
	(f["fx"] as Dictionary)["effect_mask_enabled"] = true
	_check(str((FxAssetsScript.dependency_status("fx.treatment_mask_path", f, data_dir) as Dictionary).get("state", "")) == "MISSING", "truth treatment required")

func _harvest() -> void:
	var prod = FxProductionScript.new()
	prod.data_dir = data_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	# user:// source outside data_dir gets imported + rewritten
	var r: Dictionary = FxAssetsScript.ensure_project_ref(_upath("ok.png"), data_dir)
	_check(bool(r.get("ok", false)), "harvest imports staged source", str(r.get("errors", [])))
	var ref := str(r.get("ref", ""))
	_check(ref.begins_with(data_dir), "harvest ref is project-local", ref)
	_check(FileAccess.file_exists(ref), "harvest copy exists on disk", ref)
	# second call with the harvested ref keeps it (no duplication)
	var r2: Dictionary = FxAssetsScript.ensure_project_ref(ref, data_dir)
	_check(bool(r2.get("ok", false)) and str(r2.get("ref", "")) == ref, "harvest keeps project-local ref", str(r2.get("ref", "")))
	# missing stays a clean failure (fail-closed, no silent fallback)
	var r3: Dictionary = FxAssetsScript.ensure_project_ref(_upath("ghost.png"), data_dir)
	_check(not bool(r3.get("ok", false)), "harvest missing fails closed", str(r3))

func _validation() -> void:
	# Pipeline truth (mirrors production.apply order): harvest FIRST, then
	# validate the harvested doc. Absolute authoring paths never reach
	# validation unharvested; missing files fail at the assets stage.
	var g: Dictionary = FxAssetsScript.ensure_project_ref(_upath("ghost.png"), data_dir)
	_check(not bool(g.get("ok", false)), "pipeline ghost fails at harvest", str(g))
	var c: Dictionary = FxAssetsScript.ensure_project_ref(_upath("corrupt.png"), data_dir)
	_check(bool(c.get("ok", false)), "pipeline corrupt harvests bytes", str(c.get("errors", [])))
	if bool(c.get("ok", false)):
		var lc := _layer_with("CUSTOM_TEXTURE", str(c.get("ref", "")))
		_check(not bool(FxLookScript.validate(_wrap_look(lc)).get("ok", false)), "pipeline corrupt fails validate", str(FxLookScript.validate(_wrap_look(lc)).get("errors", [])))
	var w: Dictionary = FxAssetsScript.ensure_project_ref(_upath("note.txt"), data_dir)
	_check(bool(w.get("ok", false)), "pipeline wrong-type harvests bytes", str(w.get("errors", [])))
	if bool(w.get("ok", false)):
		var lw := _layer_with("CUSTOM_TEXTURE", str(w.get("ref", "")))
		_check(not bool(FxLookScript.validate(_wrap_look(lw)).get("ok", false)), "pipeline wrong-type fails validate", str(FxLookScript.validate(_wrap_look(lw)).get("errors", [])))
	var r: Dictionary = FxAssetsScript.ensure_project_ref(_upath("ok.png"), data_dir)
	var l5 := _layer_with("CUSTOM_TEXTURE", str(r.get("ref", "")))
	_check(bool(FxLookScript.validate(_wrap_look(l5)).get("ok", false)), "pipeline harvested ref validates", str(FxLookScript.validate(_wrap_look(l5)).get("errors", [])))
	# required + empty still fails even without harvest
	var l1 := _layer_with("CUSTOM_TEXTURE", null)
	_check(not bool(FxLookScript.validate(_wrap_look(l1)).get("ok", false)), "validate rejects empty required")

func _atomicity() -> void:
	# Harvest atomicity (researcher 11-16 §6): harvested pool files are
	# content-addressed + immutable; a FAILED apply must leave persisted
	# Production docs/assignments byte-identical and must never modify an
	# already-referenced asset. An unreferenced orphan blob is tolerated.
	var prod = FxProductionScript.new()
	prod.data_dir = data_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	var look: Dictionary = _wrap_look(_layer_with("CUSTOM_TEXTURE", _upath("ok.png")))
	look["look_id"] = "ATOMIC"
	look["revision"] = 1
	var a1: Dictionary = prod.apply({"look": look})
	_check(bool(a1.get("ok", false)), "atomicity seed apply ok", str(a1.get("errors", [])))
	if not bool(a1.get("ok", false)):
		return
	var look_bytes: PackedByteArray = FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(prod.look_path("ATOMIC")))
	var asg_bytes: PackedByteArray = FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(prod.assignments_path()))
	var persisted: Dictionary = prod.load_look("ATOMIC")["doc"]
	var href := ""
	for l in (persisted.get("layers", []) as Array):
		var p = ((l as Dictionary).get("displacement", {}) as Dictionary).get("custom_texture", null)
		if p != null:
			href = str(p)
	# Production-ref invariant (§4): no user:// authoring source survives.
	_check(href != "" and not href.begins_with("user://fx_asset_stage") and href.begins_with(data_dir), "atomicity persisted ref project-local", href)
	var asset_bytes: PackedByteArray = FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(href))
	# Inject a later failure (revision rule): docs must stay byte-identical,
	# referenced asset untouched.
	var bad: Dictionary = _wrap_look(_layer_with("CUSTOM_TEXTURE", _upath("ok.png")))
	bad["look_id"] = "ATOMIC"
	bad["revision"] = 999
	var a2: Dictionary = prod.apply({"look": bad})
	_check(not bool(a2.get("ok", false)), "atomicity bad revision fails", str(a2.get("errors", [])))
	_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(prod.look_path("ATOMIC"))) == look_bytes, "atomicity look bytes stable")
	_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(prod.assignments_path())) == asg_bytes, "atomicity assignments bytes stable")
	_check(FileAccess.file_exists(href) and FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(href)) == asset_bytes, "atomicity referenced asset untouched")

func _wrap_look(layer: Dictionary) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look("TRUTH", "truth")
	look = FxLookScript.materialize(look)
	(look["layers"] as Array).append(layer)
	return look
