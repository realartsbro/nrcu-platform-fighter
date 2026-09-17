#!/usr/bin/env python3
from pathlib import Path
import re, sys
p=Path(__file__).resolve().parents[1]
s=(p/'project/scripts/nrcu_fx_lab_v2.gd').read_text()
checks=[]
def c(name,ok): checks.append((name,bool(ok)))
def body(name):
 m=re.search(rf'^func {re.escape(name)}\([^\n]*\).*?:\n',s,re.M)
 if not m:return ''
 st=m.end(); n=re.search(r'^func \w+\(',s[st:],re.M)
 return s[st:st+(n.start() if n else len(s)-st)]
for fn in ['_coverage_contexts','_production_coverage_report','_refresh_assignment_coverage']:
 c('coverage function '+fn, 'func '+fn in s)
cb=body('_coverage_contexts')
for role in ['primary','echo','name']:
 c('coverage samples '+role, f'"{role}"' in cb)
for side in ['left','right']:
 c('coverage samples visual side '+side, f'"{side}"' in cb)
for eid in ['vs_mark','side_field_left','side_field_right','name_plate_left','name_plate_right','accent_line_left','accent_line_right','stage']:
 c('coverage static '+eid, eid in cb)
rb=body('_production_coverage_report')
c('coverage resolves through shared registry','StyleRegistry.resolve_binding' in rb)
c('coverage distinguishes broken look refs','BROKEN' in rb and 'looks.has(look_id)' in rb)
c('coverage distinguishes unassigned','UNASSIGNED' in rb)
c('coverage tab exists','PRODUCTION COVERAGE' in s)
c('coverage refresh button exists','REFRESH COVERAGE' in s)
c('coverage updates with assignment refresh','_refresh_assignment_coverage()' in body('_refresh_assignment_view'))
failed=[x for x in checks if not x[1]]
for name,ok in checks: print(('PASS' if ok else 'FAIL')+'  '+name)
print(f'\n{len(checks)-len(failed)}/{len(checks)} production-coverage checks PASS')
sys.exit(1 if failed else 0)
