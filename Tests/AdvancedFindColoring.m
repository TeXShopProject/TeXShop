// SPDX-License-Identifier: GPL-2.0-or-later
// The coloring of the Advanced Find panel's fields and of the multiple replacement rules: the tokens of patterns and
// replacement strings as the engine reads them, the brackets that pair up, the real named groups (also the engine's),
// the marks of OgreKit's differences from the one table, bracket matching in the find field, the message line, the
// panel and the rule table in every language, with images, and the source's theme, font and TeX coloring in the
// fields and the rules (light and dark, a change of theme, syntax coloring off). Built by
// Tests/run-advanced-find-coloring.py; no window is ever shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindFieldScanners.h"
#import "TSMultipleReplaceWindowController.h"
#import "TSMultipleReplaceLibrary.h"
#import "TSRegexOnigmoIncompatibility.h"
#import "TSAdvancedFindFieldStyle.h"

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

#pragma mark Themes

/// The bundled themes (Resources/TeXShop/Themes, given by the runner).
static NSDictionary *Theme(NSString *name)
{
    NSString *directory = NSProcessInfo.processInfo.environment[@"ADVANCED_FIND_THEMES"] ?: @"";
    NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:[[directory stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"plist"]];
    if (!theme) {
        fprintf(stderr, "FAIL: no theme %s in %s\n", name.UTF8String, directory.UTF8String);
        exit(1);
    }
    return theme;
}

/// A color of a theme as the source shows it: opaque, whatever alpha the theme stores.
static NSColor *ThemeColor(NSDictionary *theme, NSString *key)
{
    NSArray<NSNumber *> *rgb = theme[key];
    return [NSColor colorWithRed:rgb[0].doubleValue green:rgb[1].doubleValue blue:rgb[2].doubleValue alpha:1];
}

static BOOL SameColor(id a, id b)
{
    if (![a isKindOfClass:[NSColor class]] || ![b isKindOfClass:[NSColor class]])
        return NO;
    NSColor *x = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return x && y && fabs(x.redComponent - y.redComponent) < 0.002 && fabs(x.greenComponent - y.greenComponent) < 0.002
        && fabs(x.blueComponent - y.blueComponent) < 0.002 && fabs(x.alphaComponent - y.alphaComponent) < 0.002;
}

/// What the application gives (TSAppDelegate.m, checked by run-advanced-find-field-style.py), with these themes.
static NSDictionary *LightTheme, *DarkTheme;
static BOOL ColorsSyntax = YES;
static NSFont *SourceFont;

static void InstallProvider(void)
{
    TSAdvancedFindFieldStyle.provider = ^TSAdvancedFindFieldStyle *(BOOL dark) {
        NSDictionary *theme = dark ? DarkTheme : LightTheme;
        TSSyntaxColorScheme *scheme = ColorsSyntax ? [[TSSyntaxColorScheme alloc] initWithTheme:theme dark:dark] : nil;
        return [[TSAdvancedFindFieldStyle alloc] initWithScheme:scheme texOptions:[TSSyntaxTeXOptions new] font:SourceFont
                                                      textColor:ThemeColor(theme, @"EditorText") backgroundColor:ThemeColor(theme, @"EditorBackground")
                                            insertionPointColor:ThemeColor(theme, @"EditorInsertionPoint")];
    };
}

