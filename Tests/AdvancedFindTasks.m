// SPDX-License-Identifier: GPL-2.0-or-later
// The long actions of the Advanced Find panel: Replace All, Find All and Multiple Replace in the background on a
// 10 MB document, with the text views locked and unlocked, Cancel, the progress sheet, a text changed meanwhile, Find
// All in a read-only text view receiving output, and the cache of matches. Built by Tests/run-advanced-find-tasks.py;
// no window is ever shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "AdvancedFindTaskWait.h"
#import "TSLayoutManager.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindController+MultipleReplace.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindTask.h"
#import "TSAdvancedFindProgressSheet.h"
#import "TSAdvancedFindMatchCache.h"
#import "TSMultipleReplaceWindowController.h"
#import "TSMultipleReplaceLibrary.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

static void RunFor(NSTimeInterval seconds)
{
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

#pragma mark Documents

/// One text storage, two TSLayoutManagers and text views (the split window), in a window that is never shown. The
/// font has Japanese glyphs, as TeXShop's Japanese documents do: without them a 10 MB text has a million attribute
/// runs, and undoing a Replace All over it takes minutes in AppKit.
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
    NSFont *font = [NSFont fontWithName:@"Osaka-Mono" size:13] ?: [NSFont fontWithName:@"HiraginoSans-W3" size:13] ?: [NSFont userFixedPitchFontOfSize:13];
    _storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName: font}];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed = NO;
    NSMutableArray<NSTextView *> *views = [NSMutableArray array];
    for (NSInteger i = 0; i < 2; i++) {
        TSLayoutManager *layout = [TSLayoutManager new];
        layout.allowsNonContiguousLayout = YES;
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

/// About 10 MB of UTF-8, LaTeX-like, with Japanese.
static NSString *LargeText(void)
{
    static NSString *text;
    if (!text) {
        NSMutableString *string = [NSMutableString stringWithCapacity:12000000];
        for (int i = 0; i < 90000; i++)
            [string appendFormat:@"\\section{第%d節} 関数 $f(x) = x^2 + %d$ を考える。\\textbf{太字} と {\\bf 太字} の line %d\n", i, i % 97, i];
        text = [string copy];
    }
    return text;
}

static TSAdvancedFindController *MakeController(NSUInteger *beeps)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    TSAdvancedFindController *controller = [[TSAdvancedFindController alloc] initWithSettings:settings];
    controller.beepHandler = ^{ (*beeps)++; };
    controller.lineEndingHandler = ^NSString *(NSTextView *view) { return @"\n"; };
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    return controller;
}

/// Waits for the running task, noting its progress and its message as the sheet reads them.
static BOOL WaitWatching(TSAdvancedFindController *controller, NSTimeInterval seconds, NSMutableArray<NSNumber *> *progress,
                         NSMutableOrderedSet<NSString *> *messages)
{
    TSAdvancedFindTask *task = controller.runningTask;
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (controller.runningTask && limit.timeIntervalSinceNow > 0) {
        [progress addObject:@(task.progress)];
        if (task.message.length > 0)
            [messages addObject:task.message];
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    [progress addObject:@(task.progress)];
    if (task.message.length > 0)
        [messages addObject:task.message];
    return controller.runningTask == nil;
}

/// The bar fills as the work goes: it never goes back, it is seen between the ends, and it ends full.
static BOOL ProgressFills(NSArray<NSNumber *> *progress)
{
    double last = -1;
    BOOL between = NO;
    for (NSNumber *value in progress) {
        double p = value.doubleValue;
        if (p >= 0 && p + 1e-9 < last)
            return NO;
        if (p >= 0)
            last = p;
        between = between || (p > 0 && p < 1);
    }
    return between && last > 0.999;
}

static NSString *Digits(NSString *text)
{
    return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet] componentsJoinedByString:@""];
}

static BOOL AllEnabled(NSArray<NSControl *> *controls, BOOL enabled)
{
    for (NSControl *control in controls)
        if (control.isEnabled != enabled)
            return NO;
    return controls.count > 0;
}

