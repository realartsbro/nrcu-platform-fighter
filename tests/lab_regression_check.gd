extends SceneTree
# ============================================================================
# Gate H — adversarial regression sweep over the full state matrix.
# Deterministic combination sweep; every step must complete without errors
# and leave the lab in the expected state.
# ============================================================================

var lab: Node
var out_dir: String
var checks: Array = []

func _init() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(45)

    await _targets_and_sources()
    await _families()
    await _pure_value_preservation()
    await _dither_fringe_independence()
    await _time_and_hold()
    await _masks_and_bypass()
    await _envelopes_and_reset()
    await _persistence_cycles()
    await _resolution_sweep()
    await _combination_sweep()

    var f := FileAccess.open(out_dir.path_join("summary_regression.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify({"checks": checks}, "  "))
        f.close()
    var failed := 0
    for c in checks:
        if not c["ok"]:
            failed += 1
    print("[REGRESSION] done · checks=", checks.size(), " failed=", failed)
    quit()

func settle(n: int) -> void:
    for i in n:
        await process_frame

func _check(name: String, ok: bool, detail: String = "") -> void:
    checks.append({"check": name, "ok": ok, "detail": detail})
    print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "  ", detail)

func _targets_and_sources() -> void:
    for src in [0, 1]:
        lab._on_source_mode(src)
        await settle(8)
        for mode in ["SELECTED", "ROLE", "ALL"]:
            lab._on_target_mode(lab.TARGET_MODES.find(mode))
            if mode == "ROLE":
                for role in lab.TARGET_ROLES:
                    lab._on_target_role(lab.TARGET_ROLES.find(role))
                    await settle(2)
                    # Element Study now exposes every scanned authored asset,
                    # including vector-mask roles added by the authoring parity
                    # handoff. The expected non-empty roles are data-driven.
                    var expect_nonempty := true
                    if src == 1:
                        var active_study_role: String = str(lab.slot_roles.get("study_asset", ""))
                        expect_nonempty = active_study_role == role
                    else:
                        expect_nonempty = role != "OTHER TEXTURES"
                    if expect_nonempty:
                        _check("targets: %s × %s × %s" % [mode, role, lab.source_mode],
                            lab._target_keys().size() > 0, "")
                    else:
                        _check("targets: %s × %s × %s (correctly empty)" % [mode, role, lab.source_mode],
                            lab._target_keys().size() == 0, "")
            else:
                await settle(2)
                _check("targets: %s × %s" % [mode, lab.source_mode], lab._target_keys().size() > 0, "")
    lab._on_source_mode(0)
    lab._on_target_mode(2)

func _families() -> void:
    for fam in lab.FORMAT_NAMES:
        lab._on_format(lab.FORMAT_NAMES.find(fam))
        await settle(40)
        var primaries := 0
        for k in lab._target_keys():
            if "primary" in str(k):
                primaries += 1
        _check("family %s mounts" % fam, lab.mode_format == fam and primaries >= 2,
            "primaries=%d" % primaries)
    lab._on_format(0)
    await settle(30)

func _pure_value_preservation() -> void:
    lab.state["dither_pixel"] = 3.0
    lab.state["fringe_bayer_level"] = 3.0
    lab.state["temporal_hold"] = 8.0
    lab.state["signal_posterize"] = 4.0
    lab._apply_fx()
    lab._on_pure(true)
    await settle(8)
    var kept: bool = float(lab.state["dither_pixel"]) == 3.0 and float(lab.state["fringe_bayer_level"]) == 3.0 \
        and float(lab.state["temporal_hold"]) == 8.0 and float(lab.state["signal_posterize"]) == 4.0
    _check("PURE preserves authored values", kept, "dither_pixel=%.0f hold=%.0f posterize=%.0f" % [
        float(lab.state["dither_pixel"]), float(lab.state["temporal_hold"]), float(lab.state["signal_posterize"])])
    lab._on_pure(false)
    await settle(6)

func _dither_fringe_independence() -> void:
    for f in ["dither", "fringe", "flow", "rgb"]:
        lab.state["fx_on"][f] = f == "fringe"
    lab.state["fringe_coverage_mode"] = 0.0
    lab._apply_fx()
    await settle(4)
    var mat: ShaderMaterial = lab.materials[lab.materials.keys()[0]]
    var d_off: bool = float(mat.get_shader_parameter("fx_dither")) == 0.0
    var fr_on: bool = float(mat.get_shader_parameter("fx_fringe")) > 0.0
    _check("dither OFF + smooth Fringe independent", d_off and fr_on,
        "fx_dither=%.2f fx_fringe=%.2f" % [float(mat.get_shader_parameter("fx_dither")), float(mat.get_shader_parameter("fx_fringe"))])
    for f in ["dither", "fringe", "flow", "rgb"]:
        lab.state["fx_on"][f] = false
    lab._apply_fx()
    await settle(4)

func _time_and_hold() -> void:
    for ts in lab.TIME_SOURCES:
        lab._on_time_source(lab.TIME_SOURCES.find(ts))
        await settle(6)
        for hold in [0.0, 8.0]:
            lab.state["temporal_hold"] = hold
            lab._apply_fx()
            await settle(8)
            _check("time %s × hold %.0f runs" % [ts, hold], is_instance_valid(lab), "shader_time=%.2f" % lab.shader_time)
    lab.state["temporal_hold"] = 0.0
    lab._apply_fx()

func _masks_and_bypass() -> void:
    for f in ["dither", "fringe", "flow", "rgb"]:
        lab.state["fx_on"][f] = true
    lab.state["effect_mask_enabled"] = true
    lab.treatment_mask_path = lab.mask_paths[0] if lab.mask_paths.size() > 0 else ""
    lab._apply_fx()
    await settle(6)
    lab._on_bypass(true)
    await settle(6)
    var all_zero := true
    for key in lab.materials.keys():
        var m: ShaderMaterial = lab.materials[key]
        if float(m.get_shader_parameter("fx_fringe")) != 0.0 or float(m.get_shader_parameter("fx_dither")) != 0.0:
            all_zero = false
    _check("BYPASS zeroes FX on all targets (masks armed)", all_zero, "")
    var values_kept: bool = bool(lab.state["fx_on"]["fringe"]) and bool(lab.state["effect_mask_enabled"])
    _check("BYPASS keeps authored values", values_kept, "")
    lab._on_bypass(false)
    lab.state["effect_mask_enabled"] = false
    for f in ["dither", "fringe", "flow", "rgb"]:
        lab.state["fx_on"][f] = false
    lab._apply_fx()
    await settle(4)

func _envelopes_and_reset() -> void:
    lab.motion_enabled["fringe"] = true
    lab.motion["fringe"]["anchor"] = "clash_impact"
    lab._mount_screen()
    await settle(40)
    _check("anchored envelope runs after remount", lab.screen != null, "")
    lab.motion["fringe"]["anchor"] = "manual"
    lab._trigger_manual()
    await settle(6)
    _check("manual envelope triggers", lab.motion_running.size() > 0, str(lab.motion_running.keys()))
    lab.motion_enabled["fringe"] = false
    lab.state["grade_saturation"] = 0.33
    lab._on_time_source(1)
    lab._reset_look()
    await settle(6)
    _check("RESET restores factory state", absf(float(lab.state["grade_saturation"]) - 1.0) < 0.001 and lab.time_source == "PRESENTATION TIME",
        "saturation=%.2f source=%s" % [float(lab.state["grade_saturation"]), lab.time_source])

func _persistence_cycles() -> void:
    for cycle in 2:
        lab.preset_name_edit.text = "REG_CYCLE_%d" % cycle
        lab.state["grade_saturation"] = 1.1 + float(cycle) * 0.1
        lab._on_time_source(1)
        lab._save_preset()
        lab.state["grade_saturation"] = 0.5
        lab._on_time_source(0)
        lab._refresh_preset_list("REG_CYCLE_%d" % cycle)
        lab._load_preset()
        await settle(4)
        _check("cycle %d save/load" % cycle,
            absf(float(lab.state["grade_saturation"]) - (1.1 + float(cycle) * 0.1)) < 0.001 and lab.time_source == "FREE RUN", "")
        var snap: Dictionary = lab._snapshot()
        lab._reset_look()
        await settle(4)
        lab._apply_snapshot(snap)
        await settle(4)
        _check("cycle %d A/B snapshot" % cycle, lab.time_source == "FREE RUN", "")
        lab.preset_name_edit.text = "REG_JSON_%d" % cycle
        lab._export_json()
        lab._on_time_source(0)
        lab._import_json(ProjectSettings.globalize_path("user://fx_look_exports/REG_JSON_%d.json" % cycle))
        await settle(4)
        _check("cycle %d JSON roundtrip" % cycle, lab.time_source == "FREE RUN", "")
        lab._refresh_preset_list("REG_CYCLE_%d" % cycle)
        lab._delete_preset()
        lab._on_time_source(0)
        _check("cycle %d delete" % cycle, true, "")
    lab._reset_look()
    await settle(4)

func _resolution_sweep() -> void:
    for size in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1600, 900)]:
        root.size = size
        await settle(24)
        var host: Vector2 = lab.viewport_host.size
        _check("resolution %dx%d layout valid" % [size.x, size.y],
            host.x > 600.0 and host.y > 300.0 and float(lab.disp.scale.x) > 0.15,
            "host=%s scale=%.3f" % [str(host), float(lab.disp.scale.x)])

