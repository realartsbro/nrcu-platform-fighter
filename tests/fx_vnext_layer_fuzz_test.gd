extends SceneTree
# NRCU FX Lab vNEXT — §11 layer property/fuzz (headless, seeded).
#
# A seeded generator builds random Looks with 1..20 layers (canonical SOURCE +
# SOURCE_COPY / FX types, every plane, every supported blend mode, masks,
# displacement, motion, and extreme numeric values inside the schema-legal
# ranges) and re-verifies the layer/document invariants for every Look:
#
#   L1  exactly one canonical SOURCE layer (pinned to TARGET_SOURCE, layer 0)
#   L2  generated Looks are schema-legal and canonical (validate + materialize
#       idempotent + is_serialized_normalized)
#   L3  layer_id is stable across rename / plane move / reorder / materialize
#   L4  duplicate_layer_in gives a NEW id, inserts next to the original and keeps
#       every other id (a duplicated SOURCE is rejected instead of silently
#       producing a second canonical SOURCE)
#   L5  save->load is idempotent (semantic document equality through the real
#       FxProduction file round trip)
#   L6  Copy/Paste does not alias mutable state (deep mutation of the copy never
#       reaches the source; neutral defaults are freshly allocated per layer)
#   L7  sibling masks/transforms/displacement/fx/motion never leak
#   L8  hiding one layer never changes sibling state (and unhiding restores it)
#   L9  extreme numeric values: schema-legal extremes are accepted, violations
#       one step outside the range are rejected
#   L10 save->load->save normalizes to the same semantic document (canonical
#       serialization is byte-stable across a second round trip)
#   L11 malformed layer input stays rejected (duplicate ids, second SOURCE,
#       plane/input rules, FOLLOW_LAYER mask space, non-finite numbers, absolute
#       or remote asset paths, unknown layer type, empty layer list)
#
# Determinism: FXLAB_FUZZ_SEED (default 20260915) seeds the generator RNG and the
# global RNG (deterministic layer ids). Scale: FXLAB_FUZZ_LOOKS (default 80).
# Evidence: FXLAB_EVIDENCE_DIR (default res://evidence/vnext_build/)
# -> layer_fuzz_samples.json, layer_fuzz_checks.log, summary_layer_fuzz_check.json.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")

const SEED_DEFAULT := 20260915
const LOOKS_DEFAULT := 80

const POSITION_EXTREMES := [-4096.0, -512.0, -1.0, 0.0, 1.0, 512.0, 4096.0]
const SCALE_EXTREMES := [0.001, 0.01, 0.5, 1.0, 4.0, 64.0, 1000000.0]
const ROTATION_EXTREMES := [-1440.0, -360.0, -0.5, 0.0, 0.5, 360.0, 1440.0]
const PIVOT_EXTREMES := [0.0, 0.25, 0.5, 0.75, 1.0]
const OPACITY_EXTREMES := [0.0, 0.000001, 0.25, 0.5, 0.999999, 1.0]
const SIZE_EXTREMES := [0.0, 0.001, 1.0, 12.0, 512.0, 65536.0]
const CONTRACT_EXTREMES := [-256.0, -1.0, 0.0, 1.0, 256.0]
const SEED_EXTREMES := [0, 1, 2, 65535, 2147483647]
const TIME_EXTREMES := [0.0, 0.0001, 0.25, 1.0, 60.0, 3600.0]
const FX_NUMERIC_KEYS := [
	"size", "intensity", "pattern_scale", "fringe", "rgb", "flow", "dither",
	"base_opacity", "grade_black_point", "grade_white_point", "grade_gamma",
	"grade_contrast", "grade_brightness", "grade_saturation", "mono_threshold",
	"mono_bayer_level", "mono_pixel", "dither_threshold", "dither_gamma",
	"dither_levels", "edge_threshold", "edge_width", "wind_reach", "wind_trail",
	"wind_cutoff", "split_separation", "signal_gain", "color_blur",
	"signal_softness", "fringe_coverage_threshold", "fringe_bleed",
	"FIELD_STRENGTH", "FIELD_SPEED", "OUTWARDNESS", "FIELD_BREAKUP",
	"COORD_NUDGE", "FIELD_SIZE", "LEGACY_SCALE", "LEGACY_SPEED", "LEGACY_RADIAL",
	"DRIVER_CENTER_X", "DRIVER_SCALE", "DRIVER_DETAIL", "flow_strength",
	"rgb_shift_amount", "rgb_shift_angle", "temporal_hold", "palette_hue_offset",
	"palette_saturation", "palette_value",
]

var checks: Array = []
var failures: int = 0
var families: Dictionary = {}
var samples: Array = []
var notes: Array = []
var out_dir: String
var rng := RandomNumberGenerator.new()
var prod
var looks_target: int = LOOKS_DEFAULT
var looks_generated: int = 0
var round_tripped: int = 0

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seed_text := OS.get_environment("FXLAB_FUZZ_SEED")
	var useed := SEED_DEFAULT if seed_text == "" else int(seed_text)
	var looks_text := OS.get_environment("FXLAB_FUZZ_LOOKS")
	looks_target = looks_target if looks_text == "" else maxi(int(looks_text), 1)
	rng.seed = useed
	seed(useed)

	var prod_dir := "user://vnext_layer_fuzz_prod"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir

	print("[FX-LAYER-FUZZ] seed=%d looks=%d" % [useed, looks_target])
	for index in range(looks_target):
		_fuzz_look(index)
	_malformed_section()
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_evidence(useed)

# ================================================================ one Look

