// SPDX-License-Identifier: GPL-2.0-or-later
// The coloring of the Advanced Find panel's fields and of the multiple replacement rules: the tokens of patterns and
// replacement strings as the engine reads them, the brackets that pair up, the real named groups (also the engine's),
// the marks of OgreKit's differences from the one table, bracket matching in the find field, the message line, and
// the panel and the rule table in every language, with images. Built by Tests/run-advanced-find-coloring.py; no
// window is ever shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindFieldScanners.h"
#import "TSMultipleReplaceWindowController.h"
#import "TSMultipleReplaceLibrary.h"
#import "TSRegexOnigmoIncompatibility.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

/// Runs the main queue once: the shared coloring colors an edit right after it.
static void RunLoopOnce(void)
{
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static TSAdvancedFindController *MakeController(void)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    TSAdvancedFindController *controller = [[TSAdvancedFindController alloc] initWithSettings:settings];
    controller.beepHandler = ^{};
    return controller;
}

#pragma mark Tokens

static NSString *RoleName(TSSyntaxRole role)
{
    switch (role) {
        case TSSyntaxRoleRegexCharacterClass: return @"class";
        case TSSyntaxRoleRegexBackreference: return @"ref";
        case TSSyntaxRoleRegexQuantifier: return @"quant";
        case TSSyntaxRoleRegexAnchor: return @"anchor";
        case TSSyntaxRoleRegexSymbol: return @"sym";
        case TSSyntaxRoleRegexEscape: return @"esc";
        case TSSyntaxRoleRegexIncompatible: return @"ONIG";
        case TSSyntaxRoleInvalid: return @"BAD";
        case TSSyntaxRoleComment: return @"comment";
        default: return @"other";
    }
}

/// The tokens as "role:text role:text …".
static NSString *Tokens(id<TSSyntaxScanner> scanner, NSString *string)
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [scanner enumerateTokensInString:string range:[scanner lineAlignedRangeForEditedRange:NSMakeRange(0, 0) inString:string]
                          usingBlock:^(NSRange range, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        [parts addObject:[NSString stringWithFormat:@"%@:%@", RoleName(role), [string substringWithRange:range]]];
    }];
    return [parts componentsJoinedByString:@" "];
}

static void CheckTokens(id<TSSyntaxScanner> scanner, NSString *string, NSString *expected)
{
    NSString *actual = Tokens(scanner, string);
    Check([actual isEqualToString:expected], [NSString stringWithFormat:@"tokens of %@: expected [%@], got [%@]", string, expected, actual]);
}

