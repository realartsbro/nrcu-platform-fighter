extends SceneTree
# P0 event-authority parity (windowed, reference scene): a production look
# with anchor=clash_impact must fire at the canonical event time through the
# reference nrcu_vs_runtime.tscn consumption path — never silently at
# anchor_time. The renderer is NEVER configured directly here; marks flow
# from FxScreenRuntime.event_marks() on both lab and runtime paths.
#
# Discriminator: anchor_time=0.1 (fixed fallback would fire at 0.1) while
# clash_impact ~= 0.615/0.66 (event path fires at event+0.1). A capture at
# t=0.3 shows the effect ONLY under the fallback — absent means parity.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const RuntimeScene := preload("res://scenes/nrcu_vs_runtime.tscn")

var checks: Array = []
var failures := 0
var out_dir: String
var data_dir: String

func _init() -> void:
	out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/event_parity")
	DirAccess.make_dir_recursive_absolute(out_dir)
	data_dir = out_dir.path_join("production_data")
	_wipe_dir(data_dir)
	DirAccess.make_dir_recursive_absolute(data_dir)
	OS.set_environment("NRCU_FX_DATA_DIR", data_dir)
	OS.set_environment("NRCU_VS_FORMAT", "1v1")
	_seed_production()
	await _prove_1v1()
	await _prove_mp_marks()
	print("[FX-EVENT-PARITY] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _seed_production() -> void:
	var prod := FxProductionScript.new()
	prod.data_dir = data_dir
	var look: Dictionary = FxLookScript.new_look("EVENT_PARITY_LOOK", "Event parity", "PRODUCTION")
	var layer: Dictionary = FxLookScript.new_layer("FX", "clash fringe")
	var fx: Dictionary = layer["fx"]
	fx["fringe"] = 2.5
	fx["intensity"] = 1.5
	fx["edge_width"] = 12.0
	var motion: Dictionary = layer["motion"]
	(motion["enabled"] as Dictionary)["fringe"] = true
	var track: Dictionary = (motion["tracks"] as Dictionary)["fringe"]
	track["anchor"] = "clash_impact"
	track["anchor_time"] = 0.1
	track["delay"] = 0.0
	track["attack"] = 0.5
	track["hold"] = 2.0
	track["release"] = 0.5
	look["layers"].append(layer)
	look = FxLookScript.materialize(look)
	_check(bool(prod.apply({"look": look})["ok"]), "P0 parity look applies")
	var probe := FxScreenRuntimeScript.new()
	root.add_child(probe.subvp)
	await settle(30)
	probe.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(30)
	var doc: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(doc, FxResolverScript.normalize_selector(probe.registry.context_for_key("echo_left")), "EVENT_PARITY_LOOK", "event parity binding")
	_check(bool(prod.apply({"assignments": doc})["ok"]), "P0 parity assignment applies")
	probe.subvp.queue_free()
	await settle(6)

func _prove_1v1() -> void:
	root.size = Vector2i(1280, 720)
	await settle(10)
	var rt = RuntimeScene.instantiate()
	root.add_child(rt)
	# Capture isolation (researcher C): the scene's own stretch=true container
	# never composited into window captures, so the harness displays the
	# reference runtime un-stretched, exactly like the lab shell does.
	var cont = (rt as Control).get_child(0) as SubViewportContainer
	cont.stretch = false
	cont.size = Vector2(1280, 720)
	cont.custom_minimum_size = Vector2(1280, 720)
	await settle(90)
	rt.seek(0.3)
	rt.reload_production()
	await settle(10)
	# Harness timing: uncapped script-mode frames can outrun first-frame
	# shader/viewport warmup — give the compositor a real beat.
	OS.delay_msec(2500)
	await settle(10)
	_check(int(rt.last_summary.get("styled_targets", 0)) > 0, "P0 production plan styles targets", str(rt.last_summary))
	_check(int((rt.renderer.get("_stacks") as Dictionary).size()) > 0, "P0 renderer owns stacks", str((rt.renderer.get("_stacks") as Dictionary).keys()))
	# Integration: the scene's renderer owns the canonical table (not empty,
	# all five canonical names — no silent fallback for known events).
	var marks: Dictionary = rt.renderer.get("_event_marks")
	var names := ["vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]
	var missing: Array = []
	for n in names:
		if not marks.has(n):
			missing.append(n)
	_check(missing.is_empty(), "P0 runtime renderer owns all canonical events", str(missing))
	_check(marks.size() == 5, "P0 runtime event table has exactly the canonical five", str(marks.keys()))
	var clash := float(marks.get("clash_impact", -1.0))
	# Before the event: fixed-fallback (anchor_time=0.1) would already show
	# the fringe; the event path shows nothing yet.
	rt.seek(0.3)
	await settle(10)
	var pre: Image = await capture_runtime(rt, "parity_1v1_pre")
	var fringe_pre := _stack_fringe(rt)
	# Lifetime: seeks past minimum_exposure must never self-teardown the
	# preview-owned composition (regression for the freed-slot failure).
	_check(is_instance_valid(rt.runtime.screen), "P0 preview screen survives post-exposure seeks")
	rt.seek(clash + 0.1 + 0.6)
	await settle(10)
	var post: Image = await capture_runtime(rt, "parity_1v1_post")
	var fringe_post := _stack_fringe(rt)
	_check(fringe_pre < 0.05, "P0 pre-event fringe uniform gated to zero", str(fringe_pre))
	_check(fringe_post > 1.0, "P0 post-event fringe uniform carries the envelope", str(fringe_post))
	_check(_mean_abs_diff(pre, post) > 0.002, "P0 clash_impact fires the envelope via the real scene", "mean=%.5f clash=%.3f" % [_mean_abs_diff(pre, post), clash])
	# Seek reconstructs deterministically.
	rt.seek(0.3)
	await settle(10)
	var pre2: Image = await capture_runtime(rt, "parity_1v1_pre_again")
	_check(_mean_abs_diff(pre, pre2) < 0.0005, "P0 pre-event seek reconstructs deterministically", "mean=%.6f" % _mean_abs_diff(pre, pre2))
	# Reload keeps event semantics (re-asserted table + still fires).
	rt.reload_production()
	await settle(10)
	var marks2: Dictionary = rt.renderer.get("_event_marks")
	_check(str(marks2) == str(marks), "P0 reload keeps the identical event table")
	rt.seek(clash + 0.1 + 0.6)
	await settle(10)
	var post2: Image = await capture_runtime(rt, "parity_1v1_post_reload")
	_check(_mean_abs_diff(post, post2) < 0.0005, "P0 reload keeps event firing", "mean=%.6f" % _mean_abs_diff(post, post2))
	# Remount delivers the same table.
	rt.runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(30)
	var marks3: Dictionary = rt.runtime.event_marks()
	_check(str(marks3) == str(marks), "P0 remount delivers the identical event table")
	rt.queue_free()
	await settle(6)

func _prove_mp_marks() -> void:
	OS.set_environment("NRCU_VS_FORMAT", "TEAM_2V2")
	var rt = RuntimeScene.instantiate()
	root.add_child(rt)
	await settle(90)
	_check(str(rt.runtime.mode_format) == "TEAM_2V2", "P0 MP runtime mounts multiplayer", rt.runtime.mode_format)
	var marks: Dictionary = rt.renderer.get("_event_marks")
	var missing: Array = []
	for n in ["vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]:
		if not marks.has(n):
			missing.append(n)
	_check(missing.is_empty(), "P0 MP renderer owns all canonical events", str(missing))
	_check(str(rt.runtime.event_marks()) == str(marks), "P0 MP renderer table equals the authority table")
	rt.queue_free()
	OS.set_environment("NRCU_VS_FORMAT", "1v1")
	await settle(6)

func _stack_fringe(rt) -> float:
	var best := -1.0
	var stacks: Dictionary = rt.renderer.get("_stacks")
	for key in stacks.keys():
		for quad_entry in (stacks[key] as Dictionary).get("quads", []):
			var quad = (quad_entry as Dictionary).get("node")
			if quad != null and is_instance_valid(quad) and (quad as Control).material != null:
				best = maxf(best, float(((quad as Control).material as ShaderMaterial).get_shader_parameter("fx_fringe")))
	return best

func settle(n: int) -> void:
	for i in n:
		await process_frame

# The reference runtime's own viewport is the consumption surface. Capturing
# an outer harness viewport through nested SubViewportContainers proved
# unreliable (flat clear-color reads); the inner texture is authoritative.
func capture_runtime(_rt, name: String) -> Image:
	return await capture_root(name)

func capture_root(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
	checks.append(line)
	if not ok:
		failures += 1
		print(line)

func _wipe_dir(dir_path: String) -> void:
	var abs := dir_path
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))

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
