class_name FxTargets
extends RefCounted
# NRCU FX Lab vNext — presentation target registry (Stream A/B foundation).
#
# Enumerates the real render targets of a mounted VS screen and derives the
# semantic target context plus the canonical target signature defined in
# specs/15 §9 (fixed key order, empty strings for missing fields).
#
# Pure data + node inspection: no UI, no rendering, no screen mutation.

const ROLE_IDS := {
	"VS MARK": "vs_mark",
	"PRIMARIES": "primary",
	"ECHOES": "echo",
	"NAMES": "name",
	"STAGE": "stage",
	"SIDE FIELDS": "side_field",
	"NAME PLATES": "name_plate",
	"ACCENT LINES": "accent_line",
}

# Canonical target signature key order — specs/15 §9. Do not reorder.
const SIGNATURE_ORDER: Array[String] = [
	"element_id", "fighter_id", "element_role", "visual_side",
	"presentation_slot", "team_side", "mode_family", "stage_id",
]

var screen: Node
var mode_format := "1v1"
var stage_id := "debug"

var slot_nodes: Dictionary = {}
var slot_roles: Dictionary = {}

var _multiplayer_layouts: Dictionary = {}

func _init() -> void:
	_multiplayer_layouts = _load_json("res://assets/vs/schema/multiplayer_layouts_1280x720.json")

# ---------------------------------------------------------------- binding

func bind_screen(screen_node: Node, format: String, stage: String) -> void:
	screen = screen_node
	mode_format = format
	stage_id = stage
	collect()

func collect() -> void:
	slot_nodes.clear()
	slot_roles.clear()
	if screen == null or not is_instance_valid(screen):
		return
	var root := screen.get_node_or_null("Root")
	if root != null:
		_gather(root)

func keys() -> Array:
	var result: Array = slot_nodes.keys()
	result.sort()
	return result

func target_node(key: String) -> Node:
	return slot_nodes.get(key)

# ---------------------------------------------------------------- roles

func role_for_key(key: String) -> String:
	if key == "mark" or key.contains("vs_mark"):
		return "VS MARK"
	if key == "stage" or key.contains("stage"):
		return "STAGE"
	if key.contains("side_field") or key.contains("field_left") or key.contains("field_right"):
		return "SIDE FIELDS"
	if key.contains("plate"):
		return "NAME PLATES"
	if key.contains("accent"):
		return "ACCENT LINES"
	if key.contains("primary"):
		return "PRIMARIES"
	if key.contains("echo"):
		return "ECHOES"
	if key.begins_with("name") or key.contains("_name_"):
		return "NAMES"
	return "OTHER TEXTURES"

func role_id(role: String) -> String:
	return str(ROLE_IDS.get(role, role.to_snake_case()))

func fighter_id_for(node: Variant) -> String:
	if not (node is TextureRect) or node.texture == null:
		return ""
	var path := String(node.texture.resource_path)
	var parts := path.split("/")
	for i in range(parts.size() - 1):
		if parts[i] == "fighters":
			return String(parts[i + 1])
	return ""

# ---------------------------------------------------------------- semantic context

func context_for_key(key: String) -> Dictionary:
	var context := {"mode_family": mode_format, "stage_id": stage_id}
	if not slot_nodes.has(key):
		return context
	var role := str(slot_roles.get(key, "OTHER TEXTURES"))
	var node = slot_nodes[key]
	context["target_key"] = key
	context["element_role"] = role_id(role)
	var fighter_id := str(node.get_meta("fx_fighter_id", "")) if node is Node else ""
	if fighter_id == "":
		fighter_id = fighter_id_for(node)
	if fighter_id != "":
		context["fighter_id"] = fighter_id
	var presentation_slot := presentation_slot_for_key(key)
	if presentation_slot != "":
		context["presentation_slot"] = presentation_slot
		var visual_side := visual_side_for_slot(presentation_slot)
		if visual_side != "":
			context["visual_side"] = visual_side
		var team_side := team_side_for_slot(presentation_slot)
		if team_side != "":
			context["team_side"] = team_side
	if node is Node and node.has_meta("fx_visual_side"):
		context["visual_side"] = str(node.get_meta("fx_visual_side"))
	if node is Node and node.has_meta("fx_stage_id"):
		context["stage_id"] = str(node.get_meta("fx_stage_id"))
	if node is Node and node.has_meta("fx_element_id"):
		context["element_id"] = str(node.get_meta("fx_element_id"))
	elif role == "VS MARK":
		context["element_id"] = "vs_mark"
	elif role == "STAGE":
		context["element_id"] = "stage"
	return context

