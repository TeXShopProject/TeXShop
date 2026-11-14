#!/usr/bin/env python3
"""The sample sets of multiple replacement (Resources/MultipleReplaceSamples), built with Tests/MultipleReplaceSamples.m.

- The samples are made from Edit > Character Type Conversion's ajmacros tables (NSString-CharacterConversion), not
  written by hand: the files must be what the generator makes now, byte for byte. --write makes them again.
- Equivalence: applied by the multiple replacement engine, each sample does exactly what its menu item does
  (line ends of every kind with %, the end of the text, the short forms such as \\ajMaru1, decomposed text), also with
  the yen sign, OgreKit's replacement syntax and the replacement not unescaped.
- Installing, in all 12 languages: the samples are written translated, only into a folder of sets that does not exist
  yet, and a changed or removed sample is never written again.
- Every name and note of the samples is in MultipleReplaceSamples.strings of every language, and nothing else is.
- The project bundles the folder and the tables, and the menu's library points at the folder.
--mutations breaks one thing at a time and checks that the test notices."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
SAMPLES = root / 'Resources/MultipleReplaceSamples'
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
TO_MACROS = 'Unicode Characters → ajmacros'
TO_CHARACTERS = 'ajmacros → Unicode Characters'
UTILITIES = ['NSString-CharacterConversion.m', 'NSString-Extras.m', 'NSMutableString-Extras.m']


def build(tmp, find, utilities):
    """A small application bundle, so that the strings tables are found as in TeXShop.app."""
    app = tmp / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    for language in LANGUAGES:
        (resources / f'{language}.lproj').mkdir(parents=True)
        for table in ['MultipleReplaceSamples.strings', 'AdvancedFind.strings', 'AdvancedFindEngine.strings']:
            shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.MultipleReplaceSamples</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    probe = app / 'Contents/MacOS/probe'
    engine = sorted(find.glob('TSRegex*.m')) + [find / 'TSMultipleReplaceLibrary.m']
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-Wno-deprecated-declarations', '-I', str(find), '-I', str(utilities), *include_args(root), '-I', str(root / 'Tests'),
                    '-framework', 'Cocoa', '-framework', 'CoreText', str(root / 'Tests/MultipleReplaceSamples.m'),
                    *map(str, engine), *(str(utilities / name) for name in UTILITIES), '-o', str(probe)], check=True)
    return probe


def run(probe, mode, directory, language='en', stop_at_failure=False):
    environment = dict(os.environ, TS_SAMPLES_STOP_AT_FAILURE='1') if stop_at_failure else None
    return subprocess.run([str(probe), mode, str(directory), '-AppleLanguages', f'({language})'], capture_output=True, text=True, timeout=1200, env=environment)


def copy_sources(tmp):
    find, utilities = tmp / 'find', tmp / 'utilities'
    find.mkdir()
    utilities.mkdir()
    for path in (root / 'Sources/Find').glob('*.[mh]'):
        shutil.copy(path, find / path.name)
    for name in UTILITIES + ['NSString-CharacterConversion.h', 'NSString-Extras.h', 'NSMutableString-Extras.h']:
        shutil.copy(root / 'Sources/Utilities' / name, utilities / name)
    return find, utilities


def sample_files(directory):
    return sorted(p.name for p in directory.glob('*.json'))


def generated_matches(probe, tmp, samples):
    """The samples are what the generator makes from the conversions now."""
    out = tmp / 'generated'
    if out.exists():
        shutil.rmtree(out)
    result = run(probe, 'generate', out)
    if result.returncode:
        print(result.stdout + result.stderr, end='')
        return False
    if sample_files(out) != sample_files(samples):
        print(f'FAIL: generated {sample_files(out)}, bundled {sample_files(samples)}')
        return False
    different = [name for name in sample_files(out) if (out / name).read_bytes() != (samples / name).read_bytes()]
    if different:
        print(f'FAIL: the bundled samples differ from what the conversions make: {different} (Tests/run-multiple-replace-samples.py --write)')
        return False
    return True


def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def check_tables(samples, interfaces):
    """Every name and note of the samples is translated in every language, and the table has nothing else."""
    keys = {TO_MACROS, TO_CHARACTERS}
    for name in sample_files(samples):
        keys |= {rule.get('description') for rule in json.loads((samples / name).read_text())['replacements']}
    problems = []
    if None in keys:
        problems.append('a rule without a note')
    for language in LANGUAGES:
        table = strings(interfaces / f'{language}.lproj/MultipleReplaceSamples.strings')
        if set(table) != keys:
            problems.append(f'{language}: missing {sorted(keys - set(table))[:3]}, extra {sorted(set(table) - keys)[:3]}')
        elif language == 'en' and any(table[k] != k for k in table):
            problems.append('en: a value differs from its key')
        elif language != 'en' and any(table[k] == k for k in table):
            problems.append(f'{language}: untranslated {[k for k in table if table[k] == k][:3]}')
    for problem in problems:
        print(f'FAIL: MultipleReplaceSamples.strings {problem}')
    return not problems


def check_bundling(project, menu):
    """The project copies the folder and the tables into the application; the menu's library uses the folder."""
    ok = True
    folder = re.search(r'(\w{24}) /\* MultipleReplaceSamples \*/ = \{isa = PBXFileReference; lastKnownFileType = folder; path = Resources/MultipleReplaceSamples;', project)
    table = re.search(r'(\w{24}) /\* MultipleReplaceSamples\.strings \*/ = \{\s*isa = PBXVariantGroup;', project)
    phase = re.search(r'isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);', project, re.S)
    for ref, what in [(folder, 'the folder'), (table, 'the strings tables')]:
        build = ref and re.search(rf'(\w{{24}}) /\* [^*]* in Resources \*/ = \{{isa = PBXBuildFile; fileRef = {ref.group(1)} ', project)
        if not (build and phase and build.group(1) in phase.group(1)):
            print(f'FAIL: the project does not copy {what} of the samples into the application')
            ok = False
    languages = set(re.findall(r'path = ([\w-]+)\.lproj/MultipleReplaceSamples\.strings;', project))
    if languages != set(LANGUAGES):
        print(f'FAIL: the project has MultipleReplaceSamples.strings in {sorted(languages)}')
        ok = False
    if 'library.samplesDirectory = [NSBundle.mainBundle URLForResource:@"MultipleReplaceSamples" withExtension:nil];' not in menu:
        print('FAIL: the menu\'s library does not use the bundled samples')
        ok = False
    return ok


