# UI-01 behavioral proof (windowed, full shell): macro/expert/displace/mask
# controls mutate exact canonical keys (never legacy aliases), persist via
# session, reach renderer uniforms, and produce observable readback.
# Chain per control: UI action -> canonical mutation -> session ->
# persistence -> renderer value -> observable output.
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
	_check(shell._session_ready(), "UI-01 session ready on echo_left")
	var layers: Array = shell.session.look.get("layers", [])
	_check(layers.size() == 2, "UI-01 session look has SOURCE+FX", str(layers.size()))
	var fx_id := str((layers[1] as Dictionary).get("layer_id", ""))
	shell.selected_layer_id = fx_id
	shell._rebuild_inspector()
	await settle(5)
	# Freeze transport so readback compares authoring, not animation.
	shell.runtime.screen.lab_preview_pause()
	await _macro_rgb_writes_canonical_key(fx_id)
	await _macro_grade_visible(fx_id)
	await _flow_is_live(fx_id)
	await _dither_threshold_visible(fx_id)
	await _displace_phase_time_editable(fx_id)
	await _custom_texture_incomplete_cycle(fx_id)
	await _expert_typed_edit(fx_id)
	await _numeric_spin_transactions(fx_id)
	await _slider_drag_is_one_transaction(fx_id)
	_inventory_reachability_rose()
	print("[FX-AUTHORING-UI] done · checks=%d failures=%d" % [checks.size(), failures])
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
	# Full store isolation (see palette suite): wipe the shell's RESOLVED
	# store dirs (honors NRCU_FX_DATA_DIR/_DRAFT_DIR overrides) before seeding.
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	# Draft slot isolation (see palette suite): clear the stable target slot.
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	# Unique look per run: user:// production persists across runs and the
	# revision rule would reject re-seeding a fixed id.
	var look_id := "UI01_%d" % int(Time.get_unix_time_from_system())
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-01")
	var fx: Dictionary = FxLookScript.new_layer("FX", "ui01")
	look["layers"].append(fx)
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-01 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-01 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-01 seed assignment applies")

func _fx() -> Dictionary:
	return FxLookScript.find_layer(shell.session.look, shell.selected_layer_id)["fx"]

func _disp() -> Dictionary:
	return FxLookScript.find_layer(shell.session.look, shell.selected_layer_id)["displacement"]

func _find_slider(label_text: String) -> HSlider:
	return _find_slider_under(shell.inspector_content, label_text)

func _find_slider_under(node: Node, label_text: String) -> HSlider:
	for child in node.get_children():
		if child is HBoxContainer:
			var lab = (child as HBoxContainer).get_child(0)
			if lab is Label and (lab as Label).text == label_text:
				for sub in (child as HBoxContainer).get_children():
					if sub is HSlider:
						return sub
		var found := _find_slider_under(child, label_text)
		if found != null:
			return found
	return null

func _find_spin(label_text: String) -> SpinBox:
	return _find_spin_under(shell.inspector_content, label_text)

func _find_spin_under(node: Node, label_text: String) -> SpinBox:
	# Spin rows are HBoxes that may hold several label+spin pairs (Scale +
	# Phase, W/F/±): match any label child, return any spin child.
	for child in node.get_children():
		if child is HBoxContainer:
			var want := false
			var spin: SpinBox = null
			for sub in (child as HBoxContainer).get_children():
				if sub is Label and (sub as Label).text.strip_edges() == label_text:
					want = true
				if sub is SpinBox:
					spin = sub
			# Pair labels to spins positionally when several share one box.
			if want:
				var labels: Array = []
				var spins: Array = []
				for sub in (child as HBoxContainer).get_children():
					if sub is Label:
						labels.append((sub as Label).text.strip_edges())
					if sub is SpinBox:
						spins.append(sub)
				var idx := labels.find(label_text)
				if idx >= 0 and idx < spins.size():
					return spins[idx]
				if spin != null:
					return spin
		var found := _find_spin_under(child, label_text)
		if found != null:
			return found
	return null

func _find_option(label_text: String) -> OptionButton:
	return _find_option_under(shell.inspector_content, label_text)

func _find_option_under(node: Node, label_text: String) -> OptionButton:
	for child in node.get_children():
		if child is HBoxContainer and (child as HBoxContainer).get_child_count() >= 2:
			var lab = (child as HBoxContainer).get_child(0)
			if lab is Label and (lab as Label).text == label_text:
				for sub in (child as HBoxContainer).get_children():
					if sub is OptionButton:
						return sub
		var found := _find_option_under(child, label_text)
		if found != null:
			return found
	return null

