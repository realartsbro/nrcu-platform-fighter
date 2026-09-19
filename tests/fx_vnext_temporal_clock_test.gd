extends SceneTree
# Phase 4 clock regressions (windowed — needs real frames + shell):
# TM-01 playback advances the presentation lifecycle without implicitly
# advancing the authoring FX clock; TM-02 numeric entry syncs both clocks;
# TM-05 seeks reconstruct ENTRY/HOLD/EXIT; TM-06 seeks and edits never steal
# the user's play/pause choice; TM-07 keeps direct lifecycle seeks separate
# from explicit shell authoring transport.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var shell: Control
var checks: Array = []
var failures := 0

func _init() -> void:
	shell = _spawn()
	await settle(30)
	_seed()
	shell._render_current_look()
	await settle(5)
	await _tm01_playback_advances_fx_clock()
	await _tm02_numeric_entry_syncs()
	await _tm05_exit_seekable()
	_tm06_seek_keeps_play_choice()
	print("[FX-TEMPORAL-CLOCK] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _seed() -> void:
	var doc: Dictionary = FxLookScript.new_look("TM_CLOCK", "Clock")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Rgb")
	layer["input"] = "ORIGINAL_SOURCE"
	(layer["fx"] as Dictionary)["rgb"] = 1.0
	doc["layers"].append(layer)
	shell.production.apply({"look": doc})

func _quad_fx_time() -> float:
	var best := -1.0
	if shell.renderer == null:
		return best
	for key in shell.renderer._stacks.keys():
		for quad_entry in shell.renderer._all_quad_entries(shell.renderer._stacks[key]):
			var quad = (quad_entry as Dictionary).get("node", null)
			if quad is Control and str((quad as Control).name).begins_with("vnext_"):
				var mat = (quad as Control).material
				if mat is ShaderMaterial:
					best = maxf(best, float((mat as ShaderMaterial).get_shader_parameter("fx_time")))
	return best

func _tm01_playback_advances_fx_clock() -> void:
	shell.renderer.apply_composition([{"key": "mark", "look": (shell.production.load_look("TM_CLOCK") as Dictionary)["doc"]}])
	var screen = shell.runtime.screen
	var authoring_t0 := float(shell.renderer.clock_state().get("presentation_time", -1.0))
	# Direct lifecycle control enters the open-ended HOLD without touching the
	# shell's authoring/evaluation playhead.
	screen.lab_preview_seek(screen.hold_start_time() + 0.05)
	screen.lab_preview_resume()
	var lifecycle_t0 := float(screen.elapsed())
	await settle(30)
	var lifecycle_t1 := float(screen.elapsed())
	var authoring_t1 := float(shell.renderer.clock_state().get("presentation_time", -1.0))
	_check(str(screen.state()) == "hold" and lifecycle_t1 > lifecycle_t0 + 0.2 and absf(authoring_t1 - authoring_t0) < 0.01, "TM-01 open-ended lifecycle advances without implicit authoring FX-time mutation", "lifecycle=%.2f->%.2f authoring=%.2f->%.2f" % [lifecycle_t0, lifecycle_t1, authoring_t0, authoring_t1])
	screen.lab_preview_pause()

func _tm02_numeric_entry_syncs() -> void:
	shell._on_time_entered(1.2)
	await settle(4)
	var ft := _quad_fx_time()
	var el: float = shell.runtime.elapsed()
	_check(absf(ft - 1.2) < 0.05 and absf(el - 1.2) < 0.05, "TM-02 numeric entry syncs both clocks", "fx=%.2f elapsed=%.2f" % [ft, el])

func _tm05_exit_seekable() -> void:
	var screen = shell.runtime.screen
	var hold: float = screen.hold_start_time()
	var expo: float = screen.minimum_exposure()
	screen.lab_preview_seek(0.05)
	_check(str(screen.state()) == "entry", "TM-05 early seek reconstructs ENTRY", str(screen.state()))
	screen.lab_preview_seek(hold + 0.05)
	_check(str(screen.state()) == "hold", "TM-05 mid seek reconstructs HOLD", str(screen.state()))
	screen.lab_preview_seek(expo + 0.3)
	await settle(2)
	_check(str(screen.state()) == "exit", "TM-05 late seek reconstructs EXIT", str(screen.state()))
	_check(bool(screen.match_ready_signalled()), "TM-05 EXIT seek keeps match-ready", str(screen.match_ready_signalled()))
	var direct_authoring_t := float(shell.renderer.clock_state().get("presentation_time", -1.0))
	var direct_spin_t := float(shell.time_spin.value)
	screen.lab_preview_seek(24.0)
	await settle(3)
	var direct_after_t := float(shell.renderer.clock_state().get("presentation_time", -1.0))
	_check(absf(direct_after_t - direct_authoring_t) < 0.01 and absf(float(shell.time_spin.value) - direct_spin_t) < 0.01, "TM-07 direct screen lifecycle seek leaves authoring playhead unchanged", "spin=%.3f->%.3f fx=%.3f->%.3f" % [direct_spin_t, float(shell.time_spin.value), direct_authoring_t, direct_after_t])
	# Only explicit shell transport clamps and synchronizes the bounded
	# authoring/evaluation clock to the visible timeline.
	shell._on_time_entered(24.0)
	await settle(3)
	var explicit_t := float(shell.renderer.clock_state().get("presentation_time", -1.0))
	_check(absf(float(shell.time_spin.value) - float(shell.TIMELINE_LEN)) < 0.01 and absf(explicit_t - float(shell.TIMELINE_LEN)) < 0.01, "TM-07 explicit shell transport clamps authoring clock beyond presentation hold", "spin=%.3f fx=%.3f" % [float(shell.time_spin.value), explicit_t])
	_check(str(shell.timeline_time_label.text).begins_with("T 2.400 / 2.400"), "TM-07 explicit shell transport updates bounded visible clock", shell.timeline_time_label.text)

func _tm06_seek_keeps_play_choice() -> void:
	var screen = shell.runtime.screen
	screen.lab_preview_pause()
	_check(bool(screen.lab_preview_is_paused()), "TM-06 paused baseline")
	screen.lab_preview_seek(0.4)
	_check(bool(screen.lab_preview_is_paused()), "TM-06 seek while paused stays paused")
	screen.lab_preview_resume()
	_check(not bool(screen.lab_preview_is_paused()), "TM-06 resumed baseline")
	screen.lab_preview_seek(0.5)
	_check(not bool(screen.lab_preview_is_paused()), "TM-06 seek while playing stays playing")
	screen.lab_preview_pause()

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
