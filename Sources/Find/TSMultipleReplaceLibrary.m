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

/// The table of the samples' names and translations: its keys are the file names of the sets and the English notes.
static NSString *const TSMultipleReplaceSamplesTable = @"MultipleReplaceSamples";

@interface TSMultipleReplaceLibrary ()
/// The samples are considered once, by the first listing.
@property (nonatomic) BOOL samplesConsidered;
@end

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

- (NSBundle *)samplesBundle
{
    return _samplesBundle ?: NSBundle.mainBundle;
}

- (NSArray<NSString *> *)setNames
{
    if (!self.samplesConsidered) {
        self.samplesConsidered = YES;
        [self installSamples];
    }
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.directory includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSURL *file in files)
        if ([file.pathExtension isEqualToString:TSMultipleReplaceLibrary.fileExtension])
            // The file system may give the name decomposed (é as e and U+0301, Hangul as jamo); a name is
            // compared with the names that were saved, chosen and typed, which are composed.
            [names addObject:file.URLByDeletingPathExtension.lastPathComponent.precomposedStringWithCanonicalMapping ?: @""];
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

/// A bundled sample with its notes translated.
- (TSRegexMultipleReplace *)translatedSample:(TSRegexMultipleReplace *)sample
{
    NSMutableArray<TSRegexReplacementRule *> *rules = [NSMutableArray arrayWithCapacity:sample.rules.count];
    for (TSRegexReplacementRule *rule in sample.rules) {
        NSString *note = rule.note ? [self.samplesBundle localizedStringForKey:(NSString *_Nonnull)rule.note value:rule.note table:TSMultipleReplaceSamplesTable] : nil;
        [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:rule.findString replaceString:rule.replaceString
                                                      usesRegularExpression:rule.usesRegularExpression ignoresCase:rule.ignoresCase
                                                                    enabled:rule.enabled note:note]];
    }
    return [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:sample.textualOptions
                                regularExpressionOptions:sample.regularExpressionOptions replacementSyntax:sample.replacementSyntax];
}

- (BOOL)installSamples
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *samples = self.samplesDirectory;
    // Only into a folder that does not exist yet: an empty one means that the user removed every set.
    if (!samples || [manager fileExistsAtPath:self.directory.path ?: @""])
        return NO;
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *file in [manager contentsOfDirectoryAtURL:(NSURL *_Nonnull)samples includingPropertiesForKeys:nil
                                                  options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL] ?: @[])
        if ([file.pathExtension isEqualToString:TSMultipleReplaceLibrary.fileExtension])
            [files addObject:file];
    NSURL *parent = self.directory.URLByDeletingLastPathComponent;
    if (files.count == 0 || !parent || ![manager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:NULL])
        return NO;
    NSString *hidden = [NSString stringWithFormat:@".%@-%@", self.directory.lastPathComponent, NSUUID.UUID.UUIDString];
    NSURL *staging = [parent URLByAppendingPathComponent:hidden isDirectory:YES];
    if (![manager createDirectoryAtURL:staging withIntermediateDirectories:NO attributes:nil error:NULL])
        return NO;
    BOOL written = YES;
    for (NSURL *file in files) {
        NSData *data = [NSData dataWithContentsOfURL:file];
        TSRegexMultipleReplace *sample = data ? [[TSRegexMultipleReplace alloc] initWithJSONData:(NSData *_Nonnull)data error:NULL] : nil;
        // The file's name is a key (ASCII, so that any archiver unpacks the sources); the table names the set.
        NSString *key = file.URLByDeletingPathExtension.lastPathComponent ?: @"";
        NSString *name = [self.samplesBundle localizedStringForKey:key value:key table:TSMultipleReplaceSamplesTable];
        if (![TSMultipleReplaceLibrary isValidName:name])
            name = key;
        NSURL *target = [[staging URLByAppendingPathComponent:name isDirectory:NO] URLByAppendingPathExtension:TSMultipleReplaceLibrary.fileExtension];
        if (!sample || ![TSMultipleReplaceLibrary isValidName:name]
            || ![[self translatedSample:(TSRegexMultipleReplace *_Nonnull)sample].JSONData writeToURL:target options:NSDataWritingWithoutOverwriting error:NULL]) {
            written = NO;
            break;
        }
    }
    // A move does not replace a folder that appeared meanwhile.
    written = written && [manager moveItemAtURL:staging toURL:self.directory error:NULL];
    if (!written)
        [manager removeItemAtURL:staging error:NULL];
    return written;
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