func _find_lineedit(label_text: String) -> LineEdit:
	return _find_lineedit_under(shell.inspector_content, label_text)

func _find_lineedit_under(node: Node, label_text: String) -> LineEdit:
	for child in node.get_children():
		if child is HBoxContainer and (child as HBoxContainer).get_child_count() >= 2:
			var lab = (child as HBoxContainer).get_child(0)
			if lab is Label and (lab as Label).text == label_text:
				for sub in (child as HBoxContainer).get_children():
					if sub is LineEdit:
						return sub
		var found := _find_lineedit_under(child, label_text)
		if found != null:
			return found
	return null

func _has_incomplete() -> bool:
	return _has_incomplete_under(shell.inspector_content)

func _has_incomplete_under(node: Node) -> bool:
	for child in node.get_children():
		if child is Label and (child as Label).text.begins_with("⚠ INCOMPLETE"):
			return true
		if _has_incomplete_under(child):
			return true
	return false

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

# The lab window shows browser chrome + preview; readback measures the live
# preview viewport only (browser panel pixels would dilute to exact zero).
func _preview_rect() -> Rect2i:
	var r: Rect2 = (shell.viewport_host as Control).get_global_rect()
	var vp_size := root.size
	var x0 := clampi(int(r.position.x), 0, vp_size.x - 1)
	var y0 := clampi(int(r.position.y), 0, vp_size.y - 1)
	var x1 := clampi(int(r.end.x), 0, vp_size.x)
	var y1 := clampi(int(r.end.y), 0, vp_size.y)
	return Rect2i(x0, y0, maxi(x1 - x0, 8), maxi(y1 - y0, 8))

func _mean_diff(a: Image, b: Image) -> float:
	var roi := _preview_rect()
	var sum := 0.0
	var n := 0
	for y in range(roi.position.y, roi.end.y, 3):
		for x in range(roi.position.x, roi.end.x, 3):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			sum += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			n += 1
	return sum / float(maxi(n, 1)) / 3.0

# ---- proofs ----
func _macro_rgb_writes_canonical_key(fx_id: String) -> void:
	var slider := _find_slider("Shift px")
	_check(slider != null, "UI-01 Shift-px macro slider reachable")
	if slider == null:
		return
	slider.value = 30.0
	await settle(5)
	var fx: Dictionary = _fx()
	_check(absf(float(fx.get("rgb_shift_amount", -1.0)) - 30.0) < 0.001, "UI-01 macro writes rgb_shift_amount", str(fx.get("rgb_shift_amount", "?")))
	_check(not fx.has("rgb_shift"), "UI-01 macro writes no legacy rgb_shift alias", str(fx.keys()))

func _macro_grade_visible(fx_id: String) -> void:
	var amount := _find_slider("Grade amount")
	_check(amount != null, "UI-01 Grade amount macro slider reachable")
	if amount == null:
		return
	amount.value = 1.0
	await settle(5)
	var before: Image = await _capture("ui01_grade_before")
	var slider := _find_slider("Brightness")
	_check(slider != null, "UI-01 Brightness macro slider reachable")
	if slider == null:
		return
	slider.value = 0.5
	await settle(8)
	var after: Image = await _capture("ui01_grade_after")
	_check(absf(float(_fx().get("grade_brightness", 0.0)) - 0.5) < 0.001, "UI-01 Brightness persists in session")
	_check(_mean_diff(before, after) > 0.002, "UI-01 Brightness visibly renders", "mean=%.5f" % _mean_diff(before, after))

func _flow_is_live(fx_id: String) -> void:
	var slider := _find_slider("Flow")
	_check(slider != null, "UI-01 Flow macro slider reachable")
	if slider == null:
		return
	# Dependency honesty: flow without fringe is a documented no-op.
	slider.value = 2.0
	await settle(5)
	slider.value = 0.0
	await settle(5)
	var fringe := _find_slider("Fringe")
	_check(fringe != null, "UI-01 Fringe macro slider reachable")
	if fringe == null:
		return
	var before: Image = await _capture("ui01_flow_before")
	fringe.value = 1.0
	await settle(5)
	slider.value = 2.0
	await settle(8)
	var after: Image = await _capture("ui01_flow_after")
	_check(_mean_diff(before, after) > 0.001, "UI-01 Flow drives the fringe field visibly", "mean=%.5f" % _mean_diff(before, after))

