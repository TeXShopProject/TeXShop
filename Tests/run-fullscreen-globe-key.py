#!/usr/bin/env python3
"""Enter Full Screen has Globe-F, given at launch, and Control-Command-F is Next Mark's alone.

Loads each compiled MainMenu nib (12 languages, 36 variants), lets AppKit customize it as at launch, runs the launch
step of the shortcuts (TSGiveFullScreenGlobeKey, then the store reads the default keys) and checks that Enter Full
Screen has f with the Globe (fn) modifier only, that Next Mark has Control-Command-F, and that no other item of the
whole menu, hidden ones included, answers Control-Command-F. Also checks the call at launch in TSAppDelegate.
--mutations: forgetting the launch step, setting the Globe key before the action, and Control-Command-F left in a nib.
"""
from pathlib import Path
import subprocess, sys, tempfile
from shortcut_sources import NAMES, companion_sources
from source_tree import include_args, source_file

r = Path(__file__).resolve().parents[1]
STEP = '    TSGiveFullScreenGlobeKey(menu);\n    self.store = [[TSShortcutStore alloc]'
ORDER = ('        item.keyEquivalentModifierMask = NSEventModifierFlagFunction;\n        item.keyEquivalent = @"f";\n')


def delegate_failures(text):
    """The launch call in TSAppDelegate: after the KeyEquivalents.plist of earlier versions, in applicationWillFinishLaunching."""
    failures = []
    start = text.index('- (void)applicationWillFinishLaunching:')
    body = text[start:text.index('\n}\n', start)]
    legacy, call = body.find('[self finishMenuKeyEquivalentsConfigure];'), body.find('TSGiveFullScreenGlobeKey(NSApp.mainMenu);')
    if call < 0 or legacy < 0 or call < legacy:
        failures.append('TSAppDelegate gives Enter Full Screen Globe-F after the KeyEquivalents.plist of earlier versions')
    legacy_source = (r / 'Sources/Shortcuts/TSLegacyMenuKeyEquivalents.inc').read_text()
    if 'if (item.action == @selector(toggleFullScreen:)) return;' not in legacy_source:
        failures.append('a KeyEquivalents.plist of earlier versions leaves Enter Full Screen alone')
    return failures


def main():
    delegate = (r / 'Sources/App/TSAppDelegate.m').read_text(encoding='latin-1')
    failures = delegate_failures(delegate)
    assert not failures, failures
    print('PASS: TSAppDelegate gives Enter Full Screen Globe-F after the KeyEquivalents.plist of earlier versions, which leaves it alone')
    nibs = sorted((r / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(nibs) == 36, len(nibs)
    with tempfile.TemporaryDirectory(prefix='texshop-fullscreen-globe-') as directory:
        d = Path(directory)
        source = source_file(r, 'TSKeyboardShortcuts.m')

        def build(path):
            command = ['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-Wno-nullability-completeness',
                       '-mmacosx-version-min=14.6', *include_args(r), '-I', str(r / 'Sources/Shortcuts'), '-I', str(r / 'Tests'),
                       '-framework', 'Cocoa', '-framework', 'Carbon', str(r / 'Tests/FullScreenGlobeKey.m'),
                       *[str(path) if n == 'TSKeyboardShortcuts.m' else str(source_file(r, n)) for n in NAMES],
                       *companion_sources(r), '-o', str(d / 'probe')]
            subprocess.run(command, check=True)

        def run(nib, *extra):
            return subprocess.run([str(d / 'probe'), str(nib), *extra], capture_output=True, text=True, timeout=30)

        build(source)
        for nib in nibs:
            result = run(nib)
            assert result.returncode == 0, (str(nib), result.stdout, result.stderr)
            print(result.stdout.strip(), flush=True)
        print(f'PASS: {len(nibs)} compiled menus: Enter Full Screen has Globe-F only and Control-Command-F is Next Mark alone')
        if '--mutations' not in sys.argv:
            return
        base = r / 'Resources/Interfaces/Base.lproj/MainMenu.nib/keyedobjects.nib'
        text = source.read_text()
        cases = [('forget the launch step', STEP, '    self.store = [[TSShortcutStore alloc]',
                  'Enter Full Screen has f with the Globe key only'),
                 ('set the Globe key before the action', ORDER,
                  '        SEL action = item.action; item.action = NULL;\n' + ORDER + '        item.action = action;\n',
                  'Enter Full Screen has f with the Globe key only')]
        for name, old, new, expected in cases:
            assert text.count(old) == 1, name
            mutated = d / 'TSKeyboardShortcuts.m'
            mutated.write_text(text.replace(old, new))
            build(mutated)
            result = run(base)
            assert result.returncode and f'FAIL: {expected}' in result.stderr, (name, result.stdout, result.stderr)
            print('DETECTED', name, result.stderr.strip(), flush=True)
        build(source)
        # Control-Command-F left in a nib: ibtool drops the key, which Next Mark has, and keeps the modifiers; where no
        # other item had the key, AppKit would move it to a hidden copy at launch (--runtime-only gives the item that key).
        designable = (r / 'Resources/Interfaces/Base.lproj/MainMenu.nib/designable.nib').read_text(encoding='utf-8')
        item = '<menuItem title="Enter Full Screen" id="1181" identifier="TSShortcut.toggleFullScreen:.0">'
        assert designable.count(item) == 1
        nib_dir = d / 'Left.nib'
        (d / 'left.xib').write_text(designable.replace(item, item.replace(' id=', ' keyEquivalent="f" id=') +
                                                       '<modifierMask key="keyEquivalentModifierMask" control="YES" command="YES"/>'), encoding='utf-8')
        subprocess.run(['xcrun', 'ibtool', '--compile', str(nib_dir), str(d / 'left.xib')], check=True, capture_output=True)
        compiled = nib_dir / 'keyedobjects.nib' if nib_dir.is_dir() else nib_dir
        for extra, expected in [((), 'Enter Full Screen has no key or modifiers in the nib'),
                                (('--runtime-only',), 'AppKit adds no hidden Control-Command-F copy of Enter Full Screen')]:
            result = run(compiled, *extra)
            assert result.returncode and f'FAIL: {expected}' in result.stderr, (extra, result.stdout, result.stderr)
            print('DETECTED Control-Command-F left in a nib', *extra, result.stderr.strip(), flush=True)
        failures = delegate_failures(delegate.replace('    TSGiveFullScreenGlobeKey(NSApp.mainMenu);\n', ''))
        assert failures, 'the launch call left out of TSAppDelegate is not found'
        print('DETECTED forget the launch call in TSAppDelegate:', failures[0])
        result = run(base)
        assert result.returncode == 0, result.stderr
        print('NORMAL CONTROL', result.stdout.strip())


if __name__ == '__main__':
    main()
