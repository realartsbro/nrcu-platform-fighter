extends SceneTree
# Migration review — shell reachability (windowed).
# Queue → select → panel → ack-gate → approve → refresh, through shell methods.

const FxMigrationScript := preload("res://scripts/fx_vnext/fx_migration.gd")

var shell: Control
var checks: Array = []
var failures := 0

func _init() -> void:
	shell = _spawn()
	await settle(30)
	_seed_production()
	_check(shell.has_method("migration_review_ids"), "shell exposes review queue")
	var queue: Array = shell.migration_review_ids()
	_check(queue.has("BASELINE_MARK_FRINGE"), "queue reaches shell", str(queue))
	_check(shell.has_method("migration_review_select"), "shell exposes review select")
	var selected: Dictionary = shell.migration_review_select("BASELINE_MARK_FRINGE")
	_check(bool(selected.get("ok", false)), "shell selects review", str(selected.get("errors", [])))
	_check(not (selected.get("notes", []) as Array).is_empty(), "shell shows notes", str(selected.get("notes", [])))
	_check(shell.review_look_id == "BASELINE_MARK_FRINGE", "shell tracks selection")
	_check(shell.review_panel != null and is_instance_valid(shell.review_panel), "review panel is open")
	_check(shell.review_ack_field != null and is_instance_valid(shell.review_ack_field), "ack field is reachable")
	var clean: Dictionary = shell.migration_review_select("BASELINE_ECHO_DITHER_RGB")
	_check(not bool(clean.get("ok", false)), "clean look not selectable for review")
	_check(shell.has_method("migration_review_approve"), "shell exposes review approve")
	var denied: Dictionary = shell.migration_review_approve("")
	_check(not bool(denied.get("ok", false)), "shell enforces ack gate")
	_check(shell.migration_review_ids().has("BASELINE_MARK_FRINGE"), "still queued after denied shell approval")
	var approved: Dictionary = shell.migration_review_approve("verified in shell: flow note + masks")
	_check(bool(approved.get("ok", false)), "shell approval persists", str(approved.get("errors", [])))
	_check(not shell.migration_review_ids().has("BASELINE_MARK_FRINGE"), "queue updated after shell approval")
	_check(shell.review_panel == null, "panel closed after approval")
	print("[FX-MIGRATION-UI] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _seed_production() -> void:
	var fixture := _load_json("res://tests/fixtures/vnext/fixture_fx_looks_v03.json")
	var migration = FxMigrationScript.new()
	var result: Dictionary = migration.migrate_looks_document(fixture)
	for look_id in (result.get("looks", {}) as Dictionary).keys():
		shell.production.apply({"look": (result["looks"] as Dictionary)[look_id]})
	shell._refresh_library()

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func settle(n: int) -> void:
	for i in n:
		await process_frame

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