#pragma mark Replace All

static void TestReplaceAll(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    // The panel first: it takes the controller's status handler, which the test then takes over.
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    panel.showsResults = NO;
    __block NSString *status = @"";
    __block BOOL isError = NO;
    controller.statusHandler = ^(NSString *message, BOOL error) { status = message; isError = error; };
    TestDocument *document = [[TestDocument alloc] initWithText:LargeText()];
    NSTextView *upper = document.upper, *lower = document.lower;
    TSAdvancedFindController.testTargetTextView = upper;
    [panel updateButtons];
    Check(AllEnabled(panel.buttons, YES), @"before, the panel's buttons are enabled");
    controller.settings.findString = @"\\b(\\w)(\\w*)";
    controller.settings.replaceString = @"$2$1";

    // Cancel: the text stays as it was, and both views of the split window are editable again.
    Check([controller performAction:TSAdvancedFindActionReplaceAll inTextView:upper], @"Replace All starts");
    TSAdvancedFindTask *task = controller.runningTask;
    Check(task && !upper.isEditable && !lower.isEditable, @"while it runs, every view of the document is read-only");
    Check(![controller performAction:TSAdvancedFindActionNext inTextView:upper] && beeps == 1, @"while it runs, other actions are refused with a beep");
    Check(![controller validateAction:TSAdvancedFindActionHighlight forTextView:upper] && [controller validateAction:TSAdvancedFindActionShowFindPanel forTextView:upper],
          @"while it runs, the menu items are gray but Find… still shows the panel");
    Check(AllEnabled(panel.buttons, NO), @"while it runs, the panel's buttons are gray");
    NSRange selection = upper.selectedRange;
    Check(![controller incrementalSearchInTextView:upper] && NSEqualRanges(upper.selectedRange, selection), @"while it runs, typing in the find field does not search");
    RunFor(0.05);
    [task cancel];
    NSDate *cancelled = NSDate.date;
    Check(TSTestWaitForTask(controller, 10), @"a cancelled task ends");
    NSTimeInterval latency = -cancelled.timeIntervalSinceNow;
    Check(latency < 1, [NSString stringWithFormat:@"Cancel takes effect within a second on 10 MB (%.2f s)", latency]);
    Check([upper.string isEqualToString:LargeText()] && upper.isEditable && lower.isEditable, @"after Cancel the text is unchanged and the views are editable again");
    Check(AllEnabled(panel.buttons, YES), @"after it, the panel's buttons are enabled again");
    Check(status.length > 0 && !isError && !upper.undoManager.canUndo,
          [NSString stringWithFormat:@"Cancel is reported and leaves nothing to undo (%@)", status]);

    // To the end: the progress, the count, one undo step gives back the 10 MB text.
    lower.editable = NO; // a view that was read-only before stays so
    NSDate *start = NSDate.date;
    [controller performAction:TSAdvancedFindActionReplaceAll inTextView:upper];
    task = controller.runningTask;
    NSMutableArray<NSNumber *> *progress = [NSMutableArray array];
    NSMutableOrderedSet<NSString *> *messages = [NSMutableOrderedSet orderedSet];
    Check(WaitWatching(controller, 60, progress, messages), @"Replace All on 10 MB ends");
    printf("  Replace All on 10 MB: %.2f s, %lu progress samples, last message %s\n", -start.timeIntervalSinceNow, (unsigned long)progress.count, messages.lastObject.UTF8String);
    Check(ProgressFills(progress) && messages.count >= 3 && Digits(status).length > 0 && [Digits(messages.lastObject) isEqualToString:Digits(status)],
          [NSString stringWithFormat:@"Replace All shows its progress and the matches so far (%lu messages, last %@, status %@)",
           (unsigned long)messages.count, messages.lastObject, status]);
    Check(![upper.string isEqualToString:LargeText()] && [upper.string hasPrefix:@"\\ections{"], @"Replace All changed the text");
    Check(upper.isEditable && !lower.isEditable, @"only the views it locked are made editable again");
    Check(task.sheetWasDue && !task.sheet, @"a task longer than the delay calls for the sheet; none on a window not shown");
    start = NSDate.date;
    [upper.undoManager undo];
    Check([upper.string isEqualToString:LargeText()], [NSString stringWithFormat:@"one undo restores the 10 MB text (%.2f s)", -start.timeIntervalSinceNow]);
    lower.editable = YES;

    // A text changed meanwhile behind the read-only views' backs is left alone, with an error.
    controller.settings.findString = @"\\w+";
    controller.settings.replaceString = @"x";
    [controller performAction:TSAdvancedFindActionReplaceAll inTextView:upper];
    [upper.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"%"];
    TSTestWaitForTask(controller, 60);
    Check(isError && [upper.string isEqualToString:[@"%" stringByAppendingString:LargeText()]] && upper.isEditable,
          @"a text changed meanwhile is left alone, with an error");
    [upper.textStorage replaceCharactersInRange:NSMakeRange(0, 1) withString:@""];

    // No match: one beep after the search, nothing changed
    beeps = 0;
    controller.settings.findString = @"zzzz";
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper) && beeps == 1 && [upper.string isEqualToString:LargeText()] && !upper.undoManager.canUndo,
          @"no match: one beep and the text as it was");
    TSAdvancedFindController.testTargetTextView = nil;
}

