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
    return copy;
}

@end

static inline BOOL TSIsLineEnding(unichar c)
{
    return c == '\n' || c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029;
}

// Tab, VT, FF and the space separators (Zs), which are all in the BMP.
static inline BOOL TSIsWhitespace(unichar c)
{
    return c == '\t' || c == 0x0B || c == 0x0C || c == ' ' || (c > 0x7F && u_charType(c) == U_SPACE_SEPARATOR);
}

// The text without the line endings and whitespace that are not counted, a run of the rest taken as its first one.
static NSString *TSFilteredText(NSString *string, TSCharacterCountOptions *options, TSStatusBarCancel cancel)
{
    BOOL lineEndings = options.ignoresLineEndings, whitespace = options.ignoresWhitespace, runs = options.treatsConsecutiveWhitespaceAsOne;
    if (!lineEndings && !whitespace && !runs)
        return string;
    NSUInteger length = string.length;
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)length));
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    unichar kept[4096];
    NSUInteger count = 0, check = 1 << 16;
    BOOL inRun = NO;
    for (NSUInteger i = 0; i < length; ) {
        if (i >= check) {
            if (cancel && cancel())
                return string;
            check = i + (1 << 16);
        }
        unichar c = CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)i);
        BOOL ending = TSIsLineEnding(c), space = !ending && TSIsWhitespace(c);
        // CR LF is one line ending.
        NSUInteger width = c == '\r' && i + 1 < length && CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)(i + 1)) == '\n' ? 2 : 1;
        BOOL skip = (ending && lineEndings) || (space && whitespace);
        if (!skip && (ending || space) && runs) {
            // A character left out does not end the run.
            skip = inRun;
            inRun = YES;
        } else if (!skip) {
            inRun = NO;
        }
        if (!skip) {
            if (count + width > sizeof kept / sizeof kept[0]) {
                CFStringAppendCharacters((__bridge CFMutableStringRef)result, kept, (CFIndex)count);
                count = 0;
            }
            for (NSUInteger j = 0; j < width; j++)
                kept[count++] = CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)(i + j));
        }
        i += width;
    }
    CFStringAppendCharacters((__bridge CFMutableStringRef)result, kept, (CFIndex)count);
    return result;
}

// The canonical mapping of the parts of the text outside the ranges that HFS+ leaves as they are.
static NSString *TSModifiedNormalization(NSString *string, BOOL composed)
{
    static NSRegularExpression *outside;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        outside = [NSRegularExpression regularExpressionWithPattern:@"[^\\x{2000}-\\x{2FFF}\\x{F900}-\\x{FAFF}\\x{2F800}-\\x{2FAFF}]+" options:0 error:NULL];
    });
    NSMutableString *result = [NSMutableString stringWithCapacity:string.length];
    __block NSUInteger done = 0;
    [outside enumerateMatchesInString:string options:0 range:NSMakeRange(0, string.length)
                           usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSRange range = match.range;
        [result appendString:[string substringWithRange:NSMakeRange(done, range.location - done)]];
        NSString *part = [string substringWithRange:range];
        [result appendString:composed ? part.precomposedStringWithCanonicalMapping : part.decomposedStringWithCanonicalMapping];
        done = NSMaxRange(range);
    }];
    [result appendString:[string substringFromIndex:done]];
    return result;
}

// NFKC_Casefold: NFKC of the case folding of NFKC, without the default ignorable code points, until it does not change.
static NSString *TSNFKCCaseFold(NSString *string)
{
    NSString *current = string.precomposedStringWithCompatibilityMapping;
    for (NSUInteger pass = 0; pass < 3; pass++) {
        NSMutableString *folded = [current mutableCopy];
        CFStringFold((__bridge CFMutableStringRef)folded, kCFCompareCaseInsensitive, NULL);
        NSMutableString *kept = [NSMutableString stringWithCapacity:folded.length];
        [folded enumerateSubstringsInRange:NSMakeRange(0, folded.length) options:NSStringEnumerationByComposedCharacterSequences | NSStringEnumerationSubstringNotRequired
                                usingBlock:^(NSString *substring, NSRange range, NSRange enclosing, BOOL *stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); ) {
                UChar32 c = [folded characterAtIndex:i];
                NSUInteger units = 1;
                if (CFStringIsSurrogateHighCharacter((UniChar)c) && i + 1 < NSMaxRange(range)
                    && CFStringIsSurrogateLowCharacter([folded characterAtIndex:i + 1])) {
                    c = (UChar32)CFStringGetLongCharacterForSurrogatePair((UniChar)c, [folded characterAtIndex:i + 1]);
                    units = 2;
                }
                if (!u_hasBinaryProperty(c, UCHAR_DEFAULT_IGNORABLE_CODE_POINT))
                    [kept appendString:[folded substringWithRange:NSMakeRange(i, units)]];
                i += units;
            }
        }];
        NSString *next = kept.precomposedStringWithCompatibilityMapping;
        if ([next isEqualToString:current])
            break;
        current = next;
    }
    return current;
}

static NSString *TSNormalizedText(NSString *string, TSUnicodeNormalization normalization)
{
    switch (normalization) {
        case TSUnicodeNormalizationNone: return string;
        case TSUnicodeNormalizationNFC: return string.precomposedStringWithCanonicalMapping;
        case TSUnicodeNormalizationNFD: return string.decomposedStringWithCanonicalMapping;
        case TSUnicodeNormalizationNFKC: return string.precomposedStringWithCompatibilityMapping;
        case TSUnicodeNormalizationNFKD: return string.decomposedStringWithCompatibilityMapping;
        case TSUnicodeNormalizationNFKCCaseFold: return TSNFKCCaseFold(string);
        case TSUnicodeNormalizationModifiedNFC: return TSModifiedNormalization(string, YES);
        case TSUnicodeNormalizationModifiedNFD: return TSModifiedNormalization(string, NO);
    }
    return string;
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
    if (cancel && cancel())
        return NSNotFound;
    text = TSNormalizedText(text, options.normalization);
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
