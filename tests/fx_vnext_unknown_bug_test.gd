extends SceneTree
# vNext §23 unknown-bug hunt — one suite of hostile/edge inputs driven against
# the REAL production APIs (FxTargets target registry, FxSession authoring state
# machine, FxResolver assignments, FxProduction transaction store, FxDrafts store
# and the FxLayerRenderer material push). Headless: pure data + node inspection,
# one mounted vs_screen for the real target registry (no render readback).
#
# Every case asserts the SAFE, TRUTHFUL behavior: a clear error/status, no crash,
# no silent data loss. Where the API has no defined behavior, the check asserts
# the most defensible invariant and the comment says why.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")

var checks: Array = []
var failures: int = 0
var out_dir: String
var prod_dir := "user://vnext_unknown_prod"
var draft_dir := "user://vnext_unknown_drafts"
var scratch := "user://vnext_unknown_scratch"
var prod
var drafts
var _owned: Array = []

func _init() -> void:
	await _run()

func _run() -> void:
	seed(424242)
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	prod.ensure_dirs()

	await _case_target_registry()
	await _case_missing_stage_entry()
	await _case_missing_fighter_texture()
	_case_duplicate_fighter()
	_case_long_look_name()
	_case_unicode_look_name()
	_case_invalid_filename_chars()
	_case_unwritable_dirs()
	_case_interrupted_save_leftovers()
	_case_custom_assets()
	_case_texture_edge_cases()
	_case_stale_target_ids()
	_case_future_schema()
	_case_material_misuse()

	var f := FileAccess.open(out_dir.path_join("unit_fx_unknown_bug.log"), FileAccess.WRITE)
	var summary := "[FX-UNKNOWN] done · checks=%d failures=%d" % [checks.size(), failures]
	if f != null:
		f.store_string("\n".join(checks) + "\n" + summary + "\n")
		f.close()
	print(summary)
	for node in _owned:
		if node != null and is_instance_valid(node):
			node.free()
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	_wipe_dir(ProjectSettings.globalize_path(scratch))
	quit(1 if failures > 0 else 0)

# ================================================================ 0 / 1 / 16 targets

func _case_target_registry() -> void:
	# ---- zero targets: a registry bound to a screen without presentation slots
	var empty_screen := _synthetic_screen([])
	var reg_empty = FxTargetsScript.new()
	reg_empty.bind_screen(empty_screen, "1v1", "debug")
	var empty_keys: Array = reg_empty.keys()
	_check(empty_keys.is_empty(), "zero targets: registry collects nothing", str(empty_keys))
	var ghost_ctx: Dictionary = reg_empty.context_for_key("ghost_left")
	_check(str(ghost_ctx.get("mode_family", "")) == "1v1" and str(ghost_ctx.get("stage_id", "")) == "debug" and not ghost_ctx.has("target_key"),
		"zero targets: unknown key yields a base context (no crash)", str(ghost_ctx))
	_check(reg_empty.target_node("ghost_left") == null, "zero targets: unknown key has no node")
	_check(reg_empty.signature_for_key("ghost_left") == "||||||1v1|debug",
		"zero targets: unknown key still produces a canonical signature", reg_empty.signature_for_key("ghost_left"))
	_check(reg_empty.role_for_key("ghost_left") == "OTHER TEXTURES", "zero targets: unknown key maps to the fallback role", reg_empty.role_for_key("ghost_left"))

	# ---- one target
	var one_reg = _synthetic_registry([{"name": "primary_left", "size": Vector2(320, 400)}], "1v1", "debug")
	var one_keys: Array = one_reg.keys()
	_check(one_keys.size() == 1 and str(one_keys[0]) == "primary_left", "one target: exactly one key collected", str(one_keys))
	if not one_keys.is_empty():
		var one_ctx: Dictionary = one_reg.context_for_key(str(one_keys[0]))
		_check(str(one_ctx.get("element_role", "")) == "primary" and str(one_ctx.get("visual_side", "")) == "left",
			"one target: context resolves role + side", str(one_ctx))
		_check(_signature_fields(one_reg.signature_for_key(str(one_keys[0]))) == 8, "one target: signature has all 8 canonical fields", one_reg.signature_for_key(str(one_keys[0])))
		var one_node = one_reg.target_node(str(one_keys[0]))
		_check(one_node != null and one_node.texture != null, "one target: registry only exposes textured slots")

	# ---- 16 targets, each with its own element identity
	var specs: Array = []
	for i in range(16):
		specs.append({"name": "slot_%d" % i, "size": Vector2(64 + i, 64), "element": "elem_%d" % i})
	var many_reg = _synthetic_registry(specs, "1v1", "debug")
	var many_keys: Array = many_reg.keys()
	_check(many_keys.size() == 16, "16 targets: every slot is collected", "n=%d" % many_keys.size())
	_check(_unique(many_keys).size() == 16, "16 targets: keys are unique")
	var null_tex := 0
	var collected_ok := true
	for key in many_keys:
		var node = many_reg.target_node(str(key))
		if node == null or node.texture == null:
			null_tex += 1
		if _signature_fields(many_reg.signature_for_key(str(key))) != 8:
			collected_ok = false
	_check(null_tex == 0, "16 targets: no key ever exposes a null texture", "null=%d" % null_tex)
	_check(collected_ok, "16 targets: every signature is well formed")
	var before_keys: Array = many_reg.keys()
	many_reg.collect()
	_check(many_reg.keys() == before_keys, "16 targets: re-collecting the same screen is deterministic", str(many_reg.keys().slice(0, 3)))

	# 16 bindings (one per element identity) must resolve per target without
	# cross-contamination.
	var look: Dictionary = _production_look("MANY_TARGETS_LOOK", "Many Targets Look")
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "16 targets: shared look applies", str(applied.get("errors", [])))
	var assignments: Dictionary = FxResolverScript.new_assignments()
	for i in range(16):
		FxResolverScript.upsert_binding(assignments, {"element_id": "elem_%d" % i}, "MANY_TARGETS_LOOK", "many targets %d" % i)
	var bound: Dictionary = prod.apply({"assignments": assignments})
	_check(bool(bound["ok"]), "16 targets: 16 distinct bindings apply", str(bound.get("errors", [])))
	var wrong := 0
	for key in many_keys:
		var resolved: Dictionary = FxResolverScript.resolve(prod.load_assignments()["doc"], many_reg.context_for_key(str(key)))
		if str(resolved.get("status", "")) != "ASSIGNED" or str(resolved.get("look_id", "")) != "MANY_TARGETS_LOOK":
			wrong += 1
	_check(wrong == 0, "16 targets: every target resolves to the bound look", "wrong=%d" % wrong)
	_check(int(prod.usage("MANY_TARGETS_LOOK").get("count", 0)) == 16, "16 targets: usage counts all 16 bindings", str(prod.usage("MANY_TARGETS_LOOK").get("count", 0)))

