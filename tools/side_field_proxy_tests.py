#!/usr/bin/env python3
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
S=(PROOT/'scripts/nrcu_fx_lab_v2.gd').read_text()
SH=(PROOT/'shaders/nrcu_fx_v2.gdshader').read_text()
checks=[]
def c(n,x):checks.append((n,bool(x)))
def body(name):
 m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',S,re.M)
 if not m:return ''
 st=m.end(); n=re.search(r'^func \w+\(',S[st:],re.M); return S[st:st+(n.start() if n else len(S)-st)]
for side in ['left','right']:
 p=PROOT/f'assets/vs/generated/side_field_{side}_mask.png'
 c('generated side field '+side+' mask exists',p.exists() and p.stat().st_size>1000)
c('SIDE FIELDS is a semantic target role','"SIDE FIELDS"' in re.search(r'const TARGET_ROLES := \[(.*?)\]',S,re.S).group(1))
c('mount installs vector proxies','_install_vector_proxies()' in body('_mount_screen'))
proxy=body('_install_vector_proxy')+body('_install_vector_proxies')
c('proxy replaces original vector geometry in lab','source.visible = false' in proxy)
c('proxy spans canonical 1280x720 presentation','proxy.size = Vector2(1280,720)' in proxy)
c('proxy retains polygon/line tint including alpha','fx_source_tint' in proxy and 'Polygon2D' in proxy and 'Line2D' in proxy)
c('proxy gets stable static element IDs','side_field_' in proxy and 'fx_element_id' in proxy)
c('proxy role metadata participates in target registry','fx_role' in proxy)
c('shader has source tint','uniform vec4 source_tint' in SH and '*source_tint*inside' in SH)
c('source sampler is linear for continuous parity','source_tex : filter_linear' in SH)
c('gather respects proxy role metadata','get_meta("fx_role"' in body('_gather'))
c('production context respects proxy element id','get_meta("fx_element_id"' in body('_current_target_context'))
c('direct selection alpha-tests proxy mask','_texture_hit_alpha' in body('_pick_live_texture_at'))
c('study catalog exposes side fields','SIDE FIELD ·' in body('_scan_assets'))
failed=[x for x in checks if not x[1]]
for n,o in checks: print(('PASS' if o else 'FAIL')+'  '+n)
print(f'\n{len(checks)-len(failed)}/{len(checks)} side-field proxy checks PASS')
sys.exit(1 if failed else 0)