/// The theme keys of the regular expression roles (Sources/Syntax/TSSyntaxColorScheme.m, TSSyntaxRoleThemeKeys).
static NSDictionary<NSNumber *, NSString *> *RegexKeys(void)
{
    return @{@(TSSyntaxRoleRegexCharacterClass): @"SyntaxCommand", @(TSSyntaxRoleRegexEscape): @"explIntenseFunction",
             @(TSSyntaxRoleRegexBackreference): @"explVariable", @(TSSyntaxRoleRegexQuantifier): @"SyntaxMarker",
             @(TSSyntaxRoleRegexAnchor): @"explFunction", @(TSSyntaxRoleRegexSymbol): @"SyntaxMarkerParen", @(TSSyntaxRoleComment): @"SyntaxComment"};
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

    // Comments of the x option, turned on or off inside the pattern and ended as ICU ends them (first audit F1, F2):
    // the names are those of ICU's groups, and \g<name> gives what ICU's group matched.
    NSString *ls = @" ", *ps = @" ", *nel = [NSString stringWithFormat:@"%C", (unichar)0x85];
    struct { NSString *pattern; BOOL extended; NSArray<NSString *> *names; } scoped[] = {
        {@"(?-x:#(?<real>a))", YES, @[@"real"]},
        {@"(?x)#(?<fake>b)\n(?<real>a)", NO, @[@"real"]},
        {@"(?x:#(?<fake>b)\n)(?<real>a)", NO, @[@"real"]},
        {@"(?x:#(?<fake>b)\n)(?<real>a)", YES, @[@"real"]},
        {@"(a(?x)) #(?<after>b)", NO, @[@"after"]},  // (?x) ends with its group
        {@"(?x-x)#(?<last>a)", YES, @[@"last"]},       // the last x of the flags counts
        {[NSString stringWithFormat:@"#comment%@(?<real>a)", ls], YES, @[@"real"]},
        {[NSString stringWithFormat:@"#comment%@(?<real>a)", nel], YES, @[@"real"]},
        {[NSString stringWithFormat:@"#comment%@(?<fake>a)", ps], YES, @[]},  // U+2029 does not end a comment
    };
    for (size_t i = 0; i < sizeof scoped / sizeof scoped[0]; i++) {
        TSRegexFindOptions options = regex | (scoped[i].extended ? TSRegexFindAllowCommentsAndWhitespace : 0);
        NSString *shown = [[scoped[i].pattern stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"] stringByAppendingFormat:@" (x %d)", scoped[i].extended];
        TSRegexFindPattern *found = [[TSRegexFindPattern alloc] initWithFindString:scoped[i].pattern options:options error:NULL];
        Check(found && [found.captureGroupNames isEqualToArray:scoped[i].names],
              [NSString stringWithFormat:@"the named groups of %@: %@", shown, [found.captureGroupNames componentsJoinedByString:@","]]);
        NSRegularExpression *icu = [NSRegularExpression regularExpressionWithPattern:scoped[i].pattern
                                                                             options:scoped[i].extended ? NSRegularExpressionAllowCommentsAndWhitespace : 0 error:NULL];
        NSString *name = scoped[i].names.firstObject ?: @"fake";
        NSTextCheckingResult *match = [icu firstMatchInString:@"#ab" options:0 range:NSMakeRange(0, 3)];
        TSRegexReplacementTemplate *expand = [[TSRegexReplacementTemplate alloc] initWithString:[NSString stringWithFormat:@"\\g<%@>", name]
                                                                                         pattern:found syntax:TSRegexReplacementSyntaxOgreKit];
        NSString *expected = scoped[i].names.count && match ? [@"#ab" substringWithRange:[match rangeWithName:name]] : @"";
        NSString *got = match && found ? [expand replacementForMatchRange:match.range result:match inString:@"#ab" previousMatchEnd:0] : @"";
        Check([got isEqualToString:expected], [NSString stringWithFormat:@"\\g<%@> of %@ gives what ICU's group matched: [%@] (ICU: [%@])", name, shown, got, expected]);
    }

    // The replace field knows only the real groups: \g<b> refers to a name inside a class.
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:@"[(?<b>y)]x" options:regex error:NULL];
    TSAdvancedFindReplacementScanner *replace = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:TSRegexReplacementSyntaxOgreKit options:regex pattern:pattern];
    BOOL flagged = NO;
    for (TSSyntaxDiagnostic *diagnostic in [replace diagnosticsInString:@"<\\g<b>>"])
        flagged = flagged || diagnostic.role == TSSyntaxRoleInvalid;
    Check(pattern && flagged, @"\\g<b> is marked when (?<b> is only inside a class");
    // ... and expanding it gives nothing: the engine no longer asks ICU for a group it does not have (which raises).
    TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:@"<\\g<b>>" pattern:pattern syntax:TSRegexReplacementSyntaxOgreKit];
    NSRegularExpression *icu = [NSRegularExpression regularExpressionWithPattern:@"[(?<b>y)]x" options:0 error:NULL];
    NSTextCheckingResult *match = [icu firstMatchInString:@"yx" options:0 range:NSMakeRange(0, 2)];
    NSString *expanded = nil;
    @try {
        expanded = [template replacementForMatchRange:match.range result:match inString:@"yx" previousMatchEnd:0];
    } @catch (NSException *exception) {
        expanded = [@"exception: " stringByAppendingString:exception.name];
    }
    Check([expanded isEqualToString:@"<>"], [NSString stringWithFormat:@"\\g<b> of a name only inside a class gives nothing (%@)", expanded]);
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
    TSSyntaxColorScheme *scheme = panel.fieldStyle.fieldScheme;
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
    Check([panel.statusField.stringValue isEqualToString:[NSString stringWithFormat:@"%@ %@", hexMessage, more]],
          [NSString stringWithFormat:@"and the message line counts its mark at once (%@)", panel.statusField.stringValue]);
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
    // Without regular expressions, the fields are read as TeX: nothing is marked and the line is empty.
    settings.options = TSRegexFindDefaultOptions;
    [panel optionsDidChange];
    Check(ForegroundAt(find, 1) == nil && UnderlineAt(find, 0) == nil && UnderlineAt(replace, 2) == nil && panel.statusField.stringValue.length == 0,
          @"plain text is read as TeX, without marks or a message");
    Check(ForegroundAt(find, 0) == [scheme attributesForRole:TSSyntaxRoleBracketParen][NSForegroundColorAttributeName]
          && ForegroundAt(replace, 0) == [scheme attributesForRole:TSSyntaxRoleCommand][NSForegroundColorAttributeName],
          @"( is a TeX bracket and \\1 a TeX command");
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
    if ([cell isKindOfClass:[NSTableCellView class]]) // the field, centered in the row
        cell = ((NSTableCellView *)cell).textField;
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

