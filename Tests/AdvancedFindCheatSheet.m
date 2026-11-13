// SPDX-License-Identifier: GPL-2.0-or-later
// The regular expression cheat sheet of the Advanced Find panel and the engine's one table of differences from
// OgreKit: what the table says holds in ICU, the "?" and the sheet's pages, tabs, size, replacement syntax and
// layout, in the current language. Built by Tests/run-advanced-find-cheat-sheet.py; no window is ever shown and the
// defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSRegexOnigmoIncompatibility.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

static NSString *Language(void)
{
    return NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
}

#pragma mark The table

static TSRegexFindPattern *Compiled(NSString *pattern)
{
    return [[TSRegexFindPattern alloc] initWithFindString:pattern options:TSRegexFindDefaultOptions | TSRegexFindRegularExpression error:NULL];
}

/// The ranges of the matches of `pattern` in `text`, as "location+length" separated by spaces; nil when it does not compile.
static NSString *_Nullable Matches(NSString *pattern, NSString *text)
{
    TSRegexFindPattern *compiled = Compiled(pattern);
    if (!compiled)
        return nil;
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    [compiled enumerateMatchesInString:text range:NSMakeRange(0, text.length) cancellation:nil
                            usingBlock:^(NSRange range, NSTextCheckingResult *result, BOOL *stop) {
        [matches addObject:[NSString stringWithFormat:@"%lu+%lu", (unsigned long)range.location, (unsigned long)range.length]];
    }];
    return [matches componentsJoinedByString:@" "];
}

static void TestTable(void)
{
    NSArray<TSRegexOnigmoIncompatibility *> *entries = TSRegexFindPattern.onigmoIncompatibilities;
    NSMutableSet<NSNumber *> *kinds = [NSMutableSet set];
    NSMutableSet<NSString *> *terms = [NSMutableSet set], *messages = [NSMutableSet set];
    NSUInteger marked = 0;
    for (TSRegexOnigmoIncompatibility *entry in entries) {
        [kinds addObject:@(entry.kind)];
        [terms addObject:entry.term];
        [messages addObject:entry.message];
        marked += entry.isMarked ? 1 : 0;
        Check([TSRegexFindPattern onigmoIncompatibilityOfKind:entry.kind] == entry, [NSString stringWithFormat:@"%@ is found by its kind", entry.term]);
    }
    Check(entries.count == 10 && kinds.count == 10 && terms.count == 10 && messages.count == 10 && marked == 7,
          @"the table has 10 differences of their own kinds, terms and messages: 7 marked in the find field, 3 explained only");
    Check(entries.firstObject.kind == TSRegexOnigmoIncompatibilityUnicodeClasses && !entries.firstObject.isMarked,
          @"the everyday \\d \\w \\s \\b come first and are not marked");
    for (TSRegexOnigmoIncompatibilityKind kind = TSRegexOnigmoIncompatibilityHexDigit; kind <= TSRegexOnigmoIncompatibilityLiteralBrace; kind++)
        Check([TSRegexFindPattern onigmoIncompatibilityOfKind:kind].isMarked, [NSString stringWithFormat:@"difference %ld is marked", (long)kind]);

    // The messages are in this language's AdvancedFindEngine.strings, not the English of the code.
    NSString *english = [NSBundle.mainBundle pathForResource:@"AdvancedFindEngine" ofType:@"strings" inDirectory:nil forLocalization:@"en"];
    NSDictionary<NSString *, NSString *> *englishTable = english ? [NSDictionary dictionaryWithContentsOfFile:english] : nil;
    Check(englishTable.count >= 15, @"the English table of the engine is in the bundle");
    for (TSRegexOnigmoIncompatibility *entry in entries) {
        BOOL inEnglish = [englishTable.allValues containsObject:entry.message];
        Check([Language() isEqualToString:@"en"] ? inEnglish : !inEnglish,
              [NSString stringWithFormat:@"%@: the message is %@: %@", entry.term, [Language() isEqualToString:@"en"] ? @"English" : @"translated", entry.message]);
    }

    // What the table and the cheat sheet say holds in ICU, through the engine.
    Check([Matches(@"\\h", @"a b\tc") isEqualToString:@"1+1 3+1"], @"\\h is a horizontal space, not a hexadecimal digit");
    Check([Matches(@"(?m)^b", @"a\nb") isEqualToString:@"2+1"] && [Matches(@"(?m)a.b", @"a\nb") isEqualToString:@""]
          && [Matches(@"(?s)a.b", @"a\nb") isEqualToString:@"0+3"], @"(?m) makes ^ match at each line; (?s) makes . match a line break");
    Check([Matches(@"a{2}+", @"aaaa") isEqualToString:@"0+2 2+2"], @"{n}+ is possessive, not a repeated repetition");
    Check([Matches(@"a\\Kb", @"ab") isEqualToString:@""], @"\\K matches nothing");
    Check([Matches(@"(a)\\g<1>", @"aa") isEqualToString:@""], @"\\g<1> calls nothing");
    Check(!Compiled(@"(?~a)"), @"(?~…) is an error");
    Check(!Compiled(@"a}") && !Compiled(@"{a") && Compiled(@"\\{a\\}"), @"a brace by itself is an error, \\{ \\} are braces");
    Check([Matches(@"\\d", @"5５") isEqualToString:@"0+1 1+1"] && [Matches(@"\\w", @"漢か") isEqualToString:@"0+1 1+1"]
          && [Matches(@"\\s", @"　") isEqualToString:@"0+1"] && [Matches(@"\\b", @"漢字") isEqualToString:@"0+0 2+0"],
          @"\\d \\w \\s \\b have their Unicode meaning");
    Check(Compiled(@"(?<x>a)(b)").numberOfCaptureGroups == 2, @"a named group is numbered too");
    Check(!Compiled(@"\\p{^L}") && Compiled(@"\\P{L}"), @"\\p{^…} is an error, \\P{…} is not");
    Check(!Compiled(@"a{,2}") && [Matches(@"a{0,2}", @"aaa") isEqualToString:@"0+2 2+1 3+0"], @"{,n} is an error, {0,n} is not");
    Check([Matches(@"\\R", @"a\r\nb\rc") isEqualToString:@"1+2 4+1"], @"\\R is one line break, CR LF included");
    Check([Matches(@"\\p{Han}", @"a漢か") isEqualToString:@"1+1"], @"\\p{Han} is a kanji");
}

#pragma mark The sheet

/// The monospaced terms and the descriptions shown (not hidden), in order.
static NSArray<NSTextField *> *VisibleLabels(NSView *root)
{
    NSMutableArray<NSTextField *> *labels = [NSMutableArray array];
    NSMutableArray<NSView *> *pending = [root.subviews mutableCopy];
    while (pending.count) {
        NSView *view = pending.firstObject;
        [pending removeObjectAtIndex:0];
        if (view.isHiddenOrHasHiddenAncestor)
            continue;
        if ([view isKindOfClass:[NSTextField class]])
            [labels addObject:(NSTextField *)view];
        [pending insertObjects:view.subviews atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, view.subviews.count)]];
    }
    return labels;
}

static BOOL IsTerm(NSTextField *label)
{
    return [label.font.fontName.lowercaseString containsString:@"mono"];
}

static NSString *VisibleTerms(NSView *root)
{
    NSMutableArray<NSString *> *terms = [NSMutableArray array];
    for (NSTextField *label in VisibleLabels(root))
        if (IsTerm(label))
            [terms addObject:label.stringValue];
    return [@" " stringByAppendingString:[[terms componentsJoinedByString:@" "] stringByAppendingString:@" "]];
}

static BOOL Shows(NSView *root, NSString *term)
{
    return [VisibleTerms(root) containsString:[NSString stringWithFormat:@" %@ ", term]];
}

static NSSegmentedControl *_Nullable Tabs(TSAdvancedFindCheatSheet *sheet)
{
    for (NSView *view in sheet.view.subviews)
        if ([view isKindOfClass:[NSSegmentedControl class]])
            return (NSSegmentedControl *)view;
    return nil;
}

static void Click(NSSegmentedControl *tabs, NSInteger segment)
{
    tabs.selectedSegment = segment;
    [tabs sendAction:tabs.action to:tabs.target];
}

/// A label shows all of its text: one line wide enough, or lines that wrap within its height.
static int CheckLabelFits(NSTextField *label, NSString *name)
{
    NSString *text = label.stringValue;
    if (text.length == 0)
        return 0;
    NSSize frame = label.frame.size;
    NSCell *cell = label.cell;
    BOOL wraps = !cell.usesSingleLineMode && (cell.lineBreakMode == NSLineBreakByWordWrapping || cell.lineBreakMode == NSLineBreakByCharWrapping);
    BOOL cut = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, frame.width, CGFLOAT_MAX)].height > frame.height + 0.5
                     : cell.cellSize.width > frame.width + 0.5;
    if (cut)
        printf("FAIL %s: label cut: %s (%.1f×%.1f, needs %.1f wide or %.1f high)\n", name.UTF8String, text.UTF8String, frame.width, frame.height,
               cell.cellSize.width, [cell cellSizeForBounds:NSMakeRect(0, 0, frame.width, CGFLOAT_MAX)].height);
    return cut ? 1 : 0;
}

