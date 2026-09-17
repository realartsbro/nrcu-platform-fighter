extends SceneTree
# Round-2 Finding 5: apply must be a REAL transaction. After ANY injected failure
# (before first commit / after first replacement / during second replacement /
# before the final marker) Production must be byte- AND semantically identical
# to its previous valid state (look revision, assignments, resolver output).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")

var checks: Array = []
var failures: int = 0
var prod
var out_dir: String
var prod_dir := "user://vnext_txn_prod"

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/transaction")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir

	var ctx := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}

	# ---- baseline: valid production state ---------------------------------------
	var look: Dictionary = _make_look(1, "Ice Echo r1")
	var assignments: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(assignments, ctx.duplicate(), "ICE_MAGE_ECHO_LEFT", "")
	var applied: Dictionary = prod.apply({"look": look, "assignments": assignments})
	_check(bool(applied["ok"]), "baseline apply succeeds", str(applied.get("errors", [])))

	var look_bytes_before := _read_file_bytes(prod.look_path("ICE_MAGE_ECHO_LEFT"))
	var asg_bytes_before := _read_file_bytes(prod.assignments_path())
	var res_before: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], ctx)
	_check(str(res_before.get("status", "")) == "ASSIGNED" and str(res_before.get("look_id", "")) == "ICE_MAGE_ECHO_LEFT", "baseline resolver output", str(res_before))

	# ---- the four mandatory injection points -------------------------------------
	var look2: Dictionary = _make_look(2, "Ice Echo r2")
	var assignments2: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(assignments2, ctx.duplicate(), "ICE_MAGE_ECHO_LEFT", "note r2")

	for inject in ["before_first_commit", "after_first_replace", "during_second_replace", "before_final_marker"]:
		var attempt: Dictionary = prod.apply({"look": look2, "assignments": assignments2, "inject_failure": inject})
		_check(not bool(attempt["ok"]), "injected failure is reported: " + inject, str(attempt))
		_check(bool(attempt.get("rolled_back", false)), "rollback executed: " + inject)
		var look_now := _read_file_bytes(prod.look_path("ICE_MAGE_ECHO_LEFT"))
		var asg_now := _read_file_bytes(prod.assignments_path())
		_check(look_now == look_bytes_before, "look file byte-identical after: " + inject)
		_check(asg_now == asg_bytes_before, "assignments file byte-identical after: " + inject)
		var loaded_now: Dictionary = prod.load_look("ICE_MAGE_ECHO_LEFT")
		_check(bool(loaded_now["ok"]) and int(loaded_now["doc"].get("revision", 0)) == 1, "look revision stays 1 after: " + inject)
		var res_now: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], ctx)
		_check(str(res_now.get("status", "")) == str(res_before.get("status", "")) and str(res_now.get("look_id", "")) == str(res_before.get("look_id", "")), "resolver output unchanged after: " + inject, str(res_now))
		_check(not FileAccess.file_exists(prod.look_path("ICE_MAGE_ECHO_LEFT") + ".tmp") and not FileAccess.file_exists(prod.assignments_path() + ".tmp"), "no temp leftovers after: " + inject)

	# ---- then the real apply without injection lands -----------------------------
	var final_apply: Dictionary = prod.apply({"look": look2, "assignments": assignments2})
	_check(bool(final_apply["ok"]), "clean apply lands after injected failures", str(final_apply.get("errors", [])))
	var loaded_final: Dictionary = prod.load_look("ICE_MAGE_ECHO_LEFT")
	_check(bool(loaded_final["ok"]) and int(loaded_final["doc"].get("revision", 0)) == 2, "revision advanced to 2")

	var f := FileAccess.open(out_dir.path_join("summary_transaction_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[TRANSACTION] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _make_look(revision: int, name: String) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look("ICE_MAGE_ECHO_LEFT", name)
	look["revision"] = revision
	var fx: Dictionary = FxLookScript.new_layer("FX", "Echo rgb")
	fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 12.0 + float(revision)}
	look["layers"].append(fx)
	return look

func _read_file_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes

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
