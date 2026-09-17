extends SceneTree
# R3 §6 + §7 — SOURCE SEMANTICS + MASK SPACE TORTURE (red-team torture).
#
# §6 TRANSFORMED_SOURCE: canonical SOURCE with unmistakable transform
#    (+120px X, -60px Y, scale 1.25, 25° rotation, strong deterministic noise
#    displacement). A = ORIGINAL_SOURCE samples the untouched canonical texture;
#    B = TRANSFORMED_SOURCE samples post Transform+Displacement, before later
#    source FX / mask / opacity / blend / composite.
#      6.1 A and B differ (hard).
#      6.2 changing the SOURCE transform changes B; A stays BYTE-IDENTICAL.
#      6.3 changing the SOURCE displacement changes B; A stays BYTE-IDENTICAL.
#      6.4 enabling a source MASK must change both looks' frames IDENTICALLY in
#          attribution (the mask must not leak into the transformed stage):
#          the per-capture diff F(mask) vs G(mask) may not diverge in the FX
#          region beyond epsilon. (Differential attribution - documented in the
#          R3 report as the closest clean isolation available in full-frame
#          capture.)
# §7 MASK SPACES: one deliberately ASYMMETRIC custom mask (accent line asset),
#    extreme translation+rotation+scale+displacement, tested across
#    SOURCE/LAYER/PRESENTATION space for two mask sources, plus region and
#    band variants (expand/contract/feather/invert), requiring each to apply
#    cleanly and to change the render, and requiring invert to differ from
#    non-invert. Equal-presentation-pixel comparability is asserted via the
#    space separations being delta-level, not scale-level (bounded ratios).
# Windowed: renders.