/// Every control shown inside the view, at least `inset` points from its right edge, with all its text.
static int CheckLayout(NSView *root, NSString *name, CGFloat inset)
{
    int count = 0;
    NSMutableArray<NSView *> *pending = [root.subviews mutableCopy];
    while (pending.count) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:v.subviews];
        if (![v isKindOfClass:[NSControl class]] || v.isHiddenOrHasHiddenAncestor)
            continue;
        NSRect frame = [v convertRect:v.bounds toView:root];
        NSString *title = [v isKindOfClass:[NSTextField class]] ? ((NSTextField *)v).stringValue
                        : [v isKindOfClass:[NSButton class]] ? ((NSButton *)v).title : NSStringFromClass(v.class);
        if (NSMaxX(frame) > NSMaxX(root.bounds) - inset + 0.5 || !NSContainsRect(NSInsetRect(root.bounds, -0.5, -0.5), frame)) {
            printf("FAIL %s: not inside with a %.0f-point inset: %s %s in %s\n", name.UTF8String, inset, title.UTF8String,
                   NSStringFromRect(frame).UTF8String, NSStringFromRect(root.bounds).UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSTextField class]])
            count += CheckLabelFits((NSTextField *)v, name);
        else if (v.frame.size.width + 0.5 < v.fittingSize.width) {
            printf("FAIL %s: cut: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
    }
    return count;
}

