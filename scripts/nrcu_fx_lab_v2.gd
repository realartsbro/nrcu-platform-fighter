extends Node2D
# NRCU LOOK DEVELOPMENT LAB v0.3 — authoring / spatial parity development build
# Real VS screen + explicit semantic targeting + independent quantisation domains.

const LOOK_SCHEMA := "NRCU_FX_LOOK_V0_3"
const LEGACY_LOOK_SCHEMAS := ["NRCU_FX_LOOK_V0_2"]
const PRESET_PATH := "user://nrcu_fx_looks_v02.cfg"
const EXPORT_DIR := "user://fx_look_exports"
const CAPTURE_DIR := "user://fx_lab_captures"
const PRODUCTION_FX_DIR := "res://assets/vs/fx"
const PRODUCTION_LOOKS_PATH := "res://assets/vs/fx/fx_looks.json"
const PRODUCTION_ASSIGNMENTS_PATH := "res://assets/vs/fx/fx_assignments.json"
const PRODUCTION_LOOKS_SCHEMA := "NRCU_VS_FX_LOOKS_V1"
const PRODUCTION_ASSIGNMENTS_SCHEMA := "NRCU_VS_FX_ASSIGNMENTS_V1"
const ASSIGNMENT_SCOPES := ["EXACT ELEMENT", "FIGHTER + ROLE + VISUAL SIDE", "FIGHTER + ROLE", "ROLE + VISUAL SIDE", "ROLE ONLY", "STATIC ELEMENT"]
const VSRequest := preload("res://scripts/vs_presentation_request.gd")
const StyleRegistry := preload("res://scripts/vs_fx_style_registry.gd")