#pragma mark Find All and Multiple Replace

static void TestFindAllAndMultipleReplace(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    __block NSUInteger listed = 0;
    controller.findAllHandler = ^(TSAdvancedFindResults *results, NSTextView *textView) { listed = results.items.count; };
    TestDocument *document = [[TestDocument alloc] initWithText:LargeText()];
    NSTextView *view = document.upper;

    controller.settings.findString = @"\\w+";
    [controller performAction:TSAdvancedFindActionFindAll inTextView:view];
    TSAdvancedFindTask *task = controller.runningTask;
    RunFor(0.05);
    [task cancel];
    TSTestWaitForTask(controller, 10);
    Check(listed == 0 && view.isEditable, @"a cancelled Find All lists nothing");

    controller.settings.findString = @"\\\\textbf";
    [controller performAction:TSAdvancedFindActionFindAll inTextView:view];
    task = controller.runningTask;
    TSTestWaitForTask(controller, 60);
    Check(listed == 90000 && task.progress > 0.9, [NSString stringWithFormat:@"Find All lists 90,000 matches with its progress (%lu, %.2f)", (unsigned long)listed, task.progress]);

    // Multiple replace with hundreds of rules, cancelled and to the end.
    NSMutableArray<TSRegexReplacementRule *> *rules = [NSMutableArray array];
    for (int i = 0; i < 240; i++)
        [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:[NSString stringWithFormat:@"line %d\n", i * 370]
                                                              replaceString:[NSString stringWithFormat:@"LINE %d\n", i] usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil]];
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:TSRegexFindDefaultOptions
                                                       regularExpressionOptions:TSRegexFindDefaultOptions | TSRegexFindRegularExpression
                                                              replacementSyntax:TSRegexReplacementSyntaxICU];
    __block BOOL called = NO;
    __block TSRegexMultipleReplaceResult *done = nil;
    Check([controller applyMultipleReplace:set inTextView:view inSelection:NO completion:^(TSRegexMultipleReplaceResult *result) { called = YES; done = result; }],
          @"multiple replace starts");
    Check(![controller applyMultipleReplace:set inTextView:view inSelection:NO completion:nil], @"a second one does not start while the first runs");
    [controller.runningTask cancel];
    TSTestWaitForTask(controller, 30);
    Check(called && !done && [view.string isEqualToString:LargeText()] && view.isEditable, @"a cancelled multiple replace changes nothing");
    NSDate *start = NSDate.date;
    [controller applyMultipleReplace:set inTextView:view inSelection:NO completion:^(TSRegexMultipleReplaceResult *result) { done = result; }];
    NSMutableArray<NSNumber *> *progress = [NSMutableArray array];
    NSMutableOrderedSet<NSString *> *messages = [NSMutableOrderedSet orderedSet];
    WaitWatching(controller, 180, progress, messages);
    // "Rule 37 of 240" under a bar that runs over all the rules
    NSString *ruleFormat = TSAdvancedFindLocalized(@"MultipleReplace.RuleProgress", @"Rule %1$lu of %2$lu");
    NSString *lastRule = [NSString localizedStringWithFormat:ruleFormat, (unsigned long)240, (unsigned long)240];
    NSUInteger ruleMessages = 0;
    for (NSUInteger i = 1; i <= 240; i++)
        ruleMessages += [messages containsObject:[NSString localizedStringWithFormat:ruleFormat, (unsigned long)i, (unsigned long)240]];
    Check(ProgressFills(progress) && [messages.lastObject isEqualToString:lastRule] && ruleMessages >= 3 && ruleMessages + 1 >= messages.count,
          [NSString stringWithFormat:@"multiple replace shows which rule it is on (%lu rule messages, last %@)", (unsigned long)ruleMessages, messages.lastObject]);
    printf("  240 rules on 10 MB: %.2f s\n", -start.timeIntervalSinceNow);
    Check(done.totalCount == 240 && [view.string containsString:@"LINE 239\n"] && ![view.string containsString:@"line 370\n"],
          [NSString stringWithFormat:@"240 rules on 10 MB (%lu replaced)", (unsigned long)done.totalCount]);
    [view.undoManager undo];
    Check([view.string isEqualToString:LargeText()], @"one undo takes back the multiple replacement");
}

