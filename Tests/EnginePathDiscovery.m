#import <Foundation/Foundation.h>
#import "TSEnginePathDiscovery.h"

static void check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static void script(NSString *directory, NSString *name, NSString *body) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [directory stringByAppendingPathComponent:name];
    [[@"#!/bin/sh\n" stringByAppendingString:body] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fm setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:path error:NULL];
}
static void tex(NSString *directory, NSString *version) {
    for (NSString *name in @[@"tex", @"latex", @"pdflatex", @"pdftex"]) script(directory, name, [NSString stringWithFormat:@"echo '%@'\n", version]);
}
int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *older = [root stringByAppendingPathComponent:@"old tex"];
    NSString *newer = [root stringByAppendingPathComponent:@"new tex"];
    NSString *alias = [root stringByAppendingPathComponent:@"alias"];
    NSString *gs1 = [root stringByAppendingPathComponent:@"gs1"];
    NSString *gs2 = [root stringByAppendingPathComponent:@"gs2"];
    tex(older, @"pdfTeX 3.141592653-2.6-1.40.27 (TeX Live 2025)");
    tex(newer, @"pdfTeX 3.141592653-2.6-1.40.28 (TeX Live 2026)");
    [fm createSymbolicLinkAtPath:alias withDestinationPath:newer error:NULL];
    script(gs1, @"gs", @"echo 10.9.0\n"); script(gs2, @"gs", @"echo 10.10.0\n");
    NSDictionary *found = [TSEnginePathDiscovery candidatesForPaths:@[older,gs1,newer,alias,gs2] currentTeX:older currentGhostscript:gs1];
    check([found[@"TeX"] count] == 2, @"one candidate per executable; all distinct versions retained");
    check([found[@"TeX"][0][@"path"] isEqual:newer], @"newest TeX Live beats older existing setting and path order");
    check([found[@"Ghostscript"][0][@"path"] isEqual:gs2], @"Ghostscript uses numeric version order");
    check([found[@"TeX"][1][@"path"] isEqual:older], @"older installation available for manual selection");
    check([found[@"TeX"][0][@"version"] isEqual:@"TeX Live 2026 (3.141592653-2.6-1.40.28)"], @"list includes parsed TeX Live and pdfTeX versions");
    check([found[@"Ghostscript"][0][@"version"] isEqual:@"10.10.0"], @"list includes parsed Ghostscript version");
    NSString *unknown = [root stringByAppendingPathComponent:@"2029/unknown"];
    tex(unknown, @"custom build without version information");
    script(unknown, @"gs", @"exit 0\n");
    NSString *sameYear = [root stringByAppendingPathComponent:@"same year"];
    tex(sameYear, @"pdfTeX 3.141592653-2.6-1.40.9 (TeX Live 2026)");
    found = [TSEnginePathDiscovery candidatesForPaths:@[sameYear, newer, older, gs1, gs2] currentTeX:unknown currentGhostscript:unknown];
    check([found[@"TeX"] count] == 4 && [found[@"Ghostscript"] count] == 3, @"unidentified versions remain selectable");
    check([found[@"TeX"][0][@"path"] isEqual:newer] && [found[@"TeX"][1][@"path"] isEqual:sameYear], @"same-year TeX sorted numerically by pdfTeX, not directory name");
    check([[found[@"TeX"] lastObject][@"path"] isEqual:unknown] && [[found[@"Ghostscript"] lastObject][@"path"] isEqual:unknown], @"unknown existing installations sort after all identified versions");
    check([[found[@"TeX"] lastObject][@"version"] length] == 0 && [[found[@"Ghostscript"] lastObject][@"version"] length] == 0, @"unknown versions supply no fabricated number");
    tex(unknown, @"TeX Live 2027");
    found = [TSEnginePathDiscovery candidatesForPaths:@[unknown,newer] currentTeX:@"" currentGhostscript:@""];
    check([found[@"TeX"][0][@"version"] isEqual:@"TeX Live 2027"], @"known TeX Live year without pdfTeX number displayed without empty parentheses");
    script(unknown, @"gs", @"printf '  11.0.0\\n'\n");
    found = [TSEnginePathDiscovery candidatesForPaths:@[gs2,unknown] currentTeX:@"" currentGhostscript:@""];
    check([found[@"Ghostscript"][0][@"version"] isEqual:@"11.0.0"], @"Ghostscript version parsing tolerates surrounding whitespace");
    // Banners as printed by real builds: TeX Live releases, the trunk between releases, and distributor suffixes.
    NSDictionary *(^banner)(NSString *) = ^(NSString *text) { return [TSEnginePathDiscovery texLiveReleaseInBanner:text]; };
    NSDictionary *r = banner(@"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2027/dev)\nkpathsea version 6.4.2\n");
    check([r[@"name"] isEqual:@"TeX Live 2027/dev"] && [r[@"year"] integerValue] == 2027 && [r[@"dev"] boolValue], @"trunk build recognized as development version");
    r = banner(@"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026)\n");
    check([r[@"name"] isEqual:@"TeX Live 2026"] && ![r[@"dev"] boolValue], @"release not taken for development version");
    r = banner(@"pdfTeX 3.141592653-2.6-1.40.26 (TeX Live 2025/dev/Debian)\n");
    check([r[@"name"] isEqual:@"TeX Live 2025/dev"] && [r[@"dev"] boolValue], @"development version keeps dev before distributor suffix, suffix not shown");
    for (NSString *text in @[@"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/Debian)", @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/MacPorts 2026.78225_0)",
                             @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/Homebrew)", @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/Arch Linux)",
                             @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/W32TeX)", @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/devuan)",
                             @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/dev-tools)", @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026/dev.1)"]) {
        r = banner(text);
        check([r[@"name"] isEqual:@"TeX Live 2026"] && ![r[@"dev"] boolValue], [@"distributor suffix is not a development version: " stringByAppendingString:text]);
    }
    r = banner(@"pdfTeX 3.141592653-2.6-1.40.29 (Web2C 2027/dev)\n");
    check([r[@"name"] isEqual:@"Web2C 2027/dev"] && [r[@"dev"] boolValue], @"build outside TeX Live keeps its own banner word");
    r = banner(@"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2027/dev) \n");
    check([r[@"dev"] boolValue], @"trailing space after the banner keeps dev");
    // Only the pdfTeX banner line is read: not a wrapper's words before it, nor lines after it.
    r = banner(@"Local wrapper for TeX Live 2030\npdfTeX 3.14 (TeX Live 2027/dev)\nkpathsea version 6.4\n");
    check([r[@"name"] isEqual:@"TeX Live 2027/dev"] && [r[@"year"] integerValue] == 2027, @"a year in the words before the banner is not read");
    check(banner(@"pdfTeX 3.14\nLocal wrapper compatible with TeX Live 2030\n") == nil, @"a year in the words after the banner is not read");
    check(banner(@"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2026)\nkpathsea version 6.4.2\nCopyright 2026 Han The Thanh (pdfTeX) et al.\n") != nil, @"the usual banner with the lines after it");
    check(banner(@"pdfTeX 3.141592653-2.6-1.40.29\n") == nil && banner(@"") == nil, @"banner without release gives no release");
    NSString *dev = [root stringByAppendingPathComponent:@"dev"];
    NSString *debianDev = [root stringByAppendingPathComponent:@"debian dev"];
    tex(dev, @"pdfTeX 3.141592653-2.6-1.40.29 (TeX Live 2027/dev)");
    tex(debianDev, @"pdfTeX 3.141592653-2.6-1.40.30 (TeX Live 2026/dev/Debian)");
    tex(unknown, @"custom build without version information");
    NSArray *(^defaults)(NSArray *) = ^(NSArray *list) {
        return [list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"default == YES"]];
    };
    found = [TSEnginePathDiscovery candidatesForPaths:@[debianDev, dev, older, newer, unknown, gs1, gs2] currentTeX:dev currentGhostscript:@""];
    NSArray *order = [found[@"TeX"] valueForKey:@"path"];
    check([order isEqual:@[dev, newer, debianDev, older, unknown]], @"newest first by year, development builds included; same-year release before its development build; unidentified last");
    check([found[@"TeX"][0][@"version"] isEqual:@"TeX Live 2027/dev (3.141592653-2.6-1.40.29)"], @"development version shown with banner wording");
    check([found[@"TeX"][2][@"version"] isEqual:@"TeX Live 2026/dev (3.141592653-2.6-1.40.30)"], @"same-year development version shown after release despite newer pdfTeX");
    check([defaults(found[@"TeX"]) count] == 1 && [found[@"TeX"][1][@"default"] boolValue], @"newest release preselected, not the newer development build");
    check([defaults(found[@"Ghostscript"]) count] == 1 && [found[@"Ghostscript"][0][@"default"] boolValue], @"newest Ghostscript preselected");
    found = [TSEnginePathDiscovery candidatesForPaths:@[debianDev, unknown, dev] currentTeX:@"" currentGhostscript:@""];
    check([[found[@"TeX"] valueForKey:@"path"] isEqual:@[dev, debianDev, unknown]] && [defaults(found[@"TeX"]) count] == 1 && [found[@"TeX"][0][@"default"] boolValue],
          @"without a release, the newest development build is preselected, not an unidentified one");
    NSString *wrapper = [root stringByAppendingPathComponent:@"wrapper"];
    for (NSString *name in @[@"tex", @"latex", @"pdflatex", @"pdftex"])
        script(wrapper, name, @"echo 'Local wrapper for TeX Live 2030 around pdfTeX 1.40.99'\necho 'pdfTeX 3.14 (TeX Live 2027/dev)'\n");
    found = [TSEnginePathDiscovery candidatesForPaths:@[wrapper, newer] currentTeX:@"" currentGhostscript:@""];
    check([[found[@"TeX"] valueForKey:@"path"] isEqual:@[wrapper, newer]] && [found[@"TeX"][1][@"default"] boolValue] &&
          [found[@"TeX"][0][@"version"] isEqual:@"TeX Live 2027/dev (3.14)"], @"a wrapper's words around the banner change neither the version nor the default");
    NSString *bare = [root stringByAppendingPathComponent:@"bare"];
    tex(bare, @"pdfTeX 3.141592653-2.6-1.40.30");
    found = [TSEnginePathDiscovery candidatesForPaths:@[bare, dev] currentTeX:@"" currentGhostscript:@""];
    check([[found[@"TeX"] valueForKey:@"path"] isEqual:@[dev, bare]] && [found[@"TeX"][0][@"default"] boolValue],
          @"a banner naming no release is not taken for a release");
    found = [TSEnginePathDiscovery candidatesForPaths:@[unknown] currentTeX:@"" currentGhostscript:@""];
    check([defaults(found[@"TeX"]) count] == 1 && [found[@"TeX"][0][@"default"] boolValue], @"an unidentified installation alone is preselected");
    NSString *partial = [root stringByAppendingPathComponent:@"partial"];
    script(partial,@"pdflatex",@"exit 0\n");
    check(![TSEnginePathDiscovery directory:partial containsPrograms:@[@"tex",@"latex",@"pdftex",@"pdflatex"]], @"partial TeX installation rejected");
    [fm setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:[newer stringByAppendingPathComponent:@"pdftex"] error:NULL];
    check(![TSEnginePathDiscovery directory:newer containsPrograms:@[@"pdftex"]], @"nonexecutable rejected");
    check(![TSEnginePathDiscovery directory:@"." containsPrograms:@[@"pdftex"]], @"relative search path rejected");
    NSString *hanging = [root stringByAppendingPathComponent:@"hang"];
    script(hanging,@"gs",@"exec /bin/sleep 30\n");
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    found = [TSEnginePathDiscovery candidatesForPaths:@[hanging] currentTeX:@"" currentGhostscript:@""];
    check([found[@"Ghostscript"] count] == 0 && NSProcessInfo.processInfo.systemUptime-start < 5, @"version timeout rejects hanging tool");
    script(hanging,@"gs",@"while :; do echo '0123456789012345678901234567890123456789012345678901234567890123456789'; done\n");
    found = [TSEnginePathDiscovery candidatesForPaths:@[hanging] currentTeX:@"" currentGhostscript:@""];
    check([found[@"Ghostscript"] count] == 0, @"oversized output rejected without pipe deadlock");
    script(hanging,@"gs",@"echo 99.0.0\ni=0; while [ $i -lt 2000 ]; do echo '0123456789012345678901234567890123456789012345678901234567890123456789'; i=$((i+1)); done\n");
    found = [TSEnginePathDiscovery candidatesForPaths:@[hanging] currentTeX:@"" currentGhostscript:@""];
    check([found[@"Ghostscript"] count] == 0, @"finite oversized output rejected independently of timeout");
    check([TSEnginePathDiscovery shouldSearchOnFirstLaunch:@{}], @"fresh user gets initial setup");
    check(![TSEnginePathDiscovery shouldSearchOnFirstLaunch:@{@"TSHasBeenUsed":@YES}], @"existing user not prompted");
    check(![TSEnginePathDiscovery shouldSearchOnFirstLaunch:@{@"TetexBinPath":older}], @"preconfigured path preserved on first launch");
    for (NSString *year in @[@"2025",@"2026",@"2027",@"current",@"123",@"20260"]) [fm createDirectoryAtPath:[root stringByAppendingPathComponent:year] withIntermediateDirectories:YES attributes:nil error:NULL];
    NSArray *paths = [TSEnginePathDiscovery texLivePathsUnderRoots:@[root]];
    check([paths[0] containsString:@"/2029/"], @"future TeX Live years discovered without hardcoded limit");
    check(![[paths componentsJoinedByString:@"\n"] containsString:@"/current/"], @"only year directories expanded");
    check(![[paths componentsJoinedByString:@"\n"] containsString:@"/123/"] && ![[paths componentsJoinedByString:@"\n"] containsString:@"/20260/"], @"year directories must contain exactly four digits");
    [fm removeItemAtPath:root error:NULL];
    NSLog(@"PASS: discovery, ranking, development versions, alternatives, duplicates, validation, first launch, bounded version probes");
} return 0; }