def check_all(probe, tmp, samples, interfaces, project, menu, quiet=False):
    """Every check, the slow equivalence last; stops at the first that fails. A list of what failed."""
    if not generated_matches(probe, tmp, samples):
        return ['generated']
    for language in LANGUAGES:
        result = run(probe, 'install', samples, language)
        if not quiet or result.returncode:
            print(result.stdout + result.stderr, end='')
        if result.returncode:
            return [f'install {language}']
    if not check_tables(samples, interfaces):
        return ['tables']
    if not check_bundling(project, menu):
        return ['bundling']
    result = run(probe, 'equivalence', samples, stop_at_failure=quiet)
    if not quiet or result.returncode:
        print(result.stdout + result.stderr, end='')
    return ['equivalence'] if result.returncode else []


def mutate_json(samples, tmp, name, change):
    """A copy of the samples with one file changed."""
    copy = tmp / 'mutated-samples'
    if copy.exists():
        shutil.rmtree(copy)
    shutil.copytree(samples, copy)
    path = copy / f'{name}.json'
    data = json.loads(path.read_text())
    change(data['replacements'])
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    return copy


def remove_entry(rules, index):
    """Removes the index-th entry of the table: its plain rule and the end-of-line rule before it."""
    plain = [i for i, r in enumerate(rules) if not r.get('usesRegularExpression')][index]
    del rules[plain]
    if plain > 0 and rules[plain - 1].get('usesRegularExpression'):
        del rules[plain - 1]


