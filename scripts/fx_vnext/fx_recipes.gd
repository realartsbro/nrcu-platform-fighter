extends RefCounted
class_name FxRecipes
# NRCU FX Lab vNext — Phase 7 first-class Hero Recipe registry.
#
# Recipes are authoring data, not Production Looks and not replacements for the
# generic one-layer templates. Every recipe definition names its target intent,
# authored canonical fields and macro/Advanced access. Instantiation is pure:
# the caller supplies an instance key and all resulting layer ids are derived
# from that key (never from the process-global FxLook id counter or RNG).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

const PRIMARY_FLAME_ENERGY := "PRIMARY_FLAME_ENERGY"
const ORGANIC_SIDE_FIELD := "ORGANIC_SIDE_FIELD"
const EDGE_HALO := "EDGE_HALO"
const RGB_TEAR := "RGB_TEAR"
const DITHER_TREATMENT := "DITHER_TREATMENT"
const KINETIC_RUSH := "KINETIC_RUSH"
const PATTERN_CUT := "PATTERN_CUT"
const LIVING_CONTOUR := "LIVING_CONTOUR"
const SIGNAL_MELT := "SIGNAL_MELT"
const VACUUM_CLASH := "VACUUM_CLASH"
const CLASH_OVERDRIVE := "CLASH_OVERDRIVE"
const HERO_RECIPE_IDS := [PRIMARY_FLAME_ENERGY, ORGANIC_SIDE_FIELD]
const CURATED_RECIPE_IDS := [EDGE_HALO, RGB_TEAR, DITHER_TREATMENT]
const GOLD_RECIPE_IDS := [LIVING_CONTOUR, SIGNAL_MELT, KINETIC_RUSH, VACUUM_CLASH, PATTERN_CUT, CLASH_OVERDRIVE]
const RECIPE_IDS := HERO_RECIPE_IDS + GOLD_RECIPE_IDS + CURATED_RECIPE_IDS
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const COMPOSITION_RECIPE_IDS := [KINETIC_RUSH, PATTERN_CUT, VACUUM_CLASH, CLASH_OVERDRIVE]

static func recipe_ids() -> Array:
	return RECIPE_IDS.duplicate()

static func list() -> Array:
	var out: Array = []
	for recipe_id in RECIPE_IDS:
		out.append(get_recipe(str(recipe_id)))
	return out

static func has_recipe(recipe_id: String) -> bool:
	return RECIPE_IDS.has(recipe_id)

static func get_recipe(recipe_id: String) -> Dictionary:
	var definition := _definition(recipe_id)
	return definition.duplicate(true)

static func instantiate(recipe_id: String, instance_key: String) -> Dictionary:
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "errors": ["unknown recipe: " + recipe_id], "layers": []}
	var key := instance_key.strip_edges()
	if key == "":
		return {"ok": false, "errors": ["instance_key must not be empty"], "layers": []}
	var layers: Array = []
	var errors: Array = []
	for raw_spec in recipe.get("layers", []):
		var spec: Dictionary = raw_spec
		var layer := FxLookScript.new_layer(str(spec.get("type", FxLookScript.TYPE_FX)), str(spec.get("name", "Recipe Layer")))
		layer["layer_id"] = deterministic_layer_id(recipe_id, key, str(spec.get("instance_key", "layer")))
		var authored: Dictionary = spec.get("authored_fields", {})
		for field_path in authored.keys():
			if not _set_field(layer, str(field_path), authored[field_path]):
				errors.append("%s.%s: unsupported canonical field" % [str(spec.get("instance_key", "layer")), str(field_path)])
		# Re-materialize each layer so callers receive exactly the same canonical
		# shape as a normal FxSession edit, including float coercion and complete
		# neutral defaults.
		var materialized := FxLookScript.materialize({"layers": [layer]})
		var fixed_layers: Array = materialized.get("layers", [])
		if fixed_layers.is_empty():
			errors.append("%s: failed to materialize" % str(spec.get("instance_key", "layer")))
		else:
			layers.append(fixed_layers[0])
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "layers": layers}
	var result := {
		"ok": true,
		"errors": [],
		"recipe_id": recipe_id,
		"instance_key": key,
		"layers": layers,
		"layer_ids": layers.map(func(layer): return str((layer as Dictionary).get("layer_id", ""))),
	}
	if COMPOSITION_RECIPE_IDS.has(recipe_id):
		result["composition"] = instantiate_composition(recipe_id, key, layers)
	return result

static func is_composition_recipe(recipe_id: String) -> bool:
	return COMPOSITION_RECIPE_IDS.has(recipe_id)

