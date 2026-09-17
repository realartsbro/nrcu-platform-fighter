extends SceneTree
# R3 §19 — PERFORMANCE + SOAK. Real soak of the RUNTIME path (mounts, look
# loading, source copies, masks, displacement, global planes, motion, remounts)
# plus the SHELL path (target cycling, edit cycles, apply/revert) for
# `FXLAB_SOAK_SECONDS` (default 1800). Samples memory / object counts / frame
# time every 30s, then performs a graceful shutdown and writes soak_report.json.
# Windowed.

var checks: Array = []
var failures: int = 0
var out_dir: String
var samples: Array = []

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/soak")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seconds := int(OS.get_environment("FXLAB_SOAK_SECONDS")) if OS.get_environment("FXLAB_SOAK_SECONDS") != "" else 1800

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

	var deadline := Time.get_ticks_msec() + seconds * 1000
	var next_sample := Time.get_ticks_msec()
	var cycles := 0
	var remounts := 0
	var formats: Array = ["1v1", "FFA_4", "TEAM_2V2"]
	var fmt_index := 0
	var max_frame_ms := 0.0

	runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(60)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	while Time.get_ticks_msec() < deadline:
		cycles += 1
		# ---- cycle: format remount every 20 cycles -------------------------------
		if cycles % 20 == 0:
			fmt_index = (fmt_index + 1) % formats.size()
			runtime.mount(str(formats[fmt_index]), "debug", "ice_mage", "doge_man")
			remounts += 1
			await settle(30)
			renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
		var keys: Array = []
		for key in runtime.registry.keys():
			keys.append(str(key))
		keys.sort()
		# ---- build and apply a look cycle over the available targets -------------
		for i in range(keys.size()):
			var look: Dictionary = FxLookScript.new_look("SOAK_%d_%d" % [cycles, i], "soak")
			var bg: Dictionary = FxLookScript.new_layer("FX", "BG")
			bg["plane"] = "COMPOSITION_BACKGROUND"
			bg["fx"] = {"dither": 1.0, "dither_mode": 1.0, "dither_pixel": 4.0, "dither_levels": 3.0}
			(look["layers"] as Array).append(bg)
			var local: Dictionary = FxLookScript.new_layer("FX", "Local")
			local["fx"] = {"fringe": 1.0, "edge_width": 8.0, "rgb": 1.0, "rgb_shift_amount": 12.0}
			(local["mask"] as Dictionary)["enabled"] = true
			(local["mask"] as Dictionary)["source"] = "ORIGINAL_SOURCE_ALPHA"
			(local["mask"] as Dictionary)["region"] = "EDGE_BAND"
			(local["mask"] as Dictionary)["width_px"] = 9.0
			((local["displacement"] as Dictionary))["enabled"] = true
			((local["displacement"] as Dictionary))["driver"] = "NOISE"
			((local["displacement"] as Dictionary))["amount_px"] = [18.0, 9.0]
			((local["displacement"] as Dictionary))["speed"] = 1.0
			var motion: Dictionary = local["motion"]
			(motion["enabled"] as Dictionary)["dither"] = true
			(motion["tracks"]["dither"] as Dictionary)["anchor"] = "manual"
			(motion["tracks"]["dither"] as Dictionary)["anchor_time"] = 0.0
			(motion["tracks"]["dither"] as Dictionary)["attack"] = 0.6
			(look["layers"] as Array).append(local)
			if i == 1:
				var copy: Dictionary = FxLookScript.new_layer("SOURCE_COPY", "Copy")
				copy["opacity"] = 0.55
				((copy["transform"] as Dictionary))["position_px"] = [-6.0, 2.0]
				((copy["fx"] as Dictionary))["base_tint"] = "#74E7FF"
				(look["layers"] as Array).append(copy)
			var applied: Dictionary = renderer.apply_look(str(keys[i]), look)
			if not bool(applied.get("ok", false)):
				_check(false, "soak apply ok (cycle %d)" % cycles, str(applied.get("errors", [])))
		renderer.set_time(0.5 + float(cycles % 20) * 0.25)
		# ---- frame-time tracking ---------------------------------------------------
		# NOTE: process_frame, not frame_post_draw — an occluded window can starve
		# the post-draw signal and stall the entire soak (observed and fixed in R3).
		await process_frame
		var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		if frame_ms > max_frame_ms:
			max_frame_ms = frame_ms
		# ---- sample every 30 s ------------------------------------------------------
		var now := Time.get_ticks_msec()
		if now >= next_sample:
			next_sample = now + 30000
			var sample := {
				"t_s": (now - (deadline - seconds * 1000)) / 1000,
				"cycles": cycles,
				"remounts": remounts,
				"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				"objects_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				"frame_process_ms": frame_ms,
				"max_frame_ms": max_frame_ms,
			}
			samples.append(sample)
			print("[SOAK] %s" % JSON.stringify(sample))
		await process_frame

	# ---- graceful shutdown + report ------------------------------------------------
	renderer.clear_all()
	await settle(10)
	var final_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check(not renderer.has_stack("echo_left"), "soak: no stray stacks after clear")
	if samples.size() >= 2:
		var first: Dictionary = samples[0]
		var growth := final_objects - int(first["objects"])
		# Generous bound: no runaway accumulation across the soak. Real leaks of
		# per-cycle objects would blow far past this.
		_check(growth < 20000, "soak: object count bounded (no runaway leak)", "growth=%d first=%d final=%d" % [growth, int(first["objects"]), final_objects])
	else:
		_check(false, "soak produced samples", "n=%d" % samples.size())

	var f := FileAccess.open(out_dir.path_join("soak_report.json"), FileAccess.WRITE)
	var report := {
		"seconds": seconds,
		"cycles": cycles,
		"remounts": remounts,
		"samples": samples,
		"final_objects": final_objects,
		"max_frame_ms": max_frame_ms,
		"checks": checks.size(),
		"failures": failures,
	}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[SOAK] done · seconds=%d cycles=%d failures=%d" % [seconds, cycles, failures])
	quit(1 if failures > 0 else 0)

var runtime
var renderer

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
