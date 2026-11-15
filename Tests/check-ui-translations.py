#!/usr/bin/env python3
"""Every visible piece of UI text outside the Settings window is translated.

For each of the eleven translations, text that equals the English text is reported
unless Tests/Fixtures/UITranslationAllowlist.json lists it for that language and
file: names, commands and words that are the same in that language. The check covers

- the .strings tables (other than Settings*.strings, which run-settings-visible-text.py
  checks in the composed Settings window): every English key must exist, and its value
  must not be the English text;
- the localized nibs (all of them but Preferences.nib, which is no longer loaded):
  visible titles, tool tips, placeholders and labels that equal a text of the Base nib.
  Hidden views, untitled boxes and image-only buttons are skipped. A nib that exists
  only compiled is read from the compiled archive (all its texts). The tool tips are
  also read from every compiled variant the application may load (keyed archives and
  NIBArchive files), where Interface Builder keeps them apart from the views, so a tool
  tip translated in the source but not in the compiled nib is found too. LaTeX code in
  the tool tips of the LaTeX panel is the same in every language. The tool tips of the
  old Find panel (FindPanel.nib) are left out while nothing opens that panel: the check
  looks for code or a menu item that opens it, and then checks them too.

Japanese, Korean and Chinese text must also contain a character of that script unless
it is allowed (catches English that differs from the current English wording), and
must not be written in one of the other two (Japanese kana or kanji in a Korean nib).
No string of a Korean or Chinese nib, in its source or in any compiled variant, visible
or not, contains Japanese kana.

In the .strings tables, a value is also reported as English, unless allowed, when
- it is the English text in other capitals ("Postscript File" for "PostScript File");
- it reads as an English phrase: common English words make up much of it;
- it is or holds an English text of two or more words (of the English tables, the keys
  of Localizable.strings or the Base nibs) that this language does not keep as its own
  ("Toon Sync Marks" in Dutch, "Split Window" for Split Source in European Portuguese);
- the same key has the same text in languages of three or more families (Spanish and
  the two Portuguese are one family) while English says something else: an English
  wording left from an earlier version ("Sharing" for Share Source in four languages).
  The allowlist's "shared" lists the words that languages really share ("Variante");
- in InfoPlist.strings, it is a file extension where English names a kind ("py" for
  Python File).

Text in the other languages is reported as English, unless allowed, also when
- it is a word of two letters that the Base nib has ("of" in "Page 1 of 3");
- it reads as an English phrase: two or more common English words, which catches an
  English text left from an earlier English wording ("Package name whose documentation
  you want to see:");
- an element of a nib written in XML has the same text as that element in another
  language, outside Spanish and the two Portuguese, while Base says something else
  (an Italian tool tip left in the German nib), or a nib text is another language's
  translation of a text in Localizable.strings or ToolbarItems.strings that this
  language translates differently (Italian "Compila" for Typeset in the German nib).
  The allowlist's "shared" lists the words that two languages really share.
A localized text must not start with a space. The allowlist's "pending" lists texts of
nibs that another change is translating; they are reported as notes, not failures.
"""
from pathlib import Path
import base64
import json
import plistlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'
LANGUAGES = ['de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-PT', 'pt', 'ro', 'zh_CN']
TABLES = ['Localizable', 'ToolbarItems', 'InfoPlist', 'Encodings', 'FindPanel', 'CustomModalWindowController', 'AdvancedFindEngine', 'AdvancedFind', 'MultipleReplaceSamples']
NIBS = ['MainMenu', 'TSDocument', 'MacroEditor', 'matrixpanel', 'completionpanel1.2', 'Movie', 'FindPanel']
ATTRIBUTES = ('title', 'toolTip', 'placeholderString', 'label', 'paletteLabel')
ARCHIVE_KEYS = ('NSTitle', 'NSToolTip', 'NSContents', 'NSPlaceholderString', 'NSWindowTitle')
CJK = re.compile(r'[぀-ヿ㐀-鿿가-힯＀-￯]')
WORD = re.compile(r'[A-Za-z]{3,}')
SHORT = re.compile(r'[A-Za-z]{2}')
# Words of English that the other languages do not use on their own.
ENGLISH = re.compile(r"\b(?:the|you|your|to|of|is|are|this|that|with|for|and|want|whose|will|be|not|can|please|from|which|when|usually|best|would|should|could)\b", re.I)
KANA = re.compile(r'[぀-ヿ]')
HANGUL = re.compile(r'[가-힯]')
HAN = re.compile(r'[一-鿿]')  # Korean in macOS is written without hanja
# Spanish and the two Portuguese share many words; other languages that share a text name it in "shared".
FAMILY = {'es': 'iberian', 'pt': 'iberian', 'pt-PT': 'iberian'}


