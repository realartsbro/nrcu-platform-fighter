extends SceneTree
# vNext §17 window torture — the REAL workspace shell driven through real window
# sizes: 1366x768 / 1600x900 / 1920x1080 / 2560x1440, the minimum supported
# width, very wide (3000x900), very tall (900x2000), rapid resize, maximize and
# restore. Asserts, at every size: the toolbar stays fully reachable, the
# overflow menu is present, the browser pane can reopen, the inspector is
# reachable, the preview owns the remaining space, the timeline resizes/collapses
# and the workspace state survives.
#
# Scene note: the brief named res://scenes/nrcu_fx_lab.tscn, but in this project
# that is the CLASSIC lab (Node2D + nrcu_fx_lab_v2.gd). The vNext shell that owns
# the toolbar / browser / inspector / timeline layout is
# res://scenes/nrcu_fx_lab_vnext.tscn (lab_shell.gd) — the same scene the
# ui_round2 and shell_check suites instantiate.
#
# WINDOWED suite: this file is authored/parse-verified only for now
# (--check-only). A windowed run drives the real OS window:
#   engine/Godot_v4.7.2-stable_win64_console.exe --path project --always-on-top \
#     --script res://tests/lab_vnext_responsive_check.gd

const SHELL_SCENE := "res://scenes/nrcu_fx_lab_vnext.tscn"

# Canonical acceptance resolutions (specs/01 responsive acceptance).
const SIZES := [[1366, 768], [1600, 900], [1920, 1080], [2560, 1440]]
# No window min_size is declared by the shell; 1280x720 is the declared floor of
# this torture sweep: the toolbar needs ~1104 px of button minimum widths with
# the brand label hidden below 1240 px, so 1280 is the narrowest width at which
# every primary control is still fully inside the window.
const MIN_SIZE := [1280, 720]
const WIDE_SIZE := [3000, 900]
const TALL_SIZE := [900, 2000]

var checks: Array = []
var failures: int = 0
var out_dir: String
var shell: Control
var shots: Array = []
var preview_measurements: Array = []
var rail_width := 1440.0
var tall_timeline_height := 800.0

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/responsive")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(OS.get_environment("NRCU_FX_DATA_DIR")))
	_wipe_dir(ProjectSettings.globalize_path(OS.get_environment("NRCU_FX_DRAFT_DIR")))

	if not ResourceLoader.exists(SHELL_SCENE):
		_check(false, "shell scene present", SHELL_SCENE)
		_finish()
		return
	shell = _spawn()
	await settle(45)
	if shell == null:
		_check(false, "shell instantiates", SHELL_SCENE)
		_finish()
		return

	_check(shell.has_method("_apply_browser_mode") and shell.has_method("_toggle_browser") and shell.has_method("_toggle_dock") and shell.has_method("_toggle_timeline_expanded"),
		"shell exposes the responsive API", "lab_shell.gd")
	rail_width = float(shell.AUTO_RAIL_WIDTH)
	tall_timeline_height = float(shell.AUTO_TIMELINE_COLLAPSE_HEIGHT)
	_check(absf(rail_width - 1440.0) < 0.001 and absf(tall_timeline_height - 800.0) < 0.001,
		"responsive thresholds match the accepted contract", "rail=%.0f tall=%.0f" % [rail_width, tall_timeline_height])
	# Toolbar overflow is dynamic (measured fit, no static width tier):
	# at the default narrow test window the menu must carry actions.
	shell._toolbar_overflow()
	_check(shell.toolbar != null and shell.browser_panel != null and shell.preview_area != null and shell.dock != null and shell.timeline_panel != null,
		"shell exposes toolbar / browser / preview / dock / timeline", "lab_shell.gd")
	_check(shell.overflow_button != null and shell.overflow_button.get_popup().item_count >= 1,
		"overflow menu exists and carries the secondary action", _overflow_items())

	shell._reset_workspace()
	await settle(12)
	await _sweep("canonical")

	# ---- timeline expanded sweep (the timeline is a second responsive axis) ----
	shell.ws.data["timeline_expanded"] = true
	shell._apply_timeline()
	await settle(8)
	await _sweep("timeline-expanded")
	shell.ws.data["timeline_expanded"] = false
	shell._apply_timeline()
	await settle(8)

	await _case_rapid_resize()
	await _case_maximize_restore()
	await _case_browser_reopen()
	await _case_inspector_reachable()
	await _case_timeline_resize()
	await _case_workspace_persistence()

	# ---- restore a sane window and finish -------------------------------------
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await settle(16)
	_finish()

