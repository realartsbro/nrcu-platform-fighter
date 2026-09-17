# UI-03 §2 responsive acceptance (windowed): LOOK / MOTION / PALETTE /
# ADVANCED show no horizontal overflow, no clipped controls and sane click
# heights at 1280x720, 1440x900, 1600x900 and 1920x1080. Vertical overflow is
# fine (the inspector scrolls); horizontal scroll is disabled by design, so
# any control wider than the window is a defect. Screenshots are evidence.
extends SceneTree

var shell: Control
var checks: Array = []
var failures := 0
var out_dir: String

func _init() -> void:
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/responsive_sweep")
	DirAccess.make_dir_recursive_absolute(out_dir)
	shell = _spawn()
	await settle(30)
	_seed()
	shell._select_key("echo_left", false)
	await settle(20)
	var layers: Array = shell.session.look.get("layers", [])
	var fx_id := str((layers[1] as Dictionary).get("layer_id", ""))
	shell.selected_layer_id = fx_id
	# Setup (not asserted): arm one motion domain so MOTION shows live rows.
	shell.session.edit(func(doc):
		var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
		var l: Dictionary = FxLookScript.find_layer(doc, fx_id)
		((l["motion"] as Dictionary)["enabled"] as Dictionary)["FRINGE"] = true
	)
	shell._rebuild_inspector()
	await settle(10)
	shell.runtime.screen.lab_preview_pause()
	for size in [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = size
		await settle(25)
		for tab in ["LOOK", "MOTION", "PALETTE", "ADVANCED"]:
			_select_tab(tab)
			await settle(15)
			_assert_tab(tab, size)
			_shot(tab, size)
	print("[FX-RESPONSIVE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _notification(what: int) -> void:
	# Windowed-runner hygiene: a fatal error inside _init (e.g. a bad API
	# call) must never leave a ghost window behind — always exit.
	if what == NOTIFICATION_CRASH:
		quit(1)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
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

func _seed() -> void:
	var look_id := "UIRESP_%d" % int(Time.get_unix_time_from_system())
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var look: Dictionary = FxLookScript.new_look(look_id, "UI-Resp")
	var fx: Dictionary = FxLookScript.new_layer("FX", "uiresp")
	look["layers"].append(fx)
	look = FxLookScript.materialize(look)
	_check(bool(shell.production.apply({"look": look})["ok"]), "UI-Resp seed look applies")
	var asg: Dictionary = shell.production.load_assignments()["doc"]
	var ctx: Dictionary = shell.runtime.registry.context_for_key("echo_left")
	FxResolverScript.upsert_binding(asg, {"fighter_id": str(ctx.get("fighter_id", "ice_mage")), "element_role": "echo"}, look_id, "ui-resp proof binding")
	_check(bool(shell.production.apply({"assignments": asg})["ok"]), "UI-Resp seed assignment applies")

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _select_tab(tab_name: String) -> void:
	for child in _walk(shell.inspector_content):
		if child is TabContainer:
			for i in (child as TabContainer).get_tab_count():
				if (child as TabContainer).get_tab_title(i) == tab_name:
					(child as TabContainer).current_tab = i
					return

func _active_page(tab_name: String) -> Control:
	for child in _walk(shell.inspector_content):
		if child is VBoxContainer and (child as VBoxContainer).name == tab_name:
			return child
	return null

func _assert_tab(tab_name: String, size: Vector2i) -> void:
	var tag := "%s@%dx%d" % [tab_name, size.x, size.y]
	var page := _active_page(tab_name)
	_check(page != null, "UI-Resp %s page found" % tag)
	if page == null:
		return
	var bad_w := 0
	var bad_h := 0
	var bad_x := 0
	var n := 0
	for child in _walk(page):
		if child is Button or child is OptionButton or child is SpinBox or child is CheckBox or child is HSlider or child is ColorPickerButton or child is LineEdit:
			if not (child as Control).is_visible_in_tree():
				continue
			n += 1
			var r: Rect2 = (child as Control).get_global_rect()
			if r.size.x > float(size.x) + 1.0:
				bad_w += 1
			# Horizontal sliders are thin tracks by design (grab area spans
			# the full row width); other controls need full click height.
			var need_h := 10.0 if (child is HSlider) else 16.0
			if r.size.y < need_h:
				bad_h += 1
			# Crushed controls (zero-width expand victims) are as unusable
			# as overflowing ones — this caught the side-by-side A/B pickers.
			if r.size.x < 20.0:
				bad_w += 1
			if r.position.x < -1.0:
				bad_x += 1
			if (r.size.y < need_h or r.size.x > float(size.x) + 1.0 or r.position.x < -1.0) and n < 60:
				print("OFFENDER %s %s h=%.1f w=%.1f x=%.1f parent=%s" % [tag, (child as Control).get_class(), r.size.y, r.size.x, r.position.x, (child as Control).get_parent().get_class()])
	_check(n > 5, "UI-Resp %s has interactive controls" % tag, str(n))
	_check(bad_w == 0, "UI-Resp %s no horizontal overflow" % tag, "bad=%d/%d" % [bad_w, n])
	_check(bad_h == 0, "UI-Resp %s sane click heights" % tag, "bad=%d/%d" % [bad_h, n])
	_check(bad_x == 0, "UI-Resp %s nothing clipped left" % tag, "bad=%d/%d" % [bad_x, n])

func _shot(tab_name: String, size: Vector2i) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s_%dx%d.png" % [out_dir, tab_name, size.x, size.y])
