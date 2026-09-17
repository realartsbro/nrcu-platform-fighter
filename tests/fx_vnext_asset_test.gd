extends SceneTree
# Round-2 Finding 15: external masks/textures are imported into project-local
# production assets at apply time; the persisted Look never references an
# absolute external path, and works after the original file is gone.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")

var checks: Array = []
var failures: int = 0
var prod_dir := "user://vnext_asset_prod"

func _init() -> void:
	var out_dir := OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/assets")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir

	# ---- 1. external mask file on disk (outside the project) --------------------
	var ext_dir := OS.get_environment("TEMP").replace("\\", "/") + "/fxlab_asset_src"
	DirAccess.make_dir_recursive_absolute(ext_dir)
	var ext_path := ext_dir + "/custom_mask.png"
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var inside := Vector2(x - 32, y - 32).length() < 28.0
			img.set_pixel(x, y, Color(1, 1, 1, 1) if inside else Color(0, 0, 0, 0))
	img.save_png(ext_path)
	_check(FileAccess.file_exists(ext_path), "external mask exists on disk", ext_path)

	# ---- 2. apply imports it into project-local production assets ---------------
	var look: Dictionary = FxLookScript.new_look("MASK_LOOK", "Mask Look")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Custom masked")
	layer["mask"] = {"custom_mask": ext_path}
	look["layers"].append(layer)
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "apply imports the external mask", str(applied.get("errors", [])))
	var loaded: Dictionary = prod.load_look("MASK_LOOK")
	_check(bool(loaded["ok"]), "look reloads")
	var stored_ref := str(((loaded["doc"]["layers"][1] as Dictionary).get("mask", {}) as Dictionary).get("custom_mask", ""))
	_check(stored_ref.begins_with(prod_dir + "/assets/"), "stored ref is project-local", stored_ref)
	_check(not stored_ref.contains("Users") and not stored_ref.contains("AppData") and not stored_ref.contains("C:"), "stored ref has no machine path", stored_ref)
	var abs_stored := ProjectSettings.globalize_path(stored_ref)
	_check(FileAccess.file_exists(stored_ref), "imported asset exists")
	var src_bytes := FileAccess.get_file_as_bytes(ext_path)
	var dst_bytes := FileAccess.get_file_as_bytes(abs_stored)
	_check(src_bytes == dst_bytes, "imported bytes identical to source")

	# ---- 3. the original external file disappears --------------------------------
	DirAccess.remove_absolute(ext_path)
	_check(not FileAccess.file_exists(ext_path), "external original removed")
	var reload: Dictionary = prod.load_look("MASK_LOOK")
	_check(bool(reload["ok"]), "look still loads without the original")
	_check(bool(FxLookScript.validate(reload["doc"])["ok"]), "look validates without the original")
	var mask_img := Image.load_from_file(abs_stored)
	_check(mask_img != null and mask_img.get_size() == Vector2i(64, 64), "imported mask usable", str(mask_img.get_size()) if mask_img != null else "null")

	# ---- 4. re-apply does not re-import or break ---------------------------------
	var reloaded: Dictionary = reload["doc"]
	reloaded["revision"] = int(reloaded.get("revision", 0)) + 1
	var reapplied: Dictionary = prod.apply({"look": reloaded})
	_check(bool(reapplied["ok"]), "re-apply of the migrated look succeeds", str(reapplied.get("errors", [])))
	var again: Dictionary = prod.load_look("MASK_LOOK")
	var again_ref := str(((again["doc"]["layers"][1] as Dictionary).get("mask", {}) as Dictionary).get("custom_mask", ""))
	_check(again_ref == stored_ref, "asset ref stable across re-apply", "%s vs %s" % [again_ref, stored_ref])

	# ---- 5. missing external at apply is rejected clear --------------------------
	var look2: Dictionary = FxLookScript.new_look("MASK_LOOK_2", "Mask Look 2")
	var layer2: Dictionary = FxLookScript.new_layer("FX", "Broken mask")
	layer2["mask"] = {"custom_mask": ext_dir + "/does_not_exist.png"}
	look2["layers"].append(layer2)
	var rejected: Dictionary = prod.apply({"look": look2})
	_check(not bool(rejected["ok"]), "missing external rejected", str(rejected.get("errors", [])))
	_check(str(rejected.get("stage", "")) == "assets", "rejection names the assets stage", str(rejected.get("stage", "")))

	# ---- 6. a missing project asset is a clear diagnostic ------------------------
	var look3: Dictionary = FxLookScript.new_look("MASK_LOOK_3", "Mask Look 3")
	var layer3: Dictionary = FxLookScript.new_layer("FX", "Vanished")
	layer3["mask"] = {"custom_mask": "res://nrcu_fx_data/assets/missing_xyz.png"}
	look3["layers"].append(layer3)
	var diag: Dictionary = FxLookScript.validate(look3)
	_check(not bool(diag["ok"]), "missing project asset is an invalid state")
	var diag_text := str(diag["errors"])
	_check(diag_text.contains("does not exist"), "diagnostic names the missing asset", diag_text.substr(0, 100))

	var f := FileAccess.open(out_dir.path_join("summary_asset_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL", "stored_ref": stored_ref}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[ASSET] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
