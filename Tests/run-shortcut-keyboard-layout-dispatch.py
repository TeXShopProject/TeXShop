#!/usr/bin/env python3
"""Menu shortcuts on French and German keyboard layouts, matched by AppKit's own dispatch.

The probe switches keyboard layouts, so it never runs on this Mac: it is built here and run
over ssh on the Mac named by TEXSHOP_LAYOUT_VM (for example user@192.168.0.32), which must
have this Mac's key. Several Macs separated by commas run the probe on each of them, and the
mutants are built in parallel and shared among them. Without TEXSHOP_LAYOUT_VM the build and the fixture are checked and the
run is skipped. --mutations also checks that the probe catches the double-localized keys of
6.00 beta 6 and a conflict check that misses the keys a layout shows.
"""
from pathlib import Path
import os
import plistlib
import subprocess
import sys
import tempfile
import threading
import queue
from concurrent.futures import ThreadPoolExecutor
import xml.etree.ElementTree as ET
from shortcut_sources import NAMES, companion_sources
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
# One VM, or several separated by commas: the probe and the mutants are spread over them.
vms = [v for v in os.environ.get('TEXSHOP_LAYOUT_VM', '').split(',') if v]
vm = vms[0] if vms else ''

# The menu commands of MainMenu.nib with the keys the nib gives them.
MASKS = {'shift': 1 << 17, 'control': 1 << 18, 'option': 1 << 19, 'command': 1 << 20}
items, seen = [], set()
nib = ET.parse(root / 'Resources/Interfaces/fr.lproj/MainMenu.nib/designable.nib').getroot()
for item in nib.iter('menuItem'):
    key, ident = item.get('keyEquivalent', ''), item.get('identifier', '')
    if not key or not ident.startswith('TSShortcut.') or item.get('alternate') == 'YES':
        continue
    mask = item.find('modifierMask')
    modifiers = MASKS['command'] if mask is None else sum(v for k, v in MASKS.items() if mask.get(k) == 'YES')
    if (key, modifiers) in seen or ident in {i['identifier'] for i in items}:
        continue
    seen.add((key, modifiers))
    items.append({'identifier': ident, 'key': key, 'modifiers': modifiers})
fixture = {i['identifier']: i for i in items}
assert fixture['TSShortcut.associatedWindow:.0']['key'] == '1', 'Source ⇔ Preview is Command-1 in the nib'
assert fixture['TSShortcut.displayConsole:.0']['key'] == '0'
# Keys the probe assigns must be free in the nib.
for key in ('j', 'k'):
    assert (key, MASKS['command'] | MASKS['control']) not in seen, key
print(f'PASS: fixture has {len(items)} menu commands with their nib keys', flush=True)

