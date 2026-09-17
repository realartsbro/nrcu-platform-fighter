extends SceneTree
## Runtime acceptance driver for presentation-space FX parity.
##
## This is intentionally a rendered test. The Python contracts can prove that
## the right uniforms exist, but only Godot can prove that differently-sized
## source assets produce comparable visible geometry in the 1280×720 design.

const LAB_SCENE := preload("res://scenes/nrcu_fx_lab.tscn")
const TARGET_LABELS := [
    "VS MARK",
    "PRIMARY · GGB",
    "ECHO · GGB",
    "PRIMARY · ICE_MAGE",
    "NAME · GGB"
]
var out_dir: String
const BBOX_SAMPLE_STRIDE := 4

var lab: Node
var checks: Array = []
var measurements: Array = []
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, name: String, detail := "") -> void:
    checks.append({"check":name,"ok":ok,"detail":detail})
    print(("PASS" if ok else "FAIL") + "  " + name + (" :: " + detail if detail != "" else ""))
    if not ok:
        failures.append(name)

func _settle(frames: int = 6) -> void:
    for _i in range(frames):
        await process_frame

func _study_index(label: String) -> int:
    for i in range(lab.study_assets.size()):
        if str((lab.study_assets[i] as Dictionary).get("label","")) == label:
            return i
    return -1

func _capture(tag: String) -> Image:
    await RenderingServer.frame_post_draw
    var image: Image = lab.subvp.get_texture().get_image()
    image.convert(Image.FORMAT_RGBA8)
    image.save_png(out_dir.path_join(tag + ".png"))
    return image

func _bbox_against_corner_background(image: Image, threshold: int = 18) -> Rect2i:
    if image == null or image.is_empty():
        return Rect2i()
    var bg := image.get_pixel(4,4)
    var bg8 := Vector3i(roundi(bg.r*255.0),roundi(bg.g*255.0),roundi(bg.b*255.0))
    var min_x := image.get_width()
    var min_y := image.get_height()
    var max_x := -1
    var max_y := -1
    for y in range(0, image.get_height(), BBOX_SAMPLE_STRIDE):
        for x in range(0, image.get_width(), BBOX_SAMPLE_STRIDE):
            var c := image.get_pixel(x,y)
            var d := absi(roundi(c.r*255.0)-bg8.x)+absi(roundi(c.g*255.0)-bg8.y)+absi(roundi(c.b*255.0)-bg8.z)
            if d > threshold:
                # Expand each hit to its sampled cell so sparse sampling does not
                # under-report the visible bounds at asset edges.
                min_x = mini(min_x, maxi(x-BBOX_SAMPLE_STRIDE+1,0))
                min_y = mini(min_y, maxi(y-BBOX_SAMPLE_STRIDE+1,0))
                max_x = maxi(max_x, mini(x+BBOX_SAMPLE_STRIDE-1,image.get_width()-1))
                max_y = maxi(max_y, mini(y+BBOX_SAMPLE_STRIDE-1,image.get_height()-1))
    if max_x < min_x or max_y < min_y:
        return Rect2i()
    return Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1)

func _bbox_expansion(base: Rect2i, fx: Rect2i) -> Dictionary:
    return {
        "left": maxf(float(base.position.x-fx.position.x),0.0),
        "top": maxf(float(base.position.y-fx.position.y),0.0),
        "right": maxf(float(fx.end.x-base.end.x),0.0),
        "bottom": maxf(float(fx.end.y-base.end.y),0.0)
    }

func _max_expansion(d: Dictionary) -> float:
    return maxf(maxf(float(d.left),float(d.right)),maxf(float(d.top),float(d.bottom)))

func _configure_neutral_base() -> void:
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

func _configure_parity_fringe() -> void:
    _configure_neutral_base()
    lab.state["fx_on"]["fringe"] = true
    lab.state["fx_on"]["flow"] = false
    lab.state["edge_source_mode"] = 0.0 # alpha silhouette
    lab.state["geometry_units"] = 1.0 # presentation px
    lab.state["edge_width"] = 4.0
    lab.state["wind_reach"] = 24.0
    lab.state["wind_trail"] = 1.0
    lab.state["split_separation"] = 0.0
    lab.state["color_blur"] = 0.0
    lab.state["fringe_bleed"] = 1.0
    lab.state["signal_gain"] = 2.0
    lab.state["wind_cutoff"] = 0.05
    lab.state["fringe_coverage_mode"] = 0.0
    lab.state["fx_amount"]["fringe"] = 1.0
    lab._reset_runtime_amounts()
    lab._apply_fx()

