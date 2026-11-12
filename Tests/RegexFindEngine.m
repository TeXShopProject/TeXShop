// The engine of the Advanced Find panel: patterns, replacement strings in the ICU and OgreKit
// syntaxes, next/previous search, replace all and multiple replacement. Foundation only; nothing is displayed.
#import <Foundation/Foundation.h>
#import "TSRegexTextFind.h"
#import "TSRegexMultipleReplace.h"

static int failures;
static void Check(BOOL ok, NSString *name)
{
    if (!ok) {
        printf("FAIL %s\n", name.UTF8String);
        failures++;
    }
}

static TSRegexFindPattern *Pattern(NSString *find, TSRegexFindOptions options)
{
    NSError *error = nil;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:find options:options error:&error];
    if (!pattern)
        printf("FAIL pattern %s: %s\n", find.UTF8String, error.localizedDescription.UTF8String), failures++;
    return pattern;
}

static NSString *Matches(NSString *find, TSRegexFindOptions options, NSString *text)
{
    TSRegexFindPattern *pattern = Pattern(find, options);
    if (!pattern)
        return @"<error>";
    TSRegexTextFind *finder = [[TSRegexTextFind alloc] initWithString:text pattern:pattern selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSValue *value in [finder matchRangesWithCancellation:nil])
        [parts addObject:[text substringWithRange:value.rangeValue]];
    return [parts componentsJoinedByString:@"|"];
}

static NSString *ReplaceAll(NSString *find, TSRegexFindOptions options, NSString *replace, NSString *text, TSRegexReplacementSyntax syntax)
{
    TSRegexFindPattern *pattern = Pattern(find, options);
    if (!pattern)
        return @"<error>";
    TSRegexTextFind *finder = [[TSRegexTextFind alloc] initWithString:text pattern:pattern selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
    TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:replace pattern:pattern syntax:syntax];
    TSRegexReplaceAllResult *result = [finder replaceAllWithTemplate:template cancellation:nil];
    NSMutableString *output = [text mutableCopy];
    for (TSRegexFindReplacement *replacement in result.replacements.reverseObjectEnumerator)
        [output replaceCharactersInRange:replacement.range withString:replacement.string];
    return output;
}

static void ExpectMatches(NSString *find, TSRegexFindOptions options, NSString *text, NSString *expected)
{
    NSString *actual = Matches(find, options, text);
    Check([actual isEqualToString:expected], [NSString stringWithFormat:@"find %@ in %@: got [%@], expected [%@]", find, text, actual, expected]);
}

static void ExpectReplaceIn(TSRegexReplacementSyntax syntax, NSString *find, TSRegexFindOptions options, NSString *replace, NSString *text, NSString *expected)
{
    NSString *actual = ReplaceAll(find, options, replace, text, syntax);
    Check([actual isEqualToString:expected], [NSString stringWithFormat:@"replace %@ by %@ in %@ (syntax %ld): got [%@], expected [%@]", find, replace, text, (long)syntax, actual, expected]);
}

static void ExpectReplace(NSString *find, TSRegexFindOptions options, NSString *replace, NSString *text, NSString *expected)
{
    ExpectReplaceIn(TSRegexReplacementSyntaxOgreKit, find, options, replace, text, expected);
}

static void ExpectICU(NSString *find, TSRegexFindOptions options, NSString *replace, NSString *text, NSString *expected)
{
    ExpectReplaceIn(TSRegexReplacementSyntaxICU, find, options, replace, text, expected);
}

/// The string with every unit outside ASCII written as \uXXXX, so that lone surrogates can be printed.
static const char *Shown(NSString *string)
{
    NSMutableString *shown = [NSMutableString string];
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c < 0x80)
            [shown appendFormat:@"%C", c];
        else
            [shown appendFormat:@"\\u%04X", c];
    }
    return shown.UTF8String;
}

/// CotEditor's "Unescape replacement text", written here with a regular expression as CotEditor does.
static NSString *UnescapedLikeCotEditor(NSString *template)
{
    NSRegularExpression *escapes = [NSRegularExpression regularExpressionWithPattern:@"\\\\([0tnr\"'\\\\])" options:0 error:NULL];
    NSMutableString *result = [NSMutableString string];
    __block NSUInteger location = 0;
    [escapes enumerateMatchesInString:template options:0 range:NSMakeRange(0, template.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        [result appendString:[template substringWithRange:NSMakeRange(location, match.range.location - location)]];
        NSString *c = [template substringWithRange:[match rangeAtIndex:1]];
        NSDictionary *map = @{@"0": [NSString stringWithFormat:@"%C", (unichar)0], @"t": @"\t", @"n": @"\n", @"r": @"\r", @"\"": @"\"", @"'": @"'", @"\\": @"\\\\"};
        [result appendString:map[c]];
        location = NSMaxRange(match.range);
    }];
    [result appendString:[template substringFromIndex:location]];
    return result;
}

