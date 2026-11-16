// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootReplace.h"
#include <sys/xattr.h>
#include <sys/stat.h>
#include <errno.h>

NSErrorDomain const TSTeXRootReplaceErrorDomain = @"TSTeXRootReplaceErrorDomain";

static NSError *TSReplaceError(TSTeXRootReplaceError code, NSURL *_Nullable url, NSError *_Nullable underlying)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (url)
        info[NSURLErrorKey] = url;
    if (underlying) {
        info[NSUnderlyingErrorKey] = underlying;
        info[NSLocalizedDescriptionKey] = underlying.localizedDescription;
    }
    return [NSError errorWithDomain:TSTeXRootReplaceErrorDomain code:code userInfo:info];
}

#pragma mark Plan

@interface TSTeXRootReplaceFile ()
@property (nonatomic, readwrite) TSTeXRootProjectFile *file;
@property (nonatomic, readwrite, getter=isOpenDocument) BOOL openDocument;
@property (nonatomic, readwrite) NSUInteger numberOfItems;
@property (nonatomic, readwrite, copy) NSArray<TSRegexFindReplacement *> *replacements;
@property (nonatomic, readwrite, copy) NSString *originalText;
@property (nonatomic, readwrite, copy) NSString *replacedText;
@property (nonatomic, readwrite, copy, nullable) NSData *replacedData;
@property (nonatomic, readwrite, copy, nullable) NSData *originalSHA256;
@end

@implementation TSTeXRootReplaceFile
- (instancetype)initPrivate { return [super init]; }
@end

@interface TSTeXRootReplacePlan ()
@property (nonatomic, readwrite, copy) NSArray<TSTeXRootReplaceFile *> *files;
@end

@implementation TSTeXRootReplacePlan

- (instancetype)initPrivate { return [super init]; }

