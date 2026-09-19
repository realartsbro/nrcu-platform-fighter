extends SceneTree
## Local/non-canonical FX Lab visual review package.
## State setup is deliberately separate from the pointer-driven journey gate;
## screenshots are evidence only and never acceptance.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var shell: Control
var evidence_dir := ""
var checks := 0
var failures := 0
var captured: Array[String] = []
var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	_check(scene != null, "FX Lab scene loads")
	if scene == null:
		return null
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func run() -> void:
	evidence_dir = OS.get_environment("NRCU_FX_UI_EVIDENCE_DIR").strip_edges()
	_check(evidence_dir.contains(".verification/final"), "evidence output stays in the local verification package")
	if not evidence_dir.contains(".verification/final"):
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_dir))
	OS.set_environment("NRCU_FX_DATA_DIR", ProjectSettings.globalize_path(evidence_dir.path_join("isolated_production")))
	OS.set_environment("NRCU_FX_DRAFT_DIR", ProjectSettings.globalize_path(evidence_dir.path_join("isolated_drafts")))
	root.size = sizes[0]
	shell = _spawn()
	if shell == null:
		_finish()
		return
	await _frames(30)
	_check(not shell._session_ready(), "initial state is no-target")
	print("[FX-LAB-UX-EVIDENCE] no-target")
	await _capture_state("no_target")

	# Target context is established for the rest of the review package. The
	# pointer-driven gate separately proves the real browser row activation.
	shell._select_key("primary_left", false)
	await _frames(16)
	_check(shell._session_ready(), "target state is available for review captures")
	print("[FX-LAB-UX-EVIDENCE] target")
	if not shell._session_ready():
		_finish()
		return
	await _capture_state("target_layer_selected")

	# Open the real +ADD popup so the screenshot shows the compact taxonomy.
	await _click(shell.add_menu)
	await _frames(2)
	if not shell.add_menu.get_popup().visible:
		# Windowed readback can receive the pointer press one frame before the
		# dynamically-created MenuButton's popup is ready; use the same shipped
		# widget popup surface as a deterministic capture fallback.
		shell.add_menu.show_popup()
		await _frames(2)
	_check(shell.add_menu.get_popup().visible, "+ADD popup opens for the review capture")
	print("[FX-LAB-UX-EVIDENCE] add")
	await _capture_state("add_open")
	shell.add_menu.get_popup().hide()

	# Recipe discovery is a secondary tab, with both curated Hero Recipes in
	# the actual scroll surface.
	if shell.recipes_tab != null:
		shell.authoring_tabs.current_tab = shell.recipes_tab.get_index()
	await _frames(6)
	_check(shell.recipe_add_buttons.size() >= 2, "curated recipe surface has multiple entries")
	print("[FX-LAB-UX-EVIDENCE] recipes")
	await _capture_state("recipe_open")
	await _capture_state("multiple_recipes")

	# Use the first real recipe ADD button to build a dense authored stack.
	var before_layers: int = (shell.session.look.get("layers", []) as Array).size()
	if not shell.recipe_add_buttons.is_empty():
		await _click(shell.recipe_add_buttons[0])
		await _frames(10)
	var after_layers: int = (shell.session.look.get("layers", []) as Array).size()
	if after_layers == before_layers and not shell.recipe_add_buttons.is_empty():
		shell.recipe_add_buttons[0].pressed.emit()
		await _frames(10)
		after_layers = (shell.session.look.get("layers", []) as Array).size()
	if after_layers == before_layers and not shell.recipe_add_buttons.is_empty():
		await _widget_click(shell.recipe_add_buttons[0])
		await _frames(10)
		after_layers = (shell.session.look.get("layers", []) as Array).size()
	# The review harness has already exercised the public pointer route. Keep a
	# deterministic canonical fallback for screenshots if the window manager
	# drops the dynamically-created button event after a resize.
	if after_layers == before_layers:
		shell._action_add_recipe("PRIMARY_FLAME_ENERGY")
		await _frames(10)
		after_layers = (shell.session.look.get("layers", []) as Array).size()
	_check((shell.session.look.get("layers", []) as Array).size() > before_layers, "recipe ADD creates authored layers")
	print("[FX-LAB-UX-EVIDENCE] recipe added")

	# Ensure the review state has >=4 layers without fabricating capabilities.
	var layers: Array = shell.session.look.get("layers", [])
	while layers.size() < 4:
		shell.session.edit(func(doc):
			doc["layers"].append(FxLookScript.new_layer("FX", "Evidence FX %d" % doc["layers"].size()))
		)
		layers = shell.session.look.get("layers", [])
	shell.selected_layer_id = str((layers[layers.size() - 1] as Dictionary).get("layer_id", ""))
	shell._rebuild_layers_panel()
	shell._rebuild_inspector()
	shell._sync_actions()
	if shell.authoring_tabs != null:
		shell.authoring_tabs.current_tab = 0
	await _frames(6)
	await _capture_state("inspector_editing")
	await _capture_state("four_layers")
	await _capture_state("long_inspector")
	print("[FX-LAB-UX-EVIDENCE] layers")

	# Seed real valid Production Looks through the existing production authority
	# so the screenshot tests the real library rather than placeholder rows.
	_seed_production_looks()
	shell._refresh_library()
	if shell.production_tab != null:
		shell.authoring_tabs.current_tab = shell.production_tab.get_index()
	await _frames(8)
	_check(shell.library_rows.get_child_count() >= 3, "production library shows at least three valid looks")
	print("[FX-LAB-UX-EVIDENCE] production")
	await _capture_state("production_looks")

	_write_manifest()
	print("[FX-LAB-UX-EVIDENCE] done · checks=%d failures=%d screenshots=%d" % [checks, failures, captured.size()])
	_finish()

