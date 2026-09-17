extends SceneTree
# R3 §8 CRASH PROBE (run 1 of 2). Sets up a known production state (look A +
# assignments), snapshots the exact bytes, then starts an apply of look B whose
# commit is terminated by an ABRUPT process kill at the stage named by
# FXLAB_CRASH_STAGE (before_first_commit / after_first_replace /
# during_second_replace / before_final_marker). The verify run then checks
# strict last-known-good recovery. Exit 2 = crash stage never reached.

func _init() -> void:
	var FxProductionScript = load("res://scripts/fx_vnext/fx_production.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")

	var prod = FxProductionScript.new()
	var data_override := OS.get_environment("NRCU_FX_DATA_DIR")
	if data_override != "":
		prod.data_dir = data_override
	prod.ensure_dirs()
	prod.recover_if_needed()

	var stage := OS.get_environment("FXLAB_CRASH_STAGE")
	var root := OS.get_environment("FXLAB_CRASH_DIR")
	var snap_dir := root.path_join("snapshot")
	DirAccess.make_dir_recursive_absolute(snap_dir)

	# ---- baseline state: look A bound to ice_mage/echo --------------------------
	var look_a: Dictionary = FxLookScript.new_look("CRASH_LOOK_A", "crash A")
	((look_a["layers"][0] as Dictionary)["fx"] as Dictionary)["dither"] = 1.0
	var asg_doc: Dictionary = FxResolverScript.new_assignments()
	var binding_id: String = FxResolverScript.upsert_binding(asg_doc, {"fighter_id": "ice_mage", "element_role": "echo"}, "CRASH_LOOK_A", "crash baseline")
	var applied: Dictionary = prod.apply({"look": look_a, "assignments": asg_doc})
	if not bool(applied.get("ok", false)):
		print("[CRASH-PROBE] baseline apply failed: ", applied.get("errors", []))
		quit(3)
		return

	# ---- snapshot the exact bytes ------------------------------------------------
	var look_path: String = prod.look_path("CRASH_LOOK_A")
	var asg_path: String = prod.assignments_path()
	_snapshot(look_path, snap_dir.path_join("look_a.json"))
	_snapshot(asg_path, snap_dir.path_join("assignments.json"))
	print("[CRASH-PROBE] baseline ready (binding=%s) stage=%s" % [binding_id, stage])

	# ---- candidate: look B = updated A (same id, distinctive change) -------------
	var look_b: Dictionary = look_a.duplicate(true)
	look_b["revision"] = int(look_a.get("revision", 1)) + 1
	((look_b["layers"][0] as Dictionary)["fx"] as Dictionary)["rgb"] = 1.0
	((look_b["layers"][0] as Dictionary)["fx"] as Dictionary)["rgb_shift_amount"] = 20.0

	# ---- crash apply --------------------------------------------------------------
	print("[CRASH-PROBE] starting crashing apply at stage=%s" % stage)
	var result: Dictionary = prod.apply({"look": look_b, "assignments": asg_doc, "crash_at": stage})
	# Reaching here means the crash point was never triggered.
	print("[CRASH-PROBE] ERROR: crash stage never reached, apply returned: ", result)
	quit(2)

func _snapshot(from_path: String, to_path: String) -> void:
	var file := FileAccess.open(from_path, FileAccess.READ)
	if file == null:
		print("[CRASH-PROBE] snapshot failed for ", from_path)
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var out := FileAccess.open(to_path, FileAccess.WRITE)
	if out != null:
		out.store_buffer(bytes)
		out.close()
