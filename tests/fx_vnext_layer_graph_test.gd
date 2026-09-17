# LG-01..LG-05 — layer graph authority regression.
# One order model (visual = document order), raw-index moves, SOURCE pinned
# at root index 0, topology validated in the MODEL, drops never mutate planes.
# NOTE: new_layer auto-generates layer_id; display names are the handles here.
extends SceneTree

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")

var checks := 0
var failures := 0

func _init() -> void:
	_lg04_materialize_pins_source()
	_lg04_validate_rejects_unpinned_source()
	_lg03_topology_rejects_bad_input()
	_lg03_topology_rejects_bad_blend()
	_lg03_topology_rejects_double_viewport_consumer()
	_lg03_topology_rejects_transformed_plus_viewport()
	_lg03_topology_accepts_supported_single_chain()
	_lg03_production_rejects_bad_topology()
	_lg02_move_mutates_document_order()
	_lg04_source_refuses_every_move()
	_lg05_drop_reorders_without_plane_change()
	_lg05_drop_onto_source_lands_after_it()
	_lg05_plane_drop_changes_only_plane()
	print("[FX-LAYER-GRAPH] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		failures += 1
		print("[CHECK] FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")

func _names(doc: Dictionary) -> Array:
	var out: Array = []
	for layer in doc.get("layers", []):
		out.append(str((layer as Dictionary).get("name", "?")))
	return out

func _by_name(doc: Dictionary, layer_name: String) -> Dictionary:
	for layer in doc.get("layers", []):
		if str((layer as Dictionary).get("name", "")) == layer_name:
			return layer
	return {}

func _lid(doc: Dictionary, layer_name: String) -> String:
	return str(_by_name(doc, layer_name).get("layer_id", ""))

func _fx(doc: Dictionary, layer_name: String, plane := "TARGET_SOURCE", blend := "NORMAL", input := "ORIGINAL_SOURCE") -> Dictionary:
	var layer := FxLookScript.new_layer("FX", layer_name)
	layer["input"] = input
	layer["blend_mode"] = blend
	layer["plane"] = plane
	doc["layers"].append(layer)
	return doc

func _doc3() -> Dictionary:
	# new_look seeds exactly one SOURCE layer ("Source"); add two FX layers.
	var doc := FxLookScript.new_look("LG", "Layer graph")
	_fx(doc, "a")
	_fx(doc, "b")
	return doc

# ---- LG-04 ----
func _lg04_materialize_pins_source() -> void:
	var doc := FxLookScript.new_look("LG", "Pin")
	_fx(doc, "x")
	var mat: Dictionary = FxLookScript.materialize(doc)
	_check(str(_names(mat)) == str(["Source", "x"]), "LG-04 seeded SOURCE stays at root index 0", str(_names(mat)))
	# Off-order raw doc (SOURCE appended late) normalizes to the pin.
	var raw := FxLookScript.new_look("LG", "Raw")
	_fx(raw, "x")
	raw["layers"].append(FxLookScript.new_layer("SOURCE", "Late"))
	raw["layers"].pop_front()
	var mat2: Dictionary = FxLookScript.materialize(raw)
	_check(str(_names(mat2)) == str(["Late", "x"]), "LG-04 materialize pins late SOURCE at root index 0", str(_names(mat2)))

func _lg04_validate_rejects_unpinned_source() -> void:
	var doc := FxLookScript.new_look("LG", "Unpinned")
	_fx(doc, "x")
	doc["layers"].push_front(doc["layers"].pop_back())
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "LG-04 validate rejects SOURCE off index 0", str(res.get("errors", [])))

func _lg04_source_refuses_every_move() -> void:
	var doc := _doc3()
	var s := _lid(doc, "Source")
	var a := _lid(doc, "a")
	_check(not FxLookScript.move_layer_in(doc, s, 1), "LG-04 SOURCE refuses move down")
	_check(not FxLookScript.move_layer_in(doc, s, -1), "LG-04 SOURCE refuses move up")
	_check(not FxLookScript.reorder_layer_in(doc, s, a), "LG-04 SOURCE refuses drag reorder")
	_check(not FxLookScript.set_layer_plane(doc, s, "COMPOSITION_FOREGROUND"), "LG-04 SOURCE refuses plane change")
	_check(str(_names(doc)) == str(["Source", "a", "b"]), "LG-04 refused moves leave order intact", str(_names(doc)))

