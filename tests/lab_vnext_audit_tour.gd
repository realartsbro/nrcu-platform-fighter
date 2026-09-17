extends SceneTree
# vNext audit tour — the evidence generator for the independent audit package.
# Drives the REAL shell scene (same handlers the UI buttons call) through every
# interaction family the audit requires, capturing JPEG frames per segment
# (assembled into MP4s afterwards) and labeled PNG stills at key moments.
# Windowed: needs rendering.

var out_dir: String
var frames_root: String
var stills_dir: String
var shell: Control
var counters: Dictionary = {}
var segments: Array = []

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/tour")
	frames_root = out_dir.path_join("frames")
	stills_dir = out_dir.path_join("stills")
	DirAccess.make_dir_recursive_absolute(frames_root)
	DirAccess.make_dir_recursive_absolute(stills_dir)

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	shell = scene.instantiate()
	root.add_child(shell)
	await settle(30)

	await seg_workspace_responsive()
	await seg_browser_layers_inspector()
	await seg_draft_apply_shared()
	await seg_layer_ops_planes()
	await seg_transform_displacement_mask()
	await seg_fx_planes()
	await seg_families()
	await seg_study_zoom()
	await seg_migration_production()

	var summary := FileAccess.open(out_dir.path_join("tour_summary.json"), FileAccess.WRITE)
	if summary != null:
		summary.store_string(JSON.stringify({"segments": segments, "counters": counters}, "  "))
		summary.close()
	print("[TOUR] done · segments=", segments.size(), " frames=", counters)
	quit(0)

# ================================================================ helpers

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(segment: String) -> void:
	var index := int(counters.get(segment, 0)) + 1
	counters[segment] = index
	var dir := frames_root.path_join(segment)
	if index == 1:
		DirAccess.make_dir_recursive_absolute(dir)
		segments.append(segment)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_jpg(dir.path_join("f_%04d.jpg" % index), 0.85)

func frames(segment: String, count: int, every := 2) -> void:
	for i in count:
		await process_frame
		if i % every == 0:
			await capture(segment)

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(stills_dir.path_join(name + ".png"))

func select_target(key: String) -> void:
	shell._select_key(key, false)
	await settle(10)

# ================================================================ segments

func seg_workspace_responsive() -> void:
	var seg := "workspace_responsive"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await frames(seg, 14)
	await still("responsive_1600x900")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await frames(seg, 14)
	await still("responsive_1920x1080")
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	await frames(seg, 14)
	await still("responsive_2560x1440")
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await frames(seg, 16)
	await still("responsive_1366x768_collapsed_overflow")
	# panel collapse / expand + presets
	shell._apply_workspace_preset("PREVIEW")
	await frames(seg, 12)
	await still("preset_preview_compact")
	shell._apply_workspace_preset("AUTHORING")
	await frames(seg, 12)
	shell._toggle_timeline_expanded()
	await frames(seg, 10)
	shell._toggle_browser()
	await frames(seg, 10)
	shell._toggle_browser()
	shell._toggle_dock()
	await frames(seg, 10)
	shell._toggle_dock()
	await frames(seg, 8)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await frames(seg, 10)
	await still("workspace_restored_1600x900")

func seg_browser_layers_inspector() -> void:
	var seg := "browser_layers_inspector"
	await select_target("echo_left")
	await frames(seg, 10)
	await still("browser_target_echo_selected")
	await select_target("mark")
	await frames(seg, 8)
	await select_target("primary_left")
	await frames(seg, 8)
	await select_target("stage")
	await frames(seg, 8)
	await select_target("field_left_fx_proxy")
	await frames(seg, 8)
	await select_target("name_left")
	await frames(seg, 8)
	# layer creation through the real Add Layer handler
	await select_target("echo_left")
	await frames(seg, 6)
	shell._action_add_layer("Source Copy")
	await frames(seg, 12)
	await still("layers_with_source_copy")
	shell._action_add_layer("Outer Halo")
	await frames(seg, 12)
	await still("layers_with_halo_inspector")
	shell.selected_layer_id = str((shell.session.look["layers"][2] as Dictionary)["layer_id"])
	shell._rebuild_inspector()
	await frames(seg, 10)
	await still("inspector_halo_full")

