#!/usr/bin/env python3
"""Issue #68: the key of Quit closes Sparkle's app-modal alerts and quits.

The probe shows Sparkle's own alerts and activates itself, so it never runs on this Mac: it is
built here and run over ssh on the Macs named by TEXSHOP_GUI_VM (for example
user@192.168.0.32,user@192.168.0.29), which must have this Mac's key and a logged-in user.
Without TEXSHOP_GUI_VM the probe is built and the run is skipped. --mutations checks that the
probe catches each mutation of TSSparkleController.m; --binary DIR only writes the probe app."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from shortcut_sources import NAMES, companion_sources
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
vms = [v for v in os.environ.get('TEXSHOP_GUI_VM', '').split(',') if v]

MUTATIONS = {
    # Sparkle does not tell the controller about its alerts.
    'no-delegate': ('    userDriverDelegate = self;\n', ''),
    # Nothing watches the keys while an alert is shown.
    'no-monitor': ('- (void)standardUserDriverWillShowModalAlert\n{\n    [self stopQuitKeyMonitor];\n',
                   '- (void)standardUserDriverWillShowModalAlert\n{\n    [self stopQuitKeyMonitor];\n    return;\n'),
    # The monitor stays after the alert.
    'monitor-kept': ('- (void)standardUserDriverDidShowModalAlert\n{\n    [self stopQuitKeyMonitor];', '- (void)standardUserDriverDidShowModalAlert\n{\n'),
    # TeXShop is asked to quit while the alert is still running.
    'quit-during-alert': ('    self.quitRequested = YES;\n', '    [NSApp terminate:nil];\n'),
    # Over another modal window the key closes the alert, and the quit waits for that window (first audit).
    'nested-intercepted': ('    if (NSApp.modalWindow != nil) return;\n', ''),
    # Over another modal window the key closes the alert without quitting (second audit).
    'nested-closes': [('    if (NSApp.modalWindow != nil) return;\n', ''), ('    if (quit)\n', '    if (quit && NSApp.modalWindow == nil)\n')],
    # The alert is not closed.
    'alert-stays': ('    [NSApp stopModalWithCode:NSAlertFirstButtonReturn];\n', ''),
    # Command-Q is hard-wired instead of the key of the Quit item.
    'command-q-wired': ('![TSShortcutStore event:event matchesItem:quit]',
                        '!([event.charactersIgnoringModifiers isEqualToString:@"q"] && (event.modifierFlags & NSEventModifierFlagCommand))'),
    # Any key quits.
    'any-key': ('|| ![TSShortcutStore event:event matchesItem:quit]', ''),
    # Every key is swallowed while an alert is shown.
    'swallow-keys': ('return [weakSelf quitFromModalAlertWithEvent:event] ? nil : event;', '[weakSelf quitFromModalAlertWithEvent:event]; return nil;'),
}


def build(directory, source):
    app = Path(directory) / 'SparkleQuitKey.app'
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    (app / 'Contents/Frameworks').mkdir()
    shutil.copytree(root / 'Frameworks/Sparkle.framework', app / 'Contents/Frameworks/Sparkle.framework', symlinks=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'SparkleQuitKey', 'CFBundleIdentifier': 'app.texshop.test.sparkle-quit-key',
        'CFBundleName': 'TeXShop', 'CFBundleShortVersionString': '6.00', 'CFBundleVersion': '1',
        'CFBundlePackageType': 'APPL', 'LSMinimumSystemVersion': '14.0'}))
    sources = [str(source_file(root, n)) for n in NAMES]
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-arch', 'arm64', '-mmacosx-version-min=14.0',
                    *include_args(root), '-I', str(root / 'Tests'), '-F', str(root / 'Frameworks'),
                    '-framework', 'Cocoa', '-framework', 'Carbon', '-framework', 'Sparkle',
                    '-Wl,-rpath,@executable_path/../Frameworks',
                    str(root / 'Tests/SparkleQuitKey.m'), str(source), str(source_file(root, 'globals.m')),
                    *sources, *companion_sources(root), '-o', str(macos / 'SparkleQuitKey')], check=True)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True, capture_output=True)
    return app


def mutated(directory, mutation):
    source = source_file(root, 'TSSparkleController.m')
    if not mutation:
        return source
    edits = MUTATIONS[mutation]
    text = source.read_text(encoding='utf-8')
    for old, new in (edits if isinstance(edits, list) else [edits]):
        assert text.count(old) == 1, 'mutation target must be unique: ' + mutation
        text = text.replace(old, new)
    path = Path(directory) / 'TSSparkleController.m'
    path.write_text(text, encoding='utf-8')
    return path


def run_on(vm, app, tag):
    remote = f'texshop-sparkle-quit-{os.getpid()}-{tag}'
    subprocess.run(['ssh', '-o', 'BatchMode=yes', vm, f'rm -rf {remote} && mkdir -p {remote}/home/Library'], check=True)
    subprocess.run(['scp', '-q', '-r', str(app), f'{vm}:{remote}/'], check=True)
    try:
        # Started with open, the probe becomes the active application, so its alerts take keys;
        # started directly over ssh, macOS 26 leaves it in the background.
        result = subprocess.run(['ssh', '-o', 'BatchMode=yes', vm,
                                 f'cd {remote} && open -W -n --stdout $PWD/out.txt --stderr $PWD/err.txt '
                                 f'--env CFFIXED_USER_HOME=$PWD/home --env TMPDIR=$PWD/ ./SparkleQuitKey.app; '
                                 f'cat out.txt; cat err.txt >&2'],
                                capture_output=True, text=True, timeout=180)
        passed = result.stdout.rstrip().endswith('ALL PASSED')
        return subprocess.CompletedProcess(result.args, 0 if passed else 1, result.stdout, result.stderr)
    finally:
        subprocess.run(['ssh', '-o', 'BatchMode=yes', vm, f'rm -rf {remote}'], check=False)


def one(mutation, vm):
    with tempfile.TemporaryDirectory(prefix='texshop-sparkle-quit-') as tmp:
        app = build(tmp, mutated(tmp, mutation))
        return run_on(vm, app, mutation or 'plain')


def main():
    args = sys.argv[1:]
    if '--binary' in args:
        out = Path(args[args.index('--binary') + 1])
        with tempfile.TemporaryDirectory(prefix='texshop-sparkle-quit-') as tmp:
            app = build(tmp, mutated(tmp, None))
            shutil.rmtree(out / app.name, ignore_errors=True)
            shutil.copytree(app, out / app.name, symlinks=True)
        print(f'wrote {out / app.name}')
        return 0
    if not vms:
        with tempfile.TemporaryDirectory(prefix='texshop-sparkle-quit-') as tmp:
            build(tmp, mutated(tmp, None))
            for name in MUTATIONS:
                mutated(tmp, name)
        print('PASS: the probe builds and every mutation target is found')
        print('SKIP: set TEXSHOP_GUI_VM to run the probe on a test Mac')
        return 0
    if '--mutations' in args or '--mutation' in args:
        names = [args[args.index('--mutation') + 1]] if '--mutation' in args else list(MUTATIONS)
        # One probe at a time on each Mac, since only one application can be active there.
        def on_vm(vm):
            return [((name, vm), one(name, vm)) for name in names]
        with ThreadPoolExecutor(max_workers=len(vms)) as pool:
            results = [r for rs in pool.map(on_vm, vms) for r in rs]
        ok = True
        for (name, vm), result in results:
            caught = result.returncode != 0
            first = next((l for l in result.stdout.splitlines() if l.startswith('FAIL')), result.stderr.strip()[:200])
            print(('CAUGHT ' if caught else 'SURVIVED ') + f'{name} on {vm}: {first}')
            ok = ok and caught
        return 0 if ok else 1
    ok = True
    for vm in vms:
        result = one(None, vm)
        print(f'== {vm}')
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        ok = ok and result.returncode == 0
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