static func instantiate_composition(recipe_id: String, instance_key: String, canonical_layers := []) -> Dictionary:
	if not COMPOSITION_RECIPE_IDS.has(recipe_id):
		return {"ok": false, "errors": ["recipe is not composition-owned: " + recipe_id], "doc": {}}
	var layers: Array = canonical_layers
	if layers.is_empty():
		var result := instantiate(recipe_id, instance_key)
		if not bool(result.get("ok", false)):
			return {"ok": false, "errors": result.get("errors", []), "doc": {}}
		layers = result.get("layers", [])
	var doc := FxCompositionScript.new_document("COMP_%s_%s" % [recipe_id, instance_key], str(_definition(recipe_id).get("name", recipe_id)))
	var passes: Array = []
	for index in range(layers.size()):
		var layer: Dictionary = layers[index]
		var fx: Dictionary = (layer.get("fx", {}) as Dictionary).duplicate(true)
		var operator_id := str(fx.get("operator", "NONE"))
		passes.append({
			"pass_id": deterministic_layer_id(recipe_id, instance_key, "composition_pass_%d" % index),
			"name": str(layer.get("name", operator_id)),
			"operator": operator_id,
			"enabled": bool(layer.get("enabled", true)),
			"event_start": float(fx.get("operator_event_start", 0.0)),
			"duration": float(fx.get("operator_duration", 0.0)),
			"lane": "FINAL_COMPOSITE",
			"plane": "COMPOSITION_FOREGROUND",
			"authority": "COMPOSITION",
			"fx": fx,
		})
	# Explicit terminal identity keeps the authored sequence inspectable while
	# the renderer skips it as a no-op; creative passes own their neutral return.
	passes.append({"pass_id": deterministic_layer_id(recipe_id, instance_key, "composition_neutral"), "name": "Neutral Release", "operator": "NONE", "enabled": true, "event_start": 0.0, "duration": 0.0, "lane": "FINAL_COMPOSITE", "plane": "COMPOSITION_FOREGROUND", "authority": "COMPOSITION", "fx": {}})
	doc["final_passes"] = passes
	var check := FxCompositionScript.validate(doc)
	return {"ok": bool(check.get("ok", false)), "errors": check.get("errors", []), "doc": check.get("doc", doc), "pass_ids": passes.map(func(final_pass): return str((final_pass as Dictionary).get("pass_id", "")))}

static func instantiate_look(recipe_id: String, look_id: String, look_name: String, instance_key: String) -> Dictionary:
	var result := instantiate(recipe_id, instance_key)
	var recipe := _definition(recipe_id)
	if not bool(result.get("ok", false)):
		return result
	var look := FxLookScript.new_look(look_id, look_name)
	look["layers"].append_array(result["layers"])
	# Keep the Recipe contract beside the canonical Look. Macros are intent
	# controls over these same fields; they are not a hidden second state store.
	look["metadata"]["recipe_id"] = recipe_id
	look["metadata"]["recipe_macros"] = recipe.get("macros", []).duplicate(true)
	look["metadata"]["recipe_target_compatibility"] = recipe.get("target_compatibility", {}).duplicate(true)
	look["metadata"]["source_semantics"] = recipe.get("source_semantics", {}).duplicate(true)
	look = FxLookScript.materialize(look)
	var validation := FxLookScript.validate_input(look)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "errors": validation.get("errors", []), "layers": result["layers"], "look": look}
	result["look"] = look
	return result

static func apply_macro(doc: Dictionary, recipe_id: String, macro_id: String, value) -> bool:
	# Apply an intent value to the authored canonical fields of every matching
	# recipe layer. Advanced fields remain the sole source of truth after this
	# mapping and therefore round-trip through the normal session transaction.
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return false
	var macro: Dictionary = {}
	for raw_macro in recipe.get("macros", []):
		if str((raw_macro as Dictionary).get("id", "")) == macro_id:
			macro = raw_macro
			break
	if macro.is_empty():
		return false
	var mapping: Dictionary = macro.get("mapping", {})
	for raw_layer in doc.get("layers", []):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		for raw_path in mapping.keys():
			var path := str(raw_path)
			var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
			var source := str(rule.get("source", "value"))
			var mapped = _macro_mapped_value(layer, path, rule, source, value)
			if mapped != null:
				_set_field(layer, path, mapped)
	return true

static func _macro_mapped_value(layer: Dictionary, path: String, rule: Dictionary, source: String, value):
	if source == "anchor":
		return str(value)
	if source == "clock":
		return str(value)
	if source == "mode":
		if value is String:
			return ["LINES", "DISTORTION", "COMBINED"].find(str(value)) if ["LINES", "DISTORTION", "COMBINED"].has(str(value)) else 0.0
		return roundi(clampf(float(value), 0.0, 1.0) * 2.0)
	if source == "option":
		if value is String:
			var options := ["GRID", "DIAGONAL", "ANGULAR", "PULL", "PUSH"]
			var found := options.find(str(value))
			return float(maxi(found, 0))
		return roundi(clampf(float(value), 0.0, 1.0) * 2.0)
	if rule.get("axis", "") != "":
		var angle := clampf(float(value), 0.0, 1.0) * TAU
		return cos(angle) if str(rule.get("axis", "")) == "x" else sin(angle)
	var number := clampf(float(value), 0.0, 1.0)
	if rule.has("min") or rule.has("max"):
		return lerpf(float(rule.get("min", 0.0)), float(rule.get("max", 1.0)), number)
	var leaf := path.get_slice(".", path.get_slice_count(".") - 1)
	var meta: Dictionary = FxLookScript.field_meta_all().get(leaf, {})
	if meta.has("min") or meta.has("max"):
		return lerpf(float(meta.get("min", 0.0)), float(meta.get("max", 1.0)), number)
	return number

static func deterministic_layer_id(recipe_id: String, instance_key: String, layer_key: String) -> String:
	# Slugs remain readable in the layer panel. The bounded digest prevents
	# collisions when two external keys normalize to the same slug while still
	# making the full identity a deterministic function of the supplied key.
	var digest_source := "%s|%s|%s" % [recipe_id, instance_key, layer_key]
	var digest := digest_source.md5_text().substr(0, 8)
	return "recipe-%s-%s-%s-%s" % [_slug(recipe_id), _slug(instance_key), _slug(layer_key), digest]

