// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSTextStatistics.m
 */

#import "TSTextStatistics.h"
#import <stdatomic.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <unicode/uchar.h>
#import "NSString-Extras.h"

#pragma mark Counting with options

const NSUInteger TSCharacterCountUnencodable = NSUIntegerMax - 1;

static NSString *const TSIgnoresLineEndingsKey = @"StatisticsIgnoresLineEndings";
static NSString *const TSIgnoresWhitespaceKey = @"StatisticsIgnoresWhitespace";
static NSString *const TSConsecutiveWhitespaceKey = @"StatisticsTreatsConsecutiveWhitespaceAsOne";
static NSString *const TSNormalizationKey = @"StatisticsNormalization";
static NSString *const TSCharacterUnitKey = @"StatisticsCharacterUnit";

// The names the settings keep, in the order of the enums.
static NSArray<NSString *> *TSNormalizationNames(void)
{
    return @[@"None", @"NFC", @"NFD", @"NFKC", @"NFKD", @"NFKCCaseFold", @"ModifiedNFC", @"ModifiedNFD"];
}

static NSArray<NSString *> *TSUnitNames(void)
{
    return @[@"GraphemeCluster", @"UnicodeScalar", @"UTF16", @"Byte"];
}

@implementation TSCharacterCountOptions

- (instancetype)init
{
    if ((self = [super init]))
        _encoding = NSUTF8StringEncoding;
    return self;
}

+ (instancetype)savedOptions
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    TSCharacterCountOptions *options = [self new];
    options.ignoresLineEndings = [defaults boolForKey:TSIgnoresLineEndingsKey];
    options.ignoresWhitespace = [defaults boolForKey:TSIgnoresWhitespaceKey];
    options.treatsConsecutiveWhitespaceAsOne = [defaults boolForKey:TSConsecutiveWhitespaceKey];
    NSString *normalization = [defaults stringForKey:TSNormalizationKey], *unit = [defaults stringForKey:TSCharacterUnitKey];
    NSUInteger index = normalization ? [TSNormalizationNames() indexOfObject:normalization] : NSNotFound;
    options.normalization = index == NSNotFound ? TSUnicodeNormalizationNone : (TSUnicodeNormalization)index;
    index = unit ? [TSUnitNames() indexOfObject:unit] : NSNotFound;
    options.unit = index == NSNotFound ? TSCharacterUnitGraphemeCluster : (TSCharacterUnit)index;
    return options;
}

- (void)save
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:self.ignoresLineEndings forKey:TSIgnoresLineEndingsKey];
    [defaults setBool:self.ignoresWhitespace forKey:TSIgnoresWhitespaceKey];
    [defaults setBool:self.treatsConsecutiveWhitespaceAsOne forKey:TSConsecutiveWhitespaceKey];
    [defaults setObject:TSNormalizationNames()[(NSUInteger)self.normalization] forKey:TSNormalizationKey];
    [defaults setObject:TSUnitNames()[(NSUInteger)self.unit] forKey:TSCharacterUnitKey];
}

- (BOOL)isDefault
{
    return !self.ignoresLineEndings && !self.ignoresWhitespace && !self.treatsConsecutiveWhitespaceAsOne
        && self.normalization == TSUnicodeNormalizationNone && self.unit == TSCharacterUnitGraphemeCluster;
}

- (id)copyWithZone:(NSZone *)zone
{
    TSCharacterCountOptions *copy = [TSCharacterCountOptions new];
    copy.ignoresLineEndings = self.ignoresLineEndings;
    copy.ignoresWhitespace = self.ignoresWhitespace;
    copy.treatsConsecutiveWhitespaceAsOne = self.treatsConsecutiveWhitespaceAsOne;
    copy.normalization = self.normalization;
    copy.unit = self.unit;
    copy.encoding = self.encoding;
    copy.textForEncoding = self.textForEncoding;
    copy.composesForSaving = self.composesForSaving;
    return copy;
}

@end

// ICU's normalizers, which libicucore exports without a header in the SDK.
typedef struct UNormalizer2 UNormalizer2;
const UNormalizer2 *unorm2_getNFCInstance(UErrorCode *error);
const UNormalizer2 *unorm2_getNFDInstance(UErrorCode *error);
const UNormalizer2 *unorm2_getNFKCInstance(UErrorCode *error);
const UNormalizer2 *unorm2_getNFKDInstance(UErrorCode *error);
const UNormalizer2 *unorm2_getNFKCCasefoldInstance(UErrorCode *error);
int32_t unorm2_normalize(const UNormalizer2 *normalizer, const UChar *source, int32_t length, UChar *destination, int32_t capacity, UErrorCode *error);
UBool unorm2_hasBoundaryBefore(const UNormalizer2 *normalizer, UChar32 c);

