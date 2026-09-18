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
	await _reproduce_templates()
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

func _defining_values(spec: Dictionary) -> Dictionary:
	# Template constructor values BEYOND neutral defaults (str comparison
	# covers arrays and floats). Shared by audit + reproduction. Covers all
	# creative categories: fx, mask, plane, input, transform, displacement,
	# motion. Structural identity (layer_id/name/revision) is never creative.
	var neutral: Dictionary = FxLookScript.new_layer(str(spec.get("type", "FX")), "neutral-ref")
	var out := {"fx": {}, "mask": {}, "plane": "", "input": "", "extra": {}}
	var spec_fx: Dictionary = spec.get("fx", {})
	var neutral_fx: Dictionary = neutral.get("fx", {})
	for k in spec_fx.keys():
		if str(spec_fx[k]) != str(neutral_fx.get(k, null)):
			(out["fx"] as Dictionary)[k] = spec_fx[k]
	var spec_mask: Dictionary = spec.get("mask", {})
	var neutral_mask: Dictionary = neutral.get("mask", {})
	for k in spec_mask.keys():
		if str(spec_mask[k]) != str(neutral_mask.get(k, null)):
			(out["mask"] as Dictionary)[k] = spec_mask[k]
	var neutral_plane := str(neutral.get("plane", ""))
	if str(spec.get("plane", neutral_plane)) != neutral_plane:
		out["plane"] = str(spec.get("plane", ""))
	var neutral_input := str(neutral.get("input", ""))
	if str(spec.get("input", neutral_input)) != neutral_input:
		out["input"] = str(spec.get("input", ""))
	for cat in ["transform", "displacement", "motion"]:
		var s: Dictionary = spec.get(cat, {})
		var n: Dictionary = neutral.get(cat, {})
		for k in s.keys():
			if str(s[k]) != str(n.get(k, null)):
				(out["extra"] as Dictionary)[cat + "." + str(k)] = s[k]
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
	# Defining values = constructor values beyond neutral (shared helper).
	var spec: Dictionary = FxTemplatesScript.template_layer(template)
	_check(str(layer.get("type", "")) == str(spec.get("type", "")), "UI-06 %s type persists" % template, str(layer.get("type", "")))
	var defining: Dictionary = _defining_values(spec)
	var defining_fx: Dictionary = defining["fx"]
	var defining_mask: Dictionary = defining["mask"]
	var sess_fx: Dictionary = (layer.get("fx", {}) as Dictionary) if layer.get("fx", {}) is Dictionary else {}
	var lost: Array = []
	for k in defining_fx.keys():
		if str(sess_fx.get(k, null)) != str(defining_fx[k]):
			lost.append(str(k))
	_check(lost.is_empty(), "UI-06 %s defining fx survives" % template, str(lost))
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
	for k in (defining["extra"] as Dictionary).keys():
		# transform/displacement/motion values have no tagged authoring
		# controls today: any defining value here keeps UI-06 honestly open.
		unreached.append(str(k))
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

func _reproduce_templates() -> void:
	# Manual reproduction: blank layer of the same type, then every defining
	# value set through its tagged UI control. Final canonical state must
	# equal the template constructor (creative identity, not ids/names).
	for template in FxTemplatesScript.TEMPLATES:
		await _reproduce_template(str(template))

