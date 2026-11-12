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

/// The ICU syntax gives what NSRegularExpression gives, for templates without \t \n \r.
static void CompareWithFoundation(NSString *find, NSString *text, NSUInteger count, uint32_t seed)
{
    // Single characters, and characters outside the BMP whole and as lone surrogates.
    static NSString *const alphabet = @"$$$\\\0123456789ax{}&g<>+`'-uU";
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
        NSString *expected = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:replace];
        NSString *actual = ReplaceAll(find, TSRegexFindRegularExpression, replace, text, TSRegexReplacementSyntaxICU);
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
        CompareWithFoundation(@"(a)(b)?(c)", @"xacy abcz ac", 3000, 1);
        CompareWithFoundation(@"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)", @"-abcdefghijkl-", 3000, 7);

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

        // Plain text search.
        ExpectMatches(@"a.", T, @"a.ab", @"a.");
        ExpectMatches(@"cat", T | TSRegexFindWholeWord, @"cat concat cat_ cat.", @"cat|cat");
        ExpectMatches(@"aa", T, @"aaaa", @"aa|aa");
        ExpectMatches(@"aa", T | TSRegexFindWholeWord, @"aaa aa", @"aa");
        // Characters outside the BMP are letters too.
        ExpectMatches(@"a", T | TSRegexFindWholeWord, @"a\U00020BB7 \U00020BB7a a\U00010400 a", @"a");
        ExpectMatches(@"\U00020BB7", T | TSRegexFindWholeWord, @"x\U00020BB7y \U00020BB7", @"\U00020BB7");
        ExpectMatches(@"a", T | TSRegexFindWholeWord, @"\U0001F600a\U0001F600", @"a");
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

        // Multiple replacement: rules in order, each on the previous result.
        TSRegexReplacementRule *(^ruleIn)(TSRegexReplacementSyntax, NSString *, NSString *, TSRegexFindOptions, BOOL) = ^(TSRegexReplacementSyntax x, NSString *f, NSString *r, TSRegexFindOptions o, BOOL on) {
            return [[TSRegexReplacementRule alloc] initWithFindString:f replaceString:r options:o replacementSyntax:x enabled:on note:@""];
        };
        TSRegexReplacementRule *(^rule)(NSString *, NSString *, TSRegexFindOptions, BOOL) = ^(NSString *f, NSString *r, TSRegexFindOptions o, BOOL on) {
            return ruleIn(TSRegexReplacementSyntaxOgreKit, f, r, o, on);
        };
        NSArray *rules = @[rule(@"a", @"b", T, YES), rule(@"b", @"c", T, YES), rule(@"c", @"X", T, NO),
                           rule(@"(", @"", R, YES), rule(@"(\\w+)\\{(\\w)\\}", @"\\1[\\2]", R, YES)];
        TSRegexMultipleReplaceResult *multi = [TSRegexMultipleReplace applyRules:rules toString:@"a b \\x{y}" selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO sharedOptions:0 cancellation:nil];
        Check([multi.string isEqualToString:@"c c \\x[y]"], [@"rules apply in order: " stringByAppendingString:multi.string]);
        Check([multi.counts isEqual:@[@1, @2, @0, @0, @1]] && multi.totalCount == 4, @"counts per rule; disabled and invalid rules count 0");
        Check(multi.errors.count == 1 && multi.errors[@3].code == TSRegexFindErrorInvalidPattern, @"an invalid rule is reported and skipped");
        TSRegexMultipleReplaceResult *scopedMulti = [TSRegexMultipleReplace applyRules:@[rule(@"a", @"aaa", T, YES), rule(@"a", @"b", T, YES)] toString:@"a|a"
                                                                        selectedRanges:@[[NSValue valueWithRange:NSMakeRange(2, 1)]] inSelection:YES sharedOptions:0 cancellation:nil];
        Check([scopedMulti.string isEqualToString:@"a|bbb"] && [scopedMulti.selectedRanges isEqual:@[[NSValue valueWithRange:NSMakeRange(2, 3)]]], @"the selection follows each rule");
        TSRegexMultipleReplaceResult *yen = [TSRegexMultipleReplace applyRules:@[rule(@"\u00A5d", @"#", R, YES)] toString:@"a1" selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO sharedOptions:TSRegexFindYenIsBackslash cancellation:nil];
        Check([yen.string isEqualToString:@"a#"], @"the shared yen setting applies to every rule");
        TSRegexReplacementRule *stored = rules[4];
        Check([[[TSRegexReplacementRule alloc] initWithDictionary:stored.dictionaryRepresentation] isEqual:stored], @"a rule survives its dictionary");
        Check([[TSRegexReplacementRule alloc] initWithDictionary:@{@"replace": @"x"}] == nil, @"a rule needs a find string");
        // Each rule reads its replacement in its own syntax.
        TSRegexMultipleReplaceResult *mixed = [TSRegexMultipleReplace applyRules:@[ruleIn(TSRegexReplacementSyntaxICU, @"(a)", @"$1$1\\1", R, YES),
                                                                                   ruleIn(TSRegexReplacementSyntaxOgreKit, @"(1)", @"\\1$1", R, YES)]
                                                                       toString:@"a" selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO sharedOptions:0 cancellation:nil];
        Check([mixed.string isEqualToString:@"aa1$1"], [@"rules keep their own syntax: " stringByAppendingString:mixed.string]);
        TSRegexReplacementRule *icuRule = ruleIn(TSRegexReplacementSyntaxICU, @"x", @"$0", R, YES);
        Check([[[TSRegexReplacementRule alloc] initWithDictionary:icuRule.dictionaryRepresentation] isEqual:icuRule] && [icuRule.dictionaryRepresentation[@"syntax"] isEqual:@0], @"the ICU syntax is stored");
        Check([[TSRegexReplacementRule alloc] initWithDictionary:stored.dictionaryRepresentation].replacementSyntax == TSRegexReplacementSyntaxOgreKit, @"the OgreKit syntax is stored");
        Check([[TSRegexReplacementRule alloc] initWithDictionary:@{@"find": @"x"}].replacementSyntax == TSRegexReplacementSyntaxICU, @"a rule without a syntax reads as ICU");
        Check([[TSRegexReplacementRule alloc] initWithDictionary:@{@"find": @"x", @"syntax": @7}].replacementSyntax == TSRegexReplacementSyntaxICU, @"an unknown syntax reads as ICU");

        if (failures == 0)
            puts("PASS: multiple replacement in order, per-rule syntax, counts and errors, selection scope, shared yen setting, stored rules");
        if (failures == 0)
            puts("PASS: ICU replacement strings (compared with Foundation), OgreKit replacement strings, TeX dollars, yen signs, regex and plain-text options, next/previous/wrap, selection scope, groups, cancellation");
    }
    return failures ? 1 : 0;
}