func _case_missing_stage_entry() -> void:
	# A look authored for a target whose identifying slot is MISSING from the
	# screen must fall back to the semantic element identity, never to a
	# universal scope (a universal binding would silently paint every target).
	var screen := _synthetic_screen([{"name": "primary_left", "size": Vector2(320, 400)}])
	var reg = FxTargetsScript.new()
	reg.bind_screen(screen, "1v1", "debug")
	_check(not reg.keys().has("stage"), "missing stage entry: registry has no stage slot", str(reg.keys()))
	var ctx: Dictionary = reg.context_for_key("stage")
	var sig: String = reg.signature_for_key("stage")
	var session = FxSessionScript.new(prod, drafts)
	var opened: Dictionary = session.open_target("stage", ctx, sig, "stage")
	_check(bool(opened["ok"]) and str(opened.get("opened", "")) == "neutral", "missing stage entry: opens a neutral design", str(opened))
	var selector: Dictionary = session.novice_selector()
	_check(not selector.is_empty() and str(selector.get("element_id", "")) == "stage",
		"missing stage entry: scope falls back to the stage element identity (never universal)", str(selector))
	var applied: Dictionary = session.apply()
	_check(bool(applied["ok"]), "missing stage entry: Apply works under the element scope", str(applied.get("errors", [])))
	var asg_doc: Dictionary = prod.load_assignments().get("doc", {})
	var stage_ctx := {"element_id": "stage", "element_role": "stage", "mode_family": "1v1", "stage_id": "debug"}
	var mark_ctx := {"element_id": "vs_mark", "element_role": "vs_mark", "mode_family": "1v1", "stage_id": "debug"}
	_check(str(FxResolverScript.resolve(asg_doc, stage_ctx).get("status", "")) == "ASSIGNED",
		"missing stage entry: the real stage element resolves the new look", str(FxResolverScript.resolve(asg_doc, stage_ctx)))
	_check(str(FxResolverScript.resolve(asg_doc, mark_ctx).get("status", "")) == "UNASSIGNED",
		"missing stage entry: no other element is captured by the fallback scope", str(FxResolverScript.resolve(asg_doc, mark_ctx).get("status", "")))

func _case_missing_fighter_texture() -> void:
	# Real mounted duel screen: a slot whose texture is unloadable/absent must
	# disappear from the registry rather than being exposed as a null-texture
	# target the renderer would sample.
	var subvp := SubViewport.new()
	subvp.size = Vector2i(1280, 720)
	root.add_child(subvp)
	_owned.append(subvp)
	var screen: Node = load("res://scenes/vs_screen.tscn").instantiate()
	subvp.add_child(screen)
	var mounted: bool = bool(screen.start("ice_mage", "doge_man", "debug"))
	await settle(30)
	_check(mounted, "missing fighter texture: duel screen mounts")
	var reg = FxTargetsScript.new()
	reg.bind_screen(screen, "1v1", "debug")
	var keys: Array = reg.keys()
	_check(keys.has("echo_left"), "missing fighter texture: echo_left present before damage", str(keys))
	var node = reg.target_node("echo_left")
	var saved_texture = node.texture if node != null else null
	if node != null:
		node.texture = null
	reg.collect()
	_check(not reg.keys().has("echo_left"), "missing fighter texture: damaged slot is dropped from the registry", str(reg.keys()))
	var null_exposed := 0
	for key in reg.keys():
		var entry = reg.target_node(str(key))
		if entry == null or entry.texture == null:
			null_exposed += 1
	_check(null_exposed == 0, "missing fighter texture: registry never exposes a null texture", "n=%d" % null_exposed)
	var damaged_ctx: Dictionary = reg.context_for_key("echo_left")
	_check(str(damaged_ctx.get("mode_family", "")) == "1v1", "missing fighter texture: context lookup stays safe", str(damaged_ctx))
	if node != null and saved_texture != null:
		node.texture = saved_texture
	reg.collect()
	_check(reg.keys().has("echo_left"), "missing fighter texture: restoring the texture restores the slot", str(reg.keys().size()))
	_check(reg.role_for_key("echo_left") == "ECHOES", "missing fighter texture: roles are unaffected after recovery")

func _case_duplicate_fighter() -> void:
	# Two presentation slots that share fighter + role + side have the SAME
	# semantic target. Writing a second look for that scope must replace the
	# single binding (specs/09 §2 upsert), resolve identically for both slots and
	# never silently delete the first Look from the Library.
	var specs := [
		{"name": "echo_left", "size": Vector2(256, 256), "fighter": "ice_mage"},
		{"name": "echo_left_mirror", "size": Vector2(256, 256), "fighter": "ice_mage"},
	]
	var reg = _synthetic_registry(specs, "1v1", "debug")
	var keys: Array = reg.keys()
	_check(keys.size() == 2, "duplicate fighter: both slots collected", str(keys))
	var ctx_a: Dictionary = reg.context_for_key("echo_left")
	var ctx_b: Dictionary = reg.context_for_key("echo_left_mirror")
	_check(str(ctx_a.get("fighter_id", "")) == "ice_mage" and str(ctx_b.get("fighter_id", "")) == "ice_mage",
		"duplicate fighter: both slots resolve the same fighter", str(ctx_a) + " / " + str(ctx_b))
	_check(FxResolverScript.selector_key(ctx_a) == FxResolverScript.selector_key(ctx_b),
		"duplicate fighter: both slots share one semantic scope", FxResolverScript.selector_key(ctx_a))

	var first: Dictionary = prod.apply({"look": _production_look("DUP_FIGHTER_A", "Dup A")})
	_check(bool(first["ok"]), "duplicate fighter: first look applies", str(first.get("errors", [])))
	var asg: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(asg, ctx_a, "DUP_FIGHTER_A", "first")
	var asg_applied: Dictionary = prod.apply({"assignments": asg})
	_check(bool(asg_applied["ok"]), "duplicate fighter: first binding applies", str(asg_applied.get("errors", [])))
	_check(str(FxResolverScript.resolve(prod.load_assignments()["doc"], ctx_a)["status"]) == "ASSIGNED", "duplicate fighter: slot A assigned")

	var second: Dictionary = prod.apply({"look": _production_look("DUP_FIGHTER_B", "Dup B")})
	_check(bool(second["ok"]), "duplicate fighter: second look applies", str(second.get("errors", [])))
	var asg2: Dictionary = prod.load_assignments()["doc"]
	FxResolverScript.upsert_binding(asg2, ctx_b, "DUP_FIGHTER_B", "second")
	_check((asg2["bindings"] as Array).size() == 1, "duplicate fighter: upsert replaces instead of appending", "n=%d" % (asg2["bindings"] as Array).size())
	var asg2_applied: Dictionary = prod.apply({"assignments": asg2})
	_check(bool(asg2_applied["ok"]), "duplicate fighter: second binding applies", str(asg2_applied.get("errors", [])))

	var final_doc: Dictionary = prod.load_assignments()["doc"]
	var res_a: Dictionary = FxResolverScript.resolve(final_doc, ctx_a)
	var res_b: Dictionary = FxResolverScript.resolve(final_doc, ctx_b)
	_check(str(res_a["status"]) == "ASSIGNED" and str(res_b["status"]) == "ASSIGNED", "duplicate fighter: both slots stay assigned (no ambiguity)", str(res_a["status"]) + "/" + str(res_b["status"]))
	_check(str(res_a["look_id"]) == "DUP_FIGHTER_B" and str(res_b["look_id"]) == "DUP_FIGHTER_B", "duplicate fighter: both slots resolve the same winner", str(res_a["look_id"]) + "/" + str(res_b["look_id"]))
	_check(prod.list_look_ids().has("DUP_FIGHTER_A"), "duplicate fighter: the replaced Look is still in the Library", str(prod.list_look_ids()))
	_check(int(prod.usage("DUP_FIGHTER_A").get("count", 0)) == 0 and int(prod.usage("DUP_FIGHTER_B").get("count", 0)) == 1,
		"duplicate fighter: usage reflects the single binding", "%d/%d" % [int(prod.usage("DUP_FIGHTER_A").get("count", 0)), int(prod.usage("DUP_FIGHTER_B").get("count", 0))])

