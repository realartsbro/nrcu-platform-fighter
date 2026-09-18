extends SceneTree
# vNext workspace shell acceptance driver (specs/01 — Phase 1).
# Windowed run: resizes the real window across the four target resolutions,
# verifies layout bounds (nothing outside the window), collapse behavior,
# toolbar overflow, browser content/search/selection, timeline toggle and
# workspace persistence. Captures screenshots per resolution.

var shell: Control
var checks: Array = []
var failures: int = 0
var out_dir: String
var shots: Array = []

const SIZES := [[1366, 768], [1600, 900], [1920, 1080], [2560, 1440]]

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/shell")
	DirAccess.make_dir_recursive_absolute(out_dir)
	shell = _spawn()
	await settle(45)
	shell._reset_workspace()
	await settle(10)
	# UI-11: no target is an explicit state. Target-mutating rows must not
	# masquerade as available disabled actions before selection.
	_check(shell.status_title.text == "NO TARGET SELECTED" and shell.status_badge.text == "○ UNASSIGNED", "no-target state is explicit")
	_check(not bool(shell.target_action_row.visible) and not bool(shell.target_action_row3.visible), "no-target hides target actions", "row=%s row3=%s selected=%s mode=%s" % [shell.target_action_row.visible, shell.target_action_row3.visible, shell.selected_key, shell.session.mode])

	# ---- browser content ---------------------------------------------------
	var rows: int = _count_rows(shell.browser.tree.get_root())
	_check(rows >= 14, "browser lists targets", "rows=%d" % rows)
	var groups := _group_labels(shell.browser.tree.get_root())
	_check(groups.has("VS") and groups.has("FIGHTERS") and groups.has("COMPOSITION"), "browser groups present", str(groups))

	# ---- resolution sweep --------------------------------------------------
	for s in SIZES:
		DisplayServer.window_set_size(Vector2i(int(s[0]), int(s[1])))
		await settle(16)
		var violations: Array = _bounds_violations()
		_check(violations.is_empty(), "no control outside window at %dx%d" % [int(s[0]), int(s[1])], str(violations.slice(0, 4)))
		var img: Image = await _screenshot()
		if img != null:
			var path := out_dir.path_join("shell_%dx%d.png" % [int(s[0]), int(s[1])])
			img.save_png(path)
			shots.append({"size": [int(s[0]), int(s[1])], "file": path.get_file(), "actual": [img.get_width(), img.get_height()]})

	# ---- responsive assertions (should be at 2560x1440 now) ----------------
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await settle(16)
	_check(not shell.browser.visible and shell.browser_rail.visible, "browser collapses to rail at 1366")
	_check(not shell.timeline_ruler.visible, "timeline stays collapsed at 1366")
	_check(shell.overflow_button.visible, "secondary actions move to overflow at 1366")
	var transport_labels: Array = []
	for control in shell.toolbar.get_children():
		if control is Button and control.is_visible_in_tree():
			transport_labels.append((control as Button).text)
	var transport_count := 0
	for label in transport_labels:
		for token in ["START", "PAUSE", "PLAY", "1F", "PEAK"]:
			if token in str(label):
				transport_count += 1
				break
	_check(transport_count >= 5, "primary transport buttons present at 1366", str(transport_labels))
	_check(shell.play_button != null and shell.play_button.is_visible_in_tree(), "play control visible")
	for token in ["BROWSER", "RESET"]:
		var found := false
		for label in transport_labels:
			if token in str(label):
				found = true
		_check(found, "view control visible · " + token)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(16)
	_check(shell.browser.visible and not shell.browser_rail.visible, "browser fully visible at 1920")
	_check(not shell.overflow_button.visible, "overflow hidden at 1920")
	_check(shell.remount_button.visible, "secondary actions inline at 1920")
	# UI-09: AUTO is a heuristic only; an explicit user open wins below the
	# narrow breakpoint and remains open after widening.
	shell._toggle_browser()
	await settle(8)
	_check(not bool(shell.browser.visible) and str(shell.ws.data.get("browser_intent", "")) == "USER_CLOSED", "browser user-close records explicit intent")
	shell._toggle_browser()
	await settle(8)
	_check(bool(shell.browser.visible) and str(shell.ws.data.get("browser_intent", "")) == "USER_OPEN", "browser rail toggle records explicit user-open intent")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await settle(16)
	_check(bool(shell.browser.visible) and not bool(shell.browser_rail.visible), "explicit browser open wins at 1280x720")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(16)
	_check(bool(shell.browser.visible), "explicit browser open survives widening")
	shell._toggle_browser()
	await settle(8)
	_check(not bool(shell.browser.visible) and str(shell.ws.data.get("browser_intent", "")) == "USER_CLOSED", "browser user-close remains explicit")
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	await settle(16)
	_check(not bool(shell.browser.visible), "explicit browser close survives widening")
	shell._reset_workspace()
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await settle(16)
	_check(str(shell.ws.data.get("browser_intent", "")) == "AUTO" and not bool(shell.browser.visible), "reset returns browser to AUTO collapse")

	# ---- timeline toggle ---------------------------------------------------
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(16)
	shell._reset_workspace()
	shell._toggle_timeline_expanded()
	await settle(10)
	_check(shell.timeline_ruler.visible, "timeline expands on toggle")
	var expanded_h: float = shell.timeline_panel.custom_minimum_size.y
	_check(expanded_h >= 120.0 and expanded_h <= 240.0, "expanded timeline height within bounds", "%.0f" % expanded_h)
	_check(str(shell.ws.data.get("timeline_intent", "")) == "USER_OPEN", "timeline open records explicit intent")
	shell._toggle_timeline_expanded()
	await settle(10)
	_check(not shell.timeline_ruler.visible, "timeline collapses back")
	_check(str(shell.ws.data.get("timeline_intent", "")) == "USER_CLOSED", "timeline close records explicit intent")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await settle(16)
	shell._reset_workspace()
	await settle(8)
	_check(str(shell.ws.data.get("timeline_intent", "")) == "AUTO" and not bool(shell.timeline_ruler.visible), "timeline AUTO collapses at 1280x720")
	shell._toggle_timeline_expanded()
	await settle(10)
	_check(bool(shell.timeline_ruler.visible) and str(shell.ws.data.get("timeline_intent", "")) == "USER_OPEN", "timeline can be explicitly opened at 1280x720")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await settle(16)
	_check(bool(shell.timeline_ruler.visible), "explicit timeline open survives widening")
	shell._toggle_timeline_expanded()
	await settle(8)
	_check(not bool(shell.timeline_ruler.visible) and str(shell.ws.data.get("timeline_intent", "")) == "USER_CLOSED", "explicit timeline close survives widening")
	shell._reset_workspace()

	# ---- browser search -----------------------------------------------------
	var before := _count_rows(shell.browser.tree.get_root())
	shell.browser.search_edit.text = "echo"
	shell.browser.search_edit.text_changed.emit("echo")
	await settle(5)
	var filtered := _count_rows(shell.browser.tree.get_root())
	_check(filtered > 0 and filtered < before, "search filters rows", "before=%d after=%d" % [before, filtered])
	shell.browser.search_edit.text = ""
	shell.browser.search_edit.text_changed.emit("")
	await settle(5)

	# ---- selection ----------------------------------------------------------
	shell._select_key("echo_left", true)
	await settle(6)
	_check(shell.breadcrumb_label.text == "ICE MAGE › ECHO › LEFT", "breadcrumb reflects selection", shell.breadcrumb_label.text)
	_check("presentation" in shell.status_detail.text, "status shows spatial readout", shell.status_detail.text)
	_check(shell.selection_outline.visible, "selection outline visible")
	# UI-11: remount clears authority, not just the browser highlight.
	shell._remount_current()
	await settle(12)
	_check(shell.status_title.text == "NO TARGET SELECTED" and not bool(shell.target_action_row.visible) and not bool(shell.target_action_row3.visible), "remount returns to no-target state")
	shell._select_key("echo_left", false)
	await settle(8)

	# ---- dock toggle ---------------------------------------------------------
	shell._toggle_dock()
	await settle(6)
	_check(not shell.dock.visible, "inspector toggle hides dock")
	shell._toggle_dock()
	await settle(6)
	_check(shell.dock.visible, "inspector toggle restores dock")

	# ---- persistence ---------------------------------------------------------
	shell.ws.data["browser_w"] = 340.0
	shell.ws.data["dock_w"] = 430.0
	shell.ws.data["timeline_expanded"] = true
	shell.ws.data["preview_focus"] = "DIM OTHERS"
	shell.ws.save_state()
	shell.queue_free()
	await settle(6)
	var shell2: Control = _spawn()
	await settle(40)
	_check(absf(float(shell2.ws.data["browser_w"]) - 340.0) < 0.5, "browser width persisted")
	_check(absf(float(shell2.ws.data["dock_w"]) - 430.0) < 0.5, "dock width persisted")
	_check(bool(shell2.ws.data["timeline_expanded"]), "timeline state persisted")
	_check(str(shell2.ws.data["preview_focus"]) == "DIM OTHERS", "preview focus persisted")
	shell2._reset_workspace()
	await settle(8)
	_check(absf(float(shell2.ws.data["browser_w"]) - 280.0) < 0.5, "reset restores defaults")
	shell2.queue_free()
	await settle(6)

	# ---- restore window ------------------------------------------------------
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var f := FileAccess.open(out_dir.path_join("summary_shell_check.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks.size(), "failures": failures, "shots": shots}, "  "))
		f.close()
	print("[SHELL] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func _count_rows(item: TreeItem) -> int:
	var count := 0
	var child := item.get_first_child()
	while child != null:
		if child.get_metadata(0) != null:
			count += 1
		count += _count_rows(child)
		child = child.get_next()
	return count

func _group_labels(item: TreeItem) -> Array:
	var out: Array = []
	var child := item.get_first_child()
	while child != null:
		if child.get_metadata(0) == null:
			out.append(str(child.get_text(0)))
		child = child.get_next()
	return out

func _bounds_violations() -> Array:
	var win := Vector2(DisplayServer.window_get_size())
	var phys_scale := win.x / 1600.0
	var flag: Array = []
	var targets: Array = [shell.toolbar, shell.browser_panel, shell.preview_area, shell.dock, shell.timeline_panel]
	for control in targets:
		_collect_violations(control, win, phys_scale, flag)
	for control in shell.toolbar.get_children():
		if control is Control and control.visible:
			_collect_violations(control, win, phys_scale, flag)
	return flag

func _collect_violations(control: Control, win: Vector2, phys_scale: float, flag: Array) -> void:
	if control == null or not control.visible:
		return
	# Control rects live in the fixed 1600×900 canvas space; convert to physical
	# pixels before comparing against the window.
	var rect: Rect2 = control.get_global_rect()
	var phys := Rect2(rect.position * phys_scale, rect.size * phys_scale)
	if phys.position.x < -2.0 or phys.position.y < -2.0 or phys.end.x > win.x + 2.0 or phys.end.y > win.y + 2.0:
		flag.append("%s %s" % [control.name, str(phys)])

func _screenshot() -> Image:
	await RenderingServer.frame_post_draw
	if root == null:
		return null
	return root.get_texture().get_image()

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok:
		failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
