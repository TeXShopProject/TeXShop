// SPDX-License-Identifier: GPL-2.0-or-later
//
//  TSTeXOptions.h
//
//  TeX options in typesetting commands, written as the engines' own usage messages write them:
//  one hyphen for pdfTeX, XeTeX, e-pTeX, e-upTeX and the other web2c engines (-file-line-error,
//  -synctex=1, -shell-escape), two for LuaTeX (--file-line-error). Every engine accepts both.
//
//  A command is read the way TeXShop runs it (TSDocument -separate:into:): words are split at
//  spaces, and a word that starts with a double quote runs to the word that ends with one; the
//  quotes are dropped and the words inside joined with one space. latexmk passes the command of an
//  -e "$pdflatex=q/…/" or -pdflatex="…" option on to a shell; its words are read too.
//

#import <Foundation/Foundation.h>

// One argument of a command: its value, the range it takes in the command (quotes included), and
// where each character of the value stands in the command (the words inside quotes are joined with
// one space, which stands for the first of the spaces between them).
#define TSTeXArgumentValue @"value"
#define TSTeXArgumentRange @"range"
#define TSTeXArgumentOffsets @"offsets"

// The value of a word made by the functions below; every word they make has one.
static inline NSString *TSTeXWordValue(NSDictionary *word)
{
    return (NSString * _Nonnull)word[TSTeXArgumentValue];
}

static inline NSArray<NSNumber *> *TSTeXOffsets(NSUInteger from, NSUInteger count)
{
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++)
        [offsets addObject:@(from + i)];
    return offsets;
}

// The words of the command as TeXShop passes them to the program: the program first, then its
// arguments. A quoted argument that is never closed is dropped, as TeXShop drops it.
static inline NSArray<NSDictionary *> *TSTeXCommandArguments(NSString *command)
{
    NSMutableArray<NSDictionary *> *arguments = [NSMutableArray array];
    if (![command isKindOfClass:NSString.class])
        return arguments;
    NSUInteger length = command.length, location = 0;
    BOOL programFound = NO, inMiddle = NO;
    NSMutableString *middle = nil;
    NSMutableArray<NSNumber *> *middleOffsets = nil;
    NSUInteger middleStart = 0;
    while (location <= length) {
        NSRange space = [command rangeOfString:@" " options:NSLiteralSearch range:NSMakeRange(location, length - location)];
        NSUInteger end = space.location == NSNotFound ? length : space.location;
        NSRange wordRange = NSMakeRange(location, end - location);
        NSString *word = [command substringWithRange:wordRange];
        if (word.length > 0) {
            if (!programFound) {
                programFound = YES;
                [arguments addObject:@{TSTeXArgumentValue: word, TSTeXArgumentRange: [NSValue valueWithRange:wordRange], TSTeXArgumentOffsets: TSTeXOffsets(location, word.length)}];
            } else if (inMiddle) {
                [middle appendFormat:@" %@", word];
                [middleOffsets addObject:@(location - 1)];
                [middleOffsets addObjectsFromArray:TSTeXOffsets(location, word.length)];
                if ([word characterAtIndex:word.length - 1] == '"') {
                    NSRange range = NSMakeRange(middleStart, NSMaxRange(wordRange) - middleStart);
                    NSRange inner = NSMakeRange(1, middle.length - 2);
                    [arguments addObject:@{TSTeXArgumentValue: [middle substringWithRange:inner], TSTeXArgumentRange: [NSValue valueWithRange:range],
                                           TSTeXArgumentOffsets: [middleOffsets subarrayWithRange:inner]}];
                    inMiddle = NO;
                }
            } else if ([word characterAtIndex:0] == '"') {
                // A lone '"' opens a quoted argument; it cannot also close it.
                if (word.length >= 2 && [word characterAtIndex:word.length - 1] == '"')
                    [arguments addObject:@{TSTeXArgumentValue: [word substringWithRange:NSMakeRange(1, word.length - 2)], TSTeXArgumentRange: [NSValue valueWithRange:wordRange],
                                           TSTeXArgumentOffsets: TSTeXOffsets(location + 1, word.length - 2)}];
                else {
                    middle = [word mutableCopy];
                    middleOffsets = [TSTeXOffsets(location, word.length) mutableCopy];
                    middleStart = location;
                    inMiddle = YES;
                }
            } else
                [arguments addObject:@{TSTeXArgumentValue: word, TSTeXArgumentRange: [NSValue valueWithRange:wordRange], TSTeXArgumentOffsets: TSTeXOffsets(location, word.length)}];
        }
        if (space.location == NSNotFound)
            break;
        location = end + 1;
    }
    return arguments;
}

