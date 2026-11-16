// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootProject.h"
#import "TSRootFileResolver.h"
#import <CommonCrypto/CommonDigest.h>
#include <stdlib.h>

static NSString *const TSTeXRootBackupFolderName = @"TeXShop Backups";

/// Latin 9, which TeXShop reads unreadable bytes in (the same value as its global NSISOLatin9StringEncoding).
static NSStringEncoding TSLatin9Encoding(void)
{
    return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9);
}

#pragma mark - Reading

@interface TSTeXRootSourceReading ()
- (instancetype)initWithEncoding:(NSStringEncoding)encoding byteOrderMark:(TSTeXRootByteOrderMark)byteOrderMark
                            text:(NSString *)text decodedStrictly:(BOOL)decodedStrictly roundTrips:(BOOL)roundTrips;
@end

@implementation TSTeXRootSourceReading
- (instancetype)initWithEncoding:(NSStringEncoding)encoding byteOrderMark:(TSTeXRootByteOrderMark)byteOrderMark
                            text:(NSString *)text decodedStrictly:(BOOL)decodedStrictly roundTrips:(BOOL)roundTrips
{
    if ((self = [super init])) {
        _encoding = encoding;
        _byteOrderMark = byteOrderMark;
        _text = [text copy];
        _decodedStrictly = decodedStrictly;
        _roundTrips = roundTrips;
    }
    return self;
}
@end

@implementation TSTeXRootSourceCodec {
    NSStringEncoding (^_encodingForData)(NSData *, NSURL *);
    NSString * (^_textForEditing)(NSString *, NSStringEncoding);
    NSString * (^_textForSaving)(NSString *, NSStringEncoding);
}

- (instancetype)initWithEncodingForData:(NSStringEncoding (^)(NSData *data, NSURL *url))encodingForData
                         textForEditing:(NSString * (^)(NSString *text, NSStringEncoding encoding))textForEditing
                          textForSaving:(NSString * (^)(NSString *text, NSStringEncoding encoding))textForSaving
{
    if ((self = [super init])) {
        _encodingForData = [encodingForData copy];
        _textForEditing = [textForEditing copy];
        _textForSaving = [textForSaving copy];
    }
    return self;
}

