#!/usr/bin/env python3
"""Reverting a reviewed row translation must fail its independent wording contract."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile

r=Path(__file__).resolve().parents[1]
expected=json.loads((r/'Tests/Fixtures/SettingsRowTranslations.json').read_text())['rows']
with tempfile.TemporaryDirectory(prefix='texshop-row-translations-') as temp:
    t=Path(temp)
    for source in (r/'Resources/Interfaces').glob('*.lproj/*.strings'):
        destination=t/source.relative_to(r/'Resources/Interfaces')
        destination.parent.mkdir(exist_ok=True)
        shutil.copy2(source,destination)
    def check():
        return subprocess.run(['python3',str(r/'Tests/run-settings-ui-wording.py'),'--interfaces',str(t)],capture_output=True,text=True)
    result=check();assert result.returncode==0,result.stderr
    for lang,values in expected.items():
        path=t/f'{lang}.lproj/SettingsCategories.strings'
        original=path.read_bytes()
        dictionary=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
        key=next(iter(values));dictionary[key]='UNTRANSLATED ROW'
        path.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in dictionary.items()))
        result=check();assert result.returncode and 'translated row name' in result.stderr,(lang,result.stderr)
        path.write_bytes(original)
        print('DETECTED untranslated row',lang,flush=True)
    result=check();assert result.returncode==0,result.stderr
    print('NORMAL CONTROL: reviewed translations in all reviewed languages')
