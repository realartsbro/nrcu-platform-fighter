extends CanvasLayer
# NRCU VS presentation — the 2D overlay. Two paths share one lifecycle:
#
#   DUEL_1V1    the approved 1v1 presentation
#               (NRCU_VS_FINAL_IMPLEMENTATION_HANDOFF_v2_0, contract §3-§8) —
#               start(left_fighter_id, right_fighter_id, stage_id). UNCHANGED.
#   MULTIPLAYER the v1.3 follow-up (NRCU_VS_MULTIPLAYER_FOLLOWUP_HANDOFF_v1_3):
#               start_presentation(plan) renders one of the five layout
#               families (FFA_3, FFA_4, TEAM_2V2, TEAM_2V1/TEAM_1V2,
#               TEAM_3V1/TEAM_1V3) from a normalized 2-4 fighter plan.
#
# WHAT THIS IS
#   A lightweight, deterministic CanvasLayer overlay that reproduces the locked
#   target: stage plate, translucent side fields, echo layers, primary fighters,
#   the user-supplied VS mark, name plates + name textures, and the loader-safe
#   transition cover. Every number comes from the handoff's machine-readable
#   specs under res://assets/vs/schema/ (no duplicated constants here):
#     vs_layout_1280x720.json            1v1 layer geometry
#     roster_presentation.json           1v1 per-fighter canonical side + optical
#     motion_timing.json                 1v1 ENTRY/HOLD/EXIT timings
#     multiplayer_layouts_1280x720.json  the five family layouts
#     roster_optical_facing_profiles.json the orientation authority
#     multiplayer_motion_timing.json     the shared multiplayer bands
#   The assets under res://assets/vs/ are the handoff's own files, copied
#   byte-identical (verified by tests/test_vs_screen.gd and
#   tests/test_vs_multiplayer.gd against the packages' manifests).
#
# WHAT THIS IS NOT
#   * no live 3D / SubViewport: the primaries are already real-3D presentation
#     renders and are the visual authority (contract §1, §11);
#   * no runtime font for names: names are the supplied transparent name
#     textures (§7). The v1.3 P1-P4 tag is the ONE functional text and draws
#     through the engine's fallback font (the follow-up package ships no label
#     art and the label must survive the visual permutation);
#   * no grunge rays / stripes and no persistent FX behind the VS mark;
#   * no per-frame echo generation and no unbounded tween/timer creation: ENTRY
#     is ONE Tween per path, HOLD is a state flag plus an elapsed accumulator,
#     EXIT is driven by _process (contract §11, acceptance test 8).
#
# CURSOR LIFECYCLE (v1.3 contract "Cursor lifecycle")
#   While ANY VS presentation is active the frontend hand cursor is suppressed
#   by lifecycle state (not by the inactivity timeout) through the Cursor
#   service's own suspension API, and released again when the overlay tears
#   down (exit_finished) or leaves the tree. The hand can therefore never
#   render above (or through) the VS CanvasLayer.
#
# EXTERNAL CONTRACT (the narrow surface the orchestration adapter uses)
#   start(left_fighter_id, right_fighter_id, stage_id) -> bool   (DUEL_1V1)
#   start_presentation(plan) -> bool                             (families)
#   signal_match_ready()
#   signal transition_cover_reached   at full cover, once
#   signal exit_finished              after the reveal, before the overlay frees
#   plus the motion_timing event signals (vs_enter ... exit_finished).
#
# STATE MACHINE
#   idle -> entry -> hold -> exit -> done
#   ENTRY follows motion_timing.entry (1v1) / multiplayer_motion_timing.shared
#   (families, with the family's symmetric micro-stagger). HOLD is
#   cheap/static and lasts until BOTH minimum_total_exposure (>= 1.50 s) and
#   the match-readiness signal are true. EXIT is a 0.24 s center-origin cover
#   close, then a 0.16 s reveal; transition_cover_reached fires at full cover
#   and exit_finished at the end.

signal vs_enter
signal stage_reveal
signal fighter_reveal
signal fighter_lock
signal clash_impact
signal hold_enter
signal match_ready
signal vs_exit
signal transition_cover_reached
signal exit_finished

const STATE_IDLE := "idle"
const STATE_ENTRY := "entry"
const STATE_HOLD := "hold"
const STATE_EXIT := "exit"
const STATE_DONE := "done"

const RequestScript = preload("res://scripts/vs_presentation_request.gd")

# --- handoff specs (copied unmodified from the packages) --------------------
const LAYOUT_JSON := "res://assets/vs/schema/vs_layout_1280x720.json"
const ROSTER_JSON := "res://assets/vs/schema/roster_presentation.json"
const TIMING_JSON := "res://assets/vs/schema/motion_timing.json"
# The specs author asset paths relative to the package root ("assets/stages/…",
# "assets/ui/vs_mark.png"); the package's runtime tree lives under assets/vs/.
const ASSET_ROOT := "res://assets/vs/"
const ASSET_SCHEMA_PREFIX := "assets/"

# Design size of the handoff art (layout spec design_size).
const DESIGN_WIDTH := 1280.0
const DESIGN_HEIGHT := 720.0

# --- name plate geometry (v1.3) --------------------------------------------
# The multiplayer schema authors each name plate as a rect (x, y, w, h). The
# approved v1.3 reference boards render that rect as a skewed banner: the plate
# is the rect sheared to the right by PLATE_SHEAR * h over its height, with its
# top edge rising PLATE_RISE * w to the right; the accent line is the top edge
# inset by ACCENT_INSET on both ends, drawn accent_line_width wide; the name
# texture is scaled so its height is rect_h - NAME_INSET and centred.
const PLATE_SHEAR := 0.2
const PLATE_RISE := 0.01
const ACCENT_INSET := 5.0
const NAME_INSET := 22.0
const LABEL_INSET_X := 11.0
const LABEL_INSET_Y := 8.0
const LABEL_FONT_SIZE := 10

# The multiplayer timing schema authors the band TIMES; the per-layer scale and
# outside-offset treatment is the approved 1v1 layer language reused verbatim
# (contract "Assets"/"Layer language": reuse, do not invent FX).
const FAMILY_STAGE_SCALE_START := 1.025
const FAMILY_LAYER_SCALE_START := 1.035
const FAMILY_ECHO_SCALE_START := 1.03
const FAMILY_PRIMARY_OFFSET_PX := 52.0
const FAMILY_ECHO_OFFSET_PX := 48.0
const FAMILY_VS_SCALE_START := 0.72
const FAMILY_NAME_Y_OFFSET := 25.0
const FAMILY_STAGE_SCALE_END := 1.0

# Node paths inside scenes/vs_screen.tscn (layer order = layout spec
# layer_order, with the full-frame impact flash above the names and the cover
# last so nothing can ever draw over the loader cover). FamilyBack/FamilyFront
# are the v1.3 additions, placed so the multiplayer fighters sit above the
# stage/fields, the VS mark above them, and the family plates/names above the
# mark — the same relative order the 1v1 path uses.
const P_ROOT := "Root"
const P_STAGE := "Root/Stage"
const P_SIDE_FIELDS := "Root/SideFields"
const P_FIELD_LEFT := "Root/SideFields/FieldLeft"
const P_FIELD_RIGHT := "Root/SideFields/FieldRight"
const P_ECHO_LEFT := "Root/EchoLeft"
const P_ECHO_RIGHT := "Root/EchoRight"
const P_PRIMARY_LEFT := "Root/PrimaryLeft"
const P_PRIMARY_RIGHT := "Root/PrimaryRight"
const P_FAMILY_BACK := "Root/FamilyBack"
const P_FAMILY_ECHOES := "Root/FamilyBack/Echoes"
const P_FAMILY_PRIMARIES := "Root/FamilyBack/Primaries"
const P_VS_MARK := "Root/VsMark"
const P_VS_SHADOW := "Root/VsMark/UnderShadow"
const P_VS_MARK_ART := "Root/VsMark/Mark"
const P_PLATES := "Root/NamePlates"
const P_PLATE_LEFT := "Root/NamePlates/PlateLeft"
const P_PLATE_RIGHT := "Root/NamePlates/PlateRight"
const P_ACCENT_LEFT := "Root/NamePlates/AccentLeft"
const P_ACCENT_RIGHT := "Root/NamePlates/AccentRight"
const P_NAME_LEFT := "Root/NameLeft"
const P_NAME_RIGHT := "Root/NameRight"
const P_FAMILY_FRONT := "Root/FamilyFront"
const P_FAMILY_PLATES := "Root/FamilyFront/Plates"
const P_FAMILY_NAMES := "Root/FamilyFront/Names"
const P_FAMILY_LABELS := "Root/FamilyFront/Labels"
const P_FLASH := "Root/ImpactFlash"
const P_COVER := "Root/TransitionCover"
const P_COVER_LEFT := "Root/TransitionCover/CoverLeft"
const P_COVER_RIGHT := "Root/TransitionCover/CoverRight"

