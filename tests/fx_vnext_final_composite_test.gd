extends SceneTree
# FINAL_COMPOSITE lane contract and runtime proof.
# The readback section is intentionally small: it only claims pixels after a
# real SubViewport render has produced two captures.

const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxEvidenceScript := preload("res://scripts/fx_vnext/fx_evidence.gd")

var checks := 0
var failures := 0
var host: Control
var runtime
var renderer
var evidence_dir: String = ""
var neutral_readback: Image
var active_readback: Image

func _init() -> void:
	var supplied: String = OS.get_environment("FXLAB_EVIDENCE_DIR")
	evidence_dir = ProjectSettings.globalize_path(supplied) if supplied != "" else ProjectSettings.globalize_path("user://fx_evidence/final_composite")
	_static_contract()
	await _runtime_contract()
	_write_evidence_summary()
	print("[FX-FINAL-COMPOSITE] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _static_contract() -> void:
	_check(FxOperatorsScript.final_composite_supported(), "FINAL_COMPOSITE is supported only with the dedicated shader path")
	var entry: Dictionary = FxOperatorsScript.operator_entry("final_composite")
	_check(bool(entry.get("authoring_reachable", false)), "final_composite authoring flag is truthful")
	_check(bool(entry.get("persistence_proven", false)), "final_composite persistence flag is truthful")
	_check(bool(entry.get("runtime_observable", false)), "final_composite runtime flag is truthful")
	_check(str(entry.get("status", "")) != "UNSUPPORTED", "final_composite registry status is not unsupported")
	var shader_text := _read_text("res://shaders/nrcu_fx_vnext_final_composite.gdshader")
	_check(shader_text.find("hint_screen_texture") >= 0, "final shader samples the BackBufferCopy screen texture")
	_check(shader_text.find("uniform float final_tint_amount") >= 0, "final shader exposes the neutral tint amount")
	_check(shader_text.find("uniform float presentation_time") >= 0, "final shader exposes supplied presentation time")
	var raw_time := RegEx.new()
	raw_time.compile("(^|[^A-Z_])TIME([^A-Z_]|$)")
	_check(raw_time.search(shader_text) == null, "final shader never uses raw TIME")

	var final_layer: Dictionary = _final_layer(0.0)
	var accepted: Dictionary = FxOperatorsScript.validate_layer_lane(final_layer)
	_check(bool(accepted.get("ok", false)), "explicit FINAL_COMPOSITE lane is accepted")
	_check(bool(accepted.get("supported", false)), "explicit FINAL_COMPOSITE lane is supported")
	_check(FxOperatorsScript.operator_ids_for_layer(final_layer).has("final_composite"), "final lane reports the final_composite operator")
	for plane in ["COMPOSITION_BACKGROUND", "COMPOSITION_FOREGROUND"]:
		var forged: Dictionary = final_layer.duplicate(true)
		forged["plane"] = plane
		var rejected: Dictionary = FxOperatorsScript.validate_layer_lane(forged)
		_check(not bool(rejected.get("ok", false)), "%s cannot masquerade as FINAL_COMPOSITE" % plane)

	var doc := FxLookScript.new_look("FINAL_SCHEMA", "Final schema")
	doc["layers"].append(final_layer)
	var materialized: Dictionary = FxLookScript.materialize(doc)
	_check((materialized["layers"][1]["fx"] as Dictionary).has("final_tint_amount"), "FxLook materializes final-composite metadata")
	_check(FxLookScript.field_meta_all().has("final_tint_amount") and FxLookScript.field_meta_all().has("final_tint_color"), "authoring metadata exposes final-composite fields")
	_check(bool(FxLookScript.validate(materialized).get("ok", false)), "schema-compatible explicit final Look validates")

func _runtime_contract() -> void:
	host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.size = Vector2(1280, 720)
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "runtime mounts for final-composite proof")
	await _settle(35)
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)

	var neutral: Dictionary = _look("FINAL_NEUTRAL", _final_layer(0.0))
	var neutral_result: Dictionary = renderer.apply_composition([{"key": "echo_left", "look": neutral}])
	_check(bool(neutral_result.get("ok", false)), "neutral final composition commits", str(neutral_result.get("errors", [])))
	_check(int(neutral_result.get("final_composite", 0)) == 1, "one explicit final layer produces one final pass")
	var final_node: Node = runtime.screen.get_node_or_null("Root/vnext_final_composite")
	var final_bbc: Node = runtime.screen.get_node_or_null("Root/vnext_final_bbc")
	_check(final_node is ColorRect, "final pass uses a dedicated full-canvas quad")
	_check(final_bbc is BackBufferCopy, "final pass has a dedicated BackBufferCopy")
	if final_node is ColorRect:
		var neutral_mat := (final_node as ColorRect).material as ShaderMaterial
		_check(neutral_mat != null, "final quad has a shader material")
		if neutral_mat != null:
			_check(is_equal_approx(float(neutral_mat.get_shader_parameter("final_tint_amount")), 0.0), "neutral final uniform is zero")
		_check(final_node.get_index() < runtime.screen.get_node("Root/ImpactFlash").get_index(), "final quad is before ImpactFlash")
		_check(final_node.get_index() < runtime.screen.get_node("Root/TransitionCover").get_index(), "final quad is before TransitionCover")
	if final_bbc is BackBufferCopy and final_node is ColorRect:
		_check(final_bbc.get_index() + 1 == final_node.get_index(), "BackBufferCopy immediately precedes final quad")

	renderer.set_clocks(2.5, 9.0)
	if final_node is ColorRect:
		var clock_mat := (final_node as ColorRect).material as ShaderMaterial
		if clock_mat != null:
			_check(is_equal_approx(float(clock_mat.get_shader_parameter("presentation_time")), 2.5), "final quad receives presentation clock")
			_check(is_equal_approx(float(clock_mat.get_shader_parameter("free_run_time")), 9.0), "final quad receives free-run clock")

	var readback_enabled := OS.get_environment("FX_FINAL_READBACK") != ""
	if readback_enabled:
		neutral_readback = await _capture()
	var active_fx: Dictionary = _final_layer(1.0)
	(active_fx["fx"] as Dictionary)["final_tint_color"] = [0.0, 0.0, 0.0, 1.0]
	var active_result: Dictionary = renderer.apply_composition([{"key": "echo_left", "look": _look("FINAL_ACTIVE", active_fx)}])
	_check(bool(active_result.get("ok", false)), "non-neutral final composition commits", str(active_result.get("errors", [])))
	await _settle(4)
	var active_node: Node = runtime.screen.get_node_or_null("Root/vnext_final_composite")
	if active_node is ColorRect:
		var active_mat := (active_node as ColorRect).material as ShaderMaterial
		if active_mat != null:
			_check(float(active_mat.get_shader_parameter("final_tint_amount")) > 0.0, "non-neutral final uniform is non-zero")
	if readback_enabled:
		active_readback = await _capture()
		_check(_mean_abs_diff(neutral_readback, active_readback) > 0.0005, "non-neutral final pass changes rendered pixels")
	else:
		_check(true, "pixel readback is opt-in for headless contract runs")

	var local_only: Dictionary = _look("FINAL_REMOUNT", null)
	var local_result: Dictionary = renderer.apply_composition([{"key": "echo_left", "look": local_only}])
	_check(bool(local_result.get("ok", false)), "local-only remount still commits")
	_check(runtime.screen.get_node_or_null("Root/vnext_final_composite") == null, "local-only remount removes final quad")
	_check(runtime.screen.get_node_or_null("Root/vnext_final_bbc") == null, "local-only remount removes final BackBufferCopy")
	var no_final: Dictionary = renderer.apply_final_composite([])
	_check(not bool(no_final.get("ok", false)), "direct final pass fails closed without explicit layers")
	var forged_final: Dictionary = _final_layer(1.0)
	forged_final["plane"] = "COMPOSITION_BACKGROUND"
	var forged_result: Dictionary = renderer.apply_final_composite([forged_final])
	_check(not bool(forged_result.get("ok", false)), "direct final pass rejects composition-plane masquerading")

