// SPDX-License-Identifier: GPL-2.0-or-later
// The Find All list of the Advanced Find panel: the matches, their lines and text, the edits,
// live update, a large document, the list in the panel, and its layout and images in every language.
// Built by Tests/run-advanced-find-results.py; no window is ever shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "AdvancedFindTaskWait.h"
#import "TSLayoutManager.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

#pragma mark Documents

/// One text storage, two TSLayoutManagers and text views (the split window), in a window that is never shown.
@interface TestDocument : NSObject
@property NSTextStorage *storage;
@property NSTextView *upper;
@property NSTextView *lower;
@property NSWindow *window;
@end

@implementation TestDocument
- (instancetype)initWithText:(NSString *)text
{
    if (!(self = [super init]))
        return nil;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineSpacing = 1; // a paragraph attribute, as TeXShop's text has: fixing it widens the edited range
    _storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:14] ?: [NSFont systemFontOfSize:14],
                                                                       NSParagraphStyleAttributeName: paragraph}];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 400) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                            backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed = NO;
    _window.title = @"sample.tex";
    NSMutableArray<NSTextView *> *views = [NSMutableArray array];
    for (NSInteger i = 0; i < 2; i++) {
        TSLayoutManager *layout = [TSLayoutManager new];
        [_storage addLayoutManager:layout];
        NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(400, 1e7)];
        container.widthTracksTextView = YES;
        [layout addTextContainer:container];
        NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 200 - 200 * i, 400, 200) textContainer:container];
        view.allowsUndo = YES;
        view.richText = NO;
        [_window.contentView addSubview:view];
        [views addObject:view];
    }
    _upper = views[0];
    _lower = views[1];
    return self;
}
@end

static NSTextView *MakeTextView(NSString *string)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    view.allowsUndo = YES;
    view.richText = NO;
    view.string = string;
    return view;
}

static void Edit(NSTextView *view, NSRange range, NSString *string)
{
    [view.textStorage replaceCharactersInRange:range withString:string];
}

/// Runs the run loop until `done` or a second has passed (a live update searches on a background queue).
static void RunLoopUntil(BOOL (^done)(void))
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

static NSString *Lines(TSAdvancedFindResults *results)
{
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (TSAdvancedFindResultItem *item in results.items)
        [lines addObject:[NSString stringWithFormat:@"%lu%@", (unsigned long)[results lineNumberOfItem:item], item.isStale ? @"x" : @""]];
    return [lines componentsJoinedByString:@" "];
}

static TSAdvancedFindResults *FindAll(NSTextView *view, NSString *findString, TSRegexFindOptions options, BOOL inSelection)
{
    NSError *error = nil;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:findString options:options error:&error];
    TSRegexTextFind *find = pattern ? [[TSRegexTextFind alloc] initWithString:view.string pattern:pattern lineEnding:nil
                                                               selectedRanges:view.selectedRanges inSelection:inSelection error:&error] : nil;
    if (!find) { // the tests below cannot go on
        fprintf(stderr, "FAIL: find all of %s: %s\n", findString.UTF8String, error.localizedDescription.UTF8String);
        exit(1);
    }
    return [[TSAdvancedFindResults alloc] initWithTextStorage:view.textStorage find:find findString:findString];
}

static NSDictionary *Attributes(void)
{
    return @{NSFontAttributeName: [NSFont systemFontOfSize:12]};
}

static NSColor *BackgroundAt(NSAttributedString *text, NSUInteger index)
{
    return index < text.length ? [text attribute:NSBackgroundColorAttributeName atIndex:index effectiveRange:NULL] : nil;
}

static TSAdvancedFindController *MakeController(NSUInteger *beeps)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    TSAdvancedFindController *controller = [[TSAdvancedFindController alloc] initWithSettings:settings];
    controller.beepHandler = ^{ (*beeps)++; };
    controller.lineEndingHandler = ^NSString *(NSTextView *view) { return @"\n"; };
    return controller;
}

#pragma mark The list's contents

