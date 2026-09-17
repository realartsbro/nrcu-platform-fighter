class_name FxLook
extends RefCounted
# NRCU FX Lab vNext — Look v0.4 model (schema: docs/vnext/schema/nrcu_fx_look_v04.schema.json).
#
# Owns the normalized Look document: fully materialized neutral defaults
# (specs/15 §1), stable layer ids, layer types SOURCE / SOURCE_COPY / FX and
# semantic validation (specs/09 §3). Pure data: no UI, no rendering.

const SCHEMA := "NRCU_FX_LOOK_V0_4"

const TYPE_SOURCE := "SOURCE"
const TYPE_SOURCE_COPY := "SOURCE_COPY"
const TYPE_FX := "FX"
const TYPES := [TYPE_SOURCE, TYPE_SOURCE_COPY, TYPE_FX]

const PLANES := ["COMPOSITION_BACKGROUND", "TARGET_UNDERLAY", "TARGET_SOURCE", "TARGET_OVERLAY", "COMPOSITION_FOREGROUND"]
const BLEND_MODES := ["NORMAL", "ADD", "SCREEN", "MULTIPLY"]
const INPUTS := ["ORIGINAL_SOURCE", "TRANSFORMED_SOURCE", "LAYER_BELOW", "COMPOSITE_BELOW"]
const STATUSES := ["DRAFT", "PRODUCTION", "MIGRATION_REVIEW_REQUIRED"]
const DISPLACEMENT_DRIVERS := ["NOISE", "DIRECTIONAL", "WAVE", "CELLULAR", "FRINGE_DRIVER", "CUSTOM_TEXTURE"]
const EDGE_MODES := ["TRANSPARENT", "CLAMP", "MIRROR", "REPEAT"]
const TIME_SOURCES := ["PRESENTATION_TIME", "FREE_RUN"]
const MASK_SOURCES := ["NONE", "ORIGINAL_SOURCE_ALPHA", "POST_DISPLACEMENT_ALPHA", "CUSTOM_MASK"]
const MASK_REGIONS := ["FULL", "EDGE_BAND", "OUTER_BAND", "INNER_BAND"]
const MASK_SPACES := ["SOURCE_SPACE", "LAYER_SPACE", "PRESENTATION_SPACE"]

static var _serial := 0

# ---------------------------------------------------------------- neutral defaults (specs/15 §1)

static func neutral_transform() -> Dictionary:
	return {
		"position_px": [0.0, 0.0],
		"scale": [1.0, 1.0],
		"rotation_deg": 0.0,
		"pivot": [0.5, 0.5],
		"flip_x": false,
		"flip_y": false,
	}

static func neutral_displacement() -> Dictionary:
	return {
		"enabled": false,
		"driver": "NOISE",
		"amount_px": [0.0, 0.0],
		"scale": 1.0,
		"speed": 0.0,
		"phase": 0.0,
		"seed": 1,
		"time_source": "PRESENTATION_TIME",
		"angle_deg": 0.0,
		"edge_mode": "TRANSPARENT",
		"custom_texture": null,
		"influence_mask": null,
	}

static func neutral_mask() -> Dictionary:
	return {
		"enabled": false,
		"source": "NONE",
		"region": "FULL",
		"space": "LAYER_SPACE",
		"expand_contract_px": 0.0,
		"width_px": 0.0,
		"feather_px": 0.0,
		"invert": false,
		"custom_mask": null,
	}

