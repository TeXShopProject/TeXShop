#!/usr/bin/env python3
"""The find method after launch: the production launch branch of TSAppDelegate and
-[TSPreferences registerFactoryDefaults] (its setPersistentDomain:) are taken verbatim and run on in-memory defaults
with the shipped FactoryDefaults.plist. At the first launch of 6.00 every earlier user moves to the Advanced Find
panel, once; those who came from OgreKit write replacements the OgreKit way unless they chose a way. The final find
method, the replacement way as the panel reads it (TSAdvancedFindSettings) and the mark of the switch are checked for
every kind of user, for a second launch after choosing again, for an explicit reset and for every shipped profile.
Nothing is displayed.

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
    'TSAdvancedFindSettings.h': source_file(root, 'TSAdvancedFindSettings.h'),
    'TSAdvancedFindSettings.m': source_file(root, 'TSAdvancedFindSettings.m'),
    'FactoryDefaults.plist': root / 'Resources/Defaults/FactoryDefaults.plist',
}
PROFILES = sorted((root / 'Resources/Defaults').glob('Defaults_*.plist'))
FACTORY_MARK = '\t<key>FindMethodSwitchedToAdvancedFind</key>\n\t<string>YES</string>\n'

MUTATIONS = {
    'a new user needs both marks missing': ('TSPreferenceLaunch.m',
        '[defaults boolForKey:TSHasBeenUsedKey] == NO || [defaults objectForKey:TetexBinPath] == nil',
        '[defaults boolForKey:TSHasBeenUsedKey] == NO && [defaults objectForKey:TetexBinPath] == nil'),
    'the switch keeps the old method (the plan of 11-12)': ('TSPreferenceLaunch.m',
        '    [defaults setInteger:TSFindMethodAdvancedPanel forKey:FindMethodKey];\n',
        '    if (savedSettings[FindMethodKey] == nil) [defaults setInteger:TSFindMethodFindBar forKey:FindMethodKey];\n'),
    'the switch runs at every launch': ('TSPreferenceLaunch.m',
        '    if ([TSSavedScalar(savedSettings, FindMethodSwitchedToAdvancedFindKey) boolValue])\n        return;\n', ''),
    'the mark of the switch is not written': ('TSPreferenceLaunch.m',
        '    [defaults setBool:YES forKey:FindMethodSwitchedToAdvancedFindKey];\n', ''),
    'the factory defaults lack the mark': ('FactoryDefaults.plist', FACTORY_MARK, ''),
    'OgreKit users get the ICU way': ('TSPreferenceLaunch.m',
        '        [defaults setInteger:TSRegexReplacementSyntaxOgreKit forKey:TSAdvancedFindReplacementSyntaxKey];\n', '        ;\n'),
    'every earlier user gets the OgreKit way': ('TSPreferenceLaunch.m',
        'integerValue] == TSFindMethodOgreKit;', 'integerValue] == TSFindMethodOgreKit || YES;'),
    'a chosen replacement way is replaced': ('TSPreferenceLaunch.m',
        'if (fromOgreKit && savedSettings[TSAdvancedFindReplacementSyntaxKey] == nil)', 'if (fromOgreKit)'),
    'the switch writes a key the panel does not read': ('TSPreferenceLaunch.m',
        'forKey:TSAdvancedFindReplacementSyntaxKey];', 'forKey:@"AdvancedFindReplaceSyntax"];'),
    # The experiment's own judgement (either mark makes an earlier user), written after the reset
    'the migration judges for itself, after the reset': ('TSAppDelegate.m',
        '\t\tTSPreferencesMigrateEarlierUser(SUD, savedSettings);\n', '',
        '[SUD registerDefaults:factoryDefaults];\n\t}\n',
        '[SUD registerDefaults:factoryDefaults];\n\t}\n\tif ([savedSettings[@"TSHasBeenUsed"] boolValue] || savedSettings[@"TetexBinPath"] != nil)\n\t\tTSPreferencesMigrateEarlierUser(SUD, savedSettings);\n'),
    'new users keep the find bar': ('FactoryDefaults.plist', '<key>FindMethod</key>\n\t<string>3</string>', '<key>FindMethod</key>\n\t<string>1</string>'),
    'a profile sets the find method': ('TSPreferenceProfile.m', '        FindMethodKey, //', '        //'),
    'a profile drops the mark of the switch': ('TSPreferenceProfile.m', '        FindMethodSwitchedToAdvancedFindKey, //', '        //'),
    'a profile resets the panel\'s own settings': ('TSPreferenceProfile.m', '        [key hasPrefix:@"AdvancedFind"]) return YES;', '        NO) return YES;'),
}

PROGRAM = r"""
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "globals.h"
#import "TSPreferenceLaunch.h"
#import "TSPreferenceProfile.h"
#import "TSFindInterface.h"
#import "TSAdvancedFindSettings.h"
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

