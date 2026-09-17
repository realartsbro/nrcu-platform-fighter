#!/usr/bin/env python3
from pathlib import Path
import re, sys

ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
SCRIPT=(PROOT/'scripts/nrcu_fx_lab_v2.gd').read_text(encoding='utf-8')
SHADER=(PROOT/'shaders/nrcu_fx_v2.gdshader').read_text(encoding='utf-8')
checks=[]
def check(name, cond, detail=''):
    checks.append((name,bool(cond),detail))

schema_match=re.search(r'const PARAM_SCHEMA := \{(.*?)\n\}\n\nconst SECTION_KEYS',SCRIPT,re.S)
schema=set(re.findall(r'^\s*"([^"]+)"\s*:',schema_match.group(1),re.M)) if schema_match else set()
slider_keys=set(re.findall(r'_state_slider\([^\n]*?,\s*"[^"]+"\s*,\s*"([^"]+)"\)',SCRIPT))
for block in re.findall(r'for spec in \[(.*?)\]:\n\s*_state_slider\(',SCRIPT,re.S):
    slider_keys.update(re.findall(r'\["([^"]+)"\s*,',block))
check('all state sliders are schema-backed', bool(slider_keys) and slider_keys <= schema, str(sorted(slider_keys-schema)))
check('schema has no orphan slider metadata', schema <= slider_keys, str(sorted(schema-slider_keys)))
check('creative numeric entry may exceed slider max','spin.allow_greater = not bounded' in SCRIPT)
check('FX amount numeric entry may exceed 1','spin.allow_greater = true' in SCRIPT and 'fx_amount_' in SCRIPT)
check('intrinsically bounded controls retain bounds','"base_opacity": {"slider_min":0.0,"slider_max":1.0' in SCRIPT and '"bounded":true' in SCRIPT)

check('base opacity exists in factory state','"base_opacity": 1.0' in SCRIPT)
check('base opacity is shader uniform','uniform float base_opacity = 1.0' in SHADER)
check('base opacity is target gated','set_shader_parameter("base_opacity", float(state["base_opacity"]) if active else 1.0)' in SCRIPT)
check('base opacity does not directly scale fringe alpha','src.a*source_opacity' in SHADER and 'fringe_alpha=clamp(show*clamp(fringe_bleed' in SHADER)

for phrase,name in [
    ('_reset_button(slider.get_parent(), key','per-slider reset'),
    ('_reset_button(option.get_parent(), key','per-option reset'),
    ('_state_check(','toggle reset helper'),
    ('_reset_fx_amount','FX amount reset'),
    ('_reset_motion_value','motion value reset'),
    ('_reset_state_key.bind(key)','colour/state reset'),
    ('RESET SECTION','section reset'),
    ('REVERT LOOK','revert look'),
]: check(name, phrase in SCRIPT)
check('factory reset and revert are distinct','func _reset_look' in SCRIPT and 'func _revert_look' in SCRIPT and 'loaded_look_snapshot' in SCRIPT)
check('reset buttons expose default state','_update_reset_buttons()' in SCRIPT and '_reset_key_is_default' in SCRIPT)

check('master FX size exists','"fx_size": 1.0' in SCRIPT and 'uniform float fx_size = 1.0' in SHADER)
check('master FX intensity exists','"fx_intensity": 1.0' in SCRIPT and 'uniform float fx_intensity = 1.0' in SHADER)
check('master pattern scale exists','"pattern_scale": 1.0' in SCRIPT and 'uniform float pattern_scale = 1.0' in SHADER)
check('edge width is explicit','"edge_width": 3.0' in SCRIPT and 'uniform float edge_width = 3.0' in SHADER)
check('split distance no longer multiplied by flow strength','split=split_axis*split_separation*move_texel*spatial_scale' in SHADER and 'flow_strength*split_separation' not in SHADER)
check('procedural driver UV offset normalized to geometry pixels','driver_offset=field_offset*(flow_strength*32.0)*move_texel*spatial_scale' in SHADER)
check('edge kernel uses geometry/presentation basis','edge_texel=move_texel*max(edge_width*max(fx_size,0.0)' in SHADER)
check('presentation size uses full transform basis','get_global_transform()' in SCRIPT and 'transform.x.length()' in SCRIPT and 'transform.y.length()' in SCRIPT)
check('presentation size refreshes at runtime','set_shader_parameter("element_size", _presentation_size_for(node, node.texture))' in SCRIPT)
check('processing summary exposes spatial conversion','source %d×%d → presentation' in SCRIPT)
check('geometry UI names presentation pixels','const GEOMETRY_UNITS := ["SOURCE PX", "PRESENTATION PX"]' in SCRIPT)

