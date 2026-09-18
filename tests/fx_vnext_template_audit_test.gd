extends SceneTree
# UI-06 template hidden-state audit (windowed): every template is added
# through the REAL UI action; every defining creative value it sets must be
# findable/editable in the normal or advanced inspector (tagged
# canonical_field controls) — no hidden creative state. Save/reopen keeps
# values (dict equality) and rendering (pixel parity, frozen clock).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxTemplatesScript := preload("res://scripts/fx_vnext/fx_templates.gd")

var shell: Control
var checks: Array = []
var failures := 0
var out_dir: String
var look_id := ""
var template_layers := {}

func _init() -> void:
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/template_audit")
	DirAccess.make_dir_recursive_absolute(out_dir)
	shell = _spawn()
	await settle(30)
	_seed()
	shell._select_key("echo_left", false)
	await settle(20)
	_check(shell._session_ready(), "UI-06 session ready on echo_left")
	shell.runtime.screen.lab_preview_pause()
	for template in FxTemplatesScript.TEMPLATES:
		await _audit_template(str(template))
	await _edit_wiring()
	await _save_reopen_parity()
	print("[FX-TEMPLATE-AUDIT] done · checks=%d failures=%d" % [checks.size(), failures])
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
	# Full store isolation (palette pattern): wipe resolved store dirs and
	# the stable target slot so template layers cannot accumulate across runs.
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	look_id = "UI06_%d" % int(Time.get_unix_time_from_system())
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-06")
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-06 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-06 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-06 seed assignment applies")

func _tagged_fields() -> Dictionary:
	var found := {}
	for child in _walk(shell.inspector_content):
		if child is Object and (child as Object).has_meta("canonical_field"):
			var f := str((child as Object).get_meta("canonical_field"))
			found[f] = int(found.get(f, 0)) + 1
	return found

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _audit_template(template: String) -> void:
	var before: int = (shell.session.look.get("layers", []) as Array).size()
	shell._action_add_layer(template)
	await settle(8)
	var layers: Array = shell.session.look.get("layers", [])
	_check(layers.size() == before + 1, "UI-06 %s adds one layer via UI" % template, str(layers.size()))
	if layers.size() != before + 1:
		return
	var layer: Dictionary = layers[layers.size() - 1]
	template_layers[template] = str(layer.get("layer_id", ""))
	# Defining values = what the template constructor sets BEYOND neutral
	# defaults (template_layer returns full layers, so diff against a
	# neutral sibling; str() comparison covers arrays and floats).
	var spec: Dictionary = FxTemplatesScript.template_layer(template)
	_check(str(layer.get("type", "")) == str(spec.get("type", "")), "UI-06 %s type persists" % template, str(layer.get("type", "")))
	var neutral: Dictionary = FxLookScript.new_layer(str(spec.get("type", "FX")), "neutral-ref")
	var spec_fx: Dictionary = spec.get("fx", {})
	var neutral_fx: Dictionary = neutral.get("fx", {})
	var defining_fx := {}
	for k in spec_fx.keys():
		if str(spec_fx[k]) != str(neutral_fx.get(k, null)):
			defining_fx[k] = spec_fx[k]
	var sess_fx: Dictionary = (layer.get("fx", {}) as Dictionary) if layer.get("fx", {}) is Dictionary else {}
	var lost: Array = []
	for k in defining_fx.keys():
		if str(sess_fx.get(k, null)) != str(defining_fx[k]):
			lost.append(str(k))
	_check(lost.is_empty(), "UI-06 %s defining fx survives" % template, str(lost))
	var spec_mask: Dictionary = spec.get("mask", {})
	var neutral_mask: Dictionary = neutral.get("mask", {})
	var defining_mask := {}
	for k in spec_mask.keys():
		if str(spec_mask[k]) != str(neutral_mask.get(k, null)):
			defining_mask[k] = spec_mask[k]
	var sess_mask: Dictionary = (layer.get("mask", {}) as Dictionary) if layer.get("mask", {}) is Dictionary else {}
	var mlost: Array = []
	for k in defining_mask.keys():
		if str(sess_mask.get(k, null)) != str(defining_mask[k]):
			mlost.append(str(k))
	_check(mlost.is_empty(), "UI-06 %s defining mask survives" % template, str(mlost))
	if str(spec.get("plane", "")) != "":
		_check(str(layer.get("plane", "")) == str(spec.get("plane", "")), "UI-06 %s plane persists" % template, str(layer.get("plane", "")))
	if str(spec.get("input", "")) != "":
		_check(str(layer.get("input", "")) == str(spec.get("input", "")), "UI-06 %s input persists" % template, str(layer.get("input", "")))
	# Every defining value must be authorable: tagged control exists.
	shell.selected_layer_id = str(layer.get("layer_id", ""))
	shell._rebuild_inspector()
	await settle(5)
	var found := _tagged_fields()
	var unreached: Array = []
	for k in defining_fx.keys():
		if int(found.get(str(k), 0)) == 0:
			unreached.append("fx." + str(k))
	for k in defining_mask.keys():
		if int(found.get("mask." + str(k), 0)) == 0:
			unreached.append("mask." + str(k))
	if str(spec.get("plane", "")) != "" and int(found.get("layer.plane", 0)) == 0:
		unreached.append("layer.plane")
	if str(spec.get("input", "")) != "" and int(found.get("layer.input", 0)) == 0:
		unreached.append("layer.input")
	_check(unreached.is_empty(), "UI-06 %s no hidden creative state" % template, str(unreached))

