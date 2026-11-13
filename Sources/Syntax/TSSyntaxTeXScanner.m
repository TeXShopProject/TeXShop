// SPDX-License-Identifier: GPL-2.0-or-later
// The rules are those that -[TSDocument colorizeText:range:] has always used, kept as they were, including their
// quirks: what a source showed before, it shows now.
#import "TSSyntaxTeXScanner.h"
#import "TSSyntaxXMLScanning.h"

// The letters of a command.
static BOOL TSIsTeXCommandLetter(NSInteger c, BOOL expl3, BOOL atLetter)
{
    if ((c >= 'A') && (c <= 'Z'))
        return YES;
    else if ((c >= 'a') && (c <= 'z'))
        return YES;
    else if (c == '@' && atLetter)
        return YES;
    else if (((c == '@') || (c == '_') || (c == ':')) && expl3)
        return YES;
    else
        return NO;
}

// The letters of what follows an expl3 key: a period is one too.
static BOOL TSIsExtendedTeXCommandLetter(NSInteger c, BOOL expl3, BOOL atLetter)
{
    return TSIsTeXCommandLetter(c, expl3, atLetter) || (c == '.' && expl3);
}

static BOOL TSIsOrdinaryLetter(NSInteger c)
{
    return ((c >= 'A') && (c <= 'Z')) || ((c >= 'a') && (c <= 'z'));
}

typedef struct {
    CFStringInlineBuffer buffer;
    NSUInteger lineEnd;
    __unsafe_unretained TSSyntaxTokenBlock block;
} TSTeXScan;

static inline NSInteger TSCharacter(TSTeXScan *scan, NSUInteger index)
{
    return CFStringGetCharacterFromInlineBuffer(&scan->buffer, (CFIndex)index);
}

static inline void TSToken(TSTeXScan *scan, NSUInteger location, NSUInteger length, TSSyntaxRole role)
{
    scan->block(NSMakeRange(location, length), role, TSSyntaxTokenFlagsNone);
}

static inline void TSNoSpelling(TSTeXScan *scan, NSRange range)
{
    scan->block(range, TSSyntaxRoleNone, TSSyntaxTokenFlagsNoSpellCheck);
}

// Skips an optional argument [...], coloring its brackets, and leaves *location after it.
static void TSSkipOptionalArgument(TSTeXScan *scan, NSUInteger *location)
{
    NSInteger count = 1;
    TSToken(scan, *location, 1, TSSyntaxRoleMarker);
    (*location)++;
    BOOL notDone = YES;
    while ((*location < scan->lineEnd) && notDone) {
        NSInteger c = TSCharacter(scan, *location);
        if (c == '[')
            count++;
        if (c == ']')
            count--;
        if (count == 0) {
            notDone = NO;
            TSToken(scan, *location, 1, TSSyntaxRoleMarker);
        }
        (*location)++;
    }
}

// The argument of \footnote or \index after its optional arguments: braces in the marker color, the text between
// them in the given role. Nothing is colored when the closing brace is not found before the end of the range.
// *range becomes the range of the argument: its start once the opening brace is found, its length once the closing
// one is (the spelling of the parameters of \footnote then starts there).
static void TSArgument(TSTeXScan *scan, NSUInteger *location, TSSyntaxRole role, NSRange *range)
{
    while ((*location < scan->lineEnd) && (TSCharacter(scan, *location) == '['))
        TSSkipOptionalArgument(scan, location);
    if (!((*location < scan->lineEnd) && (TSCharacter(scan, *location) == '{')))
        return;
    NSInteger count = 1;
    TSToken(scan, *location, 1, TSSyntaxRoleMarker);
    (*location)++;
    range->location = *location;
    BOOL notDone = YES;
    while ((*location < scan->lineEnd) && notDone) {
        NSInteger c = TSCharacter(scan, *location);
        if (c == '{')
            count++;
        if (c == '}')
            count--;
        if (count == 0) {
            notDone = NO;
            range->length = *location - range->location;
            TSToken(scan, range->location, range->length, role);
            TSToken(scan, *location, 1, TSSyntaxRoleMarker);
        }
        (*location)++;
    }
}

