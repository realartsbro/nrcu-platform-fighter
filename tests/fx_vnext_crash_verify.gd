extends SceneTree
# R3 §8 CRASH VERIFY (run 2 of 2). Runs in a FRESH process after the probe was
# abruptly killed mid-commit. Checks strict last-known-good recovery:
#   1. the transaction marker was observed on disk before recovery (crash really
#      interrupted a commit - stages before the first replacement may not have
#      reached the marker; both outcomes are recorded truthfully),
#   2. boot recovery (production.recover_if_needed(), exactly what the shell and
#      VS runtime call) restores EVERY byte to the pre-commit snapshot,
#   3. no *.tmp / *.txn.json leftovers remain, nothing tmp-like is loaded,
#   4. loads are clean, the binding still resolves to CRASH_LOOK_A,
#   5. a follow-up apply after recovery succeeds (system not wedged).

var checks: Array = []
var failures: int = 0

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _init() -> void:
	var FxProductionScript = load("res://scripts/fx_vnext/fx_production.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")

	var prod = FxProductionScript.new()
	var data_override := OS.get_environment("NRCU_FX_DATA_DIR")
	if data_override != "":
		prod.data_dir = data_override
	var stage := OS.get_environment("FXLAB_CRASH_STAGE")
	var root := OS.get_environment("FXLAB_CRASH_DIR")
	var snap_dir := root.path_join("snapshot")

	var look_path: String = prod.look_path("CRASH_LOOK_A")
	var asg_path: String = prod.assignments_path()
	var marker_path: String = prod.recovery_dir().path_join(".txn.json")
	var marker_before := FileAccess.file_exists(marker_path)
	var recovered_from_stage := _read_text(root.path_join("crashflag.txt"))

	# 1. crash actually interrupted a commit (probe wrote its crash flag)
	_check(recovered_from_stage.contains(stage), "probe crashed at the requested stage", recovered_from_stage.strip_edges())

	# 2. boot recovery (as the real app performs it)
	var recovery: Dictionary = prod.recover_if_needed()
	var marker_after := FileAccess.file_exists(marker_path)

	# 3. strict last-known-good: both files byte-identical to the snapshot
	var look_now := _read_bytes(look_path)
	var asg_now := _read_bytes(asg_path)
	var look_snap := _read_bytes(snap_dir.path_join("look_a.json"))
	var asg_snap := _read_bytes(snap_dir.path_join("assignments.json"))
	_check(look_now == look_snap, "look file restored byte-identical to last-known-good", "bytes=%d" % look_now.size())
	_check(asg_now == asg_snap, "assignments file restored byte-identical to last-known-good", "bytes=%d" % asg_now.size())
	_check(not marker_after, "transaction marker cleared after recovery")
	_check(not FileAccess.file_exists(look_path + ".tmp") and not FileAccess.file_exists(asg_path + ".tmp"), "no *.tmp leftovers")

	# 4. loads are clean and resolve to the recovered look
	var asg_load: Dictionary = prod.load_assignments()
	_check(bool(asg_load.get("ok", false)), "assignments load after recovery", str(asg_load.get("errors", [])))
	var resolved: Dictionary = FxResolverScript.resolve(asg_load.get("doc", {}), {"fighter_id": "ice_mage", "element_role": "echo"})
	_check(str(resolved.get("look_id", "")) == "CRASH_LOOK_A", "binding still resolves to CRASH_LOOK_A", str(resolved.get("look_id", "")))

	# 5. follow-up apply works
	var look_c: Dictionary = FxLookScript.new_look("CRASH_LOOK_C", "crash C")
	var applied: Dictionary = prod.apply({"look": look_c})
	_check(bool(applied.get("ok", false)), "follow-up apply succeeds after recovery", str(applied.get("errors", [])))

	var out := {
		"stage": stage,
		"marker_before_recovery": marker_before,
		"recover_if_needed": recovery,
		"checks": checks.size(),
		"failures": failures,
		"status": "PASS" if failures == 0 else "FAIL",
	}
	var f := FileAccess.open(root.path_join("verify_%s.json" % stage), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("[CRASH-VERIFY] stage=%s checks=%d failures=%d" % [stage, checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
