extends SceneTree
# Round-2 findings 9 (matchup/context sync), 10 (onboarding), 13 (copy/paste
# layer + id stability) through the REAL shell. Windowed: needs rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String
var shell: Control

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/ui_round2")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(OS.get_environment("NRCU_FX_DATA_DIR")))
	_wipe_dir(ProjectSettings.globalize_path(OS.get_environment("NRCU_FX_DRAFT_DIR")))

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	shell = scene.instantiate()
	root.add_child(shell)
	await settle(24)

	var browser = shell.browser
	var runtime = shell.runtime

	# ---- 9. initial visible values match the mounted context ---------------------
	_check(browser.mode_option.get_item_text(browser.mode_option.selected) == str(runtime.mode_format), "mode control matches mounted context", browser.mode_option.get_item_text(browser.mode_option.selected))
	_check(browser.stage_option.get_item_text(browser.stage_option.selected) == str(runtime.stage_id), "stage control matches mounted context", browser.stage_option.get_item_text(browser.stage_option.selected))
	_check(browser.left_option.get_item_text(browser.left_option.selected) == str(runtime.pick_l), "left fighter matches mounted context", browser.left_option.get_item_text(browser.left_option.selected))
	_check(browser.right_option.get_item_text(browser.right_option.selected) == str(runtime.pick_r), "right fighter matches mounted context", browser.right_option.get_item_text(browser.right_option.selected))
	var summary: String = str(browser.summary_button.text)
	_check(summary.contains(str(runtime.mode_format)) and summary.contains("Ice Mage") and summary.contains("Doge Man") and summary.contains(str(runtime.stage_id)), "summary matches mounted context (display names)", summary)
	await capture("ui_round2_boot")

	# ---- 9b. remount through the visible controls keeps everything in sync -------
	var fighters: Array = browser.fighter_ids
	var doge_index := fighters.find("doge_man")
	var ice_index := fighters.find("ice_mage")
	if doge_index >= 0 and ice_index >= 0:
		browser.left_option.select(doge_index)
		browser.right_option.select(ice_index)
	browser._on_remount()
	await settle(30)
	_check(str(runtime.pick_l) == "doge_man" and str(runtime.pick_r) == "ice_mage", "remount applied the visible selection", "%s vs %s" % [str(runtime.pick_l), str(runtime.pick_r)])
	_check(browser.left_option.get_item_text(browser.left_option.selected) == str(runtime.pick_l), "controls stay synced after remount", browser.left_option.get_item_text(browser.left_option.selected))
	var summary2: String = str(browser.summary_button.text)
	_check(summary2.contains("Doge Man") and summary2.contains("Ice Mage"), "summary follows remount", summary2)
	# remount back so the rest of the checks use the canonical context
	if doge_index >= 0 and ice_index >= 0:
		browser.left_option.select(ice_index)
		browser.right_option.select(doge_index)
	browser._on_remount()
	await settle(30)

	# ---- 10. onboarding hint ------------------------------------------------------
	var hint := _find_label_containing(browser, "Select a target")
	_check(hint != null, "onboarding hint present")
	if hint != null:
		var text := str(hint.text)
		_check(text.contains("1.") and text.contains("2.") and text.contains("3.") and text.contains("Apply to Target"), "onboarding lists the three steps", text)

	# ---- 13. copy / paste layer ---------------------------------------------------
	shell._select_key("echo_left", false)
	await settle(10)
	var layers: Array = shell.session.look.get("layers", [])
	var source_id := str((layers[0] as Dictionary).get("layer_id", ""))
	var source_name := str((layers[0] as Dictionary).get("name", ""))
	shell._action_copy_layer(source_id)
	_check(not shell.layer_clipboard.is_empty(), "copy fills the layer clipboard", str(shell.layer_clipboard.get("name", "")))
	_check(str(shell.layer_clipboard.get("layer_id", "")) == source_id, "clipboard keeps the source id")
	var count_before: int = shell.session.look["layers"].size()
	shell._action_paste_layer()
	await settle(6)
	var count_after: int = shell.session.look["layers"].size()
	_check(count_after == count_before + 1, "paste appends a layer", "%d -> %d" % [count_before, count_after])
	var pasted: Dictionary = {}
	for layer in shell.session.look["layers"]:
		if str((layer as Dictionary).get("name", "")) == source_name + " (pasted)":
			pasted = layer
			break
	_check(not pasted.is_empty(), "pasted layer present")
	if not pasted.is_empty():
		_check(str(pasted.get("layer_id", "")) != source_id, "paste assigns a NEW layer id", str(pasted.get("layer_id", "")))
		_check(str(pasted.get("type", "")) == "SOURCE_COPY", "pasted SOURCE becomes SOURCE_COPY", str(pasted.get("type", "")))
		# id stability across rename / reorder / plane move
		var pasted_id := str(pasted.get("layer_id", ""))
		shell._edit_layer(pasted_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, pasted_id)
			l["name"] = "Renamed Keep Id"
			l["plane"] = "TARGET_OVERLAY"
		)
		await settle(4)
		var still: Dictionary = FxLookScript.find_layer(shell.session.look, pasted_id)
		_check(not still.is_empty() and str(still.get("name", "")) == "Renamed Keep Id", "layer id survives rename + plane move", pasted_id)
	await capture("ui_round2_pasted")

	# ---- 8. inspector tabs + user-facing terminology -----------------------------
	var FxTemplatesLocal = load("res://scripts/fx_vnext/fx_templates.gd")
	var fx_id := ""
	for layer in shell.session.look.get("layers", []):
		if str((layer as Dictionary).get("type", "")) == "FX":
			fx_id = str((layer as Dictionary).get("layer_id", ""))
			break
	if fx_id == "":
		shell._action_add_layer("Outer Halo")
		await settle(8)
		for layer in shell.session.look.get("layers", []):
			if str((layer as Dictionary).get("type", "")) == "FX":
				fx_id = str((layer as Dictionary).get("layer_id", ""))
				break
	if fx_id != "":
		shell.selected_layer_id = fx_id
		shell._rebuild_inspector()
		await settle(6)
		var tabs := _find_tab_container(shell.inspector_content)
		_check(tabs != null, "inspector is tabbed for FX layers")
		if tabs != null:
			var names: Array = []
			for child in tabs.get_children():
				names.append(str(child.name))
			_check(names == ["LOOK", "MOTION", "MASK", "PALETTE", "ADVANCED"], "FX tabs are LOOK/MOTION/MASK/PALETTE/ADVANCED", str(names))
			var input_option := _find_option_with_item(tabs, "Original Source")
			_check(input_option != null, "input enum shows the friendly name", "Original Source")
			_check(_find_option_with_item(tabs, "ORIGINAL_SOURCE") == null, "raw enum tokens hidden from primary UX")
			tabs.current_tab = names.find("ADVANCED")
			await settle(4)
			var advanced := _find_label_containing(tabs, "layer_id:")
			_check(advanced != null, "ADVANCED shows raw fields")
		# SOURCE layer tab set
		var source_layer_id := ""
		for layer in shell.session.look.get("layers", []):
			if str((layer as Dictionary).get("type", "")) == "SOURCE":
				source_layer_id = str((layer as Dictionary).get("layer_id", ""))
				break
		if source_layer_id != "":
			shell.selected_layer_id = source_layer_id
			shell._rebuild_inspector()
			await settle(6)
			var tabs2 := _find_tab_container(shell.inspector_content)
			if tabs2 != null:
				var names2: Array = []
				for child in tabs2.get_children():
					names2.append(str(child.name))
				_check(names2 == ["SOURCE", "TRANSFORM", "DISPLACE", "MASK"], "SOURCE tabs are SOURCE/TRANSFORM/DISPLACE/MASK", str(names2))
		else:
			_check(false, "SOURCE layer present for tab check")
	await capture("ui_round2_inspector")

	# ---- 18. scrub reconstruction + event label separation -----------------------
	shell._toggle_timeline_expanded()
	await settle(10)
	_check(shell.timeline_ruler.visible, "timeline ruler expands")
	var t_before: float = float(shell.runtime.elapsed())
	shell._transport_step_forward()
	await settle(4)
	var t_forward: float = float(shell.runtime.elapsed())
	_check(absf((t_forward - t_before) - shell.FRAME_STEP) < 0.001, "frame step forward moves exactly one frame", "%.4f" % (t_forward - t_before))
	_check(absf(float(shell.renderer.get("_last_time")) - t_forward) < 0.001, "layer motion follows the transport", "%.3f" % float(shell.renderer.get("_last_time")))
	shell._transport_step_back()
	await settle(4)
	_check(absf(float(shell.runtime.elapsed()) - t_before) < 0.001, "frame step back returns to the previous time", "%.4f" % (float(shell.runtime.elapsed()) - t_before))
	shell._transport_to_fx_peak()
	await settle(8)
	_check(absf(float(shell.runtime.elapsed()) - 0.615) < 0.001, "FX PEAK jumps to the impact time", "%.3f" % float(shell.runtime.elapsed()))
	var peak_a: Image = await capture("ui_round2_fx_peak")
	shell._transport_to_start()
	shell._transport_to_fx_peak()
	await settle(8)
	var peak_b: Image = await capture("ui_round2_fx_peak_again")
	_check(_region_abs_diff(peak_a, peak_b, Rect2i(0, 0, 1280, 720)) < 0.0005, "FX PEAK rendering is deterministic", "")
	# event labels never overlap (layout data straight from the drawn timeline)
	var rects: Array = shell._timeline_label_rects
	_check(rects.size() >= 4, "timeline exposes event labels", "n=%d" % rects.size())
	var overlaps := 0
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			var a: Dictionary = rects[i]
			var b: Dictionary = rects[j]
			var ax0 := float(a["x"]); var ay0 := float(a["y"])
			var ax1 := ax0 + float(a["w"]); var ay1 := ay0 + float(a["h"])
			var bx0 := float(b["x"]); var by0 := float(b["y"])
			var bx1 := bx0 + float(b["w"]); var by1 := by0 + float(b["h"])
			if ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1:
				overlaps += 1
	_check(overlaps == 0, "event labels do not overlap", "overlaps=%d" % overlaps)
	await capture("ui_round2_timeline")
	shell._toggle_timeline_expanded()
	await settle(6)

	var f := FileAccess.open(out_dir.path_join("summary_ui_round2_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[UI-R2] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _find_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for child in node.get_children():
		var found := _find_tab_container(child)
		if found != null:
			return found
	return null

func _find_option_with_item(node: Node, item_text: String) -> OptionButton:
	if node is OptionButton:
		for i in node.item_count:
			if node.get_item_text(i) == item_text:
				return node
	for child in node.get_children():
		var found := _find_option_with_item(child, item_text)
		if found != null:
			return found
	return null

func _find_label_containing(node: Node, needle: String) -> Label:
	if node is Label and str(node.text).contains(needle):
		return node
	for child in node.get_children():
		var found := _find_label_containing(child, needle)
		if found != null:
			return found
	return null

func _region_abs_diff(a: Image, b: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y, 2):
		for x in range(rect.position.x, rect.position.x + rect.size.x, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(max(count, 1))

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