# ================================================================ sweeps

func _sweep(label: String) -> void:
	for spec in SIZES:
		await _surface(spec, label)
	await _surface(MIN_SIZE, label)
	await _surface(WIDE_SIZE, label)
	await _surface(TALL_SIZE, label)
	if label == "canonical":
		# The preview must own everything the panes do not use. Preview width is
		# weakly monotonic WITHIN each collapse regime; across the 1440 px
		# progressive-collapse threshold the browser pane expands again, which is
		# the designed behavior (checked regime-aware). Measured against the
		# ACTUAL window size, so a platform clamp cannot fake the result.
		var threshold := 1440
		var below: Array = preview_measurements.filter(func(m): return int(m["w"]) < threshold)
		var above: Array = preview_measurements.filter(func(m): return int(m["w"]) >= threshold)
		var monotonic := _weakly_monotonic(below) and _weakly_monotonic(above)
		_check(monotonic and preview_measurements.size() >= 4, "preview width is monotonic within each collapse regime", str(preview_measurements))
		var sorted := preview_measurements.duplicate()
		sorted.sort_custom(func(a, b): return int(a["w"]) < int(b["w"]))
		_check(sorted.size() >= 2 and float(sorted[sorted.size() - 1]["preview"]) > float(sorted[0]["preview"]),
			"preview grows with the window", "min=%s max=%s" % [str(sorted[0]), str(sorted[sorted.size() - 1])])

func _weakly_monotonic(rows: Array) -> bool:
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a, b): return int(a["w"]) < int(b["w"]))
	for i in range(1, sorted.size()):
		if float(sorted[i]["preview"]) < float(sorted[i - 1]["preview"]) - 4.0:
			return false
	return true

func _surface(spec: Array, label: String) -> void:
	var requested := Vector2i(int(spec[0]), int(spec[1]))
	DisplayServer.window_set_size(requested)
	await settle(18)
	var actual := _actual_size()
	var tag := "%dx%d" % [actual.x, actual.y]
	if label == "canonical":
		preview_measurements.append({"tag": tag, "w": actual.x, "preview": float(shell.preview_area.size.x)})

	_check(absf(float(shell.size.x) - float(actual.x)) <= 2.0 and absf(float(shell.size.y) - float(actual.y)) <= 2.0,
		"[%s] shell covers the real window at %s" % [label, tag], "shell=%s window=%s" % [str(shell.size), str(actual)])
	var outside: Array = _controls_outside()
	_check(outside.is_empty(), "[%s] no control outside the window at %s" % [label, tag], str(outside.slice(0, 4)))

	var rail_expected: bool = float(actual.x) < rail_width or bool(shell.ws.data.get("browser_collapsed", false))
	_check(bool(shell.browser_rail.visible) == rail_expected and bool(shell.browser.visible) == not rail_expected,
		"[%s] browser pane follows the responsive rule at %s" % [label, tag],
		"rail=%s browser=%s expected_rail=%s" % [str(shell.browser_rail.visible), str(shell.browser.visible), str(rail_expected)])

	# Dynamic overflow contract: the toolbar always fits, and the menu exists
	# exactly when pool buttons are collapsed into it.
	_check(float(shell.toolbar.get_combined_minimum_size().x) <= float(actual.x) + 1.0,
		"[%s] toolbar fits the window at %s" % [label, tag],
		"min=%.0f window=%d" % [float(shell.toolbar.get_combined_minimum_size().x), actual.x])
	var pool_hidden: bool = not bool(shell.remount_button.visible) or not bool(shell.review_button.visible) or not bool(shell.preset_authoring.visible) or not bool(shell.preset_preview.visible)
	_check(bool(shell.overflow_button.visible) == pool_hidden,
		"[%s] overflow menu matches collapsed pool at %s" % [label, tag],
		"overflow=%s items=%d" % [str(shell.overflow_button.visible), shell.overflow_button.get_popup().item_count])

	_check(shell.play_button != null and shell.play_button.is_visible_in_tree() and _reachable(shell.play_button),
		"[%s] play control reachable at %s" % [label, tag])
	var labels: Array = _visible_toolbar_labels()
	var transport := 0
	for text in labels:
		for token in ["START", "PAUSE", "PLAY", "1F", "PEAK"]:
			if str(text).contains(token):
				transport += 1
				break
	_check(transport >= 5, "[%s] primary transport buttons present at %s" % [label, tag], str(labels))

	var timelines_visible: bool = bool(shell.timeline_ruler.visible)
	var timeline_expected: bool = bool(shell.ws.data.get("timeline_expanded", false)) and float(actual.y) >= tall_timeline_height
	_check(timelines_visible == timeline_expected, "[%s] timeline visibility follows the responsive rule at %s" % [label, tag],
		"ruler=%s expanded=%s height=%.0f" % [str(timelines_visible), str(shell.ws.data.get("timeline_expanded", false)), float(actual.y)])

	if shell.dock.visible:
		var panes: float = float(shell.browser_panel.size.x) + float(shell.preview_area.size.x) + float(shell.dock.size.x)
		_check(absf(panes + 12.0 - float(actual.x)) <= 24.0, "[%s] preview owns the remaining horizontal space at %s" % [label, tag],
			"panes=%.0f window=%d" % [panes, actual.x])
	_check(float(shell.preview_area.size.x) > 0.0 and float(shell.preview_area.size.y) > 0.0,
		"[%s] preview keeps a positive area at %s" % [label, tag], str(shell.preview_area.size))
	if actual == requested:
		var img: Image = await _screenshot()
		if img != null:
			var path := out_dir.path_join("responsive_%s_%s.png" % [label, tag])
			img.save_png(path)
			shots.append({"label": label, "size": [actual.x, actual.y], "file": path.get_file()})