+ (TSTeXRootByteOrderMark)byteOrderMarkOfData:(NSData *)data
{
    const unsigned char *bytes = data.bytes;
    if (data.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        return TSTeXRootByteOrderMarkUTF8;
    if (data.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
        return TSTeXRootByteOrderMarkUTF16BigEndian;
    if (data.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
        return TSTeXRootByteOrderMarkUTF16LittleEndian;
    return TSTeXRootByteOrderMarkNone;
}

- (TSTeXRootSourceReading *)readData:(NSData *)data url:(NSURL *)url
{
    return [self readData:data url:url verifyingRoundTrip:YES];
}

- (TSTeXRootSourceReading *)readData:(NSData *)data url:(NSURL *)url verifyingRoundTrip:(BOOL)verifies
{
    NSStringEncoding encoding = _encodingForData(data, url);
    TSTeXRootByteOrderMark mark = [TSTeXRootSourceCodec byteOrderMarkOfData:data];
    NSString *decoded = [[NSString alloc] initWithData:data encoding:encoding];
    BOOL strict = decoded != nil;
    if (!strict) {
        // As opening does: the bytes one by one, so that the file can at least be searched.
        decoded = [[NSString alloc] initWithData:data encoding:TSLatin9Encoding()] ?: @"";
        NSString *text = _textForEditing(decoded, TSLatin9Encoding());
        return [[TSTeXRootSourceReading alloc] initWithEncoding:encoding byteOrderMark:mark text:text
                                                decodedStrictly:NO roundTrips:NO];
    }
    NSString *text = _textForEditing(decoded, encoding);
    NSData *written = verifies ? [self dataForText:text encoding:encoding byteOrderMark:mark] : nil;
    return [[TSTeXRootSourceReading alloc] initWithEncoding:encoding byteOrderMark:mark text:text
                                            decodedStrictly:YES roundTrips:[written isEqualToData:data]];
}

- (nullable NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding
                   byteOrderMark:(TSTeXRootByteOrderMark)byteOrderMark
{
    NSString *saving = _textForSaving(text, encoding);
    if (encoding == NSUTF8StringEncoding && byteOrderMark == TSTeXRootByteOrderMarkUTF8) {
        NSData *body = [saving dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
        if (body == nil)
            return nil;
        NSMutableData *data = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [data appendData:body];
        return data;
    }
    if (encoding == NSUnicodeStringEncoding && (byteOrderMark == TSTeXRootByteOrderMarkUTF16BigEndian ||
                                               byteOrderMark == TSTeXRootByteOrderMarkUTF16LittleEndian)) {
        BOOL big = byteOrderMark == TSTeXRootByteOrderMarkUTF16BigEndian;
        NSData *body = [saving dataUsingEncoding:(big ? NSUTF16BigEndianStringEncoding : NSUTF16LittleEndianStringEncoding)
                            allowLossyConversion:NO];
        if (body == nil)
            return nil;
        NSMutableData *data = [NSMutableData dataWithBytes:(big ? "\xFE\xFF" : "\xFF\xFE") length:2];
        [data appendData:body];
        return data;
    }
    return [saving dataUsingEncoding:encoding allowLossyConversion:NO];
}

@end

#pragma mark - Results

@interface TSTeXRootProjectFile ()
@property (nonatomic, readwrite, copy) NSURL *url;
@property (nonatomic, readwrite, copy) NSString *relativePath;
@property (nonatomic, readwrite) BOOL isRoot;
@property (nonatomic, readwrite) id<NSObject, NSCopying> identifier;
@property (nonatomic, readwrite) BOOL isOpen;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, nullable) TSTeXRootSourceReading *reading;
@property (nonatomic, readwrite, copy, nullable) NSData *sha256;
@property (nonatomic, readwrite) unsigned long long size;
@property (nonatomic, readwrite, copy, nullable) NSDate *modificationDate;
@property (nonatomic, readwrite) TSTeXRootSearchOnlyReason searchOnlyReason;
@end

@implementation TSTeXRootProjectFile
- (instancetype)initPrivate { return [super init]; }
@end

@interface TSTeXRootUnreadableItem ()
@property (nonatomic, readwrite, copy) NSURL *url;
@property (nonatomic, readwrite, copy) NSString *relativePath;
@property (nonatomic, readwrite) TSTeXRootUnreadableReason reason;
@property (nonatomic, readwrite, nullable) NSError *error;
@end

@implementation TSTeXRootUnreadableItem
- (instancetype)initPrivate { return [super init]; }
@end

@interface TSTeXRootProject ()
@property (nonatomic, readwrite, copy) NSURL *rootURL;
@property (nonatomic, readwrite, copy) NSURL *folderURL;
@property (nonatomic, readwrite, nullable) TSTeXRootProjectFile *rootFile;
@property (nonatomic, readwrite, copy) NSArray<TSTeXRootProjectFile *> *files;
@property (nonatomic, readwrite, copy) NSArray<TSTeXRootUnreadableItem *> *unreadableItems;
@end

@implementation TSTeXRootProject
- (instancetype)initPrivate { return [super init]; }
@end

#pragma mark - Collector

static id _Nullable TSTeXRootIdentifier(NSURL *url)
{
    id identifier = nil;
    if (![url getResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:NULL])
        return nil;
    return identifier;
}

/// The real path, with every symbolic link resolved and "/private" kept (unlike -stringByResolvingSymlinksInPath).
static NSString *TSTeXRootRealPath(NSString *path)
{
    char *resolved = realpath(path.fileSystemRepresentation, NULL);
    if (resolved == NULL)
        return path;
    NSString *result = [NSFileManager.defaultManager stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
    free(resolved);
    return result;
}

/// SHA-256 of all of `data`, given to CommonCrypto in pieces no longer than `pieceLength` (a CC_LONG is 32 bits).
static NSData *TSTeXRootSHA256(NSData *data, NSUInteger pieceLength)
{
    CC_SHA256_CTX context;
    CC_SHA256_CTX *running = &context;   // The block updates this one, not a copy of it.
    CC_SHA256_Init(running);
    [data enumerateByteRangesUsingBlock:^(const void *bytes, NSRange range, BOOL *stop) {
        for (NSUInteger offset = 0; offset < range.length; offset += pieceLength) {
            NSUInteger length = MIN(pieceLength, range.length - offset);
            CC_SHA256_Update(running, (const unsigned char *)bytes + offset, (CC_LONG)length);
        }
    }];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, running);
    return [NSData dataWithBytes:digest length:sizeof digest];
}

static const NSUInteger TSTeXRootHashPiece = 1u << 30;

@interface TSTeXRootProjectCollector ()
@property (atomic, readwrite, getter=isCancelled) BOOL cancelled;
@property (nonatomic, readwrite) TSTeXRootCollectionFailure failure;
@property (nonatomic, readwrite) TSTeXRootProblem rootProblem;
@end

@implementation TSTeXRootProjectCollector {
    NSURL *_rootURL;
    NSURL *_folderURL;
    TSTeXRootSourceCodec *_codec;
    BOOL _allowsSourceDoc;
    NSString *_jobNameToken;
    NSFileCoordinator *_currentCoordinator;  // guarded by self
}

+ (TSTeXRootProblem)problemWithRootURL:(NSURL *)rootURL
{
    NSDictionary *values = [rootURL resourceValuesForKeys:@[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey] error:NULL];
    if (values == nil)
        return TSTeXRootProblemMissing;
    if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue])
        return TSTeXRootProblemNotRegularFile;
    if (![self isCandidateName:rootURL.lastPathComponent ?: @""])
        return TSTeXRootProblemNotTeXFile;
    return TSTeXRootProblemNone;
}

+ (NSData *)sha256OfData:(NSData *)data
{
    return TSTeXRootSHA256(data, TSTeXRootHashPiece);
}

+ (NSData *)sha256OfData:(NSData *)data pieceLength:(NSUInteger)pieceLength
{
    return TSTeXRootSHA256(data, MAX(pieceLength, (NSUInteger)1));
}

+ (BOOL)isCandidateName:(NSString *)name
{
    return [name.pathExtension isEqualToString:@"tex"] && name.length > 4;
}

- (instancetype)initWithRootURL:(NSURL *)rootURL codec:(TSTeXRootSourceCodec *)codec
              allowsSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken
{
    if ((self = [super init])) {
        _rootURL = [NSURL fileURLWithPath:TSTeXRootRealPath(rootURL.path)];
        _folderURL = _rootURL.URLByDeletingLastPathComponent;
        _codec = codec;
        _allowsSourceDoc = allowsSourceDoc;
        _jobNameToken = [jobNameToken copy];
        _openDocumentTexts = @{};
    }
    return self;
}

- (void)cancel
{
    self.cancelled = YES;
    @synchronized (self) {
        [_currentCoordinator cancel];
    }
}

- (NSString *)relativePathOfURL:(NSURL *)url
{
    // The folder is a real path; so is the parent of an item met in it (folders are not followed through links).
    // The names are compared one by one and the rest is kept as it is, so that a name stored composed (é) and
    // spelled decomposed (e + ́), or the other way round, never shifts the result by a character.
    NSString *name = url.lastPathComponent ?: @"";
    NSArray<NSString *> *folder = _folderURL.path.pathComponents;
    NSArray<NSString *> *parent = TSTeXRootRealPath(url.path.stringByDeletingLastPathComponent).pathComponents;
    if (parent.count < folder.count)
        return name;
    for (NSUInteger i = 0; i < folder.count; i++)
        if ([parent[i] compare:folder[i]] != NSOrderedSame)
            return name;
    NSArray *rest = [parent subarrayWithRange:NSMakeRange(folder.count, parent.count - folder.count)];
    return [NSString pathWithComponents:[rest arrayByAddingObject:name]];
}

/// Runs `accessor` under file coordination for reading (a file not downloaded yet is downloaded first); NO when the
/// coordination failed or was cancelled.
- (BOOL)coordinateReadingURL:(NSURL *)url error:(NSError **)outError accessor:(void (^)(NSURL *readURL))accessor
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    @synchronized (self) {
        _currentCoordinator = coordinator;
    }
    if (self.cancelled)
        [coordinator cancel];
    __block BOOL ran = NO;
    [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:outError
                                 byAccessor:^(NSURL *readURL) {
        ran = YES;
        accessor(readURL);
    }];
    @synchronized (self) {
        _currentCoordinator = nil;
    }
    return ran;
}

/// The contents of `url`, read through file coordination (a file not downloaded yet is downloaded).
- (nullable NSData *)coordinatedDataAtURL:(NSURL *)url error:(NSError **)outError
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    @synchronized (self) {
        _currentCoordinator = coordinator;
    }
    if (self.cancelled)
        [coordinator cancel];
    __block NSData *data = nil;
    __block NSError *readError = nil;
    NSError *coordinationError = nil;
    [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&coordinationError
                                 byAccessor:^(NSURL *readURL) {
        data = [NSData dataWithContentsOfURL:readURL options:NSDataReadingMappedIfSafe error:&readError];
    }];
    @synchronized (self) {
        _currentCoordinator = nil;
    }
    if (outError)
        *outError = coordinationError ?: readError;
    return data;
}

