extends SceneTree
# Phase 4 temporal model regressions (headless):
# TM-03 live envelopes; TM-04 manual trigger restarts; TM-07 range validation.
# TM-08 named event anchors fire at presentation event times.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const ScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	var runtime = ScreenRuntimeScript.new()
	root.add_child(runtime.subvp)
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "TM seed: runtime mounts")
	await settle(20)
	var renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	# ---- TM-03: envelope recomputed over live time --------------------------------
	var doc: Dictionary = FxLookScript.new_look("TM_ENVELOPE", "Envelope")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Rgb ramp")
	layer["input"] = "ORIGINAL_SOURCE"
	(layer["fx"] as Dictionary)["rgb"] = 1.0
	(layer["motion"] as Dictionary)["enabled"] = {"dither": false, "fringe": false, "flow": false, "rgb": true}
	((layer["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] = {
		"anchor": "manual", "anchor_time": 0.0, "delay": 0.0, "attack": 0.5,
		"hold": 0.0, "release": 0.5, "sustain": 0.0,
		"attack_curve": "cubic_out", "release_curve": "sine_in_out",
	}
	doc["layers"].append(layer)
	_check(bool(renderer.apply_composition([{"key": "echo_left", "look": doc}])["ok"]), "TM-03 enveloped composition commits")
	renderer.set_time(0.0)
	await settle(2)
	var v0 := _fx_rgb(renderer, "echo_left")
	renderer.set_time(0.25)
	await settle(2)
	var v1 := _fx_rgb(renderer, "echo_left")
	renderer.set_time(10.0)
	await settle(2)
	var v2 := _fx_rgb(renderer, "echo_left")
	_check(v0 < 0.05, "TM-03 envelope starts at zero", "v0=%.3f" % v0)
	_check(v1 > 0.2 and v1 < 1.0, "TM-03 envelope mid-attack live", "v1=%.3f" % v1)
	_check(v2 < 0.05, "TM-03 envelope decays to sustain", "v2=%.3f" % v2)

	# ---- TM-04: manual trigger restarts ----------------------------------------------
	renderer.trigger_manual("rgb")
	await settle(2)
	var v3 := _fx_rgb(renderer, "echo_left")
	_check(v3 < 0.05, "TM-04 trigger restarts envelope at zero", "v3=%.3f" % v3)
	renderer.set_time(10.25)
	await settle(2)
	var v4 := _fx_rgb(renderer, "echo_left")
	_check(v4 > 0.2, "TM-04 envelope runs again after trigger", "v4=%.3f" % v4)

	# ---- TM-08: named event anchors fire at presentation event times -----------
	# (UI-03 quality: event presets are real runtime semantic, not labels).
	renderer.set_event_marks({"clash_impact": 2.0, "hold_enter": 4.0})
	(((layer["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] as Dictionary)["anchor"] = "clash_impact"
	(((layer["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] as Dictionary)["attack"] = 1.0
	(((layer["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] as Dictionary)["release"] = 0.5
	renderer.apply_composition([{"key": "echo_left", "look": doc}])
	renderer.set_time(1.5)
	await settle(2)
	var e0 := _fx_rgb(renderer, "echo_left")
	_check(e0 < 0.05, "TM-08 event anchor silent before event time", "e0=%.3f" % e0)
	renderer.set_time(2.5)
	await settle(2)
	var e1 := _fx_rgb(renderer, "echo_left")
	_check(e1 > 0.2 and e1 < 1.0, "TM-08 event anchor runs after event time", "e1=%.3f" % e1)
	renderer.set_time(6.0)
	await settle(2)
	var e2 := _fx_rgb(renderer, "echo_left")
	_check(e2 < 0.05, "TM-08 event anchor decays after release", "e2=%.3f" % e2)
	# Unknown anchors fall back to fixed anchor_time (documented, historical).
	(((layer["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] as Dictionary)["anchor"] = "some_future_event"
	(((layer["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] as Dictionary)["anchor_time"] = 3.0
	renderer.apply_composition([{"key": "echo_left", "look": doc}])
	renderer.set_time(2.5)
	await settle(2)
	var f0 := _fx_rgb(renderer, "echo_left")
	_check(f0 < 0.05, "TM-08 unknown anchor holds fixed anchor_time (before)", "f0=%.3f" % f0)
	renderer.set_time(3.5)
	await settle(2)
	var f1 := _fx_rgb(renderer, "echo_left")
	_check(f1 > 0.2, "TM-08 unknown anchor holds fixed anchor_time (after)", "f1=%.3f" % f1)

	# ---- TM-07: persisted ranges agree with runtime clamps ------------------------------
	var bad: Dictionary = FxLookScript.materialize(FxLookScript.new_look("TM_BAD", "Bad"))
	var bad_layer: Dictionary = FxLookScript.new_layer("FX", "Bad")
	(((bad_layer as Dictionary)["motion"] as Dictionary)["tracks"] as Dictionary)["rgb"] = {
		"anchor": "manual", "anchor_time": -1.0, "delay": 0.0, "attack": 0.0,
		"hold": 0.0, "release": -0.5, "sustain": 2.0,
		"attack_curve": "cubic_out", "release_curve": "sine_in_out",
	}
	(bad as Dictionary)["layers"].append(bad_layer)
	var check: Dictionary = FxLookScript.validate(bad)
	_check(not bool(check.get("ok", false)), "TM-07 out-of-range motion rejected", str(check.get("errors", [])))
	var good: Dictionary = FxLookScript.materialize(FxLookScript.new_look("TM_GOOD", "Good"))
	var good_layer: Dictionary = FxLookScript.new_layer("FX", "Good")
	(good as Dictionary)["layers"].append(good_layer)
	_check(bool(FxLookScript.validate(good).get("ok", false)), "TM-07 neutral motion validates")

	print("[FX-TEMPORAL-MODEL] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _fx_rgb(renderer, key: String) -> float:
	var best := -999.0
	for quad_entry in renderer.stack_quads(key):
		var quad = (quad_entry as Dictionary).get("node", null)
		if quad is Control and str((quad as Control).name).begins_with("vnext_"):
			var mat = (quad as Control).material
			if mat is ShaderMaterial:
				best = maxf(best, float((mat as ShaderMaterial).get_shader_parameter("fx_rgb")))
	return best

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