+ (nullable instancetype)planWithResults:(NSArray<TSTeXRootSearchFileResult *> *)results
                              isIncluded:(BOOL (NS_NOESCAPE ^)(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file))isIncluded
                                   codec:(TSTeXRootSourceCodec *)codec error:(NSError **)error
{
    NSMutableArray<TSTeXRootReplaceFile *> *onDisk = [NSMutableArray array], *open = [NSMutableArray array];
    for (TSTeXRootSearchFileResult *result in results) {
        if (result.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
            continue;
        NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
        NSMutableArray<TSRegexFindReplacement *> *replacements = [NSMutableArray array];
        [result.items enumerateObjectsUsingBlock:^(TSTeXRootSearchItem *item, NSUInteger index, BOOL *stop) {
            if (item.replacement && isIncluded(item, result)) {
                [indexes addIndex:index];
                [replacements addObject:[[TSRegexFindReplacement alloc] initWithRange:item.range string:(NSString *_Nonnull)item.replacement]];
            }
        }];
        if (indexes.count == 0)
            continue;
        TSTeXRootReplaceFile *file = [[TSTeXRootReplaceFile alloc] initPrivate];
        file.file = result.source.file;
        file.openDocument = result.source.isOpenDocument;
        file.numberOfItems = indexes.count;
        file.replacements = replacements;
        file.originalText = result.source.text;
        file.replacedText = [result textReplacingItemsAtIndexes:indexes];
        if (!file.openDocument) {
            TSTeXRootSourceReading *reading = result.source.file.reading;
            NSData *data = reading ? [codec dataForText:file.replacedText encoding:reading.encoding byteOrderMark:reading.byteOrderMark] : nil;
            if (!data) {
                if (error)
                    *error = TSReplaceError(TSTeXRootReplaceErrorUnencodable, result.source.file.url, nil);
                return nil;
            }
            file.replacedData = data;
            file.originalSHA256 = result.source.file.sha256;
            [onDisk addObject:file];
        } else {
            [open addObject:file];
        }
    }
    if (onDisk.count + open.count == 0)
        return nil;
    TSTeXRootReplacePlan *plan = [[TSTeXRootReplacePlan alloc] initPrivate];
    plan.files = [onDisk arrayByAddingObjectsFromArray:open];
    return plan;
}

- (NSUInteger)numberOfItems
{
    NSUInteger count = 0;
    for (TSTeXRootReplaceFile *file in self.files)
        count += file.numberOfItems;
    return count;
}

- (NSUInteger)numberOfFilesOnDisk
{
    NSUInteger count = 0;
    for (TSTeXRootReplaceFile *file in self.files)
        if (!file.openDocument)
            count++;
    return count;
}

- (NSArray<TSTeXRootReplaceFile *> *)filesOnDiskChangedInProject:(TSTeXRootProject *)project
{
    NSMutableArray<TSTeXRootReplaceFile *> *changed = [NSMutableArray array];
    for (TSTeXRootReplaceFile *planned in self.files) {
        if (planned.openDocument)
            continue;
        TSTeXRootProjectFile *now = nil;
        for (TSTeXRootProjectFile *file in project.files)
            if ([file.identifier isEqual:planned.file.identifier])
                now = file;
        TSTeXRootProjectFile *then = planned.file;
        BOOL same = now && !now.isOpen && now.sha256 && [now.sha256 isEqualToData:(NSData *_Nonnull)planned.originalSHA256]
            && now.size == then.size && (now.modificationDate == then.modificationDate || [now.modificationDate isEqualToDate:(NSDate *_Nonnull)then.modificationDate]);
        if (!same)
            [changed addObject:planned];
    }
    return changed;
}

@end

#pragma mark Attributes

/// The original's permissions, creation and modification dates and extended attributes, given to `target`.
static BOOL TSCopyAttributes(NSURL *source, NSURL *target, BOOL keepsModificationDate, NSError **error)
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *attributes = [manager attributesOfItemAtPath:(NSString *_Nonnull)source.path error:error];
    if (!attributes)
        return NO;
    NSMutableDictionary *copied = [NSMutableDictionary dictionary];
    for (NSFileAttributeKey key in @[NSFilePosixPermissions, NSFileCreationDate])
        if (attributes[key])
            copied[key] = attributes[key];
    if (keepsModificationDate && attributes[NSFileModificationDate])
        copied[NSFileModificationDate] = attributes[NSFileModificationDate];
    if (![manager setAttributes:copied ofItemAtPath:(NSString *_Nonnull)target.path error:error])
        return NO;
    const char *from = source.fileSystemRepresentation, *to = target.fileSystemRepresentation;
    ssize_t size = listxattr(from, NULL, 0, XATTR_NOFOLLOW);
    if (size < 0) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    NSMutableData *names = [NSMutableData dataWithLength:(NSUInteger)size];
    if (size > 0 && listxattr(from, names.mutableBytes, (size_t)size, XATTR_NOFOLLOW) != size) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    const char *name = names.bytes, *end = (const char *)names.bytes + size;
    while (name < end) {
        ssize_t length = getxattr(from, name, NULL, 0, 0, XATTR_NOFOLLOW);
        NSMutableData *value = [NSMutableData dataWithLength:(NSUInteger)MAX(length, 0)];
        if (length < 0 || (length > 0 && getxattr(from, name, value.mutableBytes, (size_t)length, 0, XATTR_NOFOLLOW) != length)
            || setxattr(to, name, value.bytes, value.length, 0, XATTR_NOFOLLOW) != 0) {
            if (error)
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return NO;
        }
        name += strlen(name) + 1;
    }
    return YES;
}

#pragma mark Backup

@implementation TSTeXRootBackup

+ (NSString *)folderNameForDate:(NSDate *)date
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    return [formatter stringFromDate:date];
}