- (void)addUnreadable:(NSURL *)url reason:(TSTeXRootUnreadableReason)reason error:(nullable NSError *)error
                   to:(NSMutableArray<TSTeXRootUnreadableItem *> *)items
{
    TSTeXRootUnreadableItem *item = [[TSTeXRootUnreadableItem alloc] initPrivate];
    item.url = url;
    item.relativePath = [self relativePathOfURL:url];
    item.reason = reason;
    item.error = error;
    [items addObject:item];
}

static const NSUInteger TSTeXRootReadPiece = 64 * 1024;

/// Whether the bytes are all ASCII other than NUL and ESC. In every encoding TeXShop reads byte-wise, such bytes
/// read as the same text; anything else (UTF-16 or UTF-32 without a byte order mark has NULs, ISO-2022-JP has ESCs,
/// other encodings have bytes from 0x80) is left to a full, proper reading.
static BOOL TSTeXRootPlainASCII(const unsigned char *bytes, NSUInteger length)
{
    for (NSUInteger i = 0; i < length; i++)
        if (bytes[i] >= 0x80 || bytes[i] == 0x00 || bytes[i] == 0x1B)
            return NO;
    return YES;
}

/// The length of the first `lines` lines of bytes (each with its CR, LF or CRLF), or NSNotFound when the bytes end
/// before `lines` line breaks. A CR at the very end may still be followed by LF: it counts as the break, and the LF
/// that follows is taken by the caller with the next bytes (it does not start a line of its own).
static NSUInteger TSTeXRootLengthOfLines(const unsigned char *bytes, NSUInteger length, NSUInteger lines)
{
    NSUInteger breaks = 0;
    for (NSUInteger i = 0; i < length; i++) {
        if (bytes[i] == '\n' && i > 0 && bytes[i - 1] == '\r')
            continue;
        if (bytes[i] == '\r' || bytes[i] == '\n') {
            breaks++;
            if (breaks == lines)
                return (bytes[i] == '\r' && i + 1 < length && bytes[i + 1] == '\n') ? i + 2 : i + 1;
        }
    }
    return NSNotFound;
}