static void TestPatternTokens(void)
{
    TSRegexFindOptions base = TSRegexFindRegularExpression;
    TSAdvancedFindPatternScanner *plain = [[TSAdvancedFindPatternScanner alloc] initWithOptions:base];
    CheckTokens(plain, @"x(\\d+)", @"sym:( class:\\d quant:+ sym:)");
    CheckTokens(plain, @"[a-z]+?|\\.", @"class:[a-z] quant:+? sym:| esc:\\.");
    CheckTokens(plain, @"(?<n>a)\\k<n>\\1", @"sym:(?<n> sym:) ref:\\k<n> ref:\\1");
    CheckTokens(plain, @"(?<=a)(?!b)(?:c)", @"sym:(?<= sym:) sym:(?! sym:) sym:(?: sym:)");
    CheckTokens(plain, @"^a\\b$", @"anchor:^ anchor:\\b anchor:$");
    CheckTokens(plain, @"(?#note)a", @"comment:(?#note)");
    CheckTokens(plain, @"\\h", @"ONIG:\\h");
    CheckTokens(plain, @"a\\Kb", @"ONIG:\\K");
    CheckTokens(plain, @"\\g<x>", @"ONIG:\\g<x>");
    CheckTokens(plain, @"(?m)^a", @"ONIG:(?m) anchor:^");
    CheckTokens(plain, @"(?~a)", @"ONIG:(?~ sym:)");
    CheckTokens(plain, @"(?i)a", @"sym:(?i)");
    CheckTokens(plain, @"a{2}+", @"ONIG:{2}+");
    CheckTokens(plain, @"a{2,3}?b{x}", @"quant:{2,3}? BAD:{ BAD:}");
    CheckTokens(plain, @"a}\\{", @"BAD:} esc:\\{");
    CheckTokens(plain, @"a{1,2}{3}", @"quant:{1,2} BAD:{3}");
    CheckTokens(plain, @"*a", @"BAD:*");
    CheckTokens(plain, @"(a", @"BAD:(");
    CheckTokens(plain, @"a)", @"BAD:)");
    CheckTokens(plain, @"[ab", @"BAD:[ab");
    CheckTokens(plain, @"a\\", @"BAD:\\");
    CheckTokens(plain, @"[[:alpha:]\\]]x", @"class:[[:alpha:]\\]]");
    CheckTokens(plain, @"あ+い*", @"quant:+ quant:*");
    CheckTokens(plain, @"\\つ(?ぢ)", @"esc:\\つ BAD:(?ぢ BAD:)"); // U+3064 and U+3062 must not be read as the letters d and b
    CheckTokens(plain, @"\\Qa.b\\E.", @"esc:\\Q esc:\\E class:.");
    CheckTokens(plain, @"😀+", @"quant:+");
    CheckTokens([[TSAdvancedFindPatternScanner alloc] initWithOptions:base | TSRegexFindYenIsBackslash], @"¥d+", @"class:¥d quant:+");
    CheckTokens(plain, @"¥d", @"");
    CheckTokens([[TSAdvancedFindPatternScanner alloc] initWithOptions:base | TSRegexFindAllowCommentsAndWhitespace], @"a + # many\nb", @"quant:+ comment:# many");
    CheckTokens([[TSAdvancedFindPatternScanner alloc] initWithOptions:base | TSRegexFindIgnoreMetacharacters], @"(a)+", @"");
    Check([plain diagnosticsInString:@"\\h(a"].count == 2, @"one message for \\h and one for the open group");
    NSArray<TSSyntaxDiagnostic *> *marks = [plain diagnosticsInString:@"(a"];
    Check(marks.count == 1 && [marks.firstObject.message isEqualToString:TSAdvancedFindLocalized(@"AdvancedFind.Mark.UnclosedParen", @"This group is not closed.")],
          @"an open group has its message");
}