# ================================================================ names

func _case_long_look_name() -> void:
	var long_name := "N".repeat(500)
	var look: Dictionary = _production_look("LONG_NAME_LOOK", long_name)
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "500-char look name applies", str(applied.get("errors", [])))
	var loaded: Dictionary = prod.load_look("LONG_NAME_LOOK")
	_check(str((loaded.get("doc", {}) as Dictionary).get("name", "")).length() == 500, "500-char look name round-trips without truncation",
		"len=%d" % str((loaded.get("doc", {}) as Dictionary).get("name", "")).length())
	var reloaded_name: String = str((loaded.get("doc", {}) as Dictionary).get("name", ""))
	_check(reloaded_name == long_name, "500-char look name is byte-identical after reload")

	# A 500-char Look ID becomes a filename: it must fail cleanly, without a
	# crash, a leftover candidate or a partial write.
	var huge_id := "L".repeat(500)
	var before_ids: Array = prod.list_look_ids()
	Engine.print_error_messages = false
	var rejected: Dictionary = prod.apply({"look": _production_look(huge_id, "Huge Id")})
	Engine.print_error_messages = true
	_check(not bool(rejected["ok"]), "500-char look id is rejected (filesystem domain)", str(rejected.get("stage", "")) + " " + str(rejected.get("errors", [])))
	_check(prod.list_look_ids() == before_ids, "500-char look id never appears as a Library entry", str(prod.list_look_ids()))
	_check(not FileAccess.file_exists(prod.look_path(huge_id) + ".tmp"), "500-char look id leaves no .tmp candidate")

	# A very long target signature goes into the Draft store's filename: the
	# slug must stay filesystem-safe, bounded and collision-free.
	var sig := "1v1|" + "/".repeat(60) + "|" + "雪".repeat(40)
	var path: String = drafts.target_path(sig)
	_check(path.get_file().length() <= 120 and not path.get_file().contains("/") and not path.get_file().contains("\\"),
		"long hostile signature maps to a bounded, safe draft filename", path.get_file())
	var saved: Dictionary = drafts.save_target(sig, _production_look("LONG_SIG", "Long Sig"), 1)
	_check(bool(saved["ok"]), "long hostile signature draft saves", str(saved.get("errors", [])))
	_check(bool(drafts.load_target(sig)["ok"]), "long hostile signature draft round-trips")
	var other_path: String = drafts.target_path("1v1|" + "/".repeat(60) + "|" + "雪".repeat(39) + "雨")
	_check(other_path != path, "near-identical long signatures do not collide", other_path.get_file())
	drafts.clear_target(sig)

func _case_unicode_look_name() -> void:
	var name := "冰龙 🐉 Echo / Left"
	var look: Dictionary = _production_look("UNICODE_LOOK", name)
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "unicode look name applies", str(applied.get("errors", [])))
	var loaded: Dictionary = prod.load_look("UNICODE_LOOK")
	_check(str((loaded.get("doc", {}) as Dictionary).get("name", "")) == name, "unicode look name is byte-identical after reload",
		str((loaded.get("doc", {}) as Dictionary).get("name", "")))
	var listed := false
	for key in prod.list_look_ids():
		if str(key).contains("冰") or str(key).contains("🐉"):
			listed = true
	_check(not listed, "unicode name never leaks into a Library id", str(prod.list_look_ids()))

	# A unicode fighter identity must still yield an ASCII-safe Look ID.
	var session = FxSessionScript.new(prod, drafts)
	var ctx := {"fighter_id": "冰龙", "element_role": "echo", "visual_side": "left", "mode_family": "1v1", "stage_id": "debug"}
	session.open_target("echo_left", ctx, "1v1|冰龙|echo|left|left||1v1|debug", "echo")
	var proposed: String = session.proposed_look_id()
	var ascii_only := true
	for i in range(proposed.length()):
		var ch := proposed[i]
		if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_"):
			ascii_only = false
	_check(proposed != "" and ascii_only, "unicode fighter identity produces an ASCII-safe Look ID", proposed)
	_check(not proposed.contains("/") and not proposed.contains("\\") and not proposed.contains(":"), "generated Look ID carries no path characters", proposed)