// The first arguments of a command whose parameters are not spell checked: the brackets in them are colored, and
// the command (or what range holds) and the arguments are left out of spell checking. Leaves *location one
// character further.
static void TSSkipParametersForSpelling(TSTeXScan *scan, NSRange range, NSUInteger *location)
{
    int square = 0;
    int curly = 0;
    BOOL notYetDone = YES;
    NSRange spellRange = range;
    NSUInteger spellLocation = *location;
    NSUInteger spellLength = spellRange.length;
    while ((spellLocation < scan->lineEnd) && notYetDone) {
        NSInteger c = TSCharacter(scan, spellLocation);
        if ((c == '{') || (c == '}') || (c == '[') || (c == ']') || (c == '&') || (c == '$'))
            TSToken(scan, spellLocation, 1, TSSyntaxRoleBracketCurly);
        spellLocation++;
        spellLength++;
        if (c == '[')
            square++;
        if (c == ']')
            square--;
        if (c == '{')
            curly++;
        if (c == '}')
            curly--;
        if ((square == 0) && (curly == 0)) {
            notYetDone = NO;
            spellRange.length = spellLength;
        }
    }
    // The second pass starts again at the same character; the counts of braces go on from the first.
    square = 0;
    notYetDone = YES;
    spellLocation = (*location)++;
    while ((spellLocation < scan->lineEnd) && notYetDone) {
        NSInteger c = TSCharacter(scan, spellLocation);
        if ((c == '{') || (c == '}') || (c == '[') || (c == ']') || (c == '&') || (c == '$'))
            TSToken(scan, spellLocation, 1, TSSyntaxRoleBracketCurly);
        spellLocation++;
        spellLength++;
        if (c == '[')
            square++;
        if (c == ']')
            square--;
        if (c == '{')
            curly++;
        if (c == '}')
            curly--;
        if ((square == 0) && (curly == 0)) {
            notYetDone = NO;
            spellRange.length = spellLength;
        }
    }
    TSNoSpelling(scan, spellRange);
}

@implementation TSSyntaxTeXScanner

- (instancetype)initWithOptions:(TSSyntaxTeXOptions *)options
{
    if ((self = [super init]))
        _options = [options copy];
    return self;
}

- (NSRange)lineAlignedRangeForEditedRange:(NSRange)range inString:(NSString *)string
{
    NSUInteger start, end;
    [string getLineStart:&start end:&end contentsEnd:NULL forRange:range];
    return NSMakeRange(start, end - start);
}

