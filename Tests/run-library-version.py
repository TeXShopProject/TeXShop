#!/usr/bin/env python3
"""~/Library/TeXShop is refreshed once per display version, never per build (no window, a temporary folder only).

It also checks that TSAppDelegate compares the display version and records it after copying New.
With --mutation NAME the harness runs against mutated sources and must fail; --mutations runs them all."""
from pathlib import Path
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # Only a later number copies, so 6.00 beta-1 → 6.00 copies nothing (the old rule).
    'number-only': ('                return a > l;', '                return NO;'),
    # Any other version of the same number copies, an earlier beta too.
    'unordered': ('                return a > l;', '                return YES;'),
    # A beta is taken for later than its release.
    'beta-after-release': ('[list addObject:@(beta ? 0 : 1)];', '[list addObject:@(beta ? 2 : 1)];'),
    # Betas are compared as text, so beta-10 comes before beta-9.
    'beta-as-text': ('[list addObject:@(beta ? group(3).integerValue : 0)];', '[list addObject:@(beta ? (NSInteger)group(3).UTF8String[0] : 0)];'),
    # An unknown form of the same number never copies.
    'unknown-never': ('    return ![libraryVersion isEqualToString:applicationVersion];', '    return NO;'),
    # Every launch copies.
    'always': ('    libraryVersion = [libraryVersion stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];\n    if (libraryVersion.length == 0)', '    if (YES)'),
    # An earlier number copies over a later one.
    'downgrade': ('        if (application < library - 0.005)\n            return NO;', ''),
    # Nothing is remembered, so the next launch copies again.
    'no-record': ('    return [text writeToFile:', '    return YES || [text writeToFile:'),
    # The application compares its build number (it changes with every build).
    'build-number': ('infoDictionary] objectForKey:@"CFBundleShortVersionString"];', 'infoDictionary] objectForKey:@"CFBundleVersion"];'),
    # The application copies but does not remember the version.
    'app-no-record': ('		TSLibraryRecordVersion(NewPath, currentVersion);\n', ''),
}


def check_delegate(text):
    """TSAppDelegate decides with the display version and records it right after copying New."""
    start = text.index('currentVersion = [[[NSBundle bundleForClass:[self class]]')
    decide = text[start:text.index('needsUpdating = TSLibraryNeedsUpdating(TSLibraryVersionInFolder(NewPath), currentVersion);', start)]
    if 'objectForKey:@"CFBundleShortVersionString"]' not in decide:
        return 'TSAppDelegate must compare the display version (CFBundleShortVersionString)'
    copy = ('	if (needsUpdating) {\n		[self mirrorPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"TeXShop/New"]\n'
            '				  toPath:[NewPath stringByStandardizingPath]];\n		TSLibraryRecordVersion(NewPath, currentVersion);\n	}')
    if copy not in text:
        return 'TSAppDelegate must record the version right after copying New'
    return None


def run(mutation=None):
    library = source_file(root, 'TSLibraryVersion.m')
    delegate = source_file(root, 'TSAppDelegate.m').read_text(encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix='texshop-library-version-') as tmp:
        if mutation:
            old, new = MUTATIONS[mutation]
            text = library.read_text(encoding='utf-8')
            if text.count(old) == 1:
                library = Path(tmp) / 'TSLibraryVersion.m'
                library.write_text(text.replace(old, new), encoding='utf-8')
            else:
                assert delegate.count(old) == 1, 'mutation target must be unique: ' + mutation
                delegate = delegate.replace(old, new)
        problem = check_delegate(delegate)
        if problem:
            return subprocess.CompletedProcess([], 1, '', 'FAIL: ' + problem + '\n')
        exe = Path(tmp) / 'library-version'
        subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Foundation', *include_args(root),
                        str(root / 'Tests/LibraryVersion.m'), str(library), '-o', str(exe)], check=True)
        return subprocess.run([str(exe), str(root / 'Resources/TeXShop/New')], capture_output=True, text=True, timeout=60)


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
