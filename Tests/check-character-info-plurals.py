#!/usr/bin/env python3
"""Character Info's counts and the name line of a character made of several code points, in the twelve languages:
"1 character, 1 word, 1 line" and "2 characters, 1 word, 3 lines" with the singular and plural of each language
(Localizable.stringsdict, read by a small probe application as TeXShop reads it), the words of the status bar
("Characters", "Words", "Lines"), the plural forms of the language chosen also when the region is another
(Portuguese of Portugal with the region United States: "0 palavras"), the numbers of the region otherwise, and the
keys of Sources/Panels/TSGlyphPopoverController.m found in every language.
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
COUNTS = '%1$@ characters, %2$@ words, %3$@ lines'
COMPLEX = '<a character consisting of %1$@ code points>'

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
    'zh_CN': ['1个字符，1个单词，共1行', '2个字符，1个单词，共3行', '<由2个码位组成的字符>', '<由20个码位组成的字符>'],
}

# The status bar's words for characters, words and lines, which the counts use too.
STATUS = {
    'en': ('Characters', 'Words', 'Lines'), 'de': ('Zeichen', 'Wörter', 'Zeilen'), 'es': ('Caracteres', 'Palabras', 'Líneas'),
    'fr': ('Caractères', 'Mots', 'Lignes'), 'it': ('Caratteri', 'Parole', 'Righe'), 'ja': ('文字', '単語', '行'),
    'ko': ('문자', '단어', '줄'), 'nl': ('Tekens', 'Woorden', 'Regels'), 'pt': ('Caracteres', 'Palavras', 'Linhas'),
    'pt-PT': ('Caracteres', 'Palavras', 'Linhas'), 'ro': ('Caractere', 'Cuvinte', 'Linii'), 'zh_CN': ('字符', '单词', '行'),
}

MUTATIONS = {
    # The plural rules are not in the application: "1 characters, 1 words, 1 lines".
    'no-stringsdict': None,
    # The plural forms follow the region: Portuguese of Portugal in the United States says "0 palavra".
    'current-locale': ('    if (region.length && ![region isEqualToString:current.countryCode ?: @""])', '    if (NO)'),
    # The numbers are written in the locale of the plural forms, not as the status bar writes them: "12 345".
    # The code points of one character are written without the status bar's grouping: "1234".
    'plain-code-points': ('TSStatusBarFormattedNumber(codePoints.count), (int)codePoints.count', '@(codePoints.count).stringValue, (int)codePoints.count'),
    'language-numbers': ('TSStatusBarFormattedNumber(selectedCounts.selectedCharacters)', '[[NSString alloc] initWithFormat:@"%ld" locale:CountsLocale(), (long)selectedCounts.selectedCharacters]'),
    # The controller asks for the old key, which no language has.
    'old-key': ('@"%1$@ characters, %2$@ words, %3$@ lines"', '@"%d letters, %d words, %d lines"'),
    # The counts are formatted without the plural rules of the language.
    'plain-format': ('counts with stringWithFormat:', None),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

languages = [p.stem for p in sorted(interfaces.glob('*.lproj')) if (p / 'Localizable.strings').exists()]
assert sorted(languages) == sorted(EXPECTED), languages
failures = []

controller = source_file(root, 'TSGlyphPopoverController.m').read_text()
if args.mutation in ('old-key', 'current-locale', 'language-numbers', 'plain-code-points'):
    old, new = MUTATIONS[args.mutation]
    assert controller.count(old) == 1, args.mutation
    controller = controller.replace(old, new)
if args.mutation == 'plain-format':
    controller, n = re.subn(r'NSString \*counts = \[\[NSString alloc\] initWithFormat:countsFormat locale:CountsLocale\(\),',
                            r'NSString *counts = [NSString stringWithFormat:countsFormat,', controller)
    assert n == 1, args.mutation

# The keys the controller asks for, and how it formats them.
if not re.search(r'NSString \*countsFormat = NSLocalizedString\(@"' + re.escape(COUNTS) + r'", @"[^"]*"\);', controller) \
        or 'NSString *counts = [[NSString alloc] initWithFormat:countsFormat locale:CountsLocale(),' not in controller:
    failures.append(f'the controller does not format "{COUNTS}" with the locale of the counts')
if not re.search(r'NSString \*consistingFormat = NSLocalizedString\(@"' + re.escape(COMPLEX) + r'", @"[^"]*"\);', controller) \
        or 'name = [[NSString alloc] initWithFormat:consistingFormat locale:CountsLocale(), TSStatusBarFormattedNumber(codePoints.count), (int)codePoints.count];' not in controller:
    failures.append(f'the controller does not format "{COMPLEX}" with the locale of the counts')
for language in languages:
    strings = (interfaces / f'{language}.lproj/Localizable.strings').read_text(encoding='utf-8')
    for key in (COUNTS, COMPLEX):
        if not re.search(r'^\s*"' + re.escape(key) + '" = ', strings, re.M):
            failures.append(f'{language}: Localizable.strings has no "{key}"')
    for old in ('%d letters, %d words, %d lines', '%d characters, %d words, %d lines', '<a letter consisting of %d characters>', '<a character consisting of %d code points>'):
        if f'"{old}"' in strings:
            failures.append(f'{language}: Localizable.strings still has "{old}"')

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
    counts_format = re.search(r'(NSString \*countsFormat = NSLocalizedString\(@"[^"]*", @"[^"]*"\);)', controller)
    counts_call = re.search(r'NSString \*counts = (.*?),\s*\n\s*(TSStatusBarFormattedNumber\(selectedCounts\.selectedCharacters\)|[^\n]*\(long\)selectedCounts\.selectedCharacters\]), (TSStatusBarFormattedNumber\(selectedCounts\.selectedWords\)), (TSStatusBarFormattedNumber\(selectedCounts\.selectedLines\)),', controller, re.S)
    complex_format = re.search(r'(NSString \*consistingFormat = NSLocalizedString\(@"[^"]*", @"[^"]*"\);)', controller)
    complex_call = re.search(r'name = (\[\[NSString alloc\] initWithFormat:consistingFormat locale:CountsLocale\(\)), (.*?), \(int\)codePoints\.count\];', controller)
    locale_function = re.search(r'static NSLocale \*CountsLocale\(void\)\n\{.*?\n\}\n', controller, re.S)
    counting = source_file(root, 'TSStatusBarCounting.m').read_text()
    number_function = re.search(r'NSString \*TSStatusBarFormattedNumber\(NSUInteger value\)\n\{.*?\n\}\n', counting, re.S)
    if not counts_format or not complex_format or not counts_call or not complex_call or not locale_function or not number_function:
        failures.append('the calls of the controller are not found')
    else:
        characters = counts_call.group(2).replace('selectedCounts.selectedCharacters', 'c')
        (tmp / 'probe.m').write_text(f'''#import <Foundation/Foundation.h>
{number_function.group(0)}
{locale_function.group(0)}
static NSString *Counts(NSUInteger c, NSUInteger w, NSUInteger l) {{
    {counts_format.group(1)}
    return {counts_call.group(1)}, {characters}, TSStatusBarFormattedNumber(w), TSStatusBarFormattedNumber(l), (int)c, (int)w, (int)l];
}}
int main(int argc, char **argv) {{ @autoreleasepool {{
    int counts[6][3] = {{{{1, 1, 1}}, {{2, 1, 3}}, {{3, 2, 2}}, {{2, 0, 1}}, {{1234, 5, 6}}, {{12345, 0, 1}}}};
    for (int i = 0; i < 6; i++)
        printf("%s\\n", Counts(counts[i][0], counts[i][1], counts[i][2]).UTF8String);
    {complex_format.group(1)}
    int consisting[3] = {{2, 20, 1234}};
    for (int i = 0; i < 3; i++) {{
        NSUInteger count = consisting[i];
        printf("%s\\n", [{complex_call.group(1)}, {complex_call.group(2).replace('codePoints.count', 'count')}, (int)count] description].UTF8String);
    }}
}} }}
''')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(tmp / 'probe.m'), '-o', str(app / 'Contents/MacOS/probe')], check=True)
        def run(language, locale):
            out = subprocess.run([str(app / 'Contents/MacOS/probe'), '-AppleLanguages', f'({language})', '-AppleLocale', locale],
                                 capture_output=True, text=True, timeout=60)
            return out.stdout.splitlines()
        for language in languages:
            shown = run(language, {'pt': 'pt_BR', 'zh_CN': 'zh_CN'}.get(language, language.replace('-', '_') if '-' in language else f'{language}_{ {"en": "US", "ja": "JP", "ko": "KR"}.get(language, language.upper())}'))
            got = shown[:2] + shown[6:8] if len(shown) == 9 else shown
            if got != EXPECTED[language]:
                failures.append(f'{language}: {got} instead of {EXPECTED[language]}')
            # The counts use the status bar's words for characters, words and lines.
            strings = (interfaces / f'{language}.lproj/Localizable.strings').read_text(encoding='utf-8')
            plural = shown[2].lower() if len(shown) == 9 else ''
            for key, word in zip(('Characters', 'Words', 'Lines'), STATUS[language]):
                status = re.search(r'^"' + key + '" = "(.*)";', strings, re.M).group(1)
                if status != word:
                    failures.append(f'{language}: the status bar says "{status}" for {key}, not "{word}"')
                if word.lower() not in plural:
                    failures.append(f'{language}: "{plural}" does not use the status bar\'s "{word}" for {key}')
        # The language gives the plural forms, the region the numbers.
        for language, locale, line, want in (('pt-PT', 'en_US', 3, '2 caracteres, 0 palavras, 1 linha'),
                                             ('pt-PT', 'pt_PT', 3, '2 caracteres, 0 palavras, 1 linha'),
                                             ('pt', 'en_US', 3, '2 caracteres, 0 palavra, 1 linha'),
                                             ('en', 'de_DE', 4, '1.234 characters, 5 words, 6 lines'),
                                             ('en', 'en_US', 4, '1,234 characters, 5 words, 6 lines'),
                                             ('fr', 'fr_FR', 3, '2 caractères, 0 mot, 1 ligne'),
                                             ('pt-PT', 'en_US', 5, '12,345 caracteres, 0 palavras, 1 linha'),
                                             ('pt-PT', 'en_US', 4, '1,234 caracteres, 5 palavras, 6 linhas'),
                                             ('pt-PT', 'en_US', 8, '<um carácter composto por 1,234 pontos de código>'),
                                             ('ro', 'ro_RO', 7, '<un caracter format din 20 de puncte de cod>'),
                                             ('en', 'de_DE', 8, '<a character consisting of 1.234 code points>')):
            shown = run(language, locale)
            if len(shown) < 5 or shown[line] != want:
                failures.append(f'{language} with {locale}: "{shown[line] if len(shown) > line else shown}" instead of "{want}"')

for failure in failures:
    print('FAIL:', failure)
if failures:
    sys.exit(1)
print(f'PASS: Character Info counts and code points in {len(languages)} languages, with singulars and plurals')