/// The window's Highlight and Replace All buttons, found by their actions.
static NSArray<NSControl *> *ActionButtons(TSMultipleReplaceWindowController *window)
{
    NSMutableArray<NSControl *> *buttons = [NSMutableArray array];
    NSMutableArray<NSView *> *pending = [window.window.contentView.subviews mutableCopy];
    while (pending.count) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSButton class]] && (((NSButton *)v).action == NSSelectorFromString(@"highlight:") || ((NSButton *)v).action == NSSelectorFromString(@"replaceAll:")))
            [buttons addObject:(NSControl *)v];
    }
    return buttons.count == 2 ? buttons : @[];
}

/// The multiple replacement window grays Highlight and Replace All while a task runs, and its run reports at the end.
static void TestMultipleReplaceWindow(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:directory];
    library.usesTrash = NO;
    TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"\\\\textbf" replaceString:@"\\\\textit" usesRegularExpression:YES
                                                                          ignoresCase:NO enabled:YES note:nil];
    [library saveSet:[[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:TSRegexFindDefaultOptions
                                         regularExpressionOptions:TSRegexFindDefaultOptions | TSRegexFindRegularExpression
                                                replacementSyntax:TSRegexReplacementSyntaxICU] named:@"Italic" error:NULL];
    TSMultipleReplaceWindowController *window = [[TSMultipleReplaceWindowController alloc] initWithFindController:controller library:library];
    TestDocument *document = [[TestDocument alloc] initWithText:LargeText()];
    TSAdvancedFindController.testTargetTextView = document.upper;
    [window updateButtons];
    Check(AllEnabled(ActionButtons(window), YES), @"the window's Highlight and Replace All are enabled before");
    Check([window replaceAllInTextView:nil], @"the window's Replace All starts");
    Check(AllEnabled(ActionButtons(window), NO), @"while it runs, the window's Highlight and Replace All are gray");
    Check(![window highlightInTextView:nil] && [TSAdvancedFindHighlights existingHighlightsForTextStorage:document.storage].ranges.count == 0,
          @"while it runs, Highlight is refused");
    Check(TSTestWaitForTask(controller, 60) && AllEnabled(ActionButtons(window), YES), @"after it, they are enabled again");
    Check([window.statusField.stringValue containsString:@"90"],
          [NSString stringWithFormat:@"the status comes at the end (%@)", window.statusField.stringValue]);
    TSAdvancedFindController.testTargetTextView = nil;
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
}

