class_name FxSession
extends RefCounted
# NRCU FX Lab vNext — editor session state machine (specs/06, specs/09, specs/15 §8–§11).
#
# Owns the authoring loop for one target at a time: open (Draft -> Production ->
# neutral), edit, auto-stash, Apply/Update with the novice scope builder, shared
# protection (Edit Shared Look / Make Unique), Styling ON/OFF and the Why?
# explanation. Pure logic: no UI, no rendering. The shell drives this module and
# forwards the working Look to the layer renderer.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

const FIGHTER_ROLES := ["primary", "echo", "name"]

var production
var drafts

# --- current target
var current_key: String = ""
var context: Dictionary = {}
var signature: String = ""
var role: String = ""

# --- working state
var look: Dictionary = {}
var base: Dictionary = {} # {kind: unassigned|production|draft, look_id, revision, shared_count}
var mode: String = "NONE" # NONE | EDIT_UNASSIGNED | EDIT_PRODUCTION_UNIQUE | SHARED_PROTECTED | EDIT_SHARED_DRAFT
var dirty: bool = false
var last_errors: Array = []
var last_warnings: Array = []
var resolution: Dictionary = {}
var styling_enabled: bool = true
var _undo_stack: Array = []
var _redo_stack: Array = []
var _stacks_by_sig: Dictionary = {}

func _init(production_ref, drafts_ref) -> void:
	production = production_ref
	drafts = drafts_ref

# ================================================================ undo / redo

func snapshot() -> void:
	# Called before a structural/value edit; keeps the last 60 states.
	_undo_stack.append(look.duplicate(true))
	if _undo_stack.size() > 60:
		_undo_stack.pop_front()
	_redo_stack.clear()

func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(look.duplicate(true))
	look = _undo_stack.pop_back()
	dirty = true
	return true

func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(look.duplicate(true))
	look = _redo_stack.pop_back()
	dirty = true
	return true

# ================================================================ draft revert

func revert_draft() -> Dictionary:
	# G — Revert Draft returns to the assigned clean Look (or neutral).
	if str(signature) != "":
		drafts.clear_target(signature)
	var look_id := effective_look_id()
	if look_id != "":
		var loaded: Dictionary = production.load_look(look_id)
		if bool(loaded.get("ok", false)):
			look = loaded["doc"]
			dirty = false
			_undo_stack.clear()
			_redo_stack.clear()
			return {"ok": true, "errors": [], "reverted_to": look_id}
	look = FxLookScript.new_look("", "")
	look["name"] = _breadcrumb_name()
	base = {"kind": "unassigned", "look_id": "", "revision": 0, "shared_count": 0}
	mode = "EDIT_UNASSIGNED"
	dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	return {"ok": true, "errors": [], "reverted_to": ""}

# ================================================================ library / assignment ops

func unassign_target() -> Dictionary:
	# I — Unassign removes the binding for the target's novice scope; the Look
	# stays in the Library untouched.
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	var key := FxResolverScript.selector_key(novice_selector())
	asg_doc["bindings"] = (asg_doc.get("bindings", []) as Array).filter(func(raw):
		return not (raw is Dictionary) or FxResolverScript.selector_key((raw as Dictionary).get("selector", {})) != key
	)
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	_refresh_resolution()
	return {"ok": true, "errors": []}

func disable_binding(binding_id: String) -> Dictionary:
	# I — Advanced: disable a specific binding so lower-priority rules win.
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	if not FxResolverScript.set_binding_enabled(asg_doc, binding_id, false):
		return {"ok": false, "errors": ["binding not found: " + binding_id]}
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	_refresh_resolution()
	return {"ok": true, "errors": []}

func look_library() -> Array:
	var out: Array = []
	for look_id in production.list_look_ids():
		var loaded: Dictionary = production.load_look(look_id)
		var usage: Dictionary = production.usage(look_id)
		out.append({
			"look_id": str(look_id),
			"status": str((loaded.get("doc", {}) as Dictionary).get("status", "?")),
			"revision": int((loaded.get("doc", {}) as Dictionary).get("revision", 0)),
			"usage": int(usage.get("count", 0)),
			"valid": bool(loaded.get("ok", false)),
		})
	return out

