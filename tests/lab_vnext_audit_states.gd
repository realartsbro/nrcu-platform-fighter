extends SceneTree
# vNext audit states — builds, applies and serializes the three required example
# states through the real app shell, dumps the AS-WRITTEN production files and
# labeled screenshots. Windowed: needs rendering.

var out_dir: String
var shell: Control

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/states")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("production_files"))

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	shell = scene.instantiate()
	root.add_child(shell)
	await settle(30)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var FxTemplatesScript = load("res://scripts/fx_vnext/fx_templates.gd")

	# ============ state 1: VS Mark with Source + Underlay/Halo + Overlay ==========
	shell._select_key("mark", false)
	await settle(8)
	shell._action_add_layer("Outer Halo")
	await settle(6)
	var layers: Array = shell.session.look["layers"]
	(layers[1] as Dictionary)["name"] = "Underlay Halo"
	shell._drop_layer_on_plane(str((layers[1] as Dictionary)["layer_id"]), "TARGET_UNDERLAY")
	await settle(4)
	shell._action_add_layer("RGB Tear")
	await settle(6)
	layers = shell.session.look["layers"]
	(layers[2] as Dictionary)["name"] = "Overlay Tear"
	(layers[2] as Dictionary)["plane"] = "TARGET_OVERLAY"
	shell.session.edit(func(doc): pass)
	await settle(4)
	shell._action_apply("AUDIT_VS_MARK_LAYERED")
	await settle(10)
	await still("state1_vs_mark_layered")

	# ============ state 2: Ice Mage Echo with Source Copy + Displacement ==========
	shell._select_key("echo_left", false)
	await settle(8)
	shell._action_add_layer("Source Copy")
	await settle(6)
	var layers2: Array = shell.session.look["layers"]
	var copy_id := str((layers2[1] as Dictionary)["layer_id"])
	var look_script = FxLookScript
	shell._edit_layer(copy_id, func(doc):
		var l: Dictionary = look_script.find_layer(doc, copy_id)
		(l["transform"] as Dictionary)["position_px"] = [-46.0, 0.0]
		var d: Dictionary = l["displacement"]
		d["enabled"] = true
		d["driver"] = "DIRECTIONAL"
		d["amount_px"] = [34.0, 12.0]
		d["speed"] = 1.0
		d["scale"] = 2.5
	)
	await settle(8)
	# custom mask demo (project-local asset, specs/09 loadability)
	shell._action_add_layer("Edge Treatment")
	await settle(6)
	layers2 = shell.session.look["layers"]
	var mask_demo_id := str((layers2[2] as Dictionary)["layer_id"])
	shell._edit_layer(mask_demo_id, func(doc):
		var m: Dictionary = look_script.find_layer(doc, mask_demo_id)["mask"]
		m["enabled"] = true
		m["source"] = "CUSTOM_MASK"
		m["custom_mask"] = "res://assets/vs/generated/accent_left_mask.png"
		m["region"] = "FULL"
	)
	await settle(8)
	await still("state2_echo_copy_displaced_custom_mask")
	shell._action_apply("AUDIT_ECHO_DISPLACED_COPY")
	await settle(10)

	# ============ shared look + specific override =================================
	# shared: bound to fighter+role (no side); override: fighter+role+side wins for left
	var shared_look: Dictionary = FxLookScript.new_look("AUDIT_ECHO_SHARED", "Echo Shared Base")
	var shared_fx: Dictionary = FxLookScript.new_layer("FX", "Shared Fringe")
	shared_fx["fx"] = {"fringe": 1.0, "intensity": 1.2, "edge_width": 10.0, "wind_reach": 36.0, "wind_trail": 0.6}
	shared_look["layers"].append(shared_fx)
	var shared_applied: Dictionary = shell.production.apply({"look": shared_look})
	var assignments: Dictionary = shell.production.load_assignments()["doc"]
	# re-point the echo-left binding to the override look, add the shared generic binding
	FxResolverScript.upsert_binding(assignments, {"fighter_id": "ice_mage", "element_role": "echo"}, "AUDIT_ECHO_SHARED", "audit shared scope")
	FxResolverScript.upsert_binding(assignments, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "AUDIT_ECHO_DISPLACED_COPY", "audit specific override")
	var asg_applied: Dictionary = shell.production.apply({"assignments": assignments})
	print("[STATES] shared=", shared_applied.get("ok", false), " assignments=", asg_applied.get("ok", false), " ", asg_applied.get("errors", []))
	shell.drafts.clear_target(str(shell.session.signature))
	shell._select_key("echo_left", false)
	await settle(10)
	shell._action_why()
	await settle(6)
	await still("state3_shared_plus_specific_override_why")

	# ============ geometry rects (presentation-space parity basis) ================
	var FxTargetsScript = load("res://scripts/fx_vnext/fx_targets.gd")
	var rects := {}
	for key in ["mark", "primary_left", "echo_left", "name_left"]:
		var node = shell.runtime.registry.slot_nodes.get(key)
		if node != null:
			var rect: Rect2 = FxTargetsScript.presentation_rect(node)
			rects[key] = {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y]}
	var rect_file := FileAccess.open(out_dir.path_join("geometry_rects.json"), FileAccess.WRITE)
	if rect_file != null:
		rect_file.store_string(JSON.stringify(rects, "  "))
		rect_file.close()
	print("[STATES] geometry rects: ", rects)

	# ============ dump the AS-WRITTEN production files ============================
	var prod_dir := ProjectSettings.globalize_path(shell.production.data_dir)
	_copy_tree(prod_dir, out_dir.path_join("production_files"))
	# example states as standalone JSON documents (from disk)
	var state_index := {}
	for look_id in shell.production.list_look_ids():
		var loaded: Dictionary = shell.production.load_look(look_id)
		if bool(loaded.get("ok", false)):
			var f := FileAccess.open(out_dir.path_join("state_%s.json" % str(look_id).to_lower()), FileAccess.WRITE)
			if f != null:
				f.store_string(FxLookScript.to_json(loaded["doc"]))
				f.close()
			state_index[str(look_id)] = {"revision": int((loaded["doc"] as Dictionary).get("revision", 0)), "status": str((loaded["doc"] as Dictionary).get("status", ""))}
	var idx_file := FileAccess.open(out_dir.path_join("states_index.json"), FileAccess.WRITE)
	if idx_file != null:
		idx_file.store_string(JSON.stringify(state_index, "  "))
		idx_file.close()
	print("[STATES] done · looks=", state_index.keys())
	quit(0)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))

func _copy_tree(from: String, to: String) -> void:
	var dir := DirAccess.open(from)
	if dir == null:
		return
	for file_name in dir.get_files():
		var src := from.path_join(file_name)
		var dst := to.path_join(file_name)
		var f := FileAccess.open(src, FileAccess.READ)
		if f == null:
			continue
		var bytes := f.get_buffer(f.get_length())
		f.close()
		var out := FileAccess.open(dst, FileAccess.WRITE)
		if out != null:
			out.store_buffer(bytes)
			out.close()
	for sub in dir.get_directories():
		DirAccess.make_dir_recursive_absolute(to.path_join(sub))
		_copy_tree(from.path_join(sub), to.path_join(sub))
