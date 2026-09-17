extends Node2D

## VFX Lab — all UI built in script. No scene file UI nodes.
## ============================================================================

const MAP_PATH  := "res://assets/map/beauty_placeholder.png"
const PORTRAIT_DIR := "res://assets/test_portraits"
const PORTRAIT_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

const VIEW_SIZE := Vector2(1280, 720)
const SIDE_PANEL_LEFT := 936.0
const SIDE_PANEL_RIGHT := 1280.0
const PORTRAIT_HEIGHT := 600.0
const PORTRAIT_TOP := -20.0
const PRESET_PATH := "user://vfx_lab_presets.cfg"
const PRESET_SHADER_PARAMS := [
	"threshold",
	"black_point",
	"white_point",
	"gamma_corr",
	"contrast",
	"brightness",
	"source_layout_mode",
	"dither_mode",
	"bayer_level",
	"flow_strength",
	"flow_center_x",
	"flow_center_y",
	"edge_threshold",
	"wind_reach",
	"wind_trail",
	"wind_cutoff",
	"split_separation",
	"wind_displace",
	"signal_gain",
	"color_blur",
	"temporal_hold",
	"signal_softness",
	"signal_posterize",
	"panel_edge_guard",
	"dither_pixel",
	"rgb_dither",
	"rgb_mask_enabled",
	"rgb_outer_coverage",
	"rgb_mask_feather",
	"rgb_mask_x",
	"rgb_mask_y",
	"rgb_mask_size_x",
	"rgb_mask_size_y",
	"rgb_green_color",
	"rgb_magenta_color",
	"rgb_gradient",
	"rgb_intensity",
	"rgb_gradient_balance",
	"rgb_gradient_contrast",
	"driver_mode",
	"FIELD_STRENGTH",
	"FIELD_SPEED",
	"FIELD_SIZE",
	"OUTWARDNESS",
	"FIELD_BREAKUP",
	"COORD_NUDGE",
	"FIELD_CENTER",
	"LEGACY_SCALE",
	"LEGACY_SPEED",
	"LEGACY_RADIAL",
	"DRIVER_CENTER",
	"DRIVER_SCALE",
	"DRIVER_STRETCH",
	"DRIVER_ANGLE",
	"DRIVER_SPEED",
	"DRIVER_DETAIL",
	"DRIVER_FLOW",
]
# Actually adjustable at runtime — see _build_ui and _apply_portrait_rect.

@onready var scene_vp: SubViewport      = $SceneVP
@onready var scene_bg: Sprite2D        = $"SceneVP/SceneBg"
@onready var map_sprite: Sprite2D       = $"SceneVP/MapSprite"
@onready var portrait_rect: TextureRect = $"SceneVP/PortraitRect"
@onready var side_panel_bg: Sprite2D    = $"SceneVP/SidePanelBg"
@onready var panel_edge: Sprite2D       = $"SceneVP/PanelEdge"

var portrait_idx := 0
var portrait_paths: PackedStringArray = []
var source_view_mode := 0
var flow_on      := true
var flow_strength_value := 12.0
var field_center_value := Vector2(1.25, 1.45)
var fps_acc      := 0.0
var fps_frames   := 0
var mat: ShaderMaterial
var fps_label: Label
var preset_status_label: Label
var preset_picker: OptionButton
var preset_name_edit: LineEdit
var flow_button: Button
var portrait_picker: OptionButton
var source_view_picker: OptionButton
var driver_picker: OptionButton
var dither_picker: OptionButton
var bayer_picker: OptionButton
var color_mode_picker: OptionButton
var mask_enabled_checkbox: CheckBox
var bayer_size_control: Control
var v1_driver_controls := []
var legacy_driver_controls := []
var generic_driver_controls := []
var position_driver_controls := []
var driver_shape_controls := []
var composite_layout_controls := []
var fullscreen_layout_controls := []
var portrait_source_controls := []
var composite_only_controls := []
var shader_sliders := {}
var slider_value_fields := {}
var slider_decimals := {}
var color_pickers := {}
var debug_shader: Shader
var debug_mode := 0
var mask_preview_time := 0.0
var ui_dirty_enabled := false
var suppress_dirty := false
var current_preset_name := ""
var has_unsaved_changes := false

func _ready() -> void:
	scene_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh_portrait_paths()
	_setup_side_panel_bg()
	_configure_portrait_rect()
	_load_map_texture()
	_setup_display()
	_build_ui()
	_load_portrait(0)
	_apply_nrcu_workbench()


func _apply_nrcu_workbench() -> void:
	# ---- NRCU adaptations: the lab is a fighter-art workbench ----
	# no map content, dark stage-like background, portrait shown large on the
	# right so the fighter reads at working size next to the controls.
	map_sprite.visible = false
	panel_edge.visible = false
	scene_bg.self_modulate = Color(0.043, 0.055, 0.078)
	source_view_mode = 1          # fullscreen portrait layout
	portrait_full_scale = 1.0
	portrait_full_x = 255.0
	portrait_full_y = 0.0
	mat.set_shader_parameter("source_layout_mode", 1.0)
	portrait_full_scale = maxf(portrait_full_scale, 0.25)
	_apply_portrait_rect()
	_sync_source_visibility()
	if source_view_picker != null:
		source_view_picker.select(1)


func _setup_side_panel_bg() -> void:
	# Create 1x1 white textures and tint them to fill the viewport background,
	# sidepanel, and divider. We use Sprite2D (Node2D) instead of ColorRect
	# (Control) because Controls are unreliable as direct children of
	# SubViewport on gl_compatibility.
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)

	# Full-viewport black backdrop — covers any gap left by the map.
	scene_bg.texture = tex
	scene_bg.self_modulate = Color.BLACK
	scene_bg.centered = true

	# Side panel black fill (x = 936–1280).
	side_panel_bg.texture = tex
	side_panel_bg.self_modulate = Color.BLACK
	side_panel_bg.centered = true

	# Divider line (x = 934–936).
	panel_edge.texture = tex
	panel_edge.self_modulate = Color(0.3, 0.28, 0.22, 1.0)
	panel_edge.centered = true


func _process(dt: float) -> void:
	fps_frames += 1; fps_acc += dt
	if fps_acc >= 0.5:
		fps_label.text = "FPS: %.0f" % (fps_frames / fps_acc)
		fps_acc = 0.0; fps_frames = 0
	if mask_preview_time > 0.0:
		mask_preview_time -= dt
		if mask_preview_time <= 0.0:
			mat.set_shader_parameter("rgb_mask_preview", 0.0)
	_apply_shader_inputs()


func _setup_display() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/dither_rgb.gdshader")
	_apply_shader_inputs()
	_apply_default_shader_params()
	var l := CanvasLayer.new(); l.layer = 1; add_child(l)
	var r := ColorRect.new(); r.size = VIEW_SIZE
	r.color = Color.BLACK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.material = mat
	l.add_child(r)


func _apply_shader_inputs() -> void:
	mat.set_shader_parameter("source_tex", scene_vp.get_texture())
	mat.set_shader_parameter("tex_size", VIEW_SIZE)
	mat.set_shader_parameter("portrait_bounds", _portrait_bounds())


func _apply_default_shader_params() -> void:
	mat.set_shader_parameter("threshold", 0.75)
	mat.set_shader_parameter("black_point", 0.0)
	mat.set_shader_parameter("white_point", 1.0)
	mat.set_shader_parameter("gamma_corr", 1.35)
	mat.set_shader_parameter("contrast", 1.6)
	mat.set_shader_parameter("brightness", 0.0)
	mat.set_shader_parameter("source_layout_mode", float(source_view_mode))
	mat.set_shader_parameter("dither_mode", 1.0)
	mat.set_shader_parameter("bayer_level", 2.0)
	mat.set_shader_parameter("flow_strength", 12.0)
	mat.set_shader_parameter("flow_center_x", 0.5)
	mat.set_shader_parameter("flow_center_y", 0.5)
	mat.set_shader_parameter("edge_threshold", 0.08)
	mat.set_shader_parameter("wind_reach", 32.0)
	mat.set_shader_parameter("wind_trail", 0.35)
	mat.set_shader_parameter("wind_cutoff", 0.22)
	mat.set_shader_parameter("split_separation", 0.85)
	mat.set_shader_parameter("wind_displace", 1.0)
	mat.set_shader_parameter("signal_gain", 1.35)
	mat.set_shader_parameter("color_blur", 0.0)
	mat.set_shader_parameter("temporal_hold", 0.0)
	mat.set_shader_parameter("signal_softness", 0.0)
	mat.set_shader_parameter("signal_posterize", 0.0)
	mat.set_shader_parameter("panel_edge_guard", 3.0)
	mat.set_shader_parameter("dither_scale", 1.0)
	mat.set_shader_parameter("dither_pixel", 2.0)
	mat.set_shader_parameter("rgb_dither", 1.0)
	mat.set_shader_parameter("rgb_mask_enabled", 1.0)
	mat.set_shader_parameter("rgb_outer_coverage", 1.0)
	mat.set_shader_parameter("rgb_mask_feather", 0.28)
	mat.set_shader_parameter("rgb_mask_x", 0.5)
	mat.set_shader_parameter("rgb_mask_y", 0.5)
	mat.set_shader_parameter("rgb_mask_size", 0.72)
	mat.set_shader_parameter("rgb_mask_size_x", 0.72)
	mat.set_shader_parameter("rgb_mask_size_y", 0.72)
	mat.set_shader_parameter("rgb_mask_preview", 0.0)
	mat.set_shader_parameter("rgb_green_color", Color(0.0, 1.0, 0.0, 1.0))
	mat.set_shader_parameter("rgb_magenta_color", Color(1.0, 0.0, 1.0, 1.0))
	mat.set_shader_parameter("rgb_gradient", 0.0)
	mat.set_shader_parameter("rgb_intensity", 1.0)
	mat.set_shader_parameter("rgb_gradient_balance", 0.0)
	mat.set_shader_parameter("rgb_gradient_contrast", 1.0)
	mat.set_shader_parameter("driver_mode", 0.0)
	mat.set_shader_parameter("FIELD_STRENGTH", 0.42)
	mat.set_shader_parameter("FIELD_SPEED", 0.55)
	mat.set_shader_parameter("FIELD_SIZE", 1.0)
	mat.set_shader_parameter("OUTWARDNESS", 0.55)
	mat.set_shader_parameter("FIELD_BREAKUP", 0.85)
	mat.set_shader_parameter("COORD_NUDGE", 0.18)
	mat.set_shader_parameter("FIELD_CENTER", field_center_value)
	mat.set_shader_parameter("LEGACY_SCALE", 5.0)
	mat.set_shader_parameter("LEGACY_SPEED", 0.3)
	mat.set_shader_parameter("LEGACY_RADIAL", 0.45)
	mat.set_shader_parameter("DRIVER_CENTER", Vector2(1.5, 1.5))
	mat.set_shader_parameter("DRIVER_SCALE", 1.0)
	mat.set_shader_parameter("DRIVER_STRETCH", 0.0)
	mat.set_shader_parameter("DRIVER_ANGLE", 0.0)
	mat.set_shader_parameter("DRIVER_SPEED", 1.0)
	mat.set_shader_parameter("DRIVER_DETAIL", 0.5)
	mat.set_shader_parameter("DRIVER_FLOW", 0.5)


func _set_field_center_x(v: float) -> void:
	field_center_value.x = v
	mat.set_shader_parameter("FIELD_CENTER", field_center_value)


func _set_field_center_y(v: float) -> void:
	field_center_value.y = v
	mat.set_shader_parameter("FIELD_CENTER", field_center_value)


func _set_driver_center_x(v: float) -> void:
	var center := mat.get_shader_parameter("DRIVER_CENTER") as Vector2
	center.x = v
	mat.set_shader_parameter("DRIVER_CENTER", center)


func _set_driver_center_y(v: float) -> void:
	var center := mat.get_shader_parameter("DRIVER_CENTER") as Vector2
	center.y = v
	mat.set_shader_parameter("DRIVER_CENTER", center)


func _set_temporal_hold(v: float) -> void:
	var hold := float(_sanitize_shader_param("temporal_hold", v))
	mat.set_shader_parameter("temporal_hold", hold)
	if not is_equal_approx(hold, v) and shader_sliders.has("temporal_hold"):
		var slider := shader_sliders["temporal_hold"] as HSlider
		if slider != null and not is_equal_approx(slider.value, hold):
			slider.value = hold


func _set_signal_posterize(v: float) -> void:
	var bands := float(_sanitize_shader_param("signal_posterize", v))
	mat.set_shader_parameter("signal_posterize", bands)
	if not is_equal_approx(bands, v) and shader_sliders.has("signal_posterize"):
		var slider := shader_sliders["signal_posterize"] as HSlider
		if slider != null and not is_equal_approx(slider.value, bands):
			slider.value = bands


func _show_mask_preview() -> void:
	mask_preview_time = 0.75
	mat.set_shader_parameter("rgb_mask_preview", 1.0)


func _set_mask_param(param: String, value: float) -> void:
	mat.set_shader_parameter(param, value)
	if not suppress_dirty:
		_show_mask_preview()


func _mark_dirty() -> void:
	if not ui_dirty_enabled or suppress_dirty:
		return
	has_unsaved_changes = true
	_update_preset_status()


func _update_preset_status(message := "") -> void:
	if preset_status_label == null:
		return
	if message != "":
		preset_status_label.text = message
		return
	if has_unsaved_changes:
		preset_status_label.text = "Unsaved changes" if current_preset_name == "" else "Unsaved changes: %s" % current_preset_name
	elif current_preset_name != "":
		preset_status_label.text = "Loaded: %s" % current_preset_name
	else:
		preset_status_label.text = "No preset loaded"


func _sync_flow_button() -> void:
	if flow_button != null:
		flow_button.text = "Flow " + ("ON" if flow_on else "OFF")


func _save_preset(slot: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PRESET_PATH)
	for param in PRESET_SHADER_PARAMS:
		var value = _sanitize_shader_param(param, mat.get_shader_parameter(param))
		cfg.set_value(slot, param, value)
		mat.set_shader_parameter(param, value)
	cfg.set_value(slot, "flow_on", flow_on)
	cfg.set_value(slot, "source_view_mode", source_view_mode)
	cfg.set_value(slot, "portrait_idx", portrait_idx)
	if portrait_idx >= 0 and portrait_idx < portrait_paths.size():
		cfg.set_value(slot, "portrait_path", portrait_paths[portrait_idx])
	cfg.set_value(slot, "portrait_height", portrait_height)
	cfg.set_value(slot, "portrait_top", portrait_top)
	cfg.set_value(slot, "portrait_full_scale", portrait_full_scale)
	cfg.set_value(slot, "portrait_full_x", portrait_full_x)
	cfg.set_value(slot, "portrait_full_y", portrait_full_y)
	var err := cfg.save(PRESET_PATH)
	_sync_controls_from_state()
	current_preset_name = slot
	has_unsaved_changes = false
	if preset_status_label != null:
		preset_status_label.text = "Saved: %s" % slot if err == OK else "Save failed"


func _load_preset(slot: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PRESET_PATH) != OK or not cfg.has_section(slot):
		if preset_status_label != null:
			preset_status_label.text = "No preset %s" % slot
		return
	for param in PRESET_SHADER_PARAMS:
		if cfg.has_section_key(slot, param):
			var value = _sanitize_shader_param(param, cfg.get_value(slot, param))
			if param == "FIELD_CENTER":
				field_center_value = value
			elif param == "flow_strength":
				flow_strength_value = value
			mat.set_shader_parameter(param, value)
	if cfg.has_section_key(slot, "rgb_mask_size") and not cfg.has_section_key(slot, "rgb_mask_size_x"):
		var old_size := float(_sanitize_shader_param("rgb_mask_size_x", cfg.get_value(slot, "rgb_mask_size")))
		mat.set_shader_parameter("rgb_mask_size_x", old_size)
		mat.set_shader_parameter("rgb_mask_size_y", old_size)
	flow_on = cfg.get_value(slot, "flow_on", flow_on)
	source_view_mode = int(_sanitize_shader_param("source_layout_mode", cfg.get_value(slot, "source_view_mode", mat.get_shader_parameter("source_layout_mode"))))
	portrait_idx = _resolve_portrait_index(
		cfg.get_value(slot, "portrait_path", ""),
		int(cfg.get_value(slot, "portrait_idx", portrait_idx))
	)
	portrait_height = float(cfg.get_value(slot, "portrait_height", portrait_height))
	portrait_top = float(cfg.get_value(slot, "portrait_top", portrait_top))
	portrait_full_scale = clampf(float(cfg.get_value(slot, "portrait_full_scale", portrait_full_scale)), 0.25, 4.0)
	portrait_full_x = clampf(float(cfg.get_value(slot, "portrait_full_x", portrait_full_x)), -1280.0, 1280.0)
	portrait_full_y = clampf(float(cfg.get_value(slot, "portrait_full_y", portrait_full_y)), -720.0, 720.0)
	_apply_portrait_rect()
	_set_source_view_mode(source_view_mode)
	_load_portrait(portrait_idx)
	_select_portrait_picker(portrait_idx)
	if not flow_on:
		mat.set_shader_parameter("flow_strength", 0.0)
	_set_dither_mode(int(round(float(mat.get_shader_parameter("dither_mode")))))
	_set_driver_mode(int(round(float(mat.get_shader_parameter("driver_mode")))))
	_sync_controls_from_state()
	current_preset_name = slot
	has_unsaved_changes = false
	if preset_status_label != null:
		preset_status_label.text = "Loaded: %s" % slot