check('base grade overrange remains effective','col+(graded-col)*grade_amount' in SHADER)
check('RGB amount overrange remains effective','col+(shifted-col)*amount' in SHADER)
check('dither amount overrange remains effective','col+(q-col)*amount' in SHADER)
check('flow amount is not hard-clamped to 1','float flow_amt=max(fx_flow,0.0)' in SHADER)
check('fringe amount is not hard-clamped to 1','show=debug_coverage*max(fx_fringe*mask,0.0)*max(fx_intensity,0.0)' in SHADER)

funcs=re.findall(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',SCRIPT,re.M)
check('no duplicate top-level functions',len(funcs)==len(set(funcs)))
for a,b in [('(',')'),('[',']'),('{','}')]:
    check(f'rough {a}{b} balance',SCRIPT.count(a)==SCRIPT.count(b),f'{SCRIPT.count(a)} vs {SCRIPT.count(b)}')


# MONO_DOMAIN_INDEPENDENCE_V1
# BASE / MONO STAMP must not borrow Colour Dither's pattern/tone controls.
check("mono stamp has dedicated shader threshold", "uniform float mono_threshold" in SHADER)
check("mono stamp has dedicated shader pattern", "uniform float mono_mode" in SHADER and "uniform float mono_pixel" in SHADER and "uniform float mono_space" in SHADER)
mono_match = re.search(r"float mono_stamp\([^\)]*\)\{(.*?)\n\}", SHADER, re.S)
mono_body = mono_match.group(1) if mono_match else ""
check("mono stamp does not read colour-dither controls", all(name not in mono_body for name in ["dither_threshold","dither_mode","dither_bayer_level","dither_pixel","dither_space","prep_luma"]))
check("mono stamp consumes current base luminance", "mono_stamp(mono_luma,uv,frag_px)" in SHADER)
check("mono controls live in BASE section", all(k in SCRIPT for k in ['"mono_threshold"','"mono_mode"','"mono_bayer_level"','"mono_pixel"','"mono_space"']))
check("legacy v0.2 mono appearance migration", all(x in SCRIPT for x in ['migrated["mono_threshold"]','incoming.get("dither_threshold"','migrated["mono_mode"]','incoming.get("dither_mode"']))


# BASE_PIPELINE_CONSISTENCY_V1
check("colour dither tone prep follows base pixel grid", "float lv=prep_luma(base_uv);" in SHADER)
check("RGB side samples preserve partial base grade", "plus+(plus_graded-plus)*grade_amount" in SHADER and "minus+(minus_graded-minus)*grade_amount" in SHADER)
check("source-pixel tooltip does not claim edge/fringe are pixelated", "Edge/Fringe extraction remains independently sourced" in SCRIPT)


# OVERSCAN_COST_HEURISTIC_V1
check("cost heuristic includes overscan draw area", "_target_area(true)" in SCRIPT and "pad := _required_overscan_px()" in SCRIPT)
check("cost tooltip distinguishes base and padded footprint", "before overscan" in SCRIPT and "including authored proxy padding" in SCRIPT)

failed=[x for x in checks if not x[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL')+'  '+name+((' :: '+detail) if detail and not ok else ''))
print(f'\n{len(checks)-len(failed)}/{len(checks)} authoring-foundation checks PASS')
if failed: sys.exit(1)
