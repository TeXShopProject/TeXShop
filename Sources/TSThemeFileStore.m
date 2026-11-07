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
    if (title.length == 0 || [title isEqualToString:@"."] || [title isEqualToString:@".."] ||
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
    if (![url.URLByResolvingSymlinksInPath.URLByDeletingLastPathComponent isEqual:self.directory.URLByResolvingSymlinksInPath]) return nil;
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
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}
@end
