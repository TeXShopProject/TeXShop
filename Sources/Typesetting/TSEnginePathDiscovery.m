#import "TSEnginePathDiscovery.h"
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>

@implementation TSEnginePathDiscovery
+ (BOOL)shouldSearchOnFirstLaunch:(NSDictionary *)settings
{
    return ![settings[@"TSHasBeenUsed"] boolValue] && !settings[@"TetexBinPath"] && !settings[@"GSBinPath"];
}

+ (NSArray<NSString *> *)texLivePathsUnderRoots:(NSArray<NSString *> *)roots
{
    NSMutableArray *paths = [NSMutableArray array];
#if defined(__arm64__)
    NSArray *platforms = @[@"universal-darwin", @"arm64-darwin", @"x86_64-darwin", @"x86_64-darwinlegacy"];
#else
    NSArray *platforms = @[@"universal-darwin", @"x86_64-darwin", @"x86_64-darwinlegacy"];
#endif
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        NSArray *years = [[fm contentsOfDirectoryAtPath:root error:NULL] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [b compare:a options:NSNumericSearch];
        }];
        for (NSString *year in years) {
            if (year.length != 4 || [year rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) continue;
            for (NSString *platform in platforms) {
                [paths addObject:[[[root stringByAppendingPathComponent:year] stringByAppendingPathComponent:@"bin"] stringByAppendingPathComponent:platform]];
            }
        }
    }
    return paths;
}

+ (NSArray<NSString *> *)systemSearchPaths
{
    NSMutableOrderedSet *paths = [NSMutableOrderedSet orderedSet];
    void (^add)(NSString *) = ^(NSString *path) {
        NSString *clean = [[path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByExpandingTildeInPath];
        // Never search the working directory through empty or relative PATH entries.
        if (clean.isAbsolutePath) [paths addObject:clean.stringByStandardizingPath];
    };
    // Read path_helper's inputs directly, without launching a shell or user startup scripts.
    NSMutableArray *configFiles = [NSMutableArray arrayWithObject:@"/etc/paths"];
    NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/etc/paths.d" error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) [configFiles addObject:[@"/etc/paths.d" stringByAppendingPathComponent:name]];
    for (NSString *file in configFiles) {
        NSString *contents = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
        for (NSString *line in [contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) add(line);
    }
    for (NSString *path in [NSProcessInfo.processInfo.environment[@"PATH"] componentsSeparatedByString:@":"]) add(path);
    for (NSString *path in @[@"/Library/TeX/texbin", @"/usr/texbin", @"/Applications/TeXLive/Library/mactexaddons/bin"]) add(path);
    NSArray *roots = @[@"/Applications/TeXLive", @"/Applications/TeXLive/Library/texlive", @"/Applications/TeXLive/texlive", @"/usr/local/texlive", @"/opt/texlive"];
    for (NSString *path in [self texLivePathsUnderRoots:roots]) add(path);
    for (NSString *path in @[@"/Applications/UpTeX.app/Contents/Resources/TEX/texbin", @"/Applications/UpTeX.app/Contents/Resources/texbin", @"/Applications/UpTeX.app/teTeX/bin", @"/Applications/pTeX.app/teTeX/bin", @"/usr/local/teTeX/bin", @"/opt/homebrew/bin", @"/usr/local/bin", @"/opt/local/bin", @"/sw/bin"]) add(path);
    return paths.array;
}

+ (BOOL)directory:(NSString *)directory containsPrograms:(NSArray<NSString *> *)programs
{
    NSString *expanded = directory.stringByExpandingTildeInPath;
    if (!expanded.isAbsolutePath) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in programs) {
        NSString *file = [expanded stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:file isDirectory:&isDirectory] || isDirectory || ![fm isExecutableFileAtPath:file]) return NO;
    }
    return YES;
}

