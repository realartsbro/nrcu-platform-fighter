extends SceneTree
# Migration review workflow — backend authority (headless).
# Queue → notes → repair → ack-gated approval → persist → reopen → resolve.

const FxMigrationScript := preload("res://scripts/fx_vnext/fx_migration.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	var prod_dir := "user://vnext_test_review_prod"
	var draft_dir := "user://vnext_test_review_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	prod.ensure_dirs()
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir

	var fixture := _load_json("res://tests/fixtures/vnext/fixture_fx_looks_v03.json")
	_check(not fixture.is_empty(), "fixture loads")
	var migration = FxMigrationScript.new()
	var result: Dictionary = migration.migrate_looks_document(fixture)
	_check(bool(result.get("ok", false)), "migration ok", str(result.get("errors", [])))
	for look_id in (result.get("looks", {}) as Dictionary).keys():
		var applied: Dictionary = prod.apply({"look": (result["looks"] as Dictionary)[look_id]})
		_check(bool(applied.get("ok", false)), "migrated look stored: " + str(look_id), str(applied.get("errors", [])))

	# ---- queue ------------------------------------------------------------
	var queue: Array = prod.list_migration_review_look_ids()
	_check(queue.has("BASELINE_MARK_FRINGE"), "mark is queued for review", str(queue))
	_check(not queue.has("BASELINE_ECHO_DITHER_RGB"), "clean echo is not queued")
	_check(not queue.has("BASELINE_PRIMARY_FLOW_BLUR") == false, "primary queued", str(queue))

	# ---- notes ------------------------------------------------------------
	var review: Dictionary = prod.load_migration_review("BASELINE_MARK_FRINGE")
	_check(bool(review.get("ok", false)), "review loads", str(review.get("errors", [])))
	_check(not (review.get("notes", []) as Array).is_empty(), "review carries notes", str(review.get("notes", [])))
	var clean_review: Dictionary = prod.load_migration_review("BASELINE_ECHO_DITHER_RGB")
	_check(not bool(clean_review.get("ok", false)), "clean look has no review", str(clean_review.get("errors", [])))

	# ---- approval gate ----------------------------------------------------
	var rev_before := int((review["doc"] as Dictionary).get("revision", 0))
	var denied: Dictionary = prod.approve_migration_review("BASELINE_MARK_FRINGE", "   ")
	_check(not bool(denied.get("ok", false)), "empty acknowledgement never approves")
	_check(prod.list_migration_review_look_ids().has("BASELINE_MARK_FRINGE"), "still queued after denied approval")

	# ---- repair -----------------------------------------------------------
	var doc: Dictionary = review["doc"]
	var layer_id := str((doc["layers"] as Array)[1].get("layer_id", ""))
	var repair: Dictionary = prod.save_migration_repair("BASELINE_MARK_FRINGE", {"layers": {layer_id: {"fx": {"color_blur": 2.5}}}})
	_check(bool(repair.get("ok", false)), "repair persists", str(repair.get("errors", [])))
	var reloaded: Dictionary = prod.load_look("BASELINE_MARK_FRINGE")
	_check(absf(float((((reloaded["doc"] as Dictionary)["layers"] as Array)[1] as Dictionary)["fx"].get("color_blur", -1.0)) - 2.5) < 0.0001, "repair value readable after reopen")
	_check(str((reloaded["doc"] as Dictionary).get("status", "")) == "MIGRATION_REVIEW_REQUIRED", "repair keeps REVIEW status")
	_check(int((reloaded["doc"] as Dictionary).get("revision", 0)) == rev_before + 1, "repair bumps revision by 1")

	# ---- approval ---------------------------------------------------------
	var approved: Dictionary = prod.approve_migration_review("BASELINE_MARK_FRINGE", "flow note verified against source; masks reattached")
	_check(bool(approved.get("ok", false)), "approval persists", str(approved.get("errors", [])))
	var final: Dictionary = prod.load_look("BASELINE_MARK_FRINGE")
	_check(str((final["doc"] as Dictionary).get("status", "")) == "PRODUCTION", "approved look is PRODUCTION")
	_check(str((((final["doc"] as Dictionary).get("metadata", {}) as Dictionary).get("review", {}) as Dictionary).get("acknowledged", "")) != "", "acknowledgement metadata persisted")
	_check(not prod.list_migration_review_look_ids().has("BASELINE_MARK_FRINGE"), "approved look leaves the queue")

	# ---- session + assignment resolve -------------------------------------
	var asg: Dictionary = migration.migrate_assignments(_assignments_v01())
	_check(bool(asg.get("ok", false)), "assignments migrate")
	var asg_applied: Dictionary = prod.apply({"assignments": asg["doc"]})
	_check(bool(asg_applied.get("ok", false)), "assignments stored", str(asg_applied.get("errors", [])))
	var session = FxSessionScript.new(prod, drafts)
	var opened: Dictionary = session.open_target("mark_left", {"fighter_id": "ice_mage", "element_role": "vs_mark", "visual_side": "left", "mode_family": "1v1", "stage_id": "dojo"}, "sig-review", "mark")
	_check(bool(opened.get("ok", false)), "session opens over approved look", str(opened))
	_check(str(session.base.get("look_id", "")) == "BASELINE_MARK_FRINGE", "approved look resolves in session", str(session.base))

	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	print("[FX-MIGRATION-REVIEW] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _assignments_v01() -> Dictionary:
	return {
		"schema": "NRCU_VS_FX_ASSIGNMENTS_V1",
		"bindings": [
			{"look_id": "BASELINE_MARK_FRINGE", "selector": {"fighter_id": "ice_mage", "element_role": "vs_mark", "visual_side": "left"}},
		],
	}

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _wipe_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
