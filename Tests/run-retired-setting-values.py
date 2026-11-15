#!/usr/bin/env python3
"""Values an earlier version could save that no longer apply, after launch. The production launch branch of
TSAppDelegate and -[TSPreferences registerFactoryDefaults] are taken verbatim, as in run-find-method-migration.py, and
run on in-memory defaults with the shipped FactoryDefaults.plist. A TeX path of /usr/texbin becomes /Library/TeX/texbin
(set, never removed, so that the next launch does not reset every setting); an empty kpsewhich command or HTML home page
is removed, so that the default applies; other values are left alone. The factory defaults are registered at every
launch, also the first, so that a setting removed later in Settings falls back to its default. Nothing is displayed.

--mutations breaks one rule at a time and checks that the test notices."""
from pathlib import Path
import argparse
import importlib.util
import sys

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('find_method_migration', Path(__file__).with_name('run-find-method-migration.py'))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

MUTATIONS = {
    '/usr/texbin is kept': ('TSPreferenceLaunch.m', 'isEqualToString:@"/usr/texbin"]', 'isEqualToString:@"/usr/texbin-none"]'),
    '/usr/texbin is removed instead of replaced': ('TSPreferenceLaunch.m',
        '        [defaults setObject:@"/Library/TeX/texbin" forKey:TetexBinPath];\n', '        [defaults removeObjectForKey:TetexBinPath];\n'),
    'an empty kpsewhich command is kept': ('TSPreferenceLaunch.m', '@[KpsetoolKey, HtmlHomeKey]', '@[HtmlHomeKey]'),
    'any HTML home page is removed': ('TSPreferenceLaunch.m',
        '[value stringByTrimmingCharactersInSet:spaces].length == 0', '[value stringByTrimmingCharactersInSet:spaces].length >= 0'),
    'the first launch registers no defaults': ('TSAppDelegate.m',
        '\t[SUD registerDefaults:factoryDefaults];\n', '\tif (savedSettings.count) [SUD registerDefaults:factoryDefaults];\n'),
}

MAIN = r"""
int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *library = @"/Library/TeX/texbin";
        NSDictionary *earlier = @{@"TSHasBeenUsed": @"YES", @"TetexBinPath": library, @"FindMethodSwitchedToAdvancedFind": @YES, @"Mine": @"kept"};
        NSMutableDictionary *(^with)(NSDictionary *) = ^NSMutableDictionary *(NSDictionary *b) {
            NSMutableDictionary *m = [earlier mutableCopy]; [m addEntriesFromDictionary:b]; return m; };
        NSString *factoryKpsetool = @"kpsewhich -progname=latex", *factoryHome = @"https://texshop.app";

        for (NSString *path in @[@"/usr/texbin", @"/usr/texbin/", @" /usr/texbin ", @"/usr//texbin"]) {
            Launch(with(@{@"TetexBinPath": path}));
            Check([Saved()[@"TetexBinPath"] isEqual:library], [NSString stringWithFormat:@"%@ becomes /Library/TeX/texbin, stored", path]);
            Relaunch();
            Check([Saved()[@"TetexBinPath"] isEqual:library] && [[SUD stringForKey:@"Mine"] isEqual:@"kept"], @"and the next launch keeps the settings");
        }
        for (NSString *path in @[library, @"/usr/local/texlive/2026/bin/universal-darwin", @"/usr/texbin2", @"~/texbin"]) {
            Launch(with(@{@"TetexBinPath": path}));
            Check([Saved()[@"TetexBinPath"] isEqual:path], [NSString stringWithFormat:@"%@ stays", path]);
        }
        Launch(with(@{@"Kpsetool": @"", @"HtmlHome": @"  ", @"Mine": @"kept"}));
        Check(Saved()[@"Kpsetool"] == nil && Saved()[@"HtmlHome"] == nil, @"an empty kpsewhich command and home page are removed");
        Check([[SUD stringForKey:@"Kpsetool"] isEqual:factoryKpsetool] && [[SUD stringForKey:@"HtmlHome"] isEqual:factoryHome], @"and their defaults apply");
        Check([[SUD stringForKey:@"Mine"] isEqual:@"kept"], @"other settings stay");
        Launch(with(@{@"Kpsetool": @"kpsewhich -format=tex", @"HtmlHome": @"https://tug.org"}));
        Check([Saved()[@"Kpsetool"] isEqual:@"kpsewhich -format=tex"] && [Saved()[@"HtmlHome"] isEqual:@"https://tug.org"], @"values set stay");
        Launch(with(@{@"AlternateEngine": @"", @"AltPath": @""}));
        Check([Saved()[@"AlternateEngine"] isEqual:@""] && [Saved()[@"AltPath"] isEqual:@""], @"other empty values stay");

        // A new user: everything from the factory defaults, which are also registered.
        Launch(@{});
        Check([Saved()[@"TetexBinPath"] isEqual:library], @"a new user starts with /Library/TeX/texbin");
        [SUD removeObjectForKey:@"Kpsetool"];
        Check([[SUD stringForKey:@"Kpsetool"] isEqual:factoryKpsetool], @"at the first launch, a setting removed falls back to its registered default");
        Launch(with(@{}));
        [SUD removeObjectForKey:@"HtmlHome"];
        Check([[SUD stringForKey:@"HtmlHome"] isEqual:factoryHome], @"at a later launch too");
        if (failures)
            return 1;
        puts("PASS: /usr/texbin becomes /Library/TeX/texbin, empty kpsewhich and home page fall back to their defaults, defaults registered at every launch");
    }
    return 0;
}
"""


def run(texts):
    program = harness.PROGRAM[:harness.PROGRAM.index('int main(')] + MAIN
    saved = harness.PROGRAM
    harness.PROGRAM = program
    try:
        return harness.run(texts)
    finally:
        harness.PROGRAM = saved


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    texts = {name: path.read_text(encoding='utf-8', errors='surrogateescape') for name, path in harness.FILES.items()}
    result = run(texts)
    print(result.stdout + result.stderr, end='')
    if result.returncode:
        sys.exit('FAIL: retired setting values after launch')
    if args.mutations:
        for name, (file, *pairs) in MUTATIONS.items():
            mutated = dict(texts)
            for old, new in zip(pairs[::2], pairs[1::2]):
                if mutated[file].count(old) != 1:
                    sys.exit(f'FAIL: mutation {name!r} does not apply')
                mutated[file] = mutated[file].replace(old, new)
            if run(mutated).returncode == 0:
                sys.exit(f'FAIL: mutation {name!r} was not detected')
            print(f'PASS: detected mutation {name!r}')


if __name__ == '__main__':
    main()
