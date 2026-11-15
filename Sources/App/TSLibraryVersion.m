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

BOOL TSLibraryNeedsUpdating(NSString *libraryVersion, NSString *applicationVersion)
{
    if (applicationVersion.length == 0)
        return NO;
    libraryVersion = [libraryVersion stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (libraryVersion.length == 0)
        return YES;
    // Earlier versions wrote only a number (5.59); they compared numbers, and so do older
    // applications reading what is written now ("6.00 beta-1" reads as 6.0).
    double library = libraryVersion.doubleValue, application = applicationVersion.doubleValue;
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