func _case_rapid_resize() -> void:
	# 12 rapid reconfigurations without waiting for a settle between each step:
	# the final layout must match the final window size and nothing may escape.
	var sequence: Array = [[1366, 768], [2560, 1440], [1600, 900], [900, 2000], [1920, 1080], [1280, 720],
		[3000, 900], [1920, 1080], [1366, 768], [2560, 1440], [1600, 900], [1920, 1080]]
	for spec in sequence:
		DisplayServer.window_set_size(Vector2i(int(spec[0]), int(spec[1])))
		await settle(1)
	await settle(24)
	var actual := _actual_size()
	_check(absf(float(shell.size.x) - float(actual.x)) <= 2.0, "rapid resize: shell catches up with the final size", "shell=%.0f window=%d" % [float(shell.size.x), actual.x])
	var outside: Array = _controls_outside()
	_check(outside.is_empty(), "rapid resize: no control outside the window", str(outside.slice(0, 4)))
	var rail_expected: bool = float(actual.x) < rail_width
	_check(bool(shell.browser_rail.visible) == rail_expected, "rapid resize: browser state matches the final width", "rail=%s width=%d" % [str(shell.browser_rail.visible), actual.x])
	_check(float(shell.toolbar.get_combined_minimum_size().x) <= float(actual.x) + 1.0, "rapid resize: toolbar fits the final width", "min=%.0f width=%d" % [float(shell.toolbar.get_combined_minimum_size().x), actual.x])

func _case_maximize_restore() -> void:
	var before := _actual_size()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	await settle(30)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED, "maximize engages", str(DisplayServer.window_get_mode()))
	var maximized := _actual_size()
	_check(maximized.x >= before.x and maximized.y >= before.y, "maximized window is at least the windowed size", "%s -> %s" % [str(before), str(maximized)])
	_check(absf(float(shell.size.x) - float(maximized.x)) <= 2.0 and absf(float(shell.size.y) - float(maximized.y)) <= 2.0,
		"maximize: shell covers the maximized window", "shell=%s window=%s" % [str(shell.size), str(maximized)])
	var outside: Array = _controls_outside()
	_check(outside.is_empty(), "maximize: no control outside the window", str(outside.slice(0, 4)))
	_check(shell.play_button.is_visible_in_tree() and _reachable(shell.play_button), "maximize: toolbar still reachable")

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(before)
	await settle(30)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "restore returns to windowed mode", str(DisplayServer.window_get_mode()))
	var after := _actual_size()
	_check(absf(float(after.x) - float(before.x)) <= 6.0 and absf(float(after.y) - float(before.y)) <= 6.0,
		"restore returns to the previous window size", "%s -> %s" % [str(before), str(after)])
	_check(absf(float(shell.size.x) - float(after.x)) <= 2.0, "restore: shell covers the restored window", "shell=%.0f window=%d" % [float(shell.size.x), after.x])
	var rail_expected: bool = float(after.x) < rail_width
	_check(bool(shell.browser_rail.visible) == rail_expected, "restore: browser state re-derives from the restored width", "rail=%s width=%d" % [str(shell.browser_rail.visible), after.x])

