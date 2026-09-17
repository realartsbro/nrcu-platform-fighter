#!/usr/bin/env python3
from pathlib import Path
import re,sys,json
ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
S=(PROOT/'scripts/nrcu_fx_lab_v2.gd').read_text()
SH=(PROOT/'shaders/nrcu_fx_v2.gdshader').read_text()
checks=[]
def c(n,x): checks.append((n,bool(x)))
def body(name):
 m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',S,re.M)
 if not m:return ''
 st=m.end(); n=re.search(r'^func \w+\(',S[st:],re.M); return S[st:st+(n.start() if n else len(S)-st)]
# vector masks
for fn in ['name_plate_left_mask.png','name_plate_right_mask.png','accent_left_mask.png','accent_right_mask.png','study_checker.png']:
 p=PROOT/'assets/vs/generated'/fn
 c('generated '+fn,p.exists() and p.stat().st_size>500)
for fam,count in [('ffa_3',3),('ffa_4',4),('team_2v2',4),('team_2v1',3),('team_3v1',4)]:
 c(f'{fam} plate masks complete',len(list((PROOT/'assets/vs/generated').glob(f'{fam}_plate_*_mask.png')))==count)
 c(f'{fam} accent masks complete',len(list((PROOT/'assets/vs/generated').glob(f'{fam}_accent_*_mask.png')))==count)
# target registry
roles=re.search(r'const TARGET_ROLES := \[(.*?)\]',S,re.S).group(1)
for role in ['SIDE FIELDS','NAME PLATES','ACCENT LINES']:
 c('role '+role,role in roles)
vec=body('_install_vector_proxies')
c('duel vector specs include plates','NamePlates/PlateLeft' in vec and 'NamePlates/PlateRight' in vec)
c('duel vector specs include accents','NamePlates/AccentLeft' in vec and 'NamePlates/AccentRight' in vec)
c('multiplayer vector proxy mask convention','mode_format.to_lower()' in vec and '%s_%s_%s_mask.png' in vec)
c('vector proxy preserves real source colour','source_tint' in body('_install_vector_proxy'))
c('vector source is hidden only in lab proxy path','source.visible = false' in body('_install_vector_proxy'))
# texture overscan
for u in ['source_uv_scale','source_uv_offset','source_flip_x']:
 c('shader overscan uniform '+u, re.search(rf'uniform .*\b{u}\b',SH) is not None)
c('source UV is mapped before rendering','vec2 uv=map_source_uv(UV);' in SH)
c('outside proxy samples transparent','inside_source_uv' in SH and '*inside' in re.search(r'vec4 sample_source\(vec2 uv\)\{(.*?)\n\}',SH,re.S).group(1))
c('edge mask is transparent outside source','raw_edge_mask' in SH and '*inside_source_uv(uv)' in SH)
c('treatment mask is transparent outside source','raw_treatment_mask' in SH and '*inside_source_uv(uv)' in SH)
c('pixelation does not clamp proxy padding into border smear','uv.x<0.0||uv.y<0.0||uv.x>1.0||uv.y>1.0' in body_text if False else 'uv.x<0.0||uv.y<0.0||uv.x>1.0||uv.y>1.0' in SH)
c('regular texture proxy exists','FXOverscanProxy' in body('_configure_texture_proxy'))
c('regular original hidden with self_modulate only','self_modulate' in body('_configure_texture_proxy') and 'node.visible = false' not in body('_configure_texture_proxy'))
c('proxy child follows production transform','node.add_child(proxy)' in body('_configure_texture_proxy'))
c('proxy geometry updates every runtime frame','_update_texture_proxy_geometry' in body('_apply_runtime_uniforms'))
c('overscan extent follows authored spatial FX','wind_reach' in body('_required_overscan_px') and 'rgb_shift_amount' in body('_required_overscan_px') and 'color_blur' in body('_required_overscan_px'))
c('proxy local padding derives from canonical presentation size','presentation_size' in body('_update_texture_proxy_geometry') and 'local_size.x/maxf(presentation_size.x' in body('_update_texture_proxy_geometry'))
c('gather explicitly ignores overscan proxy children','fx_overscan_proxy' in body('_gather'))
# study editor
for token in ['DARK','LIGHT','NEUTRAL','CHECKER']:
 c('study background '+token,token in re.search(r'const STUDY_BACKGROUNDS := \[(.*?)\]',S,re.S).group(1))
c('study fit computes aspect preserving footprint','minf(area.size.x/source.x,area.size.y/source.y)' in body('_study_fit_rect_for'))
c('study zoom does not author look state','study_zoom' not in re.search(r'var state := \{(.*?)\n\}',S,re.S).group(1))
c('study zoom has numeric control','study_zoom_spin' in S and '_on_study_zoom_entered' in S)
c('mouse wheel zoom','MOUSE_BUTTON_WHEEL_UP' in body('_on_preview_gui_input') and 'MOUSE_BUTTON_WHEEL_DOWN' in body('_on_preview_gui_input'))
c('middle drag pan','MOUSE_BUTTON_MIDDLE' in body('_on_preview_gui_input') and 'study_pan +=' in body('_on_preview_gui_input'))
c('F fits Element Study','KEY_F' in body('_unhandled_key_input') and '_study_fit()' in body('_unhandled_key_input'))
c('custom study geometry uses schema reference sizes','roster_presentation' in body('_study_reference_presentation_size') and 'layout_1v1' in body('_study_reference_presentation_size'))
c('study reference does not use editor zoom as production scale','study_fit_size' in body('_study_reference_presentation_size') and 'study_zoom' not in body('_study_reference_presentation_size'))
# schema migration
c('new look schema','NRCU_FX_LOOK_V0_3' in S)
c('legacy v0.2 accepted','NRCU_FX_LOOK_V0_2' in re.search(r'const LEGACY_LOOK_SCHEMAS := \[(.*?)\]',S,re.S).group(1))
c('legacy migration preserves neutral master defaults','fx_size' in body('_migrate_look_state') and 'base_opacity' in body('_migrate_look_state'))
c('production payload records look schema','"look_schema":LOOK_SCHEMA' in body('_production_look_payload'))
# capture context
cap=body('_capture')
c('capture writes metadata sidecar','NRCU_FX_LAB_CAPTURE_V1' in cap and 'meta_path' in cap)
c('capture metadata includes spatial readout','spatial_readout' in cap)
c('capture metadata includes resolved assignment','resolved_assignment' in cap)

c('source pixel grid has selectable spatial units','source_pixel_units' in S and 'Source pixel units' in S)
c('shader source pixel grid can use presentation dimensions','source_pixel_units' in SH and 'source_pixel_dims' in SH and 'element_size' in SH)
c('legacy migration preserves old source-pixel semantics','migrated["source_pixel_units"] = 0.0' in S)


c('generated-mask loader has import-independent fallback','func _load_project_texture' in S and 'ImageTexture.create_from_image(image)' in S and 'image.load(absolute_path)' in S)
c('vector proxy uses robust mask loader','var mask_texture := _load_project_texture(mask_path)' in S and 'proxy.texture = mask_texture' in S)
failed=[x for x in checks if not x[1]]
for n,o in checks: print(('PASS' if o else 'FAIL')+'  '+n)
print(f'\n{len(checks)-len(failed)}/{len(checks)} spatial/proxy/study checks PASS')
sys.exit(1 if failed else 0)
