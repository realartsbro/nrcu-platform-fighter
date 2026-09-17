#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
SCRIPT=(PROOT/'scripts/nrcu_fx_lab_v2.gd').read_text(encoding='utf-8')
REGISTRY=(PROOT/'scripts/vs_fx_style_registry.gd').read_text(encoding='utf-8')
LOOKS=PROOT/'assets/vs/fx/fx_looks.json'
ASSIGN=PROOT/'assets/vs/fx/fx_assignments.json'
checks=[]
def check(name,cond,detail=''):
    checks.append((name,bool(cond),detail))
def func_body(name):
    m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',SCRIPT,re.M)
    if not m: return ''
    start=m.end(); n=re.search(r'^func \w+\(',SCRIPT[start:],re.M)
    return SCRIPT[start:start+(n.start() if n else len(SCRIPT)-start)]

# Files/schemas
check('production looks file exists',LOOKS.exists())
check('production assignments file exists',ASSIGN.exists())
if LOOKS.exists():
    d=json.loads(LOOKS.read_text())
    check('looks schema exact',d.get('schema')=='NRCU_VS_FX_LOOKS_V1')
    check('looks root keyed dictionary',isinstance(d.get('looks'),dict))
if ASSIGN.exists():
    d=json.loads(ASSIGN.read_text())
    check('assignments schema exact',d.get('schema')=='NRCU_VS_FX_ASSIGNMENTS_V1')
    check('bindings root array',isinstance(d.get('bindings'),list))

# Look/target separation.
save=func_body('_save_preset'); load=func_body('_load_preset'); snap=func_body('_snapshot'); apply_snap=func_body('_apply_snapshot'); export=func_body('_export_json'); imp=func_body('_import_json')
for label,body in [('ConfigFile save',save),('ConfigFile load',load),('A/B snapshot',snap),('A/B apply',apply_snap)]:
    check(label+' excludes target_mode','target_mode' not in body)
    check(label+' excludes selected_slot','selected_slot' not in body)
check('JSON export relegates target to preview context','preview_context' in export and 'target' in export)
check('JSON import does not apply target_mode','target_mode =' not in imp)
check('target changes do not dirty look','_mark_dirty()' not in func_body('_on_target_mode') and '_mark_dirty()' not in func_body('_on_target_role') and '_mark_dirty()' not in func_body('_on_slot'))

# Published look payload is style only.
payload=func_body('_production_look_payload')
for key in ['state','motion','motion_enabled','time_source','edge_mask_path','treatment_mask_path']:
    check('production payload contains '+key,('"'+key+'"') in payload)
for key in ['target_mode','target_role','selected_slot','fighter_id','presentation_slot','mode_family']:
    check('production payload excludes '+key,key not in payload)
check('production publish creates clean authority snapshot','loaded_look_is_production = true' in func_body('_publish_current_look') and 'loaded_look_snapshot = _snapshot()' in func_body('_publish_current_look'))

# Selector identity and scopes.
ctx=func_body('_current_target_context')
check('fighter identity derives from texture asset path','_fighter_from_target_node' in ctx)
check('context carries semantic role','element_role' in ctx)
check('context carries presentation slot when available','presentation_slot' in ctx)
check('context carries visual side when available','visual_side' in ctx and '_visual_side_for_slot' in ctx)
check('context carries semantic team side in team families','team_side' in ctx and '_team_side_for_slot' in ctx)
check('presentation-slot resolver reads real multiplayer layout schema','multiplayer_layouts' in func_body('_presentation_slot_from_key'))
check('team slot resolver supports A/B family slots','a_' in func_body('_team_side_for_slot') and 'b_' in func_body('_team_side_for_slot'))
check('visual side comes from real layout slot metadata','multiplayer_layouts' in func_body('_visual_side_for_slot') and 'side' in func_body('_visual_side_for_slot'))
check('context can carry static element id','element_id' in ctx)
check('context carries mode family','mode_family' in ctx)
check('context carries stage id','stage_id' in ctx)
selector=func_body('_selector_for_scope')
for scope in ['ROLE ONLY','FIGHTER + ROLE + VISUAL SIDE','FIGHTER + ROLE','ROLE + VISUAL SIDE','STATIC ELEMENT']:
    check('selector scope '+scope,scope in selector)
check('exact selector includes mode family','selector["mode_family"] = mode_format' in selector)
check('FIGHTER+ROLE omits side constraint','"presentation_slot"' not in re.search(r'"FIGHTER \+ ROLE":(.*?)(?=\n\s*"|\n\s*_:)',selector,re.S).group(1))

# Resolver is a shared runtime/lab authority rather than duplicated logic.
score=func_body('_selector_score'); resolve=func_body('_resolve_assignment')
check('lab delegates selector scoring to shared registry','StyleRegistry.selector_score' in score)
check('lab delegates binding resolution to shared registry','StyleRegistry.resolve_binding' in resolve)
check('registry scoring weights semantic identity',all(k in REGISTRY for k in ['element_id','fighter_id','element_role','presentation_slot','visual_side','team_side','mode_family','stage_id']))
check('registry compares specificity score','score > best_score' in REGISTRY)
check('registry requires all selector keys','selector_matches(selector, context)' in REGISTRY)
check('registry equal-score resolution is deterministic','score == best_score' in REGISTRY and 'i > best_index' in REGISTRY)
check('registry can resolve project binding','resolve_project_binding' in REGISTRY and 'ASSIGNMENTS_PATH' in REGISTRY)
check('registry can return resolved production look','resolve_project_look' in REGISTRY and 'production_look' in REGISTRY)
check('assignment replacement uses canonical selector key','_selector_key(selector)' in func_body('_assign_current_look'))
check('unassign uses same selector identity','_selector_key(selector)' in func_body('_unassign_current'))

# Context refresh: selection changes must update resolver UI.
for fn in ['_mount_screen','_on_source_mode','_on_target_mode','_on_target_role','_on_slot']:
    check(fn+' refreshes assignment resolution','_refresh_assignment_view()' in func_body(fn))

# Runtime-authority write path.
write=func_body('_write_production_doc')
check('production write targets project-resolved filesystem','ProjectSettings.globalize_path' in write)
check('production writer creates FX directory','make_dir_recursive_absolute' in write)
check('production look can be loaded into authoring state','_deep_merge' in func_body('_apply_production_look') and '_apply_fx()' in func_body('_apply_production_look'))
check('resolved assignment can load its look','_resolve_assignment' in func_body('_load_resolved_assignment') and '_apply_production_look' in func_body('_load_resolved_assignment'))


# Production library management must be explicit and assignment-safe.
dup=func_body('_duplicate_production_look'); ren=func_body('_rename_production_look')
check('production duplicate requires loaded production authority','loaded_look_is_production' in dup and 'target production look already exists' in dup)
check('production rename requires loaded production authority','loaded_look_is_production' in ren and 'target production look already exists' in ren)
check('production rename updates binding references','bindings' in ren and 'look_id' in ren and 'source_id' in ren and 'target_id' in ren)
check('production rename writes looks and assignments','PRODUCTION_LOOKS_PATH' in ren and 'PRODUCTION_ASSIGNMENTS_PATH' in ren)

failed=[x for x in checks if not x[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL')+'  '+name+((' :: '+detail) if detail and not ok else ''))
print(f'\n{len(checks)-len(failed)}/{len(checks)} production-assignment checks PASS')
sys.exit(1 if failed else 0)
