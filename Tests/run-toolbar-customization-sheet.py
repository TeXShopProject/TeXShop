#!/usr/bin/env python3
"""The customization sheet of a document window's toolbar shows the default set at its height (TSToolbar.m).

On macOS 26, the sheet of a window with the expanded (or preference) style draws the default set in a
picture a few points shorter than its box, and stretches it to the box while the default set is pressed:
the default set grows upwards and shows twice (#48). TSToolbar gives such a window the unified style while
the sheet is made, and then the window's own style and frame again. ToolbarCustomizationSheet.m runs the
production TSToolbar in windows that are never shown, with NSToolbar's own sheet replaced by one that only
notes the window's style and frame, for each version of macOS given to it. Each rule is then broken in turn
in the production source, and the test must notice.

A window that is never shown comes back to its frame by itself when its style is given back; a shown
window stays taller unless TSToolbar puts its frame back, which only a shown window can tell (checked in
a macOS 26 VM, TeXShop-audit).

macOS 14, 15 and 27 draw the picture at the height of its box; after a major update of macOS, check
whether this is still needed (TeXShop-audit Future Tasks, "new macOS")."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]
TOOLBAR = source_file(R, 'TSToolbar.m')
CONTROLLER = source_file(R, 'TSToolbarController.m')
VERSIONS = ['14', '15', '26', '27']

MUTATIONS = {
    'every version of macOS': ('    return majorVersion == 26 && (', '    return ('),
    'preference style left out': ('(style == NSWindowToolbarStyleExpanded || style == NSWindowToolbarStylePreference)', 'style == NSWindowToolbarStyleExpanded'),
    'sheet made in the window\'s style': ('    window.toolbarStyle = NSWindowToolbarStyleUnified;\n    [super runCustomizationPalette:sender];\n',
                                          '    [super runCustomizationPalette:sender];\n'),
    'style not given back': ('    [super runCustomizationPalette:sender];\n    window.toolbarStyle = style;\n', '    [super runCustomizationPalette:sender];\n'),
    'frame put back in between': ('    window.toolbarStyle = NSWindowToolbarStyleUnified;\n    [super runCustomizationPalette:sender];\n',
                                  '    window.toolbarStyle = NSWindowToolbarStyleUnified;\n    [window setFrame:frame display:NO];\n    [super runCustomizationPalette:sender];\n'),
}


def build(tmp, source, name):
    (tmp / 'TSToolbar.m').write_text(source)
    binary = tmp / name
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'WebKit',
                    '-I', str(R / 'Tests'), *include_args(R), str(R / 'Tests/ToolbarCustomizationSheet.m'), str(tmp / 'TSToolbar.m'), '-o', str(binary)],
                   check=True, capture_output=True, text=True)
    return binary


def run_all(binary, home):
    """The output of the versions that fail, or [] when every version passes."""
    env = {'HOME': str(home), 'CFFIXED_USER_HOME': str(home), 'PATH': '/usr/bin:/bin'}
    failed, lines = [], []
    for version in VERSIONS:
        result = subprocess.run([str(binary), version], capture_output=True, text=True, timeout=120, env=env)
        if result.returncode:
            failed.append(f'macOS {version}: exit {result.returncode}\n{result.stdout}{result.stderr}'.strip())
        else:
            lines.append(result.stdout.strip())
    return failed, lines


def main():
    source = TOOLBAR.read_text()
    # Every customizable toolbar of the document windows is a TSToolbar.
    controller = CONTROLLER.read_text()
    assert controller.count('TSToolbar *toolbar = [[TSToolbar alloc] initWithIdentifier: inID];') == 1
    with tempfile.TemporaryDirectory(prefix='toolbar-sheet-') as tmp:
        tmp = Path(tmp)
        home = tmp / 'home'
        (home / 'Library').mkdir(parents=True)
        failed, lines = run_all(build(tmp, source, 'ToolbarCustomizationSheet'), home)
        if failed:
            print('\n'.join(failed))
            print('FAIL: the production toolbar')
            return 1
        print('\n'.join(lines))
        print('PASS: the sheet is made in the unified style on macOS 26 only, and the windows keep their style, frame and layout')
        missed = []
        for name, (old, new) in MUTATIONS.items():
            if source.count(old) != 1:
                print(f'FAIL: mutation "{name}" does not apply')
                return 1
            try:
                mutated = build(tmp, source.replace(old, new), 'ToolbarCustomizationSheetMutated')
            except subprocess.CalledProcessError as error:
                print(f'FAIL: mutation "{name}" does not compile: {error.stderr[-500:]}')
                return 1
            if run_all(mutated, home)[0]:
                print('DETECTED', name, flush=True)
            else:
                missed.append(name)
        if missed:
            print('FAIL: mutations not detected:', ', '.join(missed))
            return 1
        if run_all(build(tmp, source, 'ToolbarCustomizationSheet'), home)[0]:
            print('FAIL: the control fails')
            return 1
        print('NORMAL CONTROL passes again')
    return 0


if __name__ == '__main__':
    sys.exit(main())
