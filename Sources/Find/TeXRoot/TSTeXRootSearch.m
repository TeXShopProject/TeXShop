// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearch.h"
#import "TSRegexFindPattern.h"
#import "TSRegexMultipleReplace.h"
#import "TSRegexReplacementRule.h"
#import "TSRegexTextFind.h"

static BOOL TSIsLineBreak(unichar c)
{
    return c == '\n' || c == '\r' || c == 0x0085 || c == 0x2028 || c == 0x2029;
}

/// The end of `text` without its last line break.
static NSUInteger TSContentsEnd(NSString *text)
{
    NSUInteger length = text.length;
    if (length == 0 || !TSIsLineBreak([text characterAtIndex:length - 1]))
        return length;
    if (length >= 2 && [text characterAtIndex:length - 1] == '\n' && [text characterAtIndex:length - 2] == '\r')
        return length - 2;
    return length - 1;
}

#pragma mark - Source

@implementation TSTeXRootSearchSource

- (instancetype)initWithFile:(TSTeXRootProjectFile *)file openDocumentText:(NSString *)text lineEnding:(nullable NSString *)lineEnding
            searchOnlyReason:(TSTeXRootSearchOnlyReason)reason
{
    if (!(self = [super init]))
        return nil;
    _file = file;
    _text = [text copy];
    _openDocument = YES;
    _lineEnding = [lineEnding copy];
    _searchOnlyReason = reason;
    return self;
}

- (instancetype)initWithFile:(TSTeXRootProjectFile *)file
{
    if (!(self = [self initWithFile:file openDocumentText:file.text lineEnding:nil searchOnlyReason:file.searchOnlyReason]))
        return nil;
    _openDocument = NO;
    return self;
}

@end

#pragma mark - Query

@interface TSTeXRootSearchQuery ()
- (instancetype)initPrivate;
@property (nonatomic, readwrite) TSTeXRootSearchMode mode;
@property (nonatomic, readwrite, copy, nullable) NSString *findString;
@property (nonatomic, readwrite) TSRegexFindOptions options;
@property (nonatomic, readwrite, copy, nullable) NSString *replaceString;
@property (nonatomic, readwrite) TSRegexReplacementSyntax replacementSyntax;
@property (nonatomic, readwrite, nullable) TSRegexMultipleReplace *multipleReplace;
@property (nonatomic, readwrite, copy) NSDictionary<NSNumber *, NSError *> *ruleErrors;
@end

@implementation TSTeXRootSearchQuery

- (instancetype)initPrivate
{
    if (!(self = [super init]))
        return nil;
    _ruleErrors = @{};
    return self;
}

+ (nullable instancetype)findQueryWithString:(NSString *)findString options:(TSRegexFindOptions)options error:(NSError **)error
{
    if (![[TSRegexFindPattern alloc] initWithFindString:findString options:options error:error])
        return nil;
    TSTeXRootSearchQuery *query = [[self alloc] initPrivate];
    query.mode = TSTeXRootSearchModeFind;
    query.findString = findString;
    query.options = options;
    return query;
}

+ (nullable instancetype)replaceQueryWithString:(NSString *)findString replacement:(NSString *)replaceString
                                        options:(TSRegexFindOptions)options syntax:(TSRegexReplacementSyntax)syntax
                                          error:(NSError **)error
{
    TSTeXRootSearchQuery *query = [self findQueryWithString:findString options:options error:error];
    query.mode = TSTeXRootSearchModeReplace;
    query.replaceString = replaceString;
    query.replacementSyntax = syntax;
    return query;
}

+ (instancetype)multipleReplaceQueryWithSet:(TSRegexMultipleReplace *)set
{
    TSTeXRootSearchQuery *query = [[self alloc] initPrivate];
    query.mode = TSTeXRootSearchModeMultipleReplace;
    query.multipleReplace = [set copy];
    query.replacementSyntax = set.replacementSyntax;
    NSMutableDictionary<NSNumber *, NSError *> *errors = [NSMutableDictionary dictionary];
    [set.rules enumerateObjectsUsingBlock:^(TSRegexReplacementRule *rule, NSUInteger index, BOOL *stop) {
        NSError *error = nil;
        if (rule.enabled && ![[TSRegexFindPattern alloc] initWithFindString:rule.findString options:[set optionsForRule:rule] error:&error])
            errors[@(index)] = error;
    }];
    query.ruleErrors = errors;
    return query;
}

@end

#pragma mark - Item

@interface TSTeXRootSearchItem ()
- (instancetype)initWithRange:(NSRange)range replacement:(nullable NSString *)replacement lineNumber:(NSUInteger)lineNumber
                   beforeText:(NSString *)beforeText beforeHighlight:(NSRange)beforeHighlight
                    afterText:(nullable NSString *)afterText afterHighlight:(NSRange)afterHighlight;