func signature_for_key(key: String) -> String:
	var context := context_for_key(key)
	var parts: Array = []
	for field in SIGNATURE_ORDER:
		parts.append(str(context.get(field, "")))
	return "|".join(parts)

# ---------------------------------------------------------------- slot semantics

func presentation_slot_for_key(key: String) -> String:
	# Resolve against the actual layout schema instead of assuming only duel/FFA
	# left/right names. Team families use slots such as A_back and B_solo.
	var candidates: Array[String] = ["left_outer", "right_outer", "left_inner", "right_inner", "center", "left", "right"]
	var families: Dictionary = _multiplayer_layouts.get("families", {})
	for family in families.values():
		if not (family is Dictionary):
			continue
		var slots: Dictionary = family.get("slots", {})
		for raw_slot in slots.keys():
			var slot := str(raw_slot).to_lower()
			if not candidates.has(slot):
				candidates.append(slot)
	candidates.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var normalized := key.to_lower()
	for candidate in candidates:
		if normalized == candidate or normalized.begins_with(candidate + "_") or normalized.contains("_" + candidate + "_") or normalized.ends_with("_" + candidate):
			return candidate
	return ""

func visual_side_for_slot(slot: String) -> String:
	if slot == "":
		return ""
	if slot in ["left", "right", "center"]:
		return slot
	var family_spec: Dictionary = (_multiplayer_layouts.get("families", {}) as Dictionary).get(mode_format, {})
	var slot_spec: Dictionary = (family_spec.get("slots", {}) as Dictionary).get(slot, {})
	var side := str(slot_spec.get("side", "")).to_lower()
	return side if side in ["left", "right", "center"] else ""

func team_side_for_slot(slot: String) -> String:
	if not mode_format.begins_with("TEAM_"):
		return ""
	if slot.begins_with("a_"):
		return "A"
	if slot.begins_with("b_"):
		return "B"
	return ""

# ---------------------------------------------------------------- scene-space helpers

static func raw_presentation_size(node: TextureRect, tex: Texture2D) -> Vector2:
	var local_size := node.size
	if local_size.x < 1.0 or local_size.y < 1.0:
		local_size = Vector2(tex.get_width(), tex.get_height())
	var transform := node.get_global_transform()
	var scale_x := maxf(transform.x.length(), 0.0001)
	var scale_y := maxf(transform.y.length(), 0.0001)
	return Vector2(maxf(local_size.x * scale_x, 1.0), maxf(local_size.y * scale_y, 1.0))

static func presentation_rect(node: TextureRect) -> Rect2:
	var xform := node.get_global_transform()
	var corners := [Vector2.ZERO, Vector2(node.size.x, 0.0), node.size, Vector2(0.0, node.size.y)]
	var first: Vector2 = xform * corners[0]
	var minp := first
	var maxp := first
	for i in range(1, corners.size()):
		var pnt: Vector2 = xform * corners[i]
		minp.x = minf(minp.x, pnt.x)
		minp.y = minf(minp.y, pnt.y)
		maxp.x = maxf(maxp.x, pnt.x)
		maxp.y = maxf(maxp.y, pnt.y)
	return Rect2(minp, maxp - minp)

# ---------------------------------------------------------------- internals

func _gather(node: Node) -> void:
	for child in node.get_children():
		if child is TextureRect and child.texture != null and not bool(child.get_meta("fx_overscan_proxy", false)):
			var key := String(child.name).to_snake_case()
			if key not in ["shadow", "under_shadow"] and not slot_nodes.has(key):
				slot_nodes[key] = child
				slot_roles[key] = String(child.get_meta("fx_role", role_for_key(key)))
		_gather(child)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