static id CellColor(NSAttributedString *cell, NSUInteger index)
{
    return index < cell.length ? [cell attribute:NSForegroundColorAttributeName atIndex:index effectiveRange:NULL] : nil;
}

static void TestRuleTable(void)
{
    TSMultipleReplaceLibrary *library = nil;
    TSMultipleReplaceWindowController *window = MakeRuleWindow(&library);
    NSColor *quantifier = ThemeColor(LightTheme, RegexKeys()[@(TSSyntaxRoleRegexQuantifier)]);
    NSAttributedString *find = CellText(window, 0, @"find"), *replace = CellText(window, 0, @"replace");
    Check([find.string isEqualToString:@"(\\w+)\\h"] && SameColor(CellColor(find, 3), quantifier)
          && [find attribute:NSUnderlineColorAttributeName atIndex:6 effectiveRange:NULL] != nil, @"a regular expression rule's pattern is colored and \\h marked");
    Check([replace attribute:NSUnderlineColorAttributeName atIndex:0 effectiveRange:NULL] == nil && [replace attribute:NSUnderlineColorAttributeName atIndex:2 effectiveRange:NULL] != nil,
          @"its replacement knows the rule's groups: $2 is marked");
    NSAttributedString *plain = CellText(window, 1, @"find"), *plainReplace = CellText(window, 1, @"replace");
    Check(SameColor(CellColor(plain, 1), NSColor.labelColor) && [plainReplace attribute:NSUnderlineColorAttributeName atIndex:0 effectiveRange:NULL] == nil
          && SameColor(CellColor(plainReplace, 0), ThemeColor(LightTheme, @"SyntaxMarker")) && SameColor(CellColor(plainReplace, 1), NSColor.labelColor),
          @"a plain text rule is read as TeX: + is text and $ the TeX marker");
    Check(SameColor(CellColor(CellText(window, 2, @"find"), 1), NSColor.tertiaryLabelColor), @"a disabled rule is gray, not colored");
    TSRegexMultipleReplace *set = window.ruleTable.set;
    window.ruleTable.set = [[TSRegexMultipleReplace alloc] initWithRules:set.rules textualOptions:set.textualOptions regularExpressionOptions:set.regularExpressionOptions
                                                       replacementSyntax:TSRegexReplacementSyntaxOgreKit];
    NSAttributedString *ogre = CellText(window, 3, @"replace"); // \\section*{$1}
    Check(!SameColor(CellColor(ogre, 11), ThemeColor(LightTheme, RegexKeys()[@(TSSyntaxRoleRegexBackreference)]))
          && SameColor(CellColor(ogre, 0), ThemeColor(LightTheme, RegexKeys()[@(TSSyntaxRoleRegexEscape)])),
          @"with the set's OgreKit syntax, $1 is text and \\\\ an escape");
    [NSFileManager.defaultManager removeItemAtURL:library.directory error:NULL];
}