+ (nullable NSURL *)backUpPlan:(TSTeXRootReplacePlan *)plan inFolder:(NSURL *)folder date:(NSDate *)date
              openDocumentData:(NSData *_Nullable (^)(TSTeXRootReplaceFile *file, BOOL *usedUTF8))openDocumentData
                         notes:(NSArray<NSString *> *_Nullable *_Nullable)notes
                  cancellation:(nullable BOOL (^)(void))isCancelled error:(NSError **)error
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *backups = [folder URLByAppendingPathComponent:@"TeXShop Backups" isDirectory:YES];
    NSError *problem = nil;
    if (![manager createDirectoryAtURL:backups withIntermediateDirectories:YES attributes:nil error:&problem]) {
        if (error)
            *error = TSReplaceError(TSTeXRootReplaceErrorBackup, backups, problem);
        return nil;
    }
    // Made anew, never an existing folder: mkdir fails when the name is taken, and the next number is tried.
    NSString *name = [self folderNameForDate:date];
    NSURL *made = nil;
    for (NSUInteger number = 1; number < 1000 && !made; number++) {
        NSString *candidate = number == 1 ? name : [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)number];
        NSURL *url = [backups URLByAppendingPathComponent:candidate isDirectory:YES];
        if (mkdir(url.fileSystemRepresentation, 0755) == 0)
            made = url;
        else if (errno != EEXIST) {
            if (error)
                *error = TSReplaceError(TSTeXRootReplaceErrorBackup, url, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
            return nil;
        }
    }
    if (!made) {
        if (error)
            *error = TSReplaceError(TSTeXRootReplaceErrorBackup, backups, nil);
        return nil;
    }
    NSMutableArray<NSString *> *written = [NSMutableArray array];
    NSMutableArray<NSString *> *utf8 = [NSMutableArray array];
    NSError *failure = nil;
    for (TSTeXRootReplaceFile *file in plan.files) {
        if (isCancelled && isCancelled()) {
            failure = TSReplaceError(TSTeXRootReplaceErrorStopped, nil, nil);
            break;
        }
        NSURL *target = [made URLByAppendingPathComponent:file.file.relativePath isDirectory:NO];
        if (![manager createDirectoryAtURL:(NSURL *_Nonnull)target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&problem]) {
            failure = TSReplaceError(TSTeXRootReplaceErrorBackup, file.file.url, problem);
            break;
        }
        NSData *data = nil;
        if (file.openDocument) {
            BOOL usedUTF8 = NO;
            data = openDocumentData(file, &usedUTF8);
            if (usedUTF8)
                [utf8 addObject:file.file.relativePath];
        } else {
            // The bytes approved, read now: what the backup keeps is what is about to be replaced.
            data = [NSData dataWithContentsOfURL:file.file.url options:NSDataReadingUncached error:&problem];
            if (data && ![[TSTeXRootProjectCollector sha256OfData:data] isEqualToData:(NSData *_Nonnull)file.originalSHA256]) {
                failure = TSReplaceError(TSTeXRootReplaceErrorChanged, file.file.url, nil);
                break;
            }
        }
        if (!data || ![data writeToURL:target options:NSDataWritingWithoutOverwriting error:&problem]) {
            failure = TSReplaceError(TSTeXRootReplaceErrorBackup, file.file.url, problem);
            break;
        }
        if (!TSCopyAttributes(file.file.url, target, YES, &problem)) {
            failure = TSReplaceError(TSTeXRootReplaceErrorBackup, file.file.url, problem);
            break;
        }
        [written addObject:file.file.relativePath];
    }
    if (failure) {
        // Nothing half made is left: the folder of this backup goes.
        [manager removeItemAtURL:made error:NULL];
        if (error)
            *error = failure;
        return nil;
    }
    if (notes)
        *notes = utf8;
    return made;
}

@end

#pragma mark Writing

@interface TSTeXRootDiskWriter ()
@property (nonatomic, readonly) TSTeXRootSourceCodec *codec;
@end

@implementation TSTeXRootDiskWriter

- (instancetype)initWithCodec:(TSTeXRootSourceCodec *)codec
{
    if (!(self = [super init]))
        return nil;
    _codec = codec;
    return self;
}

