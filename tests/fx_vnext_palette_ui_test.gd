# UI-02 palette behavioral proof (windowed, full shell): strategy/locks/H/S/V
# author canonical fx intent, GENERATE materializes fringe_color_a/b per the
# palette contract, save/reopen persists, renderer readback proves effect.
# Chain: UI action -> canonical mutation -> generate -> persistence ->
# renderer -> observable output.
extends SceneTree

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var shell: Control
var checks: Array = []
var failures := 0
var out_dir: String

func _init() -> void:
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/authoring_ui")
	DirAccess.make_dir_recursive_absolute(out_dir)
	shell = _spawn()
	await settle(30)
	_seed()
	shell._select_key("echo_left", false)
	await settle(20)
	_check(shell._session_ready(), "UI-02 session ready on echo_left")
	var layers: Array = shell.session.look.get("layers", [])
	shell.selected_layer_id = str((layers[1] as Dictionary).get("layer_id", ""))
	shell._rebuild_inspector()
	await settle(5)
	shell.runtime.screen.lab_preview_pause()
	await _strategy_select()
	await _source_and_generate()
	await _fringe_readback()
	await _lock_a_stabilizes()
	await _hsv_visible()
	await _save_reopen_persists()
	print("[FX-PALETTE-UI] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func _wipe_dir(abs_path: String) -> void:
	if DirAccess.dir_exists_absolute(abs_path):
		for entry in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(entry))
		for sub in DirAccess.get_directories_at(abs_path):
			_wipe_dir(abs_path.path_join(sub))
			DirAccess.remove_absolute(abs_path.path_join(sub))
	else:
		DirAccess.make_dir_recursive_absolute(abs_path)

func _seed() -> void:
	# Full store isolation: wipe the shell's RESOLVED store dirs (honors
	# NRCU_FX_DATA_DIR/_DRAFT_DIR overrides) before seeding.
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	# Draft slot isolation: the target signature is stable across runs and the
	# shell auto-stashes dirty work, so a previous run's draft would shadow
	# fresh production without this (same reason session tests wipe).
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	var look_id := "UI02_%d" % int(Time.get_unix_time_from_system())
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-02")
	var fx: Dictionary = FxLookScript.new_layer("FX", "ui02")
	look["layers"].append(fx)
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-02 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-02 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-02 seed assignment applies")

func _fx() -> Dictionary:
	return FxLookScript.find_layer(shell.session.look, shell.selected_layer_id)["fx"]


func _palette_page():
	for child in _walk(shell.inspector_content):
		if child is VBoxContainer and (child as VBoxContainer).name == "PALETTE":
			return child
	return shell.inspector_content

func _find_option(label_text: String) -> OptionButton:
	return _find_labeled(_palette_page(), label_text, "OptionButton")

func _find_check(label_text: String) -> CheckBox:
	return _find_check_under(_palette_page(), label_text)

func _find_check_under(node: Node, label_text: String) -> CheckBox:
	# CheckBox rows (e.g. lock row) carry no leading Label: match by button text.
	for child in node.get_children():
		if child is CheckBox and (child as CheckBox).text == label_text:
			return child
		var found := _find_check_under(child, label_text)
		if found != null:
			return found
	return null

func _find_button(prefix: String):
	return _find_button_under(_palette_page(), prefix)

func _find_button_under(node: Node, prefix: String):
	for child in node.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
		var found = _find_button_under(child, prefix)
		if found != null:
			return found
	return null

func _find_labeled(node: Node, label_text: String, cls: String):
	for child in node.get_children():
		if child is HBoxContainer and (child as HBoxContainer).get_child_count() >= 2:
			var lab = (child as HBoxContainer).get_child(0)
			if lab is Label and (lab as Label).text == label_text:
				for sub in (child as HBoxContainer).get_children():
					if sub.get_class() == cls:
						return sub
		var found = _find_labeled(child, label_text, cls)
		if found != null:
			return found
	return null

