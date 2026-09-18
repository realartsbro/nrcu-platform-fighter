extends SceneTree
# Phase 7 shell vertical slice: Hero Recipe rows remain authoring-only and
# instantiate complete stacks through one FxSession undo transaction.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

var shell: Control
var failures := 0
var checks := 0

func _init() -> void:
	shell = _spawn()
	await settle(30)
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("primary_left"))
	shell._select_key("primary_left", false)
	await settle(15)
	_check(shell._session_ready(), "recipe shell test opens a primary target")
	_check(shell.recipe_rows != null and shell.recipe_rows.get_child_count() == 2, "Recipe Library exposes exactly two Hero Recipe rows")
	_check(shell.library_rows != null and shell.recipe_rows != null and shell.library_rows != shell.recipe_rows and shell.library_rows.get_index() < shell.recipe_rows.get_index(), "Production Inventory remains visibly separate")
	_check(shell.has_method("_action_add_recipe"), "shell exposes a first-class recipe action")

	if shell.has_method("_action_add_recipe") and shell._session_ready():
		var before_layers: Array = shell.session.look.get("layers", []).duplicate(true)
		shell.session.set_assignment_scope("ROLE")
		shell._action_add_recipe(FxRecipesScript.PRIMARY_FLAME_ENERGY)
		await settle(12)
		var flame_layers: Array = shell.session.look.get("layers", [])
		_check(flame_layers.size() == before_layers.size() + 3, "PRIMARY_FLAME_ENERGY instantiates its complete layer stack", str(flame_layers.size()))
		_check(shell.session._undo_stack.size() == 1, "PRIMARY_FLAME_ENERGY creates one undo transaction", "stack=%d" % shell.session._undo_stack.size())
		_check(str(shell.session.assignment_scope_mode) == "ROLE", "recipe instantiation is independent of Assignment Scope")
		_check(bool(shell.session.undo()), "one recipe transaction can be undone")
		await settle(5)
		_check((shell.session.look.get("layers", []) as Array).size() == before_layers.size(), "one undo removes the complete recipe stack")

		shell._action_add_recipe(FxRecipesScript.ORGANIC_SIDE_FIELD)
		await settle(12)
		var organic_layers: Array = shell.session.look.get("layers", [])
		_check(organic_layers.size() == before_layers.size() + 2, "ORGANIC_SIDE_FIELD instantiates its complete layer stack", str(organic_layers.size()))
		_check(shell.session._undo_stack.size() == 1, "ORGANIC_SIDE_FIELD creates one undo transaction", "stack=%d" % shell.session._undo_stack.size())
		var canonical: Dictionary = shell.session.look.duplicate(true)
		canonical["look_id"] = "P7_SHELL"
		canonical["name"] = "P7 Shell Recipe Fixture"
		var validation: Dictionary = FxLookScript.validate_input(canonical)
		_check(bool(validation.get("ok", false)), "recipe shell result remains a valid canonical Look", str(validation.get("errors", [])))

	print("[FX-RECIPES-UI] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)

func _wipe_dir(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)
		return
	for file_name in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs_path):
		_wipe_dir(abs_path.path_join(sub))
		DirAccess.remove_absolute(abs_path.path_join(sub))
