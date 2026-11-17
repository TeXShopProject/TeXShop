#!/usr/bin/env python3
"""The settings files of ~/Library/TeXShop that TeXShop needs are restored from the copy inside TeXShop, file by
file and without any message, when they are missing or damaged; a damaged file is kept in ~/Library/TeXShop/Backups.

TSLibraryRepair.m is compiled as it is. The copy inside TeXShop is the real Resources/TeXShop (and Resources/Themes)
of this source tree, put where +[NSBundle mainBundle] resourcePath points (the only replacement here). The home is a
temporary folder (CFFIXED_USER_HOME). The production loadMacros of TSMacroMenuController runs verbatim on it, with
NSRunAlertPanel recording any alert, so that a damaged macros file shows nothing and the Macros menu gets macros.
Removing each rule must fail."""
from pathlib import Path
import os, shutil, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
repair_source = source_file(root, 'TSLibraryRepair.m').read_text(encoding='utf-8')
macros = source_file(root, 'TSMacroMenuController.m').read_text(encoding='utf-8', errors='surrogateescape')
colors = source_file(root, 'TSColorSupport.m').read_text(encoding='latin1')
fragments = [('loadMacros', macros, method(macros, '- (void)loadMacros')),
             ('colorArrayFromDictionary', colors, method(colors, '- (NSArray *) colorArrayFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey')),
             ('colorFromDictionary', colors, method(colors, '- (NSColor *) colorFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey')),
             ('colorAndAlphaFromDictionary', colors, method(colors, '- (NSColor *) colorAndAlphaFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey'))]

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSLibraryRepair.h"
static NSMutableArray<NSString *> *alerts;
static NSInteger RecordAlert(NSString *title, NSString *format, NSString *b1, NSString *b2, NSString *b3, ...) {
    [alerts addObject:[NSString stringWithFormat:@"%@|%@", title, format]]; return 1;
}
#define NSRunAlertPanel RecordAlert
static NSString *Resources;
static NSString *TestResourcePath(id self, SEL _cmd) { return Resources; }
NSString *MacrosPath = @"~/Library/TeXShop/Macros";
NSInteger g_macroType;
enum { TexEngine = 1, LatexEngine = 2, BibtexEngine, IndexEngine, MetapostEngine };
@interface Macros : NSObject
@property (retain) NSDictionary *macroDict;
@end
@implementation Macros
__LOAD_MACROS__
@end
// How TeXShop reads the colors of a theme (TSColorSupport), to check that every theme the check lets through reads.
@interface Colors : NSObject @end
@implementation Colors
__COLORS__
@end

static int failures;
static void check(BOOL ok, NSString *what) { if (!ok) { fprintf(stderr, "FAIL: %s\n", what.UTF8String); failures++; } }
static NSString *Library(NSString *relative) { return [[@"~/Library/TeXShop" stringByAppendingPathComponent:relative] stringByExpandingTildeInPath]; }
static NSData *Bundled(NSString *relative) { return [NSData dataWithContentsOfFile:TSLibraryBundledPath(relative)]; }
static NSData *Plist(id object) { return [NSPropertyListSerialization dataWithPropertyList:object format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL]; }
static void Put(NSData *data, NSString *relative) {
    NSString *path = Library(relative);
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [data writeToFile:path atomically:YES];
}
static NSArray<NSString *> *BackupsOf(NSString *name) {
    NSMutableArray *found = [NSMutableArray array];
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtPath:TSLibraryBackupFolder()];
    for (NSString *p in e) if ([p.lastPathComponent isEqual:name] || [p.lastPathComponent hasPrefix:[name.stringByDeletingPathExtension stringByAppendingString:@" "]]) [found addObject:[TSLibraryBackupFolder() stringByAppendingPathComponent:p]];
    return found;
}
static NSArray<NSString *> *Files;
// A file another application creates while TeXShop restores the same one: when TeXShop reads its own copy of `RaceBundled`,
// `RaceTarget` is created with `RaceContents` first (the moment between finding the file missing and putting the copy).
static NSString *RaceBundled, *RaceTarget; static NSData *RaceContents;
static IMP OriginalDataWithContentsOfFile, OriginalWriteToFile;
// Another application saves the file at once (a new file renamed over it) just when TeXShop writes the backup of what it
// judged damaged: the moment after judging and before taking the file away.
static NSString *SaveTarget; static NSData *SaveContents;
static BOOL RacingWriteToFile(NSData *self, SEL _cmd, NSString *path, NSDataWritingOptions options, NSError **error) {
    if (SaveTarget && [path hasPrefix:TSLibraryBackupFolder()]) {
        NSString *target = SaveTarget; SaveTarget = nil;
        ((BOOL (*)(id, SEL, NSString *, NSDataWritingOptions, NSError **))OriginalWriteToFile)(SaveContents, _cmd, target, NSDataWritingAtomic, NULL);
    }
    return ((BOOL (*)(id, SEL, NSString *, NSDataWritingOptions, NSError **))OriginalWriteToFile)(self, _cmd, path, options, error);
}
static id RacingDataWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    if (RaceBundled && [path isEqual:RaceBundled]) {
        RaceBundled = nil;
        [RaceContents writeToFile:RaceTarget atomically:YES];
    }
    return ((id (*)(id, SEL, NSString *))OriginalDataWithContentsOfFile)(self, _cmd, path);
}

