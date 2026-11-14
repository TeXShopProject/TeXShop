#!/usr/bin/env python3
"""The windows, panels and accessory views TeXShop builds in code show their
whole text in every language, inside their windows and apart, with room for
focus rings and, for an input field that wraps, the same margin above and below
(CodeBuiltLayout.m, with the checks of LayoutChecks.inc that run-interface-label-fit.py
applies to the nibs).

The Experiment console is the production controller; the Change All view and
the engine path, engine profile, shortcut conflicts and learned words alerts are the production
functions, copied from their source between their BEGIN and END lines. Nothing
is shown on screen.

  --images DIR   also write each window and view as drawn, as PNG files
  --focus-rings  draw the focus ring of each input field in those images"""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile
from source_tree import include_args
from experiment_console_source import prefix, controller_source, advanced_find_sources
root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
parser = argparse.ArgumentParser()
parser.add_argument('--images')
parser.add_argument('--focus-rings', action='store_true')
args = parser.parse_args()


def between(path, begin, end):
    text = (root / path).read_text()
    return text[text.index(begin):text.index(end)]


spell = between('Sources/Editor/TSSpellSupport.m', '// BEGIN change all accessory', '// END change all accessory')
engine = between('Sources/Settings/TSPreferences.m', '// BEGIN engine path alert', '// END engine path alert')
conflicts = between('Sources/Macros/TSMacroEditor.m', '// BEGIN shortcut conflicts alert', '// END shortcut conflicts alert')
learned = between('Sources/Editor/TSSpellSupport.m', '// BEGIN learned words alert', '// END learned words alert')
assert 'TSChangeAllAccessory(self, &sReplacementField, &sReplacementStatus)' in (root / 'Sources/Editor/TSSpellSupport.m').read_text(), \
    'The application builds the Change All view as the check does'
assert 'return TSRunShortcutAlert(TSShortcutConflictsAlert(details));' in (root / 'Sources/Macros/TSMacroEditor.m').read_text()
assert 'alert = TSLearnedWordsAlert(language, list, &table);' in (root / 'Sources/Editor/TSSpellSupport.m').read_text()
assert 'NSAlert *alert = TSEnginePathAlert(found, matrices);' in (root / 'Sources/Settings/TSPreferences.m').read_text(), \
    'The application builds the engine path alert as the check does'
assert 'NSAlert *alert = TSEngineProfileAlert(profile, latexmk);' in (root / 'Sources/Settings/TSPreferences.m').read_text(), \
    'The application builds the engine profile sheet as the check does'
size_window = '\n'.join(line for line in (root / 'Sources/App/globals.h').read_text().splitlines() if re.match(r'#define\s+SIZE_WINDOW_', line))
assert 'SIZE_WINDOW_WIDTH' in size_window and 'SIZE_WINDOW_DRAW_X' in size_window

entries = []
for lproj in sorted(interfaces.glob('*.lproj')):
    if not (lproj / 'Localizable.strings').exists() and lproj.name != 'Base.lproj':
        continue
    strings = lproj / 'Localizable.strings' if lproj.name != 'Base.lproj' else interfaces / 'en.lproj/Localizable.strings'
    if lproj.name == 'en.lproj':
        continue  # Base uses the English strings
    entries.append(f'{lproj.stem}|{strings}')

with tempfile.TemporaryDirectory(prefix='texshop-code-built-layout-') as tmp:
    tmp = Path(tmp)
    (tmp / 'SpellAccessory.inc').write_text(spell)
    (tmp / 'EnginePathAlert.inc').write_text('#import "TSPreferenceProfile.h"\n#import "TSEnginePathDiscovery.h"\n' + engine)
    (tmp / 'SizeWindow.inc').write_text(size_window + '\n')
    (tmp / 'ShortcutConflictsAlert.inc').write_text(conflicts)
    (tmp / 'LearnedWordsAlert.inc').write_text(learned)
    program = tmp / 'CodeBuiltLayout.m'
    program.write_text(prefix(root) + controller_source(root) + (root / 'Tests/CodeBuiltLayout.m').read_text())
    binary = tmp / 'CodeBuiltLayout'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'PDFKit', '-framework', 'WebKit', '-framework', 'Quartz',
                    '-I', str(tmp), '-I', str(root / 'Tests'), *include_args(root), str(program),
                    str(root / 'Sources/Typesetting/TSExperimentJob.m'), str(root / 'Sources/Typesetting/TSConsoleOutput.m'),
                    str(root / 'Sources/Settings/TSPreferenceProfile.m'), str(root / 'Sources/App/globals.m'), str(root / 'Sources/Typesetting/TSEnginePathDiscovery.m'),
                    *advanced_find_sources(root, tmp), '-o', str(binary)], check=True)
    extra = []
    if args.images:
        Path(args.images).mkdir(parents=True, exist_ok=True)
        extra = ['--images', str(Path(args.images).resolve())] + (['--focus-rings'] if args.focus_rings else [])
    result = subprocess.run([str(binary), *extra, *entries], capture_output=True, text=True, timeout=1800)
    print(result.stdout, end='')
    if result.returncode and not result.stdout.strip():
        print(result.stderr[-3000:], file=sys.stderr)
    assert len(entries) == 12 or result.returncode, entries
    sys.exit(result.returncode)