func _fuzz_look(index: int) -> void:
	var doc: Dictionary = FxLookScript.new_look("FUZZ_LOOK_%03d" % index, "Fuzz Look %d" % index, "DRAFT")
	if index % 2 == 0:
		_shape_source_layer(doc)
	var extra := rng.randi_range(1, 20)
	for i in range(extra):
		var type := "SOURCE_COPY" if rng.randf() < 0.35 else "FX"
		doc["layers"].append(_gen_layer(type, i))
	doc = FxLookScript.materialize(doc)

	# ---- L1 canonical SOURCE -------------------------------------------------
	var source: Dictionary = FxLookScript.source_layer(doc)
	var source_count := _count_type(doc, "SOURCE")
	_prop("L1 exactly one canonical SOURCE layer", source_count == 1, "count=%d" % source_count)
	_prop("L1 exactly one canonical SOURCE layer", not source.is_empty() and str(source.get("plane", "")) == "TARGET_SOURCE", str(source.get("plane", "")))
	_prop("L1 exactly one canonical SOURCE layer", str((doc["layers"] as Array)[0].get("type", "")) == "SOURCE", "layer0=%s" % str((doc["layers"] as Array)[0].get("type", "")))
	_prop("L1 exactly one canonical SOURCE layer", not source.has("input"), "SOURCE must not carry input")
	_prop("L1 exactly one canonical SOURCE layer", (doc["layers"] as Array).size() == extra + 1, "%d layers for %d generated" % [(doc["layers"] as Array).size(), extra])

	# ---- L2 schema-legal + canonical ----------------------------------------
	var valid: Dictionary = FxLookScript.validate(doc)
	_prop("L2 generated Looks are schema-legal", bool(valid["ok"]), str(valid["errors"]))
	if not bool(valid["ok"]):
		return
	looks_generated += 1
	_prop("L2 generated Looks are canonical", FxLookScript.materialize(doc) == doc, "materialize(doc) == doc")
	_prop("L2 generated Looks are canonical", FxLookScript.is_serialized_normalized(doc), "is_serialized_normalized(doc)")

	# ---- L3 id stability ----------------------------------------------------
	_id_stability(doc)

	# ---- L4 duplicate -------------------------------------------------------
	_duplicate_layer(doc)

	# ---- L6/L7 sibling isolation + copy/paste aliasing ---------------------
	_alias_isolation(doc, index)

	# ---- L8 hiding ----------------------------------------------------------
	_hide_layer(doc)

	# ---- L5/L10 file round trip --------------------------------------------
	_round_trip(doc, index)

func _id_stability(doc: Dictionary) -> void:
	var ids: Array = _layer_ids(doc)
	var target_index := _pick_non_source_index(doc)
	if target_index < 0:
		return
	var target_id := str((doc["layers"] as Array)[target_index]["layer_id"])
	var before_json := _layer_json(doc, target_id)

	# rename
	(doc["layers"] as Array)[target_index]["name"] = "Renamed %d" % target_index
	_prop("L3 layer_id is stable across rename", str((doc["layers"] as Array)[target_index]["layer_id"]) == target_id, "id changed on rename")
	_prop("L3 layer_id is stable across rename", _layer_ids(doc) == ids, "id set changed on rename")

	# plane move
	var plane_choices: Array = FxLookScript.PLANES.duplicate()
	plane_choices.erase("TARGET_SOURCE")
	(doc["layers"] as Array)[target_index]["plane"] = str(_pick(plane_choices))
	_prop("L3 layer_id is stable across a plane move", _layer_ids(doc) == ids, "id set changed on plane move")
	_prop("L3 layer_id is stable across a plane move", not FxLookScript.find_layer(doc, target_id).is_empty(), "layer unreachable after plane move")

	# reorder (remove + insert elsewhere, exactly what the shell's move does)
	var layer: Dictionary = (doc["layers"] as Array)[target_index]
	(doc["layers"] as Array).remove_at(target_index)
	var destination := rng.randi_range(1, (doc["layers"] as Array).size())
	(doc["layers"] as Array).insert(destination, layer)
	_prop("L3 layer_id is stable across reorder", _layer_ids(doc).size() == ids.size() and _same_set(_layer_ids(doc), ids), "id set changed on reorder")
	_prop("L3 layer_id is stable across reorder", not FxLookScript.find_layer(doc, target_id).is_empty(), "layer unreachable after reorder")
	_prop("L3 layer_id is stable across reorder", str(FxLookScript.find_layer(doc, target_id)["name"]) == "Renamed %d" % target_index, "reorder swapped layer contents")
	_prop("L3 layer_id is stable across reorder", str((doc["layers"] as Array)[0].get("type", "")) == "SOURCE", "SOURCE left index 0")

	# materialize keeps every id
	var rematerialized: Dictionary = FxLookScript.materialize(doc)
	_prop("L3 layer_id is stable across materialize", _same_set(_layer_ids(rematerialized), ids), "materialize changed the id set")
	_prop("L3 layer_id is stable across materialize", str(FxLookScript.find_layer(rematerialized, target_id)["name"]) == "Renamed %d" % target_index, "materialize dropped the rename")
	_prop("L3 layer_id is stable across materialize", bool(FxLookScript.validate(rematerialized)["ok"]), str(FxLookScript.validate(rematerialized)["errors"]))
	_prop("L3 layer_id is stable across materialize", _layer_json(rematerialized, target_id) != before_json, "the edited layer did not change at all")

