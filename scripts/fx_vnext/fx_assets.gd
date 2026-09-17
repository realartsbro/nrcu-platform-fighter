extends RefCounted
# FxAssets (Round-2 Finding 15): external masks/textures used by a Look are
# IMPORTED into project-local production assets at apply time; the persisted
# Look only ever references the project-relative copy. A missing asset yields a
# clear invalid/diagnostic state instead of a broken reference.

static func is_external(ref: String) -> bool:
	var text := ref.strip_edges()
	if text == "":
		return false
	if text.begins_with("res://") or text.begins_with("user://"):
		return false
	return true

static func assets_dir(data_dir: String) -> String:
	return data_dir.path_join("assets")

static func import_external(ref: String, data_dir: String) -> Dictionary:
	# Copies the file with a content-hash prefix and returns the project ref.
	if not FileAccess.file_exists(ref):
		return {"ok": false, "errors": ["external asset not found: " + ref]}
	var bytes := FileAccess.get_file_as_bytes(ref)
	if bytes.is_empty():
		return {"ok": false, "errors": ["external asset unreadable: " + ref]}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var digest := ctx.finish().hex_encode().substr(0, 12)
	var base := ref.get_file()
	var safe := ""
	for i in range(base.length()):
		var ch := base[i]
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in [".", "_", "-"]:
			safe += ch
	if safe == "":
		safe = "asset.png"
	var rel := assets_dir(data_dir).path_join(digest + "_" + safe)
	var abs_target := ProjectSettings.globalize_path(rel)
	DirAccess.make_dir_recursive_absolute(abs_target.get_base_dir())
	if not FileAccess.file_exists(rel):
		var out := FileAccess.open(abs_target, FileAccess.WRITE)
		if out == null:
			return {"ok": false, "errors": ["cannot write project asset: " + rel]}
		out.store_buffer(bytes)
		out.close()
	if not FileAccess.file_exists(rel):
		return {"ok": false, "errors": ["project asset missing after import: " + rel]}
	return {"ok": true, "ref": rel, "bytes": bytes.size()}

static func ensure_project_ref(ref: String, data_dir: String) -> Dictionary:
	# Verifies a project-local ref (and reports a clear diagnostic if missing).
	var text := ref.strip_edges()
	if text == "":
		return {"ok": false, "errors": ["empty asset reference"]}
	if is_external(text):
		return import_external(text, data_dir)
	if FileAccess.file_exists(text) or ResourceLoader.exists(text):
		return {"ok": true, "ref": text}
	return {"ok": false, "missing": true, "errors": ["asset does not exist: " + text]}
