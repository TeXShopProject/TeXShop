#!/usr/bin/env python3
"""The prerelease update switch and channel (no window is shown, no user defaults are written).

With --mutation NAME the harness runs against a mutated copy of
TSSparkleController.m and must fail; --mutations runs them all."""
from pathlib import Path
import subprocess
import sys
import tempfile
from shortcut_sources import NAMES, companion_sources
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # A prerelease does not turn the switch on.
    'no-force': ('[defaults setBool:YES forKey:SparklePrereleaseUpdatesKey];', ';'),
    # Every launch turns it on again, so turning it off does not last.
    'force-every-launch': ('if ([[defaults stringForKey:SparklePrereleaseForcedVersionKey] isEqualToString:version]) return;', ';'),
    # Releases also turn it on.
    'force-release': ('if (![self isPrereleaseVersion:version]) return;', ';'),
    # The build number (CFBundleVersion) decides, so a beta is not seen and every build looks new.
    'build-version': ('id version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];',
                      'id version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];'),
    # The application passes its build number instead of its display version.
    'launch-build-version': ('[TSSparkleController preparePrereleaseDefaultsForBundle:[NSBundle mainBundle] defaults:SUD];',
                             '[TSSparkleController preparePrereleaseDefaultsForVersion:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] defaults:SUD];'),
    # The switch does not decide the channel.
    'channel-always': ('return [defaults boolForKey:SparklePrereleaseUpdatesKey] ? [NSSet setWithObject:TSSparklePrereleaseChannel] : [NSSet set];',
                       'return [NSSet setWithObject:TSSparklePrereleaseChannel];'),
}


def run(mutation=None):
    source = source_file(root, 'TSSparkleController.m')
    with tempfile.TemporaryDirectory(prefix='texshop-prerelease-updates-') as tmp:
        if mutation:
            old, new = MUTATIONS[mutation]
            text = source.read_text(encoding='utf-8')
            assert text.count(old) == 1, 'mutation target must be unique: ' + mutation
            source = Path(tmp) / 'TSSparkleController.m'
            source.write_text(text.replace(old, new), encoding='utf-8')
        # The application itself prepares the defaults from its bundle's display version.
        text = source.read_text(encoding='utf-8')
        awake = text[text.index('- (void)awakeFromNib'):]
        awake = awake[:awake.index('\n}')]
        if '[TSSparkleController preparePrereleaseDefaultsForBundle:[NSBundle mainBundle] defaults:SUD];' not in awake \
                or '@"CFBundleVersion"' in awake:
            return subprocess.CompletedProcess([], 1, '', 'FAIL: awakeFromNib must prepare the defaults from the display version of the main bundle\n')
        frameworks = root / 'Frameworks'
        exe = Path(tmp) / 'prerelease-updates'
        subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-F', str(frameworks), '-framework', 'Sparkle',
                        '-Wl,-rpath,' + str(frameworks), '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/PrereleaseUpdates.m'), str(source), str(source_file(root, 'TSUpdatePermissionAlert.m')), str(source_file(root, 'globals.m')),
                        # The controller matches the key of Quit with the shortcut units (#68).
                        '-framework', 'Carbon', *[str(source_file(root, n)) for n in NAMES], *companion_sources(root), '-o', str(exe)],
                       check=True)
        return subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)


def main():
    args = sys.argv[1:]
    if '--mutations' in args or '--mutation' in args:
        names = [args[args.index('--mutation') + 1]] if '--mutation' in args else list(MUTATIONS)
        ok = True
        for name in names:
            result = run(name)
            caught = result.returncode != 0
            print(('CAUGHT ' if caught else 'SURVIVED ') + name + ': ' + (result.stderr.strip().splitlines() or [''])[0])
            ok = ok and caught
        return 0 if ok else 1
    result = run()
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
