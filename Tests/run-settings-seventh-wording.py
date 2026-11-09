#!/usr/bin/env python3
"""Corrupt each explicitly reviewed seventh-audit wording value in isolation."""
from pathlib import Path
import tempfile,subprocess,shutil,json
R=Path(__file__).resolve().parents[1]
expected=json.loads((R/'Tests/Fixtures/SettingsSeventhWording.json').read_text())
with tempfile.TemporaryDirectory(prefix='texshop-seventh-wording-')as td:
    T=Path(td)
    for p in(R/'Resources/Interfaces').glob('*.lproj/*.strings'):
        dest=T/p.relative_to(R/'Resources/Interfaces');dest.parent.mkdir(exist_ok=True);shutil.copy2(p,dest)
    def run():
        return subprocess.run(['python3',str(R/'Tests/run-settings-ui-wording.py'),'--interfaces',str(T)],capture_output=True,text=True)
    result=run();assert result.returncode==0,result.stderr
    for lang,tables in expected.items():
        for table,entries in tables.items():
            path=T/f'{lang}.lproj'/table;original=path.read_bytes()
            values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
            for key in entries:
                changed=dict(values);changed[key]='UNREVIEWED WORDING'
                path.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in changed.items())+'\n')
                result=run();path.write_bytes(original)
                assert result.returncode and any(message in result.stderr for message in ['seventh audit reviewed wording','sixth audit reviewed wording','translated row name']),(lang,table,key,result.stderr)
                print('DETECTED',lang,table,key,flush=True)
    result=run();assert result.returncode==0,result.stderr
    print('NORMAL CONTROL seventh wording')
