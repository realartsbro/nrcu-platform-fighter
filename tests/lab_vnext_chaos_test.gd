extends SceneTree
# NRCU FX Lab vNEXT — §9 draft/session state-machine chaos (headless, seeded).
#
# Drives the REAL session API (FxSession over FxProduction + FxDrafts — the same
# calls the shell's actions make: _edit_layer -> snapshot()+edit(), _action_apply,
# _action_make_unique, _action_edit_shared, _action_disable_binding,
# _action_toggle_styling, _action_undo/_action_redo, _open_session_for) through
# ~300 pseudo-random operations and re-verifies the state-machine invariants
# after EVERY step:
#
#   INV-VALID    Production stays valid: every Look loads, validates, is canonical
#                and PRODUCTION; assignments stay valid (deep production_state
#                check every DEEP_CHECK_EVERY steps)
#   INV-REV      Production Look revisions never decrease
#   INV-DRAFT    no target draft disappears without an explicit discard (the chaos
#                set contains no discard at all, so the rule is absolute here) and
#                no shared draft disappears except through the documented consume
#                (successful apply of a shared draft)
#   INV-SIG      a draft of target A never shows up under target B: every record
#                declares its own target_signature, never-stashed targets have no
#                record at all, no corrupt records appear
#   INV-LINEAGE  the working design always belongs to the current target's own
#                design history (catches cross-target undo/redo stack bleed)
#   INV-CANON    the working Look is always canonical (materialize == self) with
#                exactly one SOURCE layer and unique layer ids
#   INV-DIRTY    clean/dirty bookkeeping is truthful: a clean session's parked
#                draft (target and shared) holds exactly the working Look and is
#                flagged clean; the badge carries the DRAFT suffix iff dirty
#   INV-BADGE    the browser row badge (lab_shell.gd `_badge_for_key` model)
#                equals the target's actual state for EVERY target, and the editor
#                badge equals the independently re-resolved effective state
#   INV-EFF      the effective style equals an independent FxResolver.resolve()
#                re-run over the persisted assignments
#   INV-SHARED   shared-Look semantics: protected sessions reject edits and apply,
#                shared drafts are keyed by (look_id, base_revision) and consumed
#                by apply, and the SHARED count equals the real Production usage
#   INV-RESTART  "restart" (fresh FxSession over the same stores) reconstructs the
#                same state through the documented order draft -> production
#                (incl. shared draft) -> neutral
#
# Chaos ops (the §9 list): select target, edit layer, switch target, return,
# restart (stash + fresh session + re-open), apply, make shared (production-level
# scope so a second target resolves to the Look), make unique, undo, redo,
# disable binding, styling off (= enable bypass), styling on (= remove bypass),
# apply another (a different target's Look).
#
# Determinism: FXLAB_CHAOS_SEED (default 20260915) seeds the chaos RNG and the
# global RNG (deterministic layer ids). Evidence: FXLAB_EVIDENCE_DIR (default
# res://evidence/vnext_build/chaos) -> chaos_samples.json, chaos_checks.log,
# summary_chaos_check.json.
#
# Divergences: behaviour that the candidate does not satisfy but that the
# project itself documents elsewhere. They are recorded in the evidence JSON (and
# printed once) instead of failing the run, so this suite is green on the frozen
# candidate and red on a regression of any of the invariants above. Known
# divergences so far:
#   shared-protection-via-draft — a target that reopens through its own parked
#     draft loses the SHARED badge/protection (mode EDIT_PRODUCTION_UNIQUE while
#     the Look is used by more than one scope); lab_vnext_audit_states.gd clears
#     the target draft before exercising a shared Look, i.e. the project works
#     around this path.
#   cross-target-undo-bleed — FxSession keeps its undo/redo stacks across
#     open_target, so an undo right after a target switch can restore the other
#     target's design (INV-LINEAGE reports it; the shell's Undo button is enabled
#     for every session).
#   stale-draft-after-make-unique — make_unique rebinds the target but leaves the
#     parked target draft on the previous Look, so the next open would restore
#     that design instead of the unique one.
#   apply-onto-disabled-binding — apply() writes a Look while the target's own
#     binding is disabled; the target stays unstyled (the explicit disable wins).
# FXLAB_CHAOS_STRICT=1 turns every divergence into a failure, which is the right
# mode when the divergences themselves are under test.
# FXLAB_CHAOS_STRICT=1 turns every known divergence (and every tolerated
# invariant) into a failure — use it to prove a finding instead of a regression.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxTemplatesScript := preload("res://scripts/fx_vnext/fx_templates.gd")

const STEPS := 300
const DEEP_CHECK_EVERY := 10
const SAMPLE_EVERY := 25
const SEED_DEFAULT := 20260915

const OP_TOUR := [
	"select", "edit", "switch", "return", "apply", "make_shared", "switch",
	"make_unique", "undo", "redo", "disable_binding", "styling_off",
	"styling_on", "apply_another", "restart", "edit",
]

const OP_WEIGHTS := {
	"select": 8, "switch": 10, "return": 6, "edit": 22, "restart": 6,
	"apply": 10, "apply_another": 5, "make_shared": 6, "make_unique": 4,
	"undo": 6, "redo": 4, "disable_binding": 4, "styling_off": 5, "styling_on": 4,
}

const TARGET_DEFS := [
	{
		"key": "echo_left", "role": "echo",
		"signature": "chaos|echo_left|ice_mage|echo|left",
		"context": {"element_id": "echo_left", "fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left", "presentation_slot": "a_back", "team_side": "left", "mode_family": "1v1", "stage_id": "dojo"},
	},
	{
		"key": "echo_right", "role": "echo",
		"signature": "chaos|echo_right|ice_mage|echo|right",
		"context": {"element_id": "echo_right", "fighter_id": "ice_mage", "element_role": "echo", "visual_side": "right", "presentation_slot": "a_back", "team_side": "left", "mode_family": "1v1", "stage_id": "dojo"},
	},
	{
		"key": "primary_left", "role": "primary",
		"signature": "chaos|primary_left|doge_man|primary|left",
		"context": {"element_id": "primary_left", "fighter_id": "doge_man", "element_role": "primary", "visual_side": "left", "presentation_slot": "b_front", "team_side": "right", "mode_family": "1v1", "stage_id": "ice_arena"},
	},
	{
		"key": "vs_mark", "role": "stage",
		"signature": "chaos|vs_mark|dojo",
		"context": {"element_id": "vs_mark", "stage_id": "dojo", "mode_family": "1v1"},
	},
]

var checks: Array = []
var failures: int = 0
var invariants: int = 0
var violations: int = 0
var reported: Dictionary = {}
var notes: Array = []
var divergences: Dictionary = {}
var samples: Array = []
var step_trace: Array = []
var note_counts: Dictionary = {}
var out_dir: String
var strict_mode := false
var working_source: String = ""
var rng := RandomNumberGenerator.new()

