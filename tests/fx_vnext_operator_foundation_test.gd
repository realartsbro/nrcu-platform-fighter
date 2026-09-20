extends SceneTree
# Phase 8 supplemental-operator foundation (headless).
# These tests prove contracts and honest capability declarations only. They do
# not claim a visual or live-runtime proof for unsupported lanes/operators.

const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxCostScript := preload("res://scripts/fx_vnext/fx_cost.gd")

const EXPECTED_SUPPLEMENTAL_OPERATOR_IDS := [
	"manga_impact",
	"speedlines_field",
	"pattern_transition",
	"vacuum_burst",
	"pixel_sort_smear",
	"perimeter_flux",
	"noise_erosion_border",
	"contour_pulse",
	"silhouette_extrude",
	"print_misregistration",
	"halftone_reveal",
	"dither_inversion",
	"slice_tear",
	"hit_flash",
	"mesh_smear",
	"multi_impact_field",
	"slash_arc",
	"world_outline_depth",
	"world_outline_depth_normal",
]

const EXPECTED_OPERATOR_IDS := [
	"source_copy",
	"transform",
	"displacement",
	"mask",
	"base_treatment",
	"grade",
	"source_pixelation",
	"mono_stamp",
	"dither",
	"palette",
	"edge",
	"fringe",
	"rgb",
	"flow",
	"motion_envelope",
	"manga_impact",
	"speedlines_field",
	"pattern_transition",
	"vacuum_burst",
	"pixel_sort_smear",
	"perimeter_flux",
	"noise_erosion_border",
	"contour_pulse",
	"silhouette_extrude",
	"print_misregistration",
	"halftone_reveal",
	"dither_inversion",
	"slice_tear",
	"hit_flash",
	"mesh_smear",
	"multi_impact_field",
	"slash_arc",
	"world_outline_depth",
	"world_outline_depth_normal",
	"final_composite",
	"deferred_3d",
]

const EXPECTED_SCOPE_BY_ID := {
	"manga_impact": "FINAL_COMPOSITE",
	"speedlines_field": "FINAL_COMPOSITE",
	"pattern_transition": "FINAL_COMPOSITE",
	"vacuum_burst": "FINAL_COMPOSITE",
	"perimeter_flux": "LOCAL",
	"noise_erosion_border": "LOCAL",
	"pixel_sort_smear": "LOCAL",
	"contour_pulse": "LOCAL",
	"silhouette_extrude": "LOCAL",
	"print_misregistration": "FINAL_COMPOSITE",
	"halftone_reveal": "LOCAL",
	"dither_inversion": "FINAL_COMPOSITE",
	"slice_tear": "FINAL_COMPOSITE",
	"hit_flash": "DEFERRED_3D",
	"mesh_smear": "DEFERRED_3D",
	"multi_impact_field": "DEFERRED_3D",
	"slash_arc": "DEFERRED_3D",
	"world_outline_depth": "DEFERRED_3D",
	"world_outline_depth_normal": "DEFERRED_3D",
}

const EXPECTED_STATUS_BY_ID := {
	"manga_impact": "UNSUPPORTED",
	"speedlines_field": "SUPPORTED",
	"pattern_transition": "SUPPORTED",
	"vacuum_burst": "SUPPORTED",
	"perimeter_flux": "UNSUPPORTED",
	"noise_erosion_border": "ADAPTER_ONLY",
	"pixel_sort_smear": "ADAPTER_ONLY",
	"contour_pulse": "UNSUPPORTED",
	"silhouette_extrude": "UNSUPPORTED",
	"print_misregistration": "UNSUPPORTED",
	"halftone_reveal": "UNSUPPORTED",
	"dither_inversion": "UNSUPPORTED",
	"slice_tear": "UNSUPPORTED",
	"hit_flash": "DEFERRED",
	"mesh_smear": "DEFERRED",
	"multi_impact_field": "DEFERRED",
	"slash_arc": "DEFERRED",
	"world_outline_depth": "DEFERRED",
	"world_outline_depth_normal": "DEFERRED",
}

