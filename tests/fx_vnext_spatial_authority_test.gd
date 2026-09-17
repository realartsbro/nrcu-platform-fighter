extends SceneTree
# Phase 3 spatial authority regressions (headless-safe, no readback):
# SP-03 proxy-aware logical bounds; SP-04 global-fit quads under moved
# parents; SP-05 live source_rect follow; SP-06 document-order authority
# and mirrored z. SP-01/SP-02 covered by lab_vnext_neutral_parity_check
# (pixel parity, windowed); SP-07 ranking inputs verified here.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const ScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	var runtime = ScreenRuntimeScript.new()
	root.add_child(runtime.subvp)
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "SP seed: runtime mounts")
	await settle(20)
	var renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	# ---- SP-06: document order, not lexicographic --------------------------------
	var alpha_keys: Array = runtime.registry.keys()
	var ordered: Array = runtime.registry.ordered_keys()
	_check(ordered.size() == alpha_keys.size(), "SP-06 ordered keys cover all targets", str(ordered.size()))
	var mark_pos := ordered.find("mark")
	var echo_pos := ordered.find("echo_left")
	_check(mark_pos != -1 and echo_pos != -1 and echo_pos < mark_pos, "SP-06 echoes precede VsMark in document order", "echo=%d mark=%d" % [echo_pos, mark_pos])
	_check(alpha_keys != ordered, "SP-06 document order differs from lexicographic (bug was real)", str(alpha_keys.slice(0, 4)))

	# ---- SP-06: quads mirror canonical z -----------------------------------------
	var mark_node = runtime.registry.target_node("mark")
	mark_node.z_index = 7
	var look: Dictionary = _look("SPATIAL_A")
	var applied: Dictionary = renderer.apply_composition([{"key": "mark", "look": look}])
	_check(bool(applied.get("ok", false)), "SP-06 composition commits", str(applied.get("errors", [])))
	var quads: Array = renderer.stack_quads("mark")
	_check(not quads.is_empty(), "SP-06 mark stack has quads")
	var z_ok := true
	for quad_entry in quads:
		var quad = (quad_entry as Dictionary).get("node", null)
		if not (quad is Control) or (quad as Control).z_index != 7:
			z_ok = false
	_check(z_ok, "SP-06 quads mirror canonical z_index")
	mark_node.z_index = 0

	# ---- SP-04: quads stay global under a moved parent -----------------------------
	var vs_mark = runtime.screen.get_node_or_null("Root/VsMark")
	vs_mark.position = Vector2(60, 40)
	await settle(4)
	var applied2: Dictionary = renderer.apply_composition([{"key": "mark", "look": _look("SPATIAL_B")}])
	_check(bool(applied2.get("ok", false)), "SP-04 composition commits under moved parent")
	var fit_ok := true
	for quad_entry in renderer.stack_quads("mark"):
		var q = (quad_entry as Dictionary).get("node", null)
		if q is Control and str((q as Control).name).begins_with("vnext_"):
			var gp: Vector2 = (q as Control).get_global_transform() * Vector2.ZERO
			if gp.length() > 2.0:
				fit_ok = false
	_check(fit_ok, "SP-04 quads hold global origin under moved VsMark")
	vs_mark.position = Vector2.ZERO
	await settle(2)

	# ---- SP-05: live source_rect follows canonical animation -------------------------
	var echo_node = runtime.registry.target_node("echo_left")
	renderer.apply_composition([{"key": "echo_left", "look": _look("SPATIAL_C")}])
	echo_node.position += Vector2(37, -23)
	await settle(2)
	renderer._update_stack("echo_left")
	var live: Rect2 = FxTargetsScript.presentation_rect(echo_node)
	var rect_ok := false
	for quad_entry in renderer.stack_quads("echo_left"):
		var quad = (quad_entry as Dictionary).get("node", null)
		if not (quad is Control):
			continue
		var mat = (quad as Control).material
		if mat is ShaderMaterial:
			var sr = (mat as ShaderMaterial).get_shader_parameter("source_rect")
			if sr is Array and (sr as Array).size() == 4:
				if absf(float((sr as Array)[0]) - live.position.x) < 1.5 and absf(float((sr as Array)[1]) - live.position.y) < 1.5:
					rect_ok = true
	_check(rect_ok, "SP-05 quad source_rect tracks live canonical rect", str(live))

	# ---- SP-03: proxy logical bounds --------------------------------------------------
	var proxy = runtime.screen.get_node_or_null("Root/NamePlates/PlateLeft_FXProxy")
	if proxy != null:
		var logical: Rect2 = FxTargetsScript.logical_bounds(proxy)
		_check(logical.size.x < 1280.0 and logical.size.y < 720.0, "SP-03 proxy logical bounds are element-scale, not canvas", str(logical))
	else:
		_check(false, "SP-03 plate proxy exists")

	# ---- SP-07: ranking inputs ----------------------------------------------------------
	var accent = runtime.screen.get_node_or_null("Root/NamePlates/AccentLeft_FXProxy")
	var plate = runtime.screen.get_node_or_null("Root/NamePlates/PlateLeft_FXProxy")
	if accent != null and plate != null:
		var accent_area: float = FxTargetsScript.logical_bounds(accent).size.x * FxTargetsScript.logical_bounds(accent).size.y
		var plate_area: float = FxTargetsScript.logical_bounds(plate).size.x * FxTargetsScript.logical_bounds(plate).size.y
		_check(accent_area > 0.0 and accent_area < plate_area, "SP-07 accent ranks smaller than overlapping plate", "accent=%.0f plate=%.0f" % [accent_area, plate_area])
	else:
		_check(false, "SP-07 accent + plate proxies exist")

	print("[FX-SPATIAL-AUTHORITY] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _look(look_id: String) -> Dictionary:
	var doc: Dictionary = FxLookScript.new_look(look_id, look_id)
	var layer: Dictionary = FxLookScript.new_layer("FX", "Spatial")
	layer["input"] = "ORIGINAL_SOURCE"
	(layer["fx"] as Dictionary)["rgb"] = 1.0
	doc["layers"].append(layer)
	return doc

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