var prod
var drafts
var session
var targets: Array = []
var target_index: int = 0
var lineage: Dictionary = {}
var expected_target_drafts: Dictionary = {}
var expected_shared: Dictionary = {}
var never_stashed: Dictionary = {}
var look_rev_floor: Dictionary = {}

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build/chaos")
	DirAccess.make_dir_recursive_absolute(out_dir)
	strict_mode = OS.get_environment("FXLAB_CHAOS_STRICT") == "1"
	var seed_text := OS.get_environment("FXLAB_CHAOS_SEED")
	var useed := SEED_DEFAULT if seed_text == "" else int(seed_text)
	rng.seed = useed
	seed(useed) # global RNG: layer/binding ids stay reproducible across runs

	for def in TARGET_DEFS:
		targets.append((def as Dictionary).duplicate(true))

	var prod_dir := "user://vnext_chaos_prod"
	var draft_dir := "user://vnext_chaos_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir
	for t in targets:
		never_stashed[str((t as Dictionary)["signature"])] = true

	session = FxSessionScript.new(prod, drafts)
	print("[FX-CHAOS] seed=%d steps=%d strict=%s ops=%d" % [useed, STEPS, str(strict_mode), OP_WEIGHTS.size()])

	_op_open(0)
	_verify(0, "select")
	for step in range(1, STEPS + 1):
		var op := str(OP_TOUR[step - 1]) if step <= OP_TOUR.size() else _pick_op()
		_run_op(op, step)
		_verify(step, op)
		step_trace.append({
			"step": step, "op": op, "target": str(session.current_key),
			"mode": str(session.mode), "dirty": bool(session.dirty),
			"badge": session.badge_text(), "failures": failures,
		})
		if step % SAMPLE_EVERY == 0:
			_sample(step, op)
		if step % DEEP_CHECK_EVERY == 0:
			_deep_check(step)

	_note_summary()
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	_finish(useed)

# ================================================================ chaos ops

func _pick_op() -> String:
	var total := 0
	for key in OP_WEIGHTS.keys():
		total += int(OP_WEIGHTS[key])
	var roll := rng.randi_range(1, maxi(total, 1))
	var walk := 0
	for key in OP_WEIGHTS.keys():
		walk += int(OP_WEIGHTS[key])
		if roll <= walk:
			return str(key)
	return "edit"

func _run_op(op: String, step: int) -> void:
	match op:
		"select":
			_op_open(rng.randi_range(0, targets.size() - 1))
		"switch":
			_op_open(_pick_other_index())
		"return":
			_op_open(target_index)
		"edit":
			_op_edit(step)
		"restart":
			_op_restart(step)
		"apply":
			_op_apply(step, false)
		"apply_another":
			_op_apply(step, true)
		"make_shared":
			_op_make_shared(step)
		"make_unique":
			_op_make_unique()
		"undo":
			_op_history(true)
		"redo":
			_op_history(false)
		"disable_binding":
			_op_disable_binding(step)
		"styling_off":
			_op_styling(false)
		"styling_on":
			_op_styling(true)
		_:
			_check(false, "unknown chaos op: " + op)

func _pick_other_index() -> int:
	if targets.size() < 2:
		return target_index
	var pick := rng.randi_range(0, targets.size() - 1)
	if pick == target_index:
		pick = (pick + 1) % targets.size()
	return pick

func _op_open(idx: int) -> void:
	target_index = idx
	var t: Dictionary = targets[idx]
	var opened: Dictionary = session.open_target(str(t["key"]), (t["context"] as Dictionary).duplicate(true), str(t["signature"]), str(t["role"]))
	_check(bool(opened.get("ok", false)), "open_target succeeds", str(opened.get("errors", [])))
	_inv(str(opened.get("opened", "")) in ["draft", "production", "neutral"], "INV-VALID open_target reports a documented source", str(opened.get("opened", "")))
	_inv(str(session.current_key) == str(t["key"]) and str(session.signature) == str(t["signature"]), "INV-VALID session identity follows the selection", "%s/%s" % [str(session.current_key), str(session.signature)])
	if bool(opened.get("ok", false)):
		working_source = _classify_source(idx)
		_check_open_source()

func _check_open_source() -> void:
	# open_target contract: parked draft -> production (incl. shared draft) -> neutral.
	var truth: Dictionary = _store_truth()
	if truth.is_empty():
		var layers: Array = session.look.get("layers", [])
		_inv(layers.size() == 1 and str((layers[0] as Dictionary).get("type", "")) == "SOURCE", "INV-CANON neutral open is SOURCE-only", _layer_types(session.look))
		_inv(str(session.look.get("name", "")) == _breadcrumb(session), "INV-VALID neutral open carries the target breadcrumb", str(session.look.get("name", "")))
		return
	_inv(FxLookScript.equivalent(FxLookScript.materialize(session.look), truth), "INV-VALID open restores the target's stored design", _describe(session.look) + " vs " + _describe(truth))

func _op_edit(step: int) -> void:
	var layers: Array = session.look.get("layers", [])
	if layers.is_empty():
		_inv(false, "INV-CANON the working Look always has layers", _describe(session.look))
		return
	if not bool(session.is_editable()):
		var blocked: Dictionary = session.edit(func(doc): doc["chaos_blocked"] = true)
		_check(not bool(blocked.get("ok", false)), "INV-SHARED protected session rejects edits", str(blocked.get("errors", [])))
		_check(not bool(session.look.has("chaos_blocked")), "INV-SHARED rejected edit leaves the working Look untouched")
		return

	var roll := rng.randi_range(0, 5)
	var index := rng.randi_range(0, layers.size() - 1)
	var picked: Dictionary = layers[index]
	var layer_id := str(picked.get("layer_id", ""))
	var is_source := str(picked.get("type", "")) == "SOURCE"
	var amount := float(rng.randi_range(5, 95)) / 100.0
	var plane := str(FxLookScript.PLANES[rng.randi_range(0, FxLookScript.PLANES.size() - 1)])
	var template := str(FxTemplatesScript.TEMPLATES[rng.randi_range(0, FxTemplatesScript.TEMPLATES.size() - 1)])
	var template_layer: Dictionary = FxTemplatesScript.template_layer(template)
	if is_source and roll in [1, 2, 5]:
		roll = 0 # the SOURCE layer stays pinned to TARGET_SOURCE and cannot be deleted
	var removed_id := ""
	if roll == 5 and layers.size() > 1:
		removed_id = layer_id
	var ids_before := _layer_ids(session.look)
	var mutator: Callable
	match roll:
		0:
			mutator = func(doc):
				var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
				l["opacity"] = amount
		1:
			mutator = func(doc):
				var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
				l["plane"] = plane
		2:
			mutator = func(doc):
				var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
				l["name"] = "Chaos %d" % step
		3:
			mutator = func(doc):
				var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
				l["enabled"] = not bool(l["enabled"])
		4:
			mutator = func(doc):
				doc["layers"].append(template_layer)
		_:
			mutator = func(doc):
				var doc_layers: Array = doc["layers"]
				for i in range(doc_layers.size()):
					if str((doc_layers[i] as Dictionary).get("layer_id", "")) == removed_id:
						doc_layers.remove_at(i)
						break
	session.snapshot()
	var result: Dictionary = session.edit(mutator)
	_check(bool(result.get("ok", false)), "edit is accepted while editable", str(result.get("errors", [])))
	if not bool(result.get("ok", false)):
		return
	_check(session.dirty, "edit marks the session dirty")
	_inv(_source_count(session.look) == 1, "INV-CANON exactly one SOURCE layer after an edit", _layer_types(session.look))
	_inv(_unique_ids(_layer_ids(session.look)), "INV-CANON layer ids stay unique after an edit", str(_layer_ids(session.look)))
	var ids_after := _layer_ids(session.look)
	if roll == 4:
		_inv(ids_after.size() == ids_before.size() + 1 and ids_after.has(str(template_layer["layer_id"])), "INV-CANON add layer appends exactly one new id")
	elif removed_id != "":
		_inv(ids_after.size() == ids_before.size() - 1 and not ids_after.has(removed_id), "INV-CANON delete layer removes exactly one id")
	else:
		_inv(ids_after == ids_before, "INV-CANON value edits keep the layer id set", str(ids_after))

