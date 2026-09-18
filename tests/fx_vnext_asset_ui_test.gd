extends SceneTree

# UI-07/08: dependency-bearing asset controls end-to-end.
# Picker -> canonical path -> dependency truth -> live preview ->
# save/reopen -> Production harvest -> portable authority ->
# fresh Reference Runtime -> visible effect. Negatives fail closed.
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const VsRuntimeScript := preload("res://scripts/fx_vnext/vs_runtime.gd")

var shell: Control
var checks: Array = []
var failures := 0
var out_dir: String
var look_id := ""
var stage_dir := ""
var src_dir := ""
var data_dir := ""

const FIELDS := [
	"displacement.custom_texture",
	"displacement.influence_mask.custom_mask",
	"mask.custom_mask",
	"treatment_mask_path",
]
const DRIVERS := ["NOISE", "DIRECTIONAL", "WAVE", "CELLULAR", "FRINGE_DRIVER", "CUSTOM_TEXTURE"]
const MSOURCES := ["NONE", "ORIGINAL_SOURCE_ALPHA", "POST_DISPLACEMENT_ALPHA", "CUSTOM_MASK"]

func _init() -> void:
	# P0 harness safety (researcher 12-10): this suite wipes its stores.
	# Without explicit sandbox overrides it would destroy the real default
	# production store. Fail fast BEFORE spawning anything.
	var missing_sandbox := OS.get_environment("NRCU_FX_DATA_DIR").strip_edges() == "" or OS.get_environment("NRCU_FX_DRAFT_DIR").strip_edges() == ""
	if missing_sandbox:
		var expected_refusal := OS.get_environment("NRCU_UI07_EXPECT_SANDBOX_REFUSAL") == "1"
		_check(expected_refusal, "UI-07 refuses destructive run without sandbox override", "set NRCU_FX_DATA_DIR + NRCU_FX_DRAFT_DIR")
		print("[FX-ASSET-UI] done · checks=%d failures=%d" % [checks.size(), failures])
		quit(0 if expected_refusal else 1)
		return
	# Belt and suspenders: never wipe the shipped default stores even if an
	# override typo points at them.
	var _dd := OS.get_environment("NRCU_FX_DATA_DIR").strip_edges()
	var _gd := OS.get_environment("NRCU_FX_DRAFT_DIR").strip_edges()
	if _dd == "res://nrcu_fx_data" or _gd == "user://nrcu_fx_vnext_drafts":
		_check(false, "UI-07 refuses destructive run against default stores", _dd + " / " + _gd)
		print("[FX-ASSET-UI] done · checks=%d failures=%d" % [checks.size(), failures])
		quit(1)
		return
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/asset_ui")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_stage_files()
	shell = _spawn()
	await settle(30)
	_seed()
	shell._select_key("echo_left", false)
	await settle(20)
	_check(shell._session_ready(), "UI-07 session ready on echo_left")
	shell.runtime.screen.lab_preview_pause()
	# Phase isolation (researcher 11-16): NRCU_UI07_ONLY bounds the run to a
	# comma-separated phase subset; every subset boots its own fresh
	# store/shell/look, so no invalid or protected state leaks across groups.
	var only := OS.get_environment("NRCU_UI07_ONLY")
	var run_all := only.strip_edges() == ""
	var want := func(name: String) -> bool: return run_all or ("," + only + ",").contains("," + name + ",")
	_truth_table()
	if want.call("pickers"):
		print("UI07 PHASE pickers n=%d" % checks.size())
		await _picker_rows()
		print("UI07 PHASE families n=%d" % checks.size())
		await _picks_all_families()
	if want.call("negatives"):
		print("UI07 PHASE negatives n=%d" % checks.size())
		await _negatives()
		print("UI07 PHASE dormant n=%d" % checks.size())
		await _dormant()
	if want.call("harvest"):
		print("UI07 PHASE harvest n=%d" % checks.size())
		await _harvest_flow()
	if want.call("visuals"):
		print("UI07 PHASE visuals n=%d" % checks.size())
		await _visual_proofs()
	if want.call("reopen"):
		print("UI07 PHASE save-reopen n=%d" % checks.size())
		await _save_reopen_replace()
		print("UI07 PHASE containment n=%d" % checks.size())
		await _containment()
	print("[FX-ASSET-UI] done · checks=%d failures=%d" % [checks.size(), failures])
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

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _seed() -> void:
	data_dir = str(shell.production.data_dir)
	_wipe_dir(ProjectSettings.globalize_path(data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	look_id = "UI07_%d" % int(Time.get_unix_time_from_system())
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-07")
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-07 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-07 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-07 seed assignment applies")

func _wipe_dir(abs_path: String) -> void:
	if DirAccess.dir_exists_absolute(abs_path):
		for entry in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(entry))
		for sub in DirAccess.get_directories_at(abs_path):
			_wipe_dir(abs_path.path_join(sub))
			DirAccess.remove_absolute(abs_path.path_join(sub))

# ---- staging ---------------------------------------------------------------

func _stage_files() -> void:
	stage_dir = ProjectSettings.globalize_path("user://fx_asset_stage")
	src_dir = ProjectSettings.globalize_path("user://fx_asset_src")
	DirAccess.make_dir_recursive_absolute(stage_dir)
	DirAccess.make_dir_recursive_absolute(src_dir)
	_half_mask(stage_dir.path_join("mask_half.png"))
	_half_mask(src_dir.path_join("mask_half.png"))
	_gradient(stage_dir.path_join("tex_gradient.png"))
	_flat(stage_dir.path_join("tex_flat.png"), Color(0.5, 0.5, 0.5))
	var t := FileAccess.open(stage_dir.path_join("note.txt"), FileAccess.WRITE)
	t.store_string("not a texture")
	t.close()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var corrupt := PackedByteArray()
	for i in 256:
		corrupt.append(rng.randi() & 0xFF)
	var c := FileAccess.open(stage_dir.path_join("corrupt.png"), FileAccess.WRITE)
	c.store_buffer(corrupt)
	c.close()

func _half_mask(path: String) -> void:
	# Layer/influence masks sample ALPHA: opaque white vs transparent.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color.WHITE if x < 32 else Color(0, 0, 0, 0))
	img.save_png(path)

func _gradient(path: String) -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v := float(x) / 63.0
			img.set_pixel(x, y, Color(v, v, v))
	img.save_png(path)

func _flat(path: String, col: Color) -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(col)
	img.save_png(path)

func _upath(name: String) -> String:
	return ProjectSettings.globalize_path("user://fx_asset_stage/" + name)

func _src_upath(name: String) -> String:
	return ProjectSettings.globalize_path("user://fx_asset_src/" + name)

# ---- layer + control drivers -------------------------------------------------

func _add_fx_layer() -> String:
	var before: int = (shell.session.look.get("layers", []) as Array).size()
	shell._action_add_layer("Custom FX Layer")
	return str((shell.session.look.get("layers", []) as Array)[(shell.session.look.get("layers", []) as Array).size() - 1].get("layer_id", "")) if (shell.session.look.get("layers", []) as Array).size() == before + 1 else ""

func _select_layer(lid: String) -> void:
	shell.selected_layer_id = lid
	shell._rebuild_inspector()

func _tagged_node(field_id: String):
	for child in _walk(shell.inspector_content):
		if child is Object and (child as Object).has_meta("canonical_field") and str((child as Object).get_meta("canonical_field")) == field_id:
			return child
	return null

func _control_in(node) -> Control:
	if node is HSlider or node is SpinBox or node is OptionButton or node is CheckBox or node is ColorPickerButton or node is LineEdit:
		return node
	if node is Container:
		for sub in (node as Container).get_children():
			if sub is HSlider or sub is SpinBox or sub is OptionButton or sub is CheckBox or sub is ColorPickerButton or sub is LineEdit:
				return sub
	return null

func _opt_by_index(field_id: String, idx: int) -> bool:
	var ctl := _control_in(_tagged_node(field_id))
	if not (ctl is OptionButton):
		return false
	(ctl as OptionButton).select(idx)
	(ctl as OptionButton).item_selected.emit(idx)
	return true

func _opt_by_value(field_id: String, options: Array, value: String) -> bool:
	var idx := options.find(value)
	if idx < 0:
		return false
	return _opt_by_index(field_id, idx)

func _chk(field_id: String, pressed: bool) -> bool:
	var ctl := _control_in(_tagged_node(field_id))
	if not (ctl is CheckBox):
		return false
	(ctl as CheckBox).button_pressed = pressed
	(ctl as CheckBox).toggled.emit(pressed)
	return true

func _layer(lid: String) -> Dictionary:
	return FxLookScript.find_layer(shell.session.look, lid)

func _edit(lid: String, mut: Callable) -> void:
	shell.session.edit(func(doc): mut.call(FxLookScript.find_layer(doc, lid)))

func _asset_wrap(field_id: String):
	return _tagged_node(field_id)

func _sess_assets() -> String:
	var parts: Array = []
	for l in (shell.session.look.get("layers", []) as Array):
		var d: Dictionary = (l as Dictionary).get("displacement", {})
		var m: Dictionary = (l as Dictionary).get("mask", {})
		var f: Dictionary = (l as Dictionary).get("fx", {})
		var iraw = d.get("influence_mask", {})
		var im: Dictionary = iraw if iraw is Dictionary else {}
		parts.append("%s:drv=%s,ct=%s,me=%s,ms=%s,cm=%s,ie=%s,is=%s,ic=%s,ee=%s,tp=%s" % [str((l as Dictionary).get("layer_id", "?")), str(d.get("driver", "?")), str(d.get("custom_texture", "?")), str(m.get("enabled", "?")), str(m.get("source", "?")), str(m.get("custom_mask", "?")), str(im.get("enabled", "?")), str(im.get("source", "?")), str(im.get("custom_mask", "?")), str(f.get("effect_mask_enabled", "?")), str(f.get("treatment_mask_path", "?"))])
	return " | ".join(parts)

func _ensure_editable(phase: String) -> bool:
	# Legal transition only: protected VALID state -> own editable branch.
	# make_unique on an INVALID look must fail — fail the phase fast, never
	# heal-and-continue (researcher 11-16).
	if shell.session.is_editable():
		return true
	var r: Dictionary = shell.session.make_unique()
	_check(bool(r.get("ok", false)), "UI-07 %s make-unique for editability" % phase, str(r.get("errors", [])))
	if not bool(r.get("ok", false)):
		return false
	await settle(5)
	return true

func _show_tab_of(wrap) -> void:
	# Hidden TabContainer pages never get layout (size 0): switch to the
	# page holding this row before measuring clickability/containment.
	var page: Node = wrap
	while page != null and not (page.get_parent() is TabContainer):
		page = page.get_parent()
	if page == null or not (page.get_parent() is TabContainer):
		return
	var tabs := page.get_parent() as TabContainer
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_control(i) == page:
			tabs.current_tab = i
			return

func _scroll_to(wrap) -> void:
	# Inspector content scrolls: bring the row into the visible dock area
	# before measuring (UI-06 ensure_control_visible pattern).
	_show_tab_of(wrap)
	var sc: Node = wrap
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc == null:
		return
	var target := wrap as Control
	(sc as ScrollContainer).ensure_control_visible(target)

func _scroll_to_visible(wrap, dock: Control) -> void:
	# ensure_control_visible can undershoot on very long pages (ADVANCED):
	# settle, re-measure, and drive to max scroll once if still outside.
	_scroll_to(wrap)
	await settle(3)
	var wr: Rect2 = (wrap as Control).get_global_rect()
	var dr: Rect2 = dock.get_global_rect()
	if not dr.has_point(wr.position):
		var sc: Node = wrap
		while sc != null and not (sc is ScrollContainer):
			sc = sc.get_parent()
		if sc != null:
			(sc as ScrollContainer).scroll_vertical = int((sc as ScrollContainer).get_v_scroll_bar().max_value)
			await settle(3)
			(sc as ScrollContainer).ensure_control_visible(wrap as Control)
			await settle(3)

func _asset_child(wrap, cname: String):
	for child in _walk(wrap):
		if (child as Node).name == cname:
			return child
	return null

func _badge_text(field_id: String) -> String:
	var wrap = _asset_wrap(field_id)
	if wrap == null:
		return "<no row>"
	var badge = _asset_child(wrap, "AssetStatus")
	return str((badge as Label).text) if badge is Label else "<no badge>"

func _surface(name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = shell.runtime.subvp.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _freeze_time() -> void:
	shell.runtime.screen.lab_preview_pause()
	shell._on_time_entered(0.5)
	await settle(10)
	# Session-direct edits bypass _edit_layer: re-render the preview from
	# the current session look, or captures compare stale compositions.
	shell._render_current_look()
	await settle(5)
	_check(not str(shell.action_status.text).begins_with("render:"), "UI-07 preview composes", str(shell.action_status.text))

func _roi_mean(a: Image, b: Image, r: Rect2i) -> float:
	# Strided sampling (every 4th pixel): 16x faster, robust for ROI means.
	var d := 0.0
	var n := 0
	var y := r.position.y
	while y < r.position.y + r.size.y:
		var x := r.position.x
		while x < r.position.x + r.size.x:
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			d += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			n += 1
			x += 4
		y += 4
	return d / float(maxi(n, 1) * 3)

# ---- T1: central truth table ---------------------------------------------------

func _truth_table() -> void:
	var FxAssets = load("res://scripts/fx_vnext/fx_assets.gd")
	var layer: Dictionary = FxLookScript.new_layer("FX", "truth")
	# not required + empty -> NOT_REQUIRED (all four fields on a neutral layer)
	for f in FIELDS:
		var st: Dictionary = FxAssets.dependency_status(str(f), layer, data_dir)
		_check(str(st.get("state", "")) == "NOT_REQUIRED", "UI-07 truth not-required %s" % str(f), str(st.get("state", "")))
	# required + empty -> MISSING
	(layer["displacement"] as Dictionary)["driver"] = "CUSTOM_TEXTURE"
	_check(str((FxAssets.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "MISSING", "UI-07 truth missing custom_texture")
	(layer["mask"] as Dictionary)["enabled"] = true
	(layer["mask"] as Dictionary)["source"] = "CUSTOM_MASK"
	_check(str((FxAssets.dependency_status("mask.custom_mask", layer, data_dir) as Dictionary).get("state", "")) == "MISSING", "UI-07 truth missing custom_mask")
	(layer["fx"] as Dictionary)["effect_mask_enabled"] = true
	_check(str((FxAssets.dependency_status("treatment_mask_path", layer, data_dir) as Dictionary).get("state", "")) == "MISSING", "UI-07 truth missing treatment")
	# nonexistent -> MISSING (not COMPLETE)
	(layer["displacement"] as Dictionary)["custom_texture"] = _upath("ghost.png")
	_check(str((FxAssets.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "MISSING", "UI-07 truth ghost is missing")
	# corrupt -> UNLOADABLE, wrong type -> WRONG_TYPE
	(layer["displacement"] as Dictionary)["custom_texture"] = _upath("corrupt.png")
	_check(str((FxAssets.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "UNLOADABLE", "UI-07 truth corrupt unloadable")
	(layer["displacement"] as Dictionary)["custom_texture"] = _upath("note.txt")
	_check(str((FxAssets.dependency_status("displacement.custom_texture", layer, data_dir) as Dictionary).get("state", "")) == "WRONG_TYPE", "UI-07 truth txt wrong-type")
	# valid user:// outside data_dir -> COMPLETE + needs_harvest
	(layer["displacement"] as Dictionary)["custom_texture"] = _src_upath("mask_half.png")
	var h: Dictionary = FxAssets.dependency_status("displacement.custom_texture", layer, data_dir)
	_check(str(h.get("state", "")) == "COMPLETE" and bool(h.get("needs_harvest", false)), "UI-07 truth user-src complete+harvest", str(h))
	# absolute OS path, existing -> COMPLETE + needs_harvest
	(layer["displacement"] as Dictionary)["custom_texture"] = _upath("mask_half.png")
	var ha: Dictionary = FxAssets.dependency_status("displacement.custom_texture", layer, data_dir)
	_check(str(ha.get("state", "")) == "COMPLETE" and bool(ha.get("needs_harvest", false)), "UI-07 truth absolute complete+harvest", str(ha))

# ---- T2: picker rows -------------------------------------------------------------

func _picker_rows() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 asset layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	for f in FIELDS:
		var wrap = _asset_wrap(str(f))
		_check(wrap != null, "UI-07 typed row %s" % str(f))
		if wrap == null:
			continue
		_scroll_to(wrap)
		await settle(3)
		_check(_asset_child(wrap, "AssetBrowse") is Button, "UI-07 %s browse button" % str(f))
		_check(_asset_child(wrap, "AssetClear") is Button, "UI-07 %s clear button" % str(f))
		_check(_asset_child(wrap, "AssetPath") is LineEdit, "UI-07 %s path display" % str(f))
		_check(_asset_child(wrap, "AssetStatus") is Label, "UI-07 %s status badge" % str(f))
	# make the texture path required, then browse-pick via dialog signal
	_check(_opt_by_value("displacement.driver", DRIVERS, "CUSTOM_TEXTURE"), "UI-07 driver to custom via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("displacement.custom_texture").begins_with("⚠ INCOMPLETE"), "UI-07 custom tex incomplete when empty", _badge_text("displacement.custom_texture"))
	var wrap = _asset_wrap("displacement.custom_texture")
	var browse: Button = _asset_child(wrap, "AssetBrowse")
	_check(str(browse.text) == "BROWSE", "UI-07 browse label when empty", str(browse.text))
	var undo0: int = (shell.session._undo_stack as Array).size()
	browse.pressed.emit()
	await settle(3)
	_check(shell.asset_dialog != null and shell.asset_dialog.visible, "UI-07 dialog opens on browse")
	shell.asset_dialog.file_selected.emit(_src_upath("mask_half.png"))
	await settle(8)
	_select_layer(lid)
	await settle(5)
	_check(str(FxAssetsScript.field_path("displacement.custom_texture", _layer(lid))) == _src_upath("mask_half.png"), "UI-07 pick sets canonical path", str(FxAssetsScript.field_path("displacement.custom_texture", _layer(lid))))
	_check(_badge_text("displacement.custom_texture").begins_with("✓ COMPLETE"), "UI-07 badge complete after pick", _badge_text("displacement.custom_texture"))
	_check((shell.session._undo_stack as Array).size() == undo0 + 1, "UI-07 pick is one undo entry")
	# CLEAR keeps the mode (spec H): path gone, driver still CUSTOM_TEXTURE
	var clear: Button = _asset_child(_asset_wrap("displacement.custom_texture"), "AssetClear")
	clear.pressed.emit()
	await settle(8)
	_select_layer(lid)
	await settle(5)
	_check(FxAssetsScript.field_path("displacement.custom_texture", _layer(lid)) == null, "UI-07 clear empties path")
	_check(str((_layer(lid).get("displacement", {}) as Dictionary).get("driver", "")) == "CUSTOM_TEXTURE", "UI-07 clear keeps mode")
	_check(_badge_text("displacement.custom_texture").begins_with("⚠ INCOMPLETE"), "UI-07 incomplete after clear", _badge_text("displacement.custom_texture"))
	# manual expert entry fallback: type a path, submit
	var edit: LineEdit = _asset_child(_asset_wrap("displacement.custom_texture"), "AssetPath")
	edit.text = _src_upath("mask_half.png")
	edit.text_submitted.emit(_src_upath("mask_half.png"))
	await settle(8)
	_select_layer(lid)
	await settle(5)
	_check(str(FxAssetsScript.field_path("displacement.custom_texture", _layer(lid))) == _src_upath("mask_half.png"), "UI-07 typed path applies")
	# builder-level protected wiring (no session needed): all disabled
	var prowed: Control = shell._dep_asset_row("mask.custom_mask", "Custom", _layer(lid), lid, true, Callable())
	var dis_count := 0
	for child in _walk(prowed):
		if child is Button and (child as Button).disabled:
			dis_count += 1
		if child is LineEdit and not (child as LineEdit).editable:
			dis_count += 1
	_check(dis_count >= 3, "UI-07 protected row disables picker", str(dis_count))
	prowed.queue_free()

# ---- T2b: UI picks for every dependency family --------------------------------------

func _ui_pick(field_id: String, abs_path: String) -> void:
	var wrap = _asset_wrap(field_id)
	(_asset_child(wrap, "AssetBrowse") as Button).pressed.emit()
	await settle(3)
	_check(shell.asset_dialog != null and shell.asset_dialog.visible, "UI-07 dialog opens %s" % field_id)
	shell.asset_dialog.file_selected.emit(abs_path)
	await settle(8)

func _picks_all_families() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 family layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	# mask family, all via UI
	_check(_chk("mask.enabled", true), "UI-07 mask enabled via UI")
	_check(_opt_by_value("mask.source", MSOURCES, "CUSTOM_MASK"), "UI-07 mask source custom via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("mask.custom_mask").begins_with("⚠ INCOMPLETE"), "UI-07 mask incomplete when empty", _badge_text("mask.custom_mask"))
	await _ui_pick("mask.custom_mask", _upath("mask_half.png"))
	_select_layer(lid)
	await settle(5)
	_check(str(FxAssetsScript.field_path("mask.custom_mask", _layer(lid))) == _upath("mask_half.png"), "UI-07 mask pick canonical")
	_check(_badge_text("mask.custom_mask").begins_with("✓ COMPLETE"), "UI-07 mask badge complete", _badge_text("mask.custom_mask"))
	# influence family, all via UI
	_check(_chk("displacement.influence.enabled", true), "UI-07 influence enabled via UI")
	_check(_opt_by_value("displacement.influence.source", MSOURCES, "CUSTOM_MASK"), "UI-07 influence source custom via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("displacement.influence_mask.custom_mask").begins_with("⚠ INCOMPLETE"), "UI-07 influence incomplete when empty", _badge_text("displacement.influence_mask.custom_mask"))
	await _ui_pick("displacement.influence_mask.custom_mask", _upath("mask_half.png"))
	_select_layer(lid)
	await settle(5)
	_check(str(FxAssetsScript.field_path("displacement.influence_mask.custom_mask", _layer(lid))) == _upath("mask_half.png"), "UI-07 influence pick canonical")
	# treatment family, all via UI (expert check row)
	_check(_chk("effect_mask_enabled", true), "UI-07 effect mask enabled via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("treatment_mask_path").begins_with("⚠ INCOMPLETE"), "UI-07 treatment incomplete when empty", _badge_text("treatment_mask_path"))
	await _ui_pick("treatment_mask_path", _upath("mask_half.png"))
	_select_layer(lid)
	await settle(5)
	_check(str(FxAssetsScript.field_path("treatment_mask_path", _layer(lid))) == _upath("mask_half.png"), "UI-07 treatment pick canonical")
	_check(_badge_text("treatment_mask_path").begins_with("✓ COMPLETE"), "UI-07 treatment badge complete", _badge_text("treatment_mask_path"))

# ---- T3: fail-closed negatives -----------------------------------------------------

func _negatives() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 negative layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	# 1. required + empty -> INCOMPLETE + apply rejected (validate-look)
	_check(_opt_by_value("displacement.driver", DRIVERS, "CUSTOM_TEXTURE"), "UI-07 neg driver custom")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	var r1: Dictionary = shell.session.apply()
	_check(not bool(r1.get("ok", false)), "UI-07 empty required rejects apply", str(r1.get("errors", [])))
	# 2. required + nonexistent -> INVALID/MISSING + rejected at assets stage
	_edit(lid, func(l: Dictionary) -> void: (l["displacement"] as Dictionary)["custom_texture"] = _upath("ghost.png"))
	await settle(3)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("displacement.custom_texture").begins_with("⚠ INCOMPLETE") or _badge_text("displacement.custom_texture").begins_with("✖ INVALID"), "UI-07 ghost badge not complete", _badge_text("displacement.custom_texture"))
	var r2: Dictionary = shell.session.apply()
	_check(not bool(r2.get("ok", false)) and str(r2.get("stage", "")) == "assets", "UI-07 ghost rejects at assets stage", str(r2))
	# 3a. corrupt -> rejected at validate-look (loadability gate)
	_edit(lid, func(l: Dictionary) -> void: (l["displacement"] as Dictionary)["custom_texture"] = _upath("corrupt.png"))
	await settle(3)
	var r3: Dictionary = shell.session.apply()
	_check(not bool(r3.get("ok", false)) and str(r3.get("stage", "")) == "validate-look", "UI-07 corrupt rejects at validate", str(r3))
	# 3b. wrong type -> rejected at validate-look
	_edit(lid, func(l: Dictionary) -> void: (l["displacement"] as Dictionary)["custom_texture"] = _upath("note.txt"))
	await settle(3)
	var r4: Dictionary = shell.session.apply()
	_check(not bool(r4.get("ok", false)) and str(r4.get("stage", "")) == "validate-look", "UI-07 wrong-type rejects at validate", str(r4))
	# Leave the session appliable for later phases: back to procedural.
	await _scrub_layer(lid)

# ---- T3b: dormant paths never block ----------------------------------------------

func _dormant() -> void:
	# Per family: active + broken path -> reject; same path dormant ->
	# apply succeeds + DORMANT_WARNING badge; reactivate -> reject again.
	await _dormant_displacement()
	await _dormant_mask()
	await _dormant_influence()
	await _dormant_treatment()

func _scrub_layer(lid: String) -> void:
	# No invalid or required-missing state may leak into the next phase:
	# back to fully procedural, paths cleared. Fully null-guarded: a stored
	# null is not covered by Dictionary.get defaults.
	_edit(lid, func(l: Dictionary) -> void:
		var dd = l.get("displacement", null)
		if dd is Dictionary:
			(dd as Dictionary)["driver"] = "NOISE"
			(dd as Dictionary)["custom_texture"] = null
			var iraw = (dd as Dictionary).get("influence_mask", null)
			if iraw is Dictionary:
				(iraw as Dictionary)["enabled"] = false
				(iraw as Dictionary)["custom_mask"] = null
		var mm = l.get("mask", null)
		if mm is Dictionary:
			(mm as Dictionary)["enabled"] = false
			(mm as Dictionary)["custom_mask"] = null
		var ff = l.get("fx", null)
		if ff is Dictionary:
			(ff as Dictionary)["effect_mask_enabled"] = false
			(ff as Dictionary)["treatment_mask_path"] = null
	)
	await settle(3)

func _dormant_displacement() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 dormant disp layer")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_check(_opt_by_value("displacement.driver", DRIVERS, "CUSTOM_TEXTURE"), "UI-07 dormant disp active")
	_edit(lid, func(l: Dictionary) -> void: (l["displacement"] as Dictionary)["custom_texture"] = _upath("ghost.png"))
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant disp active rejects")
	_check(_opt_by_value("displacement.driver", DRIVERS, "NOISE"), "UI-07 dormant disp off via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("displacement.custom_texture").begins_with("○ dormant"), "UI-07 dormant disp badge", _badge_text("displacement.custom_texture"))
	var rd: Dictionary = shell.session.apply()
	_check(bool(rd.get("ok", false)), "UI-07 dormant disp applies", str(rd.get("errors", [])))
	if not await _ensure_editable("dormant-disp"):
		return
	_check(_opt_by_value("displacement.driver", DRIVERS, "CUSTOM_TEXTURE"), "UI-07 dormant disp reactivated")
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant disp reactivated rejects")
	await _scrub_layer(lid)

func _dormant_mask() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 dormant mask layer")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_check(_chk("mask.enabled", true), "UI-07 dormant mask on")
	_check(_opt_by_value("mask.source", MSOURCES, "CUSTOM_MASK"), "UI-07 dormant mask custom")
	_edit(lid, func(l: Dictionary) -> void: (l["mask"] as Dictionary)["custom_mask"] = _upath("ghost.png"))
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant mask active rejects")
	_check(_chk("mask.enabled", false), "UI-07 dormant mask off via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("mask.custom_mask").begins_with("○ dormant"), "UI-07 dormant mask badge", _badge_text("mask.custom_mask"))
	var rd: Dictionary = shell.session.apply()
	_check(bool(rd.get("ok", false)), "UI-07 dormant mask applies", str(rd.get("errors", [])))
	if not await _ensure_editable("dormant-mask"):
		return
	_check(_chk("mask.enabled", true), "UI-07 dormant mask reactivated")
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant mask reactivated rejects")
	await _scrub_layer(lid)

func _dormant_influence() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 dormant infl layer")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_check(_chk("displacement.influence.enabled", true), "UI-07 dormant infl on")
	_check(_opt_by_value("displacement.influence.source", MSOURCES, "CUSTOM_MASK"), "UI-07 dormant infl custom")
	_edit(lid, func(l: Dictionary) -> void: ((l["displacement"] as Dictionary).get("influence_mask", {}) as Dictionary)["custom_mask"] = _upath("ghost.png"))
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant infl active rejects")
	_check(_chk("displacement.influence.enabled", false), "UI-07 dormant infl off via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("displacement.influence_mask.custom_mask").begins_with("○ dormant"), "UI-07 dormant infl badge", _badge_text("displacement.influence_mask.custom_mask"))
	var rd: Dictionary = shell.session.apply()
	_check(bool(rd.get("ok", false)), "UI-07 dormant infl applies", str(rd.get("errors", [])))
	if not await _ensure_editable("dormant-infl"):
		return
	_check(_chk("displacement.influence.enabled", true), "UI-07 dormant infl reactivated")
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant infl reactivated rejects")
	await _scrub_layer(lid)

func _dormant_treatment() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 dormant treat layer")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_check(_chk("effect_mask_enabled", true), "UI-07 dormant treat on")
	_edit(lid, func(l: Dictionary) -> void: (l["fx"] as Dictionary)["treatment_mask_path"] = _upath("ghost.png"))
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant treat active rejects")
	_check(_chk("effect_mask_enabled", false), "UI-07 dormant treat off via UI")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	_check(_badge_text("treatment_mask_path").begins_with("○ dormant"), "UI-07 dormant treat badge", _badge_text("treatment_mask_path"))
	var rd: Dictionary = shell.session.apply()
	_check(bool(rd.get("ok", false)), "UI-07 dormant treat applies", str(rd.get("errors", [])))
	if not await _ensure_editable("dormant-treat"):
		return
	_check(_chk("effect_mask_enabled", true), "UI-07 dormant treat reactivated")
	await settle(3)
	_check(not bool(shell.session.apply().get("ok", false)), "UI-07 dormant treat reactivated rejects")
	await _scrub_layer(lid)

func _harvest_flow() -> void:
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 harvest layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_check(_opt_by_value("displacement.driver", DRIVERS, "CUSTOM_TEXTURE"), "UI-07 harvest driver custom")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	# pick the OUTSIDE-data_dir user:// source via the real dialog path
	var wrap = _asset_wrap("displacement.custom_texture")
	(_asset_child(wrap, "AssetBrowse") as Button).pressed.emit()
	await settle(3)
	shell.asset_dialog.file_selected.emit(_src_upath("mask_half.png"))
	await settle(8)
	# amount so the texture has a visible effect later
	_edit(lid, func(l: Dictionary) -> void: (l["displacement"] as Dictionary)["amount_px"] = [60.0, 0.0])
	await _freeze_time()
	var pre_harvest: Image = await _surface("ui07_preh")
	var ap: Dictionary = shell.session.apply()
	_check(bool(ap.get("ok", false)), "UI-07 harvest apply ok", str(ap.get("errors", [])))
	var persisted: Dictionary = shell.production.load_look(str(ap.get("look_id", "")))["doc"]
	var player: Dictionary = FxLookScript.find_layer(persisted, lid)
	var href := str((player.get("displacement", {}) as Dictionary).get("custom_texture", ""))
	_check(href.begins_with(str(data_dir)) or href.begins_with("user://fx_asset_prod"), "UI-07 persisted ref is project-local", href)
	_check(not href.begins_with("user://fx_asset_src"), "UI-07 persisted ref not the authoring source", href)
	# delete the ORIGINAL authoring source: production must still render (test 6)
	DirAccess.remove_absolute(_src_upath("mask_half.png"))
	_check(not FileAccess.file_exists(_src_upath("mask_half.png")), "UI-07 authoring source deleted")
	var ref: Control = VsRuntimeScript.new()
	ref.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ref.size = Vector2(1280, 720)
	root.add_child(ref)
	await settle(30)
	var summary: Dictionary = ref.reload_production()
	_check(bool(summary.get("ok", false)), "UI-07 reference loads after source delete", str(summary.get("errors", [])))
	ref.runtime.screen.lab_preview_pause()
	ref.seek(0.5)
	await settle(10)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ref_img: Image = ref.runtime.subvp.get_texture().get_image()
	ref_img.save_png(out_dir.path_join("ui07_harvested.png"))
	_check(_roi_mean(pre_harvest, ref_img, Rect2i(0, 0, 1280, 720)) < 0.02, "UI-07 harvested production renders", "mean=%.5f" % _roi_mean(pre_harvest, ref_img, Rect2i(0, 0, 1280, 720)))
	ref.queue_free()
	await settle(5)
	# re-stage the source for later tests
	_half_mask(_src_upath("mask_half.png"))

# ---- T5: visual proofs per family ------------------------------------------------------

func _visual_proofs() -> void:
	if not await _ensure_editable("visuals"):
		return
	await _visual_mask()
	await _visual_displacement()
	await _visual_influence()
	await _visual_treatment()

func _visual_mask() -> void:
	# fringe + CUSTOM half mask: left fringed, right clean.
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 visual layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_edit(lid, func(l: Dictionary) -> void:
		(l["fx"] as Dictionary)["fringe"] = 2.5
		(l["mask"] as Dictionary)["enabled"] = true
		(l["mask"] as Dictionary)["source"] = "CUSTOM_MASK"
		(l["mask"] as Dictionary)["region"] = "FULL"
		(l["mask"] as Dictionary)["custom_mask"] = _upath("mask_half.png")
	)
	await _freeze_time()
	var masked: Image = await _surface("ui07_mask_on")
	_edit(lid, func(l: Dictionary) -> void: (l["mask"] as Dictionary)["enabled"] = false)
	await _freeze_time()
	var plain: Image = await _surface("ui07_mask_off")
	var left := _roi_mean(masked, plain, Rect2i(0, 0, 640, 720))
	var right := _roi_mean(masked, plain, Rect2i(640, 0, 640, 720))
	print("UI07 mask left=%.5f right=%.5f" % [left, right])
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = false)
	await _freeze_time()
	var base: Image = await _surface("ui07_mask_base")
	var vis := _roi_mean(masked, base, Rect2i(0, 0, 1280, 720))
	print("UI07 mask visible=%.5f" % vis)
	_check(vis > 0.003, "UI-07 mask effect visible vs no layer", "vis=%.5f" % vis)
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = true)
	_check(left > 0.005, "UI-07 mask affects masked half", "left=%.5f" % left)
	_check(right < 0.002, "UI-07 mask spares unmasked half", "right=%.5f" % right)

func _visual_displacement() -> void:
	# CUSTOM gradient texture vs NOISE driver: visibly different fields.
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 visual layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_edit(lid, func(l: Dictionary) -> void:
		(l["displacement"] as Dictionary)["enabled"] = true
		(l["displacement"] as Dictionary)["driver"] = "CUSTOM_TEXTURE"
		(l["displacement"] as Dictionary)["custom_texture"] = _upath("tex_gradient.png")
		(l["displacement"] as Dictionary)["amount_px"] = [160.0, 0.0]
	)
	await _freeze_time()
	var custom: Image = await _surface("ui07_disp_custom")
	_edit(lid, func(l: Dictionary) -> void: (l["displacement"] as Dictionary)["driver"] = "NOISE")
	await _freeze_time()
	var noise: Image = await _surface("ui07_disp_noise")
	var d := _roi_mean(custom, noise, Rect2i(0, 0, 1280, 720))
	print("UI07 displacement custom-vs-noise=%.5f" % d)
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = false)
	await _freeze_time()
	var dbase: Image = await _surface("ui07_disp_base")
	var dvis := _roi_mean(custom, dbase, Rect2i(0, 0, 1280, 720))
	print("UI07 displacement visible=%.5f" % dvis)
	_check(dvis > 0.002, "UI-07 displacement visible vs no layer", "vis=%.5f" % dvis)
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = true)
	_check(d > 0.002, "UI-07 custom texture drives displacement", "mean=%.5f" % d)

func _visual_influence() -> void:
	# influence half mask confines gradient displacement to the styled
	# (left) half: confined vs full differ where the mask transition
	# overlaps the echo, never on the empty right half.
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 visual layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_edit(lid, func(l: Dictionary) -> void:
		(l["displacement"] as Dictionary)["enabled"] = true
		(l["displacement"] as Dictionary)["driver"] = "CUSTOM_TEXTURE"
		(l["displacement"] as Dictionary)["custom_texture"] = _upath("tex_gradient.png")
		(l["displacement"] as Dictionary)["amount_px"] = [160.0, 0.0]
		(l["displacement"] as Dictionary)["influence_mask"] = {"enabled": true, "source": "CUSTOM_MASK", "region": "FULL", "space": "LAYER_SPACE", "custom_mask": _upath("mask_half.png"), "width_px": 0.0, "feather_px": 0.0, "expand_contract_px": 0.0, "invert": false}
	)
	await _freeze_time()
	var confined: Image = await _surface("ui07_infl_on")
	_edit(lid, func(l: Dictionary) -> void: ((l["displacement"] as Dictionary)["influence_mask"] as Dictionary)["enabled"] = false)
	await _freeze_time()
	var full: Image = await _surface("ui07_infl_off")
	var left := _roi_mean(confined, full, Rect2i(0, 0, 640, 720))
	var right := _roi_mean(confined, full, Rect2i(640, 0, 640, 720))
	print("UI07 influence left=%.5f right=%.5f" % [left, right])
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = false)
	await _freeze_time()
	var ibase: Image = await _surface("ui07_infl_base")
	var ivis := _roi_mean(confined, ibase, Rect2i(0, 0, 1280, 720))
	print("UI07 influence visible=%.5f" % ivis)
	_check(ivis > 0.001, "UI-07 influence effect visible vs no layer", "vis=%.5f" % ivis)
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = true)
	# The styled echo lives in the left half: confined-vs-full differ where
	# the mask transition overlaps it (left), never on the empty right.
	_check(left > 0.0015, "UI-07 influence confines left half", "left=%.5f" % left)
	_check(right < 0.002, "UI-07 influence spares right half", "right=%.5f" % right)

func _visual_treatment() -> void:
	# grade treatment gated by half treatment mask: left graded, right clean.
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 visual layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_edit(lid, func(l: Dictionary) -> void:
		(l["fx"] as Dictionary)["base_grade_amount"] = 1.0
		(l["fx"] as Dictionary)["grade_brightness"] = 0.6
		(l["fx"] as Dictionary)["effect_mask_enabled"] = true
		(l["fx"] as Dictionary)["effect_mask_base"] = true
		(l["fx"] as Dictionary)["treatment_mask_path"] = _upath("mask_half.png")
	)
	await _freeze_time()
	var treated: Image = await _surface("ui07_treat_on")
	_edit(lid, func(l: Dictionary) -> void: (l["fx"] as Dictionary)["effect_mask_enabled"] = false)
	await _freeze_time()
	var plain: Image = await _surface("ui07_treat_off")
	var left := _roi_mean(treated, plain, Rect2i(0, 0, 640, 720))
	var right := _roi_mean(treated, plain, Rect2i(640, 0, 640, 720))
	print("UI07 treatment left=%.5f right=%.5f" % [left, right])
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = false)
	await _freeze_time()
	var tbase: Image = await _surface("ui07_treat_base")
	var tvis := _roi_mean(treated, tbase, Rect2i(0, 0, 1280, 720))
	print("UI07 treatment visible=%.5f" % tvis)
	_check(tvis > 0.003, "UI-07 treatment visible vs no layer", "vis=%.5f" % tvis)
	_edit(lid, func(l: Dictionary) -> void: (l as Dictionary)["enabled"] = true)
	_check(left > 0.005, "UI-07 treatment affects masked half", "left=%.5f" % left)
	_check(right < 0.002, "UI-07 treatment spares unmasked half", "right=%.5f" % right)

# ---- T6: save/reopen/replace/clear ---------------------------------------------------------

func _save_reopen_replace() -> void:
	if not await _ensure_editable("save-reopen"):
		return
	var lid := _add_fx_layer()
	_check(lid != "", "UI-07 visual layer added")
	if lid == "":
		return
	_select_layer(lid)
	await settle(5)
	_check(_opt_by_value("displacement.driver", DRIVERS, "CUSTOM_TEXTURE"), "UI-07 sr driver custom")
	await settle(5)
	_select_layer(lid)
	await settle(5)
	var wrap = _asset_wrap("displacement.custom_texture")
	(_asset_child(wrap, "AssetBrowse") as Button).pressed.emit()
	await settle(3)
	var path_a := _upath("tex_gradient.png")
	shell.asset_dialog.file_selected.emit(path_a)
	await settle(8)
	var ap: Dictionary = shell.session.apply()
	_check(bool(ap.get("ok", false)), "UI-07 sr apply A ok", str(ap.get("errors", [])))
	var id_a := str(ap.get("look_id", ""))
	# reopen: new shell, same persisted A
	shell.queue_free()
	shell = null
	await settle(15)
	shell = _spawn()
	await settle(30)
	shell._select_key("echo_left", false)
	await settle(20)
	var back_a := ""
	for l in (shell.session.look.get("layers", []) as Array):
		if str((l as Dictionary).get("layer_id", "")) == lid:
			back_a = str(((l as Dictionary).get("displacement", {}) as Dictionary).get("custom_texture", ""))
	_check(back_a != "" and back_a == path_a.strip_edges() or back_a.begins_with(str(shell.production.data_dir)), "UI-07 reopen keeps A", back_a)
	# Apply A succeeded -> SHARED_PROTECTED (valid): own branch for replace.
	if not await _ensure_editable("replace"):
		return
	# replace with B via UI, apply, reopen: B authority, A gone from doc
	_select_layer(lid)
	await settle(5)
	var wrap2 = _asset_wrap("displacement.custom_texture")
	_check((_asset_child(wrap2, "AssetBrowse") as Button).text == "REPLACE", "UI-07 replace label when set")
	(_asset_child(wrap2, "AssetBrowse") as Button).pressed.emit()
	await settle(3)
	var path_b := _upath("mask_half.png")
	shell.asset_dialog.file_selected.emit(path_b)
	await settle(8)
	var ap2: Dictionary = shell.session.apply()
	_check(bool(ap2.get("ok", false)), "UI-07 sr apply B ok", str(ap2.get("errors", [])))
	var doc2: Dictionary = shell.production.load_look(str(ap2.get("look_id", "")))["doc"]
	var back_b := str(((FxLookScript.find_layer(doc2, lid) as Dictionary).get("displacement", {}) as Dictionary).get("custom_texture", ""))
	_check(back_b == path_b or back_b.begins_with(str(shell.production.data_dir)), "UI-07 replace persists B", back_b)

# ---- T7: dock containment ----------------------------------------------------------------------

func _containment() -> void:
	var dock: Control = shell.dock
	for f in FIELDS:
		var wrap = _asset_wrap(str(f))
		if wrap == null:
			_check(false, "UI-07 containment row %s" % str(f))
			continue
		_scroll_to_visible(wrap, dock)
		var wr: Rect2 = (wrap as Control).get_global_rect()
		var dr: Rect2 = dock.get_global_rect()
		_check(dr.has_point(wr.position) and wr.size.x <= dr.size.x + 1.0, "UI-07 row inside dock %s" % str(f), "%s in %s" % [str(wr), str(dr)])
		for cname in ["AssetBrowse", "AssetClear"]:
			var b = _asset_child(wrap, cname)
			_check(b is Button and (b as Button).is_visible_in_tree() and (b as Control).size.x > 10.0, "UI-07 %s %s clickable" % [str(f), cname])
