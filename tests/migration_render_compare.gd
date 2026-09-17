extends SceneTree
# Round-2 Finding 7: visual migration proof. Renders the MIGRATED vNEXT looks
# for the representative targets (VS MARK, PRIMARY, ECHO, NAME), pairs them with
# the REAL v0.3 captured output (produced by the v0.3 reference harness from the
# fresh v0.3 extract), computes numeric image comparisons and writes side-by-side
# + diff-heat composites plus MIGRATION_VISUAL_COMPARISON.md.
# Windowed: needs rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxMigrationScript := preload("res://scripts/fx_vnext/fx_migration.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String
var v03_dir: String
var report_rows: Array = []

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/migration_visual")
	DirAccess.make_dir_recursive_absolute(out_dir)
	v03_dir = OS.get_environment("FXLAB_V03_CAPTURE_DIR")
	if v03_dir == "":
		v03_dir = "C:/Users/will/nrcu-fx-lab-v02-work/_vnext_work/v03_ref/evidence/v03_reference"

	var fixture: Dictionary = _load_json("res://tests/fixtures/vnext/fixture_fx_looks_v03.json")
	_check(not fixture.is_empty(), "fixture loads")
	var migration = FxMigrationScript.new()
	var migrated: Dictionary = migration.migrate_looks_document(fixture)
	_check(bool(migrated["ok"]), "migration ok", str(migrated.get("errors", [])))
	var looks: Dictionary = migrated["looks"]

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
	sr.seek(1.5)
	var renderer = FxLayerRendererScript.new(sr.screen, sr.registry)
	var registry_keys: Array = []
	for key in sr.registry.keys():
		registry_keys.append(str(key))

	# case list: fixture look -> authoring target (v0.3 capture name uses the same tag)
	var cases := [
		{"look": "BASELINE_MARK_FRINGE", "target": "mark", "v03_tag": "MARK", "expect_effect": true},
		# certified semantics: flow without fringe is a no-op in the legacy shader
		# (line 867); the migrated render is expected near-neutral for this look.
		{"look": "BASELINE_PRIMARY_FLOW_BLUR", "target": "primary_left", "v03_tag": "PRIMARY", "expect_effect": false},
		{"look": "BASELINE_ECHO_DITHER_RGB", "target": "echo_left", "v03_tag": "ECHO", "expect_effect": true},
		{"look": "BASELINE_ECHO_DITHER_RGB", "target": "name_left", "v03_tag": "NAME", "expect_effect": true},
	]

	for case in cases:
		var look_id := str(case["look"])
		var target := str(case["target"])
		if not registry_keys.has(target):
			var tag := str(case["v03_tag"]).to_lower()
			for key in registry_keys:
				if str(key).contains(tag):
					target = str(key)
					break
		_check(registry_keys.has(target), "target exists in composition: %s" % target, str(registry_keys))
		if not registry_keys.has(target):
			continue
		var look: Dictionary = looks.get(look_id, {})
		if look.is_empty():
			_check(false, "migrated look present: " + look_id)
			continue
		# vNEXT render of the MIGRATED look
		renderer.clear_all()
		await settle(4)
		var no_look: Image = await shot(svp, "vnext_no_look_%s" % str(case["v03_tag"]).to_lower())
		var applied: Dictionary = renderer.apply_look(target, look)
		renderer.set_time(1.5)
		await settle(10)
		_check(bool(applied["ok"]), "migrated look applies: %s" % look_id, str(applied.get("errors", [])))
		var vnext_img: Image = await shot(svp, "vnext_%s_%s_t1500" % [str(case["v03_tag"]).to_lower(), look_id.to_lower()])
		renderer.clear_target(target)
		await settle(4)

		# v0.3 reference capture
		var tag_lower := str(case["v03_tag"]).to_lower()
		var candidates: Array = []
		for tag in [tag_lower, "vs_" + tag_lower]:
			candidates.append(v03_dir.path_join("v03_%s_%s_t1500.png" % [tag, look_id]))
			candidates.append(v03_dir.path_join("v03_%s_%s_t1500.png" % [tag, look_id.to_lower()]))
		var v03_path := ""
		var v03_img := Image.new()
		var v03_ok := false
		for candidate in candidates:
			if FileAccess.file_exists(str(candidate)):
				v03_path = str(candidate)
				v03_ok = v03_img.load(v03_path) == OK
				if v03_ok:
					break
		if v03_path == "":
			v03_path = str(candidates[0])
		_check(v03_ok, "v0.3 reference capture found: " + v03_path.get_file(), v03_path)

		var row := {"look": look_id, "target": target, "v03_file": v03_path.get_file(), "vnext_file": "vnext_%s_%s_t1500" % [str(case["v03_tag"]).to_lower(), look_id.to_lower()]}
		if v03_ok:
			var numeric := _mean_abs_diff(v03_img, vnext_img)
			row["mean_abs_diff"] = numeric
			var effect_delta := _mean_abs_diff(no_look, vnext_img)
			row["vnext_effect_delta"] = effect_delta
			if bool(case["expect_effect"]):
				_check(effect_delta > 0.001, "migrated look visibly renders (%s)" % look_id, "effect=%.5f" % effect_delta)
			else:
				_check(effect_delta <= 0.005, "migrated look stays near-neutral per certified semantics (%s)" % look_id, "effect=%.5f" % effect_delta)
			# side-by-side + diff heat
			_write_composite(v03_img, vnext_img, "compare_%s_%s" % [str(case["v03_tag"]).to_lower(), look_id.to_lower()])
			_check(numeric <= 0.30, "v0.3 vs vNEXT within documented bound (%s)" % look_id, "mean=%.5f" % numeric)
		report_rows.append(row)

	_write_report()
	var f := FileAccess.open(out_dir.path_join("summary_migration_visual_check.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL", "rows": report_rows}, "  "))
		f.close()
	print("[MIGVIS] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _write_composite(v03_img: Image, vnext_img: Image, name: String) -> void:
	# half-scale side-by-side with a divider
	var w := int(1280 / 2)
	var h := int(720 / 2)
	var left := v03_img.duplicate()
	left.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var right := vnext_img.duplicate()
	right.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var comp := Image.create(w * 2 + 4, h, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0.1, 0.1, 0.12, 1.0))
	comp.blit_rect(left, Rect2i(0, 0, w, h), Vector2i(0, 0))
	comp.blit_rect(right, Rect2i(0, 0, w, h), Vector2i(w + 4, 0))
	comp.save_png(out_dir.path_join(name + "_side_by_side.png"))
	# diff heat
	var diff := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	for y in range(0, 720, 2):
		for x in range(0, 1280, 2):
			var ca := v03_img.get_pixel(x, y)
			var cb := vnext_img.get_pixel(x, y)
			var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			var v := clampf(d * 6.0, 0.0, 1.0)
			diff.set_pixel(x, y, Color(v, v * 0.4, 0.0, 1.0))
			diff.set_pixel(x + 1, y, Color(v, v * 0.4, 0.0, 1.0))
			diff.set_pixel(x, y + 1, Color(v, v * 0.4, 0.0, 1.0))
			diff.set_pixel(x + 1, y + 1, Color(v, v * 0.4, 0.0, 1.0))
	diff.save_png(out_dir.path_join(name + "_diff_heat.png"))

