extends SceneTree
# Capture-surface isolation (researcher C): before ANY pixel assertion, prove
# the harness really captures the surface it claims. Minimal nesting —
# window -> SubViewportContainer -> SubViewport -> marker — must show the
# marker in a root capture. If this fails, no downstream readback means
# anything and the failure is harness/environment, never product behavior.

var checks: Array = []
var failures := 0

func _init() -> void:
	root.size = Vector2i(1280, 720)
	await settle(10)
	var cont := SubViewportContainer.new()
	cont.stretch = false
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cont)
	var svp := SubViewport.new()
	svp.size = Vector2i(1280, 720)
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.transparent_bg = false
	cont.add_child(svp)
	var marker := ColorRect.new()
	marker.color = Color(0.0, 0.0, 0.9)
	marker.position = Vector2(1080, 520)
	marker.size = Vector2(200, 200)
	svp.add_child(marker)
	await settle(30)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://evidence/vnext_build/capture_isolation.png"))
	var corner: Color = img.get_pixel(1179, 619)
	_check(corner.b > 0.5 and corner.r < 0.2, "C harness captures nested subviewport content", str(corner))
	# And the subviewport's own texture agrees (sample INSIDE the marker).
	var inner: Image = svp.get_texture().get_image()
	var icorner: Color = inner.get_pixel(1150, 600)
	_check(icorner.b > 0.5 and icorner.r < 0.2, "C subviewport texture carries its content", str(icorner))
	print("[FX-CAPTURE-SURFACE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, (("  (" + detail + ")") if detail != "" else "")]
	checks.append(line)
	if not ok:
		failures += 1
		print(line)

func settle(n: int) -> void:
	for i in n:
		await process_frame