# Complete v0.3 treatment surface. Keeping these keys in every materialized FX
# layer makes old looks lossless and prevents a sparse document from silently
# selecting a different shader default after a schema upgrade.
static func neutral_fx() -> Dictionary:
	return {
		"pure_continuous": false, "size": 1.0, "intensity": 1.0, "pattern_scale": 1.0,
		"fringe": 0.0, "rgb": 0.0, "flow": 0.0, "dither": 0.0,
		"base_mode": 0.0, "base_opacity": 1.0, "base_grade_amount": 0.0,
		"grade_black_point": 0.0, "grade_white_point": 1.0, "grade_gamma": 1.0,
		"grade_contrast": 1.0, "grade_brightness": 0.0, "grade_saturation": 1.0,
		"source_pixel_size": 0.0, "source_pixel_units": 1.0,
		"mono_threshold": 0.75, "mono_mode": 1.0, "mono_bayer_level": 2.0,
		"mono_pixel": 2.0, "mono_space": 1.0,
		"dither_threshold": 0.75, "dither_black_point": 0.0, "dither_white_point": 1.0,
		"dither_gamma": 1.35, "dither_contrast": 1.6, "dither_brightness": 0.0,
		"dither_mode": 1.0, "dither_bayer_level": 2.0, "dither_pixel": 2.0,
		"dither_levels": 6.0, "dither_space": 1.0,
		"edge_source_mode": 2.0, "edge_alpha_weight": 1.2, "edge_luma_weight": 1.0,
		"edge_threshold": 0.08, "edge_width": 12.0,
		"wind_reach": 54.0, "wind_trail": 1.0, "wind_cutoff": 0.22,
		"split_separation": 10.0, "wind_displace": 1.0, "signal_gain": 1.35,
		"color_blur": 0.0, "signal_softness": 0.08, "signal_posterize": 0.0,
		"fringe_coverage_mode": 0.0, "fringe_coverage_threshold": 0.12,
		"fringe_bayer_level": 2.0, "fringe_pixel": 2.0, "fringe_space": 1.0,
		"fringe_coverage_gain": 1.0, "rgb_gradient": 0.0,
		"rgb_gradient_balance": 0.0, "rgb_gradient_contrast": 1.0,
		"fringe_color_a": [0.25, 0.95, 1.0, 1.0], "fringe_color_b": [1.0, 0.4, 0.85, 1.0],
		"fringe_bleed": 0.65, "fringe_blend_mode": 0.0, "geometry_units": 1.0,
		"effect_mask_enabled": false, "effect_mask_invert": false,
		"effect_mask_threshold": 0.5, "effect_mask_softness": 0.10,
		"effect_mask_base": false, "edge_mask_path": "", "treatment_mask_path": "",
		"driver_mode": 0.0, "driver_sampling_mode": 0.0, "driver_pixel_size": 2.0,
		"FIELD_STRENGTH": 0.42, "FIELD_SPEED": 0.55, "OUTWARDNESS": 0.55,
		"FIELD_BREAKUP": 0.85, "COORD_NUDGE": 0.18, "FIELD_SIZE": 1.0,
		"FIELD_CENTER_X": 1.25, "FIELD_CENTER_Y": 1.45,
		"LEGACY_SCALE": 5.0, "LEGACY_SPEED": 0.3, "LEGACY_RADIAL": 0.45,
		"DRIVER_CENTER_X": 1.5, "DRIVER_CENTER_Y": 1.5, "DRIVER_SCALE": 1.0,
		"DRIVER_STRETCH": 0.0, "DRIVER_ANGLE": 0.0, "DRIVER_SPEED": 1.0,
		"DRIVER_DETAIL": 0.5, "DRIVER_FLOW": 0.5,
		"flow_strength": 1.8, "flow_center_x": 0.5, "flow_center_y": 0.5,
		"rgb_shift_amount": 14.0, "rgb_shift_angle": 0.0, "rgb_shift_units": 1.0,
		"rgb_shift_alpha": 0.0, "temporal_hold": 0.0,
		"palette_strategy": 0.0, "palette_lock_a": false, "palette_lock_b": false,
		"palette_swap": false, "palette_source_color": [0.5, 0.5, 0.5, 1.0],
		"palette_hue_offset": 0.0, "palette_saturation": 1.0, "palette_value": 1.0,
		"time_source": "PRESENTATION_TIME",
	}

static func neutral_motion() -> Dictionary:
	return {
		"enabled": {"dither": false, "fringe": false, "flow": false, "rgb": false},
		"tracks": {
			"dither": _neutral_motion_track(), "fringe": _neutral_motion_track(),
			"flow": _neutral_motion_track(), "rgb": _neutral_motion_track(),
		},
	}

static func _neutral_motion_track() -> Dictionary:
	return {"anchor": "manual", "anchor_time": 0.0, "delay": 0.0, "attack": 0.10,
		"hold": 0.08, "release": 0.25, "sustain": 0.0,
		"attack_curve": "cubic_out", "release_curve": "sine_in_out"}

static func new_layer(type: String, name: String) -> Dictionary:
	var layer := {
		"layer_id": next_layer_id(type),
		"name": name if name != "" else type.capitalize(),
		"type": type,
		"enabled": true,
		"locked": false,
		"opacity": 1.0,
		"blend_mode": "NORMAL",
		"plane": "TARGET_SOURCE" if type == TYPE_SOURCE else "TARGET_OVERLAY",
		"transform": neutral_transform(),
		"displacement": neutral_displacement(),
		"mask": neutral_mask(),
		"fx": neutral_fx(),
		"motion": neutral_motion(),
	}
	if type == TYPE_FX:
		layer["input"] = "ORIGINAL_SOURCE"
	return layer

