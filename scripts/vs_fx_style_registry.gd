extends RefCounted
## NRCU VS FX production-style resolver.
##
## This file deliberately owns *selection/resolution*, not rendering. The FX Lab
## publishes reusable Looks separately from semantic Bindings. Game integration
## may ask this registry which Look wins for one presentation element without
## duplicating the specificity rules or inferring meaning from filenames/P1/P2.

const LOOKS_PATH := "res://assets/vs/fx/fx_looks.json"
const ASSIGNMENTS_PATH := "res://assets/vs/fx/fx_assignments.json"
const LOOKS_SCHEMA := "NRCU_VS_FX_LOOKS_V1"
const ASSIGNMENTS_SCHEMA := "NRCU_VS_FX_ASSIGNMENTS_V1"

# Larger weights are deliberately spaced so a semantically stronger identity
# dominates a combination of weaker layout qualifiers.
const SELECTOR_WEIGHTS := {
    "element_id": 100,
    "fighter_id": 50,
    "element_role": 20,
    "presentation_slot": 12,
    "visual_side": 8,
    "team_side": 6,
    "mode_family": 5,
    "stage_id": 5
}

static func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed if parsed is Dictionary else {}

static func selector_matches(selector: Dictionary, context: Dictionary) -> bool:
    for key in selector.keys():
        if not context.has(key) or str(context[key]) != str(selector[key]):
            return false
    return true

static func selector_score(selector: Dictionary) -> int:
    var score := 0
    for key in selector.keys():
        score += int(SELECTOR_WEIGHTS.get(key, 1))
    return score

static func resolve_binding(assignments_doc: Dictionary, context: Dictionary) -> Dictionary:
    var best: Dictionary = {}
    var best_score := -1
    var best_index := -1
    var bindings = assignments_doc.get("bindings", [])
    if not (bindings is Array):
        return best
    for i in range(bindings.size()):
        var item = bindings[i]
        if not (item is Dictionary):
            continue
        var selector: Dictionary = item.get("selector", {})
        if not selector_matches(selector, context):
            continue
        var score := selector_score(selector)
        # Equal specificity is deterministic: later entries win. Publishing a
        # replacement normally keeps selectors unique, but this prevents an
        # ambiguous hand-edited file from depending on hash/dictionary order.
        if score > best_score or (score == best_score and i > best_index):
            best = item
            best_score = score
            best_index = i
    return best

static func resolve_project_binding(context: Dictionary) -> Dictionary:
    var doc := _read_json(ASSIGNMENTS_PATH)
    if str(doc.get("schema", "")) != ASSIGNMENTS_SCHEMA:
        return {}
    return resolve_binding(doc, context)

static func production_look(look_id: String) -> Dictionary:
    if look_id == "":
        return {}
    var doc := _read_json(LOOKS_PATH)
    if str(doc.get("schema", "")) != LOOKS_SCHEMA:
        return {}
    var looks = doc.get("looks", {})
    if not (looks is Dictionary):
        return {}
    var look = looks.get(look_id, {})
    return look if look is Dictionary else {}

static func resolve_project_look(context: Dictionary) -> Dictionary:
    var binding := resolve_project_binding(context)
    var look_id := str(binding.get("look_id", ""))
    if look_id == "":
        return {}
    return {
        "binding": binding,
        "look_id": look_id,
        "look": production_look(look_id)
    }
