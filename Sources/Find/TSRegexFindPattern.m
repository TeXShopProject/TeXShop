// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexFindPattern.h"

static NSString *const TSYenSign = @"¥";

#pragma mark - Plain text found quickly

// NSString's search without NSLiteralSearch finds a word where the text has the same characters, or characters with
// the same canonical decomposition, or, for digits, numbers of the same value. For a word of the characters below, with
// no decomposable one, a match of the other kinds needs a character in the text whose decomposition is free of marks
// and made of the word's own characters (U+212A KELVIN SIGN for K, U+FA03 for 糖), or, for a word with a digit, another
// number.
// Where the text has none of them, every match is a literal match: the literal matches are found quickly, and each is
// checked by the same search, anchored there.

/// The characters whose canonical decomposition has no combining mark, with that decomposition, by the decomposition's
/// first UTF-16 unit.
static NSDictionary<NSNumber *, NSArray<NSArray *> *> *TSUnmarkedDecompositions(void)
{
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSNumber *, NSMutableArray<NSArray *> *> *byFirst = [NSMutableDictionary dictionary];
        NSCharacterSet *decomposable = NSCharacterSet.decomposableCharacterSet, *marks = NSCharacterSet.nonBaseCharacterSet;
        for (UTF32Char c = 0; c <= 0x10FFFF; c++) {
            if ((c & 0xFFFF) == 0 && ![decomposable hasMemberInPlane:(uint8_t)(c >> 16)]) {
                c += 0xFFFF;
                continue;
            }
            if (![decomposable longCharacterIsMember:c])
                continue;
            UTF32Char little = NSSwapHostIntToLittle(c);
            NSString *character = [[NSString alloc] initWithBytes:&little length:4 encoding:NSUTF32LittleEndianStringEncoding];
            NSString *decomposition = character.decomposedStringWithCanonicalMapping;
            if (decomposition.length == 0 || [decomposition rangeOfCharacterFromSet:marks].location != NSNotFound
                || [decomposition compare:character options:NSLiteralSearch] == NSOrderedSame)
                continue;
            NSNumber *first = @([decomposition characterAtIndex:0]);
            if (!byFirst[first])
                byFirst[first] = [NSMutableArray array];
            [byFirst[first] addObject:@[@(c), decomposition]];
        }
        table = byFirst;
    });
    return table;
}

/// The numbers (Unicode N*) other than the ASCII digits. NSString's search without NSLiteralSearch takes a digit of
/// another script or a number of the same value for an ASCII digit (U+0660 or U+3007 for 0), and in a row of numbers
/// even more (９〇 is found as ９0, macOS 27.2).
static NSCharacterSet *TSNumbersButASCIIDigits(void)
{
    static NSCharacterSet *numbers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
        [set formIntersectionWithCharacterSet:NSCharacterSet.letterCharacterSet.invertedSet];
        [set removeCharactersInRange:NSMakeRange('0', 10)];
        numbers = [set copy];
    });
    return numbers;
}

/// The same numbers, one by one.
static NSArray<NSNumber *> *TSNumbersButASCIIDigitsList(void)
{
    static NSArray<NSNumber *> *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSCharacterSet *numbers = TSNumbersButASCIIDigits();
        NSMutableArray<NSNumber *> *all = [NSMutableArray array];
        for (UTF32Char c = 0; c <= 0x10FFFF; c++) {
            if ((c & 0xFFFF) == 0 && ![numbers hasMemberInPlane:(uint8_t)(c >> 16)]) {
                c += 0xFFFF;
                continue;
            }
            if (!(c >= 0xD800 && c <= 0xDFFF) && [numbers longCharacterIsMember:c])
                [all addObject:@(c)];
        }
        list = all;
    });
    return list;
}

/// The characters a quick word may hold: ASCII and Latin-1 but the controls (tab and LF are kept) and the soft hyphen,
/// the spacing modifier letters, CJK ideographs and symbols, kana but the sound marks, and full-width forms; no number
/// but the ASCII digits. NSString's search matches some other characters in its own way: U+0937 U+200D is found as
/// U+0937 U+0600, and U+00AD 1 as U+110BD 1 (macOS 27.2).
static inline BOOL TSIsQuickCharacter(unichar c)
{
    return (c == '\t' || c == '\n' || (c >= 0x20 && c < 0x7F) || (c >= 0xA0 && c < 0x0300 && c != 0xAD) || (c >= 0x3000 && c <= 0x3098)
            || (c >= 0x309D && c <= 0x30FF) || (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0xFF01 && c <= 0xFF9D))
        && ![TSNumbersButASCIIDigits() characterIsMember:c];
}