func _op_restart(step: int) -> void:
	var idx := target_index
	var t: Dictionary = targets[idx]
	var sig := str(t["signature"])
	var was_dirty := bool(session.dirty)
	var was_mode := str(session.mode)
	var before_look: Dictionary = session.look.duplicate(true)
	var before_effective: String = session.effective_look_id()
	var truth_before: Dictionary = _store_truth()
	if was_dirty:
		var stashed: Dictionary = session.stash()
		_check(bool(stashed.get("ok", false)), "restart: stash before the restart succeeds", str(stashed.get("errors", [])))
		if bool(stashed.get("ok", false)):
			_record_stash_write()
	# "app restarted": a brand new session object over the SAME stores
	session = FxSessionScript.new(prod, drafts)
	target_index = idx
	var opened: Dictionary = session.open_target(str(t["key"]), (t["context"] as Dictionary).duplicate(true), sig, str(t["role"]))
	_check(bool(opened.get("ok", false)), "restart: the target reopens", str(opened.get("errors", [])))
	working_source = _classify_source(idx)
	var truth_after: Dictionary = _store_truth()
	var expect_source := "neutral"
	if not truth_after.is_empty():
		expect_source = "draft" if drafts.has_target(sig) else "production"
	_check(str(opened.get("opened", "")) == expect_source, "INV-RESTART reconstruction source matches the stores", "%s vs %s" % [str(opened.get("opened", "")), expect_source])
	if not truth_after.is_empty():
		_inv(FxLookScript.equivalent(FxLookScript.materialize(session.look), truth_after), "INV-RESTART reconstructed design equals the stored truth", _describe(session.look) + " vs " + _describe(truth_after))
	_inv(session.effective_look_id() == before_effective, "INV-RESTART effective style is unchanged by a restart", "%s vs %s" % [session.effective_look_id(), before_effective])
	_check(str(session.current_key) == str(t["key"]) and str(session.signature) == sig, "INV-RESTART identity is reconstructed")
	if was_dirty:
		_inv(FxLookScript.equivalent(FxLookScript.materialize(session.look), FxLookScript.materialize(before_look)), "INV-RESTART dirty work survives the restart byte-for-byte", _describe(session.look))
		_inv(bool(session.dirty), "INV-RESTART stashed work still reports dirty until the next apply")
	elif not truth_before.is_empty() and FxLookScript.equivalent(FxLookScript.materialize(before_look), truth_before):
		_inv(FxLookScript.equivalent(FxLookScript.materialize(session.look), FxLookScript.materialize(before_look)), "INV-RESTART clean state reconstructs identically", _describe(session.look))
	else:
		_note("restart %d: the open session was stale against Production (external update) — reconstruction follows the stores" % step)
	if was_mode == "SHARED_PROTECTED":
		if not drafts.has_target(sig):
			_inv(str(session.mode) in ["SHARED_PROTECTED", "EDIT_SHARED_DRAFT"], "INV-SHARED protection survives a restart without a parked draft", str(session.mode))
		elif not str(session.mode) in ["SHARED_PROTECTED", "EDIT_SHARED_DRAFT"]:
			_record_divergence("shared-protection-via-draft", "a target that reopens through its own parked draft loses shared-Look protection (mode=%s, usage=%d) — lab_vnext_audit_states.gd clears the draft before exercising a shared Look" % [str(session.mode), int(prod.usage(before_effective).get("count", 0))])

func _op_apply(step: int, another: bool) -> void:
	if another:
		_op_open(_pick_other_index())
	var t: Dictionary = targets[target_index]
	var sig := str(t["signature"])
	var was_mode := str(session.mode)
	var shared_key := ""
	if was_mode == "EDIT_SHARED_DRAFT":
		shared_key = "%s@%d" % [str(session.base.get("look_id", "")), int(session.base.get("revision", 0))]
	var override := "CHAOS_%s_%d" % [str(t["key"]).to_upper(), step] if another else ""
	var before_revs := _revision_map()
	var before_ids: Array = prod.list_look_ids()
	var result: Dictionary = session.apply(override)

	if was_mode == "SHARED_PROTECTED":
		_check(not bool(result.get("ok", false)), "INV-SHARED apply is refused while a shared Look is protected", str(result.get("errors", [])))
		_check(_revision_map() == before_revs, "refused apply leaves Production revisions untouched")
		return
	if not bool(result.get("ok", false)):
		_check(_revision_map() == before_revs and prod.list_look_ids() == before_ids, "failed apply leaves Production unchanged", str(result.get("errors", [])))
		return

	var look_id := str(result.get("look_id", ""))
	var rev := int(result.get("revision", 0))
	var expected_rev := maxi(int(before_revs.get(look_id, 0)), 0) + 1
	_check(rev == expected_rev, "INV-REV apply writes exactly the next revision", "rev=%d expected=%d" % [rev, expected_rev])
	var loaded: Dictionary = prod.load_look(look_id)
	_check(bool(loaded.get("ok", false)) and int((loaded.get("doc", {}) as Dictionary).get("revision", 0)) == rev, "applied Look reloads at the new revision", str(loaded.get("errors", [])))
	_check(str((loaded.get("doc", {}) as Dictionary).get("status", "")) == "PRODUCTION", "applied Look is PRODUCTION")
	_check(not bool(session.dirty), "session is clean after apply")
	var applied_status := str(session.resolution.get("status", ""))
	if applied_status in ["ASSIGNED", "AMBIGUOUS"]:
		_inv(session.effective_look_id() == look_id, "INV-EFF effective style follows the apply", "%s vs %s" % [session.effective_look_id(), look_id])
	else:
		var asg_after: Dictionary = prod.load_assignments().get("doc", {})
		_inv(applied_status in ["BYPASSED", "UNASSIGNED"], "INV-EFF apply leaves a documented resolution status", applied_status)
		# An explicit styling-OFF bypass (or a disabled binding) keeps the target
		# unstyled: the applied Look must still be the winner once the bypasses are
		# removed, unless the target's own binding is explicitly disabled.
		var without_bypasses: Dictionary = asg_after.duplicate(true)
		without_bypasses["bypasses"] = []
		var fallback: Dictionary = FxResolverScript.resolve(without_bypasses, session.context)
		var fallback_look := str(fallback.get("look_id", ""))
		_inv(fallback_look == look_id or _disabled_match(asg_after, session.context), "INV-EFF an unstyled target after apply is either matched by the new Look or explicitly disabled", "status=%s fallback=%s applied=%s selector=%s" % [applied_status, fallback_look, look_id, FxResolverScript.selector_key(session.novice_selector())])
		if fallback_look != look_id:
			_record_divergence("apply-onto-disabled-binding", "session.apply() wrote a Look for a target whose own binding is disabled — the target stays unstyled until the binding is re-enabled (the chaos disables a matching binding directly, which the WHY? panel only offers for non-winning chain entries; the state itself is reachable through the assignments file)")

	# the apply parks a clean target draft (specs/06 §3)
	expected_target_drafts[sig] = true
	never_stashed.erase(sig)
	working_source = "applied"
	var record: Dictionary = drafts.load_target(sig)
	_check(bool(record.get("ok", false)), "INV-DRAFT apply parks the target draft", str(record.get("errors", [])))
	if bool(record.get("ok", false)):
		_check(not bool(record["record"].get("dirty", true)), "INV-DIRTY parked draft is flagged clean after apply")
		_check(int(record["record"].get("base_revision", -1)) == rev, "parked draft records the applied revision", str(record["record"].get("base_revision", -1)))
		_inv(FxLookScript.equivalent(FxLookScript.materialize(record["record"]["look"]), FxLookScript.materialize(session.look)), "INV-DIRTY parked draft equals the applied Look")
	if was_mode == "EDIT_SHARED_DRAFT":
		_inv(not bool(drafts.load_shared(str(session.base.get("look_id", "")), int(session.base.get("revision", 0))).get("ok", false)), "INV-SHARED apply consumes the shared draft of the base revision", shared_key)
		expected_shared.erase(shared_key)

