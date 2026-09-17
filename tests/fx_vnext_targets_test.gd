extends SceneTree
# FxTargets unit test — real vs_screen, 1v1 duel + FFA_4 multiplayer context.
# Verifies key collection, role mapping, semantic context and the canonical
# target signature (specs/15 §9). Headless-safe: no render readback.

var checks: Array = []
var failures: int = 0

func _init() -> void:
	var subvp := SubViewport.new()
	subvp.size = Vector2i(1280, 720)
	root.add_child(subvp)
	var screen: Node = load("res://scenes/vs_screen.tscn").instantiate()
	subvp.add_child(screen)
	var mounted: bool = bool(screen.start("ice_mage", "doge_man", "debug"))
	await settle(30)
	_check(mounted, "duel screen mounts")

	var reg = load("res://scripts/fx_vnext/fx_targets.gd").new()
	reg.bind_screen(screen, "1v1", "debug")

	var keys: Array = reg.keys()
	_check(keys.size() == 8, "bare duel screen collects 8 texture targets", str(keys))
	var expected_keys := ["echo_left", "echo_right", "mark", "name_left", "name_right", "primary_left", "primary_right", "stage"]
	_check(keys == expected_keys, "duel target keys exact", str(keys))
	_check(reg.role_for_key("mark") == "VS MARK", "mark role")
	_check(reg.role_for_key("primary_left") == "PRIMARIES", "primary_left role")
	_check(reg.role_for_key("echo_left") == "ECHOES", "echo_left role")
	_check(reg.role_for_key("name_left") == "NAMES", "name_left role")
	_check(reg.role_for_key("stage") == "STAGE", "stage role")
	_check(reg.role_for_key("field_left_fx_proxy") == "SIDE FIELDS", "side field proxy role")
	_check(reg.role_for_key("plate_left_fx_proxy") == "NAME PLATES", "name plate proxy role")
	_check(reg.role_for_key("accent_left_fx_proxy") == "ACCENT LINES", "accent line proxy role")

	var mark_ctx: Dictionary = reg.context_for_key("mark")
	_check(str(mark_ctx.get("element_id", "")) == "vs_mark" and str(mark_ctx.get("element_role", "")) == "vs_mark",
		"mark context has element identity", str(mark_ctx))
	_check(str(mark_ctx.get("mode_family", "")) == "1v1" and str(mark_ctx.get("stage_id", "")) == "debug",
		"mark context carries mode/stage", str(mark_ctx))
	_check(not mark_ctx.has("fighter_id"), "mark context has no fighter_id")

	var echo_ctx: Dictionary = reg.context_for_key("echo_left")
	_check(str(echo_ctx.get("fighter_id", "")) == "ice_mage" and str(echo_ctx.get("element_role", "")) == "echo",
		"echo context semantic identity", str(echo_ctx))
	_check(str(echo_ctx.get("visual_side", "")) == "left" and str(echo_ctx.get("presentation_slot", "")) == "left",
		"echo context side/slot", str(echo_ctx))

	var sig_echo: String = reg.signature_for_key("echo_left")
	_check(sig_echo == "|ice_mage|echo|left|left||1v1|debug", "echo signature canonical", sig_echo)
	var sig_mark: String = reg.signature_for_key("mark")
	_check(sig_mark == "vs_mark||vs_mark||||1v1|debug", "mark signature canonical", sig_mark)

	# ---- multiplayer context: FFA_4 ----------------------------------------
	var VSRequest := preload("res://scripts/vs_presentation_request.gd")
	var records: Array = []
	var pool := ["ggb", "teknium", "mephisto", "witcheer"]
	for i in range(4):
		var kind = VSRequest.StateScript.Kind.CPU
		records.append(VSRequest.record(i, str(pool[i]), VSRequest.StateScript.NO_TEAM, kind, 0))
	var plan: Dictionary = VSRequest.plan(records, "debug", false)
	screen.free()
	var screen_ffa: Node = load("res://scenes/vs_screen.tscn").instantiate()
	subvp.add_child(screen_ffa)
	var mounted_ffa: bool = bool(screen_ffa.start_presentation(plan))
	await settle(30)
	_check(mounted_ffa, "FFA_4 screen mounts on a fresh instance")

	var reg_ffa = load("res://scripts/fx_vnext/fx_targets.gd").new()
	reg_ffa.bind_screen(screen_ffa, "FFA_4", "debug")
	var ffa_keys: Array = reg_ffa.keys()
	_check(ffa_keys.size() >= 14, "FFA_4 collects targets", "got %d" % ffa_keys.size())
	var all_mode := true
	var primary_slot := ""
	var primary_count := 0
	for key in ffa_keys:
		var ctx: Dictionary = reg_ffa.context_for_key(str(key))
		if str(ctx.get("mode_family", "")) != "FFA_4":
			all_mode = false
		if str(ctx.get("element_role", "")) == "primary":
			primary_count += 1
			if primary_slot == "":
				primary_slot = str(ctx.get("presentation_slot", ""))
	_check(all_mode, "FFA_4 contexts carry mode_family")
	_check(primary_count >= 3, "FFA_4 exposes 3+ primaries", "count=%d" % primary_count)
	_check(primary_slot != "", "FFA_4 primary context resolves a presentation slot", "slot=%s" % primary_slot)

	print("[FX-TARGETS] done · checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)

func settle(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, name: String, detail: String = "") -> void:
	checks.append(name)
	if not ok:
		failures += 1
	print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "" if detail == "" else "  (" + detail + ")")