func delete_look(look_id: String) -> Dictionary:
	# I — Delete Look is blocked while assignments still reference it.
	var usage: Dictionary = production.usage(look_id)
	if int(usage.get("count", 0)) > 0:
		return {"ok": false, "errors": ["Look is used by %d assignment(s) — unassign or replace first" % int(usage["count"])], "usage": usage}
	var path: String = production.look_path(look_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["look not found: " + look_id]}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok": true, "errors": []}

# ================================================================ opening

func open_target(key: String, ctx: Dictionary, signature_: String, role_: String) -> Dictionary:
	var outgoing_sig := str(signature)
	if outgoing_sig != "":
		# R3 §9 fix: per-target undo/redo history — stash the outgoing target's
		# stacks so they can never bleed onto the next target, and restore the
		# incoming target's own history below.
		_stacks_by_sig[outgoing_sig] = {"undo": _undo_stack.duplicate(), "redo": _redo_stack.duplicate()}
	current_key = key
	context = ctx
	signature = signature_
	role = role_
	var inbound: Dictionary = _stacks_by_sig.get(signature_, {})
	_undo_stack = (inbound.get("undo", []) as Array).duplicate()
	_redo_stack = (inbound.get("redo", []) as Array).duplicate()
	look = {}
	base = {}
	mode = "NONE"
	dirty = false
	last_errors = []
	last_warnings = []

	var assignments: Dictionary = production.load_assignments()
	resolution = FxResolverScript.resolve(assignments.get("doc", {}), context) if bool(assignments.get("ok", false)) else {"status": "BROKEN", "chain": []}
	styling_enabled = str(resolution.get("status", "")) != "BYPASSED"

	# 1) exact target Draft exists → open Draft (specs/06 §2).
	var draft_loaded: Dictionary = drafts.load_target(signature_)
	if bool(draft_loaded.get("ok", false)):
		var record: Dictionary = draft_loaded["record"]
		look = record["look"]
		base = {
			"kind": "draft",
			"look_id": str(look.get("look_id", "")),
			"revision": int(record.get("base_revision", 0)),
			"shared_count": 0,
		}
		dirty = bool(record.get("dirty", true))
		mode = "EDIT_UNASSIGNED"
		if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
			var prod_id := str(resolution.get("look_id", ""))
			if prod_id != "" and prod_id == str(look.get("look_id", "")):
				base["kind"] = "production"
				base["look_id"] = prod_id
				# R3 §9: record shared usage; the APPLY guard enforces protection
				# for draft-branch sessions (no fake shared-draft mode).
				var usage: Dictionary = production.usage(prod_id)
				base["shared_count"] = int(usage.get("count", 0))
			mode = "EDIT_PRODUCTION_UNIQUE"
		return {"ok": true, "opened": "draft", "errors": []}

	# 2) else resolve Production Assignment; 3) load Production Look.
	if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
		var look_id := str(resolution.get("look_id", ""))
		var loaded: Dictionary = production.load_look(look_id)
		if bool(loaded.get("ok", false)):
			var usage: Dictionary = production.usage(look_id)
			look = loaded["doc"]
			base = {
				"kind": "production",
				"look_id": look_id,
				"revision": int(look.get("revision", 1)),
				"shared_count": int(usage.get("count", 0)),
			}
			mode = "SHARED_PROTECTED" if int(usage.get("count", 0)) > 1 else "EDIT_PRODUCTION_UNIQUE"
			var shared_draft: Dictionary = drafts.load_shared(look_id, int(base["revision"]))
			if bool(shared_draft.get("ok", false)):
				look = shared_draft["record"]["look"]
				mode = "EDIT_SHARED_DRAFT"
				dirty = bool(shared_draft["record"].get("dirty", true))
			return {"ok": true, "opened": "production", "errors": []}
		last_errors.append("assigned look is missing or broken: " + look_id)

	# 4) otherwise create a neutral Source-only working design.
	look = FxLookScript.new_look("", "")
	look["name"] = _breadcrumb_name()
	base = {"kind": "unassigned", "look_id": "", "revision": 0, "shared_count": 0}
	mode = "EDIT_UNASSIGNED"
	return {"ok": true, "opened": "neutral", "errors": last_errors.duplicate()}

func _breadcrumb_name() -> String:
	var selector := novice_selector()
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

# ================================================================ scope

