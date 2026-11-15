// The version of the bundled files last copied into ~/Library/TeXShop.
#import "TSLibraryVersion.h"

static NSString *TSLibraryVersionFile(NSString *folder)
{
    return [[folder stringByAppendingPathComponent:@".Version"] stringByStandardizingPath];
}

NSString *TSLibraryVersionInFolder(NSString *folder)
{
    NSString *text = [NSString stringWithContentsOfFile:TSLibraryVersionFile(folder) encoding:NSUTF8StringEncoding error:NULL];
    NSString *version = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return version.length ? version : nil;
}

// Display versions in order: 5.59 < 5.60 beta-10 (or 5.60b10) < 5.60 < 5.60.1 < 6.00 beta-1 < 6.00 beta-2 < 6.00.
// The first two parts are a decimal number, as the earlier .Version files were read (5.6 is 5.60).
// Returns NO when the version has another form.
static BOOL TSLibraryVersionParts(NSString *version, double *number, NSArray<NSNumber *> **parts)
{
    static NSRegularExpression *form;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        form = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+(?:\\.\\d+)?)((?:\\.\\d+){0,3})(?:(?: beta-|b)(\\d+)((?:\\.\\d+){0,3}))?$" options:0 error:NULL];
    });
    NSTextCheckingResult *match = [form firstMatchInString:version options:0 range:NSMakeRange(0, version.length)];
    if (!match)
        return NO;
    NSString *(^group)(NSUInteger) = ^NSString *(NSUInteger i) {
        NSRange r = [match rangeAtIndex:i];
        return r.location == NSNotFound ? @"" : [version substringWithRange:r];
    };
    NSMutableArray<NSNumber *> *list = [NSMutableArray array];
    // Up to three further parts, missing ones 0, so 6.00 and 6.00.0 are the same and 6.00 < 6.00.1.
    void (^add)(NSString *) = ^(NSString *dotted) {
        NSArray<NSString *> *items = [[dotted componentsSeparatedByString:@"."] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        for (NSUInteger i = 0; i < 3; i++)
            [list addObject:@(i < items.count ? items[i].integerValue : 0)];
    };
    *number = group(1).doubleValue;
    add(group(2));
    BOOL beta = group(3).length > 0;
    [list addObject:@(beta ? 0 : 1)];                        // a beta comes before its release
    [list addObject:@(beta ? group(3).integerValue : 0)];
    add(group(4));
    *parts = list;
    return YES;
}

BOOL TSLibraryNeedsUpdating(NSString *libraryVersion, NSString *applicationVersion)
{
    if (applicationVersion.length == 0)
        return NO;
    libraryVersion = [libraryVersion stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (libraryVersion.length == 0)
        return YES;
    // Earlier versions wrote only a number (5.59) and compared numbers; so do older applications
    // reading what is written now ("6.00 beta-1" reads as 6.0, not later than their own version).
    double library = libraryVersion.doubleValue, application = applicationVersion.doubleValue;
    NSArray<NSNumber *> *libraryParts, *applicationParts;
    if (TSLibraryVersionParts(libraryVersion, &library, &libraryParts) && TSLibraryVersionParts(applicationVersion, &application, &applicationParts)) {
        if (application > library + 0.005)
            return YES;
        if (application < library - 0.005)
            return NO;
        NSUInteger count = MAX(libraryParts.count, applicationParts.count);
        for (NSUInteger i = 0; i < count; i++) {
            NSInteger a = i < applicationParts.count ? applicationParts[i].integerValue : 0;
            NSInteger l = i < libraryParts.count ? libraryParts[i].integerValue : 0;
            if (a != l)
                return a > l;
        }
        return NO;
    }
    // Another form: a later number, or another version of the same number.
    if (application > library + 0.005)
        return YES;
    if (application < library - 0.005)
        return NO;
    return ![libraryVersion isEqualToString:applicationVersion];
}

BOOL TSLibraryRecordVersion(NSString *folder, NSString *applicationVersion)
{
    NSString *text = [applicationVersion stringByAppendingString:@"\n"];
    return [text writeToFile:TSLibraryVersionFile(folder) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