static NSDictionary *Saved(void) { return [SUD persistentDomainForName:TSPreferencesDomainName()] ?: @{}; }

/// The find method after a launch with these saved settings.
static NSInteger Launch(NSDictionary *saved)
{
    Reset(saved);
    [[LaunchProbe new] launch];
    return [SUD integerForKey:FindMethodKey];
}

/// Quit and launch again with what is saved now.
static NSInteger Relaunch(void) { return Launch(Saved()); }

/// The way of writing a replacement, as the Advanced Find panel reads it.
static TSRegexReplacementSyntax Syntax(void) { return [[TSAdvancedFindSettings alloc] initWithDefaults:SUD findPasteboard:nil].replacementSyntax; }

/// The find method and the mark are stored, not only registered.
static BOOL Stored(NSInteger method) { return [Saved()[FindMethodKey] integerValue] == method && [Saved()[@"FindMethodSwitchedToAdvancedFind"] boolValue]; }

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *path = @"/Library/TeX/texbin";
        NSDictionary *both = @{@"TSHasBeenUsed": @"YES", @"TetexBinPath": path, @"Mine": @"kept"};
        NSMutableDictionary *(^with)(NSDictionary *, NSDictionary *) = ^NSMutableDictionary *(NSDictionary *a, NSDictionary *b) {
            NSMutableDictionary *m = [a mutableCopy]; [m addEntriesFromDictionary:b]; return m; };
        TSRegexReplacementSyntax ICU = TSRegexReplacementSyntaxICU, Ogre = TSRegexReplacementSyntaxOgreKit;

        // A new user
        Check(Launch(@{}) == TSFindMethodAdvancedPanel && Syntax() == ICU, @"a new user starts with the Advanced Find panel and the ICU way");
        Check(Stored(3), @"and both come from FactoryDefaults.plist, with the mark of the switch");
        [SUD setInteger:TSFindMethodOgreKit forKey:FindMethodKey];
        Check(Relaunch() == TSFindMethodOgreKit && Syntax() == ICU, @"a new user who then chooses OgreKit keeps it at the next launch");

        // Earlier users: whatever they had, the Advanced Find panel, once
        Check(Launch(both) == TSFindMethodAdvancedPanel && Syntax() == ICU, @"an earlier user who never chose moves to the Advanced Find panel, the ICU way");
        Check(Stored(3), @"the Advanced Find panel and the mark are written for them, not only registered");
        Check([[SUD stringForKey:@"Mine"] isEqualToString:@"kept"], @"the rest of an earlier user's settings is kept");
        for (id method in @[@0, @1, @"0", @"1", @3, @"3"]) {
            Check(Launch(with(both, @{FindMethodKey: method})) == 3 && Syntax() == ICU && Stored(3),
                  [NSString stringWithFormat:@"an earlier user of %@ moves to the Advanced Find panel, the ICU way", method]);
            Check(Saved()[@"AdvancedFindReplacementSyntax"] == nil, [NSString stringWithFormat:@"no way of replacing is written for %@", method]);
        }
        for (id method in @[@2, @"2"]) {
            Check(Launch(with(both, @{FindMethodKey: method})) == 3 && Syntax() == Ogre && Stored(3),
                  [NSString stringWithFormat:@"an OgreKit user (%@) moves to the Advanced Find panel, the OgreKit way", method]);
            Check([Saved()[@"AdvancedFindReplacementSyntax"] integerValue] == Ogre, @"the OgreKit way is written");
        }
        // Who already chose a way in the Advanced Find panel (a 6.00 trial or beta)
        for (id way in @[@0, @1, @"0"])
            for (id method in @[@2, @3, @1]) {
                Check(Launch(with(both, @{FindMethodKey: method, @"AdvancedFindReplacementSyntax": way})) == 3 && Syntax() == [way integerValue],
                      [NSString stringWithFormat:@"the chosen way %@ stays for an earlier user of %@", way, method]);
            }
        Check(Launch(with(both, @{FindMethodKey: @2, @"AdvancedFindOptions": @5, @"AdvancedFindHistory": @[@"x"]})) == 3 && Syntax() == Ogre
              && [SUD integerForKey:@"AdvancedFindOptions"] == 5, @"an OgreKit user who tried the panel without choosing a way: the OgreKit way, the panel's settings kept");

        // After the switch, a method chosen again stays at the next launches
        for (id before in @[@0, @1, @2, @3])
            for (NSNumber *chosen in @[@0, @1, @2]) {
                Launch(with(both, @{FindMethodKey: before}));
                [SUD setInteger:chosen.integerValue forKey:FindMethodKey];
                Check(Relaunch() == chosen.integerValue && Relaunch() == chosen.integerValue,
                      [NSString stringWithFormat:@"a user of %@ who chooses %@ after the switch keeps it", before, chosen]);
            }
        Launch(with(both, @{FindMethodKey: @2}));
        [SUD setInteger:ICU forKey:@"AdvancedFindReplacementSyntax"];
        Check(Relaunch() == 3 && Syntax() == ICU, @"an OgreKit user who chooses the ICU way after the switch keeps it");
        [SUD setInteger:TSFindMethodOgreKit forKey:FindMethodKey];
        Check(Relaunch() == 2 && Syntax() == ICU, @"and going back to OgreKit changes nothing else");
        Check(Launch(with(both, @{FindMethodKey: @2, @"FindMethodSwitchedToAdvancedFind": @YES})) == 2 && Syntax() == ICU,
              @"a stored mark (a boolean): no switch");
        Check(Launch(with(both, @{FindMethodKey: @"1", @"FindMethodSwitchedToAdvancedFind": @"YES"})) == 1, @"a stored mark (a string): no switch");
        Check(Launch(with(both, @{FindMethodKey: @1, @"FindMethodSwitchedToAdvancedFind": @"NO"})) == 3 && Stored(3), @"a mark of NO: the switch");

        // One mark only: the whole settings are reset, as before 6.00
        Check(Launch(@{@"TSHasBeenUsed": @"YES", @"Mine": @"x"}) == 3 && [SUD objectForKey:@"Mine"] == nil && Stored(3), @"TSHasBeenUsed alone: everything reset, the Advanced Find panel");
        Check(Launch(@{@"TetexBinPath": path}) == 3 && Stored(3), @"TetexBinPath alone: reset, the Advanced Find panel");
        Check(Launch(@{@"TSHasBeenUsed": @"NO", @"TetexBinPath": path}) == 3, @"TSHasBeenUsed=NO stored: reset");
        Check(Launch(@{@"TSHasBeenUsed": @NO, @"TetexBinPath": path, FindMethodKey: @1}) == 3, @"TSHasBeenUsed=NO (a boolean) stored: reset");
        Check(Launch(@{@"TSHasBeenUsed": @"YES", FindMethodKey: @2}) == 3 && Syntax() == ICU && Stored(3),
              @"one mark and OgreKit chosen: the whole reset gives the Advanced Find panel and the ICU way");
        Check(Launch(@{@"TetexBinPath": path, FindMethodKey: @"2"}) == 3 && Syntax() == ICU, @"the other mark and OgreKit chosen: reset as well");
        [SUD setInteger:TSFindMethodFindBar forKey:FindMethodKey];
        Check(Relaunch() == 1, @"after such a reset, a method chosen again stays");

        // An explicit reset to the factory settings
        Launch(with(both, @{FindMethodKey: @2}));
        [SUD setInteger:TSFindMethodOgreKit forKey:FindMethodKey];
        [[TSPreferences sharedInstance] registerFactoryDefaults];
        Check([SUD integerForKey:FindMethodKey] == 3 && Syntax() == ICU && Stored(3), @"an explicit reset gives the Advanced Find panel, the ICU way and the mark");
        [SUD setInteger:TSFindMethodOgreKit forKey:FindMethodKey];
        Check(Relaunch() == 2 && Syntax() == ICU, @"OgreKit chosen after a reset stays at the next launch");

        // Every shipped profile keeps the find method, the mark and the panel's own settings
        NSDictionary *factory = [NSDictionary dictionaryWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"FactoryDefaults" withExtension:@"plist" subdirectory:@"Defaults"]];
        NSData *font = [NSArchiver archivedDataWithRootObject:[NSFont userFontOfSize:12]];
        NSArray<NSString *> *profiles = [[NSBundle.mainBundle pathsForResourcesOfType:@"plist" inDirectory:@"Profiles"] sortedArrayUsingSelector:@selector(compare:)];
        Check(profiles.count == 8, @"the eight shipped profiles");
        for (NSString *profilePath in profiles)
            for (NSNumber *method in @[@0, @1, @2, @3]) {
                Launch(with(both, @{FindMethodKey: @2}));
                [SUD setInteger:method.integerValue forKey:FindMethodKey];
                [SUD setObject:@5 forKey:@"AdvancedFindOptions"];
                [SUD setObject:@[@"x"] forKey:@"AdvancedFindHistory"];
                [SUD setObject:@3 forKey:@"AdvancedFindHistoryLimit"];
                TSPreferenceProfile *profile = [[TSPreferenceProfile alloc] initWithProfile:[NSDictionary dictionaryWithContentsOfFile:profilePath]
                                                                               documentFont:font registeredDefaults:factory];
                [profile applyToDefaults:SUD];
                NSString *name = profilePath.lastPathComponent;
                Check([SUD integerForKey:FindMethodKey] == method.integerValue && Syntax() == Ogre,
                      [NSString stringWithFormat:@"%@ keeps the find method %@ and the way of replacing", name, method]);
                Check([SUD integerForKey:@"AdvancedFindOptions"] == 5 && [[SUD arrayForKey:@"AdvancedFindHistory"] isEqual:@[@"x"]]
                      && [SUD integerForKey:@"AdvancedFindHistoryLimit"] == 3, @"a profile keeps the panel's own settings");
                Check(Relaunch() == method.integerValue && Syntax() == Ogre,
                      [NSString stringWithFormat:@"after %@, the next launch keeps the find method %@", name, method]);
            }
        if (failures)
            return 1;
        puts("PASS: the find method and the way of replacing after launch (new, earlier of each method, chosen way, chosen again, one mark, explicit reset) and after every profile");
    }
    return 0;
}
"""


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
        for name in ['TSPreferenceLaunch.m', 'TSPreferenceProfile.m', 'TSAdvancedFindSettings.m', 'TSAdvancedFindSettings.h']:
            (tmp / name).write_text(texts[name])
        # The copied header comes first, so a mutated one is the one compiled.
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wno-unused-parameter', '-Wno-deprecated-declarations', '-Wno-unused-variable',
                        '-I', str(tmp), *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa', str(tmp / 'probe.m'),
                        str(tmp / 'TSPreferenceLaunch.m'), str(tmp / 'TSPreferenceProfile.m'), str(tmp / 'TSAdvancedFindSettings.m'),
                        str(source_file(root, 'TSRegexFindOptions.m')), str(source_file(root, 'globals.m')),
                        '-o', str(app / 'MacOS/probe')], check=True)
        return subprocess.run([str(app / 'MacOS/probe')], capture_output=True, text=True, timeout=60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    texts = {name: path.read_text(encoding='utf-8', errors='surrogateescape') for name, path in FILES.items()}
    assert texts['TSAppDelegate.m'].count('if (TSPreferencesNeedFactoryReset(SUD)) {') == 1, 'the launch decides with the shared function'
    assert texts['FactoryDefaults.plist'].count(FACTORY_MARK) == 1, 'the factory defaults carry the mark of the switch'
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
