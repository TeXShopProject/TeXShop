// Clicking and dragging on the line numbers selects whole lines. The real
// NoodleLineNumberView receives synthetic mouse events in a window that is never
// ordered on screen.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "NoodleLineNumberView.h"

BOOL atLeastMonterey = YES;
BOOL atLeastSonoma = YES;
NSString *LineNumberSizeKey = @"LineNumberSize";

static int failures;
static void Require(const char *name, BOOL condition)
{
    if (!condition) { printf("FAIL %s\n", name); failures++; }
}

// Shrinks its text once while the mouse is down, as output arriving in a log could.
@interface ShrinkingTextView : NSTextView
@property BOOL shrinkWhileSelecting;
@property NSUInteger selectionNotifications;
@end
@implementation ShrinkingTextView
- (void)setSelectedRange:(NSRange)range affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting
{
    [super setSelectedRange:range affinity:affinity stillSelecting:stillSelecting];
    if (stillSelecting && self.shrinkWhileSelecting) {
        self.shrinkWhileSelecting = NO;
        NSUInteger length = self.string.length;
        [self.textStorage replaceCharactersInRange:NSMakeRange(length - 10, 10) withString:@""];
    }
}
@end

// Counts redisplay requests: a window that is never shown does not keep needsDisplay.
@interface CountingLineNumberView : NoodleLineNumberView
@property NSUInteger redisplays;
@end
@implementation CountingLineNumberView
- (void)setNeedsDisplay:(BOOL)flag { if (flag) self.redisplays++; [super setNeedsDisplay:flag]; }
@end

static NSWindow *window;
static NSScrollView *scroll;
static ShrinkingTextView *textView;
static CountingLineNumberView *ruler;

static void Setup(NSString *text, BOOL wraps, CGFloat height)
{
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, height) styleMask:NSWindowStyleMaskTitled
                                           backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, height)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = !wraps;
    NSSize content = scroll.contentSize;
    textView = [[ShrinkingTextView alloc] initWithFrame:NSMakeRect(0, 0, content.width, content.height)];
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = !wraps;
    textView.maxSize = NSMakeSize(1e7, 1e7);
    textView.textContainer.widthTracksTextView = wraps;
    if (!wraps)
        textView.textContainer.containerSize = NSMakeSize(1e7, 1e7);
    textView.font = [NSFont userFixedPitchFontOfSize:12];
    textView.string = text;
    scroll.documentView = textView;
    window.contentView = scroll;
    ruler = [[CountingLineNumberView alloc] initWithScrollView:scroll];
    scroll.verticalRulerView = ruler;
    scroll.hasHorizontalRuler = NO;
    scroll.hasVerticalRuler = YES;
    scroll.rulersVisible = YES;
    [window makeFirstResponder:nil];
    [scroll tile];
    // The ruler widens itself for the line count asynchronously; let it settle.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    [scroll tile];
    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
}

// A point in the ruler, in window coordinates, at the height of the line fragment
// holding the given character (fraction 0..1 down that fragment).
static NSPoint RulerPointForCharacter(NSUInteger index, CGFloat fraction)
{
    NSLayoutManager *lm = textView.layoutManager;
    NSRect fragment;
    if (index >= textView.string.length && !NSIsEmptyRect(lm.extraLineFragmentRect))
        fragment = lm.extraLineFragmentRect;
    else
        fragment = [lm lineFragmentRectForGlyphAtIndex:[lm glyphIndexForCharacterAtIndex:index] effectiveRange:NULL];
    NSPoint inText = NSMakePoint(0, NSMinY(fragment) + NSHeight(fragment) * fraction + textView.textContainerOrigin.y);
    NSPoint inWindow = [textView convertPoint:inText toView:nil];
    inWindow.x = [ruler convertPoint:NSMakePoint(NSMidX(ruler.bounds), 0) toView:nil].x;
    return inWindow;
}