func seg_draft_apply_shared() -> void:
	var seg := "draft_apply_shared"
	var layers: Array = shell.session.look.get("layers", [])
	var source_id := str((layers[0] as Dictionary)["layer_id"])
	shell._edit_layer(source_id, func(doc):
		var l: Dictionary = load("res://scripts/fx_vnext/fx_look.gd").find_layer(doc, source_id)
		l["opacity"] = 0.7
	)
	await frames(seg, 12)
	await still("draft_badge_modified")
	shell._action_save_draft()
	await frames(seg, 8)
	await still("draft_saved")
	shell._action_apply()
	await frames(seg, 14)
	await still("applied_assigned_badge")
	# second binding → shared protection on reopen
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var assignments: Dictionary = shell.production.load_assignments()["doc"]
	FxResolverScript.upsert_binding(assignments, {"element_role": "echo"}, str(shell.session.base.get("look_id", "")), "audit shared scope")
	shell.production.apply({"assignments": assignments})
	shell.drafts.clear_target(str(shell.session.signature))
	await select_target("echo_left")
	await frames(seg, 12)
	await still("shared_protected_state")
	shell._action_edit_shared()
	await frames(seg, 8)
	shell._action_make_unique()
	await frames(seg, 14)
	await still("make_unique_done")
	shell._action_toggle_styling()
	await frames(seg, 12)
	await still("styling_off_bypass")
	shell._action_toggle_styling()
	await frames(seg, 8)
	shell._action_why()
	await frames(seg, 12)
	await still("why_chain_open")
	shell._action_why()
	shell._action_revert()
	await frames(seg, 8)

func seg_layer_ops_planes() -> void:
	var seg := "layer_ops_planes"
	await select_target("echo_left")
	await frames(seg, 6)
	shell._action_add_layer("RGB Tear")
	await frames(seg, 10)
	shell._action_add_layer("Dither Treatment")
	await frames(seg, 10)
	await still("four_layers_stacked")
	var layers_now: Array = shell.session.look["layers"]
	if layers_now.size() >= 4:
		var rgb_id := str((layers_now[2] as Dictionary)["layer_id"])
		var dither_id := str((layers_now[3] as Dictionary)["layer_id"])
		# drag reorder through the real drop handler
		shell._drop_layer_on_layer(rgb_id, dither_id)
		await frames(seg, 12)
		await still("reordered_by_drag")
		# plane move through the real drop handler
		shell._drop_layer_on_plane(rgb_id, "TARGET_UNDERLAY")
		await frames(seg, 12)
		await still("plane_moved_behind_target")
		shell._drop_layer_on_plane(rgb_id, "COMPOSITION_BACKGROUND")
		await frames(seg, 12)
		await still("plane_moved_background")
		shell._drop_layer_on_plane(rgb_id, "TARGET_OVERLAY")
		await frames(seg, 10)
		# visibility + delete + undo
		shell._edit_layer(dither_id, func(doc):
			var l: Dictionary = load("res://scripts/fx_vnext/fx_look.gd").find_layer(doc, dither_id)
			l["enabled"] = false
		)
		await frames(seg, 10)
		await still("layer_visibility_off")
		shell._layer_menu_action(4, rgb_id) # reset
		await frames(seg, 8)
		shell._layer_menu_action(1, rgb_id) # duplicate
		await frames(seg, 10)
		await still("duplicated_layer")
		shell._action_undo()
		await frames(seg, 10)
		await still("undo_restored")
		shell._action_redo()
		await frames(seg, 8)
		shell._action_undo()
		await frames(seg, 6)

