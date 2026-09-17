extends SceneTree
# vNext §12 numeric audit — extremes + malformed non-finite values through the
# REAL production path: FxLook.materialize() (the Look materializer),
# FxLook.validate() (the production validator), FxProduction.apply() (the
# transactional store) and the renderer-facing uniform push
# (FxLayerRenderer._make_quad / _set_fx_uniforms — the exact values that become
# shader parameters). Headless: pure data + material construction, no window.
#
# Contract asserted here (specs/09 §3, specs/10 §1):
#   * a non-finite (NaN / +Inf / -Inf) value anywhere in a Look state is
#     REJECTED with a clear error and never crashes the process;
#   * NaN / Inf can never reach renderer-facing fields;
#   * legal overrange values either survive materialization verbatim or are
#     constrained by an intrinsic domain whose constraint is visible in the
#     materialized output (or in the rejection error for the field).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxCostScript := preload("res://scripts/fx_vnext/fx_cost.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

# Renderer-facing uniforms for the layer fields this audit feeds (see
# fx_layer_renderer.gd _make_quad / _set_fx_uniforms/_set_fx_uniforms).
const RENDER_UNIFORMS := [
	"layer_opacity", "position_px", "layer_scale", "rotation_deg", "pivot",
	"disp_amount_px", "disp_scale", "disp_speed", "disp_phase", "disp_seed", "disp_angle_deg",
	"mask_expand_contract_px", "mask_width_px", "mask_feather_px",
	"fx_size", "fx_intensity", "fx_pattern_scale", "fx_fringe", "fx_rgb", "fx_dither",
	"fx_color_blur", "fx_rgb_shift_px", "fx_rgb_alpha", "fx_edge_width", "fx_flow",
	"fx_wind_reach", "fx_split_separation", "fx_signal_gain",
	"FIELD_SPEED", "DRIVER_SPEED", "flow_strength", "temporal_hold",
]

# fx keys that are legitimately non-numeric in the persisted layer schema.
const FX_STRING_KEYS := ["time_source", "edge_mask_path", "treatment_mask_path"]

var checks: Array = []
var failures: int = 0
var out_dir: String
var prod_dir := "user://vnext_numeric_prod"
var prod

func _init() -> void:
	seed(20260915) # determinism: layer ids embed a random hex suffix
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	prod.ensure_dirs()

	_audit_legal_extremes()
	_audit_intrinsic_domains()
	_audit_non_finite_direct()
	_audit_non_finite_json_path()
	_audit_production_transaction()
	_audit_renderer_facing()

	var f := FileAccess.open(out_dir.path_join("unit_fx_numeric_extremes.log"), FileAccess.WRITE)
	var summary := "[FX-NUMERIC] done · checks=%d failures=%d" % [checks.size(), failures]
	if f != null:
		f.store_string("\n".join(checks) + "\n" + summary + "\n")
		f.close()
	print(summary)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	quit(1 if failures > 0 else 0)

# ================================================================ §12.1 legal extremes

