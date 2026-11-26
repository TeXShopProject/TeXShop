// SPDX-License-Identifier: GPL-2.0-or-later
// The Advanced Find panel: the controller on real text views, the routing of the Find
// menu, the highlights drawn by the real TSLayoutManager (checked in pixels), and the panel's layout and images.
// Built by Tests/run-advanced-find-panel.py; no window is ever shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <string.h>
#import "TestAppKitIsolation.h"
#import "AdvancedFindTaskWait.h"
#import "TSLayoutManager.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"
#import "TSMultipleReplaceMenu.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

#pragma mark A document as TeXShop's

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
    _storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:14] ?: [NSFont systemFontOfSize:14]}];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed = NO;
    NSView *content = _window.contentView;
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
        view.backgroundColor = NSColor.whiteColor;
        view.drawsBackground = YES;
        view.textContainerInset = NSMakeSize(4, 4);
        [content addSubview:view];
        [views addObject:view];
    }
    _upper = views[0];
    _lower = views[1];
    return self;
}
@end

#pragma mark Pixels

typedef struct { CGFloat r, g, b; } TestRGB;

/// The color drawn under the text of `range` in `view`: the bottom of the line, below the baseline, where letters
/// without descenders leave the background alone. The median of a few points along the range.
static TestRGB BackgroundUnder(NSTextView *view, NSRange range)
{
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    view.appearance = light;
    __block TestRGB result = {-1, -1, -1};
    [light performAsCurrentDrawingAppearance:^{
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        NSRange glyphs = [view.layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        NSRect rect = [view.layoutManager boundingRectForGlyphRange:glyphs inTextContainer:view.textContainer];
        rect = NSOffsetRect(rect, view.textContainerOrigin.x, view.textContainerOrigin.y);
        CGFloat scale = rep.pixelsWide / NSWidth(view.bounds);
        NSMutableArray<NSNumber *> *rs = [NSMutableArray array], *gs = [NSMutableArray array], *bs = [NSMutableArray array];
        for (NSInteger i = 1; i <= 5; i++) {
            CGFloat x = NSMinX(rect) + NSWidth(rect) * i / 6.0;
            CGFloat y = NSMaxY(rect) - 1.5;
            NSColor *color = [[rep colorAtX:(NSInteger)(x * scale) y:(NSInteger)(y * scale)] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            [rs addObject:@(color.redComponent)];
            [gs addObject:@(color.greenComponent)];
            [bs addObject:@(color.blueComponent)];
        }
        NSSortDescriptor *ascending = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES];
        result.r = [[rs sortedArrayUsingDescriptors:@[ascending]][2] doubleValue];
        result.g = [[gs sortedArrayUsingDescriptors:@[ascending]][2] doubleValue];
        result.b = [[bs sortedArrayUsingDescriptors:@[ascending]][2] doubleValue];
    }];
    return result;
}

static NSString *Describe(TestRGB c) { return [NSString stringWithFormat:@"(%.2f %.2f %.2f)", c.r, c.g, c.b]; }
static BOOL IsWhite(TestRGB c) { return c.r > 0.95 && c.g > 0.95 && c.b > 0.95; }
static BOOL IsHighlightOnWhite(TestRGB c) { return c.r > 0.85 && c.g > 0.75 && c.b < 0.8; }
static BOOL IsBlue(TestRGB c) { return c.r < 0.1 && c.g < 0.1 && c.b > 0.9; }
static BOOL IsGreen(TestRGB c) { return c.r < 0.1 && c.g > 0.9 && c.b < 0.5; }
/// The highlight over blue: both show, the blue through the yellow.
static BOOL IsHighlightOnBlue(TestRGB c) { return c.r > 0.25 && c.r < 0.75 && c.b > 0.3 && !IsBlue(c); }
static BOOL IsHighlightOnGreen(TestRGB c) { return c.r > 0.25 && c.g > 0.9 && !IsGreen(c); }

static void SetForeignBackground(TestDocument *document, NSRange range, NSColor *color)
{
    for (NSLayoutManager *layout in document.storage.layoutManagers) {
        [layout removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, document.storage.length)];
        if (color)
            [layout addTemporaryAttribute:NSBackgroundColorAttributeName value:color forCharacterRange:range];
    }
}

#pragma mark Controller

static TSAdvancedFindController *MakeController(NSUserDefaults *defaults, NSUInteger *beeps)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:defaults findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    TSAdvancedFindController *controller = [[TSAdvancedFindController alloc] initWithSettings:settings];
    controller.beepHandler = ^{ (*beeps)++; };
    controller.lineEndingHandler = ^NSString *(NSTextView *view) { return @"\n"; };
    return controller;
}

static void TestController(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    TSAdvancedFindSettings *settings = controller.settings;
    __block NSString *status = @"";
    __block NSInteger shown = -1, hidden = 0;
    controller.statusHandler = ^(NSString *message, BOOL isError) { status = message; };
    controller.showPanelHandler = ^(BOOL replacing) { shown = replacing; };
    controller.hidePanelHandler = ^{ hidden++; };
    TestDocument *document = [[TestDocument alloc] initWithText:@"alpha beta alpha gamma alpha\nsecond line\n"];
    NSTextView *view = document.upper;
    NSString *original = document.storage.string;

    // Next, previous, wrapping
    Check(settings.wraps && !(settings.options & TSRegexFindRegularExpression), @"the defaults: wrap around, no regular expression");
    settings.findString = @"alpha";
    view.selectedRange = NSMakeRange(0, 0);
    Check([controller performAction:TSAdvancedFindActionNext inTextView:view] && NSEqualRanges(view.selectedRange, NSMakeRange(0, 5)), @"Next finds the match at the caret");
    Check([controller performAction:TSAdvancedFindActionNext inTextView:view] && view.selectedRange.location == 11, @"Next finds the second");
    Check([controller performAction:TSAdvancedFindActionNext inTextView:view] && view.selectedRange.location == 23, @"Next finds the third");
    Check([controller performAction:TSAdvancedFindActionNext inTextView:view] && view.selectedRange.location == 0, @"Next wraps around");
    Check([status containsString:@"1"], @"the position is reported");
    Check([controller performAction:TSAdvancedFindActionPrevious inTextView:view] && view.selectedRange.location == 23, @"Previous wraps backwards");
    settings.wraps = NO;
    NSUInteger before = beeps;
    Check(![controller performAction:TSAdvancedFindActionNext inTextView:view] && beeps == before + 1 && view.selectedRange.location == 23,
          @"without wrapping, Next at the last match beeps once and keeps the selection");
    settings.wraps = YES;

    // Replace All with groups (ICU and OgreKit), one undo
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"(al)(pha)";
    settings.replaceString = @"$2$1";
    settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, view), @"Replace All");
    Check([document.storage.string isEqualToString:@"phaal beta phaal gamma phaal\nsecond line\n"], @"ICU groups in Replace All");
    Check([status containsString:@"3"], @"Replace All reports the number of replacements");
    [view.undoManager undo];
    Check([document.storage.string isEqualToString:original], @"one undo takes back the whole Replace All");
    settings.replacementSyntax = TSRegexReplacementSyntaxOgreKit;
    settings.replaceString = @"\\2\\1$";
    TSTestPerform(controller, TSAdvancedFindActionReplaceAll, view);
    Check([document.storage.string hasPrefix:@"phaal$ beta"], @"OgreKit groups, $ as text");
    [view.undoManager undo];
    settings.replacementSyntax = TSRegexReplacementSyntaxICU;

    // In selection
    view.selectedRange = NSMakeRange(6, 15); // "beta alpha gamm"
    settings.replaceString = @"X";
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAllInSelection, view), @"Replace All in Selection");
    Check([document.storage.string isEqualToString:@"alpha beta X gamma alpha\nsecond line\n"], @"only the selection is replaced");
    [view.undoManager undo];
    Check([document.storage.string isEqualToString:original], @"undo of Replace All in Selection");

    // Replace and Replace & Find
    settings.options = TSRegexFindDefaultOptions;
    settings.findString = @"alpha";
    settings.replaceString = @"ALPHA";
    view.selectedRange = NSMakeRange(0, 5);
    Check([controller performAction:TSAdvancedFindActionReplaceAndFind inTextView:view] && view.selectedRange.location == 11, @"Replace & Find replaces and selects the next");
    Check([document.storage.string hasPrefix:@"ALPHA beta alpha"], @"Replace & Find replaced the selection");
    Check([controller performAction:TSAdvancedFindActionReplace inTextView:view] && NSEqualRanges(view.selectedRange, NSMakeRange(11, 5)), @"Replace keeps the replaced text selected");
    view.selectedRange = NSMakeRange(6, 4);
    before = beeps;
    Check(![controller performAction:TSAdvancedFindActionReplace inTextView:view] && beeps == before + 1, @"Replace beeps once on a selection that is no match");
    [view.undoManager undo];
    [view.undoManager undo];
    Check([document.storage.string isEqualToString:original], @"each replacement is one undo step");

    // Select All, the selection as find string, the selected text
    Check([controller performAction:TSAdvancedFindActionSelectAll inTextView:view] && view.selectedRanges.count == 3, @"Select All selects every match");
    view.selectedRange = NSMakeRange(6, 4);
    Check([controller validateAction:TSAdvancedFindActionSetFindString forTextView:view] && [controller performAction:TSAdvancedFindActionSetFindString inTextView:view]
          && [settings.findString isEqualToString:@"beta"], @"Use Selection for Find (⌘E)");
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    view.selectedRange = NSMakeRange(29, 6); // "second"
    Check([controller performAction:TSAdvancedFindActionFindSelectedText inTextView:view] && [settings.findString isEqualToString:@"second"], @"Find Selected Text");

    // Find Selected Text finds the selection as it is with every regular expression option
    for (NSNumber *flags in @[@(TSRegexFindRegularExpression), @(TSRegexFindRegularExpression | TSRegexFindIgnoreMetacharacters),
                              @(TSRegexFindRegularExpression | TSRegexFindAllowCommentsAndWhitespace), @0])
        for (NSString *selected in @[@".*", @"two words", @"#note", @"¥100 $\\x", @"a\tb # c", @"a\u200Eb", @"a\u200Fb"]) {
            NSUInteger quiet = 0;
            TSAdvancedFindController *finder = MakeController([TSMemoryDefaults new], &quiet);
            finder.settings.options = TSRegexFindDefaultOptions | flags.unsignedIntegerValue;
            if ([selected hasPrefix:@"¥"] && !(flags.unsignedIntegerValue & TSRegexFindRegularExpression))
                continue; // without a regular expression, ¥ in the find string stands for a backslash (the option's meaning)
            if ([selected hasPrefix:@"¥"] && (flags.unsignedIntegerValue & TSRegexFindIgnoreMetacharacters))
                continue; // a literal pattern cannot escape ¥ either
            TestDocument *pair = [[TestDocument alloc] initWithText:[NSString stringWithFormat:@"%@ / %@", selected, selected]];
            pair.upper.selectedRange = NSMakeRange(0, selected.length);
            BOOL found = [finder performAction:TSAdvancedFindActionFindSelectedText inTextView:pair.upper];
            Check(found && NSEqualRanges(pair.upper.selectedRange, NSMakeRange(selected.length + 3, selected.length)),
                  [NSString stringWithFormat:@"Find Selected Text finds “%@” with options %lx (find string “%@”)", selected, flags.unsignedLongValue, finder.settings.findString]);
        }

    // Errors
    settings.findString = @"(";
    before = beeps;
    shown = -1;
    Check(![controller performAction:TSAdvancedFindActionNext inTextView:view] && beeps == before + 1 && shown == 0 && status.length > 0,
          @"an invalid pattern beeps once, shows the panel and reports the error");
    settings.options = TSRegexFindDefaultOptions;
    settings.findString = @"";
    before = beeps;
    Check(![controller performAction:TSAdvancedFindActionNext inTextView:view] && beeps == before + 1, @"an empty find string beeps");

    // The menu's panel actions (Find… 1, Find and Replace… 12, hide 11)
    shown = -1;
    Check([controller performAction:TSAdvancedFindActionShowReplacePanel inTextView:view] && shown == 1, @"Find and Replace… shows the panel at the replacement");
    Check([controller performAction:TSAdvancedFindActionShowFindPanel inTextView:view] && shown == 0, @"Find… shows the panel at the find field");
    Check([controller performAction:TSAdvancedFindActionHidePanel inTextView:view] && hidden == 1, @"Hide Find closes the panel");

    // The line ending of the document goes into the find string
    settings.findString = @"alpha\r\nsecond";
    [document.storage replaceCharactersInRange:NSMakeRange(0, document.storage.length) withString:@"x alpha\nsecond"];
    view.selectedRange = NSMakeRange(0, 0);
    Check([controller performAction:TSAdvancedFindActionNext inTextView:view] && NSEqualRanges(view.selectedRange, NSMakeRange(2, 12)), @"CRLF in the find string finds LF");

    // Read-only text views take no replacing
    view.editable = NO;
    for (NSNumber *action in @[@(TSAdvancedFindActionReplace), @(TSAdvancedFindActionReplaceAll), @(TSAdvancedFindActionReplaceAndFind), @(TSAdvancedFindActionReplaceAllInSelection)])
        Check(![controller validateAction:action.integerValue forTextView:view], @"no replacing in a read-only text view");
    Check([controller validateAction:TSAdvancedFindActionNext forTextView:view] && [controller validateAction:TSAdvancedFindActionHighlight forTextView:view],
          @"finding works in a read-only text view");
    view.editable = YES;

    // History and its limit (the hidden setting AdvancedFindHistoryLimit)
    TSMemoryDefaults *defaults = [TSMemoryDefaults new];
    [defaults setInteger:2 forKey:@"AdvancedFindHistoryLimit"];
    TSAdvancedFindSettings *limited = [[TSAdvancedFindSettings alloc] initWithDefaults:defaults findPasteboard:nil];
    for (NSString *word in @[@"one", @"two", @"three"]) {
        limited.findString = word;
        [limited noteFindString];
    }
    Check([limited.findHistory isEqualToArray:@[@"three", @"two"]], @"the history keeps the latest, up to AdvancedFindHistoryLimit");
    [defaults setInteger:1000 forKey:@"AdvancedFindHistoryLimit"];
    Check(limited.historyLimit == 100, @"the history limit is at most 100");
    [defaults removeObjectForKey:@"AdvancedFindHistoryLimit"];
    Check(limited.historyLimit == 20, @"the history limit is 20 by default");
}

