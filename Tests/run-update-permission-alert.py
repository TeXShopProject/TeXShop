#!/usr/bin/env python3
"""The question whether updates are checked automatically is a standard alert (no window is shown, no network).

TeXShop asks it in place of Sparkle's own window: on the second launch until it is answered, with
Japanese text of its own and Sparkle's translations elsewhere, without surrounding spaces. The
answer is given to Sparkle as its own window gives it. Every language of TeXShop runs in parallel.

With --mutation NAME the harness compiles a deliberately wrong source and must fail; --mutations runs them all."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
sparkle = root / 'Frameworks/Sparkle.framework'
LANGUAGES = sorted(p.name[:-len('.lproj')] for p in interfaces.glob('*.lproj') if p.name != 'Base.lproj')
EXPECTED = {
    'ja': ['アップデートを自動的に確認しますか?',
           'アップデートは“TeXShop”メニューからいつでも手動で確認できます。',
           '自動的に確認', '確認しない', 'アップデートを自動的にダウンロードしてインストール'],
    'en': ['Check for updates automatically?',
           'Should TeXShop automatically check for updates? You can always check for updates manually from the TeXShop menu.',
           'Check Automatically', 'Don’t Check', 'Automatically download and install updates'],
}
SOURCE = root / 'Sources/App/TSUpdatePermissionAlert.m'
MUTATIONS = {
    # Sparkle's Japanese text starts with a space.
    'no-trim': ('return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];', 'return text;'),
    # Sparkle asks on the second launch, not the first.
    'first-launch': (' && [launched respondsToSelector:@selector(boolValue)] && [launched boolValue]', ''),
    # Escape answers Don't Check.
    'no-escape': ('dontCheck.keyEquivalent = @"\\e";', ''),
    # SPUUpdater.allowsAutomaticUpdates is NO before checks are on, so it cannot decide whether the box is shown.
    'box-follows-checks': ('_offersDownloads = [TSUpdatePermissionAlert offersAutomaticDownloadsForBundle:appBundle];', '_offersDownloads = target.automaticallyChecksForUpdates;'),
    # Downloads can be turned on only after checks.
    'downloads-before-checks': ('''    target.automaticallyChecksForUpdates = checks;
    if (self.offersDownloads)
        target.automaticallyDownloadsUpdates = checks && self.downloadsCheckbox.state == NSControlStateValueOn;''', '''    if (self.offersDownloads)
        target.automaticallyDownloadsUpdates = checks && self.downloadsCheckbox.state == NSControlStateValueOn;
    target.automaticallyChecksForUpdates = checks;'''),
    # The box is not offered when Info.plist turns automatic updates off.
    'ignore-info': ('return ![allows respondsToSelector:@selector(boolValue)] || [allows boolValue];', 'return YES;'),
}


def build(tmp, mutation=None):
    source_dir = SOURCE.parent
    if mutation:
        old, new = MUTATIONS[mutation]
        text = SOURCE.read_text(encoding='utf-8')
        assert text.count(old) == 1, 'mutation target must be unique: ' + mutation
        source_dir = Path(tmp) / 'src'
        source_dir.mkdir()
        (source_dir / SOURCE.name).write_text(text.replace(old, new), encoding='utf-8')
        (source_dir / 'TSUpdatePermissionAlert.h').write_bytes((SOURCE.parent / 'TSUpdatePermissionAlert.h').read_bytes())
    exe = Path(tmp) / 'update-permission-alert'
    # Without this, every bundle follows the language of the test program, which has none but English.
    info = Path(tmp) / 'Info.plist'
    info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.texshop.update-permission', 'CFBundleAllowMixedLocalizations': True}))
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(source_dir),
                    '-sectcreate', '__TEXT', '__info_plist', str(info),
                    str(root / 'Tests/UpdatePermissionAlert.m'), str(source_dir / SOURCE.name), '-o', str(exe)], check=True)
    # A bundle named TeXShop with TeXShop's translations.
    bundle = Path(tmp) / 'TeXShop.bundle'
    bundle.mkdir()
    for lproj in interfaces.glob('*.lproj'):
        (bundle / lproj.name).symlink_to(lproj)
    # The same with SUAllowsAutomaticUpdates = NO in its Info.plist.
    without = Path(tmp) / 'without' / 'TeXShop.bundle'
    without.mkdir(parents=True)
    (without / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleName': 'TeXShop', 'SUAllowsAutomaticUpdates': False}))
    return exe, bundle


def run_language(exe, bundle, language, tmp):
    args = [str(exe), '-AppleLanguages', '(%s)' % language, '-Interfaces', str(bundle),
            '-InterfacesWithoutDownloads', str(Path(tmp) / 'without' / 'TeXShop.bundle'),
            '-Sparkle', str(sparkle)]
    if language in EXPECTED:
        expect = Path(tmp) / ('expect-%s.plist' % language)
        expect.write_bytes(plistlib.dumps(EXPECTED[language]))
        args += ['-ExpectFile', str(expect)]
    env = dict(os.environ, TMPDIR=tmp + '/')
    return language, subprocess.run(args, capture_output=True, text=True, timeout=120, env=env)


def run(mutation=None):
    with tempfile.TemporaryDirectory(prefix='texshop-update-permission-') as tmp:
        exe, bundle = build(tmp, mutation)
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda lang: run_language(exe, bundle, lang, tmp), LANGUAGES))
    return results


def main():
    args = sys.argv[1:]
    if '--mutations' in args or '--mutation' in args:
        names = [args[args.index('--mutation') + 1]] if '--mutation' in args else list(MUTATIONS)
        ok = True
        with ThreadPoolExecutor(max_workers=4) as pool:
            for name, results in zip(names, pool.map(run, names)):
                failed = [(lang, r) for lang, r in results if r.returncode != 0]
                first = (failed[0][1].stderr.strip().splitlines() or [''])[0] if failed else ''
                print(('CAUGHT ' if failed else 'SURVIVED ') + name + ': ' + first)
                ok = ok and bool(failed)
        return 0 if ok else 1
    status = 0
    for language, result in run():
        print('== ' + language)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        status = status or result.returncode
    print('PASS update permission alert in %d languages' % len(LANGUAGES) if status == 0 else 'FAIL')
    return status


if __name__ == '__main__':
    sys.exit(main())
