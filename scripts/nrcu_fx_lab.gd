extends Node2D
# ============================================================================
# NRCU FX Overlay Lab v3
#
# The preview IS the real screen: this lab mounts the actual vs_screen.tscn
# (copied verbatim from the VS lane; the VSMP copy is the multiplayer-capable
# superset) and puts the FX layer materials onto its element nodes.
#   - matchup: 1v1 duel + the multiplayer families (FFA_3/FFA_4/TEAM_*)
#   - element selector: pick any node of the live composition for FX
#   - FX layers: dither / fringe / flow / rgb-shift, amounts, motion anchors
#   - full-width timeline: phase bars, events, hold marker, live playhead
#   - collapsible side panel
# ============================================================================

const PRESET_PATH := "user://nrcu_fx_presets.cfg"
const VSRequest := preload("res://scripts/vs_presentation_request.gd")

var shader: Shader
var screen: Node = null
var materials := {}
var slot_nodes := {}
var selected_slot := "mark"

var state := {
	"fx_on": {"dither": false, "fringe": true, "flow": true, "rgb": false},
	"fx_amount": {"dither": 0.85, "fringe": 1.0, "flow": 1.0, "rgb": 1.0},
	"base_mode": 0.0,
	"dither_mode": 1.0, "bayer_level": 2.0, "dither_pixel": 2.0, "dither_levels": 6.0,
	"threshold": 0.75, "black_point": 0.0, "white_point": 1.0, "gamma_corr": 1.35,
	"contrast": 1.6, "brightness": 0.0,
	"edge_threshold": 0.08, "wind_reach": 32.0, "wind_trail": 0.6, "wind_cutoff": 0.22,
	"split_separation": 0.85, "signal_gain": 1.35, "signal_softness": 0.1,
	"signal_posterize": 0.0, "color_blur": 0.0, "rgb_dither": 1.0,
	"fringe_bleed": 0.7, "rgb_gradient": 0.0,
	"col_a": Color(0.25, 0.95, 1.0), "col_b": Color(1.0, 0.4, 0.85), "auto_colors": false,
	"driver_mode": 0.0, "FIELD_STRENGTH": 0.42, "FIELD_SPEED": 0.55, "OUTWARDNESS": 0.55,
	"FIELD_BREAKUP": 0.85, "COORD_NUDGE": 0.18, "FIELD_SIZE": 1.0,
	"flow_strength": 12.0, "temporal_hold": 0.0,
	"rgb_shift_amount": 6.0, "rgb_shift_angle": 0.0,
}
var motion := {
	"dither": {"delay": 0.0, "dur": 0.6, "curve": "cubic_out", "anchor": "manual"},
	"fringe": {"delay": 0.0, "dur": 0.6, "curve": "back_out", "anchor": "clash_impact"},
	"rgb": {"delay": 0.0, "dur": 0.5, "curve": "sine_in_out", "anchor": "manual"},
}
const ANCHORS := ["manual", "vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]

var fx_time := 0.0
var motion_running := {}
var motion_t0 := {}
var motion_loop := false
var preview_t := 0.0
var timeline_len := 2.4
var anchored_fired := {}
var event_marks := {}   # event name -> time (display)

# matchup
var mode_format := "1v1"
var pick_l := "ice_mage"
var pick_r := "doge_man"
var pick_extra := ["teknium", "ggb"]
var stage_id := "debug"
var fighter_ids: Array = []

# data (schemas, for the timeline display)
var timing_1v1 := {}
var mp_timing := {}

# ui
var subvp: SubViewport
var viewport_host: Control
var disp: SubViewportContainer
var ui_layer: CanvasLayer
var side_panel: Control
var panel_visible := true
var timeline_view: Control
var status_label: Label
var target_label: Label
var slot_picker: OptionButton
var swatch_nodes: Array = []


func _ready() -> void:
	shader = load("res://shaders/nrcu_fx.gdshader")
	_scan_fighters()
	_load_schemas()
	subvp = SubViewport.new()
	subvp.size = Vector2i(1280, 720)
	subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subvp.transparent_bg = false
	_build_ui()
	_mount_screen()


# ---------------------------------------------------------------- data
func _load_json(abs_path: String) -> Dictionary:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_schemas() -> void:
	timing_1v1 = _load_json("res://assets/vs/schema/motion_timing.json")
	mp_timing = _load_json("res://assets/vs/schema/multiplayer_motion_timing.json")
	event_marks = _event_times()


func _scan_fighters() -> void:
	var d := DirAccess.open("res://assets/vs/fighters")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir() and not f.begins_with("."):
			if not f.ends_with(".import"):
				fighter_ids.append(f)
		f = d.get_next()
	d.list_dir_end()
	fighter_ids.sort()
	if fighter_ids.is_empty():
		fighter_ids = ["teknimium", "doge_man", "ggb", "ice_mage", "turbofit", "witcheer", "mephisto"]


# ---------------------------------------------------------------- screen mounting
func _mp_records() -> Array:
	var teams: Array = []
	var n := 3
	match mode_format:
		"FFA_3": n = 3
		"FFA_4": n = 4
		"TEAM_2V2": teams = [0, 0, 1, 1]; n = 4
		"TEAM_2V1": teams = [0, 0, 1]; n = 3
		"TEAM_3V1": teams = [0, 0, 0, 1]; n = 4
	var pool := [pick_l, pick_r, pick_extra[0], pick_extra[1]]
	var recs := []
	for i in n:
		var rec := {"fighter_id": str(pool[i % pool.size()]), "player": i + 1, "slot_id": "P%d" % (i + 1)}
		if teams.size() > i:
			rec["team"] = teams[i]
		recs.append(rec)
	return recs


func _mount_screen() -> void:
	if screen != null and is_instance_valid(screen):
		screen.free()
	screen = load("res://scenes/vs_screen.tscn").instantiate()
	subvp.add_child(screen)
	var ok := false
	if mode_format == "1v1":
		ok = screen.start(pick_l, pick_r, stage_id)
	else:
		var plan: Dictionary = VSRequest.plan(_mp_records(), stage_id, mode_format.begins_with("TEAM"))
		ok = screen.start_presentation(plan)
		if not ok:
			status_label_text("plan rejected (%s) – showing 1v1" % str(plan.get("reason", "?")))
			mode_format = "1v1"
			ok = screen.start(pick_l, pick_r, stage_id)
	_collect_slots()
	_attach_materials()
	_apply_fx()
	_refresh_slot_picker()
	preview_t = 0.0
	if status_label != null and mode_format != "":
		status_label_text("live VS screen · %s · %s · %s" % [mode_format, pick_l + " vs " + pick_r, stage_id])


func _collect_slots() -> void:
	slot_nodes.clear()
	var root := screen.get_node_or_null("Root")
	if root == null:
		return
	_gather(root)


func _gather(n: Node) -> void:
	for ch in n.get_children():
		if ch is TextureRect and ch.texture != null:
			var key := String(ch.name).to_snake_case()
			if key == "under_shadow" or key == "shadow":
				pass
			elif not slot_nodes.has(key):
				slot_nodes[key] = ch
		_gather(ch)


func _attach_materials() -> void:
	materials.clear()
	# clean previous materials
	for key in slot_nodes.keys():
		var node = slot_nodes[key]
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("source_tex", (node as TextureRect).texture)
		var t: Texture2D = (node as TextureRect).texture
		m.set_shader_parameter("tex_size", Vector2(t.get_width(), t.get_height()))
		materials[key] = m
		(node as CanvasItem).material = m
	if not slot_nodes.has(selected_slot):
		selected_slot = "mark" if slot_nodes.has("mark") else (slot_nodes.keys()[0] if slot_nodes.size() > 0 else "")


# ---------------------------------------------------------------- fx
func _apply_fx() -> void:
	for key in materials.keys():
		var m: ShaderMaterial = materials[key]
		var on: bool = str(key) == selected_slot
		m.set_shader_parameter("base_mode", float(state["base_mode"]))
		m.set_shader_parameter("fx_dither", float(state["fx_amount"]["dither"]) if (bool(state["fx_on"]["dither"]) and on) else 0.0)
		m.set_shader_parameter("fx_fringe", float(state["fx_amount"]["fringe"]) if (bool(state["fx_on"]["fringe"]) and on) else 0.0)
		m.set_shader_parameter("fx_flow", 1.0 if bool(state["fx_on"]["flow"]) else 0.0)
		m.set_shader_parameter("fx_rgb", float(state["fx_amount"]["rgb"]) if (bool(state["fx_on"]["rgb"]) and on) else 0.0)
		for k in ["dither_mode", "bayer_level", "dither_pixel", "dither_levels", "threshold",
				"black_point", "white_point", "gamma_corr", "contrast", "brightness",
				"edge_threshold", "wind_reach", "wind_trail", "wind_cutoff", "split_separation",
				"signal_gain", "signal_softness", "signal_posterize", "color_blur", "rgb_dither",
				"fringe_bleed", "rgb_gradient", "driver_mode", "FIELD_STRENGTH", "FIELD_SPEED",
				"OUTWARDNESS", "FIELD_BREAKUP", "COORD_NUDGE", "FIELD_SIZE", "flow_strength",
				"temporal_hold", "rgb_shift_amount", "rgb_shift_angle"]:
			m.set_shader_parameter(k, float(state[k]))
		m.set_shader_parameter("fringe_color_a", state["col_a"])
		m.set_shader_parameter("fringe_color_b", state["col_b"])
	if target_label != null:
		target_label.text = "FX target: %s" % selected_slot.to_upper()


func _apply_to_all() -> void:
	for key in materials.keys():
		var m: ShaderMaterial = materials[key]
		m.set_shader_parameter("fx_fringe", float(state["fx_amount"]["fringe"]) if bool(state["fx_on"]["fringe"]) else 0.0)
	_apply_fx()


# ---------------------------------------------------------------- timeline data
func _hold_start() -> float:
	if mode_format == "1v1":
		return float((timing_1v1.get("entry", {}) as Dictionary).get("hold_start", 0.93))
	return float((mp_timing.get("shared", {}) as Dictionary).get("hold_start", 0.88))


func _event_times() -> Dictionary:
	var out := {}
	if mode_format == "1v1":
		var entry: Dictionary = timing_1v1.get("entry", {})
		out["vs_enter"] = 0.0
		out["stage_reveal"] = float((entry.get("stage", {}) as Dictionary).get("start", 0.0))
		out["fighter_reveal"] = float((entry.get("primaries", {}) as Dictionary).get("start", 0.18))
		out["clash_impact"] = float(((entry.get("vs", {}) as Dictionary).get("impact_flash", {}) as Dictionary).get("center_time", 0.615))
		out["hold_enter"] = float(entry.get("hold_start", 0.93))
	else:
		var sh: Dictionary = mp_timing.get("shared", {})
		out["vs_enter"] = 0.0
		out["stage_reveal"] = float((sh.get("stage", [0, 0.18]) as Array)[0])
		out["fighter_reveal"] = float((sh.get("primaries", [0.14, 0.46]) as Array)[0])
		out["clash_impact"] = float((sh.get("vs", [0.52, 0.66]) as Array)[1])
		out["hold_enter"] = float(sh.get("hold_start", 0.88))
	return out


func _process(delta: float) -> void:
	fx_time += delta
	for fx in ["dither", "fringe", "rgb"]:
		if motion_running.get(fx, false):
			var el := fx_time - float(motion_t0.get(fx, 0.0))
			var mt: Dictionary = motion[fx]
			var p := clampf((el - float(mt["delay"])) / maxf(float(mt["dur"]), 0.01), 0.0, 1.0)
			if bool(state["fx_on"][fx]):
				state["fx_amount"][fx] = _ease(p, String(mt["curve"]))
			if p >= 1.0:
				if motion_loop:
					motion_t0[fx] = fx_time
				else:
					motion_running[fx] = false
		for key in materials.keys():
			materials[key].set_shader_parameter("fx_time", fx_time)
	_apply_fx()
	# keep the 1280x720 preview fitted into the available area
	if viewport_host != null and disp != null:
		var avail := viewport_host.size
		if avail.x > 10 and avail.y > 10:
			var s := minf(avail.x / 1280.0, avail.y / 720.0)
			disp.scale = Vector2(s, s)
			disp.position = (avail - Vector2(1280, 720) * s) * 0.5
	# the live screen drives the timeline
	if screen != null and screen.has_method("elapsed"):
		preview_t = float(screen.elapsed())
	_fire_anchors()
	if timeline_view != null:
		timeline_view.queue_redraw()


func _fire_anchors() -> void:
	for fx in ["dither", "fringe", "rgb"]:
		var anchor := String(motion[fx]["anchor"])
		if anchor == "manual" or anchored_fired.has(fx + anchor):
			continue
		var at := float(event_marks.get(anchor, -1.0))
		if at >= 0.0 and preview_t >= at:
			motion_running[fx] = true
			motion_t0[fx] = fx_time
			anchored_fired[fx + anchor] = true


func _ease(p: float, curve: String) -> float:
	match curve:
		"linear":
			return p
		"cubic_out":
			return 1.0 - pow(1.0 - p, 3.0)
		"cubic_in":
			return p * p * p
		"back_out":
			var s := 1.70158
			var t := p - 1.0
			return t * t * ((s + 1.0) * t + s) + 1.0
		"sine_in_out":
			return 0.5 - 0.5 * cos(PI * p)
		_:
			return p


# ---------------------------------------------------------------- ui
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(root)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	col.add_child(row)

	side_panel = ScrollContainer.new()
	side_panel.custom_minimum_size = Vector2(400, 0)
	side_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(side_panel)
	var svb := VBoxContainer.new()
	svb.custom_minimum_size.x = 376
	svb.add_theme_constant_override("separation", 4)
	side_panel.add_child(svb)

	_label(svb, "NRCU FX OVERLAY LAB", 18, Color(0.35, 0.78, 0.65))
	status_label = _label(svb, "…", 12, Color(0.62, 0.68, 0.75))
	target_label = _label(svb, "FX target: MARK", 13, Color(0.95, 0.85, 0.55))

	_section(svb, "MATCHUP")
	var frow := HBoxContainer.new()
	svb.add_child(frow)
	var fmt := OptionButton.new()
	fmt.custom_minimum_size.x = 160
	var formats := ["1v1", "FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1", "TEAM_3V1"]
	for f in formats:
		fmt.add_item(f)
	fmt.item_selected.connect(func(i):
		mode_format = formats[i]
		_mount_screen())
	frow.add_child(fmt)
	var stages := OptionButton.new()
	for s in ["debug", "toy_room", "sky"]:
		stages.add_item(s)
	stages.item_selected.connect(func(i):
		stage_id = ["debug", "toy_room", "sky"][i]
		_mount_screen())
	frow.add_child(stages)
	var lrow := HBoxContainer.new()
	svb.add_child(lrow)
	for pair in [["l", 0], ["r", 1]]:
		var p := OptionButton.new()
		for fid in fighter_ids:
			p.add_item(fid)
		p.selected = maxi(fighter_ids.find(pick_l if pair[1] == 0 else pick_r), 0)
		p.item_selected.connect(func(i):
			if pair[1] == 0:
				pick_l = str(fighter_ids[i])
			else:
				pick_r = str(fighter_ids[i])
			_mount_screen())
		lrow.add_child(p)
	var erow := HBoxContainer.new()
	svb.add_child(erow)
	for idx in 2:
		var p := OptionButton.new()
		for fid in fighter_ids:
			p.add_item(fid)
		p.selected = maxi(fighter_ids.find(pick_extra[idx]), 0)
		p.item_selected.connect(func(i):
			pick_extra[idx] = str(fighter_ids[i])
			_mount_screen())
		erow.add_child(p)

	_section(svb, "FX TARGET ELEMENT")
	slot_picker = OptionButton.new()
	slot_picker.custom_minimum_size.x = 300
	slot_picker.item_selected.connect(func(i):
		selected_slot = String(slot_picker.get_item_text(i)).to_lower()
		_apply_fx())
	svb.add_child(slot_picker)
	_toggle(svb, "apply FX to ALL elements", false, func(v):
		if v:
			_apply_to_all())

	_section(svb, "FX 1 · DITHER (overlay)")
	_toggle(svb, "enabled", false, func(v): state["fx_on"]["dither"] = v; _apply_fx())
	_amount_row(svb, "dither")
	_slider(svb, "levels", 2, 24, 1, 6, func(v): state["dither_levels"] = v; _apply_fx())
	_slider(svb, "pixel size", 0.5, 6, 0.05, 2.0, func(v): state["dither_pixel"] = v; _apply_fx())
	_slider(svb, "threshold (stamp)", 0.2, 0.95, 0.01, 0.75, func(v): state["threshold"] = v; _apply_fx())
	_motion_row(svb, "dither")

	_section(svb, "FX 2 · FRINGE (edge split)")
	_toggle(svb, "enabled", true, func(v): state["fx_on"]["fringe"] = v; _apply_fx())
	_amount_row(svb, "fringe")
	var crow := HBoxContainer.new()
	svb.add_child(crow)
	_swatch(crow, true)
	_swatch(crow, false)
	var auto_b := Button.new()
	auto_b.text = "auto from image"
	auto_b.pressed.connect(func():
		state["auto_colors"] = true
		_auto_palette())
	crow.add_child(auto_b)
	_slider(svb, "edge threshold", 0.005, 0.5, 0.005, 0.08, func(v): state["edge_threshold"] = v; _apply_fx())
	_slider(svb, "wind reach px", 4, 96, 1, 32, func(v): state["wind_reach"] = v; _apply_fx())
	_slider(svb, "wind trail", 0, 1, 0.01, 0.6, func(v): state["wind_trail"] = v; _apply_fx())
	_slider(svb, "split separation", 0, 2.5, 0.01, 0.85, func(v): state["split_separation"] = v; _apply_fx())
	_slider(svb, "signal gain", 0, 3, 0.01, 1.35, func(v): state["signal_gain"] = v; _apply_fx())
	_slider(svb, "colour blur px", 0, 200, 1, 0, func(v): state["color_blur"] = v; _apply_fx())
	_slider(svb, "bleed past element", 0, 1, 0.01, 0.7, func(v): state["fringe_bleed"] = v; _apply_fx())
	_motion_row(svb, "fringe")

	_section(svb, "FX 3 · FLOW (motion)")
	_toggle(svb, "enabled", true, func(v): state["fx_on"]["flow"] = v; _apply_fx())
	_slider(svb, "flow strength", 0, 24, 0.1, 12.0, func(v): state["flow_strength"] = v; _apply_fx())
	_slider(svb, "field strength", 0, 2.5, 0.01, 0.42, func(v): state["FIELD_STRENGTH"] = v; _apply_fx())
	_slider(svb, "field speed", 0, 2, 0.01, 0.55, func(v): state["FIELD_SPEED"] = v; _apply_fx())

	_section(svb, "FX 4 · RGB SHIFT")
	_toggle(svb, "enabled", false, func(v): state["fx_on"]["rgb"] = v; _apply_fx())
	_amount_row(svb, "rgb")
	_slider(svb, "shift px", 0, 24, 0.5, 6.0, func(v): state["rgb_shift_amount"] = v; _apply_fx())
	_slider(svb, "angle", 0, 360, 1, 0, func(v): state["rgb_shift_angle"] = v; _apply_fx())
	_motion_row(svb, "rgb")

	_section(svb, "PREVIEW / LIVE SCREEN")
	var prow := HBoxContainer.new()
	svb.add_child(prow)
	var restart := Button.new()
	restart.text = "⟲ restart screen"
	restart.pressed.connect(func(): _mount_screen())
	prow.add_child(restart)
	var exitb := Button.new()
	exitb.text = "signal match_ready (exit)"
	exitb.pressed.connect(func():
		if screen != null and screen.has_method("signal_match_ready"):
			screen.signal_match_ready())
	prow.add_child(exitb)
	var fxb := Button.new()
	fxb.text = "▶ trigger FX motion"
	fxb.pressed.connect(func():
		for fx in ["dither", "fringe", "rgb"]:
			motion_running[fx] = true
			motion_t0[fx] = fx_time)
	svb.add_child(fxb)

	# preview area
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	row.add_child(right)
	var top_bar := HBoxContainer.new()
	right.add_child(top_bar)
	var panel_toggle := Button.new()
	panel_toggle.text = "◧ panel"
	panel_toggle.pressed.connect(func():
		panel_visible = not panel_visible
		side_panel.visible = panel_visible)
	top_bar.add_child(panel_toggle)
	viewport_host = Control.new()
	viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_host.clip_contents = true
	right.add_child(viewport_host)
	disp = SubViewportContainer.new()
	disp.stretch = false
	disp.size = Vector2(1280, 720)
	disp.position = Vector2.ZERO
	viewport_host.add_child(disp)
	disp.add_child(subvp)

	timeline_view = TimelineView.new()
	timeline_view.lab = self
	timeline_view.custom_minimum_size = Vector2(0, 132)
	col.add_child(timeline_view)


func status_label_text(t: String) -> void:
	if status_label != null:
		status_label.text = t


class TimelineView extends Control:
	var lab: Node
	var dragging := false
	const MARGIN := Vector2(46, 16)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.07, 0.095, 1.0))
		var t_end: float = maxf(lab.timeline_len, lab._hold_start() + 0.8)
		var span := w - MARGIN.x - 20
		var font := ThemeDB.fallback_font
		var sec := 0.0
		while sec <= t_end + 0.001:
			var x := MARGIN.x + sec / t_end * span
			draw_line(Vector2(x, 8), Vector2(x, h - 8), Color(1, 1, 1, 0.07), 1.0)
			draw_string(font, Vector2(x + 2, h - 4), "%.1f" % sec, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.62, 0.9))
			sec += 0.2
		var rows := []
		if lab.mode_format == "1v1":
			var entry: Dictionary = lab.timing_1v1.get("entry", {})
			for item in [["stage", entry.get("stage", {})], ["echoes", entry.get("echoes", {})],
					["primaries", entry.get("primaries", {})], ["vs mark", entry.get("vs", {})],
					["names", entry.get("names", {})]]:
				var d: Dictionary = item[1]
				rows.append([str(item[0]), float(d.get("start", 0.0)), float(d.get("end", 0.5))])
		else:
			var sh: Dictionary = lab.mp_timing.get("shared", {})
			for item in [["stage", sh.get("stage", [0, 0.18])], ["echoes", sh.get("echoes", [0.06, 0.28])],
					["primaries", sh.get("primaries", [0.14, 0.46])], ["vs mark", sh.get("vs", [0.52, 0.66])],
					["names", sh.get("names", [0.62, 0.88])]]:
				var arr: Array = item[1]
				rows.append([str(item[0]), float(arr[0]), float(arr[1])])
		var y := 14.0
		for r in rows:
			var x0 := MARGIN.x + float(r[1]) / t_end * span
			var x1 := MARGIN.x + float(r[2]) / t_end * span
			var color := Color(0.30, 0.62, 0.85, 0.55)
			if str(r[0]) == "vs mark":
				color = Color(0.95, 0.75, 0.35, 0.75)
			draw_rect(Rect2(x0, y, maxf(x1 - x0, 2.0), 13), color)
			draw_string(font, Vector2(x0 + 4, y + 10.5), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))
			y += 16.5
		var et: Dictionary = lab.event_marks
		var ev_y := h - 26.0
		for name in ["vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]:
			var at := float(et.get(name, 0.0))
			var x := MARGIN.x + at / t_end * span
			draw_line(Vector2(x, 6), Vector2(x, ev_y + 6), Color(0.95, 0.4, 0.75, 0.5), 1.0)
			draw_string(font, Vector2(x + 2, ev_y + 16), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.55, 0.8, 0.95))
		var hx: float = MARGIN.x + lab._hold_start() / t_end * span
		draw_line(Vector2(hx, 6), Vector2(hx, ev_y + 6), Color(0.45, 0.9, 0.7, 0.8), 2.0)
		draw_string(font, Vector2(hx + 3, 12), "hold", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.9, 0.7, 1.0))
		var pt: float = lab.preview_t
		var px := MARGIN.x + clampf(pt, 0.0, t_end) / t_end * span
		draw_line(Vector2(px, 4), Vector2(px, h - 4), Color(1.0, 0.9, 0.5, 1.0), 2.0)
		draw_circle(Vector2(px, 9), 4.0, Color(1.0, 0.9, 0.5, 1.0))
		draw_string(font, Vector2(px + 6, 14), "%.3fs" % pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.95, 0.7, 1.0))
		draw_string(font, Vector2(MARGIN.x + 4, h - 8), "live screen state: %s" % lab._screen_state(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.9, 0.75, 0.9))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				_seek(event.position.x)
			else:
				accept_event()
		elif event is InputEventMouseMotion and dragging:
			_seek((event as InputEventMouseMotion).position.x)
			accept_event()

	func _seek(x: float) -> void:
		var span := size.x - MARGIN.x - 20
		var t_end: float = maxf(lab.timeline_len, lab._hold_start() + 0.8)
		var t := clampf((x - MARGIN.x) / span, 0.0, 1.0) * t_end
		# The lab owns transport state. Using the public transport path keeps
		# drag-scrubbing, direct-time entry, frame-step and scripted evidence
		# semantically identical, and always parks the composition deterministically.
		if lab.has_method("_transport_seek_to"):
			lab._transport_seek_to(t)
		else:
			# Legacy v0.2 fallback for the classic lab only.
			var scr = lab.screen
			if scr != null:
				var tw = scr.get("_entry_tween")
				if tw != null and tw is Tween and (tw as Tween).has_method("seek"):
					(tw as Tween).seek(t)


