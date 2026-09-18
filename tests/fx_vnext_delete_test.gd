extends SceneTree
# Round-2 Finding 14 (production level): a Look with active bindings can only be
# removed through an explicit replace / unassign flow, transactionally.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

var checks: Array = []
var failures: int = 0
var prod_dir := "user://vnext_delete_prod"

func _init() -> void:
	var out_dir := OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/delete")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir

	var sel_a := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}
	var sel_b := {"element_role": "vs_mark"}

	# ---- used look + replace path ------------------------------------------------
	var look_a: Dictionary = _make_look("LOOK_A", "Look A")
	var look_b: Dictionary = _make_look("LOOK_B", "Look B")
	_check(bool(prod.apply({"look": look_a})["ok"]), "look A written")
	_check(bool(prod.apply({"look": look_b})["ok"]), "look B written")
	var doc: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(doc, sel_a, "LOOK_A", "")
	FxResolverScript.upsert_binding(doc, sel_b, "LOOK_A", "")
	_check(bool(prod.apply({"assignments": doc})["ok"]), "two bindings to A written")
	_check(int(prod.usage("LOOK_A")["count"]) == 2, "usage counts both bindings")

	var retire: Dictionary = prod.retire_look("LOOK_A", "replace", "LOOK_B")
	_check(bool(retire["ok"]), "replace-retire succeeds", str(retire.get("errors", [])))
	_check(int(retire.get("rebound", 0)) == 2, "two bindings rebound", str(retire.get("rebound", 0)))
	_check(not prod.list_look_ids().has("LOOK_A"), "LOOK_A file removed", str(prod.list_look_ids()))
	var res_a: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], sel_a)
	_check(str(res_a.get("status", "")) == "ASSIGNED" and str(res_a.get("look_id", "")) == "LOOK_B", "binding now resolves to replacement", str(res_a))
	_check(bool(FxResolverScript.validate_assignments(prod.load_assignments()["doc"])["ok"]), "assignments stay valid after replace")

	# ---- used look + unassign path ----------------------------------------------
	var look_c: Dictionary = _make_look("LOOK_C", "Look C")
	_check(bool(prod.apply({"look": look_c})["ok"]), "look C written")
	var doc2: Dictionary = prod.load_assignments()["doc"]
	FxResolverScript.upsert_binding(doc2, sel_b, "LOOK_C", "")
	_check(bool(prod.apply({"assignments": doc2})["ok"]), "binding to C added")
	var retire2: Dictionary = prod.retire_look("LOOK_C", "unassign")
	_check(bool(retire2["ok"]), "unassign-retire succeeds", str(retire2.get("errors", [])))
	_check(not prod.list_look_ids().has("LOOK_C"), "LOOK_C file removed")
	var res_b: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], sel_b)
	_check(str(res_b.get("status", "")) != "ASSIGNED" or str(res_b.get("look_id", "")) != "LOOK_C", "no reference to deleted look remains", str(res_b))
	_check(bool(FxResolverScript.validate_assignments(prod.load_assignments()["doc"])["ok"]), "assignments stay valid after unassign")

	# ---- unused look deletes directly -------------------------------------------
	var look_d: Dictionary = _make_look("LOOK_D", "Look D")
	_check(bool(prod.apply({"look": look_d})["ok"]), "look D written")
	_check(int(prod.usage("LOOK_D")["count"]) == 0, "look D unused")
	var retire3: Dictionary = prod.retire_look("LOOK_D", "unassign")
	_check(bool(retire3["ok"]), "unused delete succeeds", str(retire3.get("errors", [])))
	_check(not prod.list_look_ids().has("LOOK_D"), "look D removed")

	# ---- disabled-only reference remains a real delete dependency -------------
	var look_f: Dictionary = _make_look("LOOK_F", "Look F")
	_check(bool(prod.apply({"look": look_f})["ok"]), "look F written")
	var doc4: Dictionary = prod.load_assignments()["doc"]
	var disabled_id := FxResolverScript.upsert_binding(doc4, {"fighter_id": "ice_mage", "element_role": "primary", "visual_side": "right"}, "LOOK_F", "disabled reference")
	_check(FxResolverScript.set_binding_enabled(doc4, disabled_id, false), "disabled reference created")
	_check(bool(prod.apply({"assignments": doc4})["ok"]), "disabled reference persisted")
	var usage_f: Dictionary = prod.usage("LOOK_F")
	_check(int(usage_f.get("count", 0)) == 0 and int(usage_f.get("total_count", 0)) == 1, "disabled-only usage stays delete-protected", str(usage_f))

	# ---- rejected replace leaves everything byte-identical -----------------------
	var look_e: Dictionary = _make_look("LOOK_E", "Look E")
	_check(bool(prod.apply({"look": look_e})["ok"]), "look E written")
	var doc3: Dictionary = prod.load_assignments()["doc"]
	FxResolverScript.upsert_binding(doc3, sel_a, "LOOK_E", "")
	_check(bool(prod.apply({"assignments": doc3})["ok"]), "binding to E added")
	var asg_before: PackedByteArray = _read_bytes(prod.assignments_path())
	var e_before: PackedByteArray = _read_bytes(prod.look_path("LOOK_E"))
	var rejected: Dictionary = prod.retire_look("LOOK_E", "replace", "NO_SUCH_LOOK")
	_check(not bool(rejected["ok"]), "replace with missing target rejected", str(rejected.get("errors", [])))
	_check(_read_bytes(prod.assignments_path()) == asg_before, "assignments byte-identical after rejection")
	_check(_read_bytes(prod.look_path("LOOK_E")) == e_before, "look byte-identical after rejection")

	var f := FileAccess.open(out_dir.path_join("summary_delete_check.json"), FileAccess.WRITE)
	var report := {"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[DELETE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _make_look(look_id: String, name: String) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, name)
	var fx: Dictionary = FxLookScript.new_layer("FX", "Echo rgb")
	fx["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 10.0}
	look["layers"].append(fx)
	return look

func _read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(abs: String) -> void:
	if not DirAccess.dir_exists_absolute(abs):
		return
	for file_name in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs):
		_wipe_dir(abs.path_join(sub))
