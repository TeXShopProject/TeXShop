#!/usr/bin/env python3
"""Check wording from the actual localized production views in all twelve locales.

The probe never orders windows and uses memory defaults. Fixed text matching Base
must have an explicit, location-specific language allowance. Dictionary codes,
encoding names and user values are runtime data rather than translated labels.
"""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-PT', 'pt', 'ro', 'zh_CN']
CATEGORIES = {'general', 'documents', 'editor', 'spelling', 'appearance', 'preview',
              'typesetting', 'console', 'keyboard', 'updates'}


def identity(record):
    return tuple(record[k] for k in ('category', 'id', 'role', 'text'))


def failures(language, records, base, allowances):
    allowed = {identity(record) for record in allowances['languages'][language]}
    identical = []
    for record in records:
        text = record['text']
        if text not in base or not re.search('[A-Za-z]', text):
            continue
        # These two controls obtain their choice names from runtime registries.
        # A translated label or the "Automatic Language" choice is not exempt.
        if (record['category'], record['id'], record['role']) == ('documents', 'settings.278', 'choice'):
            continue
        if ((record['category'], record['id'], record['role']) == ('spelling', 'settings.o1v-YF-ekd', 'choice')
                and re.fullmatch('[a-z]{2,3}(?:_[A-Z]{2})?', text)):
            continue
        if identity(record) not in allowed:
            identical.append(record)
    return identical


def check_inventory(folder):
    allowance = json.loads((ROOT/'Tests/Fixtures/SettingsVisibleTextAllowlist.json').read_text())
    assert set(allowance['languages']) == set(LANGUAGES)-{'Base'}
    base = {r['text'] for r in json.loads((folder/'Base.json').read_text())}
    results = []
    for language in LANGUAGES:
        records = json.loads((folder/(language+'.json')).read_text())
        assert {r['category'] for r in records} == CATEGORIES, (language, 'all ten visible categories required')
        assert len(records) > 250, (language, 'incomplete visible text inventory')
        unknown = [] if language == 'Base' else failures(language, records, base, allowance)
        results.append({'language': language, 'records': len(records), 'untranslated': unknown})
    assert not any(r['untranslated'] for r in results), json.dumps(results, ensure_ascii=False)
    return results


def probe(output, app=None, language=None, mutation=False):
    command = ['python3', str(ROOT/'Tests/run-settings-product-shell.py'), '--visible-text-output', str(output)]
    if app:
        command += ['--app', str(app)]
    if language:
        command += ['--language', language]
    if mutation:
        command += ['--visible-text-mutation']
    output.mkdir(parents=True, exist_ok=True)
    # Also isolate when this runner is invoked directly.
    with tempfile.TemporaryDirectory(prefix='texshop-visible-defaults-') as home:
        env = dict(os.environ, HOME=home, CFFIXED_USER_HOME=home, PYTHONDONTWRITEBYTECODE='1')
        with (output/'probe.log').open('w') as log:
            subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--inventory', type=Path, help='Check an already captured real-view inventory')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-visible-wording-') as temporary:
        output = args.output or Path(temporary)
        folder = args.inventory or output/'normal'
        if not args.inventory:
            probe(folder, args.app)
        results = check_inventory(folder)
        output.mkdir(parents=True, exist_ok=True)
        (output/'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n')
        print('PASS: all 12 languages, 10 categories,', sum(r['records'] for r in results), 'visible texts')
        if args.mutations:
            changed = output/'english-mutation'
            probe(changed, args.app, 'fr', True)
            base = {r['text'] for r in json.loads((folder/'Base.json').read_text())}
            allowance = json.loads((ROOT/'Tests/Fixtures/SettingsVisibleTextAllowlist.json').read_text())
            found = failures('fr', json.loads((changed/'fr.json').read_text()), base, allowance)
            assert found and all(r['text'] == 'Typing' and r['category'] == 'editor' for r in found), found
            (output/'detected.json').write_text(json.dumps(found, ensure_ascii=False, indent=2)+'\n')
            print('DETECTED: fr group.editor.2.title -> Typing in actual production view')
            restored = output/'restored'
            probe(restored, args.app, 'fr')
            assert not failures('fr', json.loads((restored/'fr.json').read_text()), base, allowance)
            print('NORMAL CONTROL: restored French production view')
        return 0


if __name__ == '__main__':
    raise SystemExit(main())