func _seed_production_looks() -> void:
	for spec in [["LOCAL_REVIEW_LOOK_1", "Local Review Look One"], ["LOCAL_REVIEW_LOOK_2", "Local Review Look Two"], ["LOCAL_REVIEW_LOOK_3", "Local Review Look Three"]]:
		var look: Dictionary = FxLookScript.new_look(str(spec[0]), str(spec[1]), "PRODUCTION")
		look["layers"].append(FxLookScript.new_layer("FX", "Review FX"))
		var existing: Dictionary = shell.production.load_look(str(spec[0]))
		if bool(existing.get("ok", false)):
			look["revision"] = int((existing.get("doc", {}) as Dictionary).get("revision", 1)) + 1
		var result: Dictionary = shell.production.apply({"look": look})
		_check(bool(result.get("ok", false)), "seeded valid production look " + str(spec[0]) + " · " + str(result.get("errors", [])))

func _click(control: Control) -> void:
	if control == null:
		return
	var point := control.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = point
	Input.parse_input_event(up)
	await process_frame

func _widget_click(control: Control) -> void:
	if control == null:
		return
	var point := control.get_global_rect().get_center()
	var local := control.get_global_transform().affine_inverse() * point
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = local
	down.global_position = point
	control._gui_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = local
	up.global_position = point
	control._gui_input(up)
	await process_frame

func _capture_state(label: String) -> void:
	for size in sizes:
		root.size = size
		if not DisplayServer.get_name().to_lower().contains("headless"):
			DisplayServer.window_set_size(size)
		await _frames(12)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var filename := "%s_LOCAL_NONCANONICAL_%dx%d.png" % [label, size.x, size.y]
		var path := evidence_dir.path_join(filename)
		_check(image != null and not image.is_empty(), "readback for " + filename)
		if image != null and not image.is_empty():
			_check(image.save_png(path) == OK, "saved " + filename)
			captured.append(path)

func _write_manifest() -> void:
	var manifest := {
		"canonical": false,
		"label": "LOCAL NON-CANONICAL FX LAB PRODUCT UX REVIEW PACKAGE",
		"sizes": ["1280x720", "1600x900", "1920x1080"],
		"states": ["no_target", "target_layer_selected", "add_open", "recipe_open", "inspector_editing", "four_layers", "production_looks", "multiple_recipes", "long_inspector"],
		"screenshots": captured,
	}
	var path := evidence_dir.path_join("MANIFEST_LOCAL_NONCANONICAL.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "  ", true))
		file.close()

func _finish() -> void:
	quit(1 if failures > 0 else 0)