func _wipe_dir(abs_path: String) -> void:
	if DirAccess.dir_exists_absolute(abs_path):
		for entry in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(entry))
		for sub in DirAccess.get_directories_at(abs_path):
			_wipe_dir(abs_path.path_join(sub))
			DirAccess.remove_absolute(abs_path.path_join(sub))
	else:
		DirAccess.make_dir_recursive_absolute(abs_path)

func _edit_wiring() -> void:
	# Defining edit on the Dither Treatment layer: UI control -> canonical.
	if not template_layers.has("Dither Treatment"):
		_check(false, "UI-06 edit wiring needs the Dither Treatment layer")
		return
	shell.selected_layer_id = str(template_layers["Dither Treatment"])
	shell._rebuild_inspector()
	await settle(5)
	# dither_pixel lives as the LOOK macro slider ("Pixel"): drive it by tag.
	var slider := _find_slider_by_tag("dither_pixel")
	_check(slider != null, "UI-06 template defining slider reachable")
	if slider == null:
		return
	slider.value = float(slider.max_value)
	await settle(5)
	var lid := str(template_layers["Dither Treatment"])
	var fx: Dictionary = FxLookScript.find_layer(shell.session.look, lid)["fx"]
	_check(absf(float(fx.get("dither_pixel", 0.0)) - float(slider.max_value)) < 0.01, "UI-06 template edit writes canonical", str(fx.get("dither_pixel", "?")))

func _find_slider_by_tag(field_id: String) -> HSlider:
	for child in _walk(shell.inspector_content):
		if child is Object and (child as Object).has_meta("canonical_field") and str((child as Object).get_meta("canonical_field")) == field_id:
			if child is HSlider:
				return child
			if child is HBoxContainer:
				for sub in (child as HBoxContainer).get_children():
					if sub is HSlider:
						return sub
	return null

func _find_spin(field_id: String) -> SpinBox:
	# Find via the canonical_field tag (robust against label layout),
	# then take the row's spin child.
	for child in _walk(shell.inspector_content):
		if child is Object and (child as Object).has_meta("canonical_field") and str((child as Object).get_meta("canonical_field")) == field_id:
			if child is SpinBox:
				return child
			if child is HBoxContainer:
				for sub in (child as HBoxContainer).get_children():
					if sub is SpinBox:
						return sub
					for sub2 in (sub as Node).get_children() if sub is Container else []:
						if sub2 is SpinBox:
							return sub2
	return null

func _save_reopen_parity() -> void:
	# Persist everything, reload from disk, prove values + rendering equal.
	var pre: Image = await _capture("ui06_pre")
	var applied: Dictionary = shell.session.apply()
	_check(bool(applied.get("ok", false)), "UI-06 session applies to production", str(applied.get("errors", [])))
	# Apply may persist under a fresh id (unique_look_id): reload THAT doc,
	# never the stale seed id.
	if str(applied.get("verified_look_id", "")) != "":
		look_id = str(applied.get("verified_look_id"))
	var loaded: Dictionary = shell.production.load_look(look_id)
	_check(bool(loaded.get("ok", false)), "UI-06 look reloads from disk")
	if not bool(loaded.get("ok", false)):
		return
	var doc: Dictionary = loaded["doc"]
	var mism: Array = []
	for template in template_layers.keys():
		var lid := str(template_layers[template])
		var a = FxLookScript.find_layer(shell.session.look, lid)
		var b = FxLookScript.find_layer(doc, lid)
		if (a as Dictionary).is_empty() or (b as Dictionary).is_empty():
			mism.append(str(template) + ":missing")
			continue
		if str(JSON.stringify((a as Dictionary).get("fx", {}))) != str(JSON.stringify((b as Dictionary).get("fx", {}))):
			mism.append(str(template) + ":fx")
		if str(JSON.stringify((a as Dictionary).get("mask", {}))) != str(JSON.stringify((b as Dictionary).get("mask", {}))):
			mism.append(str(template) + ":mask")
	_check(mism.is_empty(), "UI-06 save/reopen keeps template values", str(mism))
	var post: Image = await _capture("ui06_post")
	_check(_mean_abs_diff(pre, post) < 0.0005, "UI-06 save/reopen keeps rendering", "mean=%.6f" % _mean_abs_diff(pre, post))

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(max(count, 1))
