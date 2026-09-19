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
	await _exercise_arbitrary_prior_state_reconstruction(runtime, screen, end_time)
	print("[FX-LIFECYCLE-RECONSTRUCTION] checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _exercise_arbitrary_prior_state_reconstruction(runtime, screen, end_time: float) -> void:
	var exposure: float = screen.minimum_exposure()
	var close: float = screen.cover_close_duration()
	var reveal: float = screen.reveal_duration()
	var exit_start: float = exposure
	var exit_close: float = exposure + close * 0.5
	var reveal_mid: float = exposure + close + reveal * 0.5
	var hold: float = screen.hold_start_time() + 0.05
	var root_node := screen.get_node_or_null("Root") as Control

	# Every target is reached from an explicitly reconstructed DONE frame, not
	# from a convenient neighboring phase. This catches stale EXIT fade state.
	runtime.seek(end_time)
	runtime.seek(exit_close)
	_check(str(screen.state()) == "exit" and not screen.cover_closed(), "DONE -> EXIT-close reconstructs cover-close phase", str(screen.state()))
	_check(_root_alpha(root_node) > 0.99, "DONE -> EXIT-close restores an opaque root", "alpha=%.3f" % _root_alpha(root_node))

	runtime.seek(end_time)
	runtime.seek(exit_start)
	_check(str(screen.state()) == "exit" and not screen.cover_closed(), "DONE -> EXIT-start reconstructs exit start", str(screen.state()))
	_check(_root_alpha(root_node) > 0.99, "DONE -> EXIT-start restores an opaque root", "alpha=%.3f" % _root_alpha(root_node))

	runtime.seek(end_time)
	runtime.seek(reveal_mid)
	_check(str(screen.state()) == "exit" and screen.cover_closed(), "DONE -> reveal reconstructs reveal phase", str(screen.state()))
	_check(_root_alpha(root_node) > 0.0 and _root_alpha(root_node) < 1.0, "DONE -> reveal reconstructs reveal alpha", "alpha=%.3f" % _root_alpha(root_node))

	runtime.seek(reveal_mid)
	runtime.seek(exit_close)
	_check(str(screen.state()) == "exit" and not screen.cover_closed(), "reveal -> EXIT-close reconstructs cover-close phase", str(screen.state()))
	_check(_root_alpha(root_node) > 0.99, "reveal -> EXIT-close restores an opaque root", "alpha=%.3f" % _root_alpha(root_node))

	runtime.seek(exit_close)
	runtime.seek(0.2)
	_check(str(screen.state()) == "entry", "EXIT-close -> ENTRY reconstructs entry", str(screen.state()))
	_check(_root_alpha(root_node) > 0.99, "EXIT-close -> ENTRY restores an opaque root", "alpha=%.3f" % _root_alpha(root_node))

	runtime.seek(end_time)
	runtime.seek(hold)
	_check(str(screen.state()) == "hold", "DONE -> HOLD reconstructs hold", str(screen.state()))
	_check(_root_alpha(root_node) > 0.99, "DONE -> HOLD restores an opaque root", "alpha=%.3f" % _root_alpha(root_node))

func _root_alpha(root_node: Control) -> float:
	return float(root_node.modulate.a) if root_node != null else -1.0

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