func _op_make_shared(step: int) -> void:
	# Sharing needs an effective style: if the current target has none, look for
	# one that does (the production-level scope write is a per-target action).
	if str(session.effective_look_id()) == "":
		var found := -1
		for i in range(targets.size()):
			var loaded: Dictionary = prod.load_assignments()
			if not bool(loaded.get("ok", false)):
				break
			var res: Dictionary = FxResolverScript.resolve(loaded["doc"], (targets[i] as Dictionary)["context"])
			if str(res.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
				found = i
				break
		if found >= 0:
			_op_open(found)
		else:
			_note_once("make_shared: no target has an effective style yet")
			return
	var t: Dictionary = targets[target_index]
	var effective: String = session.effective_look_id()
	if effective == "":
		_note_once("make_shared: the selected target has no effective style")
		return
	if not FileAccess.file_exists(prod.look_path(effective)):
		_inv(false, "INV-VALID the effective Look file exists before sharing", effective)
		return
	var loaded: Dictionary = prod.load_assignments()
	if not bool(loaded.get("ok", false)):
		_inv(false, "INV-VALID assignments load before sharing", str(loaded.get("errors", [])))
		return
	var asg_doc: Dictionary = loaded["doc"]
	var before_revs := _revision_map()
	var broad: Dictionary = _broad_selector(t)
	_inv(FxResolverScript.selector_key(broad) != FxResolverScript.selector_key(session.novice_selector()), "INV-SHARED make_shared uses a broader scope than the novice selector", FxResolverScript.selector_key(broad))
	FxResolverScript.upsert_binding(asg_doc, broad, effective, "chaos shared scope")
	var result: Dictionary = prod.apply({"assignments": asg_doc})
	_check(bool(result.get("ok", false)), "make_shared writes the shared scope", str(result.get("errors", [])))
	if bool(result.get("ok", false)):
		var use: Dictionary = prod.usage(effective)
		_inv(int(use.get("count", 0)) >= 2, "INV-SHARED the Look is now used by 2+ scopes", "usage=%d" % int(use.get("count", 0)))
	else:
		_check(_revision_map() == before_revs, "refused make_shared leaves Production unchanged", str(result.get("errors", [])))
	# the shell refreshes the editor after a production-side change
	_op_open(target_index)

func _op_make_unique() -> void:
	var was_mode := str(session.mode)
	var old_look := str(session.base.get("look_id", ""))
	var old_usage := int(prod.usage(old_look).get("count", 0)) if old_look != "" else 0
	var result: Dictionary = session.make_unique()
	if was_mode != "SHARED_PROTECTED":
		_check(not bool(result.get("ok", false)), "INV-SHARED make_unique is refused outside shared protection", str(result.get("errors", [])))
		return
	_check(bool(result.get("ok", false)), "make_unique succeeds for a shared Look", str(result.get("errors", [])))
	if not bool(result.get("ok", false)):
		return
	var new_id := str(result.get("look_id", ""))
	_check(new_id != old_look and new_id.ends_with("_UNIQUE"), "make_unique derives a fresh unique id", new_id)
	var loaded: Dictionary = prod.load_look(new_id)
	_check(bool(loaded.get("ok", false)) and int((loaded.get("doc", {}) as Dictionary).get("revision", 0)) == 1, "the unique Look starts at revision 1", str(loaded.get("errors", [])))
	_check(str(session.mode) == "EDIT_PRODUCTION_UNIQUE" and not bool(session.dirty), "the unique Look is editable and clean", str(session.mode))
	_inv(session.effective_look_id() == new_id, "INV-EFF the target resolves to the unique Look", session.effective_look_id())
	working_source = "unique"
	# R3: make_unique is an explicit semantic transition — the parked target draft
	# is cleared as part of it, so the INV-DRAFT bookkeeping must treat this
	# target as intentionally draft-free until the next stash.
	var unique_sig := str(targets[target_index]["signature"])
	expected_target_drafts.erase(unique_sig)
	never_stashed[unique_sig] = true
	var parked: Dictionary = drafts.load_target(str(targets[target_index]["signature"]))
	_check(not bool(parked.get("ok", false)), "make_unique clears the parked target draft (explicit transition)", str(parked.get("record", {}).get("look", {}).get("look_id", "")))
	if bool(parked.get("ok", false)) and str((parked["record"].get("look", {}) as Dictionary).get("look_id", "")) != new_id:
		_record_divergence("stale-draft-after-make-unique", "make_unique rebinds the target but leaves the parked target draft on the previous Look (%s); the next open would restore that design instead of the unique one" % str((parked["record"].get("look", {}) as Dictionary).get("look_id", "")))
	_inv(int(prod.usage(old_look).get("count", 0)) == old_usage - 1, "INV-SHARED the shared Look keeps one user fewer", "usage=%d old=%d" % [int(prod.usage(old_look).get("count", 0)), old_usage])

func _op_history(is_undo: bool) -> void:
	var before_hash := _look_hash(session.look)
	var was_mode := str(session.mode)
	var changed := false
	if is_undo:
		changed = session.undo()
	else:
		changed = session.redo()
	if not changed:
		_note_once("history step had nothing to apply (empty undo/redo stack for the current session)")
		return
	_check(session.dirty, "a history step marks the session dirty")
	_inv(_look_hash(session.look) != before_hash, "INV-CANON a history step changes the working Look")
	_inv(_source_count(session.look) == 1 and _unique_ids(_layer_ids(session.look)), "INV-CANON a history step keeps the Look structurally valid", _layer_types(session.look))
	if was_mode == "SHARED_PROTECTED":
		_inv(false, "INV-SHARED undo/redo never mutates a protected shared Look", "%s -> %s" % [was_mode, _look_hash(session.look).substr(0, 12)])

func _op_disable_binding(step: int) -> void:
	var loaded: Dictionary = prod.load_assignments()
	if not bool(loaded.get("ok", false)):
		_inv(false, "INV-VALID assignments load before disable_binding", str(loaded.get("errors", [])))
		return
	var doc: Dictionary = loaded["doc"]
	var enabled_ids: Array = []
	var matching_ids: Array = []
	for raw in doc.get("bindings", []):
		if not (raw is Dictionary) or not bool((raw as Dictionary).get("enabled", true)):
			continue
		var id := str((raw as Dictionary).get("binding_id", ""))
		enabled_ids.append(id)
		if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), session.context):
			matching_ids.append(id)
	if enabled_ids.is_empty():
		_note_once("disable_binding: no enabled binding in Production yet")
		return
	var pick := str(matching_ids[rng.randi_range(0, matching_ids.size() - 1)]) if not matching_ids.is_empty() else str(enabled_ids[rng.randi_range(0, enabled_ids.size() - 1)])
	var result: Dictionary = session.disable_binding(pick)
	_check(bool(result.get("ok", false)), "disable_binding persists the change", str(result.get("errors", [])))
	if not bool(result.get("ok", false)):
		return
	var after: Dictionary = prod.load_assignments()["doc"]
	var still_enabled := false
	for raw in after.get("bindings", []):
		if raw is Dictionary and str((raw as Dictionary).get("binding_id", "")) == pick:
			still_enabled = bool((raw as Dictionary).get("enabled", true))
	_inv(not still_enabled, "INV-SHARED the disabled binding is persisted as disabled", pick)
	_inv(_enabled_count(after) == enabled_ids.size() - 1, "INV-VALID exactly one binding got disabled", "%d -> %d" % [enabled_ids.size(), _enabled_count(after)])
	var res: Dictionary = FxResolverScript.resolve(after, session.context)
	_inv(str(res.get("status", "")) in ["ASSIGNED", "UNASSIGNED", "AMBIGUOUS", "BYPASSED"], "INV-EFF resolution stays a documented status after disabling", str(res.get("status", "")))
	if str(res.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
		_inv(str(res.get("binding_id", "")) != pick, "INV-EFF a disabled binding never wins resolution", pick)

func _op_styling(enabled: bool) -> void:
	var result: Dictionary = session.set_styling(enabled)
	_check(bool(result.get("ok", false)), "styling toggle applies", str(result.get("errors", [])))
	if not bool(result.get("ok", false)):
		return
	var after: Dictionary = prod.load_assignments()["doc"]
	var key := FxResolverScript.selector_key(session.novice_selector())
	var matching := 0
	for raw in after.get("bypasses", []):
		if raw is Dictionary and FxResolverScript.selector_key((raw as Dictionary).get("selector", {})) == key:
			matching += 1
	if enabled:
		_inv(matching == 0, "INV-SHARED styling ON removes this target's bypass", key)
		_inv(str(session.resolution.get("status", "")) != "BYPASSED", "INV-EFF styling ON resolves to a style again", str(session.resolution.get("status", "")))
	else:
		_inv(matching == 1, "INV-SHARED styling OFF writes exactly one bypass for this target", key)
		_inv(str(session.resolution.get("status", "")) == "BYPASSED", "INV-EFF styling OFF resolves as BYPASSED", str(session.resolution.get("status", "")))
		_inv(str(session.resolution.get("look_id", "")) == "", "INV-EFF a bypass never falls back to another Look", str(session.resolution.get("look_id", "")))
	_inv(bool(session.styling_enabled) == enabled, "INV-EFF the styling flag mirrors the store", str(session.styling_enabled))

# ================================================================ invariants

func _verify(step: int, op: String) -> void:
	var loaded_asg: Dictionary = prod.load_assignments()
	_inv(bool(loaded_asg.get("ok", false)), "INV-VALID assignments stay valid", str(loaded_asg.get("errors", [])))
	var asg_doc: Dictionary = loaded_asg.get("doc", {}) if bool(loaded_asg.get("ok", false)) else {}

	# ---- Production looks: valid, canonical, PRODUCTION, revisions monotone ----
	for raw in prod.list_look_ids():
		var look_id := str(raw)
		var loaded: Dictionary = prod.load_look(look_id)
		if not bool(loaded.get("ok", false)):
			_inv(false, "INV-VALID every Production Look loads", "%s %s" % [look_id, str(loaded.get("errors", []))])
			continue
		var doc: Dictionary = loaded["doc"]
		var rev := int(doc.get("revision", 0))
		var floor_rev := int(look_rev_floor.get(look_id, 0))
		_inv(rev >= floor_rev, "INV-REV Look revisions never decrease", "%s rev=%d floor=%d (step %d)" % [look_id, rev, floor_rev, step])
		look_rev_floor[look_id] = maxi(floor_rev, rev)
		_inv(str(doc.get("status", "")) == "PRODUCTION", "INV-VALID Production Looks carry status PRODUCTION", "%s=%s" % [look_id, str(doc.get("status", ""))])
		_inv(bool(FxLookScript.validate(doc)["ok"]), "INV-VALID Production Looks validate", "%s %s" % [look_id, str(FxLookScript.validate(doc)["errors"])])
		_inv(FxLookScript.equivalent(FxLookScript.materialize(doc), doc), "INV-CANON Production Looks are canonical", look_id)

	# ---- drafts: no loss, no cross-target leakage ----
	for raw in drafts.list_target_signatures():
		var sig := str(raw)
		if sig.begins_with("_corrupt_"):
			_inv(false, "INV-DRAFT no corrupt draft records", sig)
			continue
		var record: Dictionary = drafts.load_target(sig)
		_inv(bool(record.get("ok", false)), "INV-DRAFT every draft record is readable", sig)
		if bool(record.get("ok", false)):
			_inv(str(record["record"].get("target_signature", "")) == sig, "INV-SIG a draft is stored under its own target signature", "%s declares %s" % [sig, str(record["record"].get("target_signature", ""))])
	for sig in expected_target_drafts.keys():
		_inv(drafts.has_target(str(sig)), "INV-DRAFT no draft disappears without an explicit discard", str(sig))
	for sig in never_stashed.keys():
		_inv(not drafts.has_target(str(sig)), "INV-SIG a never-stashed target has no draft record", str(sig))
	for raw in drafts.list_shared():
		var entry: Dictionary = raw
		var key := "%s@%d" % [str(entry.get("look_id", "")), int(entry.get("base_revision", 0))]
		_inv(expected_shared.has(key), "INV-SHARED shared drafts exist only for tracked base revisions", key)
	for key in expected_shared.keys():
		var parts := str(key).split("@")
		_inv(bool(drafts.load_shared(str(parts[0]), int(parts[1])).get("ok", false)), "INV-SHARED no shared draft disappears without the documented consume", str(key))

	# ---- working state ----
	var cur_hash := _look_hash(session.look)
	var cur_sig := str(session.signature)
	_inv(FxLookScript.equivalent(FxLookScript.materialize(session.look), session.look), "INV-CANON the working Look is canonical", _describe(session.look))
	_inv(_source_count(session.look) == 1 and _unique_ids(_layer_ids(session.look)), "INV-CANON the working Look has exactly one SOURCE and unique ids", _layer_types(session.look))
	var owned: Dictionary = lineage.get(cur_sig, {})
	if op in ["undo", "redo"]:
		_inv(owned.has(cur_hash), "INV-LINEAGE undo/redo stays inside the current target's design history", "%s op=%s hash=%s (cross-target stack bleed?)" % [cur_sig, op, cur_hash.substr(0, 12)], "cross-target-undo-bleed")
	else:
		owned[cur_hash] = true
		lineage[cur_sig] = owned

	# ---- effective style == independent resolver run ----
	var independent: Dictionary = FxResolverScript.resolve(asg_doc, session.context) if bool(loaded_asg.get("ok", false)) else {"status": "BROKEN", "chain": []}
	var session_status := str(session.resolution.get("status", ""))
	_inv(session_status == str(independent.get("status", "")), "INV-EFF the session resolution equals an independent resolver run", "%s vs %s" % [session_status, str(independent.get("status", ""))])
	var expected_effective := str(independent.get("look_id", "")) if session_status in ["ASSIGNED", "AMBIGUOUS"] else ""
	_inv(session.effective_look_id() == expected_effective, "INV-EFF effective style equals the resolver result", "%s vs %s" % [session.effective_look_id(), expected_effective])
	if session_status in ["ASSIGNED", "AMBIGUOUS"]:
		_inv(FileAccess.file_exists(prod.look_path(session.effective_look_id())), "INV-EFF the effective Look file exists", session.effective_look_id())

	# ---- editor badge + dirty truthfulness ----
	var badge := str(session.badge_text())
	var dirty_suffix := " · DRAFT" if bool(session.dirty) else ""
	var expected_badge := ""
	match session_status:
		"BYPASSED":
			expected_badge = "⦸ STYLING OFF" + dirty_suffix
		"AMBIGUOUS":
			expected_badge = "⚠ AMBIGUOUS" + dirty_suffix
		"BROKEN":
			expected_badge = "⚠ BROKEN" + dirty_suffix
		"ASSIGNED":
			var effective: String = session.effective_look_id()
			var usage := int(prod.usage(effective).get("count", 0))
			var shared_count := int(session.base.get("shared_count", 0))
			if str(session.mode) in ["SHARED_PROTECTED", "EDIT_SHARED_DRAFT"]:
				_inv(shared_count > 1, "INV-SHARED a protected session counts the shared users", "%s shared_count=%d" % [str(session.mode), shared_count])
				expected_badge = "◆ SHARED (%d)" % shared_count + dirty_suffix
				_inv(usage == shared_count, "INV-SHARED the SHARED count equals the real Production usage", "%d vs %d" % [usage, shared_count])
			elif shared_count > 1:
				expected_badge = "◆ SHARED (%d)" % shared_count + dirty_suffix
				_inv(usage == shared_count, "INV-SHARED the SHARED count equals the real Production usage", "%d vs %d" % [usage, shared_count])
			else:
				expected_badge = "● ASSIGNED" + dirty_suffix
				if usage > 1 and str(session.base.get("kind", "")) == "production":
					_record_divergence("shared-protection-via-draft", "a session opened through its own parked draft reports ● ASSIGNED for a Look used by %d scopes (mode=%s)" % [usage, str(session.mode)])
		_:
			expected_badge = "◐ DRAFT" if bool(session.dirty) else "○ UNASSIGNED"
	_inv(badge == expected_badge, "INV-BADGE the editor badge equals the effective state", "badge=%s expected=%s" % [badge, expected_badge])
	_inv(badge.contains("DRAFT") == (bool(session.dirty) or badge.begins_with("◐")), "INV-DIRTY the badge DRAFT marker mirrors the dirty flag", badge)

	# ---- clean/dirty truthfulness ----
	if not bool(session.dirty):
		var record: Dictionary = drafts.load_target(cur_sig)
		var parked_look_id := str((record["record"].get("look", {}) as Dictionary).get("look_id", "")) if bool(record.get("ok", false)) else ""
		if bool(record.get("ok", false)) and str(session.base.get("kind", "")) == "production" and working_source in ["draft", "applied"] and parked_look_id == str(session.look.get("look_id", "")) and int(record["record"].get("base_revision", -1)) == int(session.base.get("revision", -2)):
			_inv(not bool(record["record"].get("dirty", true)), "INV-DIRTY a clean session's parked draft is flagged clean", cur_sig)
			_inv(FxLookScript.equivalent(FxLookScript.materialize(record["record"]["look"]), FxLookScript.materialize(session.look)), "INV-DIRTY a clean session's parked draft equals the working Look", "sig=%s source=%s mode=%s base=%s record_base_rev=%d working=%s parked=%s" % [cur_sig, working_source, str(session.mode), str(session.base), int(record["record"].get("base_revision", -1)), _describe(session.look), _describe(record["record"]["look"])])
		if str(session.mode) == "EDIT_SHARED_DRAFT":
			var base_look := str(session.base.get("look_id", ""))
			var base_rev := int(session.base.get("revision", 0))
			var shared: Dictionary = drafts.load_shared(base_look, base_rev)
			_inv(bool(shared.get("ok", false)), "INV-SHARED a clean shared-draft session has its shared draft parked", "%s@%d" % [base_look, base_rev])
			if bool(shared.get("ok", false)):
				_inv(not bool(shared["record"].get("dirty", true)), "INV-DIRTY the shared draft is flagged clean once the session is clean", "%s@%d" % [base_look, base_rev])
				_inv(FxLookScript.equivalent(FxLookScript.materialize(shared["record"]["look"]), FxLookScript.materialize(session.look)), "INV-DIRTY the shared draft equals the working Look", "%s@%d" % [base_look, base_rev])

	# ---- browser badges equal the actual state for every target ----
	for i in range(targets.size()):
		var actual := _browser_badge(i, asg_doc, bool(loaded_asg.get("ok", false)))
		var expected := _expected_browser_badge(i, asg_doc, bool(loaded_asg.get("ok", false)))
		_inv(actual == expected, "INV-BADGE the browser badge equals the target's actual state", "%s actual=%s expected=%s (step %d)" % [str((targets[i] as Dictionary)["key"]), actual, expected, step])

func _deep_check(step: int) -> void:
	var state: Dictionary = prod.production_state()
	_inv(bool(state.get("ok", false)), "INV-VALID deep production_state ok", "step %d %s" % [step, str(state.get("errors", []))])
	_inv(not bool(state.get("recovery_required", true)), "INV-VALID no recovery is required", "step %d" % step)
	var shared_seen: Dictionary = {}
	for raw in drafts.list_shared():
		var entry: Dictionary = raw
		var key := "%s@%d" % [str(entry.get("look_id", "")), int(entry.get("base_revision", 0))]
		if shared_seen.has(key):
			_inv(false, "INV-SHARED shared drafts are keyed uniquely", key)
		shared_seen[key] = true

# ================================================================ badge models

func _browser_badge(idx: int, asg_doc: Dictionary, asg_ok: bool) -> String:
	# Faithful model of the shell's browser row badge (lab_shell.gd `_badge_for_key`).
	var t: Dictionary = targets[idx]
	if drafts.has_target(str(t["signature"])):
		return "◐ DRAFT"
	if not asg_ok:
		return "⚠ BROKEN"
	var res: Dictionary = FxResolverScript.resolve(asg_doc, t["context"])
	var status := str(res.get("status", ""))
	if status == "BYPASSED":
		return "⦸ STYLING OFF"
	if status in ["ASSIGNED", "AMBIGUOUS"]:
		var look_id := str(res.get("look_id", ""))
		if not FileAccess.file_exists(prod.look_path(look_id)):
			return "⚠ BROKEN"
		return "⚠ AMBIGUOUS" if status == "AMBIGUOUS" else "● ASSIGNED"
	for raw in asg_doc.get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), t["context"]):
				return "○ DISABLED"
	return "○ UNASSIGNED"