static func authored_field_paths(recipe_id: String) -> Array:
	var recipe := _definition(recipe_id)
	var seen: Dictionary = {}
	var out: Array = []
	for raw_spec in recipe.get("layers", []):
		var fields: Dictionary = (raw_spec as Dictionary).get("authored_fields", {})
		for path in fields.keys():
			var text := str(path)
			if not seen.has(text):
				seen[text] = true
				out.append(text)
	return out

static func validate_authored_fields(recipe_id: String, layers: Array) -> Dictionary:
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "errors": ["unknown recipe: " + recipe_id]}
	var errors: Array = []
	var specs: Array = recipe.get("layers", [])
	if layers.size() != specs.size():
		errors.append("expected %d recipe layers, got %d" % [specs.size(), layers.size()])
	for i in range(mini(layers.size(), specs.size())):
		var layer: Dictionary = layers[i]
		var spec: Dictionary = specs[i]
		var authored: Dictionary = spec.get("authored_fields", {})
		for path in authored.keys():
			var actual = _get_field(layer, str(path))
			if actual == null and authored[path] != null:
				errors.append("%s.%s: authored value missing" % [str(spec.get("instance_key", "layer")), str(path)])
			elif not FxLookScript.equivalent(actual, authored[path]):
				errors.append("%s.%s: authored value changed" % [str(spec.get("instance_key", "layer")), str(path)])
		var neutral := FxLookScript.new_layer(str(spec.get("type", FxLookScript.TYPE_FX)), "neutral")
		var changed := _diff_paths(neutral, layer)
		for path in changed:
			if not authored.has(path):
				errors.append("%s.%s: hidden creative value" % [str(spec.get("instance_key", "layer")), path])
	return {"ok": errors.is_empty(), "errors": errors}

static func validate_registry() -> Dictionary:
	var errors: Array = []
	var ids := recipe_ids()
	if ids.size() < 5:
		errors.append("recipe library must expose both Hero Recipes and at least three curated starting points")
	for recipe_id in ids:
		var recipe := _definition(str(recipe_id))
		if recipe.is_empty():
			errors.append("missing definition: " + str(recipe_id))
			continue
		if str(recipe.get("stable_id", "")) != str(recipe_id):
			errors.append("%s: stable_id mismatch" % recipe_id)
		if str(recipe.get("description", "")).strip_edges() == "":
			errors.append("%s: description missing" % recipe_id)
		if not bool(recipe.get("advanced_access", false)):
			errors.append("%s: Advanced access missing" % recipe_id)
		var compatibility: Dictionary = recipe.get("target_compatibility", {})
		if (compatibility.get("target_roles", []) as Array).is_empty():
			errors.append("%s: target compatibility missing" % recipe_id)
		var layer_keys: Dictionary = {}
		var instantiated := instantiate(str(recipe_id), "registry-validation")
		if not bool(instantiated.get("ok", false)):
			errors.append_array(instantiated.get("errors", []))
			continue
		for raw_spec in recipe.get("layers", []):
			var spec: Dictionary = raw_spec
			var layer_key := str(spec.get("instance_key", ""))
			if layer_key == "" or layer_keys.has(layer_key):
				errors.append("%s: layer instance keys must be unique" % recipe_id)
			layer_keys[layer_key] = true
			var authored: Dictionary = spec.get("authored_fields", {})
			for path in authored.keys():
				if not _is_supported_field_path(str(path)):
					errors.append("%s.%s: unsupported authored field" % [recipe_id, str(path)])
		var stack_check := validate_authored_fields(str(recipe_id), instantiated.get("layers", []))
		if not bool(stack_check.get("ok", false)):
			errors.append_array(stack_check.get("errors", []))
		var look := FxLookScript.new_look("RECIPE_%s" % recipe_id, str(recipe.get("name", recipe_id)))
		look["layers"].append_array(instantiated.get("layers", []))
		var canonical := FxLookScript.materialize(look)
		var look_check := FxLookScript.validate_input(canonical)
		if not bool(look_check.get("ok", false)):
			errors.append_array(look_check.get("errors", []))
		for macro in recipe.get("macros", []):
			for path in (macro as Dictionary).get("fields", []):
				if not authored_field_paths(str(recipe_id)).has(str(path)):
					errors.append("%s macro references an unauthored field: %s" % [recipe_id, str(path)])
	return {"ok": errors.is_empty(), "errors": errors}