static func new_look(look_id: String, name: String, status := "DRAFT") -> Dictionary:
	return {
		"schema": SCHEMA,
		"look_id": look_id,
		"name": name,
		"revision": 1,
		"status": status,
		"metadata": {"migrated_from": null},
		"layers": [new_layer(TYPE_SOURCE, "Source")],
	}

# ---------------------------------------------------------------- materialize

static func materialize(doc: Dictionary) -> Dictionary:
	# Canonical normalized form: every persisted Look is fully materialized.
	var out := doc.duplicate(true)
	var layers: Array = out.get("layers", [])
	var fixed_layers: Array = []
	for raw in layers:
		if not (raw is Dictionary):
			continue
		var layer: Dictionary = (raw as Dictionary).duplicate(true)
		layer["layer_id"] = str(layer.get("layer_id", next_layer_id(str(layer.get("type", "layer")).to_lower())))
		layer["name"] = str(layer.get("name", "Layer"))
		layer["type"] = str(layer.get("type", TYPE_FX))
		layer["enabled"] = bool(layer.get("enabled", true))
		layer["locked"] = bool(layer.get("locked", false))
		layer["opacity"] = float(layer.get("opacity", 1.0))
		layer["blend_mode"] = str(layer.get("blend_mode", "NORMAL"))
		layer["plane"] = str(layer.get("plane", "TARGET_SOURCE" if layer["type"] == TYPE_SOURCE else "TARGET_OVERLAY"))
		layer["transform"] = _coerce_transform(_materialize_into(neutral_transform(), layer.get("transform", {})))
		layer["displacement"] = _coerce_displacement(_materialize_into(neutral_displacement(), layer.get("displacement", {})))
		layer["mask"] = _coerce_mask(_materialize_into(neutral_mask(), layer.get("mask", {})))
		if not (layer.get("fx") is Dictionary):
			layer["fx"] = neutral_fx()
		else:
			layer["fx"] = _materialize_into(neutral_fx(), layer["fx"])
		if not (layer.get("motion") is Dictionary):
			layer["motion"] = neutral_motion()
		else:
			layer["motion"] = _coerce_motion(_materialize_into(neutral_motion(), layer["motion"]))
		if layer["type"] == TYPE_FX:
			layer["input"] = str(layer.get("input", "ORIGINAL_SOURCE"))
		else:
			layer.erase("input")
		fixed_layers.append(layer)
	out["layers"] = fixed_layers
	out["schema"] = str(out.get("schema", SCHEMA))
	out["look_id"] = str(out.get("look_id", ""))
	out["name"] = str(out.get("name", ""))
	out["revision"] = int(out.get("revision", 1))
	out["status"] = str(out.get("status", "DRAFT"))
	if not (out.get("metadata") is Dictionary):
		out["metadata"] = {}
	if not out["metadata"].has("migrated_from"):
		out["metadata"]["migrated_from"] = null
	return out

static func _materialize_into(neutral: Dictionary, incoming) -> Dictionary:
	var out := neutral.duplicate(true)
	if incoming is Dictionary:
		for key in (incoming as Dictionary).keys():
			if out.has(key):
				out[key] = (incoming as Dictionary)[key]
	return out

# Type canonicalization: JSON loading yields floats for every number, code paths
# yield ints. Canonical form fixes the numeric type per schema field so that
# serialization roundtrips are strictly stable (Godot's recursive container
# equality is type-strict for numbers).
static func _coerce_transform(obj: Dictionary) -> Dictionary:
	obj["position_px"] = _float_pair(obj.get("position_px", [0.0, 0.0]))
	obj["scale"] = _float_pair(obj.get("scale", [1.0, 1.0]))
	obj["rotation_deg"] = float(obj.get("rotation_deg", 0.0))
	obj["pivot"] = _float_pair(obj.get("pivot", [0.5, 0.5]))
	obj["flip_x"] = bool(obj.get("flip_x", false))
	obj["flip_y"] = bool(obj.get("flip_y", false))
	return obj

static func _coerce_displacement(obj: Dictionary) -> Dictionary:
	obj["enabled"] = bool(obj.get("enabled", false))
	obj["driver"] = str(obj.get("driver", "NOISE"))
	obj["amount_px"] = _float_pair(obj.get("amount_px", [0.0, 0.0]))
	obj["scale"] = float(obj.get("scale", 1.0))
	obj["speed"] = float(obj.get("speed", 0.0))
	obj["phase"] = float(obj.get("phase", 0.0))
	obj["seed"] = int(obj.get("seed", 1))
	obj["time_source"] = str(obj.get("time_source", "PRESENTATION_TIME"))
	obj["angle_deg"] = float(obj.get("angle_deg", 0.0))
	obj["edge_mode"] = str(obj.get("edge_mode", "TRANSPARENT"))
	if obj.get("custom_texture") != null:
		obj["custom_texture"] = str(obj["custom_texture"])
	if obj.get("influence_mask") is Dictionary:
		obj["influence_mask"] = _coerce_mask((obj["influence_mask"] as Dictionary).duplicate(true))
	return obj