/// A word that can be found quickly: only quick characters, none decomposable.
@interface TSQuickWord : NSObject {
@public
    NSUInteger _length;
    const unichar *_units;
    uint32_t _skip[256];
    /// The characters that a match of the word without NSLiteralSearch could hold in its place: a bitmap of the
    /// BMP, and the others; nil when there are none.
    NSData *_others;
    NSSet<NSNumber *> *_astralOthers;
}
@property (nonatomic, readonly) NSData *unitData;
@end

@implementation TSQuickWord

+ (nullable TSQuickWord *)quickWordWithString:(NSString *)word
{
    NSUInteger length = word.length;
    if (length == 0 || [word rangeOfCharacterFromSet:NSCharacterSet.nonBaseCharacterSet].location != NSNotFound
        || [word.decomposedStringWithCanonicalMapping compare:word options:NSLiteralSearch] != NSOrderedSame)
        return nil;
    NSMutableData *units = [NSMutableData dataWithLength:length * sizeof(unichar)];
    unichar *u = units.mutableBytes;
    [word getCharacters:u range:NSMakeRange(0, length)];
    NSMutableIndexSet *own = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < length; i++) {
        if (!TSIsQuickCharacter(u[i]))
            return nil;
        [own addIndex:u[i]];
    }
    TSQuickWord *quick = [[TSQuickWord alloc] init];
    quick->_length = length;
    quick->_unitData = units;
    quick->_units = u;
    for (NSUInteger i = 0; i < 256; i++)
        quick->_skip[i] = (uint32_t)length;
    for (NSUInteger i = 0; i + 1 < length; i++)
        quick->_skip[u[i] & 0xFF] = (uint32_t)(length - 1 - i);
    __block NSMutableData *others = nil;
    NSMutableSet<NSNumber *> *astral = [NSMutableSet set];
    void (^addOther)(NSNumber *) = ^(NSNumber *character) {
        UTF32Char c = character.unsignedIntValue;
        if (c > 0xFFFF) {
            [astral addObject:character];
            return;
        }
        if (!others)
            others = [NSMutableData dataWithLength:0x10000 / 8];
        ((uint8_t *)others.mutableBytes)[c >> 3] |= (uint8_t)(1u << (c & 7));
    };
    // With a digit, any other number in the text is left to the search itself.
    if ([own intersectsIndexesInRange:NSMakeRange('0', 10)])
        for (NSNumber *number in TSNumbersButASCIIDigitsList())
            addOther(number);
    NSDictionary<NSNumber *, NSArray<NSArray *> *> *table = TSUnmarkedDecompositions();
    [own enumerateIndexesUsingBlock:^(NSUInteger first, BOOL *stop) {
        for (NSArray *entry in table[@(first)]) {
            NSString *decomposition = entry[1];
            BOOL allOwn = YES;
            for (NSUInteger i = 0; i < decomposition.length && allOwn; i++)
                allOwn = [own containsIndex:[decomposition characterAtIndex:i]];
            if (allOwn)
                addOther(entry[0]);
        }
    }];
    quick->_others = others;
    quick->_astralOthers = astral.count ? astral : nil;
    return quick;
}

/// Whether the characters hold one that a match of the word without NSLiteralSearch could hold in its place.
- (BOOL)hasOthersIn:(const unichar *)chars length:(NSUInteger)length
{
    const uint8_t *bits = _others.bytes;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = chars[i];
        if (bits && (bits[c >> 3] & (1u << (c & 7))))
            return YES;
        if (_astralOthers && CFStringIsSurrogateHighCharacter(c) && i + 1 < length && CFStringIsSurrogateLowCharacter(chars[i + 1])
            && [_astralOthers containsObject:@(CFStringGetLongCharacterForSurrogatePair(c, chars[i + 1]))])
            return YES;
    }
    return NO;
}

/// The first literal match in chars[from - base ..< limit - base], or NSNotFound (Boyer-Moore-Horspool).
- (NSUInteger)literalMatchIn:(const unichar *)chars base:(NSUInteger)base from:(NSUInteger)from limit:(NSUInteger)limit
{
    NSUInteger m = _length;
    unichar last = _units[m - 1];
    for (NSUInteger i = from; i + m <= limit; ) {
        unichar c = chars[i - base + m - 1];
        if (c == last && memcmp(chars + (i - base), _units, (m - 1) * sizeof(unichar)) == 0)
            return i;
        i += _skip[c & 0xFF];
    }
    return NSNotFound;
}

@end

#pragma mark -