typedef NS_ENUM(NSInteger, TSTeXRootJudgement) {
    TSTeXRootJudgementNo = 0,
    TSTeXRootJudgementYes,
    TSTeXRootJudgementReadFully,
};

/// Decides from the head of a file on the disk, read through `handle`, whether it names the root, without reading
/// the rest, except to look for an old "%SourceDoc " line when that setting is on (the file is then streamed, a
/// piece at a time). Every line break the editor would see in ASCII text is CR or LF, so the first 20 lines lie
/// within the first 20 CR/LF line breaks. When the bytes read are not plain ASCII, the decision is left to a full,
/// proper reading (TSTeXRootJudgementReadFully).
- (TSTeXRootJudgement)judgeHandle:(NSFileHandle *)handle url:(NSURL *)url rootIdentifier:(id)rootIdentifier
                            error:(NSError **)outError
{
    NSMutableData *head = [NSMutableData data];
    BOOL atEnd = NO;
    NSUInteger linesLength = NSNotFound;
    while (!atEnd && linesLength == NSNotFound) {
        if (self.cancelled)
            return TSTeXRootJudgementNo;
        NSData *piece = [handle readDataUpToLength:TSTeXRootReadPiece error:outError];
        if (self.pieceReadHandler)
            self.pieceReadHandler();
        if (piece == nil)
            return TSTeXRootJudgementNo;
        if (piece.length == 0) {
            atEnd = YES;
            break;
        }
        [head appendData:piece];
        linesLength = TSTeXRootLengthOfLines(head.bytes, head.length, 20);
    }
    // Only the first 20 lines decide; the bytes read after them (the rest of the last piece) are not looked at here.
    NSData *lines = linesLength == NSNotFound ? head : [head subdataWithRange:NSMakeRange(0, linesLength)];
    if (!TSTeXRootPlainASCII(lines.bytes, lines.length))
        return TSTeXRootJudgementReadFully;
    NSString *headText = [[NSString alloc] initWithData:lines encoding:NSASCIIStringEncoding] ?: @"";
    TSRootFileSpecifier *specifier = [TSRootFileResolver specifierInSource:headText allowingSourceDoc:NO];
    if (specifier == nil && _allowsSourceDoc)
        return [self judgeSourceDocInHandle:handle head:head atEnd:atEnd url:url rootIdentifier:rootIdentifier error:outError];
    if (specifier == nil)
        return TSTeXRootJudgementNo;
    return [self specifier:specifier ofURL:url namesRoot:rootIdentifier] ? TSTeXRootJudgementYes : TSTeXRootJudgementNo;
}