// Called on a worker queue. Limit both runtime and output of version probes.
+ (NSString *)versionOutputForProgram:(NSString *)program
{
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:program];
    task.arguments = @[@"--version"];
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return nil;
    int fd = pipe.fileHandleForReading.fileDescriptor;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    NSMutableData *data = [NSMutableData data];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 2.0;
    BOOL failed = NO;
    for (;;) {
        // Check before draining: output written just before exit must also be read.
        BOOL exited = !task.running;
        char buffer[4096];
        ssize_t count;
        while ((count = read(fd, buffer, sizeof(buffer))) > 0) {
            if (data.length + count > 65536) { failed = YES; break; }
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        if (failed || NSProcessInfo.processInfo.systemUptime > deadline) { failed = YES; break; }
        if (exited) break;
        [NSThread sleepForTimeInterval:0.01];
    }
    if (task.running) kill(task.processIdentifier, SIGKILL);
    [task waitUntilExit];
    [pipe.fileHandleForReading closeFile];
    [pipe.fileHandleForWriting closeFile];
    if (failed || task.terminationStatus != 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (NSString *)capture:(NSString *)pattern in:(NSString *)text
{
    NSTextCheckingResult *match = [[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL] firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match ? [text substringWithRange:[match rangeAtIndex:1]] : @"";
}

+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)candidatesForPaths:(NSArray<NSString *> *)paths currentTeX:(NSString *)texPath currentGhostscript:(NSString *)gsPath
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *keys = @[@"TeX", @"Ghostscript"];
    NSArray *current = @[texPath, gsPath];
    NSArray *programs = @[@[@"tex", @"latex", @"pdftex", @"pdflatex"], @[@"gs"]];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSMutableArray *matches = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        // For equivalent installations, prefer the stable MacTeX entry point.
        NSMutableOrderedSet *candidates = [NSMutableOrderedSet orderedSetWithArray:paths];
        [candidates removeObject:current[i]];
        [candidates insertObject:current[i] atIndex:0];
        if ([candidates containsObject:@"/Library/TeX/texbin"]) {
            [candidates removeObject:@"/Library/TeX/texbin"];
            [candidates insertObject:@"/Library/TeX/texbin" atIndex:0];
        }
        for (NSString *path in candidates) {
            if (![self directory:path containsPrograms:programs[i]]) continue;
            NSString *directory = path.stringByExpandingTildeInPath.stringByStandardizingPath;
            NSString *program = [directory stringByAppendingPathComponent:i == 0 ? @"pdftex" : @"gs"];
            NSString *identity = program.stringByResolvingSymlinksInPath;
            if ([seen containsObject:identity]) continue;
            NSString *output = [self versionOutputForProgram:program];
            if (!output) continue;
            [seen addObject:identity];
            NSString *version = [self capture:i == 0 ? @"pdfTeX ([0-9][0-9.\\-]+)" : @"^\\s*([0-9]+(?:\\.[0-9]+)+)" in:output];
            NSInteger year = i == 0 ? [[self capture:@"TeX Live ([0-9]{4})" in:output] integerValue] : 0;
            NSString *displayVersion = version;
            if (year > 0) {
                displayVersion = [NSString stringWithFormat:@"TeX Live %ld", (long)year];
                if (version.length) displayVersion = [displayVersion stringByAppendingFormat:@" (%@)", version];
            }
            [matches addObject:@{@"path": directory, @"version": displayVersion,
                                 @"number": version, @"year": @(year), @"order": @(matches.count)}];
        }
        [matches sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            // Unidentified versions remain selectable, after every identified version.
            BOOL aKnown = [a[@"version"] length] > 0, bKnown = [b[@"version"] length] > 0;
            if (aKnown != bKnown) return aKnown ? NSOrderedAscending : NSOrderedDescending;
            NSComparisonResult year = [b[@"year"] compare:a[@"year"]];
            if (year != NSOrderedSame) return year;
            NSComparisonResult version = [b[@"number"] compare:a[@"number"] options:NSNumericSearch];
            return version != NSOrderedSame ? version : [a[@"order"] compare:b[@"order"]];
        }];
        result[keys[i]] = matches;
    }
    return result;
}
@end