func _find_picker() -> ColorPickerButton:
	return _find_picker_under(_palette_page())

func _find_picker_under(node: Node):
	for child in node.get_children():
		if child is ColorPickerButton:
			return child
		var found = _find_picker_under(child)
		if found != null:
			return found
	return null

func _find_slider(label_text: String) -> HSlider:
	for child in _walk(_palette_page()):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == label_text:
				for sub in kids:
					if sub is HSlider:
						return sub
	return null

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _preview_diff(a: Image, b: Image) -> float:
	var r: Rect2 = (shell.viewport_host as Control).get_global_rect()
	var w := a.get_width()
	var h := a.get_height()
	var x0 := clampi(int(r.position.x), 0, w - 1)
	var y0 := clampi(int(r.position.y), 0, h - 1)
	var x1 := clampi(int(r.end.x), x0 + 1, w)
	var y1 := clampi(int(r.end.y), y0 + 1, h)
	var sum := 0.0
	var n := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			sum += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			n += 1
	return sum / float(maxi(n, 1)) / 3.0

func _fx_hue() -> float:
	return float(_fx().get("palette_hue_offset", -999.0))

func _strategy_select() -> void:
	var opt := _find_option("Strategy")
	_check(opt != null, "UI-02 Strategy option reachable")
	if opt == null:
		return
	opt.selected = 1
	opt.item_selected.emit(1)
	await settle(5)
	_check(absf(float(_fx().get("palette_strategy", -1.0)) - 1.0) < 0.001, "UI-02 Strategy writes canonical index", str(_fx().get("palette_strategy", "?")))

func _source_and_generate() -> void:
	var picker := _find_picker()
	_check(picker != null, "UI-02 Source color picker reachable")
	if picker == null:
		return
	picker.color = Color(0.9, 0.15, 0.2)
	picker.color_changed.emit(picker.color)
	await settle(5)
	var sc: Array = _fx().get("palette_source_color", [])
	_check(sc.size() >= 3 and absf(float(sc[0]) - 0.9) < 0.01, "UI-02 Source color persists canonically", str(sc))
	# Live regeneration: intent edits regenerate unlocked colors immediately —
	# no stale output behind intent, no separate Generate press required.
	var oracle: Dictionary = FxLookScript.new_look("ORACLE", "o")
	var ofx: Dictionary = FxLookScript.new_layer("FX", "o")
	(oracle["layers"] as Array).append(ofx)
	oracle = FxLookScript.materialize(oracle)
	var olayer: Dictionary = (oracle["layers"] as Array)[1]
	(olayer["fx"] as Dictionary)["palette_strategy"] = 1.0
	(olayer["fx"] as Dictionary)["palette_source_color"] = [0.9, 0.15, 0.2, 1.0]
	var ores: Dictionary = FxLookScript.generate_palette(oracle, str((olayer as Dictionary).get("layer_id", "")), Color(0.9, 0.15, 0.2), Color(1.0, 0.4, 0.85))
	var ofa: Array = ((ores["doc"] as Dictionary)["layers"] as Array)[1]["fx"]["fringe_color_a"]
	var ofb: Array = ((ores["doc"] as Dictionary)["layers"] as Array)[1]["fx"]["fringe_color_b"]
	var fa: Array = _fx().get("fringe_color_a", [])
	var fb: Array = _fx().get("fringe_color_b", [])
	_check(fa.size() >= 3 and absf(float(fa[0]) - float(ofa[0])) < 0.001 and absf(float(fa[1]) - float(ofa[1])) < 0.001, "UI-02 intent edits regenerate A live per contract", "%s vs oracle %s" % [str(fa), str(ofa)])
	_check(fb.size() >= 3 and absf(float(fb[0]) - float(ofb[0])) < 0.001 and absf(float(fb[1]) - float(ofb[1])) < 0.001, "UI-02 intent edits regenerate B live per contract", "%s vs oracle %s" % [str(fb), str(ofb)])