@end

@implementation TSTeXRootSearchItem

- (instancetype)initWithRange:(NSRange)range replacement:(nullable NSString *)replacement lineNumber:(NSUInteger)lineNumber
                   beforeText:(NSString *)beforeText beforeHighlight:(NSRange)beforeHighlight
                    afterText:(nullable NSString *)afterText afterHighlight:(NSRange)afterHighlight
{
    if (!(self = [super init]))
        return nil;
    _range = range;
    _replacement = [replacement copy];
    _lineNumber = lineNumber;
    _beforeText = [beforeText copy];
    _beforeHighlight = beforeHighlight;
    _afterText = [afterText copy];
    _afterHighlight = afterHighlight;
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ line %lu>", self.class, NSStringFromRange(self.range), (unsigned long)self.lineNumber];
}

@end

#pragma mark - Results

@interface TSTeXRootSearchFileResult ()
- (instancetype)initWithSource:(TSTeXRootSearchSource *)source items:(NSArray<TSTeXRootSearchItem *> *)items
              searchOnlyReason:(TSTeXRootSearchOnlyReason)reason truncated:(BOOL)truncated;
@end

@implementation TSTeXRootSearchFileResult

- (instancetype)initWithSource:(TSTeXRootSearchSource *)source items:(NSArray<TSTeXRootSearchItem *> *)items
              searchOnlyReason:(TSTeXRootSearchOnlyReason)reason truncated:(BOOL)truncated
{
    if (!(self = [super init]))
        return nil;
    _source = source;
    _items = [items copy];
    _searchOnlyReason = reason;
    _truncated = truncated;
    return self;
}

- (NSString *)textReplacingItemsAtIndexes:(NSIndexSet *)indexes
{
    NSString *text = self.source.text;
    NSMutableString *result = [NSMutableString stringWithCapacity:text.length];
    __block NSUInteger location = 0;
    [self.items enumerateObjectsUsingBlock:^(TSTeXRootSearchItem *item, NSUInteger index, BOOL *stop) {
        if (!item.replacement || ![indexes containsIndex:index])
            return;
        [result appendString:[text substringWithRange:NSMakeRange(location, item.range.location - location)]];
        [result appendString:(NSString *_Nonnull)item.replacement];
        location = NSMaxRange(item.range);
    }];
    [result appendString:[text substringFromIndex:location]];
    return result;
}

@end

@interface TSTeXRootSearchResult ()
- (instancetype)initWithMode:(TSTeXRootSearchMode)mode generation:(NSUInteger)generation
                       files:(NSArray<TSTeXRootSearchFileResult *> *)files reachedLimit:(BOOL)reachedLimit;
@end

@implementation TSTeXRootSearchResult

- (instancetype)initWithMode:(TSTeXRootSearchMode)mode generation:(NSUInteger)generation
                       files:(NSArray<TSTeXRootSearchFileResult *> *)files reachedLimit:(BOOL)reachedLimit
{
    if (!(self = [super init]))
        return nil;
    _mode = mode;
    _generation = generation;
    _files = [files copy];
    NSUInteger count = 0;
    for (TSTeXRootSearchFileResult *file in files)
        count += file.items.count;
    _numberOfItems = count;
    _reachedLimit = reachedLimit;
    return self;
}

@end

#pragma mark - Line numbers

/// Counts the lines before positions given in ascending order (a CRLF is one line break).
typedef struct {
    CFStringInlineBuffer buffer;
    NSUInteger length;
    NSUInteger position;
    NSUInteger line;
} TSLineCounter;

static void TSLineCounterInit(TSLineCounter *counter, NSString *text)
{
    counter->length = text.length;
    CFStringInitInlineBuffer((__bridge CFStringRef)text, &counter->buffer, CFRangeMake(0, (CFIndex)counter->length));
    counter->position = 0;
    counter->line = 1;
}

/// The line number of `position`, which is the start of a line and not before the last position asked for.
static NSUInteger TSLineCounterLineAt(TSLineCounter *counter, NSUInteger position)
{
    for (NSUInteger i = counter->position; i < position; i++) {
        unichar c = CFStringGetCharacterFromInlineBuffer(&counter->buffer, (CFIndex)i);
        if (c == '\n' && i > 0 && CFStringGetCharacterFromInlineBuffer(&counter->buffer, (CFIndex)i - 1) == '\r')
            continue;
        if (TSIsLineBreak(c))
            counter->line++;
    }
    if (position > counter->position)
        counter->position = position;
    return counter->line;
}

#pragma mark - Multiple replacement: what changed

