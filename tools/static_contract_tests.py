#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
SCRIPT=(ROOT/'project/scripts/nrcu_fx_lab_v2.gd').read_text()
SHADER=(ROOT/'project/shaders/nrcu_fx_v2.gdshader').read_text()
SCENE=(ROOT/'project/scenes/nrcu_fx_lab.tscn').read_text()
checks=[]
def check(name, cond, detail=''):
    checks.append((name,bool(cond),detail))
def body(name):
    m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',SCRIPT,re.M)
    if not m:return ''
    n=re.search(r'^func \w+\(',SCRIPT[m.end():],re.M)
    return SCRIPT[m.end():m.end()+(n.start() if n else len(SCRIPT)-m.end())]
check('scene uses v2 controller','res://scripts/nrcu_fx_lab_v2.gd' in SCENE)
check('v2 controller uses v2 shader','res://shaders/nrcu_fx_v2.gdshader' in SCRIPT)
check('factory start is neutral','"fx_on": {"dither": false, "fringe": false, "flow": false, "rgb": false}' in SCRIPT)
# uniforms
uniforms=set(re.findall(r'uniform\s+(?:sampler2D|vec[234]|float|int|bool)\s+([A-Za-z_][A-Za-z0-9_]*)',SHADER))
literals=set(re.findall(r'set_shader_parameter\("([A-Za-z_][A-Za-z0-9_]*)"',SCRIPT))
check('literal shader params all exist',not(literals-uniforms),str(sorted(literals-uniforms)))
m=re.search(r'var scalar_keys := \[(.*?)\]\n\s*for parameter in scalar_keys:',SCRIPT,re.S)
loop=set(re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"',m.group(1))) if m else set()
check('scalar loop params all exist',bool(loop) and not(loop-uniforms),str(sorted(loop-uniforms)))
# continuous guarantee
for title, token in [
 ('source pixel grid guarded','source_pixel_size>0.5&&pure_continuous<0.5'),
 ('mono stamp guarded','base_mode>=0.5&&pure_continuous<0.5'),
 ('colour dither guarded','fx_dither>0.001&&pure_continuous<0.5'),
 ('fringe coverage smooth/pure branch','pure_continuous>0.5||fringe_coverage_mode<0.5'),
 ('signal posterize guarded','pure_continuous>0.5||signal_posterize<1.5'),
 ('driver grid guarded','pure_continuous>0.5||driver_sampling_mode<0.5'),
 ('temporal hold guarded','temporal_hold>0.01&&pure_continuous<0.5')]: check(title,token in SHADER)
check('continuous grade survives pure mode','base_grade_amount>0.001' in SHADER and 'grade_colour' in SHADER)
# independence
check('dither and fringe Bayer levels independent','dither_bayer_level' in SHADER and 'fringe_bayer_level' in SHADER)
check('dither and fringe cell sizes independent','dither_pixel' in SHADER and 'fringe_pixel' in SHADER)
check('base grade and dither prep independent','grade_black_point' in SHADER and 'dither_black_point' in SHADER)
check('edge/treatment masks independent','custom_edge_mask_tex' in SHADER and 'treatment_mask_tex' in SHADER)
check('flow driver source uses raw source signal','float source_drive=raw_luma(guv);' in SHADER)
check('RGB shifted samples preserve partial base grade','plus+(plus_graded-plus)*grade_amount' in SHADER and 'minus+(minus_graded-minus)*grade_amount' in SHADER)
# targets/bypass
apply=body('_apply_fx')
check('base grade target gated','base_grade_amount", float(state["base_grade_amount"]) if active else 0.0' in apply)
check('source grid target gated','source_pixel_size", float(state["source_pixel_size"]) if active else 0.0' in apply)
check('selected role all targeting','const TARGET_MODES := ["SELECTED", "ROLE", "ALL"]' in SCRIPT)
check('semantic roles present',all(x in SCRIPT for x in ['VS MARK','PRIMARIES','ECHOES','NAMES','STAGE']))
# hot path
proc=body('_process')
check('process does not call static apply','_apply_fx()' not in proc)
check('process uses runtime uniforms','_apply_runtime_uniforms()' in proc)
check('anchored motion tied to preview timeline','preview_t-float(event_marks.get(anchor,0.0))' in proc)
# look authoring
check('current look schema v0.3','const LOOK_SCHEMA := "NRCU_FX_LOOK_V0_3"' in SCRIPT)
check('legacy look schemas migrate','LEGACY_LOOK_SCHEMAS' in SCRIPT and '_look_schema_supported' in SCRIPT and '_migrate_look_state' in SCRIPT)
check('unknown look keys ignored','if not result.has(key): continue' in body('_deep_merge'))
check('preview context not ConfigFile look state','cfg.set_value(name,"source_mode"' not in body('_save_preset'))
check('A/B snapshots exist','snapshot_a' in SCRIPT and 'snapshot_b' in SCRIPT)
check('custom element study','ELEMENT STUDY' in SCRIPT and 'res://assets/elements' in SCRIPT)
check('dedicated mask folder','res://assets/masks' in SCRIPT)
# honesty
check('unsupported geometry counted',all(x in SCRIPT for x in ['Polygon2D','Line2D','ColorRect']))
check('no overscan implementation claim','overscan' not in SHADER.lower())
# structure
fn=re.findall(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',SCRIPT,re.M)
dups=sorted({x for x in fn if fn.count(x)>1})
check('no duplicate top-level funcs',not dups,str(dups))
for a,b in [('(',')'),('[',']'),('{','}')]:check('rough balance '+a+b,SCRIPT.count(a)==SCRIPT.count(b),f'{SCRIPT.count(a)} vs {SCRIPT.count(b)}')
failed=[c for c in checks if not c[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL')+'  '+name+((' :: '+detail) if detail and not ok else ''))
print(f'\n{len(checks)-len(failed)}/{len(checks)} static checks PASS')
sys.exit(1 if failed else 0)