#pragma mark Routing

/// The shared controller of the tests: in-memory defaults and a unique find pasteboard, not the system's.
static TSAdvancedFindController *TestSharedController;
static NSUInteger TestSharedBeeps;
static id SharedControllerForTests(id self, SEL _cmd) { return TestSharedController; }

static void TestRouting(void)
{
    TSAdvancedFindController *controller = TestSharedController;
    controller.settings.findString = @"beta";
    TSAdvancedFindTextView *view = [[TSAdvancedFindTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    view.string = @"alpha beta gamma beta";
    [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"FindMethod"];
    Check(view.findController == controller, @"with the Advanced Find panel, a plain text view finds with the shared controller");
    NSMenuItem *next = [[NSMenuItem alloc] initWithTitle:@"Find Next" action:@selector(performFindPanelAction:) keyEquivalent:@"g"];
    next.tag = NSFindPanelActionNext;
    [view performFindPanelAction:next];
    Check(NSEqualRanges(view.selectedRange, NSMakeRange(6, 4)), @"the Find menu's Find Next reaches the controller");
    NSMenuItem *replace = [[NSMenuItem alloc] initWithTitle:@"Find and Replace…" action:@selector(performTextFinderAction:) keyEquivalent:@"f"];
    replace.tag = NSTextFinderActionShowReplaceInterface;
    __block NSInteger shown = -1;
    controller.showPanelHandler = ^(BOOL replacing) { shown = replacing; };
    Check([view validateMenuItem:replace], @"Find and Replace… is enabled");
    [view performTextFinderAction:replace];
    Check(shown == 1, @"Find and Replace… reaches the controller");
    view.editable = NO;
    NSMenuItem *replaceAll = [[NSMenuItem alloc] initWithTitle:@"Replace All" action:@selector(performFindPanelAction:) keyEquivalent:@""];
    replaceAll.tag = NSFindPanelActionReplaceAll;
    Check(![view validateMenuItem:replaceAll], @"no Replace All from the menu in a read-only text view");
    // A text view that is not TeXShop's gets the layout manager that draws the highlights; TSLayoutManager is kept.
    Check([view.layoutManager conformsToProtocol:@protocol(TSAdvancedFindHighlightDrawing)], @"a plain text view draws the highlights");
    TestDocument *document = [[TestDocument alloc] initWithText:@"x"];
    NSLayoutManager *own = document.upper.layoutManager;
    [TSAdvancedFindLayoutManager installInTextView:document.upper];
    Check(document.upper.layoutManager == own && [own isKindOfClass:TSLayoutManager.class], @"TSLayoutManager draws the highlights itself and is not replaced");
}

#pragma mark Highlights

static void TestHighlights(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    TestDocument *document = [[TestDocument alloc] initWithText:@"xx aaaa xx aaaa xx\nmmmm aaaa mmmm\n"];
    NSTextView *upper = document.upper, *lower = document.lower;
    upper.selectedRange = NSMakeRange(document.storage.length, 0);
    lower.selectedRange = NSMakeRange(document.storage.length, 0);
    NSRange first = NSMakeRange(3, 4), second = NSMakeRange(11, 4), third = NSMakeRange(24, 4), plain = NSMakeRange(19, 4);
    Check(IsWhite(BackgroundUnder(upper, first)), [NSString stringWithFormat:@"the text starts on white %@", Describe(BackgroundUnder(upper, first))]);

    // (a) another feature's background under a match: both show while highlighted, the background stays after
    SetForeignBackground(document, NSMakeRange(2, 6), NSColor.blueColor);
    controller.settings.findString = @"aaaa";
    Check([controller performAction:TSAdvancedFindActionHighlight inTextView:upper], @"Highlight All finds the matches");
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:document.storage].ranges.count == 3, @"three highlights");
    TestRGB both = BackgroundUnder(upper, first);
    Check(IsHighlightOnBlue(both), [NSString stringWithFormat:@"(a) the highlight and the background under it both show %@", Describe(both)]);
    Check(IsHighlightOnWhite(BackgroundUnder(upper, second)), [NSString stringWithFormat:@"a highlight on white %@", Describe(BackgroundUnder(upper, second))]);
    Check(IsWhite(BackgroundUnder(upper, plain)), @"no highlight where nothing matched");

    // (b) coloring the text again keeps the highlights (TeXShop colors with temporary attributes)
    for (NSLayoutManager *layout in document.storage.layoutManagers) {
        [layout removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0, document.storage.length)];
        [layout addTemporaryAttribute:NSForegroundColorAttributeName value:NSColor.redColor forCharacterRange:NSMakeRange(0, document.storage.length)];
    }
    Check(IsHighlightOnWhite(BackgroundUnder(upper, second)), @"(b) coloring again keeps the highlight");

    // (c) the background changed meanwhile: the new one is left
    SetForeignBackground(document, NSMakeRange(2, 6), NSColor.greenColor);
    Check(IsHighlightOnGreen(BackgroundUnder(upper, first)), [NSString stringWithFormat:@"(c) the highlight over the new background %@", Describe(BackgroundUnder(upper, first))]);

    // (e) both views of the split window
    Check(IsHighlightOnWhite(BackgroundUnder(lower, second)), @"(e) the other view of the split window shows the highlight");

    [controller performAction:TSAdvancedFindActionUnhighlight inTextView:upper];
    TestRGB after = BackgroundUnder(upper, first);
    Check(IsGreen(after), [NSString stringWithFormat:@"(a)(c) removing the highlights leaves the background that is there now %@", Describe(after)]);
    Check(IsWhite(BackgroundUnder(upper, second)) && IsWhite(BackgroundUnder(lower, second)), @"removing the highlights clears both views");
    SetForeignBackground(document, NSMakeRange(0, 0), nil);

    // (d) edits move the highlights after them and drop the ones they touch
    [controller performAction:TSAdvancedFindActionHighlight inTextView:upper];
    [upper insertText:@"++++" replacementRange:NSMakeRange(0, 0)];
    NSRange moved = NSMakeRange(second.location + 4, 4);
    Check(IsHighlightOnWhite(BackgroundUnder(upper, moved)), @"(d) an edit before a highlight moves it");
    Check(IsHighlightOnWhite(BackgroundUnder(lower, moved)), @"(d)(e) in the other view as well");
    Check(IsWhite(BackgroundUnder(upper, NSMakeRange(second.location, 2))), @"(d) nothing stays at the old place");
    [upper insertText:@"b" replacementRange:NSMakeRange(third.location + 4 + 1, 1)];
    NSArray<NSValue *> *ranges = [TSAdvancedFindHighlights existingHighlightsForTextStorage:document.storage].ranges;
    Check(ranges.count == 2, @"(d) an edit inside a highlight drops it");
    Check(IsWhite(BackgroundUnder(upper, NSMakeRange(third.location + 4, 4))), @"(d) the edited match is no longer highlighted");
    [controller performAction:TSAdvancedFindActionUnhighlight inTextView:upper];
}

#pragma mark Panel

/// Windows that are never shown do not draw buttons; each button's own cell is drawn at its measured frame
/// at its measured frame. Window glass and translucency are not reproduced.
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

/// Every control inside the view, at least `rightInset` points from its right edge, with a title that fits.
static int CheckLayoutInset(NSView *root, NSString *name, CGFloat rightInset)
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
        if (rightInset > 0 && NSMaxX(frame) > NSMaxX(root.bounds) - rightInset) {
            printf("FAIL %s: no right inset: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
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
    }
    return count;
}

static NSString *L(NSString *key, NSString *english)
{
    return TSAdvancedFindLocalized(key, english);
}

/// The messages of the line under the options and the results in the find field, each in the smallest panel.
static int CheckMessages(TSAdvancedFindPanelController *panel)
{
    NSMutableArray<NSString *> *messages = [NSMutableArray array];
    for (NSString *english in @[@"The find string is empty.", @"There is no selection to search in."])
        [messages addObject:[NSBundle.mainBundle localizedStringForKey:english value:english table:@"AdvancedFindEngine"]];
    NSError *error = nil;
    for (NSString *pattern in @[@"(", @"a{x}", @"[a-", @"\\"])
        if (![[TSRegexFindPattern alloc] initWithFindString:pattern options:TSRegexFindRegularExpression error:&error])
            [messages addObject:error.localizedDescription];
    int count = 0;
    if (![NSBundle.mainBundle pathForResource:@"AdvancedFindEngine" ofType:@"strings"] || ![NSBundle.mainBundle pathForResource:@"AdvancedFind" ofType:@"strings"]) {
        puts("FAIL the tables AdvancedFind.strings and AdvancedFindEngine.strings are not in the bundle");
        count++;
    }
    NSWindow *window = panel.window;
    NSRect old = window.frame;
    [window setContentSize:window.contentMinSize];
    for (NSString *message in messages) {
        panel.statusField.stringValue = message;
        [window.contentView layoutSubtreeIfNeeded];
        count += CheckLabelFits(panel.statusField, @"panel message");
    }
    panel.statusField.stringValue = @"";
    NSArray<NSString *> *results = @[[NSString localizedStringWithFormat:L(@"AdvancedFind.Position", @"%1$lu of %2$lu"), 12345UL, 12345UL],
        [[NSString localizedStringWithFormat:L(@"AdvancedFind.Position", @"%1$lu of %2$lu"), 12345UL, 12345UL] stringByAppendingFormat:@" %@", L(@"AdvancedFind.Wrapped", @"(wrapped)")],
        [NSString localizedStringWithFormat:L(@"AdvancedFind.Found", @"%lu found"), 12345UL],
        [NSString localizedStringWithFormat:L(@"AdvancedFind.Replaced", @"%lu replaced"), 12345UL], L(@"AdvancedFind.NotFound", @"Not found")];
    for (NSString *result in results) {
        panel.findBox.statusLabel.stringValue = result;
        [window.contentView layoutSubtreeIfNeeded];
        count += CheckLayoutInset(window.contentView, @"find field result", 0);
    }
    panel.findBox.statusLabel.stringValue = @"";
    [window setFrame:old display:NO];
    [window.contentView layoutSubtreeIfNeeded];
    return count;
}

/// The panel and its options: layout in the current language (every language is run by the script), images on request.
/// The Multiple Replace windows asked to show (the window itself is never ordered in).
static NSUInteger TestShownMultipleReplaceWindows;
static void TestCountShowWindow(id self, SEL _cmd, id sender) { TestShownMultipleReplaceWindows++; }

/// "Multiple Replace…" right of Replace All opens the window as Edit Multiple Replace… does, whatever the target.
static void TestMultipleReplaceButton(TSAdvancedFindPanelController *panel, NSUInteger *beeps)
{
    NSButton *button = panel.multipleReplaceButton;
    NSStackView *row = (NSStackView *)button.superview;
    NSUInteger index = [row.arrangedSubviews indexOfObject:button];
    Check(button && index != NSNotFound && index > 0 && row.arrangedSubviews[index - 1] == panel.buttons[1]
          && [row.views containsObject:button] && [[row viewsInGravity:NSStackViewGravityLeading] containsObject:button],
          @"Multiple Replace… is right after Replace All, on the left of the row");
    Check([button.title isEqualToString:TSAdvancedFindLocalized(@"AdvancedFind.MultipleReplace", @"Multiple Replace…")] && [button.title hasSuffix:@"…"]
          && ![panel.buttons containsObject:button] && button.bezelStyle == ((NSButton *)panel.buttons[1]).bezelStyle,
          @"its title ends with …, it looks as Replace All and does not follow the target");
    method_setImplementation(class_getInstanceMethod(TSMultipleReplaceWindowController.class, @selector(showWindow:)), (IMP)TestCountShowWindow);
    if (!TSMultipleReplaceMenu.sharedMenu) {
        NSUInteger before = *beeps;
        [button performClick:nil];
        Check(*beeps == before + 1 && TestShownMultipleReplaceWindows == 0, @"without the menu's window (never in TeXShop) it beeps");
        NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
        [main addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""].submenu = edit;
        NSMenu *find = [[NSMenu alloc] initWithTitle:@"Find"];
        [edit addItemWithTitle:@"Find" action:NULL keyEquivalent:@""].submenu = find;
        [find addItemWithTitle:@"Find…" action:@selector(performFindPanelAction:) keyEquivalent:@"f"].tag = NSFindPanelActionShowFindPanel;
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [TSMultipleReplaceMenu installInMainMenu:main directory:[directory URLByAppendingPathComponent:@"MultipleReplace"]];
    }
    TSMultipleReplaceMenu *menu = TSMultipleReplaceMenu.sharedMenu;
    NSUInteger shown = TestShownMultipleReplaceWindows;
    Check(button.enabled, @"Multiple Replace… is enabled");
    [button performClick:nil];
    Check(menu && TestShownMultipleReplaceWindows == shown + 1 && !menu.windowController.window.isVisible,
          @"Multiple Replace… shows the menu's Multiple Replace window (never ordered in here)");
}