static func _definition(recipe_id: String) -> Dictionary:
	match recipe_id:
		KINETIC_RUSH:
			return _decorate({
				"stable_id": KINETIC_RUSH,
				"name": "Kinetic Rush",
				"category": "Gold Recipe",
				"description": "A full-frame radial speedline field for forward motion and clash escalation, authored as a real final-composite operator.",
				"intent": "Kinetic final-frame acceleration",
				"operator_ids": ["speedlines_field"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "ENERGY", "label": "Energy", "fields": ["fx.operator_strength", "fx.operator_distortion"], "mapping": {"fx.operator_strength": {"source": "value"}, "fx.operator_distortion": {"source": "value", "scale": 0.45}}},
					{"id": "DENSITY", "label": "Density", "fields": ["fx.operator_scale", "fx.operator_pattern_mode"], "mapping": {"fx.operator_scale": {"source": "value", "min": 0.5, "max": 2.5}, "fx.operator_pattern_mode": {"source": "value", "threshold": 0.72}}},
					{"id": "FOCUS", "label": "Focus", "fields": ["fx.operator_center_x", "fx.operator_center_y"], "mapping": {"fx.operator_anchor": {"source": "anchor"}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value", "axis": "x"}, "fx.operator_axis_y": {"source": "value", "axis": "y"}}},
					{"id": "DISTORTION", "label": "Distortion", "fields": ["fx.operator_distortion", "fx.operator_mix_mode"], "mapping": {"fx.operator_distortion": {"source": "value"}, "fx.operator_mix_mode": {"source": "mode"}}},
					{"id": "MOTION", "label": "Motion", "fields": ["fx.operator_speed", "fx.operator_time_source"], "mapping": {"fx.operator_speed": {"source": "value", "min": 0.0, "max": 3.0}, "fx.operator_time_source": {"source": "clock"}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "kinetic_speedlines", "name": "Kinetic Speedlines", "type": "FX", "authored_fields": {
					"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "speedlines_field", "fx.operator_anchor": "TARGET_CENTER", "fx.operator_strength": 0.72, "fx.operator_scale": 1.0, "fx.operator_speed": 1.25, "fx.operator_pattern_mode": 0.0, "fx.operator_mix_mode": 2.0, "fx.operator_distortion": 0.24, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.final_tint_amount": 0.0,
				}}],
			})
		PATTERN_CUT:
			return _decorate({
				"stable_id": PATTERN_CUT,
				"name": "Pattern Cut",
				"category": "Gold Recipe",
				"description": "A clocked geometric cut that replaces frame-wide transition guesswork with a readable captured-frame pattern.",
				"intent": "Patterned transition cut",
				"operator_ids": ["pattern_transition"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "PROGRESS", "label": "Progress", "fields": ["fx.operator_progress_start", "fx.operator_progress_end"], "mapping": {"fx.operator_progress_start": {"source": "value", "min": 0.0, "max": 1.0}, "fx.operator_progress_end": {"source": "value", "min": 0.0, "max": 1.0}}},
					{"id": "PATTERN", "label": "Pattern", "fields": ["fx.operator_pattern_family", "fx.operator_pattern_mode"], "mapping": {"fx.operator_pattern_family": {"source": "option"}, "fx.operator_pattern_mode": {"source": "value"}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value"}, "fx.operator_axis_y": {"source": "value"}}},
					{"id": "SCALE", "label": "Scale", "fields": ["fx.operator_scale"], "mapping": {"fx.operator_scale": {"source": "value", "min": 0.5, "max": 3.0}}},
					{"id": "FEATHER", "label": "Feather", "fields": ["fx.operator_softness"], "mapping": {"fx.operator_softness": {"source": "value", "min": 0.01, "max": 0.5}}},
					{"id": "MOTION", "label": "Motion", "fields": ["fx.operator_speed", "fx.operator_time_source"], "mapping": {"fx.operator_speed": {"source": "value", "min": 0.0, "max": 3.0}, "fx.operator_time_source": {"source": "clock"}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "pattern_cut", "name": "Pattern Cut", "type": "FX", "authored_fields": {
					"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "pattern_transition", "fx.operator_strength": 0.78, "fx.operator_scale": 1.0, "fx.operator_speed": 1.0, "fx.operator_pattern_family": 1.0, "fx.operator_progress": 0.0, "fx.operator_progress_start": 0.0, "fx.operator_progress_end": 1.0, "fx.operator_progress_mode": "EVENT_LINEAR", "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.18, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.operator_color_a": [0.25, 0.95, 1.0, 1.0], "fx.operator_color_b": [1.0, 0.35, 0.82, 1.0], "fx.final_tint_amount": 0.0,
				}}],
			})
		LIVING_CONTOUR:
			return _decorate({
				"stable_id": LIVING_CONTOUR,
				"name": "Living Contour",
				"category": "Gold Recipe",
				"description": "A source-alpha-aware eroded contour with clocked noise breakup; transparent space remains transparent.",
				"intent": "Living source contour",
				"operator_ids": ["noise_erosion_border"],
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "LIFE", "label": "Life", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value"}}},
					{"id": "EDGE_DEPTH", "label": "Edge Depth", "fields": ["mask.width_px", "mask.feather_px"], "mapping": {"mask.width_px": {"source": "value"}, "mask.feather_px": {"source": "value", "scale": 0.25}}},
					{"id": "BREAKUP", "label": "Breakup", "fields": ["fx.operator_threshold"], "mapping": {"fx.operator_threshold": {"source": "value"}}},
					{"id": "TURBULENCE", "label": "Turbulence", "fields": ["fx.operator_scale", "fx.operator_speed"], "mapping": {"fx.operator_scale": {"source": "value"}, "fx.operator_speed": {"source": "value"}}},
					{"id": "DRIFT", "label": "Drift", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value"}, "fx.operator_axis_y": {"source": "value"}}},
					{"id": "INTENSITY", "label": "Intensity", "fields": ["fx.operator_strength", "fx.operator_time_source"], "mapping": {"fx.operator_strength": {"source": "value"}, "fx.operator_time_source": {"source": "clock"}}},
				],
				"source_semantics": {"input": "ORIGINAL_SOURCE_ALPHA", "mask_source": "ORIGINAL_SOURCE_ALPHA", "approximation": "NONE"},
				"layers": [{"instance_key": "living_contour", "name": "Living Contour", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "TARGET_LOCAL", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "EDGE_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 18.0, "mask.feather_px": 3.0,
					"fx.operator": "noise_erosion_border", "fx.operator_strength": 0.84, "fx.operator_scale": 1.0, "fx.operator_speed": 1.1, "fx.operator_threshold": 0.48, "fx.operator_softness": 0.12, "fx.operator_time_source": "PRESENTATION_TIME",
				}}],
			})
		SIGNAL_MELT:
			return _decorate({
				"stable_id": SIGNAL_MELT,
				"name": "Signal Melt",
				"category": "Gold Recipe",
				"description": "A directional luminance-run smear that selects from the resolved local input instead of faking motion with RGB separation or dither.",
				"intent": "Directional signal smear",
				"operator_ids": ["pixel_sort_smear"],
				"target_compatibility": {"target_roles": ["echo"], "element_roles": ["echo"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false, "primary_intent": "ECHO"},
				"advanced_access": true,
				"macros": [
					{"id": "MELT", "label": "Melt", "fields": ["fx.operator_strength", "fx.operator_scale"], "mapping": {"fx.operator_strength": {"source": "value"}, "fx.operator_scale": {"source": "value", "min": 0.5, "max": 4.0}}},
					{"id": "THRESHOLD", "label": "Threshold", "fields": ["fx.operator_threshold"], "mapping": {"fx.operator_threshold": {"source": "value"}}},
					{"id": "SOFTNESS", "label": "Softness", "fields": ["fx.operator_softness"], "mapping": {"fx.operator_softness": {"source": "value", "min": 0.01, "max": 0.5}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value"}, "fx.operator_axis_y": {"source": "value"}}},
					{"id": "TURBULENCE", "label": "Turbulence", "fields": ["fx.operator_speed"], "mapping": {"fx.operator_speed": {"source": "value", "min": 0.0, "max": 3.0}}},
					{"id": "CHROMATIC_SPLIT", "label": "Chromatic Split", "fields": ["fx.operator_mix_mode"], "mapping": {"fx.operator_mix_mode": {"source": "mode"}}},
				],
				"source_semantics": {"input": "LOCAL_RESOLVED_INPUT", "approximation": "NONE"},
				"layers": [{"instance_key": "signal_melt", "name": "Signal Melt", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "TARGET_LOCAL", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "pixel_sort_smear", "fx.operator_strength": 0.98, "fx.operator_scale": 2.4, "fx.operator_threshold": 0.32, "fx.operator_softness": 0.08, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_time_source": "PRESENTATION_TIME",
				}}],
			})
		VACUUM_CLASH:
			return _decorate({
				"stable_id": VACUUM_CLASH,
				"name": "Vacuum Clash",
				"category": "Gold Recipe",
				"description": "A radial inward pull and moving burst ring over the captured final frame for clash punctuation.",
				"intent": "Radial clash vacuum",
				"operator_ids": ["vacuum_burst"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "STRENGTH", "label": "Strength", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value"}}},
					{"id": "POLARITY", "label": "Pull / Push", "fields": ["fx.operator_polarity"], "mapping": {"fx.operator_polarity": {"source": "option"}}},
					{"id": "RADIUS", "label": "Radius", "fields": ["fx.operator_scale"], "mapping": {"fx.operator_scale": {"source": "value", "min": 0.5, "max": 3.0}}},
					{"id": "WOBBLE", "label": "Wobble", "fields": ["fx.operator_speed", "fx.operator_distortion"], "mapping": {"fx.operator_speed": {"source": "value"}, "fx.operator_distortion": {"source": "value", "scale": 0.4}}},
					{"id": "DURATION", "label": "Duration", "fields": ["fx.operator_duration"], "mapping": {"fx.operator_duration": {"source": "value", "min": 0.05, "max": 3.0}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "vacuum_clash", "name": "Vacuum Clash", "type": "FX", "authored_fields": {
					"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "vacuum_burst", "fx.operator_anchor": "VS_MARK", "fx.operator_strength": 0.86, "fx.operator_scale": 1.0, "fx.operator_speed": 1.3, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_polarity": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.operator_color_a": [0.25, 0.95, 1.0, 1.0], "fx.operator_color_b": [1.0, 0.35, 0.82, 1.0], "fx.final_tint_amount": 0.0,
				}}],
			})
		CLASH_OVERDRIVE:
			return _decorate({
				"stable_id": CLASH_OVERDRIVE,
				"name": "Clash Overdrive",
				"category": "Gold Recipe",
				"description": "A deliberate ordered final-composite choreography: vacuum anticipation, speedline burst, then patterned breakup and release.",
				"intent": "Full-frame clash overdrive",
				"operator_ids": ["vacuum_burst", "speedlines_field", "pattern_transition"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "IMPACT", "label": "Impact", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value"}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value"}, "fx.operator_axis_y": {"source": "value"}}},
					{"id": "GRAPHIC_BREAKUP", "label": "Graphic Breakup", "fields": ["fx.operator_pattern_family", "fx.operator_progress_start", "fx.operator_progress_end"], "mapping": {"fx.operator_pattern_family": {"source": "option"}, "fx.operator_progress_start": {"source": "value"}, "fx.operator_progress_end": {"source": "value"}}},
					{"id": "DISTORTION", "label": "Distortion", "fields": ["fx.operator_distortion", "fx.operator_mix_mode"], "mapping": {"fx.operator_distortion": {"source": "value"}, "fx.operator_mix_mode": {"source": "mode"}}},
					{"id": "DURATION", "label": "Duration", "fields": ["fx.operator_duration"], "mapping": {"fx.operator_duration": {"source": "value", "min": 0.1, "max": 3.0}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "composition": "VACUUM_SPEEDLINES_PATTERN", "approximation": "NONE"},
				"layers": [
					{"instance_key": "clash_vacuum", "name": "Clash Vacuum Anticipation", "type": "FX", "authored_fields": {
						"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
						"fx.operator": "vacuum_burst", "fx.operator_anchor": "VS_MARK", "fx.operator_strength": 0.86, "fx.operator_scale": 1.0, "fx.operator_speed": 1.3, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_polarity": 0.0, "fx.operator_event_start": 0.0, "fx.operator_duration": 0.42, "fx.operator_time_source": "PRESENTATION_TIME", "fx.final_tint_amount": 0.0,
					}},
					{"instance_key": "clash_speedlines", "name": "Clash Speedline Burst", "type": "FX", "authored_fields": {
						"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
						"fx.operator": "speedlines_field", "fx.operator_anchor": "VS_MARK", "fx.operator_strength": 0.92, "fx.operator_scale": 1.1, "fx.operator_speed": 1.5, "fx.operator_pattern_mode": 0.0, "fx.operator_mix_mode": 2.0, "fx.operator_distortion": 0.28, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_event_start": 0.16, "fx.operator_duration": 0.62, "fx.operator_time_source": "PRESENTATION_TIME", "fx.final_tint_amount": 0.0,
					}},
					{"instance_key": "clash_pattern", "name": "Clash Pattern Breakup", "type": "FX", "authored_fields": {
						"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
						"fx.operator": "pattern_transition", "fx.operator_anchor": "VS_MARK", "fx.operator_strength": 0.78, "fx.operator_scale": 1.0, "fx.operator_speed": 1.0, "fx.operator_pattern_family": 2.0, "fx.operator_progress": 0.0, "fx.operator_progress_start": 0.0, "fx.operator_progress_end": 1.0, "fx.operator_progress_mode": "EVENT_LINEAR", "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.18, "fx.operator_event_start": 0.42, "fx.operator_duration": 0.78, "fx.operator_time_source": "PRESENTATION_TIME", "fx.final_tint_amount": 0.0,
					}},
				],
			})
		PRIMARY_FLAME_ENERGY:
			return _decorate({
				"stable_id": PRIMARY_FLAME_ENERGY,
				"name": "Primary Flame Energy",
				"category": "Hero Recipe",
				"description": "A layered flame-energy wake behind the PRIMARY fighter, combining alpha-gated fringe, flow, a named driver and event motion.",
				"intent": "Behind PRIMARY fighter",
				"target_compatibility": {
					"target_roles": ["primary"],
					"element_roles": ["primary"],
					"allowed_planes": ["TARGET_UNDERLAY"],
					"requires_fighter": true,
				},
				"advanced_access": true,
				"macros": [
					{"id": "FLAME_EDGE", "label": "Flame Edge", "fields": ["fx.fringe", "fx.edge_width", "fx.fringe_bleed"]},
					{"id": "FLAME_FLOW", "label": "Flame Flow", "fields": ["fx.flow", "fx.flow_strength", "fx.driver_mode"]},
					{"id": "FLAME_MOTION", "label": "Impact Motion", "fields": ["motion.enabled.fringe", "motion.enabled.flow"]},
				],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "plane": "TARGET_UNDERLAY"},
				"layers": [
					{
						"instance_key": "flame_fringe",
						"name": "Primary Flame Fringe",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_UNDERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "OUTER_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 10.0, "mask.feather_px": 4.0,
							"fx.fringe": 1.15, "fx.intensity": 1.15, "fx.edge_width": 14.0, "fx.wind_reach": 48.0, "fx.wind_trail": 0.85, "fx.fringe_bleed": 0.90, "fx.edge_source_mode": 0.0,
							"motion.enabled.fringe": true, "motion.tracks.fringe.anchor": "clash_impact", "motion.tracks.fringe.delay": 0.03, "motion.tracks.fringe.attack": 0.08, "motion.tracks.fringe.hold": 0.18, "motion.tracks.fringe.release": 0.34, "motion.tracks.fringe.sustain": 0.85,
						},
					},
					{
						"instance_key": "flame_flow",
						"name": "Primary Flame Flow",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_UNDERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "SCREEN",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 3.0,
							"fx.flow": 1.0, "fx.flow_strength": 2.2, "fx.driver_mode": 8.0, "fx.DRIVER_FLOW": 0.9, "fx.wind_reach": 32.0, "fx.wind_trail": 0.60,
							"displacement.enabled": true, "displacement.driver": "FRINGE_DRIVER", "displacement.amount_px": [7.0, 3.0], "displacement.scale": 1.5, "displacement.speed": 0.85, "displacement.seed": 17,
							"motion.enabled.flow": true, "motion.tracks.flow.anchor": "clash_impact", "motion.tracks.flow.delay": 0.05, "motion.tracks.flow.attack": 0.10, "motion.tracks.flow.hold": 0.20, "motion.tracks.flow.release": 0.40, "motion.tracks.flow.sustain": 0.75,
						},
					},
					{
						"instance_key": "flame_core",
						"name": "Primary Flame Core",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_UNDERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "INNER_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 5.0, "mask.feather_px": 2.0,
							"fx.fringe": 0.55, "fx.flow": 0.55, "fx.intensity": 1.05, "fx.driver_mode": 8.0, "fx.edge_source_mode": 0.0,
							"motion.enabled.fringe": true, "motion.enabled.flow": true, "motion.tracks.fringe.anchor": "fixed", "motion.tracks.flow.anchor": "fixed",
						},
					},
				],
			})
		ORGANIC_SIDE_FIELD:
			return _decorate({
				"stable_id": ORGANIC_SIDE_FIELD,
				"name": "Organic Side Field",
				"category": "Hero Recipe",
				"description": "An irregular side-field treatment driven by the actual source alpha contour, never a rectangle or radial approximation.",
				"intent": "Follow actual irregular side-field source alpha",
				"target_compatibility": {
					"target_roles": ["side_field"],
					"element_roles": ["side_field"],
					"allowed_planes": ["TARGET_SOURCE", "TARGET_OVERLAY"],
					"requires_fighter": false,
				},
				"advanced_access": true,
				"macros": [
					{"id": "ORGANIC_CONTOUR", "label": "Organic Contour", "fields": ["mask.source", "mask.space", "fx.edge_source_mode", "fx.edge_width"]},
					{"id": "ORGANIC_FLOW", "label": "Contour Flow", "fields": ["fx.flow", "fx.flow_strength", "fx.driver_mode"]},
					{"id": "ORGANIC_MOTION", "label": "Field Motion", "fields": ["motion.enabled.fringe", "motion.enabled.flow"]},
				],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "edge_source_mode": "ALPHA", "approximation": "NONE"},
				"layers": [
					{
						"instance_key": "organic_alpha",
						"name": "Organic Alpha Field",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_SOURCE", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "SCREEN",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 1.5,
							"fx.edge_source_mode": 0.0, "fx.edge_alpha_weight": 2.0, "fx.edge_luma_weight": 0.0, "fx.edge_threshold": 0.035, "fx.edge_width": 16.0,
							"fx.fringe": 0.80, "fx.flow": 0.90, "fx.flow_strength": 1.60, "fx.driver_mode": 10.0, "fx.DRIVER_FLOW": 0.80,
							"motion.enabled.fringe": true, "motion.enabled.flow": true, "motion.tracks.fringe.anchor": "hold_enter", "motion.tracks.flow.anchor": "hold_enter", "motion.tracks.fringe.attack": 0.16, "motion.tracks.flow.attack": 0.20,
						},
					},
					{
						"instance_key": "organic_contour",
						"name": "Organic Alpha Contour",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "EDGE_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 7.0, "mask.feather_px": 2.0,
							"fx.edge_source_mode": 0.0, "fx.edge_alpha_weight": 2.5, "fx.edge_luma_weight": 0.0, "fx.edge_threshold": 0.05, "fx.edge_width": 11.0,
							"fx.fringe": 0.65, "fx.flow": 0.45, "fx.flow_strength": 1.20, "fx.driver_mode": 10.0, "fx.wind_reach": 22.0, "fx.wind_trail": 0.30,
							"motion.enabled.fringe": true, "motion.tracks.fringe.anchor": "fixed", "motion.tracks.fringe.attack": 0.12, "motion.tracks.fringe.release": 0.30,
						},
					},
				],
			})
		EDGE_HALO:
			return _decorate({
				"stable_id": EDGE_HALO,
				"name": "Edge Halo",
				"category": "Curated Preset",
				"description": "A restrained alpha-contour halo that clarifies the silhouette without turning the fighter into a glowing cutout.",
				"intent": "Readable silhouette edge",
				"target_compatibility": {"target_roles": ["primary", "secondary"], "element_roles": ["primary", "secondary"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": true},
				"advanced_access": true,
				"macros": [{"id": "HALO_EDGE", "label": "Edge Halo", "fields": ["mask.source", "fx.edge_width", "fx.fringe", "fx.intensity"]}],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "approximation": "NONE"},
				"layers": [{"instance_key": "edge_halo", "name": "Edge Halo", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "EDGE_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 8.0, "mask.feather_px": 3.0,
					"fx.edge_source_mode": 0.0, "fx.edge_width": 9.0, "fx.fringe": 0.65, "fx.intensity": 1.08, "fx.fringe_bleed": 0.55,
				}}],
			})
		RGB_TEAR:
			return _decorate({
				"stable_id": RGB_TEAR,
				"name": "RGB Tear",
				"category": "Curated Preset",
				"description": "A controlled chromatic split for impact and transition moments, with the source alpha kept as the authority.",
				"intent": "Chromatic impact accent",
				"target_compatibility": {"target_roles": ["primary", "secondary"], "element_roles": ["primary", "secondary"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": true},
				"advanced_access": true,
				"macros": [{"id": "RGB_IMPACT", "label": "RGB Impact", "fields": ["fx.rgb", "fx.rgb_shift_amount", "fx.rgb_shift_alpha"]}],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "approximation": "NONE"},
				"layers": [{"instance_key": "rgb_tear", "name": "RGB Tear", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "SCREEN",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 2.0,
					"fx.rgb": 0.78, "fx.rgb_shift_amount": 9.0, "fx.rgb_shift_alpha": 0.35, "fx.intensity": 0.92,
				}}],
			})
		DITHER_TREATMENT:
			return _decorate({
				"stable_id": DITHER_TREATMENT,
				"name": "Dither Treatment",
				"category": "Curated Preset",
				"description": "A small-pixel breakup for graphic texture and controlled degradation, balanced to remain production-readable.",
				"intent": "Graphic texture breakup",
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "DITHER_TEXTURE", "label": "Dither Texture", "fields": ["fx.dither", "fx.dither_pixel", "fx.dither_contrast", "fx.dither_gamma"]}],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "approximation": "NONE"},
				"layers": [{"instance_key": "dither_treatment", "name": "Dither Treatment", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 1.0,
					"fx.dither": 0.55, "fx.dither_pixel": 2.0, "fx.dither_contrast": 1.4, "fx.dither_gamma": 1.25, "fx.intensity": 0.90,
				}}],
			})
	return {}

