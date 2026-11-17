// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSLibraryRepair.h"
#import <libproc.h>
#import <stdio.h>

static NSString *const TSLibraryFolder = @"~/Library/TeXShop";
NSTimeInterval TSLibraryQuietSeconds = 5;

static id PropertyList(NSData *data)
{
    if (!data.length) return nil;
    @try { return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL]; }
    @catch (NSException *exception) { return nil; }
}

TSLibraryFileCheck TSLibraryDictionaryCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) { return [PropertyList(data) isKindOfClass:NSDictionary.class]; };
}

static BOOL AllOfClass(NSArray *array, Class class)
{
    for (id item in array) if (![item isKindOfClass:class]) return NO;
    return YES;
}

TSLibraryFileCheck TSLibraryShapeOfBundledCheck(NSSet<NSString *> *anyLength)
{
    return ^BOOL(NSData *data, NSData *bundled) {
        NSDictionary *mine = PropertyList(data), *theirs = PropertyList(bundled);
        if (![mine isKindOfClass:NSDictionary.class]) return NO;
        if (![theirs isKindOfClass:NSDictionary.class]) return YES;
        for (id key in theirs) {
            id expected = theirs[key], value = mine[key];
            if ([expected isKindOfClass:NSArray.class]) {
                // The panels read most arrays at fixed positions; the ones in anyLength they read as far as they go.
                if (![value isKindOfClass:NSArray.class]) return NO;
                if (![anyLength containsObject:key] && [value count] < [expected count]) return NO;
                Class element = [[expected firstObject] isKindOfClass:NSString.class] ? NSString.class : nil;
                if (element && !AllOfClass(value, element)) return NO;
            }
            if ([expected isKindOfClass:NSDictionary.class] && ![value isKindOfClass:NSDictionary.class]) return NO;
        }
        return YES;
    };
}

// Each item as the Macros menu reads it: a dictionary with a name, its content and key as strings, and a submenu
// of such items.
static BOOL MacroItems(id items, NSUInteger depth)
{
    if (![items isKindOfClass:NSArray.class] || depth > 64) return NO;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"name"] isKindOfClass:NSString.class]) return NO;
        for (NSString *key in @[@"content", @"key"])
            if (item[key] && ![item[key] isKindOfClass:NSString.class]) return NO;
        if (item[@"submenu"] && !MacroItems(item[@"submenu"], depth + 1)) return NO;
    }
    return YES;
}

TSLibraryFileCheck TSLibraryMacrosCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) {
        NSDictionary *macros = PropertyList(data);
        if (![macros isKindOfClass:NSDictionary.class]) return NO;
        return macros[@"submenu"] == nil || MacroItems(macros[@"submenu"], 0);
    };
}

TSLibraryFileCheck TSLibraryStringDictionaryCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) {
        NSDictionary *dict = PropertyList(data);
        if (![dict isKindOfClass:NSDictionary.class]) return NO;
        for (id key in dict)
            if (![key isKindOfClass:NSString.class] || ![dict[key] isKindOfClass:NSString.class]) return NO;
        return YES;
    };
}

TSLibraryFileCheck TSLibraryThemeCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) {
        NSDictionary *theme = PropertyList(data);
        if (![theme isKindOfClass:NSDictionary.class]) return NO;
        // A theme of the user's own is checked against TeXShop's Lite theme, wherever it is checked.
        NSDictionary *reference = PropertyList(bundled);
        if (![reference isKindOfClass:NSDictionary.class]) {
            NSString *lite = TSLibraryBundledPath(@"Themes/LiteTheme.plist");
            reference = lite ? PropertyList([NSData dataWithContentsOfFile:lite]) : nil;
        }
        if (![reference isKindOfClass:NSDictionary.class]) reference = nil;
        // A color is read as red, green, blue and alpha. A key that the copy inside TeXShop has as a color must be one;
        // any other array must be one too. Keys may be missing (TeXShop has defaults for them).
        for (id key in theme) {
            id value = theme[key], expected = reference[key];
            BOOL color = [expected isKindOfClass:NSArray.class] || (expected == nil && [value isKindOfClass:NSArray.class]);
            if (color) {
                if (![value isKindOfClass:NSArray.class] || [value count] < 4 || !AllOfClass(value, NSNumber.class)) return NO;
            } else if (expected && ![value isKindOfClass:[expected class]] && !([expected isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class])) return NO;
        }
        return YES;
    };
}

