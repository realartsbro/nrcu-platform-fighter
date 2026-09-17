extends SceneTree
# Packaged-app launch smoke (Round-2 Finding 19): boots the REAL shell scene,
# holds it for a few seconds, captures one frame, then quits CLEANLY - no forced
# kill, so no artificial engine leak errors appear in the final logs.

func _init() -> void:
	var frames := 360
	var frames_env := OS.get_environment("FXLAB_SMOKE_FRAMES")
	if frames_env != "":
		frames = int(frames_env)
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var shell: Control = scene.instantiate()
	root.add_child(shell)
	for i in frames:
		await process_frame
	var out := OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out != "":
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("app_launch_smoke.png"))
	var f := FileAccess.open(ProjectSettings.globalize_path("user://app_launch_smoke.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ok": shell != null, "frames": frames}, "  "))
		f.close()
	print("[LAUNCH-SMOKE] clean boot · frames=%d · quitting cleanly" % frames)
	quit(0)