/// A part of the text that replacements touched: [cLoc, cLoc + cLen) in the current text came from
/// [oLoc, oLoc + oLen) of the original; between parts both texts are the same.
typedef struct {
    NSUInteger cLoc, cLen, oLoc, oLen;
} TSTeXRootRegion;

/// One replacement of one rule, in the text the rule searched.
typedef struct {
    NSUInteger location, length, newLength;
} TSTeXRootEdit;

/// The parts after a rule's replacements, in the rule's result. Parts and replacements that overlap or touch become one.
static NSData *TSComposeRegions(NSData *regionData, NSData *editData)
{
    const TSTeXRootRegion *regions = regionData.bytes;
    const TSTeXRootEdit *edits = editData.bytes;
    NSUInteger regionCount = regionData.length / sizeof(TSTeXRootRegion), editCount = editData.length / sizeof(TSTeXRootEdit);
    NSMutableData *result = [NSMutableData data];
    NSUInteger i = 0, j = 0;
    NSInteger delta = 0;    // original position minus current position, between parts
    NSInteger shift = 0;    // result position minus current position, after the replacements so far
    while (i < regionCount || j < editCount) {
        BOOL takesRegion = i < regionCount && (j >= editCount || regions[i].cLoc <= edits[j].location);
        NSUInteger start = takesRegion ? regions[i].cLoc : edits[j].location;
        NSUInteger end = start;
        NSInteger deltaBefore = delta, grows = 0;
        BOOL first = YES;
        for (;;) {
            if (i < regionCount && (first ? takesRegion : regions[i].cLoc <= end)) {
                end = MAX(end, regions[i].cLoc + regions[i].cLen);
                delta = (NSInteger)(regions[i].oLoc + regions[i].oLen) - (NSInteger)(regions[i].cLoc + regions[i].cLen);
                i++;
            } else if (j < editCount && (first ? !takesRegion : edits[j].location <= end)) {
                end = MAX(end, edits[j].location + edits[j].length);
                grows += (NSInteger)edits[j].newLength - (NSInteger)edits[j].length;
                j++;
            } else {
                break;
            }
            first = NO;
        }
        TSTeXRootRegion region;
        region.oLoc = (NSUInteger)((NSInteger)start + deltaBefore);
        region.oLen = (NSUInteger)((NSInteger)end + delta - (NSInteger)region.oLoc);
        region.cLoc = (NSUInteger)((NSInteger)start + shift);
        region.cLen = (NSUInteger)((NSInteger)(end - start) + grows);
        shift += grows;
        [result appendBytes:&region length:sizeof region];
    }
    return result;
}

/// A run of whole lines: [oStart, oEnd) of the original and [fStart, fEnd) of the result.
typedef struct {
    NSUInteger oStart, oEnd, fStart, fEnd;
} TSTeXRootWindow;

/// The parts widened to whole lines, joined when they share a line or touch. Outside them both texts are the same.
static NSData *TSWindowsOfRegions(NSData *regionData, NSString *final)
{
    const TSTeXRootRegion *regions = regionData.bytes;
    NSUInteger count = regionData.length / sizeof(TSTeXRootRegion), length = final.length;
    NSMutableData *result = [NSMutableData data];
    for (NSUInteger index = 0; index < count; index++) {
        TSTeXRootRegion r = regions[index];
        // Between the parts the texts are the same, so a line break found there is a line break of both. A CR just
        // before the part may be half of a CRLF in one text only: it is passed over.
        NSUInteger gapStart = index > 0 ? regions[index - 1].cLoc + regions[index - 1].cLen : 0;
        NSUInteger start = gapStart;
        for (NSUInteger p = r.cLoc; p > gapStart; p--) {
            unichar c = [final characterAtIndex:p - 1];
            if (!TSIsLineBreak(c) || (c == '\r' && p == r.cLoc))
                continue;
            start = p;
            break;
        }
        NSUInteger gapEnd = index + 1 < count ? regions[index + 1].cLoc : length;
        NSUInteger end = gapEnd;
        for (NSUInteger q = r.cLoc + r.cLen; q < gapEnd; q++) {
            unichar c = [final characterAtIndex:q];
            if (!TSIsLineBreak(c))
                continue;
            // A CR just before the next part ends where that part starts, so the two are joined.
            end = c == '\r' && q + 1 < gapEnd && [final characterAtIndex:q + 1] == '\n' ? q + 2 : q + 1;
            break;
        }
        TSTeXRootWindow window = {
            r.oLoc - (r.cLoc - start), r.oLoc + r.oLen + (end - (r.cLoc + r.cLen)), start, end
        };
        TSTeXRootWindow *last = result.length > 0 ? (TSTeXRootWindow *)((char *)result.mutableBytes + result.length - sizeof window) : NULL;
        if (last && last->fEnd >= window.fStart) {
            last->oEnd = window.oEnd;
            last->fEnd = window.fEnd;
        } else {
            [result appendBytes:&window length:sizeof window];
        }
    }
    return result;
}