// The way CotEditor's Advanced Character Count leaves out and joins characters (String+AdvancedCounting.swift): three
// passes, each over the characters (grapheme clusters) of what the pass before left, as Swift's regular expressions
// match whole characters by their first code point. Line endings (\R: LF, VT, FF, CR, CR LF, NEL, LS, PS) go first,
// then whitespace ([\t\p{Zs}]), and then a run of two or more white space characters (\s: White_Space) becomes one space.
static UChar32 TSFirstCodePoint(NSString *string, NSUInteger location, NSUInteger end)
{
    unichar c = [string characterAtIndex:location];
    if (CFStringIsSurrogateHighCharacter(c) && location + 1 < end) {
        unichar d = [string characterAtIndex:location + 1];
        if (CFStringIsSurrogateLowCharacter(d))
            return (UChar32)CFStringGetLongCharacterForSurrogatePair(c, d);
    }
    return c;
}

static inline BOOL TSIsLineEnding(UChar32 c)
{
    return (c >= 0x0A && c <= 0x0D) || c == 0x85 || c == 0x2028 || c == 0x2029;
}

static inline BOOL TSIsWhitespace(UChar32 c)
{
    return c == '\t' || u_charType(c) == U_SPACE_SEPARATOR;
}

// The text without the characters whose first code point `takes` takes, or, with `runs`, with each run of two or more
// characters it takes replaced by one space. nil when `cancel` stopped it.
static NSString *TSFilterPass(NSString *string, BOOL (*takes)(UChar32), BOOL runs, TSStatusBarCancel cancel)
{
    NSUInteger length = string.length, check = 1 << 16;
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    // The text kept since `kept`, appended in one piece; a run of taken characters starts at `run`.
    NSUInteger kept = 0, run = NSNotFound, inRun = 0;
    for (NSUInteger i = 0; i < length; ) {
        if (i >= check) {
            if (cancel && cancel())
                return nil;
            check = i + (1 << 16);
        }
        NSUInteger next = TSStatusBarCharacterEnd(string, i, length);
        BOOL taken = takes(TSFirstCodePoint(string, i, next));
        if (!runs) {
            if (taken) {
                if (i > kept)
                    [result appendString:[string substringWithRange:NSMakeRange(kept, i - kept)]];
                kept = next;
            }
        } else if (taken) {
            if (inRun++ == 0)
                run = i;
        } else if (inRun) {
            if (inRun > 1) {
                [result appendString:[string substringWithRange:NSMakeRange(kept, run - kept)]];
                [result appendString:@" "];
                kept = i;
            }
            inRun = 0;
        }
        i = next;
    }
    if (runs && inRun > 1) {
        [result appendString:[string substringWithRange:NSMakeRange(kept, run - kept)]];
        [result appendString:@" "];
    } else if (length > kept) {
        [result appendString:[string substringWithRange:NSMakeRange(kept, length - kept)]];
    }
    return result;
}

static BOOL TSTakesLineEnding(UChar32 c) { return TSIsLineEnding(c); }
static BOOL TSTakesWhitespace(UChar32 c) { return TSIsWhitespace(c); }
static BOOL TSTakesWhiteSpaceProperty(UChar32 c) { return u_isUWhiteSpace(c); }

// nil when `cancel` stopped it.
static NSString *TSFilteredText(NSString *string, TSCharacterCountOptions *options, TSStatusBarCancel cancel)
{
    BOOL lineEndings = options.ignoresLineEndings, whitespace = options.ignoresWhitespace;
    NSString *text = string;
    if (lineEndings && !(text = TSFilterPass(text, TSTakesLineEnding, NO, cancel)))
        return nil;
    if (whitespace && !(text = TSFilterPass(text, TSTakesWhitespace, NO, cancel)))
        return nil;
    if (options.treatsConsecutiveWhitespaceAsOne && !(lineEndings && whitespace)
        && !(text = TSFilterPass(text, TSTakesWhiteSpaceProperty, YES, cancel)))
        return nil;
    return text;
}