#pragma mark Find All while output comes in

static NSArray<NSValue *> *RangesOf(NSString *word, NSString *text)
{
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSRange search = NSMakeRange(0, text.length);
    while (YES) {
        NSRange found = [text rangeOfString:word options:0 range:search];
        if (found.location == NSNotFound)
            return ranges;
        [ranges addObject:[NSValue valueWithRange:found]];
        search = NSMakeRange(NSMaxRange(found), text.length - NSMaxRange(found));
    }
}

/// A read-only text view that receives output while Find All searches it (the console or the log during a
/// typesetting): the list follows the changes made meanwhile instead of being thrown away. Replace All and Multiple
/// Replace still refuse a text changed meanwhile (tested above).
static void TestFindAllWhileOutputComes(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    __block BOOL error = NO;
    controller.statusHandler = ^(NSString *message, BOOL isError) { error = error || isError; };
    __block TSAdvancedFindResults *listed = nil;
    controller.findAllHandler = ^(TSAdvancedFindResults *results, NSTextView *textView) { listed = results; };
    NSMutableString *log = [NSMutableString string];
    for (int i = 0; i < 400; i++)
        [log appendFormat:@"Page %04d of the log: Overfull \\hbox (%d.0pt too wide) in paragraph at lines %d--%d\n", i + 1, i % 9, i, i + 2];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    TSAdvancedFindTextView *output = [[TSAdvancedFindTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    window.contentView = output;
    output.string = log;
    output.editable = NO;
    NSArray<NSValue *> *found = RangesOf(@"Overfull", output.string);
    controller.settings.options = TSRegexFindDefaultOptions;
    controller.settings.findString = @"Overfull";
    Check([controller performAction:TSAdvancedFindActionFindAll inTextView:output], @"Find All starts in a read-only text view");
    // Before the search can end (its end comes on this thread): output comes in, the start is cut, a match is touched.
    [output.textStorage replaceCharactersInRange:NSMakeRange(output.string.length, 0) withString:@"\nOverfull \\hbox (1.0pt too wide) in paragraph at lines 1--2\n"];
    [output.textStorage replaceCharactersInRange:NSMakeRange(0, 10) withString:@""];
    NSRange second = NSMakeRange(found[1].rangeValue.location - 10, 1);
    [output.textStorage replaceCharactersInRange:second withString:@"o"];
    Check(TSTestWaitForTask(controller, 30), @"Find All ends");
    Check(listed && !error, @"the list is shown, without the error of a text that changed meanwhile");
    NSArray<TSAdvancedFindResultItem *> *items = listed.items;
    Check(items.count == found.count, [NSString stringWithFormat:@"the list has the %lu matches of the text searched (%lu)", (unsigned long)found.count, (unsigned long)items.count]);
    BOOL moved = items.count == found.count;
    for (NSUInteger i = 0; moved && i < items.count; i++) {
        NSRange range = items[i].currentRange;
        moved = i == 1 ? items[i].stale
                       : !items[i].stale && range.location == found[i].rangeValue.location - 10 && [[output.string substringWithRange:range] isEqualToString:@"Overfull"];
    }
    Check(moved, @"each match moved with the changes made during the search; the touched one is stale");
    Check(!output.isEditable, @"a read-only view stays read-only");
    [output.textStorage replaceCharactersInRange:NSMakeRange(0, output.string.length) withString:@""]; // a new typesetting
    Check(listed.staleCount == items.count, @"a new typesetting makes every match stale");
}

#pragma mark Cache

static void TestCache(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);
    TestDocument *first = [[TestDocument alloc] initWithText:@"ab ab ab"];
    TestDocument *second = [[TestDocument alloc] initWithText:@"ab"];
    NSTextView *view = first.upper;
    TSAdvancedFindMatchCache *cache = [TSAdvancedFindMatchCache cacheForTextStorage:view.textStorage];
    __block NSString *status = @"";
    controller.statusHandler = ^(NSString *message, BOOL isError) { status = message; };
    controller.settings.options = TSRegexFindDefaultOptions;
    controller.settings.findString = @"ab";
    view.selectedRange = NSMakeRange(0, 0);
    [controller performAction:TSAdvancedFindActionNext inTextView:view];
    NSUInteger hits = cache.hits;
    [controller performAction:TSAdvancedFindActionNext inTextView:view];
    Check(cache.hits == hits + 1 && NSEqualRanges(view.selectedRange, NSMakeRange(3, 2)), @"the second Next uses the cached matches");
    [first.lower insertText:@" ab" replacementRange:NSMakeRange(8, 0)]; // typing in the other view of the split window
    hits = cache.hits;
    [controller performAction:TSAdvancedFindActionNext inTextView:view];
    Check(cache.hits == hits && [status containsString:@"4"], [NSString stringWithFormat:@"typing clears the cache: the new match counts (%@)", status]);
    [first.lower.undoManager undo];
    hits = cache.hits;
    [controller performAction:TSAdvancedFindActionHighlight inTextView:view];
    Check(cache.hits == hits && [status containsString:@"3"], [NSString stringWithFormat:@"Undo clears the cache (%@)", status]);
    [view.textStorage addAttribute:NSForegroundColorAttributeName value:NSColor.redColor range:NSMakeRange(0, 2)];
    hits = cache.hits;
    [controller performAction:TSAdvancedFindActionHighlight inTextView:view];
    Check(cache.hits == hits + 1, @"a change of colors (syntax coloring) keeps the cache");
    [controller performAction:TSAdvancedFindActionHighlight inTextView:second.upper];
    Check([status containsString:@"1"], [NSString stringWithFormat:@"another document has its own cache (%@)", status]);
    controller.settings.findString = @"AB";
    [controller performAction:TSAdvancedFindActionHighlight inTextView:view];
    Check([status containsString:@"0"], [NSString stringWithFormat:@"AB is not found with case (%@)", status]);
    controller.settings.options = TSRegexFindDefaultOptions | TSRegexFindIgnoreCase;
    hits = cache.hits;
    [controller performAction:TSAdvancedFindActionHighlight inTextView:view];
    Check(cache.hits == hits && [status containsString:@"3"], [NSString stringWithFormat:@"the same string with other options is another search (%@)", status]);
    controller.settings.options = TSRegexFindDefaultOptions;
    controller.lineEndingHandler = ^NSString *(NSTextView *textView) { return @"\r\n"; };
    controller.settings.findString = @"ab";
    hits = cache.hits;
    [controller performAction:TSAdvancedFindActionHighlight inTextView:view];
    Check(cache.hits == hits, @"another line ending is another search");
    // A replacement clears it too: the matches after Replace All are those of the new text.
    controller.lineEndingHandler = ^NSString *(NSTextView *textView) { return @"\n"; };
    controller.settings.replaceString = @"abab";
    TSTestPerform(controller, TSAdvancedFindActionReplaceAll, view);
    [controller performAction:TSAdvancedFindActionHighlight inTextView:view];
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges.count == 6, @"after Replace All the cache has the new matches");
}

