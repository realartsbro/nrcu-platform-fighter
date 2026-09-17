extends SceneTree
# NRCU FX Lab vNEXT — §10 resolver property/fuzz (headless, seeded).
#
# A seeded generator builds many random VALID assignment sets (bindings with
# selectors of varying specificity, enabled/disabled flags, bypass entries) and
# re-verifies the documented resolution properties for every generated context.
# The expected winner is re-implemented independently (specs/09 §1.2–§1.3) and
# compared against the real FxResolver; nothing here calls the resolver to
# compute the expectation.
#
# Properties:
#   P1  most specific enabled selector wins, deterministically
#   P2  resolve() is deterministic across repeat runs (status, look, binding, chain)
#   P3  binding insertion order is irrelevant (bindings + bypasses permuted)
#   P4  JSON field order and serialize->reload are irrelevant
#   P5  equal ambiguous winners are rejected (duplicate selector and
#       distinct-but-equal-specificity selectors)
#   P6  duplicate normalized selectors are rejected by the validator
#   P7  a disabled binding opens the fallback (and a disabled binding never wins)
#   P8  a matching bypass blocks ALL styling (no fallback), never leaks
#   P9  deleting unrelated bindings never changes the winner
#   P10 validator and resolver agree about ambiguity
#   P11 specificity is monotone: a superset selector outranks its subset
#   P12 malformed Production input (missing Look, invalid IDs, duplicate IDs,
#       corrupt JSON, unsupported schema version, broken custom asset) fails
#       safely and produces a truthful BROKEN state through the production
#       layer (load_look / production_state / recovery_required) — the resolver
#       itself stays a pure data function
#   P13 hostile-but-typed inputs never crash and stay inside the documented enum
#
# Determinism: FXLAB_FUZZ_SEED (default 20260915) seeds the generator RNG and the
# global RNG. Evidence: FXLAB_EVIDENCE_DIR (default res://evidence/vnext_build)
# -> resolver_fuzz_samples.json, resolver_fuzz_checks.log,
# summary_resolver_fuzz_check.json.
# Scale: FXLAB_FUZZ_SETS (default 120), FXLAB_FUZZ_CONTEXTS (default 12).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")

const SEED_DEFAULT := 20260915
const SETS_DEFAULT := 120
const CONTEXTS_DEFAULT := 12
const STATUSES := ["UNASSIGNED", "ASSIGNED", "BYPASSED", "AMBIGUOUS"]
const FIELDS := ["element_id", "fighter_id", "element_role", "visual_side", "presentation_slot", "team_side", "mode_family", "stage_id"]
const VALUES := {
	"element_id": ["vs_mark", "stage_banner"],
	"fighter_id": ["ice_mage", "doge_man", "dragon"],
	"element_role": ["echo", "primary", "name"],
	"visual_side": ["left", "right"],
	"presentation_slot": ["a_back", "b_front"],
	"team_side": ["left", "right"],
	"mode_family": ["1v1", "team"],
	"stage_id": ["dojo", "ice_arena"],
}

var checks: Array = []
var failures: int = 0
var families: Dictionary = {}
var samples: Array = []
var notes: Array = []
var divergences: Dictionary = {}
var out_dir: String
var rng := RandomNumberGenerator.new()
var generated_sets: int = 0
var dropped_candidates: int = 0
var resolutions: int = 0
var sets_target: int = SETS_DEFAULT
var contexts_target: int = CONTEXTS_DEFAULT

var prod
var drafts

func _init() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://evidence/vnext_build")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seed_text := OS.get_environment("FXLAB_FUZZ_SEED")
	var useed := SEED_DEFAULT if seed_text == "" else int(seed_text)
	var sets_text := OS.get_environment("FXLAB_FUZZ_SETS")
	sets_target = sets_target if sets_text == "" else maxi(int(sets_text), 1)
	var ctx_text := OS.get_environment("FXLAB_FUZZ_CONTEXTS")
	contexts_target = contexts_target if ctx_text == "" else maxi(int(ctx_text), 1)
	rng.seed = useed
	seed(useed)

	print("[FX-RESOLVER-FUZZ] seed=%d sets=%d contexts=%d" % [useed, sets_target, contexts_target])

	for s in range(sets_target):
		_fuzz_set(s)
	_malformed_section()
	_hostile_section()
	_evidence(useed)

# ================================================================ generator

