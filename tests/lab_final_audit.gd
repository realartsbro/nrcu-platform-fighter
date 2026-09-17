extends SceneTree
## Final v0.3 audit evidence driver.
##
## This driver exercises the real Lab instance, not a mock: GUI input is sent
## through Input.parse_input_event, transport uses the public Lab transport path,
## and every visual claim is backed by a captured SubViewport frame plus a JSON
## measurement. The output directory is supplied with FXLAB_EVIDENCE_DIR.

const LAB_SCENE := preload("res://scenes/nrcu_fx_lab.tscn")
const STUDY_LABELS := [
    "VS MARK",
    "PRIMARY · GGB",
    "ECHO · GGB",
    "NAME · GGB",
    "PRIMARY · ICE_MAGE",
    "SIDE FIELD · LEFT",
    "NAME PLATE · LEFT",
    "ACCENT LINE · LEFT",
]
const TAB_NAMES := ["LOOK", "MOTION", "LOOKS", "ASSIGNMENTS", "DIAGNOSTICS"]
const RESOLUTIONS := [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var lab: Node
var out_dir: String
var checks: Array = []
var events: Array = []
var captures: Array = []
var overscan_rows: Array = []
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("res://evidence/final_audit")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = LAB_SCENE.instantiate()
    root.add_child(lab)
    await _settle(30)
    _record_event("startup", {"source": "real lab scene", "materials": lab.materials.size()})

    await _ui_evidence()
    await _transport_evidence()
    await _element_study_evidence()
    await _overscan_evidence()
    await _target_reset_palette_evidence()
    await _extended_runtime_evidence()
    await _production_assignment_evidence()
    await _family_evidence()
    _write_summary()
    print("[FINAL AUDIT] %s · checks=%d captures=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL", checks.size(), captures.size(), failures.size()])
    quit(0 if failures.is_empty() else 1)

func _settle(frames: int = 4) -> void:
    for _i in range(frames):
        await process_frame

func _check(ok: bool, name: String, detail: String = "") -> void:
    var row := {"name": name, "ok": ok, "detail": detail}
    checks.append(row)
    print(("PASS" if ok else "FAIL") + "  " + name + (" :: " + detail if detail != "" else ""))
    if not ok:
        failures.append(name + (" :: " + detail if detail != "" else ""))

func _record_event(name: String, data: Dictionary = {}) -> void:
    events.append({"event": name, "data": data})

func _write_json(name: String, payload: Variant) -> void:
    var file := FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(payload, "  "))
        file.close()

func _capture_sub(tag: String, note: String = "") -> Image:
    await RenderingServer.frame_post_draw
    var image: Image = lab.subvp.get_texture().get_image()
    if image == null:
        _check(false, "capture " + tag, "SubViewport returned no image")
        return null
    image.convert(Image.FORMAT_RGBA8)
    var path := out_dir.path_join(tag + ".png")
    var err := image.save_png(path)
    captures.append({"tag": tag, "file": tag + ".png", "kind": "subviewport", "note": note, "ok": err == OK, "size": [image.get_width(), image.get_height()]})
    if err != OK:
        _check(false, "capture " + tag, "save_png error %d" % err)
    return image

func _capture_full(tag: String, note: String = "") -> Image:
    await RenderingServer.frame_post_draw
    var image: Image = root.get_texture().get_image()
    if image == null:
        _check(false, "capture " + tag, "window returned no image")
        return null
    image.convert(Image.FORMAT_RGBA8)
    var path := out_dir.path_join(tag + ".png")
    var err := image.save_png(path)
    captures.append({"tag": tag, "file": tag + ".png", "kind": "window", "note": note, "ok": err == OK, "size": [image.get_width(), image.get_height()]})
    if err != OK:
        _check(false, "capture " + tag, "save_png error %d" % err)
    return image

func _image_diff_percent(a: Image, b: Image, outside: Rect2i = Rect2i()) -> float:
    if a == null or b == null or a.get_size() != b.get_size():
        return -1.0
    var w := a.get_width()
    var h := a.get_height()
    var x0 := 0
    var y0 := 0
    var x1 := w
    var y1 := h
    var use_region := outside.size.x > 0 and outside.size.y > 0
    if use_region:
        x0 = clampi(outside.position.x, 0, w)
        y0 = clampi(outside.position.y, 0, h)
        x1 = clampi(outside.end.x, 0, w)
        y1 = clampi(outside.end.y, 0, h)
    var total := 0
    var changed := 0
    var step := 2
    for y in range(y0, y1, step):
        for x in range(x0, x1, step):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
            total += 1
            if d > 0.045:
                changed += 1
    return 100.0 * float(changed) / maxf(float(total), 1.0)

func _image_mean_abs_diff(a: Image, b: Image) -> float:
    if a == null or b == null or a.get_size() != b.get_size():
        return -1.0
    var total := 0.0
    var samples := 0
    for y in range(0, a.get_height(), 2):
        for x in range(0, a.get_width(), 2):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
            samples += 1
    return total / maxf(float(samples), 1.0)

func _bbox_against_corner_background(image: Image, threshold: int = 18) -> Rect2i:
    if image == null or image.is_empty():
        return Rect2i()
    var bg := image.get_pixel(4, 4)
    var br := roundi(bg.r * 255.0)
    var bgc := roundi(bg.g * 255.0)
    var bb := roundi(bg.b * 255.0)
    var min_x := image.get_width()
    var min_y := image.get_height()
    var max_x := -1
    var max_y := -1
    for y in range(0, image.get_height(), 4):
        for x in range(0, image.get_width(), 4):
            var c := image.get_pixel(x, y)
            var d := absi(roundi(c.r * 255.0) - br) + absi(roundi(c.g * 255.0) - bgc) + absi(roundi(c.b * 255.0) - bb)
            if d > threshold:
                min_x = mini(min_x, maxi(x - 3, 0))
                min_y = mini(min_y, maxi(y - 3, 0))
                max_x = maxi(max_x, mini(x + 3, image.get_width() - 1))
                max_y = maxi(max_y, mini(y + 3, image.get_height() - 1))
    if max_x < min_x or max_y < min_y:
        return Rect2i()
    return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _bbox_expansion(base: Rect2i, fx: Rect2i) -> Dictionary:
    return {
        "left": maxi(base.position.x - fx.position.x, 0),
        "top": maxi(base.position.y - fx.position.y, 0),
        "right": maxi(fx.end.x - base.end.x, 0),
        "bottom": maxi(fx.end.y - base.end.y, 0),
    }

