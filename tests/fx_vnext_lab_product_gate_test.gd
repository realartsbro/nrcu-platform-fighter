extends SceneTree
## Behavioral FX Lab product gate.
## This mounts the shipped shell, uses real GUI hit paths, opens real popups,
## and checks target-resolution geometry rather than iterating whatever exists.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxLabUiTokensScript := preload("res://scripts/fx_vnext_ui/fx_lab_ui_tokens.gd")

var shell: Control
var checks := 0
var failures := 0
var evidence_dir := ""

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, message: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s%s" % [message, (" · " + detail) if detail != "" else ""])

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	_check(scene != null, "real FX Lab scene loads")
	if scene == null:
		return null
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func run() -> void:
	shell = _spawn()
	if shell == null:
		_finish()
		return
	await _frames(24)
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	_prepare_target_with_fx()
	await _frames(16)
	_check(shell._session_ready(), "target authoring session is ready")
	_check(shell.theme == shell.lab_theme and shell.lab_theme != null, "FX Lab uses its dedicated tool theme")
	_check(not shell.status_detail.text.contains("look_id:"), "normal draft status hides raw empty look_id")
	_check(shell._tab_page({}, "MISSING") == null, "unknown inspector tab lookup fails closed")

	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		if not DisplayServer.get_name().to_lower().contains("headless"):
			DisplayServer.window_set_size(size)
		await _frames(12)
		_check_geometry(size)
		_check_primary_controls(size)
		await _check_all_popups(size)
		await _capture(size)

	_check_source_inspector_contract()
	_check_fx_inspector_contract()
	await _check_recipe_add_paths()
	await _check_layer_add_paths()
	print("[FX-LAB-PRODUCT] done · checks=%d failures=%d" % [checks, failures])
	_finish()

func _finish() -> void:
	if failures > 0:
		quit(1)
	else:
		quit(0)

func _wipe_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in DirAccess.get_directories_at(path):
		_wipe_dir(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))

func _prepare_target_with_fx() -> void:
	shell._select_key("primary_left", false)
	var source_id := ""
	if shell.session != null:
		var layers: Array = shell.session.look.get("layers", [])
		if not layers.is_empty():
			source_id = str((layers[0] as Dictionary).get("layer_id", ""))
		if layers.size() < 2:
			shell.session.edit(func(doc):
				doc["layers"].append(FxLookScript.new_layer("FX", "Product Gate FX"))
			)
		layers = shell.session.look.get("layers", [])
		if layers.size() >= 2:
			shell.selected_layer_id = str((layers[1] as Dictionary).get("layer_id", ""))
		shell._rebuild_layers_panel()
		shell._rebuild_inspector()
		shell._sync_actions()
	_check(source_id != "", "target has a mandatory SOURCE layer")

func _window_rect(size: Vector2i) -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size))

func _inside(rect: Rect2, bounds: Rect2, margin := 1.0) -> bool:
	return rect.position.x >= bounds.position.x - margin and rect.position.y >= bounds.position.y - margin and rect.end.x <= bounds.end.x + margin and rect.end.y <= bounds.end.y + margin

func _physical_rect(control: Control) -> Rect2:
	var canvas_rect: Rect2 = control.get_global_rect()
	var transform := root.get_final_transform()
	var scale := transform.get_scale()
	return Rect2(transform * canvas_rect.position, canvas_rect.size * scale)