func _duplicate_layer(doc: Dictionary) -> void:
	var ids: Array = _layer_ids(doc)
	var index := _pick_non_source_index(doc)
	if index < 0:
		return
	var original_id := str((doc["layers"] as Array)[index]["layer_id"])
	var copy: Dictionary = FxLookScript.duplicate_layer_in(doc, original_id)
	_prop("L4 duplicate gives a NEW id", not copy.is_empty() and str(copy.get("layer_id", "")) != original_id, str(copy.get("layer_id", "")))
	_prop("L4 duplicate gives a NEW id", str(copy.get("layer_id", "")).length() >= 8, str(copy.get("layer_id", "")))
	_prop("L4 duplicate keeps every other id", _layer_ids(doc).size() == ids.size() + 1 and _contains_all(_layer_ids(doc), ids), str(_layer_ids(doc)))
	_prop("L4 duplicate keeps every other id", str((doc["layers"] as Array)[index + 1].get("layer_id", "")) == str(copy.get("layer_id", "")), "copy not inserted next to the original")
	_prop("L4 duplicate keeps every other id", bool(FxLookScript.validate(FxLookScript.materialize(doc))["ok"]), str(FxLookScript.validate(FxLookScript.materialize(doc))["errors"]))
	_prop("L4 duplicate keeps every other id", FxLookScript.duplicate_layer_in(doc, "layer-missing-0000").is_empty(), "duplicate of a missing layer must return {}")
	_prop("L4 duplicate keeps every other id", not FxLookScript.reset_layer_in(doc, "layer-missing-0000"), "reset of a missing layer must return false")

	# duplicating the canonical SOURCE must not silently create a second SOURCE
	var source_copy_look: Dictionary = FxLookScript.new_look("FUZZ_SOURCE_DUP", "Source Dup", "DRAFT")
	var source_id := str((source_copy_look["layers"] as Array)[0]["layer_id"])
	var duplicated_source: Dictionary = FxLookScript.duplicate_layer_in(source_copy_look, source_id)
	var source_dup_check: Dictionary = FxLookScript.validate(FxLookScript.materialize(source_copy_look))
	_prop("L4 duplicate gives a NEW id", not duplicated_source.is_empty() and str(duplicated_source.get("layer_id", "")) != source_id, "duplicated SOURCE kept the id")
	_prop("L4 duplicate gives a NEW id", not bool(source_dup_check["ok"]) and str(source_dup_check["errors"]).contains("exactly one SOURCE"), "second SOURCE must be rejected: " + str(source_dup_check["errors"]))

func _alias_isolation(doc: Dictionary, look_index: int) -> void:
	var layers: Array = doc["layers"]
	if layers.size() < 2:
		return
	# ---- L7 sibling masks/transforms never leak -----------------------------
	var subject := rng.randi_range(0, layers.size() - 1)
	var siblings_before := {}
	for i in range(layers.size()):
		if i != subject:
			siblings_before[i] = _layer_json(doc, str((layers[i] as Dictionary)["layer_id"]))
	var subject_layer: Dictionary = layers[subject]
	subject_layer["mask"]["enabled"] = true
	subject_layer["mask"]["width_px"] = 7.5
	subject_layer["mask"]["feather_px"] = 3.25
	subject_layer["mask"]["region"] = "OUTER_BAND"
	subject_layer["transform"]["position_px"] = [42.0, -17.0]
	subject_layer["transform"]["scale"] = [2.5, 0.75]
	subject_layer["transform"]["rotation_deg"] = 33.0
	subject_layer["displacement"]["enabled"] = true
	subject_layer["displacement"]["amount_px"] = [12.0, -4.0]
	subject_layer["displacement"]["seed"] = 4242
	subject_layer["fx"]["rgb"] = 0.9
	subject_layer["fx"]["intensity"] = 3.5
	subject_layer["motion"]["enabled"]["rgb"] = true
	subject_layer["motion"]["tracks"]["rgb"]["attack"] = 0.75
	subject_layer["opacity"] = 0.375
	for i in siblings_before.keys():
		_prop("L7 sibling masks/transforms never leak", _layer_json(doc, str((layers[int(i)] as Dictionary)["layer_id"])) == str(siblings_before[i]), "sibling %d changed while layer %d was edited" % [int(i), subject])

	# the reverse direction: editing a sibling never changes the subject
	if siblings_before.size() > 0:
		var first_sibling := int(siblings_before.keys()[0])
		var subject_json := _layer_json(doc, str(subject_layer["layer_id"]))
		(layers[first_sibling] as Dictionary)["mask"]["feather_px"] = 99.0
		(layers[first_sibling] as Dictionary)["transform"]["pivot"] = [0.1, 0.9]
		_prop("L7 sibling masks/transforms never leak", _layer_json(doc, str(subject_layer["layer_id"])) == subject_json, "subject changed while a sibling was edited")
		(layers[first_sibling] as Dictionary)["mask"]["feather_px"] = 0.0
		(layers[first_sibling] as Dictionary)["transform"]["pivot"] = [0.5, 0.5]
	_prop("L7 sibling masks/transforms never leak", bool(FxLookScript.validate(FxLookScript.materialize(doc))["ok"]), str(FxLookScript.validate(FxLookScript.materialize(doc))["errors"]))

	# ---- L6 Copy/Paste must not alias ---------------------------------------
	var clipboard: Dictionary = (subject_layer as Dictionary).duplicate(true)
	(clipboard as Dictionary)["layer_id"] = FxLookScript.next_layer_id(str(clipboard.get("type", "fx")).to_lower())
	(clipboard as Dictionary)["name"] = str(clipboard.get("name", "Layer")) + " (pasted)"
	var uploaded: Dictionary = clipboard.duplicate(true)
	var pasted_id := str(uploaded["layer_id"])
	layers.append(uploaded)
	var subject_before := _layer_json(doc, str(subject_layer["layer_id"]))
	var clipboard_before := JSON.stringify(clipboard)
	# mutate the pasted copy as deeply as the schema allows
	var pasted: Dictionary = FxLookScript.find_layer(doc, pasted_id)
	pasted["opacity"] = 0.123
	pasted["mask"]["width_px"] = 55.5
	pasted["transform"]["scale"] = [7.0, 7.0]
	pasted["transform"]["flip_x"] = not bool(pasted["transform"]["flip_x"])
	pasted["displacement"]["enabled"] = not bool(pasted["displacement"]["enabled"])
	pasted["displacement"]["amount_px"] = [88.0, 99.0]
	pasted["fx"]["intensity"] = 12.5
	pasted["fx"]["fringe"] = 1.0
	pasted["motion"]["enabled"]["fringe"] = true
	pasted["motion"]["tracks"]["fringe"]["release"] = 1.5
	_prop("L6 copy/paste does not alias mutable state", _layer_json(doc, str(subject_layer["layer_id"])) == subject_before, "mutating the pasted layer reached the source")
	_prop("L6 copy/paste does not alias mutable state", JSON.stringify(clipboard) == clipboard_before, "mutating the pasted layer reached the clipboard")
	# and the reverse: mutating the source must not reach the paste
	var paste_before := _layer_json(doc, pasted_id)
	(clipboard as Dictionary)["mask"]["width_px"] = 123.0
	(clipboard as Dictionary)["fx"]["intensity"] = 9.0
	_prop("L6 copy/paste does not alias mutable state", _layer_json(doc, pasted_id) == paste_before, "mutating the clipboard reached the pasted layer")
	(clipboard as Dictionary)["mask"]["width_px"] = 7.5
	(clipboard as Dictionary)["fx"]["intensity"] = 3.5
	(layers as Array).remove_at((layers as Array).size() - 1)

	# ---- L6 neutral defaults are freshly allocated --------------------------
	var fa: Dictionary = FxLookScript.neutral_fx()
	var fb: Dictionary = FxLookScript.neutral_fx()
	fa["rgb"] = 0.75
	fa["fringe_color_a"] = [1.0, 0.0, 0.0, 1.0]
	_prop("L6 copy/paste does not alias mutable state", float(fb["rgb"]) == 0.0 and (fb["fringe_color_a"] as Array)[0] == 0.25, "neutral_fx() shares state between calls")
	var ma: Dictionary = FxLookScript.neutral_mask()
	var mb: Dictionary = FxLookScript.neutral_mask()
	ma["width_px"] = 11.0
	_prop("L6 copy/paste does not alias mutable state", float(mb["width_px"]) == 0.0, "neutral_mask() shares state between calls")
	var ta: Dictionary = FxLookScript.neutral_transform()
	var tb: Dictionary = FxLookScript.neutral_transform()
	(ta["scale"] as Array)[0] = 3.0
	_prop("L6 copy/paste does not alias mutable state", float((tb["scale"] as Array)[0]) == 1.0, "neutral_transform() shares state between calls")
	var da: Dictionary = FxLookScript.neutral_displacement()
	var db: Dictionary = FxLookScript.neutral_displacement()
	(da["amount_px"] as Array)[0] = 5.0
	_prop("L6 copy/paste does not alias mutable state", float((db["amount_px"] as Array)[0]) == 0.0, "neutral_displacement() shares state between calls")
	var na: Dictionary = FxLookScript.new_layer("FX", "A")
	var nb: Dictionary = FxLookScript.new_layer("FX", "B")
	na["mask"]["width_px"] = 21.0
	na["transform"]["position_px"] = [9.0, 9.0]
	na["fx"]["flow"] = 0.5
	_prop("L6 copy/paste does not alias mutable state", float(nb["mask"]["width_px"]) == 0.0 and float((nb["transform"]["position_px"] as Array)[0]) == 0.0 and float(nb["fx"]["flow"]) == 0.0, "new_layer() shares nested state between layers")
	var look_a: Dictionary = FxLookScript.new_look("FUZZ_ALIAS_A", "Alias A", "DRAFT")
	var look_b: Dictionary = FxLookScript.new_look("FUZZ_ALIAS_B", "Alias B", "DRAFT")
	look_a["layers"][0]["opacity"] = 0.2
	_prop("L6 copy/paste does not alias mutable state", float(look_b["layers"][0]["opacity"]) == 1.0, "new_look() shares layers between Looks")
	_prop("L6 copy/paste does not alias mutable state", _layer_json(doc, str(subject_layer["layer_id"])) == subject_before, "look_index %d: subject changed at the end of the aliasing block" % look_index)

