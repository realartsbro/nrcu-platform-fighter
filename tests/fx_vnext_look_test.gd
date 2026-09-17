extends SceneTree
# Look v0.4 model unit tests — normalized form, neutral defaults, validation.

var checks: Array = []
var failures: int = 0

func _init() -> void:
	var FxLookScript = load("res://scripts/fx_vnext/fx_look.gd")

	# ---- new look + mandatory SOURCE ---------------------------------------
	var look: Dictionary = FxLookScript.new_look("TEST_LOOK", "Test Look")
	var res: Dictionary = FxLookScript.validate(look)
	_check(bool(res["ok"]), "new look validates", str(res["errors"]))
	var source: Dictionary = FxLookScript.source_layer(look)
	_check(str(source.get("layer_id", "")).length() >= 8, "SOURCE layer has stable id")
	_check(str(source.get("plane", "")) == "TARGET_SOURCE", "SOURCE uses TARGET_SOURCE plane")

	# ---- neutral defaults (specs/15 §1 spot checks) -------------------------
	var disp: Dictionary = source["displacement"]
	_check(disp["enabled"] == false and disp["driver"] == "NOISE" and float(disp["scale"]) == 1.0, "neutral displacement basics")
	_check(int(disp["seed"]) == 1 and disp["edge_mode"] == "TRANSPARENT" and disp["time_source"] == "PRESENTATION_TIME", "neutral displacement determinism fields")
	var mask: Dictionary = source["mask"]
	_check(mask["enabled"] == false and mask["source"] == "NONE" and mask["region"] == "FULL" and mask["space"] == "LAYER_SPACE", "neutral mask basics")
	_check(float(mask["expand_contract_px"]) == 0.0 and float(mask["width_px"]) == 0.0 and float(mask["feather_px"]) == 0.0, "neutral mask sizes")
	var transform: Dictionary = source["transform"]
	_check(transform["position_px"] == [0.0, 0.0] and transform["pivot"] == [0.5, 0.5] and transform["flip_x"] == false, "neutral transform")

	# ---- materialize --------------------------------------------------------
	var sparse := {
		"schema": FxLookScript.SCHEMA, "look_id": "SPARSE", "name": "Sparse",
		"revision": 1, "status": "DRAFT", "metadata": {},
		"layers": [{"layer_id": "layer-source-sparse", "name": "S", "type": "SOURCE"}],
	}
	var norm: Dictionary = FxLookScript.materialize(sparse)
	_check(bool(FxLookScript.validate(norm)["ok"]), "materialized sparse look validates")
	_check(FxLookScript.is_serialized_normalized(norm), "materialized form is canonical")
	_check(FxLookScript.materialize(norm) == norm, "materialize is idempotent")

	# ---- planning example ---------------------------------------------------
	var example: Dictionary = _load_fixture("vs_mark_layered_look.json")
	_check(not example.is_empty(), "planning example loads")
	var ex_res: Dictionary = FxLookScript.validate(example)
	_check(bool(ex_res["ok"]), "planning example validates", str(ex_res["errors"]))
	_check((example.get("layers", []) as Array).size() == 3, "planning example has 3 layers")
	_check(FxLookScript.is_serialized_normalized(example), "planning example is fully materialized")

	# ---- validation failures -------------------------------------------------
	var base: Dictionary = FxLookScript.materialize(FxLookScript.new_look("VALIDATION_BASE", "Validation"))
	var fx_layer: Dictionary = FxLookScript.new_layer("FX", "Halo")
	base["layers"].append(fx_layer)

	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"] = [d["layers"][1]]), "exactly one SOURCE"), "missing SOURCE rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"].append(d["layers"][0].duplicate(true))), "duplicate"), "duplicate layer id rejected")
	_check(_validation_error_contains(FxLookScript, _with_second_source(base), "exactly one SOURCE"), "two SOURCE layers rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][0]["plane"] = "TARGET_OVERLAY"), "TARGET_SOURCE"), "SOURCE plane enforced")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][0]["opacity"] = 1.5), "opacity"), "opacity range enforced")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][0]["mask"]["width_px"] = -3.0), "width_px"), "negative mask width rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][0]["transform"]["scale"] = [INF, 1.0]), "non-finite"), "non-finite transform rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][1]["mask"]["custom_mask"] = "C:\\\\x.png"), "absolute"), "absolute path rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][1]["displacement"]["custom_texture"] = "user://x.png"), "does not exist"), "missing app-local path rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][1]["displacement"]["custom_texture"] = "https://example.com/x.png"), "project-local"), "remote URL rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][0]["mask"]["space"] = "FOLLOW_LAYER"), "FOLLOW_LAYER"), "FOLLOW_LAYER not persisted")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["schema"] = "NRCU_FX_LOOK_V0_3"), "schema"), "wrong schema rejected")
	_check(_validation_error_contains(FxLookScript, _mutate(base, func(d): d["layers"][1].erase("input")), "input"), "FX layer requires input")

	# ---- duplicate / reset ---------------------------------------------------
	var doc: Dictionary = FxLookScript.materialize(FxLookScript.new_look("DUP_BASE", "Dup"))
	var halo: Dictionary = FxLookScript.new_layer("FX", "Halo")
	doc["layers"].append(halo)
	var copy: Dictionary = FxLookScript.duplicate_layer_in(doc, str(halo["layer_id"]))
	_check(not copy.is_empty() and str(copy["layer_id"]) != str(halo["layer_id"]), "duplicate gets a new stable id")
	_check((doc.get("layers", []) as Array).size() == 3, "duplicate inserted after original")
	_check(bool(FxLookScript.validate(doc)["ok"]), "look with duplicate still validates")
	copy["opacity"] = 0.2
	copy["mask"]["enabled"] = true
	_check(FxLookScript.reset_layer_in(doc, str(copy["layer_id"])), "reset layer works")
	_check(float(copy["opacity"]) == 1.0 and copy["mask"]["enabled"] == false, "reset restores neutral values")

	# ---- serialization -------------------------------------------------------
	var text: String = FxLookScript.to_json(doc)
	var parsed: Dictionary = FxLookScript.from_json(text)
	_check(FxLookScript.materialize(parsed) == doc, "json roundtrip stable in canonical form")
	_check(int(FxLookScript.bump_revision(doc)) == 2, "revision bump")

	print("[FX-LOOK] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func _with_second_source(doc: Dictionary) -> Dictionary:
	var copy: Dictionary = doc.duplicate(true)
	var extra: Dictionary = (copy["layers"][0] as Dictionary).duplicate(true)
	extra["layer_id"] = "layer-source-second"
	(copy["layers"] as Array).insert(1, extra)
	return copy

func _mutate(doc: Dictionary, mutator: Callable) -> Dictionary:
	var copy: Dictionary = doc.duplicate(true)
	mutator.call(copy)
	return copy

func _validation_error_contains(FxLookScript, doc: Dictionary, needle: String) -> bool:
	var res: Dictionary = FxLookScript.validate(doc)
	if bool(res["ok"]):
		return false
	for error in res["errors"]:
		if needle in str(error):
			return true
	return false

func _load_fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/vnext/" + name, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok:
		failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