static func _decorate(recipe: Dictionary) -> Dictionary:
	var out := recipe.duplicate(true)
	var group := "CHARACTER"
	match str(out.get("stable_id", "")):
		KINETIC_RUSH, VACUUM_CLASH:
			group = "MOTION / IMPACT"
		PATTERN_CUT:
			group = "GRAPHIC TRANSITION"
		CLASH_OVERDRIVE:
			group = "SIGNATURE"
		EDGE_HALO, RGB_TEAR, DITHER_TREATMENT:
			group = "BASIC PRESETS"
	out["library_group"] = group
	var all_fields: Dictionary = {}
	for raw_spec in out.get("layers", []):
		var spec: Dictionary = raw_spec
		for path in (spec.get("authored_fields", {}) as Dictionary).keys():
			all_fields["%s.%s" % [str(spec.get("instance_key", "layer")), str(path)]] = (spec["authored_fields"] as Dictionary)[path]
	out["authored_fields"] = all_fields
	out["canonical_fields"] = authored_field_paths_from_recipe(out)
	out["macro_metadata"] = out.get("macros", []).duplicate(true)
	if COMPOSITION_RECIPE_IDS.has(str(out.get("stable_id", ""))):
		out["ownership"] = "COMPOSITION"
		out["composition_passes"] = out.get("layers", []).duplicate(true)
	else:
		out["ownership"] = "TARGET_LOOK"
	return out