/// The lines of `text` in `range` (each with its line break), as ranges of `text`.
static NSArray<NSValue *> *TSLinesInRange(NSString *text, NSRange range)
{
    NSMutableArray<NSValue *> *lines = [NSMutableArray array];
    NSUInteger location = range.location, end = NSMaxRange(range);
    while (location < end) {
        NSUInteger lineEnd = 0;
        [text getLineStart:NULL end:&lineEnd contentsEnd:NULL forRange:NSMakeRange(location, 0)];
        lineEnd = MIN(lineEnd, end);
        [lines addObject:[NSValue valueWithRange:NSMakeRange(location, lineEnd - location)]];
        location = lineEnd;
    }
    return lines;
}

/// The lines that stay the same, as pairs (index in `a`, index in `b`) in ascending order, by Myers's algorithm. Nil
/// when more than `maximumEdits` edits are needed, or when cancelled.
static NSArray<NSValue *> *_Nullable TSMatchingLines(NSArray<NSString *> *a, NSArray<NSString *> *b, NSUInteger maximumEdits,
                                                     BOOL (^_Nullable cancellation)(void))
{
    NSInteger n = (NSInteger)a.count, m = (NSInteger)b.count;
    NSInteger max = MIN(n + m, (NSInteger)maximumEdits);
    NSUInteger *hashA = malloc(sizeof(NSUInteger) * (NSUInteger)MAX(n, 1)), *hashB = malloc(sizeof(NSUInteger) * (NSUInteger)MAX(m, 1));
    for (NSInteger i = 0; i < n; i++)
        hashA[i] = a[(NSUInteger)i].hash;
    for (NSInteger j = 0; j < m; j++)
        hashB[j] = b[(NSUInteger)j].hash;
    BOOL (^equal)(NSInteger, NSInteger) = ^BOOL(NSInteger x, NSInteger y) {
        return hashA[x] == hashB[y] && [a[(NSUInteger)x] isEqualToString:b[(NSUInteger)y]];
    };
    NSInteger offset = max + 1;
    NSInteger *v = calloc((NSUInteger)(2 * max + 3), sizeof(NSInteger));
    NSMutableArray<NSData *> *trace = [NSMutableArray array];   // trace[d]: v[-d ... d] after step d
    NSInteger found = -1;
    for (NSInteger d = 0; d <= max && found < 0; d++) {
        if (cancellation && cancellation())
            break;
        for (NSInteger k = -d; k <= d; k += 2) {
            NSInteger x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1;
            NSInteger y = x - k;
            while (x < n && y < m && equal(x, y)) {
                x++;
                y++;
            }
            v[offset + k] = x;
            if (x >= n && y >= m) {
                found = d;
                break;
            }
        }
        [trace addObject:[NSData dataWithBytes:v + offset - d length:sizeof(NSInteger) * (NSUInteger)(2 * d + 1)]];
    }
    free(v);
    NSMutableArray<NSValue *> *pairs = nil;
    if (found >= 0) {
        pairs = [NSMutableArray array];
        NSInteger x = n, y = m;
        for (NSInteger d = found; d > 0; d--) {
            const NSInteger *previous = (const NSInteger *)trace[(NSUInteger)d - 1].bytes;
            NSInteger base = d - 1;   // previous[k + base] is v[k] after step d - 1
            NSInteger k = x - y;
            NSInteger previousK = (k == -d || (k != d && previous[k - 1 + base] < previous[k + 1 + base])) ? k + 1 : k - 1;
            NSInteger previousX = previous[previousK + base], previousY = previousX - previousK;
            while (x > previousX && y > previousY) {
                x--;
                y--;
                [pairs addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)x, (NSUInteger)y)]];
            }
            x = previousX;
            y = previousY;
        }
        while (x > 0 && y > 0) {
            x--;
            y--;
            [pairs addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)x, (NSUInteger)y)]];
        }
        pairs = [[pairs reverseObjectEnumerator].allObjects mutableCopy];
    }
    free(hashA);
    free(hashB);
    return pairs;
}

#pragma mark - Items