#pragma mark The theme

static id BackgroundAt(NSTextView *field, NSUInteger index)
{
    return [field.layoutManager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:index effectiveRange:NULL];
}

/// The first index of `part` in the field.
static NSUInteger At(NSTextView *field, NSString *part)
{
    return [field.string rangeOfString:part].location;
}

/// Every role of a pattern and a replacement in the colors of the theme's keys, and both fields in the theme's text,
/// background and insertion point colors, in a light and a dark window.
static void CheckFieldsInTheme(TSAdvancedFindPanelController *panel, NSDictionary *theme, NSString *label)
{
    TSAdvancedFindSettings *settings = panel.findController.settings;
    TSAdvancedFindFieldView *find = (TSAdvancedFindFieldView *)panel.findField, *replace = (TSAdvancedFindFieldView *)panel.replaceField;
    for (TSAdvancedFindFieldView *field in @[find, replace]) {
        Check(SameColor(field.textColor, ThemeColor(theme, @"EditorText")) && SameColor(field.typingAttributes[NSForegroundColorAttributeName], field.textColor)
              && SameColor(field.insertionPointColor, ThemeColor(theme, @"EditorInsertionPoint")) && !field.drawsBackground
              && SameColor(field.box.fillColor, ThemeColor(theme, @"EditorBackground")),
              [NSString stringWithFormat:@"%@: the field's text, insertion point and box take the theme's colors", label]);
        __block CGColorRef fill = NULL;
        [field.box updateLayer];
        fill = field.box.layer.backgroundColor;
        Check(fill && SameColor([NSColor colorWithCGColor:fill], ThemeColor(theme, @"EditorBackground")) && field.box.layer.cornerRadius == 7,
              [NSString stringWithFormat:@"%@: the rounded box is filled with the theme's background", label]);
    }
    // With "Regular expression" on, every role in the color of its key.
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;
    settings.findString = @"^\\\\sec\\{([a-z]*)\\}\\b\\1(?#n)";
    settings.replaceString = @"\\\\textbf{$1}";
    [panel reloadFromSettings];
    RunLoopOnce();
    struct { NSTextView *field; NSString *part; TSSyntaxRole role; } roles[] = {
        {find, @"^", TSSyntaxRoleRegexAnchor}, {find, @"\\\\", TSSyntaxRoleRegexEscape}, {find, @"(", TSSyntaxRoleRegexSymbol},
        {find, @"[a-z]", TSSyntaxRoleRegexCharacterClass}, {find, @"*", TSSyntaxRoleRegexQuantifier}, {find, @"\\b", TSSyntaxRoleRegexAnchor},
        {find, @"\\1", TSSyntaxRoleRegexBackreference}, {find, @"(?#", TSSyntaxRoleComment},
        {replace, @"\\\\", TSSyntaxRoleRegexEscape}, {replace, @"$1", TSSyntaxRoleRegexBackreference},
    };
    for (size_t i = 0; i < sizeof roles / sizeof roles[0]; i++) {
        NSString *key = RegexKeys()[@(roles[i].role)];
        id color = ForegroundAt(roles[i].field, At(roles[i].field, roles[i].part));
        Check(SameColor(color, ThemeColor(theme, key)), [NSString stringWithFormat:@"%@: %@ in the %@ field has the color of %@ (%@)", label, roles[i].part,
                                                         roles[i].field == find ? @"find" : @"replace", key, color]);
    }
    Check(ForegroundAt(find, At(find, @"sec")) == nil && ForegroundAt(replace, At(replace, @"textbf")) == nil, [NSString stringWithFormat:@"%@: literal text keeps the text color", label]);
    // With it off, as the source reads TeX.
    settings.options = TSRegexFindDefaultOptions;
    settings.findString = @"\\section{a} $x$ % note";
    settings.replaceString = @"\\textbf{[1]}";
    [panel optionsDidChange];
    [panel reloadFromSettings];
    RunLoopOnce();
    struct { NSTextView *field; NSString *part; NSString *key; } tex[] = {
        {find, @"\\section", @"SyntaxCommand"}, {find, @"{", @"SyntaxMarkerCurly"}, {find, @"$", @"SyntaxMarker"}, {find, @"% note", @"SyntaxComment"},
        {replace, @"\\textbf", @"SyntaxCommand"}, {replace, @"[", @"SyntaxMarkerSquare"}, {replace, @"}", @"SyntaxMarkerCurly"},
    };
    for (size_t i = 0; i < sizeof tex / sizeof tex[0]; i++) {
        id color = ForegroundAt(tex[i].field, At(tex[i].field, tex[i].part));
        Check(SameColor(color, ThemeColor(theme, tex[i].key)), [NSString stringWithFormat:@"%@: TeX %@ in the %@ field has the color of %@ (%@)", label, tex[i].part,
                                                                tex[i].field == find ? @"find" : @"replace", tex[i].key, color]);
    }
    Check(!find.bracketScanner && ForegroundAt(find, At(find, @"a")) == nil, [NSString stringWithFormat:@"%@: TeX text keeps the text color", label]);
}