def swap_first_pair(rules):
    rules[0], rules[1] = rules[1], rules[0]


def edit_regex(rules, old, new):
    for rule in rules:
        if rule.get('usesRegularExpression'):
            rule['findString'] = rule['findString'].replace(old, new)


def single_backslash(rules):
    for rule in rules:
        if rule.get('usesRegularExpression'):
            rule['replacementString'] = rule['replacementString'].replace('\\\\', '\\')


def drop_short_form(rules):
    rules[:] = [r for r in rules if r['findString'] != '\\ajMaru1']


JSON_MUTATIONS = {
    'an entry is missing (→ ajmacros)': (TO_MACROS, lambda rules: remove_entry(rules, 300), 'equivalence'),
    'an entry is missing (→ Unicode)': (TO_CHARACTERS, lambda rules: remove_entry(rules, 500), 'equivalence'),
    'the end-of-line rules are missing': (TO_MACROS, lambda rules: rules.__setitem__(slice(None), [r for r in rules if not r.get('usesRegularExpression')]), 'equivalence'),
    'the rules are in another order': (TO_MACROS, swap_first_pair, 'equivalence'),
    'the end of the text adds %': (TO_MACROS, lambda rules: edit_regex(rules, '(?=\\r|\\n)', '(?=\\r|\\n|$)'), 'equivalence'),
    'the end-of-line replacement has single backslashes': (TO_MACROS, single_backslash, 'equivalence'),
    'a short form is missing': (TO_CHARACTERS, drop_short_form, 'equivalence'),
    'a note is not in the tables': (TO_MACROS, lambda rules: rules[5].__setitem__('description', 'Circled digits'), 'tables'),
}

