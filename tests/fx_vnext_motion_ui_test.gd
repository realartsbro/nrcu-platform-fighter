# UI-03 motion behavioral proof (windowed, full shell): enable gates, track
# spins, curves, anchor edit, TRIGGER restarts the live envelope, save/reopen.
# Chain: UI action -> canonical track mutation -> live renderer envelope ->
# observable uniform animation -> persistence.
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
	_check(shell._session_ready(), "UI-03 session ready on echo_left")
	var layers: Array = shell.session.look.get("layers", [])
	shell.selected_layer_id = str((layers[1] as Dictionary).get("layer_id", ""))
	shell._rebuild_inspector()
	await settle(5)
	shell.runtime.screen.lab_preview_pause()
	await _enable_gate()
	await _track_spins_clamped()
	await _curves_anchor()
	await _trigger_animates_envelope()
	await _domain_matrix()
	await _geometry_no_overflow()
	await _save_reopen_tracks()
	print("[FX-MOTION-UI] done · checks=%d failures=%d" % [checks.size(), failures])
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
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	var look_id := "UI03_%d" % int(Time.get_unix_time_from_system())
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-03")
	var fx: Dictionary = FxLookScript.new_layer("FX", "ui03")
	look["layers"].append(fx)
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-03 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-03 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-03 seed assignment applies")

func _motion() -> Dictionary:
	return FxLookScript.find_layer(shell.session.look, shell.selected_layer_id)["motion"]

func _track(domain: String) -> Dictionary:
	return ((_motion().get("tracks", {}) as Dictionary).get(domain, {}) as Dictionary)

func _find_check(label_text: String) -> CheckBox:
	return _find_check_under(shell.inspector_content, label_text)

func _find_check_under(node: Node, label_text: String) -> CheckBox:
	for child in node.get_children():
		if child is CheckBox and (child as CheckBox).text == label_text:
			return child
		var found = _find_check_under(child, label_text)
		if found != null:
			return found
	return null

const DOMAINS := ["DITHER", "FRINGE", "FLOW", "RGB"]

# Domain-scoped control search: the MOTION page repeats identical labels per
# domain, so bare first-match finders hit the DITHER domain. We track the
# current domain header (label + ON checkbox + TRIGGER button) and only
# match controls under the requested domain.
func _domain_box(node: Node, domain: String) -> Array:
	var boxes: Array = []
	var current := ""
	var ordered: Array = []
	_collect_boxes(node, ordered)
	for box in ordered:
		if not (box is HBoxContainer):
			continue
		var kids := (box as HBoxContainer).get_children()
		if kids.size() == 3 and kids[0] is Label and (kids[0] as Label).text in DOMAINS and kids[1] is CheckBox and kids[2] is Button:
			current = (kids[0] as Label).text
			continue
		if current == domain:
			boxes.append(box)
	return boxes