def english_phrase(text):
    """Two or more common English words that make up much of the text (Dutch and Romanian use some of them too)."""
    words = re.findall(r"[A-Za-z']{2,}", text)
    found = ENGLISH.findall(text)
    return len(found) >= 2 and len(found) >= 0.4 * len(words)


def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def archive_string(element):
    """The text of a <string> of an older Interface Builder archive, also when it is written in base64."""
    if element.get('type') == 'base64-UTF8':
        # Interface Builder leaves out the padding and sometimes ends with one character too many.
        data = re.sub(r'\s', '', element.text or '')
        data = data[:len(data) - len(data) % 4] if len(data) % 4 == 1 else data + '=' * (-len(data) % 4)
        return base64.b64decode(data).decode('utf-8', 'replace')
    return element.text


def nib_texts(path):
    """Visible texts of a nib (modern XIB or old archive format)."""
    root = ET.parse(path).getroot()
    if root.tag == 'archive':
        keys = ARCHIVE_KEYS + ('toolTip',)
        return {archive_string(s) for s in root.iter('string') if s.get('key') in keys and s.text}
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


def element_texts(nib_dir):
    """Texts of a nib written in XML, by element id and attribute (empty for an older or compiled nib)."""
    source = nib_dir / 'designable.nib'
    if not source.exists():
        return {}
    root = ET.parse(source).getroot()
    if root.tag == 'archive':
        return {}
    out = {}
    for e in root.iter():
        if not e.get('id') or e.get('hidden') == 'YES':
            continue
        for a in ATTRIBUTES:
            if e.get(a):
                out[(e.get('id'), a)] = e.get(a)
        for s in e.findall('string'):
            if s.get('key') in ATTRIBUTES and s.text:
                out[(e.get('id'), s.get('key'))] = s.text
    return out


def nibarchive(data):
    """The objects of a NIBArchive (keyedobjects-101300.nib and others): a list of (class name, {key: value}),
    where a value is a number, bytes, or ('object', index)."""
    def varint(pos):
        result = shift = 0
        while True:
            byte = data[pos]; pos += 1
            result |= (byte & 0x7f) << shift; shift += 7
            if byte & 0x80:
                return result, pos
    fields = struct.unpack_from('<10I', data, 10)
    pos, keys = fields[5], []
    for _ in range(fields[4]):
        n, pos = varint(pos); keys.append(data[pos:pos + n].decode()); pos += n
    pos, values = fields[7], []
    sizes = {0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4}
    for _ in range(fields[6]):
        k, pos = varint(pos); kind = data[pos]; pos += 1
        if kind == 8:
            n, pos = varint(pos); value = data[pos:pos + n]; pos += n
        else:
            raw = data[pos:pos + sizes[kind]]; pos += sizes[kind]
            value = ('object', struct.unpack('<I', raw)[0]) if kind == 10 else raw
        values.append((keys[k], value))
    pos, classes = fields[9], []
    for _ in range(fields[8]):
        n, pos = varint(pos); extra, pos = varint(pos); pos += 4 * extra
        classes.append(data[pos:pos + n].rstrip(b'\0').decode()); pos += n
    pos, objects = fields[3], []
    for _ in range(fields[2]):
        c, pos = varint(pos); first, pos = varint(pos); count, pos = varint(pos)
        objects.append((classes[c], dict(values[first:first + count])))
    return objects


