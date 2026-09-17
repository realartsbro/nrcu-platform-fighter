extends SceneTree
# Extension policy — forward-compatible x_* fields survive the full
# materialize → validate_input → apply → reload path; legacy aliases and
# malformed x_ keys never persist.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	var prod_dir := "user://vnext_test_extension_prod"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	prod.ensure_dirs()

	var doc: Dictionary = FxLookScript.materialize(FxLookScript.new_look("EXT_POLICY", "Extensions"))
	(doc["layers"][0] as Dictionary)["fx"] = {"x_show_id": "desk-7", "x_vendor_gain": 1.5}
	var gate: Dictionary = FxLookScript.validate_input(doc)
	_check(bool(gate.get("ok", false)), "extensions pass input gate", str(gate.get("errors", [])))
	var applied: Dictionary = prod.apply({"look": doc})
	_check(bool(applied.get("ok", false)), "extension doc applies", str(applied.get("errors", [])))
	var reloaded: Dictionary = prod.load_look("EXT_POLICY")
	_check(bool(reloaded.get("ok", false)), "extension doc reloads")
	var fx: Dictionary = ((reloaded["doc"] as Dictionary)["layers"] as Array)[0]["fx"]
	_check(str(fx.get("x_show_id", "")) == "desk-7" and absf(float(fx.get("x_vendor_gain", 0.0)) - 1.5) < 0.0001, "extensions survive persist round-trip", str(fx.get("x_show_id", null)))
	_check(bool(FxLookScript.validate_input(reloaded["doc"])["ok"]), "reloaded doc passes input gate")

	var legacy: Dictionary = FxLookScript.materialize(FxLookScript.new_look("EXT_LEGACY", "Legacy"))
	(legacy["layers"][0] as Dictionary)["fx"] = {"rgb_shift": 5.0}
	var refused: Dictionary = prod.apply({"look": legacy})
	_check(not bool(refused.get("ok", false)) and str(refused.get("stage", "")) == "validate-input", "legacy alias fails closed at apply", str(refused.get("errors", [])))

	var malformed: Dictionary = FxLookScript.materialize(FxLookScript.new_look("EXT_BAD", "Bad"))
	(malformed["layers"][0] as Dictionary)["fx"] = {"x_NoGood": 1.0}
	var refused_bad: Dictionary = prod.apply({"look": malformed})
	_check(not bool(refused_bad.get("ok", false)), "malformed x_ key fails closed at apply")

	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	print("[FX-EXTENSION] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