/// The ICU syntax gives what NSRegularExpression gives; with unescaping, what it gives for CotEditor's unescaped template.
static void CompareWithFoundation(NSString *find, NSString *text, NSUInteger count, uint32_t seed, BOOL unescapes)
{
    // Single characters, and characters outside the BMP whole and as lone surrogates.
    static NSString *const alphabet = @"$$$\\\\0123456789ax{}&g<>+`'-uUtnr\"\n";
    NSMutableArray<NSString *> *pieces = [NSMutableArray array];
    for (NSUInteger j = 0; j < alphabet.length; j++)
        [pieces addObject:[alphabet substringWithRange:NSMakeRange(j, 1)]];
    unichar high = 0xD83D, low = 0xDE00;
    [pieces addObjectsFromArray:@[@"\U0001F600", @"\U0001F600", @"\U00020BB7", @"あ",
                                  [NSString stringWithCharacters:&high length:1], [NSString stringWithCharacters:&low length:1]]];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:find options:0 error:NULL];
    uint32_t state = seed;
    NSUInteger mismatches = 0;
    for (NSUInteger k = 0; k < count; k++) {
        NSMutableString *replace = [NSMutableString string];
        state = state * 1664525u + 1013904223u;
        NSUInteger length = (state >> 24) % 9;
        for (NSUInteger j = 0; j < length; j++) {
            state = state * 1664525u + 1013904223u;
            [replace appendString:pieces[(state >> 16) % pieces.count]];
        }
        NSString *expected = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:unescapes ? UnescapedLikeCotEditor(replace) : replace];
        NSString *actual = ReplaceAll(find, TSRegexFindRegularExpression | (unescapes ? TSRegexFindUnescapesReplacement : 0), replace, text, TSRegexReplacementSyntaxICU);
        if (![actual isEqualToString:expected] && mismatches++ < 5)
            printf("FAIL ICU template %s on %s: got [%s], Foundation gives [%s]\n", Shown(replace), find.UTF8String, Shown(actual), Shown(expected));
    }
    if (mismatches)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        const TSRegexFindOptions R = TSRegexFindRegularExpression | TSRegexFindDefaultOptions;
        const TSRegexFindOptions T = TSRegexFindDefaultOptions;

        // Replacement strings written for OgreKit keep their meaning in the OgreKit syntax.
        ExpectReplace(@"(a)(b)", R, @"\\2\\1", @"ab", @"ba");
        ExpectReplace(@"a(b)", R, @"[\\0|\\&]", @"ab", @"[ab|ab]");
        ExpectReplace(@"(?<x>a)(?<y>b)", R, @"\\g<y>\\g<x>\\g<1>", @"ab", @"baa");
        ExpectReplace(@"(a)|(b)", R, @"<\\+>", @"ab", @"<a><b>");
        ExpectReplace(@"b", R, @"[\\`|\\']", @"abc", @"a[a|c]c");
        ExpectReplace(@"x", R, @"(\\-)", @"1x23x", @"1(1)23(23)");
        ExpectReplace(@"a", R, @"\\t\\n\\r\\\\", @"a", @"\t\n\r\\");
        ExpectReplace(@"a", R, @"\\x{3042}\\x{1F600}\\x{D835}\\x{DC00}", @"a", @"あ\U0001F600\U0001D400");
        // TeX: `$` is literal, and an escaped letter stands for itself.
        ExpectReplace(@"(x)", R, @"$1$\\\\frac", @"x", @"$1$\\frac");
        ExpectReplace(@"a", R, @"\\section", @"a", @"section");
        ExpectReplace(@"a", R, @"b\\", @"a", @"b");
        ExpectReplace(@"(a)", R, @"\\9\\g<nope>\\g<", @"a", @"g<");
        // A yen sign counts as a backslash when the option is on.
        ExpectReplace(@"¥d+", R, @"<¥0>", @"a12", @"a<12>");
        ExpectReplace(@"¥d+", TSRegexFindRegularExpression, @"x", @"¥dd", @"x");
        ExpectReplace(@"¥", T, @"¥¥", @"\\a", @"\\\\a");
        // Plain text replacements are literal.
        ExpectReplace(@"a.", T, @"\\1$0", @"a.a", @"\\1$0a");

        // The ICU syntax, the default: as NSRegularExpression reads it, plus \t \n \r.
        ExpectICU(@"(a)(b)", R, @"$2$1", @"ab", @"ba");
        ExpectICU(@"(a)(b)", R, @"[$0|\\2\\1]", @"ab", @"[ab|21]");
        ExpectICU(@"(a)(b)", R, @"$12|$21|$9", @"ab", @"a2|b1|");
        ExpectICU(@"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)", R, @"$11$10$110", @"abcdefghijk", @"kjk0");
        ExpectICU(@"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)", R, @"[$13|$99|$019]", @"abcdefghijk", @"[||a9]");
        ExpectICU(@"a", R, @"\\t\\n\\r\\\\\\$", @"a", @"\t\n\r\\$");
        ExpectICU(@"(x)", R, @"$1$ \\$1\\$ $x$ $", @"x", @"x$ $1$ $x$ $");
        ExpectICU(@"a", R, @"\\section\\g<1>\\x{3042}b\\", @"a", @"sectiong<1>x{3042}b");
        ExpectICU(@"(?<n>a)", R, @"${n}$n\\g<n>", @"a", @"${n}$ng<n>");
        ExpectICU(@"¥d+", R, @"<$0¥$>", @"a12", @"a<12$>");
        ExpectICU(@"a.", T, @"\\1$0", @"a.a", @"\\1$0a");
        // NSRegularExpression copies a surrogate with the unit after it, so an escaped character outside the BMP
        // keeps the next character as it stands. `\\u` is only a `u`.
        ExpectICU(@"(a)", R, @"\\\U0001F600$1|\\\U00020BB7\U0001F600$1$1|\\\U0001F600\\$1|\\\U0001F600\\\\$1|\\あ$1", @"a",
                  @"\U0001F600$1|\U00020BB7\U0001F600$1a|\U0001F600\\a|\U0001F600\\$1|あa");
        CompareWithFoundation(@"(a)(b)?(c)", @"xacy abcz ac", 3000, 1, NO);
        CompareWithFoundation(@"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)", @"-abcdefghijkl-", 3000, 7, NO);
        CompareWithFoundation(@"(a)(b)?(c)", @"xacy abcz ac", 3000, 11, YES);
        CompareWithFoundation(@"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)", @"-abcdefghijkl-", 3000, 17, YES);
        // Without unescaping, \t is a t, as in NSRegularExpression; with it, \0 is NUL and \\ stays one backslash.
        ExpectICU(@"(a)", TSRegexFindRegularExpression, @"\\t\\n$1\\0", @"a", @"tna0");
        ExpectICU(@"(a)", TSRegexFindRegularExpression | TSRegexFindUnescapesReplacement, @"\\t\\n$1\\0|\\\\n|\\\\\\n|\\\"", @"a",
                  [NSString stringWithFormat:@"\t\na%C|\\n|\\\n|\"", (unichar)0]);

        // Options of the regular expression.
        ExpectMatches(@"^\\w", R, @"ab\ncd", @"a|c");
        ExpectMatches(@"^\\w", TSRegexFindRegularExpression, @"ab\ncd", @"a");
        ExpectMatches(@"a.b", R, @"a\nb", @"");
        ExpectMatches(@"a.b", R | TSRegexFindDotMatchesLineSeparators, @"a\nb", @"a\nb");
        ExpectMatches(@"A", R | TSRegexFindIgnoreCase, @"aA", @"a|A");
        ExpectMatches(@"a b # comment", R | TSRegexFindAllowCommentsAndWhitespace, @"ab", @"ab");
        ExpectMatches(@"x*", R, @"axb", @"|x||");
        ExpectMatches(@"x*", R | TSRegexFindIgnoreEmptyMatches, @"axb", @"x");
        ExpectMatches(@"\\R", R, @"a\r\nb\nc", @"\r\n|\n");

        // Literal patterns and Unix line separators, for regular expressions.
        const TSRegexFindOptions L = R | TSRegexFindIgnoreMetacharacters;
        ExpectMatches(@"a.b", L, @"a.b axb", @"a.b");
        ExpectMatches(@"(?<x>a)", L, @"a (?<x>a)", @"(?<x>a)");
        Check(Pattern(@"(?<x>a)", L).captureGroupNames.count == 0 && Pattern(@"(?<x>a)", L).numberOfCaptureGroups == 0, @"a literal pattern has no groups");
        ExpectICU(@"\u3002", L, @"$0\\n", @"a\u3002b", @"a\u3002\nb");
        ExpectMatches(@"^b", R, @"a\rb", @"b");
        ExpectMatches(@"^b", R | TSRegexFindUseUnixLineSeparators, @"a\rb", @"");
        ExpectMatches(@"a.b", R | TSRegexFindUseUnixLineSeparators, @"a\rb", @"a\rb");

        // Plain text search.
        ExpectMatches(@"a.", T, @"a.ab", @"a.");
        ExpectMatches(@"cat", T | TSRegexFindWholeWord, @"cat concat cat_ cat.", @"cat|cat");
        ExpectMatches(@"aa", T, @"aaaa", @"aa|aa");
        ExpectMatches(@"aa", T | TSRegexFindWholeWord, @"aaa aa", @"aa");
        // Characters outside the BMP are letters too.
        ExpectMatches(@"a", T | TSRegexFindWholeWord, @"a\U00020BB7 \U00020BB7a a\U00010400 a", @"a");
        ExpectMatches(@"\U00020BB7", T | TSRegexFindWholeWord, @"x\U00020BB7y \U00020BB7", @"\U00020BB7");
        ExpectMatches(@"a", T | TSRegexFindWholeWord, @"\U0001F600a\U0001F600", @"a");
        // Word characters are ICU's \w, as in CotEditor: not circled digits or superscripts, but full-width low lines.
        ExpectMatches(@"a", T | TSRegexFindWholeWord, @"a\u2460 a\u00B2 a\uFF3F \u203Fa", @"a|a");
        // An edge that is not a word character needs no boundary.
        ExpectMatches(@"-a", T | TSRegexFindWholeWord, @"x-a x-ab --a", @"-a|-a");
        ExpectMatches(@"a-", T | TSRegexFindWholeWord, @"a-x ba- a--", @"a-|a-");
        ExpectMatches(@"foo bar", T | TSRegexFindDelimitByWhitespace, @"bar foo foobar", @"bar|foo|foo|bar");
        ExpectMatches(@"a ab", T | TSRegexFindDelimitByWhitespace, @"ab", @"ab");
        ExpectMatches(@"A", T | TSRegexFindIgnoreCase, @"aA", @"a|A");
        ExpectMatches(@"e", T | TSRegexFindIgnoreDiacritics, @"eé", @"e|é");
        ExpectMatches(@"a1", T | TSRegexFindIgnoreWidth, @"ａ１ a1", @"ａ１|a1");
        ExpectMatches(@"¥section", T, @"\\section", @"\\section");

        // Errors.
        NSError *error = nil;
        Check([[TSRegexFindPattern alloc] initWithFindString:@"(" options:R error:&error] == nil && error.code == TSRegexFindErrorInvalidPattern, @"an invalid pattern is reported");
        error = nil;
        Check([[TSRegexFindPattern alloc] initWithFindString:@"" options:R error:&error] == nil && error.code == TSRegexFindErrorEmptyFindString, @"an empty find string is reported");
        error = nil;
        Check([[TSRegexFindPattern alloc] initWithFindString:@" \n" options:T | TSRegexFindDelimitByWhitespace error:&error] == nil && error.code == TSRegexFindErrorEmptyFindString, @"only whitespace has no word to find");
        TSRegexFindPattern *x = Pattern(@"x", R);
        error = nil;
        Check([[TSRegexTextFind alloc] initWithString:@"x" pattern:x selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:YES error:&error] == nil && error.code == TSRegexFindErrorEmptySelection, @"an empty selection cannot be searched in");

        // Next and previous match, wrapping.
        NSString *text = @"x1 x2 x3";
        NSArray<NSValue *> *(^matchesFrom)(NSRange) = ^(NSRange selection) {
            TSRegexTextFind *f = [[TSRegexTextFind alloc] initWithString:text pattern:Pattern(@"x\\d", R) selectedRanges:@[[NSValue valueWithRange:selection]] inSelection:NO error:NULL];
            return [f matchRangesWithCancellation:nil];
        };
        TSRegexTextFind *(^finderAt)(NSRange) = ^(NSRange selection) {
            return [[TSRegexTextFind alloc] initWithString:text pattern:Pattern(@"x\\d", R) selectedRanges:@[[NSValue valueWithRange:selection]] inSelection:NO error:NULL];
        };
        BOOL wrapped = NO;
        NSArray *all = matchesFrom(NSMakeRange(0, 0));
        Check(NSEqualRanges([finderAt(NSMakeRange(3, 2)) nextMatchInRanges:all forward:YES includingSelection:NO wraps:YES wrapped:&wrapped], NSMakeRange(6, 2)) && !wrapped, @"next after the selected match");
        Check(NSEqualRanges([finderAt(NSMakeRange(6, 2)) nextMatchInRanges:all forward:YES includingSelection:NO wraps:YES wrapped:&wrapped], NSMakeRange(0, 2)) && wrapped, @"next wraps to the top");
        Check([finderAt(NSMakeRange(6, 2)) nextMatchInRanges:all forward:YES includingSelection:NO wraps:NO wrapped:&wrapped].location == NSNotFound, @"next stops at the end without wrapping");
        Check(NSEqualRanges([finderAt(NSMakeRange(3, 2)) nextMatchInRanges:all forward:NO includingSelection:NO wraps:YES wrapped:&wrapped], NSMakeRange(0, 2)) && !wrapped, @"previous before the selected match");
        Check(NSEqualRanges([finderAt(NSMakeRange(0, 2)) nextMatchInRanges:all forward:NO includingSelection:NO wraps:YES wrapped:&wrapped], NSMakeRange(6, 2)) && wrapped, @"previous wraps to the bottom");
        Check(NSEqualRanges([finderAt(NSMakeRange(3, 2)) nextMatchInRanges:all forward:YES includingSelection:YES wraps:YES wrapped:&wrapped], NSMakeRange(3, 2)), @"incremental search keeps the selected match");
        TSRegexTextFind *empty = [[TSRegexTextFind alloc] initWithString:@"ab" pattern:Pattern(@"x*", R) selectedRanges:@[[NSValue valueWithRange:NSMakeRange(1, 0)]] inSelection:NO error:NULL];
        Check(NSEqualRanges([empty nextMatchInRanges:[empty matchRangesWithCancellation:nil] forward:YES includingSelection:NO wraps:YES wrapped:&wrapped], NSMakeRange(2, 0)), @"an empty match at the caret is passed over");

        // Selection scope and replace in selection.
        TSRegexTextFind *scoped = [[TSRegexTextFind alloc] initWithString:@"aa|aa|aa" pattern:Pattern(@"a", R)
                                                           selectedRanges:@[[NSValue valueWithRange:NSMakeRange(6, 2)], [NSValue valueWithRange:NSMakeRange(0, 2)]] inSelection:YES error:NULL];
        TSRegexReplaceAllResult *scopedResult = [scoped replaceAllWithTemplate:[[TSRegexReplacementTemplate alloc] initWithString:@"bbb" pattern:scoped.pattern syntax:TSRegexReplacementSyntaxICU] cancellation:nil];
        Check(scopedResult.numberOfMatches == 4 && scopedResult.replacements.count == 2, @"replace all in two selections");
        Check([scopedResult.selectedRanges isEqual:@[[NSValue valueWithRange:NSMakeRange(0, 6)], [NSValue valueWithRange:NSMakeRange(10, 6)]]], @"selections follow the replaced text");
        TSRegexTextFind *lookaround = [[TSRegexTextFind alloc] initWithString:@"xa ya" pattern:Pattern(@"(?<=x)a", R)
                                                               selectedRanges:@[[NSValue valueWithRange:NSMakeRange(1, 1)]] inSelection:YES error:NULL];
        Check([lookaround matchRangesWithCancellation:nil].count == 1, @"look-behind sees the text before the selection");
        TSRegexTextFind *lookahead = [[TSRegexTextFind alloc] initWithString:@"ab" pattern:Pattern(@"a(?=b)", R)
                                                              selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 1)]] inSelection:YES error:NULL];
        Check([lookahead matchRangesWithCancellation:nil].count == 1, @"look-ahead sees the text after the selection");
        TSRegexTextFind *boundary = [[TSRegexTextFind alloc] initWithString:@"concat" pattern:Pattern(@"\\bcat", R)
                                                             selectedRanges:@[[NSValue valueWithRange:NSMakeRange(3, 3)]] inSelection:YES error:NULL];
        Check([boundary matchRangesWithCancellation:nil].count == 0, @"the edge of the selection is not a word boundary");
        TSRegexTextFind *one = [[TSRegexTextFind alloc] initWithString:@"say hello" pattern:Pattern(@"h(e)llo", R)
                                                        selectedRanges:@[[NSValue valueWithRange:NSMakeRange(4, 5)]] inSelection:NO error:NULL];
        TSRegexFindReplacement *single = [one replacementInSelectionWithTemplate:[[TSRegexReplacementTemplate alloc] initWithString:@"j\\1llo" pattern:one.pattern syntax:TSRegexReplacementSyntaxOgreKit]];
        Check([single isEqual:[[TSRegexFindReplacement alloc] initWithRange:NSMakeRange(4, 5) string:@"jello"]], @"replace the selected match");
        TSRegexTextFind *none = [[TSRegexTextFind alloc] initWithString:@"say hello" pattern:Pattern(@"x", R)
                                                         selectedRanges:@[[NSValue valueWithRange:NSMakeRange(4, 5)]] inSelection:NO error:NULL];
        Check([none replacementInSelectionWithTemplate:[[TSRegexReplacementTemplate alloc] initWithString:@"" pattern:none.pattern syntax:TSRegexReplacementSyntaxICU]] == nil, @"no replacement without a match in the selection");
        TSRegexReplaceAllResult *unchanged = [none replaceAllWithTemplate:[[TSRegexReplacementTemplate alloc] initWithString:@"x" pattern:none.pattern syntax:TSRegexReplacementSyntaxICU] cancellation:nil];
        Check(unchanged.replacements.count == 0 && unchanged.numberOfMatches == 0 && unchanged.selectedRanges == nil, @"nothing to replace leaves the text alone");

        // Groups for Find All and cancellation.
        TSRegexTextFind *groups = [[TSRegexTextFind alloc] initWithString:@"ab b" pattern:Pattern(@"(a)?(b)", R)
                                                           selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
        NSMutableArray *seen = [NSMutableArray array];
        [groups enumerateMatchesWithCancellation:nil usingBlock:^(NSArray<NSValue *> *ranges, BOOL *stop) { [seen addObject:ranges]; }];
        Check(seen.count == 2 && [seen[1][1] rangeValue].location == NSNotFound && NSEqualRanges([seen[1][2] rangeValue], NSMakeRange(3, 1)), @"groups that did not take part are reported as not found");
        NSString *long_ = [@"" stringByPaddingToLength:200000 withString:@"ab" startingAtIndex:0];
        TSRegexTextFind *cancel = [[TSRegexTextFind alloc] initWithString:long_ pattern:Pattern(@"b", R) selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
        __block NSUInteger polls = 0;
        Check([cancel matchRangesWithCancellation:^BOOL { return ++polls > 10; }] == nil, @"cancelling a search returns nothing");
        Check([cancel replaceAllWithTemplate:[[TSRegexReplacementTemplate alloc] initWithString:@"" pattern:cancel.pattern syntax:TSRegexReplacementSyntaxICU] cancellation:^BOOL { return YES; }] == nil, @"cancelling replace all returns nothing");

        // Multiple replacement, as CotEditor's: rules in order, each on the previous result, with the set's options.
        NSArray<NSValue *> *whole = @[[NSValue valueWithRange:NSMakeRange(0, 0)]];
        TSRegexReplacementRule *(^rule)(NSString *, NSString *, BOOL, BOOL, BOOL) = ^(NSString *f, NSString *r, BOOL regex, BOOL ignoresCase, BOOL on) {
            return [[TSRegexReplacementRule alloc] initWithFindString:f replaceString:r usesRegularExpression:regex ignoresCase:ignoresCase enabled:on note:nil];
        };
        TSRegexMultipleReplace *(^set)(NSArray *, TSRegexFindOptions, TSRegexFindOptions, TSRegexReplacementSyntax) = ^(NSArray *rules, TSRegexFindOptions textual, TSRegexFindOptions regex, TSRegexReplacementSyntax syntax) {
            return [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:textual regularExpressionOptions:regex replacementSyntax:syntax];
        };
        NSArray *rules = @[rule(@"a", @"b", NO, NO, YES), rule(@"b", @"c", NO, NO, YES), rule(@"c", @"X", NO, NO, NO),
                           rule(@"(", @"", YES, NO, YES), rule(@"(\\w+)\\{(\\w)\\}", @"$1[$2]", YES, NO, YES)];
        TSRegexMultipleReplace *plain = set(rules, 0, TSRegexFindAnchorsMatchLines, TSRegexReplacementSyntaxICU);
        TSRegexMultipleReplaceResult *multi = [plain applyToString:@"a b \\x{y}" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil];
        Check([multi.string isEqualToString:@"c c \\x[y]"], [@"rules apply in order: " stringByAppendingString:multi.string]);
        Check([multi.counts isEqual:@[@1, @2, @0, @0, @1]] && multi.totalCount == 4, @"counts per rule; disabled and invalid rules count 0");
        Check(multi.errors.count == 1 && multi.errors[@3].code == TSRegexFindErrorInvalidPattern, @"an invalid rule is skipped and reported");
        TSRegexMultipleReplaceResult *scopedMulti = [set(@[rule(@"a", @"aaa", NO, NO, YES), rule(@"a", @"b", NO, NO, YES)], 0, 0, TSRegexReplacementSyntaxICU)
            applyToString:@"a|a" selectedRanges:@[[NSValue valueWithRange:NSMakeRange(2, 1)]] inSelection:YES lineEnding:nil cancellation:nil];
        Check([scopedMulti.string isEqualToString:@"a|bbb"] && [scopedMulti.selectedRanges isEqual:@[[NSValue valueWithRange:NSMakeRange(2, 3)]]], @"the selection follows each rule");
        // The set's options apply by kind; the rule's case option is added to them.
        TSRegexMultipleReplace *kinds = set(@[rule(@"A", @"1", NO, NO, YES), rule(@"^B", @"2", YES, NO, YES), rule(@"c", @"3", NO, YES, YES), rule(@"¥.", @"#", YES, NO, YES)],
                                            TSRegexFindIgnoreCase, TSRegexFindAnchorsMatchLines | TSRegexFindYenIsBackslash, TSRegexReplacementSyntaxICU);
        TSRegexMultipleReplaceResult *kindResult = [kinds applyToString:@"aA\nB b\nC." selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil];
        Check([kindResult.string isEqualToString:@"11\n2 b\n3#"], [@"options by kind of rule: " stringByAppendingString:kindResult.string]);
        TSRegexMultipleReplaceResult *ruleCase = [set(@[rule(@"c", @"3", NO, YES, YES), rule(@"d", @"4", YES, YES, YES), rule(@"e", @"5", NO, NO, YES)], 0, 0, TSRegexReplacementSyntaxICU)
            applyToString:@"CDE" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil];
        Check([ruleCase.string isEqualToString:@"34E"], [@"a rule's own case option: " stringByAppendingString:ruleCase.string]);
        Check((kinds.textualOptions & TSRegexFindYenIsBackslash) && (kinds.regularExpressionOptions & TSRegexFindYenIsBackslash), @"the yen sign is one setting of the set");
        Check(!(set(@[], TSRegexFindDotMatchesLineSeparators, TSRegexFindWholeWord, 0).textualOptions & TSRegexFindDotMatchesLineSeparators)
              && !(set(@[], TSRegexFindDotMatchesLineSeparators, TSRegexFindWholeWord, 0).regularExpressionOptions & TSRegexFindWholeWord), @"options of the other kind are dropped");
        // The set's syntax reads every replacement.
        TSRegexMultipleReplaceResult *ogre = [set(@[rule(@"(a)", @"\\1$1", YES, NO, YES)], 0, TSRegexFindUnescapesReplacement, TSRegexReplacementSyntaxOgreKit)
            applyToString:@"a" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil];
        Check([ogre.string isEqualToString:@"a$1"], [@"the OgreKit syntax of the set: " stringByAppendingString:ogre.string]);
        // Line endings: find strings and replaced text follow the document's.
        TSRegexMultipleReplaceResult *crlf = [set(@[rule(@"a\nb", @"x\ny", NO, NO, YES), rule(@"(y)", @"$1\\n", YES, NO, YES)], 0, TSRegexFindUnescapesReplacement, TSRegexReplacementSyntaxICU)
            applyToString:@"a\r\nb" selectedRanges:whole inSelection:NO lineEnding:@"\r\n" cancellation:nil];
        Check([crlf.string isEqualToString:@"x\r\ny\r\n"], @"find strings and replacements take the document's line ending");
        NSArray<NSValue *> *highlights = [plain matchRangesInString:@"a b" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil];
        Check([highlights isEqual:@[[NSValue valueWithRange:NSMakeRange(0, 1)], [NSValue valueWithRange:NSMakeRange(2, 1)]]], @"matches of every rule are found in the unchanged string");

        // CotEditor's definition files.
        TSRegexReplacementRule *noted = [[TSRegexReplacementRule alloc] initWithFindString:@"x/y" replaceString:@"$0" usesRegularExpression:YES ignoresCase:YES enabled:NO note:@"memo"];
        TSRegexMultipleReplace *stored = set(@[noted, rule(@"a", @"b", NO, NO, YES)], TSRegexFindWholeWord | TSRegexFindIgnoreWidth | TSRegexFindDelimitByWhitespace | TSRegexFindYenIsBackslash,
                                            TSRegexFindAnchorsMatchLines | TSRegexFindUnicodeWordBoundaries | TSRegexFindUnescapesReplacement | TSRegexFindIgnoreEmptyMatches, TSRegexReplacementSyntaxOgreKit);
        NSData *json = stored.JSONData;
        Check([[[TSRegexMultipleReplace alloc] initWithJSONData:json error:NULL] isEqual:stored], @"a set survives its JSON");
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
        Check([object[@"settings"] isEqual:@{@"textualOptions": @(NSWidthInsensitiveSearch), @"regexOptions": @(NSRegularExpressionAnchorsMatchLines | NSRegularExpressionUseUnicodeWordBoundaries),
                                             @"matchesFullWord": @YES, @"unescapesReplacementString": @YES, @"texshopReplacementSyntax": @"OgreKit",
                                             @"texshopYenIsBackslash": @YES, @"texshopIgnoresEmptyMatches": @YES, @"texshopDelimitsByWhitespace": @YES}], @"settings are written with CotEditor's keys");
        Check([object[@"replacements"] isEqual:@[@{@"findString": @"x/y", @"replacementString": @"$0", @"usesRegularExpression": @YES, @"ignoresCase": @YES, @"isEnabled": @NO, @"description": @"memo"},
                                                 @{@"findString": @"a", @"replacementString": @"b"}]], @"default values are left out as CotEditor does");
        Check([[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] containsString:@"\"x/y\""], @"slashes are not escaped");
        NSString *cot = @"{\"replacements\":[{\"findString\":\"(\\\\d)\",\"replacementString\":\"<$1>\\\\t\",\"usesRegularExpression\":true},{\"findString\":\"b\",\"replacementString\":\"c\",\"isEnabled\":false,\"description\":null}],"
                         "\"settings\":{\"textualOptions\":1,\"regexOptions\":16,\"matchesFullWord\":false,\"unescapesReplacementString\":true,\"unknown\":3}}";
        TSRegexMultipleReplace *fromCot = [[TSRegexMultipleReplace alloc] initWithJSONData:[cot dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
        Check(fromCot && fromCot.rules.count == 2 && fromCot.textualOptions == TSRegexFindIgnoreCase
              && fromCot.regularExpressionOptions == (TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement)
              && fromCot.replacementSyntax == TSRegexReplacementSyntaxICU && !fromCot.rules[1].enabled && !fromCot.rules[1].note, @"a CotEditor file is read; unknown keys are ignored");
        Check([[fromCot applyToString:@"a1b" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil].string isEqualToString:@"a<1>\tb"], @"a CotEditor file replaces as in CotEditor");
        // Every regular expression option of a file is used and written again; comparison options the panel does not
        // show are ignored (user's decision, 2026-11-12).
        NSString *literalFile = @"{\"replacements\":[{\"findString\":\"a.b\",\"replacementString\":\"X\",\"usesRegularExpression\":true},{\"findString\":\"^q\",\"replacementString\":\"Q\",\"usesRegularExpression\":true}],"
                                 "\"settings\":{\"textualOptions\":1677,\"regexOptions\":52}}";
        TSRegexMultipleReplace *literal = [[TSRegexMultipleReplace alloc] initWithJSONData:[literalFile dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
        Check(literal.regularExpressionOptions == (TSRegexFindIgnoreMetacharacters | TSRegexFindAnchorsMatchLines | TSRegexFindUseUnixLineSeparators)
              && literal.textualOptions == (TSRegexFindIgnoreCase | TSRegexFindIgnoreDiacritics), @"regular expression options are all read; hidden comparison options are ignored");
        Check([[literal applyToString:@"a.b axb\r^q" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil].string isEqualToString:@"X axb\rQ"], @"a literal set replaces as in CotEditor");
        NSDictionary *literalSettings = [NSJSONSerialization JSONObjectWithData:literal.JSONData options:0 error:NULL][@"settings"];
        Check([literalSettings[@"regexOptions"] isEqual:@52] && [literalSettings[@"textualOptions"] isEqual:@(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)], @"they are written again; ignored ones are not");
        TSRegexMultipleReplace *unix = [[TSRegexMultipleReplace alloc] initWithJSONData:[@"{\"replacements\":[{\"findString\":\"^b\",\"replacementString\":\"X\",\"usesRegularExpression\":true}],\"settings\":{\"textualOptions\":0,\"regexOptions\":48}}" dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
        Check([[unix applyToString:@"a\rb\nb" selectedRanges:whole inSelection:NO lineEnding:nil cancellation:nil].string isEqualToString:@"a\rb\nX"], @"Unix line separators are used as in CotEditor");
        // Option values are read as Swift reads a UInt.
        for (NSString *number in @[@"0", @"1", @"1.0", @"1e0", @"1.0000000000000001", @"18446744073709551615"]) {
            NSString *file = [NSString stringWithFormat:@"{\"replacements\":[],\"settings\":{\"textualOptions\":%@,\"regexOptions\":0}}", number];
            Check([[TSRegexMultipleReplace alloc] initWithJSONData:[file dataUsingEncoding:NSUTF8StringEncoding] error:NULL] != nil, [@"a whole number is accepted: " stringByAppendingString:number]);
        }
        for (NSString *number in @[@"18446744073709551616", @"18446744073709551617", @"18446744073709551614.9", @"1.5", @"-1", @"1e40", @"true", @"null", @"\"1\""]) {
            NSString *file = [NSString stringWithFormat:@"{\"replacements\":[],\"settings\":{\"textualOptions\":0,\"regexOptions\":%@}}", number];
            Check([[TSRegexMultipleReplace alloc] initWithJSONData:[file dataUsingEncoding:NSUTF8StringEncoding] error:NULL] == nil, [@"a value that is not a UInt is refused: " stringByAppendingString:number]);
        }
        NSString *missingUnescape = @"{\"replacements\":[],\"settings\":{\"textualOptions\":0,\"regexOptions\":0}}";
        Check([[TSRegexMultipleReplace alloc] initWithJSONData:[missingUnescape dataUsingEncoding:NSUTF8StringEncoding] error:NULL].regularExpressionOptions == 0, @"a missing unescape value reads as off, as in CotEditor");
        for (NSString *bad in @[@"{\"replacements\":[]}", @"{\"settings\":{\"textualOptions\":0,\"regexOptions\":0}}", @"[]", @"{",
                                @"{\"replacements\":[{\"findString\":\"a\"}],\"settings\":{\"textualOptions\":0,\"regexOptions\":0}}",
                                @"{\"replacements\":[{\"findString\":\"a\",\"replacementString\":\"b\",\"isEnabled\":1}],\"settings\":{\"textualOptions\":0,\"regexOptions\":0}}",
                                @"{\"replacements\":[],\"settings\":{\"textualOptions\":-1,\"regexOptions\":0}}",
                                @"{\"replacements\":[],\"settings\":{\"textualOptions\":true,\"regexOptions\":0}}",
                                @"{\"replacements\":[],\"settings\":{\"textualOptions\":0,\"regexOptions\":0,\"matchesFullWord\":\"yes\"}}"]) {
            NSError *error = nil;
            Check([[TSRegexMultipleReplace alloc] initWithJSONData:[bad dataUsingEncoding:NSUTF8StringEncoding] error:&error] == nil && error,
                  [@"an invalid definition is refused: " stringByAppendingString:bad]);
        }
        TSRegexMultipleReplace *tsv = [[TSRegexMultipleReplace alloc] initWithTabSeparatedText:@"a\tb\textra\r\n\nnotab\n\tempty\r\nc\t d\te"];
        Check(tsv.rules.count == 3 && [tsv.rules[0].findString isEqualToString:@"a"] && [tsv.rules[0].replaceString isEqualToString:@"b"]
              && [tsv.rules[1].replaceString isEqualToString:@""] && [tsv.rules[2].findString isEqualToString:@"d"]
              && tsv.regularExpressionOptions == (TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement), @"tab-separated lines are read as CotEditor reads them");

        if (failures == 0)
            puts("PASS: multiple replacement in order, options by kind of rule, the set's syntax, counts and errors, selection scope, line endings, CotEditor definition files and tab-separated text");
        if (failures == 0)
            puts("PASS: ICU replacement strings (compared with Foundation), OgreKit replacement strings, TeX dollars, yen signs, regex and plain-text options, next/previous/wrap, selection scope, groups, cancellation");
    }
    return failures ? 1 : 0;
}