static CGGlyph Glyph(NSFont *font, unichar character)
{
    CGGlyph glyph = 0;
    CTFontGetGlyphsForCharacters((__bridge CTFontRef)font, &character, &glyph, 1);
    return glyph;
}

/// Whether the middle of the glyph's ink is inked.
static BOOL MiddleInked(NSFont *font, unichar character)
{
    CGGlyph glyph = Glyph(font, character);
    NSRect ink = [font boundingRectForCGGlyph:glyph];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSZeroPoint];
    [path appendBezierPathWithCGGlyph:glyph inFont:font];
    return [path containsPoint:NSMakePoint(NSMidX(ink), NSMidY(ink))];
}

/// | is a thin bar while l has a foot or a hook (its ink is at least three times as wide), and 0 is slashed or dotted
/// (its middle is inked) while O is not.
static BOOL GlyphsTellApart(NSFont *font)
{
    CGFloat bar = NSWidth([font boundingRectForCGGlyph:Glyph(font, '|')]), ell = NSWidth([font boundingRectForCGGlyph:Glyph(font, 'l')]);
    return ell >= 3 * bar && MiddleInked(font, '0') && !MiddleInked(font, 'O');
}

static void TestThemedFields(void)
{
    TSAdvancedFindController *controller = MakeController();
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    TSAdvancedFindFieldView *find = (TSAdvancedFindFieldView *)panel.findField;
    CheckFieldsInTheme(panel, LightTheme, @"light Solarized");
    Check(panel.findBox.appearance && !TSAdvancedFindAppearanceIsDark(panel.findBox.appearance), @"a light background gives the box a light appearance");

    // The window turns dark: the dark theme, at once.
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    CheckFieldsInTheme(panel, DarkTheme, @"dark (application)");
    Check(TSAdvancedFindAppearanceIsDark(panel.findBox.appearance), @"a dark background gives the box a dark appearance");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    CheckFieldsInTheme(panel, LightTheme, @"light again");
    panel.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    CheckFieldsInTheme(panel, DarkTheme, @"dark (window)");
    panel.window.appearance = nil;

    // Another theme in Settings.
    NSDictionary *solarized = LightTheme;
    LightTheme = Theme(@"LiteTheme");
    [TSAdvancedFindFieldStyle styleDidChange];
    CheckFieldsInTheme(panel, LightTheme, @"another light theme");
    // A dark theme for light windows: the box's buttons, status and marks are those of a dark background.
    LightTheme = Theme(@"Dracula");
    [TSAdvancedFindFieldStyle styleDidChange];
    CheckFieldsInTheme(panel, LightTheme, @"a dark theme in a light window");
    Check(TSAdvancedFindAppearanceIsDark(panel.findBox.appearance) && TSAdvancedFindAppearanceIsDark(panel.replaceBox.appearance)
          && !TSAdvancedFindAppearanceIsDark(panel.window.effectiveAppearance), @"the boxes of a dark theme are dark in a light window");
    LightTheme = solarized;

    // Syntax coloring off: no colors and no fullwidth backgrounds, but the theme's text and background; errors are
    // still marked.
    ColorsSyntax = NO;
    [TSAdvancedFindFieldStyle styleDidChange];
    TSAdvancedFindSettings *settings = controller.settings;
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"(a)+\\1\\h[a]";
    settings.replaceString = @"$1$5";
    [panel reloadFromSettings];
    BOOL colorless = YES;
    for (NSTextView *field in @[panel.findField, panel.replaceField])
        for (NSUInteger i = 0; i < field.string.length; i++) {
            id color = ForegroundAt(field, i);
            BOOL mark = UnderlineAt(field, i) != nil;
            colorless = colorless && (color == nil || mark) && BackgroundAt(field, i) == nil;
        }
    Check(colorless && UnderlineAt(find, At(find, @"\\h")) && UnderlineAt(panel.replaceField, 2), @"coloring off: only the marks of errors are left in a regular expression");
    settings.options = TSRegexFindDefaultOptions;
    settings.findString = @"\\section{a}$ %c Ａ";
    [panel optionsDidChange];
    [panel reloadFromSettings];
    colorless = YES;
    for (NSUInteger i = 0; i < find.string.length; i++)
        colorless = colorless && ForegroundAt(find, i) == nil && BackgroundAt(find, i) == nil && UnderlineAt(find, i) == nil;
    Check(colorless && SameColor(find.textColor, ThemeColor(LightTheme, @"EditorText")) && SameColor(panel.findBox.fillColor, ThemeColor(LightTheme, @"EditorBackground")),
          @"coloring off: TeX is plain, in the theme's text and background colors");
    ColorsSyntax = YES;
    [TSAdvancedFindFieldStyle styleDidChange];
    Check(SameColor(ForegroundAt(find, 0), ThemeColor(LightTheme, @"SyntaxCommand")), @"coloring on again colors at once");

    // The system's monospaced font at the size of the source font, kept between 11 and 16 points, whatever the source
    // font is: | and l, 0 and O look different, as they do not in Helvetica, the factory source font.
    struct { CGFloat size; CGFloat shown; } sizes[] = {{13, 13}, {24, 16}, {8, 11}, {16, 16}, {11, 11}};
    NSString *monospaced = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular].fontName;
    for (NSString *source in @[@"Helvetica", @"Menlo-Regular", @"HiraginoSans-W3"]) {
        for (size_t i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
            SourceFont = [NSFont fontWithName:source size:sizes[i].size] ?: [NSFont userFontOfSize:sizes[i].size];
            [TSAdvancedFindFieldStyle styleDidChange];
            for (NSTextView *field in @[panel.findField, panel.replaceField])
                Check([field.font.fontName isEqualToString:monospaced] && field.font.pointSize == sizes[i].shown
                      && [field.typingAttributes[NSFontAttributeName] isEqual:field.font],
                      [NSString stringWithFormat:@"a %@ source font of %.0f points gives the monospaced font of %.0f points (%@ %.1f)", source, sizes[i].size,
                       sizes[i].shown, field.font.fontName, field.font.pointSize]);
        }
    }
    Check(GlyphsTellApart(find.font) && !GlyphsTellApart([NSFont fontWithName:@"Helvetica" size:find.font.pointSize]),
          [NSString stringWithFormat:@"| and l, 0 and O look different in the fields (%@), as they do not in Helvetica", find.font.fontName]);
    SourceFont = nil;
    [TSAdvancedFindFieldStyle styleDidChange];
    Check(find.font.pointSize == NSFont.systemFontSize + 1 && [find.font.fontName isEqualToString:monospaced], @"without a source font, the monospaced font of 14 points");

    // Without the application's provider (as in the other tests), the fields are those of a text field.
    TSAdvancedFindFieldStyle *(^provider)(BOOL) = TSAdvancedFindFieldStyle.provider;
    TSAdvancedFindFieldStyle.provider = nil;
    [TSAdvancedFindFieldStyle styleDidChange];
    Check(SameColor(find.textColor, NSColor.textColor) && panel.findBox.fillColor == nil && panel.findBox.appearance == nil, @"no provider: the look of a text field");
    TSAdvancedFindFieldStyle.provider = provider;
    [TSAdvancedFindFieldStyle styleDidChange];
}