func _audit_legal_extremes() -> void:
	var huge := 3.0e30
	var tiny := 1.0e-6

	var look: Dictionary = FxLookScript.new_look("NUM_EXTREMES", "Numeric Extremes")
	look["status"] = "PRODUCTION"
	var layer: Dictionary = FxLookScript.new_layer("FX", "Extreme FX")
	layer["transform"]["position_px"] = [-huge, huge]
	layer["transform"]["scale"] = [tiny, huge]
	layer["transform"]["rotation_deg"] = 1.0e9
	layer["transform"]["pivot"] = [0.0, 1.0]
	layer["displacement"]["enabled"] = true
	layer["displacement"]["amount_px"] = [huge, -huge]
	layer["displacement"]["scale"] = tiny
	layer["displacement"]["speed"] = 1.0e9
	layer["displacement"]["phase"] = -1.0e9
	layer["displacement"]["angle_deg"] = 1.0e6
	layer["mask"]["enabled"] = true
	layer["mask"]["expand_contract_px"] = -huge
	layer["mask"]["width_px"] = huge
	layer["mask"]["feather_px"] = huge
	layer["fx"]["color_blur"] = huge
	layer["fx"]["fringe"] = huge
	layer["fx"]["rgb"] = huge
	layer["fx"]["dither"] = huge
	layer["fx"]["edge_width"] = huge
	layer["fx"]["rgb_shift_amount"] = huge
	layer["fx"]["rgb_shift_alpha"] = 1.0e-6
	layer["fx"]["FIELD_SPEED"] = 1.0e9
	layer["fx"]["DRIVER_SPEED"] = -1.0e9
	layer["fx"]["flow_strength"] = 1.0e9
	layer["fx"]["temporal_hold"] = 1.0e9
	layer["fx"]["size"] = tiny
	layer["fx"]["intensity"] = tiny
	layer["opacity"] = 1.0e-6
	look["layers"].append(layer)

	var materialized: Dictionary = FxLookScript.materialize(look)
	var check: Dictionary = FxLookScript.validate(materialized)
	_check(bool(check["ok"]), "legal extremes validate", str(check["errors"]))

	var fx: Dictionary = (materialized["layers"][1] as Dictionary)
	var tf: Dictionary = fx["transform"]
	_check(tf["position_px"] == [-huge, huge], "huge negative/positive position survives materialization", str(tf["position_px"]))
	_check(absf(float((tf["scale"] as Array)[0]) - tiny) < 1.0e-12 and absf(float((tf["scale"] as Array)[1]) - huge) < 1.0e12, "near-zero + huge scale survive verbatim", str(tf["scale"]))
	_check(absf(float(tf["rotation_deg"]) - 1.0e9) < 1.0, "huge rotation survives verbatim", str(tf["rotation_deg"]))
	_check(tf["pivot"] == [0.0, 1.0], "pivot domain edges are legal", str(tf["pivot"]))
	var disp: Dictionary = fx["displacement"]
	_check(disp["amount_px"] == [huge, -huge], "huge displacement amount survives verbatim", str(disp["amount_px"]))
	_check(absf(float(disp["scale"]) - tiny) < 1.0e-12, "near-zero displacement scale survives", str(disp["scale"]))
	_check(absf(float(disp["speed"]) - 1.0e9) < 1.0, "extreme motion speed survives verbatim", str(disp["speed"]))
	var mask: Dictionary = fx["mask"]
	_check(absf(float(mask["expand_contract_px"]) + huge) < 1.0e12, "huge negative expand/contract survives (sign is legal here)", str(mask["expand_contract_px"]))
	_check(absf(float(mask["feather_px"]) - huge) < 1.0e12, "huge mask feather survives verbatim", str(mask["feather_px"]))
	_check(absf(float(mask["width_px"]) - huge) < 1.0e12, "huge mask width survives verbatim", str(mask["width_px"]))
	var fxd: Dictionary = fx["fx"]
	_check(absf(float(fxd["color_blur"]) - huge) < 1.0e12, "huge blur radius survives verbatim", str(fxd["color_blur"]))
	_check(absf(float(fxd["rgb_shift_amount"]) - huge) < 1.0e12, "extreme RGB offset survives verbatim", str(fxd["rgb_shift_amount"]))
	_check(absf(float(fxd["FIELD_SPEED"]) - 1.0e9) < 1.0, "extreme field speed survives verbatim", str(fxd["FIELD_SPEED"]))
	_check(absf(float(fxd["size"]) - tiny) < 1.0e-12, "near-zero fx size survives verbatim", str(fxd["size"]))
	_check(absf(float(fx["opacity"]) - 1.0e-6) < 1.0e-9, "near-zero layer opacity survives (domain > 0)", str(fx["opacity"]))

	# Boundaries of the [0,1] opacity domain stay exactly representable.
	var edges: Dictionary = FxLookScript.materialize(_look_with_opacity("NUM_EDGES", 0.0))
	_check(bool(FxLookScript.validate(edges)["ok"]) and float((edges["layers"][1] as Dictionary)["opacity"]) == 0.0, "opacity 0.0 (domain edge) is legal and preserved")

	# Int64 domain: a huge float seed is constrained to an int64 (the constraint
	# is visible in the materialized output — the field stays an integer).
	var seeded: Dictionary = FxLookScript.materialize(_look_with_seed("NUM_SEED", 1.0e30))
	var seed_value = (seeded["layers"][1] as Dictionary)["displacement"]["seed"]
	_check(typeof(seed_value) == TYPE_INT and is_finite(float(seed_value)),
		"huge displacement seed is constrained to the visible int64 domain", "%s (%s)" % [str(seed_value), type_string(typeof(seed_value))])
	_check(bool(FxLookScript.validate(seeded)["ok"]), "constrained seed state validates")

	# A valid JSON number token that is finite but far outside typical ranges
	# (1e308) must survive the JSON path verbatim.
	var json_text: String = _inject_token(str(FxLookScript.to_json(_look_with_rotation("NUM_JSON_BIG", 0.0))), "rotation_deg", "1e308")
	var parsed = JSON.parse_string(json_text)
	_check(parsed is Dictionary and is_finite(float((((parsed as Dictionary)["layers"] as Array)[1] as Dictionary)["transform"]["rotation_deg"])),
		"huge finite JSON token parses to a finite number", str(parsed != null))
	if parsed is Dictionary:
		var big_doc: Dictionary = FxLookScript.materialize(parsed)
		_check(bool(FxLookScript.validate(big_doc)["ok"]), "huge finite JSON value validates")
		_check(absf(float((((big_doc["layers"] as Array)[1] as Dictionary)["transform"] as Dictionary)["rotation_deg"]) - 1.0e308) < 1.0e295,
			"huge finite JSON value survives materialization", str((((big_doc["layers"] as Array)[1] as Dictionary)["transform"] as Dictionary)["rotation_deg"]))

