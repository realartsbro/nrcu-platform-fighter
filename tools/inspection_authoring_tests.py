#!/usr/bin/env python3
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
S=(ROOT/'project/scripts/nrcu_fx_lab_v2.gd').read_text()
SH=(ROOT/'project/shaders/nrcu_fx_v2.gdshader').read_text()
checks=[]
def c(n,x): checks.append((n,bool(x)))
def body(name):
 m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',S,re.M)
 if not m:return ''
 st=m.end(); n=re.search(r'^func \w+\(',S[st:],re.M); return S[st:st+(n.start() if n else len(S)-st)]
# Live direct selection
c('preview container receives GUI input','disp.gui_input.connect(_on_preview_gui_input)' in S)
c('live hit testing uses transformed local coordinates','get_global_transform().affine_inverse()' in body('_pick_live_texture_at'))
c('hit testing prefers topmost/specific targets','z' in body('_pick_live_texture_at') and 'area' in body('_pick_live_texture_at'))
c('click forces SELECTED without dirtying look','target_mode = "SELECTED"' in body('_on_preview_gui_input') and '_mark_dirty' not in body('_on_preview_gui_input'))
c('selection outline exists','ReferenceRect.new()' in S and '_update_selection_outline()' in body('_process'))
c('isolate current live element exists','func _isolate_current_live_element' in S)
c('isolate reuses actual texture resource path','node.texture.resource_path' in body('_isolate_current_live_element'))
# Study spatial reference independent from arbitrary 900x630 canvas when live analog exists
c('study spatial reference searches hidden live screen','_find_live_texture_reference' in body('_study_reference_presentation_size'))
c('study reference first matches exact asset path','true' in body('_study_reference_presentation_size') and '_find_live_texture_reference' in body('_study_reference_presentation_size'))
c('study reference avoids wrong-fighter role fallback','not exact_path' not in body('_study_reference_presentation_size') and 'roster_presentation' in body('_study_reference_presentation_size'))
c('presentation size routes study through production reference','_study_reference_presentation_size' in body('_presentation_size_for'))
# Debug views are preview-only
c('debug views declared','DEBUG_VIEWS' in S and 'COMPOSITE' in S and 'DRIVER FIELD' in S)
c('debug view is not in look state','"debug_view' not in re.search(r'var state := \{(.*?)\n\}',S,re.S).group(1))
c('debug shader uniform exists','uniform float debug_view_mode' in SH)
c('debug only applies to active target','float(debug_view_index) if active else 0.0' in body('_apply_fx'))
for term in ['debug_edge','debug_coverage','debug_driver','debug_base_col']:
 c('shader diagnostic '+term,term in SH)
c('diagnostic callback does not dirty look','_mark_dirty' not in body('_on_debug_view'))
failed=[x for x in checks if not x[1]]
for n,o in checks: print(('PASS' if o else 'FAIL')+'  '+n)
print(f'\n{len(checks)-len(failed)}/{len(checks)} inspection/authoring checks PASS')
sys.exit(1 if failed else 0)