func seg_transform_displacement_mask() -> void:
	var seg := "transform_displacement_mask"
	await select_target("echo_left")
	await frames(seg, 6)
	var layers: Array = shell.session.look.get("layers", [])
	var source_id := str((layers[0] as Dictionary)["layer_id"])
	var look_script = load("res://scripts/fx_vnext/fx_look.gd")
	shell._edit_layer(source_id, func(doc):
		(look_script.find_layer(doc, source_id)["transform"] as Dictionary)["position_px"] = [80.0, 0.0]
	)
	await frames(seg, 10)
	await still("transform_position_80")
	shell._edit_layer(source_id, func(doc):
		(look_script.find_layer(doc, source_id)["transform"] as Dictionary)["scale"] = [1.15, 1.15]
	)
	await frames(seg, 8)
	shell._edit_layer(source_id, func(doc):
		(look_script.find_layer(doc, source_id)["transform"] as Dictionary)["rotation_deg"] = 12.0
	)
	await frames(seg, 8)
	await still("transform_scale_rotation")
	shell._edit_layer(source_id, func(doc):
		(look_script.find_layer(doc, source_id)["transform"] as Dictionary)["flip_x"] = true
	)
	await frames(seg, 8)
	await still("transform_flip")
	shell._edit_layer(source_id, func(doc):
		look_script.find_layer(doc, source_id)["transform"] = look_script.neutral_transform()
	)
	await frames(seg, 8)
	await still("transform_reset")
	# displacement drivers
	for driver in ["NOISE", "DIRECTIONAL", "WAVE", "CELLULAR", "FRINGE_DRIVER"]:
		shell._edit_layer(source_id, func(doc):
			var d: Dictionary = look_script.find_layer(doc, source_id)["displacement"]
			d["enabled"] = true
			d["driver"] = driver
			d["amount_px"] = [42.0, 22.0]
			d["speed"] = 1.2
			d["scale"] = 2.0
		)
		await frames(seg, 10)
		await still("displacement_" + driver.to_lower())
	shell._edit_layer(source_id, func(doc):
		var d: Dictionary = look_script.find_layer(doc, source_id)["displacement"]
		d["driver"] = "NOISE"
		d["edge_mode"] = "TRANSPARENT"
	)
	await frames(seg, 8)
	await still("displacement_edge_transparent")
	shell._edit_layer(source_id, func(doc):
		(look_script.find_layer(doc, source_id)["displacement"] as Dictionary)["edge_mode"] = "MIRROR"
	)
	await frames(seg, 8)
	await still("displacement_edge_mirror")
	# mask modes on the halo layer if present
	var mask_layer_id := ""
	for raw in shell.session.look["layers"]:
		if str((raw as Dictionary).get("name", "")) == "Outer Halo":
			mask_layer_id = str((raw as Dictionary)["layer_id"])
	if mask_layer_id != "":
		for region in ["EDGE_BAND", "OUTER_BAND", "INNER_BAND"]:
			shell._edit_layer(mask_layer_id, func(doc):
				var m: Dictionary = look_script.find_layer(doc, mask_layer_id)["mask"]
				m["enabled"] = true
				m["source"] = "ORIGINAL_SOURCE_ALPHA"
				m["region"] = region
				m["width_px"] = 10.0
				m["feather_px"] = 4.0
			)
			await frames(seg, 10)
			await still("mask_region_" + region.to_lower())
		shell._edit_layer(mask_layer_id, func(doc):
			look_script.find_layer(doc, mask_layer_id)["mask"]["invert"] = true
		)
		await frames(seg, 10)
		await still("mask_invert")
		shell._edit_layer(mask_layer_id, func(doc):
			var m: Dictionary = look_script.find_layer(doc, mask_layer_id)["mask"]
			m["invert"] = false
			m["width_px"] = 24.0
			m["feather_px"] = 12.0
		)
		await frames(seg, 10)
		await still("mask_width_feather")

