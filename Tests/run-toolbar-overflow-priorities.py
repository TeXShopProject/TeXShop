#!/usr/bin/env python3
"""The toolbar of the document windows (TSToolbar.m) keeps the end of the toolbar from flickering.

On macOS 27.2, AppKit moves a group of bordered items in and out of the overflow menu without end when
a window is just too narrow for the group. TSToolbar gives its items visibility priorities that let the
toolbar settle. ToolbarOverflow.m builds the production toolbar in windows that are never shown, with
the items of the nib at their sizes, styled as TSToolbarController styles them, and lays each toolbar
out 40 times at widths around the places where items go to the overflow menu: the toolbar must show
the same items every time. Each width runs in a process of its own, as AppKit carries state from one
window to the next. The checks also cover the priorities themselves and when they are given. Each rule
is then broken in turn in the production source, and the test must notice.

The widths are those where AppKit 27.2 oscillates without the priorities; after a major update of
macOS, run the test with --find-bands to see where they now lie, and check whether the priorities are
still needed (TeXShop-audit Future Tasks, "new macOS")."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse, subprocess, sys, tempfile
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]
TOOLBAR = source_file(R, 'TSToolbar.m')
CONTROLLER = source_file(R, 'TSToolbarController.m')

CONFIGS = {
    'the toolbar of the report': ('Typeset,Tags,Labels,AutoComplete,ShowFullPath,ColorIndex,flex,Sharing,Split', range(700, 711)),
    'the default source toolbar': ('Typeset,img0,img1,img2,Tags,Labels,img3,flex,Sharing,Split', range(485, 496)),
    'no flexible space': ('Typeset,Tags,Labels,AutoComplete,ShowFullPath,ColorIndex,img1,img2', range(700, 711)),
    'image items only': ('img0,img1,img2,img3,img4,img5,flex,img6,img7', range(305, 316)),
    'two flexible spaces': ('img0,img1,flex,img2,img3,flex,img4,img5', range(242, 251)),
    'a flexible space in the middle': ('img0,img1,flex,img2,img3,img4,img5', range(234, 243)),
}

MUTATIONS = {
    'no priorities': ('    if (@available(macOS 26.0, *))\n        return YES;\n    return NO;\n}', '    return NO;\n}'),
    'rising everywhere': ('    if (lastFlexibleSpace < 0)\n        return (NSToolbarItemVisibilityPriority)index;\n', '    return (NSToolbarItemVisibilityPriority)index;\n'),
    'standard without a flexible space': ('    if (lastFlexibleSpace < 0)\n        return (NSToolbarItemVisibilityPriority)index;\n',
                                          '    if (lastFlexibleSpace < 0)\n        return NSToolbarItemVisibilityPriorityStandard;\n'),
    'own priority dropped': ('MAX(TSToolbarVisibilityPriority(i, lastFlexibleSpace), own.integerValue)', 'TSToolbarVisibilityPriority(i, lastFlexibleSpace)'),
    'not given on a change': ('        [center addObserver:self selector:@selector(itemsWillChange:) name:NSToolbarWillAddItemNotification object:self];\n'
                              '        [center addObserver:self selector:@selector(itemsWillChange:) name:NSToolbarDidRemoveItemNotification object:self];\n', ''),
    'not given on validation': ('    [super validateVisibleItems];\n    if (_ownPriorities', '    [super validateVisibleItems];\n    if (NO && _ownPriorities'),
}

SEEN_IN_THE_SWEEP = {'no priorities', 'rising everywhere', 'standard without a flexible space'}


def build(tmp, source, name):
    (tmp / 'TSToolbar.m').write_text(source)
    binary = tmp / name
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'WebKit',
                    '-I', str(R / 'Tests'), *include_args(R), str(R / 'Tests/ToolbarOverflow.m'), str(tmp / 'TSToolbar.m'), '-o', str(binary)],
                   check=True, capture_output=True, text=True)
    return binary


def settle(binary, home, items, width):
    env = {'HOME': str(home), 'CFFIXED_USER_HOME': str(home), 'PATH': '/usr/bin:/bin'}
    result = subprocess.run([str(binary), 'settle', items, str(width)], capture_output=True, text=True, timeout=120, env=env)
    return result.stdout.strip() or result.stderr.strip()


def sweep(binary, home, configs):
    jobs = [(name, items, width) for name, (items, widths) in configs.items() for width in widths]
    with ThreadPoolExecutor(max_workers=8) as pool:
        lines = list(pool.map(lambda job: settle(binary, home, job[1], job[2]), jobs))
    return [(name, line) for (name, _, _), line in zip(jobs, lines)]


def checks(binary, home):
    env = {'HOME': str(home), 'CFFIXED_USER_HOME': str(home), 'PATH': '/usr/bin:/bin'}
    return subprocess.run([str(binary), 'checks'], capture_output=True, text=True, timeout=120, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--find-bands', action='store_true', help='sweep 150-900 points without the priorities and print where the toolbars oscillate')
    args = parser.parse_args()
    source = TOOLBAR.read_text()
    # The document windows use TSToolbar, and their buttons are bordered as the probe makes them.
    controller = CONTROLLER.read_text()
    assert controller.count('TSToolbar *toolbar = [[TSToolbar alloc] initWithIdentifier: inID];') == 1
    assert controller.count('[(NSButton *)customView setBezelStyle:NSBezelStyleAutomatic];\n            toolbarItem.bordered = YES;') == 1
    with tempfile.TemporaryDirectory(prefix='toolbar-overflow-') as tmp:
        tmp = Path(tmp)
        home = tmp / 'home'
        (home / 'Library').mkdir(parents=True)
        if args.find_bands:
            old, new = MUTATIONS['no priorities']
            binary = build(tmp, source.replace(old, new), 'ToolbarOverflowWithout')
            wide = {name: (items, range(150, 901)) for name, (items, _) in CONFIGS.items()}
            for name, line in sweep(binary, home, wide):
                if 'OSCILLATES' in line:
                    print(name, line)
            return 0
        binary = build(tmp, source, 'ToolbarOverflow')
        result = checks(binary, home)
        if result.returncode:
            print(result.stdout + result.stderr)
            print('FAIL: the checks of the production toolbar fail')
            return 1
        print(result.stdout.strip())
        failed = [f'{name}: {line}' for name, line in sweep(binary, home, CONFIGS) if 'steady' not in line]
        if failed:
            print('\n'.join(failed))
            print('FAIL: toolbars that do not settle')
            return 1
        count = sum(len(widths) for _, widths in CONFIGS.values())
        print(f'PASS: {len(CONFIGS)} arrangements of items settle at {count} widths around the places where items go to the overflow menu')
        missed = []
        for name, (old, new) in MUTATIONS.items():
            if source.count(old) != 1:
                print(f'FAIL: mutation "{name}" does not apply')
                return 1
            try:
                mutated = build(tmp, source.replace(old, new), 'ToolbarOverflowMutated')
            except subprocess.CalledProcessError as error:
                print(f'FAIL: mutation "{name}" does not compile: {error.stderr[-500:]}')
                return 1
            # The first three must be seen as toolbars that do not settle, not only in the checks.
            if name in SEEN_IN_THE_SWEEP:
                noticed = any('OSCILLATES' in line for _, line in sweep(mutated, home, CONFIGS))
            else:
                noticed = checks(mutated, home).returncode != 0
            if noticed:
                print('DETECTED', name, flush=True)
            else:
                missed.append(name)
        if missed:
            print('FAIL: mutations not detected:', ', '.join(missed))
            return 1
        print('NORMAL CONTROL passes again' if checks(build(tmp, source, 'ToolbarOverflow'), home).returncode == 0 else 'FAIL: the control fails')
    return 0


if __name__ == '__main__':
    sys.exit(main())
