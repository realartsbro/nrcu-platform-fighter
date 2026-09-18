extends SceneTree
# Phase 7 behavioral end-to-end proof for both Hero Recipes.
#
# This is deliberately a windowed/readback-safe test.  It drives the real Lab
# shell, FxSession, FxProduction, FxResolver, FxLayerRenderer and VsRuntime
# paths; it does not seed Production with a fixture or substitute a renderer.
# All editor/runtime stores are isolated under the evidence directory supplied
# by FXLAB_EVIDENCE_DIR (or user:// when that variable is absent).

const FxEvidenceScript := preload("res://scripts/fx_vnext/fx_evidence.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const RuntimeScene := preload("res://scenes/nrcu_vs_runtime.tscn")

const PRESENTATION_TIME := 1.25
const FLAME_RECIPE := "PRIMARY_FLAME_ENERGY"
const ORGANIC_RECIPE := "ORGANIC_SIDE_FIELD"

var shell: Control
var checks: Array = []
var failures := 0
var out_dir := ""
var data_dir := ""
var draft_dir := ""
var recipe_look_ids: Dictionary = {}
var recipe_targets := {
	FLAME_RECIPE: "primary_left",
	ORGANIC_RECIPE: "side_field_left",
}
var motion_images: Dictionary = {}

func _init() -> void:
	_configure_isolated_paths()
	_wipe_dir(data_dir)
	_wipe_dir(draft_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)

	shell = _spawn_shell()
	await settle(45)
	_check(shell != null, "Phase 7 E2E launches the real Lab shell")
	if shell == null:
		_finish()
		return

	_check(str(shell.production.data_dir) == data_dir, "Lab shell uses isolated NRCU_FX_DATA_DIR", str(shell.production.data_dir))
	_check(str(shell.drafts.base_dir) == draft_dir, "Lab shell uses isolated NRCU_FX_DRAFT_DIR", str(shell.drafts.base_dir))
	_check(not str(shell.production.data_dir).contains("res://nrcu_fx_data"), "repository default Production data is not used")
	_check(not str(shell.drafts.base_dir).begins_with("user://nrcu_fx_vnext_drafts"), "repository/default draft store is not used")

	await _prove_registry_and_ui_discoverability()
	if shell.runtime != null and shell.runtime.registry != null:
		for recipe_id in [FLAME_RECIPE, ORGANIC_RECIPE]:
			await _exercise_recipe(recipe_id, str(recipe_targets[recipe_id]))
	else:
		_check(false, "real Lab runtime registry is available for both Hero Recipes")

	await _prove_fresh_runtime_readback_and_parity()
	_write_artifacts()
	_finish()

func _configure_isolated_paths() -> void:
	var supplied := OS.get_environment("FXLAB_EVIDENCE_DIR")
	if supplied == "":
		out_dir = ProjectSettings.globalize_path("user://fx_evidence/phase7_recipe_e2e")
	else:
		out_dir = ProjectSettings.globalize_path(supplied).path_join("phase7_recipe_e2e")
	data_dir = out_dir.path_join("isolated_production")
	draft_dir = out_dir.path_join("isolated_drafts")
	OS.set_environment("FXLAB_EVIDENCE_DIR", out_dir)
	OS.set_environment("NRCU_FX_DATA_DIR", data_dir)
	OS.set_environment("NRCU_FX_DRAFT_DIR", draft_dir)
	OS.set_environment("NRCU_VS_FORMAT", "1v1")
	OS.set_environment("NRCU_VS_SEEK", str(PRESENTATION_TIME))

func _spawn_shell() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	if scene == null:
		return null
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func _prove_registry_and_ui_discoverability() -> void:
	var ids: Array = FxRecipesScript.recipe_ids()
	_check(ids == [FLAME_RECIPE, ORGANIC_RECIPE], "registry exposes exactly both stable Hero Recipe ids", str(ids))
	_check(bool(FxRecipesScript.validate_registry().get("ok", false)), "both Hero Recipe registry definitions validate")
	_check(shell.recipe_rows != null and shell.recipe_rows.get_child_count() == 2, "Lab UI exposes exactly two Hero Recipe rows")
	_check(shell.library_rows != null and shell.recipe_rows != shell.library_rows and shell.library_rows.get_index() < shell.recipe_rows.get_index(), "Recipe Library is separate from Production Look inventory")
	_check(shell.has_method("_action_add_recipe"), "Lab UI exposes the real recipe instantiation action")
	_check(shell.runtime.registry.slot_nodes.has("primary_left"), "registry exposes the primary fighter target")
	var organic_target := _target_for_role("side_field")
	recipe_targets[ORGANIC_RECIPE] = organic_target
	_check(organic_target != "", "registry exposes the organic side-field target", str(shell.runtime.registry.keys()))
	_check(str(shell.runtime.registry.context_for_key("primary_left").get("element_role", "")) == "primary", "primary target context is recipe-compatible")
	_check(organic_target != "" and str(shell.runtime.registry.context_for_key(organic_target).get("element_role", "")) == "side_field", "side-field target context is recipe-compatible")

func _exercise_recipe(recipe_id: String, target_key: String) -> void:
	var recipe: Dictionary = FxRecipesScript.get_recipe(recipe_id)
	var signature := str(shell.runtime.registry.signature_for_key(target_key))
	shell.drafts.clear_target(signature)
	shell.selected_key = ""
	shell._select_key(target_key, false)
	await settle(20)
	_check(shell._session_ready(), "%s opens its compatible target through the Lab UI" % recipe_id, target_key)
	if not shell._session_ready():
		return

	var base_layers: Array = shell.session.look.get("layers", []).duplicate(true)
	var before_count := base_layers.size()
	shell._action_add_recipe(recipe_id)
	await settle(15)
	var instantiated_layers: Array = shell.session.look.get("layers", [])
	var expected_count := (recipe.get("layers", []) as Array).size()
	_check(instantiated_layers.size() == before_count + expected_count, "%s instantiates its complete layer stack" % recipe_id, "before=%d after=%d expected_add=%d" % [before_count, instantiated_layers.size(), expected_count])
	_check(shell.session._undo_stack.size() == 1, "%s instantiation is one UI undo transaction" % recipe_id)
	var validation_look: Dictionary = shell.session.look.duplicate(true)
	validation_look["look_id"] = "E2E_%s" % recipe_id
	validation_look["name"] = "Phase 7 %s" % recipe_id
	_check(bool(FxLookScript.validate_input(validation_look).get("ok", false)), "%s UI result is a valid canonical Look" % recipe_id)
	_check(bool(FxRecipesScript.validate_authored_fields(recipe_id, _recipe_layers(instantiated_layers, before_count)).get("ok", false)), "%s authored recipe fields remain complete" % recipe_id)

	var recipe_layer_ids: Array = []
	for i in range(before_count, instantiated_layers.size()):
		recipe_layer_ids.append(str((instantiated_layers[i] as Dictionary).get("layer_id", "")))
	_check(recipe_layer_ids.size() == expected_count and not recipe_layer_ids.has(""), "%s has all complete instantiated layer ids" % recipe_id, str(recipe_layer_ids))
	for layer_id in recipe_layer_ids:
		_check(layer_id.begins_with("recipe-"), "%s layer identity is recipe-instance based" % recipe_id, layer_id)

	# All authoring changes below are driven through the actual shell controls.
	# Use the first recipe FX layer because both Hero Recipes expose the same
	# macro, Advanced and Motion seams there.
	shell.selected_layer_id = recipe_layer_ids[0] if not recipe_layer_ids.is_empty() else ""
	shell._rebuild_inspector()
	await settle(8)
	var first_layer_id: String = shell.selected_layer_id
	var initial_fx: Dictionary = (FxLookScript.find_layer(shell.session.look, first_layer_id).get("fx", {}) as Dictionary).duplicate(true)
	var macro_control: Control = shell._find_canonical_control(shell.inspector_content, "fringe")
	var macro_changed := false
	if macro_control is HSlider:
		var macro_slider := macro_control as HSlider
		var next_value := clampf(float(macro_slider.value) + 0.35, macro_slider.min_value, macro_slider.max_value)
		macro_slider.value = next_value
		macro_slider.value_changed.emit(next_value)
		macro_changed = true
	elif macro_control is HBoxContainer:
		for child in macro_control.get_children():
			if child is HSlider:
				var next_value := clampf(float((child as HSlider).value) + 0.35, (child as HSlider).min_value, (child as HSlider).max_value)
				(child as HSlider).value = next_value
				(child as HSlider).value_changed.emit(next_value)
				macro_changed = true
				break
	await settle(8)
	var after_macro_fx := FxLookScript.find_layer(shell.session.look, first_layer_id).get("fx", {}) as Dictionary
	_check(macro_changed, "%s macro control is reachable in the Lab UI" % recipe_id)
	_check(not is_equal_approx(float(after_macro_fx.get("fringe", 0.0)), float(initial_fx.get("fringe", 0.0))), "%s macro mutation changes canonical fx.fringe" % recipe_id, str(after_macro_fx.get("fringe", "")))

	var advanced_page: Node = _find_named(shell.inspector_content, "ADVANCED")
	var advanced_control: Node = _find_meta_node(advanced_page, "fringe_bleed") if advanced_page != null else null
	var advanced_changed := false
	if advanced_control is SpinBox:
		var advanced_spin := advanced_control as SpinBox
		var old_value := float(advanced_spin.value)
		var next_value := clampf(old_value + 3.0, advanced_spin.min_value, advanced_spin.max_value)
		if is_equal_approx(old_value, next_value):
			next_value = clampf(old_value - 3.0, advanced_spin.min_value, advanced_spin.max_value)
		advanced_spin.value = next_value
		advanced_spin.value_changed.emit(next_value)
		advanced_changed = not is_equal_approx(old_value, next_value)
	elif advanced_control is HBoxContainer:
		for child in advanced_control.get_children():
			if child is SpinBox:
				var old_value := float((child as SpinBox).value)
				var next_value := clampf(old_value + 3.0, (child as SpinBox).min_value, (child as SpinBox).max_value)
				if is_equal_approx(old_value, next_value):
					next_value = clampf(old_value - 3.0, (child as SpinBox).min_value, (child as SpinBox).max_value)
				(child as SpinBox).value = next_value
				(child as SpinBox).value_changed.emit(next_value)
				advanced_changed = not is_equal_approx(old_value, next_value)
				break
	await settle(8)
	var after_advanced_fx := FxLookScript.find_layer(shell.session.look, first_layer_id).get("fx", {}) as Dictionary
	_check(advanced_changed, "%s Advanced canonical control is reachable" % recipe_id, "field=fringe_bleed")
	_check(not is_equal_approx(float(after_advanced_fx.get("fringe_bleed", 0.0)), float(initial_fx.get("fringe_bleed", 0.0))), "%s Advanced mutation changes canonical fx.fringe_bleed" % recipe_id, str(after_advanced_fx.get("fringe_bleed", "")))

	var motion_result := await _exercise_motion(recipe_id, first_layer_id, target_key)
	_check(bool(motion_result.get("ok", false)), "%s motion enable/trigger and live Presentation Time seam work" % recipe_id, str(motion_result.get("detail", "")))

	var before_reopen: Dictionary = shell.session.look.duplicate(true)
	shell._action_save_draft()
	await settle(10)
	var parked: Dictionary = shell.drafts.load_target(signature)
	_check(bool(parked.get("ok", false)), "%s SAVE DRAFT writes the isolated target draft" % recipe_id, str(parked.get("errors", [])))
	if bool(parked.get("ok", false)):
		_check(FxLookScript.equivalent((parked["record"] as Dictionary).get("look", {}), before_reopen), "%s draft stores the exact canonical Look" % recipe_id)

	# Explicit close/reopen is the same target lifecycle used by the shell, not a
	# direct JSON shortcut.
	shell.session.close_target()
	shell.selected_key = ""
	shell._select_key(target_key, false)
	await settle(18)
	_check(shell._session_ready(), "%s close/reopen returns to the same target" % recipe_id)
	_check(FxLookScript.equivalent(shell.session.look, before_reopen), "%s close/reopen preserves canonical equality" % recipe_id)

	var explicit_look_id := "P7_%s" % recipe_id
	shell._action_apply(explicit_look_id)
	await settle(18)
	var persisted: Dictionary = shell.production.load_look(explicit_look_id)
	_check(bool(persisted.get("ok", false)), "%s Apply to Production persists its Look" % recipe_id, str(persisted.get("errors", [])))
	_check(str((persisted.get("doc", {}) as Dictionary).get("status", "")) == "PRODUCTION", "%s persisted Look is PRODUCTION" % recipe_id)
	var assignment_doc: Dictionary = shell.production.load_assignments()
	var resolution := FxResolverScript.resolve(assignment_doc.get("doc", {}), shell.runtime.registry.context_for_key(target_key)) if bool(assignment_doc.get("ok", false)) else {}
	_check(str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"], "%s assignment resolves after Apply to Production" % recipe_id, str(resolution))
	_check(str(resolution.get("look_id", "")) == explicit_look_id, "%s assignment resolves to the applied Look" % recipe_id, str(resolution.get("look_id", "")))
	if bool(persisted.get("ok", false)):
		recipe_look_ids[recipe_id] = explicit_look_id

func _exercise_motion(recipe_id: String, layer_id: String, target_key: String) -> Dictionary:
	var result := {"ok": false, "detail": ""}
	var header = _domain_header("FRINGE")
	if header == null:
		result["detail"] = "FRINGE motion header missing"
		return result
	var kids := (header as HBoxContainer).get_children()
	var enabled_check := kids[1] as CheckBox
	if enabled_check.button_pressed:
		enabled_check.button_pressed = false
		enabled_check.toggled.emit(false)
		await settle(5)
	header = _domain_header("FRINGE")
	kids = (header as HBoxContainer).get_children()
	enabled_check = kids[1] as CheckBox
	enabled_check.button_pressed = true
	enabled_check.toggled.emit(true)
	await settle(7)

	var anchor := _domain_control("FRINGE", "Anchor") as OptionButton
	if anchor == null:
		result["detail"] = "FRINGE anchor control missing"
		return result
	anchor.select(0)
	anchor.item_selected.emit(0)
	await settle(8)
	var motion: Dictionary = FxLookScript.find_layer(shell.session.look, layer_id).get("motion", {})
	var enabled: Dictionary = motion.get("enabled", {}) as Dictionary
	var tracks: Dictionary = motion.get("tracks", {}) as Dictionary
	var track: Dictionary = tracks.get("fringe", {}) as Dictionary
	_check(bool(enabled.get("fringe", false)), "%s motion enable writes motion.enabled.fringe" % recipe_id)
	_check(str(track.get("anchor", "")) == "manual", "%s motion Anchor writes a manual trigger track" % recipe_id, str(track))

	shell.runtime.screen.lab_preview_pause()
	shell._render_current_look()
	await settle(8)
	var trigger = _domain_header("FRINGE")
	var trigger_button := ((trigger as HBoxContainer).get_children()[2] as Button) if trigger != null else null
	if trigger_button == null:
		result["detail"] = "FRINGE TRIGGER control missing"
		return result
	shell.renderer.set_time(0.0)
	trigger_button.pressed.emit()
	shell.renderer.set_time(0.05)
	await settle(4)
	var uniform_a := _quad_uniform(target_key, layer_id, "fx_fringe")
	var image_a: Image = await _capture_subviewport(shell.runtime.subvp, "%s_motion_t005" % recipe_id.to_lower())
	shell.renderer.set_time(0.80)
	await settle(4)
	var uniform_b := _quad_uniform(target_key, layer_id, "fx_fringe")
	var image_b: Image = await _capture_subviewport(shell.runtime.subvp, "%s_motion_t080" % recipe_id.to_lower())
	var pixel_delta := _mean_abs_diff(image_a, image_b)
	var parameter_changed := not is_equal_approx(uniform_a, uniform_b)
	_check(parameter_changed, "%s supplied Presentation Time changes live motion parameter" % recipe_id, "%.6f -> %.6f" % [uniform_a, uniform_b])
	_check(pixel_delta > 0.000001, "%s supplied Presentation Time changes live pixels" % recipe_id, "mean_abs_diff=%.8f" % pixel_delta)
	motion_images[recipe_id] = {"t005": image_a, "t080": image_b, "uniform_a": uniform_a, "uniform_b": uniform_b, "pixel_delta": pixel_delta}
	result["ok"] = parameter_changed and pixel_delta > 0.000001
	result["detail"] = "parameter %.6f→%.6f, pixels %.8f" % [uniform_a, uniform_b, pixel_delta]
	return result

func _prove_fresh_runtime_readback_and_parity() -> void:
	_check(recipe_look_ids.size() == 2, "both Hero Recipe Looks are persisted before fresh runtime reload")
	var flame_loaded: Dictionary = shell.production.load_look(str(recipe_look_ids.get(FLAME_RECIPE, "")))
	var organic_loaded: Dictionary = shell.production.load_look(str(recipe_look_ids.get(ORGANIC_RECIPE, "")))
	_check(bool(flame_loaded.get("ok", false)) and (flame_loaded["doc"] as Dictionary).get("layers", []).size() >= 3, "fresh runtime input contains the complete flame recipe-derived Look")
	_check(bool(organic_loaded.get("ok", false)) and (organic_loaded["doc"] as Dictionary).get("layers", []).size() >= 2, "fresh runtime input contains the complete organic recipe-derived Look")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var fresh = RuntimeScene.instantiate()
	viewport.add_child(fresh)
	await settle(110)
	fresh.seek(PRESENTATION_TIME)
	var summary: Dictionary = fresh.reload_production()
	await settle(12)
	_check(bool(summary.get("ok", false)), "fresh VsRuntime reload_production succeeds", str(summary))
	_check(int(summary.get("styled_targets", 0)) >= 2, "fresh VsRuntime resolves both persisted recipe-derived assignments", str(summary))
	var plan_ids: Array = summary.get("plan_ids", [])
	_check(_plan_contains(plan_ids, str(recipe_look_ids[FLAME_RECIPE])), "fresh VsRuntime reads the persisted flame Look")
	_check(_plan_contains(plan_ids, str(recipe_look_ids.get(ORGANIC_RECIPE, ""))), "fresh VsRuntime reads the persisted organic Look")

	var fresh_image: Image = await _capture_subviewport(viewport, "fresh_vs_runtime_t125")
	_check(fresh_image != null and fresh_image.get_width() == 1280 and fresh_image.get_height() == 720, "direct fixed-time readback is a 1280x720 SubViewport image")

	# The same fresh runtime is remounted/reloaded through the real Lab shell. A
	# fixed transport value is supplied on both sides, so this is a readback
	# parity check rather than a timing coincidence.
	shell._remount_current()
	await settle(75)
	shell.runtime.seek(PRESENTATION_TIME)
	shell._render_current_look()
	await settle(15)
	if shell.renderer != null:
		shell.renderer.set_time(PRESENTATION_TIME)
	await settle(8)
	var remount_image: Image = await _capture_subviewport(shell.runtime.subvp, "lab_remount_reload_t125")
	var parity_delta := _mean_abs_diff(fresh_image, remount_image)
	_check(parity_delta < 0.0005, "remount/reload preserves fixed Presentation Time pixel parity", "mean_abs_diff=%.8f" % parity_delta)

	# Distinguishability is measured on the actual composed frame, not inferred
	# from the recipe ids. The two recipe outputs occupy different live targets
	# and have materially different shader stacks.
	var flame_only := await _render_single_look_readback(str(recipe_look_ids[FLAME_RECIPE]), "primary_left", "flame_only_t125")
	var organic_only := await _render_single_look_readback(str(recipe_look_ids.get(ORGANIC_RECIPE, "")), str(recipe_targets.get(ORGANIC_RECIPE, "")), "organic_only_t125")
	var distinct_delta := _mean_abs_diff(flame_only, organic_only)
	_check(distinct_delta > 0.000001, "the two Hero Recipe outputs are pixel-distinguishable", "mean_abs_diff=%.8f" % distinct_delta)

	fresh.queue_free()
	viewport.queue_free()
	await settle(5)

func _render_single_look_readback(look_id: String, target_key: String, artifact_name: String) -> Image:
	# Use a fresh ScreenRuntime + shared renderer seam for a focused output
	# comparison. Production/assignment state remains the only authority.
	var screen_runtime = load("res://scripts/fx_vnext/fx_screen_runtime.gd").new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var display := SubViewportContainer.new()
	display.stretch = true
	display.size = Vector2(1280, 720)
	viewport.add_child(display)
	display.add_child(screen_runtime.subvp)
	await settle(35)
	screen_runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(65)
	var look: Dictionary = shell.production.load_look(look_id)
	var renderer = load("res://scripts/fx_vnext/fx_layer_renderer.gd").new(screen_runtime.screen, screen_runtime.registry)
	var applied: Dictionary = renderer.apply_composition([{"key": target_key, "look": look.get("doc", {})}])
	_check(bool(applied.get("ok", false)), "%s focused shared renderer composition builds" % artifact_name, str(applied))
	renderer.set_event_marks(screen_runtime.event_marks())
	renderer.set_time(PRESENTATION_TIME)
	await settle(10)
	var image: Image = await _capture_subviewport(viewport, artifact_name)
	screen_runtime.subvp.queue_free()
	viewport.queue_free()
	await settle(4)
	return image

func _capture_subviewport(viewport: SubViewport, name: String) -> Image:
	if viewport == null:
		return null
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image != null:
		_check(FxEvidenceScript.save_png(image, out_dir.path_join(name + ".png")), "FxEvidence writes %s" % name)
	return image

func _quad_uniform(target_key: String, layer_id: String, uniform: String) -> float:
	if shell.renderer == null:
		return -1.0
	for raw in shell.renderer.stack_quads(target_key):
		var entry: Dictionary = raw
		if str(entry.get("layer_id", "")) != layer_id:
			continue
		var quad = entry.get("node", null)
		if quad is Control and (quad as Control).material is ShaderMaterial:
			return float((quad as Control).material.get_shader_parameter(uniform))
	return -1.0

func _target_for_role(role: String) -> String:
	if shell == null or shell.runtime == null or shell.runtime.registry == null:
		return ""
	for raw_key in shell.runtime.registry.keys():
		var key := str(raw_key)
		var context: Dictionary = shell.runtime.registry.context_for_key(key)
		if str(context.get("element_role", "")) == role and shell.runtime.registry.slot_nodes.has(key):
			return key
	return ""

func _recipe_layers(layers: Array, start: int) -> Array:
	var out: Array = []
	for i in range(start, layers.size()):
		out.append(layers[i])
	return out

func _domain_header(domain: String):
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() == 3 and kids[0] is Label and (kids[0] as Label).text == domain and kids[1] is CheckBox and kids[2] is Button:
				return child
	return null

func _domain_control(domain: String, label_text: String):
	var active := false
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var kids := (child as HBoxContainer).get_children()
			if kids.size() == 3 and kids[0] is Label and (kids[0] as Label).text in ["DITHER", "FRINGE", "FLOW", "RGB"] and kids[1] is CheckBox and kids[2] is Button:
				active = (kids[0] as Label).text == domain
				continue
			if active and kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text.strip_edges() == label_text:
				for sub in kids:
					if sub is Control and not sub is Label:
						return sub
	return null

func _find_named(node: Node, wanted: String):
	if node == null:
		return null
	if str(node.name) == wanted:
		return node
	for child in node.get_children():
		var found = _find_named(child, wanted)
		if found != null:
			return found
	return null

func _find_meta_node(node: Node, field: String):
	if node == null:
		return null
	if node.has_meta("canonical_field") and str(node.get_meta("canonical_field")) == field:
		return node
	for child in node.get_children():
		var found = _find_meta_node(child, field)
		if found != null:
			return found
	return null

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _plan_contains(plan_ids: Array, look_id: String) -> bool:
	for raw in plan_ids:
		if str(raw).find(look_id + ":") >= 0:
			return true
	return false

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			count += 4
	return total / float(maxi(count, 1))

func _check(ok: bool, label: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if ok:
		print(line)
	else:
		failures += 1
		printerr(line)

func _write_artifacts() -> void:
	FxEvidenceScript.write_json(out_dir.path_join("phase7_recipe_e2e_summary.json"), {
		"status": "PASS" if failures == 0 else "FAIL",
		"checks": checks.size(),
		"failures": failures,
		"recipes": recipe_look_ids,
		"isolated_data_dir": data_dir,
		"isolated_draft_dir": draft_dir,
		"presentation_time": PRESENTATION_TIME,
		"windowed_readback_safe": true,
		"visual_parity_attempted": true,
		"visual_parity_note": "Fixed-time SubViewport readback was exercised through the fresh VsRuntime and remounted Lab paths; failures remain fail-closed.",
		"checks_log": checks,
	})
	FxEvidenceScript.write_json(out_dir.path_join("phase7_recipe_e2e_completion.json"), {
		"completion_marker": "FX_VNEXT_PHASE7_RECIPE_E2E_COMPLETE",
		"status": "PASS" if failures == 0 else "FAIL",
		"checks": checks.size(),
		"failures": failures,
	})

func _finish() -> void:
	_write_artifacts()
	print("[FX-PHASE7-RECIPE-E2E] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _wipe_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(path):
		_wipe_dir(path.path_join(directory_name))
		DirAccess.remove_absolute(path.path_join(directory_name))

func settle(frames: int) -> void:
	for i in frames:
		await process_frame
