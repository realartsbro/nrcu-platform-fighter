extends SceneTree
# vNext migration render check (G5) — migrated v0.3 looks render through the
# shared runtime path (layer renderer + shared shader) inside a real mounted
# screen. Windowed: needs rendering for captures.

var checks: Array = []
var failures: int = 0
var out_dir: String
var runtime
var renderer
var root_ctrl: Control

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/migration")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxScreenRuntimeScript = load("res://scripts/fx_vnext/fx_screen_runtime.gd")
	var FxLayerRendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")
	var FxMigrationScript = load("res://scripts/fx_vnext/fx_migration.gd")

	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame

	var mounted: bool = runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(50)
	_check(mounted, "screen mounts")
	runtime.seek(1.5)
	await settle(6)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.5)

	var fixture := _load_json("res://tests/fixtures/vnext/fixture_fx_looks_v03.json")
	var migration = FxMigrationScript.new()
	var migrated: Dictionary = migration.migrate_looks_document(fixture)
	_check(bool(migrated["ok"]), "fixture migrates", str(migrated["errors"]))
	var looks: Dictionary = migrated["looks"]
	var reviews: Dictionary = migrated["reviews"]

	# target mapping: migrated look id -> authoring target + minimum expected diff
	var cases := [
		{"look": "BASELINE_ECHO_DITHER_RGB", "target": "echo_left", "min_diff": 0.0008, "max_diff": 1.0, "why": "dither + rgb tear"},
		{"look": "BASELINE_MARK_FRINGE", "target": "mark", "min_diff": 0.004, "max_diff": 1.0, "why": "fringe (+flow now ported)"},
		{"look": "BASELINE_PRIMARY_FLOW_BLUR", "target": "primary_left", "min_diff": 0.0, "max_diff": 0.005, "why": "certified semantics: flow without fringe is a no-op (legacy shader line 867)"},
	]
	for case in cases:
		var look_id := str(case["look"])
		var target := str(case["target"])
		# migration proof dumps: original v0.3 JSON + migrated v0.4 JSON
		_dump_json(out_dir.path_join("migration_%s_original.json" % look_id.to_lower()), (fixture.get("looks", {}) as Dictionary).get(look_id, {}))
		_dump_json(out_dir.path_join("migration_%s_migrated.json" % look_id.to_lower()), looks[look_id])
		var src: Image = await capture("migration_%s_neutral" % look_id.to_lower())
		var look: Dictionary = looks[look_id]
		var applied: Dictionary = renderer.apply_look(target, look)
		_check(bool(applied["ok"]), "applies to %s: %s" % [target, look_id], str(applied["errors"]))
		renderer.set_time(1.5)
		await settle(8)
		var img: Image = await capture("migration_%s_rendered" % look_id.to_lower())
		var diff := _mean_abs_diff(src, img)
		_check(diff >= float(case["min_diff"]), "%s renders its effect (%s)" % [look_id, str(case["why"])], "mean=%.5f" % diff)
		_check(diff <= float(case["max_diff"]), "%s within expected range" % look_id, "mean=%.5f" % diff)
		renderer.clear_target(target)

	# review flags must explain the flow gap and stay visible for the researcher
	_check(reviews.has("BASELINE_MARK_FRINGE") and str(reviews["BASELINE_MARK_FRINGE"]).contains("flow distortion"), "MARK_FRINGE review explains flow")
	_check(reviews.has("BASELINE_PRIMARY_FLOW_BLUR"), "PRIMARY_FLOW_BLUR flagged")

	var f := FileAccess.open(out_dir.path_join("summary_migration_check.json"), FileAccess.WRITE)
	var summary := {
		"checks": checks.size(),
		"failures": failures,
		"migrated": looks.keys(),
		"reviews": reviews,
	}
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("[MIGRATION-CHECK] done · checks=%d failures=%d" % [checks.size(), failures])
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

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _dump_json(path: String, doc: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(doc, "  ", true))
		file.close()
