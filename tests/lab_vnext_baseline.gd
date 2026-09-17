extends SceneTree
# vNext Phase 0 — immutable baseline captures (spec 14 / G0 step 4).
# Captures the unstyled VS screen and three representative v0.3 Looks at a
# deterministic presentation time. The v0.3 production files are copied out as
# migration fixtures and restored byte-exactly afterwards.

var lab: Node
var out_dir: String
var captures: Array = []
var notes: Dictionary = {}

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_phase0/baseline")
	DirAccess.make_dir_recursive_absolute(out_dir)
	lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
	root.add_child(lab)
	await settle(40)
	notes["parent"] = "NRCU_FX_LAB_v0_3_FINAL_STANDALONE_20260915.zip"
	notes["parent_sha256"] = "2e5a59a71adbdb80b6de1cd1621d1a4df8719a69e6738bf6da0ca3e54c55de45"
	notes["engine"] = str(Engine.get_version_info().get("string", ""))
	var looks_path: String = lab.PRODUCTION_LOOKS_PATH
	var assigns_path: String = lab.PRODUCTION_ASSIGNMENTS_PATH
	var looks_orig := _read_text(looks_path)
	var assigns_orig := _read_text(assigns_path)
	lab._on_source_mode(0)
	lab._on_format(0)
	await settle(10)

	# ---- 1) unstyled VS screen ---------------------------------------------
	lab.target_mode = "ALL"
	await neutral_state()
	await _seek()
	await capture("baseline_unstyled")

	# ---- 2) MARK — fringe + flow + rgb -------------------------------------
	lab.target_mode = "ROLE"
	lab.target_role = "VS MARK"
	await strong_fringe_state()
	lab.preset_name_edit.text = "BASELINE_MARK_FRINGE"
	notes["published_mark"] = bool(lab._publish_current_look())
	await settle(4)
	if lab.assignment_scope_picker != null:
		lab.assignment_scope_picker.select(lab.ASSIGNMENT_SCOPES.find("STATIC ELEMENT"))
		lab._on_assignment_scope_changed(0)
	lab._assign_current_look()
	await settle(4)
	notes["mark_context"] = lab._current_target_context()
	notes["mark_resolved"] = lab._resolve_assignment(lab._current_target_context())
	await _seek()
	await capture("baseline_look_mark_fringe")

	# ---- 3) ECHO — dither + rgb, semantic assignment -----------------------
	lab.target_mode = "ALL"
	await neutral_state()
	lab.target_mode = "SELECTED"
	lab.selected_slot = "echo_left"
	lab._normalize_target()
	lab._refresh_assignment_view()
	await echo_state()
	lab.preset_name_edit.text = "BASELINE_ECHO_DITHER_RGB"
	notes["published_echo"] = bool(lab._publish_current_look())
	await settle(3)
	if lab.assignment_scope_picker != null:
		lab.assignment_scope_picker.select(lab.ASSIGNMENT_SCOPES.find("FIGHTER + ROLE + VISUAL SIDE"))
		lab._on_assignment_scope_changed(0)
	lab._assign_current_look()
	await settle(4)
	notes["echo_context"] = lab._current_target_context()
	notes["echo_resolved"] = lab._resolve_assignment(lab._current_target_context())
	await _seek()
	await capture("baseline_look_echo_dither_rgb")

	# ---- 4) PRIMARY — flow + colour blur -----------------------------------
	lab.target_mode = "ALL"
	await neutral_state()
	lab.target_mode = "SELECTED"
	lab.selected_slot = "primary_left"
	lab._normalize_target()
	lab._refresh_assignment_view()
	await flow_blur_state()
	lab.preset_name_edit.text = "BASELINE_PRIMARY_FLOW_BLUR"
	notes["published_primary"] = bool(lab._publish_current_look())
	await settle(3)
	await _seek()
	await capture("baseline_look_primary_flow_blur")

	# ---- fixtures + byte-exact restore -------------------------------------
	_write_text(out_dir.path_join("fixture_fx_looks_v03.json"), _read_text(looks_path))
	_write_text(out_dir.path_join("fixture_fx_assignments_v03.json"), _read_text(assigns_path))
	_write_text(looks_path, looks_orig)
	_write_text(assigns_path, assigns_orig)
	notes["production_restored"] = _read_text(looks_path) == looks_orig and _read_text(assigns_path) == assigns_orig
	lab.target_mode = "ALL"
	await neutral_state()
	var f := FileAccess.open(out_dir.path_join("baseline_summary.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"notes": notes, "captures": captures}, "  "))
		f.close()
	print("[VNEXT-BASELINE] done · captures=", captures.size(), " restored=", notes["production_restored"])
	quit()

func _seek() -> void:
	lab._transport_seek_to(1.5)
	await settle(3)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(out_dir.path_join(name + ".png"))
		captures.append({"name": name, "file": name + ".png", "size": [img.get_width(), img.get_height()]})
	else:
		captures.append({"name": name, "file": "", "size": []})

func neutral_state() -> void:
	lab.state["pure_continuous"] = true
	lab.state["base_opacity"] = 1.0
	lab.state["base_grade_amount"] = 0.0
	lab.state["fx_size"] = 1.0
	lab.state["fx_intensity"] = 1.0
	lab.state["pattern_scale"] = 1.0
	for fx in lab.FX_NAMES:
		lab.state["fx_on"][fx] = false
		lab.motion_enabled[fx] = false
		lab.state["fx_amount"][fx] = 1.0
	lab._reset_runtime_amounts()
	lab._apply_fx()
	await settle(5)

func strong_fringe_state() -> void:
	lab.state["pure_continuous"] = true
	lab.state["fx_on"]["dither"] = false
	lab.state["fx_on"]["fringe"] = true
	lab.state["fx_on"]["flow"] = true
	lab.state["fx_on"]["rgb"] = true
	lab.state["fx_size"] = 1.0
	lab.state["fx_intensity"] = 1.6
	lab.state["edge_width"] = 12.0
	lab.state["wind_reach"] = 54.0
	lab.state["wind_trail"] = 1.0
	lab.state["fringe_bleed"] = 1.0
	lab.state["flow_strength"] = 1.8
	lab.state["rgb_shift_amount"] = 18.0
	lab.state["color_blur"] = 2.0
	lab.state["fringe_coverage_mode"] = 0.0
	lab._reset_runtime_amounts()
	lab._apply_fx()
	await settle(6)

func echo_state() -> void:
	lab.state["pure_continuous"] = false
	lab.state["fx_on"]["dither"] = true
	lab.state["fx_on"]["fringe"] = false
	lab.state["fx_on"]["flow"] = false
	lab.state["fx_on"]["rgb"] = true
	lab.state["fx_size"] = 1.0
	lab.state["fx_intensity"] = 1.2
	lab.state["rgb_shift_amount"] = 14.0
	lab.state["color_blur"] = 1.0
	lab.state["fringe_coverage_mode"] = 0.0
	lab._reset_runtime_amounts()
	lab._apply_fx()
	await settle(6)

func flow_blur_state() -> void:
	lab.state["pure_continuous"] = false
	lab.state["fx_on"]["dither"] = false
	lab.state["fx_on"]["fringe"] = false
	lab.state["fx_on"]["flow"] = true
	lab.state["fx_on"]["rgb"] = false
	lab.state["fx_size"] = 1.0
	lab.state["fx_intensity"] = 1.1
	lab.state["flow_strength"] = 1.4
	lab.state["color_blur"] = 3.0
	lab.state["fringe_coverage_mode"] = 0.0
	lab._reset_runtime_amounts()
	lab._apply_fx()
	await settle(6)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
