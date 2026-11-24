#!/usr/bin/env python3
"""Character Info's counts and the name line of a character made of several code points, in the twelve languages:
"1 character, 1 word, 1 line" and "2 characters, 1 word, 3 lines" with the singular and plural of each language
(Localizable.stringsdict, read by a small probe application as TeXShop reads it), the words of the status bar
("Characters"), and the keys of Sources/Panels/TSGlyphPopoverController.m found in every language.
Nothing is shown on screen.

  --mutation NAME   check that the test fails with a known mistake"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parent))
from source_tree import source_file

root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
COUNTS = '%d characters, %d words, %d lines'
COMPLEX = '<a character consisting of %d code points>'

# (1, 1, 1), (2, 1, 3), then a character of 2 and of 20 code points.
EXPECTED = {
    'en': ['1 character, 1 word, 1 line', '2 characters, 1 word, 3 lines', '<a character consisting of 2 code points>', '<a character consisting of 20 code points>'],
    'de': ['1 Zeichen, 1 Wort, 1 Zeile', '2 Zeichen, 1 Wort, 3 Zeilen', '<ein Zeichen aus 2 Codepunkten>', '<ein Zeichen aus 20 Codepunkten>'],
    'es': ['1 carácter, 1 palabra, 1 línea', '2 caracteres, 1 palabra, 3 líneas', '<un carácter compuesto por 2 puntos de código>', '<un carácter compuesto por 20 puntos de código>'],
    'fr': ['1 caractère, 1 mot, 1 ligne', '2 caractères, 1 mot, 3 lignes', '<un caractère composé de 2 points de code>', '<un caractère composé de 20 points de code>'],
    'it': ['1 carattere, 1 parola, 1 riga', '2 caratteri, 1 parola, 3 righe', '<un carattere composto da 2 punti di codice>', '<un carattere composto da 20 punti di codice>'],
    'ja': ['1文字，1単語，1行', '2文字，1単語，3行', '<2個のコードポイントからなる文字>', '<20個のコードポイントからなる文字>'],
    'ko': ['문자 1개, 단어 1개, 줄 1개', '문자 2개, 단어 1개, 줄 3개', '<코드 포인트 2개로 이루어진 문자>', '<코드 포인트 20개로 이루어진 문자>'],
    'nl': ['1 teken, 1 woord, 1 regel', '2 tekens, 1 woord, 3 regels', '<een teken bestaande uit 2 codepunten>', '<een teken bestaande uit 20 codepunten>'],
    'pt': ['1 caractere, 1 palavra, 1 linha', '2 caracteres, 1 palavra, 3 linhas', '<um caractere formado por 2 pontos de código>', '<um caractere formado por 20 pontos de código>'],
    'pt-PT': ['1 carácter, 1 palavra, 1 linha', '2 caracteres, 1 palavra, 3 linhas', '<um carácter composto por 2 pontos de código>', '<um carácter composto por 20 pontos de código>'],
    'ro': ['Caractere: 1, cuvinte: 1, linii: 1', 'Caractere: 2, cuvinte: 1, linii: 3', '<un caracter format din 2 puncte de cod>', '<un caracter format din 20 de puncte de cod>'],
    'zh_CN': ['1个字符, 1个单词, 共 1行', '2个字符, 1个单词, 共 3行', '<由2个码位组成的字符>', '<由20个码位组成的字符>'],
}

MUTATIONS = {
    # The plural rules are not in the application: "1 characters, 1 words, 1 lines".
    'no-stringsdict': None,
    # The controller asks for the old key, which no language has.
    'old-key': ('@"%d characters, %d words, %d lines"', '@"%d letters, %d words, %d lines"'),
    # The counts are formatted without the plural rules of the language.
    'plain-format': ('NSString *counts = [NSString localizedStringWithFormat:', 'NSString *counts = [NSString stringWithFormat:'),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

languages = [p.stem for p in sorted(interfaces.glob('*.lproj')) if (p / 'Localizable.strings').exists()]
assert sorted(languages) == sorted(EXPECTED), languages
failures = []

controller = source_file(root, 'TSGlyphPopoverController.m').read_text()
if args.mutation in ('old-key', 'plain-format'):
    old, new = MUTATIONS[args.mutation]
    assert controller.count(old) == 1, args.mutation
    controller = controller.replace(old, new)

# The keys the controller asks for, and how it formats them.
for key in (COUNTS, COMPLEX):
    if f'NSString localizedStringWithFormat:NSLocalizedString(@"{key}"' not in controller:
        failures.append(f'the controller does not format "{key}" with localizedStringWithFormat:')
for language in languages:
    strings = (interfaces / f'{language}.lproj/Localizable.strings').read_text(encoding='utf-8')
    for key in (COUNTS, COMPLEX):
        if not re.search(r'^\s*"' + re.escape(key) + '" = ', strings, re.M):
            failures.append(f'{language}: Localizable.strings has no "{key}"')
    for old in ('%d letters, %d words, %d lines', '<a letter consisting of %d characters>'):
        if f'"{old}"' in strings:
            failures.append(f'{language}: Localizable.strings still has "{old}"')
    # The word for characters is the status bar's.
    status = re.search(r'^"Characters" = "(.*)";', strings, re.M).group(1)
    if status.lower() not in EXPECTED[language][1].lower():
        failures.append(f'{language}: "{EXPECTED[language][1]}" does not use the status bar\'s "{status}"')

with tempfile.TemporaryDirectory(prefix='texshop-character-info-plurals-') as tmp:
    tmp = Path(tmp)
    app = tmp / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    for language in languages:
        (resources / f'{language}.lproj').mkdir(parents=True)
        for table in ('Localizable.strings', 'Localizable.stringsdict'):
            source = interfaces / f'{language}.lproj' / table
            if source.exists() and not (args.mutation == 'no-stringsdict' and table.endswith('dict')):
                shutil.copy(source, resources / f'{language}.lproj' / table)
    (app / 'Contents/Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.CharacterInfoPlurals</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>''')
    # The calls of the controller, with its keys and its way of formatting.
    counts_call = re.search(r'NSString \*counts = (\[NSString \w+:NSLocalizedString\(@"[^"]*")', controller)
    complex_call = re.search(r'name = (\[NSString \w+:NSLocalizedString\(@"<[^"]*")', controller)
    if not counts_call or not complex_call:
        failures.append('the calls of the controller are not found')
    else:
        (tmp / 'probe.m').write_text(f'''#import <Foundation/Foundation.h>
int main(int argc, char **argv) {{ @autoreleasepool {{
    int counts[2][3] = {{{{1, 1, 1}}, {{2, 1, 3}}}};
    for (int i = 0; i < 2; i++)
        printf("%s\\n", {counts_call.group(1)}, nil), counts[i][0], counts[i][1], counts[i][2]].UTF8String);
    for (int n = 2; n <= 20; n += 18)
        printf("%s\\n", {complex_call.group(1)}, nil), n].UTF8String);
}} }}
''')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(tmp / 'probe.m'), '-o', str(app / 'Contents/MacOS/probe')], check=True)
        for language in languages:
            locale = language.replace('-', '_')
            out = subprocess.run([str(app / 'Contents/MacOS/probe'), '-AppleLanguages', f'({language})', '-AppleLocale', locale],
                                 capture_output=True, text=True, timeout=60)
            shown = out.stdout.splitlines()
            if shown != EXPECTED[language]:
                failures.append(f'{language}: {shown} instead of {EXPECTED[language]}')

for failure in failures:
    print('FAIL:', failure)
if failures:
    sys.exit(1)
print(f'PASS: Character Info counts and code points in {len(languages)} languages, with singulars and plurals')