@interface TSRegexFindPattern ()
@property (nonatomic, readonly, nullable) NSRegularExpression *regex;
/// The words to look for in plain text; one word unless whitespace delimits them.
@property (nonatomic, readonly, copy) NSArray<NSString *> *words;
/// For each word, its quick form, or NSNull; empty unless the comparison is the plain one.
@property (nonatomic, readonly, copy) NSArray *quickWords;
@end

@implementation TSRegexFindPattern

+ (NSString *)normalizedString:(NSString *)string options:(TSRegexFindOptions)options
{
    if (!(options & TSRegexFindYenIsBackslash) || [string rangeOfString:TSYenSign].location == NSNotFound)
        return [string copy];
    return [string stringByReplacingOccurrencesOfString:TSYenSign withString:@"\\"];
}

+ (NSError *)errorWithCode:(TSRegexFindError)code description:(NSString *)description underlyingError:(nullable NSError *)underlyingError
{
    NSMutableDictionary<NSErrorUserInfoKey, id> *info = [NSMutableDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
    if (underlyingError)
        info[NSUnderlyingErrorKey] = underlyingError;
    return [NSError errorWithDomain:TSRegexFindErrorDomain code:code userInfo:info];
}

+ (NSRegularExpressionOptions)regularExpressionOptions:(TSRegexFindOptions)options
{
    NSRegularExpressionOptions result = 0;
    if (options & TSRegexFindIgnoreCase) result |= NSRegularExpressionCaseInsensitive;
    if (options & TSRegexFindDotMatchesLineSeparators) result |= NSRegularExpressionDotMatchesLineSeparators;
    if (options & TSRegexFindAnchorsMatchLines) result |= NSRegularExpressionAnchorsMatchLines;
    if (options & TSRegexFindAllowCommentsAndWhitespace) result |= NSRegularExpressionAllowCommentsAndWhitespace;
    if (options & TSRegexFindUnicodeWordBoundaries) result |= NSRegularExpressionUseUnicodeWordBoundaries;
    if (options & TSRegexFindIgnoreMetacharacters) result |= NSRegularExpressionIgnoreMetacharacters;
    if (options & TSRegexFindUseUnixLineSeparators) result |= NSRegularExpressionUseUnixLineSeparators;
    return result;
}

+ (NSStringCompareOptions)compareOptions:(TSRegexFindOptions)options
{
    NSStringCompareOptions result = 0;
    if (options & TSRegexFindIgnoreCase) result |= NSCaseInsensitiveSearch;
    if (options & TSRegexFindLiteral) result |= NSLiteralSearch;
    if (options & TSRegexFindIgnoreDiacritics) result |= NSDiacriticInsensitiveSearch;
    if (options & TSRegexFindIgnoreWidth) result |= NSWidthInsensitiveSearch;
    return result;
}

/// Names of `(?<name>...)` groups that are not escaped. ICU names are ASCII letters and digits.
+ (NSArray<NSString *> *)groupNamesInPattern:(NSString *)pattern
{
    static NSRegularExpression *nameRegex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        nameRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)(?:\\\\\\\\)*\\(\\?<([A-Za-z][A-Za-z0-9]*)>" options:0 error:NULL];
    });
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSTextCheckingResult *match in [nameRegex matchesInString:pattern options:0 range:NSMakeRange(0, pattern.length)])
        [names addObject:[pattern substringWithRange:[match rangeAtIndex:1]]];
    return names;
}