# ================================================================ §12.2 intrinsic domains

func _audit_intrinsic_domains() -> void:
	# Domains that constrain (reject) rather than clamp: the constraint must be
	# visible in the validator error for the exact field.
	var cases := [
		{"label": "opacity above 1", "field": "opacity", "value": 1.5, "needle": "opacity"},
		{"label": "opacity below 0", "field": "opacity", "value": -1.0e9, "needle": "opacity"},
		{"label": "pivot above 1", "field": "pivot", "value": 1.0001, "needle": "pivot"},
		{"label": "pivot below 0", "field": "pivot", "value": -1.0e9, "needle": "pivot"},
		{"label": "zero scale", "field": "scale", "value": 0.0, "needle": "scale"},
		{"label": "negative scale", "field": "scale", "value": -1.0e9, "needle": "scale"},
		{"label": "negative mask width", "field": "mask_width", "value": -1.0e-9, "needle": "width_px"},
		{"label": "negative mask feather", "field": "mask_feather", "value": -1.0e9, "needle": "feather_px"},
		{"label": "zero displacement scale", "field": "disp_scale", "value": 0.0, "needle": "scale"},
		{"label": "revision below 1", "field": "revision", "value": 0, "needle": "revision"},
	]
	for raw in cases:
		var case: Dictionary = raw
		var doc: Dictionary = _look_with_field(str(case["field"]), case["value"])
		var materialized: Dictionary = FxLookScript.materialize(doc)
		var result: Dictionary = FxLookScript.validate(materialized)
		var errors_text := str(result["errors"])
		_check(not bool(result["ok"]) and errors_text.contains(str(case["needle"])),
			"intrinsic domain rejects %s with a field-naming error" % str(case["label"]), errors_text)

# ================================================================ §12.3 non-finite (direct)

