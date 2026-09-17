extends Node
# Reference harness: renders the REAL vs_screen.tscn (copied verbatim from the
# VS lane) at 1280x720 into PNGs so the FX lab can be verified against the
# actual screen composition.
#   --left=ice_mage --right=doge_man --stage=debug [--at=0.4,1.2]
# Output: C:/Users/will/nrcu-vfx-lab/reference/vsref_<left>_<right>_<t>.png

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1]
	var left: String = args.get("left", "ice_mage")
	var right: String = args.get("right", "doge_man")
	var stage: String = args.get("stage", "debug")
	var at_list := [0.4, 0.65, 1.2]
	if args.has("at"):
		at_list = []
		for s in str(args["at"]).split(","):
			at_list.append(float(s))
	at_list.sort()

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 1)
	bg.size = Vector2(1280, 720)
	vp.add_child(bg)

	var screen: Node = load("res://scenes/vs_screen.tscn").instantiate()
	vp.add_child(screen)
	await get_tree().process_frame
	var ok: bool = screen.start(left, right, stage)
	print("[vsref] start=", ok, " left=", left, " right=", right, " stage=", stage)

	var t := 0.0
	for at in at_list:
		while t < float(at):
			await get_tree().process_frame
			t += get_process_delta_time()
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := "user://vsref_%s_%s_%s.png" % [left, right, str(at).replace(".", "p")]
		img.save_png(path)
		print("[vsref] saved ", path, " at t≈", t)
	get_tree().quit()
