// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSThemeFileStore.h"
static NSError *TSThemeStoreError(NSInteger code, NSString *title)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:@{NSFilePathErrorKey: title}];
}
static BOOL TSThemeIsRegularFile(NSURL *url)
{
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path ?: @"" error:NULL];
    return [attributes[NSFileType] isEqual:NSFileTypeRegular];
}
@implementation TSThemeFileStore
- (instancetype)initWithDirectory:(NSURL *)directory
{
    self = [super init];
    if (self == nil) return nil;
    NSURL *standardized = directory.URLByStandardizingPath;
    if (standardized == nil) return nil;
    _directory = [standardized copy];
    return self;
}
- (nullable NSURL *)URLForTitle:(NSString *)title
{
    if (title.length == 0 || [title hasPrefix:@"."] || [title isEqualToString:@"."] || [title isEqualToString:@".."] ||
        [title rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:"]].location != NSNotFound ||
        [title rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    NSString *filename = [title stringByAppendingPathExtension:@"plist"];
    if (filename == nil) return nil;
    NSURL *url = [self.directory URLByAppendingPathComponent:filename];
    // Existing symlinks must not redirect either editing or cloning outside Colors.
    NSString *path = url.path;
    if (path == nil) return nil;
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if ([attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) return nil;
    if (![url.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath isEqual:self.directory.URLByResolvingSymlinksInPath]) return nil;
    return url;
}
- (nullable NSDictionary<NSString *, id> *)readTitle:(NSString *)title
{
    NSURL *url = [self URLForTitle:title];
    if (url == nil) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data == nil) return nil;
    id colors = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if (![colors isKindOfClass:NSDictionary.class]) return nil;
    BOOL (^accepts)(NSDictionary<NSString *, id> *) = self.acceptsColors;
    return accepts == nil || accepts(colors) ? colors : nil;
}
- (BOOL)writeColors:(NSDictionary<NSString *, id> *)colors title:(NSString *)title error:(NSError **)error
{
    NSURL *url = [self URLForTitle:title];
    if (url == nil) {
        if (error != NULL) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError userInfo:nil];
        return NO;
    }
    NSMutableDictionary<NSString *, id> *copy = [colors mutableCopy];
    copy[@"Title"] = title;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:copy format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (data == nil) return NO;
    // Coordinated with the update of the bundled themes at the launch of another TeXShop.
    __block BOOL written = NO;
    __block NSError *writeError = nil;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:&coordinationError byAccessor:^(NSURL *fileURL) {
        NSError *accessError = nil;
        written = [data writeToURL:fileURL options:NSDataWritingAtomic error:&accessError];
        writeError = accessError;
    }];
    if (!written && error != NULL) *error = writeError ?: coordinationError;
    return written;
}
// Another TeXShop, the one-time update of the bundled colors or another save in this TeXShop may have changed other
// colors of the file since it was read. The file is read again, the changed colors put in it and the result written in
// one coordinated write, so that two saves that change different colors keep both.
- (nullable NSDictionary<NSString *, id> *)writeChangesFrom:(NSDictionary<NSString *, id> *)before to:(NSDictionary<NSString *, id> *)after title:(NSString *)title error:(NSError **)error
{
    NSURL *url = [self URLForTitle:title];
    if (url == nil) {
        if (error != NULL) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError userInfo:nil];
        return nil;
    }
    __block NSDictionary<NSString *, id> *written = nil;
    __block NSError *writeError = nil;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:&coordinationError byAccessor:^(NSURL *fileURL) {
        // A theme renamed or deleted elsewhere is not made again under its old name.
        if (!TSThemeIsRegularFile(fileURL)) {
            writeError = TSThemeStoreError(NSFileNoSuchFileError, title);
            return;
        }
        // A file that cannot be read (changed elsewhere into something else) is kept as it is: the save fails.
        NSDictionary<NSString *, id> *current = [self readTitle:title];
        if (current == nil) {
            writeError = TSThemeStoreError(NSFileReadCorruptFileError, title);
            return;
        }
        NSMutableDictionary<NSString *, id> *colors = [current mutableCopy];
        NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:after.allKeys];
        [keys addObjectsFromArray:before.allKeys];
        [keys removeObject:@"Title"];
        for (NSString *key in keys) {
            id now = after[key];
            if (now == before[key] || [now isEqual:before[key]]) continue;
            if (now != nil)
                colors[key] = now;
            else
                [colors removeObjectForKey:key];
        }
        // The title inside is the file's name as the folder has it: a rename elsewhere in case only (in Finder or in
        // another TeXShop) leaves a file that `title` still finds.
        colors[@"Title"] = [self existingTitleForTitle:title] ?: title;
        NSError *accessError = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:colors format:NSPropertyListXMLFormat_v1_0 options:0 error:&accessError];
        if (data != nil && [data writeToURL:fileURL options:NSDataWritingAtomic error:&accessError])
            written = [colors copy];
        writeError = accessError;
    }];
    if (written == nil && error != NULL) *error = writeError ?: coordinationError;
    return written;
}
// Every name in the folder that a theme could have, in any case of its extension and whatever the item is: a new
// theme never takes one of them.
- (NSArray<NSString *> *)takenTitles
{
    NSMutableArray<NSString *> *taken = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.directory.path ?: @"" error:NULL])
        if ([name.pathExtension compare:@"plist" options:NSCaseInsensitiveSearch] == NSOrderedSame)
            [taken addObject:name.stringByDeletingPathExtension.precomposedStringWithCanonicalMapping];
    return taken;
}
- (NSArray<NSString *> *)titles
{
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.directory.path ?: @"" error:NULL]) {
        if (![name.pathExtension isEqualToString:@"plist"] || [name hasPrefix:@"."]) continue;
        // The file system may give a name decomposed (NFD); the names kept in the settings are composed.
        NSString *title = name.stringByDeletingPathExtension.precomposedStringWithCanonicalMapping;
        NSURL *url = [self URLForTitle:title];
        // A folder or anything else that is not a file is not a theme.
        if (url != nil && TSThemeIsRegularFile(url) && ![titles containsObject:title]) [titles addObject:title];
    }
    [titles sortUsingSelector:@selector(localizedStandardCompare:)];
    return titles;
}
- (nullable NSString *)existingTitleForTitle:(NSString *)title
{
    NSString *composed = title.precomposedStringWithCanonicalMapping;
    NSArray<NSString *> *titles = [self titles];
    if ([titles containsObject:composed]) return composed;
    for (NSString *listed in titles)
        if ([listed caseInsensitiveCompare:composed] == NSOrderedSame) return listed;
    return nil;
}
- (BOOL)hasTitle:(NSString *)title except:(nullable NSString *)except
{
    for (NSString *existing in [self takenTitles]) {
        if (except != nil && [existing isEqualToString:(NSString *_Nonnull)except]) continue;
        if ([existing compare:title options:NSCaseInsensitiveSearch] == NSOrderedSame) return YES;
    }
    return NO;
}
- (NSString *)availableTitleForTitle:(NSString *)title
{
    if (![self hasTitle:title except:nil]) return title;
    for (NSUInteger number = 2; ; number++) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %lu", title, (unsigned long)number];
        if (![self hasTitle:candidate except:nil]) return candidate;
    }
}
- (nullable NSString *)addColors:(NSDictionary<NSString *, id> *)colors title:(NSString *)title error:(NSError **)error
{
    // The file is created only where none is: another TeXShop may take the free name meanwhile, and the next one
    // is tried.
    for (NSUInteger attempt = 0; attempt < 100; attempt++) {
        NSString *candidate = [self availableTitleForTitle:title];
        NSURL *url = [self URLForTitle:candidate];
        if (url == nil) {
            if (error != NULL) *error = TSThemeStoreError(NSFileWriteInvalidFileNameError, candidate);
            return nil;
        }
        NSMutableDictionary<NSString *, id> *copy = [colors mutableCopy];
        copy[@"Title"] = candidate;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:copy format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
        if (data == nil) return nil;
        __block BOOL written = NO;
        __block NSError *writeError = nil;
        NSError *coordinationError = nil;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateWritingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *fileURL) {
            NSError *accessError = nil;
            written = [data writeToURL:fileURL options:NSDataWritingWithoutOverwriting error:&accessError];
            writeError = accessError;
        }];
        if (written) return candidate;
        NSError *failure = writeError ?: coordinationError;
        if (!([failure.domain isEqualToString:NSCocoaErrorDomain] && failure.code == NSFileWriteFileExistsError) &&
            !([failure.domain isEqualToString:NSPOSIXErrorDomain] && failure.code == EEXIST)) {
            if (error != NULL) *error = failure;
            return nil;
        }
    }
    if (error != NULL) *error = TSThemeStoreError(NSFileWriteFileExistsError, title);
    return nil;
}
- (BOOL)renameTitle:(NSString *)title to:(NSString *)proposed error:(NSError **)error
{
    NSString *newTitle = proposed.precomposedStringWithCanonicalMapping;
    if ([title isEqualToString:newTitle]) return YES;
    NSURL *from = [self URLForTitle:title], *to = [self URLForTitle:newTitle];
    if (from == nil || to == nil) {
        if (error != NULL) *error = TSThemeStoreError(NSFileWriteInvalidFileNameError, newTitle);
        return NO;
    }
    // The theme is read, moved and given its new title inside it in one coordinated write: a color saved meanwhile
    // (writeChangesFrom:) waits for it, and one saved before it is kept.
    __block BOOL renamed = NO;
    __block NSError *renameError = nil;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:from options:NSFileCoordinatorWritingForMoving writingItemAtURL:to options:NSFileCoordinatorWritingForReplacing
                                      error:&coordinationError byAccessor:^(NSURL *oldURL, NSURL *newURL) {
        if ([self hasTitle:newTitle except:title]) {
            renameError = TSThemeStoreError(NSFileWriteFileExistsError, newTitle);
            return;
        }
        NSDictionary<NSString *, id> *colors = TSThemeIsRegularFile(oldURL) ? [self readTitle:title] : nil;
        if (colors == nil) {
            renameError = TSThemeStoreError(NSFileReadCorruptFileError, title);
            return;
        }
        NSMutableDictionary<NSString *, id> *titled = [colors mutableCopy];
        titled[@"Title"] = newTitle;
        NSError *accessError = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:titled format:NSPropertyListXMLFormat_v1_0 options:0 error:&accessError];
        if (data == nil || ![NSFileManager.defaultManager moveItemAtURL:oldURL toURL:newURL error:&accessError]) {
            renameError = accessError;
            return;
        }
        // Not reported as moved: a save waiting for the old name then finds no file and fails (writeChangesFrom:),
        // instead of writing the old title into the renamed file.
        if (![data writeToURL:newURL options:NSDataWritingAtomic error:&accessError]) {
            [NSFileManager.defaultManager moveItemAtURL:newURL toURL:oldURL error:NULL];
            renameError = accessError;
            return;
        }
        renamed = YES;
    }];
    if (!renamed && error != NULL) *error = renameError ?: coordinationError;
    return renamed;
}
- (BOOL)trashTitle:(NSString *)title error:(NSError **)error
{
    NSURL *url = [self URLForTitle:title];
    // Only a theme's file is moved to the Trash, never a folder that has a theme's name.
    if (url == nil || !TSThemeIsRegularFile(url)) {
        if (error != NULL) *error = TSThemeStoreError(NSFileNoSuchFileError, title);
        return NO;
    }
    return [NSFileManager.defaultManager trashItemAtURL:url resultingItemURL:NULL error:error];
}
- (BOOL)exportTitle:(NSString *)title toURL:(NSURL *)url error:(NSError **)error
{
    NSURL *from = [self URLForTitle:title];
    NSData *data = from != nil ? [NSData dataWithContentsOfURL:from options:0 error:error] : nil;
    if (data == nil) {
        if (from == nil && error != NULL) *error = TSThemeStoreError(NSFileNoSuchFileError, title);
        return NO;
    }
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}
- (nullable NSString *)importFileAtURL:(NSURL *)url check:(BOOL (^)(NSData *data))check error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (data == nil) return nil;
    id colors = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if (![colors isKindOfClass:NSDictionary.class] || !check(data)) {
        if (error != NULL) *error = TSThemeStoreError(NSFileReadCorruptFileError, url.lastPathComponent ?: @"");
        return nil;
    }
    NSString *base = url.URLByDeletingPathExtension.lastPathComponent.precomposedStringWithCanonicalMapping ?: @"";
    return [self addColors:colors title:base error:error];
}
@end