func _dither_threshold_visible(fx_id: String) -> void:
	# CT-10 contract: dither_threshold is LEGACY_DEAD_SURFACE — persisted +
	# validated + passed through, but no control anywhere and no render effect.
	# (The MONO "Threshold" slider below is mono_threshold — setting it must
	# leave dither_threshold untouched.)
	var mono_thresh := _find_slider("Threshold")
	_check(mono_thresh != null, "UI-01 mono Threshold macro slider reachable")
	if mono_thresh == null:
		return
	mono_thresh.value = 0.2
	await settle(5)
	_check(absf(float(_fx().get("dither_threshold", 0.75)) - 0.75) < 0.001, "UI-01 Threshold macro writes mono only, never dither_threshold")
	_check(_find_spin("dither_threshold") == null, "UI-01 dead Threshold has no expert control either")
	# Vary through the full range via session: value round-trips, pixels identical.
	shell.session.edit(func(doc):
		(FxLookScript.find_layer(doc, shell.selected_layer_id)["fx"] as Dictionary)["dither_threshold"] = 0.0
	)
	shell._render_current_look()
	await settle(5)
	_check(absf(float(_fx().get("dither_threshold", -1.0)) - 0.0) < 0.001, "UI-01 dead Threshold value round-trips losslessly")
	var img_zero: Image = await _capture("ui01_thresh_zero")
	shell.session.edit(func(doc):
		(FxLookScript.find_layer(doc, shell.selected_layer_id)["fx"] as Dictionary)["dither_threshold"] = 1.0
	)
	shell._render_current_look()
	await settle(8)
	var img_one: Image = await _capture("ui01_thresh_one")
	_check(_mean_diff(img_zero, img_one) == 0.0, "UI-01 dead Threshold has zero render effect (CT-10)")
	var dither := _find_slider("Dither")
	if dither == null:
		_check(false, "UI-01 Dither macro slider reachable")
		return
	_check(true, "UI-01 Dither macro slider reachable")
	dither.value = 0.0
	await settle(5)
	var before: Image = await _capture("ui01_dith_before")
	dither.value = 1.0
	await settle(8)
	_check(absf(float(_fx().get("dither", 0.0)) - 1.0) < 0.001, "UI-01 Dither persists in session", str(_fx().get("dither", "?")))
	var after: Image = await _capture("ui01_dith_after")
	_check(_mean_diff(before, after) > 0.001, "UI-01 Dither visibly renders", "mean=%.5f" % _mean_diff(before, after))

func _displace_phase_time_editable(fx_id: String) -> void:
	var spin := _find_spin("Phase")
	_check(spin != null, "UI-01 displacement Phase spin reachable")
	if spin == null:
		return
	spin.value = 1.5
	await settle(5)
	_check(absf(float(_disp().get("phase", 0.0)) - 1.5) < 0.001, "UI-01 Phase edits canonical displacement", str((_disp().get("phase", "?"))))
	var opt := _find_option("Time")
	_check(opt != null, "UI-01 displacement time_source option reachable")
	if opt == null:
		return
	opt.selected = 1
	opt.item_selected.emit(1)
	await settle(5)
	_check(str(_disp().get("time_source", "")) == "FREE_RUN", "UI-01 time_source edits to FREE_RUN", str(_disp().get("time_source", "")))

func _custom_texture_incomplete_cycle(fx_id: String) -> void:
	var driver := _find_option("Driver")
	_check(driver != null, "UI-01 displacement Driver option reachable")
	if driver == null:
		return
	driver.selected = 5
	driver.item_selected.emit(5)
	await settle(5)
	_check(_has_incomplete(), "UI-01 CUSTOM driver without asset shows INCOMPLETE")
	var edit := _find_lineedit("Custom tex")
	_check(edit != null, "UI-01 Custom tex asset row reachable")
	if edit == null:
		return
	edit.text = "res://assets/vs/generated/accent_left_mask.png"
	edit.text_submitted.emit(edit.text)
	await settle(5)
	_check(str(_disp().get("custom_texture", "")) == "res://assets/vs/generated/accent_left_mask.png", "UI-01 asset path persists in session")
	_check(not _has_incomplete(), "UI-01 INCOMPLETE clears after asset set")