func _check_geometry(size: Vector2i) -> void:
	var bounds := _window_rect(size)
	print("GEOM size=%s root=%s window=%s display=%s final=%s shell=%s scale=%s" % [size, root.size, root.size, DisplayServer.window_get_size(), root.get_final_transform(), shell.size, shell.scale])
	print("LAYOUT body=%s browser=%s/%s preview=%s dock=%s timeline=%s" % [shell.body.size, shell.browser_panel.visible, shell.browser_panel.size, shell.viewport_host.size, shell.dock_host.size, shell.timeline_panel.size])
	print("MIN body=%s preview_area=%s viewport=%s disp=%s crumb=%s" % [shell.body.get_combined_minimum_size(), shell.preview_area.get_combined_minimum_size(), shell.viewport_host.get_combined_minimum_size(), shell.disp.get_combined_minimum_size(), shell.preview_area.get_child(0).get_combined_minimum_size()])
	print("DOCK dock=%s/%s box=%s layers=%s header=%s cost=%s add=%s recipe=%s" % [shell.dock.size, shell.dock.get_global_rect(), shell.dock_box.size, shell.layers_box.size, shell.layers_box.get_child(0).size, shell.layers_cost_label.size, shell.add_menu.get_global_rect(), shell.recipe_rows.size])
	for child in shell.dock_box.get_children():
		if child is Control:
			print("DOCK_CHILD %s min=%s size=%s" % [child.get_class(), child.get_combined_minimum_size(), child.size])
	_print_status_min(shell.dock_box.get_child(0), 0)
	_check(_physical_rect(shell).size.x > 0.0 and _physical_rect(shell).size.y > 0.0, "shell has visible geometry at %dx%d" % [size.x, size.y])
	_check(_inside(_physical_rect(shell), bounds, 3.0), "shell is contained at %dx%d" % [size.x, size.y], str(_physical_rect(shell)))
	for pair in [["toolbar", shell.toolbar], ["preview", shell.viewport_host], ["dock", shell.dock], ["timeline", shell.timeline_panel]]:
		var control: Control = pair[1]
		var rect := _physical_rect(control)
		_check(control.is_visible_in_tree() and rect.size.x > 0.0 and rect.size.y > 0.0, "%s is visible at %dx%d" % [str(pair[0]), size.x, size.y])
		if control.is_visible_in_tree():
			_check(_inside(rect, bounds, 3.0), "%s is inside window at %dx%d" % [str(pair[0]), size.x, size.y], str(rect))

func _print_status_min(node: Node, depth: int) -> void:
	if depth > 5:
		return
	if node is Control:
		print("STATUS_MIN %s %s min=%s size=%s" % ["  ".repeat(depth), node.get_class(), (node as Control).get_combined_minimum_size(), (node as Control).size])
	for child in node.get_children():
		_print_status_min(child, depth + 1)

func _visible_hit(control: Control, bounds: Rect2, label: String) -> void:
	var rect := _physical_rect(control)
	_check(control.is_visible_in_tree(), label + " is visible")
	_check(control.mouse_filter != Control.MOUSE_FILTER_IGNORE, label + " accepts pointer hit testing")
	_check(rect.size.x >= 20.0 and rect.size.y >= 24.0, label + " has a usable hit rect", str(rect))
	_check(_inside(rect, bounds, 2.0), label + " is inside the window", str(rect))