static func _coerce_mask(obj: Dictionary) -> Dictionary:
	obj["enabled"] = bool(obj.get("enabled", false))
	obj["source"] = str(obj.get("source", "NONE"))
	obj["region"] = str(obj.get("region", "FULL"))
	obj["space"] = str(obj.get("space", "LAYER_SPACE"))
	obj["expand_contract_px"] = float(obj.get("expand_contract_px", 0.0))
	obj["width_px"] = float(obj.get("width_px", 0.0))
	obj["feather_px"] = float(obj.get("feather_px", 0.0))
	obj["invert"] = bool(obj.get("invert", false))
	if obj.get("custom_mask") != null:
		obj["custom_mask"] = str(obj["custom_mask"])
	return obj

static func _coerce_motion(obj: Dictionary) -> Dictionary:
	var out: Dictionary = neutral_motion()
	var enabled: Dictionary = obj.get("enabled", {}) if obj.get("enabled") is Dictionary else {}
	for key in ["dither", "fringe", "flow", "rgb"]:
		out["enabled"][key] = bool(enabled.get(key, false))
	var tracks: Dictionary = obj.get("tracks", {}) if obj.get("tracks") is Dictionary else {}
	# Accept the compact legacy shape {dither:{...}, ...} as an additive input.
	for key in ["dither", "fringe", "flow", "rgb"]:
		var incoming = tracks.get(key, obj.get(key, {}))
		if incoming is Dictionary:
			var merged: Dictionary = _materialize_into(_neutral_motion_track(), incoming)
			merged["anchor"] = str(merged.get("anchor", "manual"))
			merged["anchor_time"] = float(merged.get("anchor_time", 0.0))
			for numeric in ["delay", "attack", "hold", "release", "sustain"]:
				merged[numeric] = float(merged.get(numeric, 0.0))
			out["tracks"][key] = merged
	return out

static func swap_palette_in(doc: Dictionary, layer_id: String) -> bool:
	var layer: Dictionary = find_layer(doc, layer_id)
	if layer.is_empty() or not (layer.get("fx") is Dictionary):
		return false
	var fx: Dictionary = layer["fx"]
	var a = fx.get("fringe_color_a", neutral_fx()["fringe_color_a"])
	var b = fx.get("fringe_color_b", neutral_fx()["fringe_color_b"])
	fx["fringe_color_a"] = b
	fx["fringe_color_b"] = a
	return true

static func palette_strategy_name(strategy: float) -> String:
	var names := ["DOMINANT + DISTANT", "COMPLEMENT", "SPLIT COMPLEMENT", "ANALOGOUS", "TRIADIC", "MONOCHROME"]
	var index: int = clampi(int(strategy), 0, names.size() - 1)
	return names[index]

static func _float_pair(vec) -> Array:
	var out := [0.0, 0.0]
	if vec is Array and (vec as Array).size() >= 2:
		out[0] = float((vec as Array)[0])
		out[1] = float((vec as Array)[1])
	return out

# ---------------------------------------------------------------- validation

