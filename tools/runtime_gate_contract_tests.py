#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
PROOT=ROOT/'project' if (ROOT/'project').is_dir() else ROOT
T=(PROOT/'tests/lab_spatial_parity.gd').read_text(encoding='utf-8')
RUN=(ROOT/'RUN_SPATIAL_PARITY.bat').read_text(encoding='utf-8')
A=(PROOT/'tests/lab_authoring_parity_acceptance.gd').read_text(encoding='utf-8')
ARUN=(ROOT/'RUN_AUTHORING_PARITY_ACCEPTANCE.bat').read_text(encoding='utf-8')
checks=[]
def check(n,c): checks.append((n,bool(c)))
for label in ['VS MARK','PRIMARY · GGB','ECHO · GGB','PRIMARY · ICE_MAGE','NAME · GGB']:
    check('real parity target '+label,label in T)
check('uses rendered SubViewport pixels','lab.subvp.get_texture().get_image()' in T)
check('uses controlled background','custom_background.self_modulate' in T)
check('measures base and FX bbox','_bbox_against_corner_background' in T and '_bbox_expansion' in T)
check('converts measured expansion to presentation px','bbox_expansion_presentation_px' in T and 'presentation_expand' in T)
check('checks source-resolution parity ratio','ratio <= 2.0' in T)
check('checks study zoom neutrality','Element Study zoom does not alter authored presentation size' in T)
check('checks team layout slot identity','TEAM_2V2 presentation slots resolve from schema' in T)
check('writes machine-readable evidence','spatial_parity_summary.json' in T)
check('runner pins Godot 4.7.2 console','Godot_v4.7.2-stable_win64_console.exe' in RUN)
check('authoring runtime driver checks numeric overrange','numeric overrange reaches authored state' in A)
check('authoring runtime driver checks Base Opacity isolation','Base Opacity does not leak to non-target' in A)
check('authoring runtime driver checks Mono domain independence','Mono and Colour Dither cell sizes stay independent' in A)
check('authoring runtime driver checks presentation-space VS mark','VS mark does not use raw source size' in A)
check('authoring runtime driver checks vector roles','vector role mounted' in A)
check('authoring runtime driver checks full Element Study','SIDE FIELD · LEFT' in A and 'ACCENT LINE · LEFT' in A)
check('authoring runtime driver checks parked/free-run clocks','FREE RUN shader clock continues while composition is parked' in A)
check('authoring runtime driver checks FX Peak','FX PEAK resolves active envelope peak' in A)
check('authoring runtime driver checks palette locks','Palette A lock preserves authored colour' in A)
check('authoring runtime driver checks semantic production binding','production selector matches researcher use case' in A)
check('authoring runtime runner pins Godot 4.7.2 console','Godot_v4.7.2-stable_win64_console.exe' in ARUN)
failed=[n for n,c in checks if not c]
for n,c in checks: print(('PASS' if c else 'FAIL')+'  '+n)
print(f'\n{len(checks)-len(failed)}/{len(checks)} runtime-gate contract checks PASS')
sys.exit(1 if failed else 0)