def compiled_tooltips(nib_dir):
    """The tool tips of every compiled variant of a nib. Interface Builder keeps them in NSIBHelpConnector
    objects (the text in NSMarker, NSToolTipHelpKey in NSFile), apart from the views."""
    files = [nib_dir] if nib_dir.is_file() else sorted(nib_dir.glob('keyedobjects*.nib'))
    out = set()
    for f in files:
        data = f.read_bytes()
        if data.startswith(b'bplist'):
            objects = plistlib.loads(data)['$objects']
            def deref(value):
                value = objects[value.data] if isinstance(value, plistlib.UID) else value
                if isinstance(value, dict) and 'NS.string' in value:
                    return deref(value['NS.string'])
                return value
            for item in objects:
                if isinstance(item, dict) and '$class' in item and deref(item['$class']).get('$classname') == 'NSIBHelpConnector':
                    if deref(item.get('NSFile')) == 'NSToolTipHelpKey' and isinstance(deref(item.get('NSMarker')), str):
                        out.add(deref(item['NSMarker']))
        elif data.startswith(b'NIBArchive'):
            objects = nibarchive(data)
            def deref(value):
                if isinstance(value, tuple):
                    cls, fields = objects[value[1]]
                    return fields.get('NS.bytes', b'').decode('utf-8') if 'NS.bytes' in fields else None
                return None
            for cls, fields in objects:
                if cls == 'NSIBHelpConnector' and deref(fields.get('NSFile')) == 'NSToolTipHelpKey' and deref(fields.get('NSMarker')):
                    out.add(deref(fields['NSMarker']))
        else:
            raise SystemExit(f'FAIL: {f.relative_to(ROOT)} is neither a keyed archive nor a NIBArchive')
    return out


def all_strings(nib_dir):
    """Every string of a nib, visible or not: the source's text and attributes and the strings of every
    compiled variant."""
    out = set()
    source = nib_dir / 'designable.nib'
    if source.exists():
        for e in ET.parse(source).getroot().iter():
            out.update(v for v in e.attrib.values())
            if e.tag == 'string' and e.text:
                out.add(archive_string(e))
    for f in ([nib_dir] if nib_dir.is_file() else sorted(nib_dir.glob('keyedobjects*.nib'))):
        data = f.read_bytes()
        if data.startswith(b'bplist'):
            out.update(o for o in plistlib.loads(data)['$objects'] if isinstance(o, str))
        else:
            out.update(fields['NS.bytes'].decode('utf-8', 'replace') for cls, fields in nibarchive(data) if isinstance(fields.get('NS.bytes'), bytes))
    return out


def old_find_panel_callers():
    """What opens the old Find panel (FindPanel.nib, TextFinder's panel): sources that ask TextFinder for its
    panel, and nibs that send it orderFrontFindPanel:. Advanced Find and the system's find bar replaced it."""
    callers = [str(f.relative_to(ROOT)) for f in sorted((ROOT / 'Sources').rglob('*.[mh]')) if not f.name.startswith('TextFinder.')
               and re.search(r'orderFrontFindPanel|findNextAndOrderFindPanelOut|\bfindPanel\]|loadNibNamed:\s*@"FindPanel"', f.read_text(errors='replace'))]
    for nib in sorted(INTERFACES.glob('*.lproj/*.nib')):
        if nib.stem != 'FindPanel':
            for f in ([nib] if nib.is_file() else sorted(p for p in nib.iterdir() if p.is_file())):
                if b'orderFrontFindPanel' in f.read_bytes():
                    callers.append(str(f.relative_to(ROOT)))
    return callers


# The tool tips of the old Find panel are never shown while nothing opens it (its other texts are checked).
# Once something opens it again, its tool tips are checked too.
UNSHOWN_TOOLTIPS = () if old_find_panel_callers() else ('FindPanel',)


