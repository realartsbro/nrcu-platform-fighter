extends SceneTree
# vNext session test — open / edit / stash / apply / shared protection /
# styling on-off / why (specs/06, specs/09, specs/15 §8–§11). Pure logic.

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
	var FxSessionScript = load("res://scripts/fx_vnext/fx_session.gd")

	var prod_dir := "user://vnext_test_sess_prod"
	var draft_dir := "user://vnext_test_sess_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

	var prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	var session = FxSessionScript.new(prod, drafts)

	var ctx := {"element_id": "echo_left", "fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "presentation_slot": "a_back", "team_side": "left", "mode_family": "1v1", "stage_id": "dojo"}
	var sig := "echo_left|ice_mage|echo|left|a_back|left|1v1|dojo"

	# ---- open neutral ----------------------------------------------------------
	var opened: Dictionary = session.open_target("echo_left", ctx, sig, "echo")
	_check(bool(opened["ok"]) and str(opened["opened"]) == "neutral", "opens neutral without production", str(opened))
	_check(str(session.mode) == "EDIT_UNASSIGNED", "mode EDIT_UNASSIGNED", session.mode)
	_check(session.look["layers"].size() == 1 and str(session.look["layers"][0]["type"]) == "SOURCE", "neutral look is SOURCE-only")
	_check(session.badge_text() == "○ UNASSIGNED", "badge unassigned", session.badge_text())
	_check(session.novice_selector() == {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "novice selector per spec 15 §8", str(session.novice_selector()))
	var scope_expectations := {
		"CURRENT_OCCURRENCE": {"element_id": "echo_left", "fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "presentation_slot": "a_back", "team_side": "left", "mode_family": "1v1", "stage_id": "dojo"},
		"FIGHTER_ROLE_SIDE": {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"},
		"FIGHTER_ROLE": {"fighter_id": "ice_mage", "element_role": "echo"},
		"ROLE_SIDE": {"element_role": "echo", "visual_side": "left"},
		"ROLE": {"element_role": "echo"},
		"STATIC_ELEMENT": {"element_id": "echo_left"},
	}
	for scope_mode in scope_expectations.keys():
		var scope_result: Dictionary = session.set_assignment_scope(str(scope_mode))
		_check(bool(scope_result["ok"]) and session.assignment_selector() == scope_expectations[scope_mode], "scope agency selects exact %s" % scope_mode, str(session.assignment_selector()))
	var advanced: Dictionary = {"fighter_id": "ice_mage", "element_role": "echo", "stage_id": "dojo"}
	var advanced_result: Dictionary = session.set_assignment_scope("ADVANCED", advanced)
	_check(bool(advanced_result["ok"]) and session.assignment_selector() == advanced, "advanced selector builder round-trips", str(session.assignment_selector()))
	session.set_assignment_scope("CURRENT_OCCURRENCE")
	_check(session.proposed_look_id() == "ICE_MAGE_ECHO_LEFT", "proposed id ICE_MAGE_ECHO_LEFT", session.proposed_look_id())

	# ---- edit + dirty + stash --------------------------------------------------
	var edited: Dictionary = session.edit(func(doc): doc["layers"][0]["opacity"] = 0.5)
	_check(bool(edited["ok"]) and session.dirty, "edit marks dirty")
	_check(session.badge_text() == "◐ DRAFT", "badge shows DRAFT", session.badge_text())
	var stashed: Dictionary = session.stash()
	_check(bool(stashed["ok"]) and drafts.has_target(sig), "stash writes target draft")
	var reloaded = drafts.load_target(sig)
	_check(bool(reloaded["ok"]) and absf(float(reloaded["record"]["look"]["layers"][0]["opacity"]) - 0.5) < 0.0001, "draft content roundtrips")

	# ---- apply ------------------------------------------------------------------
	var applied: Dictionary = session.apply()
	_check(bool(applied["ok"]), "apply succeeds", str(applied["errors"]))
	_check(str(applied["look_id"]) == "ICE_MAGE_ECHO_LEFT" and int(applied["revision"]) == 1, "apply finalizes id + revision", str(applied))
	var prod_look = prod.load_look("ICE_MAGE_ECHO_LEFT")
	_check(bool(prod_look["ok"]) and str(prod_look["doc"]["status"]) == "PRODUCTION", "production look written", str(prod_look["errors"]))
	_check(not session.dirty, "clean after apply")
	_check(session.badge_text() == "● ASSIGNED", "badge assigned", session.badge_text())
	var asg = prod.load_assignments()
	var res = FxResolverScript.resolve(asg["doc"], ctx)
	_check(str(res["status"]) == "ASSIGNED" and str(res["look_id"]) == "ICE_MAGE_ECHO_LEFT", "production resolves target", str(res["status"]))
	var why_lines: Array = session.why()
	_check(why_lines.size() >= 1 and "ICE_MAGE_ECHO_LEFT" in str(why_lines[0]), "why names the winner", str(why_lines))

	# ---- reopen: draft snapshot first ------------------------------------------
	var reopened: Dictionary = session.open_target("echo_left", ctx, sig, "echo")
	_check(str(reopened["opened"]) == "draft" and str(session.mode) == "EDIT_PRODUCTION_UNIQUE", "reopen prefers clean draft snapshot", str(reopened))

	# ---- styling OFF / ON --------------------------------------------------------
	var off: Dictionary = session.set_styling(false)
	_check(bool(off["ok"]) and session.badge_text() == "⦸ STYLING OFF", "styling off badge", session.badge_text())
	var why_off: Array = session.why()
	_check("Styling OFF" in str(why_off), "why explains bypass", str(why_off))
	_check(str(why_off).contains("Without the bypass"), "why mentions fallback candidate", str(why_off))
	var on: Dictionary = session.set_styling(true)
	_check(bool(on["ok"]) and str(session.resolution["status"]) == "ASSIGNED", "styling on restores assignment", str(session.resolution["status"]))

	# ---- shared protection -------------------------------------------------------
	var asg2 = prod.load_assignments()
	var asg_doc: Dictionary = asg2["doc"]
	FxResolverScript.upsert_binding(asg_doc, {"fighter_id": "ice_mage", "element_role": "echo"}, "ICE_MAGE_ECHO_LEFT", "additional shared scope")
	var extra = prod.apply({"assignments": asg_doc})
	_check(bool(extra["ok"]), "second binding to same look applies", str(extra["errors"]))
	var usage = prod.usage("ICE_MAGE_ECHO_LEFT")
	_check(int(usage["count"]) == 2, "look is shared now", "count=%d" % int(usage["count"]))

	drafts.clear_target(sig)
	var reopened2: Dictionary = session.open_target("echo_left", ctx, sig, "echo")
	_check(str(reopened2["opened"]) == "production" and str(session.mode) == "SHARED_PROTECTED", "shared look opens protected", session.mode)
	_check(session.badge_text().contains("SHARED"), "badge shows shared", session.badge_text())
	var blocked: Dictionary = session.edit(func(doc): doc["layers"][0]["opacity"] = 0.1)
	_check(not bool(blocked["ok"]), "edit blocked while protected")
	_check(not session.undo() and not session.redo(), "history blocked while protected")

	# ---- edit shared → draft → apply bumps revision -------------------------------
	var es: Dictionary = session.edit_shared()
	_check(bool(es["ok"]) and str(session.mode) == "EDIT_SHARED_DRAFT", "edit shared opens shared draft", session.mode)
	var edit2: Dictionary = session.edit(func(doc): doc["layers"][0]["opacity"] = 0.75)
	_check(bool(edit2["ok"]) and session.dirty, "shared draft editable")
	var shared_list: Array = drafts.list_shared()
	_check(shared_list.size() == 1 and str(shared_list[0]["look_id"]) == "ICE_MAGE_ECHO_LEFT", "shared draft listed")
	var applied2: Dictionary = session.apply()
	_check(bool(applied2["ok"]) and int(applied2["revision"]) == 2, "shared apply bumps revision", str(applied2))
	_check(drafts.list_shared().is_empty(), "shared draft cleared after apply")
	var prod_look2 = prod.load_look("ICE_MAGE_ECHO_LEFT")
	_check(int(prod_look2["doc"]["revision"]) == 2, "production revision is 2")
	_check(str(session.mode) == "SHARED_PROTECTED", "still shared after update", session.mode)

	# ---- make unique ---------------------------------------------------------------
	drafts.clear_target(sig)
	session.open_target("echo_left", ctx, sig, "echo")
	var unique: Dictionary = session.make_unique()
	_check(bool(unique["ok"]) and str(unique["look_id"]) == "ICE_MAGE_ECHO_LEFT_UNIQUE", "make unique creates look", str(unique))
	_check(str(session.mode) == "EDIT_PRODUCTION_UNIQUE", "unique look editable", session.mode)
	var res2 = FxResolverScript.resolve(prod.load_assignments()["doc"], ctx)
	_check(str(res2["look_id"]) == "ICE_MAGE_ECHO_LEFT_UNIQUE", "target now points at unique look", str(res2))
	var usage_old = prod.usage("ICE_MAGE_ECHO_LEFT")
	_check(int(usage_old["count"]) == 1, "original shared look keeps remaining user", "count=%d" % int(usage_old["count"]))

	# ---- collision naming ------------------------------------------------------------
	# A different, unassigned context so the proposal collides with an existing
	# Look that is NOT the currently assigned one → deterministic `_2`.
	var ctx2 := {"element_id": "echo_left", "fighter_id": "dragon", "element_role": "echo", "visual_side": "left", "presentation_slot": "a_back", "team_side": "left", "mode_family": "1v1", "stage_id": "dojo"}
	session.open_target("echo_left", ctx2, "dragon_sig|dragon|echo|left|a_back|left|1v1|dojo", "echo")
	_check(str(session.mode) == "EDIT_UNASSIGNED", "fresh context is unassigned", session.mode)
	var collision: Dictionary = session.apply("ICE_MAGE_ECHO_LEFT_UNIQUE")
	_check(bool(collision["ok"]) and str(collision["look_id"]) == "ICE_MAGE_ECHO_LEFT_UNIQUE_2", "collision appends _2 deterministically", str(collision))

	# ---- update via apply keeps id + bumps revision ----------------------------------
	var upd: Dictionary = session.apply()
	_check(bool(upd["ok"]) and str(upd["look_id"]) == "ICE_MAGE_ECHO_LEFT_UNIQUE_2" and int(upd["revision"]) == 2, "update keeps id and bumps revision", str(upd))
	# Use a fresh unassigned target so the scope probe exercises a new Look
	# revision-1 apply rather than updating the collision fixture.
	var scope_ctx := {"element_id": "scope_target", "fighter_id": "scope_fighter", "element_role": "echo", "visual_side": "left", "presentation_slot": "scope", "team_side": "left", "mode_family": "1v1", "stage_id": "scope_stage"}
	session.open_target("scope_target", scope_ctx, "scope_target|scope_fighter|echo|left|scope|left|1v1|scope_stage", "echo")
	_check(str(session.mode) == "EDIT_UNASSIGNED", "scope probe starts from a neutral target", session.mode)
	var role_scope: Dictionary = session.set_assignment_scope("ROLE")
	var scope_apply: Dictionary = session.apply("SCOPE_AGENCY_PROBE")
	var scope_assignments: Dictionary = prod.load_assignments()
	var scope_bindings: Array = scope_assignments["doc"].get("bindings", [])
	var scope_key: String = FxResolverScript.selector_key(role_scope["selector"])
	var scope_binding_found := false
	for raw_binding in scope_bindings:
		if raw_binding is Dictionary and FxResolverScript.selector_key((raw_binding as Dictionary).get("selector", {})) == scope_key and str((raw_binding as Dictionary).get("look_id", "")) == "SCOPE_AGENCY_PROBE":
			scope_binding_found = true
	_check(bool(scope_apply["ok"]) and scope_binding_found, "Apply commits the selected ROLE selector exactly", str(scope_apply) + " bindings=" + str(scope_bindings))
	var scope_off: Dictionary = session.set_styling(false)
	var scope_after_off: Dictionary = prod.load_assignments()
	var bypass_found := false
	for raw_bypass in scope_after_off["doc"].get("bypasses", []):
		if raw_bypass is Dictionary and FxResolverScript.selector_key((raw_bypass as Dictionary).get("selector", {})) == scope_key:
			bypass_found = true
	_check(bool(scope_off["ok"]) and bypass_found, "Styling OFF commits the same selected selector", scope_key)
	var scope_unassign: Dictionary = session.unassign_target()
	var scope_after_unassign: Dictionary = prod.load_assignments()
	var binding_removed := true
	for raw_binding in scope_after_unassign["doc"].get("bindings", []):
		if raw_binding is Dictionary and FxResolverScript.selector_key((raw_binding as Dictionary).get("selector", {})) == scope_key:
			binding_removed = false
	_check(bool(scope_unassign["ok"]) and binding_removed, "Unassign removes exactly the selected selector", str(scope_unassign))
	# Remount failure must preserve the live authority and dirty work.
	session.edit(func(doc):
		doc["name"] = "Remount Probe"
	)
	session.stash_override = func(): return {"ok": false, "errors": ["forced stash failure"]}
	var refused_remount: Dictionary = session.prepare_for_remount()
	_check(not bool(refused_remount["ok"]) and session.current_key == "scope_target" and session.dirty, "failed stash refuses remount without losing authority", str(refused_remount))
	session.stash_override = Callable()
	var accepted_remount: Dictionary = session.prepare_for_remount()
	_check(bool(accepted_remount["ok"]), "successful stash permits remount", str(accepted_remount))
	session.close_target()

	var f := FileAccess.open(out_dir.path_join("unit_fx_session.log"), FileAccess.WRITE)
	var summary := "[FX-SESSION] done · checks=%d failures=%d" % [checks.size(), failures]
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