func _case_browser_reopen() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(20)
	shell._reset_workspace()
	await settle(10)
	_check(bool(shell.browser.visible) and not bool(shell.browser_rail.visible), "wide window: full browser pane is shown")
	shell._toggle_browser()
	await settle(8)
	_check(not bool(shell.browser.visible) and bool(shell.browser_rail.visible), "toggling collapses the browser to the rail",
		"browser=%s rail=%s" % [str(shell.browser.visible), str(shell.browser_rail.visible)])
	_check(_reachable(shell.browser_rail), "rail button stays reachable while collapsed")
	shell._toggle_browser()
	await settle(8)
	_check(bool(shell.browser.visible) and not bool(shell.browser_rail.visible), "browser pane reopens from the rail",
		"browser=%s rail=%s" % [str(shell.browser.visible), str(shell.browser_rail.visible)])
	_check(not bool(shell.ws.data.get("browser_collapsed", false)), "reopening clears the persisted collapse flag", str(shell.ws.data.get("browser_collapsed", false)))

	# Narrow window: the auto rule rails the pane, and the rail must be present
	# and reachable (the pane stays collapsed until the window is wide again).
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await settle(20)
	_check(bool(shell.browser_rail.visible) and not bool(shell.browser.visible), "narrow window: browser rails automatically")
	_check(_reachable(shell.browser_rail), "narrow window: rail is reachable so the pane can be re-opened")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(20)
	_check(bool(shell.browser.visible), "widening the window restores the browser pane")

func _case_inspector_reachable() -> void:
	for spec in [[1920, 1080], MIN_SIZE]:
		DisplayServer.window_set_size(Vector2i(int(spec[0]), int(spec[1])))
		await settle(20)
		var tag := "%dx%d" % [int(spec[0]), int(spec[1])]
		shell._reset_workspace()
		await settle(10)
		_check(bool(shell.dock.visible), "inspector dock visible by default at %s" % tag)
		_check(_reachable(shell.dock), "inspector dock reachable at %s" % tag)
		shell._toggle_dock()
		await settle(8)
		_check(not bool(shell.dock.visible), "inspector toggle hides the dock at %s" % tag)
		var outside: Array = _controls_outside()
		_check(outside.is_empty(), "hidden inspector leaves no stray control at %s" % tag, str(outside.slice(0, 3)))
		shell._toggle_dock()
		await settle(8)
		_check(bool(shell.dock.visible) and _reachable(shell.dock), "inspector toggle restores the dock at %s" % tag)
		_check(float(shell.dock.size.x) >= 320.0, "inspector keeps its usable minimum width at %s" % tag, "%.0f" % float(shell.dock.size.x))