func novice_selector() -> Dictionary:
	# specs/15 §8: exact novice scope rules.
	var selector: Dictionary = {}
	if role in FIGHTER_ROLES:
		selector["fighter_id"] = str(context.get("fighter_id", ""))
		selector["element_role"] = str(context.get("element_role", role))
		selector["visual_side"] = str(context.get("visual_side", ""))
		return FxResolverScript.normalize_selector(selector)
	if role == "stage":
		selector["element_id"] = str(context.get("element_id", "stage"))
		var stage_id := str(context.get("stage_id", ""))
		if stage_id != "":
			selector["stage_id"] = stage_id
		return FxResolverScript.normalize_selector(selector)
	selector["element_id"] = str(context.get("element_id", ""))
	return FxResolverScript.normalize_selector(selector)

func proposed_look_id() -> String:
	var selector := novice_selector()
	var parts: Array = []
	if selector.has("fighter_id"):
		parts.append(str(selector["fighter_id"]))
	elif selector.has("element_id"):
		parts.append(str(selector["element_id"]))
	if selector.has("element_role"):
		parts.append(str(selector["element_role"]))
	if selector.has("stage_id") and not selector.has("element_role"):
		parts.append(str(selector["stage_id"]))
	if selector.has("visual_side"):
		parts.append(str(selector["visual_side"]))
	var raw := "_".join(parts).to_upper()
	var clean := ""
	for i in range(raw.length()):
		var c := raw[i]
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_":
			clean += c
	while clean.begins_with("_"):
		clean = clean.substr(1)
	while clean.ends_with("_"):
		clean = clean.substr(0, clean.length() - 1)
	return clean if clean != "" else "UNTITLED_FX"

func unique_look_id(proposal: String, keep: String) -> String:
	# specs/15 §10: `_2`, `_3`, ... deterministically until unique; an update of
	# the currently assigned Look keeps its id.
	if proposal == "":
		return proposal
	var existing: Array = production.list_look_ids()
	if not existing.has(proposal) or proposal == keep:
		return proposal
	var index := 2
	while existing.has("%s_%d" % [proposal, index]):
		index += 1
	return "%s_%d" % [proposal, index]

# ================================================================ editing

func is_editable() -> bool:
	return mode != "SHARED_PROTECTED"

func edit(mutator: Callable) -> Dictionary:
	if not is_editable():
		last_errors = ["shared production Look opens protected — choose Edit Shared Look or Make Unique first"]
		return {"ok": false, "errors": last_errors.duplicate()}
	var result = mutator.call(look)
	if result is Dictionary and not bool((result as Dictionary).get("ok", true)):
		return result
	look = FxLookScript.materialize(look)
	var check: Dictionary = FxLookScript.validate(look)
	last_warnings = check["errors"] if not bool(check["ok"]) else []
	dirty = true
	return {"ok": true, "errors": [], "warnings": last_warnings.duplicate()}

func stash() -> Dictionary:
	# Auto-stash (specs/10 §2) — crash-safe editor work, never Production.
	if base.get("kind", "") == "production" and int(base.get("shared_count", 0)) > 1 and mode == "EDIT_SHARED_DRAFT":
		return drafts.save_shared(str(base["look_id"]), int(base["revision"]), look, dirty)
	if str(signature) == "":
		return {"ok": false, "errors": ["no target signature"]}
	return drafts.save_target(signature, look, int(base.get("revision", 0)), dirty)

func save_draft() -> Dictionary:
	var result := stash()
	if bool(result.get("ok", false)):
		return {"ok": true, "errors": [], "message": "Draft saved"}
	return result

# ================================================================ apply / update

func _prepare_doc(final_id: String, revision: int) -> Dictionary:
	var doc: Dictionary = look.duplicate(true)
	doc["look_id"] = final_id
	doc["status"] = "PRODUCTION"
	doc["revision"] = revision
	return FxLookScript.materialize(doc)