// The text normalized a piece at a time, cut where the normalizer starts afresh, so that a count can stop between pieces.
static NSString *TSNormalizedPieces(NSString *string, const UNormalizer2 *boundaries, NSString *(^normalize)(NSString *piece), TSStatusBarCancel cancel)
{
    const NSUInteger size = 1 << 16;
    NSUInteger length = string.length;
    if (length <= size || !boundaries)
        return normalize(string);
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    for (NSUInteger start = 0; start < length; ) {
        if (cancel && cancel())
            return string;
        NSUInteger end = MIN(start + size, length);
        // Back to a character before which nothing joins.
        while (end < length && end > start + 1) {
            unichar c = [string characterAtIndex:end];
            if (!CFStringIsSurrogateLowCharacter(c) && unorm2_hasBoundaryBefore(boundaries, TSFirstCodePoint(string, end, length)))
                break;
            end--;
        }
        if (end == start + 1 && end < length)
            end = MIN(start + size, length);  // no boundary: a longer piece
        while (end < length && (CFStringIsSurrogateLowCharacter([string characterAtIndex:end])
                                || !unorm2_hasBoundaryBefore(boundaries, TSFirstCodePoint(string, end, length))))
            end++;
        [result appendString:normalize([string substringWithRange:NSMakeRange(start, end - start)])];
        start = end;
    }
    return result;
}

static NSString *TSICUNormalized(NSString *string, const UNormalizer2 *normalizer)
{
    NSUInteger length = string.length;
    if (!normalizer || length == 0 || length > INT32_MAX / 4)
        return string;
    UChar *source = malloc(length * sizeof(UChar));
    [string getCharacters:source range:NSMakeRange(0, length)];
    int32_t capacity = (int32_t)length * 3 + 16;
    UChar *destination = malloc((size_t)capacity * sizeof(UChar));
    UErrorCode error = U_ZERO_ERROR;
    int32_t written = unorm2_normalize(normalizer, source, (int32_t)length, destination, capacity, &error);
    if (error == U_BUFFER_OVERFLOW_ERROR) {
        free(destination);
        capacity = written;
        destination = malloc((size_t)capacity * sizeof(UChar));
        error = U_ZERO_ERROR;
        written = unorm2_normalize(normalizer, source, (int32_t)length, destination, capacity, &error);
    }
    NSString *result = U_SUCCESS(error) ? [NSString stringWithCharacters:destination length:(NSUInteger)written] : string;
    free(source);
    free(destination);
    return result;
}

static NSString *TSNormalizedText(NSString *string, TSUnicodeNormalization normalization, TSStatusBarCancel cancel)
{
    UErrorCode error = U_ZERO_ERROR;
    const UNormalizer2 *normalizer = NULL;
    switch (normalization) {
        case TSUnicodeNormalizationNone: return string;
        case TSUnicodeNormalizationNFC: case TSUnicodeNormalizationModifiedNFC: normalizer = unorm2_getNFCInstance(&error); break;
        case TSUnicodeNormalizationNFD: case TSUnicodeNormalizationModifiedNFD: normalizer = unorm2_getNFDInstance(&error); break;
        case TSUnicodeNormalizationNFKC: normalizer = unorm2_getNFKCInstance(&error); break;
        case TSUnicodeNormalizationNFKD: normalizer = unorm2_getNFKDInstance(&error); break;
        case TSUnicodeNormalizationNFKCCaseFold: normalizer = unorm2_getNFKCCasefoldInstance(&error); break;
    }
    if (U_FAILURE(error))
        normalizer = NULL;
    // Modified NFC and NFD as Edit > Unicode Normalization makes them.
    if (normalization == TSUnicodeNormalizationModifiedNFC)
        return TSNormalizedPieces(string, normalizer, ^NSString *(NSString *piece) { return [piece normalizedStringWithModifiedNFC]; }, cancel);
    if (normalization == TSUnicodeNormalizationModifiedNFD)
        return TSNormalizedPieces(string, normalizer, ^NSString *(NSString *piece) { return [piece normalizedStringWithModifiedNFD]; }, cancel);
    return TSNormalizedPieces(string, normalizer, ^NSString *(NSString *piece) { return TSICUNormalized(piece, normalizer); }, cancel);
}

// The code points of the text: a surrogate pair is one, a lone surrogate stands for itself.
static NSUInteger TSScalarCount(NSString *string)
{
    NSUInteger length = string.length, count = 0;
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)length));
    for (NSUInteger i = 0; i < length; i++, count++)
        if (CFStringIsSurrogateHighCharacter(CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)i)) && i + 1 < length
            && CFStringIsSurrogateLowCharacter(CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)(i + 1))))
            i++;
    return count;
}