func _sanitize_shader_param(param: String, value: Variant) -> Variant:
	if param == "FIELD_CENTER":
		if value is Vector2:
			return value
		return field_center_value
	if param == "DRIVER_CENTER":
		if value is Vector2:
			return value
		return mat.get_shader_parameter("DRIVER_CENTER")
	if param == "rgb_green_color" or param == "rgb_magenta_color":
		return value if value is Color else mat.get_shader_parameter(param)

	var f := float(value)
	match param:
		"threshold", "rgb_dither", "rgb_mask_enabled", "rgb_outer_coverage", "rgb_mask_x", "rgb_mask_y", "rgb_gradient", "rgb_intensity", "OUTWARDNESS", "LEGACY_RADIAL":
			return clampf(f, 0.0, 1.0)
		"flow_center_x", "flow_center_y":
			return clampf(f, 0.0, 1.0)
		"rgb_gradient_balance":
			return clampf(f, -1.0, 1.0)
		"rgb_gradient_contrast":
			return clampf(f, 0.25, 3.0)
		"rgb_mask_feather":
			return clampf(f, 0.01, 1.0)
		"rgb_mask_size", "rgb_mask_size_x", "rgb_mask_size_y":
			return clampf(f, 0.05, 2.0)
		"black_point":
			return clampf(f, 0.0, 0.5)
		"white_point":
			return clampf(f, 0.5, 1.0)
		"gamma_corr", "contrast":
			return clampf(f, 0.5, 2.5)
		"brightness":
			return clampf(f, -0.4, 0.4)
		"source_layout_mode":
			return float(clampi(int(round(f)), 0, 2))
		"dither_mode":
			return float(clampi(int(round(f)), 0, 5))
		"bayer_level":
			return float(clampi(int(round(f)), 1, 5))
		"flow_strength":
			return clampf(f, 0.0, 80.0)
		"edge_threshold":
			return clampf(f, 0.02, 0.4)
		"wind_reach":
			return clampf(f, 0.0, 300.0)
		"wind_trail":
			return clampf(f, 0.0, 1.0)
		"wind_cutoff":
			return clampf(f, 0.0, 1.0)
		"split_separation":
			return clampf(f, 0.0, 3.0)
		"wind_displace":
			return clampf(f, 0.0, 3.0)
		"signal_gain":
			return clampf(f, 0.0, 4.0)
		"color_blur":
			return clampf(f, 0.0, 300.0)
		"temporal_hold":
			return clampf(f, 0.0, 60.0)
		"signal_softness":
			return clampf(f, 0.0, 0.25)
		"signal_posterize":
			return 0.0 if f < 1.5 else clampf(f, 2.0, 12.0)
		"panel_edge_guard":
			return clampf(f, 0.0, 5.0)
		"dither_pixel":
			return clampf(f, 1.0, 5.0)
		"FIELD_STRENGTH":
			return clampf(f, 0.0, 3.0)
		"FIELD_SPEED", "LEGACY_SPEED":
			return maxf(f, 0.0)
		"FIELD_SIZE":
			return maxf(f, 0.0001)
		"FIELD_BREAKUP":
			return clampf(f, 0.05, 6.0)
		"COORD_NUDGE":
			return clampf(f, 0.0, 2.0)
		"driver_mode":
			return float(clampi(int(round(f)), 0, 13))
		"LEGACY_SCALE":
			return maxf(f, 0.0001)
		"DRIVER_SCALE":
			return maxf(f, 0.0001)
		"DRIVER_STRETCH":
			return clampf(f, -1.0, 1.0)
		"DRIVER_ANGLE":
			return f
		"DRIVER_SPEED":
			return maxf(f, 0.0)
		"DRIVER_DETAIL", "DRIVER_FLOW":
			return clampf(f, 0.0, 1.0)
	return value


func _sync_controls_from_state() -> void:
	suppress_dirty = true
	for param in shader_sliders.keys():
		var slider := shader_sliders[param] as HSlider
		if slider == null:
			continue
		var value := 0.0
		if param == "FIELD_CENTER.x":
			value = field_center_value.x
		elif param == "FIELD_CENTER.y":
			value = field_center_value.y
		elif param == "DRIVER_CENTER.x":
			value = (mat.get_shader_parameter("DRIVER_CENTER") as Vector2).x
		elif param == "DRIVER_CENTER.y":
			value = (mat.get_shader_parameter("DRIVER_CENTER") as Vector2).y
		elif param == "portrait_height":
			value = portrait_height
		elif param == "portrait_top":
			value = portrait_top
		elif param == "portrait_full_scale":
			value = portrait_full_scale
		elif param == "portrait_full_x":
			value = portrait_full_x
		elif param == "portrait_full_y":
			value = portrait_full_y
		elif param == "flow_strength":
			value = flow_strength_value
		else:
			value = float(mat.get_shader_parameter(param))
		slider.value = value
		if slider_value_fields.has(param):
			var value_edit := slider_value_fields[param] as LineEdit
			if value_edit != null:
				value_edit.text = _format_slider_value(value, int(slider_decimals.get(param, 2)))
	for param in color_pickers.keys():
		var picker := color_pickers[param] as ColorPickerButton
		if picker != null:
			picker.color = mat.get_shader_parameter(param)
	if color_mode_picker != null:
		color_mode_picker.select(int(round(float(mat.get_shader_parameter("rgb_gradient")))))
	if mask_enabled_checkbox != null:
		mask_enabled_checkbox.button_pressed = float(mat.get_shader_parameter("rgb_mask_enabled")) > 0.5
	if bayer_picker != null:
		bayer_picker.select(clampi(int(round(float(mat.get_shader_parameter("bayer_level")))) - 1, 0, 4))
	if source_view_picker != null:
		source_view_picker.select(source_view_mode)
	_sync_flow_button()
	suppress_dirty = false


func _preset_sections() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(PRESET_PATH) != OK:
		return PackedStringArray()
	return cfg.get_sections()


func _selected_preset_name() -> String:
	if preset_name_edit != null and preset_name_edit.text.strip_edges() != "":
		return preset_name_edit.text.strip_edges()
	if preset_picker != null and not preset_picker.disabled and preset_picker.selected >= 0:
		return preset_picker.get_item_text(preset_picker.selected)
	var sections := _preset_sections()
	if sections.size() > 0:
		return sections[0]
	return "Preset 1"


func _refresh_preset_list(select_name := "") -> void:
	if preset_picker == null:
		return
	preset_picker.clear()
	var sections := _preset_sections()
	for section in sections:
		preset_picker.add_item(section)
	if sections.size() == 0:
		preset_picker.add_item("No presets")
		preset_picker.disabled = true
		return
	preset_picker.disabled = false
	var selected_idx := 0
	if select_name != "":
		for i in range(sections.size()):
			if sections[i] == select_name:
				selected_idx = i
				break
	preset_picker.select(selected_idx)


func _select_preset_by_offset(offset: int) -> void:
	if preset_picker == null or preset_picker.disabled:
		_update_preset_status("No presets")
		return
	var count := preset_picker.item_count
	if count <= 0:
		return
	var next_idx := (preset_picker.selected + offset + count) % count
	preset_picker.select(next_idx)
	var preset_name := preset_picker.get_item_text(next_idx)
	_load_preset(preset_name)
	if preset_name_edit != null:
		preset_name_edit.text = preset_name


func _save_selected_preset() -> void:
	var preset_name := _selected_preset_name()
	_save_preset(preset_name)
	_refresh_preset_list(preset_name)
	if preset_name_edit != null:
		preset_name_edit.text = preset_name


func _load_selected_preset() -> void:
	if preset_picker == null or preset_picker.disabled:
		if preset_status_label != null:
			preset_status_label.text = "No preset selected"
		return
	var preset_name := preset_picker.get_item_text(preset_picker.selected)
	_load_preset(preset_name)
	if preset_name_edit != null:
		preset_name_edit.text = preset_name


func _delete_selected_preset() -> void:
	if preset_picker == null or preset_picker.disabled:
		return
	var preset_name := preset_picker.get_item_text(preset_picker.selected)
	var cfg := ConfigFile.new()
	if cfg.load(PRESET_PATH) != OK or not cfg.has_section(preset_name):
		return
	cfg.erase_section(preset_name)
	var err := cfg.save(PRESET_PATH)
	if preset_status_label != null:
		preset_status_label.text = "Deleted %s" % preset_name if err == OK else "Delete failed"
	if preset_name_edit != null:
		preset_name_edit.text = ""
	if current_preset_name == preset_name:
		current_preset_name = ""
		has_unsaved_changes = false
	_refresh_preset_list()



func _configure_portrait_rect() -> void:
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_apply_portrait_rect()