static void TestReplacementTokens(void)
{
    TSRegexFindOptions options = TSRegexFindRegularExpression | TSRegexFindUnescapesReplacement;
    TSRegexFindPattern *two = [[TSRegexFindPattern alloc] initWithFindString:@"(a)(?<x>b)" options:options error:NULL];
    TSRegexFindPattern *twelve = [[TSRegexFindPattern alloc] initWithFindString:@"(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)" options:options error:NULL];
    TSAdvancedFindReplacementScanner *icu = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxICU options:options pattern:two];
    CheckTokens(icu, @"$1-$3 $0", @"ref:$1 BAD:$3 ref:$0");
    CheckTokens(icu, @"\\n\\$1\\\\", @"esc:\\n esc:\\$ esc:\\\\");
    CheckTokens(icu, @"$12", @"ref:$1"); // two groups: one digit is read, as NSRegularExpression does
    CheckTokens(icu, @"a\\", @"BAD:\\");
    CheckTokens([[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxICU options:options pattern:twelve], @"$123", @"ref:$12");
    CheckTokens([[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxICU options:options pattern:nil], @"$9", @"ref:$9");
    // The places of the unescaped escapes in the string as written, also next to a surrogate that takes the next unit
    CheckTokens(icu, @"😀\\t$1", @"esc:\\t ref:$1");
    CheckTokens(icu, @"\\\\$1\\t", @"esc:\\\\ ref:$1 esc:\\t");
    CheckTokens([[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxICU options:TSRegexFindRegularExpression pattern:two],
                @"\\t$1", @"esc:\\t ref:$1"); // without unescaping, \t is an escaped t
    TSAdvancedFindReplacementScanner *ogre = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxOgreKit options:options pattern:two];
    CheckTokens(ogre, @"\\1\\g<x>\\g<y>$1\\&\\x{41}", @"ref:\\1 ref:\\g<x> BAD:\\g<y> ref:\\& esc:\\x{41}");
    CheckTokens(ogre, @"\\3", @"BAD:\\3");
    CheckTokens(ogre, @"\\+\\`\\'\\-\\x", @"ref:\\+ ref:\\` ref:\\' ref:\\- esc:\\x");
    CheckTokens([[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxOgreKit options:options | TSRegexFindYenIsBackslash pattern:two], @"¥1", @"ref:¥1");
    NSArray<TSSyntaxDiagnostic *> *marks = [ogre diagnosticsInString:@"\\g<y>\\9"];
    Check(marks.count == 2 && [marks[0].message containsString:@"y"] && [marks[1].message containsString:@"9"], @"each missing group has its message with its name or number");
}

#pragma mark Brackets and names

static NSString *Pairs(NSString *pattern, TSRegexFindOptions options)
{
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSValue *pair in [[[TSAdvancedFindPatternScanner alloc] initWithOptions:options] bracketPairsInString:pattern])
        [pairs addObject:[NSString stringWithFormat:@"%lu-%lu", (unsigned long)pair.rangeValue.location, (unsigned long)NSMaxRange(pair.rangeValue) - 1]];
    return [pairs componentsJoinedByString:@" "];
}

static void TestPairsAndNames(void)
{
    TSRegexFindOptions regex = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    struct { NSString *pattern; NSString *pairs; } cases[] = {
        // groups and classes; an escaped ] in a class; then \( and a ( inside a class pair with nothing
        {@"(a(b)[c\\]d])x\\(y[(]", @"0-11 2-4 5-10 16-18"},
        {@"[a-z&&[^aeiou]]", @"0-14 6-13"},
        {@"(?#x)\\Q(\\E(y)", @"10-12"},          // a comment and \Q…\E hold no brackets
        {@"(?<name>a)(?:b)(?=c)", @"0-9 10-14 15-19"},
        {@"(a", @""},                              // unclosed
        {@"a)", @""},                              // closes nothing
        {@"[(]", @"0-2"},
        {@"¥(a)", @""},                            // ¥ is a backslash with the option on
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        TSRegexFindOptions options = regex | (i == 7 ? TSRegexFindYenIsBackslash : 0);
        NSString *pairs = Pairs(cases[i].pattern, options);
        Check([pairs isEqualToString:cases[i].pairs], [NSString stringWithFormat:@"bracket pairs of %@: %@ (expected %@)", cases[i].pattern, pairs, cases[i].pairs]);
    }
    Check(Pairs(@"(a)", regex | TSRegexFindIgnoreMetacharacters).length == 0, @"no brackets when the pattern is taken literally");

    struct { NSString *pattern; NSArray<NSString *> *names; } named[] = {
        {@"(?<a>x)[(?<b>y)]", @[@"a"]},                 // not in a class
        {@"\\Q(?<d>\\E(?<e>z)", @[@"e"]},                // not in \Q…\E
        {@"(?#(?<h>)(?<i>a)", @[@"i"]},                  // not in a comment
        {@"(?<f>a) # (?<g>b)\n", @[@"f"]},               // not in a comment of the x option
        {@"(?<one>a)|(?<two>b)", @[@"one", @"two"]},
    };
    for (size_t i = 0; i < sizeof named / sizeof named[0]; i++) {
        TSRegexFindOptions options = regex | (i == 3 ? TSRegexFindAllowCommentsAndWhitespace : 0);
        NSArray<NSString *> *names = [[[TSAdvancedFindPatternScanner alloc] initWithOptions:options] captureGroupNamesInString:named[i].pattern];
        Check([names isEqualToArray:named[i].names], [NSString stringWithFormat:@"group names of %@: %@", named[i].pattern, [names componentsJoinedByString:@","]]);
        TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:named[i].pattern options:options error:NULL];
        Check(!pattern || [pattern.captureGroupNames isEqualToArray:named[i].names],
              [NSString stringWithFormat:@"the engine has the same group names for %@: %@", named[i].pattern, [pattern.captureGroupNames componentsJoinedByString:@","]]);
    }

    // The replace field knows only the real groups: \g<b> refers to a name inside a class.
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:@"[(?<b>y)]x" options:regex error:NULL];
    TSAdvancedFindReplacementScanner *replace = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxOgreKit options:regex pattern:pattern];
    BOOL flagged = NO;
    for (TSSyntaxDiagnostic *diagnostic in [replace diagnosticsInString:@"<\\g<b>>"])
        flagged = flagged || diagnostic.role == TSSyntaxRoleInvalid;
    Check(pattern && flagged, @"\\g<b> is marked when (?<b> is only inside a class");
}