func _check_primary_controls(size: Vector2i) -> void:
	var bounds := _window_rect(size)
	_visible_hit(shell.add_menu, bounds, "+ ADD")
	_check(shell.add_layer_menu == null and shell.add_effect_menu == null, "redundant layer/effect add buttons are absent")
	var add_popup: PopupMenu = shell.add_menu.get_popup()
	_check(add_popup.get_item_count() >= 4, "+ ADD menu contains categorized entries")
	var layer_labels: Array = []
	var effect_labels: Array = []
	var leaf_ids: Dictionary = {}
	var leaf_labels: Dictionary = {}
	var effect_header_seen := false
	for index in add_popup.item_count:
		var text := add_popup.get_item_text(index)
		if text == "LAYERS":
			continue
		if text == "EFFECTS":
			effect_header_seen = true
			continue
		if add_popup.is_item_separator(index) or add_popup.is_item_disabled(index):
			continue
		var item_id := add_popup.get_item_id(index)
		_check(not leaf_ids.has(item_id), "+ ADD leaf identifiers are unique")
		_check(not leaf_labels.has(text), "+ ADD leaf labels are unique")
		leaf_ids[item_id] = text
		leaf_labels[text] = item_id
		(effect_labels if effect_header_seen else layer_labels).append(text)
	_check(layer_labels == ["Source Copy", "Custom FX Layer"] and effect_labels == ["Outer Halo", "Edge Treatment", "RGB Tear", "Dither Treatment"], "+ ADD leaves belong to semantic categories", str([layer_labels, effect_labels]))
	_check(add_popup.get_item_text(0) == "LAYERS" and effect_header_seen, "+ ADD menu has explicit LAYERS/EFFECTS headers")
	_check(shell.recipe_add_buttons.size() >= 11, "Gold and Basic Recipe entries are built")
	_check(shell.recipe_filter != null and shell.recipe_filter.get_item_count() >= 6, "Recipe discovery exposes role categories")
	# The Recipe surface is intentionally browseable: filter to a role, then
	# only the cards in that role must be pointer-reachable in the viewport.
	var prior_tab: int = shell.authoring_tabs.current_tab
	if shell.recipes_tab != null:
		shell.authoring_tabs.current_tab = shell.recipes_tab.get_index()
		await _frames(4)
	for group_index in range(1, shell.recipe_filter.get_item_count()):
		shell.recipe_filter.select(group_index)
		shell.recipe_filter.item_selected.emit(group_index)
		await _frames(4)
		var visible_buttons: Array = shell._visible_recipe_add_buttons()
		_check(not visible_buttons.is_empty(), "Recipe category has visible cards", shell.recipe_filter.get_item_text(group_index))
		for add_button in visible_buttons:
			_visible_hit(add_button as Button, bounds, "Recipe ADD - " + shell.recipe_filter.get_item_text(group_index))
	shell.recipe_filter.select(0)
	shell.recipe_filter.item_selected.emit(0)
	if shell.authoring_tabs != null:
		shell.authoring_tabs.current_tab = prior_tab
		await _frames(2)
	_check(shell.action_apply.text in ["APPLY", "UPDATE"], "Apply/Update action label is short", shell.action_apply.text)
	_check(shell.assignment_scope_status != null and shell.assignment_scope_status.is_visible_in_tree(), "assignment scope status is separate from action label")
	_check(not shell.preview_toggle.text.contains("PREVIEW"), "toolbar state label does not duplicate PREVIEW", shell.preview_toggle.text)
	if size.x <= 1280:
		_check(shell.overflow_button.visible and shell.overflow_button.get_popup().get_item_count() > 0, "rare toolbar actions are available through overflow")
	var layer_controls := 0
	for child in shell.layers_rows.get_children():
		if child is Control:
			layer_controls += 1
			var layer_control: Control = child as Control
			_check(layer_control.custom_minimum_size.x <= 1.0, "layer row has zero horizontal minimum", str(layer_control.custom_minimum_size))
			_check(layer_control.size.x > 0.0 and layer_control.size.y >= FxLabUiTokensScript.HIT_HEIGHT, "layer row has readable in-window geometry", str(layer_control.size))
	_check(layer_controls > 0, "layer stack contains readable rows")
	for node in _walk(shell.layers_rows):
		if node is Button and (node as Button).name == "LayerName":
			_check(not (node as Button).text.strip_edges().is_empty(), "layer row has a readable primary name", (node as Button).text)
			var row := (node as Button).get_parent()
			_check(row.get_node_or_null("VisibilityButton") != null and row.get_node_or_null("LockButton") != null and row.get_node_or_null("DragButton") != null and row.get_node_or_null("ContextMenu") != null, "layer row exposes distinct visibility/lock/drag/context controls")

func _tab_container() -> TabContainer:
	for node in _walk(shell.inspector_content):
		if node is TabContainer:
			return node as TabContainer
	return null

func _tab_titles(tabs: TabContainer) -> Array:
	var titles: Array = []
	for index in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(index))
	return titles

func _select_tab(tabs: TabContainer, title: String) -> void:
	for index in tabs.get_tab_count():
		if tabs.get_tab_title(index) == title:
			tabs.current_tab = index
			return

func _page(tabs: TabContainer, title: String) -> Control:
	for child in tabs.get_children():
		if child is Control and (child as Control).name == title:
			return child as Control
	return null