/// Windows that are never shown do not draw their controls: each bordered button's and segmented control's own
/// cell is drawn at its frame. Popover glass is not reproduced.
static BOOL WritePNG(NSView *view, NSAppearance *appearance, NSString *path)
{
    __block BOOL written = NO;
    [appearance performAsCurrentDrawingAppearance:^{
        [view layoutSubtreeIfNeeded];
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
            BOOL drawn = [v isKindOfClass:[NSSegmentedControl class]] || ([v isKindOfClass:[NSButton class]] && ((NSButton *)v).isBordered);
            if (!drawn || v.isHiddenOrHasHiddenAncestor)
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

static void TestSheet(NSString *_Nullable imageDirectory)
{
    NSString *language = Language();
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    TSAdvancedFindController *controller = [[TSAdvancedFindController alloc] initWithSettings:settings];
    controller.beepHandler = ^{};
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    [panel.window.contentView layoutSubtreeIfNeeded];

    // The "?" sits right after "Regular expression", in the mini size.
    NSButton *help = panel.cheatSheetButton;
    NSRect regexFrame = [panel.regexBox convertRect:panel.regexBox.bounds toView:nil];
    NSRect helpFrame = [help convertRect:help.bounds toView:nil];
    Check(help.bezelStyle == NSBezelStyleHelpButton && help.controlSize == NSControlSizeMini && help.target == panel && help.action == @selector(showCheatSheet:)
          && help.toolTip.length > 0 && help.accessibilityLabel.length > 0 && !help.isHiddenOrHasHiddenAncestor
          && NSMinX(helpFrame) >= NSMaxX(regexFrame) && NSMinX(helpFrame) - NSMaxX(regexFrame) <= 8 && fabs(NSMidY(helpFrame) - NSMidY(regexFrame)) <= 2,
          [NSString stringWithFormat:@"the ? is a mini help button right after Regular expression (%@ after %@)",
           NSStringFromRect(helpFrame), NSStringFromRect(regexFrame)]);
    // The options that follow keep their places, 16 points apart, instead of being pushed to the right.
    NSRect caseFrame = [panel.ignoreCaseBox convertRect:panel.ignoreCaseBox.bounds toView:nil];
    Check(NSMinX(caseFrame) - NSMaxX(helpFrame) <= 20, [NSString stringWithFormat:@"Ignore case follows the ? (%@ after %@)",
                                                         NSStringFromRect(caseFrame), NSStringFromRect(helpFrame)]);

    // The content: the everyday syntax, the selected replacement syntax, and every difference of the engine's table.
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;
    TSAdvancedFindCheatSheet *sheet = [panel makeCheatSheet];
    NSArray<NSString *> *terms = sheet.terms;
    for (NSString *term in @[@".", @"\\R", @"\\w", @"\\d", @"\\p{Han}", @"^", @"\\b", @"{n,m}", @"{0,n}", @"(?<name>…)", @"(?<=…) (?<!…)", @"$0", @"$1", @"\\$", @"\\\\"])
        Check([terms containsObject:term], [NSString stringWithFormat:@"the cheat sheet has %@", term]);
    for (TSRegexOnigmoIncompatibility *entry in TSRegexFindPattern.onigmoIncompatibilities)
        Check([terms containsObject:entry.term], [NSString stringWithFormat:@"the cheat sheet lists the difference %@", entry.term]);
    Check(![terms containsObject:@"\\0 \\&"], @"the ICU sheet has no OgreKit replacement");

    // Three pages under tabs, in one room: the find page first; a tab shows its page only; the size stays.
    NSSegmentedControl *tabs = Tabs(sheet);
    NSView *view = sheet.view;
    NSSize size = sheet.preferredContentSize;
    Check(tabs.segmentCount == 3 && tabs.selectedSegment == 0 && sheet.selectedPage == 0 && Shows(view, @"{n,m}")
          && !Shows(view, @"$1") && !Shows(view, @"\\h"), @"the sheet opens on the find page alone");
    Click(tabs, 2);
    Check(sheet.selectedPage == 2 && Shows(view, @"\\h") && !Shows(view, @"{n,m}") && !Shows(view, @"$1"), @"the third tab shows the differences alone");
    // The descriptions of the differences are the engine's messages, in the table's order.
    NSMutableArray<NSString *> *descriptions = [NSMutableArray array], *expected = [NSMutableArray array];
    for (NSTextField *label in VisibleLabels(view))
        if (!IsTerm(label) && [label.identifier isEqualToString:@"section"] == NO && label.cell.wraps)
            [descriptions addObject:label.stringValue];
    for (TSRegexOnigmoIncompatibility *entry in TSRegexFindPattern.onigmoIncompatibilities)
        [expected addObject:entry.message];
    Check([descriptions isEqualToArray:expected], [NSString stringWithFormat:@"the differences page says what the engine's table says (%@)", descriptions]);
    Click(tabs, 1);
    Check(sheet.selectedPage == 1 && Shows(view, @"$1") && !Shows(view, @"{n,m}") && !Shows(view, @"\\h"), @"the second tab shows the replacement alone");
    [sheet fitToContent];
    Check(NSEqualSizes(size, sheet.preferredContentSize), [NSString stringWithFormat:@"the size stays when the tab changes (%@, %@)",
                                                            NSStringFromSize(size), NSStringFromSize(sheet.preferredContentSize)]);
    Check(size.width <= 620 && size.height <= 480, [NSString stringWithFormat:@"the sheet is small (%@)", NSStringFromSize(size)]);
    printf("cheat sheet %s: %.0f×%.0f\n", language.UTF8String, size.width, size.height);
    [sheet selectPage:0];

    // Shown in the popover's appearance, the sheet is measured again, and the popover takes that size, whatever
    // was done to the view before.
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        TSAdvancedFindCheatSheet *shown = [panel makeCheatSheet];
        Check(NSEqualSizes(shown.preferredContentSize, size), [NSString stringWithFormat:@"every sheet has the same size (%@, %@)",
                                                                NSStringFromSize(shown.preferredContentSize), NSStringFromSize(size)]);
        shown.view.appearance = [NSAppearance appearanceNamed:name];
        [shown.view setFrameSize:NSMakeSize(300, 200)];
        shown.preferredContentSize = NSMakeSize(300, 200);
        [shown viewWillAppear];
        [shown.view layoutSubtreeIfNeeded];
        Check(NSEqualSizes(shown.preferredContentSize, shown.view.fittingSize) && NSEqualSizes(shown.preferredContentSize, shown.view.frame.size),
              [NSString stringWithFormat:@"the sheet is measured again when shown in %@ (%@, %@ needed)", name,
               NSStringFromSize(shown.preferredContentSize), NSStringFromSize(shown.view.fittingSize)]);
    }

    // The replacement part follows the setting while the sheet is open (as a popover or dragged off).
    NSPopover *popover = [NSPopover new];
    popover.contentViewController = sheet;
    panel.cheatSheetPopover = popover;
    settings.replacementSyntax = TSRegexReplacementSyntaxOgreKit;
    [panel reloadFromSettings];
    Check([sheet.terms containsObject:@"\\0 \\&"] && [sheet.terms containsObject:@"\\g<name>"] && ![sheet.terms containsObject:@"\\$"]
          && sheet.terms.count == terms.count + 1, @"the sheet shows the OgreKit replacement after the setting changes");
    Check(sheet.selectedPage == 0 && Shows(view, @"{n,m}") && !Shows(view, @"\\0 \\&"), @"changing the syntax keeps the page that is shown");
    // From the More Options popover as well.
    NSView *options = [panel makeOptionsViewController].view;
    NSPopUpButton *syntax = nil;
    NSMutableArray<NSView *> *pending = [options.subviews mutableCopy];
    while (pending.count) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSPopUpButton class]])
            syntax = (NSPopUpButton *)v;
    }
    [syntax selectItemAtIndex:0];
    [syntax sendAction:syntax.action to:syntax.target];
    Check(settings.replacementSyntax == TSRegexReplacementSyntaxICU && [sheet.terms containsObject:@"\\$"] && ![sheet.terms containsObject:@"\\0 \\&"],
          @"choosing the ICU syntax in More Options changes the open sheet");
    Check([panel popoverShouldDetach:popover] && ![panel popoverShouldDetach:[NSPopover new]], @"the cheat sheet can be dragged off; other popovers cannot");
    panel.cheatSheetPopover = nil;
    Check([TSAdvancedFindCheatSheet.icuGuideURL.absoluteString isEqualToString:@"https://unicode-org.github.io/icu/userguide/strings/regexp.html"],
          @"the link goes to ICU's user guide on regular expressions");

    // Layout: every page of both syntaxes, light and dark, inside the sheet with a 16-point inset and nothing cut.
    for (NSNumber *style in @[@(TSRegexReplacementSyntaxICU), @(TSRegexReplacementSyntaxOgreKit)]) {
        settings.replacementSyntax = style.integerValue;
        for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            TSAdvancedFindCheatSheet *laid = [panel makeCheatSheet];
            laid.view.appearance = [NSAppearance appearanceNamed:name];
            [laid viewWillAppear];
            for (NSInteger page = 0; page < 3; page++) {
                [laid selectPage:page];
                NSString *what = [NSString stringWithFormat:@"%@ %@ %@ page %ld", language, name, style.integerValue ? @"OgreKit" : @"ICU", (long)page];
                failures += CheckLayout(laid.view, what, 16);
                // A short description is not wrapped for nothing: every column has room for 150 points.
                for (NSTextField *label in VisibleLabels(laid.view)) {
                    NSTextField *oneLine = [NSTextField labelWithString:label.stringValue];
                    oneLine.font = label.font;
                    NSSize line = oneLine.fittingSize;
                    if (label.cell.wraps && line.width <= 150 && label.frame.size.height > line.height + 0.5) {
                        printf("FAIL %s: wrapped for nothing: %s\n", what.UTF8String, label.stringValue.UTF8String);
                        failures++;
                    }
                }
            }
        }
    }
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;
    Check(!panel.window.isVisible, @"the panel is never shown");

    if (!imageDirectory)
        return;
    [NSFileManager.defaultManager createDirectoryAtPath:imageDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:name];
        NSString *base = [imageDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-cheat-sheet", language,
                                                                         [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark"]];
        struct { TSRegexReplacementSyntax syntax; NSInteger page; NSString *suffix; } shots[] = {
            {TSRegexReplacementSyntaxICU, 0, @""}, {TSRegexReplacementSyntaxICU, 1, @"-replace"},
            {TSRegexReplacementSyntaxOgreKit, 1, @"-replace-ogrekit"}, {TSRegexReplacementSyntaxICU, 2, @"-differences"},
        };
        for (size_t i = 0; i < sizeof shots / sizeof shots[0]; i++) {
            settings.replacementSyntax = shots[i].syntax;
            TSAdvancedFindCheatSheet *drawn = [panel makeCheatSheet];
            drawn.view.appearance = appearance;
            [drawn viewWillAppear];
            [drawn selectPage:shots[i].page];
            Check(WritePNG(drawn.view, appearance, [NSString stringWithFormat:@"%@%@.png", base, shots[i].suffix]), @"images written");
        }
    }
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *mode = argc > 1 ? @(argv[1]) : @"all";
        NSString *images = argc > 2 && argv[2][0] != '-' ? @(argv[2]) : nil; // not the -AppleLanguages that follows
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"table"])
            TestTable();
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"sheet"])
            TestSheet(images);
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, Language().UTF8String);
    }
    return 0;
}
