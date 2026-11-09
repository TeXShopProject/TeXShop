#!/usr/bin/env python3
"""Protect localized menu lookup, unique strings keys and cross-language coverage.

Known pre-existing lookup misses are fixed in MenuLocalization.json; never derive
exceptions from the resource being tested. Settings category names use a separate table.
"""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[=;]|[^\s"=;/]+', re.S)


def strings(path):
    data = path.read_bytes()
    values = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
    if data.startswith(b'bplist') or data.lstrip().startswith(b'<?xml'):
        return values  # Compiled product; source uniqueness is checked separately.
    text = data.decode('utf-16' if data[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig')
    tokens, end = [], 0
    for match in TOKEN.finditer(text):
        assert match.start() == end, (path, 'unparsed text', end)
        end = match.end()
        token = match[0]
        if token.isspace() or token.startswith(('/*', '//')):
            continue
        tokens.append(token)
    assert end == len(text) and len(tokens) % 4 == 0, (path, 'invalid strings syntax')
    seen = set()
    for i in range(0, len(tokens), 4):
        key, equals, value, semicolon = tokens[i:i+4]
        assert equals == '=' and semicolon == ';', (path, 'invalid entry', key)
        key = json.loads(key.replace('\\U', '\\u')) if key.startswith('"') else key
        assert key not in seen, (path, 'duplicate key', key)
        seen.add(key)
    assert seen == values.keys(), (path, 'lexical and plist keys differ')
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=ROOT/'Resources/Interfaces')
    parser.add_argument('--app', type=Path)
    parser.add_argument('--static-only', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    contract = json.loads((ROOT/'Tests/Fixtures/MenuLocalization.json').read_text())
    routes, exceptions = contract['routes'], contract['exceptions']
    lookups = set()
    for path in (ROOT/'Sources').rglob('*.m'):
        lookups.update(re.findall(r'\[NSApp\s+mainMenu\]\s+itemWithTitle:\s*NSLocalizedString\(@"([^"]+)"', path.read_bytes().decode('utf-8', errors='replace')))
    assert lookups == {key for key, parents in routes.items() if not parents}, 'Update explicit top-level lookup coverage'
    tables = {lang: strings(args.resources/f'{lang}.lproj/Localizable.strings') for lang in contract['languages']}
    keys = set(tables['en'])
    assert {'Preview', 'Cancel', 'Stop Experiment'} <= keys
    for lang, values in tables.items():
        assert set(values) == keys, (lang, 'key set differs', sorted(keys-values.keys()), sorted(values.keys()-keys))
        assert not any('Dateigröße' in key or key.startswith('Your changes in this window will be removed.') for key in values), (lang, 'obsolete key')
    records, runtime_count = [], 0
    with tempfile.TemporaryDirectory(prefix='texshop-menu-localization-') as tmp:
        temporary = Path(tmp)
        (temporary/'Library/Preferences').mkdir(parents=True)
        env = dict(os.environ, HOME=tmp, CFFIXED_USER_HOME=tmp)
        exe = temporary/'menu-localization'
        if not args.static_only:
            subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(ROOT/'Tests/MenuLocalization.m'), '-o', str(exe)], check=True)
        for lang, values in tables.items():
            menu_lang = 'Base' if lang == 'en' else lang
            source = args.resources/f'{menu_lang}.lproj/MainMenu.nib'
            main_menu = ET.parse(source/'designable.nib').find('.//menu[@systemMenu="main"]')
            if args.app:
                resources = args.app/'Contents/Resources'
                assert strings(resources/f'{lang}.lproj/Localizable.strings') == values, (lang, 'product strings differ')
                binary = resources/f'{menu_lang}.lproj/MainMenu.nib'
            else:
                binary = source
            cases = []
            for key, parents in routes.items():
                menu = main_menu
                parent_values = [values.get(part, part) for part in parents]
                for title in parent_values:
                    item = next((item for item in menu.findall('items/menuItem') if item.get('title') == title), None) if menu is not None else None
                    menu = item.find('menu') if item is not None else None
                title = values.get(key, key)
                found = menu is not None and any(item.get('title') == title for item in menu.findall('items/menuItem'))
                if not found:
                    assert exceptions.get(lang+':'+key) == {'value': title, 'parentValues': parent_values}, (lang, 'menu lookup failed', key, title)
                cases.append({'key': key, 'title': title, 'parents': parent_values, 'found': found})
            records.append({'language': lang, 'keys': len(values), 'lookups': cases})
            if not args.static_only:
                case_file = temporary/(lang+'.json'); case_file.write_text(json.dumps(cases))
                variants = sorted(binary.glob('keyedobjects*.nib')) if binary.is_dir() else [binary]
                assert variants, (lang, 'no compiled menus')
                for variant in variants:
                    result = subprocess.run([str(exe), str(variant), str(case_file)], env=env, capture_output=True, text=True, timeout=30)
                    assert result.returncode == 0, (variant, result.stdout, result.stderr)
                    runtime_count += len(cases)
    if args.report:
        args.report.write_text(json.dumps({'languages': records, 'compiledLookups': runtime_count}, ensure_ascii=False, indent=2))
    print(f'PASS: {len(tables)} languages, {len(keys)} unique keys each, {len(routes)*len(tables)} scoped lookups, {runtime_count} compiled lookups')


if __name__ == '__main__':
    main()
