extends SceneTree
# Shared resolver unit tests — bypass-first, specificity, ambiguity, editing.

var checks: Array = []
var failures: int = 0

func _init() -> void:
	var R = load("res://scripts/fx_vnext/fx_resolver.gd")

	# ---- weights guard (specs/09 §1.2) --------------------------------------
	_check(int(R.WEIGHTS["element_id"]) == 100 and int(R.WEIGHTS["fighter_id"]) == 50, "weights: element/fighter")
	_check(int(R.WEIGHTS["element_role"]) == 20 and int(R.WEIGHTS["presentation_slot"]) == 12, "weights: role/slot")
	_check(int(R.WEIGHTS["visual_side"]) == 8 and int(R.WEIGHTS["team_side"]) == 6, "weights: side/team")
	_check(int(R.WEIGHTS["mode_family"]) == 5 and int(R.WEIGHTS["stage_id"]) == 5, "weights: mode/stage")

	var assign: Dictionary = _load_fixture("assignments_example.json")
	var bypass: Dictionary = _load_fixture("bypass_example.json")
	_check(bool(R.validate_assignments(assign)["ok"]), "planning assignments example validates", str(R.validate_assignments(assign)["errors"]))
	_check(bool(R.validate_assignments(bypass)["ok"]), "planning bypass example validates")

	var ctx := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "mode_family": "1v1", "stage_id": "debug"}

	# ---- specificity ---------------------------------------------------------
	var r: Dictionary = R.resolve(assign, ctx)
	_check(str(r["status"]) == "ASSIGNED" and str(r["look_id"]) == "ICE_MAGE_ECHO_LEFT_EXAMPLE", "most-specific binding wins", str(r))
	_check((r["chain"] as Array).size() == 2 and bool(r["chain"][0]["winner"]) and str(r["chain"][1]["look_id"]) == "ECHO_BASE", "why-chain ordered, base considered")

	var r_doge: Dictionary = R.resolve(assign, {"fighter_id": "doge_man", "element_role": "echo", "visual_side": "left", "mode_family": "1v1"})
	_check(str(r_doge["look_id"]) == "ECHO_BASE", "fallback binding wins for other fighter")

	var r_none: Dictionary = R.resolve(assign, {"element_role": "primary"})
	_check(str(r_none["status"]) == "UNASSIGNED", "no match → UNASSIGNED")

	# ---- bypass first ---------------------------------------------------------
	var rb: Dictionary = R.resolve(bypass, ctx)
	_check(str(rb["status"]) == "BYPASSED" and str(rb["bypass_id"]) == "bypass-ice-echo-left-0001", "bypass wins over every binding", str(rb))
	var rb_other: Dictionary = R.resolve(bypass, {"fighter_id": "doge_man", "element_role": "echo"})
	_check(str(rb_other["status"]) == "ASSIGNED" and str(rb_other["look_id"]) == "ECHO_BASE", "bypass does not leak to other targets")

	# ---- disabled binding falls back -----------------------------------------
	var doc: Dictionary = assign.duplicate(true)
	R.set_binding_enabled(doc, "binding-ice-echo-left-0001", false)
	var r_dis: Dictionary = R.resolve(doc, ctx)
	_check(str(r_dis["look_id"]) == "ECHO_BASE", "disabled binding opens fallback", str(r_dis))

	# ---- ambiguity: malformed duplicate selectors -----------------------------
	var bad := {
		"schema": R.ASSIGNMENTS_SCHEMA,
		"bindings": [
			{"binding_id": "binding-aaa1-0001", "selector": {"element_role": "echo"}, "look_id": "ECHO_A", "enabled": true},
			{"binding_id": "binding-bbb2-0002", "selector": {"element_role": "echo"}, "look_id": "ECHO_B", "enabled": true},
		],
		"bypasses": [],
	}
	var r_amb: Dictionary = R.resolve(bad, {"element_role": "echo"})
	_check(str(r_amb["status"]) == "AMBIGUOUS", "equal specificity with different Looks → AMBIGUOUS", str(r_amb))
	_check(str(r_amb["binding_id"]) == "binding-aaa1-0001", "deterministic tiebreak by binding_id lexical order")
	var v_bad: Dictionary = R.validate_assignments(bad)
	_check(not bool(v_bad["ok"]), "validation rejects malformed duplicate selectors", str(v_bad["errors"]))

	# ---- normalization ---------------------------------------------------------
	_check(R.selector_key({"visual_side": "left", "element_role": "echo"}) == "element_role=echo&visual_side=left", "canonical selector key ordering")
	_check(R.normalize_selector({"element_role": "echo", "visual_side": ""}).size() == 1, "empty selector fields dropped")
	_check(R.selector_matches({"fighter_id": "ice_mage"}, {"fighter_id": "ice_mage", "element_role": "echo"}), "selector matches subset")
	_check(not R.selector_matches({"fighter_id": "ice_mage"}, {"fighter_id": "doge_man"}), "selector mismatch rejected")

	# ---- editing helpers -------------------------------------------------------
	var doc2: Dictionary = R.new_assignments()
	var id1: String = R.upsert_binding(doc2, {"fighter_id": "x", "element_role": "echo"}, "LOOK_A", "first")
	var id2: String = R.upsert_binding(doc2, {"element_role": "echo", "fighter_id": "x"}, "LOOK_B", "updated")
	_check(id1 == id2 and (doc2["bindings"] as Array).size() == 1, "upsert replaces instead of appending")
	_check(str(doc2["bindings"][0]["look_id"]) == "LOOK_B", "upsert updates look")
	var bypass_id: String = R.add_bypass(doc2, {"fighter_id": "x", "element_role": "echo"})
	_check(bypass_id.length() >= 8 and (doc2["bypasses"] as Array).size() == 1, "bypass added")
	_check(R.remove_bypass(doc2, {"fighter_id": "x", "element_role": "echo"}) and (doc2["bypasses"] as Array).is_empty(), "bypass removed by selector")
	_check(bool(R.validate_assignments(doc2)["ok"]), "edited assignments validate", str(R.validate_assignments(doc2)["errors"]))

	# ---- compatible selectors ---------------------------------------------------
	_check(R.compatible_selectors({"fighter_id": "x"}, {"element_role": "echo"}), "compatible when no conflicting shared field")
	_check(not R.compatible_selectors({"fighter_id": "x"}, {"fighter_id": "y"}), "conflicting shared field incompatible")

	print("[FX-RESOLVER] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func _load_fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/vnext/" + name, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok:
		failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