func _audit_non_finite_direct() -> void:
	var non_finite := {"NAN": NAN, "INF": INF, "-INF": -INF}
	var fields := [
		{"field": "fx_size", "needle": "fx.size"},
		{"field": "position", "needle": "position_px"},
		{"field": "scale", "needle": "scale"},
		{"field": "pivot", "needle": "pivot"},
		{"field": "rotation", "needle": "rotation_deg"},
		{"field": "disp_amount", "needle": "amount_px"},
		{"field": "disp_scale", "needle": "displacement.scale"},
		{"field": "disp_speed", "needle": "speed"},
		{"field": "mask_width", "needle": "width_px"},
		{"field": "mask_feather", "needle": "feather_px"},
		{"field": "mask_expand", "needle": "expand_contract_px"},
		{"field": "motion_attack", "needle": "motion"},
		{"field": "blur", "needle": "fx.color_blur"},
		{"field": "rgb_shift", "needle": "fx.rgb_shift_amount"},
		{"field": "field_speed", "needle": "FIELD_SPEED"},
	]
	var escaped: Array = []
	for raw in fields:
		var case: Dictionary = raw
		var missed: Array = []
		for label in non_finite.keys():
			var doc: Dictionary = _look_with_field(str(case["field"]), non_finite[label])
			var materialized: Dictionary = FxLookScript.materialize(doc)
			var result: Dictionary = FxLookScript.validate(materialized)
			if bool(result["ok"]):
				missed.append(str(label))
			elif not str(result["errors"]).contains(str(case["needle"])):
				missed.append("%s(mislabeled)" % str(label))
		if not missed.is_empty():
			escaped.append("%s←%s" % [str(case["field"]), str(missed)])
		_check(missed.is_empty(), "non-finite %s is rejected for NAN/INF/-INF" % str(case["field"]), str(missed))
	_check(escaped.is_empty(), "every validated numeric field rejects all three non-finite values", str(escaped))

	# The validator itself must survive a document that is saturated with
	# non-finite values instead of crashing.
	var saturated: Dictionary = FxLookScript.new_look("NUM_SATURATED", "Saturated")
	saturated["status"] = "PRODUCTION"
	var layer: Dictionary = FxLookScript.new_layer("FX", "Saturated FX")
	layer["opacity"] = INF
	layer["transform"]["position_px"] = [NAN, INF]
	layer["transform"]["scale"] = [-INF, INF]
	layer["transform"]["rotation_deg"] = NAN
	layer["displacement"]["amount_px"] = [NAN, NAN]
	layer["displacement"]["speed"] = INF
	layer["mask"]["feather_px"] = -INF
	layer["fx"]["size"] = NAN
	layer["fx"]["fringe_color_a"] = [NAN, INF, -INF, 1.0]
	layer["motion"]["tracks"]["dither"]["attack"] = NAN
	saturated["layers"].append(layer)
	var saturated_check: Dictionary = FxLookScript.validate(FxLookScript.materialize(saturated))
	_check(not bool(saturated_check["ok"]) and (saturated_check["errors"] as Array).size() >= 8,
		"a fully non-finite document reports one error per affected field (no crash)", "n=%d" % (saturated_check["errors"] as Array).size())

	# §12-FINDING candidate: NaN opacity is invisible to the range test
	# (`if opacity < 0.0 or opacity > 1.0` is false for NaN), so a non-finite
	# layer_opacity can pass validation and reach the renderer.
	var nan_opacity: Dictionary = FxLookScript.materialize(_look_with_opacity("NUM_NAN_OPACITY", NAN))
	var nan_result: Dictionary = FxLookScript.validate(nan_opacity)
	_check(not bool(nan_result["ok"]),
		"§12-FINDING: NaN layer opacity is rejected by the validator (renderer-facing layer_opacity)",
		"validate=%s opacity=%s" % [str(nan_result["ok"]), str((nan_opacity["layers"][1] as Dictionary)["opacity"])])

# ================================================================ §12.4 non-finite (JSON path)