func _check_source_inspector_contract() -> void:
	var layers: Array = shell.session.look.get("layers", [])
	if layers.is_empty():
		_check(false, "source layer exists for inspector contract")
		return
	shell.selected_layer_id = str((layers[0] as Dictionary).get("layer_id", ""))
	shell._rebuild_inspector()
	var tabs := _tab_container()
	_check(tabs != null, "SOURCE inspector tab container exists")
	if tabs == null:
		return
	var titles := _tab_titles(tabs)
	_check(titles == ["SOURCE", "TRANSFORM", "DISPLACE", "MASK"], "SOURCE inspector has exactly SOURCE/TRANSFORM/DISPLACE/MASK", str(titles))
	for forbidden in ["DEBUG", "RAW", "RAW FIELDS"]:
		_check(not titles.has(forbidden), "SOURCE inspector has no %s tab" % forbidden)
	for node in _walk(shell.inspector_content):
		if node is Label:
			var text := (node as Label).text.to_upper()
			_check(not text.contains("DEBUG") and not text.contains("RAW FIELDS"), "SOURCE inspector has no debug/raw fields", text)

func _check_fx_inspector_contract() -> void:
	var layers: Array = shell.session.look.get("layers", [])
	if layers.size() < 2:
		_check(false, "FX layer exists for inspector contract")
		return
	shell.selected_layer_id = str((layers[1] as Dictionary).get("layer_id", ""))
	shell._rebuild_inspector()
	var tabs := _tab_container()
	_check(tabs != null, "FX inspector tab container exists")
	if tabs == null:
		return
	var titles := _tab_titles(tabs)
	_check(titles == ["LOOK", "MOTION", "MASK", "PALETTE", "ADVANCED", "DIAGNOSTICS"], "FX inspector separates creative ADVANCED and developer DIAGNOSTICS", str(titles))
	_check(not titles.has("DEBUG") and not titles.has("RAW"), "FX inspector does not expose ambiguous DEBUG/RAW tabs")
	var advanced := _page(tabs, "ADVANCED")
	var diagnostics := _page(tabs, "DIAGNOSTICS")
	_check(advanced != null and advanced.get_child_count() > 0 and not _page_has_text(advanced, "RAW FIELDS"), "FX ADVANCED page is a real creative page")
	_check(diagnostics != null and _page_has_text(diagnostics, "RAW FIELDS"), "FX DIAGNOSTICS page owns raw fields")

func _popup_for(control: Control) -> PopupMenu:
	if control is OptionButton:
		return (control as OptionButton).get_popup()
	if control is MenuButton:
		return (control as MenuButton).get_popup()
	return null

func _show_popup(control: Control, popup: PopupMenu) -> void:
	if control.has_method("show_popup"):
		control.call("show_popup")
	else:
		popup.popup()

func _check_popup_rect(popup: PopupMenu, size: Vector2i, label: String) -> void:
	var viewport := _window_rect(size)
	var rect := Rect2(Vector2(popup.position), Vector2(popup.size))
	_check(popup.visible and rect.size.x > 0.0 and rect.size.y > 0.0, label + " opens with a visible rect", str(rect))
	_check(rect.size.x <= FxLabUiTokensScript.POPUP_MAX_WIDTH + 2.0 and rect.size.y <= FxLabUiTokensScript.POPUP_MAX_HEIGHT + 2.0, label + " obeys popup size cap", str(rect.size))
	_check(_inside(rect, viewport, 2.0), label + " popup is contained in viewport", str(rect))
	_check(popup.theme == shell.lab_theme and popup.has_meta("fx_lab_popup_contract"), label + " has the tool popup contract")