/// The old "%SourceDoc ": only its first occurrence in the whole file counts, and only at the start of a line.
/// The file is streamed from where the head ended. Before that occurrence, a NUL or ESC (where ASCII bytes may not
/// mean ASCII letters) or a byte from 0x80 just before it or on its line leaves the decision to a full reading.
- (TSTeXRootJudgement)judgeSourceDocInHandle:(NSFileHandle *)handle head:(NSData *)head atEnd:(BOOL)atEnd url:(NSURL *)url
                              rootIdentifier:(id)rootIdentifier error:(NSError **)outError
{
    static const char marker[] = "%SourceDoc ";
    const NSUInteger markerLength = sizeof marker - 1;
    NSData *markerData = [NSData dataWithBytes:marker length:markerLength];
    NSMutableData *buffer = [head mutableCopy];   // the bytes not dropped yet
    unsigned char dropped = 0;                    // the last byte dropped before `buffer`, 0 at the start of the file
    BOOL droppedAny = NO;
    for (;;) {
        if (self.cancelled)
            return TSTeXRootJudgementNo;
        const unsigned char *bytes = buffer.bytes;
        NSRange found = [buffer rangeOfData:markerData options:0 range:NSMakeRange(0, buffer.length)];
        if (found.location != NSNotFound) {
            for (NSUInteger i = 0; i < found.location; i++)
                if (bytes[i] == 0x00 || bytes[i] == 0x1B)
                    return TSTeXRootJudgementReadFully;
            unsigned char before = found.location ? bytes[found.location - 1] : dropped;
            BOOL fileStart = found.location == 0 && !droppedAny;
            if (!fileStart && before >= 0x80)
                return TSTeXRootJudgementReadFully;
            if (!fileStart && before != '\n' && before != '\r')
                return TSTeXRootJudgementNo;
            // The rest of its line, with its line break.
            NSUInteger end = found.location + markerLength;
            for (;;) {
                bytes = buffer.bytes;
                while (end < buffer.length && bytes[end] != '\n' && bytes[end] != '\r')
                    end++;
                if (end < buffer.length || atEnd)
                    break;
                if (self.cancelled)
                    return TSTeXRootJudgementNo;
                NSData *piece = [handle readDataUpToLength:TSTeXRootReadPiece error:outError];
                if (self.pieceReadHandler)
                    self.pieceReadHandler();
                if (piece == nil)
                    return TSTeXRootJudgementNo;
                if (piece.length == 0)
                    atEnd = YES;
                [buffer appendData:piece];
            }
            if (end < buffer.length && ((const unsigned char *)buffer.bytes)[end] == '\r') {
                if (end + 1 == buffer.length && !atEnd) {
                    NSData *piece = [handle readDataUpToLength:1 error:outError];
                    if (piece == nil)
                        return TSTeXRootJudgementNo;
                    [buffer appendData:piece];
                }
                end += (end + 1 < buffer.length && ((const unsigned char *)buffer.bytes)[end + 1] == '\n') ? 2 : 1;
            } else if (end < buffer.length)
                end += 1;
            NSData *line = [buffer subdataWithRange:NSMakeRange(found.location, end - found.location)];
            if (!TSTeXRootPlainASCII(line.bytes, line.length))
                return TSTeXRootJudgementReadFully;
            NSString *lineText = [[NSString alloc] initWithData:line encoding:NSASCIIStringEncoding] ?: @"";
            TSRootFileSpecifier *specifier = [TSRootFileResolver sourceDocSpecifierInSource:lineText];
            return specifier && [self specifier:specifier ofURL:url namesRoot:rootIdentifier]
                ? TSTeXRootJudgementYes : TSTeXRootJudgementNo;
        }
        for (NSUInteger i = 0; i < buffer.length; i++)
            if (bytes[i] == 0x00 || bytes[i] == 0x1B)
                return TSTeXRootJudgementReadFully;
        if (atEnd)
            return TSTeXRootJudgementNo;
        // Keep the bytes that may start the marker, and the byte before them.
        NSUInteger keep = MIN(buffer.length, markerLength);
        if (buffer.length > keep) {
            dropped = bytes[buffer.length - keep - 1];
            droppedAny = YES;
            [buffer replaceBytesInRange:NSMakeRange(0, buffer.length - keep) withBytes:NULL length:0];
        }
        NSData *piece = [handle readDataUpToLength:TSTeXRootReadPiece error:outError];
        if (self.pieceReadHandler)
            self.pieceReadHandler();
        if (piece == nil)
            return TSTeXRootJudgementNo;
        if (piece.length == 0)
            atEnd = YES;
        [buffer appendData:piece];
    }
}