- (nullable instancetype)initWithFindString:(NSString *)findString options:(TSRegexFindOptions)options error:(NSError **)error
{
    if (!(self = [super init]))
        return nil;
    NSString *normalized = [TSRegexFindPattern normalizedString:findString options:options];
    if (normalized.length == 0) {
        if (error)
            *error = [TSRegexFindPattern errorWithCode:TSRegexFindErrorEmptyFindString description:NSLocalizedStringFromTable(@"The find string is empty.", @"AdvancedFindEngine", @"A plain-text or regular expression find string has nothing to find.") underlyingError:nil];
        return nil;
    }
    _findString = [findString copy];
    _options = options;
    if (options & TSRegexFindRegularExpression) {
        NSError *regexError = nil;
        _regex = [NSRegularExpression regularExpressionWithPattern:normalized options:[TSRegexFindPattern regularExpressionOptions:options] error:&regexError];
        if (!_regex) {
            if (error)
                *error = [TSRegexFindPattern errorWithCode:TSRegexFindErrorInvalidPattern description:regexError.localizedDescription underlyingError:regexError];
            return nil;
        }
        // A pattern read literally has no groups, whatever it looks like.
        _captureGroupNames = (options & TSRegexFindIgnoreMetacharacters) ? @[] : [TSRegexFindPattern groupNamesInPattern:normalized];
        _words = @[];
        _quickWords = @[];
    } else {
        _captureGroupNames = @[];
        if (options & TSRegexFindDelimitByWhitespace) {
            NSMutableArray<NSString *> *words = [NSMutableArray array];
            for (NSString *word in [normalized componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
                if (word.length > 0 && ![words containsObject:word])
                    [words addObject:word];
            if (words.count == 0) {
                if (error)
                    *error = [TSRegexFindPattern errorWithCode:TSRegexFindErrorEmptyFindString description:NSLocalizedStringFromTable(@"The find string is empty.", @"AdvancedFindEngine", @"A plain-text or regular expression find string has nothing to find.") underlyingError:nil];
                return nil;
            }
            _words = words;
        } else {
            _words = @[normalized];
        }
        NSMutableArray *quickWords = [NSMutableArray array];
        if ([TSRegexFindPattern compareOptions:options] == 0)
            for (NSString *word in _words)
                [quickWords addObject:[TSQuickWord quickWordWithString:word] ?: NSNull.null];
        _quickWords = quickWords;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (BOOL)isRegularExpression
{
    return self.regex != nil;
}

- (NSUInteger)numberOfCaptureGroups
{
    return self.regex.numberOfCaptureGroups;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[TSRegexFindPattern class]])
        return NO;
    TSRegexFindPattern *other = object;
    // Literal comparison: canonically equivalent find strings can match differently.
    return other.options == self.options && [other.findString compare:self.findString options:NSLiteralSearch] == NSOrderedSame;
}

- (NSUInteger)hash
{
    return self.findString.hash ^ self.options;
}

#pragma mark Matching

- (void)enumerateMatchesInString:(NSString *)string
                           range:(NSRange)range
                    cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                      usingBlock:(void (NS_NOESCAPE ^)(NSRange, NSTextCheckingResult *_Nullable, BOOL *))block
{
    NSParameterAssert(NSMaxRange(range) <= string.length);
    if (self.regex)
        [self enumerateRegularExpressionMatchesInString:string range:range cancellation:isCancelled usingBlock:block];
    else
        [self enumerateTextualMatchesInString:string range:range cancellation:isCancelled usingBlock:block];
}

- (void)enumerateRegularExpressionMatchesInString:(NSString *)string
                                            range:(NSRange)range
                                     cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                                       usingBlock:(void (NS_NOESCAPE ^)(NSRange, NSTextCheckingResult *_Nullable, BOOL *))block
{
    BOOL ignoresEmpty = (self.options & TSRegexFindIgnoreEmptyMatches) != 0;
    NSMatchingOptions matching = NSMatchingWithTransparentBounds | NSMatchingWithoutAnchoringBounds | (isCancelled ? NSMatchingReportProgress : 0);
    __block NSUInteger progressCount = 0;
    [self.regex enumerateMatchesInString:string options:matching range:range usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        if (isCancelled && (result || ++progressCount % 256 == 0) && isCancelled()) {
            *stop = YES;
            return;
        }
        if (!result)
            return;
        // `\R` can take the LF after the end of the range (macOS 27.2).
        if (NSMaxRange(result.range) > NSMaxRange(range))
            return;
        if (ignoresEmpty && result.range.length == 0)
            return;
        block(result.range, result, stop);
    }];
}

/// A match is a whole word when it starts at a word boundary or with a non-word character, and ends at a word
/// boundary or with a non-word character; word characters and boundaries are ICU's `\w` and `\b`, as in CotEditor.
- (BOOL)isWholeWord:(NSRange)match inString:(NSString *)string
{
    static NSRegularExpression *edges;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // `\b` comes before the lookbehind. ICU's UText path, which NSRegularExpression takes, judges `\b` at the end
        // of the text from wherever a failed lookbehind left the text (RegexMatcher::isWordBoundary, ICU 78.3).
        edges = [NSRegularExpression regularExpressionWithPattern:@"\\A(?:(?=\\W)|\\b)(?>[\\s\\S]*)(?:\\b|(?<=\\W))\\z" options:0 error:NULL];
    });
    if (match.length == 0)
        return NO;
    // Transparent bounds let `\b` see the characters beside the match.
    return [edges firstMatchInString:string options:NSMatchingWithTransparentBounds range:match] != nil;
}

- (NSRange)rangeOfWord:(NSString *)word inString:(NSString *)string from:(NSUInteger)location limit:(NSUInteger)limit compare:(NSStringCompareOptions)compare
{
    if (location >= limit)
        return NSMakeRange(NSNotFound, 0);
    NSRange found = [string rangeOfString:word options:compare range:NSMakeRange(location, limit - location)];
    // Combining marks can be found as an empty range or beyond the search range (macOS 27.2).
    if (found.location == NSNotFound || found.length == 0 || NSMaxRange(found) > limit)
        return NSMakeRange(NSNotFound, 0);
    return found;
}

