// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMultipleReplaceLibrary.h"

/// The extension of a set's file, in one place: the content is CotEditor's replacement definition.
static NSString *const TSMultipleReplaceFileExtension = @"json";
/// CotEditor's own extension for the same content, read when a file is imported.
static NSString *const TSCotEditorFileExtension = @"cotrpl";

static NSError *TSLibraryError(NSString *key, NSString *english, NSString *name)
{
    NSString *format = [NSBundle.mainBundle localizedStringForKey:key value:english table:@"AdvancedFind"];
    return [NSError errorWithDomain:TSRegexFindErrorDomain code:TSRegexFindErrorInvalidDefinition
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:format, name]}];
}

@implementation TSMultipleReplaceLibrary

+ (NSString *)fileExtension
{
    return TSMultipleReplaceFileExtension;
}

- (instancetype)initWithDirectory:(NSURL *)directory
{
    if ((self = [super init])) {
        _directory = [directory copy];
        _usesTrash = YES;
    }
    return self;
}

- (NSURL *)URLForName:(NSString *)name
{
    return [[self.directory URLByAppendingPathComponent:name isDirectory:NO] URLByAppendingPathExtension:TSMultipleReplaceLibrary.fileExtension];
}

- (BOOL)createDirectory:(NSError **)error
{
    return [NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:nil error:error];
}

+ (BOOL)isValidName:(NSString *)name
{
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 && trimmed.length == name.length && ![name hasPrefix:@"."]
        && [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\n\r"]].location == NSNotFound;
}

- (NSArray<NSString *> *)setNames
{
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.directory includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSURL *file in files)
        if ([file.pathExtension isEqualToString:TSMultipleReplaceLibrary.fileExtension])
            [names addObject:file.URLByDeletingPathExtension.lastPathComponent ?: @""];
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (nullable TSRegexMultipleReplace *)setNamed:(NSString *)name error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfURL:[self URLForName:name] options:0 error:error];
    return data ? [[TSRegexMultipleReplace alloc] initWithJSONData:data error:error] : nil;
}

- (BOOL)saveSet:(TSRegexMultipleReplace *)set named:(NSString *)name error:(NSError **)error
{
    if (![TSMultipleReplaceLibrary isValidName:name]) {
        if (error)
            *error = TSLibraryError(@"MultipleReplace.BadName", @"“%@” cannot be the name of a set.", name);
        return NO;
    }
    return [self createDirectory:error] && [set.JSONData writeToURL:[self URLForName:name] options:NSDataWritingAtomic error:error];
}

- (BOOL)removeSetNamed:(NSString *)name error:(NSError **)error
{
    NSURL *url = [self URLForName:name];
    if (self.usesTrash)
        return [NSFileManager.defaultManager trashItemAtURL:url resultingItemURL:NULL error:error];
    return [NSFileManager.defaultManager removeItemAtURL:url error:error];
}

- (BOOL)renameSetNamed:(NSString *)name to:(NSString *)newName error:(NSError **)error
{
    if ([name isEqualToString:newName])
        return YES;
    if (![TSMultipleReplaceLibrary isValidName:newName]) {
        if (error)
            *error = TSLibraryError(@"MultipleReplace.BadName", @"“%@” cannot be the name of a set.", newName);
        return NO;
    }
    // A change of case only is allowed; any other existing set with the name is not replaced.
    BOOL sameFile = [name compare:newName options:NSCaseInsensitiveSearch] == NSOrderedSame;
    if (!sameFile && [NSFileManager.defaultManager fileExistsAtPath:[self URLForName:newName].path ?: @""]) {
        if (error)
            *error = TSLibraryError(@"MultipleReplace.NameTaken", @"A set named “%@” already exists.", newName);
        return NO;
    }
    return [NSFileManager.defaultManager moveItemAtURL:[self URLForName:name] toURL:[self URLForName:newName] error:error];
}

- (NSString *)availableNameForName:(NSString *)name
{
    NSArray<NSString *> *taken = self.setNames;
    BOOL (^isTaken)(NSString *) = ^BOOL(NSString *candidate) {
        for (NSString *existing in taken)
            if ([existing compare:candidate options:NSCaseInsensitiveSearch] == NSOrderedSame)
                return YES;
        return NO;
    };
    if (!isTaken(name))
        return name;
    for (NSUInteger number = 2; ; number++) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)number];
        if (!isTaken(candidate))
            return candidate;
    }
}

- (nullable NSString *)importFileAtURL:(NSURL *)url error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data)
        return nil;
    NSString *extension = url.pathExtension.lowercaseString;
    TSRegexMultipleReplace *set = nil;
    if ([extension isEqualToString:TSMultipleReplaceFileExtension] || [extension isEqualToString:TSCotEditorFileExtension])
        set = [[TSRegexMultipleReplace alloc] initWithJSONData:data error:error];
    else {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) {
            if (error)
                *error = TSLibraryError(@"MultipleReplace.NotText", @"“%@” is not UTF-8 text.", url.lastPathComponent);
            return nil;
        }
        set = [[TSRegexMultipleReplace alloc] initWithTabSeparatedText:text];
    }
    if (!set)
        return nil;
    NSString *base = url.URLByDeletingPathExtension.lastPathComponent;
    NSString *fallback = [NSBundle.mainBundle localizedStringForKey:@"MultipleReplace.Imported" value:@"Imported" table:@"AdvancedFind"];
    NSString *name = [self availableNameForName:[TSMultipleReplaceLibrary isValidName:base] ? base : fallback];
    return [self saveSet:set named:name error:error] ? name : nil;
}

- (BOOL)exportSetNamed:(NSString *)name toURL:(NSURL *)url error:(NSError **)error
{
    TSRegexMultipleReplace *set = [self setNamed:name error:error];
    return set && [set.JSONData writeToURL:url options:NSDataWritingAtomic error:error];
}

@end
