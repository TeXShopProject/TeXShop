// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSThemeFileStore.h"
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
    return [colors isKindOfClass:NSDictionary.class] ? colors : nil;
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
        NSMutableDictionary<NSString *, id> *colors = [([self readTitle:title] ?: before) mutableCopy];
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
        colors[@"Title"] = title;
        NSError *accessError = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:colors format:NSPropertyListXMLFormat_v1_0 options:0 error:&accessError];
        if (data != nil && [data writeToURL:fileURL options:NSDataWritingAtomic error:&accessError])
            written = [colors copy];
        writeError = accessError;
    }];
    if (written == nil && error != NULL) *error = writeError ?: coordinationError;
    return written;
}
static NSError *TSThemeStoreError(NSInteger code, NSString *title)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:@{NSFilePathErrorKey: title}];
}
- (NSArray<NSString *> *)titles
{
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.directory.path ?: @"" error:NULL]) {
        if (![name.pathExtension isEqualToString:@"plist"] || [name hasPrefix:@"."]) continue;
        // The file system may give a name decomposed (NFD); the names kept in the settings are composed.
        NSString *title = name.stringByDeletingPathExtension.precomposedStringWithCanonicalMapping;
        if ([self URLForTitle:title] != nil && ![titles containsObject:title]) [titles addObject:title];
    }
    [titles sortUsingSelector:@selector(localizedStandardCompare:)];
    return titles;
}
- (BOOL)hasTitle:(NSString *)title except:(nullable NSString *)except
{
    for (NSString *existing in [self titles]) {
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
- (BOOL)renameTitle:(NSString *)title to:(NSString *)newTitle error:(NSError **)error
{
    if ([title isEqualToString:newTitle]) return YES;
    NSURL *from = [self URLForTitle:title], *to = [self URLForTitle:newTitle];
    if (from == nil || to == nil) {
        if (error != NULL) *error = TSThemeStoreError(NSFileWriteInvalidFileNameError, newTitle);
        return NO;
    }
    if ([self hasTitle:newTitle except:title]) {
        if (error != NULL) *error = TSThemeStoreError(NSFileWriteFileExistsError, newTitle);
        return NO;
    }
    NSDictionary<NSString *, id> *colors = [self readTitle:title];
    if (colors == nil) {
        if (error != NULL) *error = TSThemeStoreError(NSFileReadCorruptFileError, title);
        return NO;
    }
    // The file keeps its title inside it.
    NSMutableDictionary<NSString *, id> *renamed = [colors mutableCopy];
    renamed[@"Title"] = newTitle;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:renamed format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (data == nil || ![NSFileManager.defaultManager moveItemAtURL:from toURL:to error:error]) return NO;
    if (![data writeToURL:to options:NSDataWritingAtomic error:error]) {
        [NSFileManager.defaultManager moveItemAtURL:to toURL:from error:NULL];
        return NO;
    }
    return YES;
}
- (BOOL)trashTitle:(NSString *)title error:(NSError **)error
{
    NSURL *url = [self URLForTitle:title];
    if (url == nil) {
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
    NSString *base = url.URLByDeletingPathExtension.lastPathComponent ?: @"";
    NSString *title = [self availableTitleForTitle:base];
    return [self writeColors:colors title:title error:error] ? title : nil;
}
@end
