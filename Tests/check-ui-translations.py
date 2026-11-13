#!/usr/bin/env python3
"""Every visible piece of UI text outside the Settings window is translated.

For each of the eleven translations, text that equals the English text is reported
unless Tests/Fixtures/UITranslationAllowlist.json lists it for that language and
file: names, commands and words that are the same in that language. The check covers

- the .strings tables (other than Settings*.strings, which run-settings-visible-text.py
  checks in the composed Settings window): every English key must exist, and its value
  must not be the English text;
- the localized nibs: visible titles, tool tips, placeholders and labels that equal a
  text of the Base nib. Hidden views, untitled boxes and image-only buttons are skipped.
  A nib that exists only compiled is read from the compiled archive (all its texts).

Japanese, Korean and Chinese text must also contain a character of that script unless
it is allowed (catches English that differs from the current English wording).
"""
from pathlib import Path
import json
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'
LANGUAGES = ['de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-PT', 'pt', 'ro', 'zh_CN']
TABLES = ['Localizable', 'ToolbarItems', 'InfoPlist', 'Encodings', 'FindPanel', 'CustomModalWindowController']
NIBS = ['MainMenu', 'TSDocument', 'MacroEditor', 'matrixpanel', 'completionpanel1.2', 'Movie', 'FindPanel']
ATTRIBUTES = ('title', 'toolTip', 'placeholderString', 'label', 'paletteLabel')
ARCHIVE_KEYS = ('NSTitle', 'NSToolTip', 'NSContents', 'NSPlaceholderString')
CJK = re.compile(r'[぀-ヿ㐀-鿿가-힯＀-￯]')
WORD = re.compile(r'[A-Za-z]{3,}')


def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def nib_texts(path):
    """Visible texts of a nib (modern XIB or old archive format)."""
    root = ET.parse(path).getroot()
    if root.tag == 'archive':
        return {s.text for s in root.iter('string') if s.get('key') in ARCHIVE_KEYS and s.text}
    parents = {child: parent for parent in root.iter() for child in parent}
    def hidden(e):
        while e is not None:
            if e.get('hidden') == 'YES':
                return True
            e = parents.get(e)
        return False
    out = set()
    for e in root.iter():
        if hidden(e) or e.get('imagePosition') == 'only' or (e.tag == 'box' and e.get('titlePosition') == 'noTitle'):
            continue
        for a in ATTRIBUTES:
            if e.get(a):
                out.add(e.get(a))
        for s in e.findall('string'):
            if s.get('key') in ATTRIBUTES and s.text:
                out.add(s.text)
    return out


def compiled_texts(nib_dir):
    """Texts of a nib that only exists compiled (a keyed archive): every title, content and tool tip."""
    files = [nib_dir] if nib_dir.is_file() else sorted(nib_dir.glob('keyedobjects*.nib'))
    out = set()
    for f in files:
        data = f.read_bytes()
        if not data.startswith(b'bplist'):
            raise SystemExit(f'FAIL: {f.relative_to(ROOT)} cannot be read as a keyed archive')
        objects = plistlib.loads(data)['$objects']
        def text(value):
            if isinstance(value, plistlib.UID):
                value = objects[value.data]
            if isinstance(value, str):
                return value
            if isinstance(value, dict):
                for key in ('NS.string', 'NSString'):
                    if key in value:
                        return text(value[key])
            return None
        for item in objects:
            if isinstance(item, dict):
                for key in ARCHIVE_KEYS:
                    if key in item and text(item[key]):
                        out.add(text(item[key]))
    if not files:
        raise SystemExit(f'FAIL: {nib_dir.relative_to(ROOT)} has neither a source nor a compiled nib')
    return out


def interface_texts(nib_dir):
    """A localized nib is checked from its source when it has one, otherwise from the compiled nib."""
    source = nib_dir / 'designable.nib'
    return nib_texts(source) if source.exists() else compiled_texts(nib_dir)


def main():
    contract = json.loads((ROOT / 'Tests/Fixtures/UITranslationAllowlist.json').read_text())
    allow, shared = contract['languages'], set(contract['all_languages'])
    problems = []
    base_nibs = {n: interface_texts(INTERFACES / f'Base.lproj/{n}.nib') for n in NIBS}
    for lang in LANGUAGES:
        allowed = allow.get(lang, {})
        def report(file, text, why):
            if text not in shared and text not in allowed.get(file, []):
                problems.append(f'{lang} {file}: {why} {text!r}')
        for table in TABLES:
            english_path = INTERFACES / f'en.lproj/{table}.strings'
            path = INTERFACES / f'{lang}.lproj/{table}.strings'
            if not english_path.exists() or not path.exists():
                continue
            english, values = strings(english_path), strings(path)
            for key, text in english.items():
                if key not in values:
                    problems.append(f'{lang} {table}.strings: missing key {key!r}')
                    continue
                value = values[key]
                if not isinstance(value, str) or not WORD.search(value):
                    continue
                if table == 'InfoPlist' and (key.startswith('CF') or re.fullmatch(r'[a-z0-9]+', value)):
                    continue  # bundle names and file extensions shown as kinds
                if value == text:
                    report(f'{table}.strings', value, 'English')
                elif lang in ('ja', 'ko', 'zh_CN') and not CJK.search(value):
                    report(f'{table}.strings', value, 'no CJK text')
        for nib in NIBS:
            path = INTERFACES / f'{lang}.lproj/{nib}.nib'
            if not path.exists():
                continue  # this language uses the Base interface
            for text in sorted(interface_texts(path)):
                if not WORD.search(text):
                    continue
                if text in base_nibs[nib]:
                    report(f'{nib}.nib', text, 'English')
                elif lang in ('ja', 'ko', 'zh_CN') and not CJK.search(text):
                    report(f'{nib}.nib', text, 'no CJK text')
    if problems:
        print('\n'.join(problems))
        print(f'FAIL: {len(problems)} untranslated texts')
        sys.exit(1)
    print(f'PASS: UI text outside Settings is translated in {len(LANGUAGES)} languages ({len(TABLES)} tables, {len(NIBS)} nibs)')


if __name__ == '__main__':
    main()
