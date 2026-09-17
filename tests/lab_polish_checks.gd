extends SceneTree
# ============================================================================
# Final-polish verification driver (researcher gates B / C / D / F)
#   B: FX time source determinism (PRESENTATION TIME vs FREE RUN)
#   C: conclusive Temporal Hold on Element Study (static imported PNG)
#   D: explicit Edge Mask proof + separate Treatment Mask proof
#   F: tab screenshots + contextual-disabling screenshot
# ============================================================================

var lab: Node
var out_dir: String
var checks: Array = []
var shots: Array = []

func _init() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("user://evidence")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(45)

    await _gate_b_time_source()
    await _gate_c_temporal_hold()
    await _gate_d_masks()
    await _gate_f_shots()

    var f := FileAccess.open(out_dir.path_join("summary_polish_checks.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify({"checks": checks, "shots": shots}, "  "))
        f.close()
    print("[POLISH] done · checks=", checks.size())
    quit()

# ---------------------------------------------------------------- helpers
func settle(n: int) -> void:
    for i in n:
        await process_frame

func snap(tag: String, note: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    var path := out_dir.path_join(tag + ".png")
    img.save_png(path)
    shots.append({"tag": tag, "note": note})
    print("[SNAP] ", tag)

func _check(name: String, ok: bool, detail: String = "") -> void:
    checks.append({"check": name, "ok": ok, "detail": detail})
    print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "  ", detail)

func diff_crop(a: String, b: String, crop: Rect2i) -> float:
    var pa := out_dir.path_join(a + ".png")
    var pb := out_dir.path_join(b + ".png")
    if not FileAccess.file_exists(pa) or not FileAccess.file_exists(pb):
        return -1.0
    var ia := Image.load_from_file(pa)
    var ib := Image.load_from_file(pb)
    ia = ia.get_region(crop)
    ib = ib.get_region(crop)
    var da := ia.get_data()
    var db := ib.get_data()
    var n := da.size()
    var changed := 0
    var i := 0
    while i < n:
        if absi(int(da[i]) - int(db[i])) > 6:
            changed += 1
        i += 4
    return 100.0 * float(changed) / float(n / 4)

func set_source(mode: int) -> void:
    lab._on_source_mode(mode)
    await settle(8)

func _set_tree_process(node: Node, on: bool) -> void:
    node.set_process(on)
    for child in node.get_children():
        _set_tree_process(child, on)

func set_time_source(name: String) -> void:
    lab._on_time_source(lab.TIME_SOURCES.find(name))
    await settle(4)

func seek_presentation(t: float, hold: bool) -> void:
    var screen = lab.screen
    if screen == null:
        return
    var tween = screen.get("_entry_tween")
    if tween == null or not (tween is Tween):
        return
    var tw := tween as Tween
    tw.pause()
    if tw.has_method("seek"):
        tw.seek(t)
    else:
        # this engine build has no Tween.seek: absolute jump emulation
        tw.stop()
        tw.play()
        tw.custom_step(maxf(t, 0.0001))
        tw.pause()
    await settle(2)

func resume_presentation() -> void:
    var screen = lab.screen
    if screen == null:
        return
    var tween = screen.get("_entry_tween")
    if tween is Tween:
        (tween as Tween).play()
    await settle(2)

func fx_on(names: Array) -> void:
    for f in ["dither", "fringe", "flow", "rgb"]:
        lab.state["fx_on"][f] = f in names
    lab._apply_fx()
    await settle(4)

# full-window capture region for the preview (window is 1600x900)
func preview_crop() -> Rect2i:
    return Rect2i(640, 60, 960, 760)

# ---------------------------------------------------------------- Gate B
func _gate_b_time_source() -> void:
    print("[GATE B] time source")
    lab._on_target_mode(lab.TARGET_MODES.find("ALL"))
    await fx_on(["fringe", "flow"])
    lab.state["fringe_coverage_mode"] = 0.0
    lab.state["fx_amount"]["flow"] = 1.0
    lab._apply_fx()
    await settle(10)
    # b1: PRESENTATION TIME — freeze the presentation clock at a fixed time:
    # with the clock pinned, later frames must render identically, and the
    # same timestamp after seeking away must render identically again.
    await set_time_source("PRESENTATION TIME")
    var screen = lab.screen
    if screen == null:
        _check("B: live screen present", false, "")
        return
    screen.set_process(false)              # freeze the presentation clock
    _set_tree_process(screen, false)       # and all stage sub-animations
    screen.set("_elapsed", 0.5)
    await settle(6)
    var t_direct: float = lab.shader_time
    _check("B: PRESENTATION drives shader time from the timeline clock", absf(t_direct - 0.5) < 0.02,
        "shader_time=%.3f with presentation pinned at 0.5" % t_direct)
    await snap("b1_pres_t0p5_first", "PRESENTATION pinned @0.5 first")
    await settle(24)                       # many frames later, same timestamp
    await snap("b1_pres_t0p5_again", "PRESENTATION pinned @0.5 after 24 frames")
    var d_same := diff_crop("b1_pres_t0p5_first", "b1_pres_t0p5_again", preview_crop())
    print("[INFO] live-screen pinned-time diff over 24 frames: %.3f%% (includes the stage's own TIME-driven animation, not the FX layer)" % d_same)
    # seek away (different timestamp) then back
    screen.set("_elapsed", 1.4)
    await settle(10)
    await snap("b1_pres_t1p4", "PRESENTATION pinned @1.4 (different look)")
    var d_other := diff_crop("b1_pres_t0p5_first", "b1_pres_t1p4", preview_crop())
    _check("B: a different presentation timestamp renders a different FX pattern", d_other > 1.0,
        "0.5 vs 1.4 diff %.2f%%" % d_other)
    screen.set("_elapsed", 0.5)
    await settle(10)
    await snap("b1_pres_t0p5_back", "PRESENTATION back @0.5 (seek away and back)")
    var d_back := diff_crop("b1_pres_t0p5_first", "b1_pres_t0p5_back", preview_crop())
    print("[INFO] live-screen seek away/back diff: %.3f%% (stage animation) " % d_back)
    # b1b: same assertions on the ELEMENT STUDY — element + FX only, no stage
    # animation, so frame identity is exact.
    lab._on_source_mode(1)
    await settle(10)
    var e_idx := 0
    for i in lab.custom_asset_paths.size():
        if "fighter_beauty_test" in lab.custom_asset_paths[i]:
            e_idx = i
    lab.custom_asset_picker.select(e_idx)
    lab._on_custom_asset(e_idx)
    await settle(12)
    var e_crop := Rect2i(660, 80, 900, 740)
    lab._transport_seek_to(0.7)
    await settle(8)
    await snap("b1b_elem_t0p7_first", "element study pinned @0.7 first")
    await settle(24)
    await snap("b1b_elem_t0p7_again", "element study pinned @0.7 after 24 frames")
    var e_same := diff_crop("b1b_elem_t0p7_first", "b1b_elem_t0p7_again", e_crop)
    _check("B: same presentation timestamp => identical FX render (element study)", e_same >= 0.0 and e_same < 0.05,
        "same-timestamp diff over 24 frames: %.3f%%" % e_same)
    lab._transport_seek_to(1.6)
    await settle(10)
    await snap("b1b_elem_t1p6", "element study pinned @1.6")
    var e_other := diff_crop("b1b_elem_t0p7_first", "b1b_elem_t1p6", e_crop)
    _check("B: a different timestamp renders a different pattern (element study)", e_other > 1.0,
        "0.7 vs 1.6 diff %.2f%%" % e_other)
    lab._transport_seek_to(0.7)
    await settle(10)
    await snap("b1b_elem_t0p7_back", "element study back @0.7 (seek away and back)")
    var e_back := diff_crop("b1b_elem_t0p7_first", "b1b_elem_t0p7_back", e_crop)
    _check("B: seek away and back => identical render (element study)", e_back >= 0.0 and e_back < 0.05,
        "seek away/back diff %.3f%%" % e_back)
    lab._on_source_mode(0)
    await settle(8)
    screen.set_process(true)               # resume the live presentation
    _set_tree_process(screen, true)
    await settle(4)
    # b2: FREE RUN is unaffected by seeking (lab clock advances independently)
    await set_time_source("FREE RUN")
    await settle(20)
    var free_before: float = lab.shader_time
    await seek_presentation(0.5, true)
    await settle(20)
    var free_after: float = lab.shader_time
    _check("B: FREE RUN unaffected by seek (no jump to presentation time)",
        free_after > free_before and absf(free_after - 0.5) > 0.08,
        "free %.3f -> %.3f while presentation sat at 0.5" % [free_before, free_after])
    await snap("b2_free_before", "FREE RUN before seek")
    await seek_presentation(0.5, true)
    await settle(20)
    await snap("b2_free_after_seek", "FREE RUN after seek (time advanced, not jumped)")
    var d_free := diff_crop("b2_free_before", "b2_free_after_seek", preview_crop())
    _check("B: FREE RUN advances independently of the presentation", d_free > 0.0 and d_free < 60.0,
        "diff over seek %.2f%% (should be a small live advance, not a timeline jump)" % d_free)
    await resume_presentation()
    # b3: FREE RUN keeps running
    await snap("b3_free_run_t1", "FREE RUN advancing")
    await settle(16)
    await snap("b3_free_run_t2", "FREE RUN advancing (later)")
    var d_adv := diff_crop("b3_free_run_t1", "b3_free_run_t2", preview_crop())
    _check("B: FREE RUN advances", d_adv > 0.05, "trailing diff %.2f%%" % d_adv)
    # b4: summary string reports the source
    var readout: String = lab.processing_label.text
    _check("B: processing summary reports the time source", "FREE RUN" in readout, "")
    # b5: persistence roundtrip through ConfigFile
    lab.preset_name_edit.text = "POLISH_TSRC"
    lab._save_preset()
    await set_time_source("PRESENTATION TIME")
    lab._refresh_preset_list("POLISH_TSRC")
    lab._load_preset()
    await settle(4)
    _check("B: ConfigFile roundtrip preserves time source", lab.time_source == "FREE RUN",
        "loaded source=%s" % lab.time_source)
    lab._delete_preset()
    # b6: JSON export/import roundtrip
    await set_time_source("FREE RUN")
    lab.preset_name_edit.text = "POLISH_JSON"
    lab._export_json()
    await set_time_source("PRESENTATION TIME")
    lab._import_json(ProjectSettings.globalize_path("user://fx_look_exports/POLISH_JSON.json"))
    await settle(6)
    _check("B: JSON roundtrip preserves time source", lab.time_source == "FREE RUN",
        "imported source=%s" % lab.time_source)
    # b7: A/B snapshot roundtrip
    var snap_a: Dictionary = lab._snapshot()
    await set_time_source("PRESENTATION TIME")
    lab._apply_snapshot(snap_a)
    await settle(4)
    _check("B: A/B snapshot preserves time source", lab.time_source == "FREE RUN",
        "snapshot source=%s" % lab.time_source)
    await fx_on([])

# ---------------------------------------------------------------- Gate C
func _gate_c_temporal_hold() -> void:
    print("[GATE C] temporal hold (element study, static imported PNG)")
    # element study with the imported fighter PNG (rich silhouette for fringes)
    lab._on_source_mode(1)
    await settle(8)
    var idx := 0
    for i in lab.custom_asset_paths.size():
        if "fighter_beauty_test" in lab.custom_asset_paths[i]:
            idx = i
    lab.custom_asset_picker.select(idx)
    lab._on_custom_asset(idx)
    await settle(12)
    await set_time_source("FREE RUN")
    await fx_on(["fringe", "flow"])
    lab.state["fringe_coverage_mode"] = 0.0
    lab.state["fx_amount"]["fringe"] = 1.0
    lab.state["fx_amount"]["flow"] = 1.0
    lab._apply_fx()
    await settle(30)
    var crop := Rect2i(660, 80, 900, 740)
    # c1: motion with hold OFF
    var moving := await _series_rate("c1_hold_off", 8, crop)
    _check("C: flow+fringe visibly moving with Hold OFF", moving > 30.0, "%.0f%% frames changing" % moving)
    # c2: hold=8 — frames inside one 125 ms bucket are identical, next bucket changes
    lab.state["temporal_hold"] = 8.0
    lab._apply_fx()
    await settle(24)
    var bucket: int = int(floor(lab.free_run_time * 8.0))
    await _wait_bucket(bucket + 1)  # enter a clean bucket
    await snap("c2_hold_inbucket_a", "hold=8 · inside bucket a")
    await settle(2)
    await snap("c2_hold_inbucket_b", "hold=8 · inside bucket a (2 frames later)")
    var in_diff := diff_crop("c2_hold_inbucket_a", "c2_hold_inbucket_b", crop)
    await _wait_bucket(bucket + 2)  # next bucket
    await snap("c2_hold_nextbucket", "hold=8 · next bucket")
    var out_diff := diff_crop("c2_hold_inbucket_b", "c2_hold_nextbucket", crop)
    _check("C: frames inside one Hold bucket render identically", in_diff >= 0.0 and in_diff < 0.05,
        "in-bucket diff %.3f%%" % in_diff)
    _check("C: frame across the next Hold bucket changes", out_diff > 0.2,
        "next-bucket diff %.3f%%" % out_diff)
    # c3: PURE CONTINUOUS restores continuous motion
    lab._on_pure(true)
    await settle(10)
    var pure_rate := await _series_rate("c3_pure_on", 8, crop)
    _check("C: PURE CONTINUOUS restores continuous motion", pure_rate > 30.0, "%.0f%% frames changing" % pure_rate)
    # c4: pure bypasses hold but keeps the source
    _check("C: PURE keeps the selected source (no silent change)", lab.time_source == "FREE RUN",
        "source=%s" % lab.time_source)
    lab._on_pure(false)
    lab.state["temporal_hold"] = 0.0
    lab._apply_fx()
    lab._on_source_mode(0)
    await settle(10)
    await fx_on([])

func _wait_bucket(target: int) -> void:
    var guard := 0
    while floor(lab.free_run_time * 8.0) < target and guard < 600:
        await process_frame
        guard += 1

func _series_rate(prefix: String, count: int, crop: Rect2i) -> float:
    var changed := 0
    var prev := ""
    for i in count:
        var tag := "%s_%02d" % [prefix, i]
        await snap(tag, "series frame %d" % i)
        if i > 0:
            var d := diff_crop(prev, tag, crop)
            if d > 0.25:
                changed += 1
        prev = tag
    var rate: float = 100.0 * float(changed) / float(count - 1)
    print("[SERIES] ", prefix, " rate=", snappedf(rate, 1), "%")
    return rate

# ---------------------------------------------------------------- Gate D
func _gate_d_masks() -> void:
    print("[GATE D] masks")
    lab._on_target_mode(lab.TARGET_MODES.find("ALL"))
    await fx_on(["fringe"])
    lab.state["fringe_coverage_mode"] = 0.0
    lab._apply_fx()
    await settle(6)
    var edge_mask := ""
    var treat_mask := ""
    for p in lab.mask_paths:
        if "edge" in p and edge_mask == "":
            edge_mask = p
        if "treatment" in p and treat_mask == "":
            treat_mask = p
    if edge_mask == "" or treat_mask == "":
        _check("D: masks present", false, "missing mask assets")
        return
    # d1: edge mask loaded flag + texture asserted on ALL targeted materials
    lab.state["edge_source_mode"] = 3.0
    lab.edge_mask_path = edge_mask
    lab._apply_fx()
    await settle(4)
    var loaded := 0
    var textured := 0
    for key in lab.materials.keys():
        var m: ShaderMaterial = lab.materials[key]
        if float(m.get_shader_parameter("custom_edge_mask_loaded")) > 0.5:
            loaded += 1
        if m.get_shader_parameter("custom_edge_mask_tex") != null:
            textured += 1
    _check("D: custom edge mask loaded flag on all targets", loaded == lab.materials.size(),
        "%d/%d" % [loaded, lab.materials.size()])
    _check("D: custom edge mask texture bound on all targets", textured == lab.materials.size(),
        "%d/%d" % [textured, lab.materials.size()])
    # d2: ALPHA vs CUSTOM MASK rendered difference
    lab.state["edge_source_mode"] = 2.0
    lab._apply_fx()
    await settle(6)
    await snap("d2_edge_alpha", "EDGE SOURCE=ALPHA + LUMA")
    lab.state["edge_source_mode"] = 3.0
    lab._apply_fx()
    await settle(6)
    await snap("d2_edge_custom", "EDGE SOURCE=CUSTOM EDGE MASK")
    var d_edge := diff_crop("d2_edge_alpha", "d2_edge_custom", preview_crop())
    _check("D: ALPHA vs CUSTOM MASK produce a rendered difference", d_edge > 1.0,
        "%.2f%% pixels changed (threshold 1%%)" % d_edge)
    lab.state["edge_source_mode"] = 2.0
    # d3: treatment mask enable/load/invert
    lab.state["effect_mask_enabled"] = true
    lab.treatment_mask_path = treat_mask
    lab._apply_fx()
    await settle(6)
    var t_loaded := 0
    for key in lab.materials.keys():
        var m: ShaderMaterial = lab.materials[key]
        if float(m.get_shader_parameter("treatment_mask_loaded")) > 0.5 and float(m.get_shader_parameter("effect_mask_enabled")) > 0.5:
            t_loaded += 1
    _check("D: treatment mask enabled+loaded on all targets", t_loaded == lab.materials.size(),
        "%d/%d" % [t_loaded, lab.materials.size()])
    await snap("d3_treatment_on", "TREATMENT MASK on")
    lab.state["effect_mask_invert"] = true
    lab._apply_fx()
    await settle(6)
    await snap("d3_treatment_inverted", "TREATMENT MASK inverted")
    var d_inv := diff_crop("d3_treatment_on", "d3_treatment_inverted", preview_crop())
    _check("D: treatment mask invert changes the render", d_inv > 0.2, "%.2f%% pixels changed" % d_inv)
    lab.state["effect_mask_invert"] = false
    lab.state["effect_mask_enabled"] = false
    lab._apply_fx()
    await settle(4)
    await fx_on([])

func ctl_disabled(key: String) -> bool:
    if not lab.controls.has(key):
        return false
    var c = lab.controls[key]
    if c is BaseButton:
        return c.disabled
    if c is OptionButton:
        return c.disabled
    if c is Slider or c is SpinBox:
        return not c.editable
    return false

# ---------------------------------------------------------------- Gate F
func _gate_f_shots() -> void:
    print("[GATE F] screenshots")
    var tabs := lab.find_children("*", "TabContainer", true, false)
    if tabs.is_empty():
        _check("F: tabs found", false, "")
        return
    var order := ["LOOK", "MOTION", "LOOKS", "DIAGNOSTICS"]
    for name in order:
        tabs[0].current_tab = order.find(name)
        await settle(6)
        await snap("f_tab_" + name.to_lower(), "tab " + name)
    tabs[0].current_tab = 0
    # contextual disabling shot: dither off => dither pattern controls disabled
    lab._on_detail(2)
    await settle(4)
    lab.state["fx_on"]["dither"] = false
    lab._update_enabled_states()
    await settle(4)
    _check("F: dither pattern controls disable when Colour Dither is OFF", ctl_disabled("dither_mode"),
        "dither_mode disabled=%s" % ctl_disabled("dither_mode"))
    _check("F: treatment controls disabled while mask OFF", ctl_disabled("effect_mask_threshold"),
        "threshold disabled=%s" % ctl_disabled("effect_mask_threshold"))
    var ts = lab.controls.get("time_source")
    _check("F: time source control stays enabled (never a dead control)",
        ts != null and not ts.disabled, "")
    await snap("f_disabled_state", "contextual disabling: dither OFF")
    # header shot (look name + dirty + time source prominent)
    lab._mark_dirty()
    await settle(4)
    await snap("f_header_status", "header: LOOK name/dirty + TIME source")
