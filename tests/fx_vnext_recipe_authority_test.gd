extends SceneTree
# Recipe authority and composition identity regressions.
# This test drives the same FxSession recipe-add seam used by lab_shell.gd.

const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var checks := 0
var failures := 0

func _init() -> void:
	var production_dir := "user://vnext_test_recipe_authority_production"
	var draft_dir := "user://vnext_test_recipe_authority_drafts"
	_wipe_dir(ProjectSettings.globalize_path(production_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	var production = FxProductionScript.new()
	production.data_dir = production_dir
	var drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	var session = FxSessionScript.new(production, drafts)

	_test_target_compatibility_matrix(session)
	_test_repeated_target_recipe_memberships(session)
	_test_unscoped_macro_refuses_ambiguous_instances(session)
	_test_composition_macro_targets_declared_passes(session)
	_test_composition_memberships_survive_apply_reopen_and_undo(session, production)

	print("[FX-RECIPE-AUTHORITY] done · checks=%d failures=%d" % [checks, failures])
	_wipe_dir(ProjectSettings.globalize_path(production_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	quit(1 if failures > 0 else 0)

func _test_target_compatibility_matrix(session) -> void:
	var contexts := [
		{"key": "composition", "signature": "composition||composition||||1v1|debug", "role": "composition", "ctx": {"target_key": "composition", "element_id": "composition", "element_role": "composition", "mode_family": "1v1", "stage_id": "debug"}},
		{"key": "primary_left", "signature": "primary_left|ice_mage|primary|left|left|A|1v1|debug", "role": "primary", "ctx": {"target_key": "primary_left", "element_id": "primary_left", "element_role": "primary", "fighter_id": "ice_mage", "visual_side": "left", "presentation_slot": "left", "team_side": "A", "mode_family": "1v1", "stage_id": "debug"}},
		{"key": "echo_left", "signature": "echo_left|ice_mage|echo|left|left|A|1v1|debug", "role": "echo", "ctx": {"target_key": "echo_left", "element_id": "echo_left", "element_role": "echo", "fighter_id": "ice_mage", "visual_side": "left", "presentation_slot": "left", "team_side": "A", "mode_family": "1v1", "stage_id": "debug"}},
		{"key": "side_field_left", "signature": "side_field_left|||left|left|A|1v1|debug", "role": "side_field", "ctx": {"target_key": "side_field_left", "element_id": "side_field_left", "element_role": "side_field", "visual_side": "left", "presentation_slot": "left", "team_side": "A", "mode_family": "1v1", "stage_id": "debug"}},
		{"key": "name_left", "signature": "name_left|ice_mage|name|left|left|A|1v1|debug", "role": "name", "ctx": {"target_key": "name_left", "element_id": "name_left", "element_role": "name", "fighter_id": "ice_mage", "visual_side": "left", "presentation_slot": "left", "team_side": "A", "mode_family": "1v1", "stage_id": "debug"}},
	]
	for raw_target in contexts:
		var target: Dictionary = raw_target
		for raw_recipe_id in FxRecipesScript.recipe_ids():
			var recipe_id := str(raw_recipe_id)
			var recipe := FxRecipesScript.get_recipe(recipe_id)
			var compatibility: Dictionary = FxRecipesScript.target_compatibility(recipe_id, target["ctx"])
			var expected := (recipe.get("target_compatibility", {}).get("target_roles", []) as Array).has(str(target["role"]))
			if bool(recipe.get("target_compatibility", {}).get("requires_fighter", false)):
				expected = expected and str(target["ctx"].get("fighter_id", "")) != ""
			_check(bool(compatibility.get("ok", false)) == expected, "%s compatibility matrix %s" % [recipe_id, target["role"]], str(compatibility))

			session.open_target(str(target["key"]), target["ctx"], str(target["signature"]), str(target["role"]))
			var before_look: Dictionary = session.look.duplicate(true)
			var before_composition: Dictionary = session.composition.duplicate(true)
			var added: Dictionary = session.add_recipe_instance(recipe_id, target["ctx"])
			if expected:
				_check(bool(added.get("ok", false)), "%s compatible add succeeds on %s" % [recipe_id, target["role"]], str(added))
				_check(session.look != before_look or session.composition != before_composition, "%s compatible add mutates %s" % [recipe_id, target["role"]])
			else:
				_check(not bool(added.get("ok", false)), "%s incompatible add fails on %s" % [recipe_id, target["role"]], str(added))
				_check(session.look == before_look and session.composition == before_composition, "%s incompatible add is zero-mutation on %s" % [recipe_id, target["role"]])
		session.close_target()

func _test_repeated_target_recipe_memberships(session) -> void:
	var ctx := {"target_key": "primary_left", "element_id": "primary_left", "element_role": "primary", "fighter_id": "ice_mage", "visual_side": "left", "presentation_slot": "left", "team_side": "A", "mode_family": "1v1", "stage_id": "debug"}
	session.open_target("primary_left", ctx, "primary_left|ice_mage|primary|left|left|A|1v1|debug", "primary")
	var first: Dictionary = session.add_recipe_instance(FxRecipesScript.PRIMARY_FLAME_ENERGY, ctx)
	var second: Dictionary = session.add_recipe_instance(FxRecipesScript.PRIMARY_FLAME_ENERGY, ctx)
	_check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "repeated compatible Recipe adds succeed", str([first, second]))
	var first_id := str(first.get("recipe_instance_id", ""))
	var second_id := str(second.get("recipe_instance_id", ""))
	_check(first_id != "" and second_id != "" and first_id != second_id, "repeated Recipe adds get distinct instance ids", str([first_id, second_id]))
	var memberships: Array = session.look.get("metadata", {}).get("recipe_instances", [])
	_check(memberships.size() == 2, "target Look stores both Recipe memberships", str(memberships))
	_check(str((memberships[0] as Dictionary).get("recipe_instance_id", "")) == first_id and str((memberships[1] as Dictionary).get("recipe_instance_id", "")) == second_id, "target memberships preserve creation order")
	var before_undo_ids: Array = (memberships[0] as Dictionary).get("layer_ids", []).duplicate()
	_check(session.undo(), "undo repeated Recipe add succeeds")
	var after_undo: Array = session.look.get("metadata", {}).get("recipe_instances", [])
	_check(after_undo.size() == 1 and str((after_undo[0] as Dictionary).get("recipe_instance_id", "")) == first_id, "undo removes only the latest Recipe instance", str(after_undo))
	_check(_contains_all_layer_ids(session.look.get("layers", []), before_undo_ids), "undo retains the first Recipe instance canonical layers")
	session.close_target()

func _test_unscoped_macro_refuses_ambiguous_instances(session) -> void:
	var ctx := {"target_key": "echo_left", "element_id": "echo_left", "element_role": "echo", "fighter_id": "ice_mage", "visual_side": "left", "presentation_slot": "left", "team_side": "A", "mode_family": "1v1", "stage_id": "debug"}
	session.open_target("echo_left", ctx, "echo_left|ice_mage|echo|left|left|A|1v1|debug", "echo")
	var first: Dictionary = session.add_recipe_instance(FxRecipesScript.SIGNAL_MELT, ctx)
	var second: Dictionary = session.add_recipe_instance(FxRecipesScript.SIGNAL_MELT, ctx)
	_check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "repeated Signal Melt instances instantiate")
	var before: Dictionary = session.look.duplicate(true)
	var ambiguous := FxRecipesScript.apply_macro(session.look, FxRecipesScript.SIGNAL_MELT, "MELT", 0.9)
	_check(not ambiguous, "unscoped macro refuses ambiguous repeated Recipe instances")
	_check(session.look == before, "ambiguous unscoped macro is zero-mutation")
	session.close_target()

func _test_composition_macro_targets_declared_passes(session) -> void:
	var ctx := {"target_key": "composition", "element_id": "composition", "element_role": "composition", "mode_family": "1v1", "stage_id": "debug"}
	session.open_target("composition", ctx, "composition||composition||||1v1|debug", "composition")
	var added: Dictionary = session.add_recipe_instance(FxRecipesScript.CLASH_OVERDRIVE, ctx)
	_check(bool(added.get("ok", false)), "Clash Overdrive instantiates for macro pass targeting")
	var instance_id := str(added.get("recipe_instance_id", ""))
	var before: Array = (session.composition.get("final_passes", []) as Array).duplicate(true)
	var changed := FxRecipesScript.apply_macro(session.composition, FxRecipesScript.CLASH_OVERDRIVE, instance_id, "GRAPHIC_BREAKUP", "GRID")
	_check(changed, "Clash Graphic Breakup macro applies to its instance")
	var touched := 0
	var pattern_changed := false
	for raw_pass in session.composition.get("final_passes", []):
		var pass_doc: Dictionary = raw_pass
		var operator_id := str(pass_doc.get("operator", (pass_doc.get("fx", {}) as Dictionary).get("operator", "")))
		var before_pass := _pass_for_operator(before, operator_id)
		var before_fx: Dictionary = before_pass.get("fx", {})
		var after_fx: Dictionary = pass_doc.get("fx", {})
		if float(after_fx.get("operator_pattern_family", 0.0)) != float(before_fx.get("operator_pattern_family", 0.0)):
			touched += 1
			pattern_changed = operator_id == "pattern_transition"
	_check(touched == 1 and pattern_changed, "Graphic Breakup targets only the pattern pass", str(session.composition.get("final_passes", [])))
	session.close_target()

func _pass_for_operator(passes: Array, operator_id: String) -> Dictionary:
	for raw_pass in passes:
		var pass_doc: Dictionary = raw_pass
		if str(pass_doc.get("operator", (pass_doc.get("fx", {}) as Dictionary).get("operator", ""))) == operator_id:
			return pass_doc
	return {}

func _test_composition_memberships_survive_apply_reopen_and_undo(session, production) -> void:
	var ctx := {"target_key": "composition", "element_id": "composition", "element_role": "composition", "mode_family": "1v1", "stage_id": "debug"}
	var signature := "composition||composition||||1v1|debug"
	session.open_target("composition", ctx, signature, "composition")
	var first: Dictionary = session.add_recipe_instance(FxRecipesScript.KINETIC_RUSH, ctx)
	var second: Dictionary = session.add_recipe_instance(FxRecipesScript.PATTERN_CUT, ctx)
	_check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "two compatible composition Recipe adds succeed", str([first, second]))
	var composition_doc: Dictionary = session.composition
	var memberships: Array = composition_doc.get("metadata", {}).get("recipe_instances", [])
	_check(memberships.size() == 2, "composition stores both Recipe memberships", str(memberships))
	_check(str((memberships[0] as Dictionary).get("recipe_id", "")) == FxRecipesScript.KINETIC_RUSH and str((memberships[1] as Dictionary).get("recipe_id", "")) == FxRecipesScript.PATTERN_CUT, "composition membership order is authored order", str(memberships))
	var ordered_pass_ids := _pass_ids(composition_doc)
	_check(ordered_pass_ids == (first.get("pass_ids", []) as Array) + (second.get("pass_ids", []) as Array), "composition pass order is the concatenation of authored instances", str(ordered_pass_ids))
	var applied: Dictionary = session.apply()
	_check(bool(applied.get("ok", false)), "multi-Recipe composition Apply succeeds", str(applied))
	var persisted: Dictionary = production.load_composition()
	_check(bool(persisted.get("ok", false)), "multi-Recipe composition reloads from Production", str(persisted))
	var persisted_doc: Dictionary = persisted.get("doc", {})
	_check(_pass_ids(persisted_doc) == ordered_pass_ids, "Apply preserves ordered passes for both composition instances")
	_check((persisted_doc.get("metadata", {}).get("recipe_instances", []) as Array).size() == 2, "Apply preserves both composition memberships")
	session.close_target()
	var reopened: Dictionary = session.open_target("composition", ctx, signature, "composition")
	_check(str(reopened.get("opened", "")) in ["production", "draft"], "multi-Recipe composition reopens through composition authority", str(reopened))
	_check(_pass_ids(session.composition) == ordered_pass_ids, "load/reopen preserves both ordered composition Recipe instances")
	_check((session.composition.get("metadata", {}).get("recipe_instances", []) as Array).size() == 2, "load/reopen preserves both composition memberships")
	# Reopen intentionally starts a fresh history boundary. Undo must remove only
	# the newest instance created in this authoring session, not reconstruct the
	# persisted document from its legacy last-recipe projection.
	var third: Dictionary = session.add_recipe_instance(FxRecipesScript.KINETIC_RUSH, ctx)
	_check(bool(third.get("ok", false)), "composition add after reopen succeeds", str(third))
	_check(session.undo(), "composition undo of latest newly-created Recipe instance succeeds")
	var after_undo: Dictionary = session.composition
	var after_memberships: Array = after_undo.get("metadata", {}).get("recipe_instances", [])
	_check(after_memberships.size() == 2, "composition undo removes only latest membership", str(after_memberships))
	_check(_pass_ids(after_undo) == ordered_pass_ids, "composition undo removes only latest ordered passes")
	session.close_target()

func _pass_ids(doc: Dictionary) -> Array:
	var out: Array = []
	for raw_pass in doc.get("final_passes", []):
		out.append(str((raw_pass as Dictionary).get("pass_id", "")))
	return out

func _contains_all_layer_ids(layers: Array, ids: Array) -> bool:
	var seen: Dictionary = {}
	for raw_layer in layers:
		seen[str((raw_layer as Dictionary).get("layer_id", ""))] = true
	for raw_id in ids:
		if not seen.has(str(raw_id)):
			return false
	return true

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s%s" % [label, (" · " + detail) if detail != "" else ""])

func _wipe_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in DirAccess.get_directories_at(path):
		_wipe_dir(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))