/// The file of an open document, or of a file read from the disk with the round-trip check, its hash and attributes.
- (TSTeXRootProjectFile *)fileAtURL:(NSURL *)url identifier:(nullable id)identifier openText:(nullable NSString *)openText
                               data:(nullable NSData *)data
{
    TSTeXRootProjectFile *file = [[TSTeXRootProjectFile alloc] initPrivate];
    file.url = url;
    file.relativePath = [self relativePathOfURL:url];
    file.identifier = identifier;
    if (openText) {
        file.isOpen = YES;
        file.text = openText;
        return file;
    }
    TSTeXRootSourceReading *reading = [_codec readData:(NSData *)data url:url];
    file.reading = reading;
    file.text = reading.text;
    file.sha256 = TSTeXRootSHA256((NSData *)data, TSTeXRootHashPiece);
    file.size = data.length;

    NSDictionary *values = [url resourceValuesForKeys:@[NSURLContentModificationDateKey, NSURLLinkCountKey,
                                                        NSURLIsWritableKey, NSURLIsUserImmutableKey] error:NULL];
    file.modificationDate = values[NSURLContentModificationDateKey];
    if (!reading.decodedStrictly)
        file.searchOnlyReason = TSTeXRootSearchOnlyReasonUndecodable;
    else if (!reading.roundTrips)
        file.searchOnlyReason = TSTeXRootSearchOnlyReasonRoundTrip;
    else if ([values[NSURLLinkCountKey] integerValue] > 1)
        file.searchOnlyReason = TSTeXRootSearchOnlyReasonHardLink;
    else if (![values[NSURLIsWritableKey] boolValue] || [values[NSURLIsUserImmutableKey] boolValue])
        file.searchOnlyReason = TSTeXRootSearchOnlyReasonNotWritable;
    return file;
}

/// Whether `text`, the text of `url`, names the root.
- (BOOL)text:(NSString *)text ofURL:(NSURL *)url namesRoot:(id)rootIdentifier
{
    TSRootFileSpecifier *specifier = [TSRootFileResolver specifierInSource:text allowingSourceDoc:_allowsSourceDoc];
    return specifier != nil && [self specifier:specifier ofURL:url namesRoot:rootIdentifier];
}