/// The highlights of a hunk: what lies between the common start and the common end of the two texts, on whole
/// characters. The last line break of each text is left out unless it is inside the highlight.
static TSTeXRootSearchItem *TSHunkItem(NSRange range, NSString *before, NSString *after, NSUInteger lineNumber)
{
    NSUInteger beforeLength = before.length, afterLength = after.length;
    NSUInteger prefix = 0, limit = MIN(beforeLength, afterLength);
    while (prefix < limit && [before characterAtIndex:prefix] == [after characterAtIndex:prefix])
        prefix++;
    // On whole characters: back to where a character starts in both texts.
    for (;;) {
        NSUInteger start = prefix;
        if (start < beforeLength)
            start = MIN(start, [before rangeOfComposedCharacterSequenceAtIndex:start].location);
        if (start < afterLength)
            start = MIN(start, [after rangeOfComposedCharacterSequenceAtIndex:start].location);
        if (start == prefix)
            break;
        prefix = start;
    }
    NSUInteger suffix = 0;
    while (suffix < limit - prefix && [before characterAtIndex:beforeLength - 1 - suffix] == [after characterAtIndex:afterLength - 1 - suffix])
        suffix++;
    while (suffix > 0 && ([before rangeOfComposedCharacterSequenceAtIndex:beforeLength - suffix].location != beforeLength - suffix
                          || [after rangeOfComposedCharacterSequenceAtIndex:afterLength - suffix].location != afterLength - suffix))
        suffix--;
    NSRange beforeHighlight = NSMakeRange(prefix, beforeLength - prefix - suffix);
    NSRange afterHighlight = NSMakeRange(prefix, afterLength - prefix - suffix);
    NSUInteger beforeEnd = MAX(TSContentsEnd(before), NSMaxRange(beforeHighlight));
    NSUInteger afterEnd = MAX(TSContentsEnd(after), NSMaxRange(afterHighlight));
    return [[TSTeXRootSearchItem alloc] initWithRange:range replacement:after lineNumber:lineNumber
                                           beforeText:[before substringToIndex:beforeEnd] beforeHighlight:beforeHighlight
                                            afterText:[after substringToIndex:afterEnd] afterHighlight:afterHighlight];
}

/// A match: the lines it touches, with only this match replaced when `replacement` is given.
static TSTeXRootSearchItem *TSMatchItem(NSString *text, NSRange match, NSString *_Nullable replacement, TSLineCounter *counter)
{
    NSUInteger start = 0, end = 0, contentsEnd = 0;
    [text getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:match];
    NSUInteger lineNumber = TSLineCounterLineAt(counter, start);
    NSUInteger matchEnd = NSMaxRange(match);
    // A match that takes part of the last line break keeps the line break in the text, so that the highlight is in it.
    NSUInteger textEnd = matchEnd > contentsEnd ? end : contentsEnd;
    NSString *before = [text substringWithRange:NSMakeRange(start, textEnd - start)];
    NSRange beforeHighlight = NSMakeRange(match.location - start, match.length);
    if (!replacement)
        return [[TSTeXRootSearchItem alloc] initWithRange:match replacement:nil lineNumber:lineNumber
                                               beforeText:before beforeHighlight:beforeHighlight afterText:nil afterHighlight:NSMakeRange(0, 0)];
    NSMutableString *after = [[text substringWithRange:NSMakeRange(start, match.location - start)] mutableCopy];
    [after appendString:(NSString *_Nonnull)replacement];
    [after appendString:[text substringWithRange:NSMakeRange(matchEnd, textEnd - matchEnd)]];
    NSRange afterHighlight = NSMakeRange(match.location - start, replacement.length);
    return [[TSTeXRootSearchItem alloc] initWithRange:match replacement:replacement lineNumber:lineNumber
                                           beforeText:before beforeHighlight:beforeHighlight afterText:after afterHighlight:afterHighlight];
}

#pragma mark - Search

@implementation TSTeXRootSearch

+ (NSUInteger)defaultMaximumItemsPerFile { return 5000; }
+ (NSUInteger)defaultMaximumItems { return 500000; }
+ (NSUInteger)maximumLineEdits { return 1024; }

+ (NSString *)firstLineEndingInText:(NSString *)text
{
    static NSCharacterSet *breaks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const unichar characters[] = {'\n', '\r', 0x0085, 0x2028, 0x2029};
        breaks = [NSCharacterSet characterSetWithCharactersInString:[NSString stringWithCharacters:characters length:5]];
    });
    NSRange found = [text rangeOfCharacterFromSet:breaks options:NSLiteralSearch];
    if (found.location == NSNotFound)
        return @"\n";
    if ([text characterAtIndex:found.location] == '\r' && found.location + 1 < text.length && [text characterAtIndex:found.location + 1] == '\n')
        return @"\r\n";
    return [text substringWithRange:found];
}

+ (NSString *)lineEndingAtIndex:(NSUInteger)index inText:(NSString *)text
{
    NSUInteger end = 0, contentsEnd = 0;
    [text getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(MIN(index, text.length), 0)];
    return end > contentsEnd ? [text substringWithRange:NSMakeRange(contentsEnd, end - contentsEnd)] : [self firstLineEndingInText:text];
}