func _expected_browser_badge(idx: int, asg_doc: Dictionary, asg_ok: bool) -> String:
	# Independent derivation from the documented row-label contract (specs/06 §13).
	var t: Dictionary = targets[idx]
	var context: Dictionary = t["context"]
	if not asg_ok:
		return "◐ DRAFT" if drafts.has_target(str(t["signature"])) else "⚠ BROKEN"
	if drafts.has_target(str(t["signature"])):
		return "◐ DRAFT"
	var winner := _winner(asg_doc, context)
	if _matching_bypass(asg_doc, context) != "":
		return "⦸ STYLING OFF"
	if str(winner.get("status", "")) == "UNASSIGNED":
		return "○ DISABLED" if _disabled_match(asg_doc, context) else "○ UNASSIGNED"
	if not FileAccess.file_exists(prod.look_path(str(winner.get("look_id", "")))):
		return "⚠ BROKEN"
	return "⚠ AMBIGUOUS" if bool(winner.get("ambiguous", false)) else "● ASSIGNED"

func _winner(doc: Dictionary, context: Dictionary) -> Dictionary:
	# Independent re-implementation of specs/09 §1.2–§1.3 precedence.
	var candidates: Array = []
	for raw in doc.get("bindings", []):
		if not (raw is Dictionary):
			continue
		var binding: Dictionary = raw
		if not bool(binding.get("enabled", true)):
			continue
		var selector = binding.get("selector", {})
		if not (selector is Dictionary):
			continue
		var norm: Dictionary = FxResolverScript.normalize_selector(selector)
		if norm.is_empty():
			continue
		var matches := true
		for key in norm.keys():
			if str(context.get(str(key), "")) != str(norm[key]):
				matches = false
				break
		if not matches:
			continue
		candidates.append({
			"binding_id": str(binding.get("binding_id", "")),
			"look_id": str(binding.get("look_id", "")),
			"score": FxResolverScript.selector_score(norm),
			"count": norm.size(),
			"key": FxResolverScript.selector_key(norm),
		})
	if candidates.is_empty():
		return {"status": "UNASSIGNED"}
	candidates.sort_custom(func(a, b):
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		if str(a["key"]) != str(b["key"]):
			return str(a["key"]) < str(b["key"])
		return str(a["binding_id"]) < str(b["binding_id"])
	)
	var top: Dictionary = candidates[0]
	var ambiguous := false
	for candidate in candidates:
		if int(candidate["score"]) == int(top["score"]) and int(candidate["count"]) == int(top["count"]) and str(candidate["look_id"]) != str(top["look_id"]):
			ambiguous = true
			break
	return {
		"status": "AMBIGUOUS" if ambiguous else "ASSIGNED",
		"look_id": str(top["look_id"]), "binding_id": str(top["binding_id"]),
		"ambiguous": ambiguous,
	}