func seg_fx_planes() -> void:
	var seg := "fx_planes"
	await select_target("echo_left")
	await frames(seg, 6)
	var look_script = load("res://scripts/fx_vnext/fx_look.gd")
	var layers: Array = shell.session.look.get("layers", [])
	var fx_id := ""
	for raw in layers:
		if str((raw as Dictionary).get("type", "")) == "FX":
			fx_id = str((raw as Dictionary)["layer_id"])
			break
	if fx_id == "":
		shell._action_add_layer("Edge Treatment")
		await frames(seg, 10)
		layers = shell.session.look["layers"]
		fx_id = str((layers[layers.size() - 1] as Dictionary)["layer_id"])
	shell._drop_layer_on_plane(fx_id, "TARGET_OVERLAY")
	await frames(seg, 10)
	await still("fx_over_source")
	shell._drop_layer_on_plane(fx_id, "TARGET_UNDERLAY")
	await frames(seg, 12)
	await still("fx_under_source")
	shell._drop_layer_on_plane(fx_id, "TARGET_OVERLAY")
	await frames(seg, 8)
	# LAYER_BELOW / COMPOSITE_BELOW hero case
	shell._edit_layer(fx_id, func(doc):
		var l: Dictionary = look_script.find_layer(doc, fx_id)
		l["input"] = "COMPOSITE_BELOW"
		(l["fx"] as Dictionary)["fringe"] = 1.4
		(l["fx"] as Dictionary)["intensity"] = 1.3
		(l["fx"] as Dictionary)["edge_width"] = 10.0
		(l["fx"] as Dictionary)["wind_reach"] = 40.0
	)
	await frames(seg, 14)
	await still("fx_composite_below")
	shell._edit_layer(fx_id, func(doc):
		(look_script.find_layer(doc, fx_id))["input"] = "LAYER_BELOW"
	)
	await frames(seg, 12)
	await still("fx_layer_below")
	# composition background / foreground planes
	shell._edit_layer(fx_id, func(doc):
		var l: Dictionary = look_script.find_layer(doc, fx_id)
		l["input"] = "ORIGINAL_SOURCE"
		l["plane"] = "COMPOSITION_BACKGROUND"
		(l["fx"] as Dictionary)["dither"] = 1.0
		(l["fx"] as Dictionary)["fringe"] = 0.0
	)
	await frames(seg, 12)
	await still("fx_composition_background")
	shell._edit_layer(fx_id, func(doc):
		(look_script.find_layer(doc, fx_id))["plane"] = "COMPOSITION_FOREGROUND"
	)
	await frames(seg, 12)
	await still("fx_composition_foreground")

func seg_families() -> void:
	var seg := "families"
	for family in ["FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1", "TEAM_3V1"]:
		shell._on_remount_requested(family, "debug", "ice_mage", "doge_man")
		await frames(seg, 16)
		await still("family_" + family.to_lower())
	shell._on_remount_requested("1v1", "debug", "ice_mage", "doge_man")
	await frames(seg, 12)
	await still("family_1v1_back")

func seg_study_zoom() -> void:
	var seg := "study_zoom"
	await select_target("mark")
	await frames(seg, 8)
	for zoom in ["100%", "200%", "400%"]:
		shell._set_study(zoom)
		await frames(seg, 12)
		await still("study_" + zoom.trim_suffix("%"))
		if zoom == "400%":
			# authoring-neutral proof capture while zoomed
			await still("study_400_while_editing")
	shell._set_study("400%") # toggle off
	await frames(seg, 8)
	await still("study_off_restored")

func seg_migration_production() -> void:
	var seg := "migration_production"
	var FxMigrationScript = load("res://scripts/fx_vnext/fx_migration.gd")
	var migration = FxMigrationScript.new()
	var fixture := {}
	var file := FileAccess.open("res://tests/fixtures/vnext/fixture_fx_looks_v03.json", FileAccess.READ)
	if file != null:
		fixture = JSON.parse_string(file.get_as_text())
		file.close()
	var migrated: Dictionary = migration.migrate_looks_document(fixture)
	var written := 0
	for look_id in (migrated["looks"] as Dictionary).keys():
		var result: Dictionary = shell.production.apply({"look": migrated["looks"][look_id]})
		if bool(result.get("ok", false)):
			written += 1
	var FxResolverScript = load("res://scripts/fx_vnext/fx_resolver.gd")
	var assignments: Dictionary = shell.production.load_assignments()["doc"]
	FxResolverScript.upsert_binding(assignments, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "BASELINE_ECHO_DITHER_RGB", "audit migration demo")
	shell.production.apply({"assignments": assignments})
	print("[TOUR] migration written=", written)
	shell.drafts.clear_target(str(shell.session.signature))
	await select_target("echo_left")
	await frames(seg, 16)
	await still("migrated_look_opened_from_production")
	await select_target("mark")
	await frames(seg, 12)
	await still("migrated_mark_review_badge")
