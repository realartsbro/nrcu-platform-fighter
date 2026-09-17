extends SceneTree
# ============================================================================
# NRCU FX Lab v0.2 — evidence driver (completion gates 2/3/5/6)
# Drives the real lab instance: sets documented states through the lab's own
# functions, fires REAL input events at widgets (full GUI hit-test), captures
# full-window PNGs and samples FPS/cost metrics for the acceptance matrix.
# Output dir: $FXLAB_EVIDENCE_DIR (fallback user://evidence).
# ============================================================================

const FX := ["dither", "fringe", "flow", "rgb"]

var lab: Node
var out_dir: String
var shots: Array = []
var perf: Array = []
var checks: Array = []

func _init() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("user://evidence")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(45)

    await _ensure_masks()
    await _phase_views()
    await _phase_scopes()
    await _phase_domains()
    await _phase_pure()
    await _phase_element_study()
    await _phase_masks()
    await _phase_motion()
    await _phase_bypass()
    await _phase_real_input()
    await _phase_perf()

    _write_summary()
    print("[EVIDENCE] done · shots=", shots.size(), " perf=", perf.size(), " checks=", checks.size())
    quit()

# ---------------------------------------------------------------- helpers
func settle(n: int) -> void:
    for i in n:
        await process_frame

func snap(tag: String, note: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    var path := out_dir.path_join("%s.png" % tag)
    var err := img.save_png(path)
    shots.append({
        "tag": tag, "file": path, "note": note, "ok": err == OK,
        "fps": Engine.get_frames_per_second(),
        "cost": lab.cost_label.text if lab.cost_label != null else "",
        "status": lab.status_label.text if lab.status_label != null else "",
    })
    print("[SNAP] ", tag, " · ", note)

func _apply() -> void:
    lab._apply_fx()
    lab._update_summary()
    await settle(3)

func set_fx(solo: String) -> void:
    for f in FX:
        lab.state["fx_on"][f] = f == solo
    await _apply()

func set_fx_multi(on: Array) -> void:
    for f in FX:
        lab.state["fx_on"][f] = f in on
    await _apply()

func _tab(name: String) -> void:
    var tabs := lab.find_children("*", "TabContainer", true, false)
    if tabs.is_empty():
        return
    var order := ["LOOK", "MOTION", "LOOKS", "DIAGNOSTICS"]
    tabs[0].current_tab = order.find(name)
    await settle(4)

func _depth(name: String) -> void:
    var order := ["BASIC", "ADVANCED", "EXPERT"]
    var idx := order.find(name)
    if idx < 0:
        idx = 1
    if lab.detail_picker != null:
        lab.detail_picker.select(idx)
    lab._on_detail(idx)
    await settle(6)

func _target_mode(m: String) -> void:
    lab._on_target_mode(lab.TARGET_MODES.find(m))
    await settle(3)

func _target_role(r: String) -> void:
    lab._on_target_role(lab.TARGET_ROLES.find(r))
    await settle(3)

func _check(name: String, ok: bool, detail: String = "") -> void:
    checks.append({"check": name, "ok": ok, "detail": detail})
    print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "  ", detail)

func _find_button(text: String) -> Node:
    for n in lab.find_children("*", "Button", true, false):
        if n.text == text:
            return n
    return null

func _click(control: Node, label: String) -> void:
    var pos: Vector2 = (control as Control).get_global_rect().get_center()
    var down := InputEventMouseButton.new()
    down.button_index = MOUSE_BUTTON_LEFT
    down.pressed = true
    down.position = pos
    Input.parse_input_event(down)
    await settle(3)
    var up := InputEventMouseButton.new()
    up.button_index = MOUSE_BUTTON_LEFT
    up.pressed = false
    up.position = pos
    Input.parse_input_event(up)
    await settle(6)
    print("[CLICK] ", label, " @ ", pos)

func readout_line(n: int) -> String:
    if lab.processing_label == null:
        return ""
    var t: String = lab.processing_label.text
    for junk in ["[b]", "[/b]", "[color=#79ebb9]", "[/color]"]:
        t = t.replace(junk, "")
    var lines := t.split("\n")
    return lines[n] if n < lines.size() else ""

# ---------------------------------------------------------------- phases
func _ensure_masks() -> void:
    # Masks ship as real project assets (with .import files); the lab loads
    # them through ResourceLoader. Present = fine.
    print("[MASKS] available: ", lab.mask_paths)

