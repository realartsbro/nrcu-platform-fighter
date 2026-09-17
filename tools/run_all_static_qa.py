#!/usr/bin/env python3
from pathlib import Path
import subprocess, re, json, sys
ROOT=Path(__file__).resolve().parents[1]
rows=[]; passed=0; total=0; failures=[]
for p in sorted((ROOT/'tools').glob('*tests.py')):
    cp=subprocess.run([sys.executable,str(p)],cwd=ROOT,capture_output=True,text=True)
    m=re.search(r'(\d+)/(\d+) .*?PASS',cp.stdout)
    pa=to=0
    if m:
        pa,to=map(int,m.groups()); passed+=pa; total+=to
    row={'suite':p.name,'returncode':cp.returncode,'passed':pa,'total':to}
    rows.append(row)
    print(f"{'PASS' if cp.returncode==0 else 'FAIL'}  {p.name}  {pa}/{to}")
    if cp.returncode!=0:
        failures.append({'suite':p.name,'stdout':cp.stdout[-6000:],'stderr':cp.stderr[-2000:]})
summary={'passed':passed,'total':total,'suite_count':len(rows),'suites':rows,'failures':failures}
(ROOT/'STATIC_QA_AUTHORING_PARITY.json').write_text(json.dumps(summary,indent=2)+"\n",encoding='utf-8')
(ROOT/'STATIC_QA_AUTHORING_PARITY.log').write_text('\n'.join([f"{r['suite']}: {r['passed']}/{r['total']} rc={r['returncode']}" for r in rows])+f"\nTOTAL {passed}/{total}\n",encoding='utf-8')
print(f"\nTOTAL {passed}/{total} static source checks PASS" if not failures else f"\nTOTAL {passed}/{total}; {len(failures)} suites FAILED")
sys.exit(1 if failures else 0)