/// Whether the root named by `specifier` in `url` is the root, compared by identity.
- (BOOL)specifier:(TSRootFileSpecifier *)specifier ofURL:(NSURL *)url namesRoot:(id)rootIdentifier
{
    NSString *path = url.path;
    NSString *rootPath = [TSRootFileResolver pathForName:specifier.value homePath:path.stringByDeletingLastPathComponent
                                                 jobName:path.lastPathComponent.stringByDeletingPathExtension
                                            jobNameToken:_jobNameToken];
    id namedRoot = TSTeXRootIdentifier([NSURL fileURLWithPath:rootPath]);
    return namedRoot != nil && [namedRoot isEqual:rootIdentifier];
}

/// The file at `url` when it belongs to the project; nil otherwise or when it could not be read (then recorded).
/// A file on the disk that does not belong is decoded only for this decision and dropped at once; its full text,
/// its round trip and its hash are made only for files that belong.
- (nullable TSTeXRootProjectFile *)projectFileAtURL:(NSURL *)url identifier:(nullable id)identifier
                                       rootIdentifier:(id)rootIdentifier
                                           unreadable:(NSMutableArray<TSTeXRootUnreadableItem *> *)unreadable
{
    NSString *openText = identifier ? self.openDocumentTexts[(id<NSCopying>)identifier] : nil;
    if (openText)
        return [self text:openText ofURL:url namesRoot:rootIdentifier]
            ? [self fileAtURL:url identifier:identifier openText:openText data:nil] : nil;
    // The head decides (and, with the old setting, a streamed search for "%SourceDoc "); only a file that belongs, or
    // one whose head is not plain ASCII, is read whole. A file that does not belong is decoded only for this decision.
    __block NSData *data = nil;
    __block BOOL belongs = NO;
    __block NSError *readError = nil;
    NSError *coordinationError = nil;
    BOOL accessed = [self coordinateReadingURL:url error:&coordinationError accessor:^(NSURL *readURL) {
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:readURL error:&readError];
        if (handle == nil)
            return;
        NSError *error = nil;
        TSTeXRootJudgement judgement = [self judgeHandle:handle url:url rootIdentifier:rootIdentifier error:&error];
        if (error != nil) {
            readError = error;
            [handle closeFile];
            return;
        }
        if (judgement != TSTeXRootJudgementNo && !self.cancelled) {
            if ([handle seekToOffset:0 error:&readError])
                data = [handle readDataToEndOfFileAndReturnError:&readError];
            // Read in the encoding opening would choose, the text must name the root as well: the head was read as
            // ASCII, and an encoding that does not read ASCII bytes as ASCII letters gives another text.
            if (data != nil) {
                @autoreleasepool {
                    TSTeXRootSourceReading *judging = [self->_codec readData:data url:url verifyingRoundTrip:NO];
                    belongs = [self text:judging.text ofURL:url namesRoot:rootIdentifier];
                }
            }
        }
        [handle closeFile];
    }];
    if (!accessed || readError != nil) {
        if (!self.cancelled)
            [self addUnreadable:url reason:TSTeXRootUnreadableReasonFile error:readError ?: coordinationError to:unreadable];
        return nil;
    }
    return belongs ? [self fileAtURL:url identifier:identifier openText:nil data:(NSData *)data] : nil;
}