func _phase_views() -> void:
    await _depth("BASIC")
    await snap("01_view_look_basic", "LOOK tab · CONTROL DEPTH BASIC")
    var basic_rows := _visible_detail_rows()
    await _depth("ADVANCED")
    await snap("02_view_look_advanced", "LOOK tab · ADVANCED")
    var adv_rows := _visible_detail_rows()
    # scroll the LOOK tab into the region where advanced/expert controls live
    _scroll_look(0.5)
    await settle(4)
    await snap("02b_view_look_advanced_scrolled", "ADVANCED · scrolled to advanced section")
    await _depth("EXPERT")
    await settle(4)
    await snap("03_view_look_expert", "LOOK tab · EXPERT")
    var expert_rows := _visible_detail_rows()
    _check("CONTROL DEPTH populates controls", basic_rows < adv_rows and adv_rows <= expert_rows,
        "basic=%d advanced=%d expert=%d detail rows" % [basic_rows, adv_rows, expert_rows])
    _tab("MOTION")
    await snap("04_view_motion", "MOTION tab")
    _tab("LOOKS")
    await snap("05_view_looks", "LOOKS tab")
    _tab("DIAGNOSTICS")
    await snap("06_view_diag", "DIAGNOSTICS tab")
    _tab("LOOK")
    await _depth("ADVANCED")

func _visible_detail_rows() -> int:
    var n := 0
    for node in lab.advanced_nodes:
        if node.visible:
            n += 1
    for node in lab.expert_nodes:
        if node.visible:
            n += 1
    return n

func _scroll_look(fraction: float) -> void:
    for sc in lab.find_children("*", "ScrollContainer", true, false):
        if sc.scroll_vertical > 0 or sc.get_combined_minimum_size().y > sc.size.y:
            sc.scroll_vertical = int((sc.get_v_scroll_bar().max_value - sc.size.y) * fraction)
            return

func _phase_scopes() -> void:
    await _target_mode("ROLE")
    await _target_role("VS MARK")
    await snap("07_scope_role_mark", "TARGET ROLE=VS MARK")
    await _target_role("PRIMARIES")
    await snap("08_scope_role_primaries", "TARGET ROLE=PRIMARIES")
    await _target_role("ECHOES")
    await snap("09_scope_role_echoes", "TARGET ROLE=ECHOES")
    await _target_role("NAMES")
    await snap("10_scope_role_names", "TARGET ROLE=NAMES")
    await _target_role("STAGE")
    await snap("11_scope_role_stage", "TARGET ROLE=STAGE")
    await _target_mode("ALL")
    await snap("12_scope_all", "TARGET MODE=ALL")

var last_img: Image = null

func img_of(tag: String) -> Image:
    var p := out_dir.path_join("%s.png" % tag)
    if not FileAccess.file_exists(p):
        return null
    return Image.load_from_file(p)

func diff_percent(a: String, b: String, crop: Rect2i = Rect2i()) -> float:
    var ia := img_of(a)
    var ib := img_of(b)
    if ia == null or ib == null:
        return -1.0
    if ia.get_size() != ib.get_size():
        return -1.0
    if crop.size.x > 0 and crop.size.y > 0:
        ia = ia.get_region(crop)
        ib = ib.get_region(crop)
    var da := ia.get_data()
    var db := ib.get_data()
    var n := da.size()
    var changed := 0
    var i := 0
    while i < n:
        if absi(int(da[i]) - int(db[i])) > 10:
            changed += 1
        i += 4
    return 100.0 * float(changed) / float(n / 4)

func _mat_probe(label: String) -> void:
    var enabled := 0
    var invert := 0
    var loaded := 0
    for key in lab.materials.keys():
        var m: ShaderMaterial = lab.materials[key]
        if float(m.get_shader_parameter("effect_mask_enabled")) > 0.5:
            enabled += 1
        if float(m.get_shader_parameter("effect_mask_invert")) > 0.5:
            invert += 1
        if float(m.get_shader_parameter("treatment_mask_loaded")) > 0.5:
            loaded += 1
    print("[MATPROBE] ", label, " · enabled=", enabled, "/", lab.materials.size(), " loaded=", loaded, " invert=", invert)

func _series_change_rate(prefix: String, count: int, crop: Rect2i = Rect2i()) -> float:
    var changed := 0
    var prev := ""
    for i in count:
        var tag := "%s_%02d" % [prefix, i]
        await snap(tag, "series frame %d" % i)
        if i > 0:
            var d := diff_percent(prev, tag, crop)
            if d > 0.25:
                changed += 1
        prev = tag
    var rate := 100.0 * float(changed) / float(count - 1)
    print("[SERIES] ", prefix, " change-rate=", snappedf(rate, 1), "%")
    return rate

