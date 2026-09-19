extends SceneTree
## FX Lab lifecycle UX proof: the mounted shell owns native-pointer mode, keeps
## that claim through a runtime remount, and releases it exactly once on exit.

var checks := 0
var failures := 0
var shell: Control
var cursor: Node

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
	cursor = root.get_node_or_null("Cursor")
	_check(cursor != null, "global Cursor autoload exists")
	if cursor == null:
		_finish()
		return
	_check(cursor.has_method("native_pointer_owner_count"), "Cursor exposes owner count")
	if not cursor.has_method("native_pointer_owner_count"):
		_finish()
		return

	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	_check(scene != null, "FX Lab scene loads")
	if scene == null:
		_finish()
		return
	shell = scene.instantiate()
	root.add_child(shell)
	await _frames(8)

	_check(shell.get("_native_pointer_acquired") == true, "mounted FX Lab acquires native-pointer ownership")
	_check(cursor.native_pointer_owner_count() == 1, "mounted FX Lab is one native-pointer owner")
	var owner_before: int = int(cursor.native_pointer_owner_count())

	# Remount is a runtime operation, not a shell lifecycle transition. It must
	# preserve the shell owner and avoid a visible release/reacquire flicker.
	_check(shell.has_method("_remount_current"), "FX Lab exposes its runtime remount path")
	if shell.has_method("_remount_current"):
		shell.call("_remount_current")
	await _frames(8)
	_check(shell.get("_native_pointer_acquired") == true, "runtime remount preserves Lab ownership")
	_check(cursor.native_pointer_owner_count() == owner_before, "runtime remount does not duplicate or release owner")

	shell.queue_free()
	await _frames(2)
	_check(cursor.native_pointer_owner_count() == 0, "freeing the Lab releases native-pointer ownership")
	_check(cursor.call("is_native_pointer_owned") == false, "freeing the Lab exits native-pointer mode")
	_finish()

func _finish() -> void:
	if failures > 0:
		print("[FX-LAB-NATIVE] checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	print("[FX-LAB-NATIVE] checks=%d failures=0" % checks)
	quit(0)