func _write_evidence_summary() -> void:
	var captures: Array[String] = []
	if neutral_readback != null:
		var neutral_path := evidence_dir.path_join("final_composite_neutral.png")
		if FxEvidenceScript.save_png(neutral_readback, neutral_path):
			captures.append(neutral_path)
	if active_readback != null:
		var active_path := evidence_dir.path_join("final_composite_active.png")
		if FxEvidenceScript.save_png(active_readback, active_path):
			captures.append(active_path)
	FxEvidenceScript.write_json(evidence_dir.path_join("final_composite_summary.json"), {
		"status": "PASS" if failures == 0 else "FAIL",
		"checks": checks,
		"failures": failures,
		"presentation_time": 2.5,
		"free_run_time": 9.0,
		"captures": captures,
	})

func _final_layer(amount: float):
	var layer: Dictionary = FxLookScript.new_layer("FX", "Final")
	layer["plane"] = "TARGET_OVERLAY"
	layer["lane"] = "FINAL_COMPOSITE"
	(layer["fx"] as Dictionary)["final_tint_amount"] = amount
	return layer

func _look(look_id: String, final_layer):
	var doc: Dictionary = FxLookScript.new_look(look_id, look_id)
	if final_layer != null:
		doc["layers"].append(final_layer)
	return FxLookScript.materialize(doc)

func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return host.get_viewport().get_texture().get_image()

func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 1
	return total / float(maxi(count, 1)) / 3.0

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
	else:
		print("[CHECK] PASS  ", label)