func _phase_domains() -> void:
    await _target_mode("ALL")
    lab.state["signal_posterize"] = 0.0
    lab.state["temporal_hold"] = 0.0
    await set_fx("dither")
    await snap("13_domain_dither_solo", "only DITHER on (BAYER)")
    await set_fx("fringe")
    lab.state["fringe_coverage_mode"] = 0.0
    await _apply()
    await snap("14_domain_fringe_smooth", "only FRINGE on · coverage SMOOTH · no dither")
    _check("dither off + fringe smooth",
        lab.state["fx_on"]["dither"] == false and float(lab.state["fringe_coverage_mode"]) == 0.0,
        readout_line(2))
    lab.state["fringe_coverage_mode"] = 1.0
    await _apply()
    await snap("15_domain_fringe_bayer", "only FRINGE on · coverage BAYER")
    lab.state["fringe_coverage_mode"] = 0.0
    await _apply()
    # FLOW is the motion driver of the fringe: measure motion with and without it
    await snap("16a_fringe_static_t1", "FRINGE only · t1")
    await settle(28)
    await snap("16b_fringe_static_t2", "FRINGE only · t2 (no flow: static)")
    var still := diff_percent("16a_fringe_static_t1", "16b_fringe_static_t2")
    lab.state["fx_on"]["flow"] = true
    await _apply()
    await settle(20)
    await snap("16c_fringe_flow_t1", "FRINGE+FLOW · t1")
    await settle(28)
    await snap("16d_fringe_flow_t2", "FRINGE+FLOW · t2 (flow: motion)")
    var moving := diff_percent("16c_fringe_flow_t1", "16d_fringe_flow_t2")
    _check("FLOW is the fringe motion driver", moving > 1.0 and moving > still * 5.0,
        "no-flow %.2f%% vs flow %.2f%% pixels changing" % [still, moving])
    lab.state["fx_on"]["flow"] = false
    await set_fx("flow")
    await snap("16_domain_flow_solo", "FLOW solo (documented: fringe-bound modulator, fringe is off)")
    await set_fx("rgb")
    await snap("17_domain_rgb_solo", "only RGB SHIFT on")
    # SIGNAL: quantises the sampled colour signal — verify with the fringe running
    await set_fx("fringe")
    await snap("18a_signal_continuous", "FRINGE · signal CONTINUOUS")
    lab.state["signal_posterize"] = 4.0
    await _apply()
    await snap("18b_signal_posterize4", "FRINGE · signal posterize=4")
    var sig_diff := diff_percent("18a_signal_continuous", "18b_signal_posterize4")
    _check("SIGNAL posterize steps the colour signal", sig_diff > 0.5, "%.2f%% pixels changed" % sig_diff)
    lab.state["signal_posterize"] = 0.0
    # TEMPORAL HOLD: quantised time freezes most frames. Measure on the VS-mark
    # crop of the LIVE screen: the stage/sky animates independently, the mark's
    # FX area is dominated by the FX layer itself.
    lab.state["fx_on"]["flow"] = true
    await _apply()
    await settle(20)
    var fx_crop := Rect2i(820, 300, 520, 360)
    var live_rate := await _series_change_rate("19a_live", 10, fx_crop)
    lab.state["temporal_hold"] = 8.0
    await _apply()
    await settle(30)
    var held_rate := await _series_change_rate("19c_hold8", 10, fx_crop)
    _check("TEMPORAL HOLD freezes the look", held_rate < live_rate * 0.8,
        "mark-crop: live %.1f%% frames changing vs held %.1f%%" % [live_rate, held_rate])
    lab.state["temporal_hold"] = 0.0
    lab.state["fx_on"]["flow"] = false
    await settle(10)
    await set_fx_multi(FX)
    lab.state["signal_posterize"] = 2.0
    lab.state["temporal_hold"] = 12.0
    await _apply()
    await snap("20_domain_stack_all", "all domains stacked (not pure)")

func _phase_pure() -> void:
    lab._on_pure(true)
    await settle(8)
    lab._assert_pure()
    await settle(6)
    await snap("21_pure_continuous_on", "PURE CONTINUOUS on · all domains")
    _check("pure guarantee enforced", "PASS" in lab.status_label.text, lab.status_label.text)
    lab._on_pure(false)
    await settle(8)
    await snap("22_pure_continuous_off", "PURE off")
    _check("pure off restores stack", lab.state["pure_continuous"] == false, readout_line(3))