/// Every difference the find field marks gives the cheat sheet's message, from the engine's one table.
static void TestDifferences(void)
{
    TSRegexFindOptions regex = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    NSDictionary<NSNumber *, NSString *> *examples = @{
        @(TSRegexOnigmoIncompatibilityHexDigit): @"\\h", @(TSRegexOnigmoIncompatibilityMultiline): @"(?m)a", @(TSRegexOnigmoIncompatibilityPossessive): @"a{2}+",
        @(TSRegexOnigmoIncompatibilityKeep): @"a\\Kb", @(TSRegexOnigmoIncompatibilityCall): @"(a)\\g<1>", @(TSRegexOnigmoIncompatibilityAbsent): @"(?~a)",
        @(TSRegexOnigmoIncompatibilityLiteralBrace): @"a}",
    };
    TSAdvancedFindPatternScanner *scanner = [[TSAdvancedFindPatternScanner alloc] initWithOptions:regex];
    NSUInteger marked = 0;
    for (TSRegexOnigmoIncompatibility *entry in TSRegexFindPattern.onigmoIncompatibilities) {
        if (!entry.isMarked)
            continue;
        marked++;
        NSString *example = examples[@(entry.kind)];
        BOOL found = NO;
        for (TSSyntaxDiagnostic *diagnostic in [scanner diagnosticsInString:example ?: @""])
            found = found || [diagnostic.message isEqualToString:entry.message];
        Check(example && found, [NSString stringWithFormat:@"the field marks %@ with the table's message", entry.term]);
    }
    Check(marked == examples.count, [NSString stringWithFormat:@"the table's %lu marked differences are all marked", (unsigned long)marked]);
}

#pragma mark The panel

static id ForegroundAt(NSTextView *field, NSUInteger index)
{
    return [field.layoutManager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:index effectiveRange:NULL];
}

static id UnderlineAt(NSTextView *field, NSUInteger index)
{
    return [field.layoutManager temporaryAttribute:NSUnderlineColorAttributeName atCharacterIndex:index effectiveRange:NULL];
}