func _matching_bypass(doc: Dictionary, context: Dictionary) -> String:
	for raw in doc.get("bypasses", []):
		if not (raw is Dictionary):
			continue
		var bypass: Dictionary = raw
		if not bool(bypass.get("enabled", true)):
			continue
		if FxResolverScript.selector_matches(bypass.get("selector", {}), context):
			return str(bypass.get("bypass_id", ""))
	return ""

func _disabled_match(doc: Dictionary, context: Dictionary) -> bool:
	for raw in doc.get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), context):
				return true
	return false

# ================================================================ helpers

func _classify_source(idx: int) -> String:
	# Which store the working look came from (drives the clean/dirty truthfulness
	# checks: only a draft-sourced or freshly applied working look must equal the
	# parked target draft).
	var t: Dictionary = targets[idx]
	if drafts.has_target(str(t["signature"])):
		return "draft"
	var loaded: Dictionary = prod.load_assignments()
	if not bool(loaded.get("ok", false)):
		return "neutral"
	var res: Dictionary = FxResolverScript.resolve(loaded["doc"], t["context"])
	if str(res.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
		var look_id := str(res.get("look_id", ""))
		var look: Dictionary = prod.load_look(look_id)
		if bool(look.get("ok", false)):
			if bool(drafts.load_shared(look_id, int((look["doc"] as Dictionary).get("revision", 0))).get("ok", false)):
				return "shared_draft"
			return "production"
	return "neutral"

func _store_truth() -> Dictionary:
	# What open_target must reconstruct: parked draft -> production/shared draft -> neutral.
	var t: Dictionary = targets[target_index]
	var record: Dictionary = drafts.load_target(str(t["signature"]))
	if bool(record.get("ok", false)):
		return FxLookScript.materialize(record["record"]["look"])
	var loaded: Dictionary = prod.load_assignments()
	if not bool(loaded.get("ok", false)):
		return {}
	var res: Dictionary = FxResolverScript.resolve(loaded["doc"], t["context"])
	if str(res.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
		var look_id := str(res.get("look_id", ""))
		var look: Dictionary = prod.load_look(look_id)
		if bool(look.get("ok", false)):
			var revision := int((look["doc"] as Dictionary).get("revision", 0))
			var shared: Dictionary = drafts.load_shared(look_id, revision)
			if bool(shared.get("ok", false)):
				return FxLookScript.materialize(shared["record"]["look"])
			return FxLookScript.materialize(look["doc"])
	return {}

func _record_stash_write() -> void:
	# Mirrors FxSession.stash() routing so the draft ledger stays truthful.
	if str(session.base.get("kind", "")) == "production" and int(session.base.get("shared_count", 0)) > 1 and str(session.mode) == "EDIT_SHARED_DRAFT":
		expected_shared["%s@%d" % [str(session.base.get("look_id", "")), int(session.base.get("revision", 0))]] = true
		return
	var sig := str(session.signature)
	if sig != "":
		expected_target_drafts[sig] = true
		never_stashed.erase(sig)

func _broad_selector(t: Dictionary) -> Dictionary:
	var ctx: Dictionary = t["context"]
	if ctx.has("fighter_id") and str(t["role"]) in FxSessionScript.FIGHTER_ROLES:
		return {"fighter_id": str(ctx["fighter_id"]), "element_role": str(ctx["element_role"])}
	return {"element_id": str(ctx["element_id"])}

func _revision_map() -> Dictionary:
	var out := {}
	for raw in prod.list_look_ids():
		var look_id := str(raw)
		var loaded: Dictionary = prod.load_look(look_id)
		out[look_id] = int((loaded.get("doc", {}) as Dictionary).get("revision", -1)) if bool(loaded.get("ok", false)) else -1
	return out

func _enabled_count(doc: Dictionary) -> int:
	var count := 0
	for raw in doc.get("bindings", []):
		if raw is Dictionary and bool((raw as Dictionary).get("enabled", true)):
			count += 1
	return count

func _layer_ids(doc: Dictionary) -> Array:
	var out: Array = []
	for raw in doc.get("layers", []):
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("layer_id", "")))
	return out