static void TestLinesAndText(void)
{
    TSRegexFindOptions plain = TSRegexFindDefaultOptions, regex = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    // Every kind of line break counts once: CRLF, CR, LF, and the Unicode line separator.
    NSTextView *view = MakeTextView(@"a\r\nb\rc\nab\u2028b");
    TSAdvancedFindResults *results = FindAll(view, @"b", plain, NO);
    Check([Lines(results) isEqualToString:@"2 4 5"], [NSString stringWithFormat:@"line numbers over CRLF, CR, LF and U+2028: %@", Lines(results)]);

    // The text: a little before the match ("…" when cut), the rest of the line, the match and its groups colored.
    NSString *longLine = [NSString stringWithFormat:@"%@\\textbf{x} and more", [@"" stringByPaddingToLength:40 withString:@"ab" startingAtIndex:0]];
    view = MakeTextView([NSString stringWithFormat:@"first\n%@\nlast", longLine]);
    results = FindAll(view, @"\\\\(text)(bf)\\{(x)\\}", regex, NO);
    NSArray<NSColor *> *groups = TSAdvancedFindResultsView.groupColors;
    NSColor *matchColor = NSColor.yellowColor;
    NSAttributedString *text = [results lineTextOfItem:results.items.firstObject attributes:Attributes() matchColor:matchColor groupColors:groups];
    Check([text.string hasPrefix:@"…"] && [text.string hasSuffix:@"\\textbf{x} and more"] && text.string.length == 1 + 30 + 19,
          [NSString stringWithFormat:@"the line is cut 30 characters before the match, as in OgreKit: [%@]", text.string]);
    Check([text attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] == NSColor.secondaryLabelColor, @"the cut mark is gray");
    NSUInteger backslash = [text.string rangeOfString:@"\\text"].location;
    Check(BackgroundAt(text, backslash) == matchColor, @"the match outside its groups has the match color");
    Check(BackgroundAt(text, backslash + 1) == groups[0] && BackgroundAt(text, backslash + 5) == groups[1] && BackgroundAt(text, backslash + 8) == groups[2],
          @"each group has its own color");
    Check(BackgroundAt(text, backslash - 1) == nil && BackgroundAt(text, text.length - 1) == nil, @"the text around the match is not colored");
    Check([results lineNumberOfItem:results.items.firstObject] == 2, @"the match is on line 2");

    // 250 characters at most, cut with a gray "…"; a cut never splits a surrogate pair.
    NSString *emoji = [@"" stringByPaddingToLength:600 withString:@"😀" startingAtIndex:0];
    view = MakeTextView([NSString stringWithFormat:@"x%@", emoji]);
    results = FindAll(view, @"x", plain, NO);
    text = [results lineTextOfItem:results.items.firstObject attributes:Attributes() matchColor:matchColor groupColors:groups];
    NSString *shown = [text.string substringToIndex:text.length - 1];
    Check(text.length <= 251 && [text.string hasSuffix:@"…"] && [shown canBeConvertedToEncoding:NSUTF8StringEncoding]
          && [text attribute:NSForegroundColorAttributeName atIndex:text.length - 1 effectiveRange:NULL] == NSColor.secondaryLabelColor,
          [NSString stringWithFormat:@"a long line is cut at 250 characters, between characters (%lu)", (unsigned long)text.length]);

    // A match over line breaks: one "⏎" for each, CRLF included; tabs are spaces.
    view = MakeTextView(@"x\tx a\r\nb tail");
    results = FindAll(view, @"a\\R+b", regex, NO);
    text = [results lineTextOfItem:results.items.firstObject attributes:Attributes() matchColor:matchColor groupColors:groups];
    Check([text.string isEqualToString:@"x x a⏎b tail"], [NSString stringWithFormat:@"line breaks in a match: [%@]", text.string]);
    Check(BackgroundAt(text, 5) == matchColor && BackgroundAt(text, 6) == matchColor && BackgroundAt(text, 7) == nil, @"the ⏎ of the match is colored");
}

/// The match "345" of "0123456789" after replacing `range` with `string`: "location,length" and "x" when stale.
static NSString *AfterEdit(NSRange range, NSString *string)
{
    NSTextView *view = MakeTextView(@"0123456789");
    TSAdvancedFindResults *results = FindAll(view, @"345", TSRegexFindDefaultOptions, NO);
    Edit(view, range, string);
    TSAdvancedFindResultItem *item = results.items.firstObject;
    return [NSString stringWithFormat:@"%lu,%lu%@", (unsigned long)item.currentRange.location, (unsigned long)item.currentRange.length, item.isStale ? @"x" : @""];
}

/// OgreKit's six cases of an edit and a match (OgreTextViewFindResult -updateOldRange:newRange:).
static void TestEditCases(void)
{
    NSDictionary<NSString *, NSString *> *got = @{
        @"before": AfterEdit(NSMakeRange(0, 2), @"abc"), @"after": AfterEdit(NSMakeRange(7, 2), @""),
        @"inside": AfterEdit(NSMakeRange(4, 1), @"XY"), @"over all": AfterEdit(NSMakeRange(2, 6), @"Q"),
        @"over the start": AfterEdit(NSMakeRange(2, 2), @"Q"), @"over the end": AfterEdit(NSMakeRange(5, 3), @"Q"),
        @"typed at the start": AfterEdit(NSMakeRange(3, 0), @"Q"), @"typed at the end": AfterEdit(NSMakeRange(6, 0), @"Q"),
    };
    NSDictionary<NSString *, NSString *> *want = @{
        @"before": @"4,3", @"after": @"3,3", @"inside": @"3,4x", @"over all": @"3,0x",
        @"over the start": @"3,2x", @"over the end": @"3,2x", @"typed at the start": @"4,3", @"typed at the end": @"3,3",
    };
    for (NSString *name in want)
        Check([got[name] isEqualToString:want[name]], [NSString stringWithFormat:@"an edit %@ the match: expected %@, got %@", name, want[name], got[name]]);
}