func _hide_layer(doc: Dictionary) -> void:
	var layers: Array = doc["layers"]
	if layers.is_empty():
		return
	var subject := rng.randi_range(0, layers.size() - 1)
	var subject_id := str((layers[subject] as Dictionary)["layer_id"])
	var before := _layer_json(doc, subject_id)
	var siblings := {}
	for i in range(layers.size()):
		if i != subject:
			siblings[i] = _layer_json(doc, str((layers[i] as Dictionary)["layer_id"]))
	var ids: Array = _layer_ids(doc)
	var original_enabled := bool((layers[subject] as Dictionary).get("enabled", true))
	(layers[subject] as Dictionary)["enabled"] = not original_enabled
	_prop("L8 hiding one layer never changes sibling state", _layer_ids(doc) == ids, "id set changed when hiding a layer")
	for i in siblings.keys():
		_prop("L8 hiding one layer never changes sibling state", _layer_json(doc, str((layers[int(i)] as Dictionary)["layer_id"])) == str(siblings[i]), "sibling %d changed while layer %d was hidden" % [int(i), subject])
	_prop("L8 hiding one layer never changes sibling state", bool(FxLookScript.validate(FxLookScript.materialize(doc))["ok"]), str(FxLookScript.validate(FxLookScript.materialize(doc))["errors"]))
	var hidden_json := _layer_json(doc, subject_id)
	(layers[subject] as Dictionary)["enabled"] = original_enabled
	_prop("L8 hiding one layer never changes sibling state", _layer_json(doc, subject_id) == before, "restoring the visibility did not restore the layer (%s -> %s)" % [hidden_json.substr(0, 40), before.substr(0, 40)])
	for i in siblings.keys():
		_prop("L8 hiding one layer never changes sibling state", _layer_json(doc, str((layers[int(i)] as Dictionary)["layer_id"])) == str(siblings[i]), "sibling %d changed during the unhide" % int(i))

