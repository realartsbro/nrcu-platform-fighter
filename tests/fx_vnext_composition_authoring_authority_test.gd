extends SceneTree
# P0 composition authoring authority regressions.
# First tracer: a persisted composition must reopen through composition authority,
# never through the assignment resolver or a fighter Look.

const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

var checks := 0
var failures := 0

func _init() -> void:
	var production_dir := "user://vnext_test_composition_authoring_production"
	var draft_dir := "user://vnext_test_composition_authoring_drafts"
	_wipe_dir(ProjectSettings.globalize_path(production_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	var production = FxProductionScript.new()
	production.data_dir = production_dir
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	var session = FxSessionScript.new(production, drafts)

	var recipe_id := FxRecipesScript.CLASH_OVERDRIVE
	var composition: Dictionary = FxRecipesScript.instantiate_composition(recipe_id, "active")["doc"]
	composition["status"] = "PRODUCTION"
	(composition["metadata"] as Dictionary)["recipe_id"] = recipe_id
	_check(bool(production.apply({"composition": composition}).get("ok", false)), "composition seed applies")

	# The composition context is intentionally also present in the assignment
	# document as a trap: composition opening must not consult it.
	var ctx := {"target_key": "composition", "element_id": "composition", "element_role": "composition", "mode_family": "1v1", "stage_id": "debug"}
	var signature := "composition||composition||||1v1|debug"
	var opened: Dictionary = session.open_target("composition", ctx, signature, "composition")
	_check(str(opened.get("opened", "")) == "production", "composition opens persisted production authority", str(opened))
	_check(str(session.mode) == "EDIT_COMPOSITION", "composition session uses dedicated edit mode", str(session.mode))
	_check(str((session.look.get("metadata", {}) as Dictionary).get("recipe_id", "")) == recipe_id, "composition editor carries composition recipe metadata", str(session.look.get("metadata", {})))
	_check(str(session.look.get("name", "")) != "Untitled Design", "composition is not a neutral fighter Look", str(session.look.get("name", "")))
	_check(session.assignment_selector().is_empty(), "composition has no assignment selector")
	_check(not bool(session.set_assignment_scope("ROLE").get("ok", false)), "composition rejects assignment scope")
	_check(not bool(session.set_styling(false).get("ok", false)), "composition rejects styling assignment")
	_check(not bool(session.unassign_target().get("ok", false)), "composition rejects unassign")
	_check(not bool(session.make_unique().get("ok", false)), "composition rejects make unique")

	var applied: Dictionary = session.apply()
	_check(bool(applied.get("ok", false)), "composition production apply succeeds", str(applied))
	var persisted: Dictionary = production.load_composition()
	_check(bool(persisted.get("ok", false)) and int((persisted.get("doc", {}) as Dictionary).get("revision", 0)) == 2, "composition production revision increments")
	_check(str(session.base.get("kind", "")) == "composition" and int(session.base.get("revision", 0)) == 2 and not session.dirty, "apply reconciles composition base to persisted authority", str(session.base))
	_check(session.composition == persisted.get("doc", {}), "apply leaves a canonical composition snapshot in session")

	session.close_target()
	var reopened: Dictionary = session.open_target("composition", ctx, signature, "composition")
	_check(str(reopened.get("opened", "")) in ["draft", "production"], "composition reopens through composition authority after close", str(reopened))
	_check(session.composition == persisted.get("doc", {}), "close/reopen canonical session composition equals persisted composition")

	# A clean parked composition snapshot is only eligible at its base revision.
	var newer: Dictionary = persisted.get("doc", {}).duplicate(true)
	newer["revision"] = 3
	newer["status"] = "PRODUCTION"
	_check(bool(production.apply({"composition": newer}).get("ok", false)), "newer composition production revision applies")
	_check(bool(drafts.save_composition(signature, newer, 2, false).get("ok", false)), "stale clean composition draft saves")
	session.close_target()
	var stale_opened: Dictionary = session.open_target("composition", ctx, signature, "composition")
	_check(str(stale_opened.get("opened", "")) == "production", "stale clean composition draft loses to newer production", str(stale_opened))
	_check(not bool(drafts.load_composition(signature).get("record", {}).get("dirty", true)), "stale clean composition draft remains on disk")
	_check(session.composition == production.load_composition().get("doc", {}), "newer production composition is canonical after stale draft")

	var dirty_draft: Dictionary = newer.duplicate(true)
	dirty_draft["name"] = "Dirty Scene Draft"
	_check(bool(drafts.save_composition(signature, dirty_draft, 2, true).get("ok", false)), "dirty composition draft saves explicitly")
	session.close_target()
	var dirty_opened: Dictionary = session.open_target("composition", ctx, signature, "composition")
	_check(str(dirty_opened.get("opened", "")) == "draft" and session.dirty, "dirty composition draft remains authoritative", str(dirty_opened))
	_check(str(session.composition.get("name", "")) == "Dirty Scene Draft", "dirty composition draft content survives reopen")

	session.stash_override = func(): return {"ok": false, "errors": ["forced composition stash failure"]}
	var refused: Dictionary = session.prepare_for_remount()
	_check(not bool(refused.get("ok", false)) and session.current_key == "composition" and session.dirty, "failed composition stash blocks authority transition", str(refused))
	session.stash_override = Callable()

	print("[FX-COMPOSITION-AUTHORING-AUTHORITY] done · checks=%d failures=%d" % [checks, failures])
	_wipe_dir(ProjectSettings.globalize_path(production_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	quit(1 if failures > 0 else 0)

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s%s" % [label, (" · " + detail) if detail != "" else ""])

func _wipe_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in DirAccess.get_directories_at(path):
		_wipe_dir(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))