func _find_slider_any(label_text: String) -> HSlider:
	# Unscoped fallback for controls living on other tabs (e.g. LOOK Fringe).
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == label_text:
				for sub in kids:
					if sub is HSlider:
						return sub
	return null

func _fringe_readback() -> void:
	var before: Image = await _capture("ui02_before")
	var slider := _find_slider_any("Fringe")
	if slider == null:
		_check(false, "UI-02 Fringe slider reachable")
		return
	_check(true, "UI-02 Fringe slider reachable")
	slider.value = 1.0
	await settle(8)
	var after: Image = await _capture("ui02_after")
	_check(_preview_diff(before, after) > 0.002, "UI-02 generated palette visibly renders", "mean=%.5f" % _preview_diff(before, after))

func _lock_a_stabilizes() -> void:
	# Decoupled contract: choosing a color sets ONLY the color (lock stays
	# off); the explicit Lock checkbox pins it. Both states reachable via UI.
	var pickers := _find_ab_pickers()
	_check(pickers.size() == 2, "UI-02 A/B color pickers reachable")
	if pickers.size() != 2:
		return
	(pickers[0] as ColorPickerButton).color = Color(0.1, 0.2, 0.3)
	(pickers[0] as ColorPickerButton).color_changed.emit(Color(0.1, 0.2, 0.3))
	await settle(5)
	var fa0: Array = _fx().get("fringe_color_a", [])
	_check(fa0.size() >= 3 and absf(float(fa0[0]) - 0.1) < 0.01, "UI-02 choosing A sets authored color", str(fa0))
	_check(not bool(_fx().get("palette_lock_a", false)), "UI-02 choosing A does NOT surprise-lock", str(_fx().get("palette_lock_a", "?")))
	var lock_a := _find_check("Lock A")
	_check(lock_a != null, "UI-02 Lock A checkbox reachable")
	if lock_a == null:
		return
	lock_a.button_pressed = true
	lock_a.toggled.emit(true)
	await settle(5)
	_check(bool(_fx().get("palette_lock_a", false)), "UI-02 explicit Lock A pins")
	var strat := _find_option("Strategy")
	strat.selected = 4
	strat.item_selected.emit(4)
	await settle(5)
	var fa: Array = _fx().get("fringe_color_a", [])
	var fb: Array = _fx().get("fringe_color_b", [])
	_check(fa.size() >= 3 and absf(float(fa[0]) - 0.1) < 0.01 and absf(float(fa[1]) - 0.2) < 0.01, "UI-02 Lock A stabilizes authored color across strategy change", str(fa))
	# Lock B mirror: choose B, lock explicitly, change strategy, B stable.
	(pickers[1] as ColorPickerButton).color = Color(0.7, 0.1, 0.1)
	(pickers[1] as ColorPickerButton).color_changed.emit(Color(0.7, 0.1, 0.1))
	await settle(5)
	_check(not bool(_fx().get("palette_lock_b", false)), "UI-02 choosing B does NOT surprise-lock")
	var lockb0 := _find_check("Lock B")
	_check(lockb0 != null, "UI-02 Lock B checkbox reachable (pre)")
	if lockb0 == null:
		return
	lockb0.button_pressed = true
	lockb0.toggled.emit(true)
	await settle(5)
	_check(bool(_fx().get("palette_lock_b", false)), "UI-02 explicit Lock B pins")
	strat.selected = 2
	strat.item_selected.emit(2)
	await settle(5)
	var fb2: Array = _fx().get("fringe_color_b", [])
	_check(fb2.size() >= 3 and absf(float(fb2[0]) - 0.7) < 0.01, "UI-02 Lock B stabilizes authored color", str(fb2))
	# Unlock B via checkbox, regenerate: B must react again.
	var lock := _find_check("Lock B")
	_check(lock != null, "UI-02 Lock B checkbox reachable")
	if lock == null:
		return
	lock.button_pressed = false
	lock.toggled.emit(false)
	await settle(5)
	var gen = _find_button("REGENERATE UNLOCKED")
	_check(gen != null, "UI-02 regenerate button reachable")
	if gen == null:
		return
	gen.pressed.emit()
	await settle(5)
	var fb3: Array = _fx().get("fringe_color_b", [])
	_check(fb3.size() >= 3 and absf(float(fb3[0]) - 0.7) > 0.05, "UI-02 unlocked B regenerates on demand", str(fb3))