func _audit_non_finite_json_path() -> void:
	# Real JSON text: inject a raw overflowing number token (`1e400` parses to
	# +Inf in Godot's JSON) and a plain malformed token, then run the exact
	# production read path.
	var base_text: String = str(FxLookScript.to_json(_look_with_rotation("NUM_JSON", 0.0)))
	var injections := [
		{"key": "rotation_deg", "token": "1e400", "field": "transform.rotation_deg"},
		{"key": "rotation_deg", "token": "-1e400", "field": "transform.rotation_deg"},
		{"key": "feather_px", "token": "1e400", "field": "mask.feather_px"},
		{"key": "width_px", "token": "1e999", "field": "mask.width_px"},
		{"key": "speed", "token": "-1e400", "field": "displacement.speed"},
		{"key": "opacity", "token": "1e400", "field": "opacity"},
		{"key": "size", "token": "1e309", "field": "fx.size"},
		{"key": "angle_deg", "token": "1e400", "field": "displacement.angle_deg"},
	]
	for raw in injections:
		var injection: Dictionary = raw
		var text := _inject_token(base_text, str(injection["key"]), str(injection["token"]))
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			_check(false, "JSON injection %s:%s parses" % [str(injection["key"]), str(injection["token"])], "parse failed")
			continue
		var doc: Dictionary = parsed
		var raw_value = _value_at(doc, str(injection["field"]))
		_check(raw_value is float and not is_finite(float(raw_value)),
			"raw token %s becomes a non-finite float through the real JSON parser" % str(injection["token"]), "%s=%s" % [str(injection["field"]), str(raw_value)])
		var result: Dictionary = FxLookScript.validate(FxLookScript.materialize(doc))
		_check(not bool(result["ok"]), "JSON-path non-finite %s is rejected by the validator" % str(injection["field"]), str(result["errors"]))

	# Raw `nan` / `inf` / `-inf` / `Infinity` tokens are not JSON numbers: the
	# production reader must report an unreadable document (recovery required)
	# instead of guessing a value.
	var prod_json = FxProductionScript.new()
	prod_json.data_dir = "user://vnext_numeric_json"
	_wipe_dir(ProjectSettings.globalize_path(prod_json.data_dir))
	prod_json.ensure_dirs()
	for token in ["nan", "NaN", "inf", "-inf", "Infinity", "-Infinity"]:
		var text := _inject_token(base_text, "rotation_deg", str(token))
		var path := prod_json.look_path("NUM_TOKEN")
		_write_text(ProjectSettings.globalize_path(path), text)
		Engine.print_error_messages = false
		var loaded: Dictionary = prod_json.load_look("NUM_TOKEN")
		var state: Dictionary = prod_json.production_state()
		Engine.print_error_messages = true
		var bytes_before := _file_bytes(ProjectSettings.globalize_path(path))
		_check(not bool(loaded["ok"]) and bool(loaded["recovery_required"]),
			"raw %s token in a look file is reported unreadable (recovery required)" % str(token), str(loaded["errors"]))
		_check(_file_bytes(ProjectSettings.globalize_path(path)) == bytes_before, "raw %s token leaves the file byte-identical" % str(token))
		_check(not bool(state["ok"]), "production_state flags the unreadable look (%s)" % str(token), str(state["errors"]))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ================================================================ §12.5 production transaction