static void TestPanelFields(void)
{
    TSAdvancedFindController *controller = MakeController();
    TSAdvancedFindSettings *settings = controller.settings;
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    TSSyntaxColorScheme *scheme = TSAdvancedFindFieldColorScheme();
    NSTextView *find = panel.findField, *replace = panel.replaceField;
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;
    settings.findString = @"(a)+\\h";
    settings.replaceString = @"$1$2";
    [panel reloadFromSettings];
    Check(ForegroundAt(find, 3) == [scheme attributesForRole:TSSyntaxRoleRegexQuantifier][NSForegroundColorAttributeName], @"the quantifier of the find field is colored");
    Check(UnderlineAt(find, 5) != nil, @"\\h is marked in the find field");
    Check(ForegroundAt(replace, 0) == [scheme attributesForRole:TSSyntaxRoleRegexBackreference][NSForegroundColorAttributeName] && UnderlineAt(replace, 0) == nil,
          @"$1 is a reference");
    Check(UnderlineAt(replace, 2) != nil, @"$2 is marked: the pattern has one group");
    NSString *hexMessage = [TSRegexFindPattern onigmoIncompatibilityOfKind:TSRegexOnigmoIncompatibilityHexDigit].message;
    NSString *more = [NSString stringWithFormat:TSAdvancedFindLocalized(@"AdvancedFind.MoreMarks", @"(%lu more)"), 1UL];
    Check([panel.statusField.stringValue isEqualToString:[NSString stringWithFormat:@"%@ %@", hexMessage, more]] && panel.statusField.textColor == NSColor.systemOrangeColor,
          [NSString stringWithFormat:@"the message line gives the first mark, in orange, and how many more (%@)", panel.statusField.stringValue]);
    Check([panel.statusField.toolTip isEqualToString:panel.statusField.stringValue], @"the whole message is in the tooltip");

    // A second group makes $2 valid: the replace field follows the pattern.
    [find setSelectedRange:NSMakeRange(find.string.length, 0)];
    [find insertText:@"(b)" replacementRange:NSMakeRange(find.string.length, 0)];
    RunLoopOnce(); // the coloring follows an edit right after it
    Check(UnderlineAt(replace, 2) == nil && [settings.findString isEqualToString:@"(a)+\\h(b)"], @"typing a second group in the find field takes the mark off $2");
    // Typing in the replace field marks a reference again.
    [replace insertText:@"$3" replacementRange:NSMakeRange(replace.string.length, 0)];
    RunLoopOnce();
    Check(UnderlineAt(replace, 4) != nil, @"typing $3 in the replace field marks it");
    // An error of the engine comes first, in red.
    settings.findString = @"(a";
    [panel reloadFromSettings];
    Check(panel.statusField.textColor == NSColor.systemRedColor && [panel.statusField.stringValue containsString:@" — "]
          && [panel.statusField.stringValue hasSuffix:TSAdvancedFindLocalized(@"AdvancedFind.Mark.UnclosedParen", @"This group is not closed.")],
          [NSString stringWithFormat:@"the engine's error, then the field's mark, in red (%@)", panel.statusField.stringValue]);
    // OgreKit's syntax reads the replacement otherwise.
    settings.findString = @"(a)";
    settings.replaceString = @"\\1$2";
    settings.replacementSyntax = TSRegexReplacementSyntaxOgreKit;
    [panel reloadFromSettings];
    Check(ForegroundAt(replace, 0) == [scheme attributesForRole:TSSyntaxRoleRegexBackreference][NSForegroundColorAttributeName] && ForegroundAt(replace, 2) == nil,
          @"with OgreKit's syntax \\1 is a reference and $2 text");
    // Without regular expressions, nothing is colored or marked; the line is empty.
    settings.options = TSRegexFindDefaultOptions;
    [panel optionsDidChange];
    Check(ForegroundAt(find, 1) == nil && ForegroundAt(replace, 0) == nil && panel.statusField.stringValue.length == 0, @"plain text is not colored, and has no message");
    // With the pattern read literally, neither.
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression | TSRegexFindIgnoreMetacharacters;
    settings.findString = @"(a)+";
    [panel reloadFromSettings];
    Check(ForegroundAt(find, 3) == nil, @"a pattern read literally is not colored");
    // While text is composed with an input method, the coloring waits.
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"a+";
    [panel reloadFromSettings];
    [find setMarkedText:@"か" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(2, 0)];
    Check(find.hasMarkedText && ForegroundAt(find, 1) == [scheme attributesForRole:TSSyntaxRoleRegexQuantifier][NSForegroundColorAttributeName], @"marked text waits");
    [find unmarkText];
    Check(!panel.window.isVisible, @"the panel is never shown");
}