def interface_texts(nib_dir):
    """A localized nib is checked from its source when it has one, otherwise from the compiled nib, and its
    tool tips from every compiled variant too."""
    source = nib_dir / 'designable.nib'
    texts = nib_texts(source) if source.exists() else compiled_texts(nib_dir)
    if nib_dir.stem in UNSHOWN_TOOLTIPS:
        return texts - compiled_tooltips(nib_dir) - (tooltip_texts(source) if source.exists() else set())
    return texts | compiled_tooltips(nib_dir)


def tooltip_texts(path):
    """The tool tips written in the source of an older nib."""
    root = ET.parse(path).getroot()
    return {archive_string(s) for s in root.iter('string') if s.get('key') == 'toolTip' and s.text} if root.tag == 'archive' else set()


def main():
    contract = json.loads((ROOT / 'Tests/Fixtures/UITranslationAllowlist.json').read_text())
    allow, shared = contract['languages'], set(contract['all_languages'])
    problems = []
    base_nibs = {n: interface_texts(INTERFACES / f'Base.lproj/{n}.nib') for n in NIBS}
    elements = {(lang, n): element_texts(INTERFACES / f'{lang}.lproj/{n}.nib') for lang in ['Base'] + LANGUAGES for n in NIBS}
    shared_with, pending = contract.get('shared', {}), contract.get('pending', {})
    tables = {}
    for lang in LANGUAGES:
        tables[lang] = {}
        for table in ('Localizable', 'ToolbarItems'):
            path = INTERFACES / f'{lang}.lproj/{table}.strings'
            if path.exists():
                tables[lang].update({(table, k): v for k, v in strings(path).items() if isinstance(v, str)})
    notes = []
    # English texts of two or more words (the tables, the keys of Localizable.strings and the Base nibs), which a
    # text of another language does not hold, unless that language keeps the English text as its own translation.
    english_texts = set().union(*base_nibs.values())
    for table in TABLES:
        if (INTERFACES / f'en.lproj/{table}.strings').exists():
            english_texts |= {v for v in strings(INTERFACES / f'en.lproj/{table}.strings').values() if isinstance(v, str)}
    english_texts |= set(strings(INTERFACES / 'en.lproj/Localizable.strings'))
    phrases = sorted({t for t in english_texts if re.fullmatch(r'[A-Za-z]+(?: [A-Za-z]+)+', t)} - shared, key=lambda t: (-len(t), t))
    # Every language's values of each table, for the texts that languages of three families share.
    values_of = {(table, lang): strings(INTERFACES / f'{lang}.lproj/{table}.strings')
                 for table in TABLES for lang in LANGUAGES if (INTERFACES / f'{lang}.lproj/{table}.strings').exists()}
    # The English texts a language keeps as its own (a value that is its English text, or an allowed word).
    own_english = {lang: set().union(*(set(words) for words in allow.get(lang, {}).values())) for lang in LANGUAGES}
    for (table, lang), table_values in values_of.items():
        if (INTERFACES / f'en.lproj/{table}.strings').exists():
            english = strings(INTERFACES / f'en.lproj/{table}.strings')
            own_english[lang] |= {v for k, v in table_values.items() if english.get(k) == v}
    for lang in LANGUAGES:
        allowed = allow.get(lang, {})
        def report(file, text, why):
            if text in pending.get(lang, {}).get(file, []):
                notes.append(f'{lang} {file}: {why} {text!r} (pending)')
            elif text not in shared and text not in allowed.get(file, []):
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
                if table == 'InfoPlist' and (key.startswith('CF') or re.fullmatch(r'[a-z0-9]+', text)):
                    continue  # bundle names, and file extensions that English shows as kinds too
                if table == 'InfoPlist' and isinstance(value, str) and re.fullmatch(r'[a-z0-9]+', value):
                    report(f'{table}.strings', value, f'a file extension where English says {text!r}:')
                    continue
                if not isinstance(value, str) or not WORD.search(value):
                    continue
                if value == text:
                    report(f'{table}.strings', value, 'English')
                elif value.casefold() == text.casefold():
                    report(f'{table}.strings', value, f'English in other capitals ({text!r}):')
                elif lang in ('ja', 'ko', 'zh_CN') and not CJK.search(value):
                    report(f'{table}.strings', value, 'no CJK text')
                elif lang not in ('ja', 'ko', 'zh_CN') and english_phrase(value):
                    report(f'{table}.strings', value, 'English phrase')
                else:
                    for phrase in phrases:
                        if phrase in own_english.get(lang, set()):
                            continue
                        if re.search(r'(?<![A-Za-z])' + re.escape(phrase) + r'(?![A-Za-z])', value):
                            report(f'{table}.strings', value, f'holds the English {phrase!r}:')
                            break
                # The same text in languages of three or more families, where English says something else:
                # an English wording left from an earlier version.
                if value.casefold() != text.casefold() and value not in shared_with.get(lang, []):
                    others = sorted(other for other in LANGUAGES if other != lang and values_of.get((table, other), {}).get(key) == value)
                    if len({FAMILY.get(other, other) for other in others + [lang]}) >= 3:
                        report(f'{table}.strings', value, f'same in {"/".join(others)} where English says {text!r}:')
        for nib in NIBS:
            path = INTERFACES / f'{lang}.lproj/{nib}.nib'
            if not path.exists():
                continue  # this language uses the Base interface
            own_values = set(tables[lang].values())
            for text in sorted(interface_texts(path)):
                if text != text.lstrip():
                    report(f'{nib}.nib', text, 'starts with a space:')
                if WORD.search(text) and text not in base_nibs[nib] and text not in own_values and text not in shared_with.get(lang, []):
                    for other in LANGUAGES:
                        if other == lang or FAMILY.get(other, other) == FAMILY.get(lang, lang):
                            continue
                        keys = [k for k, v in tables[other].items() if v == text and tables[lang].get(k, text) != text]
                        if keys:
                            report(f'{nib}.nib', text, f'{other} for {keys[0][1]!r} ({lang} says {tables[lang][keys[0]]!r}):')
                            break
                if lang == 'ko' and (KANA.search(text) or HAN.search(text)) or lang == 'zh_CN' and (KANA.search(text) or HANGUL.search(text)) or lang == 'ja' and HANGUL.search(text):
                    report(f'{nib}.nib', text, 'text of another language')
                # LaTeX code (the tool tips of the LaTeX Panel) is the same in every language.
                if (not WORD.search(text) and not (SHORT.fullmatch(text.strip()) and text in base_nibs[nib])) or '\\' in text:
                    continue
                if text in base_nibs[nib]:
                    report(f'{nib}.nib', text, 'English')
                elif lang in ('ja', 'ko', 'zh_CN') and not CJK.search(text):
                    report(f'{nib}.nib', text, 'no CJK text')
                elif lang not in ('ja', 'ko', 'zh_CN') and len(ENGLISH.findall(text)) >= 2:
                    report(f'{nib}.nib', text, 'English phrase')
            # No Japanese in a Korean or Chinese nib, in any string of its source or compiled variants.
            if lang in ('ko', 'zh_CN'):
                for text in sorted(t for t in all_strings(path) if KANA.search(t)):
                    report(f'{nib}.nib', text, 'Japanese kana in a string:')
            base_elements, own = elements[('Base', nib)], elements[(lang, nib)]
            for key, text in sorted(own.items()):
                if not WORD.search(text) or base_elements.get(key) in (None, text) or text in base_nibs[nib]:
                    continue
                others = sorted(other for other in LANGUAGES if other != lang and FAMILY.get(other, other) != FAMILY.get(lang, lang)
                                and elements[(other, nib)].get(key) == text)
                if others and text not in shared_with.get(lang, []):
                    report(f'{nib}.nib', text, f'same as {"/".join(others)} where Base says {base_elements[key]!r}:')
    for note in notes:
        print('NOTE', note)
    if problems:
        print('\n'.join(problems))
        print(f'FAIL: {len(problems)} untranslated texts')
        sys.exit(1)
    print(f'PASS: UI text outside Settings is translated in {len(LANGUAGES)} languages ({len(TABLES)} tables, {len(NIBS)} nibs)')


if __name__ == '__main__':
    main()