static void TestPanel(NSString *_Nullable imageDirectory)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    TSAdvancedFindSettings *settings = controller.settings;
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";

    // The parts of the panel (Find All and its list: Tests/AdvancedFindResults.m)
    Check(panel.buttons.count == 4 && [panel.buttons[0] isKindOfClass:NSComboButton.class] && [panel.buttons[2] isKindOfClass:NSComboButton.class]
          && [panel.buttons[3] isKindOfClass:NSSegmentedControl.class], @"Find All ▾, Replace All, Replace & Find ▾, previous / next");
    for (NSButton *box in panel.optionBoxes)
        Check(box.controlSize == NSControlSizeSmall, @"the options row is small, as in CotEditor");
    NSComboButton *findAll = (NSComboButton *)panel.buttons[0];
    Check(findAll.action == @selector(advancedFindAll:) && findAll.menu.numberOfItems == 6
          && findAll.menu.itemArray[0].action == @selector(advancedHighlight:) && findAll.menu.itemArray[1].action == @selector(advancedSelectAll:)
          && findAll.menu.itemArray[3].action == @selector(advancedUnhighlight:) && findAll.menu.itemArray[4].isSeparatorItem
          && findAll.menu.itemArray[5].action == NSSelectorFromString(@"showTeXRootSearch:"),
          @"Highlight All, Select All and Remove Highlights under Find All, then the TeX sources of the root");
    Check([panel.window.title isEqualToString:L(@"AdvancedFind.Title", @"Find and Replace")], @"the panel's title");

    // The panel acts on the target text view; read-only gray-out of the replacing buttons
    TestDocument *document = [[TestDocument alloc] initWithText:@"one two one"];
    TSAdvancedFindController.testTargetTextView = document.upper;
    settings.findString = @"one";
    [panel reloadFromSettings];
    Check([panel.findField.string isEqualToString:@"one"], @"the field shows the find string");
    [panel.findField insertText:@"x" replacementRange:NSMakeRange(panel.findField.string.length, 0)];
    Check([settings.findString isEqualToString:@"onex"], @"typing in the field changes the find string");
    settings.findString = @"one";
    [panel reloadFromSettings];
    document.upper.selectedRange = NSMakeRange(0, 0);
    [panel.findField insertNewline:nil];
    Check(NSEqualRanges(document.upper.selectedRange, NSMakeRange(0, 3)), @"Return in the find field finds the next match in the target");
    NSMenuItem *previous = [[NSMenuItem alloc] initWithTitle:@"Find Previous" action:@selector(performFindPanelAction:) keyEquivalent:@"G"];
    previous.tag = NSFindPanelActionPrevious;
    Check([panel.findField validateMenuItem:previous], @"⇧⌘G is enabled while the panel is key");
    [panel.findField performFindPanelAction:previous];
    Check(NSEqualRanges(document.upper.selectedRange, NSMakeRange(8, 3)), @"⇧⌘G from the panel's field finds in the target (wrapping back)");
    document.upper.editable = NO;
    [panel updateButtons];
    Check(panel.buttons[0].enabled && !panel.buttons[1].enabled && !panel.buttons[2].enabled && panel.buttons[3].enabled,
          @"in a read-only target the replacing buttons are gray");
    Check(panel.multipleReplaceButton.enabled, @"Multiple Replace… is not: it only opens its window");
    TestMultipleReplaceButton(panel, &beeps);
    document.upper.editable = YES;
    [panel updateButtons];
    Check(panel.buttons[1].enabled && panel.buttons[2].enabled, @"in an editable target they are not");
    TSAdvancedFindController.testTargetTextView = nil;

    // The error under the options: an invalid pattern, then nothing once it is valid
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"(";
    [panel reloadFromSettings];
    Check(panel.statusField.stringValue.length > 0, @"an invalid pattern is reported under the options");
    settings.findString = @"(a)";
    [panel reloadFromSettings];
    Check(panel.statusField.stringValue.length == 0, @"the report goes once the pattern is valid");

    // History menus
    [settings noteFindString];
    NSMenu *history = [panel historyMenuForField:0];
    Check([history.itemArray[1].title isEqualToString:@"(a)"] && history.itemArray.lastObject.enabled, @"the find history and its clear item");
    Check(!panel.window.isVisible, @"the panel is never shown");

    // Layout: every control inside, titles not cut, at the normal and the smallest size, in this language
    settings.options = TSRegexFindDefaultOptions | TSRegexFindRegularExpression;
    settings.findString = @"\\\\(section|chapter)\\{([^}]*)\\}";
    settings.replaceString = @"\\\\$1*{$2}";
    [panel reloadFromSettings];
    NSView *content = panel.window.contentView;
    NSView *options = [panel makeOptionsViewController].view;
    [content layoutSubtreeIfNeeded];
    failures += CheckLayoutInset(content, [NSString stringWithFormat:@"%@ panel", language], 0);
    failures += CheckLayoutInset(options, [NSString stringWithFormat:@"%@ options", language], 16);
    NSRect old = panel.window.frame;
    [panel.window setContentSize:panel.window.contentMinSize];
    [content layoutSubtreeIfNeeded];
    failures += CheckLayoutInset(content, [NSString stringWithFormat:@"%@ smallest panel", language], 0);
    Check(panel.window.contentMinSize.width + 0.5 >= ((NSStackView *)content).arrangedSubviews.lastObject.fittingSize.width + 40,
          [NSString stringWithFormat:@"%@ smallest panel: the row of buttons sets the smallest width (%.0f)", language, panel.window.contentMinSize.width]);
    // The left and the right buttons of the row keep their room in the smallest panel.
    NSRect multiple = [panel.multipleReplaceButton convertRect:panel.multipleReplaceButton.bounds toView:content];
    NSRect replaceAndFind = [panel.buttons[2] convertRect:panel.buttons[2].bounds toView:content];
    Check(NSMaxX(multiple) + 8 <= NSMinX(replaceAndFind) && NSWidth(panel.multipleReplaceButton.frame) + 0.5 >= panel.multipleReplaceButton.fittingSize.width,
          [NSString stringWithFormat:@"%@ smallest panel: Multiple Replace… is whole and clear of Replace & Find (%.0f, %.0f)", language, NSMaxX(multiple), NSMinX(replaceAndFind)]);
    [panel.window setFrame:old display:NO];
    failures += CheckMessages(panel);
    // Made larger, the fields take the room: the buttons stay 20 points from the bottom.
    [panel.window setContentSize:NSMakeSize(900, 640)];
    [content layoutSubtreeIfNeeded];
    NSView *buttons = ((NSStackView *)content).arrangedSubviews.lastObject;
    NSRect buttonFrame = [buttons convertRect:buttons.bounds toView:content];
    CGFloat bottomGap = content.isFlipped ? NSHeight(content.bounds) - NSMaxY(buttonFrame) : NSMinY(buttonFrame);
    Check(fabs(bottomGap - 20) <= 1, [NSString stringWithFormat:@"the buttons stay 20 points from the bottom of a large panel (%.0f)", bottomGap]);
    [panel.window setFrame:old display:NO];
    [content layoutSubtreeIfNeeded];

    if (!imageDirectory)
        return;
    [NSFileManager.defaultManager createDirectoryAtPath:imageDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    TestDocument *highlighted = [[TestDocument alloc] initWithText:@"\\section{Intro} text \\chapter{One}\nmore \\section{Two}\n"];
    for (NSLayoutManager *layout in highlighted.storage.layoutManagers)
        [layout addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor.systemPinkColor colorWithAlphaComponent:0.35] forCharacterRange:NSMakeRange(0, 12)];
    highlighted.upper.selectedRange = NSMakeRange(highlighted.storage.length, 0);
    highlighted.lower.selectedRange = NSMakeRange(highlighted.storage.length, 0);
    [controller performAction:TSAdvancedFindActionHighlight inTextView:highlighted.upper];
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:name];
        NSString *tag = [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
        panel.window.appearance = appearance;
        options.appearance = appearance;
        highlighted.window.appearance = appearance;
        for (NSTextView *view in @[highlighted.upper, highlighted.lower]) {
            view.appearance = appearance;
            view.backgroundColor = NSColor.textBackgroundColor;
            view.textColor = NSColor.textColor;
        }
        NSString *base = [imageDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", language, tag]];
        Check(WritePNG(content, appearance, [base stringByAppendingString:@"-panel.png"])
              && WritePNG(options, appearance, [base stringByAppendingString:@"-options.png"])
              && WritePNG(highlighted.window.contentView, appearance, [base stringByAppendingString:@"-highlights.png"]), @"images written");
        // The smallest panel, where the row of buttons is tightest
        NSRect frame = panel.window.frame;
        [panel.window setContentSize:panel.window.contentMinSize];
        [content layoutSubtreeIfNeeded];
        Check(WritePNG(content, appearance, [base stringByAppendingString:@"-panel-smallest.png"]), @"image of the smallest panel written");
        [panel.window setFrame:frame display:NO];
        [content layoutSubtreeIfNeeded];
    }
}

#pragma mark The panel among the document windows

/// The panel is among the document windows, as the OgreKit panel was; it floats with the setting of Settings, and
/// while its target is in a floating panel (the Experiment source). Levels are read; nothing is shown.
static void TestPanelLevel(void)
{
    NSUInteger beeps = 0;
    TSMemoryDefaults *defaults = [TSMemoryDefaults new];
    TSAdvancedFindController *controller = MakeController(defaults, &beeps);
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:controller];
    NSPanel *window = (NSPanel *)panel.window;
    TestDocument *document = [[TestDocument alloc] initWithText:@"one"];
    TSAdvancedFindController.testTargetTextView = document.upper;
    Check(!window.isFloatingPanel && window.level == NSNormalWindowLevel, @"the panel is among the document windows, not above them");
    Check(window.hidesOnDeactivate && (window.styleMask & NSWindowStyleMaskUtilityWindow), @"it is still a utility panel that hides with the application");
    Check(!controller.settings.panelFloats, @"without the setting the panel does not float");

    [defaults setBool:YES forKey:TSAdvancedFindPanelFloatsKey];
    [panel updateWindowLevel];
    Check(window.isFloatingPanel && window.level == NSFloatingWindowLevel, @"with the setting on, the panel floats above the document windows");
    [defaults setBool:NO forKey:TSAdvancedFindPanelFloatsKey];
    [panel updateWindowLevel];
    Check(!window.isFloatingPanel && window.level == NSNormalWindowLevel, @"with the setting off again, it is back among them");

    // The Experiment source is in a utility panel, which floats: the panel must not be left under it.
    NSPanel *experiment = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                     styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:YES];
    experiment.releasedWhenClosed = NO;
    NSTextView *scrap = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    experiment.contentView = scrap;
    Check(experiment.level == NSFloatingWindowLevel, @"a utility panel floats");
    TSAdvancedFindController.testTargetTextView = scrap;
    [panel updateWindowLevel];
    Check(window.isFloatingPanel && window.level == NSFloatingWindowLevel, @"while the target is in a floating panel, the panel floats too");
    TSAdvancedFindController.testTargetTextView = document.upper;
    [panel updateWindowLevel];
    Check(!window.isFloatingPanel && window.level == NSNormalWindowLevel, @"with a target in a document window again, it stops floating");

    // After every event, as the buttons: only a panel that is shown follows, and showing it sets the level first.
    TSAdvancedFindController.testTargetTextView = scrap;
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidUpdateNotification object:NSApp];
    Check(!window.isFloatingPanel, @"a panel that is not shown is left alone");
    TSAdvancedFindController.testTargetTextView = nil;
    Check(!window.isVisible, @"nothing is shown");
}

#pragma mark Replace All keeps the scroll

static CGFloat ScrollY(NSTextView *view)
{
    return view.enclosingScrollView.contentView.bounds.origin.y;
}

static CGFloat ScrollX(NSTextView *view)
{
    return view.enclosingScrollView.contentView.bounds.origin.x;
}

/// The line at the top of the viewport, or empty when the viewport is below the text.
static NSString *VisibleTopLine(NSTextView *view)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || layout.numberOfGlyphs == 0)
        return @"";
    NSRect visible = view.visibleRect;
    NSRect used = NSOffsetRect([layout usedRectForTextContainer:container], view.textContainerOrigin.x, view.textContainerOrigin.y);
    if (!NSIntersectsRect(visible, used))
        return @"";
    NSPoint inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x, NSMinY(visible) + 1 - view.textContainerOrigin.y);
    NSUInteger glyph = [layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    NSUInteger character = [layout characterIndexForGlyphAtIndex:glyph];
    if (character >= view.string.length)
        return @"";
    return [view.string substringWithRange:[view.string lineRangeForRange:NSMakeRange(character, 0)]];
}

/// "line 047 alpha word" -> "line 047". The words on the line can change; the line number is the place.
static NSString *LineNumberLabel(NSString *line)
{
    return line.length >= 8 ? [line substringToIndex:8] : line;
}

/// Where `caret` lands when every "alpha" before it becomes one character shorter.
static NSUInteger CaretAfterShorterAlphas(NSString *text, NSRange caret)
{
    NSUInteger alphas = [[text substringToIndex:MIN(caret.location, text.length)] componentsSeparatedByString:@"alpha"].count - 1;
    return caret.location - alphas * 4;
}

/// A split source, scrolled, as in a document window. Nothing is ordered on screen. The window is kept for the rest of the test.
/// `mode` is the source's line break setting. Clipping grows the text view to the longest line and scrolls sideways;
/// word and character wrapping keep the text view at the window width. `clipX` is the horizontal scroll, after the
/// carets have been scrolled into view.
static BOOL MakeScrolledSourceMode(NSString *text, NSLineBreakMode mode, CGFloat clipX, NSTextView *_Nonnull *_Nonnull upperOut, NSTextView *_Nonnull *_Nonnull lowerOut, CGFloat *upperY, CGFloat *lowerY)
{
    BOOL clipping = mode == NSLineBreakByClipping;
    static NSMutableArray<NSWindow *> *windows;
    if (!windows)
        windows = [NSMutableArray array];
    NSFont *font = [NSFont userFixedPitchFontOfSize:13] ?: [NSFont systemFontOfSize:13];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = mode;
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: style}];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    [windows addObject:window];
    NSMutableArray<NSTextView *> *views = [NSMutableArray array];
    for (NSInteger i = 0; i < 2; i++) {
        NSLayoutManager *layout = [NSLayoutManager new];
        layout.allowsNonContiguousLayout = YES;
        [storage addLayoutManager:layout];
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:clipping ? NSMakeSize(FLT_MAX, FLT_MAX) : NSMakeSize(400, CGFLOAT_MAX)];
        container.widthTracksTextView = !clipping;
        [layout addTextContainer:container];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 100 * (1 - i), 420, 100)];
        scroll.hasVerticalScroller = YES;
        scroll.hasHorizontalScroller = clipping;
        NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100) textContainer:container];
        view.minSize = NSMakeSize(0, 100);
        view.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
        view.verticallyResizable = YES;
        view.horizontallyResizable = clipping;
        view.autoresizingMask = clipping ? NSViewNotSizable : NSViewWidthSizable;
        view.allowsUndo = YES;
        view.richText = NO;
        view.defaultParagraphStyle = style;
        scroll.documentView = view;
        [window.contentView addSubview:scroll];
        [views addObject:view];
    }
    NSTextView *upper = views[0], *lower = views[1];
    [window display];
    [upper.layoutManager ensureLayoutForTextContainer:upper.textContainer];
    [lower.layoutManager ensureLayoutForTextContainer:lower.textContainer];
    if (clipping) {
        [upper sizeToFit];
        [lower sizeToFit];
    }
    CGFloat upperTop = ScrollY(upper), lowerTop = ScrollY(lower);
    NSUInteger line = [text rangeOfString:@"\n"].location + 1;
    upper.selectedRange = NSMakeRange(50 * line, 0);
    lower.selectedRange = NSMakeRange(20 * line + 4, 0);
    [upper scrollRangeToVisible:upper.selectedRange];
    [lower scrollRangeToVisible:lower.selectedRange];
    if (clipX > 0) {
        for (NSTextView *view in views) {
            NSClipView *clip = view.enclosingScrollView.contentView;
            NSRect bounds = clip.bounds;
            bounds.origin.x = clipX;
            [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
            [view.enclosingScrollView reflectScrolledClipView:clip];
        }
    }
    [window display];
    *upperOut = upper;
    *lowerOut = lower;
    *upperY = ScrollY(upper);
    *lowerY = ScrollY(lower);
    return fabs(*upperY - upperTop) > 20 && fabs(*lowerY - lowerTop) > 20;
}

static BOOL MakeScrolledSource(NSString *text, BOOL clipping, CGFloat clipX, NSTextView *_Nonnull *_Nonnull upperOut, NSTextView *_Nonnull *_Nonnull lowerOut, CGFloat *upperY, CGFloat *lowerY)
{
    return MakeScrolledSourceMode(text, clipping ? NSLineBreakByClipping : NSLineBreakByWordWrapping, clipX, upperOut, lowerOut, upperY, lowerY);
}

/// Refuses every change. A real document's delegate accepts them; this is the refused replacement.
@interface ReplaceAllVeto : NSObject <NSTextViewDelegate>
@end
@implementation ReplaceAllVeto
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRanges:(NSArray<NSValue *> *)ranges replacementStrings:(NSArray<NSString *> *)strings
{
    return NO;
}
@end

static void TestWrappedMiddleKeepsPlace(void);
static void TestHorizontalLock(void);
static void TestSameLengthKeepsScreen(void);
static void TestReplaceAllKeepsPlace(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    NSMutableString *text = [NSMutableString string];
    for (int i = 0; i < 80; i++)
        [text appendFormat:@"line %03d alpha word\n", i];
    NSTextView *upper = nil, *lower = nil;
    CGFloat upperY = 0, lowerY = 0;
    Check(MakeScrolledSource(text, NO, 0, &upper, &lower, &upperY, &lowerY), @"both parts of the split source are scrolled down");
    NSString *upperLine = VisibleTopLine(upper), *lowerLine = VisibleTopLine(lower);
    NSRange upperCaret = upper.selectedRange, lowerCaret = lower.selectedRange;
    controller.settings.findString = @"alpha";
    controller.settings.replaceString = @"X";
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper), @"Replace All in a scrolled source");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    NSString *replaced = [text stringByReplacingOccurrencesOfString:@"alpha" withString:@"X"];
    NSString *upperKeptLine = [upperLine stringByReplacingOccurrencesOfString:@"alpha" withString:@"X"];
    NSString *lowerKeptLine = [lowerLine stringByReplacingOccurrencesOfString:@"alpha" withString:@"X"];
    Check([upper.string isEqualToString:replaced] && [VisibleTopLine(upper) isEqualToString:upperKeptLine] && [VisibleTopLine(lower) isEqualToString:lowerKeptLine],
          [NSString stringWithFormat:@"Replace All leaves both parts on the lines they showed (%@ / %@)",
           [VisibleTopLine(upper) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet],
           [VisibleTopLine(lower) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]]);
    NSUInteger upperKept = CaretAfterShorterAlphas(text, upperCaret), lowerKept = CaretAfterShorterAlphas(text, lowerCaret);
    Check(NSEqualRanges(upper.selectedRange, NSMakeRange(upperKept, 0)) && NSEqualRanges(lower.selectedRange, NSMakeRange(lowerKept, 0)),
          [NSString stringWithFormat:@"the carets stay on the same character (%lu, %lu)", (unsigned long)upper.selectedRange.location, (unsigned long)lower.selectedRange.location]);

    [upper.undoManager undo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check([upper.string isEqualToString:text] && !upper.undoManager.canUndo
          && [VisibleTopLine(upper) isEqualToString:upperLine] && [VisibleTopLine(lower) isEqualToString:lowerLine]
          && NSEqualRanges(upper.selectedRange, upperCaret) && NSEqualRanges(lower.selectedRange, lowerCaret),
          @"one undo puts the text, the carets and the lines back");
    [upper.undoManager redo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check([upper.string isEqualToString:replaced]
          && [VisibleTopLine(upper) isEqualToString:upperKeptLine] && [VisibleTopLine(lower) isEqualToString:lowerKeptLine]
          && NSEqualRanges(upper.selectedRange, NSMakeRange(upperKept, 0)) && NSEqualRanges(lower.selectedRange, NSMakeRange(lowerKept, 0)),
          @"redo replaces again without moving the lines");
    [upper.undoManager undo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check([upper.string isEqualToString:text] && !upper.undoManager.canUndo
          && [VisibleTopLine(upper) isEqualToString:upperLine] && [VisibleTopLine(lower) isEqualToString:lowerLine]
          && NSEqualRanges(upper.selectedRange, upperCaret) && NSEqualRanges(lower.selectedRange, lowerCaret),
          @"a second undo puts the lines and the carets back too");

    // Every line becomes one character. The old scroll offset is below the text; both parts still show it.
    NSTextView *shortUpper = nil, *shortLower = nil;
    CGFloat shortUpperY = 0, shortLowerY = 0;
    Check(MakeScrolledSource(text, NO, 0, &shortUpper, &shortLower, &shortUpperY, &shortLowerY), @"scrolled before a replacement that removes the lines");
    controller.settings.findString = @".+\\n";
    controller.settings.replaceString = @"x";
    controller.settings.options = TSRegexFindRegularExpression;
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, shortUpper), @"Replace All that removes the lines");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(shortUpper.string.length == 80 && VisibleTopLine(shortUpper).length > 0 && VisibleTopLine(shortLower).length > 0,
          [NSString stringWithFormat:@"a much shorter text stays in view (%lu, upper %@, lower %@)",
           (unsigned long)shortUpper.string.length, VisibleTopLine(shortUpper), VisibleTopLine(shortLower)]);

    // In the selection: the lines stay, and the selection becomes the replaced scope.
    controller.settings.findString = @"alpha";
    controller.settings.replaceString = @"X";
    controller.settings.options = 0;
    NSTextView *scopeUpper = nil, *scopeLower = nil;
    CGFloat scopeUpperY = 0, scopeLowerY = 0;
    Check(MakeScrolledSource(text, NO, 0, &scopeUpper, &scopeLower, &scopeUpperY, &scopeLowerY), @"scrolled again for Replace All in Selection");
    NSUInteger line = [text rangeOfString:@"\n"].location + 1;
    NSRange scope = NSMakeRange(40 * line, line); // one line, one "alpha"
    scopeUpper.selectedRange = scope;
    [scopeUpper.window display];
    // The selection itself may scroll. What must stay is the line on screen when Replace All runs.
    NSString *scopeUpperLabel = LineNumberLabel(VisibleTopLine(scopeUpper));
    NSString *scopeLowerLabel = LineNumberLabel(VisibleTopLine(scopeLower));
    controller.settings.inSelection = YES;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAllInSelection, scopeUpper), @"Replace All in Selection");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(scopeUpperLabel.length > 0 && [LineNumberLabel(VisibleTopLine(scopeUpper)) isEqualToString:scopeUpperLabel]
          && [LineNumberLabel(VisibleTopLine(scopeLower)) isEqualToString:scopeLowerLabel],
          [NSString stringWithFormat:@"Replace All in Selection does not scroll (%@ / %@)",
           LineNumberLabel(VisibleTopLine(scopeUpper)), LineNumberLabel(VisibleTopLine(scopeLower))]);
    Check([scopeUpper.string containsString:@"alpha"] && [[scopeUpper.string substringWithRange:NSMakeRange(scope.location, line - 4)] containsString:@"X"],
          @"only the selected line is replaced");

    // No wrap, scrolled past the start of a long line. Shortening every line to a few characters used to leave both
    // parts looking at the old horizontal offset, which is past the text, so both were blank.
    NSMutableString *wide = [NSMutableString string];
    NSString *chunk = [@"a" stringByPaddingToLength:360 withString:@"a" startingAtIndex:0];
    for (int i = 0; i < 80; i++)
        [wide appendFormat:@"line %03d %@ tail\n", i, chunk];
    NSTextView *wideUpper = nil, *wideLower = nil;
    CGFloat wideUpperY = 0, wideLowerY = 0;
    Check(MakeScrolledSource(wide, YES, 1300, &wideUpper, &wideLower, &wideUpperY, &wideLowerY) && ScrollX(wideUpper) > 1000 && ScrollX(wideLower) > 1000,
          @"both parts are scrolled across a long line");
    NSString *wideUpperLabel = LineNumberLabel(VisibleTopLine(wideUpper));
    NSString *wideLowerLabel = LineNumberLabel(VisibleTopLine(wideLower));
    controller.settings.findString = chunk;
    controller.settings.replaceString = @"x";
    controller.settings.options = 0;
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, wideUpper), @"Replace All that shortens the long lines");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(wideUpperLabel.length > 0 && [LineNumberLabel(VisibleTopLine(wideUpper)) isEqualToString:wideUpperLabel]
          && [LineNumberLabel(VisibleTopLine(wideLower)) isEqualToString:wideLowerLabel]
          && ScrollX(wideUpper) < 50 && ScrollX(wideLower) < 50,
          [NSString stringWithFormat:@"a shortened long line stays in view (%@ / %@, x %.0f / %.0f)",
           LineNumberLabel(VisibleTopLine(wideUpper)), LineNumberLabel(VisibleTopLine(wideLower)), ScrollX(wideUpper), ScrollX(wideLower)]);
    [wideUpper.undoManager undo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check([LineNumberLabel(VisibleTopLine(wideUpper)) isEqualToString:wideUpperLabel]
          && [LineNumberLabel(VisibleTopLine(wideLower)) isEqualToString:wideLowerLabel]
          && ScrollX(wideUpper) > 1000 && ScrollX(wideLower) > 1000,
          [NSString stringWithFormat:@"undo scrolls back across the long line (%@ / %@, x %.0f / %.0f)",
           LineNumberLabel(VisibleTopLine(wideUpper)), LineNumberLabel(VisibleTopLine(wideLower)), ScrollX(wideUpper), ScrollX(wideLower)]);

    // The same horizontal offset stays when the lines are still wider than the window.
    NSTextView *keptUpper = nil, *keptLower = nil;
    CGFloat keptUpperY = 0, keptLowerY = 0;
    Check(MakeScrolledSource(wide, YES, 1300, &keptUpper, &keptLower, &keptUpperY, &keptLowerY), @"scrolled across before a replacement that keeps the width");
    NSString *keptUpperLabel = LineNumberLabel(VisibleTopLine(keptUpper));
    NSString *keptLowerLabel = LineNumberLabel(VisibleTopLine(keptLower));
    controller.settings.findString = @"tail";
    controller.settings.replaceString = @"TAIL";
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, keptUpper), @"Replace All that keeps the long lines wide");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(keptUpperLabel.length > 0 && [LineNumberLabel(VisibleTopLine(keptUpper)) isEqualToString:keptUpperLabel]
          && [LineNumberLabel(VisibleTopLine(keptLower)) isEqualToString:keptLowerLabel]
          && ScrollX(keptUpper) > 1000 && ScrollX(keptLower) > 1000,
          [NSString stringWithFormat:@"a still-wide line keeps its horizontal place (%@ / %@, x %.0f / %.0f)",
           LineNumberLabel(VisibleTopLine(keptUpper)), LineNumberLabel(VisibleTopLine(keptLower)), ScrollX(keptUpper), ScrollX(keptLower)]);

    // A refused replacement must not drop a redo that was already there, nor end a group that was not begun.
    controller.settings.findString = @"alpha";
    controller.settings.replaceString = @"X";
    controller.settings.options = 0;
    NSTextView *vetoUpper = nil, *vetoLower = nil;
    CGFloat vetoUpperY = 0, vetoLowerY = 0;
    Check(MakeScrolledSource(text, NO, 0, &vetoUpper, &vetoLower, &vetoUpperY, &vetoLowerY), @"scrolled before a refused replacement");
    [vetoUpper insertText:@"Z" replacementRange:vetoUpper.selectedRange];
    [vetoUpper.undoManager undo];
    Check(vetoUpper.undoManager.canRedo && [vetoUpper.string isEqualToString:text], @"an earlier edit can be redone");
    ReplaceAllVeto *veto = [ReplaceAllVeto new];
    vetoUpper.delegate = veto;
    vetoLower.delegate = veto;
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, vetoUpper), @"Replace All that the delegate refuses");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check([vetoUpper.string isEqualToString:text] && vetoUpper.undoManager.canRedo && !vetoUpper.undoManager.canUndo,
          @"a refused replacement leaves the text and the redo");
    // The delegate would also refuse the redo of the earlier edit. It was only there for the replacement.
    vetoUpper.delegate = nil;
    vetoLower.delegate = nil;
    [vetoUpper.undoManager redo];
    Check([vetoUpper.string containsString:@"Z"], @"the redo still puts the earlier edit back");
    [vetoUpper.undoManager undo];
    Check(vetoUpper.undoManager.canRedo, @"the earlier edit can be redone again");
    // The search starts while the source can be edited, then the source becomes read-only. The lock does not turn it
    // back on, and the replacement is refused when it is about to be applied.
    BOOL started = [controller performAction:TSAdvancedFindActionReplaceAll inTextView:vetoUpper];
    vetoUpper.editable = YES;
    vetoLower.editable = YES;
    vetoUpper.editable = NO;
    vetoLower.editable = NO;
    Check(started && TSTestWaitForTask(controller, 60), @"Replace All that becomes read-only while searching");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check([vetoUpper.string isEqualToString:text] && vetoUpper.undoManager.canRedo && !vetoUpper.undoManager.canUndo,
          @"a source that became read-only leaves the text and the redo");
    TestHorizontalLock();
    TestWrappedMiddleKeepsPlace();
    TestSameLengthKeepsScreen();
}

/// The display line at the top of the viewport, not the whole logical line. A wrapped line has several.
static NSString *VisibleTopFragment(NSTextView *view)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || layout.numberOfGlyphs == 0)
        return @"";
    NSRect visible = view.visibleRect;
    NSPoint inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x, NSMinY(visible) + 1 - view.textContainerOrigin.y);
    NSUInteger glyph = [layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    NSRange glyphs;
    [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&glyphs];
    NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    if (characters.location == NSNotFound || characters.location >= view.string.length)
        return @"";
    if (NSMaxRange(characters) > view.string.length)
        characters.length = view.string.length - characters.location;
    return [view.string substringWithRange:characters];
}

/// Pixels of what is on screen, packed one row at a time. The bitmap's own row padding is not compared.
static NSData *PackedPixels(NSView *view, NSAppearance *appearance)
{
    __block NSData *packed = [NSData data];
    [appearance performAsCurrentDrawingAppearance:^{
        [view layoutSubtreeIfNeeded];
        [view displayIfNeeded];
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        if (!rep || !rep.bitmapData)
            return;
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        NSInteger width = rep.pixelsWide, height = rep.pixelsHigh, bytesPerRow = rep.bytesPerRow, bytesPerPixel = rep.bitsPerPixel / 8;
        if (width <= 0 || height <= 0 || bytesPerPixel <= 0)
            return;
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)(width * height * bytesPerPixel)];
        unsigned char *destination = data.mutableBytes;
        unsigned char *source = (unsigned char *)rep.bitmapData;
        for (NSInteger y = 0; y < height; y++)
            memcpy(destination + (NSUInteger)(y * width * bytesPerPixel), source + (NSUInteger)(y * bytesPerRow), (size_t)(width * bytesPerPixel));
        packed = data;
    }];
    return packed;
}

/// Ask for the glyph at the top, then draw, so the next glyphIndexForPoint names the wrap on screen (#72).
static void SyncDrawnLine(NSTextView *view)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || layout.numberOfGlyphs == 0)
        return;
    NSRect rect = view.visibleRect;
    NSPoint point = NSMakePoint(NSMinX(rect) - view.textContainerOrigin.x, NSMinY(rect) + 1 - view.textContainerOrigin.y);
    (void)[layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    [view display];
}

static void PlaceWrappedWord(NSTextView *view, NSString *word)
{
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSRange target = [view.string rangeOfString:word];
    NSUInteger glyph = target.location == NSNotFound ? NSNotFound : [view.layoutManager glyphIndexForCharacterAtIndex:target.location];
    if (glyph == NSNotFound || glyph >= view.layoutManager.numberOfGlyphs)
        return;
    NSRect line = [view.layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSClipView *clip = view.enclosingScrollView.contentView;
    NSRect bounds = clip.bounds;
    bounds.origin.y += NSMinY(line) + view.textContainerOrigin.y + 3 - NSMinY(view.visibleRect);
    [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
    [view.enclosingScrollView reflectScrolledClipView:clip];
}

/// `colorAfterScroll` is how a document sets the source color: both parts are already in place, then the upper color
/// changes and then the lower one (TSDocument-Color.m). The other order sets each part's color, lays that part out
/// and scrolls it, and the second color change leaves the first part's glyph index on another wrap.
static void CheckWrappedPlace(NSString *text, BOOL colorAfterScroll)
{
    NSString *order = colorAfterScroll ? @"after the scroll" : @"on each part before its scroll";
    NSAppearance *appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    NSTextView *upper = nil, *lower = nil, *pictureUpper = nil, *pictureLower = nil;
    CGFloat upperY = 0, lowerY = 0, pictureUpperY = 0, pictureLowerY = 0;
    Check(MakeScrolledSource(text, NO, 0, &upper, &lower, &upperY, &lowerY)
          && MakeScrolledSource(text, NO, 0, &pictureUpper, &pictureLower, &pictureUpperY, &pictureLowerY),
          [@"wrapped source scrolls, " stringByAppendingString:order]);
    void (^arrange)(NSTextView *, NSTextView *) = ^(NSTextView *top, NSTextView *bottom) {
        top.window.appearance = appearance;
        top.appearance = appearance;
        bottom.appearance = appearance;
        if (colorAfterScroll) {
            PlaceWrappedWord(top, @"x35.371");
            PlaceWrappedWord(bottom, @"x25.126");
            // The same order as a theme change on a split source.
            top.textColor = NSColor.darkGrayColor;
            bottom.textColor = NSColor.darkGrayColor;
        } else {
            for (NSTextView *view in @[top, bottom]) {
                view.textColor = NSColor.textColor;
                view.backgroundColor = NSColor.textBackgroundColor;
                PlaceWrappedWord(view, view == top ? @"x35.371" : @"x25.126");
            }
        }
    };
    arrange(upper, lower);
    arrange(pictureUpper, pictureLower);
    // The picture is drawn now. The source under test is not, until Replace All has asked which line is showing.
    NSData *pictureTop = PackedPixels(pictureUpper.enclosingScrollView, appearance);
    NSData *pictureBottom = PackedPixels(pictureLower.enclosingScrollView, appearance);
    SyncDrawnLine(pictureUpper);
    SyncDrawnLine(pictureLower);
    Check(pictureTop.length > 0 && pictureBottom.length > 0
          && [VisibleTopFragment(pictureUpper) containsString:@"x35.371"]
          && [VisibleTopFragment(pictureLower) containsString:@"x25.126"],
          [NSString stringWithFormat:@"the picture shows the wrapped words (%@)", order]);
    controller.settings.findString = @"line";
    controller.settings.replaceString = @"LINE";
    controller.settings.options = 0;
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper),
          [@"Replace All inside a wrapped line, color " stringByAppendingString:order]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    NSData *afterTop = PackedPixels(upper.enclosingScrollView, appearance);
    NSData *afterBottom = PackedPixels(lower.enclosingScrollView, appearance);
    SyncDrawnLine(upper);
    SyncDrawnLine(lower);
    Check([VisibleTopFragment(upper) containsString:@"x35.371"] && [VisibleTopFragment(lower) containsString:@"x25.126"],
          [NSString stringWithFormat:@"a wrapped line stays on the same display line when the color is set %@ (%@ / %@)",
           order,
           [VisibleTopFragment(upper) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet],
           [VisibleTopFragment(lower) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]]);
    [upper.undoManager undo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    NSData *undoTop = PackedPixels(upper.enclosingScrollView, appearance);
    NSData *undoBottom = PackedPixels(lower.enclosingScrollView, appearance);
    SyncDrawnLine(upper);
    SyncDrawnLine(lower);
    Check([undoTop isEqualToData:pictureTop] && [undoBottom isEqualToData:pictureBottom]
          && [VisibleTopFragment(upper) containsString:@"x35.371"] && [VisibleTopFragment(lower) containsString:@"x25.126"],
          [NSString stringWithFormat:@"undo puts the wrapped display lines back (%@, %@ / %@)", order,
           [VisibleTopFragment(upper) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet],
           [VisibleTopFragment(lower) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]]);
    [upper.undoManager redo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    NSData *redoTop = PackedPixels(upper.enclosingScrollView, appearance);
    NSData *redoBottom = PackedPixels(lower.enclosingScrollView, appearance);
    SyncDrawnLine(upper);
    SyncDrawnLine(lower);
    Check([redoTop isEqualToData:afterTop] && [redoBottom isEqualToData:afterBottom]
          && [VisibleTopFragment(upper) containsString:@"x35.371"] && [VisibleTopFragment(lower) containsString:@"x25.126"],
          [NSString stringWithFormat:@"redo keeps the wrapped display lines (%@)", order]);
}

/// The character under the left edge of the viewport, measured the same way Replace All anchors it.
static NSUInteger LeftEdgeCharacter(NSTextView *view)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || layout.numberOfGlyphs == 0)
        return NSNotFound;
    NSRect visible = view.visibleRect;
    NSPoint point = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x, NSMinY(visible) + 1 - view.textContainerOrigin.y);
    (void)[layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    visible = view.visibleRect;
    point = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x, NSMinY(visible) + 1 - view.textContainerOrigin.y);
    NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    return [layout characterIndexForGlyphAtIndex:glyph];
}

/// How far `character` sits from the top and the left of the viewport. A negative value starts just outside.
static void CharacterPins(NSTextView *view, NSUInteger character, CGFloat *pinX, CGFloat *pinY)
{
    NSLayoutManager *layout = view.layoutManager;
    if (!layout || character >= view.string.length) {
        *pinX = 0;
        *pinY = 0;
        return;
    }
    [layout ensureLayoutForCharacterRange:NSMakeRange(character, 1)];
    NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:character];
    if (glyph >= layout.numberOfGlyphs) {
        *pinX = 0;
        *pinY = 0;
        return;
    }
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSPoint location = [layout locationForGlyphAtIndex:glyph];
    *pinX = view.textContainerOrigin.x + NSMinX(fragment) + location.x - NSMinX(view.visibleRect);
    *pinY = view.textContainerOrigin.y + NSMinY(fragment) - NSMinY(view.visibleRect);
}

static CGFloat GlyphPin(NSTextView *view, NSUInteger character)
{
    CGFloat pinX = 0, pinY = 0;
    CharacterPins(view, character, &pinX, &pinY);
    return pinX;
}

/// Where a literal Replace All leaves `index`. A character inside a match lands at the end of that replacement.
static NSUInteger IndexAfterLiteralReplace(NSString *text, NSUInteger index, NSString *find, NSString *replace)
{
    NSInteger delta = (NSInteger)replace.length - (NSInteger)find.length;
    NSInteger shift = 0;
    NSUInteger cursor = 0;
    while (cursor < text.length) {
        NSRange found = [text rangeOfString:find options:0 range:NSMakeRange(cursor, text.length - cursor)];
        if (found.location == NSNotFound || found.location > index)
            break;
        if (found.location == index)
            return (NSUInteger)((NSInteger)index + shift);
        if (index < NSMaxRange(found))
            return (NSUInteger)((NSInteger)NSMaxRange(found) + shift + delta);
        shift += delta;
        cursor = NSMaxRange(found);
    }
    NSInteger moved = (NSInteger)index + shift;
    return moved > 0 ? (NSUInteger)moved : 0;
}

/// Puts `character` one point inside the left edge. The top line may be a different, shorter line, so the character
/// under the top-left point is not always `character`.
static BOOL ScrollGlyphToLeftEdge(NSTextView *view, NSUInteger character)
{
    NSLayoutManager *layout = view.layoutManager;
    if (!layout || character >= view.string.length)
        return NO;
    NSRange line = [view.string lineRangeForRange:NSMakeRange(character, 0)];
    [layout ensureLayoutForCharacterRange:line];
    NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:character];
    if (glyph >= layout.numberOfGlyphs)
        return NO;
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSPoint location = [layout locationForGlyphAtIndex:glyph];
    CGFloat glyphX = view.textContainerOrigin.x + NSMinX(fragment) + location.x;
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (!clip)
        return NO;
    NSRect bounds = clip.bounds;
    bounds.origin.x = glyphX + 1;
    [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
    [view.enclosingScrollView reflectScrolledClipView:clip];
    [view.window display];
    return YES;
}

/// Puts `character` one point inside the left edge, so the anchor is that character and not the one before it.
static BOOL ScrollCharacterToLeft(NSTextView *view, NSUInteger character)
{
    return ScrollGlyphToLeftEdge(view, character) && LeftEdgeCharacter(view) == character;
}

static NSRange TopFragmentRange(NSTextView *view)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || layout.numberOfGlyphs == 0)
        return NSMakeRange(NSNotFound, 0);
    NSRect visible = view.visibleRect;
    NSPoint inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x, NSMinY(visible) + 1 - view.textContainerOrigin.y);
    NSUInteger glyph = [layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    NSRange glyphs;
    [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&glyphs];
    return [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
}

/// `find` sits before KEEP on each line. Without wrapping, KEEP is scrolled to the left edge and must stay there
/// while the scroll offset follows the new width. With wrapping there is no sideways scroll: the left edge stays
/// when the edit is past it, and an edit before it must not slide the viewport off the text.
static void CheckHorizontalLock(NSLineBreakMode mode, NSString *find, NSString *replace, BOOL markerAtLeft)
{
    NSString *modeName = mode == NSLineBreakByClipping ? @"no wrap" : mode == NSLineBreakByWordWrapping ? @"word wrap" : @"character wrap";
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    NSMutableString *text = [NSMutableString string];
    for (int i = 0; i < 80; i++) {
        [text appendFormat:@"L%03d ", i];
        for (int k = 0; k < 40; k++)
            [text appendString:@"abc "];
        [text appendString:@"KEEP "];
        for (int k = 0; k < 20; k++)
            [text appendString:@"xyz "];
        if (i >= 60)
            [text appendString:@"LATE "];
        [text appendString:@"\n"];
    }
    NSTextView *upper = nil, *lower = nil;
    CGFloat upperY = 0, lowerY = 0;
    Check(MakeScrolledSourceMode(text, mode, 0, &upper, &lower, &upperY, &lowerY),
          [NSString stringWithFormat:@"%@: both parts scroll down a long line", modeName]);
    (void)upperY;
    (void)lowerY;
    if (markerAtLeft) {
        for (NSTextView *view in @[upper, lower]) {
            NSUInteger edge = LeftEdgeCharacter(view);
            NSRange line = edge == NSNotFound ? NSMakeRange(0, 0) : [view.string lineRangeForRange:NSMakeRange(edge, 0)];
            NSRange keep = [view.string rangeOfString:@"KEEP" options:0 range:line];
            Check(keep.location != NSNotFound && ScrollCharacterToLeft(view, keep.location),
                  [NSString stringWithFormat:@"%@: KEEP is at the left edge", modeName]);
        }
    }
    NSUInteger upperChar = LeftEdgeCharacter(upper), lowerChar = LeftEdgeCharacter(lower);
    CGFloat upperPin = 0, upperPinY = 0, lowerPin = 0, lowerPinY = 0;
    CharacterPins(upper, upperChar, &upperPin, &upperPinY);
    CharacterPins(lower, lowerChar, &lowerPin, &lowerPinY);
    CGFloat upperX = ScrollX(upper), lowerX = ScrollX(lower);
    NSString *upperSnippet = upperChar < text.length ? [text substringWithRange:NSMakeRange(upperChar, MIN(4, text.length - upperChar))] : @"";
    NSString *lowerSnippet = lowerChar < text.length ? [text substringWithRange:NSMakeRange(lowerChar, MIN(4, text.length - lowerChar))] : @"";
    controller.settings.findString = find;
    controller.settings.replaceString = replace;
    controller.settings.options = 0;
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper),
          [NSString stringWithFormat:@"%@: Replace All %@", modeName, find]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    NSUInteger upperMoved = IndexAfterLiteralReplace(text, upperChar, find, replace);
    NSUInteger lowerMoved = IndexAfterLiteralReplace(text, lowerChar, find, replace);
    BOOL upperLocked = upperMoved < upper.string.length && fabs(GlyphPin(upper, upperMoved) - upperPin) < 2;
    BOOL lowerLocked = lowerMoved < lower.string.length && fabs(GlyphPin(lower, lowerMoved) - lowerPin) < 2;
    if (markerAtLeft) {
        NSInteger direction = (NSInteger)replace.length - (NSInteger)find.length;
        Check(upperLocked && lowerLocked
              && (direction < 0 ? ScrollX(upper) < upperX - 50 && ScrollX(lower) < lowerX - 50
                                : ScrollX(upper) > upperX + 50 && ScrollX(lower) > lowerX + 50),
              [NSString stringWithFormat:@"%@: %@ -> %@ keeps the left-edge character (pin %.1f -> %.1f / %.1f -> %.1f, x %.0f -> %.0f / %.0f -> %.0f, %@ / %@)",
               modeName, find, replace, upperPin, GlyphPin(upper, upperMoved), lowerPin, GlyphPin(lower, lowerMoved),
               upperX, ScrollX(upper), lowerX, ScrollX(lower), upperSnippet, lowerSnippet]);
        [upper.undoManager undo];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(fabs(GlyphPin(upper, upperChar) - upperPin) < 2 && fabs(GlyphPin(lower, lowerChar) - lowerPin) < 2
              && fabs(ScrollX(upper) - upperX) < 2 && fabs(ScrollX(lower) - lowerX) < 2,
              [NSString stringWithFormat:@"%@: undo puts the long line back (pin %.1f / %.1f, x %.0f / %.0f)",
               modeName, GlyphPin(upper, upperChar), GlyphPin(lower, lowerChar), ScrollX(upper), ScrollX(lower)]);
        [upper.undoManager redo];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(upperMoved < upper.string.length && fabs(GlyphPin(upper, upperMoved) - upperPin) < 2
              && lowerMoved < lower.string.length && fabs(GlyphPin(lower, lowerMoved) - lowerPin) < 2,
              [NSString stringWithFormat:@"%@: redo keeps the left-edge character", modeName]);
    } else if ([find isEqualToString:@"LATE"]) {
        CGFloat upperAfterY = 0, lowerAfterY = 0, ignored = 0;
        CharacterPins(upper, upperMoved, &ignored, &upperAfterY);
        CharacterPins(lower, lowerMoved, &ignored, &lowerAfterY);
        Check(upperLocked && lowerLocked && ScrollX(upper) < 5 && ScrollX(lower) < 5
              && fabs(upperAfterY - upperPinY) < 2 && fabs(lowerAfterY - lowerPinY) < 2,
              [NSString stringWithFormat:@"%@: an edit below the window leaves the text where it was (x pin %.1f -> %.1f / %.1f -> %.1f, y pin %.1f -> %.1f / %.1f -> %.1f, scroll %.0f / %.0f)",
               modeName, upperPin, GlyphPin(upper, upperMoved), lowerPin, GlyphPin(lower, lowerMoved),
               upperPinY, upperAfterY, lowerPinY, lowerAfterY, ScrollX(upper), ScrollX(lower)]);
    } else {
        NSRange upperTop = TopFragmentRange(upper), lowerTop = TopFragmentRange(lower);
        Check(ScrollX(upper) < 5 && ScrollX(lower) < 5
              && upperTop.location != NSNotFound && NSLocationInRange(upperMoved, upperTop)
              && lowerTop.location != NSNotFound && NSLocationInRange(lowerMoved, lowerTop)
              && VisibleTopFragment(upper).length > 0 && VisibleTopFragment(lower).length > 0,
              [NSString stringWithFormat:@"%@: a shorter line stays in view without scrolling sideways (%@ / %@, x %.0f / %.0f)",
               modeName,
               [VisibleTopFragment(upper) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet],
               [VisibleTopFragment(lower) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet],
               ScrollX(upper), ScrollX(lower)]);
    }
}

/// The top line ends before the left edge. KEEP on the long line under it is at that edge and must stay there.
static void CheckShortTopLine(NSString *replace)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    NSMutableString *text = [NSMutableString string];
    for (int i = 0; i < 80; i++) {
        if (i % 2 == 0) {
            [text appendFormat:@"S%03d\n", i];
            continue;
        }
        [text appendFormat:@"L%03d ", i];
        for (int k = 0; k < 40; k++)
            [text appendString:@"abc "];
        [text appendString:@"KEEP "];
        for (int k = 0; k < 20; k++)
            [text appendString:@"xyz "];
        [text appendString:@"\n"];
    }
    NSTextView *upper = nil, *lower = nil;
    CGFloat upperY = 0, lowerY = 0;
    // The first line is five characters, so this builder's usual stride does not move the viewport. The views are
    // still the split source. Each part is then placed on its own short line.
    MakeScrolledSourceMode(text, NSLineBreakByClipping, 0, &upper, &lower, &upperY, &lowerY);
    (void)upperY;
    (void)lowerY;
    Check(upper != nil && lower != nil, @"short top line: both parts exist");
    NSTextView *views[2] = {upper, lower};
    NSString *labels[2] = {@"S040\n", @"S020\n"};
    NSUInteger keeps[2] = {0, 0}, shorts[2] = {0, 0};
    CGFloat pins[2] = {0, 0}, tops[2] = {0, 0}, xs[2] = {0, 0};
    for (NSUInteger v = 0; v < 2; v++) {
        NSTextView *view = views[v];
        NSRange line = [text rangeOfString:labels[v]];
        [view scrollRangeToVisible:NSMakeRange(line.location, 0)];
        CGFloat ignored = 0, pinY = 0;
        CharacterPins(view, line.location, &ignored, &pinY);
        NSClipView *clip = view.enclosingScrollView.contentView;
        NSRect bounds = clip.bounds;
        bounds.origin.y += pinY;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
        [view.enclosingScrollView reflectScrolledClipView:clip];
        NSRange below = [view.string lineRangeForRange:NSMakeRange(NSMaxRange(line), 0)];
        NSRange keep = [view.string rangeOfString:@"KEEP" options:0 range:below];
        shorts[v] = line.location;
        keeps[v] = keep.location;
        Check(keep.location != NSNotFound && ScrollGlyphToLeftEdge(view, keep.location),
              @"short top line: KEEP scrolls to the left edge");
        NSUInteger top = LeftEdgeCharacter(view);
        NSRange topLine = top == NSNotFound ? NSMakeRange(0, 0) : [view.string lineRangeForRange:NSMakeRange(top, 0)];
        CharacterPins(view, keep.location, &pins[v], &ignored);
        CharacterPins(view, line.location, &ignored, &tops[v]);
        xs[v] = ScrollX(view);
        Check(topLine.length < 10 && fabs(pins[v]) < 3 && fabs(tops[v]) < 2,
              [NSString stringWithFormat:@"short top line: part %lu shows the short line above KEEP (top %lu chars, KEEP pin %.1f, line pin %.1f)",
               (unsigned long)v, (unsigned long)topLine.length, pins[v], tops[v]]);
    }
    controller.settings.findString = @"abc";
    controller.settings.replaceString = replace;
    controller.settings.options = 0;
    controller.settings.inSelection = NO;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper),
          [NSString stringWithFormat:@"short top line: Replace All abc -> %@", replace]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    NSInteger direction = (NSInteger)replace.length - (NSInteger)@"abc".length;
    for (NSUInteger v = 0; v < 2; v++) {
        NSTextView *view = views[v];
        NSUInteger moved = IndexAfterLiteralReplace(text, keeps[v], @"abc", replace);
        NSUInteger movedTop = IndexAfterLiteralReplace(text, shorts[v], @"abc", replace);
        CGFloat pin = 0, top = 0, ignored = 0;
        CharacterPins(view, moved, &pin, &ignored);
        CharacterPins(view, movedTop, &ignored, &top);
        NSRange fragment = TopFragmentRange(view);
        BOOL scrolled = direction < 0 ? ScrollX(view) < xs[v] - 50 : ScrollX(view) > xs[v] + 50;
        Check(fabs(pin - pins[v]) < 2 && fabs(top - tops[v]) < 2 && scrolled
              && fragment.location != NSNotFound && NSLocationInRange(movedTop, fragment),
              [NSString stringWithFormat:@"short top line: abc -> %@ keeps KEEP (pin %.1f -> %.1f, line %.1f -> %.1f, x %.0f -> %.0f)",
               replace, pins[v], pin, tops[v], top, xs[v], ScrollX(view)]);
    }
    [upper.undoManager undo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    for (NSUInteger v = 0; v < 2; v++) {
        CGFloat pin = 0, ignored = 0;
        CharacterPins(views[v], keeps[v], &pin, &ignored);
        Check(fabs(pin - pins[v]) < 2 && fabs(ScrollX(views[v]) - xs[v]) < 2,
              [NSString stringWithFormat:@"short top line: undo puts KEEP back (pin %.1f, x %.0f)", pin, ScrollX(views[v])]);
    }
    [upper.undoManager redo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    for (NSUInteger v = 0; v < 2; v++) {
        NSUInteger moved = IndexAfterLiteralReplace(text, keeps[v], @"abc", replace);
        CGFloat pin = 0, ignored = 0;
        CharacterPins(views[v], moved, &pin, &ignored);
        Check(fabs(pin - pins[v]) < 2,
              [NSString stringWithFormat:@"short top line: redo keeps KEEP (pin %.1f)", pin]);
    }
}

/// Issue #72, the follow-up: long lines moved sideways. The source window wraps or it does not.
static void TestHorizontalLock(void)
{
    CheckShortTopLine(@"Z");
    CheckShortTopLine(@"abcd");
    CheckHorizontalLock(NSLineBreakByClipping, @"abc", @"Z", YES);
    CheckHorizontalLock(NSLineBreakByClipping, @"abc", @"abcd", YES);
    NSLineBreakMode wrapped[] = {NSLineBreakByWordWrapping, NSLineBreakByCharWrapping};
    for (NSUInteger i = 0; i < sizeof wrapped / sizeof wrapped[0]; i++) {
        CheckHorizontalLock(wrapped[i], @"LATE", @"LATER", NO);
        CheckHorizontalLock(wrapped[i], @"abc", @"Z", NO);
    }
}

/// A long logical line, wrapped, scrolled to a word in the middle of that line. Same-length Replace All must leave
/// that display line at the top. The color is set in the two orders that leave the glyph index on another wrap until
/// the view is drawn (#72).
static void TestWrappedMiddleKeepsPlace(void)
{
    NSMutableString *mixed = [NSMutableString string];
    for (int i = 0; i < 500; i++) {
        [mixed appendFormat:@"line%03d ", i];
        int words = i % 7 == 0 ? 75 : i % 3 == 0 ? 12 : 4;
        for (int w = 0; w < words; w++)
            [mixed appendFormat:@"x%02d.%03d ", w, i];
        [mixed appendString:@"\n"];
    }
    CheckWrappedPlace(mixed, YES);
    CheckWrappedPlace(mixed, NO);
}

/// Lines of `copies` times "aaa ", so a same-length replacement has somewhere to land, including past column 217.
static NSString *WideLines(NSUInteger lines, NSUInteger copies)
{
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < lines; i++) {
        [text appendFormat:@"L%03lu ", (unsigned long)i];
        for (NSUInteger k = 0; k < copies; k++)
            [text appendString:@"aaa "];
        [text appendString:@"\n"];
    }
    return text;
}

static NSUInteger IndexOnLine(NSString *text, NSUInteger lineNumber, CGFloat along)
{
    NSUInteger index = 0, number = 0;
    while (index < text.length) {
        NSRange line = [text lineRangeForRange:NSMakeRange(index, 0)];
        if (number == lineNumber) {
            NSUInteger span = line.length;
            if (span > 0 && [text characterAtIndex:NSMaxRange(line) - 1] == '\n')
                span--;
            if (span == 0)
                return line.location;
            NSUInteger offset = (NSUInteger)llround((double)(span - 1) * (double)MIN(MAX(along, 0), 1));
            return line.location + MIN(offset, span - 1);
        }
        number++;
        index = NSMaxRange(line);
    }
    return text.length > 0 ? text.length - 1 : 0;
}

static NSUInteger LogicalLineCount(NSString *text)
{
    if (text.length == 0)
        return 0;
    NSUInteger count = 0, index = 0;
    while (index < text.length) {
        count++;
        NSRange line = [text lineRangeForRange:NSMakeRange(index, 0)];
        if (NSMaxRange(line) <= index)
            break;
        index = NSMaxRange(line);
    }
    return count;
}

/// Non-contiguous layout leaves the text view's frame origin far above the used rect. The clip then shows a
/// different line than the one `lineTop` names. A real document at the top of the file has the frame at 0 and the
/// clip at minus the toolbar inset (#72).
static void NormalizeTextFrame(NSTextView *view)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container)
        return;
    BOOL noncontiguous = layout.allowsNonContiguousLayout;
    layout.allowsNonContiguousLayout = NO;
    [layout ensureLayoutForTextContainer:container];
    NSRect used = [layout usedRectForTextContainer:container];
    NSSize clipSize = view.enclosingScrollView.contentView.bounds.size;
    CGFloat width = MAX(clipSize.width, ceil(NSMaxX(used) + view.textContainerOrigin.x));
    CGFloat height = MAX(clipSize.height, ceil(NSMaxY(used) + view.textContainerOrigin.y));
    layout.allowsNonContiguousLayout = noncontiguous;
    [view setFrame:NSMakeRect(0, 0, MAX(width, 1), MAX(height, 1))];
}

/// Puts `character` at a fraction of the viewport. Clipping scrolls sideways. Wrapping keeps x at 0 and uses the
/// character's display line for the vertical fraction: the middle of a wrapped line is how far across that line the
/// reader is.
static BOOL PlaceGlyph(NSTextView *view, NSUInteger character, CGFloat viewportX, CGFloat viewportY)
{
    NSLayoutManager *layout = view.layoutManager;
    if (!layout || view.string.length == 0 || character >= view.string.length)
        return NO;
    [layout ensureLayoutForTextContainer:view.textContainer];
    if (view.horizontallyResizable)
        [view sizeToFit];
    NormalizeTextFrame(view);
    NSRange line = [view.string lineRangeForRange:NSMakeRange(character, 0)];
    [layout ensureLayoutForCharacterRange:line];
    NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:character];
    if (glyph >= layout.numberOfGlyphs)
        return NO;
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSPoint location = [layout locationForGlyphAtIndex:glyph];
    CGFloat glyphX = view.textContainerOrigin.x + NSMinX(fragment) + location.x;
    CGFloat lineTop = view.textContainerOrigin.y + NSMinY(fragment);
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (!clip)
        return NO;
    NSRect bounds = clip.bounds;
    bounds.origin.x = view.horizontallyResizable ? glyphX - viewportX * NSWidth(bounds) : 0;
    bounds.origin.y = lineTop - viewportY * NSHeight(bounds);
    [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
    [view.enclosingScrollView reflectScrolledClipView:clip];
    [view.window display];
    return YES;
}

/// The character under a point in the viewport. (0, 0) is the top left, just inside the edge.
static NSUInteger CharacterAtViewport(NSTextView *view, CGFloat xFraction, CGFloat yFraction)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || layout.numberOfGlyphs == 0)
        return NSNotFound;
    NSRect visible = view.visibleRect;
    CGFloat x = xFraction <= 0 ? 1 : NSWidth(visible) * xFraction;
    CGFloat y = yFraction <= 0 ? 1 : NSHeight(visible) * yFraction;
    NSPoint point = NSMakePoint(NSMinX(visible) + x - view.textContainerOrigin.x, NSMinY(visible) + y - view.textContainerOrigin.y);
    (void)[layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    return [layout characterIndexForGlyphAtIndex:glyph];
}

/// `lines` display lines under the top of the viewport, then `column` on that logical line. The caret in the report
/// sat on line 5 while line 1 was the top line.
static NSUInteger LocationLinesBelow(NSTextView *view, NSInteger lines, NSUInteger column)
{
    NSLayoutManager *layout = view.layoutManager;
    NSRange top = TopFragmentRange(view);
    if (!layout || top.location == NSNotFound || top.location >= view.string.length)
        return 0;
    NSUInteger laid = MIN(view.string.length - top.location, 12000);
    [layout ensureLayoutForCharacterRange:NSMakeRange(top.location, laid)];
    NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:top.location];
    NSRange glyphs = NSMakeRange(glyph, 1);
    for (NSInteger i = 0; i < lines; i++) {
        NSUInteger next = NSMaxRange(glyphs);
        if (next >= layout.numberOfGlyphs)
            break;
        [layout lineFragmentRectForGlyphAtIndex:next effectiveRange:&glyphs];
    }
    NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    if (characters.location >= view.string.length)
        return view.string.length > 0 ? view.string.length - 1 : 0;
    NSRange logical = [view.string lineRangeForRange:NSMakeRange(characters.location, 0)];
    NSUInteger span = logical.length;
    if (span > 0 && [view.string characterAtIndex:NSMaxRange(logical) - 1] == '\n')
        span--;
    return logical.location + MIN(column, span > 0 ? span - 1 : 0);
}