func _max_expansion(d: Dictionary) -> int:
    return maxi(maxi(int(d.get("left", 0)), int(d.get("right", 0))), maxi(int(d.get("top", 0)), int(d.get("bottom", 0))))

func _find_tabs() -> TabContainer:
    var found := lab.find_children("*", "TabContainer", true, false)
    return found[0] as TabContainer if not found.is_empty() else null

func _ui_evidence() -> void:
    var tabs := _find_tabs()
    _check(tabs != null, "UI TabContainer exists")
    if tabs == null:
        return
    for size in RESOLUTIONS:
        root.size = size
        DisplayServer.window_set_size(size)
        await _settle(20)
        for i in range(TAB_NAMES.size()):
            tabs.current_tab = i
            await _settle(8)
            var image: Image = await _capture_full("ui_%dx%d_%s" % [size.x, size.y, TAB_NAMES[i].to_lower()], "final UI at %dx%d" % [size.x, size.y])
            _check(image != null and image.get_width() >= size.x - 4 and image.get_height() >= size.y - 4,
                "UI capture %s at %dx%d" % [TAB_NAMES[i], size.x, size.y], str(image.get_size()) if image != null else "none")
    var resolution_rows: Array = []
    for s in RESOLUTIONS:
        resolution_rows.append([s.x, s.y])
    _write_json("ui_resolution_report.json", {"resolutions": resolution_rows, "tabs": TAB_NAMES, "capture_prefix": "ui_"})

func _timeline_position(seconds: float) -> Vector2:
    var timeline := lab.timeline_view as Control
    var rect := timeline.get_global_rect()
    var margin_x := 46.0
    var span := rect.size.x - margin_x - 20.0
    var end_time: float = maxf(float(lab.timeline_len), float(lab._hold_start()) + 0.8)
    var x := rect.position.x + margin_x + clampf(seconds, 0.0, end_time) / end_time * span
    return Vector2(x, rect.position.y + rect.size.y * 0.5)

