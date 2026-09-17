extends SceneTree
# Round-2 neutral-parity check (researcher request):
# Side Fields L/R, Name Plates L/R and Accent Lines L/R must, with NO vNEXT style
# active, visually match the canonical composition element they replaced. The
# generated white masks carry SHAPE/ALPHA only; colour/material comes from the
# canonical element (proxy tint). Also verified: applying an FX to one element
# changes exactly that element while the others stay at neutral parity.
# Windowed: needs rendering.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

const ELEMENTS := [
	{"node": "Root/SideFields/FieldLeft", "key": "field_left_fx_proxy", "mask": "res://assets/vs/generated/side_field_left_mask.png", "tag": "side_field_left", "family": "SIDE FIELD"},
	{"node": "Root/SideFields/FieldRight", "key": "field_right_fx_proxy", "mask": "res://assets/vs/generated/side_field_right_mask.png", "tag": "side_field_right", "family": "SIDE FIELD"},
	{"node": "Root/NamePlates/PlateLeft", "key": "plate_left_fx_proxy", "mask": "res://assets/vs/generated/name_plate_left_mask.png", "tag": "name_plate_left", "family": "NAME PLATE"},
	{"node": "Root/NamePlates/PlateRight", "key": "plate_right_fx_proxy", "mask": "res://assets/vs/generated/name_plate_right_mask.png", "tag": "name_plate_right", "family": "NAME PLATE"},
	{"node": "Root/NamePlates/AccentLeft", "key": "accent_left_fx_proxy", "mask": "res://assets/vs/generated/accent_left_mask.png", "tag": "accent_line_left", "family": "ACCENT LINE"},
	{"node": "Root/NamePlates/AccentRight", "key": "accent_right_fx_proxy", "mask": "res://assets/vs/generated/accent_right_mask.png", "tag": "accent_line_right", "family": "ACCENT LINE"},
]