func _collect_boxes(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is HBoxContainer:
			out.append(child)
		_collect_boxes(child, out)

func _find_spin(label_text: String) -> SpinBox:
	return _find_spin_in("FRINGE", label_text)

func _find_spin_in(domain: String, label_text: String) -> SpinBox:
	for box in _domain_box(shell.inspector_content, domain):
		var labels: Array = []
		var spins: Array = []
		for sub in (box as HBoxContainer).get_children():
			if sub is Label:
				labels.append((sub as Label).text.strip_edges())
			if sub is SpinBox:
				spins.append(sub)
		var idx := labels.find(label_text)
		if idx >= 0 and idx < spins.size():
			return spins[idx]
	return null

func _find_option(label_text: String) -> OptionButton:
	return _find_option_in("FRINGE", label_text)

func _find_option_in(domain: String, label_text: String) -> OptionButton:
	for box in _domain_box(shell.inspector_content, domain):
		var kids := (box as HBoxContainer).get_children()
		if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text.strip_edges() == label_text:
			for sub in kids:
				if sub is OptionButton:
					return sub
	return null

func _find_option_under(node: Node, label_text: String) -> OptionButton:
	for child in node.get_children():
		if child is HBoxContainer and (child as HBoxContainer).get_child_count() >= 2:
			var lab = (child as HBoxContainer).get_child(0)
			if lab is Label and (lab as Label).text.strip_edges() == label_text:
				for sub in (child as HBoxContainer).get_children():
					if sub is OptionButton:
						return sub
		var found = _find_option_under(child, label_text)
		if found != null:
			return found
	return null

func _find_button(prefix: String):
	return _find_button_in("FRINGE", prefix)

func _find_button_in(domain: String, prefix: String):
	# Domain header row itself carries the TRIGGER button.
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() == 3 and kids[0] is Label and (kids[0] as Label).text == domain and kids[2] is Button and (kids[2] as Button).text.begins_with(prefix):
				return kids[2]
	for child in _walk(shell.inspector_content):
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
	return null

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _find_lineedit(label_text: String) -> LineEdit:
	for box in _domain_box(shell.inspector_content, "FRINGE"):
		var kids := (box as HBoxContainer).get_children()
		if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == label_text:
			for sub in kids:
				if sub is LineEdit:
					return sub
	return null

func _enable_gate() -> void:
	# FRINGE domain header row: ON checkbox in the FRINGE header specifically
	# (all four domains share the same row shape).
	var found := false
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() == 3 and kids[0] is Label and (kids[0] as Label).text == "FRINGE" and kids[1] is CheckBox and kids[2] is Button:
				(kids[1] as CheckBox).button_pressed = true
				(kids[1] as CheckBox).toggled.emit(true)
				found = true
				break
	_check(found, "UI-03 fringe motion ON checkbox reachable")
	if not found:
		return
	await settle(5)
	_check(bool((_motion().get("enabled", {}) as Dictionary).get("fringe", false)) and not bool((_motion().get("enabled", {}) as Dictionary).get("dither", false)), "UI-03 enable gate persists canonically on fringe only")

func _track_spins_clamped() -> void:
	var atk := _find_spin("Attack")
	_check(atk != null, "UI-03 attack spin reachable")
	if atk == null:
		return
	# Editor ranges mirror validator/runtime clamps (TM-07): attack > 0.
	_check(absf(atk.min_value - 0.001) < 0.00001, "UI-03 attack editor minimum matches validator (> 0)", str(atk.min_value))
	atk.value = 2.0
	await settle(5)
	_check(absf(float(_track("fringe").get("attack", 0.0)) - 2.0) < 0.001, "UI-03 attack edits canonical track", str(_track("fringe").get("attack", "?")))
	var sus := _find_spin("Sustain")
	_check(sus != null, "UI-03 sustain spin reachable")
	if sus == null:
		return
	_check(absf(sus.min_value - 0.0) < 0.00001 and absf(sus.max_value - 1.0) < 0.00001, "UI-03 sustain editor range is [0, 1] like validator")

func _curves_anchor() -> void:
	var anchor := _find_option("Anchor")
	_check(anchor != null, "UI-03 anchor option reachable")
	if anchor == null:
		return
	anchor.selected = 0
	anchor.item_selected.emit(0)
	await settle(5)
	_check(str(_track("fringe").get("anchor", "")) == "manual", "UI-03 anchor edits canonically")
	var curve := _find_option("Attack curve")
	_check(curve != null, "UI-03 attack curve option reachable")
	if curve == null:
		return
	curve.selected = 0
	curve.item_selected.emit(0)
	await settle(5)
	_check(str(_track("fringe").get("attack_curve", "")) == "linear", "UI-03 curve edits canonically", str(_track("fringe").get("attack_curve", "")))

func _trigger_animates_envelope() -> void:
	# Fringe amount up so the envelope has something to modulate.
	shell.session.edit(func(doc):
		(FxLookScript.find_layer(doc, shell.selected_layer_id)["fx"] as Dictionary)["fringe"] = 1.0
	)
	shell._render_current_look()
	await settle(3)
	var trig = _find_button("TRIGGER")
	_check(trig != null, "UI-03 TRIGGER button reachable")
	if trig == null:
		return
	shell.renderer.set_time(5.0)
	await settle(3)
	trig.pressed.emit()
	await settle(3)
	shell.renderer.set_time(5.5)
	await settle(3)
	var u1 := _quad_fringe()
	shell.renderer.set_time(9.0)
	await settle(3)
	var u2 := _quad_fringe()
	_check(u1 > 0.001 and u1 < 0.999, "UI-03 envelope mid-attack is partial (live)", "u=%.3f" % u1)
	_check(u2 < u1, "UI-03 envelope decays after release (live)", "u1=%.3f u2=%.3f" % [u1, u2])

func _quad_fringe() -> float:
	if shell.renderer == null:
		return -1.0
	var best := -1.0
	for quad_entry in shell.renderer.stack_quads("echo_left"):
		var quad = (quad_entry as Dictionary).get("node", null)
		if quad is Control and str((quad as Control).name).begins_with("vnext_"):
			var mat := (quad as Control).material as ShaderMaterial
			if mat != null:
				best = maxf(best, float(mat.get_shader_parameter("fx_fringe")))
	return best

func _save_reopen_tracks() -> void:
	var applied: Dictionary = shell.session.apply()
	_check(bool(applied.get("ok", false)), "UI-03 session apply persists", str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var reloaded: Dictionary = shell.production.load_look(str(applied.get("look_id", "")))
	_check(bool(reloaded.get("ok", false)), "UI-03 production look reloads")
	if not bool(reloaded.get("ok", false)):
		return
	var track := {}
	for layer in (reloaded["doc"] as Dictionary).get("layers", []):
		if (layer as Dictionary).get("type", "") == "FX":
			track = (((layer as Dictionary).get("motion", {}) as Dictionary).get("tracks", {}) as Dictionary).get("fringe", {})
	_check(absf(float(track.get("attack", 0.0)) - 2.0) < 0.001 and str(track.get("attack_curve", "")) == "linear", "UI-03 tracks survive save/reopen", str(track))

func _domain_matrix() -> void:
	# Every domain independently: enable lands on its own dict, attack edit
	# lands in its own track, nothing leaks across domains (loop/lambda wiring).
	var idx := 0
	for domain in ["DITHER", "FLOW", "RGB"]:
		idx += 1
		var box = _header_box(domain)
		_check(box != null, "UI-03 %s header reachable" % domain)
		if box == null:
			continue
		var kids := (box as HBoxContainer).get_children()
		(kids[1] as CheckBox).button_pressed = true
		(kids[1] as CheckBox).toggled.emit(true)
		await settle(3)
		var spin := _find_spin_in(domain, "Attack")
		_check(spin != null, "UI-03 %s attack spin reachable" % domain)
		if spin == null:
			continue
		spin.value = 1.0 + float(idx)
		await settle(3)
		var tracks: Dictionary = (_motion().get("tracks", {}) as Dictionary)
		var got := absf(float((tracks.get(domain.to_lower(), {}) as Dictionary).get("attack", 0.0)) - (1.0 + float(idx))) < 0.01
		_check(got, "UI-03 %s attack lands in own track" % domain, str((tracks.get(domain.to_lower(), {}) as Dictionary).get("attack", "?")))
		var enabled: Dictionary = (_motion().get("enabled", {}) as Dictionary)
		_check(bool(enabled.get(domain.to_lower(), false)), "UI-03 %s enable lands on own domain" % domain)

func _header_box(domain: String):
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() == 3 and kids[0] is Label and (kids[0] as Label).text == domain and kids[1] is CheckBox and kids[2] is Button:
				return child
	return null

func _geometry_no_overflow() -> void:
	# Layout acceptance at the running window size: no inspector row may
	# overflow its page horizontally; interactive controls keep click height.
	var page = _motion_page_node()
	_check(page != null, "UI-03 MOTION page node found")
	if page == null:
		return
	var page_right := (page as Control).get_global_rect().end.x
	var bad := 0
	var short := 0
	for child in _walk(page):
		if child is HBoxContainer:
			var r: Rect2 = (child as Control).get_global_rect()
			if r.end.x > page_right + 2.0:
				bad += 1
		if child is Button or child is HSlider or child is SpinBox or child is OptionButton or child is CheckBox:
			if (child as Control).size.y < 16.0:
				short += 1
	_check(bad == 0, "UI-03 no horizontal overflow in MOTION page", "overflowing rows=%d" % bad)
	_check(short == 0, "UI-03 interactive controls keep click height", "short=%d" % short)

func _motion_page_node():
	for child in _walk(shell.inspector_content):
		if child is VBoxContainer and (child as VBoxContainer).name == "MOTION":
			return child
	return null