# The duel cache hides these when the multiplayer path renders instead.
const DUEL_LAYER_PATHS := [P_SIDE_FIELDS, P_ECHO_LEFT, P_ECHO_RIGHT, P_PRIMARY_LEFT,
	P_PRIMARY_RIGHT, P_PLATES, P_NAME_LEFT, P_NAME_RIGHT]

var _layout: Dictionary = {}
var _roster: Dictionary = {}
var _timing: Dictionary = {}

# v1.3 family path state.
var _family_mode := false
var _family := ""
var _plan: Dictionary = {}
var _family_layout: Dictionary = {}
var _family_timing: Dictionary = {}
var _placements: Array = []
var _family_nodes: Array = []
var _stagger_offsets: Array = []

var _state := STATE_IDLE
var _started := false
var _elapsed := 0.0
var _exit_started_at := 0.0
var _cover_closed := false
var _match_ready := false
var _left_id := ""
var _right_id := ""
var _stage_id := ""
var _warnings: Array = []
var _entry_events: Array = []
var _emitted_events: Dictionary = {}
var _entry_tween: Tween = null
var _tween_count := 0
var _lab_preview_paused := false
var _timer_count := 0
var _entry_snapshot: Dictionary = {}
var _cursor_suppressed := false

# --- spec reads -------------------------------------------------------------

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func layout_spec() -> Dictionary:
	return read_json(LAYOUT_JSON)


static func roster_spec() -> Dictionary:
	return read_json(ROSTER_JSON)


static func timing_spec() -> Dictionary:
	return read_json(TIMING_JSON)


static func asset_path(schema_path: String) -> String:
	# "assets/stages/debug.png" -> "res://assets/vs/stages/debug.png"
	var relative := str(schema_path)
	if relative.begins_with(ASSET_SCHEMA_PREFIX):
		relative = relative.substr(ASSET_SCHEMA_PREFIX.length())
	return ASSET_ROOT + relative


static func roster_entry(fighter_id: String) -> Dictionary:
	var roster := roster_spec()
	var entry = roster.get(fighter_id, {})
	return entry if entry is Dictionary else {}


static func supports_fighter(fighter_id: String) -> bool:
	# A fighter is supported when the presentation roster records a display name
	# and its three textures exist.
	var entry := roster_entry(fighter_id)
	if entry.is_empty():
		return false
	for key in ["primary_asset", "echo_asset", "name_asset"]:
		if str(entry.get(key, "")) == "":
			return false
		if not ResourceLoader.exists(asset_path(str(entry[key]))):
			return false
	return true


# RT-03 lifecycle root cause: processing used to be toggled by raw
# set_process() calls scattered across _ready/start/pause/resume/seek/
# finish. When mount+start ran while the screen was still outside the tree
# and _ready fired later on first tree entry, _ready's set_process(false)
# silently killed an already-started clock with no error. All transitions
# now go through one authority derived from started/paused/finished state.
func _sync_process() -> void:
	set_process(_started and not _lab_preview_paused and _state != STATE_DONE and _state != STATE_IDLE)

# --- reads used by tests / evidence tooling ---------------------------------

func _ready() -> void:
	# The overlay is inert until start(): no per-frame work while idle.
	_sync_process()

func state() -> String:
	return _state

func elapsed() -> float:
	return _elapsed

func warnings() -> Array:
	return _warnings.duplicate()

func tween_count() -> int:
	return _tween_count

func timer_count() -> int:
	return _timer_count

func active_tween_count() -> int:
	if _entry_tween != null and _entry_tween.is_valid() and _entry_tween.is_running():
		return 1
	return 0

func match_ready_signalled() -> bool:
	return _match_ready

func cover_closed() -> bool:
	return _cover_closed

func minimum_exposure() -> float:
	return float(_timing.get("minimum_total_exposure", 1.5))

func hold_start_time() -> float:
	if _family_mode:
		return RequestScript.hold_start()
	return float((_timing.get("entry", {}) as Dictionary).get("hold_start", 0.93))

func cover_close_duration() -> float:
	if _family_mode:
		return float((_family_timing.get("exit", {}) as Dictionary).get("cover_close_duration", 0.24))
	return float((_timing.get("exit", {}) as Dictionary).get("cover_close_duration", 0.24))

func reveal_duration() -> float:
	if _family_mode:
		return float((_family_timing.get("exit", {}) as Dictionary).get("reveal_duration", 0.16))
	return float((_timing.get("exit", {}) as Dictionary).get("reveal_duration", 0.16))

func layer_rects() -> Dictionary:
	return _layer_rects()

func mode() -> String:
	return "multiplayer" if _family_mode else "duel"

func route_id() -> String:
	return str(_plan.get("route", RequestScript.ROUTE_DUEL)) if _family_mode else RequestScript.ROUTE_DUEL

func family() -> String:
	return _family

func plan() -> Dictionary:
	return _plan.duplicate(true)

func placements() -> Array:
	return _placements.duplicate(true)

func cursor_suppressed() -> bool:
	return _cursor_suppressed

# --- FX Lab deterministic transport API -----------------------------------
# These methods are authoring-only helpers. Gameplay never calls them. They
# let the FX Lab pause the real VS composition, seek ENTRY in either direction
# by rebuilding the single entry tween from its authored start state, and then
# resume from that exact point. This is intentionally separate from gameplay
# orchestration; the presentation contract remains unchanged when these methods
# are unused.
func lab_preview_pause() -> void:
	_lab_preview_paused = true
	_sync_process()
	if _entry_tween != null and is_instance_valid(_entry_tween):
		_entry_tween.pause()

func lab_preview_resume() -> void:
	_lab_preview_paused = false
	if _entry_tween != null and is_instance_valid(_entry_tween):
		_entry_tween.play()
	_sync_process()

func lab_preview_is_paused() -> bool:
	return _lab_preview_paused

func lab_preview_seek(seconds: float) -> bool:
	if _state == STATE_IDLE:
		return false
	# Preview resurrection: a DONE screen (exit finished, no teardown under
	# fx_preview_no_teardown) must still scrub — the phase reconstruction
	# below picks the frame matching t (TM-05).
	var t := maxf(seconds, 0.0)
	visible = true
	_match_ready = false
	_cover_closed = false
	_apply_cover(0.0)
	# Absolute reconstruction starts from canonical visibility as well as
	# canonical geometry. DONE/reveal may have left the root fully faded; an
	# EXIT-close seek must not inherit that prior presentation state.
	_restore_root_opaque()
	# Rebuild ENTRY from canonical authored start values. This makes backwards
	# scrubbing deterministic instead of trying to reverse an already-consumed
	# one-way Tween.
	if _entry_tween != null and is_instance_valid(_entry_tween):
		_entry_tween.kill()
		_entry_tween = null
	if _family_mode:
		_apply_family_entry_start()
		_start_family_entry_tween()
	else:
		_apply_entry_start()
		_start_entry_tween()
	if _entry_tween != null and is_instance_valid(_entry_tween):
		_entry_tween.pause()
		if t > 0.0:
			_entry_tween.custom_step(t)
		if _entry_tween != null and is_instance_valid(_entry_tween):
			_entry_tween.pause()
	_elapsed = t
	# TM-05: seeks reconstruct the phase matching t — including EXIT — so
	# scrubbing into loadout shows the deterministic EXIT frame instead of
	# silently rebuilding ENTRY and dropping match-ready.
	if t >= minimum_exposure():
		_state = STATE_EXIT
		_match_ready = true
		_exit_started_at = minimum_exposure()
		_step_exit()
	elif t >= hold_start_time():
		_state = STATE_HOLD
		_restore_root_opaque()
	else:
		_state = STATE_ENTRY
		_restore_root_opaque()
	# TM-06: a seek reconstructs the frame for t but never changes the
	# user's play/pause choice — editing or scrubbing during playback must
	# not park the preview behind the user's back. A seek back from DONE also
	# resurrects the processing authority when the user was playing.
	if _state != STATE_DONE:
		_started = true
	_sync_process()
	return true

