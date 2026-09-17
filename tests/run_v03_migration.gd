extends SceneTree
# Headless v0.3 → vNext migration runner (specs/08). Reads a v0.3 looks
# document (and optionally a v1 assignments document) and writes migrated v0.4
# Looks + v2 assignments into the Production data dir through the shared
# transactional store. The v0.3 source files are never modified.
#
# Usage:
#   MIGRATION_SOURCE=<v0.3 looks json> \
#   [MIGRATION_ASSIGNMENTS=<v1 assignments json>] \
#   [NRCU_FX_DATA_DIR=res://nrcu_fx_data] \
#   godot --headless --path project --script res://tests/run_v03_migration.gd

func _init() -> void:
	var FxProductionScript = load("res://scripts/fx_vnext/fx_production.gd")
	var FxMigrationScript = load("res://scripts/fx_vnext/fx_migration.gd")

	var source_path := OS.get_environment("MIGRATION_SOURCE")
	if source_path == "":
		print("[MIGRATE] MIGRATION_SOURCE is required")
		quit(2)
		return
	var doc := _load_json(source_path)
	if doc.is_empty():
		print("[MIGRATE] cannot read source: ", source_path)
		quit(2)
		return

	var migration = FxMigrationScript.new()
	var migrated: Dictionary = migration.migrate_looks_document(doc)
	if not bool(migrated["ok"]):
		print("[MIGRATE] migration failed: ", migrated["errors"])
		quit(1)
		return

	var production = FxProductionScript.new()
	var data_override := OS.get_environment("NRCU_FX_DATA_DIR")
	if data_override != "":
		production.data_dir = data_override
	production.ensure_dirs()

	var written := 0
	var failed: Array = []
	for look_id in (migrated["looks"] as Dictionary).keys():
		var look: Dictionary = migrated["looks"][look_id]
		var result: Dictionary = production.apply({"look": look})
		if bool(result["ok"]):
			written += 1
			print("[MIGRATE] wrote ", look_id, " status=", str(look.get("status", "")))
		else:
			failed.append("%s: %s" % [str(look_id), str(result.get("errors", []))])

	var assignments_path := OS.get_environment("MIGRATION_ASSIGNMENTS")
	if assignments_path != "":
		var assignments_doc := _load_json(assignments_path)
		if assignments_doc.is_empty():
			failed.append("cannot read assignments: " + assignments_path)
		else:
			var asg: Dictionary = migration.migrate_assignments(assignments_doc)
			if not bool(asg["ok"]):
				failed.append("assignments: " + str(asg["errors"]))
			else:
				var result: Dictionary = production.apply({"assignments": asg["doc"]})
				if not bool(result["ok"]):
					failed.append("assignments apply: " + str(result.get("errors", [])))
				else:
					print("[MIGRATE] assignments written (", (asg["doc"]["bindings"] as Array).size(), " bindings)")

	var reviews: Dictionary = migrated["reviews"]
	for look_id in reviews.keys():
		print("[MIGRATE][REVIEW] ", look_id, ": ", str(reviews[look_id]))
	print("[MIGRATE] done · looks=%d written=%d failed=%d" % [(migrated["looks"] as Dictionary).size(), written, failed.size()])
	for line in failed:
		print("[MIGRATE][FAIL] ", line)
	quit(0 if failed.is_empty() else 1)

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