static void TestThemedRules(void)
{
    TSMultipleReplaceLibrary *library = nil;
    TSMultipleReplaceWindowController *window = MakeRuleWindow(&library);
    TSRegexMultipleReplace *set = window.ruleTable.set;
    window.ruleTable.set = [[TSRegexMultipleReplace alloc] initWithRules:[set.rules arrayByAddingObject:Rule(@"\\section{a} % b", @"\\emph{$1}", NO, YES)]
                                                          textualOptions:set.textualOptions regularExpressionOptions:set.regularExpressionOptions
                                                       replacementSyntax:set.replacementSyntax];
    NSInteger tex = (NSInteger)window.ruleTable.set.rules.count - 1;
    void (^check)(NSDictionary *, NSString *) = ^(NSDictionary *theme, NSString *label) {
        NSAttributedString *regex = CellText(window, 4, @"find"), *replace = CellText(window, 4, @"replace"); // \\section{(.*)} and \\section*{$1}
        NSAttributedString *plain = CellText(window, tex, @"find"), *plainReplace = CellText(window, tex, @"replace");
        Check(SameColor(CellColor(regex, 0), ThemeColor(theme, RegexKeys()[@(TSSyntaxRoleRegexEscape)]))
              && SameColor(CellColor(regex, 10), ThemeColor(theme, RegexKeys()[@(TSSyntaxRoleRegexSymbol)]))
              && SameColor(CellColor(regex, 11), ThemeColor(theme, RegexKeys()[@(TSSyntaxRoleRegexCharacterClass)]))
              && SameColor(CellColor(regex, 12), ThemeColor(theme, RegexKeys()[@(TSSyntaxRoleRegexQuantifier)]))
              && SameColor(CellColor(replace, 11), ThemeColor(theme, RegexKeys()[@(TSSyntaxRoleRegexBackreference)])),
              [NSString stringWithFormat:@"%@: a regular expression rule in the theme's colors", label]);
        Check(SameColor(CellColor(plain, 0), ThemeColor(theme, @"SyntaxCommand")) && SameColor(CellColor(plain, 8), ThemeColor(theme, @"SyntaxMarkerCurly"))
              && SameColor(CellColor(plain, 12), ThemeColor(theme, @"SyntaxComment")) && SameColor(CellColor(plain, 9), NSColor.labelColor)
              && SameColor(CellColor(plainReplace, 0), ThemeColor(theme, @"SyntaxCommand")) && SameColor(CellColor(plainReplace, 6), ThemeColor(theme, @"SyntaxMarker")),
              [NSString stringWithFormat:@"%@: a plain rule read as TeX in the theme's colors", label]);
    };
    check(LightTheme, @"rules, light");
    // The find and replacement cells are monospaced too.
    for (NSString *column in @[@"find", @"replace"]) {
        NSFont *font = [CellText(window, tex, column) attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        Check([font.fontName isEqualToString:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular].fontName] && GlyphsTellApart(font),
              [NSString stringWithFormat:@"the %@ cells of the rules are monospaced (%@)", column, font.fontName]);
    }
    // The cells shown in the table are made again when the appearance or the theme changes.
    NSTableView *table = window.ruleTable.tableView;
    [window.window.contentView layoutSubtreeIfNeeded];
    NSInteger findColumn = [table columnWithIdentifier:@"find"];
    NSAttributedString *(^shown)(NSInteger) = ^NSAttributedString *(NSInteger row) {
        NSView *cell = [table viewAtColumn:findColumn row:row makeIfNecessary:NO];
        NSTextField *field = [cell isKindOfClass:[NSTableCellView class]] ? ((NSTableCellView *)cell).textField : (NSTextField *)cell;
        return [field isKindOfClass:[NSTextField class]] ? field.attributedStringValue : [NSAttributedString new];
    };
    Check(SameColor(CellColor(shown(tex), 0), ThemeColor(LightTheme, @"SyntaxCommand")), @"the table shows the TeX rule in the light theme");
    // The cells follow the window's appearance and the theme.
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    check(DarkTheme, @"rules, dark");
    Check(SameColor(CellColor(shown(tex), 0), ThemeColor(DarkTheme, @"SyntaxCommand")), @"the table shows the TeX rule in the dark theme at once");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSDictionary *solarized = LightTheme;
    LightTheme = Theme(@"LiteTheme");
    [TSAdvancedFindFieldStyle styleDidChange];
    check(LightTheme, @"rules, another theme");
    Check(SameColor(CellColor(shown(tex), 0), ThemeColor(LightTheme, @"SyntaxCommand")) && SameColor(CellColor(shown(4), 12), ThemeColor(LightTheme, @"SyntaxMarker")),
          @"the table shows the rules in another theme at once");
    LightTheme = solarized;
    [TSAdvancedFindFieldStyle styleDidChange];
    ColorsSyntax = NO;
    [TSAdvancedFindFieldStyle styleDidChange];
    NSAttributedString *off = CellText(window, tex, @"find");
    Check(SameColor(CellColor(off, 0), NSColor.labelColor) && SameColor(CellColor(CellText(window, 4, @"find"), 0), NSColor.labelColor),
          @"rules with coloring off are plain");
    ColorsSyntax = YES;
    [TSAdvancedFindFieldStyle styleDidChange];
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

/// The panel with a TeX pattern read as a regular expression and as TeX, with every role of a regular expression, and
/// the rules, in the bundled themes of a light and a dark window.
static void WriteImages(NSString *directory, NSString *language)
{
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *light = LightTheme, *dark = DarkTheme;
    // The source font of the factory settings (TSAppDelegate.m: the user font of 12 points, Helvetica): the fields show
    // the monospaced font at its size.
    SourceFont = [NSFont userFontOfSize:12];
    NSArray<NSArray<NSString *> *> *pairs = @[@[@"SolarizedLite", @"SolarizedDark"], @[@"LiteTheme", @"DarkTheme"], @[@"GLG-Lite", @"Dracula"],
                                                       @[@"TransparentTheme", @"PreTeXt-Dark"]];
    for (NSArray<NSString *> *pair in pairs) {
        LightTheme = Theme(pair[0]);
        DarkTheme = Theme(pair[1]);
        TSAdvancedFindController *controller = MakeController();
        TSAdvancedFindSettings *settings = controller.settings;
        TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
        TSMultipleReplaceLibrary *library = nil;
        TSMultipleReplaceWindowController *rules = MakeRuleWindow(&library);
        TSRegexMultipleReplace *set = rules.ruleTable.set;
        rules.ruleTable.set = [[TSRegexMultipleReplace alloc] initWithRules:[set.rules arrayByAddingObject:Rule(@"\\section{a} % b", @"\\emph{$1}", NO, YES)]
                                                             textualOptions:set.textualOptions regularExpressionOptions:set.regularExpressionOptions
                                                          replacementSyntax:set.replacementSyntax];
        for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:name];
            BOOL isDark = [name isEqualToString:NSAppearanceNameDarkAqua];
            NSString *base = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-%@", language, isDark ? pair[1] : pair[0], isDark ? @"dark" : @"light"]];
            // Windows that are never shown do not follow the application's appearance by themselves.
            NSApp.appearance = appearance;
            panel.window.appearance = appearance;
            rules.window.appearance = appearance;
            struct { NSString *name; BOOL regex; NSString *find; NSString *replace; } shots[] = {
                {@"regex", YES, @"\\section{(.*)}", @"\\\\textbf{$1}"},
                {@"tex", NO, @"\\section{(.*)}", @"\\\\textbf{$1}"},
                {@"roles", YES, @"^\\\\(bf|it)\\b\\s+([^}]*)\\}|\\d{4}+\\h(?#note)", @"\\\\text$1{$2}$3\\n"},
            };
            for (size_t i = 0; i < sizeof shots / sizeof shots[0]; i++) {
                settings.options = TSRegexFindDefaultOptions | (shots[i].regex ? TSRegexFindRegularExpression : 0);
                settings.replacementSyntax = TSRegexReplacementSyntaxICU;
                settings.findString = shots[i].find;
                settings.replaceString = shots[i].replace;
                [panel optionsDidChange];
                [panel reloadFromSettings];
                RunLoopOnce();
                Check(WritePNG(panel.window.contentView, appearance, [base stringByAppendingFormat:@"-panel-%@.png", shots[i].name]), @"panel image written");
            }
            [rules.ruleTable.tableView reloadData];
            Check(WritePNG(rules.window.contentView, appearance, [base stringByAppendingString:@"-rules.png"]), @"rules image written");
        }
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [NSFileManager.defaultManager removeItemAtURL:library.directory error:NULL];
    }
    LightTheme = light;
    DarkTheme = dark;
    SourceFont = nil;
}

#pragma mark Main

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        LightTheme = Theme(@"SolarizedLite");
        DarkTheme = Theme(@"DarkTheme");
        InstallProvider();
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
            TestThemedFields();
            TestThemedRules();
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