func _case_invalid_filename_chars() -> void:
	# Invalid characters in the NAME are data, never a filename: they must
	# round-trip verbatim.
	var hostile_name := "a/b\\c:d*e?f\"g<h>i|j"
	var look: Dictionary = _production_look("HOSTILE_NAME_LOOK", hostile_name)
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "hostile characters in a look name apply", str(applied.get("errors", [])))
	var loaded: Dictionary = prod.load_look("HOSTILE_NAME_LOOK")
	_check(str((loaded.get("doc", {}) as Dictionary).get("name", "")) == hostile_name, "hostile name characters round-trip verbatim",
		str((loaded.get("doc", {}) as Dictionary).get("name", "")))

	# A Look ID becomes a filename: a Windows-invalid id must not crash and must
	# not create a file outside looks/.
	var bad_id := "BAD:NAME*?"
	Engine.print_error_messages = false
	var bad_applied: Dictionary = prod.apply({"look": _production_look(bad_id, "Bad Id")})
	Engine.print_error_messages = true
	var bad_confined: bool = not FileAccess.file_exists(prod.look_path(bad_id))
	_check(not bool(bad_applied["ok"]) or bad_confined, "Windows-invalid look id is rejected or confined", str(bad_applied.get("stage", "")))
	_check(not prod.list_look_ids().has(bad_id), "Windows-invalid look id never becomes an unloadable Library entry", str(prod.list_look_ids()))

	# §23-FINDING candidate: a traversal id escapes the looks/ directory (still
	# inside data_dir) and the look then vanishes from the Library listing.
	var trav_dir := "user://vnext_unknown_trav"
	_wipe_dir(ProjectSettings.globalize_path(trav_dir))
	var trav = FxProductionScript.new()
	trav.data_dir = trav_dir
	var escaped_path := trav_dir + "/ESCAPED.json"
	var traversed: Dictionary = trav.apply({"look": _production_look("../ESCAPED", "Escape")})
	var escaped_exists: bool = FileAccess.file_exists(escaped_path)
	_check(not escaped_exists,
		"§23-FINDING: a look id with path separators never writes outside the looks directory",
		"apply_ok=%s outside=%s listed=%s" % [str(traversed["ok"]), str(escaped_exists), str(trav.list_look_ids())])
	_check(not (escaped_exists and not trav.list_look_ids().has("../ESCAPED")),
		"§23-FINDING: a committed look is always visible in the Library listing",
		"listed=%s" % str(trav.list_look_ids()))
	_wipe_dir(ProjectSettings.globalize_path(trav_dir))

# ================================================================ filesystem

func _case_unwritable_dirs() -> void:
	# A truly read-only directory cannot be created portably on Windows (the
	# read-only attribute is ignored for the owner), so unwritability is
	# simulated deterministically with a path that lives INSIDE a regular file:
	# every mkdir/open against it fails at the filesystem layer, exactly like a
	# permission failure.
	var block_file := scratch + "/blocker.txt"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
	_write_text(ProjectSettings.globalize_path(block_file), "block")
	var blocked = FxProductionScript.new()
	blocked.data_dir = block_file + "/data"
	Engine.print_error_messages = false
	var mkdir_rc: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked.data_dir))
	Engine.print_error_messages = true
	_check(mkdir_rc != OK, "unwritable data dir: mkdir reports an error code", "rc=%d" % mkdir_rc)
	Engine.print_error_messages = false
	var blocked_apply: Dictionary = blocked.apply({"look": _production_look("BLOCKED", "Blocked")})
	Engine.print_error_messages = true
	_check(not bool(blocked_apply["ok"]) and (blocked_apply.get("errors", []) as Array).size() > 0,
		"unwritable data dir: apply fails with a clear error", str(blocked_apply.get("stage", "")) + " " + str(blocked_apply.get("errors", [])))
	var blocked_drafts = FxDraftsScript.new()
	blocked_drafts.base_dir = block_file + "/drafts"
	Engine.print_error_messages = false
	var blocked_save: Dictionary = blocked_drafts.save_target("sig", _production_look("BLOCKED2", "Blocked 2"), 0)
	var blocked_load: Dictionary = blocked_drafts.load_target("sig")
	Engine.print_error_messages = true
	_check(not bool(blocked_save["ok"]), "unwritable draft dir: draft save fails cleanly", str(blocked_save.get("errors", [])))
	_check(not bool(blocked_load["ok"]) and bool(blocked_load.get("missing", false)), "unwritable draft dir: load reports a clean miss", str(blocked_load))
	# The evidence-dir convention must tolerate an unusable log directory.
	var bad_log := block_file + "/evidence/run.log"
	var f := FileAccess.open(bad_log, FileAccess.WRITE)
	var guarded := f == null
	if f != null:
		f.store_string("x")
		f.close()
	_check(guarded, "unwritable evidence dir: log open returns null instead of crashing")