func _round_trip(doc: Dictionary, index: int) -> void:
	# ---- L5 save -> load is idempotent --------------------------------------
	var input: Dictionary = FxLookScript.materialize(doc)
	input["status"] = "PRODUCTION"
	input["revision"] = 1
	var applied: Dictionary = prod.apply({"look": input})
	_prop("L5 save->load is idempotent", bool(applied.get("ok", false)), str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	var first: Dictionary = prod.load_look(str(input["look_id"]))
	_prop("L5 save->load is idempotent", bool(first.get("ok", false)), str(first.get("errors", [])))
	if not bool(first.get("ok", false)):
		return
	round_tripped += 1
	var loaded_one: Dictionary = first["doc"]
	var materialized_input: Dictionary = FxLookScript.materialize(input)
	_prop("L5 save->load is idempotent", _document_equivalent(materialized_input, FxLookScript.materialize(loaded_one)), "loaded document differs from the saved document: " + _first_diff(materialized_input, FxLookScript.materialize(loaded_one)))
	_prop("L5 save->load is idempotent", FxLookScript.is_serialized_normalized(FxLookScript.materialize(loaded_one)), "reloaded document is not canonical")
	_prop("L5 save->load is idempotent", _layer_ids(loaded_one) == _layer_ids(FxLookScript.materialize(input)), "layer ids changed through the file round trip")
	_prop("L5 save->load is idempotent", bool(FxLookScript.validate(loaded_one)["ok"]), str(FxLookScript.validate(loaded_one)["errors"]))

	# ---- L10 save -> load -> save normalizes to the same document -----------
	var second_input: Dictionary = FxLookScript.materialize(loaded_one)
	second_input["revision"] = int(second_input.get("revision", 1)) + 1
	var applied_two: Dictionary = prod.apply({"look": second_input})
	_prop("L10 save->load->save normalizes", bool(applied_two.get("ok", false)), str(applied_two.get("errors", [])))
	if not bool(applied_two.get("ok", false)):
		return
	var second: Dictionary = prod.load_look(str(second_input["look_id"]))
	_prop("L10 save->load->save normalizes", bool(second.get("ok", false)), str(second.get("errors", [])))
	if not bool(second.get("ok", false)):
		return
	var loaded_two: Dictionary = second["doc"]
	_prop("L10 save->load->save normalizes", int(loaded_two.get("revision", 0)) == int(second_input["revision"]), "second save lost the revision")
	var a: Dictionary = FxLookScript.materialize(loaded_one)
	var b: Dictionary = FxLookScript.materialize(loaded_two)
	b["revision"] = a["revision"]
	_prop("L10 save->load->save normalizes", FxLookScript.to_json(a) == FxLookScript.to_json(b), "second round trip changed the document")
	_prop("L10 save->load->save normalizes", JSON.stringify(a["layers"]) == JSON.stringify(b["layers"]), "layer bodies are not stable across a second save")
	_prop("L10 save->load->save normalizes", _document_equivalent(a, b), "second round trip changed the semantic document: " + _first_diff(a, b))
	if samples.size() < 5:
		samples.append({
			"look_index": index, "look_id": str(input["look_id"]),
			"layers": (input["layers"] as Array).size(),
			"types": _types(input), "planes": _planes(input), "blends": _blends(input),
			"extreme_values": _extremes(input),
			"round_trip_layers": (loaded_two["layers"] as Array).size(),
			"canonical_json_sha256": FxLookScript.to_json(FxLookScript.materialize(loaded_two)).sha256_text(),
		})

# ================================================================ malformed layer input

func _malformed_section() -> void:
	var base: Dictionary = FxLookScript.materialize(FxLookScript.new_look("FUZZ_MALFORMED_BASE", "Malformed Base", "DRAFT"))
	var fx: Dictionary = FxLookScript.new_layer("FX", "Halos")
	fx["fx"] = {"fringe": 1.0, "intensity": 1.2, "edge_width": 9.0, "wind_reach": 33.0, "wind_trail": 0.5}
	base["layers"].append(fx)
	_check(bool(FxLookScript.validate(base)["ok"]), "malformed baseline validates", str(FxLookScript.validate(base)["errors"]))

	_check(_error_contains(_mutate(base, func(d): d["layers"].append(d["layers"][0].duplicate(true))), "exactly one SOURCE"), "malformed: two SOURCE layers rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"] = [d["layers"][1]]), "exactly one SOURCE"), "malformed: a missing SOURCE is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"].append(_with_id(d["layers"][1].duplicate(true), str(d["layers"][0]["layer_id"])))), "duplicate"), "malformed: duplicate layer ids rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["layer_id"] = "l1"), "too short"), "malformed: a short layer_id is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["type"] = "WARP"), "invalid"), "malformed: an unknown layer type is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][0]["plane"] = "TARGET_OVERLAY"), "TARGET_SOURCE"), "malformed: a SOURCE off TARGET_SOURCE is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["plane"] = "TARGET_SIDEWAYS"), "invalid"), "malformed: an invalid plane is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["blend_mode"] = "OVERLAY"), "invalid"), "malformed: an invalid blend mode is rejected")
	_check(_error_contains(_mutate_raw(base, func(d): d["layers"][1].erase("input")), "input"), "malformed: an FX layer without input is rejected")
	_check(_error_contains(_mutate_raw(base, func(d): d["layers"][0]["input"] = "ORIGINAL_SOURCE"), "input"), "malformed: a non-FX layer with input is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["input"] = "SOMETHING_ELSE"), "input"), "malformed: an invalid FX input enum is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["mask"]["space"] = "FOLLOW_LAYER"), "FOLLOW_LAYER"), "malformed: FOLLOW_LAYER mask space is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["mask"]["space"] = "SCREEN_SPACE"), "invalid"), "malformed: an invalid mask space is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["mask"]["region"] = "MIDDLE_BAND"), "invalid"), "malformed: an invalid mask region is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["mask"]["width_px"] = -2.0), "width_px"), "malformed: a negative mask width is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["opacity"] = INF), "opacity"), "malformed: a non-finite opacity is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["opacity"] = 1.0000001), "opacity"), "malformed: an out-of-range opacity is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["transform"]["scale"] = [0.0, 1.0]), "must be > 0"), "malformed: a zero scale is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["transform"]["rotation_deg"] = NAN), "non-finite"), "malformed: a non-finite rotation is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["transform"]["pivot"] = [1.5, 0.5]), "pivot"), "malformed: a pivot outside [0,1] is rejected")
	_check(_error_contains(_mutate_raw(base, func(d): d["layers"][1]["transform"]["position_px"] = [1.0, 2.0, 3.0]), "vec2"), "malformed: a non-vec2 position is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["displacement"]["scale"] = 0.0), "must be > 0"), "malformed: a zero displacement scale is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["displacement"]["driver"] = "MAGIC"), "invalid"), "malformed: an invalid displacement driver is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["displacement"]["edge_mode"] = "WRAP"), "invalid"), "malformed: an invalid edge mode is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["displacement"]["time_source"] = "WALL_CLOCK"), "invalid"), "malformed: an invalid time source is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["mask"]["custom_mask"] = "C:\\\\assets\\\\mask.png"), "absolute"), "malformed: an absolute asset path is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["displacement"]["custom_texture"] = "https://example.com/noise.png"), "project-local"), "malformed: a remote asset URL is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["displacement"]["custom_texture"] = "res://assets/vnext/not_there.png"), "does not exist"), "malformed: a missing project asset is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["fx"]["intensity"] = NAN), "non-finite"), "malformed: a non-finite FX value is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"][1]["motion"]["tracks"]["rgb"]["attack"] = INF), "non-finite"), "malformed: a non-finite motion track value is rejected")
	_check(_error_contains(_mutate(base, func(d): d["layers"] = []), "at least one layer"), "malformed: an empty layer list is rejected")
	_check(_error_contains(_mutate(base, func(d): d["schema"] = "NRCU_FX_LOOK_V0_3"), "schema"), "malformed: an unknown schema version is rejected")
	_check(bool(FxLookScript.validate(_extreme_legal_look())["ok"]), "malformed: schema-legal extremes are accepted", str(FxLookScript.validate(_extreme_legal_look())["errors"]))
	_check(not FxLookScript.swap_palette_in(base, "layer-missing-0000"), "malformed: swap_palette_in on a missing layer returns false")
	_check(FxLookScript.find_layer(base, "layer-missing-0000").is_empty(), "malformed: find_layer on a missing id returns {}")
	_check(FxLookScript.source_layer({"layers": []}).is_empty(), "malformed: source_layer without layers returns {}")