static void TestBrackets(void)
{
    TSAdvancedFindController *controller = MakeController();
    TSAdvancedFindSettings *settings = controller.settings;
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    TSAdvancedFindFieldView *field = (TSAdvancedFindFieldView *)panel.findField;
    NSMutableArray<NSValue *> *shown = [NSMutableArray array];
    field.bracketIndicator = ^(NSTextView *view, NSRange range) { [shown addObject:[NSValue valueWithRange:range]]; };
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"(a[b])c\\(d)";
    [panel reloadFromSettings];
    [panel.window makeFirstResponder:field];
    Check(field.bracketScanner != nil, @"the find field knows the pattern's brackets with Regular expression on");
    struct { NSUInteger caret; NSInteger partner; } carets[] = {
        {6, 0},   // after ) : its (
        {5, 2},   // after ] : its [
        {1, 5},   // after ( : its )
        {7, -1},  // after c
        {10, -1}, // after \(: an escaped bracket
        {11, -1}, // after a ) that closes nothing
        {0, -1},
    };
    for (size_t i = 0; i < sizeof carets / sizeof carets[0]; i++) {
        [shown removeAllObjects];
        field.selectedRange = NSMakeRange(carets[i].caret, 0);
        BOOL ok = carets[i].partner < 0 ? shown.count == 0
            : shown.count == 1 && NSEqualRanges(shown.firstObject.rangeValue, NSMakeRange((NSUInteger)carets[i].partner, 1));
        Check(ok, [NSString stringWithFormat:@"caret at %lu shows %@", (unsigned long)carets[i].caret, shown.firstObject ? NSStringFromRange(shown.firstObject.rangeValue) : @"nothing"]);
    }
    [shown removeAllObjects];
    field.selectedRange = NSMakeRange(0, 6);
    Check(shown.count == 0, @"a selection shows no partner");
    // A double-click on a bracket selects the pair; elsewhere a word as usual.
    NSRange onOpen = [field selectionRangeForProposedRange:NSMakeRange(0, 0) granularity:NSSelectByWord];
    NSRange onClose = [field selectionRangeForProposedRange:NSMakeRange(4, 0) granularity:NSSelectByWord];
    NSRange onLetter = [field selectionRangeForProposedRange:NSMakeRange(6, 0) granularity:NSSelectByWord];
    Check(NSEqualRanges(onOpen, NSMakeRange(0, 6)) && NSEqualRanges(onClose, NSMakeRange(2, 3)) && NSEqualRanges(onLetter, NSMakeRange(6, 1)),
          [NSString stringWithFormat:@"double-click selects the pair (%@ %@ %@)", NSStringFromRange(onOpen), NSStringFromRange(onClose), NSStringFromRange(onLetter)]);
    // Without regular expressions, brackets are plain text; nor in the replace field.
    settings.options = TSRegexFindDefaultOptions;
    [panel reloadFromSettings];
    [shown removeAllObjects];
    field.selectedRange = NSMakeRange(6, 0);
    Check(!field.bracketScanner && shown.count == 0 && NSEqualRanges([field selectionRangeForProposedRange:NSMakeRange(0, 0) granularity:NSSelectByWord], NSMakeRange(0, 1)),
          @"no bracket matching without Regular expression");
    Check(![(TSAdvancedFindFieldView *)panel.replaceField bracketScanner], @"no bracket matching in the replace field");
}

#pragma mark The rules of a multiple replacement

static TSRegexReplacementRule *Rule(NSString *find, NSString *replace, BOOL regex, BOOL enabled)
{
    return [[TSRegexReplacementRule alloc] initWithFindString:find replaceString:replace usesRegularExpression:regex ignoresCase:NO enabled:enabled note:nil];
}

static NSURL *TemporaryDirectory(void)
{
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
}

/// The cell of a rule's find or replacement column, as the table shows it.
static NSAttributedString *CellText(TSMultipleReplaceWindowController *window, NSInteger row, NSString *column)
{
    NSTableView *table = window.ruleTable.tableView;
    NSTableColumn *tableColumn = [table tableColumnWithIdentifier:column];
    NSView *cell = [table.delegate tableView:table viewForTableColumn:tableColumn row:row];
    return [cell isKindOfClass:[NSTextField class]] ? ((NSTextField *)cell).attributedStringValue : [NSAttributedString new];
}

static TSMultipleReplaceWindowController *MakeRuleWindow(TSMultipleReplaceLibrary **library)
{
    *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:TemporaryDirectory()];
    (*library).usesTrash = NO;
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[Rule(@"(\\w+)\\h", @"$1$2", YES, YES), Rule(@"a+", @"$1", NO, YES),
                                                                                    Rule(@"b+", @"x", YES, NO), Rule(@"\\\\section\\{([^}]*)\\}", @"\\\\section*{$1}", YES, YES),
                                                                                    Rule(@"\\\\section{(.*)}", @"\\\\section*{$1}", YES, YES)]
                                                                  textualOptions:TSRegexFindDefaultOptions
                                                        regularExpressionOptions:TSRegexFindDefaultOptions | TSRegexFindRegularExpression
                                                               replacementSyntax:TSRegexReplacementSyntaxICU];
    [*library saveSet:set named:@"Rules" error:NULL];
    return [[TSMultipleReplaceWindowController alloc] initWithFindController:MakeController() library:*library];
}