func _reproduce_template(template: String) -> void:
	var spec: Dictionary = FxTemplatesScript.template_layer(template)
	var defining: Dictionary = _defining_values(spec)
	var blank_kind := "Source Copy" if str(spec.get("type", "")) == "SOURCE_COPY" else "Custom FX Layer"
	var before: int = (shell.session.look.get("layers", []) as Array).size()
	shell._action_add_layer(blank_kind)
	await settle(8)
	var layers: Array = shell.session.look.get("layers", [])
	if layers.size() != before + 1:
		_check(false, "UI-06 reproduce %s adds blank layer" % template, "mode=%s status=%s" % [str(shell.session.mode if shell.session != null else "?"), str(shell.action_status.text if shell.action_status != null else "?")])
		return
	var blank: Dictionary = layers[layers.size() - 1]
	var bid := str(blank.get("layer_id", ""))
	# Templates with no defining values (Custom FX Layer) reproduce
	# trivially: the blank constructor IS the template.
	if (defining["fx"] as Dictionary).is_empty() and (defining["mask"] as Dictionary).is_empty() and str(defining["plane"]) == "" and str(defining["input"]) == "" and (defining["extra"] as Dictionary).is_empty():
		_check(str(blank.get("type", "")) == str(spec.get("type", "")), "UI-06 reproduce %s trivially blank" % template)
		return
	shell.selected_layer_id = bid
	shell._rebuild_inspector()
	await settle(5)
	# Disturb first: guarantees the final equality came from UI writes.
	_disturb_first(defining, template)
	for k in (defining["fx"] as Dictionary).keys():
		_drive_fx(str(k), (defining["fx"] as Dictionary)[k], template)
	for k in (defining["mask"] as Dictionary).keys():
		_drive_mask(str(k), (defining["mask"] as Dictionary)[k], template)
	if str(defining["plane"]) != "":
		_drive_option("layer.plane", str(defining["plane"]), template)
	if str(defining["input"]) != "":
		_drive_option("layer.input", str(defining["input"]), template)
	if failures > 0:
		return
	var got: Dictionary = FxLookScript.find_layer(shell.session.look, bid)
	var bad: Array = []
	for k in (defining["fx"] as Dictionary).keys():
		if str((got.get("fx", {}) as Dictionary).get(k, null)) != str(((defining["fx"] as Dictionary)[k])):
			bad.append("fx." + str(k))
	for k in (defining["mask"] as Dictionary).keys():
		if str((got.get("mask", {}) as Dictionary).get(k, null)) != str(((defining["mask"] as Dictionary)[k])):
			bad.append("mask." + str(k))
	if str(defining["plane"]) != "" and str(got.get("plane", "")) != str(defining["plane"]):
		bad.append("layer.plane")
	if str(defining["input"]) != "" and str(got.get("input", "")) != str(defining["input"]):
		bad.append("layer.input")
	for k in (defining["extra"] as Dictionary).keys():
		# No UI drivers for transform/displacement/motion yet: any defining
		# value here fails loudly instead of passing silently.
		bad.append(str(k) + ":no-driver")
	_check(bad.is_empty(), "UI-06 reproduce %s equals template" % template, str(bad))

func _disturb_first(defining: Dictionary, template: String) -> void:
	# Move one defining field AWAY from the template value (neutral/other),
	# so the later equality can only come from the UI drives below.
	var dfx: Dictionary = defining["fx"]
	if not dfx.is_empty():
		var k := str(dfx.keys()[0])
		var FxLookScriptLocal = load("res://scripts/fx_vnext/fx_look.gd")
		var kind := str(((FxLookScriptLocal.field_meta_all().get(k, {}) as Dictionary).get("kind", "amount")))
		if kind == "check":
			_drive_fx(k, not bool(dfx[k]), template)
			return
		elif kind == "amount" or kind == "int":
			_drive_fx(k, 0.0 if float(dfx[k]) != 0.0 else 1.0, template)
			return
		# option-kind fx falls through to mask/plane disturb below.
	var dm: Dictionary = defining["mask"]
	if not dm.is_empty():
		var k := str(dm.keys()[0])
		if k == "enabled" or k == "invert":
			_drive_mask(k, not bool(dm[k]), template)
		elif k == "width_px" or k == "feather_px" or k == "expand_px":
			_drive_mask(k, 0.0 if float(dm[k]) != 0.0 else 40.0, template)
		return
	if str(defining["plane"]) != "":
		_drive_option("layer.plane", "TARGET_OVERLAY" if str(defining["plane"]) != "TARGET_OVERLAY" else "TARGET_UNDERLAY", template)
		return
	if str(defining["input"]) != "":
		_drive_option("layer.input", "ORIGINAL_SOURCE" if str(defining["input"]) != "ORIGINAL_SOURCE" else "FLAT_COLOR", template)

func _tagged_node(field_id: String):
	for child in _walk(shell.inspector_content):
		if child is Object and (child as Object).has_meta("canonical_field") and str((child as Object).get_meta("canonical_field")) == field_id:
			return child
	return null