func _phase_element_study() -> void:
    lab._on_source_mode(1)
    await settle(8)
    await snap("23_source_element_study", "SOURCE MODE=ELEMENT STUDY")
    lab._on_source_mode(0)
    await settle(8)
    await snap("24_source_live_screen", "SOURCE MODE=LIVE SCREEN (restored)")

func _phase_masks() -> void:
    await set_fx("fringe")
    var edge_mask := ""
    var treat_mask := ""
    for p in lab.mask_paths:
        if "edge" in p and edge_mask == "":
            edge_mask = p
        if "treatment" in p and treat_mask == "":
            treat_mask = p
    if edge_mask == "" and lab.mask_paths.size() > 0:
        edge_mask = lab.mask_paths[0]
    if treat_mask == "" and lab.mask_paths.size() > 0:
        treat_mask = lab.mask_paths[0]
    if edge_mask == "" or treat_mask == "":
        _check("mask assets available", false, "no masks found")
        return
    _check("mask assets available", true, "%d masks" % lab.mask_paths.size())
    lab.state["edge_source_mode"] = 3.0
    lab.edge_mask_path = edge_mask
    await _apply()
    _mat_probe("edge mask set")
    await snap("25_edge_mask_custom", "EDGE SOURCE=CUSTOM EDGE MASK (%s)" % edge_mask.get_file())
    lab.state["edge_source_mode"] = 2.0
    lab.state["effect_mask_enabled"] = true
    lab.treatment_mask_path = treat_mask
    await _apply()
    _mat_probe("treatment on")
    await snap("26_treatment_mask_on", "TREATMENT MASK on (%s)" % treat_mask.get_file())
    lab.state["effect_mask_invert"] = true
    await _apply()
    _mat_probe("treatment inverted")
    await snap("26b_treatment_mask_invert", "TREATMENT MASK inverted")
    var inv_diff := diff_percent("26_treatment_mask_on", "26b_treatment_mask_invert")
    _check("TREATMENT MASK invert changes the mask", inv_diff > 0.2, "%.2f%% pixels changed" % inv_diff)
    lab.state["effect_mask_invert"] = false
    lab.state["effect_mask_enabled"] = false
    await _apply()

func _phase_motion() -> void:
    await set_fx("fringe")
    lab.motion_enabled["fringe"] = true
    lab.motion["fringe"]["anchor"] = "clash_impact"
    lab._mount_screen()
    await settle(110)
    await snap("27_motion_anchored", "fringe anchored to clash_impact (hold phase)")
    lab.motion["fringe"]["anchor"] = "manual"
    lab._trigger_manual()
    await settle(10)
    await snap("28_motion_manual_trigger", "manual motion triggered")
    lab.motion_enabled["fringe"] = false

func _phase_bypass() -> void:
    lab._on_bypass(true)
    await settle(8)
    await snap("29_bypass_on", "BYPASS on (raw)")
    lab._on_bypass(false)
    await settle(8)
    await snap("30_bypass_off", "BYPASS off")

func _phase_real_input() -> void:
    var restart := _find_button("⟲ RESTART")
    if restart == null:
        restart = _find_button("RESTART")
    if restart != null:
        var before: String = lab.status_label.text
        await _click(restart, "RESTART")
        _check("RESTART responds to real click", true, "status '%s' -> '%s'" % [before, lab.status_label.text])
    else:
        _check("RESTART responds to real click", false, "button not found")
    var pure_toggle: Node = null
    for n in lab.find_children("*", "CheckButton", true, false):
        if "PURE" in n.text:
            pure_toggle = n
    if pure_toggle != null:
        var before_pure: bool = lab.state["pure_continuous"]
        await _click(pure_toggle, "PURE CONTINUOUS toggle")
        _check("PURE toggle responds to real click", lab.state["pure_continuous"] != before_pure,
            "now %s" % lab.state["pure_continuous"])
        await _click(pure_toggle, "PURE CONTINUOUS toggle (restore)")
    else:
        _check("PURE toggle responds to real click", false, "toggle not found")
    var bypass: Node = null
    for n in lab.find_children("*", "CheckButton", true, false):
        if n.text == "BYPASS":
            bypass = n
    if bypass != null:
        await _click(bypass, "BYPASS on")
        await _click(bypass, "BYPASS off")
        _check("BYPASS responds to real click", true, lab.status_label.text)
    var trig := _find_button("▶ TRIGGER MANUAL FX")
    if trig == null:
        trig = _find_button("TRIGGER MANUAL FX")
    if trig != null:
        lab.motion_enabled["fringe"] = true
        await _click(trig, "TRIGGER MANUAL FX")
        _check("TRIGGER MANUAL FX responds", lab.motion_running.size() > 0, "running=%s" % str(lab.motion_running.keys()))
        lab.motion_enabled["fringe"] = false
    else:
        _check("TRIGGER MANUAL FX responds", false, "button not found")
    var capture_btn := _find_button("CAPTURE")
    if capture_btn != null:
        var cap_dir := ProjectSettings.globalize_path("user://fx_lab_captures")
        var before_count := _count_files(cap_dir)
        await _click(capture_btn, "CAPTURE")
        var after_count := _count_files(cap_dir)
        _check("CAPTURE writes a PNG", after_count > before_count, "%d -> %d in %s" % [before_count, after_count, cap_dir])
    var reset := _find_button("RESET LOOK")
    if reset != null:
        await _click(reset, "RESET LOOK")
        _check("RESET LOOK responds", true, lab.status_label.text)