static void TestRuleTable(void)
{
    TSMultipleReplaceLibrary *library = nil;
    TSMultipleReplaceWindowController *window = MakeRuleWindow(&library);
    TSSyntaxColorScheme *scheme = TSAdvancedFindFieldColorScheme();
    NSColor *quantifier = [scheme attributesForRole:TSSyntaxRoleRegexQuantifier][NSForegroundColorAttributeName];
    NSAttributedString *find = CellText(window, 0, @"find"), *replace = CellText(window, 0, @"replace");
    Check([find.string isEqualToString:@"(\\w+)\\h"] && [find attribute:NSForegroundColorAttributeName atIndex:3 effectiveRange:NULL] == quantifier
          && [find attribute:NSUnderlineColorAttributeName atIndex:6 effectiveRange:NULL] != nil, @"a regular expression rule's pattern is colored and \\h marked");
    Check([replace attribute:NSUnderlineColorAttributeName atIndex:0 effectiveRange:NULL] == nil && [replace attribute:NSUnderlineColorAttributeName atIndex:2 effectiveRange:NULL] != nil,
          @"its replacement knows the rule's groups: $2 is marked");
    NSAttributedString *plain = CellText(window, 1, @"find"), *plainReplace = CellText(window, 1, @"replace");
    Check([plain attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL] != quantifier && [plainReplace attribute:NSUnderlineColorAttributeName atIndex:0 effectiveRange:NULL] == nil,
          @"a plain text rule is not colored");
    Check([CellText(window, 2, @"find") attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL] != quantifier, @"a disabled rule is not colored");
    TSRegexMultipleReplace *set = window.ruleTable.set;
    window.ruleTable.set = [[TSRegexMultipleReplace alloc] initWithRules:set.rules textualOptions:set.textualOptions regularExpressionOptions:set.regularExpressionOptions
                                                       replacementSyntax:TSRegexReplacementSyntaxOgreKit];
    NSAttributedString *ogre = CellText(window, 3, @"replace"); // \\section*{$1}
    Check([ogre attribute:NSForegroundColorAttributeName atIndex:11 effectiveRange:NULL] != [scheme attributesForRole:TSSyntaxRoleRegexBackreference][NSForegroundColorAttributeName]
          && [ogre attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] == [scheme attributesForRole:TSSyntaxRoleRegexEscape][NSForegroundColorAttributeName],
          @"with the set's OgreKit syntax, $1 is text and \\\\ an escape");
    [NSFileManager.defaultManager removeItemAtURL:library.directory error:NULL];
}

#pragma mark Layout and images

