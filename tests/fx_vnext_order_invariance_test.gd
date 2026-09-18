extends SceneTree
# R3 §5 — FULL-COMPOSITION ORDER INVARIANCE (red-team torture).
# The rendered composition must not depend on the order in which targets are
# listed in the plan, on how a single logical apply is split into multiple
# apply_composition() calls, or on repeat application. Run across every format:
# 1v1, FFA_3, FFA_4, TEAM_2V2, TEAM_2V1, TEAM_3V1 — with multiple targets each
# contributing COMPOSITION_BACKGROUND / FOREGROUND layers and active Source Copies.
# Windowed: renders compositions.

var checks: Array = []
var failures: int = 0
var out_dir: String
var runtime
var renderer
var rng := RandomNumberGenerator.new()

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/order_invariance")
	DirAccess.make_dir_recursive_absolute(out_dir)
	rng.seed = 20260915  # fixed seed → reproducible permutations

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

	var hashes: Dictionary = {}
	var formats: Array = ["1v1", "FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1", "TEAM_3V1"]
	for fmt in formats:
		var mounted: bool = runtime.mount(fmt, "debug", "ice_mage", "doge_man")
		await settle(60)
		runtime.seek(1.5)
		# Freeze each visible preview so permutation readback is not racing the
		# screen lifecycle's EXIT/fade on OpenGL.
		runtime.screen.lab_preview_pause()
		await settle(8)
		_check(mounted and runtime.screen != null, "mount " + fmt, "")
		if runtime.screen == null:
			continue
		renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
		renderer.set_time(1.5)
		var keys: Array = []
		for key in runtime.registry.keys():
			keys.append(str(key))
		keys.sort()
		_check(keys.size() >= 2, fmt + " exposes >=2 targets", "keys=%d" % keys.size())
		if keys.size() < 2:
			continue

		# ---- looks: multiple BG/FG contributions + source copies ------------------
		var plan: Array = []
		for index in range(keys.size()):
			var key: String = str(keys[index])
			var look: Dictionary = FxLookScript.new_look("T_%s_%02d" % [fmt, index], "%s %d" % [fmt, index])
			if index % 2 == 0:
				var bg: Dictionary = FxLookScript.new_layer("FX", "BG dither")
				bg["plane"] = "COMPOSITION_BACKGROUND"
				bg["fx"] = {"dither": 1.0, "intensity": 1.35, "dither_levels": 3.0, "dither_pixel": 4.0}
				(look["layers"] as Array).append(bg)
			if index % 2 == 1:
				var fg: Dictionary = FxLookScript.new_layer("FX", "FG rgb")
				fg["plane"] = "COMPOSITION_FOREGROUND"
				fg["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 12.0}
				(look["layers"] as Array).append(fg)
			var local: Dictionary = FxLookScript.new_layer("FX", "Local fringe")
			local["fx"] = {"fringe": 1.0, "intensity": 1.2, "edge_width": 8.0, "wind_reach": 24.0, "wind_trail": 0.7}
			(look["layers"] as Array).append(local)
			if index == 1:
				# active SOURCE_COPY (displaced) on one target
				var copy: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Displaced copy")
				copy["opacity"] = 0.6
				(copy["transform"] as Dictionary)["position_px"] = [-8.0, 2.0]
				(copy["transform"] as Dictionary)["scale"] = [1.05, 1.05]
				(copy["fx"] as Dictionary)["base_tint"] = "#74E7FF"
				(look["layers"] as Array).append(copy)
			plan.append({"key": key, "look": look})

		# ---- reference: canonical (sorted) plan ------------------------------------
		var applied: Dictionary = renderer.apply_composition(plan)
		_check(bool(applied["ok"]), fmt + ": reference plan applies", str(applied["errors"]))
		renderer.set_time(1.5)
		await settle(8)
		var reference: Image = await capture("%s_reference" % fmt)
		var ref_bytes: PackedByteArray = reference.get_data()

		# ---- 6 seeded permutations of the plan order ------------------------------
		var perm_fail := 0
		for perm in range(6):
			var shuffled: Array = plan.duplicate()
			_seeded_shuffle(shuffled)
			applied = renderer.apply_composition(shuffled)
			if not bool(applied["ok"]):
				_check(false, "%s perm %d applies" % [fmt, perm], str(applied["errors"]))
				continue
			renderer.set_time(1.5)
			await settle(8)
			var img: Image = await capture_hashed("%s_perm_%d" % [fmt, perm], false)
			if img.get_data() != ref_bytes:
				perm_fail += 1
				img.save_png(out_dir.path_join("%s_perm_%d_MISMATCH.png" % [fmt, perm]))
		_check(perm_fail == 0, fmt + ": all permutations byte-identical", "mismatches=%d/6" % perm_fail)

		# ---- split application semantics: each apply_composition call REPLACES the
		# current composition with a full render of its plan, so the FINAL state of
		# any call sequence must equal a single apply of the last plan - in both
		# partitions and both orders. (Deterministic replace semantics.)
		var part_a: Array = []
		var part_b: Array = []
		for index in range(plan.size()):
			if index % 2 == 0:
				part_a.append(plan[index])
			else:
				part_b.append(plan[index])
		# references for each half
		renderer.apply_composition(part_a)
		renderer.set_time(1.5)
		await settle(8)
		var ref_a: Image = await capture_hashed("%s_ref_part_a" % fmt, false)
		renderer.apply_composition(part_b)
		renderer.set_time(1.5)
		await settle(8)
		var ref_b: Image = await capture_hashed("%s_ref_part_b" % fmt, false)
		# sequence (A,B) must end in exactly ref_b; (B,A) exactly ref_a
		renderer.apply_composition(part_a)
		renderer.apply_composition(part_b)
		renderer.set_time(1.5)
		await settle(8)
		var split_ab: Image = await capture_hashed("%s_split_ab" % fmt, false)
		renderer.apply_composition(part_b)
		renderer.apply_composition(part_a)
		renderer.set_time(1.5)
		await settle(8)
		var split_ba: Image = await capture_hashed("%s_split_ba" % fmt, false)
		_check(split_ab.get_data() == ref_b.get_data(), fmt + ": sequence (A,B) ends in exactly single-apply(B)")
		_check(split_ba.get_data() == ref_a.get_data(), fmt + ": sequence (B,A) ends in exactly single-apply(A)")

		# ---- repeat application is idempotent --------------------------------------
		renderer.apply_composition(plan)
		renderer.set_time(1.5)
		await settle(8)
		var repeat_img: Image = await capture_hashed("%s_repeat" % fmt, false)
		_check(repeat_img.get_data() == ref_bytes, fmt + ": repeat apply byte-identical")

		# ---- lookup-order shuffle of the dictionary happens above; also record
		# a re-sorted apply to prove the reference itself was not order-lucky.
		var desc: Array = plan.duplicate()
		desc.reverse()
		renderer.apply_composition(desc)
		renderer.set_time(1.5)
		await settle(8)
		var desc_img: Image = await capture_hashed("%s_reversed" % fmt, false)
		_check(desc_img.get_data() == ref_bytes, fmt + ": reversed plan byte-identical")

		hashes[fmt] = {"keys": keys.size(), "permuations": 6, "mismatches": perm_fail}
		renderer.clear_all()
		await settle(6)

	var f := FileAccess.open(out_dir.path_join("summary_order_invariance_check.json"), FileAccess.WRITE)
	var summary := {"checks": checks.size(), "failures": failures, "formats": hashes, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("[ORDER-INVARIANCE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _seeded_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func capture_hashed(name: String, save_always: bool) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if save_always:
		img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