func _find_ab_pickers() -> Array:
	var out: Array = []
	for child in _walk(_palette_page()):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() == 2 and kids[0] is Label and kids[1] is ColorPickerButton:
				var t := (kids[0] as Label).text
				if t == "A":
					out.insert(0, kids[1])
				elif t == "B":
					out.append(kids[1])
	return out

func _hsv_visible() -> void:
	var before: Array = (_fx().get("fringe_color_b", []) as Array).duplicate()
	var hue := _find_slider("Hue offset")
	_check(hue != null, "UI-02 Hue offset slider reachable")
	if hue == null:
		return
	hue.value = 90.0
	await settle(5)
	var after_hue: Array = _fx().get("fringe_color_b", [])
	var hue_changed := before.size() >= 3 and after_hue.size() >= 3 and (absf(float(before[0]) - float(after_hue[0])) + absf(float(before[1]) - float(after_hue[1])) + absf(float(before[2]) - float(after_hue[2]))) > 0.05
	_check(hue_changed, "UI-02 Hue visibly changes generated color", "%s -> %s" % [str(before), str(after_hue)])
	var sat := _find_slider("Saturation")
	_check(sat != null, "UI-02 Saturation slider reachable")
	if sat == null:
		return
	sat.value = 0.0
	await settle(5)
	var after_sat: Array = _fx().get("fringe_color_b", [])
	_check(after_sat.size() >= 3 and absf(float(after_sat[0]) - float(after_sat[1])) < 0.02 and absf(float(after_sat[1]) - float(after_sat[2])) < 0.02, "UI-02 Saturation 0 grays the color", str(after_sat))
	var val := _find_slider("Value")
	_check(val != null, "UI-02 Value slider reachable")
	if val == null:
		return
	val.value = 2.0
	await settle(5)
	_check(absf(float(_fx().get("palette_value", 0.0)) - 2.0) < 0.01, "UI-02 Value persists canonically")
	var swap := _find_check("Swap A/B")
	_check(swap != null, "UI-02 Swap checkbox reachable")
	if swap == null:
		return
	var img_pre: Image = await _capture("ui02_swap_before")
	swap.button_pressed = true
	swap.toggled.emit(true)
	await settle(8)
	_check(bool(_fx().get("palette_swap", false)), "UI-02 Swap persists canonically")
	var img_post: Image = await _capture("ui02_swap_after")
	_check(_preview_diff(img_pre, img_post) > 0.002, "UI-02 Swap visibly swaps render output", "mean=%.5f" % _preview_diff(img_pre, img_post))

func _save_reopen_persists() -> void:
	var before_a: Array = (_fx().get("fringe_color_a", []) as Array).duplicate()
	var applied: Dictionary = shell.session.apply()
	_check(bool(applied.get("ok", false)), "UI-02 session apply persists", str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var look_id := str(applied.get("look_id", ""))
	var reloaded: Dictionary = shell.production.load_look(look_id)
	_check(bool(reloaded.get("ok", false)), "UI-02 production look reloads")
	if not bool(reloaded.get("ok", false)):
		return
	var found := {}
	for layer in (reloaded["doc"] as Dictionary).get("layers", []):
		if (layer as Dictionary).get("type", "") == "FX":
			found = (layer as Dictionary)["fx"]
	_check(str(found.get("fringe_color_a", [])) == str(before_a), "UI-02 generated colors survive save/reopen", str(found.get("fringe_color_a", [])))
	_check(bool(FxLookScript.validate(reloaded["doc"])["ok"]), "UI-02 reloaded look validates")