func _case_timeline_resize() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(20)
	shell._reset_workspace()
	await settle(10)
	shell._toggle_timeline_expanded()
	await settle(10)
	_check(bool(shell.timeline_ruler.visible), "timeline expands on toggle at 1920x1080")
	_check(bool(shell.timeline_resize_handle.visible), "timeline resize handle appears while expanded")
	_check(absf(float(shell.timeline_panel.custom_minimum_size.y) - float(shell.ws.data.get("timeline_h", 0.0))) <= 0.5,
		"expanded timeline uses the persisted height", "%.0f" % float(shell.timeline_panel.custom_minimum_size.y))

	# Drag the resize handle through the real input path: the height must clamp
	# into the documented domain [120, 240].
	shell._dragging = "timeline"
	var motion := InputEventMouseMotion.new()
	motion.global_position = Vector2(600.0, 40.0)
	shell._handle_drag(motion, "timeline")
	await settle(4)
	_check(float(shell.ws.data.get("timeline_h", 0.0)) <= 240.0 and absf(float(shell.timeline_panel.custom_minimum_size.y) - float(shell.ws.data.get("timeline_h", 0.0))) <= 0.5,
		"timeline drag up clamps to the max height", "%.0f" % float(shell.ws.data.get("timeline_h", 0.0)))
	motion.global_position = Vector2(600.0, 4000.0)
	shell._handle_drag(motion, "timeline")
	await settle(4)
	_check(absf(float(shell.ws.data.get("timeline_h", 0.0)) - 120.0) <= 0.5, "timeline drag down clamps to the min height", "%.0f" % float(shell.ws.data.get("timeline_h", 0.0)))
	motion.global_position = Vector2(600.0, -4000.0)
	shell._handle_drag(motion, "timeline")
	await settle(4)
	_check(absf(float(shell.ws.data.get("timeline_h", 0.0)) - 240.0) <= 0.5, "timeline drag past the top clamps to the max height", "%.0f" % float(shell.ws.data.get("timeline_h", 0.0)))
	shell._dragging = ""

	var outside: Array = _controls_outside()
	_check(outside.is_empty(), "resized timeline leaves no control outside the window", str(outside.slice(0, 3)))
	shell._toggle_timeline_expanded()
	await settle(10)
	_check(not bool(shell.timeline_ruler.visible), "timeline collapses back")
	_check(not bool(shell.timeline_resize_handle.visible), "timeline resize handle hides when collapsed")
	_check(absf(float(shell.timeline_panel.custom_minimum_size.y) - 38.0) <= 0.5, "collapsed timeline uses the compact height", "%.0f" % float(shell.timeline_panel.custom_minimum_size.y))

func _case_workspace_persistence() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(20)
	shell.ws.data["browser_w"] = 340.0
	shell.ws.data["dock_w"] = 430.0
	shell.ws.data["timeline_h"] = 180.0
	shell.ws.data["timeline_expanded"] = true
	shell.ws.data["layers_split"] = 0.42
	shell.ws.save_state()
	shell._apply_state()
	await settle(8)

	# The resize sweep must not rewrite persisted widths.
	for spec in SIZES + [MIN_SIZE, WIDE_SIZE, TALL_SIZE]:
		DisplayServer.window_set_size(Vector2i(int(spec[0]), int(spec[1])))
		await settle(6)
	_check(absf(float(shell.ws.data.get("browser_w", 0.0)) - 340.0) <= 0.5 and absf(float(shell.ws.data.get("dock_w", 0.0)) - 430.0) <= 0.5,
		"the persisted pane widths survive the full resize sweep",
		"browser_w=%.0f dock_w=%.0f" % [float(shell.ws.data.get("browser_w", 0.0)), float(shell.ws.data.get("dock_w", 0.0))])
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(20)
	_check(bool(shell.browser.visible) and absf(float(shell.browser_panel.custom_minimum_size.x) - 340.0) <= 0.5,
		"persisted browser width is applied when the pane is visible", "%.0f" % float(shell.browser_panel.custom_minimum_size.x))
	_check(absf(float(shell.timeline_panel.custom_minimum_size.y) - 180.0) <= 0.5, "persisted timeline height is applied", "%.0f" % float(shell.timeline_panel.custom_minimum_size.y))
	# §17-FINDING candidate: dock_w is written by _handle_drag and stored, but no
	# layout pass ever applies it (_apply_state/_apply_browser_mode apply
	# browser_w, _apply_timeline applies timeline_h) — so the inspector always
	# reopens at the build-time width instead of the persisted one.
	_check(absf(float(shell.dock.custom_minimum_size.x) - 430.0) <= 0.5,
		"§17-FINDING: the persisted inspector width is applied on the next layout pass",
		"persisted dock_w=430 applied=%.0f (build-time default is 390)" % float(shell.dock.custom_minimum_size.x))

	# A fresh shell (new session) must see the same workspace after resizes.
	shell.queue_free()
	await settle(10)
	shell = _spawn()
	await settle(45)
	if shell == null:
		_check(false, "shell respawns for the persistence check")
		return
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(20)
	_check(absf(float(shell.ws.data.get("browser_w", 0.0)) - 340.0) <= 0.5 and absf(float(shell.ws.data.get("dock_w", 0.0)) - 430.0) <= 0.5,
		"workspace pane widths survive a shell restart",
		"browser_w=%.0f dock_w=%.0f" % [float(shell.ws.data.get("browser_w", 0.0)), float(shell.ws.data.get("dock_w", 0.0))])
	_check(bool(shell.ws.data.get("timeline_expanded", false)), "workspace timeline state survives a shell restart")
	_check(bool(shell.browser.visible) and _reachable(shell.play_button), "restarted shell lays out reachable controls at 1920x1080")
	shell._reset_workspace()
	await settle(10)
	_check(absf(float(shell.ws.data.get("browser_w", 0.0)) - 280.0) <= 0.5, "reset restores the default browser width", "%.0f" % float(shell.ws.data.get("browser_w", 0.0)))
	_check(not bool(shell.ws.data.get("timeline_expanded", false)), "reset restores the default timeline state")
	var outside: Array = _controls_outside()
	_check(outside.is_empty(), "reset workspace leaves no control outside the window", str(outside.slice(0, 3)))

