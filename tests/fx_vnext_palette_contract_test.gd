extends SceneTree
# Palette contract — six legacy strategies, independent locks, H/S/V.
# Authoring-time color materialization; the shader only renders fringe_color_*.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var checks: Array = []
var failures := 0

const NAMES := ["DOMINANT + DISTANT", "COMPLEMENT", "SPLIT COMPLEMENT", "ANALOGOUS", "TRIADIC", "MONOCHROME"]

func _init() -> void:
	var dominant := Color(0.9, 0.15, 0.2)
	var distant := Color(0.2, 0.5, 0.95)
	for strategy in 6:
		_check(FxLookScript.palette_strategy_name(float(strategy)) == NAMES[strategy], "strategy %d has canonical name" % strategy)
		var doc: Dictionary = _layer_doc(float(strategy), 0.0, 1.0, 1.0, false, false)
		var res: Dictionary = FxLookScript.generate_palette(doc, "layer-fx-palette", dominant, distant)
		_check(bool(res.get("ok", false)), "strategy %d generates" % strategy, str(res.get("errors", [])))
		var fx: Dictionary = (res["doc"] as Dictionary)["layers"][1]["fx"]
		_check((fx["fringe_color_a"] is Array) and (fx["fringe_color_b"] is Array), "strategy %d stays canonical arrays" % strategy)
		_check(bool(FxLookScript.validate(fx_wrapped(res["doc"]))["ok"]), "strategy %d output validates" % strategy)
	# strategy 0 keeps both inputs; complement derives b from dominant
	var d0: Dictionary = FxLookScript.generate_palette(_layer_doc(0.0, 0.0, 1.0, 1.0, false, false), "layer-fx-palette", dominant, distant)
	var f0: Dictionary = (d0["doc"] as Dictionary)["layers"][1]["fx"]
	_check(_close(f0["fringe_color_a"], [dominant.r, dominant.g, dominant.b]), "strategy 0 keeps dominant as A", str(f0["fringe_color_a"]))
	_check(_close(f0["fringe_color_b"], [distant.r, distant.g, distant.b]), "strategy 0 keeps distant as B", str(f0["fringe_color_b"]))
	# independent locks
	var lock_a: Dictionary = FxLookScript.generate_palette(_layer_doc(1.0, 0.0, 1.0, 1.0, true, false), "layer-fx-palette", dominant, distant)
	var fa: Dictionary = (lock_a["doc"] as Dictionary)["layers"][1]["fx"]
	_check(_close(fa["fringe_color_a"], [0.25, 0.95, 1.0]), "lock A preserves authored color", str(fa["fringe_color_a"]))
	_check(not _close(fa["fringe_color_b"], [1.0, 0.4, 0.85]), "lock A still generates B", str(fa["fringe_color_b"]))
	var lock_b: Dictionary = FxLookScript.generate_palette(_layer_doc(1.0, 0.0, 1.0, 1.0, false, true), "layer-fx-palette", dominant, distant)
	var fb: Dictionary = (lock_b["doc"] as Dictionary)["layers"][1]["fx"]
	_check(not _close(fb["fringe_color_a"], [0.25, 0.95, 1.0]), "lock B still generates A", str(fb["fringe_color_a"]))
	_check(_close(fb["fringe_color_b"], [1.0, 0.4, 0.85]), "lock B preserves authored color", str(fb["fringe_color_b"]))
	# H/S/V effect
	var h0: Dictionary = FxLookScript.generate_palette(_layer_doc(1.0, 0.0, 1.0, 1.0, false, false), "layer-fx-palette", dominant, distant)
	var h1: Dictionary = FxLookScript.generate_palette(_layer_doc(1.0, 90.0, 0.5, 1.3, false, false), "layer-fx-palette", dominant, distant)
	var c0: Array = (h0["doc"] as Dictionary)["layers"][1]["fx"]["fringe_color_b"]
	var c1: Array = (h1["doc"] as Dictionary)["layers"][1]["fx"]["fringe_color_b"]
	_check(not _close(c0, c1), "H/S/V changes generated color", "%s vs %s" % [str(c0), str(c1)])
	# determinism + JSON round-trip
	var r1: Dictionary = FxLookScript.generate_palette(_layer_doc(4.0, 10.0, 1.1, 0.9, false, false), "layer-fx-palette", dominant, distant)
	var r2: Dictionary = FxLookScript.generate_palette(_layer_doc(4.0, 10.0, 1.1, 0.9, false, false), "layer-fx-palette", dominant, distant)
	_check(str((r1["doc"] as Dictionary)["layers"][1]["fx"]["fringe_color_a"]) == str((r2["doc"] as Dictionary)["layers"][1]["fx"]["fringe_color_a"]), "palette generation is deterministic")
	var text: String = FxLookScript.to_json(r1["doc"])
	var back: Dictionary = FxLookScript.from_json(text)
	_check(bool(FxLookScript.validate(FxLookScript.materialize(back))["ok"]), "palette doc survives JSON round-trip")
	print("[FX-PALETTE] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)

func _layer_doc(strategy: float, hue: float, sat: float, val: float, lock_a: bool, lock_b: bool) -> Dictionary:
	var doc: Dictionary = FxLookScript.materialize(FxLookScript.new_look("PALETTE_CT", "Palette"))
	var layer: Dictionary = FxLookScript.new_layer("FX", "Palette")
	layer["layer_id"] = "layer-fx-palette"
	layer["input"] = "ORIGINAL_SOURCE"
	(layer["fx"] as Dictionary)["palette_strategy"] = strategy
	(layer["fx"] as Dictionary)["palette_hue_offset"] = hue
	(layer["fx"] as Dictionary)["palette_saturation"] = sat
	(layer["fx"] as Dictionary)["palette_value"] = val
	(layer["fx"] as Dictionary)["palette_lock_a"] = lock_a
	(layer["fx"] as Dictionary)["palette_lock_b"] = lock_b
	doc["layers"].append(layer)
	return doc

func fx_wrapped(doc: Dictionary) -> Dictionary:
	return doc

func _close(actual: Array, expected: Array) -> bool:
	if actual.size() < 3 or expected.size() < 3:
		return false
	for i in 3:
		if absf(float(actual[i]) - float(expected[i])) > 0.02:
			return false
	return true

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)