static void TestEdits(void)
{
    TSRegexFindOptions plain = TSRegexFindDefaultOptions;
    NSTextView *view = MakeTextView(@"ab\ncab\nxx ab");
    TSAdvancedFindResults *results = FindAll(view, @"ab", plain, NO);
    __block NSUInteger changes = 0;
    results.changeHandler = ^(TSAdvancedFindResults *changed) { changes++; };
    Check([Lines(results) isEqualToString:@"1 2 3"], [NSString stringWithFormat:@"three matches: %@", Lines(results)]);
    Edit(view, NSMakeRange(0, 0), @"new\n");
    Check([Lines(results) isEqualToString:@"2 3 4"] && changes == 1, [NSString stringWithFormat:@"a line added above moves every match down: %@", Lines(results)]);
    TSAdvancedFindResultItem *second = results.items[1];
    Check([[view.string substringWithRange:second.currentRange] isEqualToString:@"ab"], @"the moved range is the match");
    Edit(view, NSMakeRange(second.currentRange.location + 1, 0), @"Z"); // "aZb"
    Check([Lines(results) isEqualToString:@"2 3x 4"] && results.staleCount == 1, [NSString stringWithFormat:@"an edit inside a match makes it stale: %@", Lines(results)]);
    NSAttributedString *stale = [results lineTextOfItem:second attributes:Attributes() matchColor:NSColor.yellowColor groupColors:@[]];
    Check([stale.string isEqualToString:@"caZb"] && [stale attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] == NSColor.tertiaryLabelColor
          && BackgroundAt(stale, 1) == nil && [[view.string substringWithRange:second.currentRange] isEqualToString:@"aZb"],
          [NSString stringWithFormat:@"a stale row shows the text now, grayed, and its match grew with the edit: [%@]", stale.string]);
    Check(results.currentRanges.count == 2, @"a stale match is not in the current ranges");
    NSUInteger before = changes;
    [view.textStorage addAttribute:NSForegroundColorAttributeName value:NSColor.redColor range:NSMakeRange(0, 3)];
    Check(changes == before && results.staleCount == 1, @"a change of attributes only (syntax coloring) moves nothing");
    Edit(view, NSMakeRange(view.string.length, 0), @" ab");
    Check(results.items.count == 3, @"without live update, a new match is not listed");

    // Live update: the search runs again after the edit, with the same pattern.
    results.liveUpdateDelay = 0;
    results.updatesLive = YES;
    RunLoopUntil(^{ return [Lines(results) isEqualToString:@"2 4 4"]; });
    Check([Lines(results) isEqualToString:@"2 4 4"], [NSString stringWithFormat:@"turning live update on searches again: %@", Lines(results)]);
    Edit(view, NSMakeRange(0, 0), @"ab ");
    Check(results.items.count == 3, @"live update waits for the delay");
    RunLoopUntil(^{ return (BOOL)(results.items.count == 4); });
    Check([Lines(results) isEqualToString:@"1 2 4 4"], [NSString stringWithFormat:@"live update after the edit: %@", Lines(results)]);

    // Turning live update on right after the search does not search again.
    NSTextView *fresh = MakeTextView(@"ab ab");
    TSAdvancedFindResults *untouched = FindAll(fresh, @"ab", plain, NO);
    __block NSUInteger searches = 0;
    untouched.changeHandler = ^(TSAdvancedFindResults *changed) { searches++; };
    untouched.liveUpdateDelay = 0;
    untouched.updatesLive = YES;
    RunLoopUntil(^{ return (BOOL)(searches > 0); });
    Check(searches == 0, @"live update turned on with no edit since the search does not search again");
    // A search overtaken by an edit is dropped, and the newer one counts.
    Edit(fresh, NSMakeRange(5, 0), @" ab");
    Edit(fresh, NSMakeRange(8, 0), @" ab");
    RunLoopUntil(^{ return (BOOL)(untouched.items.count == 4); });
    Check(untouched.items.count == 4 && untouched.staleCount == 0, [NSString stringWithFormat:@"the last of quick edits wins: %lu", (unsigned long)untouched.items.count]);

    // Turning live update off keeps the list as it is: a search waiting for its delay, or one already running, does
    // not change it. Turned on again, it searches the text as it is now.
    NSTextView *paused = MakeTextView(@"ab ab");
    TSAdvancedFindResults *pausing = FindAll(paused, @"ab", plain, NO);
    pausing.liveUpdateDelay = 0.3;
    pausing.updatesLive = YES;
    Edit(paused, NSMakeRange(0, 2), @"zz");
    pausing.updatesLive = NO; // before the delay
    RunLoopUntil(^{ return NO; });
    Check(pausing.items.count == 2 && pausing.staleCount == 1, [NSString stringWithFormat:@"live update turned off before its delay: the list stays (%lu, %lu stale)",
                                                                (unsigned long)pausing.items.count, (unsigned long)pausing.staleCount]);
    pausing.updatesLive = YES;
    [pausing update]; // a search on the way
    pausing.updatesLive = NO;
    RunLoopUntil(^{ return NO; });
    Check(pausing.items.count == 2 && pausing.staleCount == 1, [NSString stringWithFormat:@"live update turned off while it searches: the list stays (%lu, %lu stale)",
                                                                (unsigned long)pausing.items.count, (unsigned long)pausing.staleCount]);
    pausing.liveUpdateDelay = 0;
    pausing.updatesLive = YES;
    RunLoopUntil(^{ return (BOOL)(pausing.items.count == 1); });
    Check(pausing.items.count == 1 && pausing.staleCount == 0, @"turned on again, the list is searched again");

    // A search the text was edited under is dropped: its matches are those of the older text.
    NSTextView *raced = MakeTextView(@"ab ab");
    TSAdvancedFindResults *racing = FindAll(raced, @"ab", plain, NO);
    __block NSUInteger raceChanges = 0;
    racing.changeHandler = ^(TSAdvancedFindResults *changed) { raceChanges++; };
    [racing update]; // searches a copy of "ab ab" on a background queue; its result waits for the main queue
    Edit(raced, NSMakeRange(0, 0), @"xx");
    RunLoopUntil(^{ return NO; }); // let the search finish and its result reach the main thread
    Check(raceChanges == 1 && NSEqualRanges(racing.items[0].currentRange, NSMakeRange(2, 2)) && NSEqualRanges(racing.items[1].currentRange, NSMakeRange(5, 2)),
          [NSString stringWithFormat:@"a search overtaken by an edit is dropped (%lu changes, first match at %@)", (unsigned long)raceChanges,
           NSStringFromRange(racing.items[0].currentRange)]);

    // In a selection: the scope follows the edits inside it, and matches outside it stay out.
    view = MakeTextView(@"ab ab | ab");
    view.selectedRange = NSMakeRange(0, 5);
    results = FindAll(view, @"ab", plain, YES);
    results.liveUpdateDelay = 0;
    results.updatesLive = YES;
    Check(results.items.count == 2, @"two matches in the selection");
    Edit(view, NSMakeRange(2, 0), @" ab");
    RunLoopUntil(^{ return (BOOL)(results.items.count == 3); });
    Check(results.items.count == 3, [NSString stringWithFormat:@"the scope grows with a match typed inside it: %lu", (unsigned long)results.items.count]);
    __block NSUInteger updates = 0;
    results.changeHandler = ^(TSAdvancedFindResults *changed) { updates++; };
    Edit(view, NSMakeRange(view.string.length, 0), @" ab");
    RunLoopUntil(^{ return (BOOL)(updates >= 2); }); // moved, then searched again
    Check(updates >= 2 && results.items.count == 3, @"a match typed after the scope is not listed");
    // An edit over the first characters of the scope stays inside it (OgreKit's rule would cut them off).
    view = MakeTextView(@"ab ab | ab");
    view.selectedRange = NSMakeRange(0, 5);
    results = FindAll(view, @"ab", TSRegexFindDefaultOptions, YES);
    results.liveUpdateDelay = 0;
    results.updatesLive = YES;
    Edit(view, NSMakeRange(0, 2), @"ab ab");
    RunLoopUntil(^{ return (BOOL)(results.items.count == 3); });
    Check(results.items.count == 3 && NSEqualRanges(results.scopeRanges.firstObject.rangeValue, NSMakeRange(0, 8)),
          [NSString stringWithFormat:@"an edit at the start of the scope stays in it: %lu", (unsigned long)results.items.count]);
}

