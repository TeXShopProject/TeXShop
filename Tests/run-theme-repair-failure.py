#!/usr/bin/env python3
"""A theme that comes with TeXShop stays chosen when its file cannot be restored, and the next launch restores it.

When the launch takes a damaged copy of a bundled theme (Dracula here) away to the backups and cannot put TeXShop's
copy in its place (the copy cannot be read, the folder cannot be written, the disk is full), the theme in use must
not become Lite or Dark for good: the colors of that launch come from TeXShop's own copy (or Lite or Dark when even
that cannot be read), the setting keeps Dracula, and the next launch restores the file. A missing theme of the
user's own still gives way to Lite or Dark.

TSLibraryRepair.m is compiled as it is, with the production -[TSColorSupport initializeColors]. The copy inside
TeXShop is Resources/TeXShop/Themes and Resources/Themes of this tree, put where +[NSBundle mainBundle] points; the
home is a temporary folder (CFFIXED_USER_HOME) and preferences stay in memory. Nothing is shown on screen."""
from pathlib import Path
import os, shutil, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
colors_source = source_file(root, 'TSColorSupport.m').read_text(encoding='utf-8')
initialize = method(colors_source, '- (void)initializeColors\n{')
fragments = [('complete method:initializeColors', colors_source, initialize)]

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <sys/stat.h>
#import "TestAppKitIsolation.h"
#import "TSLibraryRepair.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
#define SUD TSIsolatedAppKitDefaults
static NSString *DefaultLiteThemeKey = @"DefaultLiteTheme", *DefaultDarkThemeKey = @"DefaultDarkTheme";
static NSString *ColorPath = @"~/Library/TeXShop/Themes";
static NSDictionary *liteColors, *darkColors;
static NSString *Resources;
static NSString *TestResourcePath(id self, SEL _cmd) { return Resources; }
static NSString *TestPathForResource(id self, SEL _cmd, NSString *name, NSString *type, NSString *folder)
{
    NSString *path = [[[Resources stringByAppendingPathComponent:folder] stringByAppendingPathComponent:name] stringByAppendingPathExtension:type];
    return [NSFileManager.defaultManager fileExistsAtPath:path] ? path : nil;
}
@interface Colors : NSObject
@end
@implementation Colors
// The Lite and Dark themes are in the folder (TSColorSupport restores them first).
- (void)checkAndRestoreDefaults {}
INITIALIZE
@end