# ================================================================ helpers

func _spawn() -> Control:
	var scene: PackedScene = load(SHELL_SCENE)
	if scene == null:
		return null
	var node: Control = scene.instantiate()
	if node == null:
		return null
	root.add_child(node)
	return node

func _actual_size() -> Vector2i:
	return DisplayServer.window_get_size()

func _overflow_items() -> String:
	if shell == null or shell.overflow_button == null:
		return "no overflow button"
	var popup: PopupMenu = shell.overflow_button.get_popup()
	var items: Array = []
	for index in popup.item_count:
		items.append(popup.get_item_text(index))
	return str(items)

func _visible_toolbar_labels() -> Array:
	var labels: Array = []
	if shell == null or shell.toolbar == null:
		return labels
	for control in shell.toolbar.get_children():
		if control is Button and (control as Button).is_visible_in_tree():
			labels.append(str((control as Button).text))
	return labels

func _reachable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	if float(control.size.x) <= 0.0 or float(control.size.y) <= 0.0:
		return false
	return _inside_shell(control)

func _inside_shell(control: Control) -> bool:
	var shell_rect: Rect2 = shell.get_global_rect()
	var rect: Rect2 = control.get_global_rect()
	var tolerance := 2.0
	return rect.position.x >= shell_rect.position.x - tolerance \
		and rect.position.y >= shell_rect.position.y - tolerance \
		and rect.end.x <= shell_rect.end.x + tolerance \
		and rect.end.y <= shell_rect.end.y + tolerance

func _controls_outside() -> Array:
	# Controls live in the shell's own native-pixel space; the shell counter-scales
	# itself against the engine canvas scale, so "inside the shell rect" is exactly
	# "inside the window" (and shell.size is checked against the real window size).
	var out: Array = []
	var targets: Array = [shell.toolbar, shell.browser_panel, shell.preview_area, shell.dock, shell.timeline_panel]
	if shell.dock.visible:
		targets.append(shell.status_detail)
		targets.append(shell.inspector_content)
	for control in targets:
		_collect_outside(control, out)
	for control in shell.toolbar.get_children():
		if control is Control and (control as Control).is_visible_in_tree():
			_collect_outside(control, out)
	return out

func _collect_outside(control: Control, out: Array) -> void:
	if control == null or not control.is_visible_in_tree():
		return
	if float(control.size.x) <= 0.0 and float(control.size.y) <= 0.0:
		return
	if not _inside_shell(control):
		out.append("%s %s" % [str(control.name), str(control.get_global_rect())])

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _screenshot() -> Image:
	await RenderingServer.frame_post_draw
	if root == null:
		return null
	return root.get_texture().get_image()

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _finish() -> void:
	var f := FileAccess.open(out_dir.path_join("summary_responsive_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL", "shots": shots}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	var log_file := FileAccess.open(out_dir.path_join("responsive_checks.log"), FileAccess.WRITE)
	var summary := "[LAB-RESPONSIVE] done · checks=%d failures=%d" % [checks.size(), failures]
	if log_file != null:
		log_file.store_string("\n".join(checks) + "\n" + summary + "\n")
		log_file.close()
	print(summary)
	quit(1 if failures > 0 else 0)

func _wipe_dir(abs_path: String) -> void:
	if abs_path == "" or not DirAccess.dir_exists_absolute(abs_path):
		return
	for file_name in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs_path):
		_wipe_dir(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)