/// The first match of a quick word, as rangeOfWord finds it.
- (NSRange)rangeOfQuickWord:(TSQuickWord *)quick word:(NSString *)word inString:(NSString *)string
                      chars:(const unichar *)chars base:(NSUInteger)base from:(NSUInteger)location limit:(NSUInteger)limit
{
    if (location >= limit)
        return NSMakeRange(NSNotFound, 0);
    for (NSUInteger from = location; ; ) {
        NSUInteger at = [quick literalMatchIn:chars base:base from:from limit:limit];
        if (at == NSNotFound)
            return NSMakeRange(NSNotFound, 0);
        // The search reads the text a character at a time, and some characters join the next to them (U+0600 and a
        // digit): unless the character before the match is a quick one, the search itself is left to decide.
        if (at > 0 && !TSIsQuickCharacter(at > base ? chars[at - base - 1] : [string characterAtIndex:at - 1]))
            return [self rangeOfWord:word inString:string from:location limit:limit compare:0];
        NSRange found = [string rangeOfString:word options:NSAnchoredSearch range:NSMakeRange(at, limit - at)];
        if (found.location != NSNotFound) {
            if (found.length == 0 || NSMaxRange(found) > limit)
                return NSMakeRange(NSNotFound, 0);
            return found;
        }
        from = at + 1;
    }
}

- (void)enumerateTextualMatchesInString:(NSString *)string
                                  range:(NSRange)range
                           cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                             usingBlock:(void (NS_NOESCAPE ^)(NSRange, NSTextCheckingResult *_Nullable, BOOL *))block
{
    NSStringCompareOptions compare = [TSRegexFindPattern compareOptions:self.options];
    BOOL wholeWord = (self.options & TSRegexFindWholeWord) != 0;
    NSUInteger limit = NSMaxRange(range);
    NSUInteger count = self.words.count;
    // The characters of the range, for the quick words that can be used in it.
    const unichar *chars = CFStringGetCharactersPtr((__bridge CFStringRef)string);
    NSUInteger base = 0;
    NSMutableData *copy = nil;
    NSMutableArray *quick = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        TSQuickWord *word = i < self.quickWords.count ? self.quickWords[i] : nil;
        if (![word isKindOfClass:[TSQuickWord class]]) {
            [quick addObject:NSNull.null];
            continue;
        }
        if (!chars) {
            copy = [NSMutableData dataWithLength:range.length * sizeof(unichar)];
            [string getCharacters:copy.mutableBytes range:range];
            chars = copy.bytes;
            base = range.location;
        }
        [quick addObject:(word->_others || word->_astralOthers) && [word hasOthersIn:chars + (range.location - base) length:range.length] ? NSNull.null : word];
    }
    NSRange (^find)(NSUInteger, NSUInteger) = ^NSRange(NSUInteger i, NSUInteger from) {
        TSQuickWord *word = quick[i];
        if ([word isKindOfClass:[TSQuickWord class]])
            return [self rangeOfQuickWord:word word:self.words[i] inString:string chars:chars base:base from:from limit:limit];
        return [self rangeOfWord:self.words[i] inString:string from:from limit:limit compare:compare];
    };
    NSRange next[count];
    for (NSUInteger i = 0; i < count; i++)
        next[i] = find(i, range.location);
    NSUInteger location = range.location;
    NSUInteger steps = 0;
    while (YES) {
        if (isCancelled && ++steps % 64 == 0 && isCancelled())
            return;
        // The earliest candidate wins; the longer one breaks a tie.
        NSUInteger best = NSNotFound;
        for (NSUInteger i = 0; i < count; i++) {
            if (next[i].location == NSNotFound)
                continue;
            if (best == NSNotFound || next[i].location < next[best].location
                || (next[i].location == next[best].location && next[i].length > next[best].length))
                best = i;
        }
        if (best == NSNotFound)
            return;
        NSRange found = next[best];
        if (wholeWord && ![self isWholeWord:found inString:string]) {
            // The next candidate of the same word can overlap the rejected one.
            next[best] = find(best, found.location + 1);
            continue;
        }
        BOOL stop = NO;
        block(found, nil, &stop);
        if (stop)
            return;
        location = NSMaxRange(found);
        for (NSUInteger i = 0; i < count; i++)
            if (next[i].location != NSNotFound && next[i].location < location)
                next[i] = find(i, location);
    }
}

@end
