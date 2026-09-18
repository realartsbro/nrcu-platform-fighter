extends SceneTree
# P0 MP event oracle (headless): FxScreenRuntime.event_marks() must equal the
# ACTUAL vs_screen schedule — never a second reconstruction. For every
# supported family: marks == schedule-derived table; for 1v1 + TEAM_2V2 +
# FFA_4 additionally: real-time emitted_at() matches marks; and MP marks
# drive envelopes through the shared renderer at the true MP clash time.
# (Pixel firing per format is covered 1v1 in the parity suite; the renderer
# and shader are format-independent.)

const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var checks: Array = []
var failures := 0

const FAMILIES := ["1v1", "FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1", "TEAM_3V1"]
const NAMES := ["vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]

func _init() -> void:
	for format in FAMILIES:
		await _oracle_family(str(format))
	# Realtime emission over ALL families (not a subset): the old 70ms MP
	# clash drift must fail here, so tolerance is frame-based (0.05s),
	# not the 0.15s that would have blessed the old bug.
	await _realtime("1v1")
	await _realtime("FFA_3")
	await _realtime("FFA_4")
	await _realtime("TEAM_2V2")
	await _realtime("TEAM_2V1")
	await _realtime("TEAM_3V1")
	await _mp_envelope()
	print("[FX-EVENT-ORACLE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _mount(format: String):
	var rt = FxScreenRuntimeScript.new()
	root.add_child(rt.subvp)
	await settle(20)
	var ok: bool = rt.mount(format, "debug", "ice_mage", "doge_man")
	await settle(10)
	return {"rt": rt, "ok": ok}

func _oracle_family(format: String) -> void:
	var h = await _mount(format)
	var rt = h["rt"]
	if not bool(h["ok"]) or str(rt.mode_format) != format:
		_check(false, "P0 oracle %s mounts" % format, "mode=%s" % str(rt.mode_format))
		rt.subvp.queue_free()
		await settle(4)
		return
	_check(true, "P0 oracle %s mounts" % format)
	var marks: Dictionary = rt.event_marks()
	var missing: Array = []
	for n in NAMES:
		if not marks.has(n):
			missing.append(n)
	_check(missing.is_empty(), "P0 oracle %s marks complete" % format, str(missing))
	# White-box equality against the schedule _process() really emits.
	var sched := {}
	sched["vs_enter"] = 0.0
	for ev_raw in rt.screen._entry_events:
		var ev: Dictionary = ev_raw
		var nm := str(ev.get("name", ""))
		if nm in NAMES and nm != "vs_enter":
			sched[nm] = float(ev.get("t", 0.0))
	sched["hold_enter"] = float(rt.screen.hold_start_time())
	_check(str(sched) == str(marks), "P0 oracle %s marks == screen schedule" % format, "marks=%s sched=%s" % [str(marks), str(sched)])
	# Midpoint-vs-band-end is proven by the realtime emission checks below:
	# had marks kept the old band-end reconstruction, emitted_at would miss.
	rt.subvp.queue_free()
	await settle(4)

func _realtime(format: String) -> void:
	var h = await _mount(format)
	var rt = h["rt"]
	if str(rt.mode_format) != format:
		_check(false, "P0 realtime %s mounts" % format)
		rt.subvp.queue_free()
		return
	var marks: Dictionary = rt.event_marks()
	var deadline := float(marks.get("clash_impact", 1.0)) + 1.5
	var frames := 0
	while float(rt.screen.get("_elapsed")) < deadline and frames < 36000:
		await process_frame
		frames += 1
	for n in NAMES:
		var at := float(rt.screen.emitted_at(str(n)))
		var want := float(marks.get(n, -99.0))
		_check(at >= 0.0 and absf(at - want) < 0.05, "P0 realtime %s %s emitted at mark" % [format, str(n)], "at=%.3f want=%.3f" % [at, want])
	rt.subvp.queue_free()
	await settle(4)

func _mp_envelope() -> void:
	# MP marks drive the shared renderer: anchor clash_impact with TEAM_2V2
	# marks must gate at the TRUE mp clash (midpoint), not the old band end.
	var h = await _mount("TEAM_2V2")
	var rt = h["rt"]
	var marks: Dictionary = rt.event_marks()
	var renderer = FxLayerRendererScript.new(rt.screen, rt.registry)
	renderer.set_event_marks(marks)
	var look: Dictionary = FxLookScript.new_look("ORACLEMP", "oracle")
	var layer: Dictionary = FxLookScript.new_layer("FX", "oracle")
	(layer["fx"] as Dictionary)["rgb"] = 2.0
	var motion: Dictionary = layer["motion"]
	(motion["enabled"] as Dictionary)["rgb"] = true
	var track: Dictionary = (motion["tracks"] as Dictionary)["rgb"]
	track["anchor"] = "clash_impact"
	track["anchor_time"] = 0.0
	track["attack"] = 0.3
	track["hold"] = 2.0
	track["release"] = 0.3
	look["layers"].append(layer)
	look = FxLookScript.materialize(look)
	# MP registries use family slot keys (no duel echo_left): style the
	# first available key — the envelope math is key-independent.
	var mp_keys: Array = rt.registry.keys()
	_check(not mp_keys.is_empty(), "P0 MP registry exposes family keys", str(mp_keys.size()))
	if mp_keys.is_empty():
		rt.subvp.queue_free()
		return
	var mp_key := str(mp_keys[0])
	renderer.apply_composition([{"key": mp_key, "look": look}])
	var clash := float(marks.get("clash_impact", 0.0))
	renderer.set_time(maxf(clash - 0.2, 0.0))
	await settle(4)
	var pre := _fx_rgb(renderer, mp_key)
	renderer.set_time(clash + 0.4)
	await settle(4)
	var post := _fx_rgb(renderer, mp_key)
	_check(pre < 0.05, "P0 MP envelope silent before true clash", "pre=%.3f clash=%.3f" % [pre, clash])
	_check(post > 0.5, "P0 MP envelope fires after true clash", "post=%.3f clash=%.3f" % [post, clash])
	rt.subvp.queue_free()
	await settle(4)

func _fx_rgb(renderer, key: String) -> float:
	# Max over quads: the first quad is usually the neutral SOURCE layer.
	var best := -1.0
	var stacks: Dictionary = renderer.get("_stacks")
	if not stacks.has(key):
		return -1.0
	for quad_entry in ((stacks[key] as Dictionary).get("quads", []) as Array):
		var quad = (quad_entry as Dictionary).get("node")
		if quad != null and is_instance_valid(quad) and (quad as Control).material is ShaderMaterial:
			best = maxf(best, float(((quad as Control).material as ShaderMaterial).get_shader_parameter("fx_rgb")))
	return best

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
	checks.append(line)
	if not ok:
		failures += 1
		print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame
