// SPDX-License-Identifier: GPL-2.0-or-later
// The Advanced Find panel in the console, the log and the Experiment windows: the shipped TSDocument nibs (12
// languages) make the console and the log TSAdvancedFindTextViews, the Experiment controller makes its output one, and
// all of them route the Find menu by the find method, gray the replacing actions when read-only and draw the highlights
// (checked in pixels). The panel acts on the Experiment panels, which never become main. Find All runs while TeX's
// output comes in, and the text views are read-only meanwhile, then as before. Built by
// Tests/run-advanced-find-consoles.py; no window is ever shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSLayoutManager.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"
#import "TSAdvancedFindController+MultipleReplace.h"
#import "AdvancedFindTaskWait.h"
#import "TSExperimentConsoleController.h"
#import "TestDocumentFind.h"
#import "TSAdvancedFindResults.h"
#import "TSConsoleOutput.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

@interface TSExperimentConsoleController (Testing)
- (void)appendText:(NSString *)text;
- (void)updateConsoleColors:(NSNotification *)notification;
@end

#pragma mark The shared controller, the menu and the windows of the tests

/// The shared controller: in-memory defaults and a unique find pasteboard, not the system's.
static TSAdvancedFindController *TestShared;
static NSUInteger beeps, validations, textViewFinds;
static id SharedForTests(id self, SEL _cmd) { return TestShared; }
static IMP originalValidate;
static BOOL CountValidate(id self, SEL _cmd, NSInteger action, NSTextView *view)
{
    validations++;
    return ((BOOL (*)(id, SEL, NSInteger, NSTextView *))originalValidate)(self, _cmd, action, view);
}
/// NSTextView's own find (the Apple panel or the find bar) is only counted: it would show a panel.
static void RecordTextViewFind(id self, SEL _cmd, id sender) { textViewFinds++; }

/// The key window and the shown windows, as the window server would have them; nothing is ordered.
static __weak NSWindow *TestKeyWindow;
static NSHashTable<NSWindow *> *TestVisibleWindows;
static IMP originalIsVisible;
static id KeyWindowForTests(id self, SEL _cmd) { return TestKeyWindow; }
static BOOL IsVisibleForTests(NSWindow *self, SEL _cmd)
{
    return [TestVisibleWindows containsObject:self] || ((BOOL (*)(id, SEL))originalIsVisible)(self, _cmd);
}

static NSMenuItem *Item(SEL action, NSInteger tag)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
    item.tag = tag;
    return item;
}

static const TSAdvancedFindAction finding[] = {TSAdvancedFindActionShowFindPanel, TSAdvancedFindActionShowReplacePanel, TSAdvancedFindActionNext,
    TSAdvancedFindActionPrevious, TSAdvancedFindActionSelectAll, TSAdvancedFindActionHighlight, TSAdvancedFindActionUnhighlight};
static const TSAdvancedFindAction replacing[] = {TSAdvancedFindActionReplace, TSAdvancedFindActionReplaceAndFind,
    TSAdvancedFindActionReplaceAll, TSAdvancedFindActionReplaceAllInSelection};

static NSString *SampleLog(NSUInteger pages)
{
    NSMutableString *log = [NSMutableString stringWithString:
        @"This is e-upTeX, Version 3.141592653-p4.1.1-u1.30-250316-2.6 (utf8.uptex) (TeX Live 2026) (preloaded format=uplatex)\n"
        @" restricted \\write18 enabled.\n"
        @"entering extended mode\n"
        @"(./sample.tex\n"
        @"LaTeX2e <2025-11-01>\n"
        @"(/Applications/TeXLive/2026/texmf-dist/tex/latex/jlreq/jlreq.cls\n"
        @"Document Class: jlreq 2025/10/01 jlreq\n"
        @"(./sample.aux)\n"];
    for (NSUInteger page = 1; page <= pages; page++) {
        NSUInteger line = page * 37;
        if (page % 3 == 1)
            [log appendFormat:@"\nOverfull \\hbox (%lu.%04lupt too wide) in paragraph at lines %lu--%lu\n[]\\JY2/hmc/m/n/10 関数 $f(x)$ を考える。[]\n",
                (unsigned long)(page % 17 + 1), (unsigned long)(page * 2731 % 10000), (unsigned long)line, (unsigned long)line + 4];
        if (page % 4 == 2)
            [log appendFormat:@"\nLaTeX Warning: Reference `fig:%lu' on page %lu undefined on input line %lu.\n",
                (unsigned long)page, (unsigned long)page, (unsigned long)line + 11];
        if (page % 5 == 0)
            [log appendString:@"\nUnderfull \\vbox (badness 10000) has occurred while \\output is active\n"];
        [log appendFormat:@"[%lu]%@", (unsigned long)page, page % 8 == 0 ? @"\n" : @" "];
    }
    return log;
}

static NSArray<NSValue *> *RangesOf(NSString *word, NSString *text)
{
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSRange search = NSMakeRange(0, text.length);
    for (NSRange found; (found = [text rangeOfString:word options:0 range:search]).location != NSNotFound;) {
        [ranges addObject:[NSValue valueWithRange:found]];
        search = NSMakeRange(NSMaxRange(found), text.length - NSMaxRange(found));
    }
    return ranges;
}

/// The color in the middle of the glyphs of `range`, just above the bottom of the line (background, not ink).
static NSColor *ColorAt(NSTextView *view, NSRange range)
{
    __block NSColor *color = nil;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
        NSRect rect = [view.layoutManager boundingRectForGlyphRange:[view.layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL]
                                                    inTextContainer:view.textContainer];
        rect = NSOffsetRect(rect, view.textContainerOrigin.x, view.textContainerOrigin.y);
        [view setNeedsDisplay:YES];
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        CGFloat scale = rep.pixelsWide / NSWidth(view.bounds);
        color = [[rep colorAtX:(NSInteger)(NSMidX(rect) * scale) y:(NSInteger)((NSMaxY(rect) - 1) * scale)] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    }];
    return color;
}

static BOOL SameColor(NSColor *a, NSColor *b)
{
    return a && b && fabs(a.redComponent - b.redComponent) < 0.02 && fabs(a.greenComponent - b.greenComponent) < 0.02 && fabs(a.blueComponent - b.blueComponent) < 0.02;
}

#pragma mark The shipped TSDocument nibs

/// File's Owner: the outlets of TSDocument that the tests use (the nib connects only outlets that the owner has).
@interface NibOwner : NSObject
@property (strong) NSTextView *outputText, *logTextView, *scrapTextView;
@end
@implementation NibOwner
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
@end

static NSMutableArray *keptNibObjects;

static NibOwner *LoadDocumentNib(NSString *path)
{
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];
    NibOwner *owner = [NibOwner new];
    NSArray *objects = nil;
    if (![nib instantiateWithOwner:owner topLevelObjects:&objects])
        return nil;
    [keptNibObjects addObjectsFromArray:objects];
    return owner;
}

static BOOL DrawsHighlightsAlone(NSTextView *view)
{
    return [view.layoutManager isKindOfClass:TSAdvancedFindLayoutManager.class] && view.textStorage.layoutManagers.count == 1
        && view.textContainer.layoutManager == view.layoutManager && view.layoutManager.textContainers.count == 1;
}

/// The console and the log of every language's nib route the find menu and draw the highlights.
static void TestNibs(NSArray<NSString *> *paths)
{
    for (NSString *path in paths) {
        NSString *language = path.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.lastPathComponent;
        NibOwner *owner = LoadDocumentNib(path);
        NSTextView *console = owner.outputText, *log = owner.logTextView;
        Check(owner && [console isKindOfClass:TSAdvancedFindTextView.class] && [log isKindOfClass:TSAdvancedFindTextView.class],
              [NSString stringWithFormat:@"%@: the console and the log are TSAdvancedFindTextViews", language]);
        Check(DrawsHighlightsAlone(console) && DrawsHighlightsAlone(log),
              [NSString stringWithFormat:@"%@: they get the layout manager that draws the highlights, in place of the old one", language]);
        Check(!console.isRichText && log.isRichText && log.usesRuler && console.enclosingScrollView.documentView == console,
              [NSString stringWithFormat:@"%@: the nib's settings are kept", language]);
        Check([(TSAdvancedFindTextView *)console refusesReplacing] && [(TSAdvancedFindTextView *)log refusesReplacing] && log.isEditable,
              [NSString stringWithFormat:@"%@: the console and the log refuse replacing; the log may still be edited", language]);
        Check(!console.window.isVisible && !log.window.isVisible, [NSString stringWithFormat:@"%@: nothing is shown", language]);
    }
}

#pragma mark Routing by the find method

static NSTextView *MakeConsole(NSString *nibPath)
{
    NSTextView *console = LoadDocumentNib(nibPath).outputText;
    console.editable = NO; // as after the first typesetting: "it is never editable"
    console.string = SampleLog(12);
    return console;
}

/// `source`: an editable TSAdvancedFindTextView that does not refuse replacing, as the Experiment source.
static void TestRouting(NSTextView *console, NSTextView *log, NSTextView *experiment, NSTextView *source)
{
    TestShared.settings.findString = @"Overfull";
    TestShared.settings.replaceString = @"X";
    TestShared.settings.options = TSRegexFindDefaultOptions;
    TestShared.settings.inSelection = NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSNumber *method in @[@0, @1, @2]) {
        [defaults setInteger:method.integerValue forKey:@"FindMethod"];
        textViewFinds = validations = 0;
        for (NSTextView *view in @[console, log, experiment]) {
            [view performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionNext)];
            [view performTextFinderAction:Item(@selector(performTextFinderAction:), NSTextFinderActionShowReplaceInterface)];
            [view validateMenuItem:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)];
            [view validateMenuItem:Item(@selector(performTextFinderAction:), TSAdvancedFindActionHighlight)];
            Check([(TSAdvancedFindTextView *)view findController] == nil, @"with another find method, no controller");
        }
        Check(textViewFinds == 6 && validations == 0,
              [NSString stringWithFormat:@"find method %@: the Find menu of the console, the log and the Experiment output stays with NSTextView", method]);
    }
    [defaults setInteger:3 forKey:@"FindMethod"];
    textViewFinds = 0;
    for (NSTextView *view in @[console, log, experiment])
        Check([(TSAdvancedFindTextView *)view findController] == TestShared, @"with the Advanced Find panel, the shared controller");
    // The menu: finding everywhere; replacing neither in the read-only console and Experiment output, nor in the log,
    // which may be edited but shows TeX's output; replacing in the Experiment source.
    for (size_t i = 0; i < sizeof finding / sizeof finding[0]; i++)
        for (NSTextView *view in @[console, experiment, log])
            Check([view validateMenuItem:Item(@selector(performFindPanelAction:), finding[i])] && [view validateMenuItem:Item(@selector(performTextFinderAction:), finding[i])],
                  [NSString stringWithFormat:@"the read-only console and Experiment output take the find action %ld", (long)finding[i]]);
    for (size_t i = 0; i < sizeof replacing / sizeof replacing[0]; i++) {
        for (NSTextView *view in @[console, experiment, log])
            Check(![view validateMenuItem:Item(@selector(performFindPanelAction:), replacing[i])] && ![view validateMenuItem:Item(@selector(performTextFinderAction:), replacing[i])],
                  [NSString stringWithFormat:@"the console, the Experiment output and the log gray the replacing action %ld", (long)replacing[i]]);
        Check([source validateMenuItem:Item(@selector(performFindPanelAction:), replacing[i])],
              [NSString stringWithFormat:@"the Experiment source takes the replacing action %ld", (long)replacing[i]]);
    }
    // ⌘G finds in the console; replacing is refused with one beep each, and nothing changes.
    console.selectedRange = NSMakeRange(0, 0);
    [console performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionNext)];
    Check(NSEqualRanges(console.selectedRange, RangesOf(@"Overfull", console.string).firstObject.rangeValue), @"⌘G in the console selects the first match");
    NSString *before = [console.string copy];
    beeps = 0;
    [console performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)];
    [console performTextFinderAction:Item(@selector(performTextFinderAction:), NSTextFinderActionReplace)];
    Check([console.string isEqualToString:before] && beeps == 2, @"replacing in the console is refused with a beep each time");
    experiment.selectedRange = NSMakeRange(0, 0);
    [experiment performTextFinderAction:Item(@selector(performTextFinderAction:), NSTextFinderActionNextMatch)];
    Check(NSEqualRanges(experiment.selectedRange, RangesOf(@"Overfull", experiment.string).firstObject.rangeValue), @"Find Next in the Experiment output");
    // The log refuses Replace All too; the console before the first typesetting, still editable, as well.
    log.string = @"Overfull Overfull";
    beeps = 0;
    [log performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)];
    console.editable = YES;
    [console performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)];
    console.editable = NO;
    Check([log.string isEqualToString:@"Overfull Overfull"] && [console.string isEqualToString:before] && beeps == 2,
          @"the log and the editable console refuse Replace All with a beep");
    // A multiple replacement (from its window or the menu) is refused in all three as well.
    TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"Overfull" replaceString:@"X" usesRegularExpression:NO
                                                                          ignoresCase:NO enabled:YES note:nil];
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:TSRegexMultipleReplace.defaultTextualOptions
                                                       regularExpressionOptions:TSRegexMultipleReplace.defaultRegularExpressionOptions
                                                              replacementSyntax:TSRegexReplacementSyntaxICU];
    NSString *beforeExperiment = [experiment.string copy];
    Check(![TestShared applyMultipleReplace:set inTextView:console inSelection:NO completion:nil]
          && ![TestShared applyMultipleReplace:set inTextView:log inSelection:NO completion:nil]
          && ![TestShared applyMultipleReplace:set inTextView:experiment inSelection:NO completion:nil] && !TestShared.runningTask && [console.string isEqualToString:before]
          && [log.string isEqualToString:@"Overfull Overfull"] && [experiment.string isEqualToString:beforeExperiment],
          @"a multiple replacement is refused in the console, the log and the Experiment output");
    // Replace All in the Experiment source works as in a document, and so does a multiple replacement.
    source.string = @"Overfull Overfull";
    // Both run as background tasks.
    Check([TestShared applyMultipleReplace:set inTextView:source inSelection:NO completion:nil] && TSTestWaitForTask(TestShared, 60)
          && [source.string isEqualToString:@"X X"], @"a multiple replacement in the Experiment source");
    source.string = @"Overfull Overfull";
    [source performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)];
    Check(TSTestWaitForTask(TestShared, 60) && [source.string isEqualToString:@"X X"] && source.isEditable, @"Replace All in the Experiment source");
    Check(textViewFinds == 0, @"none of it reaches NSTextView's own find");
    // Back to the find bar without a restart.
    [defaults setInteger:1 forKey:@"FindMethod"];
    textViewFinds = 0;
    [console performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionNext)];
    Check(textViewFinds == 1, @"switching the find method back takes effect at once");
    [defaults setInteger:3 forKey:@"FindMethod"];
}

#pragma mark Highlights in pixels

static void TestHighlights(NSTextView *view, NSString *name, void (^append)(NSString *))
{
    NSRange match = RangesOf(@"Overfull", view.string).firstObject.rangeValue;
    NSColor *plain = ColorAt(view, match);
    TestShared.settings.findString = @"(Over|Under)full \\\\[hv]box";
    TestShared.settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    [view performFindPanelAction:Item(@selector(performFindPanelAction:), TSAdvancedFindActionHighlight)];
    NSUInteger expected = RangesOf(@"full \\", view.string).count;
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges.count == expected,
          [NSString stringWithFormat:@"%@: Highlight All from the menu highlights every match", name]);
    NSColor *lit = ColorAt(view, match);
    Check(!SameColor(lit, plain), [NSString stringWithFormat:@"%@: the highlight shows (%@ → %@)", name, plain, lit]);
    append(@"\nOverfull \\hbox (1.0pt too wide) in paragraph at lines 1--2\n");
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges.count == expected && SameColor(ColorAt(view, match), lit),
          [NSString stringWithFormat:@"%@: output that comes in keeps the highlights", name]);
    [view performTextFinderAction:Item(@selector(performTextFinderAction:), TSAdvancedFindActionUnhighlight)];
    Check(SameColor(ColorAt(view, match), plain), [NSString stringWithFormat:@"%@: Remove Highlights clears them", name]);
}

#pragma mark The target of the panel

/// A document window, such as the preview, as it is when shown: it can become main (a window that is never shown
/// cannot).
@interface MainCapableWindow : NSWindow
@end
@implementation MainCapableWindow
- (BOOL)canBecomeMainWindow { return YES; }
@end

static void TestPanelTarget(TSExperimentConsoleController *experimentController, NSTextView *log)
{
    TSAdvancedFindPanelController *panel = TSAdvancedFindPanelController.sharedPanelController;
    Check(panel.findController == TestShared, @"the shared panel works on the shared controller");
    NSWindow *panelWindow = panel.window;
    NSTextView *output = (NSTextView *)experimentController.outputText;
    NSWindow *experiment = output.window;
    Check(![experiment canBecomeMainWindow], @"the Experiment output is a panel, which never becomes main");
    NSWindow *document = log.window;
    NSWindow *preview = [[MainCapableWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    preview.releasedWhenClosed = NO;
    NSButton *button = [NSButton buttonWithTitle:@"PDF" target:nil action:nil];
    [preview.contentView addSubview:button];
    for (NSWindow *window in @[experiment, document, preview, panelWindow])
        [TestVisibleWindows addObject:window];
    [experiment makeFirstResponder:output];
    [document makeFirstResponder:log];
    [panelWindow makeFirstResponder:panel.findField];
    [preview makeFirstResponder:preview.contentView];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    void (^key)(NSWindow *, NSWindow *) = ^(NSWindow *from, NSWindow *to) {
        TestKeyWindow = to;
        if (from)
            [center postNotificationName:NSWindowDidResignKeyNotification object:from];
        [center postNotificationName:NSWindowDidBecomeKeyNotification object:to];
    };
    TSAdvancedFindController.testTargetTextView = nil;

    key(nil, experiment);
    Check(TSAdvancedFindController.targetTextView == output, @"the Experiment output in front is the target");
    key(experiment, panelWindow);
    Check(TSAdvancedFindController.targetTextView == output, @"clicking the panel keeps the Experiment output as its target");
    // The panel's buttons act on it: Next finds there; Replace All beeps and changes nothing.
    TestShared.settings.findString = @"Overfull";
    TestShared.settings.options = TSRegexFindDefaultOptions;
    output.selectedRange = NSMakeRange(0, 0);
    [panel advancedFindNext:nil];
    Check(NSEqualRanges(output.selectedRange, RangesOf(@"Overfull", output.string).firstObject.rangeValue), @"the panel's Next finds in the Experiment output");
    NSString *before = [output.string copy];
    beeps = 0;
    [panel advancedReplaceAll:nil];
    Check(beeps == 1 && [output.string isEqualToString:before], @"the panel's Replace All beeps in the read-only Experiment output");

    [TestVisibleWindows removeObject:experiment];
    Check(TSAdvancedFindController.targetTextView == nil, @"once the Experiment output is closed, it is not the target");
    [TestVisibleWindows addObject:experiment];

    key(panelWindow, preview);
    Check(TSAdvancedFindController.targetTextView == nil, @"a window without a text view in front: no target, as before");
    key(preview, panelWindow);
    Check(TSAdvancedFindController.targetTextView == nil, @"and the panel does not bring back an older one");

    key(panelWindow, document);
    Check(TSAdvancedFindController.targetTextView == log, @"the log in front is the target");
    // Another text view of the same window gets the focus (as the other half of a split source), with no key change.
    TSAdvancedFindTextView *other = [[TSAdvancedFindTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
    [document.contentView addSubview:other];
    [document makeFirstResponder:other];
    Check(TSAdvancedFindController.targetTextView == other, @"the focused text view of the window in front is the target");
    key(document, panelWindow);
    Check(TSAdvancedFindController.targetTextView == other, @"clicking the panel keeps the one that had the focus");
    [document makeFirstResponder:log];
    [other removeFromSuperview];
    key(panelWindow, document);
    key(document, panelWindow);
    Check(TSAdvancedFindController.targetTextView == log, @"clicking the panel keeps the log as its target");

    // The focus moved inside the window (another text view) before it stopped being key.
    key(panelWindow, experiment);
    key(experiment, panelWindow);
    Check(TSAdvancedFindController.targetTextView == output, @"the last focused text view is the target");
    TestKeyWindow = nil;
    for (NSWindow *window in @[experiment, document, preview, panelWindow])
        [TestVisibleWindows removeObject:window];
}

#pragma mark Buttons

static void TestButtons(NSTextView *console, NSTextView *log, NSTextView *source)
{
    TSAdvancedFindPanelController *panel = TSAdvancedFindPanelController.sharedPanelController;
    NSArray<NSControl *> *buttons = panel.buttons; // Highlight All ▾, Replace All, Replace & Find ▾, ‹ ›
    NSMenu *replaceMenu = ((NSComboButton *)buttons[2]).menu, *allMenu = ((NSComboButton *)buttons[0]).menu;
    id<NSMenuItemValidation> validator = (id<NSMenuItemValidation>)panel;
    TSAdvancedFindController.testTargetTextView = console;
    [panel updateButtons];
    Check(buttons[0].enabled && !buttons[1].enabled && !buttons[2].enabled && buttons[3].enabled,
          @"acting on the console, Replace All and Replace & Find are gray, Highlight All and ‹ › are not");
    Check(![validator validateMenuItem:replaceMenu.itemArray[0]] && [validator validateMenuItem:allMenu.itemArray[0]],
          @"under ▾, Replace is gray in the console, Select All is not");
    TSAdvancedFindController.testTargetTextView = log;
    [panel updateButtons];
    Check(buttons[0].enabled && !buttons[1].enabled && !buttons[2].enabled && buttons[3].enabled && ![validator validateMenuItem:replaceMenu.itemArray[0]],
          @"acting on the log, which may be edited, the replacing buttons are gray too");
    TSAdvancedFindController.testTargetTextView = source;
    [panel updateButtons];
    Check(buttons[0].enabled && buttons[1].enabled && buttons[2].enabled && buttons[3].enabled && [validator validateMenuItem:replaceMenu.itemArray[0]],
          @"acting on the Experiment source, everything");
    TSAdvancedFindController.testTargetTextView = nil;
    Check(!panel.window.isVisible, @"the panel is not shown");
}

#pragma mark Leaving the Advanced Find panel

static void TestLeavingThePanel(NSTextView *console, NSTextView *log, NSTextView *experiment)
{
    TestDocumentFind *document = [TestDocumentFind new];
    NSTextView *source = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    NSTextView *scrap = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    document->textView1 = source;
    document->outputText = console;
    document->scrapTextView = scrap;
    document.logTextView = log;
    document.experimentConsole = [TestExperimentConsole new];
    document.experimentConsole.outputText = experiment;
    NSArray<NSTextView *> *views = @[source, console, log, scrap, experiment];
    for (NSTextView *view in views) {
        view.string = @"Overfull Overfull";
        [TSAdvancedFindHighlights highlightsForTextStorage:view.textStorage].ranges = @[[NSValue valueWithRange:NSMakeRange(0, 8)]];
    }
    [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"FindMethod"];
    [document findInterfacePreferencesChanged:nil];
    for (NSTextView *view in views)
        Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges.count == 1, @"with the panel kept, the highlights stay");
    [NSUserDefaults.standardUserDefaults setInteger:1 forKey:@"FindMethod"];
    [document findInterfacePreferencesChanged:nil];
    NSArray<NSString *> *names = @[@"source", @"console", @"log", @"Experiment source", @"Experiment output"];
    for (NSUInteger i = 0; i < views.count; i++)
        Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:views[i].textStorage].ranges.count == 0,
              [NSString stringWithFormat:@"away from the panel, the highlights of the %@ go", names[i]]);
    Check(console.usesFindBar && log.usesFindBar, @"the console and the log get the find bar again");
    [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"FindMethod"];
    [document findInterfacePreferencesChanged:nil];
}

#pragma mark Find All while output comes in, and the text views read-only meanwhile

/// The search of Find All waits at this gate while it is set, so that output can come in while the task runs.
static dispatch_semaphore_t SearchGate;
static IMP originalItemsOfFind;
static id GatedItemsOfFind(id self, SEL _cmd, id find, id cancellation, id progress)
{
    dispatch_semaphore_t gate = SearchGate;
    if (gate)
        dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    return ((id (*)(id, SEL, id, id, id))originalItemsOfFind)(self, _cmd, find, cancellation, progress);
}

static TSAdvancedFindResults *listed;

/// Starts Find All of "Overfull" in `view`; its search waits at the gate. YES when a task runs.
static BOOL StartGatedFindAll(NSTextView *view)
{
    TestShared.settings.findString = @"Overfull";
    TestShared.settings.options = TSRegexFindDefaultOptions;
    TestShared.settings.inSelection = NO;
    listed = nil;
    TestShared.findAllHandler = ^(TSAdvancedFindResults *results, NSTextView *textView) { listed = results; };
    SearchGate = dispatch_semaphore_create(0);
    return [TestShared performAction:TSAdvancedFindActionFindAll inTextView:view] && TestShared.runningTask != nil;
}

/// Lets the search go on and waits for the end of the task. YES when it ended.
static BOOL FinishGatedFindAll(void)
{
    dispatch_semaphore_signal(SearchGate);
    BOOL ended = TSTestWaitForTask(TestShared, 60);
    SearchGate = nil;
    return ended;
}

static BOOL ListedAt(NSArray<NSValue *> *ranges, BOOL stale)
{
    if (listed.items.count != ranges.count)
        return NO;
    for (NSUInteger i = 0; i < ranges.count; i++)
        if (listed.items[i].isStale != stale || (!stale && !NSEqualRanges(listed.items[i].currentRange, ranges[i].rangeValue)))
            return NO;
    return YES;
}

/// The start of a typesetting (TSDocument-Jobs.m, taken verbatim by the script): the console is emptied and made
/// read-only.
void TestStartTypesetting(NSTextView *outputText, id self);

/// A real console from the nib, fed by the code that shows TeX's output, while Find All runs in it.
static void TestFindAllWhileOutputComes(NSString *nibPath, TSExperimentConsoleController *experimentController, NSTextView *log)
{
    NSTextView *console = MakeConsole(nibPath);
    NSString *output = @"\nOverfull \\hbox (2.0pt too wide) in paragraph at lines 3--4\n[]\\JY2/hmc/m/n/10 関数 []\n";
    NSArray<NSValue *> *before = RangesOf(@"Overfull", console.string);
    NSUInteger length = console.string.length;
    Check(StartGatedFindAll(console), @"Find All in the console runs as a background task");
    TSAppendConsoleOutput(console, output, nil);
    TSAppendConsoleOutput(console, output, NSColor.redColor);
    Check(console.string.length == length + 2 * output.length, @"TeX's output comes into the console while Find All runs");
    Check(FinishGatedFindAll() && ListedAt(before, NO), @"Find All lists the matches of the console as it was, at their places, after the output that came in");
    Check([console.string isEqualToString:[[console.string substringToIndex:length] stringByAppendingFormat:@"%@%@", output, output]] && !console.isEditable,
          @"the output stays, and the console stays read-only");
    TSAppendConsoleOutput(console, output, nil);
    Check(ListedAt(before, NO), @"the list follows the output that comes in later");
    // A new typesetting empties the console while Find All runs: the list is kept, every match stale.
    console.string = SampleLog(12);
    Check(StartGatedFindAll(console), @"Find All in the console again");
    TestStartTypesetting(console, nil);
    TSAppendConsoleOutput(console, output, nil);
    Check(FinishGatedFindAll() && ListedAt(before, YES) && listed.staleCount == before.count,
          @"a typesetting that started meanwhile makes every match of the list stale, and the list is not thrown away");
    // The Experiment output, emptied by a new run, and the log, filled again at the end of a typesetting.
    [experimentController.outputText setString:SampleLog(12)];
    Check(StartGatedFindAll(experimentController.outputText), @"Find All in the Experiment output");
    experimentController.outputText.string = @"";
    [experimentController appendText:output];
    Check(FinishGatedFindAll() && ListedAt(before, YES), @"a new Experiment run meanwhile makes the matches stale");
    log.string = SampleLog(12);
    Check(StartGatedFindAll(log), @"Find All in the log");
    log.string = [@"(./sample.tex)\n" stringByAppendingString:SampleLog(12)];
    Check([log.string hasPrefix:@"(./sample.tex)\n"], @"the log is filled again while Find All runs in it");
    Check(FinishGatedFindAll() && ListedAt(before, YES), @"the log filled again meanwhile makes the matches stale");
}

/// While a task runs, every text view that could be edited is read-only; afterwards each is as before. Output still
/// comes in.
static void TestReadOnlyMeanwhile(NSString *nibPath, TSExperimentConsoleController *experimentController, NSTextView *log, NSTextView *source)
{
    NSTextView *console = MakeConsole(nibPath), *experiment = experimentController.outputText;
    NSTextView *fresh = LoadDocumentNib(nibPath).outputText; // before the first typesetting
    fresh.string = SampleLog(12);
    log.string = SampleLog(12);
    source.string = SampleLog(12);
    experiment.string = SampleLog(12);
    NSArray<NSTextView *> *views = @[console, fresh, log, experiment, source];
    NSArray<NSString *> *names = @[@"the console", @"the console before the first typesetting", @"the log", @"the Experiment output", @"the Experiment source"];
    for (NSUInteger i = 0; i < views.count; i++) {
        NSTextView *view = views[i];
        NSString *name = names[i];
        BOOL editable = view.isEditable;
        NSString *text = [view.string copy];
        Check(StartGatedFindAll(view), [NSString stringWithFormat:@"Find All in %@ runs as a background task", name]);
        Check(!view.isEditable, [NSString stringWithFormat:@"%@ is read-only while it runs", name]);
        [view insertText:@"typed" replacementRange:NSMakeRange(0, 0)];
        Check([view.string isEqualToString:text], [NSString stringWithFormat:@"typing changes nothing in %@ meanwhile", name]);
        Check(![TestShared validateAction:TSAdvancedFindActionNext forTextView:view] && ![TestShared performAction:TSAdvancedFindActionFindAll inTextView:view],
              [NSString stringWithFormat:@"one task at a time in %@", name]);
        Check(FinishGatedFindAll() && view.isEditable == editable && listed.items.count == RangesOf(@"Overfull", text).count,
              [NSString stringWithFormat:@"%@ is %@ again afterwards", name, editable ? @"editable" : @"read-only"]);
    }
    // The text views of the Experiment window are locked one at a time: the other stays as it is.
    Check(StartGatedFindAll(source) && !source.isEditable && !experiment.isEditable, @"Find All in the Experiment source");
    [experimentController appendText:@"\nOverfull \\hbox\n"];
    Check([experiment.string hasSuffix:@"\nOverfull \\hbox\n"], @"the Experiment output still receives output meanwhile");
    Check(FinishGatedFindAll() && source.isEditable && !experiment.isEditable, @"afterwards the Experiment source is editable and the output read-only");
    // A typesetting that starts meanwhile makes the console read-only for good ("it is never editable" while TeX
    // runs); the end of Find All must not make it editable again.
    fresh = LoadDocumentNib(nibPath).outputText;
    fresh.string = SampleLog(12);
    Check(fresh.isEditable && StartGatedFindAll(fresh), @"Find All in the console before the first typesetting");
    TestStartTypesetting(fresh, nil);
    TSAppendConsoleOutput(fresh, @"This is e-upTeX\n", nil);
    Check(FinishGatedFindAll() && !fresh.isEditable && [fresh.string isEqualToString:@"This is e-upTeX\n"],
          @"a typesetting that started meanwhile leaves the console read-only after Find All");
}

#pragma mark Images

/// Windows that are never shown do not draw buttons; each button's own cell is drawn at its measured frame.
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

/// The console (the language's nib), the Experiment source (its nib panel, with the TSLayoutManager that the document
/// gives it) and output (the controller's window), with the highlights of "(Over|Under)full \\[hv]box", and the panel
/// acting on the console, light and dark.
static void WriteImages(NSString *nibPath, NSString *directory, TSExperimentConsoleController *experimentController)
{
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    NibOwner *owner = LoadDocumentNib(nibPath);
    NSTextView *console = owner.outputText;
    console.editable = NO;
    console.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    console.string = SampleLog(12);
    NSTextView *scrap = owner.scrapTextView;
    TSLayoutManager *layout = [TSLayoutManager new];
    [scrap.textContainer replaceLayoutManager:layout];
    scrap.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    scrap.string = @"\\documentclass{jlreq}\n\\begin{document}\n\\section{実験}\n% Overfull \\hbox を見る\n\\hbox to 10pt{関数 $f(x) = x^2$ を考える。}\n\\end{document}\n";
    NSTextView *output = experimentController.outputText;
    output.string = @"";
    [experimentController appendText:SampleLog(3)];
    TestShared.settings.findString = @"(Over|Under)full \\\\[hv]box";
    TestShared.settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    TSAdvancedFindPanelController *panel = TSAdvancedFindPanelController.sharedPanelController; // shows the count of the console, the last
    BOOL lit = YES;
    for (NSTextView *view in @[scrap, output, console])
        lit = lit && [TestShared performAction:TSAdvancedFindActionHighlight inTextView:view]
              && [TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges.count > 0;
    Check(lit, @"the images have highlights in the console and both Experiment windows");
    [panel reloadFromSettings];
    TSAdvancedFindController.testTargetTextView = console;
    [panel updateButtons];
    Check(!panel.buttons[1].enabled && !panel.buttons[2].enabled, @"the panel acting on the console grays Replace All and Replace & Find");
    for (NSString *mode in @[@"light", @"dark"]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:[mode isEqualToString:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        NSString *base = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", language, mode]];
        for (NSWindow *window in @[console.window, scrap.window, output.window, panel.window])
            window.appearance = appearance;
        // The theme's console colors (the checks' color support has no themes): the text colors of the appearance.
        __block NSDictionary *theme = nil;
        [appearance performAsCurrentDrawingAppearance:^{
            theme = @{@"ConsoleBackground": [NSColor.textBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace],
                      @"ConsoleText": [NSColor.textColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]};
        }];
        [experimentController updateConsoleColors:[NSNotification notificationWithName:@"SourceColorChanged" object:nil userInfo:theme]];
        [output.textStorage addAttribute:NSForegroundColorAttributeName value:theme[@"ConsoleText"] range:NSMakeRange(0, output.textStorage.length)];
        // The text, as in the lab's images; the buttons of the console windows are not part of this stage.
        BOOL ok = WritePNG(console.enclosingScrollView, appearance, [base stringByAppendingString:@"-console.png"])
               && WritePNG(scrap.enclosingScrollView, appearance, [base stringByAppendingString:@"-experiment-source.png"])
               && WritePNG(output.enclosingScrollView, appearance, [base stringByAppendingString:@"-experiment-output.png"])
               && WritePNG(panel.window.contentView, appearance, [base stringByAppendingString:@"-panel-console.png"]);
        Check(ok, [NSString stringWithFormat:@"the %@ images are written", mode]);
    }
    TSAdvancedFindController.testTargetTextView = nil;
    Check(!console.window.isVisible && !output.window.isVisible && !panel.window.isVisible && !scrap.window.isVisible, @"nothing is shown for the images");
}

#pragma mark Main

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        keptNibObjects = [NSMutableArray array];
        TestVisibleWindows = [NSHashTable weakObjectsHashTable];
        TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
        TestShared = [[TSAdvancedFindController alloc] initWithSettings:settings];
        TestShared.beepHandler = ^{ beeps++; };
        method_setImplementation(class_getClassMethod(TSAdvancedFindController.class, @selector(sharedController)), (IMP)SharedForTests);
        Method validate = class_getInstanceMethod(TSAdvancedFindController.class, @selector(validateAction:forTextView:));
        originalValidate = method_setImplementation(validate, (IMP)CountValidate);
        method_setImplementation(class_getInstanceMethod(NSTextView.class, @selector(performFindPanelAction:)), (IMP)RecordTextViewFind);
        method_setImplementation(class_getInstanceMethod(NSTextView.class, @selector(performTextFinderAction:)), (IMP)RecordTextViewFind);
        method_setImplementation(class_getInstanceMethod(NSApplication.class, @selector(keyWindow)), (IMP)KeyWindowForTests);
        originalIsVisible = method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(isVisible)), (IMP)IsVisibleForTests);
        originalItemsOfFind = method_setImplementation(class_getClassMethod(TSAdvancedFindResults.class, @selector(itemsOfFind:cancellation:progress:)),
                                                       (IMP)GatedItemsOfFind);
        TestShared.sheetDelay = 600; // no progress sheet: nothing is shown

        NSString *mode = argc > 1 ? @(argv[1]) : @"behavior";
        NSMutableArray<NSString *> *nibs = [NSMutableArray array];
        for (int i = 2; i < argc && argv[i][0] != '-'; i++)
            [nibs addObject:@(argv[i])];
        TSExperimentConsoleController *experimentController = [TSExperimentConsoleController new];
        (void)experimentController.window;
        NSTextView *experiment = experimentController.outputText;
        if ([mode isEqualToString:@"behavior"]) {
            TestNibs(nibs);
            Check([experiment isKindOfClass:TSAdvancedFindTextView.class] && DrawsHighlightsAlone(experiment) && !experiment.isEditable && experiment.isSelectable,
                  @"the Experiment output is a read-only TSAdvancedFindTextView that draws the highlights");
            Check(experiment.font.isFixedPitch && experiment.enclosingScrollView.documentView == experiment, @"the Experiment output keeps its font and scroll view");
            [experimentController appendText:SampleLog(12)];
            NSTextView *console = MakeConsole(nibs.firstObject);
            NSTextView *log = LoadDocumentNib(nibs.firstObject).logTextView;
            log.string = SampleLog(3);
            TSAdvancedFindTextView *source = [[TSAdvancedFindTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
            source.allowsUndo = YES;
            TestRouting(console, log, experiment, source);
            log.string = SampleLog(3);
            TestHighlights(console, @"console", ^(NSString *text) { [console.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text]]; });
            TestHighlights(experiment, @"Experiment output", ^(NSString *text) { [experimentController appendText:text]; });
            console.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            TestHighlights(console, @"console (dark)", ^(NSString *text) { [console.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text]]; });
            TestHighlights(log, @"log", ^(NSString *text) { [log.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text]]; });
            TestButtons(console, log, source);
            TestPanelTarget(experimentController, log);
            TestLeavingThePanel(console, log, experiment);
            TestFindAllWhileOutputComes(nibs.firstObject, experimentController, log);
            TestReadOnlyMeanwhile(nibs.firstObject, experimentController, log, source);
        } else if ([mode isEqualToString:@"images"]) {
            [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"FindMethod"];
            WriteImages(nibs.firstObject, nibs.lastObject, experimentController);
        }
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
