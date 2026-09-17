extends SceneTree
# Draft/session authority regressions DR-01..DR-08 (headless).
# Each check is named for its finding card repro.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var checks: Array = []
var failures := 0
var prod
var drafts
var prod_dir := "user://vnext_test_draft_authority"
var draft_dir := "user://vnext_test_draft_authority_drafts"

func _init() -> void:
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	prod.ensure_dirs()
	drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	drafts.ensure_dirs()
	_seed()
	_dr01_invalid_draft_never_poisons()
	_dr02_atomic_writes()
	_dr03_clean_draft_never_shadows_production()
	_dr04_draft_keeps_shared_protection()
	_dr05_revert_clears_shared_draft()
	_dr06_revert_reconciles_authority()
	_dr07_stash_failure_surfaces()
	_dr08_retire_resolves_forward()
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	print("[FX-DRAFT-AUTHORITY] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _seed() -> void:
	_check(bool(prod.apply({"look": _look("SHARED_LOOK", 1)})["ok"]), "DR seed: shared look stored")
	_check(bool(prod.apply({"look": _look("SOLO_LOOK", 1)})["ok"]), "DR seed: solo look stored")
	var asg: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(asg, _ctx("t1"), "SHARED_LOOK", "")
	FxResolverScript.upsert_binding(asg, _ctx("t2"), "SHARED_LOOK", "")
	FxResolverScript.upsert_binding(asg, _ctx("solo"), "SOLO_LOOK", "")
	_check(bool(prod.apply({"assignments": asg})["ok"]), "DR seed: assignments stored")

func _ctx(tag: String) -> Dictionary:
	return {"fighter_id": "ice_mage", "element_role": tag, "visual_side": "left", "mode_family": "1v1", "stage_id": "dojo"}

func _session() -> RefCounted:
	return FxSessionScript.new(prod, drafts)

func _dr01_invalid_draft_never_poisons() -> void:
	var session = _session()
	session.open_target("k1", _ctx("solo"), "sig-dr01", "solo")
	# Syntactically valid JSON, semantically wrong nested type.
	var bad_record := {"kind": "target", "target_signature": "sig-dr01", "base_revision": 1, "look": {"look_id": "X", "layers": "not-an-array"}, "dirty": true, "updated_unix": 1}
	var f := FileAccess.open(drafts.target_path("sig-dr01"), FileAccess.WRITE)
	f.store_string(JSON.stringify(bad_record))
	f.close()
	var reopened: Dictionary = session.open_target("k1", _ctx("solo"), "sig-dr01", "solo")
	_check(str(reopened.get("opened", "")) != "draft", "DR-01 invalid draft not opened as draft", str(reopened.get("opened", "")))
	_check(FileAccess.file_exists(drafts.target_path("sig-dr01")), "DR-01 invalid draft preserved on disk")
	_check(str(session.base.get("look_id", "")) == "SOLO_LOOK", "DR-01 authority opened instead", str(session.base))
	drafts.clear_target("sig-dr01")

func _dr02_atomic_writes() -> void:
	var session = _session()
	session.open_target("k1", _ctx("solo"), "sig-dr02", "solo")
	var saved: Dictionary = session.stash()
	_check(bool(saved.get("ok", false)), "DR-02 stash succeeds", str(saved.get("errors", [])))
	var dir := DirAccess.open(ProjectSettings.globalize_path(draft_dir.path_join("targets")))
	var litter := []
	if dir != null:
		for name in dir.get_files():
			if str(name).ends_with(".tmp"):
				litter.append(name)
	_check(litter.is_empty(), "DR-02 no temp litter after write", str(litter))
	var back: Dictionary = drafts.load_target("sig-dr02")
	_check(bool(back.get("ok", false)) and bool(back.get("struct_ok", false)), "DR-02 written record reads back valid")
	drafts.clear_target("sig-dr02")

func _dr03_clean_draft_never_shadows_production() -> void:
	var session = _session()
	session.open_target("k1", _ctx("solo"), "sig-dr03", "solo")
	drafts.save_target("sig-dr03", session.look, 1, false)
	var rev2: Dictionary = (prod.load_look("SOLO_LOOK") as Dictionary)["doc"]
	rev2["revision"] = 2
	_check(bool(prod.apply({"look": rev2})["ok"]), "DR-03 production advanced to rev2")
	var reopened: Dictionary = session.open_target("k1", _ctx("solo"), "sig-dr03", "solo")
	_check(str(reopened.get("opened", "")) == "production", "DR-03 current authority wins over clean parked draft", str(reopened.get("opened", "")))
	_check(int(session.base.get("revision", 0)) == 2, "DR-03 base revision is current", str(session.base))
	_check(FileAccess.file_exists(drafts.target_path("sig-dr03")), "DR-03 parked draft kept on disk")
	drafts.clear_target("sig-dr03")

func _dr04_draft_keeps_shared_protection() -> void:
	var session = _session()
	session.open_target("k1", _ctx("t1"), "sig-dr04", "t1")
	_check(bool(drafts.save_target("sig-dr04", session.look, 1, true).get("ok", false)), "DR-04 draft parked")
	var reopened: Dictionary = session.open_target("k1", _ctx("t1"), "sig-dr04", "t1")
	_check(str(reopened.get("opened", "")) == "draft", "DR-04 dirty draft still opens", str(reopened.get("opened", "")))
	_check(str(session.mode) == "SHARED_PROTECTED", "DR-04 shared protection survives draft reopen", str(session.mode))
	drafts.clear_target("sig-dr04")

func _dr05_revert_clears_shared_draft() -> void:
	var session = _session()
	session.open_target("k1", _ctx("t1"), "sig-dr05", "t1")
	_check(bool(session.edit_shared().get("ok", false)), "DR-05 edit-shared opens", str(session.mode))
	_check(bool(drafts.save_shared("SHARED_LOOK", 1, session.look, true).get("ok", false)), "DR-05 shared draft exists")
	var reverted: Dictionary = session.revert_draft()
	_check(bool(reverted.get("ok", false)), "DR-05 revert succeeds")
	_check(drafts.list_shared().is_empty(), "DR-05 shared draft cleared", str(drafts.list_shared()))
	var reopened: Dictionary = session.open_target("k1", _ctx("t1"), "sig-dr05", "t1")
	_check(str(reopened.get("opened", "")) == "production", "DR-05 no shared draft silently reopens", str(reopened.get("opened", "")))

func _dr06_revert_reconciles_authority() -> void:
	var session = _session()
	session.open_target("k1", _ctx("solo"), "sig-dr06", "solo")
	drafts.save_target("sig-dr06", session.look, 1, true)
	var rev3: Dictionary = (prod.load_look("SOLO_LOOK") as Dictionary)["doc"]
	var cur_rev := int(rev3.get("revision", 1))
	rev3["revision"] = cur_rev + 1
	_check(bool(prod.apply({"look": rev3})["ok"]), "DR-06 production advanced")
	var reverted: Dictionary = session.revert_draft()
	_check(bool(reverted.get("ok", false)), "DR-06 revert succeeds")
	_check(int(session.base.get("revision", 0)) == cur_rev + 1, "DR-06 base revision reconciled", str(session.base))
	_check(str(session.base.get("kind", "")) == "production", "DR-06 base kind reconciled", str(session.base))
	drafts.clear_target("sig-dr06")

func _dr07_stash_failure_surfaces() -> void:
	# Deterministic write failure: the store root is nested under a FILE, so
	# every directory creation and file open must fail.
	var blocker := ProjectSettings.globalize_path(draft_dir) + "-blocker"
	var bf := FileAccess.open(blocker, FileAccess.WRITE)
	if bf != null:
		bf.store_string("not a directory")
		bf.close()
	var bad_drafts = FxDraftsScript.new()
	bad_drafts.base_dir = "user://vnext_test_draft_authority_drafts-blocker/sub"
	var session = FxSessionScript.new(prod, bad_drafts)
	session.open_target("k1", _ctx("solo"), "sig-dr07", "solo")
	var stashed: Dictionary = session.stash()
	_check(not bool(stashed.get("ok", false)), "DR-07 stash failure surfaces, never silent", str(stashed))
	DirAccess.remove_absolute(blocker)

func _dr08_retire_resolves_forward() -> void:
	_check(bool(prod.apply({"look": _look("DOOMED_LOOK", 1)})["ok"]), "DR-08 doomed look stored")
	_check(bool(prod.apply({"look": _look("HEIR_LOOK", 1)})["ok"]), "DR-08 heir look stored")
	var asg: Dictionary = prod.load_assignments()["doc"]
	FxResolverScript.upsert_binding(asg, _ctx("doomed"), "DOOMED_LOOK", "")
	_check(bool(prod.apply({"assignments": asg})["ok"]), "DR-08 doomed binding stored")
	var session = _session()
	session.open_target("k1", _ctx("doomed"), "sig-dr08", "doomed")
	_check(str(session.base.get("look_id", "")) == "DOOMED_LOOK", "DR-08 session opens doomed look")
	var retired: Dictionary = prod.retire_look("DOOMED_LOOK", "replace", "HEIR_LOOK")
	_check(bool(retired.get("ok", false)), "DR-08 replace-retire succeeds", str(retired.get("errors", [])))
	var reopened: Dictionary = session.open_target("k1", _ctx("doomed"), "sig-dr08b", "doomed")
	_check(str(session.base.get("look_id", "")) == "HEIR_LOOK", "DR-08 session resolves forward to heir", str(session.base))

func _look(look_id: String, revision: int) -> Dictionary:
	var doc: Dictionary = FxLookScript.new_look(look_id, look_id)
	doc["revision"] = revision
	return doc

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