func _case_interrupted_save_leftovers() -> void:
	var look: Dictionary = _production_look("LEFTOVER_LOOK", "Leftover Look")
	var applied: Dictionary = prod.apply({"look": look})
	_check(bool(applied["ok"]), "leftovers: baseline look applies", str(applied.get("errors", [])))
	var real_path := ProjectSettings.globalize_path(prod.look_path("LEFTOVER_LOOK"))
	var good_bytes := _file_bytes(real_path)

	# (a) A stale candidate next to a committed look must be ignored.
	_write_text(real_path + ".tmp", "{\"stale\": true}")
	_write_text(ProjectSettings.globalize_path(prod.assignments_path()) + ".tmp", "not json at all")
	_check(not prod.list_look_ids().has("LEFTOVER_LOOK.tmp"), "leftovers: .tmp never appears in the Library listing", str(prod.list_look_ids()))
	var loaded: Dictionary = prod.load_look("LEFTOVER_LOOK")
	_check(bool(loaded["ok"]) and str((loaded.get("doc", {}) as Dictionary).get("name", "")) == "Leftover Look",
		"leftovers: a stale .tmp is never interpreted as Production", str(loaded.get("errors", [])))
	_check(_file_bytes(real_path) == good_bytes, "leftovers: loading never rewrites the committed file")
	var state: Dictionary = prod.production_state()
	_check(bool(state["ok"]), "leftovers: a stale .tmp does not force recovery", str(state.get("errors", [])))
	DirAccess.remove_absolute(real_path + ".tmp")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prod.assignments_path()) + ".tmp")

	# (b) An orphan .tmp with no committed look must not be loaded either.
	_write_text(ProjectSettings.globalize_path(prod.look_path("ORPHAN_LOOK")) + ".tmp", str(FxLookScript.to_json(look)))
	var orphan: Dictionary = prod.load_look("ORPHAN_LOOK")
	_check(not bool(orphan["ok"]) and not bool(orphan.get("recovery_required", false)), "leftovers: an orphan .tmp is reported as a missing look", str(orphan.get("errors", [])))
	_check(not prod.list_look_ids().has("ORPHAN_LOOK"), "leftovers: an orphan .tmp is not listed as Production", str(prod.list_look_ids()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prod.look_path("ORPHAN_LOOK")) + ".tmp")

	# (c) The crash state between the two renames of a replace cycle: the
	# committed file is gone, the ".prev" sidecar holds the previous authority.
	# _read_json documents falling back to .prev in exactly this case, so the
	# look must either be recovered from it or be flagged for recovery.
	DirAccess.remove_absolute(real_path)
	_write_text(real_path + ".prev", good_bytes.get_string_from_utf8())
	Engine.print_error_messages = false
	var prev_loaded: Dictionary = prod.load_look("LEFTOVER_LOOK")
	Engine.print_error_messages = true
	_check(bool(prev_loaded["ok"]) or bool(prev_loaded.get("recovery_required", false)),
		"§23-FINDING: a .prev-only crash state is recovered or flagged for recovery",
		"ok=%s recovery=%s listed=%s" % [str(prev_loaded["ok"]), str(prev_loaded.get("recovery_required", false)), str(prod.list_look_ids())])
	DirAccess.remove_absolute(real_path + ".prev")

	# (d) The same .prev-only crash state for assignments: load_assignments has an
	# existence pre-check too, so the documented .prev fallback is skipped and a
	# vanished assignments file is answered with a VALID, EMPTY document (every
	# binding silently gone, recovery not flagged). The defensible invariant is
	# therefore: recover from the sidecar or flag recovery — never return an
	# empty-but-valid authority while its sidecar still exists.
	var base_look: Dictionary = _production_look("PREV_ASSIGN_LOOK", "Prev Assign Look")
	prod.apply({"look": base_look})
	var asg: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(asg, {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}, "PREV_ASSIGN_LOOK", "prev test")
	var asg_applied: Dictionary = prod.apply({"assignments": asg})
	_check(bool(asg_applied["ok"]), "leftovers: assignments baseline applies", str(asg_applied.get("errors", [])))
	var asg_path := ProjectSettings.globalize_path(prod.assignments_path())
	var asg_bytes := _file_bytes(asg_path)
	DirAccess.remove_absolute(asg_path)
	_write_text(asg_path + ".prev", asg_bytes.get_string_from_utf8())
	var recovered: Dictionary = prod.load_assignments()
	var recovered_bindings: int = ((recovered.get("doc", {}) as Dictionary).get("bindings", []) as Array).size()
	_check(recovered_bindings == 1 or bool(recovered.get("recovery_required", false)),
		"§23-FINDING: a .prev-only assignments state is recovered or flagged (never a silent empty authority)",
		"ok=%s bindings=%d recovery=%s prev_exists=%s" % [str(recovered.get("ok", false)), recovered_bindings, str(recovered.get("recovery_required", false)), str(FileAccess.file_exists(asg_path + ".prev"))])
	_write_text(asg_path, asg_bytes.get_string_from_utf8())
	DirAccess.remove_absolute(asg_path + ".prev")

# ================================================================ assets

func _case_custom_assets() -> void:
	var temp_dir := OS.get_environment("TEMP").replace("\\", "/") + "/fxlab_unknown_src"
	DirAccess.make_dir_recursive_absolute(temp_dir)

	# (a) missing external asset → clear error naming the file, before any write.
	var missing_ref := temp_dir + "/missing_mask.png"
	var missing_look: Dictionary = _look_with_asset("MISSING_ASSET_LOOK", "mask", missing_ref)
	var missing_applied: Dictionary = prod.apply({"look": missing_look})
	_check(not bool(missing_applied["ok"]) and str(missing_applied.get("stage", "")) == "assets",
		"missing custom asset is refused at the asset stage", str(missing_applied.get("stage", "")) + " " + str(missing_applied.get("errors", [])))
	_check(str(missing_applied.get("errors", [])).contains("missing_mask.png"), "missing custom asset error names the file", str(missing_applied.get("errors", [])))
	_check(not FileAccess.file_exists(prod.look_path("MISSING_ASSET_LOOK")), "missing custom asset writes no look")

	# (b) huge external asset (4 MB): imported project-local with identical bytes.
	var big_src := temp_dir + "/huge_mask.png"
	var blob := PackedByteArray()
	blob.resize(4 * 1024 * 1024)
	blob.fill(7)
	var blob_file := FileAccess.open(big_src, FileAccess.WRITE)
	if blob_file != null:
		blob_file.store_buffer(blob)
		blob_file.close()
	var big_look: Dictionary = _look_with_asset("HUGE_ASSET_LOOK", "mask", big_src)
	var big_applied: Dictionary = prod.apply({"look": big_look})
	_check(bool(big_applied["ok"]), "huge custom asset imports", str(big_applied.get("errors", [])))
	var big_loaded: Dictionary = prod.load_look("HUGE_ASSET_LOOK")
	var stored_ref := ""
	if bool(big_loaded["ok"]):
		stored_ref = str((((((big_loaded["doc"] as Dictionary)["layers"] as Array)[1] as Dictionary)["mask"] as Dictionary).get("custom_mask", "")))
	_check(stored_ref.begins_with(prod_dir + "/assets/") and not stored_ref.contains(":///") and not stored_ref.contains("Users") and not stored_ref.contains("AppData"),
		"huge custom asset is stored as an app-local project reference", stored_ref)
	_check(FileAccess.get_file_as_bytes(stored_ref) == blob, "huge custom asset bytes are identical after import", "n=%d" % FileAccess.get_file_as_bytes(stored_ref).size())

	# (c) An over-long external file name must not crash: either imported under a
	# bounded name or refused with a clear error (filesystem domain).
	var long_src := temp_dir + "/" + "x".repeat(180) + ".png"
	_write_text(long_src, "tiny")
	if FileAccess.file_exists(long_src):
		var long_look: Dictionary = _look_with_asset("LONG_ASSET_LOOK", "mask", long_src)
		Engine.print_error_messages = false
		var long_applied: Dictionary = prod.apply({"look": long_look})
		Engine.print_error_messages = true
		var long_clean: bool = bool(long_applied["ok"]) or str(long_applied.get("stage", "")) == "assets" or str(long_applied.get("stage", "")) == "write"
		_check(long_clean, "over-long external asset name is imported or refused cleanly",
			str(long_applied.get("stage", "")) + " " + str(long_applied.get("errors", [])))
	else:
		_check(false, "over-long external asset name: fixture could not be created")

	# (d) A directory used as an asset reference is not a file: clear error.
	var dir_look: Dictionary = _look_with_asset("DIR_ASSET_LOOK", "mask", temp_dir)
	var dir_applied: Dictionary = prod.apply({"look": dir_look})
	_check(not bool(dir_applied["ok"]) and str(dir_applied.get("stage", "")) == "assets",
		"a directory used as a custom asset is refused cleanly", str(dir_applied.get("errors", [])))

	# (e) A project-local ref that does not exist is rejected by validation.
	var ghost_look: Dictionary = _look_with_asset("GHOST_ASSET_LOOK", "mask", "res://assets/does_not_exist.png")
	var ghost_applied: Dictionary = prod.apply({"look": ghost_look})
	_check(not bool(ghost_applied["ok"]) and str(ghost_applied.get("errors", [])).contains("does not exist"),
		"missing project-local asset reference is rejected with a diagnostic", str(ghost_applied.get("errors", [])))
	_wipe_dir(temp_dir)