/// Windows that are never shown do not draw buttons; each button's own cell is drawn at its measured frame (the
/// method of Tests/AdvancedFindPanel.m).
static BOOL WritePNG(NSView *view, NSAppearance *appearance, NSString *path)
{
    __block BOOL written = NO;
    [appearance performAsCurrentDrawingAppearance:^{
        [view layoutSubtreeIfNeeded];
        [view displayIfNeeded];
        NSBitmapImageRep *raw = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        if (!raw)
            return;
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:raw];
        NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
        [image lockFocus];
        [NSColor.windowBackgroundColor setFill];
        NSRectFill(view.bounds);
        NSImage *cached = [[NSImage alloc] initWithSize:view.bounds.size];
        [cached addRepresentation:raw];
        [cached drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        NSMutableArray<NSView *> *pending = [view.subviews mutableCopy];
        while (pending.count) {
            NSView *v = pending.lastObject;
            [pending removeLastObject];
            [pending addObjectsFromArray:v.subviews];
            if (!([v isKindOfClass:[NSButton class]] || [v isKindOfClass:[NSSegmentedControl class]]) || v.isHiddenOrHasHiddenAncestor)
                continue;
            NSRect frame = [v convertRect:v.bounds toView:view];
            [NSGraphicsContext saveGraphicsState];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:frame.origin.x yBy:view.isFlipped ? NSHeight(view.bounds) - NSMaxY(frame) : frame.origin.y];
            if (v.isFlipped) {
                [transform translateXBy:0 yBy:frame.size.height];
                [transform scaleXBy:1 yBy:-1];
            }
            [transform concat];
            [[(NSControl *)v cell] drawWithFrame:v.bounds inView:v];
            [NSGraphicsContext restoreGraphicsState];
        }
        [image unlockFocus];
        NSBitmapImageRep *painted = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        written = [[painted representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }];
    return written;
}

/// Every mark's message, alone in the line under the options of the smallest panel, in this language.
static void TestMessagesFit(NSString *language)
{
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:MakeController()];
    [panel.window setContentSize:panel.window.contentMinSize];
    NSMutableArray<NSString *> *messages = [NSMutableArray array];
    for (NSString *pattern in @[@"a)", @"(a", @"a\\", @"(?<a", @"[a", @"(?#a", @"(?Q)", @"*", @"a}"])
        for (TSSyntaxDiagnostic *diagnostic in [[[TSAdvancedFindPatternScanner alloc] initWithOptions:TSRegexFindRegularExpression] diagnosticsInString:pattern])
            [messages addObject:diagnostic.message];
    for (TSRegexOnigmoIncompatibility *entry in TSRegexFindPattern.onigmoIncompatibilities)
        if (entry.isMarked)
            [messages addObject:entry.message];
    TSRegexFindPattern *one = [[TSRegexFindPattern alloc] initWithFindString:@"(a)" options:TSRegexFindRegularExpression error:NULL];
    for (TSSyntaxDiagnostic *diagnostic in [[[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxOgreKit options:TSRegexFindRegularExpression pattern:one]
                                            diagnosticsInString:@"\\9\\g<section>\\"])
        [messages addObject:diagnostic.message];
    Check([NSSet setWithArray:messages].count == 8 + 7 + 3, [NSString stringWithFormat:@"%lu different messages", (unsigned long)[NSSet setWithArray:messages].count]);
    NSTextField *status = panel.statusField;
    for (NSString *message in messages) {
        status.stringValue = message;
        [panel.window.contentView layoutSubtreeIfNeeded];
        if (status.cell.cellSize.width > NSWidth(status.frame) + 0.5) {
            printf("FAIL %s: the mark's message is cut in the smallest panel: %s (%.0f wide, needs %.0f)\n", language.UTF8String, message.UTF8String,
                   NSWidth(status.frame), status.cell.cellSize.width);
            failures++;
        }
    }
}

static void WriteImages(NSString *directory, NSString *language)
{
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    TSAdvancedFindController *controller = MakeController();
    TSAdvancedFindSettings *settings = controller.settings;
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;
    // The lab's image (AdvancedFindLab shots/*-panel.png): every role, OgreKit's differences and a reference to a
    // group the pattern does not have
    settings.findString = @"\\\\(bf|it)\\s+([^}]*)\\}|\\d{4}+\\h";
    settings.replaceString = @"\\\\text$1{$2}$3\\n";
    [panel reloadFromSettings];
    TSMultipleReplaceLibrary *library = nil;
    TSMultipleReplaceWindowController *rules = MakeRuleWindow(&library);
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:name];
        NSString *tag = [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
        panel.window.appearance = appearance;
        rules.window.appearance = appearance;
        [rules.ruleTable.tableView reloadData];
        NSString *base = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", language, tag]];
        Check(WritePNG(panel.window.contentView, appearance, [base stringByAppendingString:@"-colored-panel.png"])
              && WritePNG(rules.window.contentView, appearance, [base stringByAppendingString:@"-colored-rules.png"]), @"images written");
    }
    [NSFileManager.defaultManager removeItemAtURL:library.directory error:NULL];
}

#pragma mark Main

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *mode = argc > 1 ? @(argv[1]) : @"all";
        NSString *images = argc > 2 && argv[2][0] != '-' ? @(argv[2]) : nil; // not the -AppleLanguages that follows
        NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"behavior"]) {
            TestPatternTokens();
            TestReplacementTokens();
            TestPairsAndNames();
            TestDifferences();
            TestPanelFields();
            TestBrackets();
            TestRuleTable();
        }
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"layout"]) {
            TestMessagesFit(language);
            if (images)
                WriteImages(images, language);
        }
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, language.UTF8String);
    }
    return 0;
}