# ---- UI (all built here) ----
func _build_ui() -> void:
	var ui := CanvasLayer.new(); ui.layer = 10; add_child(ui)
	var root := Control.new(); root.offset_right = VIEW_SIZE.x; root.offset_bottom = VIEW_SIZE.y
	ui.add_child(root)
	_build_tabbed_ui(root)
	return

	# Help label background
	_rect(root, 26, 6, 420, 42, Color.BLACK)
	_label(root, 30, 8, "NRCU Fighter VFX Lab — Obligate shader core")

	# FPS
	_rect(root, 26, 696, 124, 718, Color.BLACK)
	fps_label = _label(root, 30, 698, "FPS: --")

	# Control panel background
	_rect(root, 28, 56, 368, 660, Color(0.0, 0.0, 0.0, 0.95))

	# Scroll container for sliders
	var scroll := ScrollContainer.new()
	scroll.offset_left = 32; scroll.offset_top = 60
	scroll.offset_right = 364; scroll.offset_bottom = 656
	scroll.horizontal_scroll_mode = 0
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.offset_right = 324
	vbox.custom_minimum_size = Vector2(308, 0)
	scroll.add_child(vbox)

	# ---- PRESETS section ----
	_section(vbox, "PRESETS")
	preset_picker = OptionButton.new()
	preset_picker.custom_minimum_size = Vector2(308, 0)
	vbox.add_child(preset_picker)
	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "Preset name"
	preset_name_edit.custom_minimum_size = Vector2(308, 0)
	vbox.add_child(preset_name_edit)
	var preset_buttons := HBoxContainer.new()
	var save_preset_btn := Button.new()
	save_preset_btn.text = "Save"
	save_preset_btn.custom_minimum_size = Vector2(96, 0)
	save_preset_btn.pressed.connect(_save_selected_preset)
	preset_buttons.add_child(save_preset_btn)
	var load_preset_btn := Button.new()
	load_preset_btn.text = "Load"
	load_preset_btn.custom_minimum_size = Vector2(96, 0)
	load_preset_btn.pressed.connect(_load_selected_preset)
	preset_buttons.add_child(load_preset_btn)
	var delete_preset_btn := Button.new()
	delete_preset_btn.text = "Delete"
	delete_preset_btn.custom_minimum_size = Vector2(96, 0)
	delete_preset_btn.pressed.connect(_delete_selected_preset)
	preset_buttons.add_child(delete_preset_btn)
	vbox.add_child(preset_buttons)
	preset_status_label = Label.new()
	preset_status_label.text = "Presets saved in user data"
	preset_status_label.add_theme_font_size_override("font_size", 10)
	preset_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	vbox.add_child(preset_status_label)
	_refresh_preset_list()

	# ---- SOURCE section ----
	_section(vbox, "SOURCE")
	_source_view_picker(vbox)

	# ---- DITHER section ----
	_section(vbox, "DITHER")

	_dither_picker(vbox)
	bayer_size_control = _bayer_size_picker(vbox)

	_slider(vbox, "Threshold", 0.0, 1.0, 0.01, 0.75, func(v): mat.set_shader_parameter("threshold", v), "threshold")
	_slider(vbox, "Black point", 0.0, 0.5, 0.01, 0.0, func(v): mat.set_shader_parameter("black_point", v), "black_point")
	_slider(vbox, "White point", 0.5, 1.0, 0.01, 1.0, func(v): mat.set_shader_parameter("white_point", v), "white_point")
	_slider(vbox, "Gamma", 0.5, 2.5, 0.05, 1.35, func(v): mat.set_shader_parameter("gamma_corr", v), "gamma_corr")
	_slider(vbox, "Contrast", 0.5, 2.5, 0.05, 1.6, func(v): mat.set_shader_parameter("contrast", v), "contrast")
	_slider(vbox, "Brightness", -0.4, 0.4, 0.02, 0.0, func(v): mat.set_shader_parameter("brightness", v), "brightness")
	_slider(vbox, "Pixel scale", 1.0, 5.0, 0.05, 2.0, func(v): mat.set_shader_parameter("dither_pixel", v), "dither_pixel")
	_set_dither_mode(1)

	# ---- RGB SPLIT section ----
	_section(vbox, "RGB SPLIT")

	var flow_btn := Button.new(); flow_btn.text = "Flow ON"
	flow_btn.pressed.connect(func():
		flow_on = not flow_on
		mat.set_shader_parameter("flow_strength", flow_strength_value if flow_on else 0.0)
		flow_btn.text = "Flow " + ("ON" if flow_on else "OFF"))
	vbox.add_child(flow_btn)

	_slider(vbox, "Split strength", 0.0, 40.0, 1.0, flow_strength_value, func(v):
		flow_strength_value = v
		if flow_on:
			mat.set_shader_parameter("flow_strength", v)
	, "flow_strength")
	_slider(vbox, "Edge threshold", 0.02, 0.4, 0.01, 0.08, func(v): mat.set_shader_parameter("edge_threshold", v), "edge_threshold")
	_slider(vbox, "Wind reach", 0.0, 180.0, 2.0, 32.0, func(v): mat.set_shader_parameter("wind_reach", v), "wind_reach")
	_slider(vbox, "Wind trail", 0.0, 1.0, 0.05, 0.35, func(v): mat.set_shader_parameter("wind_trail", v), "wind_trail")
	_slider(vbox, "Wind cutoff", 0.0, 0.75, 0.01, 0.22, func(v): mat.set_shader_parameter("wind_cutoff", v), "wind_cutoff")
	_slider(vbox, "Color blur", 0.0, 300.0, 1.0, 0.0, func(v): mat.set_shader_parameter("color_blur", v), "color_blur")
	_slider(vbox, "Hold FPS", 0.0, 60.0, 1.0, 0.0, func(v): _set_temporal_hold(v), "temporal_hold")
	_slider(vbox, "Signal softness", 0.0, 0.25, 0.01, 0.0, func(v): mat.set_shader_parameter("signal_softness", v), "signal_softness")
	_slider(vbox, "Signal bands", 0.0, 12.0, 1.0, 0.0, func(v): mat.set_shader_parameter("signal_posterize", v), "signal_posterize")
	_slider(vbox, "Panel guard", 0.0, 5.0, 0.25, 3.0, func(v): mat.set_shader_parameter("panel_edge_guard", v), "panel_edge_guard")
	_slider(vbox, "RGB density", 0.0, 1.0, 0.05, 1.0, func(v): mat.set_shader_parameter("rgb_dither", v), "rgb_dither")

	_section(vbox, "RGB MASK")
	_slider(vbox, "Coverage", 0.0, 1.0, 0.01, 1.0, func(v): _set_mask_param("rgb_outer_coverage", v), "rgb_outer_coverage")
	_slider(vbox, "Feather", 0.01, 1.0, 0.01, 0.28, func(v): _set_mask_param("rgb_mask_feather", v), "rgb_mask_feather")
	_slider(vbox, "X position", 0.0, 1.0, 0.01, 0.5, func(v): _set_mask_param("rgb_mask_x", v), "rgb_mask_x")
	_slider(vbox, "Y position", 0.0, 1.0, 0.01, 0.5, func(v): _set_mask_param("rgb_mask_y", v), "rgb_mask_y")
	_slider(vbox, "Size X", 0.05, 2.0, 0.01, 0.72, func(v): _set_mask_param("rgb_mask_size_x", v), "rgb_mask_size_x")
	_slider(vbox, "Size Y", 0.05, 2.0, 0.01, 0.72, func(v): _set_mask_param("rgb_mask_size_y", v), "rgb_mask_size_y")

	_section(vbox, "RGB COLORS")

	_color_mode_picker(vbox)
	_color_picker(vbox, "Magenta", "rgb_magenta_color", Color(1.0, 0.0, 1.0, 1.0))
	_color_picker(vbox, "Green", "rgb_green_color", Color(0.0, 1.0, 0.0, 1.0))

	_section(vbox, "WHISP DRIVER")

	_driver_picker(vbox)
	_slider(vbox, "Field strength", 0.0, 1.5, 0.01, 0.42, func(v): mat.set_shader_parameter("FIELD_STRENGTH", v), "FIELD_STRENGTH")
	_slider(vbox, "Coord nudge", 0.0, 1.0, 0.01, 0.18, func(v): mat.set_shader_parameter("COORD_NUDGE", v), "COORD_NUDGE")
	v1_driver_controls.append(_slider(vbox, "Field size", 0.1, 6.0, 0.01, 1.0, func(v): mat.set_shader_parameter("FIELD_SIZE", v), "FIELD_SIZE"))
	v1_driver_controls.append(_slider(vbox, "Field speed", 0.0, 2.0, 0.01, 0.55, func(v): mat.set_shader_parameter("FIELD_SPEED", v), "FIELD_SPEED"))
	v1_driver_controls.append(_slider(vbox, "Outwardness", 0.0, 1.0, 0.01, 0.55, func(v): mat.set_shader_parameter("OUTWARDNESS", v), "OUTWARDNESS"))
	v1_driver_controls.append(_slider(vbox, "Field breakup", 0.05, 3.0, 0.01, 0.85, func(v): mat.set_shader_parameter("FIELD_BREAKUP", v), "FIELD_BREAKUP"))
	v1_driver_controls.append(_slider(vbox, "Center X", -6.0, 9.0, 0.01, field_center_value.x, func(v): _set_field_center_x(v), "FIELD_CENTER.x"))
	v1_driver_controls.append(_slider(vbox, "Center Y", -6.0, 9.0, 0.01, field_center_value.y, func(v): _set_field_center_y(v), "FIELD_CENTER.y"))
	legacy_driver_controls.append(_slider(vbox, "Legacy scale", 1.0, 20.0, 0.05, 5.0, func(v): mat.set_shader_parameter("LEGACY_SCALE", v), "LEGACY_SCALE"))
	legacy_driver_controls.append(_slider(vbox, "Legacy speed", 0.0, 2.0, 0.01, 0.3, func(v): mat.set_shader_parameter("LEGACY_SPEED", v), "LEGACY_SPEED"))
	legacy_driver_controls.append(_slider(vbox, "Legacy radial", 0.0, 1.0, 0.01, 0.45, func(v): mat.set_shader_parameter("LEGACY_RADIAL", v), "LEGACY_RADIAL"))
	generic_driver_controls.append(_slider(vbox, "Driver scale", 0.1, 8.0, 0.05, 1.0, func(v): mat.set_shader_parameter("DRIVER_SCALE", v), "DRIVER_SCALE"))
	generic_driver_controls.append(_slider(vbox, "Driver speed", 0.0, 4.0, 0.01, 1.0, func(v): mat.set_shader_parameter("DRIVER_SPEED", v), "DRIVER_SPEED"))
	generic_driver_controls.append(_slider(vbox, "Driver detail", 0.0, 1.0, 0.01, 0.5, func(v): mat.set_shader_parameter("DRIVER_DETAIL", v), "DRIVER_DETAIL"))
	generic_driver_controls.append(_slider(vbox, "Driver flow", 0.0, 1.0, 0.01, 0.5, func(v): mat.set_shader_parameter("DRIVER_FLOW", v), "DRIVER_FLOW"))
	_set_driver_mode(0)

	_section(vbox, "PORTRAIT")

	composite_layout_controls.append(_slider(vbox, "Height", 200.0, 2000.0, 10.0, 1800.0, func(v):
		portrait_height = v
		_apply_portrait_rect(), "portrait_height"))
	composite_layout_controls.append(_slider(vbox, "Top", -600.0, float(VIEW_SIZE.y), 10.0, -20.0, func(v):
		portrait_top = v
		_apply_portrait_rect(), "portrait_top"))
	fullscreen_layout_controls.append(_slider(vbox, "Full scale", 0.25, 4.0, 0.01, 1.0, func(v):
		portrait_full_scale = v
		_apply_portrait_rect(), "portrait_full_scale"))
	fullscreen_layout_controls.append(_slider(vbox, "Full X", -1280.0, 1280.0, 1.0, 0.0, func(v):
		portrait_full_x = v
		_apply_portrait_rect(), "portrait_full_x"))
	fullscreen_layout_controls.append(_slider(vbox, "Full Y", -720.0, 720.0, 1.0, 0.0, func(v):
		portrait_full_y = v
		_apply_portrait_rect(), "portrait_full_y"))

	_portrait_picker(vbox)
	_set_source_view_mode(source_view_mode)

	# ---- DEBUG ----
	_build_debug_shader()
	var debug_btn := Button.new(); debug_btn.text = "Debug: RED fill"
	debug_btn.pressed.connect(func():
		debug_mode = (debug_mode + 1) % 3
		if debug_mode == 0:
			mat.shader = load("res://shaders/dither_rgb.gdshader")
			_apply_shader_inputs()
			_apply_default_shader_params()
			debug_btn.text = "Debug: OFF"
		elif debug_mode == 1:
			mat.shader = debug_shader
			_apply_shader_inputs()
			debug_btn.text = "Debug: RED (sidepanel)"
		else:
			_build_passthrough_shader()
			mat.shader = debug_shader
			_apply_shader_inputs()
			debug_btn.text = "Debug: PASSTHROUGH"
	)
	vbox.add_child(debug_btn)


