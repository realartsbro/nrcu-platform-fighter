# UI-05 scope truth (headless): the canonical field metadata table covers all
# 109 neutral fx keys exactly once, with sane ranges/units/kinds. This is the
# single source normal macros AND expert controls consume — drift between
# normal/expert/model becomes structurally impossible.
extends SceneTree

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

var _failures := 0
var _checks := 0

func _check(ok: bool, label: String, extra := "") -> void:
	_checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		_failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", extra)

func _init() -> void:
	var meta: Dictionary = FxLookScript.field_meta_all()
	var neutral: Dictionary = FxLookScript.neutral_fx()
	_check(meta.size() == 109, "UI-05 meta covers 109 keys", str(meta.size()))
	var missing: Array = []
	for key in neutral.keys():
		if not meta.has(str(key)):
			missing.append(str(key))
	_check(missing.is_empty(), "UI-05 no canonical key missing from meta", str(missing))
	var extra: Array = []
	for key in meta.keys():
		if not neutral.has(str(key)):
			extra.append(str(key))
	_check(extra.is_empty(), "UI-05 no meta key outside canonical", str(extra))
	var kinds := {"amount": 0, "int": 0, "option": 0, "check": 0, "color": 0, "asset": 0, "compat": 0, "rejected": 0}
	var bad: Array = []
	for key in meta.keys():
		var spec: Dictionary = meta[key]
		var kind := str(spec.get("kind", "?"))
		if not kinds.has(kind):
			bad.append(str(key) + ":kind=" + kind)
			continue
		kinds[kind] += 1
		if kind == "amount" or kind == "int":
			if not (float(spec.get("min", 0.0)) < float(spec.get("max", 0.0))):
				bad.append(str(key) + ":min>=max")
			if not (float(spec.get("step", 0.0)) > 0.0):
				bad.append(str(key) + ":step<=0")
		if kind == "option" and (spec.get("options", []) as Array).size() < 2:
			bad.append(str(key) + ":<2 options")
	_check(bad.is_empty(), "UI-05 all meta entries well-formed", str(bad))
	# The hue units fix: degrees everywhere, never normalized.
	var hue: Dictionary = meta.get("palette_hue_offset", {})
	_check(float(hue.get("min", 0.0)) == -180.0 and float(hue.get("max", 0.0)) == 180.0, "UI-05 hue meta in degrees", str(hue))
	var drv: Dictionary = meta.get("driver_mode", {})
	_check((drv.get("options", []) as Array).size() == 14, "UI-05 driver has 14 named modes", str((drv.get("options", []) as Array).size()))
	var strat: Dictionary = meta.get("palette_strategy", {})
	_check((strat.get("options", []) as Array).size() == 6, "UI-05 strategy has 6 named options", str(strat))
	var compat_count := 0
	var rejected_count := 0
	for key in meta.keys():
		if str((meta[key] as Dictionary).get("kind", "")) == "compat":
			compat_count += 1
		if str((meta[key] as Dictionary).get("kind", "")) == "rejected":
			rejected_count += 1
	_check(compat_count == 1 and rejected_count == 1, "UI-05 exactly one compat + one rejected", "compat=%d rejected=%d" % [compat_count, rejected_count])
	# ---- semantic parity (UI <-> shader/runtime, not just UI <-> UI) ------
	# Every neutral canonical value must sit inside the exposed range.
	var out_of_range: Array = []
	for key in neutral.keys():
		var spec: Dictionary = meta.get(str(key), {})
		var kind := str(spec.get("kind", ""))
		if kind == "amount" or kind == "int":
			var v := float(neutral[key]) if not (neutral[key] is String) else 0.0
			if not (neutral[key] is String) and (v < float(spec.get("min", 0.0)) - 0.0001 or v > float(spec.get("max", 0.0)) + 0.0001):
				out_of_range.append(str(key) + "=" + str(v))
	_check(out_of_range.is_empty(), "UI-05 neutral values inside exposed ranges", str(out_of_range))
	# String enums must match the runtime enum lists exactly.
	_check(str((meta.get("time_source", {}) as Dictionary).get("options", [])) == str(FxLookScript.TIME_SOURCES), "UI-05 time_source options equal runtime TIME_SOURCES")
	# Integer-discrete fields expose only whole steps.
	var non_discrete: Array = []
	for key in meta.keys():
		if str((meta[key] as Dictionary).get("kind", "")) == "int" and float((meta[key] as Dictionary).get("step", 0.0)) != 1.0:
			non_discrete.append(str(key))
	_check(non_discrete.is_empty(), "UI-05 int fields step by 1", str(non_discrete))
	# Bayer levels: the shader dispatches 1..5 and normalizes 0 -> 1, so 0
	# must not be offered and 3..5 must not be hidden.
	for key in ["mono_bayer_level", "dither_bayer_level", "fringe_bayer_level"]:
		var spec: Dictionary = meta.get(key, {})
		_check(float(spec.get("min", 0.0)) == 1.0 and float(spec.get("max", 0.0)) == 5.0, "UI-05 %s exposes shader levels 1..5" % key, str(spec))
	# Enum index counts mirror shader branches (pattern_value 6 modes,
	# mono_stamp hard + 4 pattern + inverse, blend mix/add/screen, ...).
	var counts := {"dither_mode": 6, "fringe_coverage_mode": 6, "mono_mode": 6, "fringe_blend_mode": 3, "mono_space": 3, "dither_space": 3, "fringe_space": 3, "edge_source_mode": 3, "driver_sampling_mode": 2, "base_mode": 2, "geometry_units": 2, "rgb_shift_units": 2, "source_pixel_units": 2}
	var count_bad: Array = []
	for key in counts.keys():
		if ((meta.get(key, {}) as Dictionary).get("options", []) as Array).size() != int(counts[key]):
			count_bad.append(key)
	_check(count_bad.is_empty(), "UI-05 enum counts match shader branches", str(count_bad))
	# The behavioral version of this audit lives in the windowed advanced
	# suite (controls tagged with canonical_field): compat/rejected must
	# own no creative control anywhere in the built inspector.
	print("[FX-FIELD-META] done · checks=%d failures=%d" % [_checks, _failures])
	quit(_failures)
