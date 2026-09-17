extends SceneTree
## Consolidated Godot-runtime logic gate for the post-R2 Authoring / Spatial /
## Production-style development build. Rendered geometry is covered separately
## by lab_spatial_parity.gd; this driver proves the interactive/state contracts
## that static Python checks cannot certify.

const LAB_SCENE := preload("res://scenes/nrcu_fx_lab.tscn")
const StyleRegistry := preload("res://scripts/vs_fx_style_registry.gd")

var lab: Node
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, name: String, detail := "") -> void:
    checks += 1
    print(("PASS" if ok else "FAIL") + "  " + name + ((" :: " + detail) if detail != "" else ""))
    if not ok:
        failures.append(name + ((" :: " + detail) if detail != "" else ""))

func _settle(frames := 4) -> void:
    for _i in range(frames):
        await process_frame

func _study_labels() -> Array[String]:
    var labels: Array[String] = []
    for raw in lab.study_assets:
        var item: Dictionary = raw
        labels.append(str(item.get("label", "")))
    return labels

func _first_key_for_role(role: String) -> String:
    for key in lab.slot_roles.keys():
        if str(lab.slot_roles[key]) == role:
            return str(key)
    return ""

func _run() -> void:
    lab = LAB_SCENE.instantiate()
    root.add_child(lab)
    await _settle(8)

    _check(lab.shader != null, "A · shader loads")
    _check(lab.screen != null, "A · real VS screen mounts")
    _check(lab.materials.size() > 0, "A · target materials exist", str(lab.materials.size()))

    # ------------------------------------------------------------------
    # Parameter / reset foundation
    var fx_size_spin = lab.spin_controls.get("fx_size")
    _check(fx_size_spin is SpinBox and (fx_size_spin as SpinBox).allow_greater, "B · creative numeric input allows overrange")
    if fx_size_spin is SpinBox:
        (fx_size_spin as SpinBox).value = 12.0
        await _settle(2)
        _check(absf(float(lab.state["fx_size"]) - 12.0) < 0.001, "B · numeric overrange reaches authored state", str(lab.state["fx_size"]))
        lab._reset_state_key("fx_size")
        _check(absf(float(lab.state["fx_size"]) - 1.0) < 0.001, "B · per-control reset restores factory")

    lab._set_state("base_opacity", 0.31)
    lab._set_state("grade_gamma", 2.4)
    lab._set_state("mono_threshold", 0.23)
    lab._reset_section("BASE")
    _check(absf(float(lab.state["base_opacity"]) - 1.0) < 0.001, "B · BASE section reset restores opacity")
    _check(absf(float(lab.state["grade_gamma"]) - 1.0) < 0.001, "B · BASE section reset restores grade")
    _check(absf(float(lab.state["mono_threshold"]) - 0.75) < 0.001, "B · BASE section reset restores Mono Stamp")

    # Base opacity is target isolated.
    lab.target_mode = "SELECTED"
    lab.selected_slot = "mark"
    lab._set_state("base_opacity", 0.25)
    await _settle(2)
    var mark_mat: ShaderMaterial = lab.materials.get("mark")
    _check(mark_mat != null and absf(float(mark_mat.get_shader_parameter("base_opacity")) - 0.25) < 0.001, "B · Base Opacity reaches selected target")
    var other_key := _first_key_for_role("PRIMARIES")
    if other_key != "":
        var other_mat: ShaderMaterial = lab.materials[other_key]
        _check(absf(float(other_mat.get_shader_parameter("base_opacity")) - 1.0) < 0.001, "B · Base Opacity does not leak to non-target")
    lab._reset_state_key("base_opacity")

    # Dedicated Mono Stamp domain must remain independent from Colour Dither.
    lab._set_state("base_mode", 1.0)
    lab._set_state("mono_threshold", 0.21)
    lab._set_state("dither_threshold", 0.89)
    lab._set_state("mono_pixel", 7.0)
    lab._set_state("dither_pixel", 2.0)
    await _settle(2)
    mark_mat = lab.materials.get("mark")
    _check(mark_mat != null and absf(float(mark_mat.get_shader_parameter("mono_threshold")) - 0.21) < 0.001, "B · Mono threshold has independent shader uniform")
    _check(mark_mat != null and absf(float(mark_mat.get_shader_parameter("dither_threshold")) - 0.89) < 0.001, "B · Colour Dither threshold stays independent")
    _check(mark_mat != null and absf(float(mark_mat.get_shader_parameter("mono_pixel")) - 7.0) < 0.001 and absf(float(mark_mat.get_shader_parameter("dither_pixel")) - 2.0) < 0.001, "B · Mono and Colour Dither cell sizes stay independent")
    lab._reset_section("BASE")
    lab._reset_section("DITHER")

    # ------------------------------------------------------------------
    # Presentation-space geometry / semantic targets
    var mark_node = lab.slot_nodes.get("mark")

    for role in ["SIDE FIELDS", "NAME PLATES", "ACCENT LINES"]:
        _check(_first_key_for_role(role) != "", "C · vector role mounted · " + role)
    _check(lab.texture_proxy_nodes.has("mark"), "C · texture overscan proxy mounted for VS mark")

    # ------------------------------------------------------------------
    # Full Element Study and semantic metadata
    var labels := _study_labels()
    for label in ["VS MARK", "PRIMARY · GGB", "ECHO · GGB", "NAME · GGB", "PRIMARY · ICE_MAGE", "SIDE FIELD · LEFT", "NAME PLATE · LEFT", "ACCENT LINE · LEFT"]:
        _check(labels.has(label), "D · Element Study contains " + label)
    lab._on_source_mode(1)
    await _settle(5)
    _check(lab.source_mode == "ELEMENT STUDY", "D · Element Study switches source")
    _check(lab.target_mode == "SELECTED" and lab.selected_slot == "study_asset", "D · Element Study guarantees a valid selected target")
    _check(lab._target_keys().size() == 1, "D · Element Study has exactly one active target", str(lab._target_keys()))
    var zoom_before: Vector2 = lab._presentation_size_for(lab.custom_rect, lab.custom_rect.texture)
    lab._set_study_zoom(2.0)
    await _settle(2)
    var zoom_after: Vector2 = lab._presentation_size_for(lab.custom_rect, lab.custom_rect.texture)
    _check(zoom_before.distance_to(zoom_after) < 0.01, "D · Study editor zoom does not change authored presentation size", str(zoom_before) + " -> " + str(zoom_after))
    lab._study_fit()
    lab._on_source_mode(0)
    await _settle(5)
    lab._transport_seek_to(1.5)
    await _settle(2)
    mark_node = lab.slot_nodes.get("mark")
    if mark_node is TextureRect and mark_node.texture != null:
        var ps: Vector2 = lab._presentation_size_for(mark_node, mark_node.texture)
        var source_size: Vector2 = Vector2(mark_node.texture.get_width(), mark_node.texture.get_height())
        _check(ps.y > 180.0 and ps.y < 280.0, "C · VS mark presentation size is screen-space sized", str(ps))
        _check(ps.y < source_size.y * 0.5, "C · VS mark does not use raw source size", "source=" + str(source_size) + " presentation=" + str(ps))
    else:
        _check(false, "C · VS mark presentation size is screen-space sized", "live VS mark target unavailable")
        _check(false, "C · VS mark does not use raw source size", "live VS mark target unavailable")

    # ------------------------------------------------------------------
    # Transport: parked composition + independent procedural clock.
    lab._transport_seek_to(0.675)
    await _settle(2)
    _check(lab.transport_paused, "E · seek parks the composition")
    _check(absf(float(lab.preview_t) - 0.675) < 0.01, "E · seek reaches requested presentation time", "%.3f" % lab.preview_t)
    var parked := float(lab.preview_t)
    lab._on_time_source(1) # FREE RUN
    var free_before := float(lab.shader_time)
    await _settle(12)
    _check(absf(float(lab.preview_t) - parked) < 0.01, "E · paused composition remains parked under FREE RUN")
    _check(float(lab.shader_time) > free_before, "E · FREE RUN shader clock continues while composition is parked", "%.3f -> %.3f" % [free_before, lab.shader_time])
    lab._on_time_source(0) # PRESENTATION TIME
    await _settle(2)
    _check(absf(float(lab.shader_time) - float(lab.preview_t)) < 0.01, "E · PRESENTATION TIME shader clock follows parked timeline")

    # FX PEAK must derive from the enabled envelope, not a magic frame.
    lab.motion_enabled["fringe"] = true
    lab.motion["fringe"]["anchor"] = "clash_impact"
    lab.motion["fringe"]["delay"] = 0.02
    lab.motion["fringe"]["attack"] = 0.08
    var expected_peak := float(lab.event_marks.get("clash_impact", 0.615)) + 0.10
    lab._transport_to_fx_peak()
    await _settle(2)
    _check(absf(float(lab.preview_t) - expected_peak) < 0.015, "E · FX PEAK resolves active envelope peak", "expected %.3f got %.3f" % [expected_peak, lab.preview_t])
    lab.motion_enabled["fringe"] = false

    # ------------------------------------------------------------------
    # Palette strategies + lock semantics.
    lab._on_source_mode(1)
    await _settle(3)
    var ggb_index := -1
    for i in range(lab.study_assets.size()):
        if str((lab.study_assets[i] as Dictionary).get("label", "")) == "PRIMARY · GGB":
            ggb_index = i
            break
    _check(ggb_index >= 0, "F · GGB study asset available for palette test")
    if ggb_index >= 0:
        lab._on_custom_asset(ggb_index)
        await _settle(3)
        lab.state["palette_lock_a"] = false
        lab.state["palette_lock_b"] = false
        lab.state["palette_strategy"] = 1.0 # complement
        lab._auto_palette()
        var a: Color = lab.state["col_a"]
        var b: Color = lab.state["col_b"]
        _check(a != b, "F · source complementary palette produces two colours")
        lab.state["palette_lock_a"] = true
        var locked_a: Color = lab.state["col_a"]
        lab.state["palette_strategy"] = 3.0 # analogous
        lab._auto_palette()
        var after_locked: Color = lab.state["col_a"]
        _check(after_locked == locked_a, "F · Palette A lock preserves authored colour")
        lab.state["palette_lock_a"] = false
    lab._on_source_mode(0)
    await _settle(3)

    # ------------------------------------------------------------------
    # Production assignment semantics: exact semantic identity, no P1/P2.
    lab.target_mode = "SELECTED"
    lab.selected_slot = "echo_left"
    lab._normalize_target()
    var context: Dictionary = lab._current_target_context()
    _check(str(context.get("fighter_id", "")) == "ice_mage", "G · left echo context resolves fighter identity", str(context))
    _check(str(context.get("element_role", "")) == "echo", "G · left echo context resolves semantic role", str(context))
    _check(str(context.get("visual_side", "")) == "left", "G · left echo context resolves visual side", str(context))
    var selector: Dictionary = lab._selector_for_scope("FIGHTER + ROLE + VISUAL SIDE")
    _check(selector == {"fighter_id":"ice_mage","element_role":"echo","visual_side":"left"}, "G · production selector matches researcher use case", str(selector))

    var assignments := {
        "schema": StyleRegistry.ASSIGNMENTS_SCHEMA,
        "bindings": [
            {"selector":{"element_role":"echo"},"look_id":"ECHO_BASE"},
            {"selector":{"fighter_id":"ice_mage","element_role":"echo","visual_side":"left"},"look_id":"ICE_ECHO_LEFT"}
        ]
    }
    var winner: Dictionary = StyleRegistry.resolve_binding(assignments, context)
    _check(str(winner.get("look_id", "")) == "ICE_ECHO_LEFT", "G · most-specific production binding wins", str(winner))
    var payload: Dictionary = lab._production_look_payload()
    _check(payload.has("state") and not payload.has("target_mode") and not payload.has("selected_slot"), "G · published Look contains style, not editor target state")

    # ------------------------------------------------------------------
    # PURE CONTINUOUS / contextual UI remains semantically honest.
    lab._set_state("pure_continuous", true)
    await _settle(2)
    var mono_control = lab.controls.get("mono_threshold")
    var hold_control = lab.controls.get("temporal_hold")
    _check(mono_control is Slider and not (mono_control as Slider).editable, "H · PURE CONTINUOUS disables Mono quantisation UI")
    _check(hold_control is Slider and not (hold_control as Slider).editable, "H · PURE CONTINUOUS disables Temporal Hold UI")
    lab._set_state("pure_continuous", false)

    print("\nNRCU AUTHORING/PARITY RUNTIME LOGIC: %s · %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
    if not failures.is_empty():
        for item in failures:
            print("  - ", item)
    quit(0 if failures.is_empty() else 1)