# --- start (DUEL_1V1, approved path) ----------------------------------------

func start(left_fighter_id: String, right_fighter_id: String, stage_id: String) -> bool:
	# Build the whole composition ONCE and begin ENTRY. Returns false (with a
	# recorded warning) for an unsupported fighter: the caller must then use the
	# existing immediate match-start path (contract §10).
	if _state != STATE_IDLE:
		return false
	_layout = layout_spec()
	_roster = roster_spec()
	_timing = timing_spec()
	if _layout.is_empty() or _roster.is_empty() or _timing.is_empty():
		_warn("vs specs missing")
		return false
	for id in [left_fighter_id, right_fighter_id]:
		if not supports_fighter(id):
			_warn("unsupported fighter: " + str(id))
			return false
	_left_id = str(left_fighter_id)
	_right_id = str(right_fighter_id)
	_stage_id = _resolve_stage(stage_id)
	_build_sides()
	_build_stage()
	_build_side_fields()
	_build_nameplates()
	_build_vs_mark()
	_build_cover()
	_apply_entry_start()
	_start_entry_tween()
	_emitted_events.clear()
	_entry_events = _entry_event_schedule()
	_state = STATE_ENTRY
	_elapsed = 0.0
	_started = true
	_sync_process()
	_suppress_cursor(true)
	_emit("vs_enter")
	return true

# --- start (multiplayer families, v1.3) ----------------------------------------

func start_presentation(presentation_plan: Dictionary) -> bool:
	# Render a normalized 2-4 fighter plan (scripts/vs_presentation_request.gd).
	# A two-fighter plan routes through the approved duel renderer so DUEL_1V1
	# output stays visually and temporally identical.
	if _state != STATE_IDLE:
		return false
	var plan_data: Dictionary = presentation_plan
	if not bool(plan_data.get("ok", false)):
		_warn("unsupported presentation plan: " + str(plan_data.get("reason", "")))
		return false
	var fighters: Array = plan_data.get("fighters", [])
	if fighters.size() == 2:
		return start(str(fighters[0]["fighter_id"]), str(fighters[1]["fighter_id"]), str(plan_data.get("stage_id", "")))
	if fighters.size() < 3 or fighters.size() > 4:
		_warn("unsupported active fighter count: %d" % fighters.size())
		return false
	_layout = layout_spec()
	_roster = roster_spec()
	_timing = timing_spec()
	_family_layout = RequestScript.layout_spec()
	_family_timing = RequestScript.timing_spec()
	if _layout.is_empty() or _roster.is_empty() or _timing.is_empty() \
			or _family_layout.is_empty() or _family_timing.is_empty():
		_warn("vs specs missing")
		return false
	_family = str(plan_data.get("family", ""))
	if not RequestScript.has_family(_family):
		_warn("unknown presentation family: " + _family)
		return false
	var placements: Array = plan_data.get("placements", [])
	if placements.is_empty():
		_warn("empty presentation placement list")
		return false
	for placement in placements:
		var rec: Dictionary = placement.get("record", {})
		if not supports_fighter(str(rec.get("fighter_id", ""))) or not RequestScript.supports_fighter(str(rec.get("fighter_id", ""))):
			_warn("unsupported fighter: " + str(rec.get("fighter_id", "")))
			return false
	_plan = plan_data
	_placements = placements
	_family_mode = true
	_stage_id = _resolve_stage(str(plan_data.get("stage_id", "")))
	_build_family()
	_build_stage()
	_build_cover()
	_apply_family_entry_start()
	_start_family_entry_tween()
	_emitted_events.clear()
	_entry_events = _family_event_schedule()
	_state = STATE_ENTRY
	_elapsed = 0.0
	_started = true
	_sync_process()
	_suppress_cursor(true)
	_emit("vs_enter")
	return true

func _warn(message: String) -> void:
	_warnings.append(message)
	push_warning("vs_screen: " + message)

func _resolve_stage(stage_id: String) -> String:
	# Unknown stage -> the spec's unknown_fallback (debug), with a warning, and
	# never blocking the match start (contract §5, acceptance test 7).
	var stage_spec: Dictionary = _layout.get("stage", {})
	var assets: Dictionary = stage_spec.get("assets", {})
	var requested := str(stage_id)
	if assets.has(requested) and ResourceLoader.exists(asset_path(str(assets[requested]))):
		return requested
	var fallback := str(stage_spec.get("unknown_fallback", "debug"))
	if requested != "" and requested != fallback:
		_warn("unknown stage '%s' -> '%s' fallback" % [requested, fallback])
	return fallback

# --- composition (1v1) ------------------------------------------------------

func _build_stage() -> void:
	var stage := get_node_or_null(P_STAGE) as TextureRect
	if stage == null:
		_warn("stage node missing")
		return
	var assets: Dictionary = (_layout.get("stage", {}) as Dictionary).get("assets", {})
	stage.texture = load(asset_path(str(assets.get(_stage_id, "")))) as Texture2D
	stage.position = Vector2.ZERO
	stage.size = Vector2(DESIGN_WIDTH, DESIGN_HEIGHT)

func _build_sides() -> void:
	_place_fighter("left", _left_id, P_ECHO_LEFT, P_PRIMARY_LEFT)
	_place_fighter("right", _right_id, P_ECHO_RIGHT, P_PRIMARY_RIGHT)
	var name_y := float((_layout.get("nameplates", {}) as Dictionary).get("name_y", 561))
	var left_x := float((_layout.get("nameplates", {}) as Dictionary).get("left_name_x", 23))
	var right_margin := float((_layout.get("nameplates", {}) as Dictionary).get("right_name_margin", 23))
	_place_name("left", _left_id, P_NAME_LEFT, left_x, name_y)
	_place_name("right", _right_id, P_NAME_RIGHT, DESIGN_WIDTH - right_margin, name_y)

func _place_fighter(side: String, fighter_id: String, echo_path: String, primary_path: String) -> void:
	var entry := roster_entry(fighter_id)
	var canonical := str(entry.get("canonical_side", "left"))
	# Contract §4: a config is authored for canonical_side. On the opposite side
	# the texture is mirrored horizontally and
	#   mirrored_x = 1280 - canonical_x - rendered_width
	# with Y and the target size unchanged.
	var mirrored := canonical != side
	for pair in [[echo_path, entry.get("echo", {}), "echo"], [primary_path, entry.get("primary", {}), "primary"]]:
		var node := get_node_or_null(str(pair[0])) as TextureRect
		if node == null:
			continue
		var spec: Dictionary = pair[1]
		var schema_asset := str(entry.get(str(pair[2]) + "_asset", ""))
		var tex := load(asset_path(schema_asset)) as Texture2D
		if tex == null:
			_warn("missing %s texture for %s" % [str(pair[2]), fighter_id])
			continue
		var fitted := _fit(spec, tex)
		var size: Vector2 = fitted["size"]
		var x := float(fitted["x"])
		if mirrored:
			x = DESIGN_WIDTH - x - size.x
		node.texture = tex
		node.flip_h = mirrored
		node.position = Vector2(x, float(fitted["y"]))
		node.size = size
		node.pivot_offset = size * 0.5
		node.modulate = Color(1, 1, 1, 1.0 if str(pair[2]) == "primary" else float(spec.get("opacity", 1.0)))