# ================================================================ generator

func _shape_source_layer(doc: Dictionary) -> void:
	var source: Dictionary = FxLookScript.source_layer(doc)
	source["opacity"] = float(_pick(OPACITY_EXTREMES))
	source["enabled"] = rng.randf() < 0.9
	source["blend_mode"] = str(_pick(FxLookScript.BLEND_MODES))
	source["transform"] = _gen_transform()
	source["mask"] = _gen_mask()
	source["motion"] = _gen_motion()

func _gen_layer(type: String, index: int) -> Dictionary:
	var layer: Dictionary = FxLookScript.new_layer(type, "%s %02d" % [type, index])
	layer["opacity"] = float(_pick(OPACITY_EXTREMES))
	layer["enabled"] = rng.randf() < 0.85
	layer["locked"] = rng.randf() < 0.15
	layer["blend_mode"] = str(_pick(FxLookScript.BLEND_MODES))
	layer["plane"] = str(_pick(FxLookScript.PLANES))
	layer["transform"] = _gen_transform()
	layer["displacement"] = _gen_displacement()
	layer["mask"] = _gen_mask()
	layer["motion"] = _gen_motion()
	if type == "FX":
		layer["input"] = str(_pick(FxLookScript.INPUTS))
		var fx: Dictionary = layer["fx"]
		var keys: Array = FX_NUMERIC_KEYS.duplicate()
		for i in range(mini(rng.randi_range(3, 12), keys.size())):
			var key := str(_pick(keys))
			keys.erase(key)
			fx[key] = float(_pick(SIZE_EXTREMES if i % 2 == 0 else CONTRACT_EXTREMES))
		fx["fringe_color_a"] = [rng.randf(), rng.randf(), rng.randf(), 1.0]
		fx["fringe_color_b"] = [rng.randf(), rng.randf(), rng.randf(), 1.0]
		fx["time_source"] = str(_pick(FxLookScript.TIME_SOURCES))
		fx["palette_lock_a"] = rng.randf() < 0.5
		fx["palette_swap"] = rng.randf() < 0.5
	else:
		layer["mask"]["enabled"] = rng.randf() < 0.6
	return layer

func _gen_transform() -> Dictionary:
	return {
		"position_px": [float(_pick(POSITION_EXTREMES)), float(_pick(POSITION_EXTREMES))],
		"scale": [float(_pick(SCALE_EXTREMES)), float(_pick(SCALE_EXTREMES))],
		"rotation_deg": float(_pick(ROTATION_EXTREMES)),
		"pivot": [float(_pick(PIVOT_EXTREMES)), float(_pick(PIVOT_EXTREMES))],
		"flip_x": rng.randf() < 0.5,
		"flip_y": rng.randf() < 0.5,
	}

func _gen_displacement() -> Dictionary:
	var displacement: Dictionary = FxLookScript.neutral_displacement()
	displacement["enabled"] = rng.randf() < 0.4
	displacement["driver"] = str(_pick(FxLookScript.DISPLACEMENT_DRIVERS))
	displacement["amount_px"] = [float(_pick(CONTRACT_EXTREMES)), float(_pick(CONTRACT_EXTREMES))]
	displacement["scale"] = float(_pick(SCALE_EXTREMES))
	displacement["speed"] = float(_pick(CONTRACT_EXTREMES))
	displacement["phase"] = float(_pick(TIME_EXTREMES))
	displacement["seed"] = int(_pick(SEED_EXTREMES))
	displacement["time_source"] = str(_pick(FxLookScript.TIME_SOURCES))
	displacement["angle_deg"] = float(_pick(ROTATION_EXTREMES))
	displacement["edge_mode"] = str(_pick(FxLookScript.EDGE_MODES))
	return displacement