// The bytes of the text in the encoding, without a byte order mark.
static NSUInteger TSByteCount(NSString *string, NSStringEncoding encoding)
{
    CFStringEncoding cf = CFStringConvertNSStringEncodingToEncoding(encoding);
    if (cf == kCFStringEncodingInvalidId)
        return TSCharacterCountUnencodable;
    CFIndex length = (CFIndex)string.length, used = 0;
    CFIndex converted = CFStringGetBytes((__bridge CFStringRef)string, CFRangeMake(0, length), cf, 0, false, NULL, 0, &used);
    return converted == length ? (NSUInteger)used : TSCharacterCountUnencodable;
}

NSUInteger TSCharacterCountWithOptions(NSString *string, TSCharacterCountOptions *options, TSStatusBarCancel cancel)
{
    NSString *text = TSFilteredText(string, options, cancel);
    if (!text || (cancel && cancel()))
        return NSNotFound;
    text = TSNormalizedText(text, options.normalization, cancel);
    if (cancel && cancel())
        return NSNotFound;
    NSUInteger count = 0;
    switch (options.unit) {
        case TSCharacterUnitGraphemeCluster:
            count = TSStatusBarCharacterCount(text, NSMakeRange(0, text.length), cancel);
            break;
        case TSCharacterUnitUnicodeScalar:
            count = TSScalarCount(text);
            break;
        case TSCharacterUnitUTF16:
            count = text.length;
            break;
        case TSCharacterUnitByte:
            // Composed as TeXShop composes the text it saves, a piece at a time.
            if (options.composesForSaving && options.normalization != TSUnicodeNormalizationModifiedNFC) {
                text = TSNormalizedText(text, TSUnicodeNormalizationModifiedNFC, cancel);
                if (cancel && cancel())
                    return NSNotFound;
            }
            count = TSByteCount(options.textForEncoding ? options.textForEncoding(text, options.encoding) : text, options.encoding);
            break;
    }
    return cancel && cancel() ? NSNotFound : count;
}

#pragma mark Text Statistics

@interface TSTextStatisticsResult ()
@property (nonatomic, readwrite) TSTextStatisticsState state;
@property (nonatomic, readwrite) BOOL selection;
@property (nonatomic, readwrite) TSStatusBarCounts source;
@property (nonatomic, readwrite) TSStatusBarCounts text;
@property (nonatomic, readwrite) NSDate *date;
@property (nonatomic, readwrite) NSUInteger sourceCharacters, textCharacters;
@property (nonatomic, readwrite, copy) TSCharacterCountOptions *options;
@property (nonatomic, readwrite, copy) NSString *sourceString;
@property (nonatomic, readwrite, copy, nullable) NSString *textString;
@end

@implementation TSTextStatisticsResult

- (instancetype)init
{
    if ((self = [super init])) {
        _sourceCharacters = NSNotFound;
        _textCharacters = NSNotFound;
        _options = [TSCharacterCountOptions new];
        _sourceString = @"";
    }
    return self;
}

@end

// One count, which `stop` or a newer count cancels.
@interface TSTextStatisticsRun : NSObject
{
@public
    atomic_bool cancelled;
}
@property (nonatomic, strong, nullable) NSTask *task;
@property (nonatomic, strong, nullable) NSURL *file;
@end

@implementation TSTextStatisticsRun
@end

static void TSRemoveFile(NSURL *_Nullable file)
{
    NSString *path = file.path;
    if (path)
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
}

@interface TSTextStatistics ()
@property (nonatomic, strong, nullable) TSTextStatisticsRun *run;
@property (nonatomic) dispatch_queue_t queue;
@end

@implementation TSTextStatistics

+ (nullable NSURL *)detexInFolder:(nullable NSString *)binFolder
{
    if (binFolder.length == 0)
        return nil;
    NSString *path = [[binFolder stringByExpandingTildeInPath] stringByAppendingPathComponent:@"detex"];
    return [NSFileManager.defaultManager isExecutableFileAtPath:path] ? [NSURL fileURLWithPath:path] : nil;
}

