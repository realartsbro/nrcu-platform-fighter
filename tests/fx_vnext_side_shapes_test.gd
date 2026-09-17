extends SceneTree
# Round-2 architecture addition: side-field geometry is a SHAPE/MASK PRESET.
# Verifies: default preset, per-side selection, mirror semantics, explicit
# project-local masks, graceful fallback for broken selections, and the REAL
# mount path consuming the resolved mask (side-field render target works).
# Windowed: mounts and renders.

const FxSideShapesScript := preload("res://scripts/fx_vnext/fx_side_shapes.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/side_shapes")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data_dir := "user://vnext_shapes_data"
	_wipe_dir(ProjectSettings.globalize_path(data_dir))
	OS.set_environment("NRCU_FX_DATA_DIR", data_dir)

	# ---- preset table integrity ---------------------------------------------------
	_check((FxSideShapesScript.preset_table_ok() as Array).is_empty(), "default preset masks are loadable project assets", str(FxSideShapesScript.preset_table_ok()))

	# ---- defaults -----------------------------------------------------------------
	var defaults: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((defaults["left"] as Dictionary).get("preset_id", "")) == "CURRENT_HOURGLASS", "left defaults to the current hourglass preset", str(defaults["left"]))
	_check(str((defaults["right"] as Dictionary).get("preset_id", "")) == "CURRENT_HOURGLASS", "right defaults to the current hourglass preset", str(defaults["right"]))
	_check(str((defaults["left"] as Dictionary).get("mask", "")) == "res://assets/vs/generated/side_field_left_mask.png", "left default mask is the current asset", str((defaults["left"] as Dictionary).get("mask", "")))

	# ---- explicit project-local mask per side --------------------------------------
	var mask_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			mask_img.set_pixel(x, y, Color(1, 1, 1, 1) if x < 32 else Color(0, 0, 0, 0))
	var custom_ref := data_dir.path_join("custom_field_mask.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	mask_img.save_png(ProjectSettings.globalize_path(custom_ref))
	_check(FileAccess.file_exists(custom_ref), "custom side-field mask written", custom_ref)
	_check(FxSideShapesScript.write_selection(data_dir, {"left": custom_ref}), "selection file written")
	var resolved: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((resolved["left"] as Dictionary).get("source", "")) == "explicit", "left honors the explicit mask", str(resolved["left"]))
	_check(str((resolved["left"] as Dictionary).get("mask", "")) == custom_ref, "left resolves the explicit ref", str((resolved["left"] as Dictionary).get("mask", "")))
	_check(str((resolved["right"] as Dictionary).get("preset_id", "")) == "CURRENT_HOURGLASS", "right stays on the default while left is custom", str(resolved["right"]))

	# ---- mirror semantics -----------------------------------------------------------
	FxSideShapesScript.write_selection(data_dir, {"left": custom_ref, "mirror": true})
	var mirrored: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((mirrored["right"] as Dictionary).get("mask", "")) == custom_ref, "mirror applies the left selection to the right side", str(mirrored["right"]))
	FxSideShapesScript.write_selection(data_dir, {"left": "CURRENT_HOURGLASS", "mirror": true})
	var mirrored_preset: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((mirrored_preset["right"] as Dictionary).get("mask", "")).ends_with("side_field_right_mask.png"), "mirrored preset keeps per-side preset masks", str(mirrored_preset["right"]))

	# ---- graceful fallback ----------------------------------------------------------
	FxSideShapesScript.write_selection(data_dir, {"left": "user://vnext_shapes_data/does_not_exist.png"})
	var missing: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((missing["left"] as Dictionary).get("source", "")) == "fallback", "missing explicit mask falls back", str(missing["left"]))
	_check(str((missing["left"] as Dictionary).get("warning", "")) != "", "fallback records a warning", str((missing["left"] as Dictionary).get("warning", "")))
	FxSideShapesScript.write_selection(data_dir, {"left": "C:/external/shape.png"})
	var external: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((external["left"] as Dictionary).get("source", "")) == "fallback", "external path falls back (never breaks the mount)", str(external["left"]))
	# garbage selection file
	var f := FileAccess.open(ProjectSettings.globalize_path(data_dir.path_join("side_shapes.json")), FileAccess.WRITE)
	f.store_string("{{{{ not json")
	f.close()
	var garbage: Dictionary = FxSideShapesScript.resolve_all(data_dir)
	_check(str((garbage["left"] as Dictionary).get("preset_id", "")) == "CURRENT_HOURGLASS", "garbage selection falls back to defaults", str(garbage["left"]))

	# ---- REAL mount consumes the resolved mask ---------------------------------------
	FxSideShapesScript.write_selection(data_dir, {"left": custom_ref})
	var svp := SubViewport.new()
	svp.size = Vector2i(1280, 720)
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	var sr = FxScreenRuntimeScript.new()
	var disp := SubViewportContainer.new()
	disp.stretch = true
	disp.size = Vector2(1280, 720)
	svp.add_child(disp)
	disp.add_child(sr.subvp)
	await settle(40)
	sr.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(60)
	var field_left = sr.screen.get_node_or_null("Root/SideFields/FieldLeft")
	_check(field_left != null, "side field node exists")
	if field_left != null:
		_check(str(field_left.get_meta("fx_side_shape_source", "")) == "explicit", "mount consumed the explicit selection", str(field_left.get_meta("fx_side_shape_source", "")))
		_check(str(field_left.get_meta("fx_side_shape_mask", "")) == custom_ref, "mount resolved the custom mask", str(field_left.get_meta("fx_side_shape_mask", "")))
	var field_right = sr.screen.get_node_or_null("Root/SideFields/FieldRight")
	if field_right != null:
		_check(str(field_right.get_meta("fx_side_shape_source", "")) == "preset", "right side keeps its own selection", str(field_right.get_meta("fx_side_shape_source", "")))
	sr.seek(1.5)
	var renderer = FxLayerRendererScript.new(sr.screen, sr.registry)
	var keys: Array = []
	for key in sr.registry.keys():
		keys.append(str(key))
	var field_key := ""
	for key in keys:
		if str(key).begins_with("field_left"):
			field_key = str(key)
			break
	_check(field_key != "", "side field is an fx target key", str(keys))
	if field_key != "":
		await RenderingServer.frame_post_draw
		var baseline: Image = svp.get_texture().get_image()
		var look: Dictionary = FxLookScript.new_look("SIDE_FIELD_TEST", "Side Field")
		var fx: Dictionary = FxLookScript.new_layer("FX", "field rgb")
		fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 16.0}
		look["layers"].append(fx)
		var applied: Dictionary = renderer.apply_look(field_key, look)
		renderer.set_time(1.5)
		await settle(10)
		await RenderingServer.frame_post_draw
		var styled: Image = svp.get_texture().get_image()
		styled.save_png(out_dir.path_join("side_field_styled.png"))
		_check(bool(applied["ok"]), "look applies to the side field", str(applied.get("errors", [])))
		_check(_mean_abs_diff(baseline, styled) > 0.002, "side field renders through the resolved mask", "mean=%.5f" % _mean_abs_diff(baseline, styled))

	var rf := FileAccess.open(out_dir.path_join("summary_side_shapes_check.json"), FileAccess.WRITE)
	if rf != null:
		rf.store_string(JSON.stringify({"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}, "  "))
		rf.close()
	print("[SIDE-SHAPES] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func settle(n: int) -> void:
	for i in n:
		await process_frame

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

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
