#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
LAB=(ROOT/'project/scripts/nrcu_fx_lab_v2.gd').read_text(encoding='utf-8')
VS=(ROOT/'project/scripts/vs_screen.gd').read_text(encoding='utf-8')
checks=[]
def c(name, cond): checks.append((name,bool(cond)))

# Real study library, not just assets/elements.
c('study catalog includes VS mark','res://assets/vs/ui/vs_mark.png' in LAB)
c('study catalog includes all fighter layers','primary.png' in LAB and 'echo.png' in LAB and 'name.png' in LAB)
c('study catalog includes stages','res://assets/vs/stages/%s.png' in LAB)
c('element study forces valid SELECTED target','target_mode = "SELECTED"' in LAB and 'selected_slot = "study_asset"' in LAB)
c('live target state preserved across study','live_target_mode' in LAB and 'live_target_role' in LAB and 'live_selected_slot' in LAB)
c('zero-target state is explicit','NO ACTIVE TARGETS' in LAB)

# Transport / scrubbing.
for fn in ['_toggle_transport','_transport_seek_to','_transport_to_start','_transport_step_back','_transport_step_forward','_transport_to_fx_peak']:
    c('transport function '+fn, ('func '+fn+'(') in LAB)
c('timeline drag handles mouse motion','InputEventMouseMotion' in LAB and 'MOUSE_BUTTON_MASK_LEFT' in LAB)
c('scrubbing routes through transport','lab._transport_seek_to(t)' in LAB)
c('transport has exact numeric time entry','transport_time_spin' in LAB and 'step = 0.001' in LAB)

# Real VS preview API.
for fn in ['lab_preview_pause','lab_preview_resume','lab_preview_seek','lab_preview_is_paused']:
    c('vs preview API '+fn, ('func '+fn+'(') in VS)
c('preview seek rebuilds entry tween','_apply_entry_start()' in VS and '_apply_family_entry_start()' in VS and 'custom_step(t)' in VS)
c('preview seek clears cover','_apply_cover(0.0)' in VS)
c('canonical base metadata preserved','if not node.has_meta("base_x")' in VS and 'if not name_node.has_meta("base_y")' in VS)

# Clock semantics.
c('FREE RUN can be independent of parked composition','shader_time = free_run_time if time_source == "FREE RUN" else preview_t' in LAB)
c('study has its own presentation transport','study_presentation_time' in LAB)
c('hidden live screen pauses during study','screen.lab_preview_pause()' in LAB)

# Fringe semantics / preview recipe.
c('flow renamed as fringe motion','FRINGE MOTION / DRIVER' in LAB and 'Animate fringe' in LAB)
c('flow controls disabled without fringe','var fringe_on := bool(state["fx_on"]["fringe"])' in LAB)
c('safe animated fringe recipe exists','func _safe_animated_fringe_preview()' in LAB and 'time_source = "FREE RUN"' in LAB)
c('safe recipe disables amplitude envelopes','motion_enabled["fringe"] = false' in LAB and 'motion_enabled["flow"] = false' in LAB)

# Structural sanity.
for text,name in [(LAB,'lab'),(VS,'vs')]:
    for a,b in [('(',')'),('[',']'),('{','}')]:
        c(f'{name} rough balance {a}{b}', text.count(a)==text.count(b))
    funcs=re.findall(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',text,re.M)
    c(f'{name} no duplicate top-level funcs',len(funcs)==len(set(funcs)))

failed=[]
for name,ok in checks:
    print(('PASS' if ok else 'FAIL')+'  '+name)
    if not ok: failed.append(name)
print(f'\n{len(checks)-len(failed)}/{len(checks)} authoring contract checks PASS')
sys.exit(1 if failed else 0)