+ (NSString *)countedTextOfString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges selection:(BOOL *)selection
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSValue *value in ranges) {
        NSRange range = NSIntersectionRange(value.rangeValue, NSMakeRange(0, string.length));
        if (range.length > 0)
            [parts addObject:[string substringWithRange:range]];
    }
    if (selection)
        *selection = parts.count > 0;
    return parts.count ? [parts componentsJoinedByString:@"\n"] : [string copy];
}

- (instancetype)init
{
    if ((self = [super init]))
        _queue = dispatch_queue_create("TeXShop.textStatistics", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (BOOL)isRunning
{
    return self.run != nil;
}

- (nullable NSURL *)temporaryFile
{
    return self.run.file;
}

- (void)stop
{
    TSTextStatisticsRun *run = self.run;
    self.run = nil;
    if (!run)
        return;
    atomic_store(&run->cancelled, true);
    @synchronized (run) {
        if (run.task.isRunning)
            [run.task terminate];
    }
}

- (void)countString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges folder:(nullable NSURL *)folder
              detex:(nullable NSURL *)detex encoding:(NSStringEncoding)encoding options:(TSCharacterCountOptions *)options
         completion:(void (^)(TSTextStatisticsResult *result))completion
{
    [self stop];
    options = [options copy];
    BOOL selection = NO;
    NSString *text = [TSTextStatistics countedTextOfString:string ranges:ranges selection:&selection];
    TSTextStatisticsRun *run = [TSTextStatisticsRun new];
    self.run = run;
    NSDate *date = [NSDate date];
    NSURL *directory = folder ?: [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    // A name of its own in the temporary folder; detex runs in the document's folder for \input and \include.
    NSString *name = [NSString stringWithFormat:@"TeXShop-statistics-%@.tex", NSUUID.UUID.UUIDString];
    NSURL *file = detex ? [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]] : nil;
    run.file = file;
    __weak TSTextStatistics *weakSelf = self;
    dispatch_async(self.queue, ^{
        TSStatusBarCounts source = TSStatusBarCountsUnknown(), body = TSStatusBarCountsUnknown();
        NSString *stripped = nil;
        TSStatusBarCount(text, @[], YES, NO, &source, ^BOOL{ return atomic_load(&run->cancelled); });
        TSTextStatisticsState state = TSTextStatisticsDetexMissing;
        if (detex && !atomic_load(&run->cancelled)) {
            state = TSTextStatisticsDetexFailed;
            NSData *data = [text dataUsingEncoding:encoding allowLossyConversion:YES] ?: [text dataUsingEncoding:NSUTF8StringEncoding];
            if ([data writeToURL:(NSURL *_Nonnull)file atomically:NO]) {
                NSTask *task = [NSTask new];
                task.executableURL = detex;
                task.arguments = @[file.path ?: name];
                task.currentDirectoryURL = directory;
                NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
                NSString *bin = detex.URLByDeletingLastPathComponent.path ?: @"/usr/bin";
                environment[@"PATH"] = environment[@"PATH"] ? [NSString stringWithFormat:@"%@:%@", bin, environment[@"PATH"]] : bin;
                task.environment = environment;
                NSPipe *output = [NSPipe pipe];
                task.standardOutput = output;
                task.standardError = NSFileHandle.fileHandleWithNullDevice;
                task.standardInput = NSFileHandle.fileHandleWithNullDevice;
                // The output is read as it comes, so that detex never waits for room in the pipe, and without waiting
                // for the end of the pipe: a process that detex started could keep the pipe open after detex ends.
                int fd = output.fileHandleForReading.fileDescriptor;
                fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
                NSMutableData *result = [NSMutableData data];
                dispatch_queue_t reading = dispatch_queue_create("TeXShop.textStatistics.read", DISPATCH_QUEUE_SERIAL);
                // Reads what is in the pipe; YES at its end.
                BOOL (^drain)(void) = ^BOOL{
                    char buffer[65536];
                    ssize_t count;
                    while ((count = read(fd, buffer, sizeof buffer)) > 0)
                        [result appendBytes:buffer length:(NSUInteger)count];
                    return count == 0;
                };
                dispatch_source_t reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, reading);
                dispatch_semaphore_t readerDone = dispatch_semaphore_create(0), exited = dispatch_semaphore_create(0);
                dispatch_source_set_event_handler(reader, ^{
                    if (drain())
                        dispatch_source_cancel(reader);
                });
                dispatch_source_set_cancel_handler(reader, ^{ dispatch_semaphore_signal(readerDone); });
                task.terminationHandler = ^(NSTask *ended) { dispatch_semaphore_signal(exited); };
                BOOL launched = NO;
                @synchronized (run) {
                    if (!atomic_load(&run->cancelled)) {
                        run.task = task;
                        launched = [task launchAndReturnError:NULL];
                    }
                }
                dispatch_resume(reader);
                if (launched) {
                    // detex ends by itself, or by -stop; one that does not end within 2 seconds after -stop is killed.
                    CFAbsoluteTime stopped = 0;
                    while (dispatch_semaphore_wait(exited, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC))) {
                        if (!atomic_load(&run->cancelled))
                            continue;
                        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                        if (stopped == 0)
                            stopped = now;
                        else if (now - stopped > 2 && task.processIdentifier > 0)
                            kill(task.processIdentifier, SIGKILL);
                    }
                }
                // What detex wrote before it ended is in the pipe: read it, then stop reading.
                dispatch_sync(reading, ^{
                    if (!dispatch_source_testcancel(reader)) {
                        dispatch_source_cancel(reader);
                        drain();
                    }
                });
                dispatch_semaphore_wait(readerDone, DISPATCH_TIME_FOREVER);
                if (launched) {
                    if (!atomic_load(&run->cancelled) && task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0) {
                        stripped = [[NSString alloc] initWithData:result encoding:encoding]
                            ?: [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding]
                            ?: [[NSString alloc] initWithData:result encoding:NSISOLatin1StringEncoding];
                        if (stripped && TSStatusBarCount(stripped, @[], YES, NO, &body, ^BOOL{ return atomic_load(&run->cancelled); }))
                            state = TSTextStatisticsDone;
                    }
                }
            }
        }
        TSRemoveFile(file);
        if (atomic_load(&run->cancelled))
            return;
        TSTextStatisticsResult *done = [TSTextStatisticsResult new];
        done.state = state;
        done.selection = selection;
        done.source = source;
        done.text = state == TSTextStatisticsDone ? body : TSStatusBarCountsUnknown();
        done.date = date;
        done.options = options;
        done.sourceString = text;
        done.textString = state == TSTextStatisticsDone ? stripped : nil;
        TSStatusBarCancel cancel = ^BOOL{ return atomic_load(&run->cancelled); };
        // With the options of the status bar, the characters are those counted already.
        done.sourceCharacters = options.isDefault ? source.characters : TSCharacterCountWithOptions(text, options, cancel);
        if (done.textString)
            done.textCharacters = options.isDefault ? body.characters : TSCharacterCountWithOptions((NSString *_Nonnull)done.textString, options, cancel);
        if (atomic_load(&run->cancelled))
            return;
        dispatch_async(dispatch_get_main_queue(), ^{
            TSTextStatistics *strongSelf = weakSelf;
            if (atomic_load(&run->cancelled) || (strongSelf && strongSelf.run != run))
                return;
            if (strongSelf)
                strongSelf.run = nil;
            completion(done);
        });
    });
}