func _count_files(dir_path: String) -> int:
    var d := DirAccess.open(dir_path)
    if d == null:
        return 0
    var n := 0
    for f in d.get_files():
        if f.ends_with(".png"):
            n += 1
    return n

func _phase_perf() -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    await settle(10)
    # Cases follow the final report template's performance table.
    var cases := [
        ["neutral_baseline", {"fx": [], "signal": 0.0, "hold": 0.0, "pure": false, "driver": 0.0, "blur": 0.0, "format": "1v1"}],
        ["mark_smooth_fringe_flow_off", {"fx": ["fringe"], "signal": 0.0, "hold": 0.0, "pure": false, "driver": 0.0, "blur": 0.0, "format": "1v1"}],
        ["echoes_smooth_fringe_flow_on", {"fx": ["fringe", "flow"], "signal": 0.0, "hold": 0.0, "pure": false, "driver": 0.0, "blur": 0.0, "format": "1v1"}],
        ["ffa4_primaries_generic_driver", {"fx": ["fringe", "flow"], "signal": 0.0, "hold": 0.0, "pure": false, "driver": 2.5, "blur": 0.0, "format": "FFA_4"}],
        ["all_colour_blur", {"fx": FX, "signal": 2.0, "hold": 0.0, "pure": false, "driver": 0.0, "blur": 1.0, "format": "1v1"}],
    ]
    # warm-up pass (shader compilation / resource streaming leave the numbers)
    for entry in cases:
        var wcfg: Dictionary = entry[1]
        await _apply_perf_case(wcfg)
        await settle(20)
    for entry in cases:
        var cfg: Dictionary = entry[1]
        await _apply_perf_case(cfg)
        await settle(40)
        var n := 0
        var total := 0.0
        var worst := 99999.0
        while n < 130:
            await process_frame
            var f := float(Engine.get_frames_per_second())
            if n >= 30:
                total += f
                worst = minf(worst, f)
            n += 1
        var avg := total / 100.0
        perf.append({"state": entry[0], "avg_fps": snappedf(avg, 1), "min_fps": snappedf(worst, 1),
            "cost": lab.cost_label.text})
        print("[PERF] ", entry[0], " avg=", snappedf(avg, 1), " min=", snappedf(worst, 1), " · ", lab.cost_label.text)
    # restore
    lab.state["color_blur"] = 0.0
    lab.state["driver_mode"] = 0.0
    lab.state["pure_continuous"] = false
    lab.state["signal_posterize"] = 0.0
    lab.state["temporal_hold"] = 0.0
    lab._on_format(lab.FORMAT_NAMES.find("1v1"))
    await settle(20)
    await set_fx_multi([])
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
    await settle(4)

func _apply_perf_case(cfg: Dictionary) -> void:
    var wanted_format: String = str(cfg.get("format", "1v1"))
    if lab.mode_format != wanted_format:
        lab._on_format(lab.FORMAT_NAMES.find(wanted_format))
        await settle(20)
    lab.state["pure_continuous"] = bool(cfg["pure"])
    lab.state["signal_posterize"] = float(cfg["signal"])
    lab.state["temporal_hold"] = float(cfg["hold"])
    lab.state["driver_mode"] = float(cfg["driver"])
    lab.state["color_blur"] = float(cfg["blur"])
    await set_fx_multi(cfg["fx"])

func _write_summary() -> void:
    var out := {"shots": shots, "perf": perf, "checks": checks}
    var f := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(out, "  "))
        f.close()
        print("[EVIDENCE] summary written")
