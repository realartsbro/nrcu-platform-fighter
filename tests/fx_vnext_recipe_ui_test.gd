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
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key(_target_key("primary", "left")))
	var primary_key := _target_key("primary", "left")
	_check(primary_key != "", "public registry resolves PRIMARY left target from semantic identity")
	await _click_target(primary_key)
	await settle(15)
	_check(shell._session_ready(), "recipe shell test opens a primary target through Browser selection")
	_check(shell.recipe_rows != null and shell.recipe_rows.get_child_count() >= 5, "Recipe Library exposes Hero Recipes and curated starting points")
	_check(shell.library_rows != null and shell.recipe_rows != null and shell.library_rows != shell.recipe_rows and shell.production_tab.is_ancestor_of(shell.library_rows) and shell.recipes_tab.is_ancestor_of(shell.recipe_rows), "Production Looks and Recipes are separate secondary dock surfaces")
	_check(shell.has_method("_action_add_recipe"), "shell exposes a first-class recipe action")

	if shell.has_method("_action_add_recipe") and shell._session_ready():
		var before_layers: Array = shell.session.look.get("layers", []).duplicate(true)
		shell.session.set_assignment_scope("ROLE")
		await _select_recipe_and_click_add(FxRecipesScript.PRIMARY_FLAME_ENERGY)
		await settle(12)
		var flame_layers: Array = shell.session.look.get("layers", [])
		_check(flame_layers.size() == before_layers.size() + 3, "PRIMARY_FLAME_ENERGY instantiates its complete layer stack", str(flame_layers.size()))
		_check(shell.session._undo_stack.size() == 1, "PRIMARY_FLAME_ENERGY creates one undo transaction", "stack=%d" % shell.session._undo_stack.size())
		_check(str(shell.session.assignment_scope_mode) == "ROLE", "recipe instantiation is independent of Assignment Scope")
		_check(bool(shell.session.undo()), "one recipe transaction can be undone")
		await settle(5)
		_check((shell.session.look.get("layers", []) as Array).size() == before_layers.size(), "one undo removes the complete recipe stack")

		# ORGANIC_SIDE_FIELD is intentionally fail-closed for fighter targets;
		# continue the real UI flow on the declared side-field target instead of
		# weakening the compatibility authority to satisfy this shell fixture.
		var side_field_key := _target_key("side_field", "left")
		_check(side_field_key != "", "public registry resolves LEFT side-field target from semantic identity")
		await _click_target(side_field_key)
		await settle(15)
		_check(str(shell.selected_key) == side_field_key and str(shell.session.current_key) == side_field_key, "Browser selection opens the resolved side-field target", "selected=%s current=%s status=%s" % [shell.selected_key, shell.session.current_key, shell.action_status.text])
		var organic_before_layers: Array = shell.session.look.get("layers", []).duplicate(true)
		await _select_recipe_and_click_add(FxRecipesScript.ORGANIC_SIDE_FIELD)
		await settle(12)
		var organic_layers: Array = shell.session.look.get("layers", [])
		_check(organic_layers.size() == organic_before_layers.size() + 2, "ORGANIC_SIDE_FIELD instantiates its complete layer stack", str(organic_layers.size()))
		_check(shell.session._undo_stack.size() == 1, "ORGANIC_SIDE_FIELD creates one undo transaction", "stack=%d" % shell.session._undo_stack.size())
		var canonical: Dictionary = shell.session.look.duplicate(true)
		canonical["look_id"] = "P7_SHELL"
		canonical["name"] = "P7 Shell Recipe Fixture"
		var validation: Dictionary = FxLookScript.validate_input(canonical)
		_check(bool(validation.get("ok", false)), "recipe shell result remains a valid canonical Look", str(validation.get("errors", [])))

	print("[FX-RECIPES-UI] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _target_key(element_role: String, visual_side: String) -> String:
	if shell == null or shell.runtime == null or shell.runtime.registry == null:
		return ""
	for raw_key in shell.runtime.registry.keys():
		var key := str(raw_key)
		var ctx: Dictionary = shell.runtime.registry.context_for_target(key)
		if str(ctx.get("element_role", "")).to_lower() == element_role.to_lower() and str(ctx.get("visual_side", "")).to_lower() == visual_side.to_lower():
			return key
	return ""

func _click_target(key: String) -> void:
	if shell.browser == null or shell.browser.tree == null:
		_check(false, "Browser target tree is available")
		return
	for raw_item in shell.browser.row_keys.keys():
		var item: TreeItem = raw_item
		if str(shell.browser.row_keys[raw_item]) != key:
			continue
		shell.browser.tree.scroll_to_item(item, true)
		await settle(2)
		var area: Rect2 = shell.browser.tree.get_item_area_rect(item, 0)
		_click_point(shell.browser.tree.get_global_transform_with_canvas() * area.get_center())
		return
	_check(false, "Browser exposes the semantic target row", key)

func _select_recipe_and_click_add(recipe_id: String) -> void:
	var tab_index: int = shell.authoring_tabs.get_tab_idx_from_control(shell.recipes_tab)
	shell.authoring_tabs.current_tab = tab_index
	var recipe: Dictionary = FxRecipesScript.get_recipe(recipe_id)
	var group := str(recipe.get("library_group", recipe.get("category", ""))).to_upper()
	var filter_index := 0
	for index in range(shell.recipe_filter.item_count):
		if shell.recipe_filter.get_item_text(index).to_upper() == group:
			filter_index = index
			break
	shell.recipe_filter.select(filter_index)
	shell.recipe_filter.item_selected.emit(filter_index)
	var selector_index := -1
	for index in range(shell.recipe_selector.item_count):
		if str(shell.recipe_selector.get_item_metadata(index)) == recipe_id:
			selector_index = index
			break
	_check(selector_index >= 0, "Recipe Browser exposes the requested recipe", recipe_id)
	if selector_index < 0:
		return
	shell.recipe_selector.select(selector_index)
	shell.recipe_selector.item_selected.emit(selector_index)
	await settle(3)
	for raw_button in shell.recipe_add_buttons:
		var button: Button = raw_button
		if not button.is_visible_in_tree():
			continue
		var ancestor: Node = button
		while ancestor != null:
			if ancestor.name == "RecipeCard_" + recipe_id:
				_click_control(button)
				return
			ancestor = ancestor.get_parent()
	_check(false, "Visible Recipe ADD reaches the requested recipe card", recipe_id)

func _click_control(control: Control) -> void:
	if control is BaseButton:
		(control as BaseButton).grab_focus()
		(control as BaseButton).pressed.emit()
		return
	_click_point(control.get_global_rect().get_center())

func _click_point(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)

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