# ---- LG-03 ----
func _lg03_topology_rejects_bad_input() -> void:
	var doc := _doc3()
	_by_name(doc, "a")["input"] = "SCREEN_BUFFER"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "LG-03 model rejects unsupported input")

func _lg03_topology_rejects_bad_blend() -> void:
	var doc := _doc3()
	_by_name(doc, "a")["blend_mode"] = "OVERLAY"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "LG-03 model rejects unsupported blend")

func _lg03_topology_rejects_double_viewport_consumer() -> void:
	var doc := _doc3()
	_by_name(doc, "a")["input"] = "LAYER_BELOW"
	_by_name(doc, "b")["input"] = "COMPOSITE_BELOW"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "LG-03 model rejects two offscreen consumers")

func _lg03_topology_rejects_transformed_plus_viewport() -> void:
	var doc := _doc3()
	_by_name(doc, "a")["input"] = "TRANSFORMED_SOURCE"
	_by_name(doc, "b")["input"] = "LAYER_BELOW"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(not bool(res.get("ok", true)), "LG-03 model rejects transformed+viewport mix")

func _lg03_topology_accepts_supported_single_chain() -> void:
	var doc := _doc3()
	_by_name(doc, "b")["input"] = "LAYER_BELOW"
	_by_name(doc, "b")["blend_mode"] = "ADD"
	var res: Dictionary = FxLookScript.validate(doc)
	_check(bool(res.get("ok", false)), "LG-03 model accepts supported single offscreen chain", str(res.get("errors", [])))

func _lg03_production_rejects_bad_topology() -> void:
	var dir := "user://fx_layer_graph"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var prod = FxProductionScript.new()
	prod.data_dir = dir
	_check(prod != null, "LG-03 production spawns")
	var doc := _doc3()
	_by_name(doc, "a")["blend_mode"] = "OVERLAY"
	var res: Dictionary = prod.apply({"look": doc})
	_check(not bool(res.get("ok", true)), "LG-03 production rejects bad topology at apply")

# ---- LG-02 / LG-05 ----
func _lg02_move_mutates_document_order() -> void:
	var doc := _doc3()
	var a := _lid(doc, "a")
	_check(FxLookScript.move_layer_in(doc, a, 1), "LG-02 move down succeeds")
	_check(str(_names(doc)) == str(["Source", "b", "a"]), "LG-02 move lands in document order", str(_names(doc)))
	_check(FxLookScript.move_layer_in(doc, a, -1), "LG-02 move up succeeds")
	_check(str(_names(doc)) == str(["Source", "a", "b"]), "LG-02 move up restores order", str(_names(doc)))
	_check(not FxLookScript.move_layer_in(doc, a, -1), "LG-02 move into SOURCE slot refused")

func _lg05_drop_reorders_without_plane_change() -> void:
	var doc := _doc3()
	_by_name(doc, "a")["plane"] = "TARGET_SOURCE"
	_by_name(doc, "b")["plane"] = "COMPOSITION_FOREGROUND"
	_check(FxLookScript.reorder_layer_in(doc, _lid(doc, "b"), _lid(doc, "a")), "LG-05 drop reorders across planes")
	_check(str(_names(doc)) == str(["Source", "b", "a"]), "LG-05 drop lands at target position", str(_names(doc)))
	_check(str(_by_name(doc, "b").get("plane", "")) == "COMPOSITION_FOREGROUND", "LG-05 drop never adopts target plane")
	_check(str(_by_name(doc, "a").get("plane", "")) == "TARGET_SOURCE", "LG-05 target plane untouched")

func _lg05_drop_onto_source_lands_after_it() -> void:
	var doc := _doc3()
	_check(FxLookScript.reorder_layer_in(doc, _lid(doc, "b"), _lid(doc, "Source")), "LG-05 drop onto SOURCE succeeds")
	_check(str(_names(doc)) == str(["Source", "b", "a"]), "LG-05 drop onto SOURCE lands directly after it", str(_names(doc)))

func _lg05_plane_drop_changes_only_plane() -> void:
	var doc := _doc3()
	_check(FxLookScript.set_layer_plane(doc, _lid(doc, "a"), "COMPOSITION_BACKGROUND"), "LG-05 plane drop succeeds")
	_check(str(_names(doc)) == str(["Source", "a", "b"]), "LG-05 plane drop keeps document order", str(_names(doc)))
	_check(str(_by_name(doc, "a").get("plane", "")) == "COMPOSITION_BACKGROUND", "LG-05 plane actually changes")
