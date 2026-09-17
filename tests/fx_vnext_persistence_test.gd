extends SceneTree
# vNext persistence test — Production transactions (specs/10) + Draft store
# (specs/06). Pure file IO; runs headless.

var checks: Array = []
var failures: int = 0
var out_dir: String

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var FxProductionScript = load("res://scripts/fx_vnext/fx_production.gd")
	var FxDraftsScript = load("res://scripts/fx_vnext/fx_drafts.gd")

	var prod_dir := "user://vnext_test_prod"
	var draft_dir := "user://vnext_test_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir

	# ---- create + apply a look with an assignment -----------------------------
	var look: Dictionary = FxLookScript.new_look("ICE_MAGE_ECHO_LEFT", "Ice Mage Echo Left")
	var fx: Dictionary = FxLookScript.new_layer("FX", "Outer Halo")
	fx["input"] = "TRANSFORMED_SOURCE"
	fx["opacity"] = 0.65
	look["layers"].append(fx)
	look["status"] = "PRODUCTION"
	var assignments: Dictionary = FxResolverScript.new_assignments()
	var binding_id: String = FxResolverScript.upsert_binding(assignments, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "ICE_MAGE_ECHO_LEFT", "novice default scope")
	var applied: Dictionary = prod.apply({"look": look, "assignments": assignments})
	_check(bool(applied["ok"]), "first apply succeeds", str(applied["errors"]))

	var loaded = prod.load_look("ICE_MAGE_ECHO_LEFT")
	_check(bool(loaded["ok"]) and str(loaded["doc"]["layers"][1]["name"]) == "Outer Halo", "look reloads with layer")
	var loaded_asg = prod.load_assignments()
	_check(bool(loaded_asg["ok"]), "assignments reload valid")
	var resolution: Dictionary = FxResolverScript.resolve(loaded_asg["doc"], {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "mode_family": "1v1"})
	_check(str(resolution["status"]) == "ASSIGNED" and str(resolution["look_id"]) == "ICE_MAGE_ECHO_LEFT", "production resolves to look", str(resolution["status"]))

	# ---- revision rule (specs/10 §6) ------------------------------------------
	var same_rev = prod.apply({"look": look})
	_check(not bool(same_rev["ok"]) and str(same_rev.get("stage", "")) == "revision", "same revision rejected")
	var skip_rev: Dictionary = look.duplicate(true)
	skip_rev["revision"] = 5
	var skipped = prod.apply({"look": skip_rev})
	_check(not bool(skipped["ok"]) and str(skipped.get("stage", "")) == "revision", "skipping revisions rejected")
	look["revision"] = 2
	var bump = prod.apply({"look": look})
	_check(bool(bump["ok"]) and int(bump.get("look_revision", 0)) == 2, "exact +1 update accepted", str(bump["errors"]))

	# ---- rejected apply leaves production byte-equivalent ---------------------
	var look_before := _file_bytes(ProjectSettings.globalize_path(prod.look_path("ICE_MAGE_ECHO_LEFT")))
	var asg_before := _file_bytes(ProjectSettings.globalize_path(prod.assignments_path()))
	var bad_look: Dictionary = FxLookScript.new_look("BAD_LOOK", "Bad")
	bad_look["layers"].append(FxLookScript.new_layer("SOURCE", "Second Source"))
	bad_look["status"] = "PRODUCTION"
	var rejected = prod.apply({"look": bad_look})
	_check(not bool(rejected["ok"]), "two-SOURCE look rejected")
	_check(look_before == _file_bytes(ProjectSettings.globalize_path(prod.look_path("ICE_MAGE_ECHO_LEFT"))), "rejected apply leaves looks byte-identical")

	var bad_asg: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(bad_asg, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "ICE_MAGE_ECHO_LEFT")
	FxResolverScript.upsert_binding(bad_asg, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "OTHER_LOOK")
	var rejected2 = prod.apply({"assignments": bad_asg})
	_check(not bool(rejected2["ok"]), "duplicate selector rejected")
	_check(asg_before == _file_bytes(ProjectSettings.globalize_path(prod.assignments_path())), "rejected apply leaves assignments byte-identical")

	var missing_ref: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(missing_ref, {"fighter_id": "doge_man"}, "GHOST_LOOK")
	var rejected3 = prod.apply({"assignments": missing_ref})
	_check(not bool(rejected3["ok"]) and str(rejected3.get("stage", "")) == "validate-references", "binding to missing look rejected")

	# ---- second look + usage + listing ----------------------------------------
	var look2: Dictionary = FxLookScript.new_look("DOGE_ECHO_BASE", "Doge Echo Base")
	look2["status"] = "PRODUCTION"
	var applied2: Dictionary = prod.apply({"look": look2})
	_check(bool(applied2["ok"]), "second look applies")
	var asg2: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(asg2, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "ICE_MAGE_ECHO_LEFT")
	FxResolverScript.upsert_binding(asg2, {"fighter_id": "ice_mage"}, "ICE_MAGE_ECHO_LEFT")
	FxResolverScript.upsert_binding(asg2, {"mode_family": "team"}, "DOGE_ECHO_BASE")
	var applied3: Dictionary = prod.apply({"assignments": asg2})
	_check(bool(applied3["ok"]), "multi-binding assignment applies", str(applied3["errors"]))
	var usage: Dictionary = prod.usage("ICE_MAGE_ECHO_LEFT")
	_check(int(usage["count"]) == 2, "usage counts both bindings", "count=%d" % int(usage["count"]))
	var ids: Array = prod.list_look_ids()
	_check(ids == ["DOGE_ECHO_BASE", "ICE_MAGE_ECHO_LEFT"], "look listing sorted", str(ids))
	var rec: Array = prod.list_recovery()
	_check(rec.size() >= 1, "recovery backup retained", "n=%d" % rec.size())

	# ---- bypass integration ----------------------------------------------------
	var asg3: Dictionary = asg2.duplicate(true)
	FxResolverScript.add_bypass(asg3, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "styling off")
	var applied4: Dictionary = prod.apply({"assignments": asg3})
	_check(bool(applied4["ok"]), "bypass assignment applies")
	var byp: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"})
	_check(str(byp["status"]) == "BYPASSED", "stored bypass wins", str(byp["status"]))
	FxResolverScript.remove_bypass(asg3, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"})
	var applied5: Dictionary = prod.apply({"assignments": asg3})
	var back: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"})
	_check(bool(applied5["ok"]) and str(back["status"]) == "ASSIGNED", "bypass removal restores binding", str(back["status"]))

	# ---- corrupt production file → recovery diag, no crash ---------------------
	var asg_path := ProjectSettings.globalize_path(prod.assignments_path())
	var good_bytes := _file_bytes(asg_path)
	_write_text(asg_path, "{ this is not json")
	Engine.print_error_messages = false
	var st: Dictionary = prod.production_state()
	Engine.print_error_messages = true
	_check(not bool(st["ok"]) and bool(st["recovery_required"]), "corrupt production flagged for recovery")
	_write_text(asg_path, good_bytes.get_string_from_utf8())
	_check(bool(prod.load_assignments()["ok"]), "restored assignments valid again")

	# ---- drafts -----------------------------------------------------------------
	var draft_look: Dictionary = look.duplicate(true)
	draft_look["layers"][1]["opacity"] = 0.42
	var saved = drafts.save_target("1v1|ice_mage|echo|left", draft_look, 2)
	_check(bool(saved["ok"]), "target draft saved")
	var dl = drafts.load_target("1v1|ice_mage|echo|left")
	_check(bool(dl["ok"]) and absf(float(dl["record"]["look"]["layers"][1]["opacity"]) - 0.42) < 0.0001, "target draft roundtrips")
	_check(bool(dl["record"].get("dirty", false)), "draft marked dirty")
	drafts.mark_target_clean("1v1|ice_mage|echo|left")
	_check(not bool(drafts.load_target("1v1|ice_mage|echo|left")["record"].get("dirty", true)), "draft clean after mark")

	var sigs: Array = drafts.list_target_signatures()
	_check(sigs == ["1v1|ice_mage|echo|left"], "drafts list for badges", str(sigs))
	var shared = drafts.save_shared("ICE_MAGE_ECHO_LEFT", 2, draft_look)
	_check(bool(shared["ok"]), "shared draft saved")
	_check(bool(drafts.load_shared("ICE_MAGE_ECHO_LEFT", 2)["ok"]), "shared draft loads at base revision")
	_check(drafts.load_shared("ICE_MAGE_ECHO_LEFT", 3)["missing"], "different revision → separate (empty) entry")
	var shared_list: Array = drafts.list_shared()
	_check(shared_list.size() == 1 and str(shared_list[0]["look_id"]) == "ICE_MAGE_ECHO_LEFT", "shared draft listed")

	# corrupt draft: discarded cleanly, production untouched
	var sig := "1v1|doge_man|echo|right"
	_write_text(ProjectSettings.globalize_path(drafts.target_path(sig)), "{broken json")
	Engine.print_error_messages = false
	var corrupt = drafts.load_target(sig)
	Engine.print_error_messages = true
	_check(not bool(corrupt["ok"]) and not bool(corrupt["missing"]), "corrupt draft reported")
	drafts.clear_target(sig)
	_check(not drafts.has_target(sig), "corrupt draft discarded")
	_check(_file_bytes(asg_path) == good_bytes, "draft activity never touches production")

	drafts.clear_target("1v1|ice_mage|echo|left")
	_check(not drafts.has_target("1v1|ice_mage|echo|left"), "target draft cleared")

	var f := FileAccess.open(out_dir.path_join("unit_fx_persistence.log"), FileAccess.WRITE)
	var summary := "[FX-PERSISTENCE] done · checks=%d failures=%d" % [checks.size(), failures]
	if f != null:
		f.store_string("\n".join(checks) + "\n" + summary + "\n")
		f.close()
	print(summary)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _file_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