static func validate(doc: Dictionary) -> Dictionary:
	var errors: Array = []
	if str(doc.get("schema", "")) != SCHEMA:
		errors.append("schema: expected %s, got %s" % [SCHEMA, str(doc.get("schema", ""))])
	if str(doc.get("look_id", "")) == "":
		errors.append("look_id: must not be empty")
	elif not is_valid_look_id(str(doc.get("look_id", ""))):
		# R3 §23 security finding: an id with path separators or control characters
		# would escape the looks/ directory or destabilize file paths.
		errors.append("look_id: illegal id %s" % str(doc.get("look_id", "")))
	if str(doc.get("name", "")) == "":
		errors.append("name: must not be empty")
	var revision := int(doc.get("revision", 0))
	if revision < 1:
		errors.append("revision: must be >= 1")
	if str(doc.get("status", "")) not in STATUSES:
		errors.append("status: invalid value %s" % str(doc.get("status", "")))
	var layers: Array = doc.get("layers", [])
	if layers.is_empty():
		errors.append("layers: at least one layer required")
	var source_count := 0
	var seen_ids: Dictionary = {}
	for raw in layers:
		if not (raw is Dictionary):
			errors.append("layers: entry is not an object")
			continue
		var layer: Dictionary = raw
		var layer_id := str(layer.get("layer_id", ""))
		var type := str(layer.get("type", ""))
		if layer_id.length() < 8:
			errors.append("layer_id: too short: %s" % layer_id)
		if seen_ids.has(layer_id):
			errors.append("layer_id: duplicate: %s" % layer_id)
		seen_ids[layer_id] = true
		if type not in TYPES:
			errors.append("layer type: invalid %s" % type)
			continue
		if type == TYPE_SOURCE:
			source_count += 1
			if str(layer.get("plane", "")) != "TARGET_SOURCE":
				errors.append("SOURCE layer must use TARGET_SOURCE plane (layer %s)" % layer_id)
		if type == TYPE_FX:
			if str(layer.get("input", "")) not in INPUTS:
				errors.append("FX layer requires a valid input (layer %s)" % layer_id)
		elif layer.has("input"):
			errors.append("non-FX layer must not carry input (layer %s)" % layer_id)
		if str(layer.get("plane", "")) not in PLANES:
			errors.append("plane: invalid %s (layer %s)" % [str(layer.get("plane", "")), layer_id])
		if str(layer.get("blend_mode", "")) not in BLEND_MODES:
			errors.append("blend_mode: invalid %s (layer %s)" % [str(layer.get("blend_mode", "")), layer_id])
		var opacity := float(layer.get("opacity", -1.0))
		if not is_finite(opacity) or opacity < 0.0 or opacity > 1.0:
			errors.append("opacity out of range (layer %s)" % layer_id)
		errors.append_array(_validate_transform(layer.get("transform", {}), layer_id))
		errors.append_array(_validate_displacement(layer.get("displacement", {}), layer_id))
		errors.append_array(_validate_mask(layer.get("mask", {}), layer_id))
		errors.append_array(_validate_fx(layer.get("fx", {}), layer_id))
		errors.append_array(_validate_motion(layer.get("motion", {}), layer_id))
	if source_count != 1:
		errors.append("layers: exactly one SOURCE layer required (found %d)" % source_count)
	return {"ok": errors.is_empty(), "errors": errors}

static func _validate_fx(fx, layer_id: String) -> Array:
	var errors: Array = []
	if not (fx is Dictionary):
		return ["fx: missing (layer %s)" % layer_id]
	var f: Dictionary = fx
	for key in ["size", "intensity", "pattern_scale", "fringe", "rgb", "flow", "dither",
		"base_mode", "base_opacity", "base_grade_amount", "grade_black_point", "grade_white_point",
		"grade_gamma", "grade_contrast", "grade_brightness", "grade_saturation", "source_pixel_size",
		"source_pixel_units", "mono_threshold", "mono_mode", "mono_bayer_level", "mono_pixel", "mono_space",
		"dither_threshold", "dither_black_point", "dither_white_point", "dither_gamma", "dither_contrast",
		"dither_brightness", "dither_mode", "dither_bayer_level", "dither_pixel", "dither_levels", "dither_space",
		"edge_source_mode", "edge_alpha_weight", "edge_luma_weight", "edge_threshold", "edge_width",
		"wind_reach", "wind_trail", "wind_cutoff", "split_separation", "wind_displace", "signal_gain",
		"color_blur", "signal_softness", "signal_posterize", "fringe_coverage_mode", "fringe_coverage_threshold",
		"fringe_bayer_level", "fringe_pixel", "fringe_space", "fringe_coverage_gain", "rgb_gradient",
		"rgb_gradient_balance", "rgb_gradient_contrast", "fringe_bleed", "fringe_blend_mode", "geometry_units",
		"effect_mask_threshold", "effect_mask_softness", "driver_mode", "driver_sampling_mode", "driver_pixel_size",
		"FIELD_STRENGTH", "FIELD_SPEED", "OUTWARDNESS", "FIELD_BREAKUP", "COORD_NUDGE", "FIELD_SIZE",
		"FIELD_CENTER_X", "FIELD_CENTER_Y", "LEGACY_SCALE", "LEGACY_SPEED", "LEGACY_RADIAL", "DRIVER_CENTER_X",
		"DRIVER_CENTER_Y", "DRIVER_SCALE", "DRIVER_STRETCH", "DRIVER_ANGLE", "DRIVER_SPEED", "DRIVER_DETAIL",
		"DRIVER_FLOW", "flow_strength", "flow_center_x", "flow_center_y", "rgb_shift_amount", "rgb_shift_angle",
		"rgb_shift_units", "rgb_shift_alpha", "temporal_hold", "palette_strategy", "palette_hue_offset",
		"palette_saturation", "palette_value"]:
		if f.has(key) and not _finite_number(f.get(key, null)):
			errors.append("fx.%s: non-finite (layer %s)" % [key, layer_id])
	for key in ["palette_lock_a", "palette_lock_b", "palette_swap"]:
		if f.has(key) and not (f.get(key) is bool):
			errors.append("fx.%s: expected bool (layer %s)" % [key, layer_id])
	if f.has("palette_source_color"):
		var source_color = f.get("palette_source_color", null)
		if not (source_color is Array) or (source_color as Array).size() < 3 or not _finite_numbers(source_color as Array):
			errors.append("fx.palette_source_color: expected finite color (layer %s)" % layer_id)
	for key in ["fringe_color_a", "fringe_color_b"]:
		if not f.has(key):
			continue
		var color = f.get(key, null)
		if not (color is Array) or (color as Array).size() < 3 or not _finite_numbers(color as Array):
			errors.append("fx.%s: expected finite color (layer %s)" % [key, layer_id])
	if f.has("time_source") and str(f.get("time_source", "")) not in TIME_SOURCES:
		errors.append("fx.time_source: invalid (layer %s)" % layer_id)
	return errors

