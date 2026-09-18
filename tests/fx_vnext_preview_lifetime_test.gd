extends SceneTree
# Researcher A: explicit lifecycle contract split. The GAME lifecycle frees
# the screen on FINISHED (untouched legacy behavior); the PREVIEW/REFERENCE
# lifecycle (fx_preview_no_teardown) freezes on deterministic frames so
# seeks past minimum_exposure keep inspecting the same composition.
# Headless: lifetime needs no rendering, only node validity across frames.

const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")

var checks: Array = []
var failures := 0

func _init() -> void:
	# Game lifecycle: a bare screen with no preview flag tears itself down.
	var bare = load("res://scenes/vs_screen.tscn").instantiate()
	root.add_child(bare)
	await settle(10)
	_check(not bare.has_meta("fx_preview_no_teardown"), "A game screen carries no preview flag by default")
	bare._finish()
	await settle(5)
	_check(not is_instance_valid(bare), "A game screen frees itself on FINISHED (legacy teardown intact)")
	# Preview lifecycle: mounted screens opt in and survive exit + seeks.
	var rt = FxScreenRuntimeScript.new()
	root.add_child(rt.subvp)
	await settle(10)
	rt.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(10)
	_check(bool(rt.screen.get_meta("fx_preview_no_teardown", false)), "A mounted preview screen opts in explicitly")
	rt.seek(1.5 + 0.3)
	await settle(10)
	_check(is_instance_valid(rt.screen), "A preview screen survives post-exposure seeks")
	rt.seek(0.2)
	await settle(10)
	_check(is_instance_valid(rt.screen), "A preview screen resurrects back to entry")
	var rootn = rt.screen.get_node_or_null("Root") as Control
	_check(rootn != null and absf(float((rootn as Control).modulate.a) - 1.0) < 0.01, "Resurrection restores Root opacity (un-fades EXIT)", str((rootn as Control).modulate) if rootn != null else "missing")
	rt.subvp.queue_free()
	await settle(4)
	await _game_full_flow()
	print("[FX-PREVIEW-LIFETIME] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

var _cover_count := 0
var _exit_count := 0

func _game_full_flow() -> void:
	# Real game lifecycle, no preview flag: start -> ENTRY -> HOLD ->
	# match_ready -> exposure -> EXIT -> cover -> exit_finished -> free.
	var scr = load("res://scenes/vs_screen.tscn").instantiate()
	root.add_child(scr)
	await settle(10)
	_check(bool(scr.start("ice_mage", "doge_man", "debug")), "Game flow starts")
	scr.connect("transition_cover_reached", func() -> void: _cover_count += 1)
	scr.connect("exit_finished", func() -> void: _exit_count += 1)
	scr.signal_match_ready()
	var frames := 0
	while is_instance_valid(scr) and frames < 36000:
		await process_frame
		frames += 1
	_check(_cover_count == 1, "Game flow emits transition_cover_reached once", str(_cover_count))
	_check(_exit_count == 1, "Game flow emits exit_finished once", str(_exit_count))
	_check(not is_instance_valid(scr), "Game flow frees the screen at the end")

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
	checks.append(line)
	if not ok:
		failures += 1
		print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame
