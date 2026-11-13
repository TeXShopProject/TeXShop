#!/usr/bin/env python3
"""The find method after launch: the production launch branch of TSAppDelegate and
-[TSPreferences registerFactoryDefaults] (its setPersistentDomain:) are taken verbatim and run on in-memory defaults
with the shipped FactoryDefaults.plist; the final value is checked for every kind of user, for an explicit reset and
for every shipped profile. Nothing is displayed.

--mutations breaks one rule at a time and checks that the test notices."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
FILES = {
    'TSAppDelegate.m': source_file(root, 'TSAppDelegate.m'),
    'TSPreferences.m': source_file(root, 'TSPreferences.m'),
    'TSPreferenceLaunch.m': source_file(root, 'TSPreferenceLaunch.m'),
    'TSPreferenceProfile.m': source_file(root, 'TSPreferenceProfile.m'),
    'FactoryDefaults.plist': root / 'Resources/Defaults/FactoryDefaults.plist',
}
PROFILES = sorted((root / 'Resources/Defaults').glob('Defaults_*.plist'))

MUTATIONS = {
    'a new user needs both marks missing': ('TSPreferenceLaunch.m',
        '[defaults boolForKey:TSHasBeenUsedKey] == NO || [defaults objectForKey:TetexBinPath] == nil',
        '[defaults boolForKey:TSHasBeenUsedKey] == NO && [defaults objectForKey:TetexBinPath] == nil'),
    'a chosen find method is replaced': ('TSPreferenceLaunch.m', '    if (savedSettings[FindMethodKey] == nil)\n', '    if (YES)\n'),
    'earlier users get the Advanced Find panel': ('TSPreferenceLaunch.m',
        '[defaults setInteger:TSFindMethodFindBar forKey:FindMethodKey];', '[defaults setInteger:TSFindMethodAdvancedPanel forKey:FindMethodKey];'),
    # The experiment's own judgement (either mark makes an earlier user), written after the reset
    'the migration judges for itself, after the reset': ('TSAppDelegate.m',
        '\t\tTSPreferencesMigrateEarlierUser(SUD, savedSettings);\n', '',
        '[SUD registerDefaults:factoryDefaults];\n\t}\n',
        '[SUD registerDefaults:factoryDefaults];\n\t}\n\tif ([savedSettings[@"TSHasBeenUsed"] boolValue] || savedSettings[@"TetexBinPath"] != nil)\n\t\tTSPreferencesMigrateEarlierUser(SUD, savedSettings);\n'),
    'new users keep the find bar': ('FactoryDefaults.plist', '<key>FindMethod</key>\n\t<string>3</string>', '<key>FindMethod</key>\n\t<string>1</string>'),
    'a profile sets the find method': ('TSPreferenceProfile.m', '        FindMethodKey, //', '        //'),
    'a profile resets the panel\'s own settings': ('TSPreferenceProfile.m', '        [key hasPrefix:@"AdvancedFind"]) return YES;', '        NO) return YES;'),
}

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "globals.h"
#import "TSPreferenceLaunch.h"
#import "TSPreferenceProfile.h"
#import "TSFindInterface.h"
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { fprintf(stderr, "FAIL: %s\n", what.UTF8String); failures++; } }
static NSString *TSPreferencesDomainName(void) { return [[NSBundle mainBundle] bundleIdentifier] ?: @"TeXShop"; }
@interface TSEnginePathDiscovery : NSObject
+ (BOOL)shouldSearchOnFirstLaunch:(NSDictionary *)saved;
@end
@implementation TSEnginePathDiscovery
+ (BOOL)shouldSearchOnFirstLaunch:(NSDictionary *)saved { return NO; }
@end
@interface TSPreferences : NSObject
@property NSFont *documentFont;
@property NSDictionary *fontAttributes;
+ (instancetype)sharedInstance;
- (void)registerFactoryDefaults;
@end
@implementation TSPreferences
+ (instancetype)sharedInstance
{
    static TSPreferences *shared;
    if (!shared) { shared = [self new]; shared.documentFont = [NSFont userFontOfSize:12]; shared.fontAttributes = @{}; }
    return shared;
}
REGISTER
@end
@interface LaunchProbe : NSObject
@property BOOL shouldDiscoverEnginePaths;
@end
@implementation LaunchProbe
- (void)launch
{
    NSString *fileName;
    NSDictionary *factoryDefaults;
LAUNCH
    (void)fileName;
}
@end

static void Reset(NSDictionary *saved)
{
    TSMemoryDefaults *d = TSIsolatedAppKitDefaults;
    d.values = [NSMutableDictionary new];
    d.fallbacks = [NSMutableDictionary new];
    d.persistentValues = [NSMutableDictionary new];
    if (saved.count)
        [d setPersistentDomain:saved forName:TSPreferencesDomainName()];
}

static NSInteger Launch(NSDictionary *saved)
{
    Reset(saved);
    [[LaunchProbe new] launch];
    return [SUD integerForKey:FindMethodKey];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *path = @"/Library/TeX/texbin";
        NSDictionary *both = @{@"TSHasBeenUsed": @"YES", @"TetexBinPath": path, @"Mine": @"kept"};
        NSMutableDictionary *(^with)(NSDictionary *, NSDictionary *) = ^NSMutableDictionary *(NSDictionary *a, NSDictionary *b) {
            NSMutableDictionary *m = [a mutableCopy]; [m addEntriesFromDictionary:b]; return m; };

        Check(Launch(@{}) == TSFindMethodAdvancedPanel, @"a new user starts with the Advanced Find panel");
        Check([[SUD persistentDomainForName:TSPreferencesDomainName()][FindMethodKey] integerValue] == 3, @"and it is stored, from FactoryDefaults.plist");
        Check(Launch(both) == TSFindMethodFindBar, @"an earlier user who never chose keeps the find bar");
        Check([[SUD persistentDomainForName:TSPreferencesDomainName()][FindMethodKey] integerValue] == 1, @"the find bar is written for them, not only registered");
        Check([[SUD stringForKey:@"Mine"] isEqualToString:@"kept"], @"the rest of an earlier user's settings is kept");
        for (NSNumber *method in @[@0, @1, @2, @3, @"2", @"3"])
            Check(Launch(with(both, @{FindMethodKey: method})) == [method integerValue],
                  [NSString stringWithFormat:@"an earlier user's choice %@ stays", method]);
        Check(Launch(@{@"TSHasBeenUsed": @"YES", @"Mine": @"x"}) == 3 && [SUD objectForKey:@"Mine"] == nil, @"TSHasBeenUsed alone: everything reset, the Advanced Find panel");
        Check(Launch(@{@"TetexBinPath": path}) == 3, @"TetexBinPath alone: reset, the Advanced Find panel");
        Check(Launch(@{@"TSHasBeenUsed": @"NO", @"TetexBinPath": path}) == 3, @"TSHasBeenUsed=NO stored: reset");
        Check(Launch(@{@"TSHasBeenUsed": @NO, @"TetexBinPath": path, FindMethodKey: @1}) == 3, @"TSHasBeenUsed=NO (a boolean) stored: reset");
        Check(Launch(@{@"TSHasBeenUsed": @"YES", FindMethodKey: @2}) == 3, @"one mark and OgreKit chosen: the whole reset gives the Advanced Find panel");
        Check(Launch(@{@"TetexBinPath": path, FindMethodKey: @"2"}) == 3, @"the other mark and OgreKit chosen: reset as well");

        // An explicit reset to the factory settings
        Launch(with(both, @{FindMethodKey: @1}));
        [[TSPreferences sharedInstance] registerFactoryDefaults];
        Check([SUD integerForKey:FindMethodKey] == 3, @"an explicit reset gives the Advanced Find panel");

        // Every shipped profile keeps the find method and the panel's own settings
        NSDictionary *factory = [NSDictionary dictionaryWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"FactoryDefaults" withExtension:@"plist" subdirectory:@"Defaults"]];
        NSData *font = [NSArchiver archivedDataWithRootObject:[NSFont userFontOfSize:12]];
        NSArray<NSString *> *profiles = [[NSBundle.mainBundle pathsForResourcesOfType:@"plist" inDirectory:@"Profiles"] sortedArrayUsingSelector:@selector(compare:)];
        Check(profiles.count == 8, @"the eight shipped profiles");
        for (NSString *profilePath in profiles)
            for (NSNumber *method in @[@0, @1, @2, @3]) {
                Launch(with(both, @{FindMethodKey: method, @"AdvancedFindOptions": @5, @"AdvancedFindHistory": @[@"x"], @"AdvancedFindHistoryLimit": @3}));
                TSPreferenceProfile *profile = [[TSPreferenceProfile alloc] initWithProfile:[NSDictionary dictionaryWithContentsOfFile:profilePath]
                                                                               documentFont:font registeredDefaults:factory];
                [profile applyToDefaults:SUD];
                Check([SUD integerForKey:FindMethodKey] == method.integerValue,
                      [NSString stringWithFormat:@"%@ keeps the find method %@", profilePath.lastPathComponent, method]);
                Check([SUD integerForKey:@"AdvancedFindOptions"] == 5 && [[SUD arrayForKey:@"AdvancedFindHistory"] isEqual:@[@"x"]]
                      && [SUD integerForKey:@"AdvancedFindHistoryLimit"] == 3, @"a profile keeps the panel's own settings");
            }
        if (failures)
            return 1;
        puts("PASS: the find method after launch (new, earlier, one mark, TSHasBeenUsed=NO, explicit reset) and after every profile");
    }
    return 0;
}
'''


def method(text, signature):
    start = text.index(signature)
    return text[start:text.index('\n}\n', start) + 3]


def run(texts):
    delegate = texts['TSAppDelegate.m']
    start = delegate.index('    NSDictionary *savedSettings = [SUD persistentDomainForName:')
    launch = delegate[start:delegate.index('    editorCanAddBrackets = [SUD')]
    register = method(texts['TSPreferences.m'], '- (void)registerFactoryDefaults\n')
    with tempfile.TemporaryDirectory(prefix='texshop-find-method-migration-') as tmp:
        tmp = Path(tmp)
        app = tmp / 'Probe.app/Contents'
        (app / 'MacOS').mkdir(parents=True)
        (app / 'Resources/Defaults').mkdir(parents=True)
        (app / 'Resources/Profiles').mkdir(parents=True)
        (app / 'Info.plist').write_text('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key>'
                                        '<string>org.texshop.test.FindMethodMigration</string><key>CFBundleExecutable</key><string>probe</string></dict></plist>')
        (app / 'Resources/Defaults/FactoryDefaults.plist').write_text(texts['FactoryDefaults.plist'])
        for profile in PROFILES:
            shutil.copy(profile, app / 'Resources/Profiles' / profile.name)
        (tmp / 'probe.m').write_text(PROGRAM.replace('REGISTER', register).replace('LAUNCH', launch))
        for name in ['TSPreferenceLaunch.m', 'TSPreferenceProfile.m']:
            (tmp / name).write_text(texts[name])
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wno-unused-parameter', '-Wno-deprecated-declarations', '-Wno-unused-variable',
                        *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa', str(tmp / 'probe.m'),
                        str(tmp / 'TSPreferenceLaunch.m'), str(tmp / 'TSPreferenceProfile.m'), str(source_file(root, 'globals.m')),
                        '-o', str(app / 'MacOS/probe')], check=True)
        return subprocess.run([str(app / 'MacOS/probe')], capture_output=True, text=True, timeout=60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    texts = {name: path.read_text(encoding='utf-8', errors='surrogateescape') for name, path in FILES.items()}
    assert texts['TSAppDelegate.m'].count('if (TSPreferencesNeedFactoryReset(SUD)) {') == 1, 'the launch decides with the shared function'
    result = run(texts)
    print(result.stdout + result.stderr, end='')
    if result.returncode:
        sys.exit('FAIL: the find method after launch')
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
