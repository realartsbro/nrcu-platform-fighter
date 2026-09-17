extends SceneTree
# vNext migration test — v0.3 → v0.4 Looks + v1 → v2 assignments (specs/08).

var checks: Array = []
var failures: int = 0
var out_dir: String

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var FxProductionScript = load("res://scripts/fx_vnext/fx_production.gd")
	var FxDraftsScript = load("res://scripts/fx_vnext/fx_drafts.gd")
	var FxMigrationScript = load("res://scripts/fx_vnext/fx_migration.gd")

	var migration = FxMigrationScript.new()

	# ---- migrate the v0.3 fixture -------------------------------------------------
	var fixture := _load_json("res://tests/fixtures/vnext/fixture_fx_looks_v03.json")
	_check(not fixture.is_empty(), "fixture loads")
	var result: Dictionary = migration.migrate_looks_document(fixture)
	_check(bool(result["ok"]), "migration ok", str(result["errors"]))
	var looks: Dictionary = result["looks"]
	var reviews: Dictionary = result["reviews"]
	_check(looks.size() == 3, "three looks migrated", "n=%d" % looks.size())

	# ---- ECHO_DITHER_RGB: clean, fully mapped -------------------------------------
	var echo: Dictionary = looks.get("BASELINE_ECHO_DITHER_RGB", {})
	_check(not echo.is_empty() and str(echo["status"]) == "PRODUCTION", "echo look migrates clean", str(echo.get("status", "")))
	_check(not reviews.has("BASELINE_ECHO_DITHER_RGB"), "echo needs no review")
	_check(echo["layers"].size() == 2, "echo has SOURCE + legacy FX")
	_check(str(echo["layers"][1]["name"]) == "Legacy v0.3 Treatment", "legacy layer name", str(echo["layers"][1].get("name", "")))
	_check(str(echo["layers"][1]["input"]) == "ORIGINAL_SOURCE" and str(echo["layers"][1]["plane"]) == "TARGET_SOURCE", "legacy layer input/plane")
	var echo_fx: Dictionary = echo["layers"][1]["fx"]
	_check(absf(float(echo_fx["dither"]) - 1.0) < 0.0001 and absf(float(echo_fx["rgb"]) - 1.0) < 0.0001 and absf(float(echo_fx["fringe"])) < 0.0001, "echo fx amounts mapped", str([echo_fx["dither"], echo_fx["rgb"], echo_fx["fringe"]]))
	_check(absf(float(echo_fx.get("rgb_shift_amount", -1.0)) - 14.0) < 0.0001, "rgb shift mapped to canonical key", str(echo_fx.get("rgb_shift_amount", null)))
	_check(not echo_fx.has("rgb_shift"), "legacy rgb_shift alias not retained")
	_check(absf(float(echo_fx["intensity"]) - 1.2) < 0.0001 and absf(float(echo_fx["dither_space"]) - 1.0) < 0.0001, "intensity/dither space mapped")
	_check(absf(float(echo_fx["color_blur"]) - 1.0) < 0.0001, "color blur mapped")
	var col_a: Array = echo_fx["fringe_color_a"]
	_check(absf(float(col_a[0]) - 0.25) < 0.001 and absf(float(col_a[2]) - 1.0) < 0.001, "colour pair mapped", str(col_a))

	# ---- R3 red-team additions: Motion + Palette preservation ---------------------
	# Motion: the fixture dither track carries real values (anchor=manual, attack=0.1);
	# a migration that drops or neutralizes Motion must fail this check.
	var echo_motion: Dictionary = (echo["layers"][1] as Dictionary).get("motion", {})
	var echo_tracks: Dictionary = echo_motion.get("tracks", {})
	var dither_track: Dictionary = echo_tracks.get("dither", {})
	_check(str(dither_track.get("anchor", "")) == "manual" and absf(float(dither_track.get("attack", 0.0)) - 0.1) < 0.0001, "echo motion track preserved (anchor/attack)", str(dither_track))
	# Palette: the shipped fixture is palette-neutral, so build a palette-bearing
	# variant of the same v0.3 look in memory and migrate it through the same path.
	var palette_probe: Dictionary = fixture.duplicate(true)
	var probe_look: Dictionary = palette_probe["looks"]["BASELINE_ECHO_DITHER_RGB"]
	var probe_state: Dictionary = probe_look["state"]
	probe_state["palette_lock_a"] = true
	probe_state["palette_lock_b"] = true
	probe_state["palette_swap"] = true
	probe_state["palette_strategy"] = 1.0
	# R3: distinctive NON-DEFAULT motion values so a drop-to-neutral cannot pass.
	var probe_motion: Dictionary = probe_look["motion"]
	var probe_dither: Dictionary = probe_motion["dither"]
	probe_dither["attack"] = 0.42
	probe_dither["anchor_time"] = 1.25
	probe_dither["delay"] = 0.33
	probe_dither["anchor"] = "peak"
	var probe_result: Dictionary = migration.migrate_looks_document(palette_probe)
	_check(bool(probe_result.get("ok", false)), "palette probe migrates ok", str(probe_result.get("errors", [])))
	var probe_echo: Dictionary = probe_result.get("looks", {}).get("BASELINE_ECHO_DITHER_RGB", {})
	var probe_fx: Dictionary = {}
	if probe_echo.get("layers", []).size() >= 2:
		probe_fx = probe_echo["layers"][1]["fx"]
	_check(bool(probe_fx.get("palette_swap", false)) and bool(probe_fx.get("palette_lock_a", false)) and bool(probe_fx.get("palette_lock_b", false)) and absf(float(probe_fx.get("palette_strategy", -1.0)) - 1.0) < 0.0001, "palette locks/swap/strategy preserved through migration", str([probe_fx.get("palette_swap"), probe_fx.get("palette_lock_a"), probe_fx.get("palette_strategy")]))
	var probe_motion_out: Dictionary = {}
	if probe_echo.get("layers", []).size() >= 2:
		probe_motion_out = (probe_echo["layers"][1] as Dictionary).get("motion", {})
	var probe_track: Dictionary = (probe_motion_out.get("tracks", {}) as Dictionary).get("dither", {})
	_check(str(probe_track.get("anchor", "")) == "peak" and absf(float(probe_track.get("attack", 0.0)) - 0.42) < 0.0001 and absf(float(probe_track.get("anchor_time", 0.0)) - 1.25) < 0.0001 and absf(float(probe_track.get("delay", 0.0)) - 0.33) < 0.0001, "motion track non-default values preserved through migration (anchor/attack/anchor_time/delay)", str(probe_track))

	# ---- MARK_FRINGE: fringe mapped, flow flagged ---------------------------------
	var mark: Dictionary = looks.get("BASELINE_MARK_FRINGE", {})
	_check(str(mark["status"]) == "MIGRATION_REVIEW_REQUIRED", "mark flagged for review", str(mark["status"]))
	var mark_notes: Array = reviews.get("BASELINE_MARK_FRINGE", [])
	_check(str(mark_notes).contains("flow distortion"), "mark note explains flow", str(mark_notes))
	var mark_fx: Dictionary = mark["layers"][1]["fx"]
	_check(absf(float(mark_fx["fringe"]) - 1.0) < 0.0001 and absf(float(mark_fx["rgb"]) - 1.0) < 0.0001 and absf(float(mark_fx["dither"])) < 0.0001, "mark fx amounts mapped", str([mark_fx["fringe"], mark_fx["rgb"], mark_fx["dither"]]))
	_check(bool(mark_fx["pure_continuous"]), "pure continuous carried")
	_check(absf(float(mark_fx.get("rgb_shift_amount", -1.0)) - 18.0) < 0.0001, "mark rgb shift mapped to canonical key")
	_check(not mark_fx.has("rgb_shift") and not mark_fx.has("fx_size") and not mark_fx.has("fx_intensity"), "legacy aliases consumed, not retained")
	_check(absf(float(mark_fx["color_blur"]) - 2.0) < 0.0001, "mark colour blur mapped")

	# ---- PRIMARY_FLOW_BLUR: only the unrepresentable semantic engaged --------------
	var primary: Dictionary = looks.get("BASELINE_PRIMARY_FLOW_BLUR", {})
	_check(str(primary["status"]) == "MIGRATION_REVIEW_REQUIRED", "primary flagged for review", str(primary["status"]))
	var primary_fx: Dictionary = primary["layers"][1]["fx"]
	_check(absf(float(primary_fx["fringe"])) < 0.0001 and absf(float(primary_fx["rgb"])) < 0.0001 and absf(float(primary_fx["dither"])) < 0.0001, "primary has no representable effect (flagged, not approximated)")

	# ---- every migrated document validates + carries metadata ----------------------
	for look_id in looks.keys():
		var doc: Dictionary = looks[look_id]
		var check: Dictionary = FxLookScript.validate(doc)
		_check(bool(check["ok"]), "migrated doc validates: " + str(look_id), str(check["errors"]))
		var from: Dictionary = doc["metadata"].get("migrated_from", {})
		_check(str(from.get("look_id", "")) == str(look_id), "migrated_from metadata: " + str(look_id))
		_check(doc["metadata"].has("migration_notes"), "notes carried: " + str(look_id))

	# ---- legacy v0.3 spellings are consumed, never re-emitted -------------------
	var legacy_probe: Dictionary = fixture.duplicate(true)
	var legacy_state: Dictionary = legacy_probe["looks"]["BASELINE_ECHO_DITHER_RGB"]["state"]
	legacy_state.erase("rgb_shift_amount")
	legacy_state["rgb_shift"] = 14.0
	legacy_state.erase("intensity")
	legacy_state["fx_intensity"] = 1.2
	var legacy_result: Dictionary = migration.migrate_looks_document(legacy_probe)
	_check(bool(legacy_result.get("ok", false)), "legacy-spelling probe migrates ok", str(legacy_result.get("errors", [])))
	var legacy_echo: Dictionary = (legacy_result.get("looks", {}) as Dictionary).get("BASELINE_ECHO_DITHER_RGB", {})
	var legacy_fx: Dictionary = (legacy_echo.get("layers", []) as Array)[1]["fx"] if (legacy_echo.get("layers", []) as Array).size() >= 2 else {}
	_check(absf(float(legacy_fx.get("rgb_shift_amount", -1.0)) - 14.0) < 0.0001, "legacy rgb_shift consumed into canonical key")
	_check(absf(float(legacy_fx.get("intensity", -1.0)) - 1.2) < 0.0001, "legacy fx_intensity consumed into canonical key")
	_check(not legacy_fx.has("rgb_shift") and not legacy_fx.has("fx_intensity"), "legacy spellings not re-emitted")
	_check(bool(FxLookScript.validate_input(legacy_echo)["ok"]), "legacy-consumed doc passes validate_input")

	# ---- bad schema rejected --------------------------------------------------------
	var bad: Dictionary = migration.migrate_look("X", {"look_schema": "NOPE", "state": {}})
	_check(not bool(bad["ok"]), "bad schema rejected")

	# ---- assignments migration ------------------------------------------------------
	var v01 := {
		"schema": "NRCU_VS_FX_ASSIGNMENTS_V1",
		"bindings": [
			{"look_id": "BASELINE_ECHO_DITHER_RGB", "selector": {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}},
			{"look_id": "BASELINE_MARK_FRINGE", "selector": {"element_role": "vs_mark"}},
		],
	}
	var asg: Dictionary = migration.migrate_assignments(v01)
	_check(bool(asg["ok"]), "assignments migrate", str(asg["errors"]))
	_check(str(asg["doc"]["schema"]) == "NRCU_VS_FX_ASSIGNMENTS_V2", "v2 schema emitted")
	var migrated_binding: Dictionary = asg["doc"]["bindings"][0]
	_check(migrated_binding.has("binding_id") and bool(migrated_binding["enabled"]), "neutral v2 fields added", str(migrated_binding.keys()))
	var res: Dictionary = FxResolverScript.resolve(asg["doc"], {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"})
	_check(str(res["status"]) == "ASSIGNED" and str(res["look_id"]) == "BASELINE_ECHO_DITHER_RGB", "migrated binding resolves", str(res["status"]))

	# ---- end to end: migrated data through the shared authority ---------------------
	var prod_dir := "user://vnext_test_migration_prod"
	var draft_dir := "user://vnext_test_migration_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir

	# All migrated Looks first, then the migrated assignments (bindings must
	# reference existing Looks).
	for look_id in looks.keys():
		var doc_for_write: Dictionary = looks[look_id].duplicate(true)
		var look_applied: Dictionary = prod.apply({"look": doc_for_write})
		_check(bool(look_applied["ok"]), "migrated look apply: " + str(look_id), str(look_applied["errors"]))
	var applied: Dictionary = prod.apply({"assignments": asg["doc"]})
	_check(bool(applied["ok"]), "migrated production apply", str(applied["errors"]))
	var FxSessionScript = load("res://scripts/fx_vnext/fx_session.gd")
	var session = FxSessionScript.new(prod, drafts)
	var ctx := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "mode_family": "1v1", "stage_id": "dojo"}
	var opened: Dictionary = session.open_target("echo_left", ctx, "sig", "echo")
	_check(str(opened["opened"]) == "production" and str(session.base.get("look_id", "")) == "BASELINE_ECHO_DITHER_RGB", "session opens migrated look", str(opened))
	_check(str(session.badge_text()) == "● ASSIGNED", "migrated look resolves in session", session.badge_text())
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	var f := FileAccess.open(out_dir.path_join("unit_fx_migration.log"), FileAccess.WRITE)
	var summary := "[FX-MIGRATION] done · checks=%d failures=%d" % [checks.size(), failures]
	if f != null:
		f.store_string("\n".join(checks) + "\n" + summary + "\n")
		f.close()
	print(summary)
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