- (void)recountCharactersOfResult:(TSTextStatisticsResult *)result options:(TSCharacterCountOptions *)options
                       completion:(void (^)(TSTextStatisticsResult *result))completion
{
    [self stop];
    options = [options copy];
    TSTextStatisticsRun *run = [TSTextStatisticsRun new];
    self.run = run;
    __weak TSTextStatistics *weakSelf = self;
    dispatch_async(self.queue, ^{
        TSStatusBarCancel cancel = ^BOOL{ return atomic_load(&run->cancelled); };
        TSTextStatisticsResult *done = [TSTextStatisticsResult new];
        done.state = result.state;
        done.selection = result.selection;
        done.source = result.source;
        done.text = result.text;
        done.date = result.date;
        done.options = options;
        done.sourceString = result.sourceString;
        done.textString = result.textString;
        done.sourceCharacters = options.isDefault ? result.source.characters : TSCharacterCountWithOptions(result.sourceString, options, cancel);
        if (done.textString)
            done.textCharacters = options.isDefault ? result.text.characters : TSCharacterCountWithOptions((NSString *_Nonnull)done.textString, options, cancel);
        if (atomic_load(&run->cancelled))
            return;
        dispatch_async(dispatch_get_main_queue(), ^{
            TSTextStatistics *strongSelf = weakSelf;
            if (atomic_load(&run->cancelled) || (strongSelf && strongSelf.run != run))
                return;
            if (strongSelf)
                strongSelf.run = nil;
            completion(done);
        });
    });
}

@end