// The words of text[range] as a shell reads them (latexmk hands its commands to a shell, and so does env -S): blanks
// split words; quotes, which may start or end inside a word, group blanks into it and are dropped; a backslash outside
// single quotes takes the next character as it is. Each word has a value, the range it takes in text (quotes included)
// and, for each character of the value, its place in text.
static inline NSArray<NSDictionary *> *TSTeXShellWords(NSString *text, NSRange range)
{
    NSMutableArray<NSDictionary *> *words = [NSMutableArray array];
    __block NSMutableString *value = nil;
    __block NSMutableArray<NSNumber *> *offsets = nil;
    __block NSUInteger start = 0, last = 0;
    unichar quote = 0;
    NSCharacterSet *blank = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    void (^finish)(void) = ^{
        if (value != nil)
            [words addObject:@{TSTeXArgumentValue: [value copy], TSTeXArgumentRange: [NSValue valueWithRange:NSMakeRange(start, last + 1 - start)],
                               TSTeXArgumentOffsets: [offsets copy]}];
    };
    for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
        unichar c = [text characterAtIndex:i];
        if (quote == 0 && [blank characterIsMember:c]) {
            finish();
            value = nil;
            continue;
        }
        if (value == nil) { value = [NSMutableString string]; offsets = [NSMutableArray array]; start = i; }
        last = i;
        if (quote == 0 && (c == '"' || c == '\'')) { quote = c; continue; }
        if (quote != 0 && c == quote) { quote = 0; continue; }
        if (c == '\\' && quote != '\'' && i + 1 < NSMaxRange(range)) {
            unichar next = [text characterAtIndex:i + 1];
            if (quote == 0 || next == '"' || next == '\\' || next == '$' || next == '`') { i++; last = i; c = next; }
        }
        [value appendFormat:@"%C", c];
        [offsets addObject:@(i)];
    }
    finish();
    return words;
}

// The program the command runs: its first word, past env with its options (and the values of
// -u, -P, -L, -U, -C, -S) and NAME=value settings; the words of env -S are read as the command.
static inline NSString *TSTeXCommandProgram(NSString *command)
{
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSDictionary *argument in TSTeXCommandArguments(command))
        [words addObject:TSTeXWordValue(argument)];
    NSSet *withValue = [NSSet setWithObjects:@"-u", @"-P", @"-L", @"-U", @"-C", @"--unset", @"--chdir", nil];
    BOOL afterEnv = NO;
    while (words.count) {
        NSString *word = words.firstObject;
        [words removeObjectAtIndex:0];
        NSString *name = word.lastPathComponent;
        if (!afterEnv && [name isEqualToString:@"env"]) { afterEnv = YES; continue; }
        if (afterEnv) {
            if ([word isEqualToString:@"-S"] || [word isEqualToString:@"--split-string"] || [word hasPrefix:@"--split-string="]) {
                NSString *string = [word hasPrefix:@"--split-string="] ? [word substringFromIndex:15] : (words.count ? words.firstObject : @"");
                if (![word hasPrefix:@"--split-string="] && words.count) [words removeObjectAtIndex:0];
                NSMutableArray<NSString *> *inner = [NSMutableArray array];
                // env -S of macOS also takes \\_ for a blank between words.
                string = [string stringByReplacingOccurrencesOfString:@"\\_" withString:@" "];
                for (NSDictionary *w in TSTeXShellWords(string, NSMakeRange(0, string.length)))
                    [inner addObject:TSTeXWordValue(w)];
                [words replaceObjectsInRange:NSMakeRange(0, 0) withObjectsFromArray:inner];
                continue;
            }
            if ([withValue containsObject:word]) { if (words.count) [words removeObjectAtIndex:0]; continue; }
            if ([word hasPrefix:@"-"] || [word containsString:@"="]) continue;
        }
        return name;
    }
    return @"";
}

// Whether the command runs LuaTeX (luatex, lualatex, luahbtex, dviluatex, dvilualatex, …), whose usage writes two hyphens.
static inline BOOL TSTeXCommandRunsLuaTeX(NSString *command)
{
    NSString *program = TSTeXCommandProgram(command).lowercaseString;
    return [program hasPrefix:@"lua"] || [program hasPrefix:@"dvilua"];
}

// The hyphens of a TeX option for the engine of the command: "--" for LuaTeX, "-" otherwise.
static inline NSString *TSTeXOptionDashes(NSString *command)
{
    return TSTeXCommandRunsLuaTeX(command) ? @"--" : @"-";
}