func _build_tabbed_ui(root: Control) -> void:
	_rect(root, 26, 6, 420, 42, Color.BLACK)
	_label(root, 30, 8, "NRCU Fighter VFX Lab — Obligate shader core")
	_rect(root, 26, 696, 124, 718, Color.BLACK)
	fps_label = _label(root, 30, 698, "FPS: --")
	_rect(root, 28, 56, 412, 684, Color(0.0, 0.0, 0.0, 0.95))

	_build_header(root)
	_build_tabs(root)
	_build_debug_shader()

	ui_dirty_enabled = true
	_sync_source_visibility()
	_sync_driver_visibility()
	_update_preset_status()


func _build_header(root: Control) -> void:
	var header := VBoxContainer.new()
	header.offset_left = 32
	header.offset_top = 60
	header.offset_right = 404
	header.offset_bottom = 260
	header.custom_minimum_size = Vector2(360, 0)
	root.add_child(header)

	preset_picker = OptionButton.new()
	preset_picker.custom_minimum_size = Vector2(360, 0)
	header.add_child(preset_picker)

	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "Preset name"
	preset_name_edit.custom_minimum_size = Vector2(360, 0)
	header.add_child(preset_name_edit)

	var preset_buttons := HBoxContainer.new()
	_add_header_button(preset_buttons, "Prev", 52, func(): _select_preset_by_offset(-1))
	_add_header_button(preset_buttons, "Next", 52, func(): _select_preset_by_offset(1))
	_add_header_button(preset_buttons, "Save", 60, _save_selected_preset)
	_add_header_button(preset_buttons, "Load", 60, _load_selected_preset)
	_add_header_button(preset_buttons, "Delete", 64, _delete_selected_preset)
	header.add_child(preset_buttons)

	preset_status_label = Label.new()
	preset_status_label.text = "No preset loaded"
	preset_status_label.add_theme_font_size_override("font_size", 10)
	preset_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	header.add_child(preset_status_label)
	_refresh_preset_list()

	_source_view_picker(header)
	_portrait_picker(header)


func _add_header_button(parent: Control, text: String, width: float, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 0)
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _build_tabs(root: Control) -> void:
	var tabs := TabContainer.new()
	tabs.offset_left = 32
	tabs.offset_top = 266
	tabs.offset_right = 404
	tabs.offset_bottom = 680
	root.add_child(tabs)

	_build_dither_tab(_tab_vbox(tabs, "Dither"))
	_build_rgb_tab(_tab_vbox(tabs, "RGB"))
	_build_mask_tab(_tab_vbox(tabs, "Mask"))
	_build_colors_tab(_tab_vbox(tabs, "Color"))
	_build_driver_tab(_tab_vbox(tabs, "Driver"))
	_build_portrait_tab(_tab_vbox(tabs, "Layout"))
	_build_debug_tab(_tab_vbox(tabs, "Debug"))


