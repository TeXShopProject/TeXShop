// When ~/Library/TeXShop is refreshed from the application: once per display version, never per build.
// Everything happens in a temporary folder; the real ~/Library/TeXShop is not touched.
#import <Foundation/Foundation.h>
#import "TSLibraryVersion.h"

static int failures;
static void Check(BOOL condition, NSString *message) { if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }

static void Write(NSString *folder, NSString *text)
{
    [text writeToFile:[folder stringByAppendingPathComponent:@".Version"] atomically:YES encoding:NSASCIIStringEncoding error:NULL];
}

// One launch: refresh when needed and remember the version, as TSAppDelegate does.
static BOOL Launch(NSString *folder, NSString *applicationVersion)
{
    BOOL needs = TSLibraryNeedsUpdating(TSLibraryVersionInFolder(folder), applicationVersion);
    if (needs)
        Check(TSLibraryRecordVersion(folder, applicationVersion), @"The version can be written");
    return needs;
}

// One launch with the real bundled New folder, whose own .Version still says 5.59:
// TSAppDelegate removes New, copies the bundled one and then records its version.
static BOOL LaunchCopying(NSString *bundled, NSString *folder, NSString *applicationVersion)
{
    BOOL needs = TSLibraryNeedsUpdating(TSLibraryVersionInFolder(folder), applicationVersion);
    if (needs) {
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
        Check([NSFileManager.defaultManager copyItemAtPath:bundled toPath:folder error:NULL], @"The bundled New folder is copied");
        TSLibraryRecordVersion(folder, applicationVersion);
    }
    return needs;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TeXShop-LibraryVersion-%d", getpid()]];
        NSString *folder = [base stringByAppendingPathComponent:@"New"];
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];

        if (argc > 1) {
            NSString *bundled = @(argv[1]);
            NSString *copied = [base stringByAppendingPathComponent:@"Copied"];
            Check(LaunchCopying(bundled, copied, @"6.00 beta-1"), @"A first launch copies the bundled files");
            Check([TSLibraryVersionInFolder(copied) isEqual:@"6.00 beta-1"], @"The copied .Version is replaced by the running version");
            Check(!LaunchCopying(bundled, copied, @"6.00 beta-1"), @"The second launch copies nothing");
            [@"5.59\n" writeToFile:[copied stringByAppendingPathComponent:@".Version"] atomically:YES encoding:NSASCIIStringEncoding error:NULL];
            Check(LaunchCopying(bundled, copied, @"6.00 beta-1"), @"After 5.59, the first launch of 6.00 beta-1 copies");
            Check(!LaunchCopying(bundled, copied, @"6.00 beta-1"), @"... and the second launch copies nothing");
        } else {
            Check(NO, @"The bundled New folder is given");
        }

        Check(TSLibraryVersionInFolder(folder) == nil, @"No .Version reads as nothing");
        Check(Launch(folder, @"6.00 beta-1"), @"Without a .Version the files are copied");
        Check([TSLibraryVersionInFolder(folder) isEqual:@"6.00 beta-1"], @"The display version is remembered");
        NSString *written = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@".Version"] encoding:NSASCIIStringEncoding error:NULL];
        Check([written isEqual:@"6.00 beta-1\n"], @".Version holds the display version and a newline, like the earlier files");
        Check(written.doubleValue == 6.0, @"Earlier versions read what is written as the number 6.0");
        Check(!Launch(folder, @"6.00 beta-1"), @"The next launch of the same version copies nothing");

        // 5.59 and the 5.60 betas shipped New/.Version with 5.59 in it.
        Write(folder, @"5.59\n");
        Check(Launch(folder, @"6.00 beta-1"), @"Coming from 5.59 or a 5.60 beta, 6.00 beta-1 copies once");
        Check(!Launch(folder, @"6.00 beta-1"), @"... and only once");
        Write(folder, @"5.6");
        Check(Launch(folder, @"6.00 beta-1"), @"Coming from a .Version of 5.6, it copies once");
        Check(!Launch(folder, @"6.00 beta-1"), @"... and only once");

        Check(Launch(folder, @"6.00 beta-2"), @"The next beta of the same number copies");
        Check(!Launch(folder, @"6.00 beta-2"), @"... once");
        Check(Launch(folder, @"6.00"), @"The release after its betas copies");
        Check(!Launch(folder, @"6.00"), @"... once");
        Check(Launch(folder, @"6.01"), @"A later version copies");
        Check(!Launch(folder, @"6.00"), @"An earlier number does not copy over a later one");
        Check([TSLibraryVersionInFolder(folder) isEqual:@"6.01"], @"... and leaves the later version in .Version");

        Write(folder, @"6.00 beta-2\n");
        Check(!Launch(folder, @"6.00 beta-1"), @"An earlier beta does not copy over a later one");
        Check(!TSLibraryNeedsUpdating(@"6.00", @"6.00 beta-2"), @"A beta does not copy over its release");
        Check(!TSLibraryNeedsUpdating(@"6.00", @"6.00.0"), @"6.00.0 is 6.00");
        Check(TSLibraryNeedsUpdating(@"6.00", @"6.00.1"), @"6.00.1 is later than 6.00");
        Check(TSLibraryNeedsUpdating(@"5.60 beta-9", @"5.60 beta-10"), @"Betas are ordered by number, not text");
        Check(TSLibraryNeedsUpdating(@"5.60b10", @"5.60 beta-11"), @"5.60b10 is the same kind of version as 5.60 beta-10");
        Check(!TSLibraryNeedsUpdating(@"5.6", @"5.60"), @"5.6 is 5.60");
        // Release candidates come after the betas and before the release.
        Check(TSLibraryNeedsUpdating(@"6.00 beta-9", @"6.00 RC1"), @"6.00 RC1 is later than 6.00 beta-9");
        Check(TSLibraryNeedsUpdating(@"6.00 beta-12", @"6.00 RC1"), @"6.00 RC1 is later than any beta");
        Check(!TSLibraryNeedsUpdating(@"6.00 RC1", @"6.00 beta-9"), @"A beta does not copy over a release candidate");
        Check(TSLibraryNeedsUpdating(@"6.00 RC1", @"6.00 RC2"), @"6.00 RC2 is later than 6.00 RC1");
        Check(TSLibraryNeedsUpdating(@"6.00 RC9", @"6.00 RC10"), @"Release candidates are ordered by number, not text");
        Check(TSLibraryNeedsUpdating(@"6.00 RC2", @"6.00"), @"The release is later than its release candidates");
        Check(!TSLibraryNeedsUpdating(@"6.00", @"6.00 RC2"), @"A release candidate does not copy over its release");
        Check(!TSLibraryNeedsUpdating(@"6.00 RC1", @"6.00 RC1"), @"6.00 RC1 again copies nothing");
        Check(TSLibraryNeedsUpdating(@"6.00 RC1", @"6.00.1"), @"6.00.1 is later than 6.00 RC1");
        // TetsuTeXShop versions.
        Check(!TSLibraryNeedsUpdating(@"5.60b10.1", @"5.60b10.1"), @"5.60b10.1 again copies nothing");
        Check(TSLibraryNeedsUpdating(@"5.60b10.1", @"5.60b11.1"), @"5.60b11.1 is later than 5.60b10.1");
        Check(TSLibraryNeedsUpdating(@"5.60b10.1", @"5.60b10.2"), @"5.60b10.2 is later than 5.60b10.1");
        Check(TSLibraryNeedsUpdating(@"5.58.1", @"5.58.2"), @"5.58.2 is later than 5.58.1");
        Check(TSLibraryNeedsUpdating(@"5.60b10.1", @"6.00b1.1"), @"6.00b1.1 is later than 5.60b10.1");
        Check(TSLibraryNeedsUpdating(@"6.00b9.1", @"6.00rc1.1"), @"6.00rc1.1 is later than 6.00b9.1");
        Check(TSLibraryNeedsUpdating(@"6.00rc1.1", @"6.00rc1.2"), @"6.00rc1.2 is later than 6.00rc1.1");
        Check(!TSLibraryNeedsUpdating(@"6.00rc1.1", @"6.00b9.1"), @"6.00b9.1 does not copy over 6.00rc1.1");
        Check(TSLibraryNeedsUpdating(@"6.00rc1.1", @"6.00.1"), @"6.00.1 is later than 6.00rc1.1");
        // Another form of the same number copies once.
        Check(TSLibraryNeedsUpdating(@"6.00 rc-1", @"6.00"), @"An unknown form of the same number copies");
        Check(!TSLibraryNeedsUpdating(@"6.00 rc-1", @"6.00 rc-1"), @"... but not again");

        Write(folder, @"5.59\n");
        Check(!Launch(folder, @"5.59"), @"5.59 over its own files copies nothing");
        Check(!TSLibraryNeedsUpdating(@"6.00 beta-1", @"5.59"), @"5.59 after 6.00 beta-1 copies nothing");
        Check(!TSLibraryNeedsUpdating(@"6.00 beta-1", nil), @"Without a display version nothing is copied");
        Check(TSLibraryNeedsUpdating(@"garbage", @"6.00 beta-1"), @"An unreadable .Version copies");

        [fm removeItemAtPath:base error:NULL];
    }
    if (failures) { fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    puts("PASS library version");
    return 0;
}