func _audit_production_transaction() -> void:
	# A legal extreme look must commit and round-trip through the JSON store.
	var look: Dictionary = FxLookScript.new_look("NUM_COMMIT", "Commit Extremes")
	look["status"] = "PRODUCTION"
	var layer: Dictionary = FxLookScript.new_layer("FX", "Commit FX")
	layer["transform"]["position_px"] = [-3.0e30, 3.0e30]
	layer["transform"]["scale"] = [1.0e-6, 1.0e30]
	layer["displacement"]["amount_px"] = [3.0e30, -3.0e30]
	layer["displacement"]["speed"] = 1.0e9
	layer["mask"]["feather_px"] = 3.0e30
	layer["fx"]["color_blur"] = 3.0e30
	layer["fx"]["rgb_shift_amount"] = 3.0e30
	layer["opacity"] = 0.5
	look["layers"].append(layer)
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "legal extreme look commits to Production", str(applied.get("errors", [])))
	var loaded: Dictionary = prod.load_look("NUM_COMMIT")
	_check(bool(loaded["ok"]), "committed extreme look reloads", str(loaded.get("errors", [])))
	var reloaded: Array = (loaded.get("doc", {}) as Dictionary).get("layers", [])
	var reloaded_layer: Dictionary = reloaded[1] if reloaded.size() > 1 else {}
	var reloaded_rot: float = 0.0
	if not reloaded_layer.is_empty():
		reloaded_rot = float((reloaded_layer["transform"] as Dictionary)["position_px"][0])
	_check(absf(reloaded_rot + 3.0e30) < 1.0e20, "huge position round-trips through the JSON store", str(reloaded_rot))
	_check(_non_finite_in(loaded.get("doc", {})) == 0, "reloaded extreme look contains no non-finite value", str(_non_finite_in(loaded.get("doc", {}))))

	# A non-finite candidate must be rejected before anything is written, and a
	# rejected apply must leave the previous authority byte-identical.
	var good_bytes := _file_bytes(ProjectSettings.globalize_path(prod.look_path("NUM_COMMIT")))
	var bad: Dictionary = FxLookScript.new_look("NUM_COMMIT", "Commit Extremes")
	bad["status"] = "PRODUCTION"
	bad["revision"] = 2
	var bad_layer: Dictionary = FxLookScript.new_layer("FX", "Bad FX")
	bad_layer["fx"]["size"] = INF
	bad["layers"].append(bad_layer)
	var rejected: Dictionary = prod.apply({"look": bad})
	_check(not bool(rejected["ok"]) and str(rejected.get("stage", "")) == "validate-look", "non-finite apply is rejected at validate-look", str(rejected.get("stage", "")))
	_check(str(rejected.get("errors", [])).contains("non-finite"), "rejection names the non-finite field", str(rejected.get("errors", [])))
	_check(_file_bytes(ProjectSettings.globalize_path(prod.look_path("NUM_COMMIT"))) == good_bytes, "rejected apply leaves Production byte-identical")
	_check(not FileAccess.file_exists(prod.look_path("NUM_COMMIT") + ".tmp"), "rejected apply leaves no .tmp candidate")

	# A document saturated with non-finite values must be rejected as a whole.
	var saturated: Dictionary = FxLookScript.new_look("NUM_SAT2", "Saturated 2")
	saturated["status"] = "PRODUCTION"
	var s_layer: Dictionary = FxLookScript.new_layer("FX", "Sat FX")
	s_layer["transform"]["scale"] = [NAN, 1.0]
	s_layer["mask"]["feather_px"] = -INF
	saturated["layers"].append(s_layer)
	var s_rejected: Dictionary = prod.apply({"look": saturated})
	_check(not bool(s_rejected["ok"]) and not FileAccess.file_exists(prod.look_path("NUM_SAT2")), "saturated non-finite look is never persisted")
	_check(not FileAccess.file_exists(prod.look_path("NUM_SAT2") + ".tmp"), "saturated non-finite look leaves no candidate")

	# NaN opacity: the validator misses it (§12-FINDING above), so the failure
	# must at minimum be caught by the candidate re-read and must stay safe.
	var nan_look: Dictionary = _look_with_opacity("NUM_NAN_COMMIT", NAN)
	nan_look["status"] = "PRODUCTION"
	Engine.print_error_messages = false
	var nan_applied: Dictionary = prod.apply({"look": nan_look})
	Engine.print_error_messages = true
	_check(not bool(nan_applied["ok"]), "NaN-opacity apply does not reach Production", str(nan_applied.get("stage", "")))
	_check(not FileAccess.file_exists(prod.look_path("NUM_NAN_COMMIT")) and not FileAccess.file_exists(prod.look_path("NUM_NAN_COMMIT") + ".tmp"),
		"NaN-opacity apply writes no look and no leftover")
	_check(_file_bytes(ProjectSettings.globalize_path(prod.look_path("NUM_COMMIT"))) == good_bytes, "NaN-opacity apply never touches unrelated Production data")
	_check(str(nan_applied.get("errors", [])).contains("opacity") or str(nan_applied.get("errors", [])).contains("non-finite"),
		"§12-FINDING: NaN-opacity apply reports the offending field (not a schema-shaped error)",
		str(nan_applied.get("stage", "")) + " " + str(nan_applied.get("errors", [])))

	# The cost estimator consumes the same values: extremes must stay finite.
	var extreme_cost: Dictionary = FxCostScript.look_cost(FxLookScript.materialize(look))
	_check(is_finite(float(extreme_cost.get("total", -1.0))) and float(extreme_cost.get("total", 0.0)) >= 1.0,
		"cost estimator stays finite for extreme values", str(extreme_cost.get("total", 0.0)))

# ================================================================ §12.6 renderer-facing