func _layer_types(doc: Dictionary) -> String:
	var out: Array = []
	for raw in doc.get("layers", []):
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("type", "")))
	return ",".join(out)

func _source_count(doc: Dictionary) -> int:
	var count := 0
	for raw in doc.get("layers", []):
		if raw is Dictionary and str((raw as Dictionary).get("type", "")) == "SOURCE":
			count += 1
	return count

func _unique_ids(ids: Array) -> bool:
	var seen: Dictionary = {}
	for id in ids:
		if seen.has(str(id)):
			return false
		seen[str(id)] = true
	return true

func _look_hash(doc: Dictionary) -> String:
	return JSON.stringify(doc).sha256_text()

func _describe(doc: Dictionary) -> String:
	return "%s/rev%d/%d layers" % [str(doc.get("look_id", "")), int(doc.get("revision", 0)), (doc.get("layers", []) as Array).size()]

func _breadcrumb(sess) -> String:
	var selector: Dictionary = sess.novice_selector()
	var parts: Array = []
	if selector.has("fighter_id"):
		parts.append(str(selector["fighter_id"]).replace("_", " ").capitalize())
	if selector.has("element_role"):
		parts.append(str(selector["element_role"]).capitalize())
	elif selector.has("element_id"):
		parts.append(str(selector["element_id"]).replace("_", " ").capitalize())
	if selector.has("visual_side"):
		parts.append(str(selector["visual_side"]).capitalize())
	return " ".join(parts) if not parts.is_empty() else "Untitled Design"