func _fuzz_set(index: int) -> void:
	var doc: Dictionary = FxResolverScript.new_assignments()
	var wanted := rng.randi_range(2, 7)
	for i in range(wanted):
		var selector := _gen_selector()
		var accepted := false
		for attempt in range(4):
			var candidate := {
				"binding_id": "binding-fuzz-%04d-%04d" % [index, i * 10 + attempt],
				"selector": selector,
				"look_id": "FUZZ_LOOK_%d" % rng.randi_range(0, 3),
				"enabled": rng.randf() < 0.75,
			}
			(doc["bindings"] as Array).append(candidate)
			if bool(FxResolverScript.validate_assignments(doc)["ok"]):
				accepted = true
				break
			(doc["bindings"] as Array).pop_back()
		if not accepted:
			dropped_candidates += 1
	# a derived superset binding so specificity has something to prefer (P11)
	var bindings_now: Array = doc["bindings"]
	if not bindings_now.is_empty() and rng.randf() < 0.6:
		var base_raw: Dictionary = bindings_now[rng.randi_range(0, bindings_now.size() - 1)]
		var superset: Dictionary = FxResolverScript.normalize_selector(base_raw.get("selector", {}))
		var spare: Array = []
		for field in FIELDS:
			if not superset.has(field):
				spare.append(field)
		var extra_count := mini(rng.randi_range(1, 2), spare.size())
		for i in range(extra_count):
			var field := str(spare[rng.randi_range(0, spare.size() - 1)])
			spare.erase(field)
			var values: Array = VALUES[field]
			superset[field] = str(values[rng.randi_range(0, values.size() - 1)])
		if extra_count > 0:
			var derived := {
				"binding_id": "binding-fuzz-%04d-9000" % index,
				"selector": superset,
				"look_id": "FUZZ_LOOK_%d" % rng.randi_range(0, 3),
				"enabled": true,
			}
			bindings_now.append(derived)
			if not bool(FxResolverScript.validate_assignments(doc)["ok"]):
				bindings_now.pop_back()
	for i in range(rng.randi_range(0, 2)):
		var bypass := {
			"bypass_id": "bypass-fuzz-%04d-%04d" % [index, i],
			"selector": _gen_selector(),
			"enabled": rng.randf() < 0.8,
		}
		(doc["bypasses"] as Array).append(bypass)
		if not bool(FxResolverScript.validate_assignments(doc)["ok"]):
			(doc["bypasses"] as Array).pop_back()

	var valid: Dictionary = FxResolverScript.validate_assignments(doc)
	_prop("GEN generator produces valid assignment sets", bool(valid["ok"]), "%s %s" % [str(doc["bindings"]), str(valid["errors"])])
	if not bool(valid["ok"]):
		return
	generated_sets += 1

	var contexts: Array = []
	for c in range(contexts_target):
		contexts.append(_gen_context(doc))
	_resolve_properties(doc, contexts)
	if samples.size() < 5:
		var preview: Array = []
		for c in range(mini(contexts_target, 4)):
			var ctx_preview: Dictionary = contexts[c]
			var res_preview: Dictionary = FxResolverScript.resolve(doc, ctx_preview)
			preview.append({
				"context": ctx_preview, "status": str(res_preview.get("status", "")),
				"look_id": str(res_preview.get("look_id", "")), "chain": _chain_tuples(res_preview),
			})
		samples.append({"set": index, "bindings": doc.get("bindings", []), "bypasses": doc.get("bypasses", []), "resolutions": preview})

	# heavy per-set properties on a context that has a winner
	var hot := _context_with_winner(doc)
	if hot.is_empty():
		hot = contexts[0]
	_order_properties(doc, hot)
	_mutation_properties(doc, hot)

# ================================================================ properties

func _resolve_properties(doc: Dictionary, contexts: Array) -> void:
	# P1 is evaluated on a bypass-free copy: bypass precedence is P8's claim.
	var bindings_only := _bypass_free(doc)
	for raw in contexts:
		var context: Dictionary = raw
		var res: Dictionary = FxResolverScript.resolve(bindings_only, context)
		resolutions += 1
		var expected := _winner(bindings_only, context)
		var status := str(res.get("status", ""))
		_prop("P1 most specific enabled selector wins", status == str(expected.get("status", "")) and status in STATUSES, "ctx=%s res=%s expected=%s" % [str(context), str(res), str(expected)])
		if status in ["ASSIGNED", "AMBIGUOUS"]:
			_prop("P1 most specific enabled selector wins", str(res.get("look_id", "")) == str(expected.get("look_id", "")) and str(res.get("binding_id", "")) == str(expected.get("binding_id", "")), "ctx=%s res=%s expected=%s" % [str(context), str(res), str(expected)])
		var again: Dictionary = FxResolverScript.resolve(bindings_only, context)
		_prop("P2 resolve() is deterministic across repeat runs", _same_outcome(res, again), "%s vs %s" % [str(res), str(again)])
		# P10 validator <-> resolver agreement on ambiguity
		if bool(FxResolverScript.validate_assignments(bindings_only)["ok"]):
			_prop("P10 validator and resolver agree about ambiguity", status != "AMBIGUOUS", "validated doc resolved AMBIGUOUS: %s" % str(res))
		elif status == "AMBIGUOUS":
			_prop("P10 validator and resolver agree about ambiguity", true, "")