/// Sets the caret, then puts the clip back. Assigning selectedRange scrolls the caret into view.
static void SetCaretKeepingPlace(NSTextView *view, NSUInteger location)
{
    NSClipView *clip = view.enclosingScrollView.contentView;
    NSPoint origin = clip.bounds.origin;
    view.selectedRange = NSMakeRange(MIN(location, view.string.length), 0);
    NSRect bounds = clip.bounds;
    bounds.origin = origin;
    [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
    [view.enclosingScrollView reflectScrolledClipView:clip];
    [view.window display];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    bounds = clip.bounds;
    bounds.origin = origin;
    [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
    [view.enclosingScrollView reflectScrolledClipView:clip];
    [view.window display];
}

static NSString *BreakModeName(NSLineBreakMode mode)
{
    if (mode == NSLineBreakByClipping)
        return @"no wrap";
    if (mode == NSLineBreakByWordWrapping)
        return @"word wrap";
    return @"character wrap";
}

/// Same-length Replace All must not move the clip at any scroll, not only by the time the run loop settles (#72).
static IMP TSWatchedClipScroll;
static BOOL TSWatchClip;
static BOOL TSClipMoved;

static void TSWatchScrollPoint(NSClipView *clip, SEL _cmd, NSPoint point)
{
    NSPoint before = clip.bounds.origin;
    ((void (*)(id, SEL, NSPoint))TSWatchedClipScroll)(clip, _cmd, point);
    if (!TSWatchClip)
        return;
    NSPoint after = clip.bounds.origin;
    if (fabs(after.x - before.x) >= 1 || fabs(after.y - before.y) >= 1)
        TSClipMoved = YES;
}

static void TSInstallClipWatch(void)
{
    if (TSWatchedClipScroll)
        return;
    Method method = class_getInstanceMethod(NSClipView.class, @selector(scrollToPoint:));
    TSWatchedClipScroll = method_setImplementation(method, (IMP)TSWatchScrollPoint);
}

/// One split source, the caret four display lines below the top (column 217, as in the report), then Replace All.
static void CheckPlacedReplace(NSString *text, NSLineBreakMode mode, NSString *place, NSUInteger lineNumber, CGFloat along,
                               CGFloat viewportX, CGFloat viewportY, NSString *replace, BOOL expectStill)
{
    NSString *modeName = BreakModeName(mode);
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    NSTextView *upper = nil, *lower = nil;
    CGFloat ignoredY = 0;
    Check(MakeScrolledSourceMode(text, mode, 0, &upper, &lower, &ignoredY, &ignoredY),
          [NSString stringWithFormat:@"%@ / %@: the split source scrolls", modeName, place]);
    NSTextView *views[2] = {upper, lower};
    NSUInteger featureLine = lineNumber == NSNotFound ? LogicalLineCount(text) / 2 : lineNumber;
    NSPoint origin[2];
    NSUInteger center[2], top[2], caret[2];
    CGFloat pinX[2], pinY[2], edgePinX[2], edgePinY[2];
    NSUInteger edge[2];
    for (NSUInteger v = 0; v < 2; v++) {
        NSTextView *view = views[v];
        NSUInteger feature = IndexOnLine(text, featureLine, along);
        Check(PlaceGlyph(view, feature, viewportX, viewportY),
              [NSString stringWithFormat:@"%@ / %@: part %lu is placed", modeName, place, (unsigned long)v]);
        NSUInteger caretLocation = LocationLinesBelow(view, 4, 217);
        SetCaretKeepingPlace(view, caretLocation);
        origin[v] = NSMakePoint(ScrollX(view), ScrollY(view));
        center[v] = CharacterAtViewport(view, 0.5, 0.5);
        top[v] = TopFragmentRange(view).location;
        caret[v] = view.selectedRange.location;
        edge[v] = LeftEdgeCharacter(view);
        CharacterPins(view, center[v], &pinX[v], &pinY[v]);
        CharacterPins(view, edge[v], &edgePinX[v], &edgePinY[v]);
        NSRange topFragment = TopFragmentRange(view);
        Check(top[v] != NSNotFound && center[v] != NSNotFound && edge[v] != NSNotFound
              && !NSLocationInRange(caret[v], topFragment),
              [NSString stringWithFormat:@"%@ / %@: part %lu shows text and the caret is not on the top line (top %lu, caret %lu)",
               modeName, place, (unsigned long)v, (unsigned long)top[v], (unsigned long)caret[v]]);
    }
    controller.settings.findString = @"aaa";
    controller.settings.replaceString = replace;
    controller.settings.options = 0;
    controller.settings.inSelection = NO;
    TSClipMoved = NO;
    TSWatchClip = expectStill;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper),
          [NSString stringWithFormat:@"%@ / %@: Replace All aaa -> %@", modeName, place, replace]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    TSWatchClip = NO;
    for (NSUInteger v = 0; v < 2; v++) {
        NSTextView *view = views[v];
        NSUInteger centerNow = CharacterAtViewport(view, 0.5, 0.5);
        NSUInteger topNow = TopFragmentRange(view).location;
        NSRange topFragment = TopFragmentRange(view);
        BOOL caretOnTop = topFragment.location != NSNotFound && NSLocationInRange(view.selectedRange.location, topFragment);
        if (expectStill) {
            CGFloat centerX = 0, centerY = 0;
            CharacterPins(view, center[v], &centerX, &centerY);
            Check(fabs(ScrollX(view) - origin[v].x) < 1 && fabs(ScrollY(view) - origin[v].y) < 1
                  && centerNow == center[v] && topNow == top[v]
                  && fabs(centerX - pinX[v]) < 1 && fabs(centerY - pinY[v]) < 1
                  && view.selectedRange.location == caret[v] && !caretOnTop && !TSClipMoved,
                  [NSString stringWithFormat:@"%@ / %@: aaa -> %@ does not move part %lu (scroll %.1f,%.1f -> %.1f,%.1f, center %lu -> %lu, top %lu -> %lu, caret %lu, jumped %d)",
                   modeName, place, replace, (unsigned long)v,
                   origin[v].x, origin[v].y, ScrollX(view), ScrollY(view),
                   (unsigned long)center[v], (unsigned long)centerNow,
                   (unsigned long)top[v], (unsigned long)topNow, (unsigned long)view.selectedRange.location, TSClipMoved]);
        } else {
            NSUInteger moved = IndexAfterLiteralReplace(text, edge[v], @"aaa", replace);
            CGFloat nowX = 0, nowY = 0;
            CharacterPins(view, moved, &nowX, &nowY);
            NSInteger direction = (NSInteger)replace.length - (NSInteger)@"aaa".length;
            BOOL sideways = mode != NSLineBreakByClipping || origin[v].x <= 80
                || (direction < 0 ? ScrollX(view) < origin[v].x - 20 : ScrollX(view) > origin[v].x + 20);
            // Wrapping has no horizontal scroll. A shorter or longer match before the left edge reflows that
            // character to another column of the same display line, so its x pin moves while the line stays.
            BOOL xPinned = mode == NSLineBreakByClipping ? fabs(nowX - edgePinX[v]) < 2 : ScrollX(view) < 5;
            Check(xPinned && fabs(nowY - edgePinY[v]) < 2 && sideways && !caretOnTop,
                  [NSString stringWithFormat:@"%@ / %@: aaa -> %@ keeps the left-edge character on part %lu (pin %.1f,%.1f -> %.1f,%.1f, scroll %.1f,%.1f -> %.1f,%.1f, caret %lu on top %d)",
                   modeName, place, replace, (unsigned long)v,
                   edgePinX[v], edgePinY[v], nowX, nowY,
                   origin[v].x, origin[v].y, ScrollX(view), ScrollY(view),
                   (unsigned long)view.selectedRange.location, caretOnTop]);
        }
    }
    if (!expectStill)
        return;
    TSWatchClip = YES;
    [upper.undoManager undo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    Check([upper.string isEqualToString:text],
          [NSString stringWithFormat:@"%@ / %@: undo restores the text", modeName, place]);
    for (NSUInteger v = 0; v < 2; v++) {
        Check(fabs(ScrollX(views[v]) - origin[v].x) < 1 && fabs(ScrollY(views[v]) - origin[v].y) < 1
              && views[v].selectedRange.location == caret[v] && !TSClipMoved,
              [NSString stringWithFormat:@"%@ / %@: undo puts part %lu back (scroll %.1f,%.1f, caret %lu, jumped %d)",
               modeName, place, (unsigned long)v, ScrollX(views[v]), ScrollY(views[v]),
               (unsigned long)views[v].selectedRange.location, TSClipMoved]);
    }
    [upper.undoManager redo];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    TSWatchClip = NO;
    for (NSUInteger v = 0; v < 2; v++) {
        Check(fabs(ScrollX(views[v]) - origin[v].x) < 1 && fabs(ScrollY(views[v]) - origin[v].y) < 1
              && CharacterAtViewport(views[v], 0.5, 0.5) == center[v] && !TSClipMoved,
              [NSString stringWithFormat:@"%@ / %@: redo keeps part %lu still (scroll %.1f,%.1f, center %lu, jumped %d)",
               modeName, place, (unsigned long)v, ScrollX(views[v]), ScrollY(views[v]),
               (unsigned long)CharacterAtViewport(views[v], 0.5, 0.5), TSClipMoved]);
    }
}

static void ScrollToProposed(NSTextView *view, CGFloat x, CGFloat y)
{
    NSClipView *clip = view.enclosingScrollView.contentView;
    NSRect bounds = clip.bounds;
    bounds.origin = NSMakePoint(x, y);
    [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
    [view.enclosingScrollView reflectScrolledClipView:clip];
    [view.window display];
}

static void ApplyInsets(NSTextView *view, NSEdgeInsets insets)
{
    NSScrollView *scroll = view.enclosingScrollView;
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.contentInsets = insets;
    [view.window display];
}

/// A document window draws the source under the toolbar, so the clip origin at the top of the file is minus the
/// top inset, and the bottom inset lets the clip go past the text frame. The old clamp used the frame and dropped
/// both. The other half of the split has no inset, as in the real window (#72).
static void TestInsetPlace(NSString *place, NSLineBreakMode mode, NSEdgeInsets insets, CGFloat proposeX, CGFloat proposeY,
                           NSString *replace, BOOL expectStill, BOOL expectPastFrame)
{
    NSString *modeName = BreakModeName(mode);
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController([TSMemoryDefaults new], &beeps);
    NSString *text = WideLines(40, 50);
    NSTextView *upper = nil, *lower = nil;
    CGFloat ignored = 0;
    Check(MakeScrolledSourceMode(text, mode, 0, &upper, &lower, &ignored, &ignored),
          [NSString stringWithFormat:@"inset %@ / %@: the split source scrolls", modeName, place]);
    // The caret scroll above lands in the estimated coordinate system (frame origin far above 0). Put both panes
    // back on a frame that starts at 0, which is where a document window rests, then apply the toolbar inset (#72).
    NormalizeTextFrame(upper);
    NormalizeTextFrame(lower);
    ApplyInsets(upper, insets);
    ScrollToProposed(upper, proposeX, proposeY);
    ScrollToProposed(lower, 0, 0);
    SetCaretKeepingPlace(upper, LocationLinesBelow(upper, 4, 217));
    ScrollToProposed(upper, proposeX, proposeY);
    NSPoint upperOrigin = NSMakePoint(ScrollX(upper), ScrollY(upper));
    NSPoint lowerOrigin = NSMakePoint(ScrollX(lower), ScrollY(lower));
    if (proposeY < -1000) {
        Check(fabs(upperOrigin.y + insets.top) <= 2,
              [NSString stringWithFormat:@"inset %@ / %@: the top rests on the inset (y %.1f, inset %.1f)",
               modeName, place, upperOrigin.y, insets.top]);
    } else if (proposeY < 0) {
        Check(upperOrigin.y < -20 && upperOrigin.y > -insets.top - 1,
              [NSString stringWithFormat:@"inset %@ / %@: between the inset and the text stays there (y %.1f)",
               modeName, place, upperOrigin.y]);
    } else if (proposeY < 1e8) {
        Check(fabs(upperOrigin.y - proposeY) < 2,
              [NSString stringWithFormat:@"inset %@ / %@: the proposed line is where it was put (y %.1f)",
               modeName, place, upperOrigin.y]);
    }
    if (proposeX > 100 && mode == NSLineBreakByClipping) {
        Check(upperOrigin.x > 100,
              [NSString stringWithFormat:@"inset %@ / %@: the view is scrolled across (x %.1f)", modeName, place, upperOrigin.x]);
    }
    if (expectPastFrame) {
        CGFloat naive = NSMaxY(upper.frame) - NSHeight(upper.enclosingScrollView.contentView.bounds);
        Check(upperOrigin.y > naive + 10,
              [NSString stringWithFormat:@"inset %@ / %@: the bottom passes the frame clamp (y %.1f, clamp %.1f)",
               modeName, place, upperOrigin.y, naive]);
    }
    NSUInteger edgeUpper = LeftEdgeCharacter(upper), edgeLower = LeftEdgeCharacter(lower);
    CGFloat edgeUX = 0, edgeUY = 0, edgeLX = 0, edgeLY = 0;
    CharacterPins(upper, edgeUpper, &edgeUX, &edgeUY);
    CharacterPins(lower, edgeLower, &edgeLX, &edgeLY);
    NSUInteger caret = upper.selectedRange.location;
    controller.settings.findString = @"aaa";
    controller.settings.replaceString = replace;
    controller.settings.options = 0;
    controller.settings.inSelection = NO;
    TSClipMoved = NO;
    TSWatchClip = YES;
    Check(TSTestPerform(controller, TSAdvancedFindActionReplaceAll, upper),
          [NSString stringWithFormat:@"inset %@ / %@: Replace All aaa -> %@", modeName, place, replace]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    TSWatchClip = NO;
    if (expectStill) {
        Check(fabs(ScrollX(upper) - upperOrigin.x) < 1 && fabs(ScrollY(upper) - upperOrigin.y) < 1
              && fabs(ScrollX(lower) - lowerOrigin.x) < 1 && fabs(ScrollY(lower) - lowerOrigin.y) < 1
              && upper.selectedRange.location == caret && !TSClipMoved,
              [NSString stringWithFormat:@"inset %@ / %@: aaa -> %@ does not move (upper %.1f,%.1f -> %.1f,%.1f, lower %.1f,%.1f -> %.1f,%.1f, jumped %d)",
               modeName, place, replace,
               upperOrigin.x, upperOrigin.y, ScrollX(upper), ScrollY(upper),
               lowerOrigin.x, lowerOrigin.y, ScrollX(lower), ScrollY(lower), TSClipMoved]);
        TSWatchClip = YES;
        [upper.undoManager undo];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
        Check([upper.string isEqualToString:text]
              && fabs(ScrollX(upper) - upperOrigin.x) < 1 && fabs(ScrollY(upper) - upperOrigin.y) < 1
              && fabs(ScrollX(lower) - lowerOrigin.x) < 1 && fabs(ScrollY(lower) - lowerOrigin.y) < 1
              && upper.selectedRange.location == caret && !TSClipMoved,
              [NSString stringWithFormat:@"inset %@ / %@: undo puts the inset place back (upper %.1f,%.1f, lower %.1f,%.1f, jumped %d)",
               modeName, place, ScrollX(upper), ScrollY(upper), ScrollX(lower), ScrollY(lower), TSClipMoved]);
        [upper.undoManager redo];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
        TSWatchClip = NO;
        Check(fabs(ScrollX(upper) - upperOrigin.x) < 1 && fabs(ScrollY(upper) - upperOrigin.y) < 1
              && fabs(ScrollX(lower) - lowerOrigin.x) < 1 && fabs(ScrollY(lower) - lowerOrigin.y) < 1
              && !TSClipMoved,
              [NSString stringWithFormat:@"inset %@ / %@: redo keeps the inset place (upper %.1f,%.1f, lower %.1f,%.1f, jumped %d)",
               modeName, place, ScrollX(upper), ScrollY(upper), ScrollX(lower), ScrollY(lower), TSClipMoved]);
        return;
    }
    NSUInteger movedUpper = IndexAfterLiteralReplace(text, edgeUpper, @"aaa", replace);
    NSUInteger movedLower = IndexAfterLiteralReplace(text, edgeLower, @"aaa", replace);
    CGFloat nowUX = 0, nowUY = 0, nowLX = 0, nowLY = 0;
    CharacterPins(upper, movedUpper, &nowUX, &nowUY);
    CharacterPins(lower, movedLower, &nowLX, &nowLY);
    Check(fabs(ScrollY(upper) - upperOrigin.y) < 2 && fabs(ScrollY(lower) - lowerOrigin.y) < 2
          && fabs(nowUX - edgeUX) < 2 && fabs(nowUY - edgeUY) < 2
          && fabs(nowLX - edgeLX) < 2 && fabs(nowLY - edgeLY) < 2,
          [NSString stringWithFormat:@"inset %@ / %@: aaa -> %@ keeps the clip and the left edge (upper %.1f -> %.1f, pin %.1f,%.1f -> %.1f,%.1f)",
           modeName, place, replace, upperOrigin.y, ScrollY(upper), edgeUX, edgeUY, nowUX, nowUY]);
}

/// Same-length Replace All must not move either axis. A shorter or longer replacement keeps the character that was
/// under the left edge. The caret starts four lines below the top, which is where the view was jumping.
static void TestSameLengthKeepsScreen(void)
{
    TSInstallClipWatch();
    NSFont *font = [NSFont userFixedPitchFontOfSize:13] ?: [NSFont systemFontOfSize:13];
    CGFloat a = [@"a" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    CGFloat d = [@"d" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    Check(fabs(a - d) < 0.01, @"the fixed-pitch source font draws aaa and ddd at the same width");
    NSString *text = WideLines(60, 80);
    NSLineBreakMode modes[] = {NSLineBreakByClipping, NSLineBreakByWordWrapping, NSLineBreakByCharWrapping};
    struct {
        NSString *name;
        NSUInteger line;
        CGFloat along;
        CGFloat viewportX;
        CGFloat viewportY;
    } places[] = {
        {@"top left", 0, 0, 0, 0},
        {@"vertical middle, left", NSNotFound, 0, 0, 0.5},
        {@"top, horizontal middle", 0, 0.5, 0.5, 0},
        {@"vertical and horizontal middle", NSNotFound, 0.5, 0.5, 0.5},
    };
    for (NSUInteger m = 0; m < sizeof modes / sizeof modes[0]; m++) {
        for (NSUInteger p = 0; p < sizeof places / sizeof places[0]; p++) {
            CheckPlacedReplace(text, modes[m], places[p].name, places[p].line, places[p].along,
                               places[p].viewportX, places[p].viewportY, @"ddd", YES);
            CheckPlacedReplace(text, modes[m], places[p].name, places[p].line, places[p].along,
                               places[p].viewportX, places[p].viewportY, @"aa", NO);
            CheckPlacedReplace(text, modes[m], places[p].name, places[p].line, places[p].along,
                               places[p].viewportX, places[p].viewportY, @"aaaa", NO);
        }
    }
    // Longer than the layout window used to place one line, viewport at the start, caret on line 5 column 217.
    CheckPlacedReplace(WideLines(30, 2100), NSLineBreakByClipping, @"long line, top left", 0, 0, 0, 0, @"ddd", YES);
    // The source sits under the toolbar. 68 and 18 are the insets measured on a document window; 32 is the toolbar hidden.
    NSEdgeInsets bar = NSEdgeInsetsMake(68, 0, 18, 0);
    NSEdgeInsets hiddenBar = NSEdgeInsetsMake(32, 0, 0, 0);
    TestInsetPlace(@"top", NSLineBreakByClipping, bar, 0, -1e9, @"ddd", YES, NO);
    TestInsetPlace(@"near top", NSLineBreakByClipping, bar, 0, -30, @"ddd", YES, NO);
    TestInsetPlace(@"middle", NSLineBreakByClipping, bar, 400, 400, @"ddd", YES, NO);
    TestInsetPlace(@"bottom", NSLineBreakByClipping, bar, 0, 1e9, @"ddd", YES, YES);
    TestInsetPlace(@"top, shorter", NSLineBreakByClipping, bar, 0, -1e9, @"aa", NO, NO);
    TestInsetPlace(@"bottom, longer", NSLineBreakByClipping, bar, 0, 1e9, @"aaaa", NO, YES);
    TestInsetPlace(@"top", NSLineBreakByWordWrapping, bar, 0, -1e9, @"ddd", YES, NO);
    TestInsetPlace(@"top", NSLineBreakByCharWrapping, bar, 0, -1e9, @"ddd", YES, NO);
    TestInsetPlace(@"toolbar hidden", NSLineBreakByClipping, hiddenBar, 0, -1e9, @"ddd", YES, NO);
    TestInsetPlace(@"video, top and across", NSLineBreakByClipping, bar, 500, -1e9, @"ddd", YES, NO);
}

#pragma mark Main

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *mode = argc > 1 ? @(argv[1]) : @"all";
        NSString *images = argc > 2 && argv[2][0] != '-' ? @(argv[2]) : nil; // not the -AppleLanguages that follows
        TestSharedController = MakeController([TSMemoryDefaults new], &TestSharedBeeps);
        method_setImplementation(class_getClassMethod(TSAdvancedFindController.class, @selector(sharedController)), (IMP)SharedControllerForTests);
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"behavior"]) {
            TestController();
            TestRouting();
            TestHighlights();
            TestPanelLevel();
            TestReplaceAllKeepsPlace();
        }
        if ([mode isEqualToString:@"all"] || [mode isEqualToString:@"panel"])
            TestPanel(images);
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