func _gen_mask() -> Dictionary:
	var mask: Dictionary = FxLookScript.neutral_mask()
	mask["enabled"] = rng.randf() < 0.5
	mask["source"] = str(_pick(FxLookScript.MASK_SOURCES))
	mask["region"] = str(_pick(FxLookScript.MASK_REGIONS))
	mask["space"] = str(_pick(FxLookScript.MASK_SPACES))
	mask["expand_contract_px"] = float(_pick(CONTRACT_EXTREMES))
	mask["width_px"] = absf(float(_pick(SIZE_EXTREMES)))
	mask["feather_px"] = absf(float(_pick(SIZE_EXTREMES)))
	mask["invert"] = rng.randf() < 0.3
	return mask

func _gen_motion() -> Dictionary:
	var motion: Dictionary = FxLookScript.neutral_motion()
	for key in ["dither", "fringe", "flow", "rgb"]:
		motion["enabled"][key] = rng.randf() < 0.4
		motion["tracks"][key]["anchor"] = str(_pick(["manual", "attack", "release"]))
		for numeric in ["anchor_time", "delay", "attack", "hold", "release", "sustain"]:
			motion["tracks"][key][numeric] = float(_pick(TIME_EXTREMES if numeric != "sustain" else CONTRACT_EXTREMES))
	return motion

func _extreme_legal_look() -> Dictionary:
	var doc: Dictionary = FxLookScript.new_look("FUZZ_EXTREME_LEGAL", "Extreme Legal", "PRODUCTION")
	var source: Dictionary = FxLookScript.source_layer(doc)
	source["opacity"] = 0.0
	source["mask"]["enabled"] = true
	source["mask"]["source"] = "ORIGINAL_SOURCE_ALPHA"
	source["mask"]["region"] = "FULL"
	source["mask"]["space"] = "PRESENTATION_SPACE"
	source["mask"]["expand_contract_px"] = -256.0
	source["mask"]["width_px"] = 0.0
	source["mask"]["feather_px"] = 65536.0
	source["transform"]["scale"] = [0.001, 1000000.0]
	source["transform"]["rotation_deg"] = -1440.0
	source["transform"]["pivot"] = [1.0, 0.0]
	source["displacement"]["enabled"] = true
	source["displacement"]["scale"] = 0.001
	source["displacement"]["amount_px"] = [-4096.0, 4096.0]
	source["displacement"]["seed"] = 2147483647
	source["displacement"]["edge_mode"] = "REPEAT"
	source["displacement"]["time_source"] = "FREE_RUN"
	var fx: Dictionary = FxLookScript.new_layer("FX", "Extreme FX")
	fx["opacity"] = 1.0
	fx["input"] = "COMPOSITE_BELOW"
	fx["plane"] = "COMPOSITION_FOREGROUND"
	fx["blend_mode"] = "MULTIPLY"
	for key in ["size", "intensity", "fringe", "rgb", "time_source"]:
		if key == "time_source":
			fx["fx"][key] = "FREE_RUN"
		else:
			fx["fx"][key] = 1000000.0
	fx["fx"]["palette_source_color"] = [0.0, 0.5, 1.0, 1.0]
	fx["mask"]["enabled"] = true
	fx["mask"]["source"] = "POST_DISPLACEMENT_ALPHA"
	fx["mask"]["region"] = "INNER_BAND"
	fx["mask"]["space"] = "SOURCE_SPACE"
	doc["layers"].append(fx)
	return FxLookScript.materialize(doc)

func _mutate(doc: Dictionary, mutator: Callable) -> Dictionary:
	var copy: Dictionary = doc.duplicate(true)
	mutator.call(copy)
	return FxLookScript.materialize(copy)

func _mutate_raw(doc: Dictionary, mutator: Callable) -> Dictionary:
	# No materialize: for structural violations that materialize() coerces away.
	var copy: Dictionary = doc.duplicate(true)
	mutator.call(copy)
	return copy

func _first_diff(a, b, path := "", depth := 0) -> String:
	# Numeric-type tolerant first-difference locator (mirrors FxLook.equivalent).
	if depth > 10:
		return ""
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		for key in da.keys():
			if not db.has(key):
				return "%s/%s missing on the loaded side" % [path, str(key)]
			var sub := _first_diff(da[key], db[key], "%s/%s" % [path, str(key)], depth + 1)
			if sub != "":
				return sub
		for key in db.keys():
			if not da.has(key):
				return "%s/%s only on the loaded side" % [path, str(key)]
		return ""
	if a is Array and b is Array:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return "%s size %d vs %d" % [path, aa.size(), ba.size()]
		for i in range(aa.size()):
			var sub := _first_diff(aa[i], ba[i], "%s[%d]" % [path, i], depth + 1)
			if sub != "":
				return sub
		return ""
	if a == null or b == null:
		return "" if (a == null and b == null) else "%s %s vs %s" % [path, str(a), str(b)]
	if a is bool or b is bool:
		return "" if (a is bool and b is bool and a == b) else "%s %s vs %s" % [path, str(a), str(b)]
	if (a is int or a is float) and (b is int or b is float):
		return "" if _num_close(a, b) else "%s %s vs %s" % [path, str(a), str(b)]
	return "" if a == b else "%s %s vs %s" % [path, str(a), str(b)]