func apply(look_id_override := "") -> Dictionary:
	if mode == "SHARED_PROTECTED":
		last_errors = ["shared Look is protected — Edit Shared Look or Make Unique before applying"]
		return {"ok": false, "errors": last_errors.duplicate()}
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	# R3 §9: shared-Look protection covers EVERY entry into apply. A draft-branch
	# session whose underlying look is shared must go through Edit Shared Look or
	# Make Unique — never silently update the shared look in place.
	if mode != "EDIT_SHARED_DRAFT" and str(base.get("kind", "")) == "production":
		var keep_id := str(base.get("look_id", ""))
		if keep_id != "":
			var usage_now: Dictionary = production.usage(keep_id)
			if int(usage_now.get("count", 0)) > 1:
				last_errors = ["shared Look is protected — Edit Shared Look or Make Unique before applying"]
				return {"ok": false, "errors": last_errors.duplicate()}
	# R3 §9: if an intentionally disabled binding still covers this scope, say so
	# — applying will create an active binding that takes precedence over it.
	var disabled_notice := _disabled_binding_notice()
	if disabled_notice != "" and not last_warnings.has(disabled_notice):
		last_warnings.append(disabled_notice)
	var selector := novice_selector()
	var keep := ""
	var revision := 1
	if str(base.get("kind", "")) == "production":
		keep = str(base.get("look_id", ""))
		revision = int(base.get("revision", 1)) + 1
	var proposal := look_id_override if look_id_override != "" else (keep if keep != "" else proposed_look_id())
	var final_id := unique_look_id(proposal, keep)
	if final_id == "":
		return {"ok": false, "errors": ["cannot derive a Look ID — set one explicitly"]}

	var doc := _prepare_doc(final_id, revision)
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	FxResolverScript.upsert_binding(asg_doc, selector, final_id, "novice apply")
	var result: Dictionary = production.apply({"look": doc, "assignments": asg_doc})
	if not bool(result.get("ok", false)):
		last_errors = result.get("errors", [])
		return result

	# Success (specs/15 §10): status PRODUCTION, draft stays as clean snapshot.
	if mode == "EDIT_SHARED_DRAFT":
		drafts.clear_shared(str(base.get("look_id", "")), int(base.get("revision", 0)))
	look = doc
	last_errors = []
	dirty = false
	var usage: Dictionary = production.usage(final_id)
	base = {
		"kind": "production",
		"look_id": final_id,
		"revision": revision,
		"shared_count": int(usage.get("count", 0)),
	}
	mode = "SHARED_PROTECTED" if int(usage.get("count", 0)) > 1 else "EDIT_PRODUCTION_UNIQUE"
	_refresh_resolution()
	if str(signature) != "":
		drafts.save_target(signature, look, revision, false)
	return {"ok": true, "errors": [], "look_id": final_id, "revision": revision}

func make_unique() -> Dictionary:
	if mode != "SHARED_PROTECTED":
		return {"ok": false, "errors": ["Make Unique is only needed for shared Looks"]}
	var original_id := str(base.get("look_id", ""))
	var proposal := unique_look_id(original_id + "_UNIQUE", "")
	var selector := novice_selector()
	var doc := _prepare_doc(proposal, 1)
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	FxResolverScript.upsert_binding(asg_doc, selector, proposal, "make unique")
	var result: Dictionary = production.apply({"look": doc, "assignments": asg_doc})
	if not bool(result.get("ok", false)):
		last_errors = result.get("errors", [])
		return result
	look = doc
	base = {"kind": "production", "look_id": proposal, "revision": 1, "shared_count": 1}
	mode = "EDIT_PRODUCTION_UNIQUE"
	dirty = false
	last_errors = []
	# R3 §9 fix: a stale parked draft for this target would reopen the OLD shared
	# look on the next visit - drop it now that the target owns its unique copy.
	if str(signature) != "":
		drafts.clear_target(signature)
	_refresh_resolution()
	return {"ok": true, "errors": [], "look_id": proposal}

func _disabled_binding_notice() -> String:
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return ""
	for raw in (assignments["doc"] as Dictionary).get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), context):
				return "a disabled binding covers this scope; the applied binding takes precedence over it"
	return ""

func edit_shared() -> Dictionary:
	# Opens (or creates) the shared draft for the current shared Look revision.
	if mode != "SHARED_PROTECTED":
		return {"ok": false, "errors": ["not in shared-protected state"]}
	var look_id := str(base.get("look_id", ""))
	var revision := int(base.get("revision", 1))
	var existing: Dictionary = drafts.load_shared(look_id, revision)
	if not bool(existing.get("ok", false)):
		var saved: Dictionary = drafts.save_shared(look_id, revision, look, false)
		if not bool(saved.get("ok", false)):
			return saved
	mode = "EDIT_SHARED_DRAFT"
	return {"ok": true, "errors": []}

# ================================================================ styling on/off

func set_styling(enabled: bool) -> Dictionary:
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	var selector := novice_selector()
	if enabled:
		FxResolverScript.remove_bypass(asg_doc, selector)
	else:
		FxResolverScript.add_bypass(asg_doc, selector, "styling off")
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	styling_enabled = enabled
	_refresh_resolution()
	return {"ok": true, "errors": []}

