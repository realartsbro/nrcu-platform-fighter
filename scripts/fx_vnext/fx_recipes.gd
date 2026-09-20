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
	return {
		"ok": true,
		"errors": [],
		"recipe_id": recipe_id,
		"instance_key": key,
		"layers": layers,
		"layer_ids": layers.map(func(layer): return str((layer as Dictionary).get("layer_id", ""))),
	}

static func instantiate_look(recipe_id: String, look_id: String, look_name: String, instance_key: String) -> Dictionary:
	var result := instantiate(recipe_id, instance_key)
	if not bool(result.get("ok", false)):
		return result
	var look := FxLookScript.new_look(look_id, look_name)
	look["layers"].append_array(result["layers"])
	look = FxLookScript.materialize(look)
	var validation := FxLookScript.validate_input(look)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "errors": validation.get("errors", []), "layers": result["layers"], "look": look}
	result["look"] = look
	return result

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
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "KINETIC_FIELD", "label": "Kinetic Field", "fields": ["fx.operator_strength", "fx.operator_scale", "fx.operator_speed", "fx.operator_pattern_mode", "fx.operator_mix_mode", "fx.operator_distortion", "fx.operator_center_x", "fx.operator_center_y", "fx.operator_axis_x", "fx.operator_axis_y", "fx.operator_time_source"]}],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "kinetic_speedlines", "name": "Kinetic Speedlines", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "FINAL_COMPOSITE", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "speedlines_field", "fx.operator_strength": 0.72, "fx.operator_scale": 1.0, "fx.operator_speed": 1.25, "fx.operator_pattern_mode": 0.0, "fx.operator_mix_mode": 2.0, "fx.operator_distortion": 0.24, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.final_tint_amount": 0.0,
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
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "PATTERN_CUT", "label": "Pattern Cut", "fields": ["fx.operator_strength", "fx.operator_scale", "fx.operator_speed", "fx.operator_pattern_family", "fx.operator_progress", "fx.operator_axis_x", "fx.operator_axis_y", "fx.operator_time_source", "fx.operator_color_a", "fx.operator_color_b"]}],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "pattern_cut", "name": "Pattern Cut", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "FINAL_COMPOSITE", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "pattern_transition", "fx.operator_strength": 0.78, "fx.operator_scale": 1.0, "fx.operator_speed": 1.0, "fx.operator_pattern_family": 1.0, "fx.operator_progress": 0.5, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.18, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.operator_color_a": [0.25, 0.95, 1.0, 1.0], "fx.operator_color_b": [1.0, 0.35, 0.82, 1.0], "fx.final_tint_amount": 0.0,
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
				"macros": [{"id": "LIVING_CONTOUR", "label": "Living Contour", "fields": ["fx.operator_strength", "fx.operator_scale", "fx.operator_speed", "fx.operator_threshold", "fx.operator_time_source"]}],
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
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "SIGNAL_MELT", "label": "Signal Melt", "fields": ["fx.operator_strength", "fx.operator_scale", "fx.operator_threshold", "fx.operator_axis_x", "fx.operator_axis_y", "fx.operator_time_source"]}],
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
				"target_compatibility": {"target_roles": ["primary", "secondary"], "element_roles": ["primary", "secondary"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "VACUUM_CLASH", "label": "Vacuum Clash", "fields": ["fx.operator_strength", "fx.operator_scale", "fx.operator_speed", "fx.operator_center_x", "fx.operator_center_y", "fx.operator_polarity", "fx.operator_time_source", "fx.operator_color_a", "fx.operator_color_b"]}],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "vacuum_clash", "name": "Vacuum Clash", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "FINAL_COMPOSITE", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "vacuum_burst", "fx.operator_strength": 0.86, "fx.operator_scale": 1.0, "fx.operator_speed": 1.3, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_polarity": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.operator_color_a": [0.25, 0.95, 1.0, 1.0], "fx.operator_color_b": [1.0, 0.35, 0.82, 1.0], "fx.final_tint_amount": 0.0,
				}}],
			})
		CLASH_OVERDRIVE:
			return _decorate({
				"stable_id": CLASH_OVERDRIVE,
				"name": "Clash Overdrive",
				"category": "Gold Recipe",
				"description": "A deliberate final-composite combination of vacuum pull and radial speedline energy, kept as one authored lane.",
				"intent": "Full-frame clash overdrive",
				"operator_ids": ["speedlines_field", "vacuum_burst"],
				"target_compatibility": {"target_roles": ["primary", "secondary"], "element_roles": ["primary", "secondary"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "CLASH_OVERDRIVE", "label": "Clash Overdrive", "fields": ["fx.operator", "fx.operator_secondary", "fx.operator_strength", "fx.operator_scale", "fx.operator_speed", "fx.operator_time_source"]}],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "composition": "SPEEDLINES_PLUS_VACUUM", "approximation": "NONE"},
				"layers": [{"instance_key": "clash_overdrive", "name": "Clash Overdrive", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "FINAL_COMPOSITE", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "speedlines_field", "fx.operator_secondary": "vacuum_burst", "fx.operator_strength": 0.92, "fx.operator_scale": 1.1, "fx.operator_speed": 1.5, "fx.operator_pattern_mode": 0.0, "fx.operator_mix_mode": 2.0, "fx.operator_distortion": 0.28, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_polarity": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.final_tint_amount": 0.0,
				}}],
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
		return parts.size() == 2 and str(parts[1]) in ["plane", "lane", "input", "blend_mode"]
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
		if prefix == "" and key in ["plane", "lane", "input", "blend_mode"]:
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
