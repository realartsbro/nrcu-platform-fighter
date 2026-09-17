extends RefCounted
# NRCU FX Lab vNext — layer/look cost estimator (specs/02 §11).
#
# Non-blocking, deterministic relative cost estimate. Factors mirror the spec
# list: source-copy pass, overscan/full-frame planes, blur radius, displacement,
# custom texture/mask sampling, COMPOSITE_BELOW input, procedural drivers and
# the FX stage amounts. Pure logic: no rendering, no UI.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

static func layer_cost(layer: Dictionary) -> Dictionary:
	var factors: Array = []
	var cost := 1.0
	factors.append("base 1.0")

	var type := str(layer.get("type", ""))
	if type == "SOURCE_COPY":
		cost += 0.5
		factors.append("source copy pass +0.5")
	elif type == "FX":
		cost += 0.5
		factors.append("fx stage +0.5")
		var fx: Dictionary = layer.get("fx", {})
		var fringe := float(fx.get("fringe", 0.0))
		if fringe > 0.001:
			cost += 2.0 * fringe
			factors.append("fringe +%.2f" % (2.0 * fringe))
		var dither := float(fx.get("dither", 0.0))
		if dither > 0.001:
			cost += 0.5 * dither
			factors.append("dither +%.2f" % (0.5 * dither))
		var rgb := float(fx.get("rgb", 0.0))
		if rgb > 0.001:
			cost += 0.3 * rgb
			factors.append("rgb tear +%.2f" % (0.3 * rgb))
		var blur := float(fx.get("color_blur", 0.0))
		if blur > 0.001:
			cost += 0.7 * blur
			factors.append("blur radius +%.2f" % (0.7 * blur))
		var input := str(layer.get("input", "ORIGINAL_SOURCE"))
		if input == "COMPOSITE_BELOW":
			cost += 2.5
			factors.append("composite-below flatten +2.5")
		elif input == "LAYER_BELOW":
			cost += 1.0
			factors.append("layer-below pass +1.0")

	var displacement: Dictionary = layer.get("displacement", {})
	if bool(displacement.get("enabled", false)):
		cost += 0.6
		factors.append("displacement driver +0.6")
		if displacement.get("custom_texture") != null:
			cost += 0.2
			factors.append("custom driver texture +0.2")

	var mask: Dictionary = layer.get("mask", {})
	if bool(mask.get("enabled", false)):
		cost += 0.4
		factors.append("mask silhouette scan +0.4")
		if mask.get("custom_mask") != null:
			cost += 0.3
			factors.append("custom mask sampling +0.3")
		var feather := float(mask.get("feather_px", 0.0))
		if feather > 0.0:
			cost += minf(0.3, feather * 0.01)
			factors.append("mask feather +%.2f" % minf(0.3, feather * 0.01))

	var plane := str(layer.get("plane", "TARGET_SOURCE"))
	if plane == "COMPOSITION_BACKGROUND" or plane == "COMPOSITION_FOREGROUND":
		cost += 0.8
		factors.append("full-frame composition plane +0.8")

	var fx_size := float((layer.get("fx", {}) as Dictionary).get("size", 1.0))
	if fx_size > 1.0:
		cost *= fx_size
		factors.append("fx size factor ×%.2f" % fx_size)

	return {"layer_id": str(layer.get("layer_id", "")), "cost": cost, "factors": factors}

static func look_cost(doc: Dictionary) -> Dictionary:
	var layers: Array = []
	var total := 0.0
	for raw in doc.get("layers", []):
		if not (raw is Dictionary) or not bool((raw as Dictionary).get("enabled", true)):
			continue
		var entry := layer_cost(raw)
		layers.append(entry)
		total += float(entry["cost"])
	var level := "LOW"
	if total > 6.0:
		level = "HIGH"
	elif total > 3.0:
		level = "MEDIUM"
	return {"layers": layers, "total": total, "level": level}