func _refresh_resolution() -> void:
	var assignments: Dictionary = production.load_assignments()
	resolution = FxResolverScript.resolve(assignments.get("doc", {}), context) if bool(assignments.get("ok", false)) else {"status": "BROKEN", "chain": []}
	styling_enabled = str(resolution.get("status", "")) != "BYPASSED"

# ================================================================ status / why

func effective_look_id() -> String:
	return str(resolution.get("look_id", "")) if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"] else ""

func badge_text() -> String:
	var effective := str(resolution.get("status", "UNASSIGNED"))
	var suffix := " · DRAFT" if dirty else ""
	# R3 §23 fix: a resolution that merely POINTS at a look whose file is gone
	# must not display as assigned — surface the broken state truthfully.
	for entry in last_errors:
		if str(entry).begins_with("assigned look is missing or broken"):
			return "⚠ BROKEN" + suffix
	match effective:
		"BYPASSED":
			return "⦸ STYLING OFF" + suffix
		"AMBIGUOUS":
			return "⚠ AMBIGUOUS" + suffix
		"ASSIGNED":
			if int(base.get("shared_count", 0)) > 1:
				return "◆ SHARED (%d)" % int(base["shared_count"]) + suffix
			return "● ASSIGNED" + suffix
		"BROKEN":
			return "⚠ BROKEN" + suffix
	if dirty:
		return "◐ DRAFT"
	return "○ UNASSIGNED"

func status_detail() -> String:
	var lines: Array = []
	var effective := str(resolution.get("status", "UNASSIGNED"))
	if effective == "ASSIGNED" or effective == "AMBIGUOUS":
		lines.append("Effective Style: " + str(resolution.get("look_id", "")))
	else:
		lines.append("Effective Style: —")
	if int(base.get("shared_count", 0)) > 1:
		lines.append("Used by %d assignments" % int(base["shared_count"]))
	if mode == "SHARED_PROTECTED":
		lines.append("Protected: shared Look — Edit Shared Look or Make Unique to change.")
	elif mode == "EDIT_SHARED_DRAFT":
		lines.append("Editing shared draft (applies to every target using this Look).")
	return "\n".join(lines)

func why() -> Array:
	# specs/06 §10: explain the winning match in human terms.
	var lines: Array = []
	var assignments: Dictionary = production.load_assignments()
	var doc: Dictionary = assignments.get("doc", {}) if bool(assignments.get("ok", false)) else {}
	var status := str(resolution.get("status", "UNASSIGNED"))
	if status == "BYPASSED":
		var sel := str(resolution.get("selector", {}).get("element_id", ""))
		lines.append("Styling OFF — explicit bypass matches this target.")
		var byp_selector: Dictionary = resolution.get("selector", {})
		lines.append("Bypass scope: " + FxResolverScript.selector_key(byp_selector))
		var fallback := FxResolverScript.resolve(_without_bypass(doc), context)
		if str(fallback.get("status", "")) == "ASSIGNED":
			lines.append("Without the bypass: " + str(fallback.get("look_id", "")))
		return lines
	# disabled bindings that match (fallback explanation)
	for raw in doc.get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), context):
				lines.append("%s — disabled" % str((raw as Dictionary).get("look_id", "")))
	var chain: Array = resolution.get("chain", [])
	for entry in chain:
		var desc := _selector_human(str(entry.get("selector_key", "")))
		if bool(entry.get("winner", false)):
			lines.append("%s — selected (%s, score %d)" % [str(entry.get("look_id", "")), desc, int(entry.get("score", 0))])
		else:
			lines.append("%s — lower priority (%s, score %d)" % [str(entry.get("look_id", "")), desc, int(entry.get("score", 0))])
	if status == "AMBIGUOUS":
		lines.append("Ambiguous tie — resolved deterministically; fix the bindings.")
	if lines.is_empty():
		lines.append("No matching assignment — neutral design.")
	return lines

func _without_bypass(doc: Dictionary) -> Dictionary:
	var copy: Dictionary = doc.duplicate(true)
	copy["bypasses"] = []
	return copy

func _selector_human(key: String) -> String:
	if key == "":
		return "universal"
	var parts: Array = []
	for pair in key.split("&"):
		var kv := pair.split("=")
		if kv.size() == 2:
			parts.append(str(kv[1]).replace("_", " "))
	return " · ".join(parts) if not parts.is_empty() else key