- (nullable TSTeXRootProject *)collect
{
    NSMutableArray<TSTeXRootUnreadableItem *> *unreadable = [NSMutableArray array];
    self.failure = TSTeXRootCollectionFailureNone;
    TSTeXRootProblem problem = [TSTeXRootProjectCollector problemWithRootURL:_rootURL];
    if (problem != TSTeXRootProblemNone) {
        self.rootProblem = problem;
        self.failure = TSTeXRootCollectionFailureRootProblem;
        return nil;
    }
    id rootIdentifier = TSTeXRootIdentifier(_rootURL);
    if (rootIdentifier == nil) {
        self.failure = TSTeXRootCollectionFailureRootIdentity;
        return nil;
    }

    // The root is listed whether or not it names itself; when it cannot be read it is recorded and left out, and
    // the files that name it are still collected.
    TSTeXRootProjectFile *root = nil;
    NSString *rootOpenText = self.openDocumentTexts[rootIdentifier];
    if (rootOpenText)
        root = [self fileAtURL:_rootURL identifier:rootIdentifier openText:rootOpenText data:nil];
    else {
        NSError *error = nil;
        NSData *data = [self coordinatedDataAtURL:_rootURL error:&error];
        if (data)
            root = [self fileAtURL:_rootURL identifier:rootIdentifier openText:nil data:data];
        else if (!self.cancelled)
            [self addUnreadable:_rootURL reason:TSTeXRootUnreadableReasonFile error:error to:unreadable];
    }
    if (self.cancelled) {
        self.failure = TSTeXRootCollectionFailureCancelled;
        return nil;
    }
    root.isRoot = YES;
    root.relativePath = _rootURL.lastPathComponent ?: @"";

    NSMutableArray<TSTeXRootProjectFile *> *others = [NSMutableArray array];
    // A file with several names (a hard link) is listed once, under the name that sorts first.
    NSMutableDictionary<id, TSTeXRootProjectFile *> *byIdentifier = [NSMutableDictionary dictionary];
    NSArray<NSURLResourceKey> *keys = @[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey, NSURLIsRegularFileKey];
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [NSFileManager.defaultManager enumeratorAtURL:_folderURL includingPropertiesForKeys:keys options:0
                                         errorHandler:^BOOL(NSURL *url, NSError *error) {
            [self addUnreadable:url reason:TSTeXRootUnreadableReasonFolder error:error to:unreadable];
            return YES;
        }];
    NSUInteger folders = 1, files = 0;
    NSString *currentFolder = @"";
    if (self.progressHandler)
        self.progressHandler(folders, files, currentFolder);

    for (NSURL *url in enumerator) @autoreleasepool {
        if (self.cancelled)
            break;
        NSDictionary *values = [url resourceValuesForKeys:keys error:NULL];
        if ([values[NSURLIsSymbolicLinkKey] boolValue])
            continue;   // Neither folders nor files are followed through symbolic links.
        if ([values[NSURLIsDirectoryKey] boolValue]) {
            if (enumerator.level == 1 && [url.lastPathComponent isEqualToString:TSTeXRootBackupFolderName]) {
                [enumerator skipDescendants];
                continue;
            }
            folders++;
            currentFolder = [self relativePathOfURL:url];
            if (self.progressHandler)
                self.progressHandler(folders, files, currentFolder);
            continue;
        }
        if (![values[NSURLIsRegularFileKey] boolValue] || ![TSTeXRootProjectCollector isCandidateName:url.lastPathComponent ?: @""])
            continue;
        files++;
        if (self.progressHandler && files % 50 == 0)
            self.progressHandler(folders, files, currentFolder);

        id identifier = TSTeXRootIdentifier(url);
        if (identifier != nil && [identifier isEqual:rootIdentifier])
            continue;   // The root itself (or another name of it) is already listed.
        TSTeXRootProjectFile *file = [self projectFileAtURL:url identifier:identifier rootIdentifier:rootIdentifier
                                                 unreadable:unreadable];
        if (self.cancelled || file == nil)
            continue;
        TSTeXRootProjectFile *same = identifier ? byIdentifier[identifier] : nil;
        if (same != nil) {
            if ([file.relativePath localizedStandardCompare:same.relativePath] == NSOrderedAscending) {
                [others replaceObjectAtIndex:[others indexOfObjectIdenticalTo:same] withObject:file];
                byIdentifier[identifier] = file;
            }
            continue;
        }
        if (identifier)
            byIdentifier[identifier] = file;
        [others addObject:file];
    }
    if (self.cancelled) {
        self.failure = TSTeXRootCollectionFailureCancelled;
        return nil;
    }
    if (self.progressHandler)
        self.progressHandler(folders, files, currentFolder);

    [others sortUsingComparator:^NSComparisonResult(TSTeXRootProjectFile *a, TSTeXRootProjectFile *b) {
        return [a.relativePath localizedStandardCompare:b.relativePath];
    }];
    TSTeXRootProject *project = [[TSTeXRootProject alloc] initPrivate];
    project.rootURL = _rootURL;
    project.folderURL = _folderURL;
    project.rootFile = root;
    project.files = root ? [@[root] arrayByAddingObjectsFromArray:others] : [others copy];
    project.unreadableItems = unreadable;
    return project;
}

@end