with tempfile.TemporaryDirectory(prefix='texshop-layout-dispatch-') as directory:
    d = Path(directory)
    (d / 'menu.plist').write_bytes(plistlib.dumps(items))
    store = source_file(root, 'TSShortcutStore.m')
    models = source_file(root, 'TSShortcutModels.m')
    search = source_file(root, 'TSShortcutSearch.m')
    coordinator = source_file(root, 'TSKeyboardShortcuts.m')
    pane = source_file(root, 'TSShortcutPaneController.m')

    def build(replace=None, name='probe'):
        sources = [str(source_file(root, n)) for n in NAMES]
        for original, path in replace or []:
            sources = [str(path) if s == str(original) else s for s in sources]
        command = ['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-arch', 'arm64',
                   '-mmacosx-version-min=14.0', *include_args(root), '-I', str(root / 'Tests'),
                   '-framework', 'Cocoa', '-framework', 'Carbon', str(root / 'Tests/ShortcutKeyboardLayoutDispatch.m'),
                   *sources, *companion_sources(root), '-o', str(d / name)]
        subprocess.run(command, check=True)
        return d / name

    def run(binary, vm=vm):
        remote = f'texshop-layout-dispatch-{os.getpid()}-{binary.name}'
        subprocess.run(['ssh', '-o', 'BatchMode=yes', vm, f'mkdir -p {remote}'], check=True)
        subprocess.run(['scp', '-q', str(binary), str(d / 'menu.plist'), f'{vm}:{remote}/'], check=True)
        try:
            return subprocess.run(['ssh', '-o', 'BatchMode=yes', vm,
                                   f'TEXSHOP_ALLOW_LAYOUT_SWITCH=1 {remote}/{binary.name} {remote}/menu.plist'],
                                  capture_output=True, text=True, timeout=600)
        finally:
            subprocess.run(['ssh', '-o', 'BatchMode=yes', vm, f'rm -rf {remote}'], check=False)
            # The probe selects ABC again and turns off the layouts it turned on; check that it did.
            check = subprocess.run(['ssh', '-o', 'BatchMode=yes', vm, 'defaults read com.apple.HIToolbox AppleSelectedInputSources'],
                                   capture_output=True, text=True)
            assert 'ABC' in check.stdout, ('ABC not selected after the probe', check.stdout)
            check = subprocess.run(['ssh', '-o', 'BatchMode=yes', vm, 'defaults read com.apple.HIToolbox AppleEnabledInputSources'],
                                   capture_output=True, text=True)
            assert check.returncode == 0 and 'French' not in check.stdout and 'German' not in check.stdout, ('French or German left on', check.stdout)

    binary = build()
    local = subprocess.run([str(binary), str(d / 'menu.plist')], capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != 'TEXSHOP_ALLOW_LAYOUT_SWITCH'})
    assert local.returncode == 2 and 'Refusing' in local.stderr, ('probe must refuse to switch layouts here', local)
    print('PASS: the probe refuses to switch keyboard layouts outside a VM', flush=True)
    if not vm:
        print('SKIP: set TEXSHOP_LAYOUT_VM=user@host to run the probe in a VM', flush=True)
        sys.exit(0)
    # The probe on every VM at once (each VM switches only its own layouts).
    with ThreadPoolExecutor(len(vms)) as pool:
        results = list(pool.map(lambda host: (host, run(binary, host)), vms))
    for host, result in results:
        version = subprocess.run(['ssh', '-o', 'BatchMode=yes', host, 'sw_vers -productVersion'], capture_output=True, text=True).stdout.strip()
        print(f'== {host} (macOS {version})', flush=True)
        print(result.stdout, end='', flush=True)
        assert result.returncode == 0, (host, result.stderr)
    if '--mutations' in sys.argv:
        mutations = [
            ('default read as AppKit shows it', models,
             '    item.allowsAutomaticKeyEquivalentLocalization = NO;\n    _defaultKey=[item.keyEquivalent copy];_defaultModifiers=item.keyEquivalentModifierMask;\n    item.allowsAutomaticKeyEquivalentLocalization = _defaultLocalization;',
             '    _defaultKey=[item.keyEquivalent copy];_defaultModifiers=item.keyEquivalentModifierMask;',
             "the layout's keys give 1 100000 for the nib's key, AppKit shows ! 100000"),
            ('6.00 beta 6: shown default assigned again to every item', models,
             '    item.allowsAutomaticKeyEquivalentLocalization = NO;\n    _defaultKey=[item.keyEquivalent copy];_defaultModifiers=item.keyEquivalentModifierMask;\n    item.allowsAutomaticKeyEquivalentLocalization = _defaultLocalization;',
             '    _defaultKey=[item.keyEquivalent copy];_defaultModifiers=item.keyEquivalentModifierMask;',
             'FAIL: store started on com.apple.keylayout.French: '),
            ('conflicts only with given keys', store,
             '        if (![TSShownBinding(item) isEqual:binding] && ![[self.itemBindings objectForKey:item] containsObject:binding]) { return; }',
             '        if (![TSGivenBinding(item) isEqual:binding]) { return; }',
             'is used by (null)'),
            ('layout keys of Command applied to every modifier as they are', store,
             '    return TSBinding(base.key, (given.modifiers & ~NSEventModifierFlagShift) | (base.modifiers & NSEventModifierFlagShift));',
             '    return TSBinding(base.key, base.modifiers);',
             'the layout\'s keys give'),
            ('changes made before the layout keys are not checked again', store,
             '        if (learned) [self checkChangesMadeBeforeLayoutKeys:layout];',
             '        ;',
             'FAIL: '),
            ('Settings act before the layout keys are known', pane,
             '    if (self.runningAfterLayoutKeys || [self.store knowsKeysOfCurrentLayout]) return NO;',
             '    if (YES) return NO;',
             'FAIL: restoring Source ⇔ Preview in the pass French is chosen'),
            ('a key every variant of which is in use left unknown', store,
             '                if (candidates.count == 1) keys[base] = candidates.anyObject;\n                else if',
             '                if',
             'Command-1 with every variant in use'),
            ('Restore waits for the keys and restores what is selected then', pane,
             'if (deferringSelf.selectedCommand == chosen) [deferringSelf restoreShortcut:sender];',
             '[deferringSelf restoreShortcut:sender];',
             'another selection while Restore waits'),
            ('a layout change and back while Settings wait is not noticed', pane,
             '        if (strongSelf.layoutChanges != changes) return;',
             '        ;',
             'French, ABC and French again'),
            ('Restore All does not ask again for macros it did not name', pane,
             '    if (![[NSSet setWithArray:[store macrosAffectedByRestoringAll] ?: @[]] isSubsetOfSet:[NSSet setWithArray:named]]) {',
             '    if (NO) {',
             'asks again naming'),
            ('keys a layout could show one of several of are not compared', store,
             '                else if (candidates.count > 1) possible[base] = candidates;',
             '                ;',
             'meets the Control-Command-é item'),
            ('a layout change while the macro question is open is ignored when recording', pane,
             '        if (!accepted || strongSelf.layoutChanges != changes) { [strongSelf endRecording]; return; }',
             '        if (!accepted) { [strongSelf endRecording]; return; }',
             'a layout change while the question is open records nothing'),
            ('recording names only macros showing the key or given it', store,
             '        if ([TSShownBinding(item) isEqual:binding] || [[self bindingsForMacroKey:given.key modifiers:given.modifiers] containsObject:binding])',
             '        if ([TSShownBinding(item) isEqual:binding] || [given isEqual:binding])',
             'names the Control-Option-2 macro'),
            ('a macro item is taken for whichever macro shows its key', store,
             '    if (placed.count == 1) return TSBinding(placed[0].key, placed[0].modifiers);',
             '    if (NO) return nil;',
             'names MacroTwo'),
            ('saved keys checked against given defaults only', store,
             '    return [NSSet setWithObjects:given, [self shownDefaultForCommand:command], nil];',
             '    return [NSSet setWithObject:given];',
             'FAIL: '),
            ('shown defaults never worked out', store,
             '    if ((known && known.count == TSLayoutKeyCount()) || !self.menu) { completion(NO); return; }',
             '    if (YES) { completion(NO); return; }',
             'keys of com.apple.keylayout.French worked out'),
            ('macro keys compared only as their files name them', store,
             '    [result addObject:[self shownBindingForGivenKey:key modifiers:flags]];\n    // When the layout could show',
             '    // When the layout could show',
             'FAIL: a new Control-Command-1 macro meets'),
            ('macro editor compares macros as their files name them', store,
             '        NSArray<TSShortcutBinding *> *bindings = [self bindingsForMacroKey:binding.key modifiers:binding.modifiers];',
             '        NSArray<TSShortcutBinding *> *bindings = @[binding];',
             'FAIL: a new Control-Command-1 macro meets'),
            ('key search compares macro items as shown', search,
             '            match = activeMacros[[store givenBindingForMacroItem:item path:path]];',
             '            match = activeMacros[binding];',
             'key search by pressing Control-Command-&'),
            ('layout change waits behind a menu change', coordinator,
             '    if (!self.keyboardLayout || [TSKeyboardLayoutID() isEqual:self.keyboardLayout] || self.layoutRefreshPending) return;',
             '    if (!self.keyboardLayout || [TSKeyboardLayoutID() isEqual:self.keyboardLayout] || self.layoutRefreshPending || self.menuRefreshPending) return;',
             'a layout change while a menu change waits'),
        ]
        every_item = ('    if (item.allowsAutomaticKeyEquivalentLocalization != localized) return NO;',
                      '    return NO;')
        # --only NAME... runs the mutations whose names contain one of the words given after it.
        only = sys.argv[sys.argv.index('--only') + 1:] if '--only' in sys.argv else []
        selected = [m for m in mutations if not only or any(word in m[0] for word in only)]
        # Mutants are built in parallel here, then run one at a time on each VM, the VMs in parallel.
        def make(numbered):
            number, (name, path, old, new, expected) = numbered
            text = path.read_text()
            assert text.count(old) == 1, name
            folder = d / f'source{number}'
            folder.mkdir()
            mutated = folder / path.name
            mutated.write_text(text.replace(old, new))
            replace = [(path, mutated)]
            if name.startswith('6.00 beta 6'):
                text = store.read_text()
                assert text.count(every_item[0]) == 1
                (folder / 'store').mkdir()
                (folder / 'store' / store.name).write_text(text.replace(*every_item))
                replace.append((store, folder / 'store' / store.name))
            return build(replace, f'mutant{number}')
        with ThreadPoolExecutor(min(8, len(selected) or 1)) as pool:
            binaries = list(pool.map(make, enumerate(selected)))
        jobs = queue.Queue()
        for job in zip(selected, binaries):
            jobs.put(job)
        outcomes = {}
        def worker(host):
            while True:
                try:
                    (name, path, old, new, expected), mutant = jobs.get_nowait()
                except queue.Empty:
                    return
                outcomes[name] = (host, run(mutant, host), expected)
        threads = [threading.Thread(target=worker, args=(host,)) for host in vms]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        for name, *_ in selected:
            host, result, expected = outcomes[name]
            assert result.returncode != 0 and expected in result.stderr, (name, host, result.stdout, result.stderr)
            print('DETECTED', name, f'({host}) ->', result.stderr.strip().splitlines()[-1], flush=True)
        with ThreadPoolExecutor(len(vms)) as pool:
            results = list(pool.map(lambda host: (host, run(binary, host)), vms))
        for host, result in results:
            assert result.returncode == 0, (host, result.stderr)
        print('NORMAL CONTROL passed on', ', '.join(vms), flush=True)