/// Typing in TeXShop's text (TSLayoutManager, paragraph attributes, both views of a split window): the text storage
/// widens the edited range to the paragraph while it processes the edit; the list must use the edit itself.
static void TestTypingInDocument(void)
{
    TestDocument *document = [[TestDocument alloc] initWithText:@"ab cd ab\nab\n"];
    TSAdvancedFindResults *results = FindAll(document.upper, @"ab", TSRegexFindDefaultOptions, NO);
    document.lower.selectedRange = NSMakeRange(0, 0);
    [document.lower insertText:@"x" replacementRange:NSMakeRange(0, 0)];
    Check(results.staleCount == 0 && [Lines(results) isEqualToString:@"1 1 2"] && NSEqualRanges(results.items[1].currentRange, NSMakeRange(7, 2)),
          [NSString stringWithFormat:@"typing at the start of a line in the other view moves its matches without making them stale: %@", Lines(results)]);
    [document.upper insertText:@"y" replacementRange:NSMakeRange(5, 0)];
    Check(results.staleCount == 0 && NSEqualRanges(results.items[1].currentRange, NSMakeRange(8, 2)), @"typing between two matches of a line leaves both");
    [document.upper.undoManager undo];
    [document.upper.undoManager undo];
    Check(results.staleCount == 0 && NSEqualRanges(results.items[1].currentRange, NSMakeRange(6, 2)) && NSEqualRanges(results.items[2].currentRange, NSMakeRange(9, 2)),
          @"undo moves the matches back");
}

/// A large document: Find All, its line numbers and the rows the table shows stay quick.
static void TestLargeDocument(void)
{
    NSMutableString *string = [NSMutableString string];
    for (int i = 0; i < 20000; i++)
        [string appendString:@"\\section{ab} some text on the line\n"];
    NSTextView *view = MakeTextView(string);
    NSDate *start = NSDate.date;
    TSAdvancedFindResults *results = FindAll(view, @"ab", TSRegexFindDefaultOptions, NO);
    NSUInteger last = [results lineNumberOfItem:results.items.lastObject];
    NSTimeInterval elapsed = -start.timeIntervalSinceNow;
    Check(results.items.count == 20000 && last == 20000, @"20000 matches on their lines");
    Check(elapsed < 2, [NSString stringWithFormat:@"20000 matches listed in %.2f s", elapsed]);

    // About 8 MB with 200000 matches, through the controller and the panel's list: the search, the list and its
    // first screen of rows; only the rows on screen are made.
    NSMutableString *big = [NSMutableString stringWithCapacity:8200000];
    NSString *line = [@"\\item{ab} " stringByPaddingToLength:40 withString:@"lorem ipsum " startingAtIndex:0];
    for (int i = 0; i < 200000; i++)
        [big appendFormat:@"%@%d\n", line, i];
    TestDocument *document = [[TestDocument alloc] initWithText:big];
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    panel.showsResults = NO;
    controller.settings.findString = @"ab";
    start = NSDate.date;
    BOOL found = TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper);
    TSAdvancedFindResultsView *list = panel.resultsView;
    [panel.window.contentView layoutSubtreeIfNeeded];
    [list.tableView scrollRowToVisible:199999];
    [panel.window.contentView displayIfNeeded];
    NSString *lastLine = [list.tableView.dataSource tableView:list.tableView objectValueForTableColumn:list.tableView.tableColumns[0] row:199999];
    elapsed = -start.timeIntervalSinceNow;
    Check(found && list.results.items.count == 200000 && [lastLine isEqual:@"200000"],
          [NSString stringWithFormat:@"200000 matches of 8 MB listed, the last on line %@", lastLine]);
    Check(elapsed < 5, [NSString stringWithFormat:@"8 MB, 200000 matches: found and listed in %.2f s", elapsed]);
    start = NSDate.date;
    [document.upper insertText:@"new line\n" replacementRange:NSMakeRange(0, 0)];
    lastLine = [list.tableView.dataSource tableView:list.tableView objectValueForTableColumn:list.tableView.tableColumns[0] row:199999];
    elapsed = -start.timeIntervalSinceNow;
    Check([lastLine isEqual:@"200001"] && elapsed < 1, [NSString stringWithFormat:@"an edit moves 200000 matches in %.2f s", elapsed]);
    [list clear];
}

#pragma mark The controller and the panel

