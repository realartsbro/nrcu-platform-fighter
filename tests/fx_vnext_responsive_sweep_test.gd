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
	# Canonical domain keys are lowercase (neutral_motion).
	shell.session.edit(func(doc):
		var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
		var l: Dictionary = FxLookScript.find_layer(doc, fx_id)
		((l["motion"] as Dictionary)["enabled"] as Dictionary)["fringe"] = true
	)
	shell._rebuild_inspector()
	await settle(10)
	shell.runtime.screen.lab_preview_pause()
	for size in [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = size
		await settle(25)
		_assert_whole_window(size)
		for tab in ["LOOK", "MOTION", "PALETTE", "ADVANCED"]:
			_select_tab(tab)
			await settle(15)
			await _assert_tab(tab, size)
			await _shot(tab, size)
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

# P0 UI shell: the whole lab must live inside the real window client rect
# (a stale 1600x900 counter-scale once zoomed everything to 125% at
# 1280x720 while inspector-relative checks stayed green — whole-window
# reachability needs final/global transforms, never local rects alone).
func _assert_whole_window(size: Vector2i) -> void:
	var tag := "SHELL@%dx%d" % [size.x, size.y]
	var win := Rect2(Vector2.ZERO, Vector2(root.size))
	_check(Rect2(shell.get_global_rect()).intersects(win), "UI-Resp %s shell presented" % tag)
	# Net visual scale must be ~1.0 (native pixels): engine stretch times
	# the shell counter-scale. Never assert the counter alone (it is 1/1.5
	# at a 1920 window with a 1280 base — exactly correct).
	var engine := root.get_final_transform().get_scale()
	var sc: Vector2 = (shell as Control).scale
	var net := Vector2(sc.x * engine.x, sc.y * engine.y)
	_check(absf(net.x - 1.0) < 0.03 and absf(net.y - 1.0) < 0.03, "UI-Resp %s net scale is native (%s)" % [tag, str(net)])
	# Geometry below compares PHYSICAL pixels: canvas rects times the
	# engine scale (comparing canvas units to window units directly once
	# faked 34px of toolbar overflow and hid real click heights).
	var tol := 2.0
	var regions := {
		"shell": _px(shell.get_global_rect()),
		"toolbar": _px(shell.toolbar.get_global_rect()),
		"preview": _px(shell.viewport_host.get_global_rect()),
		"dock": _px(shell.dock.get_global_rect()),
		"timeline": _px(shell.timeline_panel.get_global_rect()),
	}
	if (shell.browser_panel as Control).is_visible_in_tree():
		regions["browser"] = _px((shell.browser_panel as Control).get_global_rect())
	elif (shell.browser_rail as Control).is_visible_in_tree():
		regions["browser-rail"] = _px((shell.browser_rail as Control).get_global_rect())
	for key in regions.keys():
		var r: Rect2 = regions[key]
		var inside := r.position.x >= win.position.x - tol and r.position.y >= win.position.y - tol and r.end.x <= win.end.x + tol and r.end.y <= win.end.y + tol
		_check(inside, "UI-Resp %s %s inside window" % [tag, str(key)], str(r))

func _px(r: Rect2) -> Rect2:
	# Canvas units -> physical window pixels via the real stretch transform.
	# (SceneTree root: no get_tree() here.)
	var e: Vector2 = root.get_final_transform().get_scale()
	return Rect2(r.position * e, r.size * e)

func _assert_tab(tab_name: String, size: Vector2i) -> void:
	var tag := "%s@%dx%d" % [tab_name, size.x, size.y]
	_check(root.size == size, "UI-Resp %s window size applied" % tag, str(root.size))
	var page := _active_page(tab_name)
	_check(page != null, "UI-Resp %s page found" % tag)
	if page == null:
		return
	# Geometry authority: the inspector ScrollContainer's visible rect, NOT
	# the whole window (a 600px control can overflow a 390px dock while the
	# window is 1280px wide — the old assertion was a false green).
	var view := _px(_inspector_view_rect())
	_check(view.size.x > 50.0, "UI-Resp %s inspector viewport found" % tag, str(view))
	var bad_w := 0
	var bad_h := 0
	var n := 0
	for child in _walk(page):
		if child is Button or child is OptionButton or child is SpinBox or child is CheckBox or child is HSlider or child is ColorPickerButton or child is LineEdit:
			if not (child as Control).is_visible_in_tree():
				continue
			n += 1
			var r: Rect2 = _px((child as Control).get_global_rect())
			# Left AND right clip edges against the visible viewport.
			if r.position.x < view.position.x - 1.0 or r.end.x > view.end.x + 1.0:
				bad_w += 1
			# Horizontal scroll is disabled by design: anything wider than
			# the viewport can never be reached.
			if r.size.x > view.size.x + 1.0:
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
			if (r.size.y < need_h or r.size.x > view.size.x + 1.0 or r.size.x < 20.0) and n < 60:
				print("OFFENDER %s %s h=%.1f w=%.1f x=%.1f parent=%s" % [tag, (child as Control).get_class(), r.size.y, r.size.x, r.position.x, (child as Control).get_parent().get_class()])
	_check(n > 5, "UI-Resp %s has interactive controls" % tag, str(n))
	_check(bad_w == 0, "UI-Resp %s inside inspector viewport (left+right)" % tag, "bad=%d/%d" % [bad_w, n])
	_check(bad_h == 0, "UI-Resp %s sane click heights" % tag, "bad=%d/%d" % [bad_h, n])
	_check(_no_sibling_overlap(page), "UI-Resp %s no label/control overlap" % tag)
	var scroll_ok := await _scroll_reaches_ends(page)
	_check(scroll_ok, "UI-Resp %s scroll reaches first+last control" % tag)

func _inspector_view_rect() -> Rect2:
	var node: Node = shell.inspector_content
	while node != null:
		node = node.get_parent()
		if node is ScrollContainer:
			return (node as Control).get_global_rect()
	return Rect2()

func _no_sibling_overlap(page: Control) -> bool:
	for child in _walk(page):
		if child is HBoxContainer or child is VBoxContainer:
			var rects: Array = []
			for sub in (child as BoxContainer).get_children():
				if sub is Control and (sub as Control).is_visible_in_tree():
					rects.append(_px((sub as Control).get_global_rect()))
			for i in range(rects.size()):
				for j in range(i + 1, rects.size()):
					var a: Rect2 = rects[i]
					var b: Rect2 = rects[j]
					# Touching edges are fine; positive-area overlap is not.
					var inter: Rect2 = a.intersection(b)
					if inter.size.x > 1.0 and inter.size.y > 1.0:
						print("OVERLAP %s vs %s" % [str(a), str(b)])
						return false
	return true

func _scroll_reaches_ends(page: Control) -> bool:
	var node: Node = shell.inspector_content
	var scroll: ScrollContainer = null
	while node != null:
		node = node.get_parent()
		if node is ScrollContainer:
			scroll = node
			break
	if scroll == null:
		return false
	var bar := scroll.get_v_scroll_bar()
	# The ScrollContainer owns scrolling (scroll_vertical); its scrollbar is
	# a slave that clamps direct writes — drive the container itself.
	var probe = _first_control(shell.inspector_content)
	var r0: Rect2 = (probe as Control).get_global_rect() if probe != null else Rect2()
	scroll.scroll_vertical = int(bar.max_value)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var r1: Rect2 = (probe as Control).get_global_rect() if probe != null else Rect2()
	var view: Rect2 = _px(scroll.get_global_rect())
	# The LAST control of the active page must be bringable into view.
	var last = _last_control(page)
	var last_ok := false
	var detail := "no-last"
	if last != null:
		# User-facing capability: the container can bring any control FULLY
		# into view (a footer below the tabs makes raw max-scroll overshoot
		# the page end, so max-scroll alone proves nothing either way).
		# A merely intersecting sliver is NOT reachable: require full
		# containment inside the clip rect.
		scroll.ensure_control_visible(last as Control)
		await process_frame
		await process_frame
		await process_frame
		await process_frame
		var lr: Rect2 = _px((last as Control).get_global_rect())
		detail = str(lr)
		last_ok = lr.position.y >= view.position.y - tol() and lr.end.y <= view.end.y + tol()
	if not last_ok:
		print("SCROLLMISS view=%s last=%s page=%s" % [str(view), detail, str(page.get_path())])
		return false
	# And back to top: the FIRST control must be fully visible too.
	var first = _first_control(page)
	if first == null:
		return false
	scroll.ensure_control_visible(first as Control)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var fr: Rect2 = _px((first as Control).get_global_rect())
	var first_ok := fr.position.y >= view.position.y - tol() and fr.end.y <= view.end.y + tol()
	if not first_ok:
		print("SCROLLMISS-TOP view=%s first=%s page=%s" % [str(view), str(fr), str(page.get_path())])
	bar.value = bar.min_value
	scroll.scroll_vertical = 0
	await process_frame
	await process_frame
	return first_ok

func tol() -> float:
	return 2.0

func _first_control(node: Node):
	for child in _walk(node):
		if child is Control and not (child is Label) and not (child is Container) and (child as Control).is_visible_in_tree():
			return child
	return null

func _last_control(node: Node):
	# Visual bottom, not walk order: internal sub-controls (spinbox line
	# edits, option internals) come last in tree order but sit mid-page.
	var found = null
	var best := -1.0
	for child in _walk(node):
		if child is Control and not (child is Label) and not (child is Container) and (child as Control).is_visible_in_tree():
			var end_y := (child as Control).get_global_rect().end.y
			if end_y > best:
				best = end_y
				found = child
	return found

func _shot(tab_name: String, size: Vector2i) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s_%dx%d.png" % [out_dir, tab_name, size.x, size.y])