func _measure_asset(label: String) -> Dictionary:
    var index := _study_index(label)
    _check(index >= 0,"study asset exists · " + label)
    if index < 0:
        return {}
    lab._on_custom_asset(index)
    await _settle(8)
    # A controlled solid background makes the visible source bbox measurable
    # even for transparent/black artwork. Selection/UI overlays live outside
    # the SubViewport and therefore do not contaminate this capture.
    lab.custom_background.texture = null
    lab.custom_background.self_modulate = Color(0.17,0.29,0.41,1.0)
    lab.custom_background.visible = true

    _configure_neutral_base()
    await _settle(4)
    var base := await _capture(label.to_snake_case()+"_base")
    var base_box := _bbox_against_corner_background(base)
    _check(base_box.size.x > 2 and base_box.size.y > 2,"base bbox measurable · " + label,str(base_box))

    _configure_parity_fringe()
    await _settle(4)
    var fx := await _capture(label.to_snake_case()+"_fringe")
    var fx_box := _bbox_against_corner_background(fx)
    _check(fx_box.size.x >= base_box.size.x and fx_box.size.y >= base_box.size.y,"FX bbox contains base · " + label,str(fx_box))

    var expansion := _bbox_expansion(base_box,fx_box)
    var screen_expand := _max_expansion(expansion)
    var tex: Texture2D = lab.custom_rect.texture
    var presentation_size: Vector2 = lab._study_reference_presentation_size(tex)
    var sx: float = lab.custom_rect.size.x/maxf(presentation_size.x,1.0)
    var sy: float = lab.custom_rect.size.y/maxf(presentation_size.y,1.0)
    var editor_scale := maxf((sx+sy)*0.5,0.0001)
    var presentation_expand := screen_expand/editor_scale
    var item := {
        "label":label,
        "source_size":[tex.get_width(),tex.get_height()],
        "presentation_size":[presentation_size.x,presentation_size.y],
        "study_draw_size":[lab.custom_rect.size.x,lab.custom_rect.size.y],
        "base_bbox":[base_box.position.x,base_box.position.y,base_box.size.x,base_box.size.y],
        "fx_bbox":[fx_box.position.x,fx_box.position.y,fx_box.size.x,fx_box.size.y],
        "bbox_expansion_screen_px":screen_expand,
        "bbox_expansion_presentation_px":presentation_expand
    }
    measurements.append(item)
    _check(presentation_expand > 1.0,"visible presentation-space fringe expands · " + label,"%.2f px" % presentation_expand)
    return item

func _run() -> void:
    out_dir = OS.get_environment("FXLAB_SPATIAL_EVIDENCE_DIR")
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("res://evidence/spatial_parity_final")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = LAB_SCENE.instantiate()
    root.add_child(lab)
    await _settle(12)
    lab._on_source_mode(1)
    await _settle(8)
    _check(lab.source_mode == "ELEMENT STUDY","Element Study active")
    _check(lab.target_mode == "SELECTED","Element Study forces selected target")

    var values: Array[float] = []
    for label in TARGET_LABELS:
        var result := await _measure_asset(label)
        if not result.is_empty():
            values.append(float(result["bbox_expansion_presentation_px"]))

    if values.size() >= 3:
        var lo := values[0]
        var hi := values[0]
        for v in values:
            lo = minf(lo,v); hi = maxf(hi,v)
        var ratio := hi/maxf(lo,0.001)
        # Real silhouettes differ, so this is deliberately broader than a
        # synthetic-kernel test. A source-resolution bug like the old VS Mark
        # path should fail dramatically rather than hide inside this tolerance.
        _check(ratio <= 2.0,"real-asset presentation-space parity","min %.2f px · max %.2f px · ratio %.2f" % [lo,hi,ratio])

    # Editor zoom is presentation-neutral: authored element_size must not change.
    var idx := _study_index("VS MARK")
    if idx >= 0:
        lab._on_custom_asset(idx); await _settle(4)
        var before: Vector2 = (lab.materials["study_asset"] as ShaderMaterial).get_shader_parameter("element_size")
        lab._set_study_zoom(2.0); await _settle(4)
        lab._apply_runtime_uniforms()
        var after: Vector2 = (lab.materials["study_asset"] as ShaderMaterial).get_shader_parameter("element_size")
        _check(before.distance_to(after) < 0.01,"Element Study zoom does not alter authored presentation size","%s -> %s" % [before,after])

    # Leave Element Study before exercising the live multiplayer schema.
    lab._on_source_mode(0)
    await _settle(4)
    lab.mode_format = "TEAM_2V2"
    lab._mount_screen(); await _settle(8)
    var team_slots := 0
    var team_key_report: Array[String] = []
    for key in lab.slot_nodes.keys():
        var slot: String = lab._presentation_slot_from_key(str(key))
        team_key_report.append("%s=>%s" % [str(key),slot])
        if slot in ["a_back","a_front","b_front","b_back"]:
            team_slots += 1
    _check(team_slots >= 4,"TEAM_2V2 presentation slots resolve from schema","format=%s resolved nodes %d keys=%s" % [lab.mode_format,team_slots,";".join(team_key_report)])

    var report := {"checks":checks,"measurements":measurements,"failures":failures}
    var out := FileAccess.open(out_dir.path_join("spatial_parity_summary.json"),FileAccess.WRITE)
    if out != null:
        out.store_string(JSON.stringify(report,"  "))
        out.close()
    print("NRCU spatial parity: ","PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
