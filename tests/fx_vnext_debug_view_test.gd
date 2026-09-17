# UI-04 debug view behavioral proof (windowed, full shell): the selector
# drives real renderer output (previously a silent no-op), two modes differ
# deterministically, return to COMPOSITE restores the exact frame (no leak).
extends SceneTree

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var shell: Control
var checks: Array = []
var failures := 0
var out_dir: String

func _init() -> void:
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/authoring_ui")
	DirAccess.make_dir_recursive_absolute(out_dir)
	shell = _spawn()
	await settle(30)
	_seed()
	shell._select_key("echo_left", false)
	await settle(20)
	_check(shell._session_ready(), "UI-04 session ready on echo_left")
	var layers: Array = shell.session.look.get("layers", [])
	shell.selected_layer_id = str((layers[1] as Dictionary).get("layer_id", ""))
	shell._rebuild_inspector()
	await settle(5)
	shell.runtime.screen.lab_preview_pause()
	await _debug_modes_switch_output()
	await _selector_drives_renderer()
	print("[FX-DEBUG-VIEW] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func _wipe_dir(abs_path: String) -> void:
	if DirAccess.dir_exists_absolute(abs_path):
		for entry in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(entry))
		for sub in DirAccess.get_directories_at(abs_path):
			_wipe_dir(abs_path.path_join(sub))
			DirAccess.remove_absolute(abs_path.path_join(sub))
	else:
		DirAccess.make_dir_recursive_absolute(abs_path)

func _seed() -> void:
	_wipe_dir(ProjectSettings.globalize_path(shell.production.data_dir))
	_wipe_dir(ProjectSettings.globalize_path(shell.drafts.base_dir))
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	var look_id := "UI04_%d" % int(Time.get_unix_time_from_system())
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-04")
	var fx: Dictionary = FxLookScript.new_layer("FX", "ui04")
	(fx["fx"] as Dictionary)["fringe"] = 1.0
	(fx["fx"] as Dictionary)["edge_width"] = 10.0
	look["layers"].append(fx)
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-04 seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-04 proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-04 seed assignment applies")

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _roi_diff(a: Image, b: Image) -> float:
	var r: Rect2 = (shell.viewport_host as Control).get_global_rect()
	var w := a.get_width()
	var h := a.get_height()
	var x0 := clampi(int(r.position.x), 0, w - 1)
	var y0 := clampi(int(r.position.y), 0, h - 1)
	var x1 := clampi(int(r.end.x), x0 + 1, w)
	var y1 := clampi(int(r.end.y), y0 + 1, h)
	var sum := 0.0
	var n := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			sum += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			n += 1
	return sum / float(maxi(n, 1)) / 3.0

func _debug_modes_switch_output() -> void:
	shell.renderer.set_time(1.1)
	await settle(3)
	shell.renderer.set_debug_view("COMPOSITE")
	await settle(6)
	var img_c: Image = await _capture("ui04_composite")
	shell.renderer.set_debug_view("EDGE")
	await settle(6)
	var img_e: Image = await _capture("ui04_edge")
	_check(_roi_diff(img_c, img_e) > 0.002, "UI-04 EDGE differs from COMPOSITE deterministically", "mean=%.5f" % _roi_diff(img_c, img_e))
	shell.renderer.set_debug_view("MASK")
	await settle(6)
	var img_m: Image = await _capture("ui04_mask")
	_check(_roi_diff(img_e, img_m) > 0.002, "UI-04 MASK differs from EDGE deterministically", "mean=%.5f" % _roi_diff(img_e, img_m))
	shell.renderer.set_debug_view("COMPOSITE")
	await settle(6)
	var img_c2: Image = await _capture("ui04_composite2")
	_check(_roi_diff(img_c, img_c2) == 0.0, "UI-04 return to COMPOSITE restores exact frame (no leak)", "mean=%.5f" % _roi_diff(img_c, img_c2))

func _selector_drives_renderer() -> void:
	var opt := _find_view_option()
	_check(opt != null, "UI-04 View selector reachable")
	if opt == null:
		return
	opt.selected = 3
	opt.item_selected.emit(3)
	await settle(5)
	_check(shell.debug_view == "EDGE", "UI-04 selector sets shell state", shell.debug_view)
	_check(shell.renderer != null and shell.renderer.debug_view() == "EDGE", "UI-04 selector drives renderer state (not a no-op)")

func _find_view_option() -> OptionButton:
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == "View":
				for sub in kids:
					if sub is OptionButton:
						return sub
	return null

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
