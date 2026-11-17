// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSLibraryRepair.h"

static NSString *const TSLibraryFolder = @"~/Library/TeXShop";

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

TSLibraryFileCheck TSLibraryShapeOfBundledCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) {
        NSDictionary *mine = PropertyList(data), *theirs = PropertyList(bundled);
        if (![mine isKindOfClass:NSDictionary.class]) return NO;
        if (![theirs isKindOfClass:NSDictionary.class]) return YES;
        for (id key in theirs) {
            id expected = theirs[key], value = mine[key];
            if ([expected isKindOfClass:NSArray.class] && !([value isKindOfClass:NSArray.class] && [value count] >= [expected count])) return NO;
            if ([expected isKindOfClass:NSDictionary.class] && ![value isKindOfClass:NSDictionary.class]) return NO;
        }
        return YES;
    };
}

TSLibraryFileCheck TSLibraryMacrosCheck(void)
{
    return ^BOOL(NSData *data, NSData *bundled) {
        NSDictionary *macros = PropertyList(data);
        if (![macros isKindOfClass:NSDictionary.class]) return NO;
        id submenu = macros[@"submenu"];
        return submenu == nil || [submenu isKindOfClass:NSArray.class];
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
        // A color is an array of red, green, blue (and alpha); anything else that is an array is damaged.
        for (id key in theme) {
            id value = theme[key];
            if (![value isKindOfClass:NSArray.class]) continue;
            if ([value count] < 3) return NO;
            for (id component in value) if (![component isKindOfClass:NSNumber.class]) return NO;
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
static NSString *Destination(NSString *path)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *current = path;
    for (NSUInteger hops = 0; hops < 16; hops++) {
        NSDictionary *attributes = [fm attributesOfItemAtPath:current error:NULL];
        if (![attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) return current;
        NSString *target = [fm destinationOfSymbolicLinkAtPath:current error:NULL];
        if (!target) return current;
        current = target.isAbsolutePath ? target : [[current stringByDeletingLastPathComponent] stringByAppendingPathComponent:target];
        current = current.stringByStandardizingPath;
    }
    return current;
}

// Moves a damaged file (or a folder where a file belongs) to ~/Library/TeXShop/Backups/<date>/<name>.
static void BackUp(NSString *path)
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
    [fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSUInteger n = 2; [fm fileExistsAtPath:target] && n < 100; n++)
        target = [NSString stringWithFormat:@"%@ %lu%@%@", target.stringByDeletingPathExtension, (unsigned long)n,
                  path.pathExtension.length ? @"." : @"", path.pathExtension];
    if (![fm moveItemAtPath:path toPath:target error:NULL]) [fm removeItemAtPath:path error:NULL];
}

BOOL TSLibraryRepairFile(NSString *path, NSString *bundledPath, TSLibraryFileCheck check)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *file = Destination(path);
    NSData *bundled = bundledPath ? [NSData dataWithContentsOfFile:bundledPath] : nil;
    BOOL directory = NO;
    BOOL exists = [fm fileExistsAtPath:file isDirectory:&directory];
    NSData *data = exists && !directory ? [NSData dataWithContentsOfFile:file] : nil;
    if (data && check(data, bundled)) return YES;
    // Missing or damaged: keep what is there, then put the copy inside TeXShop in its place.
    BOOL damaged = exists || [fm attributesOfItemAtPath:file error:NULL] != nil;
    if (damaged) BackUp(file);
    if (!bundled) return NO;
    [fm createDirectoryAtPath:file.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    BOOL restored = [bundled writeToFile:file options:NSDataWritingAtomic error:NULL];
    NSLog(@"TeXShop restored %@ from its own copy%@", path.stringByAbbreviatingWithTildeInPath, damaged ? @"; the damaged file is in Backups" : @"");
    return restored;
}

static void Repair(NSString *relative, TSLibraryFileCheck check)
{
    NSString *path = [[TSLibraryFolder stringByAppendingPathComponent:relative] stringByExpandingTildeInPath];
    TSLibraryRepairFile(path, TSLibraryBundledPath(relative), check);
}

void TSLibraryRepairAll(void)
{
    Repair(@"Macros/Macros_Latex.plist", TSLibraryMacrosCheck());
    Repair(@"LatexPanel/completion.plist", TSLibraryShapeOfBundledCheck());
    Repair(@"MatrixPanel/matrixpanel_1.plist", TSLibraryShapeOfBundledCheck());
    Repair(@"Keyboard/autocompletion.plist", TSLibraryStringDictionaryCheck());
    Repair(@"Menus/KeyEquivalents.plist", TSLibraryDictionaryCheck());
    Repair(@"CommandCompletion/CommandCompletion.txt", TSLibraryReadableCheck());
    Repair(@"CommandCompletion/CommandCompletionXML.txt", TSLibraryReadableCheck());
    Repair(@"Themes/LiteTheme.plist", TSLibraryThemeCheck());
    Repair(@"Themes/DarkTheme.plist", TSLibraryThemeCheck());
    Repair(@"SpellCheck/SpellingExclusions.txt", TSLibraryUTF8TextCheck());
    Repair(@"HTML/Help.html", TSLibraryReadableCheck());
}