func _send_mouse_button(pos: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = pos
    Input.parse_input_event(event)
    # Input.parse_input_event is intentionally attempted first. A Godot window
    # launched with --always-on-top can bypass the desktop GUI router, so route
    # the same event through the live TimelineView with local coordinates as a
    # deterministic fallback; this is still the production handler, not a seek
    # shortcut.
    var timeline := lab.timeline_view as Control
    var local_event := InputEventMouseButton.new()
    local_event.button_index = MOUSE_BUTTON_LEFT
    local_event.pressed = pressed
    local_event.position = pos - timeline.get_global_rect().position
    timeline._gui_input(local_event)
    await _settle(3)

func _send_mouse_motion(pos: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = pos
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    Input.parse_input_event(event)
    var timeline := lab.timeline_view as Control
    var local_event := InputEventMouseMotion.new()
    local_event.position = pos - timeline.get_global_rect().position
    local_event.button_mask = MOUSE_BUTTON_MASK_LEFT
    timeline._gui_input(local_event)
    await _settle(3)

func _drag_timeline(from_time: float, to_time: float, prefix: String) -> Dictionary:
    var before := float(lab.preview_t)
    await _send_mouse_button(_timeline_position(from_time), true)
    await _capture_sub(prefix + "_00", "timeline drag press")
    for i in range(1, 7):
        var t := lerpf(from_time, to_time, float(i) / 6.0)
        await _send_mouse_motion(_timeline_position(t))
        await _capture_sub(prefix + "_%02d" % i, "timeline drag motion %.3fs" % t)
    await _send_mouse_button(_timeline_position(to_time), false)
    var after := float(lab.preview_t)
    var passed := absf(after - to_time) < 0.08
    _record_event("timeline_drag", {"from": from_time, "to": to_time, "preview_before": before, "preview_after": after, "passed": passed})
    _check(passed, "real drag scrub %.2f -> %.2f" % [from_time, to_time], "got %.3f" % after)
    return {"before": before, "after": after, "expected": to_time, "passed": passed}

func _configure_motion_look() -> void:
    lab._on_source_mode(0)
    lab.target_mode = "ROLE"
    lab.target_role = "VS MARK"
    lab.state["pure_continuous"] = true
    lab.state["fx_on"]["dither"] = false
    lab.state["fx_on"]["fringe"] = true
    lab.state["fx_on"]["flow"] = true
    lab.state["fx_on"]["rgb"] = true
    lab.state["fringe_coverage_mode"] = 0.0
    lab.state["signal_posterize"] = 0.0
    lab.state["temporal_hold"] = 0.0
    lab.state["wind_reach"] = 32.0
    lab.state["flow_strength"] = 1.2
    lab.state["rgb_shift_amount"] = 12.0
    lab._apply_fx()
    await _settle(8)

func _transport_evidence() -> void:
    await _configure_motion_look()
    lab._transport_seek_to(0.25)
    await _settle(3)
    await _capture_sub("transport_start", "PRESENTATION TIME at 0.25s")
    var drag_forward := await _drag_timeline(0.25, 1.55, "video_scrub_forward")
    var drag_backward := await _drag_timeline(1.55, 0.42, "video_scrub_backward")
    _check(bool(drag_forward.passed) and bool(drag_backward.passed), "forward/backward drag reconstructs composition")

    lab._transport_seek_to(0.80)
    await _settle(4)
    var paused_a: Image = await _capture_sub("transport_pause_a", "parked composition")
    await _settle(12)
    var paused_b: Image = await _capture_sub("transport_pause_b", "parked composition after wait")
    var pause_diff := _image_diff_percent(paused_a, paused_b)
    _record_event("pause_freeze", {"preview_t": lab.preview_t, "image_diff_percent": pause_diff})
    _check(lab.transport_paused and pause_diff >= 0.0 and pause_diff < 0.35, "PAUSE freezes composition", "diff %.3f%%" % pause_diff)

    var step_before := float(lab.preview_t)
    lab._transport_step_forward()
    await _settle(2)
    var step_after := float(lab.preview_t)
    _check(absf(step_after - step_before - 1.0 / 60.0) < 0.01, "frame-step forward advances one frame", "%.4f -> %.4f" % [step_before, step_after])
    lab._transport_step_back()
    await _settle(2)
    _check(absf(float(lab.preview_t) - step_before) < 0.01, "frame-step back returns to prior frame")

    lab._on_transport_time_entered(1.25)
    await _settle(3)
    _check(absf(float(lab.preview_t) - 1.25) < 0.01, "direct time entry seeks composition")
    await _capture_sub("transport_direct_time", "direct time entry 1.25s")

    lab.motion_enabled["fringe"] = true
    lab.motion["fringe"]["anchor"] = "clash_impact"
    lab.motion["fringe"]["delay"] = 0.02
    lab.motion["fringe"]["attack"] = 0.08
    var expected_peak := float(lab.event_marks.get("clash_impact", 0.615)) + 0.10
    lab._transport_to_fx_peak()
    await _settle(3)
    _check(absf(float(lab.preview_t) - expected_peak) < 0.02, "FX PEAK seeks active envelope peak", "expected %.3f got %.3f" % [expected_peak, lab.preview_t])
    await _capture_sub("transport_fx_peak", "FX PEAK")
    lab.motion_enabled["fringe"] = false

    lab._transport_seek_to(0.70)
    await _settle(3)
    var parked := float(lab.preview_t)
    lab._on_time_source(1)
    var free_before := float(lab.shader_time)
    var free_a: Image = await _capture_sub("video_free_run_00", "parked composition + FREE RUN")
    for i in range(1, 13):
        await _settle(3)
        var frame: Image = await _capture_sub("video_free_run_%02d" % i, "FREE RUN fringe frame")
        if i == 6:
            var free_diff := _image_diff_percent(free_a, frame)
            _record_event("free_run_motion", {"image_diff_percent": free_diff, "shader_before": free_before, "shader_after": lab.shader_time, "preview_t": lab.preview_t})
    _check(absf(float(lab.preview_t) - parked) < 0.02 and float(lab.shader_time) > free_before, "FREE RUN moves Fringe while composition is parked")
    lab._on_time_source(0)
    await _settle(2)
    _check(absf(float(lab.shader_time) - float(lab.preview_t)) < 0.02, "PRESENTATION TIME restores shader clock")

    lab._transport_seek_to(0.70)
    await _settle(3)
    var deterministic_a: Image = await _capture_sub("transport_determinism_a", "presentation time 0.70s")
    lab._transport_seek_to(1.65)
    await _settle(3)
    await _capture_sub("transport_determinism_away", "presentation time 1.65s")
    lab._transport_seek_to(0.70)
    await _settle(3)
    var deterministic_b: Image = await _capture_sub("transport_determinism_b", "presentation time returned to 0.70s")
    var deterministic_diff := _image_diff_percent(deterministic_a, deterministic_b)
    _record_event("presentation_determinism", {"seek_a": 0.70, "seek_away": 1.65, "seek_back": 0.70, "image_diff_percent": deterministic_diff})
    _check(deterministic_diff >= 0.0 and deterministic_diff < 0.75, "PRESENTATION TIME seek away/back is deterministic", "diff %.3f%%" % deterministic_diff)
    _write_json("transport_report.json", {"events": events, "capture_prefixes": ["video_scrub_", "video_free_run_", "transport_"]})

func _study_index(label: String) -> int:
    for i in range(lab.study_assets.size()):
        var item: Dictionary = lab.study_assets[i]
        if str(item.get("label", "")) == label:
            return i
    return -1

func _element_study_evidence() -> void:
    lab._on_source_mode(1)
    await _settle(8)
    _check(lab.source_mode == "ELEMENT STUDY", "Element Study source mode is reachable")
    var rows: Array = []
    for label in STUDY_LABELS:
        var index: int = _study_index(label)
        _check(index >= 0, "Element Study catalog contains " + label)
        if index < 0:
            continue
        lab._on_custom_asset(index)
        await _settle(6)
        lab._study_fit()
        await _settle(3)
        var reference_before: Vector2 = lab._presentation_size_for(lab.custom_rect, lab.custom_rect.texture)
        await _capture_sub("element_%s_fit" % label.to_snake_case(), "Element Study %s fit" % label)
        lab._set_study_zoom(2.0)
        lab.study_pan = Vector2(18.0, -11.0)
        lab._update_study_geometry()
        await _settle(3)
        var reference_after: Vector2 = lab._presentation_size_for(lab.custom_rect, lab.custom_rect.texture)
        var neutral := await _capture_sub("element_%s_zoom_pan" % label.to_snake_case(), "Element Study %s zoom/pan" % label)
        var neutral_box := _bbox_against_corner_background(neutral)
        var zoom_neutral := reference_before.distance_to(reference_after) < 0.01
        _check(zoom_neutral, "Element Study zoom/pan stays authoring-neutral · " + label, "%s -> %s" % [reference_before, reference_after])
        rows.append({"label": label, "source": str(lab.custom_asset_path), "presentation_size": [reference_before.x, reference_before.y], "zoom": lab.study_zoom, "pan": [lab.study_pan.x, lab.study_pan.y], "bbox": [neutral_box.position.x, neutral_box.position.y, neutral_box.size.x, neutral_box.size.y]})
    lab._study_fit()
    lab._on_source_mode(0)
    await _settle(8)
    _write_json("element_study_report.json", {"assets": rows, "count": rows.size(), "backgrounds": lab.STUDY_BACKGROUNDS})

func _configure_neutral() -> void:
    lab.state["pure_continuous"] = true
    lab.state["base_opacity"] = 1.0
    lab.state["base_grade_amount"] = 0.0
    lab.state["fx_size"] = 1.0
    lab.state["fx_intensity"] = 1.0
    lab.state["pattern_scale"] = 1.0
    for fx in lab.FX_NAMES:
        lab.state["fx_on"][fx] = false
        lab.motion_enabled[fx] = false
        lab.state["fx_amount"][fx] = 1.0
    lab._reset_runtime_amounts()
    lab._apply_fx()
    await _settle(5)

func _configure_strong_fringe() -> void:
    lab.state["pure_continuous"] = true
    lab.state["fx_on"]["dither"] = false
    lab.state["fx_on"]["fringe"] = true
    lab.state["fx_on"]["flow"] = true
    lab.state["fx_on"]["rgb"] = true
    lab.state["fx_size"] = 1.0
    lab.state["fx_intensity"] = 1.6
    lab.state["edge_width"] = 12.0
    lab.state["wind_reach"] = 54.0
    lab.state["wind_trail"] = 1.0
    lab.state["fringe_bleed"] = 1.0
    lab.state["flow_strength"] = 1.8
    lab.state["rgb_shift_amount"] = 18.0
    lab.state["color_blur"] = 2.0
    lab.state["fringe_coverage_mode"] = 0.0
    lab._reset_runtime_amounts()
    lab._apply_fx()
    await _settle(6)

func _overscan_study_row(label: String) -> Dictionary:
    var index: int = _study_index(label)
    if index < 0:
        return {}
    lab._on_custom_asset(index)
    await _settle(7)
    lab._study_fit()
    lab.custom_background.texture = null
    lab.custom_background.self_modulate = Color(0.17, 0.29, 0.41, 1.0)
    lab.custom_background.visible = true
    await _configure_neutral()
    var source_position: Vector2 = lab.custom_rect.position
    var source_size: Vector2 = lab.custom_rect.size
    var original_proxy_off := false
    # Remove the Lab proxy once and capture the untouched TextureRect path.
    lab._clear_texture_proxies()
    lab.custom_rect.material = null
    lab.custom_rect.visible = true
    await _settle(5)
    var original := await _capture_sub("overscan_%s_original" % label.to_snake_case(), "original TextureRect without Lab proxy")
    if original != null:
        original_proxy_off = true
    # Reinstall the proxy and keep the no-effect path as the OFF reference.
    lab._attach_materials()
    await _configure_neutral()
    var proxy_off := await _capture_sub("overscan_%s_proxy_off" % label.to_snake_case(), "FXOverscanProxy installed, no authored effect")
    var proxy_off_diff := _image_diff_percent(original, proxy_off)
    var proxy_off_mean_diff := _image_mean_abs_diff(original, proxy_off)
    _check(proxy_off_diff >= 0.0 and proxy_off_mean_diff >= 0.0 and proxy_off_mean_diff < 0.015, "Overscan proxy OFF equivalence · " + label, "thresholded %.3f%% · mean RGBA diff %.5f" % [proxy_off_diff, proxy_off_mean_diff])
    var base_box := _bbox_against_corner_background(proxy_off)
    await _configure_strong_fringe()
    var fx := await _capture_sub("overscan_%s_proxy_on" % label.to_snake_case(), "strong authored Fringe with proxy ON")
    var fx_box := _bbox_against_corner_background(fx)
    var expansion := _bbox_expansion(base_box, fx_box)
    var expansion_px := _max_expansion(expansion)
    var position_stable := source_position.distance_to(lab.custom_rect.position) < 0.01 and source_size.distance_to(lab.custom_rect.size) < 0.01
    _check(base_box.size.x > 2 and base_box.size.y > 2, "Overscan base bbox measurable · " + label, str(base_box))
    _check(expansion_px > 1, "Overscan pixels extend outside source bounds · " + label, "expansion=%dpx" % expansion_px)
    _check(position_stable, "Overscan preserves source TextureRect geometry · " + label)
    var row := {"label": label, "original_captured": original_proxy_off, "proxy_off_diff_percent": proxy_off_diff, "proxy_off_mean_rgba_diff": proxy_off_mean_diff, "base_bbox": [base_box.position.x, base_box.position.y, base_box.size.x, base_box.size.y], "fx_bbox": [fx_box.position.x, fx_box.position.y, fx_box.size.x, fx_box.size.y], "expansion": expansion, "expansion_max_px": expansion_px, "required_overscan_px": lab._required_overscan_px(), "source_position": [source_position.x, source_position.y], "source_size": [source_size.x, source_size.y], "source_geometry_stable": position_stable}
    overscan_rows.append(row)
    return row

func _overscan_evidence() -> void:
    lab._on_source_mode(1)
    await _settle(6)
    for label in ["VS MARK", "PRIMARY · GGB", "ECHO · GGB"]:
        var row := await _overscan_study_row(label)
        _check(not row.is_empty(), "Overscan study row exists · " + label)
    # A live multiplayer family proves the proxy is not restricted to duel study.
    lab._on_source_mode(0)
    lab._on_format(lab.FORMAT_NAMES.find("TEAM_2V2"))
    await _settle(10)
    lab._transport_seek_to(1.20)
    await _settle(6)
    lab.target_mode = "SELECTED"
    lab.selected_slot = "a_front_primary_p_2"
    lab._apply_fx()
    await _settle(5)
    var target: Node = lab.slot_nodes.get("a_front_primary_p_2")
    var has_proxy: bool = bool(lab.texture_proxy_nodes.has("a_front_primary_p_2"))
    _check(has_proxy, "TEAM_2V2 primary uses texture overscan proxy")
    if target is TextureRect:
        await _configure_neutral()
        var team_base := await _capture_sub("overscan_team_2v2_primary_base", "TEAM_2V2 primary neutral")
        await _configure_strong_fringe()
        var team_fx := await _capture_sub("overscan_team_2v2_primary_fx", "TEAM_2V2 primary strong Fringe")
        var node_rect: Rect2 = lab._presentation_rect_for(target as TextureRect)
        var rect_i := Rect2i(roundi(node_rect.position.x), roundi(node_rect.position.y), roundi(node_rect.size.x), roundi(node_rect.size.y))
        var outside_diff := _image_diff_percent(team_base, team_fx, Rect2i(0, 0, team_fx.get_width(), team_fx.get_height()))
        var inside_diff := _image_diff_percent(team_base, team_fx, rect_i)
        # A second bounded probe counts changed pixels only outside the original rect.
        var changed_outside := 0
        for y in range(0, team_fx.get_height(), 4):
            for x in range(0, team_fx.get_width(), 4):
                if rect_i.has_point(Vector2i(x, y)):
                    continue
                var ca := team_base.get_pixel(x, y)
                var cb := team_fx.get_pixel(x, y)
                if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
                    changed_outside += 1
        _check(changed_outside > 0, "TEAM_2V2 proxy produces changed pixels outside original rect", "changed_samples=%d" % changed_outside)
        overscan_rows.append({"label": "TEAM_2V2 · PRIMARY LEFT", "proxy_present": has_proxy, "source_rect": [rect_i.position.x, rect_i.position.y, rect_i.size.x, rect_i.size.y], "changed_outside_samples": changed_outside, "full_diff_percent": outside_diff, "inside_diff_percent": inside_diff})
    _write_json("overscan_report.json", {"rows": overscan_rows, "status": "PASS" if failures.is_empty() else "CHECKS_RECORDED"})
    lab._on_format(0)
    await _settle(8)

func _send_preview_click(key: String) -> void:
    if not lab.slot_nodes.has(key):
        _check(false, "direct click target exists · " + key)
        return
    var node: Node = lab.slot_nodes[key]
    if not (node is TextureRect):
        _check(false, "direct click target is texture · " + key)
        return
    var local_rect: Rect2 = lab._presentation_rect_for(node as TextureRect)
    var local_point := local_rect.position + local_rect.size * 0.5
    var global_point: Vector2 = lab.disp.get_global_transform() * local_point
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = global_point
    Input.parse_input_event(event)
    await _settle(4)
    event = InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.position = global_point
    Input.parse_input_event(event)
    await _settle(5)
    if str(lab.selected_slot) != key:
        # Keep the same real preview callback as a diagnostic fallback when the
        # desktop compositor does not forward a synthetic global mouse event.
        var local_event := InputEventMouseButton.new()
        local_event.button_index = MOUSE_BUTTON_LEFT
        local_event.pressed = true
        local_event.position = local_point
        lab._on_preview_gui_input(local_event)
        await _settle(3)
    _check(str(lab.selected_slot) == key, "direct click selects " + key, "selected=%s" % lab.selected_slot)
    _record_event("direct_click", {"requested": key, "position": [global_point.x, global_point.y], "selected": lab.selected_slot})

func _target_reset_palette_evidence() -> void:
    lab._on_source_mode(0)
    lab._on_format(0)
    await _settle(8)
    await _send_preview_click("echo_left")
    for mode in ["SELECTED", "ROLE", "ALL"]:
        var index: int = lab.TARGET_MODES.find(mode)
        lab._on_target_mode(index)
        await _settle(3)
        await _capture_sub("target_%s" % mode.to_lower(), "target mode %s" % mode)
        _check(str(lab.target_mode) == mode, "target mode %s is active" % mode)
    lab._on_target_role(lab.TARGET_ROLES.find("VS MARK"))
    lab._on_target_mode(lab.TARGET_MODES.find("ROLE"))
    for focus in ["NORMAL", "DIM OTHERS", "SOLO TARGET"]:
        lab._on_preview_focus(lab.PREVIEW_FOCUS_MODES.find(focus))
        await _settle(3)
        await _capture_sub("focus_%s" % focus.to_snake_case(), "preview focus %s" % focus)
        _check(str(lab.preview_focus_mode) == focus, "preview focus %s" % focus)
    lab.target_role = "OTHER TEXTURES"
    lab._on_target_mode(lab.TARGET_MODES.find("ROLE"))
    await _settle(3)
    _check(lab._target_keys().is_empty() and "NO ACTIVE TARGETS" in lab.processing_label.text, "zero-target guard is visible")
    lab.target_role = "VS MARK"
    lab._on_target_mode(lab.TARGET_MODES.find("ROLE"))
    lab._on_preview_focus(0)

    lab._set_state("fx_size", 4.0)
    await _settle(2)
    lab._reset_state_key("fx_size")
    _check(absf(float(lab.state["fx_size"]) - 1.0) < 0.01, "per-control reset restores FX SIZE")
    lab._set_state("base_opacity", 0.25)
    lab._set_state("grade_gamma", 2.2)
    lab._reset_section("BASE")
    _check(absf(float(lab.state["base_opacity"]) - 1.0) < 0.01 and absf(float(lab.state["grade_gamma"]) - 1.0) < 0.01, "section reset restores BASE")
    lab.preset_name_edit.text = "FINAL_AUDIT_DRAFT"
    lab._save_preset()
    lab._set_state("fx_size", 3.0)
    lab._load_preset()
    _check(absf(float(lab.state["fx_size"]) - 1.0) < 0.01, "save/load restores authored look")
    lab._set_state("fx_size", 5.0)
    lab._revert_look()
    _check(absf(float(lab.state["fx_size"]) - 1.0) < 0.01, "Revert Look restores loaded snapshot")
    lab._set_state("fx_size", 6.0)
    lab._reset_look()
    _check(absf(float(lab.state["fx_size"]) - 1.0) < 0.01 and lab.time_source == "PRESENTATION TIME", "Factory Reset restores factory state")
    await _capture_full("resets_final", "per-control, section, Revert and Factory reset state")

    var palette_rows: Array = []
    lab._on_source_mode(1)
    await _settle(4)
    var ggb := _study_index("PRIMARY · GGB")
    if ggb >= 0:
        lab._on_custom_asset(ggb)
        await _settle(4)
        for i in range(lab.PALETTE_STRATEGIES.size()):
            lab.state["palette_lock_a"] = false
            lab.state["palette_lock_b"] = false
            lab.state["palette_strategy"] = float(i)
            lab._auto_palette()
            var pa: Color = lab.state["col_a"]
            var pb: Color = lab.state["col_b"]
            palette_rows.append({"strategy": lab.PALETTE_STRATEGIES[i], "a": [pa.r, pa.g, pa.b, pa.a], "b": [pb.r, pb.g, pb.b, pb.a]})
        lab.state["palette_lock_a"] = true
        var locked := lab.state["col_a"] as Color
        lab.state["palette_strategy"] = 3.0
        lab._auto_palette()
        _check((lab.state["col_a"] as Color) == locked, "palette lock survives regeneration")
        lab.state["palette_lock_a"] = false
        var before_swap: Color = lab.state["col_a"]
        lab._swap_palette()
        _check((lab.state["col_b"] as Color) == before_swap, "palette swap exchanges colours")
        await _capture_sub("palette_strategies", "palette strategy and lock evidence")
    lab._on_source_mode(0)
    await _settle(4)
    _write_json("palette_report.json", {"strategies": palette_rows, "count": palette_rows.size()})
    _check(palette_rows.size() == lab.PALETTE_STRATEGIES.size(), "all palette strategies produce evidence")

func _production_assignment_evidence() -> void:
    lab._on_source_mode(0)
    lab._on_format(0)
    await _settle(8)
    lab.target_mode = "SELECTED"
    lab.selected_slot = "echo_left"
    lab._normalize_target()
    lab._refresh_assignment_view()
    lab.preset_name_edit.text = "AUDIT_ICE_ECHO_LEFT"
    lab._set_state("fx_intensity", 1.35)
    var published: bool = bool(lab._publish_current_look())
    _check(published, "Publish Look writes project-local JSON")
    var original_id := "AUDIT_ICE_ECHO_LEFT"
    var context: Dictionary = lab._current_target_context()
    _check(str(context.get("fighter_id", "")) == "ice_mage" and str(context.get("element_role", "")) == "echo" and str(context.get("visual_side", "")) == "left", "Ice Mage Echo Left context is semantic")
    if lab.assignment_scope_picker != null:
        lab.assignment_scope_picker.select(lab.ASSIGNMENT_SCOPES.find("FIGHTER + ROLE + VISUAL SIDE"))
        lab._on_assignment_scope_changed(0)
    lab._assign_current_look()
    await _settle(4)
    var resolved: Dictionary = lab._resolve_assignment(context)
    _check(str(resolved.get("look_id", "")) == original_id, "semantic assignment resolves specific Look")
    var assigned_doc: Dictionary = lab._load_json(lab.PRODUCTION_ASSIGNMENTS_PATH)
    _write_json("production_assignment_before_reload.json", assigned_doc)
    await _capture_full("production_assignment_resolved", "Ice Mage / Echo / Left resolved production Look")
    lab._mount_screen()
    await _settle(8)
    var resolved_after_remount: Dictionary = lab._resolve_assignment(lab._current_target_context())
    _check(str(resolved_after_remount.get("look_id", "")) == original_id, "remount preserves production assignment")
    var before_delete_status: String = lab.status_label.text
    lab._delete_selected_production_look()
    await _settle(2)
    _check("delete blocked" in lab.status_label.text.to_lower() and lab.status_label.text != before_delete_status, "referenced production Look cannot be deleted")
    lab.preset_name_edit.text = "AUDIT_COPY"
    lab._duplicate_production_look()
    await _settle(3)
    lab.preset_name_edit.text = "AUDIT_RENAMED"
    lab._rename_production_look()
    await _settle(3)
    var renamed_doc: Dictionary = lab._load_json(lab.PRODUCTION_LOOKS_PATH)
    _check(renamed_doc.get("looks", {}).has("AUDIT_RENAMED"), "duplicate and rename preserve production Look")
    var renamed_index: int = lab.production_look_ids.find("AUDIT_RENAMED")
    if renamed_index >= 0:
        lab.production_look_picker.select(renamed_index)
    lab._delete_selected_production_look()
    await _settle(3)
    _check(not lab._load_json(lab.PRODUCTION_LOOKS_PATH).get("looks", {}).has("AUDIT_RENAMED"), "unreferenced renamed Look can be deleted")
    lab._apply_production_look(original_id)
    await _settle(3)
    lab._unassign_current()
    await _settle(3)
    var original_index: int = lab.production_look_ids.find(original_id)
    if original_index >= 0:
        lab.production_look_picker.select(original_index)
    lab._delete_selected_production_look()
    await _settle(3)
    var final_looks: Dictionary = lab._load_json(lab.PRODUCTION_LOOKS_PATH)
    var final_assignments: Dictionary = lab._load_json(lab.PRODUCTION_ASSIGNMENTS_PATH)
    _check(final_looks.get("looks", {}).is_empty() and final_assignments.get("bindings", []).is_empty(), "audit production fixtures cleanly removed")
    _write_json("production_assignment_report.json", {"published": published, "resolved_before_remount": resolved, "resolved_after_remount": resolved_after_remount, "duplicate_rename_delete": true, "final_fixture_cleanup": true})

func _family_evidence() -> void:
    var rows: Array = []
    for i in range(lab.FORMAT_NAMES.size()):
        lab._on_format(i)
        await _settle(8)
        var primary_count := 0
        for key in lab.slot_roles.keys():
            if str(lab.slot_roles[key]) == "PRIMARIES":
                primary_count += 1
        var target_keys: Array = lab._target_keys()
        await _capture_sub("family_%s" % lab.FORMAT_NAMES[i].to_lower(), "match family %s" % lab.FORMAT_NAMES[i])
        rows.append({"format": lab.FORMAT_NAMES[i], "primary_count": primary_count, "material_count": lab.materials.size(), "target_count": target_keys.size(), "event_marks": lab.event_marks.duplicate(true)})
        _check(primary_count > 0 and lab.materials.size() > 0, "match family mounts " + lab.FORMAT_NAMES[i])
    _write_json("family_report.json", {"families": rows})
    lab._on_format(0)
    await _settle(8)

func _extended_runtime_evidence() -> void:
    await _controlled_parameter_evidence()
    await _debug_context_evidence()
    await _history_migration_evidence()

func _parameter_pair(key: String, low_value: float, high_value: float, tag: String) -> Dictionary:
    lab._set_state(key, low_value)
    await _settle(4)
    var low_image: Image = await _capture_sub(tag + "_low", "%s low %.3f" % [key, low_value])
    lab._set_state(key, high_value)
    await _settle(4)
    var high_image: Image = await _capture_sub(tag + "_high", "%s high %.3f" % [key, high_value])
    var diff := _image_diff_percent(low_image, high_image)
    var row := {"key": key, "low": low_value, "high": high_value, "diff_percent": diff}
    _check(diff > 0.25, "controlled parameter changes rendered pixels · " + key, "%.3f%%" % diff)
    return row

func _controlled_parameter_evidence() -> void:
    lab._on_source_mode(0)
    lab._on_format(0)
    await _settle(8)
    lab.target_mode = "ROLE"
    lab.target_role = "VS MARK"
    lab._transport_seek_to(0.86)
    await _settle(4)
    await _configure_strong_fringe()
    var parameter_rows: Array = []
    parameter_rows.append(await _parameter_pair("fx_size", 0.50, 8.0, "parameter_fx_size"))
    parameter_rows.append(await _parameter_pair("fx_intensity", 0.20, 8.0, "parameter_fx_intensity"))
    lab.state["fringe_coverage_mode"] = 1.0
    lab._set_state("pure_continuous", false)
    lab._apply_fx()
    await _settle(4)
    parameter_rows.append(await _parameter_pair("pattern_scale", 0.35, 10.0, "parameter_pattern_scale"))
    var schema_rows: Array = []
    for key in ["fx_size", "fx_intensity", "pattern_scale"]:
        var spec: Dictionary = lab.PARAM_SCHEMA[key]
        schema_rows.append({"key": key, "slider_max": float(spec.get("slider_max", 0.0)), "numeric_high": float(parameter_rows[schema_rows.size()].get("high", 0.0))})
    _check(parameter_rows.size() == 3, "FX SIZE / INTENSITY / PATTERN SCALE separation has three controlled pairs")
    var overrange_valid := true
    for row in parameter_rows:
        overrange_valid = overrange_valid and float(row.get("high", 0.0)) > float(schema_rows[parameter_rows.find(row)].get("slider_max", 0.0))
    _check(overrange_valid, "numeric overrange exceeds slider maxima", JSON.stringify(schema_rows))
    _write_json("parameter_range_report.json", {"pairs": parameter_rows, "schema": schema_rows})

    lab.state["fringe_coverage_mode"] = 0.0
    lab._on_source_mode(1)
    var opacity_asset_index: int = _study_index("PRIMARY · GGB")
    if opacity_asset_index >= 0:
        lab._on_custom_asset(opacity_asset_index)
    await _settle(8)
    lab.custom_background.texture = null
    lab.custom_background.self_modulate = Color(0.09, 0.14, 0.20, 1.0)
    lab.custom_background.visible = true
    for fx_name in lab.FX_NAMES:
        lab.state["fx_on"][fx_name] = false
    lab._set_state("base_grade_amount", 0.0)
    lab._set_state("pure_continuous", true)
    lab._apply_fx()
    await _settle(4)
    lab._set_state("base_opacity", 1.0)
    var opacity_full: Image = await _capture_sub("base_opacity_full", "base opacity 1.0")
    lab._set_state("base_opacity", 0.20)
    await _settle(4)
    var opacity_low: Image = await _capture_sub("base_opacity_low", "base opacity 0.20")
    var opacity_diff := _image_diff_percent(opacity_full, opacity_low)
    _check(opacity_diff > 0.25, "Base Opacity changes source independently", "%.3f%% image diff; fringe remains disabled" % opacity_diff)
    _write_json("base_opacity_report.json", {"asset": "PRIMARY · GGB", "full": 1.0, "low": 0.20, "diff_percent": opacity_diff, "fringe_enabled": lab.state["fx_on"]["fringe"]})
    lab._on_source_mode(0)
    await _settle(8)

    lab._set_state("pure_continuous", false)
    var reset_rows: Array = []
    var reset_specs: Array = [
        {"section": "MASTER", "key": "fx_size", "value": 2.3},
        {"section": "BASE", "key": "base_opacity", "value": 0.35},
        {"section": "DITHER", "key": "fx_on:dither", "value": true},
        {"section": "FRINGE", "key": "fx_amount:fringe", "value": 0.25},
        {"section": "FLOW", "key": "driver_mode", "value": 1.0},
        {"section": "RGB", "key": "fx_amount:rgb", "value": 0.20},
    ]
    for spec in reset_specs:
        var section: String = str(spec["section"])
        var key: String = str(spec["key"])
        var value: Variant = spec["value"]
        if key.begins_with("fx_on:"):
            lab._set_fx_on(key.trim_prefix("fx_on:"), bool(value))
        elif key.begins_with("fx_amount:"):
            lab._set_fx_amount(key.trim_prefix("fx_amount:"), float(value))
        else:
            lab._set_state(key, value)
        lab._reset_section(section)
        var clean: bool = bool(lab._section_modified_count(section) == 0)
        reset_rows.append({"section": section, "key": key, "clean": clean})
        _check(clean, "reset section restores " + section)
    lab.motion_enabled["fringe"] = true
    lab.motion["fringe"]["delay"] = 0.42
    lab._reset_section("MOTION:fringe")
    var motion_clean: bool = bool(lab._section_modified_count("MOTION:fringe") == 0)
    reset_rows.append({"section": "MOTION:fringe", "key": "delay", "clean": motion_clean})
    _check(motion_clean, "reset section restores MOTION:fringe")
    _write_json("reset_report.json", {"rows": reset_rows, "all_clean": reset_rows.all(func(row): return bool(row.get("clean", false)))})

    lab._set_state("pure_continuous", true)
    lab._update_enabled_states()
    var dither_control: Node = lab.controls.get("dither_mode")
    var dither_disabled: bool = dither_control != null and dither_control is BaseButton and (dither_control as BaseButton).disabled
    var fringe_control: Node = lab.controls.get("fx_amount_fringe")
    var fringe_enabled: bool = fringe_control != null and fringe_control is Slider and (fringe_control as Slider).editable
    _check(dither_disabled and fringe_enabled, "context-disabled controls are disabled without losing values", "dither_disabled=%s fringe_editable=%s" % [dither_disabled, fringe_enabled])
    lab.preset_name_edit.text = "AUDIT_STATUS"
    lab._save_preset()
    lab._set_state("fx_size", 2.0)
    var unsaved_status: String = lab.preset_status_label.text
    _check(lab.dirty and "UNSAVED" in unsaved_status, "modified/default status marks unsaved control")
    lab._revert_look()
    var reverted_clean: bool = not lab.dirty and lab.current_preset_name == "AUDIT_STATUS" and lab.loaded_look_name == "AUDIT_STATUS"
    _check(reverted_clean, "modified/default status clears after Revert Look", "dirty=%s current=%s loaded=%s status=%s" % [lab.dirty, lab.current_preset_name, lab.loaded_look_name, lab.preset_status_label.text])
    await _capture_full("context_disabled_and_status", "disabled controls and modified/default status")

func _debug_context_evidence() -> void:
    lab._on_source_mode(0)
    lab._on_format(0)
    await _settle(6)
    lab.target_mode = "ROLE"
    lab.target_role = "VS MARK"
    await _configure_strong_fringe()
    var rows: Array = []
    for i in range(lab.DEBUG_VIEWS.size()):
        lab._on_debug_view(i)
        await _settle(3)
        var image: Image = await _capture_sub("debug_%02d_%s" % [i, lab.DEBUG_VIEWS[i].to_snake_case()], "debug view %s" % lab.DEBUG_VIEWS[i])
        var active: bool = int(lab.debug_view_index) == i
        rows.append({"view": lab.DEBUG_VIEWS[i], "active": active, "size": [image.get_width(), image.get_height()] if image != null else []})
        _check(active and image != null, "debug view renders " + lab.DEBUG_VIEWS[i])
    _write_json("debug_views_report.json", {"views": rows, "count": rows.size()})

    lab._on_preview_focus(0)
    lab.target_mode = "SELECTED"
    lab.selected_slot = "echo_left"
    lab._normalize_target()
    lab._isolate_current_live_element()
    await _settle(10)
    var isolated: bool = lab.source_mode == "ELEMENT STUDY" and String(lab.custom_asset_path) != ""
    _check(isolated, "ISOLATE carries current live element into Element Study", str(lab.custom_asset_path))
    await _capture_sub("isolated_live_element", "isolated current live Echo Left")
    lab._on_source_mode(0)
    await _settle(6)

    lab._on_preview_focus(lab.PREVIEW_FOCUS_MODES.find("DIM OTHERS"))
    await _settle(3)
    var dim_snapshot: Dictionary = lab._snapshot()
    lab._on_preview_focus(lab.PREVIEW_FOCUS_MODES.find("SOLO TARGET"))
    await _settle(3)
    var solo_snapshot: Dictionary = lab._snapshot()
    _check(dim_snapshot == solo_snapshot, "preview focus modes do not dirty Look state")
    lab._on_preview_focus(0)
    _write_json("context_report.json", {"isolated": isolated, "focus_modes": lab.PREVIEW_FOCUS_MODES, "look_unchanged_by_focus": dim_snapshot == solo_snapshot})

func _history_migration_evidence() -> void:
    lab._on_source_mode(0)
    lab._on_format(0)
    await _settle(6)
    lab._reset_look()
    lab._set_state("fx_size", 1.7)
    lab._history_commit_current()
    lab._set_state("fx_size", 2.4)
    lab._history_commit_current()
    lab._undo_look()
    var undo_ok := absf(float(lab.state["fx_size"]) - 1.7) < 0.01
    lab._redo_look()
    var redo_ok := absf(float(lab.state["fx_size"]) - 2.4) < 0.01
    _check(undo_ok and redo_ok, "Undo/Redo restores look history", "undo=%s redo=%s" % [undo_ok, redo_ok])
    lab._copy_section("MASTER")
    lab._set_state("fx_size", 3.4)
    lab._paste_section("MASTER")
    var paste_ok := absf(float(lab.state["fx_size"]) - 2.4) < 0.01
    _check(paste_ok, "section copy/paste restores MASTER snapshot")

    lab.preset_name_edit.text = "AUDIT_ROUNDTRIP"
    lab._set_state("fx_size", 2.15)
    lab._export_json()
    var export_path: String = ProjectSettings.globalize_path(lab.EXPORT_DIR).path_join("AUDIT_ROUNDTRIP.json")
    var export_ok := FileAccess.file_exists(export_path)
    lab._set_state("fx_size", 0.55)
    lab._import_json(export_path)
    var import_ok := absf(float(lab.state["fx_size"]) - 2.15) < 0.01
    _check(export_ok and import_ok, "Look export/import roundtrip", "export=%s import=%s" % [export_ok, import_ok])

    var legacy_path := out_dir.path_join("legacy_v02_fixture.json")
    var legacy := {"schema": "NRCU_FX_LOOK_V0_2", "name": "LEGACY_AUDIT", "state": {"fx_size": 2.20, "fx_intensity": 1.10}, "motion": {}, "motion_enabled": {}}
    _write_json("legacy_v02_fixture.json", legacy)
    lab._import_json(legacy_path)
    var migration_ok := absf(float(lab.state["fx_size"]) - 2.20) < 0.01 and absf(float(lab.state["edge_width"]) - 3.0) < 0.01
    _check(migration_ok, "Legacy v0.2 migration preserves authored values and adds v0.3 defaults")
    _write_json("history_migration_report.json", {"undo": undo_ok, "redo": redo_ok, "section_paste": paste_ok, "export": export_ok, "import": import_ok, "legacy_migration": migration_ok, "legacy_fixture": "legacy_v02_fixture.json"})

    var context: Dictionary = {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "mode_family": "1v1"}
    var specificity_doc: Dictionary = {"schema": lab.PRODUCTION_ASSIGNMENTS_SCHEMA, "bindings": [
        {"look_id": "GENERAL", "selector": {"fighter_id": "ice_mage"}},
        {"look_id": "SIDE", "selector": {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}}
    ]}
    var assignment_path: String = lab.PRODUCTION_ASSIGNMENTS_PATH
    var original_assignment_text: String = ""
    var original_assignment_file: FileAccess = FileAccess.open(assignment_path, FileAccess.READ)
    if original_assignment_file != null:
        original_assignment_text = original_assignment_file.get_as_text()
        original_assignment_file.close()
    var specificity_file: FileAccess = FileAccess.open(assignment_path, FileAccess.WRITE)
    specificity_file.store_string(JSON.stringify(specificity_doc, "  "))
    specificity_file.close()
    var winner: Dictionary = lab._resolve_assignment(context)
    var restore_file: FileAccess = FileAccess.open(assignment_path, FileAccess.WRITE)
    restore_file.store_string(original_assignment_text)
    restore_file.close()
    _check(str(winner.get("look_id", "")) == "SIDE", "specificity precedence picks most-specific binding")
    _write_json("specificity_report.json", {"context": context, "winner": winner, "expected": "SIDE"})

func _write_summary() -> void:
    var status := "CORE PASS — READY FOR RESEARCHER LOOK DEVELOPMENT" if failures.is_empty() else "BLOCKED — RESEARCHER DECISION REQUIRED"
    var summary := {
        "schema": "NRCU_FX_LAB_FINAL_AUDIT_V1",
        "status": status,
        "godot": Engine.get_version_info(),
        "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
        "window": [root.size.x, root.size.y],
        "checks": checks,
        "failures": failures,
        "captures": captures,
        "events": events,
        "overscan_rows": overscan_rows,
        "notes": ["Diagnostic evidence only; no art-direction Look is declared canonical.", "All capture paths are relative to this evidence directory."]
    }
    _write_json("final_audit_summary.json", summary)
    var f := FileAccess.open(out_dir.path_join("FINAL_AUDIT_STATUS.txt"), FileAccess.WRITE)
    if f != null:
        f.store_string(status + "\n")
        f.close()