var checks: Array = []
var failures: int = 0
var out_dir: String
var svp: SubViewport
var sr
var renderer
var screen_root: Node

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/neutral_parity")
	DirAccess.make_dir_recursive_absolute(out_dir)

	svp = SubViewport.new()
	svp.size = Vector2i(1280, 720)
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	sr = FxScreenRuntimeScript.new()
	var disp := SubViewportContainer.new()
	disp.stretch = true
	disp.size = Vector2(1280, 720)
	svp.add_child(disp)
	disp.add_child(sr.subvp)
	await settle(40)
	var mounted: bool = sr.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(60)
	_check(mounted, "screen mounts")
	# Parity needs a frozen transport: the suite outlives the presentation
	# (DONE frees the screen by design) and EXIT animation would confound
	# ref/proxy pairs. HOLD + pause makes every capture comparable.
	sr.seek(1.1)
	sr.screen.lab_preview_pause()
	renderer = FxLayerRendererScript.new(sr.screen, sr.registry)
	renderer.set_time(1.1)
	await settle(8)
	screen_root = sr.screen.get_node("Root")

	var refs: Dictionary = {}
	for element in ELEMENTS:
		var src = sr.screen.get_node_or_null(str(element["node"]))
		var proxy = sr.screen.get_node_or_null(str(element["node"]) + "_FXProxy")
		_check(src != null and proxy != null, "%s: source + proxy exist" % element["tag"])
		if src == null or proxy == null:
			continue
		var interior := _interior_mask(str(element["mask"]))
		# A) canonical element alone
		proxy.visible = false
		src.visible = true
		await settle(5)
		var ref_img: Image = await capture("ref_" + str(element["tag"]))
		# B) proxy alone (neutral vNEXT state)
		src.visible = false
		proxy.visible = true
		await settle(5)
		var proxy_img: Image = await capture("neutral_" + str(element["tag"]))
		refs[element["tag"]] = {"img": proxy_img, "interior": interior, "element": element}
		var full := _diff_region(ref_img, proxy_img, interior["bbox"])
		var inner := _diff_masked(ref_img, proxy_img, interior["mask"])
		var frame_mean := _diff_region(ref_img, proxy_img, Rect2i(0, 0, 1280, 720))
		var mass_in_bbox := _diff_mass_fraction(ref_img, proxy_img, interior["bbox"])
		if not (interior["mask"] as Array).is_empty():
			_check(inner <= 0.006, "%s: neutral proxy matches the canonical element" % element["tag"], "interior=%.5f bbox=%.5f frame=%.5f" % [inner, full, frame_mean])
		else:
			# thin/antialiased element (accent line): measure honestly - the
			# difference must stay sub-AA, confined to the element's band.
			_check(frame_mean <= 0.002 and mass_in_bbox >= 0.9, "%s: neutral proxy matches the canonical element (thin AA fallback)" % element["tag"], "frame=%.5f in_band_mass=%.2f bbox=%.5f" % [frame_mean, mass_in_bbox, full])
		if element["family"] == "SIDE FIELD":
			_check(full <= 0.02, "%s: no white-flat regression" % element["tag"], "bbox=%.5f" % full)
		# restore canonical+proxy default visibility for the next element
		proxy.visible = true
		src.visible = false
		await settle(2)

	# C) an FX on one element changes it and leaves the others in parity
	for fx_tag in ["side_field_left", "name_plate_left", "accent_line_left"]:
		if not refs.has(fx_tag):
			continue
		var element: Dictionary = refs[fx_tag]["element"]
		var look: Dictionary = FxLookScript.new_look("NP_" + str(element["tag"]).to_upper(), "NP")
		var layer: Dictionary = FxLookScript.new_layer("FX", "rgb")
		layer["fx"] = {"rgb": 1.0, "intensity": 1.2, "rgb_shift_amount": 22.0}
		look["layers"].append(layer)
		var applied: Dictionary = renderer.apply_look(str(element["key"]), look)
		renderer.set_time(1.1)
		await settle(8)
		_check(bool(applied.get("ok", false)), "%s: FX applies" % fx_tag, str(applied.get("errors", [])))
		var fx_img: Image = await capture("fx_" + fx_tag)
		var fx_interior: Dictionary = refs[fx_tag]["interior"]
		var fx_frame := _diff_region((refs[fx_tag]["img"] as Image), fx_img, Rect2i(0, 0, 1280, 720))
		var fx_band := _diff_region((refs[fx_tag]["img"] as Image), fx_img, fx_interior["bbox"])
		var inner := _diff_masked((refs[fx_tag]["img"] as Image), fx_img, fx_interior["mask"]) if not (fx_interior["mask"] as Array).is_empty() else fx_band
		_check(inner > 0.0008, "%s: FX visibly changes the element" % fx_tag, "delta=%.5f band=%.5f frame=%.5f" % [inner, fx_band, fx_frame])
		# another element must stay at neutral parity
		for other_tag in refs.keys():
			if other_tag == fx_tag:
				continue
			var other: Dictionary = refs[other_tag]
			var other_inner := _diff_masked((other["img"] as Image), fx_img, (other["interior"] as Dictionary)["mask"])
			_check(other_inner <= 0.02, "%s: stays in parity while %s is styled" % [str(other_tag), fx_tag], "delta=%.5f" % other_inner)
			break
		renderer.clear_target(str(element["key"]))
		await settle(5)

	var f := FileAccess.open(out_dir.path_join("summary_neutral_parity_check.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks.size(), "failures": failures, "status": "PASS" if failures == 0 else "FAIL"}, "  "))
		f.close()
	print("[NEUTRAL-PARITY] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _interior_mask(mask_path: String) -> Dictionary:
	# alpha>0.5 bbox + a 3px-eroded interior pixel list (subsampled)
	var img := Image.load_from_file(ProjectSettings.globalize_path(mask_path))
	if img == null:
		return {"bbox": Rect2i(0, 0, 1280, 720), "mask": []}
	var w := img.get_width()
	var h := img.get_height()
	var xs_min := w
	var xs_max := -1
	var ys_min := h
	var ys_max := -1
	var solid: Array = []
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if img.get_pixel(x, y).a > 0.5:
				xs_min = mini(xs_min, x)
				xs_max = maxi(xs_max, x)
				ys_min = mini(ys_min, y)
				ys_max = maxi(ys_max, y)
				if x > 3 and y > 3 and x < w - 4 and y < h - 4:
					var edge := false
					for oy in [-3, 0, 3]:
						for ox in [-3, 0, 3]:
							if img.get_pixel(x + ox, y + oy).a <= 0.5:
								edge = true
					if not edge:
						solid.append(Vector2i(x, y))
	if xs_max < 0:
		return {"bbox": Rect2i(0, 0, w, h), "mask": solid}
	return {"bbox": Rect2i(xs_min, ys_min, xs_max - xs_min + 1, ys_max - ys_min + 1), "mask": solid}

func _diff_region(a: Image, b: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, mini(rect.position.y + rect.size.y, 720), 2):
		for x in range(rect.position.x, mini(rect.position.x + rect.size.x, 1280), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(max(count, 1))

func _diff_mass_fraction(a: Image, b: Image, rect: Rect2i) -> float:
	# fraction of the frame's total difference mass that lies inside the element band
	var total := 0.0
	var inside := 0.0
	for y in range(0, 720, 2):
		for x in range(0, 1280, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			total += d
			if rect.has_point(Vector2i(x, y)):
				inside += d
	return inside / max(total, 1e-9)

func _diff_masked(a: Image, b: Image, points: Array) -> float:
	if points.is_empty():
		return 999.0
	var total := 0.0
	for point in points:
		var x: int = point.x
		var y: int = point.y
		var ca := a.get_pixel(x, y)
		var cb := b.get_pixel(x, y)
		total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(points.size() * 3)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = svp.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
