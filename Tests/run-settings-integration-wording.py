#!/usr/bin/env python3
"""Protect each independently reviewed integration-audit localization migration."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
expected = json.loads((ROOT/'Tests/Fixtures/SettingsIntegrationWording.json').read_text())
with tempfile.TemporaryDirectory(prefix='texshop-integration-wording-') as temporary:
    folder = Path(temporary)
    for source in (ROOT/'Resources/Interfaces').glob('*.lproj/*.strings'):
        destination = folder/source.relative_to(ROOT/'Resources/Interfaces')
        destination.parent.mkdir(exist_ok=True)
        shutil.copy2(source, destination)

    def check():
        return subprocess.run(['python3', str(ROOT/'Tests/run-settings-ui-wording.py'),
                               '--interfaces', str(folder)], capture_output=True, text=True)

    normal = check()
    assert normal.returncode == 0, normal.stderr
    count = 0
    for language, tables in expected.items():
        for table, entries in tables.items():
            path = folder/(language+'.lproj')/table
            original = path.read_bytes()
            values = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
            for key in entries:
                changed = dict(values)
                changed[key] = 'UNTRANSLATED SETTING'
                path.write_text('\n'.join(json.dumps(k, ensure_ascii=False)+' = '+
                                          json.dumps(v, ensure_ascii=False)+';'
                                          for k, v in changed.items())+'\n')
                result = check()
                path.write_bytes(original)
                assert result.returncode and key in result.stderr and any(
                    reason in result.stderr for reason in (
                        'integration audit reviewed wording', 'translated row name',
                        'sixth audit reviewed wording', 'seventh audit reviewed wording',
                        'eighth audit reviewed wording')), (language, table, key, result.stderr)
                count += 1
                print('DETECTED', language, table, key, flush=True)
    normal = check()
    assert normal.returncode == 0, normal.stderr
    print('NORMAL CONTROL:', count, 'reviewed localization mutations')

