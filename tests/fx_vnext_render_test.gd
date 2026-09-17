extends SceneTree
# vNext layer renderer test — SOURCE-only parity, transform, displacement,
# mask, plane placement, atomic failure, clear. Windowed run (rendering).

var checks: Array = []
var failures: int = 0
var out_dir: String
var runtime
var renderer
var container: SubViewportContainer

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/render")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxScreenRuntimeScript = load("res://scripts/fx_vnext/fx_screen_runtime.gd")
	var FxLayerRendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")

	runtime = FxScreenRuntimeScript.new()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.size = Vector2(1280, 720)
	root.add_child(host)
	container = SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(container)
	container.add_child(runtime.subvp)
	# Let the tree go active before mounting: vs_screen.start() touches
	# /root shortcuts that only resolve inside an active scene tree.
	await process_frame

	var mounted: bool = runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(50)
	_check(mounted, "screen mounts")
	runtime.seek(1.5)
	await settle(6)

	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.5)

	var base: Image = await _capture("render_base")

	# ---- neutral SOURCE-only parity -----------------------------------------
	var neutral: Dictionary = FxLookScript.new_look("T_ECHO", "Neutral")
	var applied: Dictionary = renderer.apply_look("echo_left", neutral)
	_check(bool(applied["ok"]), "neutral SOURCE-only look applies", str(applied["errors"]))
	var canonical: Node = runtime.registry.target_node("echo_left")
	_check(canonical.visible == true and canonical.self_modulate.a == 0.0, "canonical node hidden via self_modulate while stack active")
	_check(renderer.stack_quads("echo_left").size() == 1, "one quad for source-only stack")
	renderer.set_time(1.5)
	await settle(4)
	var src: Image = await _capture("render_source_only")
	var parity := _mean_abs_diff(base, src)
	_check(parity < 0.006, "SOURCE-only neutral parity", "mean=%.5f" % parity)

	# ---- transform -----------------------------------------------------------
	var moved: Dictionary = FxLookScript.new_look("T_MOVE", "Moved")
	(moved["layers"][0]["transform"] as Dictionary)["position_px"] = [60.0, 0.0]
	applied = renderer.apply_look("echo_left", moved)
	_check(bool(applied["ok"]), "transform look applies")
	renderer.set_time(1.5)
	await settle(4)
	var moved_img: Image = await _capture("render_transform")
	var moved_diff := _mean_abs_diff(src, moved_img)
	_check(moved_diff > 0.002, "transform moves rendered content", "mean=%.5f" % moved_diff)

	# ---- determinism + displacement -----------------------------------------
	renderer.set_time(2.5)
	await settle(4)
	var det_a: Image = await _capture("render_det_a")
	renderer.set_time(2.5)
	await settle(2)
	var det_b: Image = await _capture("render_det_b")
	_check(det_a.get_data() == det_b.get_data(), "same time → identical frame")

	var disp: Dictionary = FxLookScript.new_look("T_DISP", "Displaced")
	(disp["layers"][0]["displacement"] as Dictionary)["enabled"] = true
	(disp["layers"][0]["displacement"] as Dictionary)["amount_px"] = [40.0, 0.0]
	(disp["layers"][0]["displacement"] as Dictionary)["speed"] = 1.0
	applied = renderer.apply_look("echo_left", disp)
	_check(bool(applied["ok"]), "displacement look applies")
	renderer.set_time(1.5)
	await settle(4)
	var disp_a: Image = await _capture("render_disp_a")
	renderer.set_time(2.5)
	await settle(4)
	var disp_b: Image = await _capture("render_disp_b")
	var disp_time_diff := _mean_abs_diff(disp_a, disp_b)
	_check(disp_time_diff > 0.001, "displacement animates over time", "mean=%.5f" % disp_time_diff)
	renderer.set_time(1.5)
	await settle(4)
	var disp_a2: Image = await _capture("render_disp_a2")
	_check(disp_a.get_data() == disp_a2.get_data(), "displacement reproducible at same time")

	# ---- FREE RUN time source --------------------------------------------------
	var free_look: Dictionary = FxLookScript.new_look("T_FREE", "Free run")
	var free_layer: Dictionary = free_look["layers"][0] as Dictionary
	free_layer["displacement"] = {
		"enabled": true, "driver": "NOISE", "amount_px": [30.0, 14.0], "scale": 2.0,
		"speed": 1.5, "phase": 0.0, "seed": 3, "time_source": "FREE_RUN",
		"angle_deg": 0.0, "edge_mode": "TRANSPARENT", "custom_texture": null, "influence_mask": null,
	}
	applied = renderer.apply_look("echo_left", free_look)
	_check(bool(applied["ok"]), "free-run look applies", str(applied["errors"]))
	renderer.set_time(1.5)
	renderer.set_free_run(10.0)
	await settle(4)
	var free_a: Image = await _capture("render_free_a")
	renderer.set_free_run(25.0)
	await settle(4)
	var free_b: Image = await _capture("render_free_b")
	_check(_mean_abs_diff(free_a, free_b) > 0.0005, "FREE RUN advances while composition parked", "mean=%.5f" % _mean_abs_diff(free_a, free_b))
	var pres_look: Dictionary = free_look.duplicate(true)
	(pres_look["layers"][0] as Dictionary)["displacement"]["time_source"] = "PRESENTATION_TIME"
	renderer.apply_look("echo_left", pres_look)
	renderer.set_time(1.5)
	renderer.set_free_run(10.0)
	await settle(4)
	var pres_a: Image = await _capture("render_free_pres_a")
	renderer.set_free_run(25.0)
	await settle(4)
	var pres_b: Image = await _capture("render_free_pres_b")
	_check(_mean_abs_diff(pres_a, pres_b) < 0.0002, "PRESENTATION_TIME ignores the free clock", "mean=%.5f" % _mean_abs_diff(pres_a, pres_b))

	# ---- LAYER_BELOW with no lower layer: defined transparent input --------------
	var empty_below: Dictionary = FxLookScript.new_look("T_EMPTY_BELOW", "Empty below")
	var eb_fx: Dictionary = FxLookScript.new_layer("FX", "Consumer first")
	eb_fx["input"] = "LAYER_BELOW"
	eb_fx["fx"] = {"fringe": 1.5, "intensity": 1.2}
	empty_below["layers"].insert(0, eb_fx)
	# fresh baseline at the same parked time (the old `src` predates the free-run
	# section, so animation drift would pollute the comparison)
	renderer.clear_target("echo_left")
	renderer.set_time(1.5)
	await settle(6)
	var neutral_now: Image = await _capture("render_empty_below_baseline")
	applied = renderer.apply_look("echo_left", empty_below)
	_check(bool(applied["ok"]), "empty-below look applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var empty_img: Image = await _capture("render_empty_below")
	_check(_mean_abs_diff(neutral_now, empty_img) < 0.002, "missing lower input renders transparent, not garbage", "mean=%.5f" % _mean_abs_diff(neutral_now, empty_img))

	# ---- two SOURCE_COPY layers stay independent ---------------------------------
	var copies: Dictionary = FxLookScript.new_look("T_COPIES", "Copies")
	var c1: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Copy 1")
	(c1["transform"] as Dictionary)["position_px"] = [40.0, 0.0]
	var c2: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Copy 2")
	(c2["transform"] as Dictionary)["position_px"] = [-40.0, 0.0]
	(c2["displacement"] as Dictionary)["enabled"] = true
	(c2["displacement"] as Dictionary)["driver"] = "WAVE"
	(c2["displacement"] as Dictionary)["amount_px"] = [24.0, 0.0]
	(c2["displacement"] as Dictionary)["speed"] = 1.0
	copies["layers"].append(c1)
	copies["layers"].append(c2)
	applied = renderer.apply_look("echo_left", copies)
	_check(bool(applied["ok"]), "two-copy look applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var copies_img: Image = await _capture("render_two_copies")
	_check(_mean_abs_diff(src, copies_img) > 0.002, "two copies with independent settings render", "mean=%.5f" % _mean_abs_diff(src, copies_img))
	(copies["layers"][2] as Dictionary)["displacement"]["speed"] = 0.0
	renderer.apply_look("echo_left", copies)
	renderer.set_time(1.5)
	await settle(4)
	var copies_static: Image = await _capture("render_two_copies_static")
	var copy_delta := _mean_abs_diff(copies_img, copies_static)
	_check(copy_delta > 0.0002, "copy2 displacement drives only copy2", "mean=%.5f" % copy_delta)

	# ---- custom texture driver + custom mask (project-local assets) ----------------
	var custom_look: Dictionary = FxLookScript.new_look("T_CUSTOM", "Custom assets")
	var custom_layer: Dictionary = custom_look["layers"][0] as Dictionary
	custom_layer["displacement"] = {
		"enabled": true, "driver": "CUSTOM_TEXTURE", "amount_px": [64.0, 0.0], "scale": 1.0,
		"speed": 0.0, "phase": 0.0, "seed": 5, "time_source": "PRESENTATION_TIME",
		"angle_deg": 0.0, "edge_mode": "MIRROR", "custom_texture": "res://assets/masks/treatment_mask_test.png",
		"influence_mask": null,
	}
	applied = renderer.apply_look("echo_left", custom_look)
	_check(bool(applied["ok"]), "custom driver look applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var custom_img: Image = await _capture("render_custom_driver")
	_check(_mean_abs_diff(src, custom_img) > 0.002, "CUSTOM_TEXTURE driver samples the project asset", "mean=%.5f" % _mean_abs_diff(src, custom_img))
	var mask_asset_look: Dictionary = FxLookScript.new_look("T_MASKASSET", "Mask asset")
	var mal: Dictionary = mask_asset_look["layers"][0] as Dictionary
	mal["mask"]["enabled"] = true
	mal["mask"]["source"] = "CUSTOM_MASK"
	mal["mask"]["custom_mask"] = "res://assets/vs/generated/accent_left_mask.png"
	applied = renderer.apply_look("echo_left", mask_asset_look)
	_check(bool(applied["ok"]), "custom mask look applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var mask_asset_img: Image = await _capture("render_custom_mask_asset")
	_check(_mean_abs_diff(src, mask_asset_img) > 0.002, "CUSTOM_MASK samples the project asset", "mean=%.5f" % _mean_abs_diff(src, mask_asset_img))

	# ---- TRANSFORMED_SOURCE vs ORIGINAL_SOURCE (Round-2 mandated) ---------------
	var base_pair: Dictionary = FxLookScript.new_look("T_PAIR", "Pair")
	var pair_source: Dictionary = base_pair["layers"][0] as Dictionary
	(pair_source["transform"] as Dictionary)["position_px"] = [92.0, 0.0]
	var pair_disp: Dictionary = pair_source["displacement"]
	pair_disp["enabled"] = true
	pair_disp["driver"] = "NOISE"
	pair_disp["amount_px"] = [30.0, 16.0]
	pair_disp["speed"] = 1.0
	pair_disp["scale"] = 2.0
	var fx_a: Dictionary = FxLookScript.new_layer("FX", "A original")
	fx_a["input"] = "ORIGINAL_SOURCE"
	fx_a["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 14.0}
	var fx_b: Dictionary = FxLookScript.new_layer("FX", "B transformed")
	fx_b["input"] = "TRANSFORMED_SOURCE"
	fx_b["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 14.0}
	var look_a: Dictionary = base_pair.duplicate(true)
	(look_a["layers"] as Array).append(fx_a.duplicate(true))
	var look_b: Dictionary = base_pair.duplicate(true)
	(look_b["layers"] as Array).append(fx_b.duplicate(true))
	applied = renderer.apply_look("echo_left", look_a)
	_check(bool(applied["ok"]), "ORIGINAL_SOURCE pair applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var pair_a_img: Image = await _capture("render_pair_original")
	applied = renderer.apply_look("echo_left", look_b)
	_check(bool(applied["ok"]), "TRANSFORMED_SOURCE pair applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var pair_b_img: Image = await _capture("render_pair_transformed")
	var pair_delta := _mean_abs_diff(pair_a_img, pair_b_img)
	_check(pair_delta > 0.002, "TRANSFORMED_SOURCE differs from ORIGINAL_SOURCE under transformed source", "mean=%.5f" % pair_delta)
	# mixing both input families must fail loudly (nested stages)
	var mixed_look: Dictionary = look_b.duplicate(true)
	var fx_c: Dictionary = FxLookScript.new_layer("FX", "C below")
	fx_c["input"] = "LAYER_BELOW"
	(mixed_look["layers"] as Array).append(fx_c)
	applied = renderer.apply_look("echo_left", mixed_look)
	_check(not bool(applied["ok"]), "mixed TRANSFORMED_SOURCE + LAYER_BELOW rejected")

	# ---- mask spaces three-way (Round-2 mandated) --------------------------------
	var space_look: Dictionary = FxLookScript.new_look("T_SPACES", "Spaces")
	var space_source: Dictionary = space_look["layers"][0] as Dictionary
	(space_source["transform"] as Dictionary)["position_px"] = [70.0, -30.0]
	(space_source["transform"] as Dictionary)["rotation_deg"] = 18.0
	var space_disp: Dictionary = space_source["displacement"]
	space_disp["enabled"] = true
	space_disp["driver"] = "DIRECTIONAL"
	space_disp["amount_px"] = [26.0, 12.0]
	space_disp["speed"] = 1.0
	var space_mask: Dictionary = space_source["mask"]
	space_mask["enabled"] = true
	space_mask["source"] = "ORIGINAL_SOURCE_ALPHA"
	space_mask["region"] = "EDGE_BAND"
	space_mask["width_px"] = 10.0
	space_mask["feather_px"] = 3.0
	var space_images: Array = []
	for space_name in ["SOURCE_SPACE", "LAYER_SPACE", "PRESENTATION_SPACE"]:
		(space_source["mask"] as Dictionary)["space"] = space_name
		applied = renderer.apply_look("echo_left", space_look)
		_check(bool(applied["ok"]), "mask space applies: " + space_name, str(applied["errors"]))
		renderer.set_time(1.5)
		await settle(6)
		space_images.append(await _capture("render_space_" + space_name.to_lower()))
	var d_sl := _mean_abs_diff(space_images[0], space_images[1])
	var d_lp := _mean_abs_diff(space_images[1], space_images[2])
	var d_sp := _mean_abs_diff(space_images[0], space_images[2])
	_check(d_sl > 0.0003, "SOURCE vs LAYER mask space visibly differ", "mean=%.5f" % d_sl)
	_check(d_lp > 0.0005, "LAYER vs PRESENTATION mask space visibly differ", "mean=%.5f" % d_lp)
	_check(d_sp > 0.0005, "SOURCE vs PRESENTATION mask space visibly differ", "mean=%.5f" % d_sp)

	# ---- mask ----------------------------------------------------------------
	var masked: Dictionary = FxLookScript.new_look("T_MASK", "Masked")
	var m: Dictionary = masked["layers"][0]["mask"]
	m["enabled"] = true
	m["source"] = "ORIGINAL_SOURCE_ALPHA"
	m["region"] = "EDGE_BAND"
	m["width_px"] = 30.0
	m["feather_px"] = 12.0
	applied = renderer.apply_look("echo_left", masked)
	_check(bool(applied["ok"]), "mask look applies")
	renderer.set_time(1.5)
	await settle(4)
	var masked_img: Image = await _capture("render_mask_edge")
	var mask_diff := _mean_abs_diff(src, masked_img)
	_check(mask_diff > 0.0013, "edge-band mask changes render", "mean=%.5f" % mask_diff)

	# ---- fx stage: rgb tear / fringe / dither --------------------------------
	var rgb_look: Dictionary = FxLookScript.new_look("T_RGB", "RGB tear")
	rgb_look["layers"][0]["fx"] = {"rgb": 1.0, "rgb_shift_amount": 24.0, "intensity": 1.0}
	applied = renderer.apply_look("echo_left", rgb_look)
	_check(bool(applied["ok"]), "rgb fx applies")
	renderer.set_time(1.5)
	await settle(4)
	var rgb_img: Image = await _capture("render_fx_rgb")
	var rgb_diff := _mean_abs_diff(src, rgb_img)
	_check(rgb_diff > 0.001, "rgb tear changes render", "mean=%.5f" % rgb_diff)

	var fringe_look: Dictionary = FxLookScript.new_look("T_FRINGE", "Fringe")
	fringe_look["layers"][0]["fx"] = {
		"fringe": 2.0, "intensity": 1.6, "edge_width": 12.0, "wind_reach": 54.0,
		"wind_trail": 1.0, "color_blur": 2.0, "signal_gain": 1.8, "fringe_bleed": 1.0,
	}
	applied = renderer.apply_look("echo_left", fringe_look)
	_check(bool(applied["ok"]), "fringe fx applies")
	renderer.set_time(1.5)
	await settle(6)
	var fringe_img: Image = await _capture("render_fx_fringe")
	var fringe_diff := _mean_abs_diff(src, fringe_img)
	_check(fringe_diff > 0.004, "fringe changes render", "mean=%.5f" % fringe_diff)

	var dither_look: Dictionary = FxLookScript.new_look("T_DITHER", "Dither")
	dither_look["layers"][0]["fx"] = {"dither": 1.0, "intensity": 1.5, "dither_levels": 4.0, "dither_pixel": 3.0}
	applied = renderer.apply_look("echo_left", dither_look)
	_check(bool(applied["ok"]), "dither fx applies")
	renderer.set_time(1.5)
	await settle(4)
	var dither_img: Image = await _capture("render_fx_dither")
	var dither_diff := _mean_abs_diff(src, dither_img)
	_check(dither_diff > 0.001, "dither changes render", "mean=%.5f" % dither_diff)
	renderer.set_time(2.9)
	await settle(2)
	var dither_b: Image = await _capture("render_fx_dither_b")
	renderer.set_time(1.5)
	await settle(2)
	var dither_a2: Image = await _capture("render_fx_dither_a2")
	_check(dither_img.get_data() == dither_a2.get_data(), "fx render reproducible at same time")

	# ---- planes ---------------------------------------------------------------
	var layered: Dictionary = FxLookScript.new_look("T_LAYERS", "Layered")
	var bg: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Halo background")
	bg["plane"] = "COMPOSITION_BACKGROUND"
	layered["layers"].append(bg)
	var fg: Dictionary = FxLookScript.new_layer("FX", "Overlay")
	fg["plane"] = "TARGET_OVERLAY"
	fg["input"] = "ORIGINAL_SOURCE"
	layered["layers"].append(fg)
	applied = renderer.apply_look("echo_left", layered)
	_check(bool(applied["ok"]), "layered look applies", str(applied["errors"]))
	var quads: Array = renderer.stack_quads("echo_left")
	_check(quads.size() == 3, "three quads for three layers", "count=%d" % quads.size())
	var root_node: Node = runtime.screen.get_node("Root")
	var bg_quad: Node = null
	var fg_quad: Node = null
	for entry in quads:
		if str(entry["plane"]) == "COMPOSITION_BACKGROUND":
			bg_quad = entry["node"]
		if str(entry["plane"]) == "TARGET_OVERLAY":
			fg_quad = entry["node"]
	var side_fields := root_node.get_node_or_null("SideFields")
	_check(bg_quad != null and bg_quad.get_parent() == root_node, "background quad parented in Root")
	_check(bg_quad != null and side_fields != null and bg_quad.get_index() == side_fields.get_index() + 1, "background quad above side fields")
	_check(fg_quad != null and fg_quad.get_parent() == root_node and fg_quad.get_index() == canonical.get_index() + 1, "overlay quad directly above canonical")
	renderer.set_time(1.5)
	await settle(4)
	await _capture("render_layered")

	# ---- offscreen inputs: LAYER_BELOW ---------------------------------------
	var below: Dictionary = FxLookScript.new_look("T_BELOW", "Below")
	(below["layers"][0]["transform"] as Dictionary)["position_px"] = [40.0, 0.0]
	var below_fx: Dictionary = FxLookScript.new_layer("FX", "Consumes below")
	below_fx["input"] = "LAYER_BELOW"
	below_fx["fx"] = {"rgb": 1.0, "rgb_shift_amount": 20.0, "intensity": 1.0}
	below["layers"].append(below_fx)
	applied = renderer.apply_look("echo_left", below)
	_check(bool(applied["ok"]), "LAYER_BELOW applies", str(applied["errors"]))
	_check(_input_viewport_count() == 1, "offscreen stage created", "count=%d" % _input_viewport_count())
	renderer.set_time(1.5)
	await settle(6)
	var below_img: Image = await _capture("render_input_below")
	var below_diff := _mean_abs_diff(src, below_img)
	_check(below_diff > 0.001, "LAYER_BELOW renders lower output", "mean=%.5f" % below_diff)
	var orig_look: Dictionary = below.duplicate(true)
	(orig_look["layers"][1] as Dictionary)["input"] = "ORIGINAL_SOURCE"
	applied = renderer.apply_look("echo_left", orig_look)
	_check(bool(applied["ok"]), "control look applies")
	renderer.set_time(1.5)
	await settle(6)
	var orig_img: Image = await _capture("render_input_original")
	var io_diff := _mean_abs_diff(below_img, orig_img)
	_check(io_diff > 0.0003, "LAYER_BELOW differs from ORIGINAL_SOURCE input", "mean=%.5f" % io_diff)

	# ---- COMPOSITE_BELOW -------------------------------------------------------
	var composite: Dictionary = FxLookScript.new_look("T_COMP", "Composite")
	(composite["layers"][0]["transform"] as Dictionary)["position_px"] = [40.0, 0.0]
	var copy_layer: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Offset copy")
	(copy_layer["transform"] as Dictionary)["position_px"] = [-60.0, 0.0]
	composite["layers"].append(copy_layer)
	var comp_fx: Dictionary = FxLookScript.new_layer("FX", "Reads composite")
	comp_fx["input"] = "COMPOSITE_BELOW"
	comp_fx["fx"] = {"fringe": 1.6, "intensity": 1.4, "edge_width": 10.0, "wind_reach": 40.0, "wind_trail": 1.0, "fringe_bleed": 1.0}
	composite["layers"].append(comp_fx)
	applied = renderer.apply_look("echo_left", composite)
	_check(bool(applied["ok"]), "COMPOSITE_BELOW applies", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(8)
	var comp_img: Image = await _capture("render_input_composite")
	var comp_diff := _mean_abs_diff(src, comp_img)
	_check(comp_diff > 0.002, "COMPOSITE_BELOW renders", "mean=%.5f" % comp_diff)

	# ---- blend modes (spec 15 §12) --------------------------------------------
	var blend_look: Dictionary = FxLookScript.new_look("T_BLEND", "Blend")
	(blend_look["layers"][0]["transform"] as Dictionary)["position_px"] = [30.0, 0.0]
	var blend_copy: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Blend copy")
	blend_look["layers"].append(blend_copy)
	var region := Rect2i(0, 0, 640, 720)
	applied = renderer.apply_look("echo_left", blend_look)
	_check(bool(applied["ok"]), "blend stack in place", str(applied["errors"]))
	renderer.set_time(1.5)
	await settle(6)
	var normal_img: Image = await _capture("render_blend_normal")
	var luma_normal := _region_mean_luma(normal_img, region)

	blend_copy["blend_mode"] = "ADD"
	applied = renderer.apply_look("echo_left", blend_look)
	_check(bool(applied["ok"]), "ADD blend applies", str(applied["errors"]))
	_check(_bbc_count() == 1, "backbuffer pin created for blend layer", "count=%d" % _bbc_count())
	renderer.set_time(1.5)
	await settle(6)
	var add_img: Image = await _capture("render_blend_add")
	var luma_add := _region_mean_luma(add_img, region)
	_check(luma_add > luma_normal + 0.0005, "ADD brightens vs NORMAL", "add=%.4f normal=%.4f" % [luma_add, luma_normal])

	blend_copy["blend_mode"] = "SCREEN"
	applied = renderer.apply_look("echo_left", blend_look)
	renderer.set_time(1.5)
	await settle(6)
	var screen_img: Image = await _capture("render_blend_screen")
	var luma_screen := _region_mean_luma(screen_img, region)
	_check(luma_screen > luma_normal + 0.0005, "SCREEN brightens vs NORMAL", "screen=%.4f normal=%.4f" % [luma_screen, luma_normal])

	blend_copy["blend_mode"] = "MULTIPLY"
	applied = renderer.apply_look("echo_left", blend_look)
	renderer.set_time(1.5)
	await settle(6)
	var mult_img: Image = await _capture("render_blend_multiply")
	var luma_mult := _region_mean_luma(mult_img, region)
	_check(luma_mult < luma_normal - 0.0005, "MULTIPLY darkens vs NORMAL", "mult=%.4f normal=%.4f" % [luma_mult, luma_normal])
	_check(_mean_abs_diff(add_img, mult_img) > 0.001, "ADD and MULTIPLY visibly differ", "mean=%.5f" % _mean_abs_diff(add_img, mult_img))

	blend_copy["blend_mode"] = "OVERLAY"
	applied = renderer.apply_look("echo_left", blend_look)
	_check(not bool(applied["ok"]), "unknown blend rejected")
	blend_copy["blend_mode"] = "NORMAL"

	# ---- multiple / nested consumers fail loudly -------------------------------
	var nested: Dictionary = composite.duplicate(true)
	var extra_fx: Dictionary = FxLookScript.new_layer("FX", "Second consumer")
	extra_fx["input"] = "LAYER_BELOW"
	(nested["layers"] as Array).append(extra_fx)
	applied = renderer.apply_look("echo_left", nested)
	_check(not bool(applied["ok"]) and not (applied["errors"] as Array).is_empty(), "multiple offscreen consumers rejected (v1)")
	_check(_input_viewport_count() == 0, "rejected apply leaves no offscreen stage")
	_check(not renderer.has_stack("echo_left"), "failed apply leaves no stack")
	_check(canonical.self_modulate.a == 1.0, "failed apply restores canonical rendering")

	# ---- clear ----------------------------------------------------------------
	applied = renderer.apply_look("echo_left", FxLookScript.new_look("T_AGAIN", "Again"))
	_check(bool(applied["ok"]), "re-apply works")
	renderer.clear_target("echo_left")
	_check(canonical.self_modulate.a == 1.0 and not renderer.has_stack("echo_left"), "clear restores canonical render")
	_check(_input_viewport_count() == 0, "no stray offscreen stages after clear", "count=%d" % _input_viewport_count())
	_check(_bbc_count() == 0, "no stray backbuffer pins after clear", "count=%d" % _bbc_count())

	var f := FileAccess.open(out_dir.path_join("summary_render_check.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks.size(), "failures": failures}, "  "))
		f.close()
	print("[FX-RENDER] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _input_viewport_count() -> int:
	var count := 0
	for child in runtime.screen.get_children():
		if str(child.name) == "vnext_input":
			count += 1
	return count

func _bbc_count() -> int:
	return _count_named(runtime.screen, "vnext_bbc")

func _count_named(node: Node, wanted: String) -> int:
	var count := 0
	if str(node.name) == wanted:
		count += 1
	for child in node.get_children():
		count += _count_named(child, wanted)
	return count

func _region_mean_luma(img: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y, 2):
		for x in range(rect.position.x, rect.position.x + rect.size.x, 2):
			var c := img.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			count += 1
	return total / float(max(count, 1))

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var crop: Image = img.get_region(Rect2i(0, 0, 1280, 720))
	crop.save_png(out_dir.path_join(name + ".png"))
	return crop

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 999.0
	var data_a := a.get_data()
	var data_b := b.get_data()
	if data_a == data_b:
		return 0.0
	var total := 0.0
	var samples := 0
	var width := a.get_width()
	var height := a.get_height()
	var stride := 3
	for y in range(0, height, stride):
		for x in range(0, width, stride):
			var i := (y * width + x) * 4
			total += absf(float(data_a[i] - data_b[i])) + absf(float(data_a[i + 1] - data_b[i + 1])) + absf(float(data_a[i + 2] - data_b[i + 2]))
			samples += 3
	return total / maxf(float(samples) * 255.0, 1.0)

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok:
		failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