int main(int argc, char **argv) { @autoreleasepool {
    alerts = [NSMutableArray array];
    Resources = @(argv[1]);
    method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(resourcePath)), (IMP)TestResourcePath);
    NSFileManager *fm = NSFileManager.defaultManager;
    // The files are written just before they are checked; the wait for a file being saved is tried on its own below.
    TSLibraryQuietSeconds = 0;
    Files = @[@"Macros/Macros_Latex.plist", @"LatexPanel/completion.plist", @"MatrixPanel/matrixpanel_1.plist", @"Keyboard/autocompletion.plist",
              @"Menus/KeyEquivalents.plist", @"CommandCompletion/CommandCompletion.txt", @"CommandCompletion/CommandCompletionXML.txt",
              @"Themes/LiteTheme.plist", @"Themes/DarkTheme.plist", @"SpellCheck/SpellingExclusions.txt", @"HTML/Help.html"];
    for (NSString *f in Files) check(Bundled(f).length > 0, [@"the copy inside TeXShop exists: " stringByAppendingString:f]);

    // 1. Nothing there: every file comes from the copy inside TeXShop, and nothing goes to the backups.
    TSLibraryRepairAll();
    for (NSString *f in Files) check([[NSData dataWithContentsOfFile:Library(f)] isEqual:Bundled(f)], [@"missing file restored: " stringByAppendingString:f]);
    check(![fm fileExistsAtPath:TSLibraryBackupFolder()], @"restoring missing files makes no backups");

    // 2. Edited but sound: kept as they are.
    NSMutableDictionary *macros = [[NSPropertyListSerialization propertyListWithData:Bundled(@"Macros/Macros_Latex.plist") options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    [macros[@"submenu"] removeLastObject];
    NSMutableDictionary *completion = [[NSPropertyListSerialization propertyListWithData:Bundled(@"LatexPanel/completion.plist") options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    for (NSString *key in completion) if ([completion[key] isKindOfClass:NSArray.class]) [completion[key] addObject:@"\\mine"];
    NSMutableDictionary *theme = [[NSPropertyListSerialization propertyListWithData:Bundled(@"Themes/LiteTheme.plist") options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    for (NSString *key in theme.allKeys) if ([theme[key] isKindOfClass:NSArray.class]) { theme[key] = @[@0.1, @0.2, @0.3, @1]; break; }
    NSMutableDictionary *shortCustomized = [completion mutableCopy];
    shortCustomized[@"Customized"] = @[@"Mine", @"\\mine"];
    NSDictionary *nested = @{@"submenu": @[@{@"name": @"Group", @"submenu": @[@{@"name": @"Inner", @"content": @"x", @"key": @"F1"}]}, @{@"name": @"Plain"}]};
    NSDictionary *edited = @{@"Macros/Macros_Latex.plist": Plist(macros), @"LatexPanel/completion.plist": Plist(shortCustomized),
                             @"Macros/Macros_Tex.plist": Plist(nested),
                             @"Keyboard/autocompletion.plist": Plist(@{@"a": @"b"}), @"Menus/KeyEquivalents.plist": Plist(@{}),
                             @"CommandCompletion/CommandCompletion.txt": [@"\\mine\n" dataUsingEncoding:NSShiftJISStringEncoding],
                             @"Themes/LiteTheme.plist": Plist(theme), @"SpellCheck/SpellingExclusions.txt": [@"% mine\n" dataUsingEncoding:NSUTF8StringEncoding]};
    for (NSString *f in edited) Put(edited[f], f);
    TSLibraryRepairAll();
    for (NSString *f in edited) check([[NSData dataWithContentsOfFile:Library(f)] isEqual:edited[f]], [@"an edited file that can be used is kept: " stringByAppendingString:f]);
    check(![fm fileExistsAtPath:TSLibraryBackupFolder()], @"sound files make no backups");

    // 3. Damaged: replaced by the copy inside TeXShop, the damaged one kept in the backups.
    NSData *garbage = [@"<plist><dict><key>broken" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *shortPanel = [completion mutableCopy];
    for (NSString *key in shortPanel.allKeys) if ([shortPanel[key] isKindOfClass:NSArray.class]) { shortPanel[key] = @[@"x"]; break; }
    NSMutableDictionary *badTheme = [theme mutableCopy];
    // One color too short; the components of the colors are checked by the other theme, which is not a property list.
    // A color with three components: the colors are read with their alpha.
    for (NSString *key in badTheme.allKeys) if ([badTheme[key] isKindOfClass:NSArray.class]) { badTheme[key] = @[@0.5, @0.5, @0.5]; break; }
    NSMutableDictionary *numberTheme = [theme mutableCopy];
    for (NSString *key in numberTheme.allKeys) if ([numberTheme[key] isKindOfClass:NSArray.class]) { numberTheme[key] = @42; break; }
    NSMutableDictionary *badMatrix = [[NSPropertyListSerialization propertyListWithData:Bundled(@"MatrixPanel/matrixpanel_1.plist") options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    for (NSString *key in badMatrix.allKeys) if ([badMatrix[key] isKindOfClass:NSArray.class]) { NSMutableArray *a = [badMatrix[key] mutableCopy]; a[0] = @7; badMatrix[key] = a; }
    unsigned char latin1[] = {0x25, 0x20, 0xE9, 0x0A};
    NSDictionary *damaged = @{@"Macros/Macros_Latex.plist": Plist(@{@"submenu": @[@42]}),
                              @"LatexPanel/completion.plist": Plist(shortPanel),
                              @"MatrixPanel/matrixpanel_1.plist": Plist(badMatrix),
                              @"HTML/Help.html": [NSData data],
                              @"Keyboard/autocompletion.plist": Plist(@{@"a": @[@"b"]}),
                              @"Menus/KeyEquivalents.plist": [NSData data],
                              @"Themes/LiteTheme.plist": Plist(badTheme),
                              @"Themes/DarkTheme.plist": Plist(numberTheme),
                              @"SpellCheck/SpellingExclusions.txt": [NSData dataWithBytes:latin1 length:4]};
    for (NSString *f in damaged) Put(damaged[f], f);
    // A folder where a file belongs.
    [fm removeItemAtPath:Library(@"CommandCompletion/CommandCompletionXML.txt") error:NULL];
    [fm createDirectoryAtPath:Library(@"CommandCompletion/CommandCompletionXML.txt") withIntermediateDirectories:YES attributes:nil error:NULL];
    TSLibraryRepairAll();
    for (NSString *f in damaged) {
        check([[NSData dataWithContentsOfFile:Library(f)] isEqual:Bundled(f)], [@"damaged file restored: " stringByAppendingString:f]);
        NSArray *kept = BackupsOf(f.lastPathComponent);
        check(kept.count == 1 && [[NSData dataWithContentsOfFile:kept[0]] isEqual:damaged[f]], [NSString stringWithFormat:@"damaged file kept in Backups: %@ %@", f, kept]);
        check(kept.count == 0 || [kept[0] hasPrefix:[[@"~/Library/TeXShop/Backups/" stringByExpandingTildeInPath] stringByAppendingString:@"/"]], @"backups live in ~/Library/TeXShop/Backups");
    }
    BOOL directory = NO;
    check([fm fileExistsAtPath:Library(@"CommandCompletion/CommandCompletionXML.txt") isDirectory:&directory] && !directory &&
          [[NSData dataWithContentsOfFile:Library(@"CommandCompletion/CommandCompletionXML.txt")] isEqual:Bundled(@"CommandCompletion/CommandCompletionXML.txt")],
          @"a folder where a file belongs is replaced by the file");
    check([BackupsOf(@"CommandCompletionXML.txt") count] == 1, @"the folder is kept in Backups");
    check([[BackupsOf(@"Macros_Latex.plist") firstObject] hasSuffix:@"/Macros/Macros_Latex.plist"], @"a backup keeps the path below ~/Library/TeXShop");

    // 4. A symbolic link: the file where it points is restored, the link stays.
    NSString *elsewhere = [[@"~/Elsewhere" stringByExpandingTildeInPath] stringByAppendingPathComponent:@"autocompletion.plist"];
    [fm createDirectoryAtPath:elsewhere.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [garbage writeToFile:elsewhere atomically:YES];
    [fm removeItemAtPath:Library(@"Keyboard/autocompletion.plist") error:NULL];
    [fm createSymbolicLinkAtPath:Library(@"Keyboard/autocompletion.plist") withDestinationPath:elsewhere error:NULL];
    TSLibraryRepairAll();
    check([[fm attributesOfItemAtPath:Library(@"Keyboard/autocompletion.plist") error:NULL][NSFileType] isEqual:NSFileTypeSymbolicLink] &&
          [[NSData dataWithContentsOfFile:elsewhere] isEqual:Bundled(@"Keyboard/autocompletion.plist")], @"a damaged file behind a link is restored where the link points");
    [fm removeItemAtPath:elsewhere error:NULL];
    TSLibraryRepairAll();
    check([[NSData dataWithContentsOfFile:elsewhere] isEqual:Bundled(@"Keyboard/autocompletion.plist")], @"a link to a missing file gets the file where it points");

    // 9. Every theme the check lets through can be read as TeXShop reads its colors; the ones that cannot are refused.
    Colors *reader = [Colors new];
    NSDictionary *reference = [NSPropertyListSerialization propertyListWithData:Bundled(@"Themes/LiteTheme.plist") options:0 format:NULL error:NULL];
    NSArray *values = @[@[@0.1, @0.2, @0.3, @1], @[@0.1, @0.2, @0.3], @[@0.1, @0.2], @[], @42, @"red", @[@"r", @0, @0, @1], @[@0.1, @0.2, @0.3, @1, @9], @{}];
    for (NSString *key in reference) {
        if (![reference[key] isKindOfClass:NSArray.class]) continue;
        for (id value in values) {
            NSMutableDictionary *probe = [reference mutableCopy]; probe[key] = value;
            BOOL accepted = TSLibraryThemeCheck()(Plist(probe), Bundled(@"Themes/LiteTheme.plist"));
            BOOL reads = YES;
            @try { [reader colorFromDictionary:probe andKey:key]; [reader colorAndAlphaFromDictionary:probe andKey:key]; }
            @catch (NSException *e) { reads = NO; }
            if (accepted && !reads) check(NO, [NSString stringWithFormat:@"a theme the check lets through cannot be read: %@ = %@", key, value]);
        }
        break;
    }

    // 6. A damaged file that cannot be kept in the backups is left as it is, and nothing is restored over it.
    // The backups of this run go to one folder named after its first backup; a folder there that cannot be written to
    // lets the folder be made but not the file moved in.
    NSString *session = [[fm contentsOfDirectoryAtPath:TSLibraryBackupFolder() error:NULL] firstObject];
    check(session != nil, @"the backups of this run are in one folder");
    NSString *menus = [[TSLibraryBackupFolder() stringByAppendingPathComponent:session] stringByAppendingPathComponent:@"Menus"];
    [fm removeItemAtPath:menus error:NULL];
    [fm createDirectoryAtPath:menus withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0500} error:NULL];
    Put(garbage, @"Menus/KeyEquivalents.plist");
    check(!TSLibraryRepairFile(Library(@"Menus/KeyEquivalents.plist"), TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Menus/KeyEquivalents.plist")] isEqual:garbage], @"a damaged file that cannot be moved to the backups stays as it was");
    [fm setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:menus error:NULL];
    // Nor when the backups folder cannot be made.
    [fm removeItemAtPath:TSLibraryBackupFolder() error:NULL];
    [@"in the way" writeToFile:TSLibraryBackupFolder() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    check(!TSLibraryRepairFile(Library(@"Menus/KeyEquivalents.plist"), TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Menus/KeyEquivalents.plist")] isEqual:garbage], @"a damaged file stays as it was when the backups folder cannot be made");
    [fm removeItemAtPath:TSLibraryBackupFolder() error:NULL];

    // 7. A file changed in the last seconds may be being saved: left alone, then restored once it is quiet.
    TSLibraryQuietSeconds = 5;
    Put(garbage, @"Keyboard/autocompletion.plist");
    [fm removeItemAtPath:elsewhere error:NULL];
    check(!TSLibraryRepairFile(Library(@"Keyboard/autocompletion.plist"), TSLibraryBundledPath(@"Keyboard/autocompletion.plist"), TSLibraryStringDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Keyboard/autocompletion.plist")] isEqual:garbage] && ![fm fileExistsAtPath:TSLibraryBackupFolder()],
          @"a damaged file changed just now is left alone");
    [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-60]} ofItemAtPath:Library(@"Keyboard/autocompletion.plist") error:NULL];
    check(TSLibraryRepairFile(Library(@"Keyboard/autocompletion.plist"), TSLibraryBundledPath(@"Keyboard/autocompletion.plist"), TSLibraryStringDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Keyboard/autocompletion.plist")] isEqual:Bundled(@"Keyboard/autocompletion.plist")], @"once quiet, it is restored");
    TSLibraryQuietSeconds = 0;

    // 8. Links that loop or go on too long: nothing is written, the links stay.
    NSString *chain = [@"~/Chain" stringByExpandingTildeInPath];
    [fm createDirectoryAtPath:chain withIntermediateDirectories:YES attributes:nil error:NULL];
    for (int i = 0; i < 40; i++)
        [fm createSymbolicLinkAtPath:[chain stringByAppendingFormat:@"/link%d", i] withDestinationPath:[chain stringByAppendingFormat:@"/link%d", i + 1] error:NULL];
    [garbage writeToFile:[chain stringByAppendingString:@"/link40"] atomically:YES];
    check(!TSLibraryRepairFile([chain stringByAppendingString:@"/link0"], TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck()), @"a chain of 40 links is not followed");
    BOOL allLinks = YES;
    for (int i = 0; i < 40; i++) allLinks = allLinks && [[fm attributesOfItemAtPath:[chain stringByAppendingFormat:@"/link%d", i] error:NULL][NSFileType] isEqual:NSFileTypeSymbolicLink];
    check(allLinks && [[NSData dataWithContentsOfFile:[chain stringByAppendingString:@"/link40"]] isEqual:garbage], @"every link of the chain stays a link, the end untouched");
    [fm createSymbolicLinkAtPath:[chain stringByAppendingString:@"/loopA"] withDestinationPath:[chain stringByAppendingString:@"/loopB"] error:NULL];
    [fm createSymbolicLinkAtPath:[chain stringByAppendingString:@"/loopB"] withDestinationPath:[chain stringByAppendingString:@"/loopA"] error:NULL];
    check(!TSLibraryRepairFile([chain stringByAppendingString:@"/loopA"], TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck()) &&
          [[fm attributesOfItemAtPath:[chain stringByAppendingString:@"/loopA"] error:NULL][NSFileType] isEqual:NSFileTypeSymbolicLink], @"a loop of links is left alone");

    // 12. A file that appears between finding it missing and putting TeXShop's copy is kept, never replaced.
    OriginalDataWithContentsOfFile = method_setImplementation(class_getClassMethod(NSData.class, @selector(dataWithContentsOfFile:)), (IMP)RacingDataWithContentsOfFile);
    NSData *theirs = Plist(@{@"a": @"from another application"});
    [fm removeItemAtPath:Library(@"Keyboard/autocompletion.plist") error:NULL];
    RaceBundled = TSLibraryBundledPath(@"Keyboard/autocompletion.plist"); RaceTarget = Library(@"Keyboard/autocompletion.plist"); RaceContents = theirs;
    check(TSLibraryRestoreMissingFile(Library(@"Keyboard/autocompletion.plist"), TSLibraryBundledPath(@"Keyboard/autocompletion.plist"), TSLibraryStringDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Keyboard/autocompletion.plist")] isEqual:theirs], @"while running, a file created meanwhile is kept and used");
    // The same at launch, after the damaged file has gone to the backups.
    Put(garbage, @"Keyboard/autocompletion.plist");
    RaceBundled = TSLibraryBundledPath(@"Keyboard/autocompletion.plist"); RaceTarget = Library(@"Keyboard/autocompletion.plist"); RaceContents = theirs;
    check(TSLibraryRepairFile(Library(@"Keyboard/autocompletion.plist"), TSLibraryBundledPath(@"Keyboard/autocompletion.plist"), TSLibraryStringDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Keyboard/autocompletion.plist")] isEqual:theirs], @"at launch, a file created after the backup is kept and used");
    RaceBundled = nil;
    method_setImplementation(class_getClassMethod(NSData.class, @selector(dataWithContentsOfFile:)), OriginalDataWithContentsOfFile);

    // 14. A damaged file that another application replaces with a good one just after TeXShop judged it: the good one
    // stays where it is, and no backup is left.
    OriginalWriteToFile = method_setImplementation(class_getInstanceMethod(NSData.class, @selector(writeToFile:options:error:)), (IMP)RacingWriteToFile);
    [fm removeItemAtPath:TSLibraryBackupFolder() error:NULL];
    Put(garbage, @"Keyboard/autocompletion.plist");
    NSData *saved = Plist(@{@"b": @"saved by another application"});
    SaveTarget = Library(@"Keyboard/autocompletion.plist"); SaveContents = saved;
    check(TSLibraryRepairFile(Library(@"Keyboard/autocompletion.plist"), TSLibraryBundledPath(@"Keyboard/autocompletion.plist"), TSLibraryStringDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Keyboard/autocompletion.plist")] isEqual:saved] && [BackupsOf(@"autocompletion.plist") count] == 0,
          [NSString stringWithFormat:@"a file saved at once after it was judged damaged stays, and no backup is left %@", BackupsOf(@"autocompletion.plist")]);
    SaveTarget = nil;
    method_setImplementation(class_getInstanceMethod(NSData.class, @selector(writeToFile:options:error:)), OriginalWriteToFile);

    // 13. A damaged file another process has open (it may be writing it in place) is left as it is, even at launch.
    Put(garbage, @"Menus/KeyEquivalents.plist");
    NSTask *holder = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]
        arguments:@[@"-c", [NSString stringWithFormat:@"exec 3<>'%@'; sleep 30", Library(@"Menus/KeyEquivalents.plist")]] error:NULL terminationHandler:nil];
    [NSThread sleepForTimeInterval:0.5];
    check(!TSLibraryRepairFile(Library(@"Menus/KeyEquivalents.plist"), TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Menus/KeyEquivalents.plist")] isEqual:garbage], @"a damaged file another process has open is left alone");
    [holder terminate]; [holder waitUntilExit];
    check(TSLibraryRepairFile(Library(@"Menus/KeyEquivalents.plist"), TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck()) &&
          [[NSData dataWithContentsOfFile:Library(@"Menus/KeyEquivalents.plist")] isEqual:Bundled(@"Menus/KeyEquivalents.plist")], @"once nobody has it open, it is repaired");

    // 5. The macros as TeXShop reads them while it runs: nothing is shown, the menu gets macros, and a file that is
    // there is never changed (it may be being saved); the next launch repairs it.
    NSDictionary *bundledMacros = [NSPropertyListSerialization propertyListWithData:Bundled(@"Macros/Macros_Latex.plist") options:0 format:NULL error:NULL];
    Macros *m = [Macros new];
    g_macroType = LatexEngine;
    Put(garbage, @"Macros/Macros_Latex.plist");
    [alerts removeAllObjects]; [m loadMacros];
    check(alerts.count == 0 && [m.macroDict isEqual:bundledMacros] && [[NSData dataWithContentsOfFile:Library(@"Macros/Macros_Latex.plist")] isEqual:garbage],
          [NSString stringWithFormat:@"damaged LaTeX macros while running: TeXShop's macros are read, the file is left, no message %@", alerts]);
    TSLibraryRepairAll();
    check([[NSData dataWithContentsOfFile:Library(@"Macros/Macros_Latex.plist")] isEqual:Bundled(@"Macros/Macros_Latex.plist")], @"the next launch repairs the LaTeX macros");
    [fm removeItemAtPath:Library(@"Macros") error:NULL];
    [alerts removeAllObjects]; [m loadMacros];
    check(alerts.count == 0 && [m.macroDict isEqual:bundledMacros] && [[NSData dataWithContentsOfFile:Library(@"Macros/Macros_Latex.plist")] isEqual:Bundled(@"Macros/Macros_Latex.plist")],
          @"no macros folder while running: the missing file is restored, without a message");
    g_macroType = TexEngine;
    Put(Plist(@{@"submenu": @[@{@"name": @"tex mine", @"content": @"x"}]}), @"Macros/Macros_Tex.plist");
    [alerts removeAllObjects]; [m loadMacros];
    check([[m.macroDict[@"submenu"] firstObject][@"name"] isEqual:@"tex mine"], @"the macros of the engine are read when sound");
    NSData *badTex = Plist(@{@"submenu": @[@{@"name": @[@"not a string"]}]});
    Put(badTex, @"Macros/Macros_Tex.plist");
    [alerts removeAllObjects]; [m loadMacros];
    check(alerts.count == 0 && [m.macroDict isEqual:bundledMacros] && [[NSData dataWithContentsOfFile:Library(@"Macros/Macros_Tex.plist")] isEqual:badTex],
          @"damaged macros of an engine while running: the LaTeX macros are read, the file is left");
    TSLibraryRepairAll();
    check(![fm fileExistsAtPath:Library(@"Macros/Macros_Tex.plist")] && [BackupsOf(@"Macros_Tex.plist") count] == 1,
          @"the next launch puts damaged macros of an engine in the backups");

    // 10. While TeXShop runs, a missing file is restored and nothing else is changed.
    Put(garbage, @"LatexPanel/completion.plist");
    check(!TSLibraryRestoreMissingFile(Library(@"LatexPanel/completion.plist"), TSLibraryBundledPath(@"LatexPanel/completion.plist"), TSLibraryShapeOfBundledCheck(TSLibraryLaTeXPanelAnyLength())) &&
          [[NSData dataWithContentsOfFile:Library(@"LatexPanel/completion.plist")] isEqual:garbage], @"while running, a damaged file is left as it is");
    [fm removeItemAtPath:Library(@"LatexPanel/completion.plist") error:NULL];
    check(TSLibraryRestoreMissingFile(Library(@"LatexPanel/completion.plist"), TSLibraryBundledPath(@"LatexPanel/completion.plist"), TSLibraryShapeOfBundledCheck(TSLibraryLaTeXPanelAnyLength())) &&
          [[NSData dataWithContentsOfFile:Library(@"LatexPanel/completion.plist")] isEqual:Bundled(@"LatexPanel/completion.plist")], @"while running, a missing file is restored");

    // 11. A theme of the user's own is checked against TeXShop's Lite theme, with or without a reference.
    NSMutableDictionary *mine = [theme mutableCopy];
    for (NSString *key in mine.allKeys) if ([mine[key] isKindOfClass:NSArray.class]) { mine[key] = @42; break; }
    check(!TSLibraryThemeCheck()(Plist(mine), nil), @"a theme of the user's own with a number for a color is damaged, as when it is read");
    check(TSLibraryThemeCheck()(Plist(theme), nil), @"a sound theme of the user's own passes");
    // The launch checks the theme in use; a damaged one of the user's own goes to the backups.
    Put(Plist(mine), @"Themes/Mine.plist");
    // In the registration domain only, which is never written to disk.
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"DefaultLiteTheme": @"Mine"}];
    TSLibraryRepairAll();
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"DefaultLiteTheme": @""}];
    check(![fm fileExistsAtPath:Library(@"Themes/Mine.plist")] && [BackupsOf(@"Mine.plist") count] == 1, @"the launch puts a damaged theme of the user's own in the backups");
    if (failures) return 1;
    puts("PASS: settings files restored when missing or damaged, damaged ones kept, links followed, macros without a message");
} return 0; }
'''

MUTATIONS = {
    'no backup': ('        if (![contents writeToFile:target options:NSDataWritingWithoutOverwriting error:NULL]) return NO;\n', ''),
    'missing only': ('    if (data && check(data, reference)) return YES;\n', '    if (data) return YES;\n'),
    'running replaces damaged': ('    if ([fm attributesOfItemAtPath:file error:NULL]) return TSLibraryFileIsUsable(path, bundledPath, check);', '    if ([fm attributesOfItemAtPath:file error:NULL]) return TSLibraryRepairFile(path, bundledPath, check);'),
    'replace when created meanwhile': ('    BOOL placed = renamex_np(temporary.fileSystemRepresentation, file.fileSystemRepresentation, RENAME_EXCL) == 0;', '    BOOL placed = rename(temporary.fileSystemRepresentation, file.fileSystemRepresentation) == 0;'),
    'open files ignored': ('        if (OpenElsewhere(file)) return NO;\n', ''),
    'own themes unchecked': ('        if (![reference isKindOfClass:NSDictionary.class]) {\n            NSString *lite', '        if (NO) {\n            NSString *lite'),
    'link replaced': ('    NSString *file = Destination(path);\n    if (!file) return NO;\n    NSData *reference', '    NSString *file = path;\n    NSData *reference'),
    'short panels pass': ('if (![anyLength containsObject:key] && [value count] < [expected count]) return NO;', ''),
    'every array any length': ('if (![anyLength containsObject:key] && ', 'if (NO && '),
    'three components': ('[value count] < 4', '[value count] < 3'),
    'colors not required': ('if (![value isKindOfClass:NSArray.class] || [value count] < 4 || !AllOfClass(value, NSNumber.class)) return NO;', 'if ([value isKindOfClass:NSArray.class] && ([value count] < 4 || !AllOfClass(value, NSNumber.class))) return NO;'),
    'macro items unchecked': ('        return macros[@"submenu"] == nil || MacroItems(macros[@"submenu"], 0);', '        return YES;'),
    'delete when backup fails': ('        if (![contents writeToFile:target options:NSDataWritingWithoutOverwriting error:NULL]) return NO;', '        if (![contents writeToFile:target options:NSDataWritingWithoutOverwriting error:NULL]) [fm removeItemAtPath:file error:NULL];'),
    'take away whatever is there': ('        if (![FileNumber(aside) isEqual:number]) {', '        if (NO) {'),
    'no wait while saving': ('        if (modified && fabs(modified.timeIntervalSinceNow) < TSLibraryQuietSeconds) return NO;\n', ''),
    'chains followed to a point': ('    return nil;\n}\n\n// Puts `data`', '    return current;\n}\n\n// Puts `data`'),
}


def run(td, repair, name):
    work = td / name; work.mkdir()
    resources = work / 'Resources'; resources.mkdir()
    shutil.copytree(root / 'Resources/TeXShop', resources / 'TeXShop', symlinks=True)
    shutil.copytree(root / 'Resources/Themes', resources / 'Themes')
    src = work / 'probe.m'; lib = work / 'TSLibraryRepair.m'; exe = work / 'probe'
    program = PROGRAM.replace('__LOAD_MACROS__', fragments[0][2]).replace('__COLORS__', '\n'.join(f for _, _, f in fragments[1:]))
    src.write_text(program, encoding='utf-8', errors='surrogateescape'); lib.write_text(repair, encoding='utf-8')
    subprocess.run(['clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(source_file(root, 'TSLibraryRepair.h').parent),
                    str(src), str(lib), '-o', str(exe)], check=True)
    home = work / 'home'; home.mkdir()
    env = dict(os.environ, CFFIXED_USER_HOME=str(home), HOME=str(home))
    return subprocess.run([str(exe), str(resources)], capture_output=True, text=True, timeout=60, env=env), program


with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    result, program = run(td, repair_source, 'normal')
    verify_embedded(program, fragments)
    sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
    assert result.returncode == 0, 'normal harness failed'
    for name, (old, new) in MUTATIONS.items():
        assert repair_source.count(old) == 1, name
        r, _ = run(td, repair_source.replace(old, new), 'mutation-' + name.replace(' ', '-'))
        assert r.returncode != 0, 'mutation went unnoticed: ' + name
        print('PASS mutation %s: %s' % (name, ([l for l in r.stderr.splitlines() if 'FAIL' in l] or ['failed'])[0]))