func _place_name(side: String, fighter_id: String, node_path: String, margin_x: float, y: float) -> void:
	var node := get_node_or_null(node_path) as TextureRect
	if node == null:
		return
	var entry := roster_entry(fighter_id)
	var tex := load(asset_path(str(entry.get("name_asset", "")))) as Texture2D
	if tex == null:
		_warn("missing name texture for " + fighter_id)
		return
	# The spec authors the name y (top edge) and, per side, the left offset or
	# the right margin: the right name texture is right-aligned inside it.
	var left := margin_x
	if side == "right":
		left = margin_x - float(tex.get_width())
	node.texture = tex
	node.position = Vector2(left, y)
	node.size = Vector2(tex.get_width(), tex.get_height())

func _fit(spec: Dictionary, tex: Texture2D) -> Dictionary:
	# Target size comes from the spec: "height" for the human fighters, "width"
	# for the non-human (GGB) entry. The rendered width/height keep the source
	# aspect exactly (both are derived from the same scale factor).
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var scale := 1.0
	if spec.has("height"):
		scale = float(spec["height"]) / th
	elif spec.has("width"):
		scale = float(spec["width"]) / tw
	var size := Vector2(round(tw * scale), round(th * scale))
	return {"size": size, "x": float(spec.get("x", 0.0)), "y": float(spec.get("y", 0.0)), "scale": scale}

func _build_side_fields() -> void:
	var spec: Dictionary = _layout.get("side_fields", {})
	var alpha := float(spec.get("alpha", 31)) / 255.0
	_set_field(P_FIELD_LEFT, spec.get("left_points", []), _accent(_left_id, alpha))
	_set_field(P_FIELD_RIGHT, spec.get("right_points", []), _accent(_right_id, alpha))

func _set_field(node_path: String, points: Array, color: Color) -> void:
	var poly := get_node_or_null(node_path) as Polygon2D
	if poly == null:
		return
	var packed := PackedVector2Array()
	for point in points:
		packed.append(Vector2(float(point[0]), float(point[1])))
	poly.polygon = packed
	poly.color = color

func _accent(fighter_id: String, alpha: float) -> Color:
	var rgb: Array = roster_entry(fighter_id).get("accent_rgb", [255, 255, 255])
	return Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0, alpha)

func _echo_opacity(fighter_id: String) -> float:
	return float((roster_entry(fighter_id).get("echo", {}) as Dictionary).get("opacity", 1.0))

func _build_nameplates() -> void:
	var spec: Dictionary = _layout.get("nameplates", {})
	var fill: Array = spec.get("fill_rgba", [2, 4, 5, 245])
	var fill_color := Color(float(fill[0]) / 255.0, float(fill[1]) / 255.0, float(fill[2]) / 255.0, float(fill[3]) / 255.0)
	_set_field(P_PLATE_LEFT, spec.get("left_points", []), fill_color)
	_set_field(P_PLATE_RIGHT, spec.get("right_points", []), fill_color)
	var width := float(spec.get("accent_line_width", 3))
	_set_line(P_ACCENT_LEFT, spec.get("left_accent_line", []), width, _accent(_left_id, 1.0))
	_set_line(P_ACCENT_RIGHT, spec.get("right_accent_line", []), width, _accent(_right_id, 1.0))

func _set_line(node_path: String, points: Array, width: float, color: Color) -> void:
	var line := get_node_or_null(node_path) as Line2D
	if line == null:
		return
	var packed := PackedVector2Array()
	for point in points:
		packed.append(Vector2(float(point[0]), float(point[1])))
	line.points = packed
	line.width = width
	line.default_color = color
	line.antialiased = false

func _build_vs_mark() -> void:
	# Contract §6: assets/ui/vs_mark.png exactly, centered X, fixed target height
	# and Y, a tiny black under-shadow. The mark is never redrawn or combined
	# with any other geometry.
	var spec: Dictionary = _layout.get("vs_mark", {})
	_place_vs_mark(float(spec.get("height", 224)), float(spec.get("y", 0.0)), spec)

func _place_vs_mark(height: float, y: float, spec: Dictionary) -> void:
	var holder := get_node_or_null(P_VS_MARK) as Control
	var art := get_node_or_null(P_VS_MARK_ART) as TextureRect
	var shadow := get_node_or_null(P_VS_SHADOW) as TextureRect
	if holder == null or art == null or shadow == null:
		_warn("vs mark nodes missing")
		return
	var tex := load(asset_path(str(spec.get("asset", "")))) as Texture2D
	if tex == null:
		_warn("vs mark texture missing")
		return
	var scale := height / float(tex.get_height())
	var size := Vector2(round(float(tex.get_width()) * scale), round(height))
	var center_x := float(spec.get("center_x", DESIGN_WIDTH * 0.5))
	# Centered X, pixel-snapped: the scaled mark is 211 px wide, so an exact
	# centre on a 1280 px canvas lands on a half pixel. The reference board's own
	# best-fit placement is the integer 534 (measured by sub-pixel registration),
	# so the left edge is floored instead of leaving the mark on a half-pixel
	# grid (which would resample the whole badge through a half-texel offset).
	holder.position = Vector2(floorf(center_x - size.x * 0.5), y)
	holder.size = size
	holder.pivot_offset = size * 0.5
	for node in [art, shadow]:
		node.texture = tex
		node.size = size
		node.position = Vector2.ZERO
	var offset: Array = spec.get("shadow_offset", [3, 4])
	shadow.position = Vector2(float(offset[0]), float(offset[1]))
	shadow.modulate = Color(0, 0, 0, float(spec.get("shadow_alpha", 0.66)))
	var mat := shadow.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("dilate_px", float(spec.get("shadow_dilate_px", 3)))
		mat.set_shader_parameter("mark_size", size)

func _build_cover() -> void:
	# motion_timing.exit.cover_shape: two black center-origin wedges. Each wedge
	# is authored in centre-relative coordinates and grows outward from the
	# centre seam when the node's X scale is animated; the alpha ramps with the
	# same progress, so full cover is reached exactly at cover_close_duration.
	var half_w := DESIGN_WIDTH * 0.5
	var half_h := DESIGN_HEIGHT * 0.5
	var left_points := PackedVector2Array([
		Vector2(-half_w, -half_h), Vector2(0.0, -half_h), Vector2(0.0, half_h), Vector2(-half_w, half_h)])
	var right_points := PackedVector2Array([
		Vector2(0.0, -half_h), Vector2(half_w, -half_h), Vector2(half_w, half_h), Vector2(0.0, half_h)])
	for entry in [[P_COVER_LEFT, left_points], [P_COVER_RIGHT, right_points]]:
		var poly := get_node_or_null(str(entry[0])) as Polygon2D
		if poly == null:
			continue
		poly.polygon = entry[1]
		poly.position = Vector2(half_w, half_h)
		poly.color = Color(0, 0, 0, 0)
		poly.scale = Vector2(0.0, 1.0)

# --- composition (multiplayer families) -------------------------------------

func _hide_duel_layers() -> void:
	for path in DUEL_LAYER_PATHS:
		var node := get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = false

func _clear_family_layers() -> void:
	# Node-level reset only: `_placements` / `_stagger_offsets` are the plan
	# state start_presentation owns and assigns BEFORE _build_family() runs.
	# Clearing them here would empty the very loop this build iterates.
	for path in [P_FAMILY_ECHOES, P_FAMILY_PRIMARIES, P_FAMILY_PLATES, P_FAMILY_NAMES, P_FAMILY_LABELS]:
		var container := get_node_or_null(path)
		if container == null:
			continue
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_family_nodes.clear()

static func fit_in_rect(rect: Array, size: Vector2) -> Dictionary:
	# Family placement rule (v1.3): the asset is fitted INSIDE the slot rect
	# (the smaller of the two axis scales), its aspect kept, and centred in the
	# rect on both axes. Every family rect measures this way against the
	# supplied reference boards.
	var rw := float(rect[2])
	var rh := float(rect[3])
	var aw := maxf(float(size.x), 1.0)
	var ah := maxf(float(size.y), 1.0)
	var scale := minf(rw / aw, rh / ah)
	var fitted := Vector2(round(aw * scale), round(ah * scale))
	return {
		"size": fitted,
		"x": floorf(float(rect[0]) + (rw - fitted.x) * 0.5),
		"y": floorf(float(rect[1]) + (rh - fitted.y) * 0.5),
		"scale": scale,
	}