static NSEvent *MouseEvent(NSEventType type, NSPoint point, NSEventModifierFlags flags)
{
    return [NSEvent mouseEventWithType:type location:point modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

// Mouse down at the first point, drags through the rest, then mouse up at the last.
static void Gesture(NSArray<NSValue *> *points, NSEventModifierFlags flags)
{
    for (NSUInteger i = 1; i < points.count; i++)
        [NSApp postEvent:MouseEvent(NSEventTypeLeftMouseDragged, points[i].pointValue, flags) atStart:NO];
    [NSApp postEvent:MouseEvent(NSEventTypeLeftMouseUp, points.lastObject.pointValue, flags) atStart:NO];
    [ruler mouseDown:MouseEvent(NSEventTypeLeftMouseDown, points.firstObject.pointValue, flags)];
    // Leave nothing queued for the next gesture.
    NSEvent *left;
    while ((left = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                         inMode:NSDefaultRunLoopMode dequeue:YES]) != nil) {}
}

static NSValue *P(NSUInteger index) { return [NSValue valueWithPoint:RulerPointForCharacter(index, 0.5)]; }

// The ink of the ruler's numbers in the band of the line fragment holding a character,
// drawn offscreen in the light appearance.
static NSUInteger InkForLine(NSUInteger index);
static CGFloat inkLeft, inkRight;   // the inked columns of the last InkForLine band, in points

static NSUInteger InkForLine(NSUInteger index)
{
    ruler.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSRect bounds = ruler.bounds;
    NSBitmapImageRep *rep = [ruler bitmapImageRepForCachingDisplayInRect:bounds];
    [ruler cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSLayoutManager *lm = textView.layoutManager;
    NSRect fragment = [lm lineFragmentRectForGlyphAtIndex:[lm glyphIndexForCharacterAtIndex:index] effectiveRange:NULL];
    NSRect inText = NSOffsetRect(fragment, 0, textView.textContainerOrigin.y);
    NSRect inRuler = [ruler convertRect:[textView convertRect:inText toView:nil] fromView:nil];
    CGFloat scale = rep.pixelsHigh / NSHeight(bounds);
    CGFloat top = ruler.isFlipped ? NSMinY(inRuler) : NSHeight(bounds) - NSMaxY(inRuler);
    NSUInteger ink = 0;
    NSInteger left = NSIntegerMax, right = -1;
    for (NSInteger y = (NSInteger)floor(top * scale); y < (NSInteger)ceil((top + NSHeight(inRuler)) * scale); y++)
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            if (y < 0 || y >= rep.pixelsHigh) continue;
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.genericGrayColorSpace];
            NSUInteger dot = (NSUInteger)lround((1.0 - c.whiteComponent) * c.alphaComponent * 255.0);
            // The divider at the right edge is not a digit.
            if (dot > 60 && x < rep.pixelsWide - 2 * scale) { left = MIN(left, x); right = MAX(right, x); }
            ink += dot;
        }
    inkLeft = left / scale;
    inkRight = (right + 1) / scale;
    return ink;
}
static NSRange LineOf(NSUInteger index) { return [textView.string lineRangeForRange:NSMakeRange(index, 0)]; }
static NSUInteger StartOf(NSString *needle) { NSRange r = [textView.string rangeOfString:needle]; NSCAssert(r.location != NSNotFound, @"needle"); return r.location; }

