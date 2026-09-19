extends SceneTree
# P0-1 behavioral proof for the global Cursor native-pointer ownership boundary.
# The FX Lab temporarily uses the OS pointer; frontend/gameplay keeps the
# existing custom hand contract before and after the scoped authoring interval.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

func run() -> void:
	var cursor = root.get_node_or_null("Cursor")
	_check(cursor != null, "global Cursor autoload exists")
	if cursor == null:
		_finish()
		return
	_check(cursor.has_method("acquire_native_pointer"), "Cursor exposes acquire_native_pointer(owner)")
	_check(cursor.has_method("release_native_pointer"), "Cursor exposes release_native_pointer(owner)")
	_check(cursor.has_method("is_native_pointer_owned"), "Cursor exposes native-pointer ownership state")
	_check(cursor.has_method("native_pointer_owner_count"), "Cursor exposes native-pointer owner count")
	if not cursor.has_method("acquire_native_pointer") or not cursor.has_method("release_native_pointer"):
		_finish()
		return

	var hand: Control = cursor.hand
	_check(hand != null, "global Cursor owns the game hand")
	if hand == null:
		_finish()
		return

	# Establish a non-default frontend state so final release proves restoration,
	# rather than merely proving that the native mode can turn itself off.
	hand.set_scope(hand.SCOPE_FRONTEND)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hand.visible = true
	hand.set_visual_mode(hand.Visual.CARRY)
	var prior_mouse_mode: int = int(Input.mouse_mode)
	var prior_hand_visible: bool = hand.visible
	var prior_pose: int = int(hand.visual)

	# Control-authored shapes remain native-compatible when the OS pointer is
	# visible. Headless builds cannot prove the OS compositor's final glyph, but
	# they can prove the shipped Control shape contract and, when available, the
	# DisplayServer round-trip.
	var shape_probe := Control.new()
	shape_probe.name = "NativeCursorShapeProbe"
	shape_probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shape_probe.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	root.add_child(shape_probe)
	await _frames(1)
	_check(shape_probe.mouse_default_cursor_shape == Control.CURSOR_HSIZE,
		"synthetic FX Lab resize handle keeps its native HSIZE cursor shape")
	var prior_native_shape := -1
	var can_probe_native_shape := DisplayServer.has_method("cursor_get_shape") and DisplayServer.has_method("cursor_set_shape")
	if can_probe_native_shape and DisplayServer.get_name() != "headless":
		prior_native_shape = int(DisplayServer.call("cursor_get_shape"))
		DisplayServer.call("cursor_set_shape", int(Control.CURSOR_HSIZE))
		_check(int(DisplayServer.call("cursor_get_shape")) == int(Control.CURSOR_HSIZE),
			"native cursor shape round-trips through DisplayServer")
	else:
		print("[CURSOR-NATIVE] native shape probe skipped (headless compositor)")

	var owner_a := Node.new()
	owner_a.name = "FxLabAuthoringOwner"
	root.add_child(owner_a)
	var owner_b := Node.new()
	owner_b.name = "FxLabPreviewOwner"
	root.add_child(owner_b)

	# First owner enters authoring scope: native OS pointer visible, game hand
	# hidden, and the first acquisition captures the frontend state.
	cursor.acquire_native_pointer(owner_a)
	_check(cursor.is_native_pointer_owned(), "authoring owner enters native-pointer mode")
	_check(cursor.native_pointer_owner_count() == 1, "first owner is registered exactly once")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "native-pointer mode makes the OS cursor visible")
	_check(not hand.visible, "native-pointer mode hides the game hand")

	# Re-acquisition by the same owner is idempotent, while another owner gets a
	# separate claim and does not create a second snapshot/restore transition.
	cursor.acquire_native_pointer(owner_a)
	_check(cursor.native_pointer_owner_count() == 1, "re-acquiring the same owner is idempotent")
	cursor.acquire_native_pointer(owner_b)
	_check(cursor.native_pointer_owner_count() == 2, "multiple owners can hold native-pointer mode")
	hand.set_scope(hand.SCOPE_FRONTEND)
	_check(not hand.visible, "frontend scope cannot unhide the hand while native mode is owned")
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	await _frames(1)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "native ownership reasserts visible OS cursor after remount-side writes")

	# A partial release leaves the native pointer active; an unknown/repeated
	# release cannot release another owner's claim.
	cursor.release_native_pointer(owner_a)
	_check(cursor.native_pointer_owner_count() == 1, "releasing one owner leaves the other owner active")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not hand.visible,
		"partial release preserves native OS pointer and hidden hand")
	cursor.release_native_pointer(owner_a)
	_check(cursor.native_pointer_owner_count() == 1, "releasing an owner twice is idempotent")

	# The persistent Cursor service survives an authoring remount. A screen
	# lifecycle reset may change its transient pose, but it must not clear the
	# ownership boundary or reveal the hand during the remount.
	hand.begin_screen("fx_lab_remount")
	await _frames(1)
	_check(cursor.native_pointer_owner_count() == 1 and cursor.is_native_pointer_owned(),
		"authoring remount does not reset native-pointer ownership")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not hand.visible,
		"authoring remount keeps native OS cursor visible and game hand hidden")

	cursor.release_native_pointer(owner_b)
	_check(not cursor.is_native_pointer_owned() and cursor.native_pointer_owner_count() == 0,
		"final owner release ends native-pointer mode")
	_check(Input.mouse_mode == prior_mouse_mode, "final release restores the prior mouse mode")
	_check(hand.visible == prior_hand_visible, "final release restores prior hand visibility")
	_check(int(hand.visual) == prior_pose, "final release restores the prior hand pose")

	# A later authoring interval takes a fresh snapshot and restores it again;
	# ownership is not a one-shot global latch.
	cursor.acquire_native_pointer(owner_a)
	_check(cursor.is_native_pointer_owned() and not hand.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"a released owner can re-acquire native-pointer mode")
	cursor.release_native_pointer(owner_a)
	_check(not cursor.is_native_pointer_owned() and Input.mouse_mode == prior_mouse_mode and hand.visible == prior_hand_visible,
		"re-acquire/release restores the frontend state again")

	if prior_native_shape >= 0:
		DisplayServer.call("cursor_set_shape", prior_native_shape)
	shape_probe.queue_free()
	owner_a.queue_free()
	owner_b.queue_free()
	await _frames(1)
	_finish()

func _finish() -> void:
	if failures > 0:
		print("[CURSOR-NATIVE] checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	print("[CURSOR-NATIVE] checks=%d failures=0" % checks)
	quit(0)