TSLibraryFileCheck TSLibraryUTF8TextCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) { return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] != nil; };
}

TSLibraryFileCheck TSLibraryReadableCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) { return YES; };
}

TSLibraryFileCheck TSLibraryNonEmptyCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) { return data.length > 0; };
}

NSSet<NSString *> *TSLibraryLaTeXPanelAnyLength(void)
{
    // The Customized buttons are as many as the pairs in the list (TSLaTeXPanelController).
    return [NSSet setWithObject:@"Customized"];
}

NSString *TSLibraryBackupFolder(void)
{
    return [[TSLibraryFolder stringByExpandingTildeInPath] stringByAppendingPathComponent:@"Backups"];
}

NSString *TSLibraryBundledPath(NSString *relativePath)
{
    NSString *resources = NSBundle.mainBundle.resourcePath;
    if (!resources) return nil;
    NSString *path = [[resources stringByAppendingPathComponent:@"TeXShop"] stringByAppendingPathComponent:relativePath];
    BOOL directory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && !directory ? path : nil;
}

// The file a path stands for: where a symbolic link points (even when nothing is there yet), else the path itself.
// Nil for a chain of links that loops or is longer than the system follows (MAXSYMLINKS): nothing is written then.
static NSString *Destination(NSString *path)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *current = path;
    for (NSUInteger hops = 0; hops <= 32; hops++) {
        NSDictionary *attributes = [fm attributesOfItemAtPath:current error:NULL];
        if (![attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) return current;
        NSString *target = [fm destinationOfSymbolicLinkAtPath:current error:NULL];
        if (!target) return nil;
        current = target.isAbsolutePath ? target : [[current stringByDeletingLastPathComponent] stringByAppendingPathComponent:target];
        current = current.stringByStandardizingPath;
    }
    return nil;
}

// Puts `data` at `file` only if nothing is there when it lands: the copy is written next to it and renamed with
// RENAME_EXCL, so a file that another application creates meanwhile is never replaced. Returns whether it was put.
static BOOL PlaceIfAbsent(NSData *data, NSString *file)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:file.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *temporary = [file.stringByDeletingLastPathComponent stringByAppendingPathComponent:
                           [NSString stringWithFormat:@".%@.TeXShop-%@", file.lastPathComponent, NSUUID.UUID.UUIDString]];
    if (![data writeToFile:temporary options:0 error:NULL]) return NO;
    BOOL placed = renamex_np(temporary.fileSystemRepresentation, file.fileSystemRepresentation, RENAME_EXCL) == 0;
    if (!placed) [fm removeItemAtPath:temporary error:NULL];
    return placed;
}

// Whether another process has the file open (an application may be writing it in place).
static BOOL OpenElsewhere(NSString *file)
{
    int size = proc_listpidspath(PROC_ALL_PIDS, 0, file.fileSystemRepresentation, PROC_LISTPIDSPATH_EXCLUDE_EVTONLY, NULL, 0);
    if (size <= 0) return NO;
    NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)size + 64 * sizeof(pid_t)];
    int bytes = proc_listpidspath(PROC_ALL_PIDS, 0, file.fileSystemRepresentation, PROC_LISTPIDSPATH_EXCLUDE_EVTONLY, buffer.mutableBytes, (int)buffer.length);
    const pid_t *pids = buffer.bytes;
    for (int i = 0; i < bytes / (int)sizeof(pid_t); i++)
        if (pids[i] > 0 && pids[i] != getpid()) return YES;
    return NO;
}

