extends SceneTree
# FxScreenRuntime unit test — mount/remount, vector proxies, registry sync,
# transport passthrough. Headless-safe: no render readback.

var checks: Array = []
var failures: int = 0

func _init() -> void:
	var runtime = load("res://scripts/fx_vnext/fx_screen_runtime.gd").new()
	root.add_child(runtime.subvp)
	var ok: bool = runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	await settle(30)
	_check(ok, "duel mounts via runtime")

	var keys: Array = runtime.registry.keys()
	var expected := [
		"accent_left_fx_proxy", "accent_right_fx_proxy", "echo_left", "echo_right",
		"field_left_fx_proxy", "field_right_fx_proxy", "mark", "name_left", "name_right",
		"plate_left_fx_proxy", "plate_right_fx_proxy", "primary_left", "primary_right", "stage",
	]
	_check(keys.size() == 14, "duel exposes 14 targets incl vector proxies", str(keys))
	_check(keys == expected, "duel target keys exact", str(keys))

	var field_ctx: Dictionary = runtime.registry.context_for_key("field_left_fx_proxy")
	_check(str(field_ctx.get("element_id", "")) == "side_field_left", "side field carries stable element id", str(field_ctx))
	_check(str(field_ctx.get("visual_side", "")) == "left", "side field carries visual side", str(field_ctx))
	var field_source: Node = runtime.screen.get_node_or_null("Root/SideFields/FieldLeft")
	_check(field_source != null and not field_source.visible, "original polygon hidden behind vector proxy")

	runtime.seek(1.5)
	await settle(4)
	var t: float = runtime.elapsed()
	_check(absf(t - 1.5) < 0.06, "transport seek reaches 1.5s", "t=%.3f" % t)

	var ok2: bool = runtime.mount("TEAM_2V2", "debug", "ggb", "teknium")
	await settle(30)
	_check(ok2, "TEAM_2V2 mounts via runtime")
	var keys2: Array = runtime.registry.keys()
	_check(keys2.size() >= 20, "team family exposes 20+ targets", "got %d" % keys2.size())
	_check(keys2.has("a_front_primary_p_2"), "team primary key present")
	_check(keys2.has("name_a_back"), "team name key present")
	var pc: Dictionary = runtime.registry.context_for_key("a_front_primary_p_2")
	_check(str(pc.get("element_role", "")) == "primary", "team primary role", str(pc))
	_check(str(pc.get("presentation_slot", "")) == "a_front", "team primary slot", str(pc))
	_check(str(pc.get("team_side", "")) == "A", "team primary team side", str(pc))
	var sig: String = runtime.registry.signature_for_key("a_front_primary_p_2")
	_check(sig.ends_with("|a_front|A|TEAM_2V2|debug"), "team signature suffix canonical", sig)

	var ok3: bool = runtime.mount("1v1")
	await settle(20)
	_check(ok3, "remount back to duel")

	print("[FX-RUNTIME] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok:
		failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