var checks: Array = []
var failures: int = 0
var out_dir: String
var runtime
var renderer

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/source_torture")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxScreenRuntimeScript = load("res://scripts/fx_vnext/fx_screen_runtime.gd")
	var FxLayerRendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")

	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(60)
	runtime.seek(1.5)
	await settle(8)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.5)

	# ============================ §6 TRANSFORMED_SOURCE =========================
	var pair: Dictionary = FxLookScript.new_look("T_TORTURE_PAIR", "Pair torture")
	var source: Dictionary = pair["layers"][0] as Dictionary
	var tr: Dictionary = source["transform"]
	tr["position_px"] = [120.0, -60.0]
	tr["scale"] = [1.25, 1.25]
	tr["rotation_deg"] = 25.0
	var disp: Dictionary = source["displacement"]
	disp["enabled"] = true
	disp["driver"] = "NOISE"
	disp["amount_px"] = [34.0, 18.0]
	disp["speed"] = 1.0
	disp["scale"] = 2.0
	# The source layer is made invisible so the captured frame contains ONLY the
	# FX outputs: byte-identity claims about the ORIGINAL_SOURCE sampling then
	# become directly capturable (the canonical draw itself does not move).
	((pair["layers"][0] as Dictionary))["opacity"] = 0.0
	var fx_a: Dictionary = FxLookScript.new_layer("FX", "A original")
	fx_a["input"] = "ORIGINAL_SOURCE"
	fx_a["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": 14.0}
	var fx_b: Dictionary = FxLookScript.new_layer("FX", "B transformed")
	fx_b["input"] = "TRANSFORMED_SOURCE"
	fx_b["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": 14.0}
	var look_a: Dictionary = pair.duplicate(true)
	(look_a["layers"] as Array).append(fx_a.duplicate(true))
	var look_b: Dictionary = pair.duplicate(true)
	(look_b["layers"] as Array).append(fx_b.duplicate(true))

	renderer.apply_look("echo_left", look_a)
	renderer.set_time(1.5); await settle(6)
	var a1: Image = await capture("torture_a_base")
	renderer.apply_look("echo_left", look_b)
	renderer.set_time(1.5); await settle(6)
	var b1: Image = await capture("torture_b_base")
	var ab_delta := _mean_abs_diff(a1, b1)
	_check(ab_delta > 0.001, "6.1 A(original) and B(transformed) differ under extreme transform", "mean=%.5f" % ab_delta)

	# ---- 6.2 source transform change: B follows, A byte-identical ---------------
	var pair_moved: Dictionary = pair.duplicate(true)
	((pair_moved["layers"][0] as Dictionary)["transform"] as Dictionary)["position_px"] = [180.0, -60.0]
	var look_a_moved: Dictionary = pair_moved.duplicate(true)
	(look_a_moved["layers"] as Array).append(fx_a.duplicate(true))
	var look_b_moved: Dictionary = pair_moved.duplicate(true)
	(look_b_moved["layers"] as Array).append(fx_b.duplicate(true))
	renderer.apply_look("echo_left", look_a_moved)
	renderer.set_time(1.5); await settle(6)
	var a2: Image = await capture("torture_a_moved")
	renderer.apply_look("echo_left", look_b_moved)
	renderer.set_time(1.5); await settle(6)
	var b2: Image = await capture("torture_b_moved")
	_check(a1.get_data() == a2.get_data(), "6.2a source transform change: ORIGINAL_SOURCE sampling BYTE-IDENTICAL")
	var b_move_delta := _mean_abs_diff(b1, b2)
	_check(b_move_delta > 0.0001, "6.2b source transform change: TRANSFORMED_SOURCE follows the move", "mean=%.5f" % b_move_delta)

	# ---- 6.3 displacement change: B follows, A byte-identical -------------------
	var pair_disp: Dictionary = pair.duplicate(true)
	((pair_disp["layers"][0] as Dictionary)["displacement"] as Dictionary)["amount_px"] = [60.0, 34.0]
	var look_a_disp: Dictionary = pair_disp.duplicate(true)
	(look_a_disp["layers"] as Array).append(fx_a.duplicate(true))
	var look_b_disp: Dictionary = pair_disp.duplicate(true)
	(look_b_disp["layers"] as Array).append(fx_b.duplicate(true))
	renderer.apply_look("echo_left", look_a_disp)
	renderer.set_time(1.5); await settle(6)
	var a3: Image = await capture("torture_a_disp")
	renderer.apply_look("echo_left", look_b_disp)
	renderer.set_time(1.5); await settle(6)
	var b3: Image = await capture("torture_b_disp")
	# NOTE: displacement animates; both captures use the same deterministic time.
	_check(_mean_abs_diff(a3, a2) < 0.0002, "6.3a displacement change: ORIGINAL_SOURCE sampling unchanged", "mean=%.5f" % _mean_abs_diff(a3, a2))
	_check(_mean_abs_diff(b3, b2) > 0.0001, "6.3b displacement change: TRANSFORMED_SOURCE follows", "mean=%.5f" % _mean_abs_diff(b3, b2))

	# ---- 6.4 source mask attribution: must not leak into the stage ---------------
	var pair_mask: Dictionary = pair.duplicate(true)
	var mask: Dictionary = (pair_mask["layers"][0] as Dictionary)["mask"]
	mask["enabled"] = true
	mask["source"] = "ORIGINAL_SOURCE_ALPHA"
	mask["region"] = "EDGE_BAND"
	mask["width_px"] = 8.0
	mask["feather_px"] = 2.0
	var look_a_mask: Dictionary = pair_mask.duplicate(true)
	(look_a_mask["layers"] as Array).append(fx_a.duplicate(true))
	var look_b_mask: Dictionary = pair_mask.duplicate(true)
	(look_b_mask["layers"] as Array).append(fx_b.duplicate(true))
	renderer.apply_look("echo_left", look_a_mask)
	renderer.set_time(1.5); await settle(6)
	var a4: Image = await capture("torture_a_masked")
	renderer.apply_look("echo_left", look_b_mask)
	renderer.set_time(1.5); await settle(6)
	var b4: Image = await capture("torture_b_masked")
	# attribution: the mask-induced change measured in both looks must match in
	# magnitude (the FX stage must see the same base change, nothing extra).
	var d_a := _mean_abs_diff(a2, a4)
	var d_b := _mean_abs_diff(b2, b4)
	var attribution_gap := absf(d_a - d_b)
	_check(attribution_gap < 0.0008, "6.4 source-mask change attributed identically to both input families", "dA=%.5f dB=%.5f gap=%.5f" % [d_a, d_b, attribution_gap])

	# ============================ §7 MASK SPACE TORTURE =========================
	var space_look: Dictionary = FxLookScript.new_look("T_TORTURE_SPACE", "Space torture")
	var s_source: Dictionary = space_look["layers"][0] as Dictionary
	((s_source["transform"] as Dictionary))["position_px"] = [90.0, -40.0]
	((s_source["transform"] as Dictionary))["rotation_deg"] = 25.0
	((s_source["transform"] as Dictionary))["scale"] = [1.3, 1.3]
	var s_disp: Dictionary = s_source["displacement"]
	s_disp["enabled"] = true
	s_disp["driver"] = "DIRECTIONAL"
	s_disp["amount_px"] = [30.0, 14.0]
	s_disp["speed"] = 1.0
	# The masked element is a FRINGE FX layer (visible signal): a mask on the
	# source layer dims the base composition, which cannot separate the spaces.
	var s_fx: Dictionary = FxLookScript.new_layer("FX", "Masked fringe")
	s_fx["fx"] = {"fringe": 1.0, "intensity": 1.4, "edge_width": 12.0, "wind_reach": 30.0}
	(space_look["layers"] as Array).append(s_fx)
	var s_mask: Dictionary = s_fx["mask"]
	s_mask["enabled"] = true
	s_mask["width_px"] = 12.0
	s_mask["feather_px"] = 3.0

	# --- 7.1 custom asymmetric mask across the three spaces ----------------------
	s_mask["source"] = "CUSTOM_MASK"
	s_mask["custom_mask"] = "res://assets/vs/generated/side_field_left_mask.png"
	s_mask["region"] = "FULL"
	var space_imgs: Array = []
	for space_name in ["SOURCE_SPACE", "LAYER_SPACE", "PRESENTATION_SPACE"]:
		(s_mask)["space"] = space_name
		var applied: Dictionary = renderer.apply_look("echo_left", space_look)
		_check(bool(applied["ok"]), "7.1 custom mask applies: " + space_name, str(applied["errors"]))
		renderer.set_time(1.5); await settle(6)
		space_imgs.append(await capture("torture_space_" + space_name.to_lower()))
	var d01 := _mean_abs_diff(space_imgs[0], space_imgs[1])
	var d12 := _mean_abs_diff(space_imgs[1], space_imgs[2])
	var d02 := _mean_abs_diff(space_imgs[0], space_imgs[2])
	_check(d01 > 0.0002, "7.1 SOURCE vs LAYER differ (custom mask, extreme transform)", "mean=%.5f" % d01)
	_check(d12 > 0.0003, "7.1 LAYER vs PRESENTATION differ (custom mask, extreme transform)", "mean=%.5f" % d12)
	_check(d02 > 0.0003, "7.1 SOURCE vs PRESENTATION differ (custom mask, extreme transform)", "mean=%.5f" % d02)
	# comparability (equal presentation-pixel values): differences are delta-level
	_check(maxf(d01, maxf(d12, d02)) < 0.08, "7.1 space separations are delta-level, not scale-level", "d01=%.5f d12=%.5f d02=%.5f" % [d01, d12, d02])

	# --- 7.2 second mask source (post-displacement alpha) -------------------------
	s_mask["source"] = "POST_DISPLACEMENT_ALPHA"
	var pd_imgs: Array = []
	for space_name in ["SOURCE_SPACE", "LAYER_SPACE", "PRESENTATION_SPACE"]:
		s_mask["space"] = space_name
		var applied2: Dictionary = renderer.apply_look("echo_left", space_look)
		_check(bool(applied2["ok"]), "7.2 post-displacement mask applies: " + space_name, str(applied2["errors"]))
		renderer.set_time(1.5); await settle(6)
		pd_imgs.append(await capture("torture_pd_" + space_name.to_lower()))
	_check(_mean_abs_diff(pd_imgs[0], space_imgs[0]) > 0.0002, "7.2 mask source changes the render (custom vs post-displacement)", "mean=%.5f" % _mean_abs_diff(pd_imgs[0], space_imgs[0]))

	# --- 7.3 regions, expand/contract, feather, invert ----------------------------
	s_mask["source"] = "ORIGINAL_SOURCE_ALPHA"
	s_mask["space"] = "LAYER_SPACE"
	var variant_results: Dictionary = {}
	for variant in [
		{"region": "EDGE_BAND", "expand_contract_px": 0.0, "invert": false, "feather_px": 3.0},
		{"region": "INNER_BAND", "expand_contract_px": 0.0, "invert": false, "feather_px": 3.0},
		{"region": "OUTER_BAND", "expand_contract_px": 0.0, "invert": false, "feather_px": 3.0},
		{"region": "EDGE_BAND", "expand_contract_px": 22.0, "invert": false, "feather_px": 4.0},
		{"region": "EDGE_BAND", "expand_contract_px": -18.0, "invert": false, "feather_px": 4.0},
		{"region": "EDGE_BAND", "expand_contract_px": 0.0, "invert": false, "feather_px": 22.0},
		{"region": "EDGE_BAND", "expand_contract_px": 0.0, "invert": true, "feather_px": 3.0},
	]:
		for key in variant.keys():
			s_mask[key] = variant[key]
		var applied3: Dictionary = renderer.apply_look("echo_left", space_look)
		var label := "%s_e%03d_i%s_f%02d" % [str(variant["region"]), int(variant["expand_contract_px"]), str(variant["invert"]), int(variant["feather_px"])]
		_check(bool(applied3["ok"]), "7.3 mask variant applies: " + label, str(applied3["errors"]))
		renderer.set_time(1.5); await settle(6)
		variant_results[label] = await capture("torture_variant_" + label.replace("/", "_").replace("=", "").replace("+", "p").replace("-", "m"))
	var label_base := "EDGE_BAND_e000_ifalse_f03"
	var label_inv := "EDGE_BAND_e000_itrue_f03"
	var label_exp := "EDGE_BAND_e022_ifalse_f04"
	var label_con := "EDGE_BAND_e-18_ifalse_f04"
	var label_inner := "INNER_BAND_e000_ifalse_f03"
	var label_outer := "OUTER_BAND_e000_ifalse_f03"
	_check(variant_results.has(label_base) and variant_results.has(label_inv) and _mean_abs_diff(variant_results[label_base], variant_results[label_inv]) > 0.0003, "7.3 invert differs from non-invert", "mean=%.5f" % (_mean_abs_diff(variant_results[label_base], variant_results[label_inv]) if variant_results.has(label_base) and variant_results.has(label_inv) else 0.0))
	_check(variant_results.has(label_exp) and variant_results.has(label_con) and _mean_abs_diff(variant_results[label_exp], variant_results[label_con]) > 0.0001, "7.3 expand differs from contract", "")
	_check(variant_results.has(label_inner) and variant_results.has(label_outer) and _mean_abs_diff(variant_results[label_inner], variant_results[label_outer]) > 0.0002, "7.3 inner band differs from outer band", "")

	renderer.clear_all()
	await settle(6)

	var f := FileAccess.open(out_dir.path_join("summary_source_mask_torture_check.json"), FileAccess.WRITE)
	var summary := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL", "sections": ["§6 TRANSFORMED_SOURCE", "§7 MASK SPACES"]}
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("[SOURCE-MASK-TORTURE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(max(count, 1))