// Moves a damaged file (or a folder where a file belongs) to ~/Library/TeXShop/Backups/<date>/<name>. Returns whether
// it is there; when it could not be moved, it stays where it was.
static BOOL BackUp(NSString *path)
{
    static NSString *session;
    if (!session) {
        NSDateFormatter *format = [NSDateFormatter new];
        format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        format.dateFormat = @"yyyy-MM-dd HH.mm.ss";
        session = [format stringFromDate:NSDate.date];
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *library = [TSLibraryFolder stringByExpandingTildeInPath].stringByStandardizingPath;
    NSString *standard = path.stringByStandardizingPath;
    NSString *name = [standard hasPrefix:[library stringByAppendingString:@"/"]] ? [standard substringFromIndex:library.length + 1] : standard.lastPathComponent;
    NSString *target = [[TSLibraryBackupFolder() stringByAppendingPathComponent:session] stringByAppendingPathComponent:name];
    if (![fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]) return NO;
    for (NSUInteger n = 2; [fm fileExistsAtPath:target] && n < 100; n++)
        target = [NSString stringWithFormat:@"%@ %lu%@%@", target.stringByDeletingPathExtension, (unsigned long)n,
                  path.pathExtension.length ? @"." : @"", path.pathExtension];
    return [fm moveItemAtPath:path toPath:target error:NULL];
}

BOOL TSLibraryRepairFile(NSString *path, NSString *bundledPath, TSLibraryFileCheck check)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *file = Destination(path);
    if (!file) return NO;
    NSData *bundled = bundledPath ? [NSData dataWithContentsOfFile:bundledPath] : nil;
    BOOL directory = NO;
    BOOL exists = [fm fileExistsAtPath:file isDirectory:&directory];
    NSData *data = exists && !directory ? [NSData dataWithContentsOfFile:file] : nil;
    if (data && check(data, bundled)) return YES;
    NSDictionary *attributes = [fm attributesOfItemAtPath:file error:NULL];
    BOOL damaged = attributes != nil;
    if (damaged) {
        // A file changed in the last seconds may be in the middle of being saved by another application: it is left
        // alone this time (the caller reads TeXShop's copy) and looked at again when it is next read.
        NSDate *modified = attributes[NSFileModificationDate];
        if (modified && fabs(modified.timeIntervalSinceNow) < TSLibraryQuietSeconds) return NO;
        // Nor is a file that changes while it is looked at.
        NSData *again = exists && !directory ? [NSData dataWithContentsOfFile:file] : nil;
        if (!(again == data || [again isEqualToData:data]) || ![[fm attributesOfItemAtPath:file error:NULL][NSFileModificationDate] isEqual:modified]) return NO;
        // Nor is a file another process has open: it may be writing it in place, however long that takes.
        if (OpenElsewhere(file)) return NO;
        if (!BackUp(file)) {
            NSLog(@"TeXShop could not keep a copy of the damaged %@ in Backups; it is left as it is", path.stringByAbbreviatingWithTildeInPath);
            return NO;
        }
    }
    if (!bundled) return NO;
    // A file that appears meanwhile is kept, and used if it can be.
    BOOL restored = PlaceIfAbsent(bundled, file);
    NSLog(@"TeXShop %@ %@ from its own copy%@", restored ? @"restored" : @"did not restore", path.stringByAbbreviatingWithTildeInPath,
          damaged ? @"; the damaged file is in Backups" : @"");
    return restored || TSLibraryFileIsUsable(path, bundledPath, check);
}