var checks := 0
var failures := 0

func _init() -> void:
	_registry_is_complete_and_typed()
	_supplemental_scope_status_contract()
	_raw_time_paths_use_supplied_clock()
	_lanes_are_explicit_and_fail_closed()
	_neutral_contract_is_truthful()
	_cost_fields_are_truthful_and_deterministic()
	print("[FX-OPERATOR-FOUNDATION] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _registry_is_complete_and_typed() -> void:
	var ids: Array = FxOperatorsScript.operator_ids()
	var registry: Dictionary = FxOperatorsScript.registry()
	_check(ids == EXPECTED_OPERATOR_IDS, "operator registry has exact stable completeness", "expected=%s actual=%s" % [str(EXPECTED_OPERATOR_IDS), str(ids)])
	var sorted_ids: Array = registry.keys()
	sorted_ids.sort()
	var sorted_expected: Array = EXPECTED_OPERATOR_IDS.duplicate()
	sorted_expected.sort()
	_check(sorted_ids == sorted_expected, "registry keys exactly match stable operator ids", "expected=%s actual=%s" % [str(sorted_expected), str(sorted_ids)])
	_check(not ids.is_empty(), "operator registry declares named operators")
	_check(registry.size() == ids.size(), "operator registry has one entry per named id", str(registry.size()))
	var registry_result: Dictionary = FxOperatorsScript.validate_registry()
	_check(bool(registry_result.get("ok", false)), "operator registry satisfies its contract", str(registry_result.get("errors", [])))
	var required := [
		"operator_id", "scope", "time_source", "time_source_support",
		"neutral_proven", "authoring_reachable", "persistence_proven",
		"runtime_observable", "cost_class", "test_evidence_reference", "lane",
		"semantic_notes", "status",
	]
	for operator_id in ids:
		var entry: Dictionary = registry.get(str(operator_id), {})
		for key in required:
			_check(entry.has(key), "%s has %s" % [str(operator_id), key])
		_check(str(entry.get("operator_id", "")) == str(operator_id), "%s id is stable" % str(operator_id))
		_check(str(entry.get("scope", "")) in FxOperatorsScript.SCOPES, "%s scope is explicit" % str(operator_id))
		var expected_lane := "TARGET_LOCAL" if str(entry.get("scope", "")) == "LOCAL" else str(entry.get("scope", ""))
		_check(str(entry.get("lane", "")) == expected_lane, "%s lane is explicit" % str(operator_id))
		_check(str(entry.get("cost_class", "")) in FxOperatorsScript.COST_CLASSES, "%s cost class is named" % str(operator_id))
		_check(entry.get("time_source") is String, "%s has a default time source" % str(operator_id))
		_check(entry.get("time_source_support") is Array, "%s has time-source support" % str(operator_id))
		_check(not (entry.get("semantic_notes", "") as String).strip_edges().is_empty(), "%s has semantic notes" % str(operator_id))
		for flag in ["neutral_proven", "authoring_reachable", "persistence_proven", "runtime_observable"]:
			_check(entry.get(flag) is bool, "%s %s is boolean" % [str(operator_id), flag])

func _supplemental_scope_status_contract() -> void:
	var registry: Dictionary = FxOperatorsScript.registry()
	for operator_id in EXPECTED_SUPPLEMENTAL_OPERATOR_IDS:
		var entry: Dictionary = registry.get(operator_id, {})
		_check(entry.has("operator_id"), "%s is explicitly registered" % operator_id)
		_check(str(entry.get("scope", "")) == str(EXPECTED_SCOPE_BY_ID[operator_id]), "%s has normative scope" % operator_id, str(entry.get("scope", "")))
		_check(str(entry.get("status", "")) == str(EXPECTED_STATUS_BY_ID[operator_id]), "%s has truthful status" % operator_id, str(entry.get("status", "")))
		_check(not (str(entry.get("test_evidence_reference", ""))).strip_edges().is_empty(), "%s has evidence reference" % operator_id)
		_check(not (str(entry.get("semantic_notes", ""))).strip_edges().is_empty(), "%s has semantic notes" % operator_id)
	var final_entry: Dictionary = registry.get("final_composite", {})
	_check(str(final_entry.get("scope", "")) == "FINAL_COMPOSITE", "final_composite has dedicated final scope")
	_check(str(final_entry.get("status", "")) == "SUPPORTED", "final_composite is supported separately")
	for operator_id in ["perimeter_flux", "noise_erosion_border"]:
		var frame_entry: Dictionary = registry.get(operator_id, {})
		var notes := str(frame_entry.get("semantic_notes", "")).to_lower()
		for forbidden_claim in ["contour-aware", "source-alpha contour", "follows the source silhouette", "organic source-contour", "normal-field"]:
			_check(notes.find(forbidden_claim) < 0, "%s does not overclaim %s" % [operator_id, forbidden_claim])
	for operator_id in ["hit_flash", "mesh_smear", "multi_impact_field", "slash_arc", "world_outline_depth", "world_outline_depth_normal"]:
		var deferred_entry: Dictionary = registry.get(operator_id, {})
		_check(str(deferred_entry.get("semantic_notes", "")).find("DEFERRED_3D_FORWARD_PLUS") >= 0, "%s records the 3D deferral reason" % operator_id)

func _raw_time_paths_use_supplied_clock() -> void:
	var regex := RegEx.new()
	regex.compile("\\bTIME\\b")
	var shader_paths := [
		"res://shaders/dither_rgb.gdshader",
		"res://shaders/fx_vector_proxy.gdshader",
		"res://shaders/nrcu_fx.gdshader",
		"res://shaders/nrcu_fx_v2.gdshader",
		"res://shaders/nrcu_fx_vnext_layer.gdshader",
	]
	for path in shader_paths:
		var shader := _read_text(path)
		_check(regex.search(shader) == null, "%s has no raw TIME builtin" % path)
	var legacy_shader := _read_text("res://shaders/dither_rgb.gdshader")
	_check(legacy_shader.find("uniform float supplied_time") >= 0, "legacy dither shader declares supplied clock")
	var legacy_lab := _read_text("res://scripts/vfx_lab.gd")
	_check(legacy_lab.find("set_shader_parameter(\"supplied_time\"") >= 0, "legacy dither caller supplies its clock")
	var renderer := _read_text("res://scripts/fx_vnext/fx_layer_renderer.gd")
	_check(renderer.find("set_shader_parameter(\"layer_time\"") >= 0, "vNext renderer supplies presentation clock")
	_check(renderer.find("set_shader_parameter(\"free_time\"") >= 0, "vNext renderer supplies free-run clock")
	_check(FxOperatorsScript.TIME_SOURCES.has("PRESENTATION_TIME") and FxOperatorsScript.TIME_SOURCES.has("FREE_RUN"), "clock contract names presentation and free-run")

func _lanes_are_explicit_and_fail_closed() -> void:
	var source: Dictionary = FxLookScript.new_layer("SOURCE", "Source")
	_check(FxOperatorsScript.lane_for_layer(source) == "TARGET_LOCAL", "new layers default to TARGET_LOCAL")
	_check(bool(FxOperatorsScript.validate_layer_lane(source).get("ok", false)), "TARGET_LOCAL lane validates")
	for plane in ["COMPOSITION_BACKGROUND", "COMPOSITION_FOREGROUND"]:
		var composition := FxLookScript.new_layer("FX", plane)
		composition["plane"] = plane
		var inferred: Dictionary = FxOperatorsScript.validate_layer_lane(composition)
		_check(bool(inferred.get("ok", false)), "%s stays on current local path" % plane)
		_check(str(inferred.get("lane", "")) == "TARGET_LOCAL", "%s is not FINAL_COMPOSITE" % plane)
		var forged := composition.duplicate(true)
		forged["lane"] = "FINAL_COMPOSITE"
		var rejected: Dictionary = FxOperatorsScript.validate_layer_lane(forged)
		_check(not bool(rejected.get("ok", false)), "%s cannot masquerade as FINAL_COMPOSITE" % plane)
	var final_layer := FxLookScript.new_layer("FX", "Final")
	final_layer["lane"] = "FINAL_COMPOSITE"
	var final_result: Dictionary = FxOperatorsScript.validate_layer_lane(final_layer)
	_check(bool(final_result.get("supported", false)), "FINAL_COMPOSITE is supported by the dedicated path")
	_check(bool(final_result.get("ok", false)), "FINAL_COMPOSITE lane validates")
	_check(FxOperatorsScript.final_composite_supported(), "dedicated final-composite path is advertised")

func _neutral_contract_is_truthful() -> void:
	var doc: Dictionary = FxLookScript.new_look("OP_NEUTRAL", "Operator neutral")
	var result: Dictionary = FxLookScript.validate(doc)
	_check(bool(result.get("ok", false)), "canonical neutral Look validates")
	var source: Dictionary = FxLookScript.source_layer(doc)
	_check(str(source.get("lane", "")) == "TARGET_LOCAL", "canonical neutral SOURCE carries lane metadata")
	_check(bool(FxOperatorsScript.neutral_contract_ok()), "operator registry neutral contract is internally consistent")
	var registry: Dictionary = FxOperatorsScript.registry()
	for operator_id in FxOperatorsScript.operator_ids():
		var entry: Dictionary = registry[str(operator_id)]
		if str(entry.get("scope", "")) == "LOCAL":
			_check(str(entry.get("status", "")) in ["ADAPTER_ONLY", "UNSUPPORTED"], "%s has truthful local status" % str(operator_id))
		if str(entry.get("status", "")) in ["UNSUPPORTED", "DEFERRED"]:
			_check(not bool(entry.get("runtime_observable", true)), "%s does not claim runtime proof" % str(operator_id))

func _cost_fields_are_truthful_and_deterministic() -> void:
	var layer: Dictionary = FxLookScript.new_layer("FX", "Dither")
	(layer["fx"] as Dictionary)["dither"] = 1.0
	var first: Dictionary = FxCostScript.layer_cost(layer)
	var second: Dictionary = FxCostScript.layer_cost(layer.duplicate(true))
	_check(first == second, "layer cost aggregation is deterministic")
	_check(first.has("operator_cost") and first.has("operator_costs"), "layer cost exposes operator fields")
	_check(first.has("lane") and first.has("lane_cost") and first.has("lane_costs"), "layer cost exposes lane fields")
	_check(str(first.get("lane", "")) == "TARGET_LOCAL", "local operator cost uses TARGET_LOCAL")
	_check((first.get("operator_costs", {}) as Dictionary).has("dither"), "active dither is named in operator costs")
	_check(is_equal_approx(float(first.get("operator_cost", 0.0)), 1.0), "dither operator cost follows MEDIUM class", str(first.get("operator_cost", "")))
	_check(is_equal_approx(float(first.get("cost", 0.0)), 3.0), "layer cost includes named operator exactly once", str(first.get("cost", "")))
	var doc: Dictionary = FxLookScript.new_look("OP_COST", "Operator cost")
	doc["layers"].append(layer)
	var look_cost: Dictionary = FxCostScript.look_cost(doc)
	_check(look_cost.has("operator_costs") and look_cost.has("lane_costs"), "look cost exposes aggregate operator/lane fields")
	_check((look_cost.get("operator_costs", {}) as Dictionary).has("dither"), "look cost aggregates dither deterministically")
	_check(is_equal_approx(float(look_cost.get("operator_cost_total", 0.0)), 1.0), "look operator total is deterministic", str(look_cost.get("operator_cost_total", "")))
	var forged := layer.duplicate(true)
	forged["lane"] = "FINAL_COMPOSITE"
	var supported_final: Dictionary = FxCostScript.layer_cost(forged)
	_check(bool(supported_final.get("lane_supported", false)), "supported final lane cost is reported as renderable")
	_check(str(supported_final.get("lane_status", "")) == "SUPPORTED", "final lane cost carries truthful status")

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
	else:
		print("[CHECK] PASS  ", label)