#pragma mark Sheet

static void TestSheet(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    TSAdvancedFindTask *task = [[TSAdvancedFindTask alloc] initWithTitle:TSAdvancedFindLocalized(@"AdvancedFind.ReplaceAll", @"Replace All") textView:view];
    TSAdvancedFindProgressSheet *sheet = [[TSAdvancedFindProgressSheet alloc] initWithTask:task];
    NSView *content = sheet.window.contentView;
    [content layoutSubtreeIfNeeded];
    NSRect cancel = [sheet.cancelButton convertRect:sheet.cancelButton.bounds toView:content];
    NSRect bar = [sheet.progressBar convertRect:sheet.progressBar.bounds toView:content];
    Check([sheet.cancelButton.keyEquivalent isEqualToString:@"\e"] && sheet.cancelButton.title.length == 0 && sheet.cancelButton.image
          && NSMinX(cancel) > NSMaxX(bar) && fabs(NSMidY(cancel) - NSMidY(bar)) < 1 && sheet.cancelButton.toolTip.length > 0,
          [NSString stringWithFormat:@"Cancel is an × right of the bar, with a tooltip, and answers Escape (× %@, bar %@)", NSStringFromRect(cancel), NSStringFromRect(bar)]);
    Check([sheet.cancelButton.toolTip isEqualToString:TSAdvancedFindLocalized(@"AdvancedFind.Cancel", @"Cancel")]
          && [sheet.cancelButton.image.accessibilityDescription isEqualToString:sheet.cancelButton.toolTip], @"its tooltip and its spoken name are Cancel");
    Check(sheet.progressBar.isIndeterminate, @"no progress known: the bar moves on its own");
    Check(sheet.cancelButton.controlSize == NSControlSizeSmall && sheet.progressBar.controlSize == NSControlSizeSmall
          && sheet.messageField.font.pointSize <= NSFont.smallSystemFontSize, @"every part of the sheet is small");
    task.progress = 0.5;
    task.message = @"Searching… 12";
    [sheet update];
    Check(!sheet.progressBar.isIndeterminate && sheet.progressBar.doubleValue == 0.5 && [sheet.messageField.stringValue isEqualToString:@"Searching… 12"], @"the sheet follows the task");
    [sheet.cancelButton performClick:nil];
    Check(task.isCancelled && !sheet.cancelButton.isEnabled
          && [sheet.messageField.stringValue isEqualToString:TSAdvancedFindLocalized(@"AdvancedFind.Cancelling", @"Cancelling…")], @"Cancel cancels the task once and says so");

    // A short task never calls for the sheet.
    TSAdvancedFindTask *quick = [[TSAdvancedFindTask alloc] initWithTitle:@"Find All" textView:view];
    quick.sheetDelay = 0.3;
    __block BOOL finished = NO;
    [quick runWork:^id(TSAdvancedFindTask *t) { return @1; } completion:^(id result, BOOL cancelled) { finished = YES; }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished && limit.timeIntervalSinceNow > 0)
        RunFor(0.01);
    RunFor(0.4);
    Check(finished && !quick.sheetWasDue, @"a task shorter than the delay shows no sheet");
}