BOOL TSLibraryRestoreMissingFile(NSString *path, NSString *bundledPath, TSLibraryFileCheck check)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *file = Destination(path);
    if (!file) return NO;
    // Something there, usable or not, is not touched while TeXShop runs (it may be being saved): see TSLibraryRepairAll.
    if ([fm attributesOfItemAtPath:file error:NULL]) return TSLibraryFileIsUsable(path, bundledPath, check);
    NSData *bundled = bundledPath ? [NSData dataWithContentsOfFile:bundledPath] : nil;
    if (!bundled) return NO;
    // Never over a file that another application creates meanwhile: that one is kept, and used if it can be.
    if (PlaceIfAbsent(bundled, file)) {
        NSLog(@"TeXShop restored the missing %@ from its own copy", path.stringByAbbreviatingWithTildeInPath);
        return YES;
    }
    return TSLibraryFileIsUsable(path, bundledPath, check);
}

BOOL TSLibraryFileIsUsable(NSString *path, NSString *bundledPath, TSLibraryFileCheck check)
{
    NSString *file = Destination(path);
    BOOL directory = NO;
    if (!file || ![NSFileManager.defaultManager fileExistsAtPath:file isDirectory:&directory] || directory) return NO;
    NSData *data = [NSData dataWithContentsOfFile:file];
    return data && check(data, bundledPath ? [NSData dataWithContentsOfFile:bundledPath] : nil);
}

static void Repair(NSString *relative, TSLibraryFileCheck check)
{
    NSString *path = [[TSLibraryFolder stringByAppendingPathComponent:relative] stringByExpandingTildeInPath];
    TSLibraryRepairFile(path, TSLibraryBundledPath(relative), check);
}

void TSLibraryRepairAll(void)
{
    Repair(@"Macros/Macros_Latex.plist", TSLibraryMacrosCheck());
    Repair(@"LatexPanel/completion.plist", TSLibraryShapeOfBundledCheck(TSLibraryLaTeXPanelAnyLength()));
    Repair(@"MatrixPanel/matrixpanel_1.plist", TSLibraryShapeOfBundledCheck(nil));
    Repair(@"Keyboard/autocompletion.plist", TSLibraryStringDictionaryCheck());
    Repair(@"Menus/KeyEquivalents.plist", TSLibraryDictionaryCheck());
    Repair(@"CommandCompletion/CommandCompletion.txt", TSLibraryReadableCheck());
    Repair(@"CommandCompletion/CommandCompletionXML.txt", TSLibraryReadableCheck());
    Repair(@"Themes/LiteTheme.plist", TSLibraryThemeCheck());
    Repair(@"Themes/DarkTheme.plist", TSLibraryThemeCheck());
    // The themes in use: one that comes with TeXShop is restored; a damaged one of the user's own goes to the backups,
    // and TeXShop then uses its Lite or Dark theme (TSColorSupport).
    for (NSString *key in @[@"DefaultLiteTheme", @"DefaultDarkTheme"]) {
        NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:key];
        if (!name.length || [name containsString:@"/"] || [name isEqual:@"LiteTheme"] || [name isEqual:@"DarkTheme"]) continue;
        NSString *relative = [[@"Themes" stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"plist"];
        NSString *path = [[TSLibraryFolder stringByAppendingPathComponent:relative] stringByExpandingTildeInPath];
        if ([NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL] || TSLibraryBundledPath(relative))
            TSLibraryRepairFile(path, TSLibraryBundledPath(relative), TSLibraryThemeCheck());
    }
    // The macros of the other engines have no copy inside TeXShop: a damaged one goes to the backups, and the LaTeX
    // macros are used.
    for (NSString *name in @[@"Macros_Tex", @"Macros_Bibtex", @"Macros_Index", @"Macros_Metapost"]) {
        NSString *path = [[TSLibraryFolder stringByAppendingPathComponent:[[@"Macros" stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"plist"]] stringByExpandingTildeInPath];
        if ([NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL]) TSLibraryRepairFile(path, nil, TSLibraryMacrosCheck());
    }
    Repair(@"SpellCheck/SpellingExclusions.txt", TSLibraryUTF8TextCheck());
    Repair(@"HTML/Help.html", TSLibraryNonEmptyCheck());
}
