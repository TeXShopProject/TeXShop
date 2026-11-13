// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxAppleScriptScanner.h"

// The reserved words of AppleScript (AppleScript Language Guide), compared in lowercase. Words of several words, such
// as "apart from" or "on error", are colored word by word.
static NSSet<NSString *> *TSAppleScriptReservedWords(void)
{
    static NSSet<NSString *> *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = [NSSet setWithArray:@[
            @"about", @"above", @"after", @"against", @"and", @"apart", @"around", @"as", @"aside", @"at", @"back",
            @"before", @"beginning", @"behind", @"below", @"beneath", @"beside", @"between", @"but", @"by", @"considering",
            @"contain", @"contains", @"continue", @"copy", @"div", @"does", @"eighth", @"else", @"end", @"equal", @"equals",
            @"error", @"every", @"exit", @"false", @"fifth", @"first", @"for", @"fourth", @"from", @"front", @"get", @"given",
            @"global", @"if", @"ignoring", @"in", @"instead", @"into", @"is", @"it", @"its", @"last", @"local", @"me",
            @"middle", @"mod", @"my", @"ninth", @"not", @"of", @"on", @"onto", @"or", @"out", @"over", @"prop", @"property",
            @"put", @"ref", @"reference", @"repeat", @"return", @"returning", @"script", @"second", @"set", @"seventh",
            @"since", @"sixth", @"some", @"tell", @"tenth", @"that", @"the", @"then", @"third", @"through", @"thru",
            @"timeout", @"times", @"to", @"transaction", @"true", @"try", @"until", @"where", @"while", @"whose", @"with",
            @"without"]];
    });
    return words;
}

static BOOL TSIsWordStart(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static BOOL TSIsWordCharacter(unichar c) { return TSIsWordStart(c) || (c >= '0' && c <= '9'); }
static BOOL TSIsDigit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL TSIsLineBreak(unichar c) { return c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029; }

@implementation TSSyntaxAppleScriptScanner

- (instancetype)initWithPlaceholders:(NSArray<NSString *> *)placeholders
{
    if ((self = [super init]))
        _placeholders = [placeholders copy];
    return self;
}

- (NSRange)lineAlignedRangeForEditedRange:(NSRange)range inString:(NSString *)string
{
    return NSMakeRange(0, string.length);
}

// The length of the placeholder that starts at location, or 0.
- (NSUInteger)placeholderLengthAtLocation:(NSUInteger)location inString:(NSString *)string
{
    for (NSString *placeholder in self.placeholders)
        if (location + placeholder.length <= string.length &&
            [string compare:placeholder options:NSLiteralSearch range:NSMakeRange(location, placeholder.length)] == NSOrderedSame)
            return placeholder.length;
    return 0;
}

- (void)enumerateTokensInString:(NSString *)string range:(NSRange)range usingBlock:(NS_NOESCAPE TSSyntaxTokenBlock)block
{
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)string.length));
#define CHAR(i) CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)(i))
    const NSUInteger end = NSMaxRange(range);
    NSSet<NSString *> *reserved = TSAppleScriptReservedWords();
    NSUInteger location = range.location;
    while (location < end) {
        unichar c = CHAR(location);
        unichar next = location + 1 < end ? CHAR(location + 1) : 0;
        NSUInteger start = location;
        TSSyntaxRole role = TSSyntaxRoleNone;
        NSUInteger placeholder = c == '#' ? [self placeholderLengthAtLocation:location inString:string] : 0;
        if (placeholder > 0) {
            // A placeholder, not a comment: it is colored over everything by whoever asked for it.
            location += placeholder;
        } else if ((c == '-' && next == '-') || c == '#') {
            // A comment to the end of the line, the line break not included.
            while (location < end && !TSIsLineBreak(CHAR(location)))
                location++;
            role = TSSyntaxRoleComment;
        } else if (c == '(' && next == '*') {
            // A block comment, which may hold others; one that is not closed runs to the end of the text.
            NSInteger depth = 0;
            while (location < end) {
                unichar a = CHAR(location), b = location + 1 < end ? CHAR(location + 1) : 0;
                if (a == '(' && b == '*') {
                    depth++;
                    location += 2;
                } else if (a == '*' && b == ')') {
                    depth--;
                    location += 2;
                    if (depth == 0)
                        break;
                } else
                    location++;
            }
            role = TSSyntaxRoleComment;
        } else if (c == '"') {
            // A string, over several lines if need be, with \" and \\ inside.
            location++;
            while (location < end) {
                unichar a = CHAR(location);
                if (a == '\\' && location + 1 < end)
                    location += 2;
                else {
                    location++;
                    if (a == '"')
                        break;
                }
            }
            role = TSSyntaxRoleString;
        } else if (c == 0x00AB) {
            // «event abcdefgh», on one line.
            location++;
            while (location < end && !TSIsLineBreak(CHAR(location)))
                if (CHAR(location++) == 0x00BB)
                    break;
            role = TSSyntaxRoleRawEvent;
        } else if (c == '|') {
            // An identifier between vertical bars, on one line: not colored.
            location++;
            while (location < end && !TSIsLineBreak(CHAR(location)))
                if (CHAR(location++) == '|')
                    break;
        } else if (TSIsWordStart(c)) {
            while (location < end && TSIsWordCharacter(CHAR(location)))
                location++;
            NSString *word = [[string substringWithRange:NSMakeRange(start, location - start)] lowercaseString];
            if ([reserved containsObject:word])
                role = TSSyntaxRoleKeyword;
        } else if (TSIsDigit(c) || (c == '.' && TSIsDigit(next))) {
            // 12, 3.5, .5, 1.0e-3
            while (location < end && TSIsDigit(CHAR(location)))
                location++;
            if (location + 1 < end && CHAR(location) == '.' && TSIsDigit(CHAR(location + 1)))
                for (location++; location < end && TSIsDigit(CHAR(location)); location++)
                    ;
            if (location < end && (CHAR(location) == 'e' || CHAR(location) == 'E')) {
                NSUInteger exponent = location + 1;
                if (exponent < end && (CHAR(exponent) == '+' || CHAR(exponent) == '-'))
                    exponent++;
                if (exponent < end && TSIsDigit(CHAR(exponent)))
                    for (location = exponent; location < end && TSIsDigit(CHAR(location)); location++)
                        ;
            }
            role = TSSyntaxRoleNumber;
        } else
            location++;
        if (role != TSSyntaxRoleNone)
            block(NSMakeRange(start, location - start), role, TSSyntaxTokenFlagsNone);
    }
#undef CHAR
}

@end