int main(void)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];

        NSString *longLine = [@"" stringByPaddingToLength:400 withString:@"wrap me " startingAtIndex:0];
        NSString *text = [NSString stringWithFormat:@"first\nsecond\n%@\n\nfifth\r\nsixth\nlast\n", longLine];
        Setup(text, YES, 400);
        __block NSUInteger notifications = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextViewDidChangeSelectionNotification object:textView
                                                                         queue:nil usingBlock:^(NSNotification *n) { notifications++; }];

        // A click selects the whole line with its line ending and focuses the text.
        textView.selectedRange = NSMakeRange(0, 0);
        notifications = 0;
        Gesture(@[P(StartOf(@"second"))], 0);
        Require("click selects the line", NSEqualRanges(textView.selectedRange, NSMakeRange(StartOf(@"second"), 7)));
        Require("click focuses the text", window.firstResponder == textView);
        Require("one selection change per click", notifications == 1);

        // A wrapped line is one line, wherever its fragments are clicked.
        NSUInteger wrapped = StartOf(@"wrap me");
        NSRange wrappedLine = LineOf(wrapped);
        NSUInteger lastFragmentChar = NSMaxRange(wrappedLine) - 2;
        Require("long line wraps", RulerPointForCharacter(lastFragmentChar, 0.5).y != RulerPointForCharacter(wrapped, 0.5).y);
        Gesture(@[P(lastFragmentChar)], 0);
        Require("click on a wrapped fragment selects the whole line", NSEqualRanges(textView.selectedRange, wrappedLine));

        // An empty line, and a CRLF line ending in full.
        Gesture(@[P(NSMaxRange(wrappedLine))], 0);
        Require("empty line selects its line ending", NSEqualRanges(textView.selectedRange, NSMakeRange(NSMaxRange(wrappedLine), 1)));
        Gesture(@[P(StartOf(@"fifth"))], 0);
        Require("CRLF line includes both characters", NSEqualRanges(textView.selectedRange, NSMakeRange(StartOf(@"fifth"), 7)));

        // Dragging selects every line in between, in either direction, with one notification.
        notifications = 0;
        Gesture(@[P(StartOf(@"second")), P(StartOf(@"fifth")), P(StartOf(@"sixth"))], 0);
        NSRange secondToSixth = NSUnionRange(LineOf(StartOf(@"second")), LineOf(StartOf(@"sixth")));
        Require("drag down selects the lines", NSEqualRanges(textView.selectedRange, secondToSixth));
        Require("one selection change per drag", notifications == 1);
        Gesture(@[P(StartOf(@"sixth")), P(StartOf(@"first")), P(StartOf(@"second"))], 0);
        Require("drag up selects the lines", NSEqualRanges(textView.selectedRange, secondToSixth));

        // Below the last line ending is the empty last line: the end of the text.
        NSValue *below = [NSValue valueWithPoint:RulerPointForCharacter(text.length, 0.5)];
        Gesture(@[below], 0);
        Require("click below the text puts the caret at the end", NSEqualRanges(textView.selectedRange, NSMakeRange(text.length, 0)));
        Gesture(@[P(StartOf(@"sixth")), below], 0);
        Require("drag to the end selects through the last line", NSEqualRanges(textView.selectedRange, NSMakeRange(StartOf(@"sixth"), text.length - StartOf(@"sixth"))));

        // Shift extends the current selection to whole lines, on either side.
        textView.selectedRange = NSMakeRange(StartOf(@"second") + 2, 0);
        Gesture(@[P(StartOf(@"fifth"))], NSEventModifierFlagShift);
        Require("shift-click extends down from the caret", NSEqualRanges(textView.selectedRange, NSMakeRange(StartOf(@"second") + 2, NSMaxRange(LineOf(StartOf(@"fifth"))) - StartOf(@"second") - 2)));
        textView.selectedRange = NSMakeRange(StartOf(@"sixth") + 1, 3);
        Gesture(@[P(StartOf(@"second"))], NSEventModifierFlagShift);
        Require("shift-click extends up from the selection", NSEqualRanges(textView.selectedRange, NSMakeRange(StartOf(@"second"), StartOf(@"sixth") + 4 - StartOf(@"second"))));

        // Command, Option and Control clicks are left to the ruler as before.
        textView.selectedRange = NSMakeRange(1, 2);
        NSEventModifierFlags others[] = { NSEventModifierFlagCommand, NSEventModifierFlagOption, NSEventModifierFlagControl };
        for (int i = 0; i < 3; i++) {
            [ruler mouseDown:MouseEvent(NSEventTypeLeftMouseDown, P(StartOf(@"fifth")).pointValue, others[i])];
            Require("modified click leaves the selection", NSEqualRanges(textView.selectedRange, NSMakeRange(1, 2)));
        }

        // A text view that cannot be selected is left alone.
        textView.selectable = NO;
        [ruler mouseDown:MouseEvent(NSEventTypeLeftMouseDown, P(StartOf(@"fifth")).pointValue, 0)];
        Require("unselectable text is left alone", NSEqualRanges(textView.selectedRange, NSMakeRange(1, 2)));
        textView.selectable = YES;
        textView.editable = YES;  // turning selection off also turned editing off

        // The numbers of the lines selected on the ruler are bold until the selection changes otherwise.
        NSUInteger second = StartOf(@"second"), fifth = StartOf(@"fifth"), sixth = StartOf(@"sixth"), first = StartOf(@"first");
        textView.selectedRange = NSMakeRange(0, 0);
        NSUInteger plainSecond = InkForLine(second), plainFifth = InkForLine(fifth), plainSixth = InkForLine(sixth), plainFirst = InkForLine(first);
        Require("numbers are drawn", plainSecond > 0 && plainFifth > 0);
        Gesture(@[P(second), P(fifth)], 0);
        Require("selected numbers are bold", InkForLine(second) > plainSecond + plainSecond / 10 && InkForLine(fifth) > plainFifth + plainFifth / 10);
        Require("other numbers stay regular", InkForLine(sixth) == plainSixth && InkForLine(first) == plainFirst);
        ruler.redisplays = 0;
        textView.selectedRange = NSMakeRange(sixth, 0);
        Require("ruler redraws when the selection changes", ruler.redisplays > 0);
        Require("bold ends when the selection changes", InkForLine(second) == plainSecond && InkForLine(fifth) == plainFifth);
        Gesture(@[P(sixth)], 0);
        Require("a single line is bold", InkForLine(sixth) > plainSixth && InkForLine(fifth) == plainFifth);
        // Typing replaces the selected line; the caret after it is not a line selection.
        [textView insertText:@"sixth\n" replacementRange:textView.selectedRange];
        Require("typed text replaced the line", [textView.string isEqualToString:text] && textView.selectedRange.length == 0);
        Require("typing ends bold", InkForLine(sixth) == plainSixth);
        NSUInteger typedLast = InkForLine(StartOf(@"last"));
        textView.selectedRange = NSMakeRange(0, 0);
        Require("the caret line after typing is regular", InkForLine(StartOf(@"last")) == typedLast);

        // The numbers use the system's monospaced font: every digit, regular or bold, is as
        // wide as any other, so the digits of all numbers line up in both sizes.
        for (NSInteger size = 0; size <= 1; size++) {
            [NSUserDefaults.standardUserDefaults setInteger:size forKey:LineNumberSizeKey];
            NSFont *regular = ruler.font;
            NSFont *bold = [(NSDictionary *)[ruler performSelector:@selector(selectedLineTextAttributes)] objectForKey:NSFontAttributeName];
            CGFloat expected = [NSFont systemFontSizeForControlSize:size ? NSControlSizeRegular : NSControlSizeMini];
            Require("line numbers follow the size setting", regular.pointSize == expected && bold.pointSize == expected);
            Require("line numbers are monospaced", regular.isFixedPitch && bold.isFixedPitch);
            Require("bold line numbers are bold", ([[NSFontManager sharedFontManager] traitsOfFont:bold] & NSBoldFontMask) != 0);
            CGFloat narrow = [@"1111111" sizeWithAttributes:@{NSFontAttributeName: regular}].width;
            Require("all digits are equally wide", narrow == [@"8888888" sizeWithAttributes:@{NSFontAttributeName: regular}].width
                    && narrow == [@"1410800" sizeWithAttributes:@{NSFontAttributeName: regular}].width);
            Require("bold digits are as wide as regular ones", narrow == [@"1111111" sizeWithAttributes:@{NSFontAttributeName: bold}].width
                    && narrow == [@"8888888" sizeWithAttributes:@{NSFontAttributeName: bold}].width);
        }
        [NSUserDefaults.standardUserDefaults removeObjectForKey:LineNumberSizeKey];

        // Bold numbers must keep their last digit and their first, also with a proportional
        // font given through -setFont:, whose bold digits are wider. Bold numbers must not lose their last digit or their first,
        // with either size of line numbers, and at the four-to-five digit boundary.
        NSMutableString *tenThousand = [NSMutableString string];
        for (int i = 1; i <= 10010; i++) [tenThousand appendFormat:@"%d\n", i];
        for (NSInteger size = 0; size <= 2; size++) {
            [NSUserDefaults.standardUserDefaults setInteger:(size == 2 ? 0 : size) forKey:LineNumberSizeKey];
            Setup(tenThousand, YES, 400);
            BOOL proportional = (size == 2);
            if (proportional) {
                [ruler setFont:[NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeMini]]];
                [ruler setRuleThickness:[ruler requiredThickness]];
                [scroll tile];
            }
            NSUInteger from = StartOf(@"\n9998\n") + 1, to = StartOf(@"\n10008\n") + 1;
            [textView scrollRangeToVisible:NSMakeRange(from, 0)];
            [scroll tile];
            NSUInteger lines[] = { from, StartOf(@"\n9999\n") + 1, StartOf(@"\n10000\n") + 1, StartOf(@"\n10004\n") + 1, to };
            CGFloat plainLeft[5], plainRight[5];
            textView.selectedRange = NSMakeRange(0, 0);
            for (int i = 0; i < 5; i++) { InkForLine(lines[i]); plainLeft[i] = inkLeft; plainRight[i] = inkRight; }
            Gesture(@[P(from), P(to)], 0);
            for (int i = 0; i < 5; i++) {
                InkForLine(lines[i]);
                char name[160];
                snprintf(name, sizeof name, "size %ld line %d: bold number keeps its last digit (right %.1f vs %.1f)", (long)size, i, inkRight, plainRight[i]);
                Require(name, fabs(inkRight - plainRight[i]) <= 1.5);
                snprintf(name, sizeof name, "size %ld line %d: bold number starts where the regular one does, inside the ruler (left %.1f vs %.1f)", (long)size, i, inkLeft, plainLeft[i]);
                Require(name, (proportional ? inkLeft <= plainLeft[i] : fabs(inkLeft - plainLeft[i]) <= 1.5) && inkLeft >= 1.0);
            }
        }
        [NSUserDefaults.standardUserDefaults removeObjectForKey:LineNumberSizeKey];

        // Text without a final line ending: below the text is the last line.
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        Setup(@"one\ntwo\nthree", YES, 400);
        Gesture(@[[NSValue valueWithPoint:NSMakePoint(RulerPointForCharacter(0, 0.5).x, 5)]], 0);
        Require("below an unterminated last line selects it", NSEqualRanges(textView.selectedRange, NSMakeRange(8, 5)));
        Setup(@"", YES, 400);
        Gesture(@[[NSValue valueWithPoint:RulerPointForCharacter(0, 0.5)]], 0);
        Require("empty text", NSEqualRanges(textView.selectedRange, NSMakeRange(0, 0)));

        // Dragging below the visible text scrolls down, only vertically, and keeps selecting.
        NSMutableString *many = [NSMutableString string];
        for (int i = 1; i <= 200; i++) [many appendFormat:@"line %03d %@\n", i, [@"" stringByPaddingToLength:300 withString:@"x" startingAtIndex:0]];
        Setup(many, NO, 200);
        [textView scrollPoint:NSMakePoint(120, 0)];
        // The text runs under the ruler: the left of the visible rect is covered by it.
        Require("text runs under the ruler", NSMinX(scroll.contentView.frame) < NSMaxX(ruler.frame));
        NSRect before = textView.visibleRect;
        NSPoint start = RulerPointForCharacter(StartOf(@"line 002"), 0.5);
        // 60 points below the bottom of the visible text.
        NSPoint outside = [scroll.contentView convertPoint:NSMakePoint(0, NSMaxY(scroll.contentView.bounds) + 60) toView:nil];
        outside.x = start.x;
        Gesture(@[[NSValue valueWithPoint:start], [NSValue valueWithPoint:outside]], 0);
        NSRect after = textView.visibleRect;
        Require("drag below scrolls down", NSMinY(after) > NSMinY(before) + 30);
        Require("drag does not scroll sideways", NSMinX(after) == NSMinX(before));
        NSUInteger end = NSMaxRange(textView.selectedRange);
        Require("selection starts at the anchor line", textView.selectedRange.location == StartOf(@"line 002"));
        Require("selection reaches past the first view", end > [textView.layoutManager characterIndexForGlyphAtIndex:
            [textView.layoutManager glyphIndexForPoint:NSMakePoint(0, NSMaxY(before)) inTextContainer:textView.textContainer]]);
        Require("selection ends at a line end", end == NSMaxRange(LineOf(end - 1)));

        // The text changing while the mouse is down never leaves a selection past its end.
        Setup(@"aaaaaaaaa\nbbbbbbbbb\nccccccccc\nddddddddd\n", YES, 400);
        NSValue *belowEnd = [NSValue valueWithPoint:RulerPointForCharacter(40, 0.5)];
        textView.shrinkWhileSelecting = YES;
        Gesture(@[[NSValue valueWithPoint:RulerPointForCharacter(10, 0.5)], belowEnd], 0);
        Require("text shrank", textView.string.length == 30);
        Require("selection stays inside the text", NSMaxRange(textView.selectedRange) <= textView.string.length
                && textView.selectedRange.location == 10);

        if (failures) return 1;
        printf("PASS: line number clicks and drags select whole lines\n");
    }
    return 0;
}