static func _validate_motion(motion, layer_id: String) -> Array:
	var errors: Array = []
	if not (motion is Dictionary):
		return ["motion: missing (layer %s)" % layer_id]
	if (motion as Dictionary).is_empty():
		return []
	var m: Dictionary = motion
	var enabled: Dictionary = m.get("enabled", {}) if m.get("enabled") is Dictionary else {}
	var tracks: Dictionary = m.get("tracks", {}) if m.get("tracks") is Dictionary else {}
	for key in ["dither", "fringe", "flow", "rgb"]:
		if not (enabled.get(key, false) is bool):
			errors.append("motion.enabled.%s: expected bool (layer %s)" % [key, layer_id])
		var track: Dictionary = tracks.get(key, {}) if tracks.get(key, {}) is Dictionary else {}
		for numeric in ["anchor_time", "delay", "attack", "hold", "release", "sustain"]:
			if not _finite_number(track.get(numeric, null)):
				errors.append("motion.%s.%s: non-finite (layer %s)" % [key, numeric, layer_id])
	return errors

static func _validate_transform(transform, layer_id: String) -> Array:
	var errors: Array = []
	if not (transform is Dictionary):
		errors.append("transform: missing (layer %s)" % layer_id)
		return errors
	var t: Dictionary = transform
	for key in ["position_px", "scale", "pivot"]:
		var vec = t.get(key, null)
		if not (vec is Array) or (vec as Array).size() != 2:
			errors.append("transform.%s: expected vec2 (layer %s)" % [key, layer_id])
		elif not _finite_numbers(vec):
			errors.append("transform.%s: non-finite value (layer %s)" % [key, layer_id])
	if t.get("scale") is Array and (t["scale"] as Array).size() == 2:
		var scale: Array = t["scale"]
		if float(scale[0]) <= 0.0 or float(scale[1]) <= 0.0:
			errors.append("transform.scale: must be > 0 (layer %s)" % layer_id)
	if t.get("pivot") is Array and (t["pivot"] as Array).size() == 2:
		var pivot: Array = t["pivot"]
		for i in range(2):
			var v := float(pivot[i])
			if v < 0.0 or v > 1.0:
				errors.append("transform.pivot: out of [0,1] (layer %s)" % layer_id)
	if not _finite_number(t.get("rotation_deg", null)):
		errors.append("transform.rotation_deg: non-finite (layer %s)" % layer_id)
	return errors