static func authored_field_paths_from_recipe(recipe: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for raw_spec in recipe.get("layers", []):
		for path in (raw_spec as Dictionary).get("authored_fields", {}).keys():
			var text := str(path)
			if not seen.has(text):
				seen[text] = true
				out.append(text)
	return out

static func _set_field(layer: Dictionary, path: String, value) -> bool:
	if not _is_supported_field_path(path):
		return false
	var parts := path.split(".")
	if str(parts[0]) == "layer":
		parts = parts.slice(1)
	var cursor: Variant = layer
	for i in range(parts.size() - 1):
		if not (cursor is Dictionary):
			return false
		var dict: Dictionary = cursor
		var key := str(parts[i])
		if not dict.has(key) or not (dict[key] is Dictionary):
			return false
		cursor = dict[key]
	if not (cursor is Dictionary):
		return false
	(cursor as Dictionary)[str(parts[parts.size() - 1])] = value
	return true

static func _get_field(layer: Dictionary, path: String):
	if not _is_supported_field_path(path):
		return null
	var cursor: Variant = layer
	var parts := path.split(".")
	if str(parts[0]) == "layer":
		parts = parts.slice(1)
	for part in parts:
		if not (cursor is Dictionary):
			return null
		var dict: Dictionary = cursor
		if not dict.has(str(part)):
			return null
		cursor = dict[str(part)]
	return cursor

static func _is_supported_field_path(path: String) -> bool:
	var parts := path.split(".")
	if parts.size() < 2:
		return false
	if str(parts[0]) == "layer":
		return parts.size() == 2 and str(parts[1]) in ["plane", "lane", "authority", "input", "blend_mode"]
	return str(parts[0]) in ["transform", "displacement", "mask", "fx", "motion"]

static func _diff_paths(neutral: Dictionary, actual: Dictionary, prefix := "") -> Array:
	var out: Array = []
	for raw_key in neutral.keys():
		var key := str(raw_key)
		if key in ["layer_id", "name", "type"]:
			continue
		if not actual.has(key):
			continue
		var path := key if prefix == "" else prefix + "." + key
		if prefix == "" and key in ["plane", "lane", "authority", "input", "blend_mode"]:
			path = "layer." + key
		var before = neutral[key]
		var after = actual[key]
		if before is Dictionary and after is Dictionary:
			out.append_array(_diff_paths(before, after, path))
		elif not FxLookScript.equivalent(before, after):
			out.append(path)
	return out

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var out := ""
	var previous_separator := false
	for i in range(raw.length()):
		var c := raw[i]
		var valid := (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if valid:
			out += c
			previous_separator = false
		elif not previous_separator:
			out += "-"
			previous_separator = true
		if out.length() >= 48:
			break
	while out.begins_with("-"):
		out = out.substr(1)
	while out.ends_with("-"):
		out = out.substr(0, out.length() - 1)
	return out if out != "" else "key"
