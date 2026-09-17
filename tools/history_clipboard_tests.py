#!/usr/bin/env python3
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
S=(PROOT/'scripts/nrcu_fx_lab_v2.gd').read_text()
checks=[]
def c(n,x): checks.append((n,bool(x)))
def body(name):
 m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',S,re.M)
 if not m:return ''
 st=m.end(); n=re.search(r'^func \w+\(',S[st:],re.M); return S[st:st+(n.start() if n else len(S)-st)]
for fn in ['_history_reset_to_current','_queue_history_checkpoint','_history_commit_current','_undo_look','_redo_look','_restore_history_index','_copy_section','_paste_section','_unhandled_key_input']:
 c('function '+fn,('func '+fn+'(') in S)
c('history stores look snapshots only','look_history.append(_snapshot())' in body('_history_reset_to_current') and 'target_mode' not in body('_history_reset_to_current'))
c('history coalesces interactive edits','history_pending_elapsed >= 0.18' in body('_process'))
c('redo branch truncated after edit','look_history.resize(history_index + 1)' in body('_history_commit_current'))
c('history bounded','history_limit' in body('_history_commit_current') and 'pop_front' in body('_history_commit_current'))
c('dirty state recomputed against loaded authority','_dirty_against_loaded()' in body('_restore_history_index'))
c('look edits queue history','_queue_history_checkpoint()' in body('_mark_dirty'))
c('target context still excluded from history dirtying','_mark_dirty()' not in body('_on_target_mode') and '_mark_dirty()' not in body('_on_slot'))
c('copy supports motion section','MOTION:' in body('_section_snapshot'))
c('copy supports effect enable/amount','fx_on:' in body('_section_snapshot') and 'fx_amount:' in body('_section_snapshot'))
c('copy supports masks','edge_mask_path' in body('_section_snapshot') and 'treatment_mask_path' in body('_section_snapshot'))
c('paste requires same section','section_clipboard_id != section_id' in body('_paste_section'))
c('section header exposes copy','copy_button.text = "COPY"' in body('_section'))
c('section header exposes paste','paste_button.text = "PASTE"' in body('_section'))
keys=body('_unhandled_key_input')
c('Ctrl Z undo','KEY_Z' in keys and '_undo_look()' in keys)
c('Ctrl Y redo','KEY_Y' in keys and '_redo_look()' in keys)
c('Space transport shortcut','KEY_SPACE' in keys and '_toggle_transport()' in keys)
c('Arrow frame-step shortcuts','KEY_LEFT' in keys and 'KEY_RIGHT' in keys)
failed=[x for x in checks if not x[1]]
for n,o in checks: print(('PASS' if o else 'FAIL')+'  '+n)
print(f'\n{len(checks)-len(failed)}/{len(checks)} history/clipboard checks PASS')
sys.exit(1 if failed else 0)
