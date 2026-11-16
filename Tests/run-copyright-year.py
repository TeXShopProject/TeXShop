#!/usr/bin/env python3
"""The Update About copyright year phase: the About text of the built application ends with the year of the build.

Richard Koch handed TeXShop over in 2026, so "© 2001–2026 Richard Koch" stays; the current developer's
"© 2026 Yusuke Terada" becomes "© 2026–<year> Yusuke Terada" from 2027 on. The script runs on a copy of a
bundle made from Resources/Info.plist and the InfoPlist.strings of every language, in a temporary folder;
no window is shown. With --mutation NAME the harness runs against a mutated script and must fail;
--mutations runs them all."""
from pathlib import Path
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
SCRIPT = root / 'Scripts/update-copyright-year.swift'
MUTATIONS = {
    # Richard Koch's years follow the year of the build too.
    'koch-follows': ('let firstYear = 2026\n',
                     'let firstYear = 2026\nlet kochRange = try NSRegularExpression(pattern: #"(?<=2001)[-–][0-9]{4}"#)\n'),
    # The current developer keeps "2026" in later years.
    'no-ending': ('let ending = year > firstYear ? "–\\(year)" : ""', 'let ending = ""'),
    # A second build in a later year appends another year instead of replacing the first ending.
    'appends': ('(?:[-–][0-9]{4})?(?= Yusuke Terada)', '(?= Yusuke Terada)'),
    # The strings of the languages are not updated.
    'info-plist-only': ('where directory.pathExtension == "lproj" {', 'where directory.pathExtension == "never" {'),
}
# koch-follows also needs the replacement itself.
KOCH_APPLY = ('        let replacement = currentDeveloper',
              '        let replacement0 = kochRange.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "–\\(year)")\n'
              '        let replacement = currentDeveloper')
KOCH_APPLY_2 = ('.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ending)',
                '.stringByReplacingMatches(in: replacement0, range: NSRange(replacement0.startIndex..., in: replacement0), withTemplate: ending)')

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def copyrights(bundle):
    """{file: {key: text}} for the two About keys of Info.plist and every InfoPlist.strings."""
    found = {}
    files = [bundle / 'Contents/Info.plist'] + sorted((bundle / 'Contents/Resources').glob('*.lproj/InfoPlist.strings'))
    for file in files:
        data = file.read_bytes()
        try:
            values = plistlib.loads(data)
        except Exception:
            values = parse_strings(data)
        found[file.relative_to(bundle).as_posix()] = {k: values[k] for k in ('CFBundleGetInfoString', 'NSHumanReadableCopyright') if k in values}
    return found


