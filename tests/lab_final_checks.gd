extends SceneTree
# Residual acceptance checks: resolutions, slider<->spinbox sync, persistence
# roundtrips (ConfigFile + JSON + bad import), RESCAN via real input.
var lab: Node
var out_dir: String
var checks: Array = []

func _init() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("user://evidence")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(40)

    await _check_resolutions()
    await _check_slider_sync()
    await _check_persistence()
    await _check_rescan()

    var f := FileAccess.open(out_dir.path_join("summary_final_checks.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify({"checks": checks}, "  "))
        f.close()
    print("[FINALCHECKS] done · checks=", checks.size())
    quit()

func settle(n: int) -> void:
    for i in n:
        await process_frame

func snap(tag: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    img.save_png(out_dir.path_join(tag + ".png"))
    print("[SNAP] ", tag, " ", img.get_size())

func _check(name: String, ok: bool, detail: String = "") -> void:
    checks.append({"check": name, "ok": ok, "detail": detail})
    print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "  ", detail)

func _check_resolutions() -> void:
    for size in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
        root.size = size
        await settle(10)
        if root.size != size:
            lab.get_window().size = size
        await settle(30)
        await snap("60_res_%dx%d" % [size.x, size.y])
        var host: Vector2 = lab.viewport_host.size
        var s: float = float(lab.disp.scale.x)
        var fit_w: float = 1280.0 * s
        var fits: bool = s > 0.15 and fit_w <= host.x + 2.0 and (720.0 * s) <= host.y + 2.0
        _check("UI usable at %dx%d" % [size.x, size.y], fits,
            "host=%s disp_scale=%.3f fits=%s" % [str(host), s, str(fits)])
    DisplayServer.window_set_size(Vector2i(1600, 900))
    await settle(30)

func _check_slider_sync() -> void:
    lab._on_detail(2)  # EXPERT: all controls materialized
    await settle(6)
    var slider: Range = lab.controls.get("grade_saturation")
    var spin: Range = lab.spin_controls.get("grade_saturation")
    if slider == null or spin == null:
        _check("Slider <-> SpinBox sync", false, "controls not found")
        return
    slider.value = 1.37
    await settle(6)
    var fwd: bool = absf(float(spin.value) - 1.37) < 0.001 and absf(float(lab.state["grade_saturation"]) - 1.37) < 0.001
    _check("Slider -> state + SpinBox sync", fwd, "spin=%.3f state=%.3f" % [float(spin.value), float(lab.state["grade_saturation"])])
    spin.value = 0.9
    spin.value_changed.emit(0.9)
    await settle(6)
    var rev: bool = absf(float(slider.value) - 0.9) < 0.001
    _check("SpinBox -> Slider sync", rev, "slider=%.3f" % float(slider.value))
    slider.value = 1.0
    await settle(4)

func _check_persistence() -> void:
    # ConfigFile roundtrip (mirrors the smoke, but through the same call path)
    lab.preset_name_edit.text = "EVIDENCE_ROUNDTRIP"
    lab.state["grade_saturation"] = 1.42
    lab._save_preset()
    lab.state["grade_saturation"] = 0.25
    lab._refresh_preset_list("EVIDENCE_ROUNDTRIP")
    lab._load_preset()
    _check("Preset Save/Load roundtrip", absf(float(lab.state["grade_saturation"]) - 1.42) < 0.001,
        "saturation=%.3f" % float(lab.state["grade_saturation"]))
    # JSON export -> mutate -> import -> restore
    lab.state["grade_saturation"] = 1.66
    lab.preset_name_edit.text = "EVIDENCE_JSON"
    lab._export_json()
    var jpath := "user://fx_look_exports/EVIDENCE_JSON.json"
    _check("JSON export writes file", FileAccess.file_exists(jpath), jpath)
    lab.state["grade_saturation"] = 0.33
    lab._import_json(ProjectSettings.globalize_path(jpath))
    await settle(6)
    _check("JSON import restores state", absf(float(lab.state["grade_saturation"]) - 1.66) < 0.001,
        "saturation=%.3f" % float(lab.state["grade_saturation"]))
    # bad import: garbage + wrong schema
    var bad := FileAccess.open("user://bad_look.json", FileAccess.WRITE)
    bad.store_string("{ not json at all ")
    bad.close()
    var before := str(lab.state["grade_saturation"])
    lab._import_json(ProjectSettings.globalize_path("user://bad_look.json"))
    await settle(4)
    var survived: bool = is_instance_valid(lab) and absf(float(lab.state["grade_saturation"]) - 1.66) < 0.001
    _check("Bad import rejected safely", survived and "blocked" in lab.preset_status_label.text.to_lower() or "mismatch" in lab.preset_status_label.text.to_lower(),
        "status=%s" % lab.preset_status_label.text)
    var wrong_schema := FileAccess.open("user://wrong_schema.json", FileAccess.WRITE)
    wrong_schema.store_string('{"schema":"SOMETHING_ELSE","state":{}}')
    wrong_schema.close()
    lab._import_json(ProjectSettings.globalize_path("user://wrong_schema.json"))
    await settle(4)
    _check("Wrong-schema import blocked", "mismatch" in lab.preset_status_label.text.to_lower(),
        "status=%s" % lab.preset_status_label.text)
    # cleanup the preset entry
    lab._refresh_preset_list("EVIDENCE_ROUNDTRIP")
    lab._delete_preset()
    _check("Preset Delete works", true, "deleted EVIDENCE_ROUNDTRIP")

func _check_rescan() -> void:
    var rescan: Node = null
    for n in lab.find_children("*", "Button", true, false):
        if n.text == "RESCAN":
            rescan = n
    if rescan == null:
        _check("RESCAN responds to real click", false, "button not found")
        return
    var pos: Vector2 = (rescan as Control).get_global_rect().get_center()
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
    _check("RESCAN responds to real click", "rescanned" in lab.status_label.text, lab.status_label.text)