# ================================================================ textures

func _case_texture_edge_cases() -> void:
	var temp_dir := OS.get_environment("TEMP").replace("\\", "/") + "/fxlab_unknown_tex"
	DirAccess.make_dir_recursive_absolute(temp_dir)

	# (a) fully transparent source texture — a legal state, never a crash.
	var clear_path := temp_dir + "/clear.png"
	var clear_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	clear_img.fill(Color(1, 1, 1, 0))
	clear_img.save_png(clear_path)
	var clear_loaded: Image = _load_texture_image(clear_path)
	var clear_ok: bool = clear_loaded != null and clear_loaded.get_size() == Vector2i(64, 64)
	_check(clear_ok and clear_loaded.get_pixel(32, 32).a == 0.0, "fully transparent source texture loads with alpha 0",
		str(clear_loaded.get_pixel(32, 32)) if clear_ok else "unreadable")
	if clear_ok:
		var clear_tex := ImageTexture.create_from_image(clear_loaded)
		var clear_reg = _synthetic_registry([{"name": "echo_left", "size": Vector2(64, 64), "texture": clear_tex}], "1v1", "debug")
		_check(clear_reg.keys().has("echo_left"), "fully transparent source is still a legal target", str(clear_reg.keys()))
		_check(bool(FxLookScript.validate(_production_look("CLEAR_TEX_LOOK", "Clear Tex"))["ok"]), "a look for a transparent target validates")

	# (b) 1x1 tiny source: the presentation helpers must stay finite and >= 1.
	var tiny_path := temp_dir + "/tiny.png"
	var tiny_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	tiny_img.fill(Color(1, 0, 0, 1))
	tiny_img.save_png(tiny_path)
	var tiny_loaded: Image = _load_texture_image(tiny_path)
	_check(tiny_loaded != null and tiny_loaded.get_size() == Vector2i(1, 1), "1x1 source texture round-trips through PNG",
		str(tiny_loaded.get_size()) if tiny_loaded != null else "unreadable")
	if tiny_loaded != null:
		var tiny_tex := ImageTexture.create_from_image(tiny_loaded)
		var tiny_reg = _synthetic_registry([{"name": "primary_left", "size": Vector2(1, 1), "texture": tiny_tex}], "1v1", "debug")
		var tiny_node = tiny_reg.target_node("primary_left")
		var tiny_size: Vector2 = FxTargetsScript.raw_presentation_size(tiny_node, tiny_node.texture)
		_check(is_finite(tiny_size.x) and is_finite(tiny_size.y) and tiny_size.x >= 1.0 and tiny_size.y >= 1.0,
			"1x1 source yields a finite, non-degenerate presentation size", str(tiny_size))
		var tiny_rect: Rect2 = FxTargetsScript.presentation_rect(tiny_node)
		_check(is_finite(tiny_rect.size.x) and is_finite(tiny_rect.size.y), "1x1 source yields a finite presentation rect", str(tiny_rect))
		var zero_node := TextureRect.new()
		zero_node.texture = tiny_tex
		zero_node.size = Vector2.ZERO
		var zero_size: Vector2 = FxTargetsScript.raw_presentation_size(zero_node, tiny_tex)
		_check(is_finite(zero_size.x) and zero_size.x >= 1.0 and zero_size.y >= 1.0, "zero-sized target falls back to the texture size", str(zero_size))
		zero_node.free()

	# (c) unusual aspect ratio target (16:1) — no division-by-zero artefacts.
	var odd_img := Image.create(1024, 64, false, Image.FORMAT_RGBA8)
	odd_img.fill(Color(0.2, 0.4, 0.8, 1.0))
	var odd_tex := ImageTexture.create_from_image(odd_img)
	var odd_reg = _synthetic_registry([{"name": "stage", "size": Vector2(1024, 64), "texture": odd_tex}], "1v1", "debug")
	var odd_node = odd_reg.target_node("stage")
	var odd_size: Vector2 = FxTargetsScript.raw_presentation_size(odd_node, odd_node.texture)
	_check(odd_size == Vector2(1024, 64), "unusual aspect ratio target keeps its presentation size", str(odd_size))
	_check(str(odd_reg.context_for_key("stage").get("element_role", "")) == "stage", "unusual aspect ratio target keeps its semantic role")

	# (d) A mask whose resolution differs from the source is imported untouched
	# (the mask is sampled in UV space, so a resolution mismatch is legal and
	# must not trigger a resample or a rejection).
	var mask_path := temp_dir + "/odd_mask.png"
	var mask_img := Image.create(7, 3, false, Image.FORMAT_RGBA8)
	mask_img.fill(Color(1, 1, 1, 0.5))
	mask_img.save_png(mask_path)
	var mask_bytes := FileAccess.get_file_as_bytes(mask_path)
	var mask_look: Dictionary = _look_with_asset("ODD_MASK_LOOK", "mask", mask_path)
	var mask_applied: Dictionary = prod.apply({"look": mask_look})
	_check(bool(mask_applied["ok"]), "mask with a different resolution than the source applies", str(mask_applied.get("errors", [])))
	var mask_loaded: Dictionary = prod.load_look("ODD_MASK_LOOK")
	var mask_ref := ""
	if bool(mask_loaded["ok"]):
		var mask_loaded_doc: Dictionary = mask_loaded.get("doc", {})
		var mask_layers: Array = mask_loaded_doc.get("layers", [])
		if mask_layers.size() > 1:
			var mask_layer: Dictionary = mask_layers[1]
			mask_ref = str((mask_layer.get("mask", {}) as Dictionary).get("custom_mask", ""))
	var stored_img: Image = _load_texture_image(mask_ref) if mask_ref != "" else null
	_check(stored_img != null and stored_img.get_size() == Vector2i(7, 3), "mask resolution is preserved through import (no resample)",
		str(stored_img.get_size()) if stored_img != null else "missing ref=%s" % mask_ref)
	_check(mask_ref != "" and mask_ref.begins_with(prod_dir + "/assets/"), "the persisted look stores the imported mask reference", mask_ref)
	_check(mask_ref != "" and FileAccess.get_file_as_bytes(mask_ref) == mask_bytes, "mask bytes are identical after import")
	_wipe_dir(temp_dir)

