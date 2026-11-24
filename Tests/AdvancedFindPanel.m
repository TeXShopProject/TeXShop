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
/// `clipping` is the source's no-wrap setting: the text view grows to the longest line and scrolls sideways. `clipX`
/// is then the horizontal scroll, after the carets have been scrolled into view.
static BOOL MakeScrolledSource(NSString *text, BOOL clipping, CGFloat clipX, NSTextView *_Nonnull *_Nonnull upperOut, NSTextView *_Nonnull *_Nonnull lowerOut, CGFloat *upperY, CGFloat *lowerY)
{
    static NSMutableArray<NSWindow *> *windows;
    if (!windows)
        windows = [NSMutableArray array];
    NSFont *font = [NSFont userFixedPitchFontOfSize:13] ?: [NSFont systemFontOfSize:13];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = clipping ? NSLineBreakByClipping : NSLineBreakByWordWrapping;
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
    TestWrappedMiddleKeepsPlace();
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
