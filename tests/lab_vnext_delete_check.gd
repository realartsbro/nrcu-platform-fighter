extends SceneTree
# Round-2 Finding 14 (shell level): the used-Look delete chooser offers exactly
# Replace With… / Unassign affected targets / Cancel, and all three paths work
# through the real shell. Windowed: needs rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String
var shell: Control

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/delete_ui")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data_dir := OS.get_environment("NRCU_FX_DATA_DIR")
	var draft_dir := OS.get_environment("NRCU_FX_DRAFT_DIR")
	_wipe_dir(ProjectSettings.globalize_path(data_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	# ---- production with two looks, A used twice ---------------------------------
	var prod := FxProductionScript.new()
	prod.data_dir = data_dir
	_check(bool(prod.apply({"look": _make_look("LOOK_A", "A")})["ok"]), "look A written")
	_check(bool(prod.apply({"look": _make_look("LOOK_B", "B")})["ok"]), "look B written")
	var doc: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(doc, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "LOOK_A", "")
	FxResolverScript.upsert_binding(doc, {"element_role": "vs_mark"}, "LOOK_A", "")
	_check(bool(prod.apply({"assignments": doc})["ok"]), "bindings written")

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	shell = scene.instantiate()
	root.add_child(shell)
	await settle(20)
	shell._refresh_library()
	await settle(4)

	# ---- chooser opens for a used look ------------------------------------------
	shell._action_delete_look("LOOK_A")
	await settle(4)
	_check(shell.delete_panel != null and is_instance_valid(shell.delete_panel), "chooser opens for a used Look")
	var texts := _collect_texts(shell.delete_panel)
	var joined := " | ".join(texts)
	_check(joined.contains("used by 2"), "chooser reports the usage count", joined.substr(0, 120))
	_check(texts.has("Unassign affected targets"), "chooser offers unassign", joined)
	_check(texts.has("Cancel"), "chooser offers cancel")
	_check(texts.has("Replace With…"), "chooser offers replace")
	_check(texts.has("LOOK_B"), "chooser lists replace candidates")
	await capture("delete_chooser_open")

	# ---- path 1: cancel ----------------------------------------------------------
	var cancel_button := _find_button(shell.delete_panel, "Cancel")
	_check(cancel_button != null, "cancel button found")
	if cancel_button != null:
		cancel_button.emit_signal("pressed")
	await settle(4)
	_check(shell.delete_panel == null, "cancel closes the chooser")
	_check(shell.production.list_look_ids().has("LOOK_A"), "cancel keeps the Look")
	_check(int(shell.production.usage("LOOK_A")["count"]) == 2, "cancel keeps the bindings")

	# ---- path 2: replace ---------------------------------------------------------
	shell._action_delete_look("LOOK_A")
	await settle(4)
	var replace_button := _find_button(shell.delete_panel, "LOOK_B")
	_check(replace_button != null, "replace candidate button found")
	if replace_button != null:
		replace_button.emit_signal("pressed")
	await settle(6)
	_check(shell.delete_panel == null, "replace closes the chooser")
	_check(not shell.production.list_look_ids().has("LOOK_A"), "replace removed the Look", str(shell.production.list_look_ids()))
	var res: Dictionary = FxResolverScript.resolve(shell.production.load_assignments()["doc"], {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"})
	_check(str(res.get("look_id", "")) == "LOOK_B", "binding rebound to the replacement", str(res.get("look_id", "")))
	_check(shell.action_status.text.begins_with("✓"), "replace reports success", shell.action_status.text)
	await capture("delete_after_replace")

	# ---- path 3: unassign --------------------------------------------------------
	_check(bool(prod.apply({"look": _make_look("LOOK_C", "C")})["ok"]), "look C written")
	var doc2: Dictionary = shell.production.load_assignments()["doc"]
	FxResolverScript.upsert_binding(doc2, {"element_role": "vs_mark"}, "LOOK_C", "")
	_check(bool(prod.apply({"assignments": doc2})["ok"]), "binding to C written")
	shell._refresh_library()
	shell._action_delete_look("LOOK_C")
	await settle(4)
	_check(shell.delete_panel != null, "chooser opens for C")
	var unassign_button := _find_button(shell.delete_panel, "Unassign affected targets")
	_check(unassign_button != null, "unassign button found")
	if unassign_button != null:
		unassign_button.emit_signal("pressed")
	await settle(6)
	_check(not shell.production.list_look_ids().has("LOOK_C"), "unassign removed the Look", str(shell.production.list_look_ids()))
	var res2: Dictionary = FxResolverScript.resolve(shell.production.load_assignments()["doc"], {"element_role": "vs_mark"})
	_check(str(res2.get("status", "")) != "ASSIGNED", "no fallback reference remains", str(res2))
	_check(bool(FxResolverScript.validate_assignments(shell.production.load_assignments()["doc"])["ok"]), "assignments remain valid")
	await capture("delete_after_unassign")

	var f := FileAccess.open(out_dir.path_join("summary_delete_ui_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[DELETE-UI] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _make_look(look_id: String, name: String) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, name)
	var fx: Dictionary = FxLookScript.new_layer("FX", name + " fx")
	fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 8.0}
	look["layers"].append(fx)
	return look

func _collect_texts(node: Node) -> Array:
	var out: Array = []
	if node is Label or node is Button:
		out.append(str(node.text))
	for child in node.get_children():
		out.append_array(_collect_texts(child))
	return out

func _find_button(node: Node, text: String) -> Button:
	if node is Button and str(node.text) == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

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

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