func _control_in(node) -> Control:
	# First interactive child (rows wrap label + control).
	if node is HSlider or node is SpinBox or node is OptionButton or node is CheckBox or node is ColorPickerButton or node is LineEdit:
		return node
	if node is Container:
		for sub in (node as Container).get_children():
			if sub is HSlider or sub is SpinBox or sub is OptionButton or sub is CheckBox or sub is ColorPickerButton or sub is LineEdit:
				return sub
	return null

func _drive_fx(key: String, value, template: String) -> void:
	var FxLookScriptLocal = load("res://scripts/fx_vnext/fx_look.gd")
	var meta: Dictionary = FxLookScriptLocal.field_meta_all().get(key, {})
	var kind := str(meta.get("kind", "amount"))
	var ctl := _control_in(_tagged_node(key))
	_check(ctl != null, "UI-06 reproduce %s drives fx.%s" % [template, key])
	if ctl == null:
		return
	if kind == "amount" or kind == "int":
		if ctl is HSlider:
			(ctl as HSlider).value = float(value)
		elif ctl is SpinBox:
			(ctl as SpinBox).value = float(value)
		else:
			_check(false, "UI-06 reproduce %s fx.%s numeric control" % [template, key], str((ctl as Object).get_class()))
	elif kind == "option":
		var optlist: Array = meta.get("options", [])
		var oidx := optlist.find(str(value))
		if oidx < 0 and (value is float or value is int):
			oidx = clampi(int(value), 0, optlist.size() - 1)
		_drive_option_index(ctl, oidx, template, "fx." + key, str(value))
	elif kind == "check":
		if ctl is CheckBox:
			(ctl as CheckBox).button_pressed = bool(value)
			(ctl as CheckBox).toggled.emit(bool(value))
		else:
			_check(false, "UI-06 reproduce %s fx.%s check control" % [template, key], "")
	else:
		_check(false, "UI-06 reproduce %s fx.%s kind driver" % [template, key], kind)

func _drive_mask(key: String, value, template: String) -> void:
	var ctl := _control_in(_tagged_node("mask." + key))
	_check(ctl != null, "UI-06 reproduce %s drives mask.%s" % [template, key])
	if ctl == null:
		return
	if ctl is CheckBox:
		(ctl as CheckBox).button_pressed = bool(value)
		(ctl as CheckBox).toggled.emit(bool(value))
	elif ctl is OptionButton:
		var FxLookScriptLocal = load("res://scripts/fx_vnext/fx_look.gd")
		var opts: Array = []
		if key == "source":
			opts = FxLookScriptLocal.MASK_SOURCES
		elif key == "region":
			opts = FxLookScriptLocal.MASK_REGIONS
		elif key == "space":
			opts = FxLookScriptLocal.MASK_SPACES
		_drive_option_index(ctl, opts.find(str(value)), template, "mask." + key, str(value))
	elif ctl is SpinBox:
		(ctl as SpinBox).value = float(value)
	elif ctl is HSlider:
		(ctl as HSlider).value = float(value)
	else:
		_check(false, "UI-06 reproduce %s mask.%s control" % [template, key], str((ctl as Object).get_class()))

func _drive_option(field_id: String, value: String, template: String) -> void:
	var ctl := _control_in(_tagged_node(field_id))
	_check(ctl != null, "UI-06 reproduce %s drives %s" % [template, field_id])
	if ctl == null:
		return
	var FxLookScriptLocal = load("res://scripts/fx_vnext/fx_look.gd")
	var opts: Array = FxLookScriptLocal.PLANES if field_id == "layer.plane" else FxLookScriptLocal.INPUTS
	_drive_option_index(ctl, opts.find(value), template, field_id, value)