static void TestFindAllAction(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    TSAdvancedFindSettings *settings = controller.settings;
    __block NSString *status = @"";
    __block BOOL isError = NO;
    controller.statusHandler = ^(NSString *message, BOOL error) { status = message; isError = error; };
    __block TSAdvancedFindResults *listed = nil;
    __block NSTextView *listedView = nil;
    controller.findAllHandler = ^(TSAdvancedFindResults *results, NSTextView *textView) { listed = results; listedView = textView; };
    TestDocument *document = [[TestDocument alloc] initWithText:@"one two\r\none"];
    settings.findString = @"zz";
    Check(TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && beeps == 1 && !listed,
          @"nothing found: the search starts, then a beep, a message and no list");
    settings.findString = @"one";
    Check(TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && beeps == 1 && listed.items.count == 2 && listedView == document.upper,
          @"Find All hands its list to the panel");
    Check([status isEqualToString:[NSString stringWithFormat:TSAdvancedFindLocalized(@"AdvancedFind.Found", @"%lu found"), 2UL]] && !isError, @"and reports the count");
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:document.storage].ranges.count == 0, @"Find All does not highlight, as in OgreKit");
    Check([settings.findHistory.firstObject isEqualToString:@"one"], @"the find string goes into the history");
    // In the selection, and the line ending of the document in a pattern over lines
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    controller.lineEndingHandler = ^NSString *(NSTextView *view) { return @"\r\n"; };
    settings.findString = @"two\none";
    Check(TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && listed.items.count == 1
          && [listed.findString isEqualToString:@"two\none"], @"the find string is put into the document's line ending; the list shows it as typed");
    controller.lineEndingHandler = ^NSString *(NSTextView *view) { return @"\n"; };
    settings.findString = @"o";
    settings.inSelection = YES;
    document.upper.selectedRange = NSMakeRange(0, 7);
    Check(TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && listed.items.count == 2 && listed.scopeRanges.count == 1,
          @"with In selection, only the matches in the selection");
    settings.inSelection = NO;
    // An invalid pattern is an error, with no list
    listed = nil;
    settings.findString = @"(";
    Check(!TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && beeps == 2 && isError && !listed, @"an invalid pattern: an error and no list");
    // A read-only text view (the console, the log) may be listed
    document.upper.editable = NO;
    settings.findString = @"one";
    Check([controller validateAction:TSAdvancedFindActionFindAll forTextView:document.upper]
          && TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && listed, @"Find All works in a read-only text view");
    document.upper.selectable = NO;
    Check(![controller validateAction:TSAdvancedFindActionFindAll forTextView:document.upper], @"but not in one that cannot be selected");
}

/// Counts -orderOut: of one window (the panel's "close after finding").
static NSWindow *watchedWindow;
static NSUInteger watchedOrderOuts;
static IMP originalOrderOut;
static void CountOrderOut(NSWindow *self, SEL _cmd, id sender)
{
    if (self == watchedWindow)
        watchedOrderOuts++;
    ((void (*)(id, SEL, id))originalOrderOut)(self, _cmd, sender);
}

static NSView *FieldBox(TSAdvancedFindPanelController *panel)
{
    return panel.findBox;
}

