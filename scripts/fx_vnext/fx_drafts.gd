class_name FxDrafts
extends RefCounted
# NRCU FX Lab vNext — Draft store (specs/06 §3–§4, §14; specs/10 §2).
#
# Drafts are editor work only: strictly separate from Production authority,
# crash-safe on a best-effort basis, and corrupt drafts can never damage
# Production data. Target drafts are keyed by the semantic target signature;
# shared-look drafts are keyed by look_id + base_revision (specs/06 §14).
#
# Pure data layer: no UI, no rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var base_dir: String = "user://nrcu_fx_vnext_drafts"

# ---------------------------------------------------------------- paths

func targets_dir() -> String:
	return base_dir.path_join("targets")

func shared_dir() -> String:
	return base_dir.path_join("shared")

func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(targets_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shared_dir()))

func _slug(text: String) -> String:
	var safe := ""
	for i in range(text.length()):
		var c := text[i]
		if c == "_" or c == "-" or (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			safe += c
		else:
			safe += "_"
	if safe.length() > 40:
		safe = safe.substr(0, 40)
	return "%s_%s" % [safe, text.sha256_text().substr(0, 12)]

func target_path(signature: String) -> String:
	return targets_dir().path_join(_slug(signature) + ".json")

func shared_path(look_id: String, base_revision: int) -> String:
	return shared_dir().path_join("%s_%s.json" % [_slug(look_id), str(base_revision)])

# ---------------------------------------------------------------- io

func _write_record(path: String, record: Dictionary) -> bool:
	ensure_dirs()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "  ", true))
	file.close()
	return true

func _read_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": true, "record": {}, "errors": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "missing": false, "record": {}, "errors": ["draft unreadable: " + path]}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"ok": false, "missing": false, "record": {}, "errors": ["draft corrupt: " + path]}
	var record: Dictionary = parsed
	if not (record.get("look") is Dictionary):
		return {"ok": false, "missing": false, "record": {}, "errors": ["draft has no look: " + path]}
	# Drafts may temporarily reference incomplete states (specs/09 §6), so only
	# structural sanity is enforced here — full semantic validation belongs to
	# Apply/Update, never to Draft persistence.
	return {"ok": true, "missing": false, "record": record, "errors": []}

# ---------------------------------------------------------------- target drafts

func save_target(signature: String, look: Dictionary, base_revision: int, dirty := true) -> Dictionary:
	var record := {
		"kind": "target",
		"target_signature": signature,
		"base_revision": int(base_revision),
		"look": look,
		"dirty": bool(dirty),
		"updated_unix": int(Time.get_unix_time_from_system()),
	}
	var ok := _write_record(target_path(signature), record)
	return {"ok": ok, "errors": [] if ok else ["cannot write draft for " + signature]}

func load_target(signature: String) -> Dictionary:
	return _read_record(target_path(signature))

func clear_target(signature: String) -> void:
	var path := target_path(signature)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func mark_target_clean(signature: String) -> void:
	var loaded := load_target(signature)
	if bool(loaded["ok"]):
		loaded["record"]["dirty"] = false
		_write_record(target_path(signature), loaded["record"])

func has_target(signature: String) -> bool:
	return FileAccess.file_exists(target_path(signature))

func list_target_signatures() -> Array:
	# Used on startup to restore per-target DRAFT badges (specs/10 §5).
	var out: Array = []
	var dir := DirAccess.open(ProjectSettings.globalize_path(targets_dir()))
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var loaded := _read_record(targets_dir().path_join(name))
		if bool(loaded["ok"]):
			out.append(str(loaded["record"].get("target_signature", "")))
		else:
			out.append("_corrupt_:" + name)
	out.sort()
	return out

func discard_all_targets() -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(targets_dir()))
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(targets_dir().path_join(name)))

# ---------------------------------------------------------------- shared drafts

func save_shared(look_id: String, base_revision: int, look: Dictionary, dirty := true) -> Dictionary:
	var record := {
		"kind": "shared",
		"look_id": look_id,
		"base_revision": int(base_revision),
		"look": look,
		"dirty": bool(dirty),
		"updated_unix": int(Time.get_unix_time_from_system()),
	}
	var ok := _write_record(shared_path(look_id, base_revision), record)
	return {"ok": ok, "errors": [] if ok else ["cannot write shared draft for " + look_id]}

func load_shared(look_id: String, base_revision: int) -> Dictionary:
	return _read_record(shared_path(look_id, base_revision))

func clear_shared(look_id: String, base_revision: int) -> void:
	var path := shared_path(look_id, base_revision)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func list_shared() -> Array:
	# [{look_id, base_revision}] for the Library's shared-draft indicators.
	var out: Array = []
	var dir := DirAccess.open(ProjectSettings.globalize_path(shared_dir()))
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var loaded := _read_record(shared_dir().path_join(name))
		if bool(loaded["ok"]):
			out.append({
				"look_id": str(loaded["record"].get("look_id", "")),
				"base_revision": int(loaded["record"].get("base_revision", 0)),
			})
	out.sort_custom(func(a, b): return str(a["look_id"]) < str(b["look_id"]))
	return out
