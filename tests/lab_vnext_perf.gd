extends SceneTree
# vNext performance harness — RAW frame-time data (independent-audit requirement).
# Protocol: 120 warm-up frames discarded per run, then 3 runs x 600 measured
# frames per case. Every sample is written to the JSON (no aggregation-only
# reporting). Windowed, vsync per project settings (free-running).

var out_dir: String
var runtime
var renderer

const WARMUP := 120
const RUNS := 3
const FRAMES := 600

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/performance")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxScreenRuntimeScript = load("res://scripts/fx_vnext/fx_screen_runtime.gd")
	var FxLayerRendererScript = load("res://scripts/fx_vnext/fx_layer_renderer.gd")

	# Measure free-running: vsync would cap every case at the display refresh
	# (144 Hz here) and hide all cost differences. Recorded in the protocol.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

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
	var mounted: bool = runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(80)
	print("[PERF] mounted=", mounted)
	runtime.seek(1.5)
	await settle(10)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.5)

	var report := {
		"hardware": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"window": DisplayServer.window_get_size(),
		"screen": "1280x720 presentation canvas",
		"protocol": {"warmup_frames": WARMUP, "runs": RUNS, "measured_frames": FRAMES, "vsync": "disabled at runtime (VSYNC_DISABLED) for free-running measurement"},
		"cases": [],
	}

	# ---- case builders ----------------------------------------------------------
	var neutral: Dictionary = FxLookScript.new_look("PERF_NEUTRAL", "Neutral")

	var rgb_look: Dictionary = FxLookScript.new_look("PERF_RGB", "RGB")
	var rgb_fx: Dictionary = FxLookScript.new_layer("FX", "RGB Tear")
	rgb_fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": 14.0}
	rgb_look["layers"].append(rgb_fx)

	var dither_look: Dictionary = FxLookScript.new_look("PERF_DITHER", "Dither")
	var dither_fx: Dictionary = FxLookScript.new_layer("FX", "Dither")
	dither_fx["fx"] = {"dither": 1.0, "intensity": 1.2, "dither_levels": 6.0, "dither_pixel": 2.0, "dither_gamma": 1.35, "dither_contrast": 1.6}
	dither_look["layers"].append(dither_fx)

	var fringe_look: Dictionary = FxLookScript.new_look("PERF_FRINGE", "Fringe")
	var fringe_fx: Dictionary = FxLookScript.new_layer("FX", "Fringe")
	fringe_fx["fx"] = {"fringe": 1.0, "intensity": 1.6, "pure_continuous": true, "edge_width": 12.0, "wind_reach": 54.0, "wind_trail": 1.0, "fringe_bleed": 1.0, "color_blur": 2.0, "rgb": 1.0, "rgb_shift": 18.0}
	fringe_look["layers"].append(fringe_fx)

	var displacement_look: Dictionary = FxLookScript.new_look("PERF_DISPLACE", "Displace")
	var disp_layer: Dictionary = displacement_look["layers"][0] as Dictionary
	disp_layer["displacement"] = {
		"enabled": true, "driver": "NOISE", "amount_px": [40.0, 18.0], "scale": 2.0,
		"speed": 1.0, "phase": 0.25, "seed": 7, "time_source": "PRESENTATION_TIME",
		"angle_deg": 0.0, "edge_mode": "MIRROR", "custom_texture": null, "influence_mask": null,
	}

	var two_copies: Dictionary = FxLookScript.new_look("PERF_COPIES", "Copies")
	for offset in [30.0, -40.0]:
		var copy: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Copy")
		(copy["transform"] as Dictionary)["position_px"] = [offset, 0.0]
		two_copies["layers"].append(copy)

	var composite_look: Dictionary = FxLookScript.new_look("PERF_COMPOSITE", "Composite")
	var comp_fx: Dictionary = FxLookScript.new_layer("FX", "Reads composite")
	comp_fx["input"] = "COMPOSITE_BELOW"
	comp_fx["fx"] = {"fringe": 1.6, "intensity": 1.4, "edge_width": 10.0, "wind_reach": 40.0, "wind_trail": 1.0, "fringe_bleed": 1.0}
	composite_look["layers"].append(comp_fx)

	var halo_look: Dictionary = FxLookScript.new_look("PERF_HALO", "Halo")
	var halo_fx: Dictionary = FxLookScript.new_layer("FX", "Halo")
	halo_fx["fx"] = {"fringe": 1.0, "intensity": 1.4, "edge_width": 16.0, "wind_reach": 120.0, "wind_trail": 1.0, "fringe_bleed": 1.0, "size": 1.4}
	halo_look["layers"].append(halo_fx)

	# ---- measurement -------------------------------------------------------------
	await gather(runtime, renderer, FxLookScript, report, "neutral_echo", "SOURCE-only neutral", neutral, "echo_left")
	await gather(runtime, renderer, FxLookScript, report, "fx_rgb_echo", "one FX layer: RGB tear", rgb_look, "echo_left")
	await gather(runtime, renderer, FxLookScript, report, "fx_dither_echo", "one FX layer: dither treatment", dither_look, "echo_left")
	await gather(runtime, renderer, FxLookScript, report, "fx_fringe_mark", "one FX layer: fringe (pure continuous) on VS mark", fringe_look, "mark")
	await gather(runtime, renderer, FxLookScript, report, "displacement_echo", "SOURCE displacement (NOISE, mirror edges)", displacement_look, "echo_left")
	await gather(runtime, renderer, FxLookScript, report, "two_source_copies", "two SOURCE_COPY layers", two_copies, "echo_left")
	await gather(runtime, renderer, FxLookScript, report, "composite_below", "FX reading COMPOSITE_BELOW + fringe", composite_look, "echo_left")
	await gather(runtime, renderer, FxLookScript, report, "large_halo", "large halo / overscan (wind 120, size 1.4)", halo_look, "echo_left")

	# FFA4 multi-target stress
	renderer.clear_all()
	runtime.mount("FFA_4", "debug", "ice_mage", "doge_man")
	await settle(80)
	runtime.seek(1.5)
	await settle(10)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.5)
	var applied_ffa := 0
	var ffa_keys: Array = []
	for key in runtime.registry.slot_nodes.keys():
		var role := str(runtime.registry.role_for_key(str(key)))
		if role == "PRIMARIES" or role == "ECHOES":
			ffa_keys.append(str(key))
	ffa_keys.sort()
	for i in range(mini(4, ffa_keys.size())):
		var look_id := "PERF_FFA_%d" % i
		var ffa_look: Dictionary = FxLookScript.new_look(look_id, "FFA look %d" % i)
		var ffa_fx: Dictionary = FxLookScript.new_layer("FX", "fx")
		ffa_fx["fx"] = {"fringe": 1.0, "intensity": 1.2, "edge_width": 10.0, "wind_reach": 32.0, "wind_trail": 0.5}
		if i % 2 == 0:
			ffa_fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": 10.0}
		ffa_look["layers"].append(ffa_fx)
		var res: Dictionary = renderer.apply_look(str(ffa_keys[i]), ffa_look)
		if bool(res.get("ok", false)):
			applied_ffa += 1
	print("[PERF] ffa4 targets with looks: ", applied_ffa, " of ", ffa_keys.size())
	await gather_raw(report, "ffa4_multitarget_stress", "FFA_4 with %d styled targets" % applied_ffa)

	var f := FileAccess.open(out_dir.path_join("perf_raw.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[PERF] raw data written: perf_raw.json")
	quit(0)

func gather(_runtime, _renderer, _look_script, report: Dictionary, case_id: String, description: String, look: Dictionary, target: String) -> void:
	renderer.clear_all()
	var applied: Dictionary = renderer.apply_look(target, look)
	print("[PERF] apply ", case_id, " -> ", applied.get("ok", false), " ", applied.get("errors", []))
	renderer.set_time(1.5)
	await settle(20)
	await gather_raw(report, case_id, description)

func gather_raw(report: Dictionary, case_id: String, description: String) -> void:
	var runs: Array = []
	for run_index in range(RUNS):
		for i in range(WARMUP):
			await RenderingServer.frame_post_draw
		var samples: Array = []
		var frames := 0
		var previous := Time.get_ticks_usec()
		while frames < FRAMES:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
			frames += 1
		runs.append(samples)
		print("[PERF] ", case_id, " run ", run_index, " frames=", samples.size())
	var stats: Array = []
	for samples in runs:
		stats.append(_stats(samples))
	report["cases"].append({
		"id": case_id,
		"description": description,
		"runs": runs,
		"stats": stats,
	})

func _stats(samples: Array) -> Dictionary:
	var sorted_samples: Array = samples.duplicate()
	sorted_samples.sort()
	var count: int = sorted_samples.size()
	if count == 0:
		return {}
	var median: float = float(sorted_samples[count / 2])
	var p95: float = float(sorted_samples[mini(count - 1, int(count * 0.95))])
	var total := 0.0
	for value in samples:
		total += float(value)
	return {
		"min_ms": float(sorted_samples[0]),
		"median_ms": median,
		"p95_ms": p95,
		"max_ms": float(sorted_samples[count - 1]),
		"mean_ms": total / float(count),
		"median_fps": 1000.0 / maxf(median, 0.0001),
	}

func settle(n: int) -> void:
	for i in n:
		await process_frame