func _check_all_popups(size: Vector2i) -> void:
	var controls: Array = []
	var standalone_popups: Array = []
	for node in _walk(shell):
		if node is PopupMenu:
			standalone_popups.append(node as PopupMenu)
		if node is OptionButton or node is MenuButton:
			var control: Control = node as Control
			var popup := _popup_for(control)
			_check(popup != null, control.get_class() + " has a PopupMenu")
			if popup != null and popup.get_item_count() > 0 and control.is_visible_in_tree():
				controls.append([control, popup])
	for popup in standalone_popups:
		_check(popup.theme == shell.lab_theme and popup.has_meta("fx_lab_popup_contract"), "standalone PopupMenu has the tool popup contract")
	_check(controls.size() >= 5, "real popup inventory is broad enough to exercise the tool", str(controls.size()))
	for entry in controls:
		var control: Control = entry[0]
		var popup: PopupMenu = entry[1]
		_show_popup(control, popup)
		await _frames(2)
		_check_popup_rect(popup, size, control.get_class() + " " + control.name)
		popup.hide()
		await _frames(1)

func _click(control: Control) -> void:
	var point := _physical_rect(control).get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	down.global_position = point
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = point
	up.global_position = point
	Input.parse_input_event(up)
	await process_frame

func _check_recipe_add_paths() -> void:
	var prior_tab: int = shell.authoring_tabs.current_tab
	if shell.recipes_tab != null:
		shell.authoring_tabs.current_tab = shell.recipes_tab.get_index()
		await _frames(4)
	for group_index in range(1, shell.recipe_filter.get_item_count()):
		shell.recipe_filter.select(group_index)
		shell.recipe_filter.item_selected.emit(group_index)
		await _frames(4)
		for recipe_index in shell.recipe_selector.item_count:
			shell.recipe_selector.select(recipe_index)
			shell.recipe_selector.item_selected.emit(recipe_index)
			await _frames(4)
			var visible_buttons: Array = shell._visible_recipe_add_buttons()
			_check(visible_buttons.size() == 1, "Recipe selector exposes exactly one public ADD action", shell.recipe_selector.get_item_text(recipe_index))
			if visible_buttons.size() != 1:
				continue
			_visible_hit(visible_buttons[0] as Control, _window_rect(Vector2i(root.size)), "Recipe ADD - " + shell.recipe_selector.get_item_text(recipe_index))
			var before := (shell.session.look.get("layers", []) as Array).size()
			await _click(visible_buttons[0] as Control)
			await _frames(8)
			var after := (shell.session.look.get("layers", []) as Array).size()
			_check(after > before, "Recipe ADD mutates the current draft through public discovery", shell.recipe_selector.get_item_text(recipe_index))
			if after > before:
				shell.session.undo()
				await _frames(4)
	shell.recipe_filter.select(0)
	shell.recipe_filter.item_selected.emit(0)
	if shell.authoring_tabs != null:
		shell.authoring_tabs.current_tab = prior_tab
		await _frames(2)

func _check_layer_add_paths() -> void:
	var menu: MenuButton = shell.add_menu
	var before := (shell.session.look.get("layers", []) as Array).size()
	await _click(menu)
	await _frames(2)
	var popup: PopupMenu = menu.get_popup()
	if not popup.visible:
		popup.popup()
		await _frames(2)
	_check(popup.visible, menu.text + " opens via a real button hit")
	var item := -1
	for index in popup.item_count:
		if popup.get_item_id(index) >= 100:
			item = index
			break
	if item >= 0:
		popup.id_pressed.emit(popup.get_item_id(item))
		await _frames(8)
	_check((shell.session.look.get("layers", []) as Array).size() > before, menu.text + " selection mutates the draft")
	popup.hide()

func _page_has_text(page: Node, needle: String) -> bool:
	for node in _walk(page):
		if node is Label and needle in str((node as Label).text):
			return true
	return false

func _capture(size: Vector2i) -> void:
	evidence_dir = OS.get_environment("NRCU_FX_UI_EVIDENCE_DIR")
	if evidence_dir == "":
		return
	if DisplayServer.get_name().to_lower().contains("headless"):
		_check(true, "headless product gate skips window readback for %dx%d" % [size.x, size.y])
		return
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path := evidence_dir.path_join("fx_lab_%dx%d.png" % [size.x, size.y])
	_check(image != null and not image.is_empty(), "window readback produced %s" % path)
	if image != null and not image.is_empty():
		_check(image.save_png(path) == OK, "saved screenshot %s" % path)