/// The line ending of the find strings: the open document's (nil to keep them), or the file's first.
+ (nullable NSString *)findLineEndingOfSource:(TSTeXRootSearchSource *)source
{
    return source.openDocument ? source.lineEnding : [self firstLineEndingInText:source.text];
}

/// A replacement put into the line ending: the open document's (none when it has none), or for a file on the disk
/// the line ending of the line where the match starts in `text`.
+ (NSString *)replacement:(NSString *)replacement atIndex:(NSUInteger)index inText:(NSString *)text source:(TSTeXRootSearchSource *)source
{
    if (source.openDocument)
        return source.lineEnding ? TSRegexStringByReplacingLineEndings(replacement, (NSString *_Nonnull)source.lineEnding) : replacement;
    return TSRegexStringByReplacingLineEndings(replacement, [self lineEndingAtIndex:index inText:text]);
}

+ (nullable TSTeXRootSearchResult *)searchSources:(NSArray<TSTeXRootSearchSource *> *)sources
                                            query:(TSTeXRootSearchQuery *)query
                                       generation:(NSUInteger)generation
                                            codec:(nullable TSTeXRootSourceCodec *)codec
                              maximumItemsPerFile:(NSUInteger)maximumItemsPerFile
                                     maximumItems:(NSUInteger)maximumItems
                                     cancellation:(nullable BOOL (^)(void))isCancelled
                                         progress:(nullable void (^)(NSUInteger done, NSUInteger total))progress
{
    // Once isCancelled has said YES, the search is cancelled whatever it says later.
    __block BOOL cancelled = NO;
    BOOL (^cancellation)(void) = ^BOOL { return cancelled || (isCancelled && (cancelled = isCancelled())); };
    NSMutableArray<TSTeXRootSearchFileResult *> *files = [NSMutableArray array];
    NSUInteger total = 0;
    BOOL reachedLimit = NO;
    NSUInteger done = 0;
    for (TSTeXRootSearchSource *source in sources) {
        if (cancellation())
            return nil;
        NSUInteger room = maximumItems - total;
        BOOL truncated = NO, overAll = NO;
        NSString *replacedText = nil;
        NSArray<TSTeXRootSearchItem *> *items = query.mode == TSTeXRootSearchModeMultipleReplace
            ? [self hunksInSource:source query:query perFile:maximumItemsPerFile room:room truncated:&truncated overAll:&overAll
                     replacedText:&replacedText cancellation:cancellation]
            : [self matchesInSource:source query:query perFile:maximumItemsPerFile room:room truncated:&truncated overAll:&overAll
                       replacedText:&replacedText cancellation:cancellation];
        if (!items)
            return nil;
        if (truncated)
            reachedLimit = YES;
        if (items.count > 0) {
            TSTeXRootSearchOnlyReason reason = source.searchOnlyReason;
            // The text with every item replaced must be writable in the file's encoding; any part of it then is too,
            // since every character of the original text is.
            if (reason == TSTeXRootSearchOnlyReasonNone && replacedText && !source.openDocument && codec && source.file.reading
                && ![codec dataForText:replacedText encoding:source.file.reading.encoding byteOrderMark:source.file.reading.byteOrderMark])
                reason = TSTeXRootSearchOnlyReasonUnencodable;
            [files addObject:[[TSTeXRootSearchFileResult alloc] initWithSource:source items:items searchOnlyReason:reason truncated:truncated]];
            total += items.count;
        }
        done++;
        if (progress)
            progress(done, sources.count);
        if (overAll)
            break;
    }
    if (cancellation())
        return nil;
    return [[TSTeXRootSearchResult alloc] initWithMode:query.mode generation:generation files:files reachedLimit:reachedLimit];
}