func _num_close(a, b) -> bool:
	# JSON prints floats with fewer digits than a double carries, so an in-memory
	# value and its reloaded twin may differ in the last bits. 1e-9 relative is
	# still far stricter than any real field mutation.
	var fa := float(a)
	var fb := float(b)
	if is_nan(fa) or is_nan(fb):
		return is_nan(fa) and is_nan(fb)
	if is_inf(fa) or is_inf(fb):
		return fa == fb
	return absf(fa - fb) <= 1e-9 * maxf(1.0, maxf(absf(fa), absf(fb)))

func _document_equivalent(a, b) -> bool:
	return _first_diff(a, b) == ""

func _with_id(layer: Dictionary, layer_id: String) -> Dictionary:
	layer["layer_id"] = layer_id
	return layer

func _error_contains(doc: Dictionary, needle: String) -> bool:
	var result: Dictionary = FxLookScript.validate(doc)
	if bool(result["ok"]):
		return false
	return str(result["errors"]).contains(needle)

# ================================================================ helpers

func _pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]

func _layer_ids(doc: Dictionary) -> Array:
	var out: Array = []
	for raw in doc.get("layers", []):
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("layer_id", "")))
	return out

func _types(doc: Dictionary) -> Array:
	var out: Array = []
	for raw in doc.get("layers", []):
		out.append(str((raw as Dictionary).get("type", "")))
	return out

func _planes(doc: Dictionary) -> Array:
	var out: Array = []
	for raw in doc.get("layers", []):
		out.append(str((raw as Dictionary).get("plane", "")))
	return out

func _blends(doc: Dictionary) -> Array:
	var out: Array = []
	for raw in doc.get("layers", []):
		out.append(str((raw as Dictionary).get("blend_mode", "")))
	return out

func _extremes(doc: Dictionary) -> Dictionary:
	var out := {"min_scale": 0.0, "max_scale": 0.0, "min_opacity": 1.0, "max_opacity": 0.0, "negative_contract": false}
	var first := true
	for raw in doc.get("layers", []):
		if not (raw is Dictionary):
			continue
		var layer: Dictionary = raw
		var scale: Array = layer["transform"]["scale"]
		var opacity := float(layer.get("opacity", 1.0))
		var lowest := minf(float(scale[0]), float(scale[1]))
		var highest := maxf(float(scale[0]), float(scale[1]))
		if first:
			out["min_scale"] = lowest
			out["max_scale"] = highest
			out["min_opacity"] = opacity
			out["max_opacity"] = opacity
			first = false
		else:
			out["min_scale"] = minf(float(out["min_scale"]), lowest)
			out["max_scale"] = maxf(float(out["max_scale"]), highest)
			out["min_opacity"] = minf(float(out["min_opacity"]), opacity)
			out["max_opacity"] = maxf(float(out["max_opacity"]), opacity)
		if float(layer["mask"].get("expand_contract_px", 0.0)) < 0.0:
			out["negative_contract"] = true
	return out

func _count_type(doc: Dictionary, type: String) -> int:
	var count := 0
	for raw in doc.get("layers", []):
		if raw is Dictionary and str((raw as Dictionary).get("type", "")) == type:
			count += 1
	return count

func _pick_non_source_index(doc: Dictionary) -> int:
	var candidates: Array = []
	for i in range((doc.get("layers", []) as Array).size()):
		if str(((doc.get("layers", []) as Array)[i] as Dictionary).get("type", "")) != "SOURCE":
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return int(_pick(candidates))

func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	return _contains_all(a, b)

func _contains_all(haystack: Array, needles: Array) -> bool:
	for needle in needles:
		if not haystack.has(str(needle)):
			return false
	return true

func _layer_json(doc: Dictionary, layer_id: String) -> String:
	var layer: Dictionary = FxLookScript.find_layer(doc, layer_id)
	if layer.is_empty():
		return "<missing:%s>" % layer_id
	return JSON.stringify(layer, "", true)

# ================================================================ reporting

func _prop(family: String, ok: bool, detail := "") -> void:
	var f: Dictionary = families.get(family, {"instances": 0, "failures": 0, "detail": "", "examples": []})
	f["instances"] = int(f["instances"]) + 1
	if not ok:
		f["failures"] = int(f["failures"]) + 1
		if str(f["detail"]) == "":
			f["detail"] = detail
		var examples: Array = f["examples"]
		if examples.size() < 3:
			examples.append(detail)
	families[family] = f

func _note(text: String) -> void:
	notes.append(text)
	print("[NOTE] " + text)

func _evidence(useed: int) -> void:
	for family in families.keys():
		var f: Dictionary = families[family]
		_check(int(f["failures"]) == 0, "%s (%d assertions)" % [str(family), int(f["instances"])], str(f["detail"]))
	var summary := {
		"suite": "fx_vnext_layer_fuzz_test", "seed": useed,
		"looks_requested": looks_target, "looks_valid": looks_generated,
		"looks_round_tripped": round_tripped,
		"checks": checks.size(), "failures": failures,
		"families": families, "notes": notes,
		"status": "PASS" if failures == 0 else "FAIL",
	}
	var sf := FileAccess.open(out_dir.path_join("summary_layer_fuzz_check.json"), FileAccess.WRITE)
	if sf != null:
		sf.store_string(JSON.stringify(summary, "  "))
		sf.close()
	var sample_file := FileAccess.open(out_dir.path_join("layer_fuzz_samples.json"), FileAccess.WRITE)
	if sample_file != null:
		sample_file.store_string(JSON.stringify(samples, "  "))
		sample_file.close()
	var line := "[FX-LAYER-FUZZ] done · checks=%d failures=%d · looks=%d round_trips=%d families=%d" % [checks.size(), failures, looks_generated, round_tripped, families.size()]
	var lf := FileAccess.open(out_dir.path_join("layer_fuzz_checks.log"), FileAccess.WRITE)
	if lf != null:
		lf.store_string("\n".join(checks) + "\n" + line + "\n")
		lf.close()
	print(line)
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(path: String) -> void:
	if path == "":
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