func _order_properties(doc: Dictionary, context: Dictionary) -> void:
	var base: Dictionary = FxResolverScript.resolve(doc, context)
	# P3 binding insertion order is irrelevant
	var shuffled: Dictionary = doc.duplicate(true)
	shuffled["bindings"] = _permute(shuffled.get("bindings", []))
	shuffled["bypasses"] = _permute(shuffled.get("bypasses", []))
	var shuffled_res: Dictionary = FxResolverScript.resolve(shuffled, context)
	_prop("P3 binding insertion order is irrelevant", _same_outcome(base, shuffled_res), "%s vs %s" % [str(base), str(shuffled_res)])
	var reversed_doc: Dictionary = doc.duplicate(true)
	(reversed_doc["bindings"] as Array).reverse()
	(reversed_doc["bypasses"] as Array).reverse()
	_prop("P3 binding insertion order is irrelevant", _same_outcome(base, FxResolverScript.resolve(reversed_doc, context)), "reversed bindings")

	# P4 JSON field order is irrelevant (binding keys + doc keys rebuilt randomly)
	var reordered: Dictionary = _reorder_doc(doc)
	var reordered_res: Dictionary = FxResolverScript.resolve(reordered, context)
	_prop("P4 JSON field order is irrelevant", _same_outcome(base, reordered_res), "%s vs %s" % [str(base), str(reordered_res)])
	var reloaded = JSON.parse_string(JSON.stringify(doc))
	if reloaded is Dictionary:
		_prop("P4 serialize->reload is irrelevant", _same_outcome(base, FxResolverScript.resolve(reloaded, context)), "json roundtrip")
	else:
		_prop("P4 serialize->reload is irrelevant", false, "JSON.parse_string returned a non-dictionary")

	# P7 a disabled binding opens the fallback
	if str(base.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
		var winner_id := str(base.get("binding_id", ""))
		var disabled: Dictionary = doc.duplicate(true)
		var found := FxResolverScript.set_binding_enabled(disabled, winner_id, false)
		_prop("P7 a disabled binding opens the fallback", found, "set_binding_enabled(%s)" % winner_id)
		var after: Dictionary = FxResolverScript.resolve(disabled, context)
		var expected_after := _winner(disabled, context)
		_prop("P7 a disabled binding opens the fallback", _same_outcome(after, _expected_as_result(expected_after)), "%s vs %s" % [str(after), str(expected_after)])
		if str(after.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
			_prop("P7 a disabled binding opens the fallback", str(after.get("binding_id", "")) != winner_id, "disabled binding still won: %s" % winner_id)
		else:
			_prop("P7 a disabled binding opens the fallback", str(after.get("status", "")) == "UNASSIGNED", "%s" % str(after))
		var bogus := FxResolverScript.set_binding_enabled(doc.duplicate(true), "binding-does-not-exist", false)
		_prop("P7 a disabled binding opens the fallback", not bogus, "set_binding_enabled accepted an unknown binding id")

	# P9 deleting unrelated bindings never changes the winner
	var bindings: Array = doc.get("bindings", [])
	var winner_binding := str(base.get("binding_id", ""))
	for i in range(bindings.size()):
		var binding_id := str((bindings[i] as Dictionary).get("binding_id", ""))
		if binding_id == winner_binding:
			continue
		var trimmed: Dictionary = doc.duplicate(true)
		(trimmed["bindings"] as Array).remove_at(i)
		var trimmed_res: Dictionary = FxResolverScript.resolve(trimmed, context)
		_prop("P9 deleting unrelated bindings never changes the winner", _same_winner(base, trimmed_res), "removed %s -> %s vs %s" % [binding_id, str(trimmed_res), str(base)])

	# P8 bypass blocks ALL styling
	var bypass_key := "chaos|bypass|%s" % FxResolverScript.selector_key(context)
	var blocked: Dictionary = doc.duplicate(true)
	var bypass_selector: Dictionary = _winner_selector(doc, context)
	if bypass_selector.is_empty():
		# no enabled binding matches this context: block with the context's own
		# field set so the injected bypass is guaranteed to match (and prove that
		# a bypass resolves to NO style at all — never a fallback).
		bypass_selector = FxResolverScript.normalize_selector(context)
	(blocked["bypasses"] as Array).append({"bypass_id": "bypass-fuzz-hot-0001", "selector": bypass_selector, "enabled": true})
	var blocked_res: Dictionary = FxResolverScript.resolve(blocked, context)
	_prop("P8 bypass blocks ALL styling", str(blocked_res.get("status", "")) == "BYPASSED" and str(blocked_res.get("look_id", "")) == "", "%s" % str(blocked_res))
	var own_bypass := _has_matching_bypass(doc, context)
	_prop("P8 bypass blocks ALL styling", str(blocked_res.get("bypass_id", "")) == "bypass-fuzz-hot-0001" or own_bypass, "wrong bypass won: %s (the generated set has its own matching bypass: %s)" % [str(blocked_res.get("bypass_id", "")), str(own_bypass)])
	var unrelated: Dictionary = doc.duplicate(true)
	(unrelated["bypasses"] as Array).append({"bypass_id": "bypass-fuzz-hot-0002", "selector": {"fighter_id": "no_such_fighter", "stage_id": "no_such_stage"}, "enabled": true})
	_prop("P8 bypass blocks ALL styling", _same_outcome(FxResolverScript.resolve(unrelated, context), base), "unrelated bypass leaked")
	var disabled_bypass: Dictionary = blocked.duplicate(true)
	for raw in disabled_bypass.get("bypasses", []):
		if raw is Dictionary and str((raw as Dictionary).get("bypass_id", "")) == "bypass-fuzz-hot-0001":
			(raw as Dictionary)["enabled"] = false
	_prop("P8 bypass blocks ALL styling", _same_outcome(FxResolverScript.resolve(disabled_bypass, context), base), "disabled bypass still blocked styling")
	_prop("P8 bypass blocks ALL styling", FxResolverScript.remove_bypass(blocked, (blocked["bypasses"] as Array)[(blocked["bypasses"] as Array).size() - 1].get("selector", {})) and _same_outcome(FxResolverScript.resolve(blocked, context), base), "removed bypass key mismatch (%s)" % bypass_key)

	# P11 specificity is monotone under selector supersets
	for i in range(bindings.size()):
		var a: Dictionary = FxResolverScript.normalize_selector((bindings[i] as Dictionary).get("selector", {}))
		for j in range(bindings.size()):
			if i == j:
				continue
			var b: Dictionary = FxResolverScript.normalize_selector((bindings[j] as Dictionary).get("selector", {}))
			if b.is_empty() or a.is_empty():
				continue
			var is_superset := true
			for key in b.keys():
				if not a.has(key) or str(a[key]) != str(b[key]):
					is_superset = false
					break
			if not is_superset or a.size() == b.size():
				continue
			_prop("P11 specificity is monotone under supersets", FxResolverScript.selector_score(a) > FxResolverScript.selector_score(b), "%s vs %s" % [str(a), str(b)])

func _mutation_properties(doc: Dictionary, context: Dictionary) -> void:
	# P5 equal ambiguous winners are rejected
	var same_selector := {
		"schema": FxResolverScript.ASSIGNMENTS_SCHEMA,
		"bindings": [
			{"binding_id": "binding-amb-0001", "selector": {"element_role": "echo"}, "look_id": "LOOK_A", "enabled": true},
			{"binding_id": "binding-amb-0002", "selector": {"element_role": "echo"}, "look_id": "LOOK_B", "enabled": true},
		],
		"bypasses": [],
	}
	var ctx_echo := {"element_role": "echo"}
	_prop("P5 equal ambiguous winners are rejected", not bool(FxResolverScript.validate_assignments(same_selector)["ok"]), str(FxResolverScript.validate_assignments(same_selector)["errors"]))
	_prop("P6 duplicate normalized selectors are rejected", str(FxResolverScript.validate_assignments(same_selector)["errors"]).contains("duplicate selector"), str(FxResolverScript.validate_assignments(same_selector)["errors"]))
	_prop("P5 equal ambiguous winners are rejected", str(FxResolverScript.resolve(same_selector, ctx_echo).get("status", "")) == "AMBIGUOUS", str(FxResolverScript.resolve(same_selector, ctx_echo)))
	_prop("P5 equal ambiguous winners are rejected", str(FxResolverScript.resolve(same_selector, ctx_echo).get("binding_id", "")) == "binding-amb-0001", "tiebreak must be lexical by binding_id")

	var distinct_equal := {
		"schema": FxResolverScript.ASSIGNMENTS_SCHEMA,
		"bindings": [
			{"binding_id": "binding-amb-0003", "selector": {"mode_family": "1v1"}, "look_id": "LOOK_A", "enabled": true},
			{"binding_id": "binding-amb-0004", "selector": {"stage_id": "1v1"}, "look_id": "LOOK_B", "enabled": true},
		],
		"bypasses": [],
	}
	var ctx_equal := {"mode_family": "1v1", "stage_id": "1v1"}
	var distinct_errors := str(FxResolverScript.validate_assignments(distinct_equal)["errors"])
	_prop("P5 equal ambiguous winners are rejected", not bool(FxResolverScript.validate_assignments(distinct_equal)["ok"]) and distinct_errors.contains("ambiguous winner"), distinct_errors)
	_prop("P6 duplicate normalized selectors are rejected", not distinct_errors.contains("duplicate selector"), "distinct selectors must not be reported as duplicates: " + distinct_errors)
	var distinct_res: Dictionary = FxResolverScript.resolve(distinct_equal, ctx_equal)
	_prop("P5 equal ambiguous winners are rejected", str(distinct_res.get("status", "")) == "AMBIGUOUS", str(distinct_res))
	_prop("P5 equal ambiguous winners are rejected", str(distinct_res.get("binding_id", "")) == "binding-amb-0003", "canonical selector key tiebreak: " + str(distinct_res))

	# P6 duplicate normalized selectors: same fields, different order, empty field dropped
	var duplicate_key := {
		"schema": FxResolverScript.ASSIGNMENTS_SCHEMA,
		"bindings": [
			{"binding_id": "binding-dup-0001", "selector": {"element_role": "echo", "fighter_id": "ice_mage"}, "look_id": "LOOK_A", "enabled": true},
			{"binding_id": "binding-dup-0002", "selector": {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": ""}, "look_id": "LOOK_B", "enabled": true},
		],
		"bypasses": [],
	}
	_prop("P6 duplicate normalized selectors are rejected", FxResolverScript.selector_key((duplicate_key["bindings"] as Array)[0]["selector"]) == FxResolverScript.selector_key((duplicate_key["bindings"] as Array)[1]["selector"]), "normalized keys must collide")
	_prop("P6 duplicate normalized selectors are rejected", str(FxResolverScript.validate_assignments(duplicate_key)["errors"]).contains("duplicate selector"), str(FxResolverScript.validate_assignments(duplicate_key)["errors"]))
	_prop("P6 duplicate normalized selectors are rejected", not bool(FxResolverScript.validate_assignments({"schema": FxResolverScript.ASSIGNMENTS_SCHEMA, "bindings": [(duplicate_key["bindings"] as Array)[0], {"binding_id": "binding-dup-0003", "selector": {"element_role": "echo", "fighter_id": "ice_mage"}, "look_id": "LOOK_A", "enabled": true}], "bypasses": []})["ok"]), "same look, duplicate selector must still be rejected")

	# P6 upsert semantics: updating a selector replaces the binding (no duplicate piles up)
	var upsert: Dictionary = FxResolverScript.new_assignments()
	var id_a := FxResolverScript.upsert_binding(upsert, {"fighter_id": "ice_mage", "element_role": "echo"}, "LOOK_A", "first")
	var id_b := FxResolverScript.upsert_binding(upsert, {"element_role": "echo", "fighter_id": "ice_mage"}, "LOOK_B", "second")
	_prop("P6 duplicate normalized selectors are rejected", id_a == id_b and (upsert["bindings"] as Array).size() == 1 and str((upsert["bindings"] as Array)[0].get("look_id", "")) == "LOOK_B", "upsert must replace instead of appending")
	_prop("P6 duplicate normalized selectors are rejected", bool(FxResolverScript.validate_assignments(upsert)["ok"]), str(FxResolverScript.validate_assignments(upsert)["errors"]))

# ================================================================ malformed / hostile input

func _malformed_section() -> void:
	var prod_dir := "user://vnext_resolver_fuzz_prod"
	var draft_dir := "user://vnext_resolver_fuzz_drafts"
	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))
	prod = FxProductionScript.new()
	prod.data_dir = prod_dir
	drafts = FxDraftsScript.new()
	drafts.base_dir = draft_dir

	var context := {"fighter_id": "ice_mage", "element_role": "echo", "visual_side": "left"}
	var look: Dictionary = FxLookScript.new_look("FUZZ_PROD_LOOK", "Fuzz Production Look", "PRODUCTION")
	var fx: Dictionary = FxLookScript.new_layer("FX", "Fuzz FX")
	fx["input"] = "TRANSFORMED_SOURCE"
	look["layers"].append(fx)
	var assignments: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(assignments, context, "FUZZ_PROD_LOOK", "fuzz")
	var applied: Dictionary = prod.apply({"look": look, "assignments": assignments})
	_check(bool(applied.get("ok", false)), "malformed fixture applies", str(applied.get("errors", [])))
	var asg_bytes := _file_bytes(prod.assignments_path())
	var look_bytes := _file_bytes(prod.look_path("FUZZ_PROD_LOOK"))

	# ---- missing Look: the production layer must report a truthful BROKEN state --
	var orphan: Dictionary = FxResolverScript.new_assignments()
	FxResolverScript.upsert_binding(orphan, {"fighter_id": "doge_man"}, "GHOST_LOOK", "missing look")
	var rejected: Dictionary = prod.apply({"assignments": orphan})
	_check(not bool(rejected.get("ok", false)) and str(rejected.get("stage", "")) == "validate-references", "malformed: binding to a missing Look is refused", str(rejected))
	_check(_file_bytes(prod.assignments_path()) == asg_bytes and not prod.list_look_ids().has("GHOST_LOOK"), "malformed: a refused apply leaves Production byte-identical")
	var ghost: Dictionary = prod.load_look("GHOST_LOOK")
	_check(not bool(ghost.get("ok", false)) and str(ghost.get("errors", [])).contains("GHOST_LOOK"), "malformed: a missing Look reports ok=false with its id", str(ghost.get("errors", [])))

	_wipe_look_file("FUZZ_PROD_LOOK")
	var gone: Dictionary = prod.load_look("FUZZ_PROD_LOOK")
	_check(not bool(gone.get("ok", false)) and str(gone.get("errors", [])).contains("FUZZ_PROD_LOOK"), "malformed: a deleted assigned Look is reported", str(gone.get("errors", [])))
	var state: Dictionary = prod.production_state()
	_note("production_state() while a binding points at a DELETED Look file: ok=%s recovery_required=%s (it validates the Look files that exist, so a removed file is only surfaced by load_look / the row badge / the editor open — not by the startup diagnostic)" % [str(state.get("ok", false)), str(state.get("recovery_required", false))])
	divergence_count("production-state-missing-look", "production_state() returns ok=%s for a binding whose Look file was deleted (load_look and the row badge do report it)" % str(state.get("ok", false)))
	_check(_browser_badge_for(context) == "⚠ BROKEN", "malformed: the browser badge reports BROKEN for the missing Look", _browser_badge_for(context))
	var session = FxSessionScript.new(prod, drafts)
	var opened: Dictionary = session.open_target("fuzz_echo_left", context.duplicate(true), "fuzz|echo_left", "echo")
	_check(bool(opened.get("ok", false)) and str(opened.get("opened", "")) == "neutral", "malformed: the editor fails safe into a neutral design", str(opened))
	_check(str(session.mode) == "EDIT_UNASSIGNED" and (session.look.get("layers", []) as Array).size() == 1, "malformed: no styling is loaded for a broken reference", str(session.mode))
	_check(not (session.last_errors as Array).is_empty() and str(session.last_errors).contains("FUZZ_PROD_LOOK"), "malformed: the broken reference is reported in the session errors", str(session.last_errors))
	var broken_badge := session.badge_text()
	_note("editor badge while the assigned Look file is missing: %s (the browser/row badge reports BROKEN; badge_text() has no BROKEN branch for an unresolvable effective style)" % broken_badge)
	divergence_count("editor-badge-missing-look", "session.badge_text() reports %s while the assigned Look file is missing; the browser row badge reports BROKEN" % broken_badge)
	# applying from the fail-safe neutral design may only repair transactionally or refuse
	var repair: Dictionary = session.apply()
	if bool(repair.get("ok", false)):
		var repaired: Dictionary = prod.load_look(str(repair.get("look_id", "")))
		_check(bool(repaired.get("ok", false)) and int((repaired.get("doc", {}) as Dictionary).get("revision", 0)) == 1, "malformed: an applied repair writes a valid revision-1 Look", str(repair))
		_check(bool(prod.production_state().get("ok", false)), "malformed: an applied repair leaves Production valid again", str(prod.production_state().get("errors", [])))
	else:
		_check(prod.list_look_ids() == ["FUZZ_PROD_LOOK"] and _file_bytes(prod.assignments_path()) == asg_bytes, "malformed: a refused apply leaves the broken Production untouched", str(repair.get("errors", [])))
	_restore_look_file(look_bytes)
	_check(bool(prod.load_look("FUZZ_PROD_LOOK").get("ok", false)), "malformed: the Look recovers once its file is back")
	asg_bytes = _file_bytes(prod.assignments_path())

	# a corrupt (not deleted) Look file demands an explicit recovery
	_write_text(ProjectSettings.globalize_path(prod.look_path("FUZZ_PROD_LOOK")), "{{{ corrupt look")
	Engine.print_error_messages = false
	var corrupt_look: Dictionary = prod.load_look("FUZZ_PROD_LOOK")
	Engine.print_error_messages = true
	_check(not bool(corrupt_look.get("ok", false)) and bool(corrupt_look.get("recovery_required", false)), "malformed: a corrupt Look file requires recovery", str(corrupt_look.get("errors", [])))
	var corrupt_state: Dictionary = prod.production_state()
	_check(not bool(corrupt_state.get("ok", false)) and bool(corrupt_state.get("recovery_required", false)), "malformed: production_state requires recovery for a corrupt Look", str(corrupt_state.get("errors", [])))
	_check(_file_bytes(prod.assignments_path()) == asg_bytes, "malformed: an unreadable Look never rewrites assignments")
	_restore_look_file(look_bytes)
	_check(bool(prod.load_look("FUZZ_PROD_LOOK").get("ok", false)), "malformed: the Look recovers after a corrupt file")

	# ---- corrupt assignments JSON ----------------------------------------------
	_write_text(ProjectSettings.globalize_path(prod.assignments_path()), "{{{{ not json")
	Engine.print_error_messages = false
	var corrupt: Dictionary = prod.load_assignments()
	Engine.print_error_messages = true
	_check(not bool(corrupt.get("ok", false)) and bool(corrupt.get("recovery_required", false)), "malformed: corrupt assignments JSON requires recovery", str(corrupt.get("errors", [])))
	var corrupt_asg_state: Dictionary = prod.production_state()
	_check(not bool(corrupt_asg_state.get("ok", false)), "malformed: corrupt assignments flag production_state", str(corrupt_asg_state.get("errors", [])))
	var broken_session = FxSessionScript.new(prod, drafts)
	broken_session.open_target("fuzz_echo_left", context.duplicate(true), "fuzz|echo_left", "echo")
	_check(str(broken_session.resolution.get("status", "")) == "BROKEN", "malformed: the resolver status is BROKEN for unreadable assignments", str(broken_session.resolution))
	_check(broken_session.badge_text().contains("BROKEN"), "malformed: the editor badge reports BROKEN", broken_session.badge_text())
	_check(broken_session.effective_look_id() == "", "malformed: no effective style while assignments are broken", broken_session.effective_look_id())
	var broken_apply: Dictionary = broken_session.apply()
	_check(not bool(broken_apply.get("ok", false)), "malformed: apply is refused while assignments are broken", str(broken_apply.get("errors", [])))
	_check(_file_bytes(prod.look_path("FUZZ_PROD_LOOK")) == look_bytes, "malformed: broken assignments never touch the Look files")
	_write_bytes(prod.assignments_path(), asg_bytes)
	_check(bool(prod.load_assignments().get("ok", false)), "malformed: assignments recover after restoring the bytes")

	# ---- invalid IDs, duplicate IDs, unsupported schema version -----------------
	var short_id: Dictionary = FxResolverScript.new_assignments()
	(short_id["bindings"] as Array).append({"binding_id": "abc", "selector": {"element_role": "echo"}, "look_id": "LOOK_A", "enabled": true})
	_check(str(FxResolverScript.validate_assignments(short_id)["errors"]).contains("too short"), "malformed: short binding_id is rejected", str(FxResolverScript.validate_assignments(short_id)["errors"]))
	var empty_look: Dictionary = FxResolverScript.new_assignments()
	(empty_look["bindings"] as Array).append({"binding_id": "binding-bad-0001", "selector": {"element_role": "echo"}, "look_id": "", "enabled": true})
	_check(str(FxResolverScript.validate_assignments(empty_look)["errors"]).contains("look_id must not be empty"), "malformed: empty look_id is rejected", str(FxResolverScript.validate_assignments(empty_look)["errors"]))
	var empty_selector: Dictionary = FxResolverScript.new_assignments()
	(empty_selector["bindings"] as Array).append({"binding_id": "binding-bad-0002", "selector": {"unknown_field": "x"}, "look_id": "LOOK_A", "enabled": true})
	_check(str(FxResolverScript.validate_assignments(empty_selector)["errors"]).contains("empty selector"), "malformed: a selector with no known field is rejected", str(FxResolverScript.validate_assignments(empty_selector)["errors"]))
	var duplicate_ids: Dictionary = FxResolverScript.new_assignments()
	(duplicate_ids["bindings"] as Array).append({"binding_id": "binding-dup-id-0001", "selector": {"element_role": "echo"}, "look_id": "LOOK_A", "enabled": true})
	(duplicate_ids["bindings"] as Array).append({"binding_id": "binding-dup-id-0001", "selector": {"fighter_id": "ice_mage"}, "look_id": "LOOK_B", "enabled": true})
	_check(str(FxResolverScript.validate_assignments(duplicate_ids)["errors"]).contains("duplicate"), "malformed: duplicate binding ids are rejected", str(FxResolverScript.validate_assignments(duplicate_ids)["errors"]))
	var bad_schema: Dictionary = FxResolverScript.new_assignments()
	bad_schema["schema"] = "NRCU_VS_FX_ASSIGNMENTS_V1"
	_check(str(FxResolverScript.validate_assignments(bad_schema)["errors"]).contains("schema"), "malformed: an unsupported schema version is rejected", str(FxResolverScript.validate_assignments(bad_schema)["errors"]))
	var bypass_bad: Dictionary = FxResolverScript.new_assignments()
	(bypass_bad["bypasses"] as Array).append({"bypass_id": "short", "selector": {"element_role": "echo"}, "enabled": true})
	_check(str(FxResolverScript.validate_assignments(bypass_bad)["errors"]).contains("bypass_id too short"), "malformed: short bypass_id is rejected", str(FxResolverScript.validate_assignments(bypass_bad)["errors"]))

	# ---- broken custom asset + duplicate layer ids in a Look --------------------
	var broken_asset: Dictionary = FxLookScript.new_look("FUZZ_BROKEN_ASSET", "Broken Asset", "PRODUCTION")
	var fx_layer: Dictionary = FxLookScript.new_layer("FX", "Broken Mask")
	fx_layer["input"] = "ORIGINAL_SOURCE"
	fx_layer["mask"]["enabled"] = true
	fx_layer["mask"]["source"] = "CUSTOM_MASK"
	fx_layer["mask"]["custom_mask"] = "res://assets/vnext/fuzz_missing_asset.png"
	broken_asset["layers"].append(fx_layer)
	var asset_check: Dictionary = FxLookScript.validate(FxLookScript.materialize(broken_asset))
	_check(not bool(asset_check["ok"]) and str(asset_check["errors"]).contains("does not exist"), "malformed: a broken custom asset reference is rejected", str(asset_check["errors"]))
	var asset_apply: Dictionary = prod.apply({"look": broken_asset})
	_check(not bool(asset_apply.get("ok", false)) and str(asset_apply.get("stage", "")) in ["assets", "validate-look"] and str(asset_apply.get("errors", [])).contains("does not exist"), "malformed: a Look with a broken asset is refused", str(asset_apply))
	var duplicate_layers: Dictionary = FxLookScript.materialize(FxLookScript.new_look("FUZZ_DUP_LAYERS", "Dup Layers", "PRODUCTION"))
	var extra: Dictionary = FxLookScript.new_layer("FX", "Extra")
	extra["layer_id"] = str((duplicate_layers["layers"] as Array)[0]["layer_id"])
	(duplicate_layers["layers"] as Array).append(extra)
	var dup_check: Dictionary = FxLookScript.validate(duplicate_layers)
	_check(not bool(dup_check["ok"]) and str(dup_check["errors"]).contains("duplicate"), "malformed: duplicate layer ids are rejected", str(dup_check["errors"]))
	_check(_file_bytes(prod.look_path("FUZZ_PROD_LOOK")) == look_bytes and _file_bytes(prod.assignments_path()) == asg_bytes, "malformed: no malformed input reached Production")

	_wipe_dir(ProjectSettings.globalize_path(prod_dir))
	_wipe_dir(ProjectSettings.globalize_path(draft_dir))

func _hostile_section() -> void:
	_prop("P13 hostile inputs stay safe", FxResolverScript.normalize_selector(null).is_empty(), "normalize_selector(null)")
	_prop("P13 hostile inputs stay safe", FxResolverScript.selector_key(null) == "", "selector_key(null)")
	_prop("P13 hostile inputs stay safe", FxResolverScript.selector_score(null) == 0, "selector_score(null)")
	_prop("P13 hostile inputs stay safe", not FxResolverScript.selector_matches(null, {}), "selector_matches(null, {})")
	_prop("P13 hostile inputs stay safe", not FxResolverScript.selector_matches({"element_role": "echo"}, null), "selector_matches(sel, null)")
	_prop("P13 hostile inputs stay safe", FxResolverScript.compatible_selectors(null, {"fighter_id": "ice_mage"}), "compatible_selectors(null, x)")
	_prop("P13 hostile inputs stay safe", str(FxResolverScript.normalize_selector({"element_role": 5})["element_role"]) == "5", "numeric selector values must be string-coerced")
	_prop("P13 hostile inputs stay safe", FxResolverScript.normalize_selector({"element_role": "", "fighter_id": ""}).is_empty(), "empty selector values must be dropped")
	_prop("P13 hostile inputs stay safe", not FxResolverScript.normalize_selector({"element_role": null}).is_empty(), "null selector values are string-coerced (documented coercion, not a crash)")
	var weird := {
		"schema": 3,
		"bindings": "nope",
		"bypasses": [null, 7, "x", {"selector": null}, {"bypass_id": "bypass-weird-0001", "selector": {"element_role": "echo"}}],
		"extra": [1, 2, 3],
	}
	var weird_res: Dictionary = FxResolverScript.resolve(weird, {"element_role": "echo", "fighter_id": {"nested": true}})
	_prop("P13 hostile inputs stay safe", str(weird_res.get("status", "")) in STATUSES, str(weird_res))
	var weird_check: Dictionary = FxResolverScript.validate_assignments(weird)
	_prop("P13 hostile inputs stay safe", not bool(weird_check["ok"]) and not (weird_check.get("errors", []) as Array).is_empty(), str(weird_check))
	_prop("P13 hostile inputs stay safe", not bool(FxResolverScript.validate_assignments({})["ok"]), "validate_assignments({})")
	_prop("P13 hostile inputs stay safe", bool(FxResolverScript.validate_assignments(FxResolverScript.new_assignments())["ok"]), "validate_assignments(empty)")
	var garbage_binding: Dictionary = FxResolverScript.new_assignments()
	(garbage_binding["bindings"] as Array).append(null)
	(garbage_binding["bindings"] as Array).append("nope")
	(garbage_binding["bindings"] as Array).append({"binding_id": "binding-weird-0001", "selector": {"fighter_id": "ice_mage"}, "look_id": "LOOK_A", "enabled": "yes"})
	var garbage_res: Dictionary = FxResolverScript.resolve(garbage_binding, {"fighter_id": "ice_mage"})
	_prop("P13 hostile inputs stay safe", str(garbage_res.get("status", "")) in STATUSES, str(garbage_res))
	_prop("P13 hostile inputs stay safe", str(garbage_res.get("status", "")) == "ASSIGNED", "a truthy enabled flag still resolves: %s" % str(garbage_res))

# ================================================================ independent winner

func _winner(doc: Dictionary, context: Dictionary) -> Dictionary:
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
		return {"status": "UNASSIGNED", "chain": []}
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
	var chain: Array = []
	for i in range(candidates.size()):
		var entry: Dictionary = candidates[i].duplicate()
		entry["winner"] = i == 0
		chain.append(entry)
	return {
		"status": "AMBIGUOUS" if ambiguous else "ASSIGNED",
		"look_id": str(top["look_id"]), "binding_id": str(top["binding_id"]),
		"chain": chain,
	}

func _has_matching_bypass(doc: Dictionary, context: Dictionary) -> bool:
	for raw in doc.get("bypasses", []):
		if not (raw is Dictionary):
			continue
		var bypass: Dictionary = raw
		if not bool(bypass.get("enabled", true)):
			continue
		if FxResolverScript.selector_matches(bypass.get("selector", {}), context):
			return true
	return false

func _bypass_free(doc: Dictionary) -> Dictionary:
	var copy: Dictionary = doc.duplicate(true)
	copy["bypasses"] = []
	return copy

func _same_winner(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("status", "")) != str(b.get("status", "")):
		return false
	if str(a.get("status", "")) == "UNASSIGNED":
		return true
	return str(a.get("look_id", "")) == str(b.get("look_id", "")) and str(a.get("binding_id", "")) == str(b.get("binding_id", ""))

func _expected_as_result(expected: Dictionary) -> Dictionary:
	if str(expected.get("status", "")) == "UNASSIGNED":
		return {"status": "UNASSIGNED"}
	return expected

func _same_outcome(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("status", "")) != str(b.get("status", "")):
		return false
	if str(a.get("status", "")) == "UNASSIGNED":
		return true
	return str(a.get("look_id", "")) == str(b.get("look_id", "")) and str(a.get("binding_id", "")) == str(b.get("binding_id", "")) and _chain_tuples(a) == _chain_tuples(b)

func _chain_tuples(res: Dictionary) -> Array:
	var out: Array = []
	for raw in res.get("chain", []):
		if not (raw is Dictionary):
			out.append("?")
			continue
		var entry: Dictionary = raw
		out.append("%s|%s|%d|%d|%s" % [str(entry.get("binding_id", "")), str(entry.get("look_id", "")), int(entry.get("score", 0)), int(entry.get("count", 0)), str(bool(entry.get("winner", false)))])
	return out

func _winner_selector(doc: Dictionary, context: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	var best_count := -1
	for raw in doc.get("bindings", []):
		if not (raw is Dictionary) or not bool((raw as Dictionary).get("enabled", true)):
			continue
		var norm: Dictionary = FxResolverScript.normalize_selector((raw as Dictionary).get("selector", {}))
		if norm.is_empty():
			continue
		var matches := true
		for key in norm.keys():
			if str(context.get(str(key), "")) != str(norm[key]):
				matches = false
				break
		if not matches:
			continue
		var score := FxResolverScript.selector_score(norm)
		if score > best_score or (score == best_score and norm.size() > best_count):
			best = norm
			best_score = score
			best_count = norm.size()
	return best

# ================================================================ generation helpers

func _gen_selector() -> Dictionary:
	var count := rng.randi_range(1, 4)
	var pool: Array = FIELDS.duplicate()
	var out := {}
	for i in range(mini(count, pool.size())):
		var key := str(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(key)
		var values: Array = VALUES[key]
		out[key] = str(values[rng.randi_range(0, values.size() - 1)])
	return out

func _gen_context(doc: Dictionary) -> Dictionary:
	var context := {}
	for field in FIELDS:
		context[field] = str((VALUES[field] as Array)[rng.randi_range(0, (VALUES[field] as Array).size() - 1)])
	var bindings: Array = doc.get("bindings", [])
	if not bindings.is_empty() and rng.randf() < 0.7:
		var binding: Dictionary = bindings[rng.randi_range(0, bindings.size() - 1)]
		var norm: Dictionary = FxResolverScript.normalize_selector(binding.get("selector", {}))
		for key in norm.keys():
			context[key] = str(norm[key])
	for field in FIELDS:
		if rng.randf() < 0.25:
			context[field] = str((VALUES[field] as Array)[rng.randi_range(0, (VALUES[field] as Array).size() - 1)])
	return context

func _context_with_winner(doc: Dictionary) -> Dictionary:
	var bindings: Array = doc.get("bindings", [])
	if bindings.is_empty():
		return {}
	var order: Array = range(bindings.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for idx in order:
		var binding: Dictionary = bindings[idx]
		var norm: Dictionary = FxResolverScript.normalize_selector(binding.get("selector", {}))
		if norm.is_empty():
			continue
		var context: Dictionary = {}
		for field in FIELDS:
			context[field] = str((VALUES[field] as Array)[0])
		for key in norm.keys():
			context[key] = str(norm[key])
		if str(FxResolverScript.resolve(doc, context).get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
			return context
	return {}

func _permute(arr: Array) -> Array:
	var out: Array = arr.duplicate(true)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out

func _reorder_doc(doc: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = doc.keys()
	for i in range(keys.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = keys[i]
		keys[i] = keys[j]
		keys[j] = tmp
	for key in keys:
		var value = doc[key]
		if key == "bindings" or key == "bypasses":
			var rebuilt: Array = []
			for raw in value:
				if not (raw is Dictionary):
					rebuilt.append(raw)
					continue
				var entry := {}
				var entry_keys: Array = (raw as Dictionary).keys()
				for i in range(entry_keys.size() - 1, 0, -1):
					var j := rng.randi_range(0, i)
					var tmp = entry_keys[i]
					entry_keys[i] = entry_keys[j]
					entry_keys[j] = tmp
				for field in entry_keys:
					entry[field] = (raw as Dictionary)[field]
				rebuilt.append(entry)
			out[key] = rebuilt
		else:
			out[key] = value
	return out

# ================================================================ browser badge model / malformed helpers

func _browser_badge_for(context: Dictionary) -> String:
	# Faithful model of the shell's browser row badge (lab_shell.gd `_badge_for_key`).
	var loaded: Dictionary = prod.load_assignments()
	if not bool(loaded.get("ok", false)):
		return "⚠ BROKEN"
	var doc: Dictionary = loaded["doc"]
	var res: Dictionary = FxResolverScript.resolve(doc, context)
	var status := str(res.get("status", ""))
	if status == "BYPASSED":
		return "⦸ STYLING OFF"
	if status in ["ASSIGNED", "AMBIGUOUS"]:
		if not FileAccess.file_exists(prod.look_path(str(res.get("look_id", "")))):
			return "⚠ BROKEN"
		return "⚠ AMBIGUOUS" if status == "AMBIGUOUS" else "● ASSIGNED"
	for raw in doc.get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), context):
				return "○ DISABLED"
	return "○ UNASSIGNED"

func _wipe_look_file(look_id: String) -> void:
	var path := ProjectSettings.globalize_path(prod.look_path(look_id))
	if FileAccess.file_exists(prod.look_path(look_id)):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(prod.look_path(look_id) + ".prev"):
		DirAccess.remove_absolute(path + ".prev")

func _restore_look_file(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(prod.look_path("FUZZ_PROD_LOOK"), FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _file_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

# ================================================================ reporting

func _prop(family: String, ok: bool, detail := "") -> void:
	var f: Dictionary = families.get(family, {"instances": 0, "failures": 0, "detail": "", "examples": []})
	f["instances"] = int(f["instances"]) + 1
	if not ok:
		f["failures"] = int(f["failures"]) + 1
		if str(f["detail"]) == "":
			f["detail"] = detail
		var examples: Array = f["examples"]
		if examples.size() < 3:
			examples.append(detail)
	families[family] = f

func divergence_count(id: String, text: String) -> void:
	var entry: Dictionary = divergences.get(id, {"count": 0, "text": text})
	entry["count"] = int(entry["count"]) + 1
	divergences[id] = entry

func _note(text: String) -> void:
	notes.append(text)
	print("[NOTE] " + text)

func _evidence(useed: int) -> void:
	for family in families.keys():
		var f: Dictionary = families[family]
		_check(int(f["failures"]) == 0, "%s (%d assertions)" % [str(family), int(f["instances"])], str(f["detail"]))
	var summary := {
		"suite": "fx_vnext_resolver_fuzz_test", "seed": useed,
		"sets_requested": sets_target, "sets_valid": generated_sets,
		"contexts_per_set": contexts_target, "resolutions": resolutions,
		"dropped_candidates": dropped_candidates,
		"checks": checks.size(), "failures": failures,
		"families": families, "divergences": divergences, "notes": notes,
		"status": "PASS" if failures == 0 else "FAIL",
	}
	var sf := FileAccess.open(out_dir.path_join("summary_resolver_fuzz_check.json"), FileAccess.WRITE)
	if sf != null:
		sf.store_string(JSON.stringify(summary, "  "))
		sf.close()
	var sample_file := FileAccess.open(out_dir.path_join("resolver_fuzz_samples.json"), FileAccess.WRITE)
	if sample_file != null:
		sample_file.store_string(JSON.stringify(samples, "  "))
		sample_file.close()
	var line := "[FX-RESOLVER-FUZZ] done · checks=%d failures=%d · sets=%d resolutions=%d families=%d" % [checks.size(), failures, generated_sets, resolutions, families.size()]
	var lf := FileAccess.open(out_dir.path_join("resolver_fuzz_checks.log"), FileAccess.WRITE)
	if lf != null:
		lf.store_string("\n".join(checks) + "\n" + line + "\n")
		lf.close()
	print(line)
	quit(1 if failures > 0 else 0)

func _check(ok: bool, name: String, detail := "") -> void:
	var line := "[CHECK] %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""]
	checks.append(line)
	if not ok:
		failures += 1
	print(line)

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
