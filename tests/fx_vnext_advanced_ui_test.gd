# UI-05 behavioral proof (windowed): expert controls are truly typed —
# enums are named options (never raw number codes), hue is degrees, bools are
# grouped ≤3 per row, and edits write exact canonical keys.
extends SceneTree

var shell: Control
var checks: Array = []
var failures := 0

func _init() -> void:
	shell = _spawn()
	await settle(30)
	_seed()
	shell._select_key("echo_left", false)
	await settle(20)
	var layers: Array = shell.session.look.get("layers", [])
	var fx_id := str((layers[1] as Dictionary).get("layer_id", ""))
	shell.selected_layer_id = fx_id
	shell._rebuild_inspector()
	await settle(5)
	shell.runtime.screen.lab_preview_pause()
	_hue_units(fx_id)
	_enums_are_options()
	_bools_layout()
	_option_edit_writes_canonical(fx_id)
	_check_edit_writes_canonical(fx_id)
	_meta_leak_audit()
	print("[FX-ADVANCED-UI] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
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

func _seed() -> void:
	var look_id := "UI05_%d" % int(Time.get_unix_time_from_system())
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-05")
	var fx: Dictionary = FxLookScript.new_layer("FX", "ui05")
	look["layers"].append(fx)
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-05 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-05 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-05 seed assignment applies")

func _fx() -> Dictionary:
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	return FxLookScript.find_layer(shell.session.look, shell.selected_layer_id)["fx"]

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _option_for(label_text: String) -> OptionButton:
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == label_text:
				for sub in kids:
					if sub is OptionButton:
						return sub
	return null

func _spin_for(label_text: String) -> SpinBox:
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == label_text:
				for sub in kids:
					if sub is SpinBox:
						return sub
	return null

func _check_for(label_text: String) -> CheckBox:
	for child in _walk(shell.inspector_content):
		if child is CheckBox and (child as CheckBox).text == label_text:
			return child
	return null

func _hue_units(_fx_id: String) -> void:
	var spin := _spin_for("palette_hue_offset")
	_check(spin != null, "UI-05 expert hue spin reachable")
	if spin == null:
		return
	_check(absf(spin.max_value - 180.0) < 0.001 and absf(spin.min_value + 180.0) < 0.001, "UI-05 expert hue in degrees", "min=%s max=%s" % [str(spin.min_value), str(spin.max_value)])
	spin.value = 90.0
	await settle(5)
	_check(absf(float(_fx().get("palette_hue_offset", 0.0)) - 90.0) < 0.001, "UI-05 expert hue edit writes degrees", str(_fx().get("palette_hue_offset", "?")))

func _enums_are_options() -> void:
	var matrix := [["palette_strategy", 6], ["driver_mode", 14], ["mono_mode", 6], ["dither_mode", 6], ["fringe_blend_mode", 3], ["fringe_coverage_mode", 6], ["edge_source_mode", 3], ["time_source", 2]]
	for row in matrix:
		var opt := _option_for(str(row[0]))
		_check(opt != null, "UI-05 %s is a named option, not a number" % str(row[0]))
		if opt != null:
			_check(opt.item_count == int(row[1]), "UI-05 %s has %d named items" % [str(row[0]), int(row[1])], str(opt.item_count))
	# base_mode lives as a LOOK macro under its friendly label (meta-driven too).
	var base := _option_for("base_mode")
	if base == null:
		base = _option_for("Base")
	_check(base != null and base.item_count == 2, "UI-05 base_mode is a named 2-item option")

func _bools_layout() -> void:
	var worst := 0
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var n := 0
			for sub in (child as HBoxContainer).get_children():
				if sub is CheckBox:
					n += 1
			worst = maxi(worst, n)
	_check(worst <= 3, "UI-05 no bool pile-up row (max 3)", "worst=%d" % worst)

func _option_edit_writes_canonical(_fx_id: String) -> void:
	var opt := _option_for("palette_strategy")
	_check(opt != null, "UI-05 strategy option reachable (edit)")
	if opt == null:
		return
	opt.select(2)
	opt.item_selected.emit(2)
	await settle(5)
	_check(absf(float(_fx().get("palette_strategy", -1.0)) - 2.0) < 0.001, "UI-05 strategy option writes canonical index", str(_fx().get("palette_strategy", "?")))
	var topt := _option_for("time_source")
	if topt != null:
		topt.select(1)
		topt.item_selected.emit(1)
		await settle(5)
		_check(str(_fx().get("time_source", "")) == "FREE_RUN", "UI-05 string enum writes canonical value", str(_fx().get("time_source", "?")))
	else:
		_check(false, "UI-05 time_source option reachable")

func _meta_leak_audit() -> void:
	# Behavioral creative-leak audit: every built creative control carries
	# its canonical field id; compat/rejected fields must own NO creative
	# control anywhere in the inspector (macros, expert, palette).
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var meta: Dictionary = FxLookScript.field_meta_all()
	var found := {}
	for child in _walk(shell.inspector_content):
		if child is Object and (child as Object).has_meta("canonical_field"):
			var f := str((child as Object).get_meta("canonical_field"))
			found[f] = int(found.get(f, 0)) + 1
	var creative := ["amount", "int", "option", "check", "color", "asset"]
	var missing: Array = []
	var leaked: Array = []
	for key in meta.keys():
		var kind := str((meta[key] as Dictionary).get("kind", ""))
		if kind in creative and int(found.get(str(key), 0)) == 0:
			missing.append(str(key))
		if (kind == "compat" or kind == "rejected") and int(found.get(str(key), 0)) > 0:
			leaked.append(str(key))
	_check(missing.is_empty(), "UI-05 every creative field has a control", str(missing))
	_check(leaked.is_empty(), "UI-05 compat/rejected own no creative control", str(leaked))
	_check(str(found.get("dither_threshold", 0)) == "0", "UI-05 dither_threshold has no control")
	_check(str(found.get("edge_mask_path", 0)) == "0", "UI-05 edge_mask_path has no control")

func _check_edit_writes_canonical(_fx_id: String) -> void:
	var check := _check_for("palette_lock_a")
	_check(check != null, "UI-05 expert lock checkbox reachable")
	if check == null:
		return
	check.button_pressed = true
	check.toggled.emit(true)
	await settle(5)
	_check(bool(_fx().get("palette_lock_a", false)), "UI-05 expert check writes canonical bool")