func _drive_option_index(ctl: Control, idx: int, template: String, label: String, value: String) -> void:
	# Canonical-index driving: option rows list canonical arrays in order,
	# so display tokens ("Behind Target") never need inverse mapping.
	if not (ctl is OptionButton):
		_check(false, "UI-06 reproduce %s %s option control" % [template, label], "")
		return
	var opt := ctl as OptionButton
	_check(idx >= 0 and idx < opt.item_count, "UI-06 reproduce %s %s option has value" % [template, label], value)
	if idx < 0 or idx >= opt.item_count:
		return
	opt.select(idx)
	opt.item_selected.emit(idx)

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
	# Persist everything, then a REAL reopen: destroy the shell/session,
	# boot a fresh shell, reopen the persisted look in its NATURAL authority
	# state (SHARED_PROTECTED stays), same target + clock. Parity oracle is
	# the presentation SubViewport texture (fixed 1280x720, UPDATE_ALWAYS),
	# never a root screenshot: inspector/dock/browser/timeline chrome must
	# not influence a rendering proof.
	shell.runtime.screen.lab_preview_pause()
	# Same clock path as scrub (TM-02): screen seek + renderer time together.
	shell._on_time_entered(0.5)
	await settle(10)
	var want_layers: int = (shell.session.look.get("layers", []) as Array).size()
	var pre: Image = await _capture_surface("ui06_pre")
	_check(pre.get_size() == Vector2i(1280, 720), "UI-06 presentation surface is 1280x720", str(pre.get_size()))
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
	# Full-doc canonical compare (sorted keys): distinguishes a persistence
	# gap from render nondeterminism before any pixel is captured.
	var doc_diff := _canon_diff(shell.session.look, doc)
	_check(doc_diff == "", "UI-06 save/reopen keeps full document", doc_diff.left(300))
	# True reopen: kill the session/shell, boot fresh, reopen from disk.
	shell.queue_free()
	shell = null
	await settle(15)
	shell = _spawn()
	await settle(30)
	shell._select_key("echo_left", false)
	await settle(20)
	_check(shell._session_ready(), "UI-06 fresh session ready on echo_left")
	var fresh_layers: int = (shell.session.look.get("layers", []) as Array).size()
	_check(fresh_layers == want_layers, "UI-06 reopened look holds all layers", "got=%d want=%d" % [fresh_layers, want_layers])
	# Natural authority state: SHARED_PROTECTED stays (no Edit Shared for
	# screenshot geometry). Debug view stays COMPOSITE (lab default).
	shell.runtime.screen.lab_preview_pause()
	shell._on_time_entered(0.5)
	await settle(10)
	var post: Image = await _capture_surface("ui06_post")
	_check(post.get_size() == pre.get_size(), "UI-06 reopen surface stable", "%s vs %s" % [str(pre.get_size()), str(post.get_size())])
	_check(_mean_abs_diff(pre, post) < 0.0005, "UI-06 fresh reopen renders identically", "mean=%.6f" % _mean_abs_diff(pre, post))

func _canon(v):
	# Canonical form with sorted dict keys (JSON key order is unstable
	# across save/parse round-trips; arrays keep canonical layer order).
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			parts.append(JSON.stringify(str(k)) + ":" + str(_canon((v as Dictionary)[k])))
		return "{" + ",".join(parts) + "}"
	if v is Array:
		var items: Array = []
		for e in (v as Array):
			items.append(str(_canon(e)))
		return "[" + ",".join(items) + "]"
	if v is float:
		return "%.6f" % float(v)
	return JSON.stringify(v)

func _canon_diff(a: Dictionary, b: Dictionary) -> String:
	# Layer-wise canonical diff (ids excluded from identity? No: ids must
	# persist too — but apply may re-id? Report first divergence only).
	if str(_canon(a)) == str(_canon(b)):
		return ""
	for k in a.keys():
		if not b.has(k):
			return "top-level key dropped: " + str(k)
		if str(_canon(a[k])) != str(_canon(b[k])):
			if str(k) == "layers":
				var la: Array = a[k]
				var lb: Array = b[k]
				if la.size() != lb.size():
					return "layers size %d vs %d" % [la.size(), lb.size()]
				for i in range(la.size()):
					if str(_canon(la[i])) != str(_canon(lb[i])):
						var da: Dictionary = la[i]
						for fk in da.keys():
							if str(_canon(da.get(fk))) != str(_canon((lb[i] as Dictionary).get(fk, null))):
								return "layer[%d] %s field %s" % [i, str(da.get("layer_id", "?")), str(fk)]
						return "layer[%d] differs" % i
			return "top-level key differs: " + str(k)
	for k in b.keys():
		if not a.has(k):
			return "top-level key added: " + str(k)
	return "unordered-key difference"

func _capture_surface(name: String) -> Image:
	# Presentation SubViewport texture directly: fixed 1280x720 render
	# target, includes screen + FX quads, excludes ALL editor chrome.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = shell.runtime.subvp.get_texture().get_image()
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