static func _validate_displacement(displacement, layer_id: String) -> Array:
	var errors: Array = []
	if not (displacement is Dictionary):
		errors.append("displacement: missing (layer %s)" % layer_id)
		return errors
	var d: Dictionary = displacement
	if str(d.get("driver", "")) not in DISPLACEMENT_DRIVERS:
		errors.append("displacement.driver: invalid (layer %s)" % layer_id)
	if str(d.get("edge_mode", "")) not in EDGE_MODES:
		errors.append("displacement.edge_mode: invalid (layer %s)" % layer_id)
	if str(d.get("time_source", "")) not in TIME_SOURCES:
		errors.append("displacement.time_source: invalid (layer %s)" % layer_id)
	if not (d.get("amount_px") is Array) or not _finite_numbers(d.get("amount_px", [0, 0])):
		errors.append("displacement.amount_px: invalid (layer %s)" % layer_id)
	if not _finite_number(d.get("scale", null)) or float(d.get("scale", 0.0)) <= 0.0:
		errors.append("displacement.scale: must be > 0 (layer %s)" % layer_id)
	for key in ["speed", "phase", "angle_deg"]:
		if not _finite_number(d.get(key, null)):
			errors.append("displacement.%s: non-finite (layer %s)" % [key, layer_id])
	if d.get("custom_texture") != null:
		errors.append_array(_validate_asset_path(d["custom_texture"], "displacement.custom_texture", layer_id))
	if d.get("influence_mask") != null and d["influence_mask"] is Dictionary:
		errors.append_array(_validate_mask(d["influence_mask"], layer_id))
	return errors

static func _validate_mask(mask, layer_id: String) -> Array:
	var errors: Array = []
	if not (mask is Dictionary):
		errors.append("mask: missing (layer %s)" % layer_id)
		return errors
	var m: Dictionary = mask
	if str(m.get("source", "")) not in MASK_SOURCES:
		errors.append("mask.source: invalid (layer %s)" % layer_id)
	if str(m.get("region", "")) not in MASK_REGIONS:
		errors.append("mask.region: invalid (layer %s)" % layer_id)
	if str(m.get("space", "")) not in MASK_SPACES:
		errors.append("mask.space: invalid (layer %s)" % layer_id)
	if str(m.get("space", "")) == "FOLLOW_LAYER":
		errors.append("mask.space: FOLLOW_LAYER is not a persisted value (layer %s)" % layer_id)
	for key in ["expand_contract_px", "width_px", "feather_px"]:
		if not _finite_number(m.get(key, null)):
			errors.append("mask.%s: non-finite (layer %s)" % [key, layer_id])
		elif float(m[key]) < 0.0 and key != "expand_contract_px":
			errors.append("mask.%s: must be >= 0 (layer %s)" % [key, layer_id])
	if m.get("custom_mask") != null:
		errors.append_array(_validate_asset_path(m["custom_mask"], "mask.custom_mask", layer_id))
	return errors

static func _validate_asset_path(path, label: String, layer_id: String) -> Array:
	var errors: Array = []
	var text := str(path)
	if text.begins_with("res://") or text.begins_with("user://"):
		# Project-local and app-local references are valid only when the asset is
		# present. Persisting a missing user:// ref would make the materialization
		# look valid while the renderer silently samples an empty texture.
		if not FileAccess.file_exists(text) and not ResourceLoader.exists(text):
			errors.append("%s: asset does not exist: %s (layer %s)" % [label, text, layer_id])
	elif text.contains("://"):
		errors.append("%s: must be project-local (layer %s)" % [label, layer_id])
	elif text.begins_with("/") or text.contains(":\\"):
		errors.append("%s: absolute paths are invalid (layer %s)" % [label, layer_id])
	elif text.begins_with("res://"):
		# specs/09 §3: project-local AND loadable.
		if not FileAccess.file_exists(text) and not ResourceLoader.exists(text):
			errors.append("%s: asset does not exist: %s (layer %s)" % [label, text, layer_id])
	return errors

static func is_valid_look_id(look_id: String) -> bool:
	# Conservative file-safe id: letters, digits, underscore, dash; 1..80 chars;
	# must not start with a dot. R3 §23.
	if look_id.length() < 1 or look_id.length() > 80:
		return false
	if look_id.begins_with("."):
		return false
	for i in range(look_id.length()):
		var c := look_id[i]
		var is_ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not is_ok:
			return false
	return true

static func _finite_number(value) -> bool:
	if value == null or value is bool:
		return false
	if value is Array or value is Dictionary:
		return false
	if value is String:
		# float("x") is 0.0 in GDScript: a non-numeric string must NOT pass as a
		# finite number (R3 §12 finding).
		var text := (value as String).strip_edges()
		if not text.is_valid_float():
			return false
		return is_finite(text.to_float())
	var f := float(value)
	return is_finite(f)

static func _sanitize_fx_values(fx: Dictionary) -> Dictionary:
	# R3 §12: every fx field must survive materialization as FINITE data or fall
	# back to its neutral. Numeric strings coerce; containers that are valid
	# numeric vectors (colour pairs) stay; everything else resets to the neutral
	# (or is dropped when the key is not part of the schema).
	var neutral: Dictionary = neutral_fx()
	var out: Dictionary = {}
	for key in fx.keys():
		var value = fx[key]
		var keep := false
		if value is float or value is int:
			keep = is_finite(float(value))
		elif value is String and (value as String).strip_edges().is_valid_float():
			var as_float := (value as String).to_float()
			keep = is_finite(as_float)
			if keep:
				value = as_float
		elif value is Array:
			keep = _finite_numbers(value)
		if keep:
			out[key] = value
		elif neutral.has(key):
			out[key] = neutral[key]
	return out