const FX_NAMES := ["dither", "fringe", "flow", "rgb"]
const TARGET_MODES := ["SELECTED", "ROLE", "ALL"]
const TARGET_ROLES := ["VS MARK", "PRIMARIES", "ECHOES", "NAMES", "STAGE", "SIDE FIELDS", "NAME PLATES", "ACCENT LINES", "OTHER TEXTURES"]
# Look-level FX time source (Gate B): PRESENTATION TIME follows the live VS
# timeline (deterministic against the presentation clock); FREE RUN uses the
# accumulated lab clock (evaluation / element study).
const TIME_SOURCES := ["PRESENTATION TIME", "FREE RUN"]
const FORMAT_NAMES := ["1v1", "FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1", "TEAM_3V1"]
const STAGE_IDS := ["debug", "toy_room", "sky"]
const ANCHORS := ["manual", "vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]
const DITHER_PATTERNS := ["HARD LEVELS", "BAYER", "CLUSTERED NOISE", "RANDOM", "CHECKER", "HALFTONE"]
const PATTERN_SPACES := ["SOURCE", "ELEMENT", "SCREEN"]
const FRINGE_COVERAGE := ["SMOOTH", "BAYER", "CLUSTERED NOISE", "RANDOM", "CHECKER", "HALFTONE"]
const EDGE_SOURCES := ["ALPHA SILHOUETTE", "LUMA DETAIL", "ALPHA + LUMA", "CUSTOM EDGE MASK"]
const BLEND_MODES := ["NORMAL", "ADDITIVE", "SCREEN"]
const GEOMETRY_UNITS := ["SOURCE PX", "PRESENTATION PX"]
const PALETTE_STRATEGIES := ["DOMINANT PAIR", "DOMINANT + COMPLEMENT", "SPLIT COMPLEMENTARY", "ANALOGOUS", "TRIADIC", "MONOCHROME"]
const DEBUG_VIEWS := ["COMPOSITE", "BASE ONLY", "EFFECT ONLY", "EDGE SOURCE", "FRINGE COVERAGE", "TREATMENT MASK", "DRIVER FIELD"]
const STUDY_BACKGROUNDS := ["DARK", "LIGHT", "NEUTRAL", "CHECKER"]
const PREVIEW_FOCUS_MODES := ["NORMAL", "DIM OTHERS", "SOLO TARGET"]
const STUDY_ZOOM_MIN := 0.10
const STUDY_ZOOM_MAX := 8.0
const DRIVER_NAMES := [
    "TRAVELLING WHISP", "LEGACY FBM", "VORONOI", "PHASOR", "ISOLINES", "SPIRAL",
    "CURL SMOKE", "WAVEFRONT", "CELLULAR WIND", "RIDGE FLOW", "SOURCE WARP",
    "DATAMOSH RIVER", "MAGNETIC FIELD", "LIQUID SCANNER"
]

# Authoring parameter metadata. Factory values live in `state`; this schema is the
# single UI authority for slider ergonomics, numeric-entry freedom, units and
# section ownership. Creative numeric fields may exceed their slider range; only
# intrinsically bounded quantities (opacity, masks, normalized weights) stay hard
# bounded.
const PARAM_SCHEMA := {
    "fx_size": {"slider_min":0.25,"slider_max":4.0,"step":0.05,"bounded":false,"section":"MASTER","unit":"x"},
    "fx_intensity": {"slider_min":0.0,"slider_max":4.0,"step":0.05,"bounded":false,"section":"MASTER","unit":"x"},
    "pattern_scale": {"slider_min":0.25,"slider_max":4.0,"step":0.05,"bounded":false,"section":"MASTER","unit":"x"},
    "edge_width": {"slider_min":0.5,"slider_max":12.0,"step":0.25,"bounded":false,"section":"MASTER","unit":"px"},
    "base_opacity": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"BASE","unit":""},
    "base_grade_amount": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":false,"section":"BASE","unit":"x"},
    "grade_saturation": {"slider_min":0.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"BASE","unit":"x"},
    "grade_black_point": {"slider_min":0.0,"slider_max":0.99,"step":0.01,"bounded":true,"section":"BASE","unit":""},
    "grade_white_point": {"slider_min":0.01,"slider_max":1.0,"step":0.01,"bounded":true,"section":"BASE","unit":""},
    "grade_gamma": {"slider_min":0.1,"slider_max":4.0,"step":0.01,"bounded":false,"section":"BASE","unit":"x"},
    "grade_contrast": {"slider_min":0.0,"slider_max":4.0,"step":0.01,"bounded":false,"section":"BASE","unit":"x"},
    "grade_brightness": {"slider_min":-1.0,"slider_max":1.0,"step":0.01,"bounded":false,"section":"BASE","unit":""},
    "source_pixel_size": {"slider_min":0.0,"slider_max":16.0,"step":0.5,"bounded":false,"section":"BASE","unit":"px"},
    "mono_threshold": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"BASE","unit":""},
    "mono_pixel": {"slider_min":1.0,"slider_max":12.0,"step":0.25,"bounded":false,"section":"BASE","unit":"px"},
    "mono_bayer_level": {"slider_min":1.0,"slider_max":5.0,"step":1.0,"bounded":true,"section":"BASE","unit":""},

    "dither_levels": {"slider_min":2.0,"slider_max":24.0,"step":1.0,"bounded":false,"section":"DITHER","unit":""},
    "dither_pixel": {"slider_min":1.0,"slider_max":12.0,"step":0.25,"bounded":false,"section":"DITHER","unit":"px"},
    "dither_bayer_level": {"slider_min":1.0,"slider_max":5.0,"step":1.0,"bounded":true,"section":"DITHER","unit":""},
    "dither_threshold": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"DITHER","unit":""},
    "dither_black_point": {"slider_min":0.0,"slider_max":0.99,"step":0.01,"bounded":true,"section":"DITHER","unit":""},
    "dither_white_point": {"slider_min":0.01,"slider_max":1.0,"step":0.01,"bounded":true,"section":"DITHER","unit":""},
    "dither_gamma": {"slider_min":0.1,"slider_max":4.0,"step":0.01,"bounded":false,"section":"DITHER","unit":"x"},
    "dither_contrast": {"slider_min":0.0,"slider_max":4.0,"step":0.01,"bounded":false,"section":"DITHER","unit":"x"},
    "dither_brightness": {"slider_min":-1.0,"slider_max":1.0,"step":0.01,"bounded":false,"section":"DITHER","unit":""},

    "palette_hue_offset": {"slider_min":-180.0,"slider_max":180.0,"step":1.0,"bounded":false,"section":"FRINGE","unit":"deg"},
    "palette_saturation": {"slider_min":0.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FRINGE","unit":"x"},
    "palette_value": {"slider_min":0.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FRINGE","unit":"x"},
    "wind_reach": {"slider_min":0.0,"slider_max":96.0,"step":1.0,"bounded":false,"section":"FRINGE","unit":"px"},
    "wind_trail": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":false,"section":"FRINGE","unit":"x"},
    "split_separation": {"slider_min":0.0,"slider_max":32.0,"step":0.25,"bounded":false,"section":"FRINGE","unit":"px"},
    "fringe_pixel": {"slider_min":1.0,"slider_max":12.0,"step":0.25,"bounded":false,"section":"FRINGE","unit":"px"},
    "fringe_bayer_level": {"slider_min":1.0,"slider_max":5.0,"step":1.0,"bounded":true,"section":"FRINGE","unit":""},
    "effect_mask_threshold": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FRINGE","unit":""},
    "effect_mask_softness": {"slider_min":0.001,"slider_max":0.5,"step":0.005,"bounded":true,"section":"FRINGE","unit":""},
    "edge_alpha_weight": {"slider_min":0.0,"slider_max":3.0,"step":0.05,"bounded":false,"section":"FRINGE","unit":"x"},
    "edge_luma_weight": {"slider_min":0.0,"slider_max":3.0,"step":0.05,"bounded":false,"section":"FRINGE","unit":"x"},
    "edge_threshold": {"slider_min":0.005,"slider_max":0.5,"step":0.005,"bounded":true,"section":"FRINGE","unit":""},
    "wind_cutoff": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FRINGE","unit":""},
    "signal_gain": {"slider_min":0.0,"slider_max":3.0,"step":0.01,"bounded":false,"section":"FRINGE","unit":"x"},
    "signal_softness": {"slider_min":0.001,"slider_max":0.35,"step":0.005,"bounded":false,"section":"FRINGE","unit":""},
    "signal_posterize": {"slider_min":0.0,"slider_max":16.0,"step":1.0,"bounded":false,"section":"FRINGE","unit":"levels"},
    "color_blur": {"slider_min":0.0,"slider_max":200.0,"step":1.0,"bounded":false,"section":"FRINGE","unit":"px"},
    "fringe_coverage_threshold": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FRINGE","unit":""},
    "fringe_coverage_gain": {"slider_min":0.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FRINGE","unit":"x"},
    "fringe_bleed": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FRINGE","unit":""},
    "rgb_gradient": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FRINGE","unit":""},
    "rgb_gradient_balance": {"slider_min":-1.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FRINGE","unit":""},
    "rgb_gradient_contrast": {"slider_min":0.1,"slider_max":3.0,"step":0.01,"bounded":false,"section":"FRINGE","unit":"x"},

    "flow_strength": {"slider_min":0.0,"slider_max":48.0,"step":0.25,"bounded":false,"section":"FLOW","unit":"px"},
    "driver_pixel_size": {"slider_min":1.0,"slider_max":16.0,"step":0.25,"bounded":false,"section":"FLOW","unit":"px"},
    "temporal_hold": {"slider_min":0.0,"slider_max":60.0,"step":1.0,"bounded":false,"section":"FLOW","unit":"fps"},
    "FIELD_STRENGTH": {"slider_min":0.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "FIELD_SPEED": {"slider_min":0.0,"slider_max":3.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "OUTWARDNESS": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FLOW","unit":""},
    "FIELD_BREAKUP": {"slider_min":0.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "COORD_NUDGE": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "FIELD_SIZE": {"slider_min":0.1,"slider_max":4.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "FIELD_CENTER_X": {"slider_min":-2.0,"slider_max":5.0,"step":0.01,"bounded":false,"section":"FLOW","unit":""},
    "FIELD_CENTER_Y": {"slider_min":-2.0,"slider_max":5.0,"step":0.01,"bounded":false,"section":"FLOW","unit":""},
    "wind_displace": {"slider_min":0.0,"slider_max":3.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "flow_center_x": {"slider_min":-1.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FLOW","unit":""},
    "flow_center_y": {"slider_min":-1.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FLOW","unit":""},
    "LEGACY_SCALE": {"slider_min":0.1,"slider_max":20.0,"step":0.05,"bounded":false,"section":"FLOW","unit":"x"},
    "LEGACY_SPEED": {"slider_min":0.0,"slider_max":3.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "LEGACY_RADIAL": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FLOW","unit":""},
    "DRIVER_CENTER_X": {"slider_min":-2.0,"slider_max":5.0,"step":0.01,"bounded":false,"section":"FLOW","unit":""},
    "DRIVER_CENTER_Y": {"slider_min":-2.0,"slider_max":5.0,"step":0.01,"bounded":false,"section":"FLOW","unit":""},
    "DRIVER_SCALE": {"slider_min":0.05,"slider_max":8.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "DRIVER_STRETCH": {"slider_min":-2.0,"slider_max":2.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "DRIVER_ANGLE": {"slider_min":-3.1416,"slider_max":3.1416,"step":0.01,"bounded":false,"section":"FLOW","unit":"rad"},
    "DRIVER_SPEED": {"slider_min":0.0,"slider_max":5.0,"step":0.01,"bounded":false,"section":"FLOW","unit":"x"},
    "DRIVER_DETAIL": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FLOW","unit":""},
    "DRIVER_FLOW": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"FLOW","unit":""},

    "rgb_shift_amount": {"slider_min":0.0,"slider_max":40.0,"step":0.25,"bounded":false,"section":"RGB","unit":"px"},
    "rgb_shift_angle": {"slider_min":-180.0,"slider_max":180.0,"step":1.0,"bounded":false,"section":"RGB","unit":"deg"},
    "rgb_shift_alpha": {"slider_min":0.0,"slider_max":1.0,"step":0.01,"bounded":true,"section":"RGB","unit":""}
}

const SECTION_KEYS := {
    "MASTER": ["fx_size","fx_intensity","pattern_scale","edge_width"],
    "BASE": ["base_opacity","base_grade_amount","grade_saturation","grade_black_point","grade_white_point","grade_gamma","grade_contrast","grade_brightness","source_pixel_size","source_pixel_units","base_mode","mono_threshold","mono_mode","mono_bayer_level","mono_pixel","mono_space"],
    "DITHER": ["fx_on:dither","fx_amount:dither","dither_levels","dither_pixel","dither_mode","dither_space","dither_bayer_level","dither_threshold","dither_black_point","dither_white_point","dither_gamma","dither_contrast","dither_brightness"],
    "FRINGE": ["fx_on:fringe","fx_amount:fringe","col_a","col_b","palette_strategy","palette_lock_a","palette_lock_b","palette_hue_offset","palette_saturation","palette_value","wind_reach","wind_trail","split_separation","edge_source_mode","fringe_coverage_mode","geometry_units","fringe_pixel","fringe_space","fringe_bayer_level","edge_mask_path","treatment_mask_path","effect_mask_enabled","effect_mask_invert","effect_mask_base","effect_mask_threshold","effect_mask_softness","edge_alpha_weight","edge_luma_weight","edge_threshold","wind_cutoff","signal_gain","signal_softness","signal_posterize","color_blur","fringe_coverage_threshold","fringe_coverage_gain","fringe_bleed","rgb_gradient","rgb_gradient_balance","rgb_gradient_contrast","fringe_blend_mode"],
    "FLOW": ["fx_on:flow","fx_amount:flow","driver_mode","flow_strength","driver_sampling_mode","driver_pixel_size","temporal_hold","FIELD_STRENGTH","FIELD_SPEED","OUTWARDNESS","FIELD_BREAKUP","COORD_NUDGE","FIELD_SIZE","FIELD_CENTER_X","FIELD_CENTER_Y","wind_displace","flow_center_x","flow_center_y","LEGACY_SCALE","LEGACY_SPEED","LEGACY_RADIAL","DRIVER_CENTER_X","DRIVER_CENTER_Y","DRIVER_SCALE","DRIVER_STRETCH","DRIVER_ANGLE","DRIVER_SPEED","DRIVER_DETAIL","DRIVER_FLOW"],
    "RGB": ["fx_on:rgb","fx_amount:rgb","rgb_shift_amount","rgb_shift_angle","rgb_shift_units","rgb_shift_alpha"]
}

var shader: Shader
var screen: Node = null
var materials := {}
var slot_nodes := {}
var slot_roles := {}
var texture_proxy_nodes := {}
var proxy_original_self_modulate := {}
var selected_slot := "mark"
var target_mode := "SELECTED"
var target_role := "VS MARK"
var bypass_fx := false
var debug_view_index := 0
var debug_view_picker: OptionButton

var source_mode := "LIVE SCREEN"
var custom_canvas: CanvasLayer
var custom_root: Control
var custom_background: TextureRect
var custom_rect: TextureRect
var study_zoom := 1.0
var study_pan := Vector2.ZERO
var study_fit_size := Vector2(900,630)
var study_dragging := false
var study_last_pointer := Vector2.ZERO
var study_background_mode := "DARK"
var study_zoom_spin: SpinBox
var study_background_picker: OptionButton
var custom_asset_paths: Array[String] = []
var study_assets: Array[Dictionary] = []
var mask_paths: Array[String] = []
var custom_asset_path := ""
var live_target_mode := "SELECTED"
var live_target_role := "VS MARK"
var live_selected_slot := "mark"
var edge_mask_path := ""
var treatment_mask_path := ""

var state := {
    "pure_continuous": false,
    "fx_size": 1.0, "fx_intensity": 1.0, "pattern_scale": 1.0, "edge_width": 3.0,
    "fx_on": {"dither": false, "fringe": false, "flow": false, "rgb": false},
    "fx_amount": {"dither": 0.75, "fringe": 0.85, "flow": 1.0, "rgb": 0.65},
    "base_mode": 0.0,
    "base_opacity": 1.0,
    "base_grade_amount": 0.0,
    "grade_black_point": 0.0, "grade_white_point": 1.0, "grade_gamma": 1.0,
    "grade_contrast": 1.0, "grade_brightness": 0.0, "grade_saturation": 1.0,
    "source_pixel_size": 0.0,
    "source_pixel_units": 1.0,
    "mono_threshold": 0.75, "mono_mode": 1.0, "mono_bayer_level": 2.0,
    "mono_pixel": 2.0, "mono_space": 1.0,
    "dither_threshold": 0.75, "dither_black_point": 0.0, "dither_white_point": 1.0,
    "dither_gamma": 1.35, "dither_contrast": 1.6, "dither_brightness": 0.0,
    "dither_mode": 1.0, "dither_bayer_level": 2.0, "dither_pixel": 2.0,
    "dither_levels": 6.0, "dither_space": 1.0,
    "edge_source_mode": 2.0, "edge_alpha_weight": 1.2, "edge_luma_weight": 1.0,
    "edge_threshold": 0.08, "wind_reach": 32.0, "wind_trail": 0.35, "wind_cutoff": 0.22,
    "split_separation": 10.0, "wind_displace": 1.0, "signal_gain": 1.35,
    "color_blur": 0.0, "signal_softness": 0.08, "signal_posterize": 0.0,
    "fringe_coverage_mode": 0.0, "fringe_coverage_threshold": 0.12,
    "fringe_bayer_level": 2.0, "fringe_pixel": 2.0, "fringe_space": 1.0,
    "fringe_coverage_gain": 1.0, "rgb_gradient": 0.0, "rgb_gradient_balance": 0.0,
    "rgb_gradient_contrast": 1.0, "fringe_bleed": 0.65, "fringe_blend_mode": 0.0,
    "geometry_units": 1.0,
    "effect_mask_enabled": false, "effect_mask_invert": false,
    "effect_mask_threshold": 0.5, "effect_mask_softness": 0.10, "effect_mask_base": false,
    "driver_mode": 0.0, "driver_sampling_mode": 0.0, "driver_pixel_size": 2.0,
    "FIELD_STRENGTH": 0.42, "FIELD_SPEED": 0.55, "OUTWARDNESS": 0.55,
    "FIELD_BREAKUP": 0.85, "COORD_NUDGE": 0.18, "FIELD_SIZE": 1.0,
    "FIELD_CENTER_X": 1.25, "FIELD_CENTER_Y": 1.45,
    "LEGACY_SCALE": 5.0, "LEGACY_SPEED": 0.3, "LEGACY_RADIAL": 0.45,
    "DRIVER_CENTER_X": 1.5, "DRIVER_CENTER_Y": 1.5, "DRIVER_SCALE": 1.0,
    "DRIVER_STRETCH": 0.0, "DRIVER_ANGLE": 0.0, "DRIVER_SPEED": 1.0,
    "DRIVER_DETAIL": 0.5, "DRIVER_FLOW": 0.5,
    "flow_strength": 12.0, "flow_center_x": 0.5, "flow_center_y": 0.5,
    "rgb_shift_amount": 6.0, "rgb_shift_angle": 0.0, "rgb_shift_units": 1.0,
    "rgb_shift_alpha": 0.0, "temporal_hold": 0.0,
    "col_a": Color(0.25, 0.95, 1.0), "col_b": Color(1.0, 0.4, 0.85),
    "palette_strategy": 0.0, "palette_lock_a": false, "palette_lock_b": false,
    "palette_hue_offset": 0.0, "palette_saturation": 1.0, "palette_value": 1.0
}

var motion_enabled := {"dither": false, "fringe": false, "flow": false, "rgb": false}
var motion := {
    "dither": {"anchor":"manual","delay":0.0,"attack":0.10,"hold":0.08,"release":0.25,"sustain":0.0,"attack_curve":"cubic_out","release_curve":"sine_in_out"},
    "fringe": {"anchor":"clash_impact","delay":0.0,"attack":0.06,"hold":0.05,"release":0.24,"sustain":0.0,"attack_curve":"back_out","release_curve":"sine_in_out"},
    "flow": {"anchor":"manual","delay":0.0,"attack":0.12,"hold":0.15,"release":0.30,"sustain":0.0,"attack_curve":"cubic_out","release_curve":"sine_in_out"},
    "rgb": {"anchor":"manual","delay":0.0,"attack":0.06,"hold":0.05,"release":0.20,"sustain":0.0,"attack_curve":"cubic_out","release_curve":"cubic_out"}
}
var runtime_amount := {"dither":0.75,"fringe":0.85,"flow":1.0,"rgb":0.65}
var motion_running := {}
var motion_t0 := {}
var motion_has_fired := {}
var motion_loop := false

var fx_time := 0.0
var free_run_time := 0.0
var shader_time := 0.0
var time_source := "PRESENTATION TIME"
var preview_t := 0.0
var study_presentation_time := 0.0
var transport_paused := false
var transport_dragging := false
var transport_button: Button
var transport_time_spin: SpinBox
var transport_syncing := false
var timeline_len := 2.4
var event_marks := {}
var timing_1v1 := {}
var mp_timing := {}
var roster_presentation := {}
var layout_1v1 := {}
var multiplayer_layouts := {}

var mode_format := "1v1"
var pick_l := "ice_mage"
var pick_r := "doge_man"
var pick_extra := ["teknium", "ggb"]
var stage_id := "debug"
var fighter_ids: Array = []

# UI
var subvp: SubViewport
var disp: SubViewportContainer
var viewport_host: Control
var selection_outline: ReferenceRect
var preview_focus_mode := "NORMAL"
var preview_focus_picker: OptionButton
var side_panel: Control
var timeline_view: Control
var status_label: Label
var look_label: Label
var time_label: Label
var processing_label: RichTextLabel
var cost_label: Label
var fps_label: Label
var target_label: Label
var slot_picker: OptionButton
var target_mode_picker: OptionButton
var role_picker: OptionButton
var detail_picker: OptionButton
var custom_asset_picker: OptionButton
var edge_mask_picker: OptionButton
var treatment_mask_picker: OptionButton
var preset_picker: OptionButton
var preset_name_edit: LineEdit
var preset_status_label: Label
var assignment_scope_picker: OptionButton
var assignment_status_label: RichTextLabel
var assignment_coverage_label: RichTextLabel
var assignment_resolved_label: Label
var import_dialog: FileDialog
var production_look_picker: OptionButton
var assignment_binding_picker: OptionButton
var assignment_filter_picker: OptionButton
var production_look_ids: Array[String] = []
var assignment_binding_rows: Array[Dictionary] = []
var reset_buttons := {}
var section_reset_buttons := {}
var section_bodies := {}
var section_toggle_buttons := {}
var section_collapsed := {}
var section_titles := {}
var controls := {}
var spin_controls := {}
var swatches := []
var advanced_nodes := []
var expert_nodes := []
var panel_visible := true
var factory_state := {}
var factory_motion := {}
var factory_motion_enabled := {}
var current_preset_name := ""
var loaded_look_name := ""
var loaded_look_snapshot := {}
var loaded_look_is_production := false
var dirty := false
var suppress_dirty := false
var snapshot_a := {}
var snapshot_b := {}
var diagnostics_accum := 0.0
var fps_accum := 0.0
var look_history: Array[Dictionary] = []
var history_index := -1
var history_pending := false
var history_pending_elapsed := 0.0
var history_restoring := false
var history_limit := 100
var section_clipboard := {}
var section_clipboard_id := ""

func _ready() -> void:
    shader = load("res://shaders/nrcu_fx_v2.gdshader")
    factory_state = state.duplicate(true)
    factory_motion = motion.duplicate(true)
    factory_motion_enabled = motion_enabled.duplicate(true)
    _scan_fighters()
    _load_schemas()
    _scan_assets()
    subvp = SubViewport.new()
    subvp.size = Vector2i(1280, 720)
    subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    subvp.transparent_bg = false
    _build_ui()
    _build_custom_canvas()
    _mount_screen()
    _refresh_preset_list()
    _history_reset_to_current()

# ---------------------------------------------------------------- data/context
func _load_json(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {}
    var parsed = JSON.parse_string(f.get_as_text())
    return parsed if parsed is Dictionary else {}

func _load_schemas() -> void:
    timing_1v1 = _load_json("res://assets/vs/schema/motion_timing.json")
    mp_timing = _load_json("res://assets/vs/schema/multiplayer_motion_timing.json")
    roster_presentation = _load_json("res://assets/vs/schema/roster_presentation.json")
    layout_1v1 = _load_json("res://assets/vs/schema/vs_layout_1280x720.json")
    multiplayer_layouts = _load_json("res://assets/vs/schema/multiplayer_layouts_1280x720.json")
    event_marks = _event_times()

func _scan_fighters() -> void:
    fighter_ids.clear()
    var d := DirAccess.open("res://assets/vs/fighters")
    if d != null:
        d.list_dir_begin()
        var name := d.get_next()
        while name != "":
            if d.current_is_dir() and not name.begins_with(".") and not name.ends_with(".import"):
                fighter_ids.append(name)
            name = d.get_next()
        d.list_dir_end()
    fighter_ids.sort()

func _scan_dir(path: String) -> Array[String]:
    var result: Array[String] = []
    var d := DirAccess.open(path)
    if d == null:
        return result
    d.list_dir_begin()
    var name := d.get_next()
    while name != "":
        if not d.current_is_dir() and not name.ends_with(".import"):
            if name.get_extension().to_lower() in ["png","webp","jpg","jpeg"]:
                result.append(path.path_join(name))
        name = d.get_next()
    d.list_dir_end()
    result.sort()
    return result

func _project_asset_exists(path: String) -> bool:
    # ResourceLoader.exists() can be false for a valid PNG before Godot has
    # generated its import sidecar. The packaged authoring masks are intentionally
    # loadable through _load_project_texture() without requiring an editor import.
    return ResourceLoader.exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))

func _scan_assets() -> void:
    custom_asset_paths = _scan_dir("res://assets/elements")
    mask_paths = _scan_dir("res://assets/masks")
    study_assets.clear()
    var vs_path := "res://assets/vs/ui/vs_mark.png"
    if _project_asset_exists(vs_path):
        study_assets.append({"label":"VS MARK", "path":vs_path, "role":"VS MARK", "element_id":"vs_mark"})
    for fighter_id in fighter_ids:
        for layer in [["PRIMARY","primary.png","PRIMARIES"],["ECHO","echo.png","ECHOES"],["NAME","name.png","NAMES"]]:
            var path := "res://assets/vs/fighters/%s/%s" % [fighter_id, layer[1]]
            if _project_asset_exists(path):
                study_assets.append({"label":"%s · %s" % [layer[0], str(fighter_id).to_upper()], "path":path, "role":layer[2], "fighter_id":fighter_id, "layer":String(layer[0]).to_lower()})
    for stage_name in STAGE_IDS:
        var stage_path := "res://assets/vs/stages/%s.png" % stage_name
        if _project_asset_exists(stage_path):
            study_assets.append({"label":"STAGE · %s" % stage_name.to_upper(), "path":stage_path, "role":"STAGE", "element_id":"stage", "stage_id":stage_name})
    var side_alpha := float((layout_1v1.get("side_fields",{}) as Dictionary).get("alpha",31)) / 255.0
    var side_tint := Color(1.0,1.0,1.0,side_alpha)
    var fill_rgba: Array = (layout_1v1.get("nameplates",{}) as Dictionary).get("fill_rgba",[2,4,5,245])
    var plate_tint := Color(float(fill_rgba[0])/255.0,float(fill_rgba[1])/255.0,float(fill_rgba[2])/255.0,float(fill_rgba[3])/255.0) if fill_rgba.size() >= 4 else Color(0.008,0.016,0.020,0.96)
    for side in ["left","right"]:
        var field_mask := "res://assets/vs/generated/side_field_%s_mask.png" % side
        if _project_asset_exists(field_mask):
            study_assets.append({"label":"SIDE FIELD · %s" % side.to_upper(), "path":field_mask, "role":"SIDE FIELDS", "element_id":"side_field_%s" % side, "visual_side":side, "source_tint":side_tint})
    for side in ["left","right"]:
        var plate_mask := "res://assets/vs/generated/name_plate_%s_mask.png" % side
        if _project_asset_exists(plate_mask):
            study_assets.append({"label":"NAME PLATE · %s" % side.to_upper(), "path":plate_mask, "role":"NAME PLATES", "element_id":"name_plate_%s" % side, "visual_side":side, "source_tint":plate_tint})
        var accent_mask := "res://assets/vs/generated/accent_%s_mask.png" % side
        if _project_asset_exists(accent_mask):
            study_assets.append({"label":"ACCENT LINE · %s" % side.to_upper(), "path":accent_mask, "role":"ACCENT LINES", "element_id":"accent_line_%s" % side, "visual_side":side, "source_tint":Color.WHITE})
    for path in custom_asset_paths:
        study_assets.append({"label":"CUSTOM · " + path.get_file(), "path":path, "role":"OTHER TEXTURES"})
    if not study_assets.is_empty():
        var valid := false
        for item in study_assets:
            if str(item["path"]) == custom_asset_path:
                valid = true
                break
        if not valid:
            custom_asset_path = str(study_assets[0]["path"])
    if edge_mask_path != "" and not mask_paths.has(edge_mask_path):
        edge_mask_path = ""
    if treatment_mask_path != "" and not mask_paths.has(treatment_mask_path):
        treatment_mask_path = ""

func _mp_records() -> Array:
    var teams: Array = []
    var count := 3
    match mode_format:
        "FFA_4": count = 4
        "TEAM_2V2":
            count = 4
            teams = [0,0,1,1]
        "TEAM_2V1":
            count = 3
            teams = [0,0,1]
        "TEAM_3V1":
            count = 4
            teams = [0,0,0,1]
    var pool := [pick_l, pick_r, pick_extra[0], pick_extra[1]]
    var records := []
    for i in range(count):
        var team_id := int(teams[i]) if teams.size() > i else VSRequest.StateScript.NO_TEAM
        var kind := VSRequest.StateScript.Kind.HUMAN if i == 0 else VSRequest.StateScript.Kind.CPU
        records.append(VSRequest.record(i, str(pool[i]), team_id, kind, 0))
    return records

func _mount_screen() -> void:
    motion_running.clear()
    motion_has_fired.clear()
    fx_time = 0.0
    preview_t = 0.0
    study_presentation_time = 0.0
    transport_paused = false
    if screen != null and is_instance_valid(screen):
        screen.free()
    screen = load("res://scenes/vs_screen.tscn").instantiate()
    subvp.add_child(screen)
    var ok := false
    if mode_format == "1v1":
        ok = screen.start(pick_l, pick_r, stage_id)
    else:
        var plan: Dictionary = VSRequest.plan(_mp_records(), stage_id, mode_format.begins_with("TEAM"))
        ok = screen.start_presentation(plan)
        if not ok:
            mode_format = "1v1"
            ok = screen.start(pick_l, pick_r, stage_id)
    event_marks = _event_times()
    _install_vector_proxies()
    _reset_runtime_amounts()
    _set_source_visibility()
    _collect_slots()
    _attach_materials()
    _normalize_target()
    _refresh_slot_picker()
    _apply_fx()
    _refresh_assignment_view()
    if transport_button != null:
        transport_button.text = "⏸ PAUSE"
    status_label_text(("live" if ok else "fallback") + " · " + mode_format + " · " + stage_id)

func _load_project_texture(path: String) -> Texture2D:
    # Normal project assets should already be imported before this scene runs.
    # The fallback deliberately handles generated authoring masks even when an
    # import sidecar/cache is missing, avoiding the silent no-op failure mode
    # found in the earlier runtime-mask implementation.
    if ResourceLoader.exists(path):
        var imported = load(path)
        if imported is Texture2D:
            return imported as Texture2D
    var absolute_path := ProjectSettings.globalize_path(path)
    if not FileAccess.file_exists(absolute_path):
        return null
    var image := Image.new()
    if image.load(absolute_path) != OK or image.is_empty():
        return null
    return ImageTexture.create_from_image(image)

func _install_vector_proxy(source: CanvasItem, mask_path: String, role: String, element_id: String) -> void:
    if source == null:
        return
    var mask_texture := _load_project_texture(mask_path)
    if mask_texture == null:
        push_warning("FX Lab vector proxy mask unavailable: " + mask_path)
        return
    var parent := source.get_parent()
    if parent == null:
        return
    var proxy := TextureRect.new()
    proxy.name = str(source.name) + "_FXProxy"
    proxy.texture = mask_texture
    proxy.position = Vector2.ZERO
    proxy.size = Vector2(1280,720)
    proxy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
    proxy.z_index = source.z_index
    var tint := Color.WHITE
    if source is Polygon2D:
        tint = (source as Polygon2D).color
    elif source is Line2D:
        tint = (source as Line2D).default_color
    proxy.set_meta("fx_source_tint",tint)
    proxy.set_meta("fx_element_id",element_id)
    proxy.set_meta("fx_role",role)
    proxy.set_meta("fx_vector_proxy",true)
    source.visible = false
    parent.add_child(proxy)

func _install_vector_proxies() -> void:
    if screen == null or not is_instance_valid(screen):
        return
    # Duel/static vector geometry. Each proxy uses a canonical 1280×720 alpha
    # mask so the shared FX shader can expand beyond the original polygon/line.
    var static_specs := [
        ["Root/SideFields/FieldLeft","res://assets/vs/generated/side_field_left_mask.png","SIDE FIELDS","side_field_left"],
        ["Root/SideFields/FieldRight","res://assets/vs/generated/side_field_right_mask.png","SIDE FIELDS","side_field_right"],
        ["Root/NamePlates/PlateLeft","res://assets/vs/generated/name_plate_left_mask.png","NAME PLATES","name_plate_left"],
        ["Root/NamePlates/PlateRight","res://assets/vs/generated/name_plate_right_mask.png","NAME PLATES","name_plate_right"],
        ["Root/NamePlates/AccentLeft","res://assets/vs/generated/accent_left_mask.png","ACCENT LINES","accent_line_left"],
        ["Root/NamePlates/AccentRight","res://assets/vs/generated/accent_right_mask.png","ACCENT LINES","accent_line_right"]
    ]
    for spec in static_specs:
        var source := screen.get_node_or_null(String(spec[0])) as CanvasItem
        if source != null and source.visible:
            _install_vector_proxy(source,String(spec[1]),String(spec[2]),String(spec[3]))

    # Multiplayer name plates/accent lines are generated at runtime, but their
    # geometry is schema-authored. Matching generated masks therefore remain
    # exact and keep the real node's colour as source tint.
    if mode_format != "1v1":
        var family_plates := screen.get_node_or_null("Root/FamilyFront/Plates")
        if family_plates != null:
            for child in family_plates.get_children():
                var child_name := String(child.name)
                var lower := child_name.to_lower()
                var slot := ""
                var kind := ""
                var role := ""
                if lower.begins_with("plate_"):
                    slot = lower.trim_prefix("plate_")
                    kind = "plate"
                    role = "NAME PLATES"
                elif lower.begins_with("accent_"):
                    slot = lower.trim_prefix("accent_")
                    kind = "accent"
                    role = "ACCENT LINES"
                if slot == "":
                    continue
                var mask_path := "res://assets/vs/generated/%s_%s_%s_mask.png" % [mode_format.to_lower(), kind, slot]
                _install_vector_proxy(child as CanvasItem,mask_path,role,"%s_%s_%s" % [kind,mode_format.to_lower(),slot])

# Compatibility shim for older tests/handoffs.
func _install_side_field_proxies() -> void:
    _install_vector_proxies()

func _build_custom_canvas() -> void:
    custom_canvas = CanvasLayer.new()
    custom_canvas.layer = 40
    custom_canvas.visible = false
    subvp.add_child(custom_canvas)
    custom_root = Control.new()
    custom_root.set_anchors_preset(Control.PRESET_FULL_RECT)
    custom_canvas.add_child(custom_root)
    custom_background = TextureRect.new()
    custom_background.set_anchors_preset(Control.PRESET_FULL_RECT)
    custom_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    custom_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_root.add_child(custom_background)
    custom_rect = TextureRect.new()
    custom_rect.name = "CustomAsset"
    custom_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    custom_rect.stretch_mode = TextureRect.STRETCH_SCALE
    custom_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_root.add_child(custom_rect)
    _apply_study_background()
    _refresh_custom_texture()

func _study_fit_rect_for(tex: Texture2D) -> Rect2:
    var area := Rect2(Vector2(120,45),Vector2(1040,630))
    if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
        return area
    var source := Vector2(tex.get_width(),tex.get_height())
    var scale_factor := minf(area.size.x/source.x,area.size.y/source.y)
    var fitted := source*scale_factor
    return Rect2(area.position+(area.size-fitted)*0.5,fitted)

func _update_study_geometry() -> void:
    if custom_rect == null or custom_rect.texture == null:
        return
    var fit := _study_fit_rect_for(custom_rect.texture)
    study_fit_size = fit.size
    var size := fit.size*study_zoom
    custom_rect.size = size
    custom_rect.position = fit.position+(fit.size-size)*0.5+study_pan
    if study_zoom_spin != null:
        study_zoom_spin.set_value_no_signal(study_zoom*100.0)

func _study_fit() -> void:
    study_zoom = 1.0
    study_pan = Vector2.ZERO
    _update_study_geometry()
    status_label_text("element study · fit")

func _set_study_zoom(next_zoom: float, pivot := Vector2(640,360)) -> void:
    var old_zoom := maxf(study_zoom,0.0001)
    var next := clampf(next_zoom,STUDY_ZOOM_MIN,STUDY_ZOOM_MAX)
    if is_equal_approx(next,old_zoom):
        return
    # Keep the point under the cursor approximately stable while zooming.
    var fit := _study_fit_rect_for(custom_rect.texture if custom_rect != null else null)
    var base_center := fit.position+fit.size*0.5
    var current_center := base_center+study_pan
    var vector_from_center := pivot-current_center
    study_pan += vector_from_center*(1.0-next/old_zoom)
    study_zoom = next
    _update_study_geometry()

func _on_study_zoom_entered(value: float) -> void:
    _set_study_zoom(value/100.0)

func _on_study_background(index: int) -> void:
    if index >= 0 and index < STUDY_BACKGROUNDS.size():
        study_background_mode = STUDY_BACKGROUNDS[index]
    _apply_study_background()

func _apply_study_background() -> void:
    if custom_background == null:
        return
    custom_background.texture = null
    custom_background.modulate = Color.WHITE
    match study_background_mode:
        "LIGHT":
            custom_background.self_modulate = Color(0.82,0.84,0.87,1.0)
        "NEUTRAL":
            custom_background.self_modulate = Color(0.22,0.24,0.27,1.0)
        "CHECKER":
            custom_background.self_modulate = Color.WHITE
            var checker_path := "res://assets/vs/generated/study_checker.png"
            if ResourceLoader.exists(checker_path):
                custom_background.texture = load(checker_path) as Texture2D
        _:
            custom_background.self_modulate = Color(0.04,0.05,0.065,1.0)

func _refresh_custom_texture() -> void:
    if custom_rect != null and custom_asset_path != "" and ResourceLoader.exists(custom_asset_path):
        custom_rect.texture = load(custom_asset_path)
        var study_item := _study_item_for_path(custom_asset_path)
        custom_rect.set_meta("fx_source_tint",study_item.get("source_tint",Color.WHITE))
        _study_fit()

func _set_source_visibility() -> void:
    var study := source_mode == "ELEMENT STUDY"
    if custom_canvas != null:
        custom_canvas.visible = study
    if screen != null:
        screen.visible = not study

# ---------------------------------------------------------------- target/material
func _collect_slots() -> void:
    slot_nodes.clear()
    slot_roles.clear()
    if source_mode == "ELEMENT STUDY":
        if custom_rect != null and custom_rect.texture != null:
            var study_item := _study_item_for_path(custom_asset_path)
            slot_nodes["study_asset"] = custom_rect
            slot_roles["study_asset"] = str(study_item.get("role","OTHER TEXTURES"))
            custom_rect.set_meta("fx_source_tint",study_item.get("source_tint",Color.WHITE))
            for meta_key in ["element_id","visual_side","stage_id","fighter_id"]:
                if study_item.has(meta_key):
                    custom_rect.set_meta("fx_" + meta_key,str(study_item[meta_key]))
                elif custom_rect.has_meta("fx_" + meta_key):
                    custom_rect.remove_meta("fx_" + meta_key)
            selected_slot = "study_asset"
        return
    if screen == null:
        return
    var root := screen.get_node_or_null("Root")
    if root != null:
        _gather(root)

func _study_item_for_path(path: String) -> Dictionary:
    for item in study_assets:
        if str(item.get("path", "")) == path:
            return item
    return {}

func _study_role_for_path(path: String) -> String:
    return str(_study_item_for_path(path).get("role", "OTHER TEXTURES"))

func _gather(node: Node) -> void:
    for child in node.get_children():
        if child is TextureRect and child.texture != null and not bool(child.get_meta("fx_overscan_proxy",false)):
            var key := String(child.name).to_snake_case()
            if key not in ["shadow", "under_shadow"] and not slot_nodes.has(key):
                slot_nodes[key] = child
                slot_roles[key] = String(child.get_meta("fx_role",_role_for_key(key)))
        _gather(child)

func _role_for_key(key: String) -> String:
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

func _raw_presentation_size_for(node: TextureRect, tex: Texture2D) -> Vector2:
    var local_size := node.size
    if local_size.x < 1.0 or local_size.y < 1.0:
        local_size = Vector2(tex.get_width(), tex.get_height())
    var transform := node.get_global_transform()
    var scale_x := maxf(transform.x.length(), 0.0001)
    var scale_y := maxf(transform.y.length(), 0.0001)
    return Vector2(maxf(local_size.x * scale_x, 1.0), maxf(local_size.y * scale_y, 1.0))

func _find_live_texture_reference(node: Node, asset_path: String, role: String, exact_path: bool) -> TextureRect:
    if node == null:
        return null
    for child in node.get_children():
        if child is TextureRect and child.texture != null:
            var child_path := String(child.texture.resource_path)
            if exact_path and child_path == asset_path:
                return child
            if not exact_path and _role_for_key(String(child.name).to_snake_case()) == role:
                return child
        var nested := _find_live_texture_reference(child, asset_path, role, exact_path)
        if nested != null:
            return nested
    return null

func _fit_size_from_spec(spec: Dictionary, tex: Texture2D) -> Vector2:
    if tex == null:
        return Vector2.ONE
    var tw := maxf(float(tex.get_width()),1.0)
    var th := maxf(float(tex.get_height()),1.0)
    var scale_factor := 1.0
    if spec.has("height"):
        scale_factor = float(spec["height"])/th
    elif spec.has("width"):
        scale_factor = float(spec["width"])/tw
    return Vector2(round(tw*scale_factor),round(th*scale_factor))

func _study_reference_presentation_size(tex: Texture2D) -> Vector2:
    var item := {}
    for candidate in study_assets:
        if str(candidate.get("path", "")) == custom_asset_path:
            item = candidate
            break
    var role := str(item.get("role","OTHER TEXTURES"))
    var fighter_id := str(item.get("fighter_id",""))
    var layer := str(item.get("layer",""))
    if fighter_id != "" and roster_presentation.has(fighter_id):
        var fighter: Dictionary = roster_presentation[fighter_id]
        if layer == "primary" or layer == "echo":
            return _fit_size_from_spec(fighter.get(layer,{}) as Dictionary,tex)
        if layer == "name":
            # Duel names are authored at source pixel size.
            return Vector2(tex.get_width(),tex.get_height())
    if role == "VS MARK":
        var mark: Dictionary = layout_1v1.get("vs_mark",{})
        var target_h := float(mark.get("height",224.0))
        return Vector2(round(float(tex.get_width())*target_h/maxf(float(tex.get_height()),1.0)),round(target_h))
    if role == "STAGE" or role in ["SIDE FIELDS","NAME PLATES","ACCENT LINES"]:
        return Vector2(1280,720)
    # Prefer an exact live reference if a future study asset has production
    # geometry not covered by the current schemas. Never fall back by role: a
    # different fighter can have a materially different authored size.
    if screen != null and is_instance_valid(screen):
        var root := screen.get_node_or_null("Root")
        var reference := _find_live_texture_reference(root,custom_asset_path,role,true)
        if reference != null and reference.texture != null:
            return _raw_presentation_size_for(reference,reference.texture)
    # Custom assets have no production geometry. Use the fit-at-100% study
    # footprint as a stable reference; editor zoom/pan must never change FX scale.
    return study_fit_size if custom_rect != null else Vector2(tex.get_width(), tex.get_height())

func _presentation_size_for(node: TextureRect, tex: Texture2D) -> Vector2:
    if source_mode == "ELEMENT STUDY" and node == custom_rect:
        return _study_reference_presentation_size(tex)
    return _raw_presentation_size_for(node, tex)

func _presentation_rect_for(node: TextureRect) -> Rect2:
    var xform := node.get_global_transform()
    var corners := [Vector2.ZERO, Vector2(node.size.x,0.0), node.size, Vector2(0.0,node.size.y)]
    var first: Vector2 = xform * corners[0]
    var minp := first
    var maxp := first
    for i in range(1,corners.size()):
        var pnt: Vector2 = xform * corners[i]
        minp.x = minf(minp.x,pnt.x); minp.y = minf(minp.y,pnt.y)
        maxp.x = maxf(maxp.x,pnt.x); maxp.y = maxf(maxp.y,pnt.y)
    return Rect2(minp,maxp-minp)

func _texture_hit_alpha(node: TextureRect, local: Vector2) -> bool:
    if node.texture == null or node.size.x <= 0.0 or node.size.y <= 0.0:
        return false
    var uv := Vector2(local.x/node.size.x,local.y/node.size.y)
    if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
        return false
    if node.flip_h:
        uv.x = 1.0-uv.x
    var image := node.texture.get_image()
    if image == null or image.is_empty():
        return true
    var px := clampi(int(round(uv.x*float(image.get_width()-1))),0,image.get_width()-1)
    var py := clampi(int(round(uv.y*float(image.get_height()-1))),0,image.get_height()-1)
    return image.get_pixel(px,py).a > 0.03

func _pick_live_texture_at(point: Vector2) -> String:
    if source_mode != "LIVE SCREEN":
        return ""
    var hits: Array = []
    for key in slot_nodes.keys():
        var node = slot_nodes[key]
        if not (node is TextureRect) or not node.visible:
            continue
        var inv: Transform2D = node.get_global_transform().affine_inverse()
        var local: Vector2 = inv * point
        if Rect2(Vector2.ZERO,node.size).has_point(local) and _texture_hit_alpha(node,local):
            var rect := _presentation_rect_for(node)
            hits.append({"key":String(key),"area":rect.size.x*rect.size.y,"z":node.z_index})
    if hits.is_empty():
        return ""
    # Prefer visually specific/small elements over full-frame targets such as Stage.
    hits.sort_custom(func(a,b):
        if int(a["z"]) != int(b["z"]):
            return int(a["z"]) > int(b["z"])
        return float(a["area"]) < float(b["area"])
    )
    return String(hits[0]["key"])

func _on_preview_gui_input(event: InputEvent) -> void:
    if source_mode == "ELEMENT STUDY":
        if event is InputEventMouseButton:
            var mouse := event as InputEventMouseButton
            if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
                _set_study_zoom(study_zoom*1.15,mouse.position)
                get_viewport().set_input_as_handled()
            elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
                _set_study_zoom(study_zoom/1.15,mouse.position)
                get_viewport().set_input_as_handled()
            elif mouse.button_index == MOUSE_BUTTON_MIDDLE:
                study_dragging = mouse.pressed
                study_last_pointer = mouse.position
                get_viewport().set_input_as_handled()
        elif event is InputEventMouseMotion and study_dragging:
            var motion_event := event as InputEventMouseMotion
            study_pan += motion_event.position-study_last_pointer
            study_last_pointer = motion_event.position
            _update_study_geometry()
            get_viewport().set_input_as_handled()
        return
    if source_mode != "LIVE SCREEN":
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var key := _pick_live_texture_at(event.position)
        if key == "":
            return
        target_mode = "SELECTED"
        selected_slot = key
        _sync_controls()
        _update_target_controls()
        _apply_fx()
        _refresh_assignment_view()
        status_label_text("selected live element · " + key.to_upper())
        get_viewport().set_input_as_handled()

func _update_selection_outline() -> void:
    if selection_outline == null:
        return
    if source_mode != "LIVE SCREEN" or target_mode != "SELECTED" or not slot_nodes.has(selected_slot):
        selection_outline.visible = false
        return
    var node = slot_nodes[selected_slot]
    if not (node is TextureRect) or disp == null:
        selection_outline.visible = false
        return
    var rect := _presentation_rect_for(node)
    selection_outline.position = disp.position + rect.position * disp.scale
    selection_outline.size = rect.size * disp.scale
    selection_outline.visible = true

func _selected_spatial_readout() -> String:
    var targets := _target_keys()
    if targets.is_empty():
        return "Spatial: NO ACTIVE TARGETS"
    var key := String(targets[0])
    var node = slot_nodes.get(key)
    if not (node is TextureRect) or node.texture == null:
        return "Spatial: unsupported target"
    var tex: Texture2D = node.texture
    var ps := _presentation_size_for(node, tex)
    var sx := ps.x / maxf(float(tex.get_width()), 1.0)
    var sy := ps.y / maxf(float(tex.get_height()), 1.0)
    return "Spatial: source %d×%d → presentation %.1f×%.1f · scale %.3f×/%.3f×" % [tex.get_width(), tex.get_height(), ps.x, ps.y, sx, sy]

func _required_overscan_px() -> float:
    var spatial := maxf(float(state["fx_size"]),0.0)
    var extent := 0.0
    if bool(state["fx_on"]["rgb"]):
        extent = maxf(extent,float(state["rgb_shift_amount"])*spatial)
    if bool(state["fx_on"]["fringe"]):
        var fringe_extent := float(state["edge_width"])*spatial*2.0
        fringe_extent += float(state["wind_reach"])*spatial*1.15
        fringe_extent += float(state["split_separation"])*spatial
        fringe_extent += float(state["color_blur"])*spatial
        if bool(state["fx_on"]["flow"]):
            fringe_extent += float(state["flow_strength"])*spatial*2.0
        extent = maxf(extent,fringe_extent)
    return maxf(extent+12.0,12.0)

func _clear_texture_proxies() -> void:
    for key in texture_proxy_nodes.keys():
        var proxy = texture_proxy_nodes[key]
        if proxy != null and is_instance_valid(proxy):
            var source_node: Node = proxy.get_parent()
            if source_node is TextureRect and proxy_original_self_modulate.has(key):
                (source_node as TextureRect).self_modulate = proxy_original_self_modulate[key]
            if source_node != null:
                source_node.remove_child(proxy)
            proxy.queue_free()
    texture_proxy_nodes.clear()
    proxy_original_self_modulate.clear()

func _should_use_texture_proxy(key: String, node: TextureRect) -> bool:
    if bool(node.get_meta("fx_vector_proxy",false)):
        return false
    # Full-frame stage does not benefit from external overscan; every authored
    # fighter/name/mark/study texture does.
    if String(slot_roles.get(key,"")) == "STAGE" and node.size.x >= 1270.0 and node.size.y >= 710.0:
        return false
    return true

func _configure_texture_proxy(key: String, node: TextureRect, mat: ShaderMaterial) -> TextureRect:
    var proxy := TextureRect.new()
    proxy.name = "FXOverscanProxy"
    proxy.texture = node.texture
    proxy.texture_filter = node.texture_filter
    proxy.texture_repeat = node.texture_repeat
    proxy.expand_mode = node.expand_mode
    proxy.stretch_mode = node.stretch_mode
    proxy.flip_h = node.flip_h
    proxy.flip_v = node.flip_v
    proxy.modulate = node.modulate
    proxy.self_modulate = node.self_modulate
    proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
    proxy.z_index = 0
    proxy.set_meta("fx_overscan_proxy",true)
    var original_modulate: Color = node.self_modulate
    proxy_original_self_modulate[key] = original_modulate
    proxy.self_modulate = original_modulate
    node.add_child(proxy)
    var hidden := original_modulate
    hidden.a = 0.0
    node.self_modulate = hidden
    proxy.material = mat
    texture_proxy_nodes[key] = proxy
    _update_texture_proxy_geometry(key)
    return proxy

func _update_texture_proxy_geometry(key: String) -> void:
    if not texture_proxy_nodes.has(key) or not slot_nodes.has(key):
        return
    var proxy = texture_proxy_nodes[key]
    var node = slot_nodes[key]
    if not (proxy is TextureRect) or not (node is TextureRect) or node.texture == null:
        return
    var local_size: Vector2 = node.size
    if local_size.x < 1.0 or local_size.y < 1.0:
        local_size = Vector2(node.texture.get_width(),node.texture.get_height())
    var presentation_size := _presentation_size_for(node,node.texture)
    var pad_px := _required_overscan_px()
    # Convert canonical presentation pixels back into this node's local draw
    # space. This also makes Element Study zoom purely editorial: a 2x study
    # zoom doubles the visible overscan without changing the authored px value.
    var pad_local := Vector2(
        pad_px*local_size.x/maxf(presentation_size.x,1.0),
        pad_px*local_size.y/maxf(presentation_size.y,1.0)
    )
    proxy.position = -pad_local
    proxy.size = local_size+pad_local*2.0
    var mat: ShaderMaterial = materials.get(key)
    if mat != null:
        mat.set_shader_parameter("source_uv_scale",Vector2(proxy.size.x/maxf(local_size.x,1.0),proxy.size.y/maxf(local_size.y,1.0)))
        mat.set_shader_parameter("source_uv_offset",Vector2(-pad_local.x/maxf(local_size.x,1.0),-pad_local.y/maxf(local_size.y,1.0)))
        mat.set_shader_parameter("source_flip_x",1.0 if node.flip_h else 0.0)

func _attach_materials() -> void:
    _clear_texture_proxies()
    materials.clear()
    for key in slot_nodes.keys():
        var node = slot_nodes[key]
        if not (node is TextureRect) or node.texture == null:
            continue
        var mat := ShaderMaterial.new()
        mat.shader = shader
        var tex: Texture2D = node.texture
        mat.set_shader_parameter("source_tex", tex)
        mat.set_shader_parameter("source_tint", node.get_meta("fx_source_tint",Color.WHITE))
        mat.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
        mat.set_shader_parameter("element_size", _presentation_size_for(node, tex))
        mat.set_shader_parameter("viewport_size", Vector2(1280,720))
        materials[key] = mat
        mat.set_shader_parameter("source_uv_scale",Vector2.ONE)
        mat.set_shader_parameter("source_uv_offset",Vector2.ZERO)
        mat.set_shader_parameter("source_flip_x",1.0 if node.flip_h else 0.0)
        if _should_use_texture_proxy(String(key),node):
            node.material = null
            _configure_texture_proxy(String(key),node,mat)
        else:
            node.material = mat

func _normalize_target() -> void:
    if target_mode not in TARGET_MODES:
        target_mode = "SELECTED"
    if target_role not in TARGET_ROLES:
        target_role = "VS MARK"
    if target_mode == "SELECTED" and not materials.has(selected_slot):
        if materials.has("mark"):
            selected_slot = "mark"
        elif not materials.is_empty():
            selected_slot = str(materials.keys()[0])
        else:
            selected_slot = ""

func _target_keys() -> Array:
    var result := []
    if target_mode == "ALL":
        return materials.keys()
    if target_mode == "ROLE":
        for key in materials.keys():
            if String(slot_roles.get(key,"OTHER TEXTURES")) == target_role:
                result.append(key)
        return result
    if materials.has(selected_slot):
        result.append(selected_slot)
    return result

func _edge_mask_texture() -> Texture2D:
    if edge_mask_path != "" and ResourceLoader.exists(edge_mask_path):
        return load(edge_mask_path) as Texture2D
    return null

func _treatment_mask_texture() -> Texture2D:
    if treatment_mask_path != "" and ResourceLoader.exists(treatment_mask_path):
        return load(treatment_mask_path) as Texture2D
    return null

func _apply_fx() -> void:
    var targets := _target_keys()
    var edge_mask := _edge_mask_texture()
    var treatment_mask := _treatment_mask_texture()
    for key in materials.keys():
        var mat: ShaderMaterial = materials[key]
        var targeted := targets.has(key)
        var active := targeted and not bypass_fx
        var emphasis := 1.0
        if preview_focus_mode == "DIM OTHERS" and not targeted:
            emphasis = 0.18
        elif preview_focus_mode == "SOLO TARGET" and not targeted:
            emphasis = 0.0
        mat.set_shader_parameter("preview_emphasis",emphasis)
        mat.set_shader_parameter("pure_continuous", 1.0 if bool(state["pure_continuous"]) else 0.0)
        mat.set_shader_parameter("debug_view_mode", float(debug_view_index) if active else 0.0)
        mat.set_shader_parameter("base_mode", float(state["base_mode"]) if active else 0.0)
        mat.set_shader_parameter("base_opacity", float(state["base_opacity"]) if active else 1.0)
        mat.set_shader_parameter("base_grade_amount", float(state["base_grade_amount"]) if active else 0.0)
        mat.set_shader_parameter("source_pixel_size", float(state["source_pixel_size"]) if active else 0.0)
        mat.set_shader_parameter("fx_dither", _effective_amount("dither") if active and bool(state["fx_on"]["dither"]) else 0.0)
        mat.set_shader_parameter("fx_fringe", _effective_amount("fringe") if active and bool(state["fx_on"]["fringe"]) else 0.0)
        mat.set_shader_parameter("fx_flow", _effective_amount("flow") if active and bool(state["fx_on"]["flow"]) else 0.0)
        mat.set_shader_parameter("fx_rgb", _effective_amount("rgb") if active and bool(state["fx_on"]["rgb"]) else 0.0)
        mat.set_shader_parameter("effect_mask_enabled", 1.0 if active and bool(state["effect_mask_enabled"]) and treatment_mask != null else 0.0)
        mat.set_shader_parameter("effect_mask_invert", 1.0 if bool(state["effect_mask_invert"]) else 0.0)
        mat.set_shader_parameter("effect_mask_base", 1.0 if bool(state["effect_mask_base"]) else 0.0)
        var scalar_keys := [
            "fx_size","fx_intensity","pattern_scale","edge_width","source_pixel_units",
            "mono_threshold","mono_mode","mono_bayer_level","mono_pixel","mono_space",
            "grade_black_point","grade_white_point","grade_gamma","grade_contrast","grade_brightness","grade_saturation",
            "dither_threshold","dither_black_point","dither_white_point","dither_gamma","dither_contrast","dither_brightness",
            "dither_mode","dither_bayer_level","dither_pixel","dither_levels","dither_space",
            "edge_source_mode","edge_alpha_weight","edge_luma_weight","edge_threshold","wind_reach","wind_trail","wind_cutoff",
            "split_separation","wind_displace","signal_gain","color_blur","signal_softness","signal_posterize",
            "fringe_coverage_mode","fringe_coverage_threshold","fringe_bayer_level","fringe_pixel","fringe_space","fringe_coverage_gain",
            "rgb_gradient","rgb_gradient_balance","rgb_gradient_contrast","fringe_bleed","fringe_blend_mode","geometry_units",
            "effect_mask_threshold","effect_mask_softness","driver_mode","driver_sampling_mode","driver_pixel_size",
            "FIELD_STRENGTH","FIELD_SPEED","OUTWARDNESS","FIELD_BREAKUP","COORD_NUDGE","FIELD_SIZE",
            "LEGACY_SCALE","LEGACY_SPEED","LEGACY_RADIAL","DRIVER_SCALE","DRIVER_STRETCH","DRIVER_ANGLE","DRIVER_SPEED","DRIVER_DETAIL","DRIVER_FLOW",
            "flow_strength","flow_center_x","flow_center_y","rgb_shift_amount","rgb_shift_angle","rgb_shift_units","rgb_shift_alpha","temporal_hold"
        ]
        for parameter in scalar_keys:
            mat.set_shader_parameter(parameter, float(state[parameter]))
        mat.set_shader_parameter("FIELD_CENTER", Vector2(float(state["FIELD_CENTER_X"]), float(state["FIELD_CENTER_Y"])))
        mat.set_shader_parameter("DRIVER_CENTER", Vector2(float(state["DRIVER_CENTER_X"]), float(state["DRIVER_CENTER_Y"])))
        mat.set_shader_parameter("fringe_color_a", state["col_a"])
        mat.set_shader_parameter("fringe_color_b", state["col_b"])
        mat.set_shader_parameter("custom_edge_mask_loaded", 1.0 if edge_mask != null else 0.0)
        if edge_mask != null:
            mat.set_shader_parameter("custom_edge_mask_tex", edge_mask)
        mat.set_shader_parameter("treatment_mask_loaded", 1.0 if treatment_mask != null else 0.0)
        if treatment_mask != null:
            mat.set_shader_parameter("treatment_mask_tex", treatment_mask)
    _update_summary()

func _apply_runtime_uniforms() -> void:
    var targets := _target_keys()
    for key in materials.keys():
        var mat: ShaderMaterial = materials[key]
        var active := targets.has(key) and not bypass_fx
        var node = slot_nodes.get(key)
        if texture_proxy_nodes.has(key):
            _update_texture_proxy_geometry(String(key))
        if node is TextureRect and node.texture != null:
            mat.set_shader_parameter("element_size", _presentation_size_for(node, node.texture))
        mat.set_shader_parameter("fx_time", shader_time)
        mat.set_shader_parameter("fx_dither", _effective_amount("dither") if active and bool(state["fx_on"]["dither"]) else 0.0)
        mat.set_shader_parameter("fx_fringe", _effective_amount("fringe") if active and bool(state["fx_on"]["fringe"]) else 0.0)
        mat.set_shader_parameter("fx_flow", _effective_amount("flow") if active and bool(state["fx_on"]["flow"]) else 0.0)
        mat.set_shader_parameter("fx_rgb", _effective_amount("rgb") if active and bool(state["fx_on"]["rgb"]) else 0.0)

func _effective_amount(fx: String) -> float:
    return float(runtime_amount[fx]) if bool(motion_enabled.get(fx,false)) else float(state["fx_amount"][fx])

# ---------------------------------------------------------------- motion/timeline
func _hold_start() -> float:
    if mode_format == "1v1":
        return float((timing_1v1.get("entry",{}) as Dictionary).get("hold_start",0.93))
    return float((mp_timing.get("shared",{}) as Dictionary).get("hold_start",0.88))

func _event_times() -> Dictionary:
    var out := {}
    if mode_format == "1v1":
        var entry: Dictionary = timing_1v1.get("entry",{})
        out["vs_enter"] = 0.0
        out["stage_reveal"] = float((entry.get("stage",{}) as Dictionary).get("start",0.0))
        out["fighter_reveal"] = float((entry.get("primaries",{}) as Dictionary).get("start",0.18))
        out["clash_impact"] = float(((entry.get("vs",{}) as Dictionary).get("impact_flash",{}) as Dictionary).get("center_time",0.615))
        out["hold_enter"] = float(entry.get("hold_start",0.93))
    else:
        var shared: Dictionary = mp_timing.get("shared",{})
        out["vs_enter"] = 0.0
        out["stage_reveal"] = float((shared.get("stage",[0.0,0.18]) as Array)[0])
        out["fighter_reveal"] = float((shared.get("primaries",[0.14,0.46]) as Array)[0])
        out["clash_impact"] = float((shared.get("vs",[0.52,0.66]) as Array)[1])
        out["hold_enter"] = float(shared.get("hold_start",0.88))
    return out

func _reset_runtime_amounts() -> void:
    motion_running.clear()
    motion_has_fired.clear()
    for fx in FX_NAMES:
        runtime_amount[fx] = 0.0 if bool(motion_enabled[fx]) else float(state["fx_amount"][fx])
        motion_has_fired[fx] = false

func _start_manual_motion(fx: String) -> void:
    if not bool(motion_enabled.get(fx,false)) or String(motion[fx]["anchor"]) != "manual":
        return
    motion_running[fx] = true
    motion_has_fired[fx] = true
    motion_t0[fx] = fx_time
    runtime_amount[fx] = 0.0

func _ease(p: float, curve: String) -> float:
    p = clampf(p,0.0,1.0)
    match curve:
        "linear": return p
        "cubic_in": return p*p*p
        "back_out":
            var c1 := 1.70158
            var c3 := c1 + 1.0
            return 1.0 + c3*pow(p-1.0,3.0) + c1*pow(p-1.0,2.0)
        "sine_in_out": return 0.5 - 0.5*cos(PI*p)
        _: return 1.0 - pow(1.0-p,3.0)

func _motion_value(fx: String, elapsed: float) -> float:
    var m: Dictionary = motion[fx]
    var delay := float(m["delay"])
    var attack := maxf(float(m["attack"]),0.001)
    var hold := maxf(float(m["hold"]),0.0)
    var release := maxf(float(m["release"]),0.001)
    var peak := float(state["fx_amount"][fx])
    var sustain := peak*clampf(float(m["sustain"]),0.0,1.0)
    var t := elapsed-delay
    if t < 0.0: return 0.0
    if t < attack: return peak*_ease(t/attack,String(m["attack_curve"]))
    t -= attack
    if t < hold: return peak
    t -= hold
    if t < release: return lerpf(peak,sustain,_ease(t/release,String(m["release_curve"])))
    return sustain

func _motion_finished(fx: String, elapsed: float) -> bool:
    var m: Dictionary = motion[fx]
    return elapsed >= float(m["delay"])+float(m["attack"])+float(m["hold"])+float(m["release"])

func _process(delta: float) -> void:
    fx_time += delta
    free_run_time += delta
    if source_mode == "LIVE SCREEN" and screen != null and screen.has_method("elapsed"):
        preview_t = float(screen.elapsed())
    else:
        if not transport_paused:
            study_presentation_time += delta
            if study_presentation_time > timeline_len:
                study_presentation_time = timeline_len
                _set_transport_paused(true)
        preview_t = study_presentation_time
    # Composition transport and procedural FX time are intentionally separate.
    # Park the VS frame, then select FREE RUN to keep animated Fringe moving.
    shader_time = free_run_time if time_source == "FREE RUN" else preview_t
    if viewport_host != null and disp != null:
        var available := viewport_host.size
        if available.x > 10.0 and available.y > 10.0:
            var scale_factor := minf(available.x/1280.0, available.y/720.0)
            disp.scale = Vector2(scale_factor,scale_factor)
            disp.position = (available-Vector2(1280,720)*scale_factor)*0.5
    _update_selection_outline()
    if transport_time_spin != null and not transport_syncing:
        transport_syncing = true
        transport_time_spin.set_value_no_signal(preview_t)
        transport_syncing = false

    for fx in FX_NAMES:
        if not bool(motion_enabled[fx]):
            runtime_amount[fx] = float(state["fx_amount"][fx])
            continue
        var anchor := String(motion[fx]["anchor"])
        if anchor != "manual":
            runtime_amount[fx] = _motion_value(fx, preview_t-float(event_marks.get(anchor,0.0)))
            continue
        if bool(motion_running.get(fx,false)):
            var elapsed := fx_time-float(motion_t0.get(fx,fx_time))
            runtime_amount[fx] = _motion_value(fx,elapsed)
            if _motion_finished(fx,elapsed):
                if motion_loop:
                    motion_t0[fx] = fx_time
                else:
                    motion_running[fx] = false
                    motion_has_fired[fx] = true
        else:
            var sustain := float(state["fx_amount"][fx])*clampf(float(motion[fx]["sustain"]),0.0,1.0)
            runtime_amount[fx] = sustain if bool(motion_has_fired.get(fx,false)) else 0.0
    _apply_runtime_uniforms()
    diagnostics_accum += delta
    fps_accum += delta
    if diagnostics_accum >= 0.12:
        diagnostics_accum = 0.0
        _update_summary()
    if fps_accum >= 0.25:
        fps_accum = 0.0
        if fps_label != null:
            fps_label.text = "FPS · %d" % Engine.get_frames_per_second()
    if history_pending:
        history_pending_elapsed += delta
        if history_pending_elapsed >= 0.18:
            _history_commit_current()
    if timeline_view != null:
        timeline_view.queue_redraw()

# ---------------------------------------------------------------- state / summary
func _set_state(key: String, value: Variant) -> void:
    # Signal posterize reads CONTINUOUS below one rendered step; snap tiny
    # non-zero values up so the control never reports POSTERIZE while the
    # pipeline is continuous.
    if key == "signal_posterize" and float(value) > 0.0 and float(value) < 1.5:
        value = 2.0
    state[key] = value
    _mark_dirty()
    _update_enabled_states()
    _apply_fx()

func _set_fx_on(fx: String, value: bool) -> void:
    state["fx_on"][fx] = value
    _mark_dirty()
    _update_enabled_states()
    _apply_fx()

func _set_fx_amount(fx: String, value: float) -> void:
    state["fx_amount"][fx] = value
    if not bool(motion_enabled[fx]):
        runtime_amount[fx] = value
    _mark_dirty()
    _apply_fx()

func _mark_dirty() -> void:
    if not suppress_dirty:
        dirty = true
        _queue_history_checkpoint()
    _update_preset_status()
    _refresh_header_status()
    _update_reset_buttons()

func _target_description() -> String:
    if target_mode == "ALL": return "TARGET · ALL TEXTURES"
    if target_mode == "ROLE": return "TARGET · ROLE · " + target_role
    return "TARGET · " + selected_slot.to_upper() + " · " + String(slot_roles.get(selected_slot,"OTHER TEXTURES"))

func _target_area(include_overscan := false) -> float:
    var area := 0.0
    var pad := _required_overscan_px() if include_overscan else 0.0
    for key in _target_keys():
        var node = slot_nodes.get(key)
        if node is TextureRect and node.texture != null:
            var ps := _presentation_size_for(node, node.texture)
            var draw_size := ps
            if include_overscan and _should_use_texture_proxy(String(key),node):
                draw_size += Vector2(pad*2.0,pad*2.0)
            # The canonical SubViewport clips anything outside 1280×720, while
            # overlapping target draw calls still accumulate cost independently.
            draw_size.x = minf(maxf(draw_size.x,0.0),1280.0)
            draw_size.y = minf(maxf(draw_size.y,0.0),720.0)
            area += draw_size.x*draw_size.y
    return maxf(area/(1280.0*720.0),0.02)

func _estimated_cost() -> Dictionary:
    var base_area := _target_area(false)
    var area := _target_area(true)
    if bypass_fx:
        return {"tier":"BYPASS", "area":area, "base_area":base_area, "score":0.0}
    var score := 0.0
    if bool(state["fx_on"]["dither"]) and not bool(state["pure_continuous"]): score += area*0.8
    if bool(state["fx_on"]["rgb"]): score += area*1.0
    if bool(state["fx_on"]["fringe"]):
        score += area*6.0
        if float(state["color_blur"]) > 0.01: score += area*4.0
        if bool(state["fx_on"]["flow"]):
            score += area*1.5
            if int(state["driver_mode"]) >= 2: score += area*3.0
    var tier := "CHEAP"
    if score >= 24.0: tier = "VERY HEAVY"
    elif score >= 12.0: tier = "HEAVY"
    elif score >= 5.0: tier = "MEDIUM"
    return {"tier":tier,"area":area,"base_area":base_area,"score":score}

func _update_summary() -> void:
    if processing_label == null: return
    var pure := bool(state["pure_continuous"])
    var base_desc := "COLOUR · opacity %.2f · grade %.2fx" % [float(state["base_opacity"]),float(state["base_grade_amount"])]
    if int(state["base_mode"]) == 1:
        if pure:
            base_desc = "COLOUR · opacity %.2f · MONO STAMP bypassed by PURE CONTINUOUS" % float(state["base_opacity"])
        else:
            base_desc = "MONO STAMP · opacity %.2f · %s %.1fpx · %s" % [float(state["base_opacity"]),DITHER_PATTERNS[int(state["mono_mode"])],float(state["mono_pixel"]),PATTERN_SPACES[int(state["mono_space"])]]
    var dither_desc := "NONE"
    if not pure and bool(state["fx_on"]["dither"]):
        dither_desc = "%s · %.1fpx · %s" % [DITHER_PATTERNS[int(state["dither_mode"])],float(state["dither_pixel"]),PATTERN_SPACES[int(state["dither_space"])]]
    var fringe_desc := "OFF"
    if bool(state["fx_on"]["fringe"]):
        var cov: String = "SMOOTH" if pure else FRINGE_COVERAGE[int(state["fringe_coverage_mode"])]
        fringe_desc = "%s · %s" % [EDGE_SOURCES[int(state["edge_source_mode"])], cov]
        if int(state["edge_source_mode"]) == 3:
            fringe_desc += " · " + (edge_mask_path.get_file() if edge_mask_path != "" else "MISSING→ALPHA")
    var flow_desc := "OFF"
    if not bool(state["fx_on"]["fringe"]):
        flow_desc = "N/A · FRINGE OFF"
    elif bool(state["fx_on"]["flow"]):
        var sampling := "CONTINUOUS" if pure or float(state["driver_sampling_mode"]) < 0.5 else "GRID %.1fpx" % float(state["driver_pixel_size"])
        flow_desc = "%s · %s" % [DRIVER_NAMES[int(state["driver_mode"])],sampling]
    var sig_desc := "CONTINUOUS" if pure or float(state["signal_posterize"]) < 1.5 else "POSTERIZE %.0f" % float(state["signal_posterize"])
    var time := "%s · %s" % [time_source, "CONTINUOUS" if pure or float(state["temporal_hold"]) < 0.01 else "HELD %.0f FPS" % float(state["temporal_hold"])]
    var mask_desc := "NONE"
    if bool(state["effect_mask_enabled"]):
        mask_desc = treatment_mask_path.get_file() if treatment_mask_path != "" else "ARMED · NO MASK"
    var guarantee := "[color=#79ebb9][b]PURE CONTINUOUS GUARANTEE[/b][/color]\n" if pure else ""
    var target_count := _target_keys().size()
    var target_warning := "[color=#ff5c6a][b]NO ACTIVE TARGETS[/b][/color]\n" if target_count == 0 else "[color=#79ebb9]ACTIVE TARGETS · %d[/color]\n" % target_count
    var spatial := _selected_spatial_readout()
    var overscan_desc := "Overscan: %.1f presentation px" % _required_overscan_px()
    processing_label.text = guarantee + target_warning + "[b]%s[/b]\n%s\n%s\nMaster: size %.2fx · intensity %.2fx · pattern %.2fx · edge %.2fpx\nPipeline: BASE → CHANNEL → QUANTIZE → EDGE\nBase: %s\nDither: %s · Fringe: %s\nFringe motion: %s\nSignal: %s · Time: %s\nTreatment mask: %s" % [_target_description(),spatial,overscan_desc,float(state["fx_size"]),float(state["fx_intensity"]),float(state["pattern_scale"]),float(state["edge_width"]),base_desc,dither_desc,fringe_desc,flow_desc,sig_desc,time,mask_desc]
    if target_label != null: target_label.text = _target_description()
    if cost_label != null:
        var cost := _estimated_cost()
        cost_label.text = "COST · %s · %.2fx draw" % [cost["tier"],float(cost["area"])]
        cost_label.tooltip_text = "Heuristic only · target footprint %.2fx screen before overscan, %.2fx including authored proxy padding. Use the runtime benchmark for real GPU cost." % [float(cost.get("base_area",cost["area"])),float(cost["area"])]

# ---------------------------------------------------------------- look history / clipboard
func _history_reset_to_current() -> void:
    look_history.clear()
    look_history.append(_snapshot())
    history_index = 0
    history_pending = false
    history_pending_elapsed = 0.0

func _queue_history_checkpoint() -> void:
    if history_restoring or suppress_dirty:
        return
    history_pending = true
    history_pending_elapsed = 0.0

func _history_commit_current() -> void:
    history_pending = false
    history_pending_elapsed = 0.0
    var snap := _snapshot()
    if history_index >= 0 and history_index < look_history.size() and look_history[history_index] == snap:
        return
    if history_index < look_history.size() - 1:
        look_history.resize(history_index + 1)
    look_history.append(snap)
    if look_history.size() > history_limit:
        look_history.pop_front()
    history_index = look_history.size() - 1

func _flush_history_pending() -> void:
    if history_pending:
        _history_commit_current()

func _dirty_against_loaded() -> bool:
    return loaded_look_snapshot.is_empty() or not (_snapshot() == loaded_look_snapshot)

func _restore_history_index(index: int) -> void:
    if index < 0 or index >= look_history.size():
        return
    history_restoring = true
    suppress_dirty = true
    _apply_snapshot(look_history[index])
    history_index = index
    dirty = _dirty_against_loaded()
    suppress_dirty = false
    history_restoring = false
    _update_preset_status()
    _refresh_header_status()
    _update_reset_buttons()
    status_label_text("history · %d/%d" % [history_index + 1, look_history.size()])

func _undo_look() -> void:
    _flush_history_pending()
    if history_index > 0:
        _restore_history_index(history_index - 1)
    else:
        status_label_text("undo · start of look history")

func _redo_look() -> void:
    _flush_history_pending()
    if history_index >= 0 and history_index < look_history.size() - 1:
        _restore_history_index(history_index + 1)
    else:
        status_label_text("redo · end of look history")

func _section_snapshot(section_id: String) -> Dictionary:
    var out := {"section":section_id,"state":{},"motion":{},"motion_enabled":{}}
    if section_id.begins_with("MOTION:"):
        var fx := section_id.trim_prefix("MOTION:")
        out["motion"][fx] = motion[fx].duplicate(true)
        out["motion_enabled"][fx] = motion_enabled[fx]
        return out
    if not SECTION_KEYS.has(section_id):
        return {}
    for token in SECTION_KEYS[section_id]:
        var item := String(token)
        if item.begins_with("fx_on:"):
            var fx_on := item.trim_prefix("fx_on:")
            out["state"]["fx_on:" + fx_on] = state["fx_on"][fx_on]
        elif item.begins_with("fx_amount:"):
            var fx_amount := item.trim_prefix("fx_amount:")
            out["state"]["fx_amount:" + fx_amount] = state["fx_amount"][fx_amount]
        elif item == "edge_mask_path":
            out["edge_mask_path"] = edge_mask_path
        elif item == "treatment_mask_path":
            out["treatment_mask_path"] = treatment_mask_path
        elif state.has(item):
            out["state"][item] = state[item]
    return out

func _copy_section(section_id: String) -> void:
    section_clipboard = _section_snapshot(section_id)
    section_clipboard_id = section_id
    status_label_text("copied section · " + section_id)

func _paste_section(section_id: String) -> void:
    if section_clipboard.is_empty() or section_clipboard_id != section_id:
        status_label_text("paste blocked · copy the same section first")
        return
    var incoming_state: Dictionary = section_clipboard.get("state",{})
    for key in incoming_state.keys():
        var token := String(key)
        if token.begins_with("fx_on:"):
            var fx_on := token.trim_prefix("fx_on:")
            state["fx_on"][fx_on] = incoming_state[key]
        elif token.begins_with("fx_amount:"):
            var fx_amount := token.trim_prefix("fx_amount:")
            state["fx_amount"][fx_amount] = incoming_state[key]
        elif state.has(token):
            state[token] = incoming_state[key]
    if section_clipboard.has("edge_mask_path"):
        edge_mask_path = str(section_clipboard["edge_mask_path"])
    if section_clipboard.has("treatment_mask_path"):
        treatment_mask_path = str(section_clipboard["treatment_mask_path"])
    var incoming_motion: Dictionary = section_clipboard.get("motion",{})
    for fx in incoming_motion.keys():
        motion[fx] = incoming_motion[fx].duplicate(true)
    var incoming_motion_enabled: Dictionary = section_clipboard.get("motion_enabled",{})
    for fx in incoming_motion_enabled.keys():
        motion_enabled[fx] = incoming_motion_enabled[fx]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()
    status_label_text("pasted section · " + section_id)

func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or event.echo:
        return
    # Hold B for a momentary before/after comparison without changing Look state.
    if event.keycode == KEY_B and not event.ctrl_pressed and not event.meta_pressed:
        bypass_fx = event.pressed
        _apply_fx()
        status_label_text("BYPASS · held" if event.pressed else "BYPASS · released")
        get_viewport().set_input_as_handled()
        return
    if not event.pressed:
        return
    var ctrl: bool = event.ctrl_pressed or event.meta_pressed
    if ctrl and event.keycode == KEY_Z and not event.shift_pressed:
        _undo_look()
        get_viewport().set_input_as_handled()
    elif ctrl and (event.keycode == KEY_Y or (event.keycode == KEY_Z and event.shift_pressed)):
        _redo_look()
        get_viewport().set_input_as_handled()
    elif ctrl and event.keycode == KEY_S and event.shift_pressed:
        _begin_save_as()
        get_viewport().set_input_as_handled()
    elif ctrl and event.keycode == KEY_S and not event.shift_pressed:
        _save_preset()
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_SPACE and not ctrl:
        _toggle_transport()
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_HOME and not ctrl:
        _transport_to_start()
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_LEFT and not ctrl:
        _transport_step_back()
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_RIGHT and not ctrl:
        _transport_step_forward()
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_F and not ctrl and source_mode == "ELEMENT STUDY":
        _study_fit()
        get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- presets
func _begin_save_as() -> void:
    if preset_name_edit == null:
        return
    preset_name_edit.grab_focus()
    preset_name_edit.select_all()
    status_label_text("SAVE AS · enter a new Look name, then SAVE")

func _look_schema_supported(schema_name: String) -> bool:
    return schema_name == LOOK_SCHEMA or LEGACY_LOOK_SCHEMAS.has(schema_name)

func _migrate_look_state(schema_name: String, incoming: Dictionary) -> Dictionary:
    # v0.3 introduces explicit presentation-space master controls and base
    # opacity. Legacy v0.2 looks are upgraded by merging onto factory defaults;
    # authored legacy values win, newly introduced parameters stay neutral.
    var migrated := _deep_merge(factory_state,incoming)
    if schema_name == "NRCU_FX_LOOK_V0_2":
        if not incoming.has("fx_size"): migrated["fx_size"] = 1.0
        if not incoming.has("fx_intensity"): migrated["fx_intensity"] = 1.0
        if not incoming.has("pattern_scale"): migrated["pattern_scale"] = 1.0
        if not incoming.has("edge_width"): migrated["edge_width"] = 3.0
        if not incoming.has("base_opacity"): migrated["base_opacity"] = 1.0
        # Legacy Source Pixel Grid was explicitly source-resolution based.
        # Preserve that authored intent; new v0.3 looks default to presentation px.
        if not incoming.has("source_pixel_units"): migrated["source_pixel_units"] = 0.0
        # Legacy MONO STAMP borrowed Colour Dither's pattern controls. Preserve
        # that appearance while migrating into the new independent Base domain.
        migrated["mono_threshold"] = float(incoming.get("dither_threshold",0.75))
        migrated["mono_mode"] = float(incoming.get("dither_mode",1.0))
        migrated["mono_bayer_level"] = float(incoming.get("dither_bayer_level",2.0))
        migrated["mono_pixel"] = float(incoming.get("dither_pixel",2.0))
        migrated["mono_space"] = float(incoming.get("dither_space",1.0))
        # The R2 authoring surface already described geometry/rgb in display
        # pixels; preserve that intent explicitly in the new schema.
        migrated["geometry_units"] = float(incoming.get("geometry_units",1.0))
        migrated["rgb_shift_units"] = float(incoming.get("rgb_shift_units",1.0))
    return migrated

func _deep_merge(base: Dictionary, incoming: Dictionary) -> Dictionary:
    var result := base.duplicate(true)
    for key in incoming.keys():
        if not result.has(key): continue
        if result[key] is Dictionary and incoming[key] is Dictionary:
            result[key] = _deep_merge(result[key],incoming[key])
        else:
            result[key] = incoming[key]
    return result

func _save_preset() -> void:
    var name := preset_name_edit.text.strip_edges()
    if name == "": name = "LOOK_001"
    var cfg := ConfigFile.new()
    cfg.load(PRESET_PATH)
    cfg.set_value(name,"schema",LOOK_SCHEMA)
    cfg.set_value(name,"state",state.duplicate(true))
    cfg.set_value(name,"motion",motion.duplicate(true))
    cfg.set_value(name,"motion_enabled",motion_enabled.duplicate(true))
    cfg.set_value(name,"edge_mask_path",edge_mask_path)
    cfg.set_value(name,"treatment_mask_path",treatment_mask_path)
    cfg.set_value(name,"time_source",time_source)
    if cfg.save(PRESET_PATH) == OK:
        current_preset_name = name
        dirty = false
        loaded_look_name = name
        loaded_look_is_production = false
        loaded_look_snapshot = _snapshot()
        _refresh_preset_list(name)
        _flush_history_pending()
        _update_preset_status("Saved · "+name)
        _refresh_header_status()

func _load_preset() -> void:
    if preset_picker == null or preset_picker.disabled: return
    var name := preset_picker.get_item_text(preset_picker.selected)
    var cfg := ConfigFile.new()
    if cfg.load(PRESET_PATH) != OK or not cfg.has_section(name): return
    var schema_name := str(cfg.get_value(name,"schema",""))
    if not _look_schema_supported(schema_name):
        _update_preset_status("Blocked · incompatible schema")
        return
    suppress_dirty = true
    state = _migrate_look_state(schema_name,cfg.get_value(name,"state",{}))
    motion = _deep_merge(motion,cfg.get_value(name,"motion",{}))
    motion_enabled = _deep_merge(motion_enabled,cfg.get_value(name,"motion_enabled",{}))
    edge_mask_path = str(cfg.get_value(name,"edge_mask_path",edge_mask_path))
    treatment_mask_path = str(cfg.get_value(name,"treatment_mask_path",treatment_mask_path))
    time_source = str(cfg.get_value(name,"time_source",time_source))
    if not TIME_SOURCES.has(time_source):
        time_source = TIME_SOURCES[0]
    current_preset_name = name
    dirty = false
    _normalize_target()
    _reset_runtime_amounts()
    _sync_controls()
    _apply_fx()
    suppress_dirty = false
    loaded_look_name = name
    loaded_look_is_production = false
    loaded_look_snapshot = _snapshot()
    _history_reset_to_current()
    _update_preset_status("Loaded · "+name)
    _refresh_header_status()

func _delete_preset() -> void:
    if preset_picker == null or preset_picker.disabled: return
    var name := preset_picker.get_item_text(preset_picker.selected)
    var cfg := ConfigFile.new()
    if cfg.load(PRESET_PATH) != OK: return
    cfg.erase_section(name)
    cfg.save(PRESET_PATH)
    if current_preset_name == name:
        current_preset_name = ""
        loaded_look_name = ""
        loaded_look_is_production = false
        loaded_look_snapshot = {}
    _refresh_preset_list()
    _update_preset_status("Deleted · "+name)

func _json_state() -> Dictionary:
    var result := state.duplicate(true)
    for key in ["col_a","col_b"]:
        var c: Color = result[key]
        result[key] = [c.r,c.g,c.b,c.a]
    return result

func _export_json() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
    var name := preset_name_edit.text.strip_edges()
    if name == "": name = "LOOK_EXPORT"
    var payload := {"schema":LOOK_SCHEMA,"name":name,"time_source":time_source,"state":_json_state(),"motion":motion,"motion_enabled":motion_enabled,"edge_mask_path":edge_mask_path,"treatment_mask_path":treatment_mask_path,"preview_context":{"source_mode":source_mode,"format":mode_format,"stage":stage_id,"fighters":[pick_l,pick_r,pick_extra[0],pick_extra[1]],"target":{"mode":target_mode,"role":target_role,"slot":selected_slot}}}
    var path := EXPORT_DIR.path_join(name.validate_filename()+".json")
    var f := FileAccess.open(path,FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(payload,"  "))
        _update_preset_status("Exported · "+path)

func _import_json(path: String) -> void:
    var f := FileAccess.open(path,FileAccess.READ)
    if f == null: return
    var parsed = JSON.parse_string(f.get_as_text())
    if not (parsed is Dictionary):
        _update_preset_status("Import blocked · invalid JSON")
        return
    var schema_name := str(parsed.get("schema",""))
    if not _look_schema_supported(schema_name):
        _update_preset_status("Import blocked · schema mismatch")
        return
    suppress_dirty = true
    var incoming_ts := str(parsed.get("time_source", ""))
    if TIME_SOURCES.has(incoming_ts):
        time_source = incoming_ts
    var incoming: Dictionary = parsed.get("state",{})
    for key in ["col_a","col_b"]:
        if incoming.has(key) and incoming[key] is Array:
            var a: Array = incoming[key]
            if a.size() >= 3: incoming[key] = Color(float(a[0]),float(a[1]),float(a[2]),float(a[3]) if a.size()>3 else 1.0)
    state = _migrate_look_state(schema_name,incoming)
    motion = _deep_merge(motion,parsed.get("motion",{}))
    motion_enabled = _deep_merge(motion_enabled,parsed.get("motion_enabled",{}))
    edge_mask_path = str(parsed.get("edge_mask_path",edge_mask_path))
    treatment_mask_path = str(parsed.get("treatment_mask_path",treatment_mask_path))
    current_preset_name = str(parsed.get("name",path.get_file().get_basename()))
    dirty = true
    _normalize_target()
    _reset_runtime_amounts()
    _sync_controls()
    _apply_fx()
    suppress_dirty = false
    loaded_look_name = current_preset_name
    loaded_look_is_production = false
    loaded_look_snapshot = _snapshot()
    _history_reset_to_current()
    _update_preset_status(("Imported + migrated · " if schema_name != LOOK_SCHEMA else "Imported · ")+current_preset_name)
    _refresh_header_status()

func _refresh_preset_list(select_name := "") -> void:
    if preset_picker == null: return
    preset_picker.clear()
    var cfg := ConfigFile.new()
    if cfg.load(PRESET_PATH) != OK or cfg.get_sections().is_empty():
        preset_picker.add_item("No saved looks")
        preset_picker.disabled = true
        return
    preset_picker.disabled = false
    var sections := cfg.get_sections()
    var idx := 0
    for i in range(sections.size()):
        preset_picker.add_item(sections[i])
        if sections[i] == select_name: idx = i
    preset_picker.select(idx)

func _update_preset_status(message := "") -> void:
    if preset_status_label == null: return
    if message != "": preset_status_label.text = message
    elif dirty: preset_status_label.text = "UNSAVED · " + (current_preset_name if current_preset_name!="" else "new look")
    elif current_preset_name != "": preset_status_label.text = "LOADED · "+current_preset_name
    else: preset_status_label.text = "No look loaded"

func _snapshot() -> Dictionary:
    return {"state":state.duplicate(true),"motion":motion.duplicate(true),"motion_enabled":motion_enabled.duplicate(true),"edge_mask_path":edge_mask_path,"treatment_mask_path":treatment_mask_path,"time_source":time_source}

func _apply_snapshot(snap: Dictionary) -> void:
    if snap.is_empty(): return
    state = snap["state"].duplicate(true)
    motion = snap["motion"].duplicate(true)
    motion_enabled = snap["motion_enabled"].duplicate(true)
    edge_mask_path = str(snap["edge_mask_path"])
    treatment_mask_path = str(snap["treatment_mask_path"])
    time_source = str(snap.get("time_source", time_source))
    dirty = true
    _reset_runtime_amounts()
    _sync_controls()
    _apply_fx()
    _refresh_header_status()

func _variants_equal(a: Variant, b: Variant) -> bool:
    var type_a := typeof(a)
    var type_b := typeof(b)
    var a_is_number := type_a == TYPE_FLOAT or type_a == TYPE_INT
    var b_is_number := type_b == TYPE_FLOAT or type_b == TYPE_INT
    if a_is_number and b_is_number:
        return is_equal_approx(float(a), float(b))
    return a == b

func _reset_key_is_default(key: String) -> bool:
    if key == "time_source":
        return time_source == TIME_SOURCES[0]
    if key == "edge_mask_path":
        return edge_mask_path == ""
    if key == "treatment_mask_path":
        return treatment_mask_path == ""
    if key.begins_with("fx_on_"):
        var fx_on_name := key.trim_prefix("fx_on_")
        return bool(state["fx_on"][fx_on_name]) == bool(factory_state["fx_on"][fx_on_name])
    if key.begins_with("fx_amount_"):
        var fx_amount_name := key.trim_prefix("fx_amount_")
        return _variants_equal(state["fx_amount"][fx_amount_name], factory_state["fx_amount"][fx_amount_name])
    if key.begins_with("motion_enabled_"):
        var motion_enabled_name := key.trim_prefix("motion_enabled_")
        return bool(motion_enabled[motion_enabled_name]) == bool(factory_motion_enabled[motion_enabled_name])
    if key.begins_with("motion_"):
        for motion_fx_name in FX_NAMES:
            var motion_prefix: String = "motion_" + motion_fx_name + "_"
            if key.begins_with(motion_prefix):
                var motion_parameter := key.trim_prefix(motion_prefix)
                return _variants_equal(motion[motion_fx_name][motion_parameter], factory_motion[motion_fx_name][motion_parameter])
    if factory_state.has(key) and state.has(key):
        return _variants_equal(state[key], factory_state[key])
    return true

func _section_is_default(section_id: String) -> bool:
    if section_id.begins_with("MOTION:"):
        var motion_section_fx := section_id.trim_prefix("MOTION:")
        if bool(motion_enabled[motion_section_fx]) != bool(factory_motion_enabled[motion_section_fx]):
            return false
        for key in factory_motion[motion_section_fx].keys():
            if not _variants_equal(motion[motion_section_fx][key], factory_motion[motion_section_fx][key]):
                return false
        return true
    if not SECTION_KEYS.has(section_id):
        return true
    for token in SECTION_KEYS[section_id]:
        var item := String(token)
        if item.begins_with("fx_on:"):
            var section_fx_on := item.trim_prefix("fx_on:")
            if bool(state["fx_on"][section_fx_on]) != bool(factory_state["fx_on"][section_fx_on]):
                return false
        elif item.begins_with("fx_amount:"):
            var section_fx_amount := item.trim_prefix("fx_amount:")
            if not _variants_equal(state["fx_amount"][section_fx_amount], factory_state["fx_amount"][section_fx_amount]):
                return false
        elif item == "edge_mask_path" and edge_mask_path != "":
            return false
        elif item == "treatment_mask_path" and treatment_mask_path != "":
            return false
        elif state.has(item) and not _variants_equal(state[item], factory_state[item]):
            return false
    return true

func _section_modified_count(section_id: String) -> int:
    var count := 0
    if section_id.begins_with("MOTION:"):
        var fx := section_id.trim_prefix("MOTION:")
        if bool(motion_enabled[fx]) != bool(factory_motion_enabled[fx]):
            count += 1
        for key in factory_motion[fx].keys():
            if not _variants_equal(motion[fx][key],factory_motion[fx][key]):
                count += 1
        return count
    if not SECTION_KEYS.has(section_id):
        return 0
    for token in SECTION_KEYS[section_id]:
        var item := String(token)
        if item.begins_with("fx_on:"):
            var fx_on := item.trim_prefix("fx_on:")
            if bool(state["fx_on"][fx_on]) != bool(factory_state["fx_on"][fx_on]): count += 1
        elif item.begins_with("fx_amount:"):
            var fx_amount := item.trim_prefix("fx_amount:")
            if not _variants_equal(state["fx_amount"][fx_amount],factory_state["fx_amount"][fx_amount]): count += 1
        elif item == "edge_mask_path":
            if edge_mask_path != "": count += 1
        elif item == "treatment_mask_path":
            if treatment_mask_path != "": count += 1
        elif state.has(item) and not _variants_equal(state[item],factory_state[item]):
            count += 1
    return count

func _update_reset_buttons() -> void:
    for key in reset_buttons.keys():
        var button = reset_buttons[key]
        if button is Button:
            var is_default := _reset_key_is_default(String(key))
            button.disabled = is_default
            button.text = "↺" if is_default else "↺*"
            button.tooltip_text = "Factory default" if is_default else "Modified from factory · reset only this setting"
    for section_id in section_reset_buttons.keys():
        var button = section_reset_buttons[section_id]
        if button is Button:
            var count := _section_modified_count(String(section_id))
            button.disabled = count == 0
            button.text = "RESET SECTION" if count == 0 else "RESET SECTION · %d" % count
        _refresh_section_header(String(section_id))

func _reset_state_key(key: String) -> void:
    if not factory_state.has(key):
        return
    state[key] = factory_state[key]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_fx_on(fx: String) -> void:
    state["fx_on"][fx] = factory_state["fx_on"][fx]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_fx_amount(fx: String) -> void:
    state["fx_amount"][fx] = factory_state["fx_amount"][fx]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_motion_value(fx: String, key: String) -> void:
    motion[fx][key] = factory_motion[fx][key]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_motion_enabled(fx: String) -> void:
    motion_enabled[fx] = factory_motion_enabled[fx]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_time_source() -> void:
    time_source = TIME_SOURCES[0]
    _sync_controls()
    _mark_dirty()
    _update_summary()

func _reset_edge_mask_path() -> void:
    edge_mask_path = ""
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_treatment_mask_path() -> void:
    treatment_mask_path = ""
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _reset_section(section_id: String) -> void:
    if section_id.begins_with("MOTION:"):
        var motion_fx := section_id.trim_prefix("MOTION:")
        motion[motion_fx] = factory_motion[motion_fx].duplicate(true)
        motion_enabled[motion_fx] = factory_motion_enabled[motion_fx]
    elif SECTION_KEYS.has(section_id):
        for token in SECTION_KEYS[section_id]:
            var item := String(token)
            if item.begins_with("fx_on:"):
                var fx_on := item.trim_prefix("fx_on:")
                state["fx_on"][fx_on] = factory_state["fx_on"][fx_on]
            elif item.begins_with("fx_amount:"):
                var fx_amount := item.trim_prefix("fx_amount:")
                state["fx_amount"][fx_amount] = factory_state["fx_amount"][fx_amount]
            elif item == "edge_mask_path":
                edge_mask_path = ""
            elif item == "treatment_mask_path":
                treatment_mask_path = ""
            elif factory_state.has(item):
                state[item] = factory_state[item]
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()
    status_label_text("reset section · " + section_id)

func _revert_look() -> void:
    if loaded_look_snapshot.is_empty():
        status_label_text("revert unavailable · no saved/loaded look snapshot")
        return
    suppress_dirty = true
    _apply_snapshot(loaded_look_snapshot)
    current_preset_name = loaded_look_name
    dirty = false
    suppress_dirty = false
    _update_preset_status("Reverted · " + loaded_look_name)
    _refresh_header_status()
    _update_reset_buttons()

func _reset_look() -> void:
    state = factory_state.duplicate(true)
    motion = factory_motion.duplicate(true)
    motion_enabled = factory_motion_enabled.duplicate(true)
    time_source = TIME_SOURCES[0]
    current_preset_name = ""
    loaded_look_is_production = false
    dirty = true
    _reset_runtime_amounts()
    _sync_controls()
    _apply_fx()
    _refresh_header_status()
    _update_preset_status("Factory look restored")

# ---------------------------------------------------------------- production looks / assignments
func _production_default_looks() -> Dictionary:
    return {"schema":PRODUCTION_LOOKS_SCHEMA,"looks":{}}

func _production_default_assignments() -> Dictionary:
    return {"schema":PRODUCTION_ASSIGNMENTS_SCHEMA,"bindings":[]}

func _read_production_doc(path: String, expected_schema: String, fallback: Dictionary) -> Dictionary:
    var doc := _load_json(path)
    if doc.is_empty():
        return fallback.duplicate(true)
    if str(doc.get("schema","")) != expected_schema:
        status_label_text("production file schema mismatch · " + path.get_file())
        return fallback.duplicate(true)
    return doc

func _write_production_doc(path: String, payload: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRODUCTION_FX_DIR))
    var absolute_path := ProjectSettings.globalize_path(path)
    var file := FileAccess.open(absolute_path, FileAccess.WRITE)
    if file == null:
        status_label_text("production write failed · " + absolute_path)
        return false
    file.store_string(JSON.stringify(payload,"  "))
    return true

func _production_look_id() -> String:
    var raw := ""
    if preset_name_edit != null:
        raw = preset_name_edit.text.strip_edges()
    if raw == "":
        raw = current_preset_name
    if raw == "":
        return ""
    var result := raw.to_upper().replace(" ","_").replace("-","_")
    return result.validate_filename()

func _production_look_payload() -> Dictionary:
    return {
        "status":"PRODUCTION",
        "look_schema":LOOK_SCHEMA,
        "state":_json_state(),
        "motion":motion.duplicate(true),
        "motion_enabled":motion_enabled.duplicate(true),
        "time_source":time_source,
        "edge_mask_path":edge_mask_path,
        "treatment_mask_path":treatment_mask_path
    }

func _publish_current_look() -> bool:
    var look_id := _production_look_id()
    if look_id == "":
        status_label_text("publish blocked · give the look a name first")
        return false
    var doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
    var looks: Dictionary = doc.get("looks",{})
    looks[look_id] = _production_look_payload()
    doc["looks"] = looks
    if not _write_production_doc(PRODUCTION_LOOKS_PATH,doc):
        return false
    current_preset_name = look_id
    loaded_look_name = look_id
    loaded_look_is_production = true
    dirty = false
    loaded_look_snapshot = _snapshot()
    if preset_name_edit != null:
        preset_name_edit.text = look_id
    _update_preset_status("Published · " + look_id)
    _refresh_header_status()
    status_label_text("published production look · " + look_id)
    _refresh_assignment_view()
    return true

func _fighter_from_target_node(node: Variant) -> String:
    if not (node is TextureRect) or node.texture == null:
        return ""
    var path := String(node.texture.resource_path)
    var parts := path.split("/")
    for i in range(parts.size() - 1):
        if parts[i] == "fighters":
            return String(parts[i + 1])
    return ""

func _role_id(role: String) -> String:
    match role:
        "VS MARK": return "vs_mark"
        "PRIMARIES": return "primary"
        "ECHOES": return "echo"
        "NAMES": return "name"
        "STAGE": return "stage"
        "SIDE FIELDS": return "side_field"
        "NAME PLATES": return "name_plate"
        "ACCENT LINES": return "accent_line"
        _: return role.to_snake_case()

func _presentation_slot_from_key(key: String) -> String:
    # Resolve against the actual layout schema instead of assuming only duel/FFA
    # left/right names. Team families use slots such as A_back and B_solo.
    var candidates: Array[String] = ["left_outer","right_outer","left_inner","right_inner","center","left","right"]
    var families: Dictionary = multiplayer_layouts.get("families",{})
    for family in families.values():
        if not (family is Dictionary):
            continue
        var slots: Dictionary = family.get("slots",{})
        for raw_slot in slots.keys():
            var slot := str(raw_slot).to_lower()
            if not candidates.has(slot):
                candidates.append(slot)
    candidates.sort_custom(func(a: String,b: String): return a.length() > b.length())
    var normalized := key.to_lower()
    for candidate in candidates:
        if normalized == candidate or normalized.begins_with(candidate + "_") or normalized.contains("_" + candidate + "_") or normalized.ends_with("_" + candidate):
            return candidate
    return ""

func _visual_side_for_slot(slot: String) -> String:
    if slot == "":
        return ""
    if slot in ["left","right","center"]:
        return slot
    var family_spec: Dictionary = (multiplayer_layouts.get("families",{}) as Dictionary).get(mode_format,{})
    var slot_spec: Dictionary = (family_spec.get("slots",{}) as Dictionary).get(slot,{})
    var side := str(slot_spec.get("side", "")).to_lower()
    return side if side in ["left","right","center"] else ""

func _team_side_for_slot(slot: String) -> String:
    if not mode_format.begins_with("TEAM_"):
        return ""
    if slot.begins_with("a_"):
        return "A"
    if slot.begins_with("b_"):
        return "B"
    return ""

func _current_target_context() -> Dictionary:
    var context := {"mode_family":mode_format,"stage_id":stage_id}
    var keys := _target_keys()
    if keys.size() == 1:
        var key := String(keys[0])
        var role := String(slot_roles.get(key,"OTHER TEXTURES"))
        var node = slot_nodes.get(key)
        context["target_key"] = key
        context["element_role"] = _role_id(role)
        var fighter_id := str(node.get_meta("fx_fighter_id","")) if node is Node else ""
        if fighter_id == "":
            fighter_id = _fighter_from_target_node(node)
        if fighter_id != "":
            context["fighter_id"] = fighter_id
        var presentation_slot := _presentation_slot_from_key(key)
        if presentation_slot != "":
            context["presentation_slot"] = presentation_slot
            var visual_side := _visual_side_for_slot(presentation_slot)
            if visual_side != "":
                context["visual_side"] = visual_side
            var team_side := _team_side_for_slot(presentation_slot)
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
    elif target_mode == "ROLE":
        context["element_role"] = _role_id(target_role)
    return context

func _selector_for_scope(scope: String) -> Dictionary:
    var context := _current_target_context()
    var selector := {}
    match scope:
        "ROLE ONLY":
            if context.has("element_role"):
                selector["element_role"] = context["element_role"]
        "FIGHTER + ROLE + VISUAL SIDE":
            if context.has("fighter_id") and context.has("element_role") and context.has("visual_side"):
                selector["fighter_id"] = context["fighter_id"]
                selector["element_role"] = context["element_role"]
                selector["visual_side"] = context["visual_side"]
        "FIGHTER + ROLE":
            if context.has("fighter_id") and context.has("element_role"):
                selector["fighter_id"] = context["fighter_id"]
                selector["element_role"] = context["element_role"]
        "ROLE + VISUAL SIDE":
            if context.has("element_role") and context.has("visual_side"):
                selector["element_role"] = context["element_role"]
                selector["visual_side"] = context["visual_side"]
        "STATIC ELEMENT":
            if context.has("element_id"):
                selector["element_id"] = context["element_id"]
                if context["element_id"] == "stage":
                    selector["stage_id"] = stage_id
        _:
            if context.has("element_id"):
                selector["element_id"] = context["element_id"]
            if context.has("fighter_id"):
                selector["fighter_id"] = context["fighter_id"]
            if context.has("element_role"):
                selector["element_role"] = context["element_role"]
            if context.has("presentation_slot"):
                selector["presentation_slot"] = context["presentation_slot"]
            if context.has("visual_side"):
                selector["visual_side"] = context["visual_side"]
            if context.has("team_side"):
                selector["team_side"] = context["team_side"]
            selector["mode_family"] = mode_format
            if context.get("element_id","") == "stage":
                selector["stage_id"] = stage_id
    return selector

func _selector_key(selector: Dictionary) -> String:
    var keys := selector.keys()
    keys.sort()
    var parts: Array[String] = []
    for key in keys:
        parts.append(String(key) + "=" + str(selector[key]))
    return "|".join(parts)

func _selector_matches(selector: Dictionary, context: Dictionary) -> bool:
    return StyleRegistry.selector_matches(selector,context)

func _selector_score(selector: Dictionary) -> int:
    return StyleRegistry.selector_score(selector)

func _resolve_assignment(context: Dictionary) -> Dictionary:
    var doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    return StyleRegistry.resolve_binding(doc,context)

func _duplicate_production_look() -> void:
    var source_id := loaded_look_name if loaded_look_is_production else ""
    var target_id := _production_look_id()
    if source_id == "":
        status_label_text("duplicate blocked · load a production look first")
        return
    if target_id == "" or target_id == source_id:
        status_label_text("duplicate blocked · enter a different target look name")
        return
    var doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
    var looks: Dictionary = doc.get("looks",{})
    if not looks.has(source_id):
        status_label_text("duplicate blocked · source production look missing")
        return
    if looks.has(target_id):
        status_label_text("duplicate blocked · target production look already exists")
        return
    looks[target_id] = (looks[source_id] as Dictionary).duplicate(true)
    doc["looks"] = looks
    if _write_production_doc(PRODUCTION_LOOKS_PATH,doc):
        current_preset_name = target_id
        loaded_look_name = target_id
        loaded_look_is_production = true
        dirty = false
        loaded_look_snapshot = _snapshot()
        if preset_name_edit != null:
            preset_name_edit.text = target_id
        _update_preset_status("Duplicated production look · " + target_id)
        _refresh_header_status()
        _refresh_assignment_view()

func _rename_production_look() -> void:
    var source_id := loaded_look_name if loaded_look_is_production else ""
    var target_id := _production_look_id()
    if source_id == "":
        status_label_text("rename blocked · load a production look first")
        return
    if target_id == "" or target_id == source_id:
        status_label_text("rename blocked · enter a different target look name")
        return
    var looks_doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
    var looks: Dictionary = looks_doc.get("looks",{})
    if not looks.has(source_id):
        status_label_text("rename blocked · source production look missing")
        return
    if looks.has(target_id):
        status_label_text("rename blocked · target production look already exists")
        return
    looks[target_id] = (looks[source_id] as Dictionary).duplicate(true)
    looks.erase(source_id)
    looks_doc["looks"] = looks
    var assignments_doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var bindings: Array = assignments_doc.get("bindings",[])
    for i in range(bindings.size()):
        var item = bindings[i]
        if item is Dictionary and str(item.get("look_id","")) == source_id:
            item["look_id"] = target_id
            bindings[i] = item
    assignments_doc["bindings"] = bindings
    if not _write_production_doc(PRODUCTION_LOOKS_PATH,looks_doc):
        return
    if not _write_production_doc(PRODUCTION_ASSIGNMENTS_PATH,assignments_doc):
        status_label_text("rename incomplete · look renamed but assignment write failed")
        return
    current_preset_name = target_id
    loaded_look_name = target_id
    loaded_look_is_production = true
    dirty = false
    loaded_look_snapshot = _snapshot()
    if preset_name_edit != null:
        preset_name_edit.text = target_id
    _update_preset_status("Renamed production look · " + source_id + " → " + target_id)
    _refresh_header_status()
    _refresh_assignment_view()

func _assign_current_look() -> void:
    var look_id := _production_look_id()
    if look_id == "":
        status_label_text("assign blocked · name the look first")
        return
    if not _publish_current_look():
        status_label_text("assign blocked · production Look could not be published")
        return
    var scope: String = ASSIGNMENT_SCOPES[assignment_scope_picker.selected] if assignment_scope_picker != null else ASSIGNMENT_SCOPES[0]
    var selector := _selector_for_scope(scope)
    if selector.is_empty():
        status_label_text("assign blocked · current target cannot satisfy " + scope)
        return
    var doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var bindings: Array = doc.get("bindings",[])
    var selector_key := _selector_key(selector)
    var replaced := false
    for i in range(bindings.size()):
        var item = bindings[i]
        if item is Dictionary and _selector_key(item.get("selector",{})) == selector_key:
            bindings[i] = {"selector":selector,"look_id":look_id}
            replaced = true
            break
    if not replaced:
        bindings.append({"selector":selector,"look_id":look_id})
    doc["bindings"] = bindings
    if _write_production_doc(PRODUCTION_ASSIGNMENTS_PATH,doc):
        status_label_text("assigned · " + look_id + " → " + selector_key)
        _refresh_assignment_view()

func _unassign_current() -> void:
    var scope: String = ASSIGNMENT_SCOPES[assignment_scope_picker.selected] if assignment_scope_picker != null else ASSIGNMENT_SCOPES[0]
    var selector := _selector_for_scope(scope)
    if selector.is_empty():
        status_label_text("unassign blocked · no selector")
        return
    var doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var key := _selector_key(selector)
    var filtered: Array = []
    for item in doc.get("bindings",[]):
        if item is Dictionary and _selector_key(item.get("selector",{})) == key:
            continue
        filtered.append(item)
    doc["bindings"] = filtered
    if _write_production_doc(PRODUCTION_ASSIGNMENTS_PATH,doc):
        status_label_text("unassigned · " + key)
        _refresh_assignment_view()

func _decode_json_state(incoming: Dictionary) -> Dictionary:
    var decoded := incoming.duplicate(true)
    for key in ["col_a","col_b"]:
        if decoded.has(key) and decoded[key] is Array:
            var values: Array = decoded[key]
            if values.size() >= 3:
                decoded[key] = Color(float(values[0]),float(values[1]),float(values[2]),float(values[3]) if values.size() > 3 else 1.0)
    return decoded

func _apply_production_look(look_id: String) -> bool:
    var doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
    var looks: Dictionary = doc.get("looks",{})
    if not looks.has(look_id):
        status_label_text("production look missing · " + look_id)
        return false
    var payload: Dictionary = looks[look_id]
    var payload_schema := str(payload.get("look_schema",LOOK_SCHEMA))
    if not _look_schema_supported(payload_schema):
        status_label_text("production look schema unsupported · " + payload_schema)
        return false
    suppress_dirty = true
    state = _migrate_look_state(payload_schema,_decode_json_state(payload.get("state",{})))
    motion = _deep_merge(motion,payload.get("motion",{}))
    motion_enabled = _deep_merge(motion_enabled,payload.get("motion_enabled",{}))
    time_source = str(payload.get("time_source",time_source))
    edge_mask_path = str(payload.get("edge_mask_path",edge_mask_path))
    treatment_mask_path = str(payload.get("treatment_mask_path",treatment_mask_path))
    current_preset_name = look_id
    loaded_look_name = look_id
    loaded_look_is_production = true
    _reset_runtime_amounts()
    _sync_controls()
    _apply_fx()
    loaded_look_snapshot = _snapshot()
    dirty = false
    suppress_dirty = false
    _history_reset_to_current()
    _update_preset_status("Production · " + look_id)
    _refresh_header_status()
    return true

func _load_resolved_assignment() -> void:
    var resolved := _resolve_assignment(_current_target_context())
    if resolved.is_empty():
        status_label_text("no production assignment resolves for current target")
        return
    _apply_production_look(str(resolved.get("look_id","")))
    _refresh_assignment_view()

func _selected_production_look_id() -> String:
    if production_look_picker == null or production_look_picker.selected < 0 or production_look_picker.selected >= production_look_ids.size():
        return ""
    return production_look_ids[production_look_picker.selected]

func _load_selected_production_look() -> void:
    var look_id := _selected_production_look_id()
    if look_id == "":
        status_label_text("no production Look selected")
        return
    _apply_production_look(look_id)
    _refresh_assignment_view()

func _delete_selected_production_look() -> void:
    var look_id := _selected_production_look_id()
    if look_id == "":
        status_label_text("delete blocked · no production Look selected")
        return
    var assignments_doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var references := 0
    for item in assignments_doc.get("bindings",[]):
        if item is Dictionary and str(item.get("look_id","")) == look_id:
            references += 1
    if references > 0:
        status_label_text("delete blocked · %s is referenced by %d binding(s)" % [look_id,references])
        return
    var looks_doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
    var looks: Dictionary = looks_doc.get("looks",{})
    if not looks.has(look_id):
        status_label_text("delete blocked · production Look missing")
        return
    looks.erase(look_id)
    looks_doc["looks"] = looks
    if _write_production_doc(PRODUCTION_LOOKS_PATH,looks_doc):
        if loaded_look_is_production and loaded_look_name == look_id:
            loaded_look_is_production = false
            loaded_look_name = ""
            current_preset_name = ""
            dirty = true
            _refresh_header_status()
        status_label_text("deleted production Look · " + look_id)
        _refresh_assignment_view()

func _on_assignment_filter_changed(_index: int) -> void:
    _refresh_assignment_view()

func _binding_display(item: Dictionary, context: Dictionary, winner_key := "") -> String:
    var selector: Dictionary = item.get("selector",{})
    var matches := StyleRegistry.selector_matches(selector,context)
    var key := _selector_key(selector)
    var prefix := "★ " if matches and key == winner_key else "✓ " if matches else "  "
    return "%s[%03d] %s → %s" % [prefix,StyleRegistry.selector_score(selector),key,str(item.get("look_id",""))]

func _refresh_production_browsers(context: Dictionary, bindings: Array, resolved: Dictionary) -> void:
    if production_look_picker != null:
        var keep_look := _selected_production_look_id()
        var looks_doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
        var looks: Dictionary = looks_doc.get("looks",{})
        production_look_ids.clear()
        for look_id in looks.keys():
            production_look_ids.append(str(look_id))
        production_look_ids.sort()
        production_look_picker.clear()
        for look_id in production_look_ids:
            production_look_picker.add_item(look_id)
        if not production_look_ids.is_empty():
            var preferred := production_look_ids.find(keep_look)
            if preferred < 0 and loaded_look_is_production:
                preferred = production_look_ids.find(loaded_look_name)
            production_look_picker.select(maxi(preferred,0))

    if assignment_binding_picker != null:
        var winner_key := _selector_key(resolved.get("selector",{})) if not resolved.is_empty() else ""
        var show_matches_only := assignment_filter_picker != null and assignment_filter_picker.selected == 1
        assignment_binding_rows.clear()
        for item in bindings:
            if not (item is Dictionary):
                continue
            var selector: Dictionary = item.get("selector",{})
            var matches := StyleRegistry.selector_matches(selector,context)
            if show_matches_only and not matches:
                continue
            assignment_binding_rows.append({"item":item,"matches":matches,"score":StyleRegistry.selector_score(selector)})
        assignment_binding_rows.sort_custom(func(a,b):
            if bool(a["matches"]) != bool(b["matches"]):
                return bool(a["matches"])
            if int(a["score"]) != int(b["score"]):
                return int(a["score"]) > int(b["score"])
            return _selector_key((a["item"] as Dictionary).get("selector",{})) < _selector_key((b["item"] as Dictionary).get("selector",{}))
        )
        assignment_binding_picker.clear()
        for row in assignment_binding_rows:
            assignment_binding_picker.add_item(_binding_display(row["item"],context,winner_key))

func _selected_binding() -> Dictionary:
    if assignment_binding_picker == null or assignment_binding_picker.selected < 0 or assignment_binding_picker.selected >= assignment_binding_rows.size():
        return {}
    var row: Dictionary = assignment_binding_rows[assignment_binding_picker.selected]
    return row.get("item",{})

func _load_selected_binding_look() -> void:
    var binding := _selected_binding()
    if binding.is_empty():
        status_label_text("no production binding selected")
        return
    _apply_production_look(str(binding.get("look_id","")))
    _refresh_assignment_view()

func _remove_selected_binding() -> void:
    var binding := _selected_binding()
    if binding.is_empty():
        status_label_text("remove blocked · no production binding selected")
        return
    var selector: Dictionary = binding.get("selector",{})
    var key := _selector_key(selector)
    var doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var filtered: Array = []
    for item in doc.get("bindings",[]):
        if item is Dictionary and _selector_key(item.get("selector",{})) == key:
            continue
        filtered.append(item)
    doc["bindings"] = filtered
    if _write_production_doc(PRODUCTION_ASSIGNMENTS_PATH,doc):
        status_label_text("removed production binding · " + key)
        _refresh_assignment_view()

func _on_assignment_scope_changed(_index: int) -> void:
    _refresh_assignment_view()

func _refresh_assignment_view() -> void:
    if assignment_status_label == null:
        return
    var context := _current_target_context()
    var resolved := _resolve_assignment(context)
    if assignment_resolved_label != null:
        assignment_resolved_label.text = "RESOLVED · " + (str(resolved.get("look_id","none")) if not resolved.is_empty() else "none")
    var doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var lines: Array[String] = []
    lines.append("[b]CURRENT CONTEXT[/b]  " + JSON.stringify(context))
    var scope: String = ASSIGNMENT_SCOPES[assignment_scope_picker.selected] if assignment_scope_picker != null else ASSIGNMENT_SCOPES[0]
    var planned_selector := _selector_for_scope(scope)
    lines.append("[b]ASSIGN SCOPE[/b]  %s" % scope)
    lines.append("[b]WOULD BIND[/b]  " + (_selector_key(planned_selector) if not planned_selector.is_empty() else "not valid for current target"))
    if not resolved.is_empty():
        lines.append("[b]WINNER[/b]  ★ [%03d] %s → %s" % [StyleRegistry.selector_score(resolved.get("selector",{})),_selector_key(resolved.get("selector",{})),str(resolved.get("look_id",""))])
    else:
        lines.append("[b]WINNER[/b]  none")
    lines.append("[b]BINDINGS[/b]  ★ winner · ✓ also matches current context")
    var bindings: Array = doc.get("bindings",[])
    _refresh_production_browsers(context,bindings,resolved)
    if bindings.is_empty():
        lines.append("No production bindings yet.")
    else:
        for item in bindings:
            if item is Dictionary:
                lines.append("• %s  →  [b]%s[/b]" % [_selector_key(item.get("selector",{})),str(item.get("look_id",""))])
    assignment_status_label.text = "\n".join(lines)
    _refresh_assignment_coverage()

func _on_debug_view(index: int) -> void:
    debug_view_index = clampi(index,0,DEBUG_VIEWS.size()-1)
    _apply_fx()
    status_label_text("debug view · " + DEBUG_VIEWS[debug_view_index])

# ---------------------------------------------------------------- capture/diagnostics
func _capture() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
    var img := subvp.get_texture().get_image()
    if img == null: return
    var stamp := Time.get_datetime_string_from_system().replace(":","-")
    var basename := "fxlab_"+stamp
    var path := CAPTURE_DIR.path_join(basename+".png")
    if img.save_png(path) != OK:
        return
    var resolved := _resolve_assignment(_current_target_context())
    var sidecar := {
        "schema":"NRCU_FX_LAB_CAPTURE_V1",
        "image":path.get_file(),
        "captured_at":stamp,
        "source_mode":source_mode,
        "mode_family":mode_format,
        "stage_id":stage_id,
        "preview_time":preview_t,
        "shader_time":shader_time,
        "time_source":time_source,
        "target":_current_target_context(),
        "target_description":_target_description(),
        "spatial_readout":_selected_spatial_readout(),
        "look_name":loaded_look_name if loaded_look_name != "" else current_preset_name,
        "look_authority":"PRODUCTION" if loaded_look_is_production else "DRAFT",
        "dirty":dirty,
        "resolved_assignment":resolved,
        "look":{
            "schema":LOOK_SCHEMA,
            "state":_json_state(),
            "motion":motion.duplicate(true),
            "motion_enabled":motion_enabled.duplicate(true),
            "time_source":time_source,
            "edge_mask_path":edge_mask_path,
            "treatment_mask_path":treatment_mask_path
        }
    }
    var meta_path := CAPTURE_DIR.path_join(basename+".json")
    var meta_file := FileAccess.open(meta_path,FileAccess.WRITE)
    if meta_file != null:
        meta_file.store_string(JSON.stringify(sidecar,"  "))
    status_label_text("capture · "+path+" + metadata")

func _vector_source_has_proxy(source: Node) -> bool:
    if not (source is Polygon2D or source is Line2D):
        return false
    var parent := source.get_parent()
    if parent == null:
        return false
    var expected := str(source.name) + "_FXProxy"
    for sibling in parent.get_children():
        if sibling is TextureRect and str(sibling.name) == expected and bool(sibling.get_meta("fx_vector_proxy",false)):
            return true
    return false

func _unsupported_count() -> int:
    if screen == null: return 0
    var root := screen.get_node_or_null("Root")
    return _count_unsupported(root) if root != null else 0

func _count_unsupported(node: Node) -> int:
    var count := 0
    for child in node.get_children():
        if child is Polygon2D or child is Line2D:
            if not _vector_source_has_proxy(child):
                count += 1
        elif child is ColorRect:
            # Composition flashes/covers intentionally remain outside the reusable
            # look stack unless explicitly proxied in a future revision.
            count += 1
        count += _count_unsupported(child)
    return count

func _assert_pure() -> void:
    var old = state["pure_continuous"]
    state["pure_continuous"] = true
    _apply_fx()
    var all_pass := true
    for key in _target_keys():
        all_pass = all_pass and float((materials[key] as ShaderMaterial).get_shader_parameter("pure_continuous")) > 0.5
    state["pure_continuous"] = old
    _apply_fx()
    status_label_text("PURE CONTINUOUS · "+("PASS" if all_pass else "FAIL"))

# ---------------------------------------------------------------- UI
func _style(bg: Color, border: Color) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = border
    box.border_width_left = 1
    box.border_width_top = 1
    box.border_width_right = 1
    box.border_width_bottom = 1
    box.corner_radius_top_left = 4
    box.corner_radius_top_right = 4
    box.corner_radius_bottom_left = 4
    box.corner_radius_bottom_right = 4
    box.content_margin_left = 7.0
    box.content_margin_right = 7.0
    box.content_margin_top = 4.0
    box.content_margin_bottom = 4.0
    return box

func _theme() -> Theme:
    var t := Theme.new()
    t.default_font_size = 13
    var accent := Color(0.42,0.90,0.72)
    var normal := _style(Color(0.08,0.10,0.125,0.98),Color(0.17,0.20,0.24,1))
    var hover := _style(Color(0.11,0.14,0.17,1),accent)
    for type_name in ["Button","OptionButton"]:
        t.set_stylebox("normal",type_name,normal)
        t.set_stylebox("hover",type_name,hover)
        t.set_stylebox("pressed",type_name,hover)
    return t

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 10
    add_child(layer)
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.theme = _theme()
    layer.add_child(root)
    var col := VBoxContainer.new()
    col.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(col)

    var head := HBoxContainer.new()
    head.custom_minimum_size.y = 40
    col.add_child(head)
    _label(head,"NRCU LOOK DEVELOPMENT LAB · v0.3 AUTHORING DEV",17,Color(0.48,0.92,0.75))
    status_label = _label(head,"…",11,Color(0.62,0.68,0.75))
    look_label = _label(head,"LOOK · factory · CLEAN",11,Color(0.85,0.72,0.45))
    time_label = _label(head,"TIME · PRESENTATION TIME",11,Color(0.55,0.80,0.95))
    var space := Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(space)
    fps_label = _label(head,"FPS · …",11,Color(0.62,0.76,0.84))
    cost_label = _label(head,"COST · …",11,Color(0.95,0.77,0.38))
    var bypass := CheckButton.new(); bypass.text="BYPASS"; bypass.toggled.connect(_on_bypass); head.add_child(bypass)
    var capture := Button.new(); capture.text="CAPTURE"; capture.pressed.connect(_capture); head.add_child(capture)

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    col.add_child(body)
    side_panel = PanelContainer.new()
    side_panel.custom_minimum_size.x = 455
    body.add_child(side_panel)
    var panel := VBoxContainer.new()
    panel.custom_minimum_size.x = 430
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    side_panel.add_child(panel)
    _section(panel,"MATCHUP / PREVIEW CONTEXT")
    _build_matchup(panel)
    _section(panel,"TARGET")
    _build_target(panel)
    processing_label = RichTextLabel.new()
    processing_label.bbcode_enabled = true
    processing_label.fit_content = true
    processing_label.custom_minimum_size.y = 100
    panel.add_child(processing_label)
    var tabs := TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(tabs)
    _build_look_tab(tabs)
    _build_motion_tab(tabs)
    _build_looks_tab(tabs)
    _build_assignments_tab(tabs)
    _build_diag_tab(tabs)
    _apply_tooltips()



    var right := VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(right)
    var top := HBoxContainer.new(); right.add_child(top)
    _button(top,"◧ PANEL",_toggle_panel)
    _button(top,"⏮ START",_transport_to_start)
    transport_button = _button(top,"⏸ PAUSE",_toggle_transport)
    _button(top,"◀ 1F",_transport_step_back)
    _button(top,"1F ▶",_transport_step_forward)
    _button(top,"FX PEAK",_transport_to_fx_peak)
    _button(top,"ISOLATE",_isolate_current_live_element)
    var time_tag := _label(top,"T",11,Color(0.62,0.68,0.75))
    time_tag.custom_minimum_size.x = 12
    transport_time_spin = SpinBox.new()
    transport_time_spin.min_value = 0.0
    transport_time_spin.max_value = timeline_len
    transport_time_spin.step = 0.001
    transport_time_spin.custom_minimum_size.x = 92
    transport_time_spin.value_changed.connect(_on_transport_time_entered)
    top.add_child(transport_time_spin)
    _button(top,"⟲ REMOUNT",_mount_screen)
    _button(top,"RESET LOOK",_reset_look)
    _button(top,"REVERT LOOK",_revert_look)
    _button(top,"▶ TRIGGER MANUAL FX",_trigger_manual)
    _button(top,"MATCH READY / EXIT",_signal_exit)
    viewport_host = Control.new()
    viewport_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
    viewport_host.clip_contents = true
    right.add_child(viewport_host)
    disp = SubViewportContainer.new()
    disp.size = Vector2(1280,720)
    disp.stretch = false
    disp.mouse_filter = Control.MOUSE_FILTER_STOP
    disp.gui_input.connect(_on_preview_gui_input)
    viewport_host.add_child(disp)
    disp.add_child(subvp)
    selection_outline = ReferenceRect.new()
    selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
    selection_outline.border_color = Color(0.48,0.92,0.75,0.95)
    selection_outline.border_width = 2.0
    selection_outline.editor_only = false
    selection_outline.visible = false
    viewport_host.add_child(selection_outline)

    timeline_view = TimelineView.new()
    timeline_view.lab = self
    timeline_view.mouse_default_cursor_shape = Control.CURSOR_HSIZE
    timeline_view.tooltip_text = "Click or drag to scrub. Scrubbing pauses the composition. Use FREE RUN if procedural Fringe motion should keep moving while the composition is parked."
    timeline_view.custom_minimum_size.y = 118
    col.add_child(timeline_view)

func _apply_tooltips() -> void:
    var tips := {
        "fx_size":"Master multiplier for spatial FX dimensions in canonical 1280×720 presentation pixels.",
        "fx_intensity":"Master contribution gain for visible FX. Does not change geometry or pattern cell size.",
        "pattern_scale":"Master multiplier for dither, coverage and driver-grid cells without changing FX geometry.",
        "edge_width":"Edge sampling radius in presentation pixels (or source pixels when Geometry units is explicitly SOURCE PX).",
        "base_opacity":"Opacity of the underlying source element. Generated fringe alpha remains independently controllable.",
        "base_grade_amount":"Strength of the base grade (black/white/gamma/contrast/brightness/saturation).",
        "source_pixel_size":"Pixelates the Base source before Base Grade, RGB offset and Colour Dither. Edge/Fringe extraction remains independently sourced. 0 = off. PRESENTATION PX keeps visible cells consistent across differently sized assets.",
        "mono_mode":"Pattern used by BASE / MONO STAMP. This is independent from Colour Dither.",
        "mono_space":"Coordinate space for BASE / MONO STAMP only.",
        "mono_pixel":"Cell size for BASE / MONO STAMP. Pattern Scale also multiplies this cell size.",
        "mono_threshold":"Luma threshold for BASE / MONO STAMP. The input is the current Base colour after Base Grade.",
        "mono_bayer_level":"Bayer matrix size for BASE / MONO STAMP when Bayer is selected.",
        "fx_amount_dither":"Colour dither strength. Pattern family and pixel size are set in DITHER / QUANTISE.",
        "dither_mode":"Pattern family for colour dither: hard levels, Bayer, clustered noise, random, checker, halftone.",
        "dither_bayer_level":"Bayer matrix size. Larger = finer screen texture.",
        "dither_pixel":"Pattern cell size in pixels.",
        "dither_space":"Pattern coordinate space: SCREEN keeps the grid stable during motion; ELEMENT locks it to the element.",
        "dither_levels":"Number of output levels (hard-levels mode).",
        "dither_threshold":"Tone where the dither pattern starts to show.",
        "dither_gamma":"Gamma applied before quantising — shapes which tones survive the pattern.",
        "dither_contrast":"Contrast applied before quantising.",
        "palette_hue_offset":"Hue rotation applied when generating a palette from the selected source.",
        "palette_saturation":"Saturation multiplier used by palette generation. Manual colours are not changed until GENERATE is pressed.",
        "palette_value":"Brightness/value multiplier used by palette generation. Manual colours are not changed until GENERATE is pressed.",
        "edge_source_mode":"Where the fringe reads edges from: alpha silhouette, luma detail, both, or a custom edge mask.",
        "edge_alpha_weight":"Weight of the alpha-silhouette edge source.",
        "edge_luma_weight":"Weight of the luma-detail edge source.",
        "edge_threshold":"Minimum edge strength before fringe shows.",
        "wind_reach":"How far the fringe colour signal reaches from the edge.",
        "wind_trail":"Trail response — higher values stretch the fringe along the wind direction.",
        "wind_cutoff":"Cuts very weak fringe signal to keep the look clean.",
        "split_separation":"Split distance between the two colour signals (the green/magenta separation).",
        "wind_displace":"Displaces the sampled source along the wind — the moving-ink component.",
        "flow_strength":"Spatial displacement of animated Fringe. This moves the Fringe signal only; it does not distort the source image.",
        "driver_mode":"Driver family for the flow field (travelling whisp, legacy noise, generic generators).",
        "driver_sampling_mode":"CONTINUOUS samples the field smoothly; PIXEL GRID samples it on a grid for stepped motion.",
        "driver_pixel_size":"Grid cell size for driver sampling (PIXEL GRID only).",
        "signal_gain":"Gain applied to the sampled colour signal before it drives the fringe.",
        "signal_softness":"Softens the colour signal edges.",
        "signal_posterize":"0 = CONTINUOUS colour signal. 2+ quantises it into discrete steps.",
        "color_blur":"Blurs the sampled colour signal — soft, wide colour bands instead of crisp edges.",
        "fringe_coverage_mode":"How the fringe is distributed over the element: smooth, or patterned (Bayer/noise/random/checker/halftone).",
        "fringe_coverage_threshold":"Cutoff for fringe coverage.",
        "fringe_bleed":"Bleeds fringe into the alpha — lets colour read outside the silhouette.",
        "rgb_shift_amount":"Pixel distance of the red/blue separation.",
        "rgb_shift_angle":"Direction of the separation in degrees.",
        "rgb_shift_units":"PRESENTATION PX = canonical 1280×720 composition pixels; SOURCE PX = source-texture pixels.",
        "rgb_gradient":"Uses a hue gradient instead of flat colours for the two fringe signals.",
        "temporal_hold":"Quantises the selected FX time source to n updates per second. PURE CONTINUOUS bypasses hold without changing the source.",
        "effect_mask_threshold":"Luma threshold of the treatment mask.",
        "effect_mask_softness":"Edge softness of the treatment mask.",
        "grade_black_point":"Base Grade black point. Values below this point are mapped toward black before saturation/contrast.",
        "grade_white_point":"Base Grade white point. Values above this point are mapped toward white.",
        "grade_gamma":"Base Grade gamma. Values above 1 darken midtones; below 1 brighten them.",
        "grade_contrast":"Base Grade contrast around mid-grey.",
        "grade_brightness":"Base Grade additive brightness offset after contrast.",
        "grade_saturation":"Base Grade saturation multiplier; 0 is monochrome, 1 preserves source saturation.",
        "dither_black_point":"Colour Dither tone-prep black point. Independent from Base Grade.",
        "dither_white_point":"Colour Dither tone-prep white point. Independent from Base Grade.",
        "dither_brightness":"Brightness offset used only to prepare Colour Dither luminance.",
        "fringe_pixel":"Cell size for patterned Fringe coverage. Pattern Scale multiplies this value.",
        "fringe_bayer_level":"Bayer matrix size for patterned Fringe coverage when Bayer is selected.",
        "fringe_coverage_gain":"Gain applied before Fringe coverage threshold/pattern evaluation.",
        "rgb_gradient_balance":"Biases the fringe colour-gradient mix toward colour A or B.",
        "rgb_gradient_contrast":"Contrast of the fringe colour-gradient transition.",
        "rgb_shift_alpha":"How much RGB-offset samples are allowed to expand the element alpha beyond the base silhouette.",
        "flow_center_x":"Horizontal centre of the Fringe radial/driver field in element-normalised coordinates.",
        "flow_center_y":"Vertical centre of the Fringe radial/driver field in element-normalised coordinates.",
        "FIELD_STRENGTH":"Strength of the travelling-whisp vector field before spatial displacement.",
        "FIELD_SPEED":"Animation speed of the travelling-whisp field.",
        "OUTWARDNESS":"How strongly the travelling-whisp field favours radial/outward motion.",
        "FIELD_BREAKUP":"Amount of high-frequency breakup in the travelling-whisp field.",
        "COORD_NUDGE":"How strongly the field offsets the coordinate domain before Fringe sampling.",
        "FIELD_SIZE":"Spatial frequency/size of the travelling-whisp field.",
        "FIELD_CENTER_X":"Expert X centre for the travelling-whisp field domain.",
        "FIELD_CENTER_Y":"Expert Y centre for the travelling-whisp field domain.",
        "LEGACY_SCALE":"Spatial scale of the legacy FBM Fringe driver.",
        "LEGACY_SPEED":"Animation speed of the legacy FBM Fringe driver.",
        "LEGACY_RADIAL":"Radial/outward bias of the legacy FBM Fringe driver.",
        "DRIVER_CENTER_X":"Generic procedural-driver X centre.",
        "DRIVER_CENTER_Y":"Generic procedural-driver Y centre.",
        "DRIVER_SCALE":"Generic procedural-driver spatial scale.",
        "DRIVER_STRETCH":"Generic procedural-driver anisotropic stretch.",
        "DRIVER_ANGLE":"Generic procedural-driver rotation in radians.",
        "DRIVER_SPEED":"Generic procedural-driver animation speed multiplier.",
        "DRIVER_DETAIL":"Generic procedural-driver detail/high-frequency contribution.",
        "DRIVER_FLOW":"Generic procedural-driver directional-flow contribution versus radial bias.",
        "pure_continuous":"Disables every hidden quantisation (dither, patterns, hold) and drives the effects continuously — values are preserved, not erased.",
    }
    for key in tips.keys():
        if controls.has(key):
            var c = controls[key]
            if c is Control:
                (c as Control).tooltip_text = tips[key]
        if spin_controls.has(key):
            var spin = spin_controls[key]
            if spin is Control:
                (spin as Control).tooltip_text = tips[key]

func _build_matchup(parent: Node) -> void:
    var row := HBoxContainer.new(); parent.add_child(row)
    var fmt := _raw_option(row,FORMAT_NAMES,0,_on_format)
    fmt.custom_minimum_size.x = 145
    var stage := _raw_option(row,STAGE_IDS,0,_on_stage)
    stage.custom_minimum_size.x = 120
    var fighters := HBoxContainer.new(); parent.add_child(fighters)
    for slot in range(4):
        var picker := OptionButton.new()
        picker.custom_minimum_size.x = 98
        for fid in fighter_ids: picker.add_item(fid)
        var current: String = pick_l if slot==0 else pick_r if slot==1 else pick_extra[slot-2]
        picker.selected = maxi(fighter_ids.find(current),0)
        picker.item_selected.connect(_on_fighter.bind(slot))
        fighters.add_child(picker)

func _build_target(parent: Node) -> void:
    var source_row := HBoxContainer.new(); parent.add_child(source_row)
    var source_label := _label(source_row,"SOURCE",11,Color(0.62,0.68,0.75)); source_label.custom_minimum_size.x=88
    var source := _raw_option(source_row,["LIVE SCREEN","ELEMENT STUDY"],0,_on_source_mode); source.custom_minimum_size.x=220; controls["source_mode"]=source
    source.tooltip_text = "LIVE SCREEN edits real composition nodes. ELEMENT STUDY isolates a real VS asset or custom image."
    var scope_row := HBoxContainer.new(); parent.add_child(scope_row)
    var scope_label := _label(scope_row,"SCOPE",11,Color(0.62,0.68,0.75)); scope_label.custom_minimum_size.x=88
    target_mode_picker = _raw_option(scope_row,TARGET_MODES,0,_on_target_mode); target_mode_picker.custom_minimum_size.x=120; controls["target_mode"]=target_mode_picker
    var role_label := _label(scope_row,"ROLE",11,Color(0.62,0.68,0.75)); role_label.custom_minimum_size.x=42
    role_picker = _raw_option(scope_row,TARGET_ROLES,0,_on_target_role); role_picker.custom_minimum_size.x=150; controls["target_role"]=role_picker
    var focus_row := HBoxContainer.new(); parent.add_child(focus_row)
    var focus_label := _label(focus_row,"PREVIEW",11,Color(0.62,0.68,0.75)); focus_label.custom_minimum_size.x=88
    preview_focus_picker = _raw_option(focus_row,PREVIEW_FOCUS_MODES,0,_on_preview_focus)
    preview_focus_picker.custom_minimum_size.x = 180
    preview_focus_picker.tooltip_text = "Editorial preview only. DIM/SOLO helps inspect the current target and is never saved into the Look."
    var element_row := HBoxContainer.new(); parent.add_child(element_row)
    var element_label := _label(element_row,"LIVE ELEMENT",11,Color(0.62,0.68,0.75)); element_label.custom_minimum_size.x=88
    slot_picker = OptionButton.new(); slot_picker.custom_minimum_size.x=305; slot_picker.item_selected.connect(_on_slot); element_row.add_child(slot_picker)
    slot_picker.tooltip_text = "Exact texture-backed node in the live VS composition. Use SELECTED scope to edit only this element."
    var asset_row := HBoxContainer.new(); parent.add_child(asset_row)
    var asset_label := _label(asset_row,"STUDY ASSET",11,Color(0.62,0.68,0.75)); asset_label.custom_minimum_size.x=88
    custom_asset_picker = OptionButton.new(); custom_asset_picker.custom_minimum_size.x=305; asset_row.add_child(custom_asset_picker)
    custom_asset_picker.tooltip_text = "Real VS assets (VS mark, every fighter Primary/Echo/Name, stages) plus assets/elements custom images."
    custom_asset_picker.item_selected.connect(_on_custom_asset)
    _button(asset_row,"RESCAN",_rescan_assets)
    var study_row := HBoxContainer.new(); parent.add_child(study_row)
    var study_label := _label(study_row,"STUDY VIEW",11,Color(0.62,0.68,0.75)); study_label.custom_minimum_size.x=88
    _button(study_row,"FIT",_study_fit)
    study_zoom_spin = SpinBox.new()
    study_zoom_spin.min_value = STUDY_ZOOM_MIN*100.0
    study_zoom_spin.max_value = STUDY_ZOOM_MAX*100.0
    study_zoom_spin.step = 5.0
    study_zoom_spin.suffix = "%"
    study_zoom_spin.value = 100.0
    study_zoom_spin.custom_minimum_size.x = 82
    study_zoom_spin.tooltip_text = "Study-only editor zoom. It never changes canonical presentation-space FX size. Mouse wheel also zooms; middle-drag pans."
    study_zoom_spin.value_changed.connect(_on_study_zoom_entered)
    study_row.add_child(study_zoom_spin)
    study_background_picker = _raw_option(study_row,STUDY_BACKGROUNDS,0,_on_study_background)
    study_background_picker.custom_minimum_size.x = 110
    study_background_picker.tooltip_text = "Study-only background for alpha/edge inspection."
    var mask_row := HBoxContainer.new(); parent.add_child(mask_row)
    var mask_label := _label(mask_row,"MASKS",11,Color(0.62,0.68,0.75)); mask_label.custom_minimum_size.x=88
    edge_mask_picker = OptionButton.new(); edge_mask_picker.item_selected.connect(_on_edge_mask); mask_row.add_child(edge_mask_picker)
    _reset_button(mask_row,"edge_mask_path",_reset_edge_mask_path)
    treatment_mask_picker = OptionButton.new(); treatment_mask_picker.item_selected.connect(_on_treatment_mask); mask_row.add_child(treatment_mask_picker)
    _reset_button(mask_row,"treatment_mask_path",_reset_treatment_mask_path)
    _refresh_asset_pickers()

func _build_look_tab(tabs: TabContainer) -> void:
    var scroll := ScrollContainer.new(); scroll.name="LOOK"; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; tabs.add_child(scroll)
    var v := VBoxContainer.new(); v.custom_minimum_size.x=410; scroll.add_child(v)
    var depth := HBoxContainer.new(); v.add_child(depth); _label(depth,"CONTROL DEPTH",11,Color(0.65,0.70,0.78))
    detail_picker = _raw_option(depth,["BASIC","ADVANCED","EXPERT"],1,_on_detail)
    _state_check(v,"PURE CONTINUOUS · zero hidden quantisation","pure_continuous")
    var time_row := HBoxContainer.new(); v.add_child(time_row)
    _label(time_row,"FX TIME SOURCE",11,Color(0.65,0.70,0.78))
    var ts := _raw_option(time_row,TIME_SOURCES,0,_on_time_source); ts.custom_minimum_size.x=185
    ts.tooltip_text = "PRESENTATION TIME follows the live VS timeline (deterministic against the presentation clock). FREE RUN uses the accumulated lab clock (element study / free evaluation). Temporal Hold quantises whichever source is selected."
    controls["time_source"]=ts
    _reset_button(time_row,"time_source",_reset_time_source)

    var master := _section_group(v,"MASTER FX","MASTER")
    _state_slider(master,"FX size","fx_size")
    _state_slider(master,"FX intensity","fx_intensity")
    _state_slider(master,"Pattern scale","pattern_scale")
    _state_slider(master,"Edge width","edge_width")

    var base := _section_group(v,"BASE TREATMENT","BASE")
    _state_slider(base,"Base opacity","base_opacity")
    _state_slider(base,"Grade amount","base_grade_amount")
    _state_slider(base,"Saturation","grade_saturation")
    var adv_base := VBoxContainer.new(); advanced_nodes.append(adv_base); base.add_child(adv_base)
    for spec in [["grade_black_point","Black point",0,0.99,0.01],["grade_white_point","White point",0.01,1,0.01],["grade_gamma","Gamma",0.1,4,0.01],["grade_contrast","Contrast",0,4,0.01],["grade_brightness","Brightness",-1,1,0.01]]:
        _state_slider(adv_base,spec[1],spec[0])
    _state_slider(adv_base,"Source pixel grid","source_pixel_size")
    _state_option(adv_base,"Source pixel units",GEOMETRY_UNITS,"source_pixel_units")
    var exp_base := VBoxContainer.new(); expert_nodes.append(exp_base); base.add_child(exp_base)
    _state_option(exp_base,"Base mode",["COLOUR","MONO STAMP"],"base_mode")
    _state_option(exp_base,"Mono pattern",DITHER_PATTERNS,"mono_mode")
    _state_option(exp_base,"Mono pattern space",PATTERN_SPACES,"mono_space")
    _state_slider(exp_base,"Mono cell size","mono_pixel")
    _state_slider(exp_base,"Mono threshold","mono_threshold")
    _state_slider(exp_base,"Mono Bayer matrix","mono_bayer_level")

    var dith := _section_group(v,"DITHER / QUANTISE","DITHER")
    _fx_header(dith,"dither","Colour dither")
    _state_slider(dith,"Levels","dither_levels")
    _state_slider(dith,"Cell size","dither_pixel")
    var adv_d := VBoxContainer.new(); advanced_nodes.append(adv_d); dith.add_child(adv_d)
    _state_option(adv_d,"Pattern",DITHER_PATTERNS,"dither_mode")
    _state_option(adv_d,"Pattern space",PATTERN_SPACES,"dither_space")
    _state_slider(adv_d,"Bayer matrix","dither_bayer_level")
    var exp_d := VBoxContainer.new(); expert_nodes.append(exp_d); dith.add_child(exp_d)
    for spec in [["dither_threshold","Threshold",0,1,0.01],["dither_black_point","Black point",0,0.99,0.01],["dither_white_point","White point",0.01,1,0.01],["dither_gamma","Gamma",0.1,4,0.01],["dither_contrast","Contrast",0,4,0.01],["dither_brightness","Brightness",-1,1,0.01]]:
        _state_slider(exp_d,spec[1],spec[0])

    var fringe := _section_group(v,"EDGE / FRINGE","FRINGE")
    _fx_header(fringe,"fringe","Edge / Fringe")
    var colors := HBoxContainer.new(); fringe.add_child(colors); _swatch(colors,true); _swatch(colors,false); _button(colors,"SWAP",_swap_palette)
    var palette_row := HBoxContainer.new(); fringe.add_child(palette_row)
    var palette_label := _label(palette_row,"PALETTE FROM SOURCE",11,Color(0.62,0.68,0.75)); palette_label.custom_minimum_size.x=135
    var palette_strategy := _raw_option(palette_row,PALETTE_STRATEGIES,int(state["palette_strategy"]),_on_palette_strategy); palette_strategy.custom_minimum_size.x=180; controls["palette_strategy"]=palette_strategy
    _reset_button(palette_row,"palette_strategy",_reset_state_key.bind("palette_strategy"))
    _button(palette_row,"GENERATE",_auto_palette)
    var palette_lock_row := HBoxContainer.new(); fringe.add_child(palette_lock_row)
    _state_check(palette_lock_row,"Lock A","palette_lock_a")
    _state_check(palette_lock_row,"Lock B","palette_lock_b")
    var palette_adv := VBoxContainer.new(); advanced_nodes.append(palette_adv); fringe.add_child(palette_adv)
    _state_slider(palette_adv,"Palette hue offset","palette_hue_offset")
    _state_slider(palette_adv,"Palette saturation","palette_saturation")
    _state_slider(palette_adv,"Palette value","palette_value")
    _state_slider(fringe,"Reach","wind_reach")
    _state_slider(fringe,"Trail","wind_trail")
    _state_slider(fringe,"Split distance","split_separation")
    var adv_f := VBoxContainer.new(); advanced_nodes.append(adv_f); fringe.add_child(adv_f)
    _state_option(adv_f,"Edge source",EDGE_SOURCES,"edge_source_mode")
    _state_option(adv_f,"Coverage",FRINGE_COVERAGE,"fringe_coverage_mode")
    _state_option(adv_f,"Geometry units",GEOMETRY_UNITS,"geometry_units")
    _state_slider(adv_f,"Coverage cell","fringe_pixel")
    _state_option(adv_f,"Coverage space",PATTERN_SPACES,"fringe_space")
    _state_slider(adv_f,"Coverage Bayer","fringe_bayer_level")
    _state_check(adv_f,"Use treatment mask","effect_mask_enabled")
    _state_check(adv_f,"Invert treatment mask","effect_mask_invert")
    _state_check(adv_f,"Mask base treatment too","effect_mask_base")
    _state_slider(adv_f,"Mask threshold","effect_mask_threshold")
    _state_slider(adv_f,"Mask softness","effect_mask_softness")
    var exp_f := VBoxContainer.new(); expert_nodes.append(exp_f); fringe.add_child(exp_f)
    for spec in [["edge_alpha_weight","Alpha edge weight",0,3,0.05],["edge_luma_weight","Luma edge weight",0,3,0.05],["edge_threshold","Edge threshold",0.005,0.5,0.005],["wind_cutoff","Wind cutoff",0,1,0.01],["signal_gain","Signal gain",0,3,0.01],["signal_softness","Signal softness",0.001,0.35,0.005],["signal_posterize","Signal posterize",0,16,1],["color_blur","Colour blur",0,200,1],["fringe_coverage_threshold","Coverage threshold",0,1,0.01],["fringe_coverage_gain","Coverage gain",0,2,0.01],["fringe_bleed","Alpha bleed",0,1,0.01],["rgb_gradient","Hue gradient",0,1,0.01],["rgb_gradient_balance","Gradient balance",-1,1,0.01],["rgb_gradient_contrast","Gradient contrast",0.1,3,0.01]]:
        _state_slider(exp_f,spec[1],spec[0])
    _state_option(exp_f,"Blend",BLEND_MODES,"fringe_blend_mode")

    var flow := _section_group(v,"FRINGE MOTION / DRIVER","FLOW")
    _fx_header(flow,"flow","Animate fringe")
    _state_option(flow,"Driver",DRIVER_NAMES,"driver_mode")
    _state_slider(flow,"Displacement","flow_strength")
    var adv_flow := VBoxContainer.new(); advanced_nodes.append(adv_flow); flow.add_child(adv_flow)
    _state_option(adv_flow,"Sampling",["CONTINUOUS","PIXEL GRID"],"driver_sampling_mode")
    _state_slider(adv_flow,"Driver grid","driver_pixel_size")
    _state_slider(adv_flow,"Temporal hold FPS","temporal_hold")
    var exp_flow := VBoxContainer.new(); expert_nodes.append(exp_flow); flow.add_child(exp_flow)
    for spec in [["FIELD_STRENGTH","Field strength",0,2,0.01],["FIELD_SPEED","Field speed",0,3,0.01],["OUTWARDNESS","Outwardness",0,1,0.01],["FIELD_BREAKUP","Breakup",0,2,0.01],["COORD_NUDGE","Coord nudge",0,1,0.01],["FIELD_SIZE","Field size",0.1,4,0.01],["FIELD_CENTER_X","Field center X",-2,5,0.01],["FIELD_CENTER_Y","Field center Y",-2,5,0.01],["wind_displace","Wind displace",0,3,0.01],["flow_center_x","Radial center X",-1,2,0.01],["flow_center_y","Radial center Y",-1,2,0.01],["LEGACY_SCALE","Legacy scale",0.1,20,0.05],["LEGACY_SPEED","Legacy speed",0,3,0.01],["LEGACY_RADIAL","Legacy radial",0,1,0.01],["DRIVER_CENTER_X","Driver center X",-2,5,0.01],["DRIVER_CENTER_Y","Driver center Y",-2,5,0.01],["DRIVER_SCALE","Driver scale",0.05,8,0.01],["DRIVER_STRETCH","Driver stretch",-2,2,0.01],["DRIVER_ANGLE","Driver angle",-3.1416,3.1416,0.01],["DRIVER_SPEED","Driver speed",0,5,0.01],["DRIVER_DETAIL","Driver detail",0,1,0.01],["DRIVER_FLOW","Driver flow",0,1,0.01]]:
        _state_slider(exp_flow,spec[1],spec[0])

    var rgb := _section_group(v,"CHANNEL OFFSET","RGB")
    _fx_header(rgb,"rgb","RGB channel offset")
    _state_slider(rgb,"Distance","rgb_shift_amount")
    _state_slider(rgb,"Angle","rgb_shift_angle")
    _state_option(rgb,"Distance units",GEOMETRY_UNITS,"rgb_shift_units")
    var adv_rgb := VBoxContainer.new(); advanced_nodes.append(adv_rgb); rgb.add_child(adv_rgb)
    _state_slider(adv_rgb,"Shift alpha","rgb_shift_alpha")
    _update_detail_visibility()

func _build_motion_tab(tabs: TabContainer) -> void:
    var scroll := ScrollContainer.new(); scroll.name="MOTION"; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; tabs.add_child(scroll)
    var v := VBoxContainer.new(); v.custom_minimum_size.x=410; scroll.add_child(v)
    _label(v,"Attack / Hold / Release envelopes on real VS anchors. These animate effect amount; Fringe Motion/Driver controls internal procedural movement.",11,Color(0.65,0.70,0.78))
    for fx in FX_NAMES:
        var body := _section_group(v,fx.to_upper(),"MOTION:"+fx)
        var enabled_row := HBoxContainer.new(); body.add_child(enabled_row)
        var enabled := CheckButton.new(); enabled.text="Envelope enabled"; enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL; enabled.toggled.connect(_on_motion_enabled.bind(fx)); enabled_row.add_child(enabled); controls["motion_enabled_"+fx]=enabled
        _reset_button(enabled_row,"motion_enabled_"+fx,_reset_motion_enabled.bind(fx))
        _motion_option(body,fx,"anchor","Anchor",ANCHORS)
        for spec in [["delay","Delay",0,1,0.005],["attack","Attack",0.001,1.5,0.005],["hold","Hold",0,2,0.005],["release","Release",0.001,2.5,0.005],["sustain","Sustain",0,1,0.01]]:
            _motion_slider(body,fx,spec[0],spec[1],spec[2],spec[3],spec[4])
        _motion_option(body,fx,"attack_curve","Attack curve",["linear","cubic_out","cubic_in","back_out","sine_in_out"])
        _motion_option(body,fx,"release_curve","Release curve",["linear","cubic_out","cubic_in","back_out","sine_in_out"])
    var loop := CheckButton.new(); loop.text="Loop manual envelopes"; loop.toggled.connect(_on_motion_loop); v.add_child(loop)

func _coverage_contexts() -> Array[Dictionary]:
    # Coverage is an authoring diagnostic, not runtime routing. It samples the
    # semantic identities an artist can intentionally style, independent of P1/P2.
    var contexts: Array[Dictionary] = []
    var fighter_ids: Array[String] = []
    for item in study_assets:
        if not (item is Dictionary):
            continue
        var fid := str(item.get("fighter_id", ""))
        if fid != "" and not fighter_ids.has(fid):
            fighter_ids.append(fid)
    fighter_ids.sort()
    for fighter_id in fighter_ids:
        for role in ["primary", "echo", "name"]:
            for side in ["left", "right"]:
                contexts.append({
                    "label":"%s · %s · %s" % [fighter_id.to_upper(), role.to_upper(), side.to_upper()],
                    "fighter_id":fighter_id,
                    "element_role":role,
                    "visual_side":side,
                    "mode_family":mode_format,
                    "stage_id":stage_id,
                })
    for static_spec in [
        {"label":"VS MARK", "element_id":"vs_mark", "element_role":"vs_mark"},
        {"label":"SIDE FIELD · LEFT", "element_id":"side_field_left", "element_role":"side_field", "visual_side":"left"},
        {"label":"SIDE FIELD · RIGHT", "element_id":"side_field_right", "element_role":"side_field", "visual_side":"right"},
        {"label":"NAME PLATE · LEFT", "element_id":"name_plate_left", "element_role":"name_plate", "visual_side":"left"},
        {"label":"NAME PLATE · RIGHT", "element_id":"name_plate_right", "element_role":"name_plate", "visual_side":"right"},
        {"label":"ACCENT LINE · LEFT", "element_id":"accent_line_left", "element_role":"accent_line", "visual_side":"left"},
        {"label":"ACCENT LINE · RIGHT", "element_id":"accent_line_right", "element_role":"accent_line", "visual_side":"right"},
        {"label":"STAGE · %s" % stage_id.to_upper(), "element_id":"stage", "element_role":"stage", "stage_id":stage_id},
    ]:
        var context: Dictionary = static_spec.duplicate(true)
        context["mode_family"] = mode_format
        if not context.has("stage_id"):
            context["stage_id"] = stage_id
        contexts.append(context)
    return contexts

func _production_coverage_report() -> Dictionary:
    var assignments_doc := _read_production_doc(PRODUCTION_ASSIGNMENTS_PATH,PRODUCTION_ASSIGNMENTS_SCHEMA,_production_default_assignments())
    var looks_doc := _read_production_doc(PRODUCTION_LOOKS_PATH,PRODUCTION_LOOKS_SCHEMA,_production_default_looks())
    var looks: Dictionary = looks_doc.get("looks", {})
    var rows: Array = []
    var assigned := 0
    var missing := 0
    var broken := 0
    for context in _coverage_contexts():
        var resolved := StyleRegistry.resolve_binding(assignments_doc, context)
        var label := str(context.get("label", "unnamed"))
        if resolved.is_empty():
            rows.append({"label":label,"status":"UNASSIGNED","look_id":""})
            missing += 1
        else:
            var look_id := str(resolved.get("look_id", ""))
            if look_id == "" or not looks.has(look_id):
                rows.append({"label":label,"status":"BROKEN","look_id":look_id})
                broken += 1
            else:
                rows.append({"label":label,"status":"ASSIGNED","look_id":look_id})
                assigned += 1
    return {"rows":rows,"assigned":assigned,"missing":missing,"broken":broken,"total":rows.size()}

func _refresh_assignment_coverage() -> void:
    if assignment_coverage_label == null:
        return
    var report := _production_coverage_report()
    var total := int(report.get("total",0))
    var assigned := int(report.get("assigned",0))
    var missing := int(report.get("missing",0))
    var broken := int(report.get("broken",0))
    var lines: Array[String] = []
    lines.append("[b]COVERAGE · %d/%d assigned · %d unassigned · %d broken[/b]" % [assigned,total,missing,broken])
    var shown := 0
    for item in report.get("rows",[]):
        if not (item is Dictionary) or str(item.get("status","")) == "ASSIGNED":
            continue
        var icon := "⚠" if str(item.get("status","")) == "BROKEN" else "○"
        var suffix := " → " + str(item.get("look_id","")) if str(item.get("look_id","")) != "" else ""
        lines.append("%s %s · %s%s" % [icon,str(item.get("status","")),str(item.get("label","")),suffix])
        shown += 1
        if shown >= 12:
            break
    if missing + broken > shown:
        lines.append("… %d more unresolved identities" % (missing + broken - shown))
    if missing == 0 and broken == 0:
        lines.append("✓ Every sampled authoring identity resolves to a valid production Look.")
    assignment_coverage_label.text = "\n".join(lines)

func _build_looks_tab(tabs: TabContainer) -> void:
    var v := VBoxContainer.new(); v.name="LOOKS"; v.custom_minimum_size.x=410; tabs.add_child(v)
    _label(v,"Looks store style, masks, palette and motion — never target/matchup assignment. Use ASSIGNMENTS to bind a look to game elements.",11,Color(0.65,0.70,0.78))
    _label(v,"Shortcuts: Ctrl+S Save · Ctrl+Shift+S Save As · Ctrl+Z/Y Undo/Redo",10,Color(0.48,0.58,0.66))
    preset_picker = OptionButton.new(); v.add_child(preset_picker)
    preset_name_edit = LineEdit.new(); preset_name_edit.placeholder_text="VS_IMPACT_A"; v.add_child(preset_name_edit)
    var row := HBoxContainer.new(); v.add_child(row)
    _button(row,"SAVE",_save_preset); _button(row,"LOAD",_load_preset); _button(row,"DELETE",_delete_preset); _button(row,"EXPORT JSON",_export_json); _button(row,"IMPORT JSON",_open_import)
    import_dialog = FileDialog.new(); import_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE; import_dialog.access=FileDialog.ACCESS_FILESYSTEM; import_dialog.filters=PackedStringArray(["*.json ; NRCU FX Look"]); import_dialog.file_selected.connect(_import_json); v.add_child(import_dialog)
    preset_status_label = _label(v,"No look loaded",11,Color(0.48,0.92,0.75))
    _section(v,"A / B")
    var ab := HBoxContainer.new(); v.add_child(ab)
    _button(ab,"STORE A",_store_a); _button(ab,"VIEW A",_view_a); _button(ab,"STORE B",_store_b); _button(ab,"VIEW B",_view_b)
    _section(v,"SAFE STARTS")
    _button(v,"ANIMATED FRINGE PREVIEW · FREE RUN",_safe_animated_fringe_preview)
    _button(v,"PURE CONTINUOUS / SMOOTH FRINGE",_safe_smooth)
    _button(v,"VS IMPACT / SMOOTH SIGNAL",_safe_vs_impact)
    _button(v,"ECHO / ORDERED SIGNAL",_safe_echo)

func _build_assignments_tab(tabs: TabContainer) -> void:
    var scroll := ScrollContainer.new()
    scroll.name = "ASSIGNMENTS"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    tabs.add_child(scroll)
    var v := VBoxContainer.new()
    v.custom_minimum_size.x = 410
    scroll.add_child(v)
    _label(v,"Production Looks are style-only. Bindings decide where a published Look applies in the game.",11,Color(0.65,0.70,0.78))

    _section(v,"PRODUCTION LOOK LIBRARY")
    production_look_picker = OptionButton.new()
    production_look_picker.tooltip_text = "Published project-local Looks from res://assets/vs/fx/fx_looks.json. Selecting does not change the current authoring state until LOAD SELECTED is pressed."
    v.add_child(production_look_picker)
    var library_row := HBoxContainer.new(); v.add_child(library_row)
    _button(library_row,"LOAD SELECTED",_load_selected_production_look)
    _button(library_row,"PUBLISH CURRENT",_publish_current_look)
    _button(library_row,"DUPLICATE AS NAME",_duplicate_production_look)
    _button(library_row,"RENAME TO NAME",_rename_production_look)
    _button(library_row,"DELETE PRODUCTION",_delete_selected_production_look)

    _section(v,"CURRENT TARGET BINDING")
    var scope_row := HBoxContainer.new(); v.add_child(scope_row)
    var scope_label := _label(scope_row,"BINDING SCOPE",11,Color(0.62,0.68,0.75)); scope_label.custom_minimum_size.x=120
    assignment_scope_picker = _raw_option(scope_row,ASSIGNMENT_SCOPES,0,_on_assignment_scope_changed)
    assignment_scope_picker.custom_minimum_size.x = 220
    var row := HBoxContainer.new(); v.add_child(row)
    _button(row,"ASSIGN TO GAME",_assign_current_look)
    _button(row,"UNASSIGN CURRENT",_unassign_current)
    _button(row,"LOAD RESOLVED",_load_resolved_assignment)
    assignment_resolved_label = _label(v,"RESOLVED · none",11,Color(0.48,0.92,0.75))

    _section(v,"BINDING BROWSER")
    var filter_row := HBoxContainer.new(); v.add_child(filter_row)
    var filter_label := _label(filter_row,"SHOW",11,Color(0.62,0.68,0.75)); filter_label.custom_minimum_size.x=120
    assignment_filter_picker = _raw_option(filter_row,["ALL BINDINGS","MATCH CURRENT CONTEXT"],0,_on_assignment_filter_changed)
    assignment_filter_picker.custom_minimum_size.x = 220
    assignment_binding_picker = OptionButton.new()
    assignment_binding_picker.tooltip_text = "Published bindings sorted with current-context matches first, then by specificity."
    v.add_child(assignment_binding_picker)
    var binding_row := HBoxContainer.new(); v.add_child(binding_row)
    _button(binding_row,"LOAD BINDING LOOK",_load_selected_binding_look)
    _button(binding_row,"REMOVE BINDING",_remove_selected_binding)

    assignment_status_label = RichTextLabel.new()
    assignment_status_label.bbcode_enabled = true
    assignment_status_label.fit_content = true
    assignment_status_label.custom_minimum_size.y = 180
    v.add_child(assignment_status_label)

    _section(v,"PRODUCTION COVERAGE")
    _label(v,"Coverage is a planning diagnostic over every fighter Primary/Echo/Name on left/right plus static VS elements for the current family/stage. Generic bindings count when they resolve these identities.",10,Color(0.65,0.70,0.78))
    assignment_coverage_label = RichTextLabel.new()
    assignment_coverage_label.bbcode_enabled = true
    assignment_coverage_label.fit_content = true
    assignment_coverage_label.custom_minimum_size.y = 190
    v.add_child(assignment_coverage_label)
    _button(v,"REFRESH COVERAGE",_refresh_assignment_coverage)
    _refresh_assignment_view()
    _refresh_assignment_coverage()

func _build_diag_tab(tabs: TabContainer) -> void:
    var v := VBoxContainer.new(); v.name="DIAGNOSTICS"; v.custom_minimum_size.x=410; tabs.add_child(v)
    _label(v,"Render diagnostic views are preview-only and are never stored in a Look.",10,Color(0.65,0.70,0.78))
    debug_view_picker = _option(v,"DEBUG VIEW",DEBUG_VIEWS,debug_view_index,_on_debug_view)
    _button(v,"ASSERT PURE CONTINUOUS",_assert_pure)
    _button(v,"REPORT TARGET SUPPORT",_report_support)
    _label(v,"EXTERNAL OVERSCAN PROXY · RUNTIME GATE PENDING",12,Color(0.95,0.77,0.38))
    _label(v,"Authoring build includes a padded TextureRect proxy for texture targets and presentation-mask proxies for vector targets. It is not production-authoritative until Godot 4.7.2 parity/crop/transform tests pass.",10,Color(0.65,0.70,0.78))
    _label(v,"TARGET SUPPORT",12,Color(0.48,0.92,0.75))
    _label(v,"Supported: VS Mark · Primaries · Echoes · Names · Stage · Side Fields · Name Plates · Accent Lines (presentation-mask proxies) · full real-asset Element Study · texture-backed custom elements.\nReported, not shader-targeted: remaining ColorRect / intentionally non-look composition geometry.",10,Color(0.65,0.70,0.78))

# ---------------------------------------------------------------- transport / authoring preview
func _set_transport_paused(paused: bool) -> void:
    transport_paused = paused
    if source_mode == "LIVE SCREEN" and screen != null:
        if paused and screen.has_method("lab_preview_pause"):
            screen.lab_preview_pause()
        elif not paused and screen.has_method("lab_preview_resume"):
            screen.lab_preview_resume()
    if transport_button != null:
        transport_button.text = "▶ PLAY" if paused else "⏸ PAUSE"
    status_label_text(("paused" if paused else "playing") + " · %.3fs" % preview_t)

func _toggle_transport() -> void:
    _set_transport_paused(not transport_paused)

func _transport_seek_to(t: float) -> void:
    var clamped := clampf(t, 0.0, timeline_len)
    _set_transport_paused(true)
    if source_mode == "LIVE SCREEN" and screen != null and screen.has_method("lab_preview_seek"):
        screen.lab_preview_seek(clamped)
        preview_t = clamped
    else:
        study_presentation_time = clamped
        preview_t = clamped
    if transport_time_spin != null:
        transport_syncing = true
        transport_time_spin.set_value_no_signal(clamped)
        transport_syncing = false
    _apply_runtime_uniforms()
    if timeline_view != null:
        timeline_view.queue_redraw()

func _transport_to_start() -> void:
    _transport_seek_to(0.0)

func _transport_step_back() -> void:
    _transport_seek_to(preview_t - 1.0 / 60.0)

func _transport_step_forward() -> void:
    _transport_seek_to(preview_t + 1.0 / 60.0)

func _transport_to_fx_peak() -> void:
    for fx in ["fringe","dither","rgb","flow"]:
        if bool(motion_enabled.get(fx,false)):
            var spec: Dictionary = motion[fx]
            var anchor := str(spec.get("anchor","manual"))
            if anchor != "manual":
                var peak := float(event_marks.get(anchor,0.0)) + float(spec.get("delay",0.0)) + float(spec.get("attack",0.0))
                _transport_seek_to(peak)
                return
    _transport_seek_to(float(event_marks.get("clash_impact",0.615)))

func _on_transport_time_entered(value: float) -> void:
    if not transport_syncing:
        _transport_seek_to(value)

# ---------------------------------------------------------------- UI callbacks/helpers
func _on_bypass(value: bool) -> void:
    bypass_fx = value
    _apply_fx()

func _toggle_panel() -> void:
    panel_visible = not panel_visible
    side_panel.visible = panel_visible

func _signal_exit() -> void:
    if screen != null and screen.has_method("signal_match_ready"):
        screen.signal_match_ready()

func _trigger_manual() -> void:
    for fx in FX_NAMES:
        _start_manual_motion(fx)

func _on_format(index: int) -> void:
    if index >= 0 and index < FORMAT_NAMES.size():
        mode_format = FORMAT_NAMES[index]
        _mount_screen()

func _on_stage(index: int) -> void:
    if index >= 0 and index < STAGE_IDS.size():
        stage_id = STAGE_IDS[index]
        _mount_screen()

func _on_fighter(index: int, slot: int) -> void:
    if index < 0 or index >= fighter_ids.size():
        return
    if slot == 0:
        pick_l = str(fighter_ids[index])
    elif slot == 1:
        pick_r = str(fighter_ids[index])
    else:
        pick_extra[slot - 2] = str(fighter_ids[index])
    _mount_screen()

func _isolate_current_live_element() -> void:
    if source_mode != "LIVE SCREEN" or target_mode != "SELECTED" or not slot_nodes.has(selected_slot):
        status_label_text("isolate blocked · select one live texture element first")
        return
    var node = slot_nodes[selected_slot]
    if not (node is TextureRect) or node.texture == null or String(node.texture.resource_path) == "":
        status_label_text("isolate blocked · selected target has no reusable texture asset")
        return
    var path := String(node.texture.resource_path)
    var found := false
    for item in study_assets:
        if str(item.get("path","")) == path:
            custom_asset_path = path
            found = true
            break
    if not found:
        study_assets.append({"label":"LIVE · " + path.get_file(),"path":path,"role":String(slot_roles.get(selected_slot,"OTHER TEXTURES"))})
        custom_asset_path = path
    _refresh_custom_texture()
    _on_source_mode(1)
    _refresh_asset_pickers()
    status_label_text("isolated · " + path.get_file())

func _on_source_mode(index: int) -> void:
    var next_mode := "LIVE SCREEN" if index == 0 else "ELEMENT STUDY"
    if next_mode == source_mode:
        return
    if next_mode == "ELEMENT STUDY":
        live_target_mode = target_mode
        live_target_role = target_role
        live_selected_slot = selected_slot
        target_mode = "SELECTED"
        selected_slot = "study_asset"
        study_presentation_time = preview_t
        # Keep the hidden live composition parked while studying assets.
        if screen != null and screen.has_method("lab_preview_pause"):
            screen.lab_preview_pause()
    else:
        target_mode = live_target_mode
        target_role = live_target_role
        selected_slot = live_selected_slot
        if screen != null:
            if transport_paused and screen.has_method("lab_preview_pause"):
                screen.lab_preview_pause()
            elif not transport_paused and screen.has_method("lab_preview_resume"):
                screen.lab_preview_resume()
    source_mode = next_mode
    _set_source_visibility()
    _collect_slots()
    _attach_materials()
    _normalize_target()
    _refresh_slot_picker()
    _sync_controls()
    _update_target_controls()
    _apply_fx()
    _refresh_assignment_view()

func _on_target_mode(index: int) -> void:
    if index >= 0 and index < TARGET_MODES.size():
        target_mode = TARGET_MODES[index]
    _update_target_controls()
    _apply_fx()
    _refresh_assignment_view()

func _on_target_role(index: int) -> void:
    if index >= 0 and index < TARGET_ROLES.size():
        target_role = TARGET_ROLES[index]
    _apply_fx()
    _refresh_assignment_view()

func _on_preview_focus(index: int) -> void:
    if index >= 0 and index < PREVIEW_FOCUS_MODES.size():
        preview_focus_mode = PREVIEW_FOCUS_MODES[index]
    _apply_fx()
    status_label_text("preview focus · " + preview_focus_mode)

func _on_slot(index: int) -> void:
    if index < 0 or slot_picker == null:
        return
    selected_slot = str(slot_picker.get_item_metadata(index))
    _apply_fx()
    _refresh_assignment_view()

func _on_custom_asset(index: int) -> void:
    if index < 0 or index >= study_assets.size():
        return
    custom_asset_path = str(study_assets[index].get("path", ""))
    _refresh_custom_texture()
    if source_mode != "ELEMENT STUDY":
        _on_source_mode(1)
        if controls.has("source_mode"):
            (controls["source_mode"] as OptionButton).select(1)
    else:
        _collect_slots()
        _attach_materials()
        _normalize_target()
        _refresh_slot_picker()
        _apply_fx()
        _refresh_assignment_view()

func _on_edge_mask(index: int) -> void:
    edge_mask_path = "" if index <= 0 else mask_paths[index - 1]
    _mark_dirty()
    _apply_fx()

func _on_treatment_mask(index: int) -> void:
    treatment_mask_path = "" if index <= 0 else mask_paths[index - 1]
    _mark_dirty()
    _apply_fx()

func _on_detail(index: int) -> void:
    # Honor the incoming index: direct callers (tests/drivers) may not have
    # moved the picker; a real UI click always has. Keep both in sync.
    if detail_picker != null and index >= 0 and detail_picker.selected != index:
        detail_picker.select(index)
    _update_detail_visibility()

func _on_palette_strategy(index: int) -> void:
    if index >= 0 and index < PALETTE_STRATEGIES.size():
        _set_state("palette_strategy", float(index))

func _swap_palette() -> void:
    var a: Color = state["col_a"]
    state["col_a"] = state["col_b"]
    state["col_b"] = a
    _refresh_swatches()
    _mark_dirty()
    _apply_fx()

func _on_time_source(index: int) -> void:
    if index >= 0 and index < TIME_SOURCES.size():
        var next_source: String = TIME_SOURCES[index]
        if next_source == "FREE RUN" and time_source != "FREE RUN":
            # Preserve continuity when leaving the presentation clock. FREE RUN
            # is independent after the switch, but must not jump to its old epoch.
            free_run_time = shader_time
        time_source = next_source
    _mark_dirty()
    _update_summary()
    _refresh_header_status()

func _refresh_header_status() -> void:
    if look_label != null:
        var look_name := "factory"
        if preset_name_edit != null and preset_name_edit.text.strip_edges() != "":
            look_name = preset_name_edit.text.strip_edges()
        var authority := "FACTORY" if current_preset_name == "" and loaded_look_name == "" else ("PRODUCTION" if loaded_look_is_production else "DRAFT")
        look_label.text = "LOOK · %s · %s · %s" % [look_name, authority, "DIRTY" if dirty else "CLEAN"]
    if time_label != null:
        time_label.text = "TIME · " + time_source

func _on_pure(value: bool) -> void:
    _set_state("pure_continuous", value)

func _on_mask_enabled(value: bool) -> void:
    state["effect_mask_enabled"] = value
    _mark_dirty()
    _apply_fx()

func _on_mask_invert(value: bool) -> void:
    state["effect_mask_invert"] = value
    _mark_dirty()
    _apply_fx()

func _on_mask_base(value: bool) -> void:
    state["effect_mask_base"] = value
    _mark_dirty()
    _apply_fx()

func _on_motion_enabled(value: bool, fx: String) -> void:
    motion_enabled[fx] = value
    motion_running[fx] = false
    motion_has_fired[fx] = false
    runtime_amount[fx] = 0.0 if value else float(state["fx_amount"][fx])
    _mark_dirty()
    _apply_fx()

func _on_motion_loop(value: bool) -> void:
    motion_loop = value

func _on_motion_value(value: float, fx: String, key: String) -> void:
    motion[fx][key] = value
    _mark_dirty()

func _on_motion_choice(index: int, fx: String, key: String, items: Array) -> void:
    if index >= 0 and index < items.size():
        motion[fx][key] = items[index]
    _reset_runtime_amounts()
    _mark_dirty()

func _open_import() -> void:
    import_dialog.popup_centered_ratio(0.7)

func _store_a() -> void:
    snapshot_a = _snapshot()
    _update_preset_status("Stored A")

func _store_b() -> void:
    snapshot_b = _snapshot()
    _update_preset_status("Stored B")

func _view_a() -> void:
    _apply_snapshot(snapshot_a)

func _view_b() -> void:
    _apply_snapshot(snapshot_b)

func _report_support() -> void:
    status_label_text("FX targets %d · remaining non-look composition nodes %d" % [materials.size(), _unsupported_count()])

func _safe_smooth() -> void:
    state["pure_continuous"] = true
    state["fx_on"]["fringe"] = true
    state["fx_on"]["flow"] = true
    state["fx_on"]["dither"] = false
    state["fx_on"]["rgb"] = false
    state["fringe_coverage_mode"] = 0.0
    state["driver_sampling_mode"] = 0.0
    state["signal_posterize"] = 0.0
    state["temporal_hold"] = 0.0
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _safe_animated_fringe_preview() -> void:
    state["pure_continuous"] = true
    state["fx_on"]["fringe"] = true
    state["fx_on"]["flow"] = true
    state["fx_on"]["dither"] = false
    state["fx_on"]["rgb"] = false
    state["fringe_coverage_mode"] = 0.0
    state["driver_sampling_mode"] = 0.0
    state["signal_posterize"] = 0.0
    state["temporal_hold"] = 0.0
    motion_enabled["fringe"] = false
    motion_enabled["flow"] = false
    time_source = "FREE RUN"
    _sync_controls()
    _mark_dirty()
    _apply_fx()
    _refresh_header_status()
    status_label_text("animated Fringe preview · FREE RUN")

func _safe_vs_impact() -> void:
    target_mode = "ROLE"
    target_role = "VS MARK"
    state["pure_continuous"] = false
    state["fx_on"]["fringe"] = true
    state["fx_on"]["flow"] = true
    state["fx_on"]["rgb"] = true
    state["edge_source_mode"] = 0.0
    state["fringe_coverage_mode"] = 0.0
    motion_enabled["fringe"] = true
    motion["fringe"]["anchor"] = "clash_impact"
    _reset_runtime_amounts()
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _safe_echo() -> void:
    target_mode = "ROLE"
    target_role = "ECHOES"
    state["pure_continuous"] = false
    state["fx_on"]["fringe"] = true
    state["fringe_coverage_mode"] = 1.0
    state["fringe_pixel"] = 3.0
    state["fringe_space"] = 1.0
    state["fx_on"]["dither"] = false
    _sync_controls()
    _mark_dirty()
    _apply_fx()

func _rescan_assets() -> void:
    _scan_assets()
    _refresh_asset_pickers()
    _refresh_custom_texture()
    _apply_fx()
    status_label_text("rescanned · %d study assets · %d masks" % [study_assets.size(), mask_paths.size()])

func _refresh_asset_pickers() -> void:
    if custom_asset_picker != null:
        custom_asset_picker.clear()
        if study_assets.is_empty():
            custom_asset_picker.add_item("NO STUDY ASSETS")
            custom_asset_picker.disabled = true
        else:
            var selected_index := 0
            for i in range(study_assets.size()):
                var item: Dictionary = study_assets[i]
                custom_asset_picker.add_item(str(item.get("label", item.get("path", "asset"))))
                custom_asset_picker.set_item_metadata(i, str(item.get("path", "")))
                if str(item.get("path", "")) == custom_asset_path:
                    selected_index = i
            custom_asset_picker.select(selected_index)
            custom_asset_picker.disabled = source_mode != "ELEMENT STUDY"
    for picker in [edge_mask_picker, treatment_mask_picker]:
        if picker != null:
            picker.clear()
            picker.add_item("NONE")
            for path in mask_paths:
                picker.add_item(path.get_file())

func _update_target_controls() -> void:
    var study := source_mode == "ELEMENT STUDY"
    if target_mode_picker != null:
        target_mode_picker.disabled = study
    if role_picker != null:
        role_picker.disabled = study or target_mode != "ROLE"
    if slot_picker != null:
        slot_picker.disabled = study or target_mode != "SELECTED"
    if custom_asset_picker != null and not study_assets.is_empty():
        custom_asset_picker.disabled = not study
    if study_zoom_spin != null:
        study_zoom_spin.editable = study
    if study_background_picker != null:
        study_background_picker.disabled = not study

func _set_control_disabled(key: String, disabled: bool) -> void:
    if controls.has(key):
        var control = controls[key]
        if control is BaseButton:
            control.disabled = disabled
        elif control is OptionButton:
            control.disabled = disabled
        elif control is Slider:
            control.editable = not disabled
        elif control is SpinBox:
            control.editable = not disabled
    if spin_controls.has(key) and spin_controls[key] is SpinBox:
        spin_controls[key].editable = not disabled

func _update_enabled_states() -> void:
    var pure := bool(state["pure_continuous"])
    # Authored quantisation values remain intact while PURE CONTINUOUS temporarily bypasses them.
    for key in ["fx_on_dither","fx_amount_dither","dither_mode","dither_space","dither_bayer_level","dither_pixel","dither_levels","dither_threshold","dither_black_point","dither_white_point","dither_gamma","dither_contrast","dither_brightness","source_pixel_size","base_mode","mono_mode","mono_space","mono_bayer_level","mono_pixel","mono_threshold","signal_posterize","temporal_hold","driver_sampling_mode","driver_pixel_size","fringe_coverage_mode","fringe_bayer_level","fringe_pixel","fringe_space"]:
        _set_control_disabled(key, pure)
    if not pure:
        var patterned_fringe := int(state["fringe_coverage_mode"]) > 0
        for key in ["fringe_bayer_level","fringe_pixel","fringe_space"]:
            _set_control_disabled(key, not patterned_fringe)
        _set_control_disabled("driver_pixel_size", int(state["driver_sampling_mode"]) == 0)
    if edge_mask_picker != null:
        edge_mask_picker.disabled = int(state["edge_source_mode"]) != 3
    if treatment_mask_picker != null:
        treatment_mask_picker.disabled = not bool(state["effect_mask_enabled"])
    # Gate F contextual disabling: pattern controls that cannot affect the
    # current output are disabled, never reset — authored values survive.
    if not pure:
        var dither_on := bool(state["fx_on"]["dither"])
        for key in ["dither_mode","dither_space","dither_bayer_level","dither_pixel","dither_levels","dither_threshold","dither_black_point","dither_white_point","dither_gamma","dither_contrast","dither_brightness"]:
            _set_control_disabled(key, not dither_on)
        if dither_on:
            _set_control_disabled("dither_bayer_level", int(state["dither_mode"]) != 1)
        var mono_on := int(state["base_mode"]) == 1
        for key in ["mono_mode","mono_space","mono_bayer_level","mono_pixel","mono_threshold"]:
            _set_control_disabled(key, not mono_on)
        if mono_on:
            _set_control_disabled("mono_bayer_level", int(state["mono_mode"]) != 1)
    # Flow is Fringe motion, not a standalone source-distortion layer.
    var fringe_on := bool(state["fx_on"]["fringe"])
    for key in ["fx_on_flow","fx_amount_flow","driver_mode","driver_sampling_mode","driver_pixel_size","flow_strength","wind_displace","flow_center_x","flow_center_y"]:
        _set_control_disabled(key, not fringe_on)
    var flow_on := fringe_on and bool(state["fx_on"]["flow"])
    for key in ["driver_mode","driver_sampling_mode","driver_pixel_size","flow_strength","wind_displace","flow_center_x","flow_center_y"]:
        _set_control_disabled(key, not flow_on)
    var mask_ready := bool(state["effect_mask_enabled"]) and treatment_mask_path != ""
    for key in ["effect_mask_invert","effect_mask_base","effect_mask_threshold","effect_mask_softness"]:
        _set_control_disabled(key, not mask_ready)

func _update_detail_visibility() -> void:
    var level := detail_picker.selected if detail_picker != null else 1
    for node in advanced_nodes:
        node.visible = level >= 1
    for node in expert_nodes:
        node.visible = level >= 2

func _refresh_slot_picker() -> void:
    if slot_picker == null:
        return
    slot_picker.clear()
    var keys := slot_nodes.keys()
    keys.sort()
    if keys.has("mark"):
        keys.erase("mark")
        keys.push_front("mark")
    var selected_index := 0
    for i in range(keys.size()):
        var key := str(keys[i])
        slot_picker.add_item(key.to_upper() + " · " + String(slot_roles.get(key, "OTHER TEXTURES")))
        slot_picker.set_item_metadata(i, key)
        if key == selected_slot:
            selected_index = i
    if slot_picker.item_count > 0:
        slot_picker.select(selected_index)
    _update_target_controls()

func _sync_controls() -> void:
    suppress_dirty = true
    if controls.has("source_mode"):
        (controls["source_mode"] as OptionButton).select(0 if source_mode == "LIVE SCREEN" else 1)
    if target_mode_picker != null:
        target_mode_picker.select(maxi(TARGET_MODES.find(target_mode),0))
    if role_picker != null:
        role_picker.select(maxi(TARGET_ROLES.find(target_role),0))
    for key in state.keys():
        if not controls.has(key):
            continue
        var control = controls[key]
        if control is Range:
            control.set_value_no_signal(float(state[key]))
            if spin_controls.has(key):
                spin_controls[key].set_value_no_signal(float(state[key]))
        elif control is BaseButton:
            control.set_pressed_no_signal(bool(state[key]))
        elif control is OptionButton:
            control.select(clampi(int(state[key]), 0, control.item_count - 1))
    for fx in FX_NAMES:
        if controls.has("fx_on_" + fx):
            controls["fx_on_" + fx].set_pressed_no_signal(bool(state["fx_on"][fx]))
        if controls.has("fx_amount_" + fx):
            controls["fx_amount_" + fx].set_value_no_signal(float(state["fx_amount"][fx]))
            if spin_controls.has("fx_amount_" + fx):
                spin_controls["fx_amount_" + fx].set_value_no_signal(float(state["fx_amount"][fx]))
        if controls.has("motion_enabled_" + fx):
            controls["motion_enabled_" + fx].set_pressed_no_signal(bool(motion_enabled[fx]))
        for key: String in ["delay","attack","hold","release","sustain"]:
            var motion_key: String = "motion_" + str(fx) + "_" + key
            if controls.has(motion_key):
                controls[motion_key].set_value_no_signal(float(motion[fx][key]))
                if spin_controls.has(motion_key):
                    spin_controls[motion_key].set_value_no_signal(float(motion[fx][key]))
        for key: String in ["anchor","attack_curve","release_curve"]:
            var motion_key: String = "motion_" + str(fx) + "_" + key
            if controls.has(motion_key):
                var option := controls[motion_key] as OptionButton
                var wanted := String(motion[fx][key])
                for i in range(option.item_count):
                    if option.get_item_text(i) == wanted:
                        option.select(i)
                        break
    if controls.has("time_source"):
        controls["time_source"].select(clampi(TIME_SOURCES.find(time_source), 0, TIME_SOURCES.size() - 1))
    if controls.has("target_mode"):
        controls["target_mode"].select(maxi(TARGET_MODES.find(target_mode), 0))
    if controls.has("target_role"):
        controls["target_role"].select(maxi(TARGET_ROLES.find(target_role), 0))
    if controls.has("source_mode"):
        controls["source_mode"].select(0 if source_mode == "LIVE SCREEN" else 1)
    if edge_mask_picker != null:
        edge_mask_picker.select(mask_paths.find(edge_mask_path) + 1 if edge_mask_path != "" else 0)
    if treatment_mask_picker != null:
        treatment_mask_picker.select(mask_paths.find(treatment_mask_path) + 1 if treatment_mask_path != "" else 0)
    if custom_asset_picker != null and custom_asset_path != "":
        for i in range(study_assets.size()):
            if str(study_assets[i].get("path", "")) == custom_asset_path:
                custom_asset_picker.select(i)
                break
    _refresh_slot_picker()
    _update_target_controls()
    _refresh_swatches()
    _update_enabled_states()
    _update_reset_buttons()
    suppress_dirty = false

func _param_meta(key: String) -> Dictionary:
    return PARAM_SCHEMA.get(key, {}) as Dictionary

func _state_slider(parent: Node, label: String, key: String) -> void:
    var meta := _param_meta(key)
    if meta.is_empty():
        push_error("FX Lab parameter schema missing: " + key)
        return
    var slider := _slider(
        parent,
        label,
        float(meta["slider_min"]),
        float(meta["slider_max"]),
        float(meta["step"]),
        float(state[key]),
        _on_state_slider.bind(key),
        bool(meta.get("bounded", false))
    )
    controls[key] = slider
    spin_controls[key] = slider.get_meta("spin")
    _reset_button(slider.get_parent(), key, _reset_state_key.bind(key))

func _state_option(parent: Node, label: String, items: Array, key: String) -> void:
    var option := _option(parent, label, items, int(state[key]), _on_state_option.bind(key))
    controls[key] = option
    _reset_button(option.get_parent(), key, _reset_state_key.bind(key))

func _state_check(parent: Node, label: String, key: String) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var check := CheckButton.new()
    check.text = label
    check.button_pressed = bool(state[key])
    check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    check.toggled.connect(_on_state_check.bind(key))
    row.add_child(check)
    controls[key] = check
    _reset_button(row, key, _reset_state_key.bind(key))

func _on_state_slider(value: float, key: String) -> void:
    _set_state(key, value)

func _on_state_option(index: int, key: String) -> void:
    _set_state(key, float(index))

func _on_state_check(value: bool, key: String) -> void:
    _set_state(key, value)

func _fx_header(parent: Node, fx: String, title: String) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var check := CheckButton.new()
    check.text = title
    check.toggled.connect(_on_fx_check.bind(fx))
    row.add_child(check)
    controls["fx_on_" + fx] = check
    _reset_button(row, "fx_on_" + fx, _reset_fx_on.bind(fx))
    var slider := HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.01
    slider.value = float(state["fx_amount"][fx])
    slider.custom_minimum_size.x = 125
    row.add_child(slider)
    controls["fx_amount_" + fx] = slider
    var spin := SpinBox.new()
    spin.min_value = 0.0
    spin.max_value = 1.0
    spin.allow_greater = true
    spin.allow_lesser = false
    spin.step = 0.01
    spin.value = slider.value
    spin.custom_minimum_size.x = 76
    spin.tooltip_text = "Slider is the ergonomic range. Numeric entry may exceed 1.0 for deliberate stress / intensity authoring."
    row.add_child(spin)
    spin_controls["fx_amount_" + fx] = spin
    slider.value_changed.connect(_on_fx_slider.bind(fx, spin))
    spin.value_changed.connect(_on_fx_spin.bind(fx, slider))
    _reset_button(row, "fx_amount_" + fx, _reset_fx_amount.bind(fx))

func _on_fx_check(value: bool, fx: String) -> void:
    _set_fx_on(fx, value)

func _on_fx_slider(value: float, fx: String, spin: SpinBox) -> void:
    spin.set_value_no_signal(value)
    _set_fx_amount(fx, value)

func _on_fx_spin(value: float, fx: String, slider: HSlider) -> void:
    slider.set_value_no_signal(value)
    _set_fx_amount(fx, value)

func _motion_slider(parent: Node, fx: String, key: String, label: String, mn: float, mx: float, step: float) -> void:
    var control_key := "motion_" + fx + "_" + key
    var bounded := key == "sustain"
    var slider := _slider(parent, label, mn, mx, step, float(motion[fx][key]), _on_motion_value.bind(fx, key), bounded)
    controls[control_key] = slider
    spin_controls[control_key] = slider.get_meta("spin")
    _reset_button(slider.get_parent(), control_key, _reset_motion_value.bind(fx, key))

func _motion_option(parent: Node, fx: String, key: String, label: String, items: Array) -> void:
    var control_key := "motion_" + fx + "_" + key
    var option := _option(parent, label, items, items.find(String(motion[fx][key])), _on_motion_choice.bind(fx, key, items))
    controls[control_key] = option
    _reset_button(option.get_parent(), control_key, _reset_motion_value.bind(fx, key))

func _slider(parent: Node, label_text: String, mn: float, mx: float, step: float, value: float, callback: Callable, bounded := false) -> HSlider:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := _label(row, label_text, 11, Color(0.62, 0.68, 0.75))
    label.custom_minimum_size.x = 135
    var slider := HSlider.new()
    slider.min_value = mn
    slider.max_value = mx
    slider.step = step
    slider.value = value
    slider.custom_minimum_size.x = 125
    row.add_child(slider)
    var spin := SpinBox.new()
    spin.min_value = mn
    spin.max_value = mx
    spin.allow_greater = not bounded
    spin.allow_lesser = (not bounded) and mn < 0.0
    spin.step = step
    spin.value = value
    spin.custom_minimum_size.x = 82
    if not bounded:
        spin.tooltip_text = "Slider = ergonomic range. Numeric entry may exceed the slider maximum."
    row.add_child(spin)
    slider.set_meta("spin", spin)
    slider.value_changed.connect(_on_slider_link.bind(spin, callback))
    spin.value_changed.connect(_on_spin_link.bind(slider, callback))
    return slider

func _on_slider_link(value: float, spin: SpinBox, callback: Callable) -> void:
    spin.set_value_no_signal(value)
    callback.call(value)

func _on_spin_link(value: float, slider: HSlider, callback: Callable) -> void:
    slider.set_value_no_signal(value)
    callback.call(value)

func _option(parent: Node, label_text: String, items: Array, selected: int, callback: Callable) -> OptionButton:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := _label(row, label_text, 11, Color(0.62, 0.68, 0.75))
    label.custom_minimum_size.x = 135
    var option := _raw_option(row, items, selected, callback)
    option.custom_minimum_size.x = 205
    return option

func _raw_option(parent: Node, items: Array, selected: int, callback: Callable) -> OptionButton:
    var option := OptionButton.new()
    for item in items:
        option.add_item(str(item))
    if not items.is_empty():
        option.selected = clampi(selected, 0, items.size() - 1)
    option.item_selected.connect(callback)
    parent.add_child(option)
    return option

func _label(parent: Node, text: String, size_px: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size_px)
    label.add_theme_color_override("font_color", color)
    # Short structural labels must NOT autowrap: an autowrap Label reports a
    # 1-px-wide / full-column-tall minimum, which collapses headline rows and
    # squeezes the whole layout once any parent row runs out of room.
    label.autowrap_mode = TextServer.AUTOWRAP_OFF
    parent.add_child(label)
    return label

func _section_group(parent: Node, title: String, section_id: String) -> VBoxContainer:
    var wrapper := VBoxContainer.new()
    parent.add_child(wrapper)
    var row := HBoxContainer.new()
    wrapper.add_child(row)
    var toggle := Button.new()
    toggle.flat = true
    toggle.text = "▾ " + title
    toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
    toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toggle.tooltip_text = "Collapse / expand this authoring section. Values are preserved."
    toggle.pressed.connect(_toggle_section.bind(section_id))
    row.add_child(toggle)
    var copy_button := Button.new()
    copy_button.text = "COPY"
    copy_button.tooltip_text = "Copy this section's authored values."
    copy_button.pressed.connect(_copy_section.bind(section_id))
    row.add_child(copy_button)
    var paste_button := Button.new()
    paste_button.text = "PASTE"
    paste_button.tooltip_text = "Paste values copied from the same section."
    paste_button.pressed.connect(_paste_section.bind(section_id))
    row.add_child(paste_button)
    var reset := Button.new()
    reset.text = "RESET SECTION"
    reset.tooltip_text = "Restore this section to its factory defaults."
    reset.pressed.connect(_reset_section.bind(section_id))
    row.add_child(reset)
    var body := VBoxContainer.new()
    wrapper.add_child(body)
    section_bodies[section_id] = body
    section_toggle_buttons[section_id] = toggle
    section_reset_buttons[section_id] = reset
    section_titles[section_id] = title
    section_collapsed[section_id] = false
    return body

func _toggle_section(section_id: String) -> void:
    if not section_bodies.has(section_id):
        return
    var collapsed := not bool(section_collapsed.get(section_id,false))
    section_collapsed[section_id] = collapsed
    var body = section_bodies[section_id]
    if body is Control:
        (body as Control).visible = not collapsed
    _refresh_section_header(section_id)

func _refresh_section_header(section_id: String) -> void:
    if not section_toggle_buttons.has(section_id):
        return
    var toggle = section_toggle_buttons[section_id]
    if not (toggle is Button):
        return
    var title := str(section_titles.get(section_id,section_id))
    var count := _section_modified_count(section_id)
    var marker := "▸ " if bool(section_collapsed.get(section_id,false)) else "▾ "
    (toggle as Button).text = marker + title + (" · %d ≠ default" % count if count > 0 else "")

func _section(parent: Node, title: String, reset_section := "") -> void:
    if reset_section == "":
        _label(parent, "── " + title, 12, Color(0.35, 0.78, 0.65))
        return
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := _label(row, "── " + title, 12, Color(0.35, 0.78, 0.65))
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var copy_button := Button.new()
    copy_button.text = "COPY"
    copy_button.tooltip_text = "Copy this section's authored values."
    copy_button.pressed.connect(_copy_section.bind(reset_section))
    row.add_child(copy_button)
    var paste_button := Button.new()
    paste_button.text = "PASTE"
    paste_button.tooltip_text = "Paste values copied from the same section."
    paste_button.pressed.connect(_paste_section.bind(reset_section))
    row.add_child(paste_button)
    var button := Button.new()
    button.text = "RESET SECTION"
    button.tooltip_text = "Restore this section to its factory defaults."
    button.pressed.connect(_reset_section.bind(reset_section))
    row.add_child(button)
    section_reset_buttons[reset_section] = button

func _reset_button(parent: Node, key: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = "↺"
    button.custom_minimum_size.x = 28
    button.tooltip_text = "Reset only this setting to its factory default."
    button.pressed.connect(callback)
    parent.add_child(button)
    reset_buttons[key] = button
    return button

func _button(parent: Node, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _swatch(parent: Node, which_a: bool) -> void:
    var key := "col_a" if which_a else "col_b"
    var rect := ColorRect.new()
    rect.color = state[key]
    rect.custom_minimum_size = Vector2(44, 24)
    parent.add_child(rect)
    var picker := ColorPickerButton.new()
    picker.color = rect.color
    picker.custom_minimum_size = Vector2(34, 24)
    picker.color_changed.connect(_on_color.bind(which_a, rect))
    parent.add_child(picker)
    _reset_button(parent, key, _reset_state_key.bind(key))
    swatches.append({"rect": rect, "picker": picker, "a": which_a})

func _on_color(color: Color, which_a: bool, rect: ColorRect) -> void:
    state["col_a" if which_a else "col_b"] = color
    rect.color = color
    _mark_dirty()
    _apply_fx()

func _refresh_swatches() -> void:
    for item in swatches:
        var color: Color = state["col_a"] if bool(item["a"]) else state["col_b"]
        item["rect"].color = color
        item["picker"].color = color

func _palette_adjust(color: Color, hue_delta := 0.0, value_factor := 1.0, saturation_factor := 1.0) -> Color:
    var hue := fposmod(color.h + hue_delta + float(state["palette_hue_offset"]) / 360.0, 1.0)
    var saturation := clampf(color.s * float(state["palette_saturation"]) * saturation_factor, 0.0, 1.0)
    var value := clampf(color.v * float(state["palette_value"]) * value_factor, 0.0, 1.0)
    return Color.from_hsv(hue, saturation, value, color.a)

func _source_palette_candidates() -> Array[Color]:
    var result: Array[Color] = []
    var targets := _target_keys()
    if targets.is_empty():
        return result
    var node = slot_nodes.get(targets[0])
    if not (node is TextureRect) or node.texture == null:
        return result
    var img: Image = node.texture.get_image()
    if img == null:
        return result
    img = img.duplicate()
    img.resize(48, 48, Image.INTERPOLATE_BILINEAR)
    var bins := {}
    var source_tint: Color = node.get_meta("fx_source_tint",Color.WHITE)
    for y in range(48):
        for x in range(48):
            var color := img.get_pixel(x, y)
            color = Color(color.r*source_tint.r,color.g*source_tint.g,color.b*source_tint.b,color.a*source_tint.a)
            if color.a < 0.02:
                continue
            var key := Vector3i(int(color.r * 8.0), int(color.g * 8.0), int(color.b * 8.0))
            bins[key] = float(bins.get(key, 0.0)) + 1.0 + color.s * 2.0
    var keys := bins.keys()
    if keys.is_empty():
        return result
    keys.sort_custom(func(a, b): return float(bins[a]) > float(bins[b]))
    for item in keys.slice(0, mini(12, keys.size())):
        var value: Vector3i = item
        result.append(Color(value.x / 8.0, value.y / 8.0, value.z / 8.0))
    return result

func _auto_palette() -> void:
    var candidates := _source_palette_candidates()
    if candidates.is_empty():
        status_label_text("palette · no texture target")
        return
    var dominant: Color = candidates[0]
    var distant: Color = dominant
    var best_distance := -1.0
    for candidate in candidates:
        var distance := absf(candidate.r - dominant.r) + absf(candidate.g - dominant.g) + absf(candidate.b - dominant.b)
        if distance > best_distance:
            best_distance = distance
            distant = candidate
    var strategy_index := clampi(int(state["palette_strategy"]), 0, PALETTE_STRATEGIES.size() - 1)
    var color_a := dominant
    var color_b := distant
    match strategy_index:
        1: # dominant + complement
            color_a = _palette_adjust(dominant)
            color_b = _palette_adjust(dominant, 0.5)
        2: # split complementary pair around the opposite hue
            color_a = _palette_adjust(dominant, 5.0 / 12.0)
            color_b = _palette_adjust(dominant, 7.0 / 12.0)
        3: # analogous pair around dominant
            color_a = _palette_adjust(dominant, -1.0 / 12.0)
            color_b = _palette_adjust(dominant, 1.0 / 12.0)
        4: # triadic pair derived from dominant
            color_a = _palette_adjust(dominant, 1.0 / 3.0)
            color_b = _palette_adjust(dominant, 2.0 / 3.0)
        5: # monochrome light/dark
            color_a = _palette_adjust(dominant, 0.0, 1.25, 0.9)
            color_b = _palette_adjust(dominant, 0.0, 0.55, 0.75)
        _:
            color_a = _palette_adjust(dominant)
            color_b = _palette_adjust(distant)
    if not bool(state["palette_lock_a"]):
        state["col_a"] = color_a
    if not bool(state["palette_lock_b"]):
        state["col_b"] = color_b
    _refresh_swatches()
    _mark_dirty()
    _apply_fx()
    status_label_text("palette · " + PALETTE_STRATEGIES[strategy_index])

func status_label_text(text: String) -> void:
    if status_label != null:
        status_label.text = text

class TimelineView extends Control:
    var lab: Node
    const MARGIN := 46.0

    func _draw() -> void:
        if lab == null:
            return
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.07, 0.095, 1.0))
        var t_end: float = maxf(lab.timeline_len, lab._hold_start() + 0.8)
        var span := maxf(size.x - MARGIN - 20.0, 1.0)
        var font := ThemeDB.fallback_font
        var sec := 0.0
        while sec <= t_end + 0.001:
            var x := MARGIN + sec / t_end * span
            draw_line(Vector2(x, 6), Vector2(x, size.y - 6), Color(1, 1, 1, 0.06), 1.0)
            draw_string(font, Vector2(x + 2, size.y - 4), "%.1f" % sec, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.62))
            sec += 0.2
        # deterministic label lanes: stagger cue labels so they never overlap
        var lane_ends := []
        for name in ["vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]:
            var at := float(lab.event_marks.get(name, 0.0))
            var x := MARGIN + at / t_end * span
            draw_line(Vector2(x, 5), Vector2(x, size.y - 20), Color(0.95, 0.4, 0.75, 0.5), 1.0)
            var label_w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
            var lane := 0
            while lane < lane_ends.size() and x - 2.0 < lane_ends[lane]:
                lane += 1
            if lane == lane_ends.size():
                lane_ends.append(0.0)
            lane_ends[lane] = x + label_w
            draw_string(font, Vector2(x + 2, 16 + lane * 11), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.55, 0.8))

        # Active amount envelopes are shown as compact authored bands. This is
        # deliberately separate from Fringe's procedural driver motion: these
        # bands describe only the effect amount Attack/Hold/Release envelope.
        var envelope_row := 0
        for fx in lab.FX_NAMES:
            if not bool(lab.motion_enabled.get(fx,false)):
                continue
            var spec: Dictionary = lab.motion[fx]
            var anchor := str(spec.get("anchor","manual"))
            var y := 64.0 + float(envelope_row) * 9.0
            draw_string(font, Vector2(4.0,y+7.0), str(fx).substr(0,3).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 28, 8, Color(0.62,0.72,0.82))
            if anchor == "manual":
                draw_string(font, Vector2(MARGIN+2.0,y+7.0), "MANUAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.62,0.68,0.74))
                envelope_row += 1
                continue
            var start := float(lab.event_marks.get(anchor,0.0)) + float(spec.get("delay",0.0))
            var attack_end := start + maxf(float(spec.get("attack",0.0)),0.0)
            var hold_end := attack_end + maxf(float(spec.get("hold",0.0)),0.0)
            var release_end := hold_end + maxf(float(spec.get("release",0.0)),0.0)
            var x0 := MARGIN + clampf(start/t_end,0.0,1.0)*span
            var x1 := MARGIN + clampf(attack_end/t_end,0.0,1.0)*span
            var x2 := MARGIN + clampf(hold_end/t_end,0.0,1.0)*span
            var x3 := MARGIN + clampf(release_end/t_end,0.0,1.0)*span
            draw_rect(Rect2(Vector2(x0,y),Vector2(maxf(x1-x0,1.0),6.0)),Color(0.45,0.78,0.96,0.42))
            draw_rect(Rect2(Vector2(x1,y),Vector2(maxf(x2-x1,1.0),6.0)),Color(0.96,0.78,0.35,0.72))
            draw_rect(Rect2(Vector2(x2,y),Vector2(maxf(x3-x2,1.0),6.0)),Color(0.91,0.48,0.75,0.42))
            if float(spec.get("sustain",0.0)) > 0.001 and x3 < MARGIN+span:
                draw_line(Vector2(x3,y+3.0),Vector2(MARGIN+span,y+3.0),Color(0.91,0.48,0.75,0.46),2.0)
            envelope_row += 1
        var px := MARGIN + clampf(lab.preview_t, 0.0, t_end) / t_end * span
        draw_line(Vector2(px, 3), Vector2(px, size.y - 3), Color(1, 0.9, 0.5), 2.0)
        draw_circle(Vector2(px, 8), 4.0, Color(1, 0.9, 0.5))

    func _gui_input(event: InputEvent) -> void:
        if event is InputEventMouseButton:
            var mouse := event as InputEventMouseButton
            if mouse.button_index == MOUSE_BUTTON_LEFT:
                lab.transport_dragging = mouse.pressed
                if mouse.pressed:
                    _seek(mouse.position.x)
        elif event is InputEventMouseMotion:
            var motion_event := event as InputEventMouseMotion
            if (motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
                lab.transport_dragging = true
                _seek(motion_event.position.x)
            else:
                lab.transport_dragging = false

    func _seek(x: float) -> void:
        var span := maxf(size.x - MARGIN - 20.0, 1.0)
        var t_end: float = maxf(lab.timeline_len, lab._hold_start() + 0.8)
        var t := clampf((x - MARGIN) / span, 0.0, 1.0) * t_end
        lab._transport_seek_to(t)
