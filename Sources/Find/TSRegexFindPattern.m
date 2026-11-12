// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexFindPattern.h"

static NSString *const TSYenSign = @"¥";

@interface TSRegexFindPattern ()
@property (nonatomic, readonly, nullable) NSRegularExpression *regex;
/// The words to look for in plain text; one word unless whitespace delimits them.
@property (nonatomic, readonly, copy) NSArray<NSString *> *words;
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
            *error = [TSRegexFindPattern errorWithCode:TSRegexFindErrorEmptyFindString description:@"The find string is empty." underlyingError:nil];
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
        _captureGroupNames = [TSRegexFindPattern groupNamesInPattern:normalized];
        _words = @[];
    } else {
        _captureGroupNames = @[];
        if (options & TSRegexFindDelimitByWhitespace) {
            NSMutableArray<NSString *> *words = [NSMutableArray array];
            for (NSString *word in [normalized componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
                if (word.length > 0 && ![words containsObject:word])
                    [words addObject:word];
            if (words.count == 0) {
                if (error)
                    *error = [TSRegexFindPattern errorWithCode:TSRegexFindErrorEmptyFindString description:@"The find string is empty." underlyingError:nil];
                return nil;
            }
            _words = words;
        } else {
            _words = @[normalized];
        }
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

static BOOL TSIsWordCharacter(unichar character)
{
    return character == '_' || [NSCharacterSet.alphanumericCharacterSet characterIsMember:character];
}

/// A match is a whole word unless a word character on its edge continues into the text beside it.
- (BOOL)isWholeWord:(NSRange)match inString:(NSString *)string
{
    if (match.length == 0)
        return NO;
    if (match.location > 0 && TSIsWordCharacter([string characterAtIndex:match.location])
        && TSIsWordCharacter([string characterAtIndex:match.location - 1]))
        return NO;
    NSUInteger end = NSMaxRange(match);
    if (end < string.length && TSIsWordCharacter([string characterAtIndex:end - 1])
        && TSIsWordCharacter([string characterAtIndex:end]))
        return NO;
    return YES;
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

- (void)enumerateTextualMatchesInString:(NSString *)string
                                  range:(NSRange)range
                           cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                             usingBlock:(void (NS_NOESCAPE ^)(NSRange, NSTextCheckingResult *_Nullable, BOOL *))block
{
    NSStringCompareOptions compare = [TSRegexFindPattern compareOptions:self.options];
    BOOL wholeWord = (self.options & TSRegexFindWholeWord) != 0;
    NSUInteger limit = NSMaxRange(range);
    NSUInteger count = self.words.count;
    NSRange next[count];
    for (NSUInteger i = 0; i < count; i++)
        next[i] = [self rangeOfWord:self.words[i] inString:string from:range.location limit:limit compare:compare];
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
            next[best] = [self rangeOfWord:self.words[best] inString:string from:found.location + 1 limit:limit compare:compare];
            continue;
        }
        BOOL stop = NO;
        block(found, nil, &stop);
        if (stop)
            return;
        location = NSMaxRange(found);
        for (NSUInteger i = 0; i < count; i++)
            if (next[i].location != NSNotFound && next[i].location < location)
                next[i] = [self rangeOfWord:self.words[i] inString:string from:location limit:limit compare:compare];
    }
}

@end
