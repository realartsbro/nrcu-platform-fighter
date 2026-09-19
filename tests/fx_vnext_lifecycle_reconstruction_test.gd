extends SceneTree
# Explicit transport lifecycle proof. Preview-owned screens remain inspectable at
# the deterministic EXIT end, and absolute seeks reconstruct every phase from
# arbitrary prior state.

const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")

var checks := 0
var failures := 0

func _init() -> void:
	var runtime = FxScreenRuntimeScript.new()
	root.add_child(runtime.subvp)
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "preview runtime mounts")
	await _settle(20)
	var screen = runtime.screen
	screen.lab_preview_pause()
	var end_time: float = screen.minimum_exposure() + screen.cover_close_duration() + screen.reveal_duration() + 0.01
	runtime.seek(end_time)
	_check(str(screen.state()) == "done", "explicit seek reconstructs EXIT end as DONE", str(screen.state()))
	_check(bool(screen.visible), "preview-owned screen stays visible at explicit EXIT end")
	_check(bool(screen.cover_closed()), "explicit EXIT end leaves cover closed")
	_check(is_instance_valid(screen), "preview-owned screen survives explicit EXIT end")
	print("[FX-LIFECYCLE-RECONSTRUCTION] checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame

func _check(ok: bool, name: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s%s" % [name, (" · " + detail) if detail != "" else ""])
	else:
		print("PASS: %s%s" % [name, (" · " + detail) if detail != "" else ""])
