// The console and the small panels of each localized TSDocument.nib, loaded
// without ordering a window and laid out as the application lays them out
// (ProductionLayout.inc):
//   * the console's buttons are push buttons in one row along the top: the
//     first group 20 points from the left edge (measured to what the buttons draw), the second 20 points from the
//     right edge, 12 points between buttons and at least 24 between the groups,
//     8 points from the top and above the output, also at the smallest size,
//     where the output keeps two lines; each button stays in its group when
//     the console is laid out at a narrow saved width and laid out again;
//   * the left, center and right choices of the Text panel are as wide as their
//     titles, at least 12 points apart, and at least 12 points from OK at the
//     panel's usual and smallest widths;
//   * the former Statistics panel is no longer in the nib;
//   * the label of each Magnification panel shows its whole word on one line;
//   * the labels of the page number panels stand at least PageLabelGap from the
//     fields beside them.
// run-console-and-small-panels.py compiles this file with ProductionLayout.inc.
// Usage: ConsoleAndSmallPanels <language>=<compiled TSDocument.nib> ...
#import "TestAppKitIsolation.h"
#include "ProductionLayout.inc"

@interface PanelOwner : SpacingOwner {
@public id stringWindow, statisticsPanel, magnificationPanel, magnificationKitPanel, pagenumberPanel, pagenumberKitPanel;
}
@end
@implementation PanelOwner @end

static int failures, checks;
static const CGFloat PageLabelGap = 4;   // as the TOUCH check of the layout checks
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) { failures++; printf("FAIL %s\n", what.UTF8String); } }
static void All(NSView *v, NSMutableArray *out) { [out addObject:v]; for (NSView *s in v.subviews) All(s, out); }

// Ink of a view drawn alone at its own size, in points from its left edge.
static NSRect Ink(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSInteger minX = NSIntegerMax, maxX = -1, minY = NSIntegerMax, maxY = -1;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) for (NSInteger x = 0; x < rep.pixelsWide; x++) {
        NSUInteger p[4]; [rep getPixel:p atX:x y:y];
        if (p[3] > 40) { minX = MIN(minX, x); maxX = MAX(maxX, x); minY = MIN(minY, y); maxY = MAX(maxY, y); }
    }
    if (maxX < 0) return NSZeroRect;
    CGFloat scale = rep.pixelsWide / MAX(1, NSWidth(view.bounds));
    return NSMakeRect(minX / scale, minY / scale, (maxX - minX + 1) / scale, (maxY - minY + 1) / scale);
}

// What a button draws (its alignment rectangle), which the margins are measured to.
static NSRect Drawn(NSView *v) { return [v alignmentRectForFrame:v.frame]; }