func _tab_vbox(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = 0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(332, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	return vbox


func _build_dither_tab(vbox: Control) -> void:
	_dither_picker(vbox)
	bayer_size_control = _bayer_size_picker(vbox)
	_slider(vbox, "Threshold", 0.0, 1.0, 0.01, 0.75, func(v): mat.set_shader_parameter("threshold", v), "threshold")
	_slider(vbox, "Black point", 0.0, 0.5, 0.01, 0.0, func(v): mat.set_shader_parameter("black_point", v), "black_point")
	_slider(vbox, "White point", 0.5, 1.0, 0.01, 1.0, func(v): mat.set_shader_parameter("white_point", v), "white_point")
	_slider(vbox, "Gamma", 0.5, 2.5, 0.05, 1.35, func(v): mat.set_shader_parameter("gamma_corr", v), "gamma_corr")
	_slider(vbox, "Contrast", 0.5, 2.5, 0.05, 1.6, func(v): mat.set_shader_parameter("contrast", v), "contrast")
	_slider(vbox, "Brightness", -0.4, 0.4, 0.02, 0.0, func(v): mat.set_shader_parameter("brightness", v), "brightness")
	_slider(vbox, "Pixel scale", 1.0, 5.0, 0.05, 2.0, func(v): mat.set_shader_parameter("dither_pixel", v), "dither_pixel")
	_set_dither_mode(1)


func _build_rgb_tab(vbox: Control) -> void:
	flow_button = Button.new()
	flow_button.text = "Flow ON"
	flow_button.pressed.connect(func():
		flow_on = not flow_on
		mat.set_shader_parameter("flow_strength", flow_strength_value if flow_on else 0.0)
		_sync_flow_button()
		_mark_dirty()
	)
	vbox.add_child(flow_button)
	_slider(vbox, "Strength", 0.0, 80.0, 0.1, flow_strength_value, func(v):
		flow_strength_value = v
		if flow_on:
			mat.set_shader_parameter("flow_strength", v)
	, "flow_strength", 1)
	_slider(vbox, "Edge threshold", 0.02, 0.4, 0.01, 0.08, func(v): mat.set_shader_parameter("edge_threshold", v), "edge_threshold")
	_slider(vbox, "Reach", 0.0, 300.0, 0.5, 32.0, func(v): mat.set_shader_parameter("wind_reach", v), "wind_reach", 1)
	_slider(vbox, "Trail", 0.0, 1.0, 0.01, 0.35, func(v): mat.set_shader_parameter("wind_trail", v), "wind_trail")
	_slider(vbox, "Cutoff", 0.0, 1.0, 0.005, 0.22, func(v): mat.set_shader_parameter("wind_cutoff", v), "wind_cutoff", 3)
	_slider(vbox, "Separation", 0.0, 3.0, 0.01, 0.85, func(v): mat.set_shader_parameter("split_separation", v), "split_separation")
	_slider(vbox, "Wind displace", 0.0, 3.0, 0.01, 1.0, func(v): mat.set_shader_parameter("wind_displace", v), "wind_displace")
	_slider(vbox, "Signal gain", 0.0, 4.0, 0.01, 1.35, func(v): mat.set_shader_parameter("signal_gain", v), "signal_gain")
	_slider(vbox, "Origin X", 0.0, 1.0, 0.01, 0.5, func(v): mat.set_shader_parameter("flow_center_x", v), "flow_center_x")
	_slider(vbox, "Origin Y", 0.0, 1.0, 0.01, 0.5, func(v): mat.set_shader_parameter("flow_center_y", v), "flow_center_y")
	_slider(vbox, "Color blur", 0.0, 300.0, 0.5, 0.0, func(v): mat.set_shader_parameter("color_blur", v), "color_blur", 1)
	_slider(vbox, "Hold FPS", 0.0, 60.0, 1.0, 0.0, func(v): _set_temporal_hold(v), "temporal_hold", 0)
	_slider(vbox, "Softness", 0.0, 0.25, 0.01, 0.0, func(v): mat.set_shader_parameter("signal_softness", v), "signal_softness")
	_slider(vbox, "Bands", 0.0, 12.0, 1.0, 0.0, func(v): _set_signal_posterize(v), "signal_posterize", 0)
	composite_only_controls.append(_slider(vbox, "Panel guard", 0.0, 5.0, 0.25, 3.0, func(v): mat.set_shader_parameter("panel_edge_guard", v), "panel_edge_guard"))
	_slider(vbox, "RGB density", 0.0, 1.0, 0.01, 1.0, func(v): mat.set_shader_parameter("rgb_dither", v), "rgb_dither")


func _build_mask_tab(vbox: Control) -> void:
	mask_enabled_checkbox = CheckBox.new()
	mask_enabled_checkbox.text = "Mask enabled"
	mask_enabled_checkbox.button_pressed = true
	mask_enabled_checkbox.toggled.connect(func(is_on: bool):
		mat.set_shader_parameter("rgb_mask_enabled", 1.0 if is_on else 0.0)
		if is_on:
			_show_mask_preview()
		_mark_dirty()
	)
	vbox.add_child(mask_enabled_checkbox)
	_slider(vbox, "Coverage", 0.0, 1.0, 0.01, 1.0, func(v): _set_mask_param("rgb_outer_coverage", v), "rgb_outer_coverage")
	_slider(vbox, "Feather", 0.01, 1.0, 0.01, 0.28, func(v): _set_mask_param("rgb_mask_feather", v), "rgb_mask_feather")
	_slider(vbox, "Pos X", 0.0, 1.0, 0.01, 0.5, func(v): _set_mask_param("rgb_mask_x", v), "rgb_mask_x")
	_slider(vbox, "Pos Y", 0.0, 1.0, 0.01, 0.5, func(v): _set_mask_param("rgb_mask_y", v), "rgb_mask_y")
	_slider(vbox, "Size X", 0.05, 2.0, 0.01, 0.72, func(v): _set_mask_param("rgb_mask_size_x", v), "rgb_mask_size_x")
	_slider(vbox, "Size Y", 0.05, 2.0, 0.01, 0.72, func(v): _set_mask_param("rgb_mask_size_y", v), "rgb_mask_size_y")


func _build_colors_tab(vbox: Control) -> void:
	_color_mode_picker(vbox)
	_color_picker(vbox, "Magenta", "rgb_magenta_color", Color(1.0, 0.0, 1.0, 1.0))
	_color_picker(vbox, "Green", "rgb_green_color", Color(0.0, 1.0, 0.0, 1.0))
	_slider(vbox, "Intensity", 0.0, 1.0, 0.01, 1.0, func(v): mat.set_shader_parameter("rgb_intensity", v), "rgb_intensity")
	_slider(vbox, "Grad balance", -1.0, 1.0, 0.01, 0.0, func(v): mat.set_shader_parameter("rgb_gradient_balance", v), "rgb_gradient_balance")
	_slider(vbox, "Grad contrast", 0.25, 3.0, 0.01, 1.0, func(v): mat.set_shader_parameter("rgb_gradient_contrast", v), "rgb_gradient_contrast")
	_color_preset_buttons(vbox)


func _build_driver_tab(vbox: Control) -> void:
	_driver_picker(vbox)
	_slider(vbox, "Driver strength", 0.0, 3.0, 0.01, 0.42, func(v): mat.set_shader_parameter("FIELD_STRENGTH", v), "FIELD_STRENGTH")
	_slider(vbox, "Displace nudge", 0.0, 2.0, 0.01, 0.18, func(v): mat.set_shader_parameter("COORD_NUDGE", v), "COORD_NUDGE")
	v1_driver_controls.append(_slider(vbox, "Size", 0.0001, 12.0, 0.0001, 1.0, func(v): mat.set_shader_parameter("FIELD_SIZE", v), "FIELD_SIZE", 4, true))
	v1_driver_controls.append(_slider(vbox, "Speed", 0.0, 2.0, 0.001, 0.55, func(v): mat.set_shader_parameter("FIELD_SPEED", v), "FIELD_SPEED", 3, true))
	v1_driver_controls.append(_slider(vbox, "Outwardness", 0.0, 1.0, 0.01, 0.55, func(v): mat.set_shader_parameter("OUTWARDNESS", v), "OUTWARDNESS"))
	v1_driver_controls.append(_slider(vbox, "Breakup", 0.05, 6.0, 0.01, 0.85, func(v): mat.set_shader_parameter("FIELD_BREAKUP", v), "FIELD_BREAKUP"))
	v1_driver_controls.append(_slider(vbox, "Center X", -6.0, 9.0, 0.001, field_center_value.x, func(v): _set_field_center_x(v), "FIELD_CENTER.x", 3, true))
	v1_driver_controls.append(_slider(vbox, "Center Y", -6.0, 9.0, 0.001, field_center_value.y, func(v): _set_field_center_y(v), "FIELD_CENTER.y", 3, true))
	position_driver_controls.append(_slider(vbox, "Pos X", -6.0, 9.0, 0.001, 1.5, func(v): _set_driver_center_x(v), "DRIVER_CENTER.x", 3, true))
	position_driver_controls.append(_slider(vbox, "Pos Y", -6.0, 9.0, 0.001, 1.5, func(v): _set_driver_center_y(v), "DRIVER_CENTER.y", 3, true))
	driver_shape_controls.append(_slider(vbox, "Stretch", -1.0, 1.0, 0.01, 0.0, func(v): mat.set_shader_parameter("DRIVER_STRETCH", v), "DRIVER_STRETCH"))
	driver_shape_controls.append(_slider(vbox, "Angle", -180.0, 180.0, 0.5, 0.0, func(v): mat.set_shader_parameter("DRIVER_ANGLE", v), "DRIVER_ANGLE", 1, true))
	legacy_driver_controls.append(_slider(vbox, "Size", 0.0001, 12.0, 0.0001, 5.0, func(v): mat.set_shader_parameter("LEGACY_SCALE", v), "LEGACY_SCALE", 4, true))
	legacy_driver_controls.append(_slider(vbox, "Speed", 0.0, 2.0, 0.001, 0.3, func(v): mat.set_shader_parameter("LEGACY_SPEED", v), "LEGACY_SPEED", 3, true))
	legacy_driver_controls.append(_slider(vbox, "Radial", 0.0, 1.0, 0.01, 0.45, func(v): mat.set_shader_parameter("LEGACY_RADIAL", v), "LEGACY_RADIAL"))
	generic_driver_controls.append(_slider(vbox, "Size", 0.0001, 2.0, 0.0001, 1.0, func(v): mat.set_shader_parameter("DRIVER_SCALE", v), "DRIVER_SCALE", 4, true))
	generic_driver_controls.append(_slider(vbox, "Speed", 0.0, 2.0, 0.001, 1.0, func(v): mat.set_shader_parameter("DRIVER_SPEED", v), "DRIVER_SPEED", 3, true))
	generic_driver_controls.append(_slider(vbox, "Detail", 0.0, 1.0, 0.01, 0.5, func(v): mat.set_shader_parameter("DRIVER_DETAIL", v), "DRIVER_DETAIL"))
	generic_driver_controls.append(_slider(vbox, "Flow", 0.0, 1.0, 0.01, 0.5, func(v): mat.set_shader_parameter("DRIVER_FLOW", v), "DRIVER_FLOW"))
	_set_driver_mode(0)


func _build_portrait_tab(vbox: Control) -> void:
	composite_layout_controls.append(_slider(vbox, "Height", 200.0, 2000.0, 10.0, 1800.0, func(v):
		portrait_height = v
		_apply_portrait_rect(), "portrait_height"))
	composite_layout_controls.append(_slider(vbox, "Top", -600.0, float(VIEW_SIZE.y), 10.0, -20.0, func(v):
		portrait_top = v
		_apply_portrait_rect(), "portrait_top"))
	fullscreen_layout_controls.append(_slider(vbox, "Full scale", 0.25, 4.0, 0.01, 1.0, func(v):
		portrait_full_scale = v
		_apply_portrait_rect(), "portrait_full_scale"))
	fullscreen_layout_controls.append(_slider(vbox, "Full X", -1280.0, 1280.0, 1.0, 0.0, func(v):
		portrait_full_x = v
		_apply_portrait_rect(), "portrait_full_x"))
	fullscreen_layout_controls.append(_slider(vbox, "Full Y", -720.0, 720.0, 1.0, 0.0, func(v):
		portrait_full_y = v
		_apply_portrait_rect(), "portrait_full_y"))
	_set_source_view_mode(source_view_mode)


func _build_debug_tab(vbox: Control) -> void:
	var debug_btn := Button.new()
	debug_btn.text = "Debug: RED fill"
	debug_btn.pressed.connect(func():
		debug_mode = (debug_mode + 1) % 3
		if debug_mode == 0:
			mat.shader = load("res://shaders/dither_rgb.gdshader")
			_apply_shader_inputs()
			_apply_default_shader_params()
			debug_btn.text = "Debug: OFF"
		elif debug_mode == 1:
			mat.shader = debug_shader
			_apply_shader_inputs()
			debug_btn.text = "Debug: RED"
		else:
			_build_passthrough_shader()
			mat.shader = debug_shader
			_apply_shader_inputs()
			debug_btn.text = "Debug: PASSTHROUGH"
	)
	vbox.add_child(debug_btn)


func _build_debug_shader() -> void:
	debug_shader = Shader.new()
	debug_shader.code = """shader_type canvas_item;
uniform sampler2D source_tex : filter_nearest, repeat_disable;
void fragment() {
	// Red sidepanel, black left — proves ColorRect geometry.
	float in_panel = step(0.73125, UV.x);
	COLOR = vec4(mix(vec3(0.0), vec3(1.0, 0.0, 0.0), in_panel), 1.0);
}
"""


func _build_passthrough_shader() -> void:
	debug_shader = Shader.new()
	debug_shader.code = """shader_type canvas_item;
uniform sampler2D source_tex : filter_nearest, repeat_disable;
void fragment() {
	COLOR = texture(source_tex, UV);
}
"""


func _section(parent: Control, title: String) -> void:
	var l := Label.new(); l.text = "— %s —" % title
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.6))
	parent.add_child(l)


