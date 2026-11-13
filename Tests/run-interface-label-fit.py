#!/usr/bin/env python3
"""Every window, panel and view in every localized nib shows its whole text.

Loads each compiled interface without ordering a window, applies the layout and
the text the application gives it after loading (for example the key binding
editor's guide, written in the language of the nib), and checks with
InterfaceLabelFit.m that

  * each label is as wide as its text, or, when it wraps, as tall;
  * each button title fits its cell, also with the automatic bezel that toolbar
    buttons use on macOS 26 and later; each matrix cell and each pop-up choice
    fits too;
  * nothing a control draws reaches past its window, box, tab or other
    enclosing view, so a label wider than its window is found even when its
    frame is wide enough for its text;
  * no two controls draw over each other;
  * each input field has 3 points of room for its focus ring inside the
    window and beside the controls and scroll views next to it;
  * a resizable window still does all this at its smallest size.

Both compiled variants of a nib are checked where both exist; the application
loads keyedobjects-101300.nib. Placeholder titles replaced at run time
("Button", "Item 1") are skipped. The Settings window is composed from its own
labels and is checked by run-settings-product-shell.py.

  --images DIR   also write each window as drawn, as PNG files
  --focus-rings  draw the focus ring of each input field in those images
  --only NAME    check only the interfaces whose file name contains NAME"""
from pathlib import Path
import argparse, subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
parser = argparse.ArgumentParser()
parser.add_argument('--images')
parser.add_argument('--only')
parser.add_argument('--focus-rings', action='store_true')
args = parser.parse_args()
editor_source = root / 'Sources/Panels/TSAutoCompletionListEditor.m'
macro_source = root / 'Sources/Macros/TSMacroEditor.m'
assert '[self layoutEditorWindow];' in editor_source.read_text(), 'The application lays out the key binding editor as the check does'
assert '[self installShortcutStatus];\n        [self installListControls];\n        [self installPlaceholderNote];\n        [self layoutDialogButtons];' in macro_source.read_text(), \
    'The application lays out the macro editor as the check does'

def strings_for(lproj):
    own = lproj / 'Localizable.strings'
    return own if own.exists() else interfaces / 'en.lproj/Localizable.strings'

with tempfile.TemporaryDirectory(prefix='texshop-label-fit-') as tmp:
    tmp = Path(tmp)
    editor = editor_source.read_text()
    (tmp / 'EditorLayout.inc').write_text(editor[editor.index('// BEGIN editor layout'):editor.index('// END editor layout')])
    macro = macro_source.read_text()
    (tmp / 'MacroEditorLayout.inc').write_text(macro[macro.index('- (void)installShortcutStatus'):macro.index('- (void)collectShortcutCandidates:')])
    entries = []
    for lproj in sorted(interfaces.glob('*.lproj')):
        strings = strings_for(lproj)
        for item in sorted(lproj.iterdir()):
            # Preferences.nib is no longer loaded and Movie.nib holds no text. Settings*.xib
            # only supply controls: the Settings window builds its own labels from
            # SettingsCategories.strings (run-settings-product-shell.py covers them).
            if item.name in ('Preferences.nib', 'Movie.nib') or item.name.startswith('Settings'):
                continue
            if args.only and args.only not in item.name:
                continue
            label = f'{lproj.name}/{item.name}'
            if item.suffix == '.xib':
                out = tmp / f'{lproj.name}-{item.stem}.nib'
                subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(item)], check=True, stdout=subprocess.DEVNULL)
                compiled = sorted(out.glob('keyedobjects*.nib')) if out.is_dir() else [out]
            elif item.suffix == '.nib' and item.is_dir():
                compiled = sorted(item.glob('keyedobjects*.nib'))
            elif item.suffix == '.nib':
                compiled = [item]
            else:
                continue
            for nib in compiled:
                entries.append(f'{label}/{nib.name}|{nib}|{strings}')
    binary = tmp / 'InterfaceLabelFit'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-Wno-incomplete-implementation', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'AVKit', '-framework', 'WebKit',
                    '-I', str(tmp), '-I', str(root / 'Tests'), *include_args(root),
                    str(root / 'Tests/InterfaceLabelFit.m'), str(root / 'Sources/Windows/TSDialogButtonLayout.m'), str(root / 'Sources/Editor/TSMarkMenu.m'),
                    '-o', str(binary)], check=True)
    extra = (['--images', str(Path(args.images).resolve())] + (['--focus-rings'] if args.focus_rings else [])) if args.images else []
    if args.images:
        Path(args.images).mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(binary), *extra, *entries], capture_output=True, text=True, timeout=1800)
    print(result.stdout, end='')
    if result.returncode and not result.stdout.strip():
        print(result.stderr[-3000:], file=sys.stderr)
    sys.exit(result.returncode)
