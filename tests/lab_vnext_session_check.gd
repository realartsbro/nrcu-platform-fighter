extends SceneTree
# vNext session check — drives the REAL shell scene end to end (windowed):
# selection → session → layer renderer in the preview, edit → autostash,
# Apply writes Production, Styling ON/OFF, WHY?, badges. Evidence screenshots.

var checks: Array = []
var failures: int = 0
var out_dir: String
var shell: Control

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/session")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var data_dir := OS.get_environment("NRCU_FX_DATA_DIR")
	var draft_dir := OS.get_environment("NRCU_FX_DRAFT_DIR")
	_wipe_dir(ProjectSettings.globalize_path(data_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	shell = scene.instantiate()
	root.add_child(shell)
	await settle(20)

	_check(shell.session != null and shell.production != null and shell.drafts != null, "shell boots with session + stores")

	# ---- select a target: session opens, renderer draws the stack --------------
	shell._select_key("echo_left", false)
	await settle(10)
	_check(str(shell.session.current_key) == "echo_left", "session opened for echo_left", str(shell.session.current_key))
	_check(str(shell.session.mode) == "EDIT_UNASSIGNED", "neutral design (empty production)", str(shell.session.mode))
	_check(shell.renderer != null and shell.renderer.has_stack("echo_left"), "layer renderer active for target")
	_check(shell.status_badge.text == "○ UNASSIGNED", "status badge unassigned", shell.status_badge.text)
	_check(shell.layers_rows.get_child_count() > 0, "layers panel built", "rows=%d" % shell.layers_rows.get_child_count())
	await capture("session_01_neutral")

	# ---- edit through the shell path (inspector action) ------------------------
	var layers: Array = shell.session.look.get("layers", [])
	var source_id := str((layers[0] as Dictionary).get("layer_id", ""))
	shell._edit_layer(source_id, func(doc):
		var l: Dictionary = load("res://scripts/fx_vnext/fx_look.gd").find_layer(doc, source_id)
		l["opacity"] = 0.55
	)
	await settle(6)
	_check(shell.session.dirty, "edit marks session dirty")
	_check(shell.status_badge.text == "◐ DRAFT", "badge shows DRAFT", shell.status_badge.text)
	_check(shell.renderer.has_stack("echo_left"), "renderer still live after edit")

	# ---- autostash after the 500 ms debounce ------------------------------------
	var stashed := false
	for i in range(600):
		await process_frame
		if shell.drafts.has_target(str(shell.session.signature)):
			stashed = true
			break
	_check(stashed, "autostash wrote draft")

	# ---- apply via the shell action (Ctrl+Enter path) ---------------------------
	shell._action_apply()
	await settle(8)
	_check(shell.production.list_look_ids() == ["ICE_MAGE_ECHO_LEFT"], "production look written on apply", str(shell.production.list_look_ids()))
	_check(not shell.session.dirty and shell.status_badge.text == "● ASSIGNED", "badge assigned after apply", shell.status_badge.text)
	_check(shell.action_status.text.begins_with("✓ Applied"), "apply feedback shown", shell.action_status.text)
	_check(shell.action_styling.tooltip_text.contains("echo") and shell.action_unassign.tooltip_text.contains("echo"), "styling and unassign expose assignment scope")
	await capture("session_02_applied")

	# ---- why? -------------------------------------------------------------------
	shell._action_why()
	await settle(4)
	_check(shell.why_label.visible and shell.why_label.text.contains("selected"), "why panel explains winner", shell.why_label.text.substr(0, 60))

	# ---- styling on/off -----------------------------------------------------------
	shell._action_toggle_styling()
	await settle(8)
	_check(shell.status_badge.text.contains("STYLING OFF"), "styling off badge", shell.status_badge.text)
	var assignments: Dictionary = shell.production.load_assignments()
	_check((assignments["doc"].get("bypasses", []) as Array).size() == 1, "bypass persisted")
	_check(shell.renderer.has_stack("echo_left"), "stack renders while bypassed (neutral look)")
	await capture("session_03_styling_off")
	shell._action_toggle_styling()
	await settle(8)
	_check(shell.status_badge.text == "● ASSIGNED", "styling on restores", shell.status_badge.text)

	# ---- update flow: second apply bumps revision ----------------------------------
	shell._edit_layer(source_id, func(doc):
		var l: Dictionary = load("res://scripts/fx_vnext/fx_look.gd").find_layer(doc, source_id)
		l["opacity"] = 0.8
	)
	await settle(4)
	shell._action_apply()
	await settle(8)
	var look = shell.production.load_look("ICE_MAGE_ECHO_LEFT")
	_check(int((look.get("doc", {}) as Dictionary).get("revision", 0)) == 2, "update bumped revision to 2", "rev=%d" % int((look.get("doc", {}) as Dictionary).get("revision", 0)))
	_check(shell.action_apply.text.begins_with("Update Target Style"), "action label follows update state", shell.action_apply.text)
	await capture("session_04_updated")

	# ---- audit additions: templates, planes, reorder, undo, study, presets ---------
	var FxLookScriptLocal = load("res://scripts/fx_vnext/fx_look.gd")
	var FxTargetsLocal = load("res://scripts/fx_vnext/fx_targets.gd")
	var FxResolverScriptLocal = load("res://scripts/fx_vnext/fx_resolver.gd")
	shell._action_add_layer("Source Copy")
	await settle(6)
	var layers_n: Array = shell.session.look["layers"]
	_check(layers_n.size() == 2 and str((layers_n[1] as Dictionary)["type"]) == "SOURCE_COPY", "add Source Copy template creates typed layer")
	_check(str((layers_n[1] as Dictionary)["plane"]) == "TARGET_UNDERLAY", "source copy template lands behind target", str((layers_n[1] as Dictionary)["plane"]))
	shell._action_add_layer("Outer Halo")
	await settle(6)
	layers_n = shell.session.look["layers"]
	var halo: Dictionary = layers_n[2]
	_check(str(halo["type"]) == "FX" and absf(float((halo["fx"] as Dictionary).get("fringe", 0.0)) - 1.0) < 0.001 and bool((halo["mask"] as Dictionary).get("enabled", false)), "Outer Halo template prefills mask + fringe")
	var halo_id := str(halo["layer_id"])
	shell._drop_layer_on_plane(halo_id, "TARGET_UNDERLAY")
	await settle(4)
	_check(str(FxLookScriptLocal.find_layer(shell.session.look, halo_id)["plane"]) == "TARGET_UNDERLAY", "plane drop changes plane")
	shell._drop_layer_on_layer(halo_id, "PLACEHOLDER")
	await settle(2)
	var copy_id := str((shell.session.look["layers"][1] as Dictionary)["layer_id"])
	shell._drop_layer_on_layer(halo_id, copy_id)
	await settle(4)
	var order_after: Array = shell.session.look["layers"]
	_check(str((order_after[1] as Dictionary)["layer_id"]) == halo_id, "row drop reorders layers", "idx1=" + str((order_after[1] as Dictionary)["name"]))
	shell._action_undo()
	await settle(4)
	_check(str((shell.session.look["layers"][1] as Dictionary)["layer_id"]) == copy_id, "undo restores order")
	shell._action_redo()
	await settle(4)
	_check(str((shell.session.look["layers"][1] as Dictionary)["layer_id"]) == halo_id, "redo reapplies order")
	# UI-12: Ctrl+Shift+Z must be tested before the plain Ctrl+Z branch.
	shell._move_layer(halo_id, 1)
	await settle(4)
	shell._action_undo()
	await settle(4)
	var redo_key := InputEventKey.new()
	redo_key.pressed = true
	redo_key.ctrl_pressed = true
	redo_key.shift_pressed = true
	redo_key.keycode = KEY_Z
	shell._unhandled_key_input(redo_key)
	await settle(4)
	var halo_index := -1
	for i in range((shell.session.look["layers"] as Array).size()):
		if str((shell.session.look["layers"][i] as Dictionary).get("layer_id", "")) == halo_id:
			halo_index = i
	_check(halo_index == 2 and str(shell.action_status.text).contains("Redo"), "Ctrl+Shift+Z dispatches redo, not undo", "index=%d status=%s" % [halo_index, shell.action_status.text])
	# R3 red-team: the layer MENU move actions (MOVE UP/DOWN -> _move_layer) must
	# reorder WITHOUT touching any layer_id (stable identity across reorder).
	var ids_before: Array = []
	for l in (shell.session.look["layers"] as Array):
		ids_before.append(str((l as Dictionary)["layer_id"]))
	ids_before.sort()
	var idx_before := -1
	for i in range((shell.session.look["layers"] as Array).size()):
		if str((shell.session.look["layers"][i] as Dictionary)["layer_id"]) == halo_id:
			idx_before = i
	shell._move_layer(halo_id, -1)
	await settle(4)
	var ids_after: Array = []
	for l in (shell.session.look["layers"] as Array):
		ids_after.append(str((l as Dictionary)["layer_id"]))
	ids_after.sort()
	var idx_after := -1
	for i in range((shell.session.look["layers"] as Array).size()):
		if str((shell.session.look["layers"][i] as Dictionary)["layer_id"]) == halo_id:
			idx_after = i
	_check(ids_before == ids_after, "layer GUI move keeps the id set identical (no id regeneration)", "before=%s after=%s" % [str(ids_before), str(ids_after)])
	_check(idx_after != idx_before and idx_after >= 0, "layer GUI move actually reordered the moved layer", "idx %d -> %d" % [idx_before, idx_after])
	shell._move_layer(halo_id, 1)
	await settle(4)
	# source cannot be deleted / moved
	var source_id2 := str((shell.session.look["layers"][0] as Dictionary)["layer_id"])
	shell._layer_menu_action(5, source_id2)
	await settle(3)
	_check(FxLookScriptLocal.find_layer(shell.session.look, source_id2).is_empty() == false, "SOURCE cannot be deleted")
	shell._drop_layer_on_plane(source_id2, "TARGET_OVERLAY")
	await settle(3)
	_check(str(FxLookScriptLocal.find_layer(shell.session.look, source_id2)["plane"]) == "TARGET_SOURCE", "SOURCE stays pinned to TARGET_SOURCE")
	# study zoom is authoring-neutral
	var node = shell.runtime.registry.slot_nodes.get("echo_left")
	var rect_before: Rect2 = FxTargetsLocal.presentation_rect(node)
	shell._set_study("200%")
	await settle(6)
	var rect_after: Rect2 = FxTargetsLocal.presentation_rect(node)
	_check(rect_before == rect_after, "study zoom does not change authored geometry", str(rect_before))
	_check(str(shell.study_mode) == "200%", "study mode engaged")
	shell._set_study("200%")
	await settle(4)
	_check(str(shell.study_mode) == "OFF", "study toggled off")
	# workspace preset
	shell._apply_workspace_preset("PREVIEW")
	await settle(4)
	_check(str(shell.ws.data.get("preset", "")) == "PREVIEW", "workspace preset applies")
	shell._apply_workspace_preset("AUTHORING")
	await settle(4)
	# cost indicator present
	shell._refresh_selection_ui()
	await settle(4)
	_check(str(shell.layers_cost_label.text).contains("cost"), "cost indicator rendered", shell.layers_cost_label.text)
	# UI-18/UI-12: shared production state exposes a persistent protected banner
	# and gates history actions, including after a selection refresh.
	var shared_asg: Dictionary = shell.production.load_assignments()["doc"]
	FxResolverScriptLocal.upsert_binding(shared_asg, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "right"}, "ICE_MAGE_ECHO_LEFT", "shared banner proof")
	_check(bool(shell.production.apply({"assignments": shared_asg})["ok"]), "shared banner proof binding applies")
	shell._select_key("echo_left", false)
	await settle(8)
	_check(str(shell.session.mode) == "SHARED_PROTECTED", "shared target reopens protected", str(shell.session.mode))
	_check(shell.protected_banner.visible and shell.protected_banner.text.contains("PROTECTED SHARED LOOK"), "protected banner remains visible", shell.protected_banner.text)
	_check(shell.undo_button.disabled and shell.redo_button.disabled, "protected history actions disabled")
	await capture("session_05_layer_ops")

	var f := FileAccess.open(out_dir.path_join("summary_session_check.json"), FileAccess.WRITE)
	var summary := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("[SESSION-CHECK] done · checks=%d failures=%d" % [checks.size(), failures])
	_wipe_dir(ProjectSettings.globalize_path(data_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	quit(1 if failures > 0 else 0)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(name: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(path: String) -> void:
	if path == "":
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