func _set_split_colors(magenta: Color, green: Color) -> void:
	mat.set_shader_parameter("rgb_magenta_color", magenta)
	mat.set_shader_parameter("rgb_green_color", green)
	if color_pickers.has("rgb_magenta_color"):
		var magenta_picker := color_pickers["rgb_magenta_color"] as ColorPickerButton
		if magenta_picker != null:
			magenta_picker.color = magenta
	if color_pickers.has("rgb_green_color"):
		var green_picker := color_pickers["rgb_green_color"] as ColorPickerButton
		if green_picker != null:
			green_picker.color = green
	_mark_dirty()


func _swap_split_colors() -> void:
	var magenta := mat.get_shader_parameter("rgb_magenta_color") as Color
	var green := mat.get_shader_parameter("rgb_green_color") as Color
	_set_split_colors(green, magenta)


func _reset_split_colors() -> void:
	_set_split_colors(Color(1.0, 0.0, 1.0, 1.0), Color(0.0, 1.0, 0.0, 1.0))


func _color_preset_buttons(parent: Control) -> void:
	var row_a := HBoxContainer.new()
	var swap_btn := Button.new()
	swap_btn.text = "Swap"
	swap_btn.custom_minimum_size = Vector2(70, 0)
	swap_btn.pressed.connect(_swap_split_colors)
	row_a.add_child(swap_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(70, 0)
	reset_btn.pressed.connect(_reset_split_colors)
	row_a.add_child(reset_btn)
	parent.add_child(row_a)

	var row_b := HBoxContainer.new()
	var presets := [
		["Cyber", Color(1.0, 0.0, 1.0, 1.0), Color(0.0, 1.0, 0.0, 1.0)],
		["Acid", Color(0.9, 0.0, 1.0, 1.0), Color(0.7, 1.0, 0.0, 1.0)],
		["Ice", Color(0.25, 0.55, 1.0, 1.0), Color(0.75, 1.0, 1.0, 1.0)],
		["Fire", Color(1.0, 0.08, 0.0, 1.0), Color(1.0, 0.85, 0.1, 1.0)],
		["Mono", Color(0.05, 0.05, 0.05, 1.0), Color(1.0, 1.0, 1.0, 1.0)],
	]
	for preset in presets:
		var preset_magenta := preset[1] as Color
		var preset_green := preset[2] as Color
		var btn := Button.new()
		btn.text = str(preset[0])
		btn.custom_minimum_size = Vector2(58, 0)
		btn.pressed.connect(func(): _set_split_colors(preset_magenta, preset_green))
		row_b.add_child(btn)
	parent.add_child(row_b)


func _color_picker(parent: Control, label: String, param: String, default_color: Color) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.color = default_color
	picker.custom_minimum_size = Vector2(96, 24)
	picker.color_changed.connect(func(c: Color):
		mat.set_shader_parameter(param, c)
		_mark_dirty()
	)
	color_pickers[param] = picker
	row.add_child(picker)
	parent.add_child(row)


func _color_mode_picker(parent: Control) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Mode"
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	color_mode_picker = OptionButton.new()
	color_mode_picker.custom_minimum_size = Vector2(170, 0)
	color_mode_picker.add_item("Two colors", 0)
	color_mode_picker.add_item("Gradient", 1)
	color_mode_picker.item_selected.connect(func(index: int):
		mat.set_shader_parameter("rgb_gradient", float(index))
		_mark_dirty()
	)
	row.add_child(color_mode_picker)
	parent.add_child(row)


func _dither_picker(parent: Control) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Algorithm"
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	dither_picker = OptionButton.new()
	dither_picker.custom_minimum_size = Vector2(170, 0)
	dither_picker.add_item("Threshold", 0)
	dither_picker.add_item("Bayer", 1)
	dither_picker.add_item("Blue noise", 2)
	dither_picker.add_item("Random", 3)
	dither_picker.add_item("Dot diffusion", 4)
	dither_picker.add_item("Halftone", 5)
	dither_picker.item_selected.connect(func(index: int): _set_dither_mode(index))
	row.add_child(dither_picker)
	parent.add_child(row)


func _bayer_size_picker(parent: Control) -> Control:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Bayer size"
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	bayer_picker = OptionButton.new()
	bayer_picker.custom_minimum_size = Vector2(170, 0)
	bayer_picker.add_item("2x2", 0)
	bayer_picker.add_item("4x4", 1)
	bayer_picker.add_item("8x8", 2)
	bayer_picker.add_item("16x16", 3)
	bayer_picker.add_item("32x32", 4)
	bayer_picker.select(1)
	bayer_picker.item_selected.connect(func(index: int):
		mat.set_shader_parameter("bayer_level", float(index + 1))
		_mark_dirty()
	)
	row.add_child(bayer_picker)
	parent.add_child(row)
	return row


func _set_dither_mode(index: int) -> void:
	index = clampi(index, 0, 5)
	mat.set_shader_parameter("dither_mode", float(index))
	if dither_picker != null and dither_picker.selected != index:
		dither_picker.select(index)
	if bayer_size_control != null:
		bayer_size_control.visible = index == 1
	_mark_dirty()


func _driver_picker(parent: Control) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Driver"
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	driver_picker = OptionButton.new()
	driver_picker.custom_minimum_size = Vector2(170, 0)
	driver_picker.add_item("V1 Whisp", 0)
	driver_picker.add_item("Legacy FBM", 1)
	driver_picker.add_item("Voronoi", 2)
	driver_picker.add_item("Phasor", 3)
	driver_picker.add_item("Isolines", 4)
	driver_picker.add_item("Spiral bands", 5)
	driver_picker.add_item("Curl Smoke", 6)
	driver_picker.add_item("Wavefront", 7)
	driver_picker.add_item("Cellular Wind", 8)
	driver_picker.add_item("Ridge Flow", 9)
	driver_picker.add_item("Source Warp", 10)
	driver_picker.add_item("Datamosh River", 11)
	driver_picker.add_item("Magnetic Field", 12)
	driver_picker.add_item("Liquid Scanner", 13)
	driver_picker.item_selected.connect(func(index: int): _set_driver_mode(index))
	row.add_child(driver_picker)
	parent.add_child(row)


func _source_view_picker(parent: Control) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "View"
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	source_view_picker = OptionButton.new()
	source_view_picker.custom_minimum_size = Vector2(170, 0)
	source_view_picker.add_item("Composite", 0)
	source_view_picker.add_item("Portrait full", 1)
	source_view_picker.add_item("Map only", 2)
	source_view_picker.item_selected.connect(func(index: int): _set_source_view_mode(index))
	row.add_child(source_view_picker)
	parent.add_child(row)
	_set_source_view_mode(source_view_mode)


func _portrait_picker(parent: Control) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Portrait"
	lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	portrait_picker = OptionButton.new()
	portrait_picker.custom_minimum_size = Vector2(150, 0)
	_populate_portrait_picker()
	portrait_picker.item_selected.connect(func(index: int):
		portrait_idx = index
		_load_portrait(portrait_idx)
		_mark_dirty()
	)
	row.add_child(portrait_picker)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(64, 0)
	refresh_btn.pressed.connect(func():
		var current_path := ""
		if portrait_idx >= 0 and portrait_idx < portrait_paths.size():
			current_path = portrait_paths[portrait_idx]
		_refresh_portrait_paths()
		portrait_idx = _resolve_portrait_index(current_path, portrait_idx)
		_populate_portrait_picker()
		_load_portrait(portrait_idx)
		_mark_dirty()
	)
	row.add_child(refresh_btn)
	parent.add_child(row)
	portrait_source_controls.append(row)


func _set_driver_mode(index: int) -> void:
	index = clampi(index, 0, 13)
	mat.set_shader_parameter("driver_mode", float(index))
	if driver_picker != null and driver_picker.selected != index:
		driver_picker.select(index)
	_sync_driver_visibility()
	_mark_dirty()


func _sync_driver_visibility() -> void:
	var index := int(round(float(mat.get_shader_parameter("driver_mode"))))
	for control in v1_driver_controls:
		control.visible = index == 0
	for control in legacy_driver_controls:
		control.visible = index == 1
	for control in position_driver_controls:
		control.visible = index >= 1
	for control in driver_shape_controls:
		control.visible = index >= 2
	for control in generic_driver_controls:
		control.visible = index >= 2


func _set_source_view_mode(index: int) -> void:
	source_view_mode = clampi(index, 0, 2)
	if mat != null:
		mat.set_shader_parameter("source_layout_mode", float(source_view_mode))
	if source_view_picker != null and source_view_picker.selected != source_view_mode:
		source_view_picker.select(source_view_mode)
	_sync_source_visibility()
	_mark_dirty()


func _sync_source_visibility() -> void:
	scene_bg.visible = true
	map_sprite.visible = source_view_mode == 0 or source_view_mode == 2
	side_panel_bg.visible = source_view_mode == 0
	panel_edge.visible = source_view_mode == 0
	portrait_rect.visible = source_view_mode == 0 or source_view_mode == 1
	_apply_portrait_rect()
	for control in composite_layout_controls:
		control.visible = source_view_mode == 0
	for control in fullscreen_layout_controls:
		control.visible = source_view_mode == 1
	for control in portrait_source_controls:
		control.visible = source_view_mode != 2
	for control in composite_only_controls:
		control.visible = source_view_mode == 0


func _format_slider_value(value: float, decimals: int) -> String:
	return (("%." + str(decimals) + "f") % value) if decimals > 0 else str(int(round(value)))


func _slider(parent: Control, label: String, vmin: float, vmax: float, step: float, default_val: float, cb: Callable, param := "", decimals := 2, allow_manual_overflow := false) -> Control:
	var group := VBoxContainer.new()
	var row := HBoxContainer.new()
	var lbl := Label.new(); lbl.text = label; lbl.custom_minimum_size = Vector2(108, 0)
	lbl.add_theme_font_size_override("font_size", 10); row.add_child(lbl)
	var value_edit := LineEdit.new()
	value_edit.text = _format_slider_value(default_val, decimals)
	value_edit.custom_minimum_size = Vector2(64, 22)
	value_edit.add_theme_font_size_override("font_size", 10)
	row.add_child(value_edit)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(52, 0)
	reset_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(reset_btn)
	group.add_child(row)
	var s := HSlider.new()
	s.min_value = vmin; s.max_value = vmax; s.step = step; s.value = default_val
	var apply_text_value := func() -> void:
		if not value_edit.text.is_valid_float():
			value_edit.text = _format_slider_value(s.value, decimals)
			return
		var raw_value := value_edit.text.to_float()
		if allow_manual_overflow:
			s.set_block_signals(true)
			s.value = clampf(raw_value, vmin, vmax)
			s.set_block_signals(false)
			value_edit.text = _format_slider_value(raw_value, decimals)
			cb.call(raw_value)
			_mark_dirty()
			return
		s.value = clampf(raw_value, vmin, vmax)
	s.value_changed.connect(func(v: float):
		value_edit.text = _format_slider_value(v, decimals)
		cb.call(v)
		_mark_dirty()
	)
	value_edit.text_submitted.connect(func(_text: String): apply_text_value.call())
	value_edit.focus_exited.connect(func(): apply_text_value.call())
	reset_btn.pressed.connect(func(): s.value = default_val)
	if param != "":
		shader_sliders[param] = s
		slider_value_fields[param] = value_edit
		slider_decimals[param] = decimals
	group.add_child(s)
	parent.add_child(group)
	return group


func _rect(parent: Control, l: float, t: float, r: float, b: float, c: Color) -> void:
	var cr := ColorRect.new()
	cr.offset_left = l; cr.offset_top = t; cr.offset_right = r; cr.offset_bottom = b
	cr.color = c; parent.add_child(cr)


func _label(parent: Control, x: float, y: float, txt: String) -> Label:
	var lbl := Label.new()
	lbl.offset_left = x; lbl.offset_top = y; lbl.offset_right = x + 400; lbl.offset_bottom = y + 20
	lbl.text = txt; parent.add_child(lbl)
	return lbl


func _portrait_bounds() -> Vector4:
	return Vector4(
		portrait_rect.offset_left / VIEW_SIZE.x,
		portrait_rect.offset_top / VIEW_SIZE.y,
		portrait_rect.offset_right / VIEW_SIZE.x,
		portrait_rect.offset_bottom / VIEW_SIZE.y
	)


# ---- assets ----
func _load_map_texture() -> void:
	# Ensure black background
	scene_vp.transparent_bg = false
	if not FileAccess.file_exists(MAP_PATH): return
	var tex: Texture2D = load(MAP_PATH) as Texture2D
	map_sprite.texture = tex
	map_sprite.scale = Vector2(880.0/tex.get_width(), 880.0/tex.get_width())
	map_sprite.position = Vector2(440, 360)


func _refresh_portrait_paths() -> void:
	portrait_paths.clear()
	var dir := DirAccess.open(PORTRAIT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import") and not file_name.ends_with("~"):
			var ext := file_name.get_extension().to_lower()
			if PORTRAIT_EXTENSIONS.has(ext):
				portrait_paths.append("%s/%s" % [PORTRAIT_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	portrait_paths.sort()


func _portrait_label(path: String) -> String:
	return path.get_file().get_basename().capitalize()


func _populate_portrait_picker() -> void:
	if portrait_picker == null:
		return
	portrait_picker.clear()
	if portrait_paths.is_empty():
		portrait_picker.add_item("No portraits")
		portrait_picker.disabled = true
		return
	portrait_picker.disabled = false
	for path in portrait_paths:
		portrait_picker.add_item(_portrait_label(path))
	_select_portrait_picker(portrait_idx)


func _select_portrait_picker(idx: int) -> void:
	if portrait_picker == null or portrait_picker.disabled:
		return
	portrait_picker.select(clampi(idx, 0, portrait_paths.size() - 1))


func _resolve_portrait_index(path: String, fallback_idx: int) -> int:
	if path != "":
		var by_path := portrait_paths.find(path)
		if by_path >= 0:
			return by_path
	if portrait_paths.is_empty():
		return 0
	return clampi(fallback_idx, 0, portrait_paths.size() - 1)


func _load_portrait(idx: int) -> void:
	if portrait_paths.is_empty():
		portrait_rect.texture = null
		return
	portrait_idx = clampi(idx, 0, portrait_paths.size() - 1)
	var tex: Texture2D = load(portrait_paths[portrait_idx]) as Texture2D
	if tex == null: return
	portrait_rect.texture = tex
	_select_portrait_picker(portrait_idx)
var portrait_height := 1800.0
var portrait_top    := -20.0
var portrait_full_scale := 1.0
var portrait_full_x := 0.0
var portrait_full_y := 0.0
func _apply_portrait_rect() -> void:
	if source_view_mode == 1:
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var full_size := VIEW_SIZE * portrait_full_scale
		var top_left := (VIEW_SIZE - full_size) * 0.5 + Vector2(portrait_full_x, portrait_full_y)
		portrait_rect.offset_left = top_left.x
		portrait_rect.offset_top = top_left.y
		portrait_rect.offset_right = top_left.x + full_size.x
		portrait_rect.offset_bottom = top_left.y + full_size.y
		return
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_rect.offset_left = SIDE_PANEL_LEFT
	portrait_rect.offset_top = portrait_top
	portrait_rect.offset_right = SIDE_PANEL_RIGHT
	portrait_rect.offset_bottom = portrait_top + portrait_height