static void TestPanelList(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    TSAdvancedFindSettings *settings = controller.settings;
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    panel.showsResults = NO;
    TSAdvancedFindResultsView *list = panel.resultsView;
    NSUInteger *beepCount = &beeps;
    list.beepHandler = ^{ (*beepCount)++; };
    TestDocument *document = [[TestDocument alloc] initWithText:@"ab\ncab\nxx ab"];
    NSTextView *view = document.upper;
    TSAdvancedFindController.testTargetTextView = view;
    NSView *content = panel.window.contentView;
    [content layoutSubtreeIfNeeded];
    NSRect panelFrame = panel.window.frame;
    CGFloat fieldHeight = NSHeight(FieldBox(panel).frame);

    // The buttons, as in CotEditor: Find All ▾ (Highlight All, Select All, Remove Highlights), Replace All,
    // Replace & Find ▾ (Replace), ‹ ›.
    NSArray<NSControl *> *buttons = panel.buttons;
    NSComboButton *findAll = buttons.count == 4 && [buttons[0] isKindOfClass:[NSComboButton class]] ? (NSComboButton *)buttons[0] : nil;
    NSArray<NSMenuItem *> *items = findAll.menu.itemArray;
    Check(findAll.action == @selector(advancedFindAll:) && items.count == 4 && items[0].action == @selector(advancedHighlight:)
          && items[1].action == @selector(advancedSelectAll:) && items[2].isSeparatorItem && items[3].action == @selector(advancedUnhighlight:)
          && [findAll.title isEqualToString:TSAdvancedFindLocalized(@"AdvancedFind.FindAll", @"Find All")],
          [NSString stringWithFormat:@"Find All, with Highlight All, Select All and Remove Highlights under ▾ (%lu items)", (unsigned long)items.count]);
    Check(list.hidden, @"no list before Find All");

    settings.findString = @"zz";
    [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
    Check(beeps == 1 && list.hidden && NSEqualRects(panel.window.frame, panelFrame), @"nothing found: a beep and no list");

    // Find All: the panel grows at its bottom, the list takes the new room, the fields keep theirs.
    settings.findString = @"ab";
    settings.closesWhenDone = YES;
    watchedWindow = panel.window;
    originalOrderOut = method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(orderOut:)), (IMP)CountOrderOut);
    [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
    Check(watchedOrderOuts == 0, @"Find All keeps the panel open, with \"close after finding\" on: its list is in the panel");
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(orderOut:)), originalOrderOut);
    [content layoutSubtreeIfNeeded];
    NSRect grown = panel.window.frame;
    Check(!list.hidden && NSHeight(grown) > NSHeight(panelFrame) + 150 && fabs(NSMaxY(grown) - NSMaxY(panelFrame)) < 0.5,
          [NSString stringWithFormat:@"the panel grows downward for the list: %@ -> %@", NSStringFromRect(panelFrame), NSStringFromRect(grown)]);
    Check(fabs(NSHeight(FieldBox(panel).frame) - fieldHeight) < 1 && NSHeight(list.frame) > 150,
          [NSString stringWithFormat:@"the list, not the fields, takes the room: fields %.0f -> %.0f, list %.0f", fieldHeight, NSHeight(FieldBox(panel).frame), NSHeight(list.frame)]);
    Check(list.tableView.numberOfRows == 3 && [list.countField.stringValue containsString:@"3"] && [list.countField.stringValue containsString:@"sample.tex"],
          [NSString stringWithFormat:@"the list has the three matches and says where: %@", list.countField.stringValue]);
    NSView *buttonRow = ((NSStackView *)content).arrangedSubviews.lastObject;
    NSRect buttonFrame = [buttonRow convertRect:buttonRow.bounds toView:content];
    Check(fabs((content.isFlipped ? NSHeight(content.bounds) - NSMaxY(buttonFrame) : NSMinY(buttonFrame)) - 20) <= 1, @"the buttons stay 20 points from the bottom");
    settings.closesWhenDone = NO;
    Check([list showItemAtRow:2] && NSEqualRanges(view.selectedRange, NSMakeRange(10, 2)), @"choosing a row selects its match");
    Check(list.tableView.action == @selector(rowClicked:) && list.tableView.target == list && list.tableView.doubleAction == @selector(goToDocument:),
          @"a click and a double click on a row jump to the match");
    view.selectedRange = NSMakeRange(0, 0);
    [list.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    Check(NSEqualRanges(view.selectedRange, NSMakeRange(4, 2)), @"selecting a row with the keys jumps to its match");
    NSString *count = list.countField.stringValue;
    Edit(view, NSMakeRange(4, 1), @"");
    Check([list showItemAtRow:1] && NSEqualRanges(view.selectedRange, NSMakeRange(4, 1)) && beeps == 1, @"a stale row jumps to what is left of its match");
    Check(list.results.staleCount == 1 && ![list.countField.stringValue isEqualToString:count] && [list.countField.stringValue hasPrefix:count],
          [NSString stringWithFormat:@"the count adds that one row is stale: %@", list.countField.stringValue]);
    id staleLine = [list.tableView.dataSource tableView:list.tableView objectValueForTableColumn:list.tableView.tableColumns[0] row:1];
    Check([staleLine isKindOfClass:[NSAttributedString class]] && [[staleLine attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:NSColor.tertiaryLabelColor],
          @"the stale row's line number is gray too");
    // Live Update is a setting
    Check(list.liveUpdateBox.state == NSControlStateValueOff && !list.results.updatesLive, @"Live Update is off by default");
    [list.liveUpdateBox performClick:nil];
    Check(settings.updatesResultsLive && list.results.updatesLive, @"turning Live Update on is kept in the settings and updates the list");
    RunLoopUntil(^{ return (BOOL)(list.results.staleCount == 0); });
    Check(list.results.staleCount == 0 && list.tableView.numberOfRows == 2, @"and searches again after the edit");
    [list.liveUpdateBox performClick:nil];
    Check(!settings.updatesResultsLive && !list.results.updatesLive, @"and off again");

    settings.findString = @"x";
    [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
    Check(list.tableView.numberOfRows == 2 && fabs(NSHeight(panel.window.frame) - NSHeight(grown)) < 0.5, @"a new Find All replaces the list without growing again");
    // The buttons follow the target: Find All stays in a read-only text view
    view.editable = NO;
    [panel updateButtons];
    Check(buttons[0].enabled && !buttons[1].enabled, @"in a read-only target Find All stays, Replace All is gray");
    view.editable = YES;
    [panel updateButtons];

    // Each step of the window's resize animation, run here one by one: everything above the list keeps its place
    // (distance from the window's top) and size, the list takes what is left.
    CGFloat listHeight = NSHeight(list.frame), windowHeight = NSHeight(panel.window.frame);
    NSRect (^placeFromTop)(NSView *) = ^NSRect(NSView *v) {
        NSRect r = [v convertRect:v.bounds toView:nil];
        return NSMakeRect(NSMinX(r), NSHeight(panel.window.contentView.bounds) - NSMaxY(r), NSWidth(r), NSHeight(r));
    };
    NSRect fieldPlace = placeFromTop(FieldBox(panel)), replacePlace = placeFromTop(panel.replaceBox);
    TSAdvancedFindResults *kept = list.results;
    NSTextView *keptView = list.textView;
    [list clear]; // as the close button does first
    CGFloat closed = [panel prepareResultsTransition:NO];
    Check(fabs(closed - (windowHeight - listHeight)) < 1 && !list.hidden && fabs(NSHeight(list.frame) - listHeight) < 1, @"closing starts with the list as it is");
    BOOL steady = YES;
    for (int step = 1; step <= 8; step++) {
        [panel setWindowHeight:windowHeight - listHeight * step / 8 animate:NO];
        BOOL same = NSEqualRects(placeFromTop(FieldBox(panel)), fieldPlace) && NSEqualRects(placeFromTop(panel.replaceBox), replacePlace)
            && fabs(NSHeight(list.frame) - listHeight * (8 - step) / 8) < 1 && (step == 8 || !list.hidden);
        if (!same)
            printf("  step %d of closing: field %s (was %s), list %.0f\n", step, NSStringFromRect(placeFromTop(FieldBox(panel))).UTF8String,
                   NSStringFromRect(fieldPlace).UTF8String, NSHeight(list.frame));
        steady = steady && same;
    }
    [panel endResultsTransition:NO];
    Check(steady, @"at every step of closing, the fields keep their place and size and the list takes the rest");
    Check(list.hidden && NSEqualRects(panel.window.frame, panelFrame) && NSEqualRects(placeFromTop(FieldBox(panel)), fieldPlace), @"closed step by step: the panel as before");
    CGFloat opened = [panel prepareResultsTransition:YES];
    steady = !list.hidden && NSHeight(list.frame) < 1;
    for (int step = 1; step <= 8; step++) {
        [panel setWindowHeight:NSHeight(panelFrame) + (opened - NSHeight(panelFrame)) * step / 8 animate:NO];
        steady = steady && NSEqualRects(placeFromTop(FieldBox(panel)), fieldPlace) && NSEqualRects(placeFromTop(panel.replaceBox), replacePlace);
    }
    [panel endResultsTransition:YES];
    Check(steady, @"at every step of opening, the fields keep their place and size");
    if (kept && keptView)
        [list setResults:kept textView:keptView];
    Check(fabs(NSHeight(panel.window.frame) - NSHeight(grown)) < 1, [NSString stringWithFormat:@"opened again to the same height: %@ vs %@", NSStringFromRect(panel.window.frame), NSStringFromRect(grown)]);

    // Closing the list gives the room back; the next list opens at the height it had.
    [list.closeButton performClick:nil];
    [content layoutSubtreeIfNeeded];
    Check(list.hidden && !list.results && NSEqualRects(panel.window.frame, panelFrame) && fabs(NSHeight(FieldBox(panel).frame) - fieldHeight) < 1,
          [NSString stringWithFormat:@"closing the list restores the panel: %@", NSStringFromRect(panel.window.frame)]);
    Check(panel.window.contentMinSize.height == 250, @"and its smallest size");

    // Quitting with the list open closes it at once, so the panel's saved size is that without the list.
    settings.findString = @"ab";
    [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
    [panel applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil]];
    Check(list.hidden && NSEqualRects(panel.window.frame, panelFrame), @"quitting with the list open closes it first");

    // Closing another window leaves the list; closing the document's window closes it.
    [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
    TestDocument *other = [[TestDocument alloc] initWithText:@"ab"];
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:other.window];
    Check(!list.hidden && list.results, @"closing another window leaves the list");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:document.window];
    Check(list.hidden && !list.results && list.tableView.numberOfRows == 0 && NSEqualRects(panel.window.frame, panelFrame), @"the list goes with its document");
    // A list whose text view is gone beeps instead of jumping.
    [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
    @autoreleasepool {
        TestDocument *gone = [[TestDocument alloc] initWithText:@"ab ab"];
        TSAdvancedFindController.testTargetTextView = gone.upper;
        [panel advancedFindAll:nil];
    TSTestWaitForTask(controller, 60);
        [gone.upper removeFromSuperview];
        [gone.storage removeLayoutManager:gone.upper.layoutManager];
        gone = nil;
    }
    NSUInteger beepsBefore = beeps;
    Check(![list showItemAtRow:0] && beeps == beepsBefore + (list.textView ? 1 : 0), @"a row whose text view is gone does not jump");
    TSAdvancedFindController.testTargetTextView = nil;
    [list.closeButton performClick:nil];
    Check(!panel.window.isVisible && !document.window.isVisible, @"no window is shown");
}

#pragma mark Layout and images

/// Windows that are never shown do not draw buttons; each button's own cell is drawn at its measured frame
/// (the method of the plan audit's render-probe.m, as in Tests/AdvancedFindPanel.m).
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
        printf("FAIL %s: label cut: %s (%.0f wide, needs %.0f)\n", name.UTF8String, text.UTF8String, frame.width, cell.cellSize.width);
    return cut ? 1 : 0;
}

/// Every control inside the view, with a title that fits; the table's column titles fit their columns.
static int CheckLayout(NSView *root, NSString *name)
{
    int count = 0;
    NSMutableArray<NSView *> *pending = [root.subviews mutableCopy];
    while (pending.count) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        if (![v isKindOfClass:[NSScrollView class]])
            [pending addObjectsFromArray:v.subviews];
        if (!([v isKindOfClass:[NSControl class]] || [v isKindOfClass:[NSScrollView class]]) || v.isHiddenOrHasHiddenAncestor)
            continue;
        NSRect frame = [v convertRect:v.bounds toView:root];
        NSString *title = [v isKindOfClass:[NSButton class]] ? [(NSButton *)v title]
                        : [v isKindOfClass:[NSTextField class]] ? [NSString stringWithFormat:@"%@ “%@”", NSStringFromClass(v.class), ((NSTextField *)v).stringValue]
                        : NSStringFromClass(v.class);
        if (!NSContainsRect(NSInsetRect(root.bounds, -0.5, -0.5), frame)) {
            printf("FAIL %s: outside: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSButton class]] && title.length > 0 && v.frame.size.width + 0.5 < v.fittingSize.width) {
            printf("FAIL %s: title cut: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSComboButton class]] && v.frame.size.width + 0.5 < v.fittingSize.width) {
            printf("FAIL %s: title cut: %s\n", name.UTF8String, [(NSComboButton *)v title].UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).isEditable)
            count += CheckLabelFits((NSTextField *)v, name);
        if ([v isKindOfClass:[NSScrollView class]] && [((NSScrollView *)v).documentView isKindOfClass:[NSTableView class]])
            for (NSTableColumn *column in ((NSTableView *)((NSScrollView *)v).documentView).tableColumns)
                if (column.headerCell.cellSize.width > column.width + 0.5) {
                    printf("FAIL %s: column title cut: %s (%.0f wide, needs %.0f)\n", name.UTF8String, column.title.UTF8String, column.width, column.headerCell.cellSize.width);
                    count++;
                }
    }
    return count;
}

/// The panel with its list in the current language: everything fits at the normal and the smallest size, with the
/// longest count line; images on request (light and dark).
static void TestListLayout(NSString *_Nullable imageDirectory)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    TSAdvancedFindSettings *settings = controller.settings;
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    panel.showsResults = NO;
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    // A short LaTeX document with Japanese text.
    TestDocument *document = [[TestDocument alloc] initWithText:@"\\documentclass{jlreq}\n\\usepackage{amsmath}\n\\begin{document}\n\\section{はじめに}\n"
                              "関数 $f(x) = x^2 + 2x + 1$ を考える。①②③ と \\ajMaru{4} は同じ丸数字。\n値は 3.14、2.718、1.414 など。全角の　空白と半角の 空白。\n"
                              "\\begin{align}\n  a_1 &= b_1 + c_1 \\\\\n  a_2 &= b_2 + c_2\n\\end{align}\n"
                              "{\\bf 太字} と \\textbf{太字}、{\\it 斜体} と \\textit{斜体}。\n日付：2026-11-13、2026/11/13。メール：someone@example.com\n\\end{document}\n"];
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"\\\\(begin|end)\\{(\\w+)\\}|\\\\text(bf|it)";
    settings.replaceString = @"\\\\text$1{$2}$3\\n";
    [panel reloadFromSettings];
    Check(TSTestPerform(controller, TSAdvancedFindActionFindAll, document.upper) && panel.resultsView.results.items.count == 6, @"six matches for the images");
    // One match made stale by an edit
    NSRange align = [document.storage.string rangeOfString:@"\\end{align}"];
    [document.storage replaceCharactersInRange:NSMakeRange(align.location + 6, 0) withString:@"ed"];
    NSView *content = panel.window.contentView;
    [content layoutSubtreeIfNeeded];
    TSAdvancedFindResultsView *list = panel.resultsView;
    failures += CheckLayout(content, [NSString stringWithFormat:@"%@ panel with its list", language]);

    // The longest count line, in the smallest panel
    NSRect old = panel.window.frame;
    [panel.window setContentSize:panel.window.contentMinSize];
    [content layoutSubtreeIfNeeded];
    NSString *countLine = [NSString stringWithFormat:TSAdvancedFindLocalized(@"AdvancedFind.Results.CountStale", @"%2$lu found in “%1$@” (%3$lu changed since)"),
                           @"sample.tex", 123456UL, 123456UL];
    list.countField.stringValue = countLine;
    [content layoutSubtreeIfNeeded];
    failures += CheckLayout(content, [NSString stringWithFormat:@"%@ smallest panel with its list", language]);
    NSScrollView *scroll = list.tableView.enclosingScrollView;
    NSRect scrollFrame = [scroll convertRect:scroll.bounds toView:list];
    Check(NSContainsRect(NSInsetRect(list.bounds, -0.5, -0.5), scrollFrame) && NSHeight(scrollFrame) >= 99,
          [NSString stringWithFormat:@"%@: in the smallest panel the list's table is whole, not cut off under the buttons (%@ in %@)", language,
           NSStringFromRect(scrollFrame), NSStringFromRect(list.bounds)]);
    Check(list.countField.frame.size.height > 20 || [list.countField.cell cellSizeForBounds:NSMakeRect(0, 0, CGFLOAT_MAX, CGFLOAT_MAX)].width <= NSWidth(list.countField.frame),
          [NSString stringWithFormat:@"%@: a long count line wraps", language]);
    [panel.window setFrame:old display:NO];
    if (list.results.changeHandler)
        list.results.changeHandler(list.results); // the list's own count line again
    [content layoutSubtreeIfNeeded];
    Check([list.countField.stringValue containsString:@"sample.tex"], @"the count line is back");
    failures += CheckLayout(content, [NSString stringWithFormat:@"%@ panel with its list, after the smallest size", language]);
    NSRect countFrame = [list.countField convertRect:list.countField.bounds toView:list];
    NSRect liveFrame = [list.liveUpdateBox convertRect:list.liveUpdateBox.bounds toView:list];
    Check(NSMaxX(liveFrame) > NSWidth(list.bounds) - 21 && NSMinX(liveFrame) - NSMaxX(countFrame) < 13 && NSWidth(countFrame) > 250,
          [NSString stringWithFormat:@"%@: the count takes the room up to Live Update (%@, Live Update %@)", language,
           NSStringFromRect(countFrame), NSStringFromRect(liveFrame)]);

    if (!imageDirectory)
        return;
    [NSFileManager.defaultManager createDirectoryAtPath:imageDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:name];
        NSString *tag = [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
        panel.window.appearance = appearance;
        [list.tableView reloadData];
        NSString *base = [imageDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", language, tag]];
        Check(WritePNG(content, appearance, [base stringByAppendingString:@"-find-all.png"]), @"image written");
    }
}

#pragma mark Main

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *mode = argc > 1 ? @(argv[1]) : @"all";
        NSString *images = argc > 2 && argv[2][0] != '-' ? @(argv[2]) : nil; // not the -AppleLanguages that follows
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"behavior"]) {
            TestLinesAndText();
            TestEditCases();
            TestEdits();
            TestTypingInDocument();
            TestFindAllAction();
            TestPanelList();
        }
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"large"])
            TestLargeDocument();
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"layout"])
            TestListLayout(images);
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
