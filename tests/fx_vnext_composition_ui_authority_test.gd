extends SceneTree
# P0 composition UI authority regression: the synthetic composition target must
# use composition context and must not expose assignment authoring actions.

const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

var checks := 0
var failures := 0
var shell

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	_check(scene != null, "FX Lab scene loads")
	if scene == null:
		quit(1)
		return
	shell = scene.instantiate()
	root.add_child(shell)
	await _frames(30)
	var production_dir := ProjectSettings.globalize_path("user://vnext_test_composition_ui_production")
	var draft_dir := ProjectSettings.globalize_path("user://vnext_test_composition_ui_drafts")
	_wipe_dir(production_dir)
	_wipe_dir(draft_dir)
	var composition: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "active")["doc"]
	composition["status"] = "PRODUCTION"
	_check(bool(shell.production.apply({"composition": composition}).get("ok", false)), "composition production seed applies")

	shell._select_key("composition", false)
	await _frames(12)
	_check(shell._session_ready(), "composition selection opens a session")
	_check(str(shell.session.context.get("element_id", "")) == "composition", "composition selection uses synthetic element context", str(shell.session.context))
	_check(str(shell.session.context.get("element_role", "")) == "composition", "composition selection uses synthetic composition role", str(shell.session.context))
	_check(str(shell.session.resolution.get("status", "")) == "COMPOSITION", "composition session reports composition authority", str(shell.session.resolution))
	_check(shell.status_detail.text.contains("Composition revision"), "composition status shows production revision", shell.status_detail.text)
	_check(shell.status_badge.text.contains("COMPOSITION") or shell.status_badge.text.contains("SCENE FX"), "composition status is explicit", shell.status_badge.text)
	_check(not shell.action_styling.visible, "composition hides Styling assignment action")
	_check(not shell.action_unassign.visible, "composition hides Unassign assignment action")
	_check(not shell.action_unique.visible and not shell.action_edit_shared.visible, "composition hides shared assignment actions")
	_check(not shell.action_more_menu.visible, "composition hides assignment actions menu")
	_check(not shell.assignment_scope_option.visible, "composition hides assignment scope controls")
	_check(shell.action_apply.visible and not shell.action_apply.disabled, "composition keeps Apply authoring action")

	print("[FX-COMPOSITION-UI-AUTHORITY] done · checks=%d failures=%d" % [checks, failures])
	if shell != null:
		shell.queue_free()
		await _frames(3)
	_wipe_dir(production_dir)
	_wipe_dir(draft_dir)
	quit(1 if failures > 0 else 0)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

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