#pragma mark Layout and images

/// Windows that are never shown do not draw buttons; each button's own cell is drawn at its measured frame (the
/// method of Tests/AdvancedFindPanel.m). Window glass and translucency are not reproduced.
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
            if (![v isKindOfClass:[NSButton class]] || v.isHiddenOrHasHiddenAncestor)
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

/// A label shows all of its text on its one line.
static int CheckLabelFits(NSTextField *label, NSString *name)
{
    if (label.stringValue.length == 0)
        return 0;
    BOOL cut = label.cell.cellSize.width > NSWidth(label.frame) + 0.5;
    if (cut)
        printf("FAIL %s: label cut: %s (%.0f wide, needs %.0f)\n", name.UTF8String, label.stringValue.UTF8String, NSWidth(label.frame), label.cell.cellSize.width);
    return cut ? 1 : 0;
}

/// The sheet of each long action in this language, with its longest message: every part inside, nothing cut. Images
/// on request (Replace All half done, light and dark).
static void TestSheetLayout(NSString *_Nullable imageDirectory)
{
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    NSArray<NSString *> *titles = @[TSAdvancedFindLocalized(@"AdvancedFind.ReplaceAll", @"Replace All"), TSAdvancedFindLocalized(@"AdvancedFind.FindAll", @"Find All"),
                                    TSAdvancedFindLocalized(@"MultipleReplace.Action", @"Multiple Replace")];
    NSArray<NSString *> *messages = @[TSAdvancedFindLocalized(@"AdvancedFind.Searching", @"Searching…"),
        [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"AdvancedFind.SearchingCount", @"Searching… %lu"), 12345678UL],
        [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.RuleProgress", @"Rule %1$lu of %2$lu"), 1234UL, 1234UL],
        TSAdvancedFindLocalized(@"AdvancedFind.Cancelling", @"Cancelling…")];
    for (NSString *title in titles) {
        TSAdvancedFindTask *task = [[TSAdvancedFindTask alloc] initWithTitle:title textView:view];
        TSAdvancedFindProgressSheet *sheet = [[TSAdvancedFindProgressSheet alloc] initWithTask:task];
        NSView *content = sheet.window.contentView;
        for (NSString *message in messages) {
            task.message = message;
            task.progress = 0.4;
            [sheet update];
            [content layoutSubtreeIfNeeded];
            NSString *name = [NSString stringWithFormat:@"%@ sheet of %@", language, title];
            failures += CheckLabelFits(sheet.messageField, name);
            for (NSView *v in content.subviews)
                if ([v isKindOfClass:[NSTextField class]])
                    failures += CheckLabelFits((NSTextField *)v, name);
            NSRect cancel = [sheet.cancelButton convertRect:sheet.cancelButton.bounds toView:content];
            Check(NSContainsRect(NSInsetRect(content.bounds, 19.5, 0), cancel), [NSString stringWithFormat:@"%@: the × is inside the margins", name]);
        }
    }
    // The other messages of a task, in the find panel's message line (checked there by the panel's own test): the
    // error of a text changed meanwhile, in the smallest panel.
    TSAdvancedFindController *controller = MakeController(&(NSUInteger){0});
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    [panel.window setContentSize:panel.window.contentMinSize];
    panel.statusField.stringValue = TSAdvancedFindLocalized(@"AdvancedFind.TextChanged", @"The text changed meanwhile; nothing was changed.");
    [panel.window.contentView layoutSubtreeIfNeeded];
    failures += CheckLabelFits(panel.statusField, [NSString stringWithFormat:@"%@ smallest panel", language]);
    panel.findBox.statusLabel.stringValue = TSAdvancedFindLocalized(@"AdvancedFind.Cancelled", @"Cancelled");
    [panel.window.contentView layoutSubtreeIfNeeded];
    failures += CheckLabelFits(panel.findBox.statusLabel, [NSString stringWithFormat:@"%@ find field", language]);

    if (!imageDirectory)
        return;
    [NSFileManager.defaultManager createDirectoryAtPath:imageDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    TSAdvancedFindTask *task = [[TSAdvancedFindTask alloc] initWithTitle:titles[0] textView:view];
    task.progress = 0.42;
    task.message = [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"AdvancedFind.SearchingCount", @"Searching… %lu"), 41234UL];
    TSAdvancedFindProgressSheet *sheet = [[TSAdvancedFindProgressSheet alloc] initWithTask:task];
    TSAdvancedFindTask *rules = [[TSAdvancedFindTask alloc] initWithTitle:titles[2] textView:view];
    rules.progress = 0.34;
    rules.message = [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.RuleProgress", @"Rule %1$lu of %2$lu"), 81UL, 240UL];
    TSAdvancedFindProgressSheet *ruleSheet = [[TSAdvancedFindProgressSheet alloc] initWithTask:rules];
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:name];
        NSString *tag = [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
        NSString *base = [imageDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", language, tag]];
        sheet.window.appearance = appearance;
        ruleSheet.window.appearance = appearance;
        [sheet update];
        [ruleSheet update];
        Check(WritePNG(sheet.window.contentView, appearance, [base stringByAppendingString:@"-progress.png"])
              && WritePNG(ruleSheet.window.contentView, appearance, [base stringByAppendingString:@"-progress-rules.png"]), @"images written");
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
            TestFindAllWhileOutputComes();
            TestCache();
            TestSheet();
        }
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"large"]) {
            TestReplaceAll();
            TestFindAllAndMultipleReplace();
            TestMultipleReplaceWindow();
        }
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"layout"])
            TestSheetLayout(images);
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
