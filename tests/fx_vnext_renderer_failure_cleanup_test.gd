extends SceneTree
# Renderer transaction proof: injected build/attach failures leave either the
# previous LKG intact or a canonical unstyled frame, never a mixed frame.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var host_root: Node
var runtime
var renderer
var checks := 0
var failures := 0

func _init() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	host_root = Node.new()
	host_root.name = "FailureCleanupHost"
	root.add_child(host_root)
	host_root.add_child(host)
	var container := SubViewportContainer.new()
	container.size = Vector2(1280, 720)
	container.stretch = false
	host.add_child(container)
	runtime = FxScreenRuntimeScript.new()
	container.add_child(runtime.subvp)
	await process_frame
	_check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "failure harness mounts a runtime")
	await settle(40)
	runtime.screen.lab_preview_pause()
	renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	renderer.set_time(1.2)
	var look := FxLookScript.new_look("FAILURE_LKG", "Failure LKG")
	var layer := FxLookScript.new_layer("FX", "Failure FX")
	(layer["fx"] as Dictionary)["rgb"] = 1.0
	look["layers"].append(layer)
	var plan: Array = [{"key": "echo_left", "look": look}]
	var canonical_child_count: int = _root_child_count()
	var applied: Dictionary = renderer.apply_composition(plan)
	_check(bool(applied.get("ok", false)), "valid target-local baseline applies", str(applied.get("errors", [])))
	var baseline_stack_count: int = renderer._stacks.size()
	var baseline_child_count: int = _root_child_count()
	var target_failure: Dictionary = renderer.apply_composition(plan, {"inject_failure": "target_stack_build"})
	_check(not bool(target_failure.get("ok", false)), "target stack build failure rejects")
	_check(renderer._stacks.size() == baseline_stack_count and _root_child_count() == baseline_child_count, "target build failure preserves LKG stack")
	var invalid_composition: Dictionary = {"revision": 1, "final_passes": [{"pass_id": "bad"}]}
	var invalid_failure: Dictionary = renderer.apply_composition(plan, {"composition": invalid_composition})
	_check(not bool(invalid_failure.get("ok", false)), "invalid composition rejects before commit")
	_check(renderer._stacks.size() == baseline_stack_count and _root_child_count() == baseline_child_count, "invalid composition preserves LKG stack")
	var clash: Dictionary = FxRecipesScript.instantiate_composition(FxRecipesScript.CLASH_OVERDRIVE, "failure-cleanup").get("doc", {})
	var attach_failure: Dictionary = renderer.apply_composition([], {"composition": clash, "inject_failure": "attach_after_pass_2"})
	_check(not bool(attach_failure.get("ok", false)), "late final-pass attach failure rejects")
	_check(renderer._stacks.is_empty() and renderer._final_composite.is_empty(), "late attach failure leaves no stale renderer dictionaries")
	_check(_root_child_count() == canonical_child_count, "late attach failure removes all newly attached nodes", "root=%s canonical=%s names=%s" % [_root_child_count(), canonical_child_count, str(_root_child_names())])
	_check(_canonical_visible("echo_left"), "late attach failure exposes canonical target")
	var recovered: Dictionary = renderer.apply_composition([], {"composition": clash})
	_check(bool(recovered.get("ok", false)), "valid composition recovers immediately after failure", str(recovered.get("errors", [])))
	_check(not renderer._final_composite.is_empty(), "recovery installs the final composition")
	renderer.clear_all()
	runtime.free_screen()
	if host_root != null and is_instance_valid(host_root):
		host_root.free()
	print("[FX-RENDERER-FAILURE-CLEANUP] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _root() -> Node:
	return runtime.screen.get_node_or_null("Root")

func _root_child_count() -> int:
	var node := _root()
	return node.get_child_count() if node != null else -1

func _canonical_child_count() -> int:
	var node := _root()
	var count := 0
	if node == null:
		return count
	for child in node.get_children():
		if child is TextureRect or child is Control and not str(child.name).begins_with("vnext_"):
			count += 1
	return count

func _root_child_names() -> Array:
	var names: Array = []
	var node := _root()
	if node == null:
		return names
	for child in node.get_children():
		names.append(str(child.name))
	return names

func _canonical_visible(key: String) -> bool:
	var node = runtime.registry.target_node(key)
	return node != null and float(node.self_modulate.a) > 0.99

func _settle_frames(frames: int) -> void:
	for i in frames:
		await process_frame

func settle(frames: int) -> void:
	await _settle_frames(frames)

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)