static func plate_points(rect: Array) -> PackedVector2Array:
	var x := float(rect[0])
	var y := float(rect[1])
	var w := float(rect[2])
	var h := float(rect[3])
	var rise := PLATE_RISE * w
	var shear := PLATE_SHEAR * h
	return PackedVector2Array([
		Vector2(x, y + rise),
		Vector2(x + w - shear, y),
		Vector2(x + w, y + h - rise),
		Vector2(x + shear, y + h),
	])

static func accent_points(rect: Array) -> PackedVector2Array:
	var points := plate_points(rect)
	var a := points[0]
	var b := points[1]
	var direction := (b - a).normalized()
	return PackedVector2Array([a + direction * ACCENT_INSET, b - direction * ACCENT_INSET])

func _build_family() -> void:
	_hide_duel_layers()
	_clear_family_layers()
	var family_spec: Dictionary = (_family_layout.get("families", {}) as Dictionary).get(_family, {})
	var echo_alpha := float(family_spec.get("echo_opacity", 0.15))
	var labels: Array = []
	for placement in _placements:
		var rec: Dictionary = placement["record"]
		var geometry: Dictionary = placement.get("geometry", {})
		var fighter_id := str(rec["fighter_id"])
		var mirror_asset := bool(placement.get("mirror_asset", false))
		var entry := roster_entry(fighter_id)
		var z := int(placement.get("z", 0))
		for layer in ["echo", "primary"]:
			var rect: Array = geometry.get(layer, [])
			if rect.size() != 4:
				continue
			var tex := load(asset_path(str(entry.get(layer + "_asset", "")))) as Texture2D
			if tex == null:
				_warn("missing %s texture for %s" % [layer, fighter_id])
				continue
			var node := TextureRect.new()
			node.name = "%s_%s_%s" % [str(placement.get("slot", "")), layer, str(rec.get("slot_id", ""))]
			node.texture = tex
			node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			node.flip_h = mirror_asset
			var fitted := fit_in_rect(rect, Vector2(tex.get_width(), tex.get_height()))
			node.size = fitted["size"]
			node.position = Vector2(fitted["x"], fitted["y"])
			node.pivot_offset = node.size * 0.5
			node.z_index = z
			node.modulate = Color(1, 1, 1, 1.0 if layer == "primary" else echo_alpha)
			var parent_path := P_FAMILY_ECHOES if layer == "echo" else P_FAMILY_PRIMARIES
			get_node_or_null(parent_path).add_child(node)
			_family_nodes.append({"layer": layer, "slot": str(placement.get("slot", "")), "node": node})
		# Name plate, accent line, name texture, P-label.
		var name_rect: Array = geometry.get("name", [])
		if name_rect.size() == 4:
			var plate := Polygon2D.new()
			plate.name = "Plate_" + str(placement.get("slot", ""))
			plate.polygon = plate_points(name_rect)
			var fill: Array = ((_layout.get("nameplates", {}) as Dictionary).get("fill_rgba", [2, 4, 5, 245]) as Array)
			plate.color = Color(float(fill[0]) / 255.0, float(fill[1]) / 255.0, float(fill[2]) / 255.0, float(fill[3]) / 255.0)
			plate.z_index = 40
			get_node_or_null(P_FAMILY_PLATES).add_child(plate)
			_family_nodes.append({"layer": "plate", "slot": str(placement.get("slot", "")), "node": plate})
			var accent := Line2D.new()
			accent.name = "Accent_" + str(placement.get("slot", ""))
			accent.points = accent_points(name_rect)
			accent.width = float((_layout.get("nameplates", {}) as Dictionary).get("accent_line_width", 3))
			accent.antialiased = false
			accent.default_color = _accent(fighter_id, 1.0)
			accent.z_index = 41
			get_node_or_null(P_FAMILY_PLATES).add_child(accent)
			_family_nodes.append({"layer": "accent", "slot": str(placement.get("slot", "")), "node": accent})
			var name_tex := load(asset_path(str(entry.get("name_asset", "")))) as Texture2D
			if name_tex != null:
				var name_node := TextureRect.new()
				name_node.name = "Name_" + str(placement.get("slot", ""))
				name_node.texture = name_tex
				name_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				name_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
				name_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				# name texture height = rect_h - NAME_INSET, centred in the rect.
				var target_h := maxf(float(name_rect[3]) - NAME_INSET, 1.0)
				var name_scale := target_h / float(name_tex.get_height())
				var name_size := Vector2(round(float(name_tex.get_width()) * name_scale), round(target_h))
				name_node.size = name_size
				name_node.position = Vector2(
					floorf(float(name_rect[0]) + (float(name_rect[2]) - name_size.x) * 0.5),
					floorf(float(name_rect[1]) + (float(name_rect[3]) - name_size.y) * 0.5))
				name_node.z_index = 42
				get_node_or_null(P_FAMILY_NAMES).add_child(name_node)
				_family_nodes.append({"layer": "name", "slot": str(placement.get("slot", "")), "node": name_node})
			var label := _make_label(str(placement.get("label", "")), _label_text(placement), name_rect)
			get_node_or_null(P_FAMILY_LABELS).add_child(label)
			_family_nodes.append({"layer": "label", "slot": str(placement.get("slot", "")), "node": label})
	# The mark is the shared node: the family schema supplies height + y only.
	var vs_spec: Dictionary = family_spec.get("vs", {})
	var mark_spec := (_layout.get("vs_mark", {}) as Dictionary).duplicate()
	_place_vs_mark(float(vs_spec.get("height", mark_spec.get("height", 224))), float(vs_spec.get("y", 0.0)), mark_spec)

func _label_text(placement: Dictionary) -> String:
	# The player label survives the visual permutation: it is the fighter
	# record's own slot_id, plus the team tag in a team family (the v1.3
	# reference boards render "P3 - TEAM A" style tags).
	var rec: Dictionary = placement.get("record", {})
	var text := str(rec.get("slot_id", ""))
	if _family.begins_with("TEAM_"):
		var team_id := int(rec.get("team_id", RequestScript.TEAM_A))
		text += " - TEAM " + ("A" if team_id == RequestScript.TEAM_A else "B")
	return text