func _screen_state() -> String:
	if screen != null and screen.has_method("state"):
		return str(screen.state())
	return "?"


# ---------------------------------------------------------------- ui helpers
func _label(parent: Node, text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _section(parent: Node, title: String) -> void:
	_label(parent, "── " + title, 13, Color(0.35, 0.78, 0.65))


func _toggle(parent: Node, text: String, value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


func _slider(parent: Node, text: String, mn: float, mx: float, step: float, value: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(row, text, 12, Color(0.62, 0.68, 0.75))
	l.custom_minimum_size.x = 150
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 130
	var val := _label(row, "%.2f" % value, 12, Color(0.8, 0.86, 0.92))
	val.custom_minimum_size.x = 46
	s.value_changed.connect(func(v):
		val.text = "%.2f" % v
		cb.call(v))
	row.add_child(s)
	return s


func _amount_row(parent: Node, fx: String) -> void:
	_slider(parent, "amount", 0, 1, 0.01, float(state["fx_amount"][fx]), func(v): state["fx_amount"][fx] = v; _apply_fx())


func _motion_row(parent: Node, fx: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(row, "motion", 12, Color(0.62, 0.68, 0.75))
	l.custom_minimum_size.x = 50
	var d := SpinBox.new()
	d.min_value = 0; d.max_value = 3; d.step = 0.05
	d.value = float(motion[fx]["delay"]); d.custom_minimum_size.x = 70
	d.value_changed.connect(func(v): motion[fx]["delay"] = v)
	row.add_child(d)
	var du := SpinBox.new()
	du.min_value = 0.05; du.max_value = 4; du.step = 0.05
	du.value = float(motion[fx]["dur"]); du.custom_minimum_size.x = 70
	du.value_changed.connect(func(v): motion[fx]["dur"] = v)
	row.add_child(du)
	var cur := OptionButton.new()
	var curves := ["linear", "cubic_out", "cubic_in", "back_out", "sine_in_out"]
	for c in curves:
		cur.add_item(c)
	cur.selected = curves.find(String(motion[fx]["curve"]))
	cur.item_selected.connect(func(i): motion[fx]["curve"] = curves[i])
	row.add_child(cur)
	var anc := OptionButton.new()
	for a in ANCHORS:
		anc.add_item(a)
	anc.selected = ANCHORS.find(String(motion[fx]["anchor"]))
	anc.item_selected.connect(func(i): motion[fx]["anchor"] = ANCHORS[i])
	row.add_child(anc)


func _swatch(parent: Node, which_a: bool) -> void:
	var sw := ColorRect.new()
	sw.color = state["col_a"] if which_a else state["col_b"]
	sw.custom_minimum_size = Vector2(40, 24)
	parent.add_child(sw)
	swatch_nodes.append({"rect": sw, "a": which_a})
	var picker := ColorPickerButton.new()
	picker.color = sw.color
	picker.custom_minimum_size = Vector2(24, 24)
	picker.edit_alpha = true
	picker.color_changed.connect(func(c):
		if which_a:
			state["col_a"] = c
		else:
			state["col_b"] = c
		state["auto_colors"] = false
		sw.color = c
		_apply_fx())
	parent.add_child(picker)


func _auto_palette() -> void:
	var tex: Texture2D = null
	if slot_nodes.has(selected_slot) and slot_nodes[selected_slot] is TextureRect:
		tex = (slot_nodes[selected_slot] as TextureRect).texture
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img = img.duplicate() as Image
	img.resize(48, 48, Image.INTERPOLATE_BILINEAR)
	var bins := {}
	for y in 48:
		for x in 48:
			var c := img.get_pixel(x, y)
			if c.a < 0.3:
				continue
			var key := Vector3i(int(c.r * 8.0), int(c.g * 8.0), int(c.b * 8.0))
			bins[key] = float(bins.get(key, 0.0)) + 1.0 + c.s * 2.0
	var keys := bins.keys()
	if keys.is_empty():
		return
	keys.sort_custom(func(a, b): return bins[a] > bins[b])
	var top: Array = keys.slice(0, mini(8, keys.size()))
	var k0: Vector3i = top[0]
	var col_a := Color(k0.x / 8.0, k0.y / 8.0, k0.z / 8.0)
	var best := col_a
	var best_d := -1.0
	for k in top:
		var kv: Vector3i = k
		var c := Color(kv.x / 8.0, kv.y / 8.0, kv.z / 8.0)
		var d := absf(c.r - col_a.r) + absf(c.g - col_a.g) + absf(c.b - col_a.b)
		if d > best_d:
			best_d = d
			best = c
	var col_b := best
	if best_d < 0.1:
		col_b = Color(1.0 - col_a.r, 1.0 - col_a.g, 1.0 - col_a.b)
	state["col_a"] = col_a
	state["col_b"] = col_b
	refresh_swatches()
	_apply_fx()


func refresh_swatches() -> void:
	for s in swatch_nodes:
		if s["a"]:
			s["rect"].color = state["col_a"]
		else:
			s["rect"].color = state["col_b"]


func _refresh_slot_picker() -> void:
	if slot_picker == null:
		return
	slot_picker.clear()
	var keys := slot_nodes.keys()
	keys.sort()
	# put the vs mark first
	if keys.has("mark"):
		keys.erase("mark")
		keys.push_front("mark")
	var idx := 0
	for i in keys.size():
		var k := str(keys[i])
		slot_picker.add_item(k.to_upper())
		if k == selected_slot:
			idx = i
	slot_picker.selected = idx
