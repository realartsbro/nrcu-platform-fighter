extends SceneTree
# Round-2 mandated adversarial tests (contract "Zusätzliche adversariale Tests"):
# disable-exact → generic fallback, bypass → no fallback, dirty switch + restart
# recovery, corrupted production JSON, duplicate layer ids, multi-format
# compositions (FFA_4, TEAM_2V2) with all relevant production looks active.
# Windowed: renders the multi-format compositions.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/adversarial")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var prod_dir := "user://vnext_adv_prod"
	var draft_dir := "user://vnext_adv_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	var ctx := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}

	# ---- 1. disable the exact assignment -> generic fallback resolves -----------
	_check(bool(prod.apply({"look": _look("LOOK_A", 10.0)})["ok"]), "look A written")
	_check(bool(prod.apply({"look": _look("LOOK_B", 30.0)})["ok"]), "look B written")
	var doc: Dictionary = FxResolverScript.new_assignments()
	var specific := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}
	var generic := {"element_role": "echo"}
	FxResolverScript.upsert_binding(doc, specific, "LOOK_A", "specific")
	FxResolverScript.upsert_binding(doc, generic, "LOOK_B", "generic")
	_check(bool(prod.apply({"assignments": doc})["ok"]), "bindings written")
	var res_specific: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], ctx)
	_check(str(res_specific.get("look_id", "")) == "LOOK_A", "specific wins while enabled", str(res_specific.get("look_id", "")))
	# disable the exact binding
	var doc2: Dictionary = prod.load_assignments()["doc"]
	for raw in doc2["bindings"]:
		if str((raw as Dictionary).get("look_id", "")) == "LOOK_A":
			(raw as Dictionary)["enabled"] = false
	_check(bool(prod.apply({"assignments": doc2})["ok"]), "exact binding disabled")
	var res_fallback: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], ctx)
	_check(str(res_fallback.get("status", "")) == "ASSIGNED" and str(res_fallback.get("look_id", "")) == "LOOK_B", "disabled exact assignment falls back to the generic one", str(res_fallback.get("look_id", "")))

	# ---- 2. explicit styling bypass -> NO fallback ------------------------------
	var doc3: Dictionary = prod.load_assignments()["doc"]
	doc3["bypasses"] = [{"bypass_id": "bypass-test-0001", "selector": specific.duplicate(), "enabled": true}]

	var check_bypass: Dictionary = prod.apply({"assignments": doc3})
	_check(bool(check_bypass["ok"]), "bypass written", str(check_bypass.get("errors", [])))
	var res_bypass: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], ctx)
	_check(str(res_bypass.get("status", "")) == "BYPASSED", "styling bypass status", str(res_bypass.get("status", "")))
	_check(str(res_bypass.get("look_id", "")) == "", "bypass resolves to NO style (no generic fallback)", str(res_bypass.get("look_id", "")))

	# ---- 3. dirty target switch + restart recovery -------------------------------
	var session = FxSessionScript.new(prod, drafts)
	var sig := "adv-sig-0001"
	session.open_target("echo_left", ctx.duplicate(), sig, "echo")
	var first_id := str((session.look["layers"][0] as Dictionary).get("layer_id", ""))
	var edited: Dictionary = session.edit(func(sdoc):
		var l: Dictionary = FxLookScript.find_layer(sdoc, first_id)
		l["opacity"] = 0.42
	)
	_check(bool(edited.get("ok", false)) and session.dirty, "edit marks session dirty")
	session.stash()
	# "restart": a fresh session over the same stores
	var session2 = FxSessionScript.new(prod, drafts)
	session2.open_target("echo_left", ctx.duplicate(), sig, "echo")
	var restored := str((FxLookScript.find_layer(session2.look, first_id) as Dictionary).get("opacity", -1.0))
	_check(absf(float(restored) - 0.42) < 0.0001, "draft survives a restart", str(restored))

	# ---- 4. corrupted production JSON is a clean error ---------------------------
	var f := FileAccess.open(prod.assignments_path(), FileAccess.WRITE)
	f.store_string("{{{{ not json")
	f.close()
	var broken: Dictionary = prod.load_assignments()
	_check(not bool(broken.get("ok", false)) and not (broken.get("errors", []) as Array).is_empty(), "corrupted assignments reported cleanly", str(broken.get("errors", [])))
	var state: Dictionary = prod.production_state()
	_check(not bool(state.get("ok", true)), "production state marks invalid", str(state))
	# restore
	var good: Dictionary = FxResolverScript.new_assignments()
	_check(bool(prod.apply({"assignments": good})["ok"]), "production restored after corruption")

	# ---- 5. duplicate layer ids are rejected -------------------------------------
	var dup: Dictionary = _look("LOOK_DUP", 12.0)
	var extra: Dictionary = FxLookScript.new_layer("FX", "dupe")
	extra["layer_id"] = str((dup["layers"][0] as Dictionary).get("layer_id", ""))
	dup["layers"].append(extra)
	var dup_check: Dictionary = FxLookScript.validate(FxLookScript.materialize(dup))
	_check(not bool(dup_check["ok"]) and str(dup_check["errors"]).contains("duplicate"), "duplicate layer ids rejected", str(dup_check["errors"]).substr(0, 100))

	# ---- 6. FFA / team compositions with ALL production looks active -------------
	for format in ["FFA_4", "TEAM_2V2"]:
		var svp := SubViewport.new()
		svp.size = Vector2i(1280, 720)
		svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(svp)
		var sr = FxScreenRuntimeScript.new()
		var disp := SubViewportContainer.new()
		disp.stretch = true
		disp.size = Vector2(1280, 720)
		svp.add_child(disp)
		disp.add_child(sr.subvp)
		await settle(40)
		var mounted: bool = sr.mount(format, "debug", "ice_mage", "doge_man")
		await settle(60)
		var keys: Array = sr.registry.keys()
		_check(mounted and keys.size() > 0, "%s mounts with targets" % format, "keys=%d" % keys.size())
		if keys.is_empty():
			svp.queue_free()
			await settle(6)
			continue
		sr.seek(1.5)
		var renderer = FxLayerRendererScript.new(sr.screen, sr.registry)
		var baseline: Image = await shot(svp, "adv_%s_none" % format)
		var plan: Array = []
		for key in keys:
			var look: Dictionary = FxLookScript.new_look("ADV_%s_%s" % [format, str(key).to_upper()], "adv")
			var layer: Dictionary = FxLookScript.new_layer("FX", "rgb")
			layer["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": 16.0}
			look["layers"].append(layer)
			plan.append({"key": str(key), "look": look})
		var applied: Dictionary = renderer.apply_composition(plan)
		renderer.set_time(1.5)
		await settle(10)
		var styled: Image = await shot(svp, "adv_%s_all_styled" % format)
		_check(bool(applied["ok"]) and int(applied.get("targets", 0)) == keys.size(), "%s: every target participates" % format, str(applied.get("targets", 0)))
		var delta := _mean_abs_diff(baseline, styled)
		_check(delta > 0.004, "%s: all production looks render together" % format, "mean=%.5f" % delta)
		svp.queue_free()
		await settle(6)

	var rf := FileAccess.open(out_dir.path_join("summary_adversarial_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if rf != null:
		rf.store_string(JSON.stringify(report, "  "))
		rf.close()
	print("[ADVERSARIAL] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _look(look_id: String, shift: float) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, look_id)
	var fx: Dictionary = FxLookScript.new_layer("FX", "rgb")
	fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift": shift}
	look["layers"].append(fx)
	return look

func settle(n: int) -> void:
	for i in n:
		await process_frame

func shot(svp: SubViewport, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = svp.get_texture().get_image()
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

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