def parse_strings(data):
    """Read an old-style text .strings file with plutil, which knows its escapes."""
    with tempfile.NamedTemporaryFile(suffix='.strings') as f:
        f.write(data)
        f.flush()
        return plistlib.loads(subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', f.name]))


def make_bundle(folder):
    bundle = folder / 'TeXShop.app'
    (bundle / 'Contents/Resources').mkdir(parents=True)
    shutil.copy(root / 'Resources/Info.plist', bundle / 'Contents/Info.plist')
    for strings in sorted((root / 'Resources/Interfaces').glob('*.lproj/InfoPlist.strings')):
        target = bundle / 'Contents/Resources' / strings.parent.name
        target.mkdir()
        # Xcode writes the built strings files in binary; keep one language as text to cover both.
        if strings.parent.name == 'fr.lproj':
            shutil.copy(strings, target / 'InfoPlist.strings')
        else:
            subprocess.check_call(['plutil', '-convert', 'binary1', '-o', str(target / 'InfoPlist.strings'), str(strings)])
    return bundle


def run_script(script, bundle, year):
    environment = dict(os.environ, TEXSHOP_COPYRIGHT_YEAR=str(year))
    result = subprocess.run(['/usr/bin/xcrun', 'swift', str(script), str(bundle)], env=environment,
                            capture_output=True, text=True)
    check(result.returncode == 0, f'the script runs for {year}: {result.stderr.strip()}')
    return result


def expected(text, year):
    """Only the current developer's years change."""
    ending = f'–{year}' if year > 2026 else ''
    return re.sub(r'(?<=2026)(?:[-–][0-9]{4})?(?= Yusuke Terada)', ending, text)


def check_project():
    project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    phases = re.search(r'buildPhases = \(\n(.*?)\);', project[project.index('/* TeXShop */ = {\n\t\t\tisa = PBXNativeTarget;'):], re.S)[1]
    names = re.findall(r'/\* (.*?) \*/', phases)
    check('Update About copyright year' in names, f'the target runs Update About copyright year: {names}')
    if 'Update About copyright year' in names:
        check(names.index('Update About copyright year') < names.index('Set Build Number') == len(names) - 1,
              f'Update About copyright year runs before Set Build Number, which stays last: {names}')
    start = project.index('/* Update About copyright year */ = {')
    phase = project[start:project.index('\n\t\t};', start)]
    check('alwaysOutOfDate = 1;' in phase, 'the phase runs on every build')
    check('Scripts/update-copyright-year.swift' in phase and '$TARGET_BUILD_DIR/$WRAPPER_NAME' in phase,
          'the phase runs the script on the built bundle')
    check('BuildCopyrightYear.txt' in phase, 'the phase declares its output, so the bundle is signed again')
    for strings in (root / 'Resources/Interfaces').glob('*.lproj/InfoPlist.strings'):
        check(f'{strings.parent.name}/InfoPlist.strings' in phase, f'the phase lists {strings.parent.name} as an input')


def run(mutation=None):
    failures.clear()
    with tempfile.TemporaryDirectory(prefix='texshop-copyright-year-') as name:
        tmp = Path(name)
        script = tmp / 'update-copyright-year.swift'
        text = SCRIPT.read_text(encoding='utf-8')
        if mutation:
            old, new = MUTATIONS[mutation]
            assert text.count(old) == 1, 'mutation target must be unique: ' + mutation
            text = text.replace(old, new)
            if mutation == 'koch-follows':
                for old, new in (KOCH_APPLY, KOCH_APPLY_2):
                    assert text.count(old) == 1, old
                    text = text.replace(old, new)
        script.write_text(text, encoding='utf-8')
        bundle = make_bundle(tmp)
        source = copyrights(bundle)
        check(sum(len(v) for v in source.values()) >= 10, f'the About keys are found: {source}')
        check(all('2001–2026 Richard Koch' in t for v in source.values() for t in v.values() if 'Richard Koch' in t),
              'the sources name Richard Koch with 2001–2026')
        previous = source
        for year in (2026, 2027, 2031):
            run_script(script, bundle, year)
            now = copyrights(bundle)
            for file, values in source.items():
                for key, text in values.items():
                    got = now.get(file, {}).get(key)
                    check(got == expected(text, year), f'{year} {file} {key}: {got!r}')
                    if got and 'Richard Koch' in got:
                        check('2001–2026 Richard Koch' in got, f'{year} {file} {key}: Richard Koch stays 2001–2026')
            check((bundle / 'Contents/Resources/BuildCopyrightYear.txt').read_text() == f'{year}\n',
                  f'{year}: BuildCopyrightYear.txt names the year')
            previous = now
        # The years of 2031 are those of a bundle built in 2031, not "2026–2027–2031".
        check(any('2026–2031 Yusuke Terada' in t for v in previous.values() for t in v.values()), 'a later build replaces the ending year')
    check_project()
    return list(failures)


if __name__ == '__main__':
    if '--mutations' in sys.argv:
        names = list(MUTATIONS)
    elif '--mutation' in sys.argv:
        names = [sys.argv[sys.argv.index('--mutation') + 1]]
    else:
        names = []
    if not names:
        result = run()
        if result:
            print('FAIL:\n' + '\n'.join(result))
            sys.exit(1)
        print('PASS: the About copyright of the built application runs to the year of the build for the current '
              'developer and stays 2001–2026 for Richard Koch, in Info.plist and every language')
        sys.exit(0)
    missed = [m for m in names if not run(m)]
    for m in names:
        if m not in missed:
            print(f'DETECTED {m}')
    if missed:
        print('FAIL: mutations not detected: ' + ', '.join(missed))
        sys.exit(1)
    print(f'PASS: detected {len(names)} mutations')