func _audit_renderer_facing() -> void:
	var renderer = FxLayerRendererScript.new(null, null)
	_check(renderer._shader != null, "layer shader loads headless", "res://shaders/nrcu_fx_vnext_layer.gdshader")
	var canonical := TextureRect.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2i(1280, 720)
	canonical.texture = tex
	canonical.size = Vector2(1280, 720)

	# Legal extremes through the exact uniform push the renderer uses.
	var layer: Dictionary = FxLookScript.new_layer("FX", "Renderer Extremes")
	layer["transform"]["position_px"] = [3.0e30, -3.0e30]
	layer["transform"]["scale"] = [1.0e-6, 1.0e30]
	layer["transform"]["rotation_deg"] = 1.0e9
	layer["displacement"]["amount_px"] = [3.0e30, -3.0e30]
	layer["displacement"]["speed"] = 1.0e9
	layer["displacement"]["phase"] = -1.0e9
	layer["mask"]["enabled"] = true
	layer["mask"]["expand_contract_px"] = -3.0e30
	layer["mask"]["width_px"] = 3.0e30
	layer["mask"]["feather_px"] = 3.0e30
	layer["fx"]["size"] = 3.0e30
	layer["fx"]["intensity"] = 1.0e-6
	layer["fx"]["color_blur"] = 3.0e30
	layer["fx"]["rgb_shift_amount"] = 3.0e30
	layer["fx"]["rgb_shift_alpha"] = 1.0e-6
	layer["fx"]["FIELD_SPEED"] = 1.0e9
	layer["fx"]["temporal_hold"] = 1.0e9
	var materialized: Dictionary = FxLookScript.materialize(layer)
	var quad: Control = renderer._make_quad(canonical, Rect2(0.0, 0.0, 1280.0, 720.0), Color.WHITE, materialized)
	_check(quad != null and quad.material is ShaderMaterial, "renderer builds a quad for an extreme layer")
	var material: ShaderMaterial = quad.material as ShaderMaterial
	var report: Dictionary = _uniform_report(material, RENDER_UNIFORMS)
	_check((report["non_finite"] as Array).is_empty(), "no non-finite uniform for legal extreme values", str(report["non_finite"]))
	_check((report["missing"] as Array).is_empty(), "every renderer-facing uniform is present", str(report["missing"]))
	_check(not _collect_numeric_fields(materialized).is_empty(), "extreme layer exposes numeric renderer fields")

	# Same push with a fully saturated non-finite layer: the renderer must not
	# crash (the validator is the gate that keeps such a layer out of the lab).
	var poisoned: Dictionary = FxLookScript.new_layer("FX", "Poisoned")
	poisoned["fx"]["size"] = NAN
	poisoned["transform"]["position_px"] = [NAN, 0.0]
	var poisoned_quad: Control = renderer._make_quad(canonical, Rect2(0.0, 0.0, 1280.0, 720.0), Color.WHITE, poisoned)
	_check(poisoned_quad != null and poisoned_quad.material is ShaderMaterial, "renderer survives a poisoned layer without crashing")

	# §12-FINDING: the NaN that the validator missed reaches the renderer.
	var nan_layer: Dictionary = _look_with_opacity("NUM_RENDER_NAN", NAN)["layers"][1]
	var nan_quad: Control = renderer._make_quad(canonical, Rect2(0.0, 0.0, 1280.0, 720.0), Color.WHITE, nan_layer)
	var nan_material: ShaderMaterial = nan_quad.material as ShaderMaterial
	var nan_opacity = nan_material.get_shader_parameter("layer_opacity")
	_check(not (nan_opacity is float and not is_finite(float(nan_opacity))),
		"§12-FINDING: NaN layer opacity never reaches the renderer-facing uniform",
		"layer_opacity=%s" % str(nan_opacity))

	# Non-numeric junk in a numeric fx field: materialization is a PURE normalizer
	# (R3 §12) — it must not silently repair hostile values; the VALIDATOR is the
	# gate that rejects them and the renderer carries its own finite gate. This
	# preserves the apply pipeline's reject-on-hostile-input semantics.
	var junk: Dictionary = FxLookScript.materialize(_look_with_junk_fx("NUM_JUNK", "intensity"))
	var junk_check: Dictionary = FxLookScript.validate(junk)
	_check(not bool(junk_check.get("ok", true)), "§12-FINDING: junk fx value is rejected by the validator (not silently repaired)", str(junk_check.get("errors", [])))
	_check((junk["layers"][1] as Dictionary)["fx"].has("intensity"), "junk fx document keeps its field identity", str((junk["layers"][1] as Dictionary)["fx"].get("intensity", "?")))

	# Free the off-tree probes so the engine exits without ResourceDB noise.
	for node in [quad, poisoned_quad, nan_quad]:
		if node != null and is_instance_valid(node):
			node.free()
	canonical.free()

# ================================================================ helpers

func _look_with_opacity(look_id: String, value: float) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, "Opacity Case")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Opacity FX")
	layer["opacity"] = value
	look["layers"].append(layer)
	return look

func _look_with_seed(look_id: String, value: float) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, "Seed Case")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Seed FX")
	layer["displacement"]["seed"] = value
	look["layers"].append(layer)
	return look

func _look_with_rotation(look_id: String, value) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, "Rotation Case")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Rotation FX")
	layer["transform"]["rotation_deg"] = value
	look["layers"].append(layer)
	return look

func _look_with_junk_fx(look_id: String, key: String) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, "Junk FX Case")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Junk FX")
	layer["fx"][key] = "not-a-number"
	look["layers"].append(layer)
	return look