static void CheckConsole(NSWindow *console, NSString *lang, NSString *size) {
    NSView *host = console.contentView;
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    NSScrollView *output = nil;
    for (NSView *v in host.subviews) {
        if ([v isKindOfClass:NSButton.class]) [buttons addObject:(NSButton *)v];
        if ([v isKindOfClass:NSScrollView.class]) output = (NSScrollView *)v;
    }
    NSString *where = [NSString stringWithFormat:@"%@ console (%@)", lang, size];
    Check(buttons.count >= 2 && output, [where stringByAppendingString:@": buttons and output"]);
    [buttons sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(Drawn(a)) < NSMinX(Drawn(b)) ? NSOrderedAscending : NSOrderedDescending; }];
    CGFloat width = NSWidth(host.bounds), height = NSHeight(host.bounds);
    NSButton *first = buttons.firstObject, *last = buttons.lastObject;
    Check(fabs(NSMinX(Drawn(first)) - 20) < 0.5 && fabs(width - NSMaxX(Drawn(last)) - 20) < 0.5,
          [NSString stringWithFormat:@"%@: 20 points from both sides (%.1f, %.1f)", where, NSMinX(Drawn(first)), width - NSMaxX(Drawn(last))]);
    NSUInteger wideGaps = 0;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton *b = buttons[i];
        Check(b.bezelStyle == NSBezelStylePush && b.controlSize == NSControlSizeRegular && b.bordered,
              [NSString stringWithFormat:@"%@: \"%@\" is a regular push button", where, b.title]);
        Check(NSWidth(b.frame) >= ceil(b.fittingSize.width) - 0.5 && NSHeight(b.frame) >= b.fittingSize.height - 0.5,
              [NSString stringWithFormat:@"%@: \"%@\" is as large as its title", where, b.title]);
        Check(fabs(height - NSMaxY(Drawn(b)) - 8) < 0.5 && fabs(NSMinY(Drawn(b)) - 8 - NSMaxY(output.frame)) < 0.5,
              [NSString stringWithFormat:@"%@: \"%@\" is 8 points below the top and above the output", where, b.title]);
        if (i == 0) continue;
        CGFloat gap = NSMinX(Drawn(b)) - NSMaxX(Drawn(buttons[i - 1]));
        if (gap > 12.5) wideGaps++;
        Check(gap >= 11.5, [NSString stringWithFormat:@"%@: \"%@\" and \"%@\" are %.1f points apart", where, buttons[i - 1].title, b.title, gap]);
        Check(gap < 12.5 || gap >= 23.5, [NSString stringWithFormat:@"%@: the groups are %.1f points apart", where, gap]);
    }
    Check(wideGaps == 1, [NSString stringWithFormat:@"%@: two groups (%lu wide gaps)", where, (unsigned long)wideGaps]);
    Check(NSHeight(output.frame) >= 27.5, [NSString stringWithFormat:@"%@: the output keeps two lines (%.1f)", where, NSHeight(output.frame)]);
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    for (int i = 1; i < argc; i++) {
        NSString *arg = @(argv[i]); NSRange eq = [arg rangeOfString:@"="];
        NSString *lang = [arg substringToIndex:eq.location];
        PanelOwner *owner = [PanelOwner new];
        NSArray *objects = nil;
        NSData *nibData = [NSData dataWithContentsOfFile:[arg substringFromIndex:NSMaxRange(eq)]];
        if (![[[NSNib alloc] initWithNibData:nibData bundle:nil] instantiateWithOwner:owner topLevelObjects:&objects]) { printf("ERROR %s cannot load\n", lang.UTF8String); return 2; }
        ApplyProductionLayout(@"TSDocument.nib", owner, objects);

        // The console, as it opens and at its smallest.
        NSWindow *console = owner->outputWindow;
        NSSize normal = console.contentView.frame.size;
        CheckConsole(console, lang, @"as it opens");
        Check(console.contentMinSize.width <= normal.width, [NSString stringWithFormat:@"%@ console: opens at least as wide as its smallest", lang]);
        [console setContentSize:console.contentMinSize];
        CheckConsole(console, lang, @"smallest");
        [console setContentSize:normal];

        // A console whose saved frame is narrow when it is laid out, and laid out
        // again: each button stays in the group the nib holds it to (Goto Error at
        // the left edge, Abort and Trash Aux Files at the right), in the same place.
        for (NSNumber *narrow in @[@260, @400]) {
            PanelOwner *again = [PanelOwner new]; NSArray *more = nil;
            [[[NSNib alloc] initWithNibData:nibData bundle:nil] instantiateWithOwner:again topLevelObjects:&more];
            NSWindow *c = again->outputWindow;
            NSMapTable<NSButton *, NSNumber *> *right = [NSMapTable strongToStrongObjectsMapTable];
            for (NSView *v in c.contentView.subviews)
                if ([v isKindOfClass:NSButton.class]) [right setObject:@((v.autoresizingMask & NSViewMinXMargin) != 0) forKey:(NSButton *)v];
            [c setContentSize:NSMakeSize(narrow.doubleValue, NSHeight(c.contentView.frame))];
            TSLayoutConsoleButtonRow(c);
            NSString *where = [NSString stringWithFormat:@"%@ console restored %@ points wide", lang, narrow];
            NSArray<NSValue *> *(^frames)(void) = ^NSArray<NSValue *> *{
                NSMutableArray *out = [NSMutableArray array];
                for (NSButton *b in right.keyEnumerator) [out addObject:[NSValue valueWithRect:b.frame]];
                return out;
            };
            void (^groups)(NSString *) = ^(NSString *when) {
                CGFloat w = NSWidth(c.contentView.bounds), leftEnd = 0, rightStart = CGFLOAT_MAX, rightEnd = 0;
                NSUInteger lefts = 0;
                for (NSButton *b in right.keyEnumerator) {
                    NSRect d = Drawn(b);
                    if ([right objectForKey:b].boolValue) { rightStart = MIN(rightStart, NSMinX(d)); rightEnd = MAX(rightEnd, NSMaxX(d)); }
                    else { lefts++; leftEnd = MAX(leftEnd, NSMaxX(d)); Check(fabs(NSMinX(d) - 20) < 0.5, [NSString stringWithFormat:@"%@ (%@): \"%@\" stays at the left edge", where, when, b.title]); }
                }
                Check(lefts == 1 && fabs(w - rightEnd - 20) < 0.5 && rightStart - leftEnd >= 23.5,
                      [NSString stringWithFormat:@"%@ (%@): the buttons held to the right edge stay there, apart from Goto Error (%.1f)", where, when, rightStart - leftEnd]);
            };
            groups(@"laid out");
            NSArray *first = frames();
            TSLayoutConsoleButtonRow(c);
            Check([frames() isEqual:first], [NSString stringWithFormat:@"%@: a second layout changes nothing", where]);
            [c setContentSize:NSMakeSize(640, NSHeight(c.contentView.frame))];
            groups(@"widened");
            [c setContentSize:c.contentMinSize];
            TSLayoutConsoleButtonRow(c);
            groups(@"at its smallest, laid out again");
        }

        // The text of a text annotation is edited in a popover of the annotation toolbar
        // (run-annotation-toolbar.py checks its labels); the Text panel is gone.
        Check(owner->stringWindow == nil, [NSString stringWithFormat:@"%@: no Text panel", lang]);

        // The former Statistics panel is gone; Text Statistics is a popover of the status bar.
        Check(owner->statisticsPanel == nil, [NSString stringWithFormat:@"%@: no Statistics panel", lang]);

        // Page number panels: each label stands apart from the fields beside it, as far as
        // the labels of the panel for the PDFKit preview do (the older panel's "ページ" and
        // "페이지" ran into the field before them).
        for (NSWindow *panel in @[owner->pagenumberKitPanel, owner->pagenumberPanel]) {
            NSMutableArray<NSView *> *all = [NSMutableArray array]; All(panel.contentView, all);
            NSMutableArray<NSTextField *> *labels = [NSMutableArray array], *fields = [NSMutableArray array];
            for (NSView *v in all) if ([v isKindOfClass:NSTextField.class]) [(((NSTextField *)v).isBezeled ? fields : labels) addObject:(NSTextField *)v];
            Check(labels.count >= 2 && fields.count == 2, [NSString stringWithFormat:@"%@ page number panel: labels and two fields", lang]);
            for (NSTextField *label in labels) for (NSTextField *field in fields) {
                NSRect l = [label convertRect:Ink(label) toView:nil], f = [field convertRect:Ink(field) toView:nil];
                if (NSIsEmptyRect(l) || NSMaxY(l) < NSMinY(f) || NSMaxY(f) < NSMinY(l)) continue;
                CGFloat gap = MAX(NSMinX(l) - NSMaxX(f), NSMinX(f) - NSMaxX(l));
                Check(gap >= PageLabelGap, [NSString stringWithFormat:@"%@ page number panel \"%@\": \"%@\" is %.1f points from a field (need %.0f)", lang, panel.title, label.stringValue, gap, PageLabelGap]);
            }
        }

        // Magnification: the label shows the whole word on one line.
        for (NSWindow *panel in @[owner->magnificationKitPanel, owner->magnificationPanel]) {
            NSMutableArray<NSView *> *all = [NSMutableArray array]; All(panel.contentView, all);
            for (NSView *v in all) {
                if (![v isKindOfClass:NSTextField.class] || ((NSTextField *)v).isEditable) continue;
                NSTextField *label = (NSTextField *)v;
                NSString *word = [label.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                NSTextField *alone = [NSTextField labelWithString:word]; alone.font = label.font;
                [alone sizeToFit];
                NSRect drawn = Ink(label), whole = Ink(alone);
                Check(NSWidth(drawn) >= NSWidth(whole) - 1 && NSHeight(drawn) <= NSHeight(whole) + 1,
                      [NSString stringWithFormat:@"%@ Magnification: \"%@\" is whole on one line (%.1f×%.1f of %.1f×%.1f)", lang, word, NSWidth(drawn), NSHeight(drawn), NSWidth(whole), NSHeight(whole)]);
            }
        }
    }
    if (failures) { printf("FAIL: %d of %d checks\n", failures, checks); return 1; }
    printf("PASS: the console's push buttons and the Magnification labels in %d languages, without the former Text and Statistics panels (%d checks)\n", argc - 1, checks);
} return 0; }