/// Find and replace: one item per match, the replacements built as Replace All builds them.
+ (nullable NSArray<TSTeXRootSearchItem *> *)matchesInSource:(TSTeXRootSearchSource *)source query:(TSTeXRootSearchQuery *)query
                                                     perFile:(NSUInteger)perFile room:(NSUInteger)room
                                                   truncated:(BOOL *)truncated overAll:(BOOL *)overAll
                                                replacedText:(NSString *_Nullable *_Nonnull)replacedText
                                                cancellation:(BOOL (^)(void))cancellation
{
    NSString *text = source.text;
    NSString *lineEnding = [self findLineEndingOfSource:source];
    NSString *findString = lineEnding ? TSRegexStringByReplacingLineEndings((NSString *_Nonnull)query.findString, (NSString *_Nonnull)lineEnding)
                                      : (NSString *_Nonnull)query.findString;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:findString options:query.options error:NULL];
    if (!pattern)
        return @[];
    BOOL replaces = query.mode == TSTeXRootSearchModeReplace;
    TSRegexReplacementTemplate *template = replaces ? [[TSRegexReplacementTemplate alloc] initWithString:(NSString *_Nonnull)query.replaceString
                                                                                                  pattern:pattern syntax:query.replacementSyntax] : nil;
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *replacements = [NSMutableArray array];
    __block NSUInteger location = 0;
    [pattern enumerateMatchesInString:text range:NSMakeRange(0, text.length) cancellation:cancellation usingBlock:^(NSRange matchRange, NSTextCheckingResult *result, BOOL *stop) {
        if (ranges.count == perFile || ranges.count == room) {
            *truncated = YES;
            *overAll = ranges.count == room;
            *stop = YES;
            return;
        }
        [ranges addObject:[NSValue valueWithRange:matchRange]];
        if (template)
            [replacements addObject:[self replacement:[template replacementForMatchRange:matchRange result:result inString:text previousMatchEnd:location]
                                              atIndex:matchRange.location inText:text source:source]];
        location = NSMaxRange(matchRange);
    }];
    if (cancellation())
        return nil;
    NSMutableArray<TSTeXRootSearchItem *> *items = [NSMutableArray arrayWithCapacity:ranges.count];
    TSLineCounter counter;
    TSLineCounterInit(&counter, text);
    NSMutableString *replaced = replaces ? [NSMutableString stringWithCapacity:text.length] : nil;
    NSUInteger copied = 0;
    for (NSUInteger index = 0; index < ranges.count; index++) {
        if (index % 1024 == 1023 && cancellation())
            return nil;
        NSRange range = ranges[index].rangeValue;
        [items addObject:TSMatchItem(text, range, replaces ? replacements[index] : nil, &counter)];
        if (replaced) {
            [replaced appendString:[text substringWithRange:NSMakeRange(copied, range.location - copied)]];
            [replaced appendString:replacements[index]];
            copied = NSMaxRange(range);
        }
    }
    if (replaced) {
        [replaced appendString:[text substringFromIndex:copied]];
        *replacedText = replaced;
    }
    return items;
}

/// Applies the enabled rules one after another to the whole text, as the panel does, and keeps track of the parts
/// of the original that the replacements touched. Nil when cancelled.
+ (nullable NSString *)applyRulesToSource:(TSTeXRootSearchSource *)source query:(TSTeXRootSearchQuery *)query
                                  regions:(NSData *_Nullable *_Nonnull)regions cancellation:(BOOL (^)(void))cancellation
{
    TSRegexMultipleReplace *set = (TSRegexMultipleReplace *_Nonnull)query.multipleReplace;
    NSString *lineEnding = [self findLineEndingOfSource:source];
    NSString *current = source.text;
    NSData *parts = [NSData data];
    for (TSRegexReplacementRule *rule in set.rules) {
        if (cancellation())
            return nil;
        if (!rule.enabled)
            continue;
        NSString *findString = lineEnding ? TSRegexStringByReplacingLineEndings(rule.findString, (NSString *_Nonnull)lineEnding) : rule.findString;
        TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:findString options:[set optionsForRule:rule] error:NULL];
        if (!pattern)
            continue;
        TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:rule.replaceString pattern:pattern syntax:set.replacementSyntax];
        NSString *string = current;
        NSMutableString *next = [NSMutableString stringWithCapacity:string.length];
        NSMutableData *edits = [NSMutableData data];
        __block NSUInteger location = 0;
        [pattern enumerateMatchesInString:string range:NSMakeRange(0, string.length) cancellation:cancellation usingBlock:^(NSRange matchRange, NSTextCheckingResult *result, BOOL *stop) {
            NSString *replacement = [self replacement:[template replacementForMatchRange:matchRange result:result inString:string previousMatchEnd:location]
                                              atIndex:matchRange.location inText:string source:source];
            [next appendString:[string substringWithRange:NSMakeRange(location, matchRange.location - location)]];
            [next appendString:replacement];
            TSTeXRootEdit edit = {matchRange.location, matchRange.length, replacement.length};
            [edits appendBytes:&edit length:sizeof edit];
            location = NSMaxRange(matchRange);
        }];
        if (cancellation())
            return nil;
        if (edits.length == 0)
            continue;
        [next appendString:[string substringFromIndex:location]];
        parts = TSComposeRegions(parts, edits);
        current = next;
    }
    *regions = parts;
    return current;
}