func _write_report() -> void:
	var f := FileAccess.open(out_dir.path_join("MIGRATION_VISUAL_COMPARISON.md"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# MIGRATION VISUAL COMPARISON (Round-2 Finding 7)\n\n")
	f.store_string("v0.3: real captured output from the fresh v0.3 extract (v03_reference harness).\n")
	f.store_string("vNEXT: migrated look rendered through the shared runtime path at the same frozen time (t=1.5).\n\n")
	f.store_string("| Look | Target | v0.3 file | vNEXT file | mean abs diff | vNEXT effect vs no-look | Side-by-side | Diff heat |\n")
	f.store_string("|---|---|---|---|---|---|---|---|\n")
	for row in report_rows:
		var numeric = row.get("mean_abs_diff", null)
		var effect = row.get("vnext_effect_delta", null)
		f.store_string("| %s | %s | %s | %s | %s | %s | compare_%s_side_by_side.png | compare_%s_diff_heat.png |\n" % [
			str(row["look"]), str(row["target"]), str(row["v03_file"]), str(row["vnext_file"]),
			("%.5f" % numeric) if numeric != null else "n/a",
			("%.5f" % effect) if effect != null else "n/a",
			str(row["look"]).to_lower(), str(row["look"]).to_lower(),
		])
	f.store_string("\nBound: global mean-abs-diff <= 0.30 for the pair (different pipelines; the numeric values and the visual composites are the evidence; per-pixel identity is not claimed across the legacy monolith and the layered renderer).\n")
	f.close()

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func settle(n: int) -> void:
	for i in n:
		await process_frame

func shot(svp: SubViewport, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = svp.get_texture().get_image()
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