func _numeric_spin_transactions(fx_id: String) -> void:
	await _probe_spin_transaction("Phase", "phase", true, [0.3, 0.7, 1.1])
	await _probe_spin_transaction("signal_gain", "signal_gain", false, [1.1, 1.7, 2.1])

func _probe_spin_transaction(label_text: String, field: String, displacement: bool, values: Array) -> void:
	var spin := _find_spin(label_text)
	_check(spin != null, "UI-13 %s SpinBox transaction probe reachable" % label_text)
	if spin == null:
		return
	var before := float((_disp() if displacement else _fx()).get(field, 0.0))
	shell._ui_transactions.clear()
	shell.session._undo_stack.clear()
	for value in values:
		spin.value = float(value)
		await settle(1)
	await settle(20)
	_check(shell.session._undo_stack.size() == 1, "UI-13 %s intermediate edits create one undo transaction" % label_text, "stack=%d" % shell.session._undo_stack.size())
	var undone: bool = shell.session.undo()
	await settle(2)
	var after_undo := float((_disp() if displacement else _fx()).get(field, 0.0))
	_check(undone and absf(after_undo - before) < 0.001, "UI-13 %s undo restores exact pre-edit value" % label_text, "before=%.3f after=%.3f" % [before, after_undo])
	var redone: bool = shell.session.redo()
	await settle(2)
	var after_redo := float((_disp() if displacement else _fx()).get(field, 0.0))
	_check(redone and absf(after_redo - float(values[values.size() - 1])) < 0.001, "UI-13 %s redo restores exact final value" % label_text, "final=%.3f after=%.3f" % [float(values[values.size() - 1]), after_redo])

func _slider_drag_is_one_transaction(fx_id: String) -> void:
	var slider := _find_slider("Brightness")
	_check(slider != null, "UI-13 slider transaction probe reachable")
	if slider == null:
		return
	shell._refresh_inspector_cost()
	_check(shell.inspector_cost_badge != null and shell.inspector_cost_badge.text.begins_with("LIVE COST"), "UI-17 live cost badge is visible")
	slider.grab_focus()
	shell._rebuild_inspector()
	await settle(2)
	_check(shell._focused_canonical_field() == "grade_brightness", "UI-16 inspector remount restores canonical focus", shell._focused_canonical_field())
	_check(shell.recipe_rows != null and shell.recipe_rows.get_child_count() == 6, "UI-18 recipe library is separate from Production inventory")
	# The remount intentionally replaces the old node; continue with the new
	# canonical control rather than touching a freed reference.
	slider = _find_slider("Brightness")
	# A drag emits many value_changed events but must create one history entry.
	shell._ui_transactions.clear()
	shell.session._undo_stack.clear()
	var before: float = float(_fx().get("grade_brightness", 0.0))
	var n0: int = shell.session._undo_stack.size()
	for value in [0.15, 0.30, 0.45, 0.60]:
		slider.value = value
		await settle(1)
	shell._end_ui_transaction("fx:%s:%s" % [fx_id, "grade_brightness"])
	_check(shell.session._undo_stack.size() == n0 + 1, "UI-13 slider drag is one undo transaction", "before=%d after=%d" % [n0, shell.session._undo_stack.size()])
	shell._action_undo()
	await settle(4)
	_check(absf(float(_fx().get("grade_brightness", 0.0)) - before) < 0.001, "UI-13 one undo restores pre-drag value", "before=%.3f after=%.3f" % [before, float(_fx().get("grade_brightness", 0.0))])

func _expert_typed_edit(fx_id: String) -> void:
	var spin := _find_spin("signal_gain")
	_check(spin != null, "UI-01 expert signal_gain spin reachable")
	if spin == null:
		return
	spin.value = 2.5
	await settle(5)
	_check(absf(float(_fx().get("signal_gain", 0.0)) - 2.5) < 0.001, "UI-01 expert edit writes exact canonical field", str(_fx().get("signal_gain", "?")))

func _inventory_reachability_rose() -> void:
	# Behavioral gate: the UI-01 controls must exist for the headline fields.
	# ("Threshold" is deliberately NOT a macro: declaration-only legacy field.)
	for label_text in ["Shift px", "Brightness", "Levels", "Phase", "Custom tex", "signal_gain", "Grade amount"]:
		var found := _find_slider(label_text) != null or _find_spin(label_text) != null or _find_lineedit(label_text) != null
		_check(found, "UI-01 inventory: %s reachable" % label_text)
