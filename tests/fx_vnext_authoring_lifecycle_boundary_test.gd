extends SceneTree
# P0 regression: authoring/evaluation rebuilds must not seek the presentation
# lifecycle. A real FX Lab target-row selection is exercised after the mounted
# screen has remained in its open-ended HOLD beyond TIMELINE_LEN.

var shell: Control
var checks := 0
var failures := 0
var evidence_dir := ""

func _init() -> void:
	evidence_dir = OS.get_environment("FXLAB_EVIDENCE_DIR").strip_edges()
	if evidence_dir != "":
		DirAccess.make_dir_recursive_absolute(evidence_dir)
	shell = _spawn()
	await _settle(30)
	# Open a real authoring target so the preview has meaningful pixels before
	# the boundary action. This is setup; the regression action below is the real
	# target-row selection path.
	shell._select_key("mark", false)
	await _settle(20)
	var screen = shell.runtime.screen
	_check(screen != null, "mounted FX Lab owns a real VS screen")
	if screen == null:
		_finish()
		return
	await _settle(360)
	_check(str(screen.state()) == "hold", "presentation remains in open-ended HOLD past timeline length", str(screen.state()))
	_check(float(screen.elapsed()) > float(shell.TIMELINE_LEN), "HOLD elapsed time is not clamped by the authoring UI", "elapsed=%.3f timeline=%.3f" % [float(screen.elapsed()), float(shell.TIMELINE_LEN)])
	var before := _lifecycle_snapshot(screen)
	var before_image: Image = await _capture_preview("before_target_row_selection", before)
	_check(_select_target_row_via_gui("echo_left"), "real target browser row selection is available")
	await _settle(20)
	var after := _lifecycle_snapshot(screen)
	var after_image: Image = await _capture_preview("after_target_row_selection", after)
	_check(after.get("state") == before.get("state"), "target selection preserves presentation state", "%s -> %s" % [before.get("state"), after.get("state")])
	_check(after.get("visible") == before.get("visible"), "target selection preserves screen visibility")
	_check(after.get("cover_closed") == before.get("cover_closed"), "target selection preserves cover state")
	_check(after.get("match_ready") == before.get("match_ready"), "target selection preserves match-ready state")
	_check(after.get("paused") == before.get("paused"), "target selection preserves paused intent")
	_check(_mean_abs_diff(before_image, after_image) < 0.45, "target selection does not replace the preview with a catastrophic frame", "mean_diff=%.5f" % _mean_abs_diff(before_image, after_image))

	# Repeat the same real target-row action while the user's transport is paused.
	screen.lab_preview_pause()
	await _settle(5)
	var paused_before := _lifecycle_snapshot(screen)
	var paused_before_image: Image = await _capture_preview("before_paused_target_row_selection", paused_before)
	_check(_select_target_row_via_gui("primary_left"), "paused target browser row selection is available")
	await _settle(20)
	var paused_after := _lifecycle_snapshot(screen)
	var paused_after_image: Image = await _capture_preview("after_paused_target_row_selection", paused_after)
	_assert_lifecycle_unchanged(paused_before, paused_after, "paused target selection")
	_check(_mean_abs_diff(paused_before_image, paused_after_image) < 0.45, "paused target selection keeps a meaningful preview", "mean_diff=%.5f" % _mean_abs_diff(paused_before_image, paused_after_image))

	# Authoring rebuilds use the same paused HOLD boundary: add FX, edit a visible
	# slider, undo, redo, and save draft without touching presentation lifecycle.
	var authoring_before := _lifecycle_snapshot(screen)
	shell._action_add_layer("Custom FX Layer")
	await _settle(12)
	var after_add := _lifecycle_snapshot(screen)
	_assert_lifecycle_unchanged(authoring_before, after_add, "add FX")
	var opacity := _find_slider_under(shell.inspector_content, "Opacity")
	_check(opacity != null, "visible authoring slider is reachable after adding FX")
	if opacity != null:
		opacity.value = 0.55
		await _settle(12)
	var after_edit := _lifecycle_snapshot(screen)
	_assert_lifecycle_unchanged(authoring_before, after_edit, "visible slider edit")
	shell._action_undo()
	await _settle(12)
	var after_undo := _lifecycle_snapshot(screen)
	_assert_lifecycle_unchanged(authoring_before, after_undo, "undo")
	shell._action_redo()
	await _settle(12)
	var after_redo := _lifecycle_snapshot(screen)
	_assert_lifecycle_unchanged(authoring_before, after_redo, "redo")
	shell._action_save_draft()
	await _settle(12)
	var after_save := _lifecycle_snapshot(screen)
	_assert_lifecycle_unchanged(authoring_before, after_save, "Save Draft")
	await _capture_preview("after_authoring_actions", after_save)

	await _exercise_explicit_transport(screen)
	_finish()

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame

func _select_target_row_via_gui(key: String) -> bool:
	if shell == null or shell.browser == null or shell.browser.tree == null:
		return false
	for item in shell.browser.row_keys.keys():
		if str(shell.browser.row_keys[item]) == key:
			# Use the shipped Tree selection signal path, not the shell's private
			# _select_key helper. This is the same path a target-row click uses.
			item.select(0)
			shell.browser.tree.item_selected.emit()
			return true
	return false

func _lifecycle_snapshot(screen: Node) -> Dictionary:
	return {
		"state": str(screen.state()),
		"elapsed": float(screen.elapsed()),
		"visible": bool(screen.visible),
		"cover_closed": bool(screen.cover_closed()),
		"match_ready": bool(screen.match_ready_signalled()),
		"paused": bool(screen.lab_preview_is_paused()),
	}

func _assert_lifecycle_unchanged(before: Dictionary, after: Dictionary, action: String) -> void:
	_check(after.get("state") == before.get("state"), action + " preserves presentation state", "%s -> %s" % [before.get("state"), after.get("state")])
	_check(after.get("visible") == before.get("visible"), action + " preserves screen visibility")
	_check(after.get("cover_closed") == before.get("cover_closed"), action + " preserves cover state")
	_check(after.get("match_ready") == before.get("match_ready"), action + " preserves match-ready state")
	_check(after.get("paused") == before.get("paused"), action + " preserves paused intent")
	_check(absf(float(after.get("elapsed", 0.0)) - float(before.get("elapsed", 0.0))) < 0.05, action + " does not mutate presentation elapsed", "%.3f -> %.3f" % [float(before.get("elapsed", 0.0)), float(after.get("elapsed", 0.0))])

func _find_slider_under(node: Node, label_text: String) -> HSlider:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			var label = child.get_child(0)
			if label is Label and str((label as Label).text).strip_edges() == label_text:
				for sub in child.get_children():
					if sub is HSlider:
						return sub as HSlider
		var found := _find_slider_under(child, label_text)
		if found != null:
			return found
	return null

func _exercise_explicit_transport(screen: Node) -> void:
	var hold: float = screen.hold_start_time()
	var exposure: float = screen.minimum_exposure()
	var close: float = screen.cover_close_duration()
	var reveal: float = screen.reveal_duration()
	var end_time: float = exposure + close + reveal + 0.01
	_check(bool(screen.lab_preview_is_paused()), "explicit transport test starts with paused intent")
	await _exercise_long_hold_frame_steps(screen)
	shell._on_time_entered(0.2)
	_check(str(screen.state()) == "entry" and absf(screen.elapsed() - 0.2) < 0.02, "explicit numeric seek reconstructs ENTRY", str(screen.state()))
	_check(bool(screen.lab_preview_is_paused()), "ENTRY seek preserves paused intent")
	shell._on_time_entered(hold + 0.05)
	_check(str(screen.state()) == "hold", "explicit numeric seek reconstructs HOLD", str(screen.state()))
	shell._on_time_entered(exposure + close * 0.5)
	_check(str(screen.state()) == "exit" and not screen.cover_closed(), "explicit numeric seek reconstructs EXIT cover close", str(screen.state()))
	shell._on_time_entered(exposure + close + 0.01)
	_check(str(screen.state()) == "exit" and screen.cover_closed() and screen.visible, "explicit numeric seek reconstructs full-cover EXIT", str(screen.state()))
	shell._on_time_entered(exposure + close + reveal * 0.5)
	var root_node := screen.get_node_or_null("Root") as Control
	var reveal_alpha := float(root_node.modulate.a) if root_node != null else -1.0
	_check(str(screen.state()) == "exit" and screen.cover_closed() and reveal_alpha > 0.0 and reveal_alpha < 1.0, "explicit numeric seek reconstructs reveal midpoint", "alpha=%.3f" % reveal_alpha)
	shell._on_time_entered(end_time)
	_check(str(screen.state()) == "done" and screen.visible, "explicit numeric seek reconstructs EXIT end without hiding preview", str(screen.state()))
	shell._on_time_entered(hold + 0.05)
	_check(str(screen.state()) == "hold" and screen.visible, "seek back to HOLD reconstructs from arbitrary EXIT state", str(screen.state()))
	shell._on_time_entered(0.2)
	_check(str(screen.state()) == "entry" and screen.visible, "seek back to ENTRY reconstructs from arbitrary HOLD state", str(screen.state()))
	_check(bool(screen.lab_preview_is_paused()), "all explicit seeks preserve paused intent")
	# The same end-and-back path while playing must resume the lifecycle clock,
	# not merely clear the paused flag.
	screen.lab_preview_resume()
	shell.runtime.seek(end_time)
	shell.runtime.seek(0.2)
	_check(not screen.lab_preview_is_paused() and screen.is_processing(), "playing intent survives explicit EXIT-end then back seek")
	screen.lab_preview_pause()