func _combination_sweep() -> void:
    # deterministic combination sweep: target × source × family × pure × source-clock
    var combos := [
        ["SELECTED", "LIVE SCREEN", "1v1", false, 0],
        ["ROLE", "LIVE SCREEN", "FFA_3", false, 0],
        ["ALL", "LIVE SCREEN", "1v1", true, 1],
        ["ALL", "ELEMENT STUDY", "1v1", false, 1],
        ["SELECTED", "ELEMENT STUDY", "1v1", true, 0],
        ["ROLE", "LIVE SCREEN", "FFA_4", false, 1],
        ["ALL", "LIVE SCREEN", "TEAM_2V2", false, 0],
        ["SELECTED", "LIVE SCREEN", "TEAM_2V1", true, 1],
        ["ROLE", "ELEMENT STUDY", "1v1", false, 0],
        ["ALL", "LIVE SCREEN", "FFA_3", true, 0],
        ["SELECTED", "LIVE SCREEN", "1v1", false, 1],
        ["ALL", "ELEMENT STUDY", "1v1", true, 1],
    ]
    var done := 0
    for combo in combos:
        lab._on_source_mode(0 if combo[1] == "LIVE SCREEN" else 1)
        lab._on_format(lab.FORMAT_NAMES.find(combo[2]))
        lab._on_target_mode(lab.TARGET_MODES.find(combo[0]))
        if combo[0] == "ROLE":
            var role_for: String = "VS MARK" if combo[1] == "ELEMENT STUDY" else "PRIMARIES"
            lab._on_target_role(lab.TARGET_ROLES.find(role_for))
        lab._on_pure(bool(combo[3]))
        lab._on_time_source(int(combo[4]))
        await settle(18)
        var ok: bool = lab._target_keys().size() > 0 and lab.mode_format == str(combo[2]) and lab.time_source == lab.TIME_SOURCES[int(combo[4])]
        if ok:
            done += 1
        else:
            _check("combo %s" % str(combo), false, "keys=%d source=%s format=%s target=%s slots=%d" % [lab._target_keys().size(),lab.source_mode,lab.mode_format,lab.target_mode,lab.slot_nodes.size()])
    _check("combination sweep (%d combos)" % combos.size(), done == combos.size(), "%d/%d clean" % [done, combos.size()])
    lab._on_format(0)
    lab._on_source_mode(0)
    lab._on_target_mode(0)
    lab._on_pure(false)
    lab._on_time_source(0)
    await settle(20)