/// Multiple replacement: one item per hunk of changed lines.
+ (nullable NSArray<TSTeXRootSearchItem *> *)hunksInSource:(TSTeXRootSearchSource *)source query:(TSTeXRootSearchQuery *)query
                                                   perFile:(NSUInteger)perFile room:(NSUInteger)room
                                                 truncated:(BOOL *)truncated overAll:(BOOL *)overAll
                                              replacedText:(NSString *_Nullable *_Nonnull)replacedText
                                              cancellation:(BOOL (^)(void))cancellation
{
    NSData *regions = nil;
    NSString *final = [self applyRulesToSource:source query:query regions:&regions cancellation:cancellation];
    if (!final)
        return nil;
    NSString *text = source.text;
    NSData *windowData = TSWindowsOfRegions((NSData *_Nonnull)regions, final);
    const TSTeXRootWindow *windows = windowData.bytes;
    NSUInteger windowCount = windowData.length / sizeof(TSTeXRootWindow);
    NSMutableArray<TSTeXRootSearchItem *> *items = [NSMutableArray array];
    TSLineCounter counter;
    TSLineCounterInit(&counter, text);
    for (NSUInteger w = 0; w < windowCount; w++) {
        if (cancellation())
            return nil;
        TSTeXRootWindow window = windows[w];
        NSUInteger firstLine = TSLineCounterLineAt(&counter, window.oStart);
        NSArray<NSValue *> *linesA = TSLinesInRange(text, NSMakeRange(window.oStart, window.oEnd - window.oStart));
        NSArray<NSValue *> *linesB = TSLinesInRange(final, NSMakeRange(window.fStart, window.fEnd - window.fStart));
        NSMutableArray<NSString *> *a = [NSMutableArray arrayWithCapacity:linesA.count], *b = [NSMutableArray arrayWithCapacity:linesB.count];
        for (NSValue *line in linesA)
            [a addObject:[text substringWithRange:line.rangeValue]];
        for (NSValue *line in linesB)
            [b addObject:[final substringWithRange:line.rangeValue]];
        // Lines the same at both ends are left out before comparing.
        NSUInteger head = 0;
        while (head < a.count && head < b.count && [a[head] isEqualToString:b[head]])
            head++;
        NSUInteger tail = 0;
        while (tail < a.count - head && tail < b.count - head && [a[a.count - 1 - tail] isEqualToString:b[b.count - 1 - tail]])
            tail++;
        NSArray<NSString *> *middleA = [a subarrayWithRange:NSMakeRange(head, a.count - head - tail)];
        NSArray<NSString *> *middleB = [b subarrayWithRange:NSMakeRange(head, b.count - head - tail)];
        if (middleA.count == 0 && middleB.count == 0)
            continue;
        NSArray<NSValue *> *pairs = TSMatchingLines(middleA, middleB, self.maximumLineEdits, cancellation);
        if (cancellation())
            return nil;
        // Hunks are the runs between lines that stay the same.
        NSMutableArray<NSValue *> *hunks = [NSMutableArray array];   // {start in a, start in b}, {end in a, end in b}
        NSUInteger i = 0, j = 0;
        for (NSValue *pair in pairs ?: @[]) {
            NSUInteger x = pair.rangeValue.location, y = pair.rangeValue.length;
            if (x > i || y > j) {
                [hunks addObject:[NSValue valueWithRange:NSMakeRange(i, j)]];
                [hunks addObject:[NSValue valueWithRange:NSMakeRange(x, y)]];
            }
            i = x + 1;
            j = y + 1;
        }
        if (i < middleA.count || j < middleB.count) {
            [hunks addObject:[NSValue valueWithRange:NSMakeRange(i, j)]];
            [hunks addObject:[NSValue valueWithRange:NSMakeRange(middleA.count, middleB.count)]];
        }
        for (NSUInteger h = 0; h < hunks.count; h += 2) {
            NSUInteger startA = head + hunks[h].rangeValue.location, startB = head + hunks[h].rangeValue.length;
            NSUInteger endA = head + hunks[h + 1].rangeValue.location, endB = head + hunks[h + 1].rangeValue.length;
            NSUInteger from = startA < linesA.count ? linesA[startA].rangeValue.location : window.oEnd;
            NSUInteger to = endA > startA ? NSMaxRange(linesA[endA - 1].rangeValue) : from;
            NSUInteger fromB = startB < linesB.count ? linesB[startB].rangeValue.location : window.fEnd;
            NSUInteger toB = endB > startB ? NSMaxRange(linesB[endB - 1].rangeValue) : fromB;
            if (items.count == perFile || items.count == room) {
                *truncated = YES;
                *overAll = items.count == room;
                *replacedText = final;
                return items;
            }
            [items addObject:TSHunkItem(NSMakeRange(from, to - from), [text substringWithRange:NSMakeRange(from, to - from)],
                                        [final substringWithRange:NSMakeRange(fromB, toB - fromB)], firstLine + startA)];
        }
    }
    *replacedText = final;
    return items;
}

@end