static NSString *Home(NSString *name) { return [[@"~/Library/TeXShop/Themes" stringByExpandingTildeInPath] stringByAppendingPathComponent:name]; }
static NSDictionary *Read(NSString *path) { return [NSDictionary dictionaryWithContentsOfFile:path]; }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    Resources = @(argv[1]);
    method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(resourcePath)), (IMP)TestResourcePath);
    method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(pathForResource:ofType:inDirectory:)), (IMP)TestPathForResource);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *bundled = TSLibraryBundledPath(@"Themes/Dracula.plist"), *reserveLite = TestPathForResource(nil, NULL, @"LiteTheme", @"plist", @"Themes");
    REQUIRE(bundled != nil && reserveLite != nil);
    NSDictionary *dracula = Read(bundled), *lite = Read(reserveLite);
    REQUIRE(dracula.count > 10 && lite.count > 10 && ![dracula isEqual:lite]);
    [fm createDirectoryAtPath:Home(@"") withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSString *name in @[@"LiteTheme.plist", @"DarkTheme.plist"])
        REQUIRE([fm copyItemAtPath:[[Resources stringByAppendingPathComponent:@"Themes"] stringByAppendingPathComponent:name] toPath:Home(name) error:NULL]);
    Colors *colors = [Colors new];
    [SUD setObject:@"Dracula" forKey:DefaultLiteThemeKey];
    [SUD setObject:@"DarkTheme" forKey:DefaultDarkThemeKey];

    // A damaged Dracula, and TeXShop's copy cannot be read: the launch takes the damaged file away and cannot put
    // the copy in its place.
    REQUIRE([[@"damaged" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:Home(@"Dracula.plist") atomically:YES]);
    REQUIRE([fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-3600]} ofItemAtPath:Home(@"Dracula.plist") error:NULL]);
    chmod(bundled.fileSystemRepresentation, 0);
    TSLibraryRepairAll();
    REQUIRE(![fm fileExistsAtPath:Home(@"Dracula.plist")]);
    [colors initializeColors];
    REQUIRE([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Dracula"]);
    REQUIRE([liteColors isEqual:lite]);
    printf("PASS: a bundled theme whose copy cannot be read stays chosen, and the launch draws with Lite\n");

    // The next launch, with TeXShop's copy readable: the file comes back and is used.
    chmod(bundled.fileSystemRepresentation, 0644);
    TSLibraryRepairAll();
    REQUIRE([Read(Home(@"Dracula.plist")) isEqual:dracula]);
    [colors initializeColors];
    REQUIRE([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Dracula"] && [liteColors isEqual:dracula]);
    printf("PASS: the next launch restores it\n");

    // The folder cannot be written: TeXShop's copy is read, and the theme stays chosen.
    REQUIRE([fm removeItemAtPath:Home(@"Dracula.plist") error:NULL]);
    chmod(Home(@"").fileSystemRepresentation, 0555);
    [colors initializeColors];
    chmod(Home(@"").fileSystemRepresentation, 0755);
    REQUIRE(![fm fileExistsAtPath:Home(@"Dracula.plist")]);
    REQUIRE([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Dracula"] && [liteColors isEqual:dracula]);
    printf("PASS: a bundled theme that cannot be written back is read from TeXShop's copy and stays chosen\n");

    // A missing theme of the user's own gives way to Dark, as before.
    [SUD setObject:@"Mine" forKey:DefaultDarkThemeKey];
    [colors initializeColors];
    REQUIRE([[SUD stringForKey:DefaultDarkThemeKey] isEqual:@"DarkTheme"] && [darkColors isEqual:Read(Home(@"DarkTheme.plist"))]);
    printf("PASS: a missing theme of the user's own gives way to Dark\n");
} return 0; }
'''


def run(initialize_text, label):
    with tempfile.TemporaryDirectory(prefix='texshop-theme-repair-failure-') as folder:
        work = Path(folder)
        resources = work / 'Resources'
        (resources / 'TeXShop').mkdir(parents=True)
        shutil.copytree(root / 'Resources/TeXShop/Themes', resources / 'TeXShop/Themes')
        shutil.copytree(root / 'Resources/Themes', resources / 'Themes')
        program = PROGRAM.replace('INITIALIZE', initialize_text)
        (work / 'probe.m').write_text(program, encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(work / 'probe.m'), str(source_file(root, 'TSLibraryRepair.m')), '-o', str(work / 'probe')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        home = work / 'home'
        (home / 'Library/Preferences').mkdir(parents=True)
        env = dict(os.environ, CFFIXED_USER_HOME=str(home), HOME=str(home))
        try:
            return subprocess.run([str(work / 'probe'), str(resources)], capture_output=True, text=True, timeout=60, env=env)
        finally:
            for path in (resources / 'TeXShop/Themes/Dracula.plist', home / 'Library/TeXShop/Themes'):
                if path.exists():
                    os.chmod(path, 0o755)


result = run(initialize, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: a bundled theme that could not be restored is no longer chosen')
if '--mutations' in sys.argv:
    mutations = {
        'switches to Lite': ('        if (bundledLite != nil)\n            liteThemePath = bundledLite;\n        else {', '        {'),
        'keeps a missing theme of the user\'s own': ('            [SUD setObject: @"DarkTheme" forKey: DefaultDarkThemeKey];\n', ''),
    }
    for name, (before, after) in mutations.items():
        assert initialize.count(before) == 1, name
        r = run(initialize.replace(before, after), name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, [l for l in r.stderr.splitlines() if 'FAIL' in l][-1])
print('PASS: bundled themes stay chosen when they cannot be restored, and come back at the next launch')