static func _finite_numbers(values: Array) -> bool:
	for value in values:
		if not _finite_number(value):
			return false
	return true

# ---------------------------------------------------------------- editing helpers

static func find_layer(doc: Dictionary, layer_id: String) -> Dictionary:
	for layer in doc.get("layers", []):
		if layer is Dictionary and str(layer.get("layer_id", "")) == layer_id:
			return layer
	return {}

static func source_layer(doc: Dictionary) -> Dictionary:
	for layer in doc.get("layers", []):
		if layer is Dictionary and str(layer.get("type", "")) == TYPE_SOURCE:
			return layer
	return {}

static func duplicate_layer_in(doc: Dictionary, layer_id: String, new_name := "") -> Dictionary:
	var layers: Array = doc.get("layers", [])
	for index in range(layers.size()):
		var layer: Dictionary = layers[index]
		if str(layer.get("layer_id", "")) != layer_id:
			continue
		var copy: Dictionary = layer.duplicate(true)
		copy["layer_id"] = next_layer_id(str(layer.get("type", "fx")).to_lower())
		copy["name"] = new_name if new_name != "" else str(layer.get("name", "Layer")) + " Copy"
		layers.insert(index + 1, copy)
		return copy
	return {}

static func reset_layer_in(doc: Dictionary, layer_id: String) -> bool:
	var layer := find_layer(doc, layer_id)
	if layer.is_empty():
		return false
	var type := str(layer.get("type", TYPE_FX))
	layer["enabled"] = true
	layer["locked"] = false
	layer["opacity"] = 1.0
	layer["blend_mode"] = "NORMAL"
	layer["transform"] = neutral_transform()
	layer["displacement"] = neutral_displacement()
	layer["mask"] = neutral_mask()
	layer["fx"] = neutral_fx()
	layer["motion"] = neutral_motion()
	if type == TYPE_FX:
		layer["input"] = "ORIGINAL_SOURCE"
	else:
		layer.erase("input")
	return true

static func set_look_status(doc: Dictionary, status: String) -> void:
	if status in STATUSES:
		doc["status"] = status

static func bump_revision(doc: Dictionary) -> int:
	doc["revision"] = int(doc.get("revision", 1)) + 1
	return int(doc["revision"])

# ---------------------------------------------------------------- ids / serialization

static func next_layer_id(prefix: String) -> String:
	_serial += 1
	return "layer-%s-%04d-%s" % [prefix.to_lower(), _serial, _hex(4)]

static func _hex(length: int) -> String:
	var out := ""
	for i in range(length):
		out += "0123456789abcdef"[randi() % 16]
	return out

static func to_json(doc: Dictionary) -> String:
	return JSON.stringify(doc, "  ", true)

static func from_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

static func is_serialized_normalized(doc: Dictionary) -> bool:
	# Numeric-type tolerant comparison: `revision: 1` and `revision: 1.0` are the
	# same normalized value (Godot's recursive container equality is type-strict,
	# JSON loading widens all numbers to float).
	return equivalent(materialize(doc), doc) or _legacy_v03_shape_is_normalized(doc)

static func _legacy_v03_shape_is_normalized(doc: Dictionary) -> bool:
	# vNEXT 0.1/0.2 looks used the serialized `fx_size`/`fx_intensity`
	# aliases. They were already canonical for that schema; accepting them here
	# keeps old planning documents loadable while materialize() upgrades them.
	var layers = doc.get("layers", [])
	if not (layers is Array) or (layers as Array).is_empty():
		return false
	var saw_legacy: bool = false
	for layer_value in layers:
		if not (layer_value is Dictionary):
			return false
		var layer: Dictionary = layer_value
		var fx = layer.get("fx", {})
		if fx is Dictionary and ((fx as Dictionary).has("fx_size") or (fx as Dictionary).has("fx_intensity")):
			saw_legacy = true
	return saw_legacy

static func equivalent(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da.keys():
			if not db.has(key):
				return false
			if not equivalent(da[key], db[key]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return false
		for i in range(aa.size()):
			if not equivalent(aa[i], ba[i]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	if a is bool or b is bool:
		return (a is bool) and (b is bool) and a == b
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return a == b