func _make_label(placement_name: String, text: String, name_rect: Array) -> Control:
	var label := Control.new()
	label.name = "Label_" + placement_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(float(name_rect[0]) + LABEL_INSET_X, float(name_rect[1]) + LABEL_INSET_Y)
	label.size = Vector2(maxf(float(name_rect[2]) - LABEL_INSET_X * 2.0, 1.0), 16.0)
	label.z_index = 43
	label.set_meta("text", text)
	label.draw.connect(func() -> void:
		var font := label.get_theme_default_font()
		if font == null:
			return
		label.draw_string(font, Vector2(0.0, float(LABEL_FONT_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.86, 0.88, 0.90, 0.92))
		)
	return label

func _family_tween_node(node_path: String, layer: String, fighter_id: String) -> Node:
	for entry in _family_nodes:
		if entry["slot"] == node_path and entry["layer"] == layer:
			return entry["node"]
	return null

# --- ENTRY (1v1) ------------------------------------------------------------

func _entry_start_values() -> Dictionary:
	var entry: Dictionary = _timing.get("entry", {})
	var vs: Dictionary = entry.get("vs", {})
	var names: Dictionary = entry.get("names", {})
	var names_offset: Array = names.get("y_offset", [25, 0])
	return {
		"stage_scale": float((entry.get("stage", {}) as Dictionary).get("scale", [1.025, 1.0])[0]),
		"echo_scale": float((entry.get("echoes", {}) as Dictionary).get("scale", [1.03, 1.0])[0]),
		"echo_offset": float((entry.get("echoes", {}) as Dictionary).get("outside_offset_px", 48)),
		"primary_scale": float((entry.get("primaries", {}) as Dictionary).get("scale", [1.035, 1.0])[0]),
		"primary_offset": float((entry.get("primaries", {}) as Dictionary).get("outside_offset_px", 52)),
		"vs_scale": float(vs.get("scale", [0.72, 1.0])[0]),
		"name_offset": float(names_offset[0]),
	}

func _apply_entry_start() -> void:
	var start := _entry_start_values()
	_set_layer_alpha(P_STAGE, 0.0)
	_set_layer_alpha(P_ECHO_LEFT, 0.0)
	_set_layer_alpha(P_ECHO_RIGHT, 0.0)
	_set_layer_alpha(P_PRIMARY_LEFT, 0.0)
	_set_layer_alpha(P_PRIMARY_RIGHT, 0.0)
	_set_layer_alpha(P_VS_MARK, 0.0)
	_set_layer_alpha(P_NAME_LEFT, 0.0)
	_set_layer_alpha(P_NAME_RIGHT, 0.0)
	_set_layer_alpha(P_FLASH, 0.0)
	var stage := get_node_or_null(P_STAGE) as Control
	if stage != null:
		stage.scale = Vector2.ONE * float(start["stage_scale"])
	var vs := get_node_or_null(P_VS_MARK) as Control
	if vs != null:
		vs.scale = Vector2.ONE * float(start["vs_scale"])
	for pair in [[P_ECHO_LEFT, "echo_offset", "echo_scale", -1.0], [P_ECHO_RIGHT, "echo_offset", "echo_scale", 1.0],
			[P_PRIMARY_LEFT, "primary_offset", "primary_scale", -1.0], [P_PRIMARY_RIGHT, "primary_offset", "primary_scale", 1.0]]:
		var node := get_node_or_null(str(pair[0])) as Control
		if node == null:
			continue
		node.scale = Vector2.ONE * float(start[str(pair[2])])
		if not node.has_meta("base_x"):
			node.set_meta("base_x", node.position.x)
		var canonical_x := float(node.get_meta("base_x", node.position.x))
		node.position.x = canonical_x + float(start[str(pair[1])]) * float(pair[3])
	for node_path in [P_NAME_LEFT, P_NAME_RIGHT]:
		var name_node := get_node_or_null(node_path) as Control
		if name_node != null:
			if not name_node.has_meta("base_y"):
				name_node.set_meta("base_y", name_node.position.y)
			var canonical_y := float(name_node.get_meta("base_y", name_node.position.y))
			name_node.position.y = canonical_y + float(start["name_offset"])

func _start_entry_tween() -> void:
	# ONE Tween object for the whole ENTRY (contract §11: no unbounded tween or
	# timer creation). Every layer runs in parallel with its authored delay.
	var entry: Dictionary = _timing.get("entry", {})
	var stage: Dictionary = entry.get("stage", {})
	var echoes: Dictionary = entry.get("echoes", {})
	var primaries: Dictionary = entry.get("primaries", {})
	var vs: Dictionary = entry.get("vs", {})
	var names: Dictionary = entry.get("names", {})
	var tw := create_tween()
	tw.set_parallel(true)
	_tween_count += 1
	_entry_tween = tw
	var stage_scale := float(stage.get("scale", [1.025, 1.0])[1])
	tw.tween_property(get_node(P_STAGE), "modulate:a", 1.0, float(stage.get("end", 0.22)) - float(stage.get("start", 0.0))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(get_node(P_STAGE), "scale", Vector2.ONE * stage_scale, float(stage.get("end", 0.22)) - float(stage.get("start", 0.0))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for pair in [[P_ECHO_LEFT, -1.0], [P_ECHO_RIGHT, 1.0]]:
		# The layer fades in from 0 to ITS OWN authored opacity (the echo's is
		# the roster's echo.opacity, never 1.0).
		var echo_id := _left_id if str(pair[0]) == P_ECHO_LEFT else _right_id
		_tween_fighter(tw, str(pair[0]), echoes, float(pair[1]), _echo_opacity(echo_id))
	for pair in [[P_PRIMARY_LEFT, -1.0], [P_PRIMARY_RIGHT, 1.0]]:
		_tween_fighter(tw, str(pair[0]), primaries, float(pair[1]), 1.0)
	var vs_duration := float(vs.get("end", 0.72)) - float(vs.get("start", 0.58))
	tw.tween_property(get_node(P_VS_MARK), "modulate:a", 1.0, vs_duration).set_delay(float(vs.get("start", 0.58))).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(get_node(P_VS_MARK), "scale", Vector2.ONE, vs_duration).set_delay(float(vs.get("start", 0.58))).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween_impact_flash(tw, vs.get("impact_flash", {}))
	var name_duration := float(names.get("end", 0.93)) - float(names.get("start", 0.7))
	for node_path in [P_NAME_LEFT, P_NAME_RIGHT]:
		var node := get_node(node_path) as Control
		var base_y := float(node.get_meta("base_y", node.position.y))
		tw.tween_property(node, "modulate:a", 1.0, name_duration).set_delay(float(names.get("start", 0.7))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "position:y", base_y, name_duration).set_delay(float(names.get("start", 0.7))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(_on_entry_tween_finished)

func _tween_fighter(tw: Tween, node_path: String, spec: Dictionary, outward: float, target_alpha: float) -> void:
	var node := get_node_or_null(node_path) as Control
	if node == null:
		return
	var start := float(spec.get("start", 0.18))
	var duration := float(spec.get("end", 0.5)) - start
	var offset := float(spec.get("outside_offset_px", 0))
	var target_scale := float(spec.get("scale", [1.0, 1.0])[1])
	var base_x := float(node.get_meta("base_x", node.position.x))
	tw.tween_property(node, "modulate:a", target_alpha, duration).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position:x", base_x, duration).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE * target_scale, duration).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _tween_impact_flash(tw: Tween, flash: Dictionary) -> void:
	if flash.is_empty():
		return
	var rect := get_node_or_null(P_FLASH) as ColorRect
	if rect == null:
		return
	var peak: Array = flash.get("rgba_peak", [255, 244, 198, 32])
	var half_width := float(flash.get("half_width", 0.02))
	var center := float(flash.get("center_time", 0.615))
	var color := Color(float(peak[0]) / 255.0, float(peak[1]) / 255.0, float(peak[2]) / 255.0, 0.0)
	rect.color = color
	var rise := maxf(half_width, 0.001)
	tw.tween_property(rect, "color:a", float(peak[3]) / 255.0, rise).set_delay(center - half_width).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tw.tween_property(rect, "color:a", 0.0, rise).set_delay(center).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)

func _on_entry_tween_finished() -> void:
	_entry_tween = null

func authorable_motion_event_marks() -> Dictionary:
	# Single event authority: the SAME schedule _process() actually emits
	# (_entry_events built at start, plus the hold epoch). Timestamps are
	# never reconstructed a second time from JSON anywhere else.
	# Empty before start(): no schedule, no marks, no silent fallback.
	if _entry_events.is_empty():
		return {}
	var marks := {"vs_enter": 0.0}
	for ev_raw in _entry_events:
		var ev: Dictionary = ev_raw
		var nm := str(ev.get("name", ""))
		if nm != "vs_enter" and nm in FxScreenRuntime.AUTHORABLE_MOTION_EVENTS:
			marks[nm] = float(ev.get("t", 0.0))
	marks["hold_enter"] = hold_start_time()
	return marks

func _entry_event_schedule() -> Array:
	var entry: Dictionary = _timing.get("entry", {})
	var events: Array = [
		{"t": 0.0, "name": "stage_reveal"},
		{"t": float((entry.get("primaries", {}) as Dictionary).get("start", 0.18)), "name": "fighter_reveal"},
		{"t": float((entry.get("primaries", {}) as Dictionary).get("end", 0.5)), "name": "fighter_lock"},
		{"t": float((entry.get("vs", {}) as Dictionary).get("impact_flash", {}).get("center_time", 0.615)), "name": "clash_impact"},
	]
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return events

# --- ENTRY (multiplayer families) -------------------------------------------

func _family_scale_pair(name: String, fallback: Array) -> Array:
	var entry: Dictionary = _family_timing.get("shared", {})
	var band: Array = entry.get(name, fallback)
	return band if band.size() == 2 else fallback

func _family_band(name: String) -> Array:
	return RequestScript.band(name)

func _family_stagger_offsets() -> Array:
	# "symmetrical around base start; maximum added span <= 0.06s; never
	# serialize all fighters": every fighter's echo + primary band is shifted by
	# its own offset, in visual order.
	var step := RequestScript.stagger_for(_family)
	return RequestScript.stagger_offsets(_placements.size(), step)

func _apply_family_entry_start() -> void:
	_set_layer_alpha(P_STAGE, 0.0)
	_set_layer_alpha(P_VS_MARK, 0.0)
	_set_layer_alpha(P_FLASH, 0.0)
	var stage := get_node_or_null(P_STAGE) as Control
	if stage != null:
		stage.scale = Vector2.ONE * FAMILY_STAGE_SCALE_START
	var vs := get_node_or_null(P_VS_MARK) as Control
	if vs != null:
		vs.scale = Vector2.ONE * FAMILY_VS_SCALE_START
	_stagger_offsets = _family_stagger_offsets()
	for entry in _family_nodes:
		var node := entry["node"] as Control
		var layer := str(entry["layer"])
		if layer == "echo" or layer == "primary":
			# Outside offset: the fighters slide in from the frame edge nearest
			# their slot (left slots from the left, right slots from the right),
			# exactly like the 1v1 layers do.
			var placement := _placement_for_slot(str(entry["slot"]))
			var side := str(placement.get("side", "left"))
			var outward := -1.0 if side == "left" else 1.0
			if side == "center":
				outward = 0.0
			var offset := FAMILY_PRIMARY_OFFSET_PX
			if layer == "echo":
				offset = FAMILY_ECHO_OFFSET_PX
			node.scale = Vector2.ONE * (FAMILY_ECHO_SCALE_START if layer == "echo" else FAMILY_LAYER_SCALE_START)
			if not node.has_meta("base_position"):
				node.set_meta("base_position", node.position)
				node.set_meta("base_x", node.position.x)
				node.set_meta("target_alpha", node.modulate.a)
			var canonical_position: Vector2 = node.get_meta("base_position", node.position)
			node.position = canonical_position
			node.position.x = canonical_position.x + offset * outward
			node.modulate.a = 0.0
		elif layer == "name":
			node.modulate.a = 0.0
			if not node.has_meta("base_position"):
				node.set_meta("base_position", node.position)
			var canonical_name_position: Vector2 = node.get_meta("base_position", node.position)
			node.position = canonical_name_position
			node.position.y = canonical_name_position.y + FAMILY_NAME_Y_OFFSET
		elif layer == "label":
			node.modulate.a = 0.0

func _placement_for_slot(slot: String) -> Dictionary:
	for placement in _placements:
		if str(placement.get("slot", "")) == slot:
			return placement
	return {}

func _start_family_entry_tween() -> void:
	# ONE Tween for the whole family ENTRY (the same contract as the 1v1 path).
	var stage_band := _family_band("stage")
	var echo_band := _family_band("echoes")
	var primary_band := _family_band("primaries")
	var vs_band := _family_band("vs")
	var name_band := _family_band("names")
	var shared: Dictionary = _family_timing.get("shared", {})
	var stage_scale := FAMILY_STAGE_SCALE_END
	var tw := create_tween()
	tw.set_parallel(true)
	_tween_count += 1
	_entry_tween = tw
	var stage_start := float(stage_band[0])
	var stage_end := float(stage_band[1])
	var stage_node := get_node_or_null(P_STAGE)
	if stage_node != null:
		tw.tween_property(stage_node, "modulate:a", 1.0, maxf(stage_end - stage_start, 0.001)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(stage_node, "scale", Vector2.ONE * stage_scale, maxf(stage_end - stage_start, 0.001)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in _family_nodes.size():
		var entry: Dictionary = _family_nodes[i]
		var node := entry["node"] as Control
		var layer := str(entry["layer"])
		var slot := str(entry["slot"])
		var offset := _stagger_for_slot(slot)
		if layer == "echo" or layer == "primary":
			var band := echo_band if layer == "echo" else primary_band
			var start := float(band[0]) + offset
			var end := float(band[1]) + offset
			var duration := maxf(end - start, 0.001)
			var base_position: Vector2 = node.get_meta("base_position", node.position)
			var target_alpha := float(node.get_meta("target_alpha", 1.0))
			tw.tween_property(node, "modulate:a", target_alpha, duration).set_delay(maxf(start, 0.0)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "position:x", base_position.x, duration).set_delay(maxf(start, 0.0)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "scale", Vector2.ONE, duration).set_delay(maxf(start, 0.0)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		elif layer == "name":
			var start := float(name_band[0])
			var duration := maxf(float(name_band[1]) - start, 0.001)
			var base_position: Vector2 = node.get_meta("base_position", node.position)
			tw.tween_property(node, "modulate:a", 1.0, duration).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "position:y", base_position.y, duration).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		elif layer == "label":
			tw.tween_property(node, "modulate:a", 1.0, 0.12).set_delay(float(name_band[0])).set_trans(Tween.TRANS_LINEAR)
	var vs_start := float(vs_band[0])
	var vs_duration := maxf(float(vs_band[1]) - vs_start, 0.001)
	var mark := get_node_or_null(P_VS_MARK)
	if mark != null:
		tw.tween_property(mark, "modulate:a", 1.0, vs_duration).set_delay(vs_start).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(mark, "scale", Vector2.ONE, vs_duration).set_delay(vs_start).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The 1v1 impact flash spec, re-used for the family. Explicit Dictionary
	# typing: the chained Variant .get() cannot be inferred by `:=`.
	var flash: Dictionary = ((_timing.get("entry", {}) as Dictionary).get("vs", {}) as Dictionary).get("impact_flash", {})
	var family_flash: Dictionary = flash.duplicate()
	family_flash["center_time"] = (vs_start + float(vs_band[1])) * 0.5
	_tween_impact_flash(tw, family_flash)
	tw.finished.connect(_on_entry_tween_finished)

func _stagger_for_slot(slot: String) -> float:
	for i in _placements.size():
		if str(_placements[i].get("slot", "")) == slot:
			if i < _stagger_offsets.size():
				return float(_stagger_offsets[i])
			return 0.0
	return 0.0

func _family_event_schedule() -> Array:
	var primary_band := _family_band("primaries")
	var vs_band := _family_band("vs")
	var offsets := _family_stagger_offsets()
	var min_offset := 0.0
	var max_offset := 0.0
	for offset in offsets:
		min_offset = minf(min_offset, float(offset))
		max_offset = maxf(max_offset, float(offset))
	var events: Array = [
		{"t": 0.0, "name": "stage_reveal"},
		{"t": float(primary_band[0]) + min_offset, "name": "fighter_reveal"},
		{"t": float(primary_band[1]) + max_offset, "name": "fighter_lock"},
		{"t": (float(vs_band[0]) + float(vs_band[1])) * 0.5, "name": "clash_impact"},
	]
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return events

# --- cursor lifecycle -------------------------------------------------------

func _suppress_cursor(suppressed: bool) -> void:
	# v1.3 contract "Cursor lifecycle": the frontend hand cursor is suppressed
	# for the ENTIRE overlay lifetime through the Cursor service's own
	# suspension API (lifecycle state, never the inactivity timeout) and
	# released again at exit_finished / when this overlay leaves the tree.
	var cursor: Node = null
	if is_inside_tree():
		cursor = get_node_or_null("/root/Cursor")
	if cursor != null and cursor.has_method("set_overlay_suppressed"):
		cursor.set_overlay_suppressed(suppressed)
		_cursor_suppressed = suppressed

func _release_cursor() -> void:
	if _cursor_suppressed:
		_suppress_cursor(false)

func _exit_tree() -> void:
	# A freed overlay can never leave the cursor suspended behind it.
	_release_cursor()

# --- state machine ----------------------------------------------------------

func _process(delta: float) -> void:
	match _state:
		STATE_ENTRY:
			_elapsed += delta
			for event in _entry_events:
				if _elapsed >= float(event["t"]):
					_emit(str(event["name"]))
			if _elapsed >= hold_start_time():
				_enter_hold()
		STATE_HOLD:
			# Cheap and static: no tween, no timer, no per-frame echo work. The
			# only cost is this accumulator and the readiness check.
			_elapsed += delta
			if _match_ready and _elapsed >= minimum_exposure():
				_begin_exit()
		STATE_EXIT:
			_elapsed += delta
			_step_exit()

func _emit(name: String) -> void:
	if _emitted_events.has(name):
		return
	_emitted_events[name] = _elapsed
	# Duplicate event list of motion_timing.events, emitted once each.
	emit_signal(name)

func emitted_at(name: String) -> float:
	return float(_emitted_events.get(name, -1.0))

func emitted_events() -> Array:
	var names: Array = _emitted_events.keys()
	names.sort()
	return names

func _restore_root_opaque() -> void:
	# The EXIT fade drives Root modulate to 0; scrubbing back to ENTRY/HOLD
	# must un-fade or the resurrected composition stays invisible forever.
	var root := get_node_or_null(P_ROOT) as Control
	if root != null:
		root.modulate.a = 1.0

func _enter_hold() -> void:
	_state = STATE_HOLD
	_entry_snapshot = _static_state()
	_emit("hold_enter")

func signal_match_ready() -> void:
	# The orchestration adapter's readiness handoff: the match may start.
	# Match-ready before the minimum exposure is remembered, never acted on
	# (acceptance test 9); after it, EXIT begins on the next orchestration step
	# (`_process` in HOLD checks the same condition, so a readiness that lands
	# while ENTRY is still running still exits at exactly the minimum exposure).
	_match_ready = true
	_emit("match_ready")
	if _state == STATE_HOLD and _elapsed >= minimum_exposure():
		_begin_exit()

func _begin_exit() -> void:
	if _state != STATE_HOLD:
		return
	_state = STATE_EXIT
	_exit_started_at = _elapsed
	_cover_closed = false
	_emit("vs_exit")

func _step_exit() -> void:
	var close := cover_close_duration()
	var reveal := reveal_duration()
	var t := _elapsed - _exit_started_at
	if not _cover_closed:
		var progress := clampf(t / maxf(close, 0.0001), 0.0, 1.0)
		_apply_cover(progress)
		if progress >= 1.0:
			_cover_closed = true
			# Emitted exactly at full cover: the gameplay reveal and the existing
			# Ready/Go start hang off this signal, and the overlay is still up
			# and still fully covering the frame (acceptance test 11).
			_emit("transition_cover_reached")
	# Direct preview seeks may cross both cover close and reveal in one call;
	# continue into the reveal phase instead of returning at full cover.
	if _cover_closed:
		var q := clampf((t - close) / maxf(reveal, 0.0001), 0.0, 1.0)
		var root := get_node_or_null(P_ROOT) as Control
		if root != null:
			root.modulate.a = 1.0 - _ease_out_quad(q)
		if q >= 1.0:
			_finish()

func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

func _apply_cover(progress: float) -> void:
	for node_path in [P_COVER_LEFT, P_COVER_RIGHT]:
		var poly := get_node_or_null(node_path) as Polygon2D
		if poly == null:
			continue
		poly.scale = Vector2(progress, 1.0)
		poly.color = Color(0, 0, 0, progress)

func _finish() -> void:
	if _state == STATE_DONE:
		return
	_state = STATE_DONE
	_started = false
	_sync_process()
	var preview_owned := bool(get_meta("fx_preview_no_teardown", false))
	# Preview-owned screens remain visible on the deterministic EXIT frame. The
	# game lifecycle keeps the legacy hidden-before-signal behavior.
	if not preview_owned:
		visible = false
	# Teardown releases the cursor: ordinary frontend cursor behavior resumes
	# (the frontend scope decides whether the hand is drawn again).
	_release_cursor()
	_emit("exit_finished")
	# Preview-owned screens (lab + reference runtime) freeze on the
	# deterministic EXIT frame instead of self-teardown: scrubbing past
	# minimum_exposure must never free the composition out from under the
	# shared renderer (fail-closed lifetime belongs to the consumer).
	# The game path never sets this meta and keeps exact legacy behavior.
	if preview_owned:
		return
	queue_free()

# --- helpers ----------------------------------------------------------------

func _set_layer_alpha(node_path: String, alpha: float) -> void:
	var node := get_node_or_null(node_path) as CanvasItem
	if node == null:
		return
	var color := node.modulate
	node.modulate = Color(color.r, color.g, color.b, alpha)

func _layer_rects() -> Dictionary:
	var out: Dictionary = {}
	for where in [["echo_left", P_ECHO_LEFT], ["echo_right", P_ECHO_RIGHT], ["primary_left", P_PRIMARY_LEFT],
			["primary_right", P_PRIMARY_RIGHT], ["name_left", P_NAME_LEFT], ["name_right", P_NAME_RIGHT],
			["vs_mark", P_VS_MARK]]:
		var node := get_node_or_null(str(where[1])) as Control
		if node == null:
			continue
		out[str(where[0])] = {
			"x": node.position.x,
			"y": node.position.y,
			"w": node.size.x,
			"h": node.size.y,
			"mirrored": node is TextureRect and (node as TextureRect).flip_h,
		}
	return out

func family_rects() -> Dictionary:
	# Per-slot geometry of the multiplayer composition (tests / evidence):
	# slot -> {primary: {...}, echo: {...}, name: {...}, label: text}.
	var out: Dictionary = {}
	for entry in _family_nodes:
		var slot := str(entry["slot"])
		var layer := str(entry["layer"])
		if not out.has(slot):
			out[slot] = {}
		var node: Variant = entry["node"]
		var record: Dictionary = out[slot]
		if node is Control:
			var control := node as Control
			record[layer] = {
				"x": control.position.x,
				"y": control.position.y,
				"w": control.size.x,
				"h": control.size.y,
				"mirrored": control is TextureRect and (control as TextureRect).flip_h,
			}
		elif node is Polygon2D:
			record[layer] = {"points": (node as Polygon2D).polygon}
		elif node is Line2D:
			record[layer] = {"points": (node as Line2D).points, "color": (node as Line2D).default_color}
	return out

func label_texts() -> Dictionary:
	var out: Dictionary = {}
	for entry in _family_nodes:
		if str(entry["layer"]) != "label":
			continue
		out[str(entry["slot"])] = str((entry["node"] as Control).get_meta("text", ""))
	return out

func mark_rect() -> Dictionary:
	var holder := get_node_or_null(P_VS_MARK) as Control
	if holder == null:
		return {}
	return {"x": holder.position.x, "y": holder.position.y, "w": holder.size.x, "h": holder.size.y}

func _static_state() -> Dictionary:
	# Everything that must not change while HOLD is active (acceptance test 8:
	# HOLD survives >= 10 s without advancing or accumulating).
	var out: Dictionary = {"layers": {}, "state": _state, "elapsed": _elapsed}
	for where in [P_STAGE, P_ECHO_LEFT, P_ECHO_RIGHT, P_PRIMARY_LEFT, P_PRIMARY_RIGHT, P_VS_MARK, P_NAME_LEFT, P_NAME_RIGHT, P_FLASH]:
		var node := get_node_or_null(where) as Control
		if node == null:
			continue
		out["layers"][where] = {
			"position": [node.position.x, node.position.y],
			"scale": [node.scale.x, node.scale.y],
			"alpha": node.modulate.a,
		}
	for entry in _family_nodes:
		var node := entry["node"] as CanvasItem
		if node == null:
			continue
		out["layers"]["%s:%s" % [str(entry["slot"]), str(entry["layer"])]] = {
			"position": [node.position.x, node.position.y] if node is Control else [0.0, 0.0],
			"scale": [node.scale.x, node.scale.y] if node is Node2D else [1.0, 1.0],
			"alpha": node.modulate.a,
		}
	return out

func static_state() -> Dictionary:
	return _static_state()

func entry_state_snapshot() -> Dictionary:
	return _entry_snapshot.duplicate(true)

func node_ref(path: String) -> Node:
	return get_node_or_null(path)