# Leaving out the check that the folder exists is not a mutation: the move that follows never replaces a folder,
# so nothing changes. Replacing it is 'samples are written over the user's sets'.
SOURCE_MUTATIONS = {
    'the conversion table changes': ('utilities', 'NSString-CharacterConversion.m',
        '[str replaceAllOccurrencesOfString:@"㍾" withString:@"\\\\ajLig{明治}" addingPercentForEndOfLine:YES];',
        '[str replaceAllOccurrencesOfString:@"㍾" withString:@"\\\\ajLig{明冶}" addingPercentForEndOfLine:YES];'),
    'the menu gets a new entry': ('utilities', 'NSString-CharacterConversion.m',
        '    [str replaceAllOccurrencesOfString:@"㍽" withString:@"\\\\ajLig{大正}" addingPercentForEndOfLine:YES];\n',
        '    [str replaceAllOccurrencesOfString:@"㍽" withString:@"\\\\ajLig{大正}" addingPercentForEndOfLine:YES];\n'
        '    [str replaceAllOccurrencesOfString:@"㋿" withString:@"\\\\ajLig{X}" addingPercentForEndOfLine:NO];\n'),
    'samples are written over the user\'s sets': ('find', 'TSMultipleReplaceLibrary.m',
        '    if (!samples || [manager fileExistsAtPath:self.directory.path ?: @""])\n        return NO;\n',
        '    if (!samples)\n        return NO;\n    [manager removeItemAtURL:self.directory error:NULL];\n'),
    'the staging folder is left': ('find', 'TSMultipleReplaceLibrary.m',
        '    if (!written)\n        [manager removeItemAtURL:staging error:NULL];\n', ''),
    'the names are not translated': ('find', 'TSMultipleReplaceLibrary.m',
        'localizedStringForKey:english value:english table:TSMultipleReplaceSamplesTable]', 'localizedStringForKey:english value:english table:@"Missing"]'),
    'the notes are not translated': ('find', 'TSMultipleReplaceLibrary.m',
        '        NSString *note = rule.note ? [self.samplesBundle localizedStringForKey:(NSString *_Nonnull)rule.note value:rule.note table:TSMultipleReplaceSamplesTable] : nil;',
        '        NSString *note = rule.note;'),
    'the options are not kept': ('find', 'TSMultipleReplaceLibrary.m',
        'return [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:sample.textualOptions',
        'return [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:TSRegexMultipleReplace.defaultTextualOptions'),
    'the first listing does not write them': ('find', 'TSMultipleReplaceLibrary.m',
        '        self.samplesConsidered = YES;\n        [self installSamples];\n', '        self.samplesConsidered = YES;\n'),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true', help='make the bundled samples again from the conversions')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    interfaces = root / 'Resources/Interfaces'
    project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text()
    menu = (root / 'Sources/Find/TSMultipleReplaceMenu.m').read_text()
    with tempfile.TemporaryDirectory(prefix='texshop-multiple-replace-samples-') as tmp:
        tmp = Path(tmp)
        probe = build(tmp, root / 'Sources/Find', root / 'Sources/Utilities')
        if args.write:
            if SAMPLES.exists():
                shutil.rmtree(SAMPLES)
            result = run(probe, 'generate', SAMPLES)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit('FAIL: making the samples')
        failed = check_all(probe, tmp, SAMPLES, interfaces, project, menu)
        if failed:
            sys.exit(f'FAIL: {", ".join(failed)}')
        if args.mutations:
            for name, (file, change, expected) in JSON_MUTATIONS.items():
                mutated = mutate_json(SAMPLES, tmp, file, change)
                if expected == 'tables':
                    caught = not check_tables(mutated, interfaces)
                else:
                    caught = run(probe, expected, mutated, stop_at_failure=True).returncode != 0
                if not caught:
                    sys.exit(f'FAIL: mutation {name!r} was not detected')
                print(f'PASS: detected mutation {name!r}')
            missing = tmp / 'missing-tables'
            shutil.copytree(interfaces, missing, ignore=shutil.ignore_patterns('*.nib', 'TeXShopHelp', '*.pdf', '*.rtf'))
            table = missing / 'fr.lproj/MultipleReplaceSamples.strings'
            table.write_text(table.read_text().replace('"Roman numerals" = "Chiffres romains";', '"Roman numerals" = "Roman numerals";'))
            if check_tables(SAMPLES, missing):
                sys.exit('FAIL: mutation \'an untranslated note\' was not detected')
            print('PASS: detected mutation \'an untranslated note\'')
            for name, mutated_project, mutated_menu in [
                    ('the folder is not copied', re.sub(r'\n\t+\w{24} /\* MultipleReplaceSamples in Resources \*/,', '', project, count=1), menu),
                    ('a language is missing', project.replace('path = ro.lproj/MultipleReplaceSamples.strings;', 'path = ro.lproj/Missing.strings;'), menu),
                    ('the menu has no samples', project, menu.replace('library.samplesDirectory = ', '(void)'))]:
                if mutated_project == project and mutated_menu == menu:
                    sys.exit(f'FAIL: mutation {name!r} does not apply')
                if check_bundling(mutated_project, mutated_menu):
                    sys.exit(f'FAIL: mutation {name!r} was not detected')
                print(f'PASS: detected mutation {name!r}')
            for name, (where, file, old, new) in SOURCE_MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-multiple-replace-samples-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    find, utilities = copy_sources(mtmp)
                    path = (find if where == 'find' else utilities) / file
                    text = path.read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    path.write_text(text.replace(old, new))
                    mprobe = build(mtmp, find, utilities)
                    if not check_all(mprobe, mtmp, SAMPLES, interfaces, project, menu, quiet=True):
                        sys.exit(f'FAIL: mutation {name!r} was not detected')
                    print(f'PASS: detected mutation {name!r}')
    print('PASS: multiple replacement samples')


if __name__ == '__main__':
    main()