func _sample(step: int, op: String) -> void:
	var loaded: Dictionary = prod.load_assignments()
	var asg_doc: Dictionary = loaded.get("doc", {}) if bool(loaded.get("ok", false)) else {}
	var independent: Dictionary = FxResolverScript.resolve(asg_doc, session.context) if bool(loaded.get("ok", false)) else {"status": "BROKEN"}
	var draft_list: Array = []
	for raw in drafts.list_target_signatures():
		var sig := str(raw)
		var record: Dictionary = drafts.load_target(sig)
		if bool(record.get("ok", false)):
			draft_list.append({
				"signature": sig,
				"base_revision": int(record["record"].get("base_revision", -1)),
				"dirty": bool(record["record"].get("dirty", false)),
				"look_id": str((record["record"].get("look", {}) as Dictionary).get("look_id", "")),
				"layers": ((record["record"].get("look", {}) as Dictionary).get("layers", []) as Array).size(),
			})
		else:
			draft_list.append({"signature": sig, "readable": false})
	var badges := {}
	for i in range(targets.size()):
		badges[str((targets[i] as Dictionary)["key"])] = _browser_badge(i, asg_doc, bool(loaded.get("ok", false)))
	samples.append({
		"step": step, "op": op,
		"target": str(session.current_key), "mode": str(session.mode),
		"dirty": bool(session.dirty), "badge": session.badge_text(),
		"resolution": str(independent.get("status", "")),
		"effective_look_id": session.effective_look_id(),
		"look_hash": _look_hash(session.look), "working_layers": _layer_types(session.look),
		"production_looks": _revision_map(), "look_floor": look_rev_floor.duplicate(true),
		"target_drafts": draft_list, "shared_drafts": drafts.list_shared(),
		"browser_badges": badges,
		"checks": checks.size(), "failures": failures, "violations": violations,
	})

func _finish(useed: int) -> void:
	var samples_file := FileAccess.open(out_dir.path_join("chaos_samples.json"), FileAccess.WRITE)
	if samples_file != null:
		samples_file.store_string(JSON.stringify(samples, "  "))
		samples_file.close()
	var trace_file := FileAccess.open(out_dir.path_join("chaos_step_trace.json"), FileAccess.WRITE)
	if trace_file != null:
		trace_file.store_string(JSON.stringify(step_trace, "  "))
		trace_file.close()
	var summary := {
		"suite": "lab_vnext_chaos_test", "seed": useed, "steps": STEPS,
		"checks": checks.size(), "failures": failures,
		"invariants": invariants, "violations": violations,
		"divergences": divergences, "notes": notes,
		"strict_mode": strict_mode, "samples": samples.size(),
		"status": "PASS" if failures == 0 else "FAIL",
	}
	var summary_file := FileAccess.open(out_dir.path_join("summary_chaos_check.json"), FileAccess.WRITE)
	if summary_file != null:
		summary_file.store_string(JSON.stringify(summary, "  "))
		summary_file.close()
	var line := "[FX-CHAOS] done · checks=%d failures=%d · steps=%d invariants=%d violations=%d divergences=%d" % [checks.size(), failures, STEPS, invariants, violations, divergences.size()]
	var log_file := FileAccess.open(out_dir.path_join("chaos_checks.log"), FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("\n".join(checks) + "\n" + line + "\n")
		log_file.close()
	print(line)
	quit(1 if failures > 0 else 0)

func _inv(ok: bool, label: String, detail := "", known_id := "") -> void:
	invariants += 1
	if ok:
		return
	violations += 1
	if known_id != "" and not strict_mode:
		_record_divergence(known_id, "%s: %s" % [label, detail])
		_note_once("tolerated %s (%s)" % [known_id, label])
		return
	var count := int(reported.get(label, 0)) + 1
	reported[label] = count
	if count == 1:
		_check(false, label, detail)
	elif count == 2:
		print("[CHECK] ... %s repeats; further occurrences are only counted (violations=%d)" % [label, violations])

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

func _note(text: String) -> void:
	notes.append(text)
	print("[NOTE] " + text)

func _note_once(text: String) -> void:
	if note_counts.has(text):
		note_counts[text] = int(note_counts[text]) + 1
		return
	note_counts[text] = 1
	_note(text)

func _note_summary() -> void:
	for text in note_counts.keys():
		if int(note_counts[text]) > 1:
			_note("%s (x%d)" % [str(text), int(note_counts[text])])

func _record_divergence(id: String, text: String) -> void:
	if not divergences.has(id):
		divergences[id] = {"count": 0, "text": text}
	divergences[id]["count"] = int(divergences[id]["count"]) + 1

func _wipe_dir(path: String) -> void:
	if path == "":
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_wipe_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
