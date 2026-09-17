#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
S=(PROOT/'scripts/nrcu_fx_lab_v2.gd').read_text(encoding='utf-8')
D=(ROOT/'docs/CANONICAL_AUTHORING_BACKLOG.md').read_text(encoding='utf-8')
checks=[]
def c(name, cond): checks.append((name,bool(cond)))
def body(name):
    m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',S,re.M)
    if not m:return ''
    tail=S[m.end():]; n=re.search(r'^func \w+\(',tail,re.M)
    return tail[:n.start() if n else len(tail)]

# Previously-missed compile blockers.
c('reset_buttons declared', re.search(r'^var reset_buttons\s*:=',S,re.M))
c('section_reset_buttons declared', re.search(r'^var section_reset_buttons\s*:=',S,re.M))

# Collapsible/organised authoring sections.
for fn in ['_section_group','_toggle_section','_refresh_section_header']:
    c('section UX function '+fn, 'func '+fn in S)
for sec in ['MASTER','BASE','DITHER','FRINGE','FLOW','RGB']:
    c('LOOK uses collapsible '+sec, re.search(rf'_section_group\(v,[^\n]+"{sec}"\)',body('_build_look_tab')))
for fx in ['dither','fringe','flow','rgb']:
    c('MOTION collapsible '+fx, '"MOTION:"+fx' in body('_build_motion_tab'))
c('section header shows non-default count','≠ default' in body('_refresh_section_header'))

# Save-As / shortcuts.
c('Ctrl Shift S Save As', 'event.keycode == KEY_S and event.shift_pressed' in body('_unhandled_key_input'))
c('Save As visibly focuses name field','select_all()' in body('_begin_save_as') and 'grab_focus()' in body('_begin_save_as'))

# Production library/browser.
for v in ['production_look_picker','assignment_binding_picker','assignment_filter_picker']:
    c('production browser var '+v,re.search(rf'^var {v}:',S,re.M))
for fn in ['_load_selected_production_look','_delete_selected_production_look','_load_selected_binding_look','_remove_selected_binding','_refresh_production_browsers']:
    c('production browser function '+fn,'func '+fn in S)
c('production delete blocks referenced Looks','referenced by %d binding(s)' in body('_delete_selected_production_look'))
c('binding browser marks winner','★ ' in body('_binding_display'))
c('binding browser shows also-matching rules','✓ ' in body('_binding_display'))
c('assignment preview shows would-bind selector','WOULD BIND' in body('_refresh_assignment_view'))
c('assignment preview shows winner','[b]WINNER[/b]' in body('_refresh_assignment_view'))
c('ASSIGN TO GAME wording','ASSIGN TO GAME' in body('_build_assignments_tab'))

# Transaction safety: never create orphan assignment if look publish fails.
c('publish returns bool','func _publish_current_look() -> bool:' in S)
c('publish failure returns false','return false' in body('_publish_current_look'))
c('assign aborts if publish fails','if not _publish_current_look()' in body('_assign_current_look'))

# Element Study semantic authority (not just pretty masks).
c('study VS mark carries element id','"element_id":"vs_mark"' in body('_scan_assets'))
c('study stage carries own stage id','"stage_id":stage_name' in body('_scan_assets'))
c('study side fields carry semantic id','"element_id":"side_field_%s" % side' in body('_scan_assets'))
c('study name plates carry semantic id','"element_id":"name_plate_%s" % side' in body('_scan_assets'))
c('study accent lines carry semantic id','"element_id":"accent_line_%s" % side' in body('_scan_assets'))
c('study static elements carry visual side','"visual_side":side' in body('_scan_assets'))
c('study applies semantic metadata to custom rect','custom_rect.set_meta("fx_" + meta_key' in body('_collect_slots'))
c('target context honors study visual side','fx_visual_side' in body('_current_target_context'))
c('target context honors study stage id','fx_stage_id' in body('_current_target_context'))
c('vector study uses source tint','source_tint' in body('_scan_assets') and 'fx_source_tint' in body('_refresh_custom_texture'))
c('palette generation honors source tint','fx_source_tint' in body('_source_palette_candidates'))

# Version/readout clarity.
c('header no longer pretends v0.2 final','v0.3 AUTHORING DEV' in body('_build_ui'))

# Structural sanity.
fnames=re.findall(r'^func\s+([A-Za-z_]\w*)\s*\(',S,re.M)
dups=sorted({x for x in fnames if fnames.count(x)>1})
c('no duplicate funcs',not dups)
for a,b in [('(',')'),('[',']'),('{','}')]: c('rough '+a+b+' balance',S.count(a)==S.count(b))


# PARAM_TOOLTIP_COVERAGE_V1
schema_match=re.search(r'const PARAM_SCHEMA := \{(.*?)\n\}\n\nconst SECTION_KEYS',S,re.S)
schema_keys=set(re.findall(r'^\s*"([^"]+)"\s*:',schema_match.group(1),re.M)) if schema_match else set()
tips_match=re.search(r'func _apply_tooltips\(\) -> void:\n\s*var tips := \{(.*?)\n\s*\}',S,re.S)
tip_keys=set(re.findall(r'^\s*"([^"]+)"\s*:',tips_match.group(1),re.M)) if tips_match else set()
c('every schema slider has a tooltip', schema_keys <= tip_keys)
c('paired numeric fields receive the same tooltip', 'if spin_controls.has(key)' in body('_apply_tooltips'))


# MOTION_TIMELINE_BANDS_V1
c('timeline shows active amount envelopes', 'Active amount envelopes are shown as compact authored bands' in S and 'motion_enabled.get(fx,false)' in S)
c('timeline distinguishes manual motion', '"MANUAL"' in S and 'anchor == "manual"' in S)
c('timeline draws attack hold release bands', all(x in S for x in ['attack_end','hold_end','release_end']))


# BASE_SUMMARY_V1
c('processing summary exposes Base Opacity / mode', 'Base: %s' in S and 'MONO STAMP · opacity' in S)
c('processing summary exposes Pure bypass of Mono Stamp', 'MONO STAMP bypassed by PURE CONTINUOUS' in S)

failed=[x for x in checks if not x[1]]
for name,ok in checks: print(('PASS' if ok else 'FAIL')+'  '+name)
print(f'\n{len(checks)-len(failed)}/{len(checks)} final-authoring UX checks PASS')
if failed: sys.exit(1)