func _exercise_long_hold_frame_steps(screen: Node) -> void:
	# The presentation clock is deliberately allowed to run far beyond the
	# authoring timeline. Frame steps must still operate on the authored
	# playhead, not on raw lifecycle elapsed time from the open-ended HOLD.
	var authored_t := 1.2
	shell._on_time_entered(authored_t)
	screen.lab_preview_resume()
	await _settle(360)
	var lifecycle_t := float(screen.elapsed())
	_check(str(screen.state()) == "hold", "long-HOLD frame-step setup remains in HOLD", str(screen.state()))
	_check(lifecycle_t > float(shell.TIMELINE_LEN), "long-HOLD frame-step setup exceeds authoring timeline", "elapsed=%.3f timeline=%.3f" % [lifecycle_t, float(shell.TIMELINE_LEN)])
	_check(absf(_renderer_authoring_time() - authored_t) < 0.02, "long HOLD does not advance the authoring playhead", "authoring=%.3f expected=%.3f" % [_renderer_authoring_time(), authored_t])
	shell._transport_step_back()
	var back_t := authored_t - float(shell.FRAME_STEP)
	_check(absf(_renderer_authoring_time() - back_t) < 0.02, "1F back uses the authoring playhead after long HOLD", "authoring=%.3f expected=%.3f" % [_renderer_authoring_time(), back_t])
	_check(str(screen.state()) == "hold", "1F back does not jump lifecycle out of HOLD", str(screen.state()))
	shell._transport_step_forward()
	_check(absf(_renderer_authoring_time() - authored_t) < 0.02, "1F forward uses the authoring playhead after long HOLD", "authoring=%.3f expected=%.3f" % [_renderer_authoring_time(), authored_t])
	_check(str(screen.state()) == "hold", "1F forward does not jump lifecycle out of HOLD", str(screen.state()))
	screen.lab_preview_pause()

func _renderer_authoring_time() -> float:
	if shell.renderer != null and shell.renderer.has_method("clock_state"):
		return float(shell.renderer.clock_state().get("presentation_time", -1.0))
	return -1.0

func _capture_preview(label: String, lifecycle: Dictionary) -> Image:
	if DisplayServer.get_name().to_lower().contains("headless"):
		await process_frame
	else:
		await RenderingServer.frame_post_draw
	var headless := DisplayServer.get_name().to_lower().contains("headless")
	if headless:
		_check(true, label + " readback skipped only under headless dummy rendering")
		return null
	var texture: Texture2D = shell.runtime.subvp.get_texture()
	if texture == null:
		_check(false, label + " readback texture exists")
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_check(false, label + " readback is non-empty")
		return null
	var quality := _quality(image)
	_check(float(quality.get("mean", 0.0)) > 0.01 and float(quality.get("lit_fraction", 0.0)) > 0.01, label + " is meaningful and not catastrophic black", str(quality))
	if evidence_dir != "":
		image.save_png(evidence_dir.path_join(label + ".png"))
		var authoring_time := 0.0
		if shell.renderer != null and shell.renderer.has_method("clock_state"):
			authoring_time = float(shell.renderer.clock_state().get("presentation_time", 0.0))
		var metadata := {
			"label": label,
			"lifecycle": lifecycle,
			"authoring_time": authoring_time,
			"preview_mode": str(shell.preview_mode),
			"selected_target": str(shell.selected_key),
			"screen_visible": bool(shell.runtime.screen.visible),
			"cover_state": bool(shell.runtime.screen.cover_closed()),
			"quality": quality,
		}
		var file := FileAccess.open(evidence_dir.path_join(label + ".json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(metadata, "  "))
			file.close()
	return image

func _quality(image: Image) -> Dictionary:
	var total := 0.0
	var lit := 0
	var samples := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var pixel := image.get_pixel(x, y)
			var value := pixel.r + pixel.g + pixel.b
			total += value
			if value > 0.08:
				lit += 1
			samples += 1
	return {"mean": total / float(maxi(samples, 1)) / 3.0, "lit_fraction": float(lit) / float(maxi(samples, 1)), "width": image.get_width(), "height": image.get_height()}

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 0.0
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 3
	return total / float(maxi(count, 1))

func _check(ok: bool, name: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s%s" % [name, (" · " + detail) if detail != "" else ""])
	else:
		print("PASS: %s%s" % [name, (" · " + detail) if detail != "" else ""])

func _finish() -> void:
	print("[FX-AUTHORING-LIFECYCLE-BOUNDARY] checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