- (void)enumerateTokensInString:(NSString *)string range:(NSRange)range usingBlock:(NS_NOESCAPE TSSyntaxTokenBlock)block
{
    TSSyntaxTeXOptions *options = self.options;
    const BOOL expl3 = options.colorsExpl3, atLetter = options.makesAtLetter, xml = options.isXML;
    const BOOL fullwidth = options.marksFullwidthSymbols;
    const NSInteger texCharacter = options.texCharacter;
    TSTeXScan scan;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &scan.buffer, CFRangeMake(0, (CFIndex)string.length));
    scan.lineEnd = NSMaxRange(range);
    scan.block = block;
    const NSUInteger lineStart = range.location, lineEnd = scan.lineEnd;
    // The letters after the command's backslash. The fourth is read for five-letter commands too, although it is
    // only set for longer ones: it keeps the value of the last longer command of this range, as it always has.
    NSInteger first = 0, second = 0, third = 0, fourth = 0;

    NSUInteger location = lineStart;
    while (location < lineEnd) {
        NSInteger c = TSCharacter(&scan, location);
        if (xml && (c == '<'))
            TSSyntaxScanXMLTag(string, &location, lineEnd, block);
        else if (xml && (c == '&'))
            TSSyntaxScanXMLEntity(string, &location, lineEnd, block);
        else if (fullwidth && TSIsHighlightedFullwidthCharacter((unichar)c)) {
            TSToken(&scan, location, 1, TSSyntaxRoleFullwidthSymbol);
            location++;
        }
        else if ((c == '&') || (c == '$')) {
            TSToken(&scan, location, 1, TSSyntaxRoleMarker);
            location++;
        }
        else if ((c == '[') || (c == ']')) {
            TSToken(&scan, location, 1, TSSyntaxRoleBracketSquare);
            location++;
        }
        else if ((c == '{') || (c == '}')) {
            TSToken(&scan, location, 1, TSSyntaxRoleBracketCurly);
            location++;
        }
        else if ((c == '(') || (c == ')')) {
            TSToken(&scan, location, 1, TSSyntaxRoleBracketParen);
            location++;
        }
        else if (c == '%') {
            // A comment runs to the end of its line.
            NSUInteger end;
            [string getLineStart:NULL end:NULL contentsEnd:&end forRange:NSMakeRange(location, 1)];
            NSRange comment = NSMakeRange(location, end - location);
            block(comment, TSSyntaxRoleComment, TSSyntaxTokenFlagsNone);
            location = end;
            if (options.excludesCommentsFromSpelling)
                TSNoSpelling(&scan, comment);
        }
        else if (c == texCharacter) {
            // A command: the TeX character and the letters after it, or the one character after it.
            NSRange command = NSMakeRange(location, 1);
            location++;
            if ((location < lineEnd) && !TSIsTeXCommandLetter(TSCharacter(&scan, location), expl3, atLetter)) {
                location++;
                command.length = location - command.location;
            } else {
                while ((location < lineEnd) && TSIsTeXCommandLetter(TSCharacter(&scan, location), expl3, atLetter)) {
                    location++;
                    command.length = location - command.location;
                }
            }
            NSString *commandString = [string substringWithRange:command];
            if (expl3) {
                if (command.length > 3) {
                    first = [commandString characterAtIndex:1];
                    second = [commandString characterAtIndex:2];
                    third = [commandString characterAtIndex:3];
                }
                if (command.length > 5)
                    fourth = [commandString characterAtIndex:4];
                BOOL hasUnderlineAndColon = [commandString containsString:@"_"] && [commandString containsString:@":"];
                TSSyntaxRole role;
                BOOL unspelled = YES;
                if ((command.length > 3) && ((first == 'l') || (first == 'g') || (first == 'c')) && (second == '_') && (third != '_'))
                    role = TSSyntaxRoleExplVariable;
                else if ((command.length > 3) && ((first == 'l') || (first == 'g') || (first == 'c')) && (second == '_') && (third == '_'))
                    role = TSSyntaxRoleExplIntenseVariable;
                else if ((command.length > 3) && (first == '_') && (second == '_') && hasUnderlineAndColon)
                    role = TSSyntaxRoleExplIntenseFunction;
                else if ((command.length > 4) && (first == 'm') && (second == 's') && (third == 'g') && (fourth == '_'))
                    role = TSSyntaxRoleExplMessage;
                else {
                    // Without an underscore but with a colon, a name is an ordinary command.
                    role = hasUnderlineAndColon ? TSSyntaxRoleExplFunction : TSSyntaxRoleCommand;
                    unspelled = NO;
                }
                TSToken(&scan, command.location, command.length, role);
                if (unspelled)
                    TSNoSpelling(&scan, command);
            } else
                TSToken(&scan, command.location, command.length, TSSyntaxRoleCommand);
            if (options.excludesCommandsFromSpelling)
                TSNoSpelling(&scan, command);

            NSRange colorRange = command;
            if (options.colorsFootnote &&
                ([commandString isEqualToString:@"\\footnote"] || [commandString isEqualToString:@"\\autocite"] ||
                 [commandString hasPrefix:@"\\cite"] || [commandString hasPrefix:@"\\Cite"] ||
                 [commandString isEqualToString:@"\\footcite"]))
                TSArgument(&scan, &location, TSSyntaxRoleFootnote, &colorRange);

            // The spelling of parameters is left alone after an index entry, which has been colored.
            if (options.colorsIndex && ([commandString isEqualToString:@"\\index"] || [commandString isEqualToString:@"\\esindex"]))
                TSArgument(&scan, &location, TSSyntaxRoleIndex, &colorRange);
            else if (options.excludesParametersFromSpelling &&
                     (options.excludesParametersOfUnlistedCommands
                      ? ![options.commandsWithCheckedParameters containsObject:commandString]
                      : [options.commandsWithUncheckedParameters containsObject:commandString]))
                TSSkipParametersForSpelling(&scan, colorRange, &location);
        }
        else if (expl3 && TSIsOrdinaryLetter(c)) {
            // An expl3 key: a word, spaces, then a property such as .tl_set:N on the same line.
            NSUInteger end = location;
            while ((end < lineEnd) && TSIsOrdinaryLetter(TSCharacter(&scan, end)))
                end++;
            NSRange key = NSMakeRange(location, end - location);
            NSUInteger wordEnd = end;
            while ((end < lineEnd) && (TSCharacter(&scan, end) == ' '))
                end++;
            BOOL atEndOfLine = (end == lineEnd);
            NSRange property = NSMakeRange(end, 1);
            end++;
            while ((end < lineEnd) && TSIsExtendedTeXCommandLetter(TSCharacter(&scan, end), expl3, atLetter)) {
                end++;
                property.length = end - property.location;
            }
            location = wordEnd;
            if (!atEndOfLine) {
                NSString *argument = [string substringWithRange:property];
                if ([argument containsString:@"."] && ([argument containsString:@":"] || [argument containsString:@"_"])) {
                    TSToken(&scan, key.location, key.length, TSSyntaxRoleExplKey);
                    TSNoSpelling(&scan, key);
                    TSToken(&scan, property.location, property.length, TSSyntaxRoleExplKeyArgument);
                    TSNoSpelling(&scan, property);
                    location = end;
                }
            }
        }
        else
            location++;
    }

    if (xml)
        TSSyntaxScanXMLComments(string, NSMakeRange(lineStart, lineEnd - lineStart), block);
}

@end