func _load_texture_image(path: String) -> Image:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)

# ================================================================ assignments / schema / material

func _case_stale_target_ids() -> void:
	# A binding whose selector field is not part of the selector schema is
	# dropped during normalization; if nothing survives, the binding is refused
	# instead of silently becoming universal.
	var asg: Dictionary = FxResolverScript.new_assignments()
	asg["bindings"].append({
		"binding_id": "binding-0001-stale",
		"selector": {"target_key": "ghost_left"},
		"look_id": "DUP_FIGHTER_A",
		"enabled": true,
	})
	var stale_applied: Dictionary = prod.apply({"assignments": asg})
	_check(not bool(stale_applied["ok"]) and str(stale_applied.get("stage", "")) == "validate-assignments",
		"unknown selector field is refused (never a universal binding)", str(stale_applied.get("errors", [])))

	# A stale element identity must not match any real target.
	var stale: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(stale, {"element_id": "ghost_left", "stage_id": "debug"}, "DUP_FIGHTER_B", "stale target")
	var stale_applied2: Dictionary = prod.apply({"assignments": stale})
	_check(bool(stale_applied2["ok"]), "stale but well-formed selector can be stored", str(stale_applied2.get("errors", [])))
	var matched := 0
	for key in ["echo_left", "echo_right", "primary_left", "primary_right", "mark", "stage", "name_left", "name_right"]:
		var ctx := {"element_id": key, "element_role": key, "visual_side": "left", "mode_family": "1v1", "stage_id": "debug"}
		if str(FxResolverScript.resolve(stale, ctx)["status"]) != "UNASSIGNED":
			matched += 1
	_check(matched == 0, "stale target id never applies to a different target", "matched=%d" % matched)

	# A corrupt stored look must never be silently overwritten by an update.
	var corrupt_id := "CORRUPT_LOOK"
	var fresh: Dictionary = prod.apply({"look": _production_look(corrupt_id, "Corrupt Look")})
	_check(bool(fresh["ok"]), "stale ids: baseline look applies", str(fresh.get("errors", [])))
	_write_text(ProjectSettings.globalize_path(prod.look_path(corrupt_id)), "{ this is not json")
	Engine.print_error_messages = false
	var update: Dictionary = prod.apply({"look": _production_look(corrupt_id, "Corrupt Look")})
	Engine.print_error_messages = true
	_check(not bool(update["ok"]) and str(update.get("stage", "")) == "revision",
		"an update against a corrupt stored look is refused", str(update.get("stage", "")) + " " + str(update.get("errors", [])))
	_check(str(update.get("errors", [])).contains("unreadable"), "the refusal explains that Production is unreadable", str(update.get("errors", [])))
	_check(_file_bytes(ProjectSettings.globalize_path(prod.look_path(corrupt_id))).get_string_from_utf8() == "{ this is not json",
		"the corrupt file is left for the recovery flow (not overwritten)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prod.look_path(corrupt_id)))

	# Re-write clean assignments so later cases start from a valid state.
	var clean: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(clean, {"element_id": "ghost_left", "stage_id": "debug"}, "DUP_FIGHTER_B", "stale target")
	var clean_applied: Dictionary = prod.apply({"assignments": clean})
	_check(bool(clean_applied["ok"]), "assignments restore to a valid document", str(clean_applied.get("errors", [])))

func _case_future_schema() -> void:
	var future_dir := "user://vnext_unknown_future"
	_wipe_dir(ProjectSettings.globalize_path(future_dir))
	var future = FxProductionScript.new()
	future.data_dir = future_dir
	future.ensure_dirs()
	var doc: Dictionary = _production_look("FUTURE_LOOK", "Future Look")
	doc["schema"] = "NRCU_FX_LOOK_V0_9"
	var path := ProjectSettings.globalize_path(future.look_path("FUTURE_LOOK"))
	_write_text(path, str(FxLookScript.to_json(doc)))
	var bytes := _file_bytes(path)
	Engine.print_error_messages = false
	var loaded: Dictionary = future.load_look("FUTURE_LOOK")
	Engine.print_error_messages = true
	_check(not bool(loaded["ok"]) and bool(loaded["recovery_required"]), "future look schema is rejected and flagged for recovery", str(loaded.get("errors", [])))
	_check(str(loaded.get("errors", [])).contains("NRCU_FX_LOOK_V0_4"), "future schema error names the expected schema", str(loaded.get("errors", [])))
	_check(_file_bytes(path) == bytes, "future schema file is left byte-identical (no destructive fixup)")
	_check(not bool(future.production_state()["ok"]), "production_state reports the future-schema look")

	var asg_path := ProjectSettings.globalize_path(future.assignments_path())
	var asg_doc: Dictionary = FxResolverScript.new_assignments()
	asg_doc["schema"] = "NRCU_VS_FX_ASSIGNMENTS_V9"
	_write_text(asg_path, str(JSON.stringify(asg_doc)))
	var asg_loaded: Dictionary = future.load_assignments()
	_check(not bool(asg_loaded["ok"]) and bool(asg_loaded["recovery_required"]), "future assignments schema is rejected and flagged", str(asg_loaded.get("errors", [])))
	var schema_missing: Dictionary = _production_look("NO_SCHEMA", "No Schema")
	schema_missing.erase("schema")
	_check(not bool(FxLookScript.validate(schema_missing)["ok"]), "a look without a schema field is rejected")

func _case_material_misuse() -> void:
	var renderer = FxLayerRendererScript.new(null, null)
	var material := ShaderMaterial.new()
	material.shader = renderer._shader
	# Invalid shader PARAMETER names and wrong-typed values must not crash.
	Engine.print_error_messages = false
	material.set_shader_parameter("definitely_not_a_uniform", 1.0)
	material.set_shader_parameter("layer_opacity", [1.0, 2.0, 3.0])
	material.set_shader_parameter("position_px", "not a vector")
	material.set_shader_parameter("source_tex", 5)
	Engine.print_error_messages = true
	var hostile_echo = material.get_shader_parameter("layer_opacity")
	_check(hostile_echo is Array and (hostile_echo as Array).size() == 3,
		"hostile parameter values are accepted without aborting the material", "layer_opacity=%s" % str(hostile_echo))
	# The material stays usable afterwards: a legal value still lands.
	material.set_shader_parameter("layer_opacity", 0.25)
	_check(float(material.get_shader_parameter("layer_opacity")) == 0.25, "the material remains usable after hostile parameters",
		str(material.get_shader_parameter("layer_opacity")))

	# Garbage fx/motion dictionaries: the renderer's coercion helpers are
	# documented per-field fallbacks (float("junk") -> 0.0, _vec2 of a non-array
	# -> Vector2.ZERO), so a hostile STRING/BOOL must not poison the uniforms.
	Engine.print_error_messages = false
	renderer._set_fx_uniforms(material, {"size": "junk", "intensity": true, "rgb_shift_amount": "x", "color_blur": 1.0e30, "time_source": 5, "palette_source_color": "not-a-color"}, {"enabled": {"dither": true}, "tracks": {"dither": {"attack": "junk"}}})
	Engine.print_error_messages = true
	var coerced_size = material.get_shader_parameter("fx_size")
	var coerced_blur = material.get_shader_parameter("fx_color_blur")
	# R3 note: the finite-default for a hostile value is the field's NEUTRAL
	# (fx_size neutral = 1.0, identical to the shader default) - not numeric zero,
	# which would silently blank the parameter.
	_check(coerced_size is float and is_finite(float(coerced_size)) and float(coerced_size) == 1.0,
		"a hostile string fx value falls back to a finite default", "fx_size=%s" % str(coerced_size))
	# NOTE: shader uniforms are float32; compare huge values with a relative
	# tolerance (a double equality against 1.0e30 can never hold).
	_check(coerced_blur is float and is_finite(float(coerced_blur)) and absf(float(coerced_blur) / 1.0e30 - 1.0) < 1.0e-4,
		"the remaining fx values still reach the shader after a coercible hostile value", "fx_color_blur=%s" % str(coerced_blur))

	# §23-FINDING candidate: a hostile TYPE that the coercion helpers cannot
	# absorb (`float([1, 2])`) aborts the whole uniform push, so the documented
	# per-field fallback never runs and EVERY uniform of the layer is dropped —
	# silently in a release log, with only a script error in the editor log.
	Engine.print_error_messages = false
	renderer._set_fx_uniforms(material, {"fringe": [1, 2], "color_blur": 2.5e30}, {})
	Engine.print_error_messages = true
	var after_abort = material.get_shader_parameter("fx_color_blur")
	# float32 uniform tolerance (a double equality against 2.5e30 cannot hold)
	_check(after_abort is float and absf(float(after_abort) / 2.5e30 - 1.0) < 1.0e-4,
		"§23-FINDING: a hostile array in one numeric fx field does not drop every other uniform",
		"fx_color_blur=%s (expected 2.5e+30)" % str(after_abort))

	# A hostile TYPE in a numeric field of a real Look must be refused by the
	# validator rather than silently persisted (the validator and the renderer
	# must not disagree about what a number is).
	var poison: Dictionary = _production_look("POISON_TYPE_LOOK", "Poison Type")
	var poison_layer: Dictionary = (poison["layers"] as Array)[1]
	poison_layer["fx"]["size"] = [1, 2]
	Engine.print_error_messages = false
	var poison_result = FxLookScript.validate(FxLookScript.materialize(poison))
	Engine.print_error_messages = true
	_check(poison_result is Dictionary and not bool((poison_result as Dictionary).get("ok", true)),
		"a hostile TYPE in a numeric fx field is refused by the validator", str(poison_result))

	var canonical := TextureRect.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2i(64, 64)
	canonical.texture = tex
	var layer: Dictionary = FxLookScript.new_layer("FX", "Misuse")
	var quad: Control = renderer._make_quad(canonical, Rect2(0.0, 0.0, 1280.0, 720.0), Color.WHITE, layer)
	_check(quad != null and quad.material is ShaderMaterial, "the renderer still builds quads after material misuse")
	# A material whose shader is a minimal valid program (no matching uniforms)
	# must accept the same parameter push without a compile failure.
	var minimal := Shader.new()
	minimal.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n"
	var minimal_material := ShaderMaterial.new()
	minimal_material.shader = minimal
	minimal_material.set_shader_parameter("layer_opacity", 0.5)
	_check(minimal_material.shader != null, "a material with an unrelated shader tolerates parameter pushes")
	if quad != null:
		quad.free()
	canonical.free()

# ================================================================ helpers

func _synthetic_screen(specs: Array) -> Node:
	var screen := Node.new()
	screen.name = "Screen"
	var root_node := Node2D.new()
	root_node.name = "Root"
	screen.add_child(root_node)
	for raw in specs:
		var spec: Dictionary = raw
		var tr := TextureRect.new()
		tr.name = str(spec.get("name", "slot"))
		var texture = spec.get("texture", null)
		if texture == null:
			var placeholder := PlaceholderTexture2D.new()
			placeholder.size = Vector2i(64, 64)
			texture = placeholder
		tr.texture = texture
		tr.size = spec.get("size", Vector2(64, 64))
		if str(spec.get("fighter", "")) != "":
			tr.set_meta("fx_fighter_id", str(spec["fighter"]))
		if str(spec.get("element", "")) != "":
			tr.set_meta("fx_element_id", str(spec["element"]))
		root_node.add_child(tr)
	_owned.append(screen)
	return screen

func _synthetic_registry(specs: Array, mode: String, stage: String):
	var reg = FxTargetsScript.new()
	reg.bind_screen(_synthetic_screen(specs), mode, stage)
	return reg

func _production_look(look_id: String, display_name: String) -> Dictionary:
	var look: Dictionary = FxLookScript.new_look(look_id, display_name, "PRODUCTION")
	var layer: Dictionary = FxLookScript.new_layer("FX", "FX Layer")
	layer["fx"]["fringe"] = 0.4
	layer["fx"]["rgb_shift_amount"] = 6.0
	look["layers"].append(layer)
	return look

func _look_with_asset(look_id: String, field: String, ref: String) -> Dictionary:
	var look: Dictionary = _production_look(look_id, look_id)
	var layer: Dictionary = (look["layers"] as Array)[1]
	if field == "mask":
		layer["mask"] = {"enabled": true, "source": "CUSTOM_MASK", "custom_mask": ref}
	else:
		layer["displacement"] = {"enabled": true, "driver": "CUSTOM_TEXTURE", "custom_texture": ref}
	return look

func _signature_fields(signature: String) -> int:
	return signature.split("|").size()

func _unique(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out

func settle(n: int) -> void:
	for i in n:
		await process_frame

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