func _look_with_field(field: String, value) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look("NUM_FIELD", "Field Case")
	var layer: Dictionary = FxLookScript.new_layer("FX", "Field FX")
	match field:
		"opacity": layer["opacity"] = value
		"pivot": layer["transform"]["pivot"] = [value, 0.5]
		"scale": layer["transform"]["scale"] = [value, 1.0]
		"position": layer["transform"]["position_px"] = [value, 0.0]
		"rotation": layer["transform"]["rotation_deg"] = value
		"disp_amount": layer["displacement"]["amount_px"] = [value, 0.0]
		"disp_scale": layer["displacement"]["scale"] = value
		"disp_speed": layer["displacement"]["speed"] = value
		"mask_width": layer["mask"]["width_px"] = value
		"mask_feather": layer["mask"]["feather_px"] = value
		"mask_expand": layer["mask"]["expand_contract_px"] = value
		"motion_attack": layer["motion"]["tracks"]["dither"]["attack"] = value
		"fx_size": layer["fx"]["size"] = value
		"blur": layer["fx"]["color_blur"] = value
		"rgb_shift": layer["fx"]["rgb_shift_amount"] = value
		"field_speed": layer["fx"]["FIELD_SPEED"] = value
		"revision": look["revision"] = value
		_: pass
	look["layers"].append(layer)
	return look

func _inject_token(json_text: String, key: String, token: String) -> String:
	# Rewrites `<"key": number>` in the serialized Look so the production reader
	# sees the raw token exactly as a hand-edited or corrupt file would.
	var re := RegEx.new()
	re.compile("\"%s\"\\s*:\\s*[-+0-9.eE]+" % key)
	return re.sub(json_text, "\"%s\": %s" % [key, token], true)

func _value_at(doc: Dictionary, field: String):
	# Layer-level path lookup (all audited fields live on layer index 1).
	var layers: Array = doc.get("layers", [])
	if layers.size() < 2:
		return null
	var cursor = layers[1]
	for part in field.split("."):
		if cursor is Dictionary:
			cursor = (cursor as Dictionary).get(part, null)
		else:
			return null
	return cursor

func _collect_numeric_fields(value, path := "") -> Array:
	var out: Array = []
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			out.append_array(_collect_numeric_fields((value as Dictionary)[key], path + "/" + str(key)))
	elif value is Array:
		var index := 0
		for item in (value as Array):
			out.append_array(_collect_numeric_fields(item, path + "/" + str(index)))
			index += 1
	elif value is float or value is int:
		out.append({"path": path, "value": float(value)})
	return out

func _non_finite_in(value) -> int:
	var bad := 0
	for entry in _collect_numeric_fields(value):
		if not is_finite(float((entry as Dictionary)["value"])):
			bad += 1
	return bad

func _uniform_report(material: ShaderMaterial, names: Array) -> Dictionary:
	var non_finite: Array = []
	var missing: Array = []
	for name in names:
		var value = material.get_shader_parameter(str(name))
		if value == null:
			missing.append(str(name))
			continue
		for entry in _collect_numeric_fields(value, str(name)):
			if not is_finite(float((entry as Dictionary)["value"])):
				non_finite.append("%s=%s" % [str((entry as Dictionary)["path"]), str((entry as Dictionary)["value"])])
	return {"non_finite": non_finite, "missing": missing}

func _non_numeric_render_fields(doc: Dictionary) -> Array:
	# Renderer numeric fields must be numbers (or numeric arrays) after
	# materialization; only the documented string keys may stay strings.
	var out: Array = []
	var layers: Array = doc.get("layers", [])
	if layers.size() < 2:
		return out
	var fx: Dictionary = (layers[1] as Dictionary).get("fx", {})
	for key in fx.keys():
		if FX_STRING_KEYS.has(str(key)):
			continue
		var value = fx[key]
		if value == null or value is bool or value is int or value is float:
			continue
		if value is Array:
			var numeric := true
			for item in (value as Array):
				if not (item is int or item is float):
					numeric = false
			if numeric:
				continue
		out.append("%s=%s (%s)" % [str(key), str(value), type_string(typeof(value))])
	return out

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _wipe_dir(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	for file_name in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs_path):
		_wipe_dir(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)

func _file_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