// The arguments to look at for TeX options: those of the command, and for latexmk also the words of
// the TeX commands it is told to run (-e "$pdflatex=q/…/", -pdflatex="…" and the like), read as a shell reads them. Each has a value, a range in the command and the offsets of its characters.
static inline NSArray<NSDictionary *> *TSTeXOptionArguments(NSString *command)
{
    NSArray<NSDictionary *> *arguments = TSTeXCommandArguments(command);
    if (![TSTeXCommandProgram(command).lowercaseString hasPrefix:@"latexmk"])
        return arguments;
    static NSRegularExpression *perl, *option;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Only the settings that name a TeX command ($latex, $pdflatex, $lualatex, $xelatex, $dvilualatex, $hilatex), not $out_dir and other settings.
        perl = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\$(?:pdf|lua|xe|dvilua|hi)?latex\\s*=\\s*q/(.*)/\\s*;?\\s*$" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
        option = [NSRegularExpression regularExpressionWithPattern:@"^-{1,2}(?:pdf|lua|xe|dvilua|hi)?latex=(.*)$" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
    });
    NSMutableArray<NSDictionary *> *all = [arguments mutableCopy];
    for (NSUInteger i = 1; i < arguments.count; i++) {
        NSString *value = arguments[i][TSTeXArgumentValue];
        NSTextCheckingResult *match = nil;
        if ([arguments[i - 1][TSTeXArgumentValue] isEqualToString:@"-e"])
            match = [perl firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
        if (!match)
            match = [option firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
        if (!match)
            continue;
        NSArray<NSNumber *> *offsets = arguments[i][TSTeXArgumentOffsets];
        for (NSDictionary *w in TSTeXShellWords(value, [match rangeAtIndex:1])) {
            NSRange within = [w[TSTeXArgumentRange] rangeValue];
            NSUInteger from = offsets[within.location].unsignedIntegerValue, to = offsets[NSMaxRange(within) - 1].unsignedIntegerValue + 1;
            NSMutableArray<NSNumber *> *places = [NSMutableArray array];
            for (NSNumber *n in w[TSTeXArgumentOffsets])
                [places addObject:offsets[n.unsignedIntegerValue]];
            [all addObject:@{TSTeXArgumentValue: TSTeXWordValue(w), TSTeXArgumentRange: [NSValue valueWithRange:NSMakeRange(from, to - from)],
                             TSTeXArgumentOffsets: places}];
        }
    }
    return all;
}

static inline BOOL TSTeXArgumentIsShellEscape(NSDictionary *argument)
{
    NSString *value = argument[TSTeXArgumentValue];
    return [value isEqualToString:@"-shell-escape"] || [value isEqualToString:@"--shell-escape"];
}

// Whether -shell-escape or --shell-escape is one of the arguments (not -no-shell-escape, not part of a path or name).
static inline BOOL TSTeXCommandHasShellEscape(NSString *command)
{
    for (NSDictionary *argument in TSTeXOptionArguments(command))
        if (TSTeXArgumentIsShellEscape(argument))
            return YES;
    return NO;
}

// The command without its -shell-escape or --shell-escape arguments (with their quotes).
static inline NSString *TSTeXCommandWithoutShellEscape(NSString *command)
{
    if (command.length == 0)
        return command;
    NSMutableString *result = [command mutableCopy];
    NSArray *arguments = [TSTeXOptionArguments(command) sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [@([b[TSTeXArgumentRange] rangeValue].location) compare:@([a[TSTeXArgumentRange] rangeValue].location)];
    }];
    for (NSDictionary *argument in arguments) {
        NSRange range = [argument[TSTeXArgumentRange] rangeValue];
        if (TSTeXArgumentIsShellEscape(argument))
            [result deleteCharactersInRange:range];
    }
    return result;
}

// The command with the TeX options that both spellings name written with one hyphen, to compare
// commands that differ only in that (the profiles of earlier versions wrote --file-line-error). Only
// arguments that are exactly --file-line-error, --shell-escape (and their --no- forms), --synctex=N
// or --interaction=mode change; other names, values and paths stay as they are.
static inline NSString *TSTeXCommandWithOneHyphenOptions(NSString *command)
{
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
            @"^--(?:(?:no-)?(?:file-line-error|shell-escape)|synctex=-?\\d+|interaction=[a-z]+)$" options:0 error:NULL];
    });
    if (command.length == 0)
        return command;
    NSMutableIndexSet *hyphens = [NSMutableIndexSet indexSet];
    for (NSDictionary *argument in TSTeXOptionArguments(command)) {
        NSString *value = argument[TSTeXArgumentValue];
        if ([expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)])
            [hyphens addIndex:[argument[TSTeXArgumentOffsets][0] unsignedIntegerValue]];
    }
    NSMutableString *result = [command mutableCopy];
    [hyphens enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger index, BOOL *stop) {
        [result deleteCharactersInRange:NSMakeRange(index, 1)];
    }];
    return result;
}
