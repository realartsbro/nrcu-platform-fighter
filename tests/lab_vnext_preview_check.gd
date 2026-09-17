extends SceneTree
# Round-2 Finding 2: Full Composition Preview.
# WORKING  = selected target shows its Draft, ALL other targets show their
#            effective persisted Production styles (composited together).
# PRODUCTION = every target shows persisted styles only.
# The contract example: style target A in production, then edit target B while
# A's applied look REMAINS visible. Windowed: needs rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String
var shell: Control
var data_dir: String
var draft_dir: String

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/preview")
	DirAccess.make_dir_recursive_absolute(out_dir)
	data_dir = OS.get_environment("NRCU_FX_DATA_DIR")
	draft_dir = OS.get_environment("NRCU_FX_DRAFT_DIR")
	_wipe_dir(ProjectSettings.globalize_path(data_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	shell = scene.instantiate()
	root.add_child(shell)
	await settle(20)
	# park the transport at a fully revealed HOLD time (deterministic stills)
	shell.runtime.seek(1.5)
	shell._sync_time(1.5)
	if shell.renderer != null:
		shell.renderer.set_time(1.5)
	await settle(8)

	# ---- select mark and give its draft a visible change -------------------------
	shell._select_key("mark", false)
	await settle(10)
	var layers: Array = shell.session.look.get("layers", [])
	var source_id := str((layers[0] as Dictionary).get("layer_id", ""))
	shell._edit_layer(source_id, func(doc):
		var l: Dictionary = load("res://scripts/fx_vnext/fx_look.gd").find_layer(doc, source_id)
		l["opacity"] = 0.5
	)
	await settle(8)
	_check(shell.preview_mode == "WORKING", "preview starts in WORKING mode", shell.preview_mode)
	var baseline: Image = await capture("preview_baseline_no_production")

	# ---- write a Production look + assignment for echo_left ----------------------
	var prod := FxProductionScript.new()
	prod.data_dir = data_dir
	var echo_look: Dictionary = FxLookScript.new_look("ICE_MAGE_ECHO_LEFT", "Ice Echo")
	var fx: Dictionary = FxLookScript.new_layer("FX", "Echo rgb")
	fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": 20.0}
	echo_look["layers"].append(fx)
	var applied: Dictionary = prod.apply({"look": echo_look})
	_check(bool(applied["ok"]), "production accepts echo look", str(applied.get("errors", [])))
	var doc: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(doc, FxResolverScript.normalize_selector(shell.runtime.registry.context_for_key("echo_left")), "ICE_MAGE_ECHO_LEFT", "")
	applied = prod.apply({"assignments": doc})
	_check(bool(applied["ok"]), "production accepts assignment", str(applied.get("errors", [])))

	# ---- WORKING preview: echo production visible WHILE mark is edited -----------
	shell._render_current_look()
	await settle(10)
	var working: Image = await capture("preview_working_mark_draft")
	_check(str(shell._plan_status.get("mark", "")) == "DRAFT", "WORKING: selected target is the draft", str(shell._plan_status.get("mark", "")))
	_check(str(shell._plan_status.get("echo_left", "")).begins_with("PRODUCTION"), "WORKING: other target uses production", str(shell._plan_status.get("echo_left", "")))
	var unstyled_found := false
	var unstyled_key := ""
	for key in shell.runtime.registry.keys():
		if str(shell._plan_status.get(str(key), "")) == "UNSTYLED":
			unstyled_found = true
			unstyled_key = str(key)
			break
	_check(unstyled_found, "WORKING: unstyled targets stay unstyled", unstyled_key)
	var echo_visible := _mean_abs_diff(baseline, working)
	_check(echo_visible > 0.0003, "WORKING: applied production look of the OTHER target is visible", "mean=%.5f" % echo_visible)

	# ---- PRODUCTION preview: draft disappears, persisted styles stay -------------
	shell._toggle_preview_mode()
	await settle(10)
	_check(shell.preview_mode == "PRODUCTION", "toggle switches to PRODUCTION", shell.preview_mode)
	var production: Image = await capture("preview_production_only")
	_check(str(shell._plan_status.get("mark", "")) == "UNSTYLED", "PRODUCTION: draft is not shown", str(shell._plan_status.get("mark", "")))
	_check(str(shell._plan_status.get("echo_left", "")).begins_with("PRODUCTION"), "PRODUCTION: persisted style shown", str(shell._plan_status.get("echo_left", "")))
	var mark_rect := Rect2i(534, 222, 211, 224)
	var draft_delta := _region_abs_diff(working, production, mark_rect)
	_check(draft_delta > 0.0002, "PRODUCTION: draft edit gone in the mark region", "region=%.5f" % draft_delta)
	_check(_mean_abs_diff(baseline, production) > 0.003, "PRODUCTION: production look still visible", "mean=%.5f" % _mean_abs_diff(baseline, production))

	# ---- back to WORKING: draft returns deterministically ------------------------
	shell._toggle_preview_mode()
	await settle(10)
	var working2: Image = await capture("preview_working_again")
	_check(_mean_abs_diff(working, working2) < 0.0005, "WORKING is deterministic across toggles", "mean=%.6f" % _mean_abs_diff(working, working2))

	# ---- the contract example end to end: apply mark, then edit echo -------------
	# (style A, then edit B - A stays visible; here: mark draft applied to
	# production, then echo edited as the selected target)
	shell._action_apply()
	await settle(10)
	shell._render_current_look()
	await settle(8)
	var applied_ids: Array = shell.production.list_look_ids()
	var mark_applied := false
	for look_id in applied_ids:
		if str(look_id).contains("MARK"):
			mark_applied = true
	_check(mark_applied, "mark draft applied to production", str(applied_ids))
	shell._select_key("echo_left", false)
	await settle(10)
	var contract_capture: Image = await capture("preview_contract_example")
	_check(str(shell._plan_status.get("echo_left", "")) == "DRAFT", "contract: echo is now the draft", str(shell._plan_status.get("echo_left", "")))
	_check(str(shell._plan_status.get("mark", "")).begins_with("PRODUCTION"), "contract: previous target style stays visible", str(shell._plan_status.get("mark", "")))
	var mark_still := _region_abs_diff(baseline, contract_capture, mark_rect)
	_check(mark_still > 0.001, "contract: applied mark look visibly retained while editing echo", "region=%.5f" % mark_still)

	var f := FileAccess.open(out_dir.path_join("summary_preview_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[PREVIEW] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

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

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(max(count, 1))

func _region_abs_diff(a: Image, b: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y, 2):
		for x in range(rect.position.x, rect.position.x + rect.size.x, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(max(count, 1))

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