- (BOOL)writeFile:(TSTeXRootReplaceFile *)file error:(NSError **)error
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *url = file.file.url;
    NSData *data = file.replacedData;
    if (file.openDocument || !data || !file.originalSHA256) {
        if (error)
            *error = TSReplaceError(TSTeXRootReplaceErrorWrite, url, nil);
        return NO;
    }
    // A hidden file next to the original, whose name never ends in .tex.
    NSString *temporaryName = [NSString stringWithFormat:@".%@.texshop-%@", url.lastPathComponent, NSUUID.UUID.UUIDString];
    NSURL *temporary = [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:temporaryName isDirectory:NO];
    NSError *problem = nil;
    if (![data writeToURL:temporary options:NSDataWritingWithoutOverwriting error:&problem]) {
        if (error)
            *error = TSReplaceError(TSTeXRootReplaceErrorWrite, url, problem);
        return NO;
    }
    if (self.failsCopyingAttributes || !TSCopyAttributes(url, temporary, NO, &problem)) {
        [manager removeItemAtURL:temporary error:NULL];
        if (error)
            *error = TSReplaceError(TSTeXRootReplaceErrorAttributes, url, problem);
        return NO;
    }
    __block NSError *failure = nil;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:&coordinationError byAccessor:^(NSURL *writing) {
        if (self.beforeCheck)
            self.beforeCheck(writing);
        // Check 3 of §2.5.1: the file is still the one approved, read right before it is replaced.
        NSError *readError = nil;
        NSData *current = [NSData dataWithContentsOfURL:writing options:NSDataReadingUncached error:&readError];
        if (!current || ![[TSTeXRootProjectCollector sha256OfData:current] isEqualToData:(NSData *_Nonnull)file.originalSHA256]) {
            failure = TSReplaceError(TSTeXRootReplaceErrorChanged, url, readError);
            return;
        }
        NSError *replaceError = nil;
        if (![manager replaceItemAtURL:writing withItemAtURL:temporary backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly
                      resultingItemURL:NULL error:&replaceError])
            failure = TSReplaceError(TSTeXRootReplaceErrorWrite, url, replaceError);
    }];
    if (coordinationError && !failure)
        failure = TSReplaceError(TSTeXRootReplaceErrorWrite, url, coordinationError);
    if (failure) {
        [manager removeItemAtURL:temporary error:NULL];
        if (error)
            *error = failure;
        return NO;
    }
    // Read back strictly: the bytes written, and the text they read as, are those meant.
    NSData *written = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&problem];
    TSTeXRootSourceReading *reading = written ? [self.codec readData:(NSData *_Nonnull)written url:url verifyingRoundTrip:NO] : nil;
    if (!written || ![written isEqualToData:data] || !reading.decodedStrictly || ![reading.text isEqualToString:file.replacedText]) {
        if (error)
            *error = TSReplaceError(TSTeXRootReplaceErrorVerification, url, problem);
        return NO;
    }
    return YES;
}

@end

#pragma mark Mapping

@implementation TSTeXRootReplaceMapping

+ (NSArray<NSValue *> *)ranges:(NSArray<NSValue *> *)ranges afterReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
{
    NSMutableArray<NSValue *> *moved = [NSMutableArray arrayWithCapacity:ranges.count];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        NSInteger shift = 0;
        for (TSRegexFindReplacement *replacement in replacements)
            if (NSMaxRange(replacement.range) <= range.location && !(replacement.range.length == 0 && replacement.range.location == range.location && range.length == 0))
                shift += (NSInteger)replacement.string.length - (NSInteger)replacement.range.length;
        [moved addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)((NSInteger)range.location + shift), range.length)]];
    }
    return moved;
}

+ (BOOL)range:(NSRange)a overlapsRange:(NSRange)b
{
    if (a.length > 0 && b.length > 0)
        return a.location < NSMaxRange(b) && b.location < NSMaxRange(a);
    if (a.length == 0)
        return a.location >= b.location && a.location <= NSMaxRange(b);
    return b.location >= a.location && b.location <= NSMaxRange(a);
}

@end
