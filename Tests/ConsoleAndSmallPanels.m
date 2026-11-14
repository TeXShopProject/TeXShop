// The console and the small panels of each localized TSDocument.nib, loaded
// without ordering a window and laid out as the application lays them out
// (ProductionLayout.inc):
//   * the console's buttons are push buttons in one row along the top: the
//     first group 20 points from the left edge, the second 20 points from the
//     right edge, 12 points between buttons and at least 24 between the groups,
//     8 points from the top and above the output, also at the smallest size,
//     where the output keeps two lines;
//   * the left, center and right choices of the Text panel are as wide as their
//     titles, at least 12 points apart, and at least 12 points from OK at the
//     panel's usual and smallest widths;
//   * Statistics shows three right-aligned labels and three fields with one
//     left edge and one width (no NSForm, whose square cells stay white in Dark
//     Mode), connected to the outlets the document fills;
//   * the label of each Magnification panel shows its whole word on one line.
// run-console-and-small-panels.py compiles this file with ProductionLayout.inc.
// Usage: ConsoleAndSmallPanels <language>=<compiled TSDocument.nib> ...
#import "TestAppKitIsolation.h"
#include "ProductionLayout.inc"

@interface PanelOwner : SpacingOwner {
@public id stringWindow, statisticsPanel, statisticsWords, statisticsLines, statisticsCharacters, magnificationPanel, magnificationKitPanel;
}
@end
@implementation PanelOwner @end

static int failures, checks;
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
    [buttons sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    CGFloat width = NSWidth(host.bounds), height = NSHeight(host.bounds);
    NSButton *first = buttons.firstObject, *last = buttons.lastObject;
    Check(fabs(NSMinX(first.frame) - 20) < 0.5 && fabs(width - NSMaxX(last.frame) - 20) < 0.5,
          [NSString stringWithFormat:@"%@: 20 points from both sides (%.1f, %.1f)", where, NSMinX(first.frame), width - NSMaxX(last.frame)]);
    NSUInteger wideGaps = 0;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton *b = buttons[i];
        Check(b.bezelStyle == NSBezelStylePush && b.controlSize == NSControlSizeRegular && b.bordered,
              [NSString stringWithFormat:@"%@: \"%@\" is a regular push button", where, b.title]);
        Check(NSWidth(b.frame) >= ceil(b.fittingSize.width) - 0.5 && NSHeight(b.frame) >= b.fittingSize.height - 0.5,
              [NSString stringWithFormat:@"%@: \"%@\" is as large as its title", where, b.title]);
        Check(fabs(height - NSMaxY(b.frame) - 8) < 0.5 && fabs(NSMinY(b.frame) - 8 - NSMaxY(output.frame)) < 0.5,
              [NSString stringWithFormat:@"%@: \"%@\" is 8 points below the top and above the output", where, b.title]);
        if (i == 0) continue;
        CGFloat gap = NSMinX(b.frame) - NSMaxX(buttons[i - 1].frame);
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
        if (![[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:[arg substringFromIndex:NSMaxRange(eq)]] bundle:nil] instantiateWithOwner:owner topLevelObjects:&objects]) { printf("ERROR %s cannot load\n", lang.UTF8String); return 2; }
        ApplyProductionLayout(@"TSDocument.nib", owner, objects);

        // The console, as it opens and at its smallest.
        NSWindow *console = owner->outputWindow;
        NSSize normal = console.contentView.frame.size;
        CheckConsole(console, lang, @"as it opens");
        Check(console.contentMinSize.width <= normal.width, [NSString stringWithFormat:@"%@ console: opens at least as wide as its smallest", lang]);
        [console setContentSize:console.contentMinSize];
        CheckConsole(console, lang, @"smallest");
        [console setContentSize:normal];

        // The Text panel's choices and OK, at its usual and smallest widths.
        NSWindow *text = owner->stringWindow;
        for (NSString *size in @[@"usual", @"smallest"]) {
            if ([size isEqual:@"smallest"]) [text setContentSize:text.contentMinSize];
            NSMutableArray<NSButton *> *radios = [NSMutableArray array]; NSButton *ok = nil;
            for (NSView *v in text.contentView.subviews) if ([v isKindOfClass:NSButton.class]) {
                if ([((NSButton *)v).keyEquivalent isEqual:@"\r"]) ok = (NSButton *)v; else [radios addObject:(NSButton *)v];
            }
            [radios sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
            Check(radios.count == 3 && ok, [NSString stringWithFormat:@"%@ Text panel: three choices and OK", lang]);
            for (NSUInteger r = 0; r < radios.count; r++) {
                NSButton *b = radios[r];
                CGFloat drawn = NSMinX(b.frame) + NSMaxX(Ink(b));
                Check(NSWidth(b.frame) >= ceil(b.fittingSize.width) - 0.5, [NSString stringWithFormat:@"%@ Text panel: \"%@\" is as wide as its title", lang, b.title]);
                NSView *next = r + 1 < radios.count ? radios[r + 1] : ok;
                // Offscreen, a choice that is not selected draws a faint circle; its circle starts at its frame.
                CGFloat gap = NSMinX(next.frame) + (next == ok ? NSMinX(Ink(ok)) : 0) - drawn;
                Check(gap >= 12, [NSString stringWithFormat:@"%@ Text panel (%@): \"%@\" is %.1f points from the next control", lang, size, b.title, gap]);
            }
        }

        // Statistics.
        NSWindow *statistics = owner->statisticsPanel;
        NSMutableArray<NSView *> *views = [NSMutableArray array]; All(statistics.contentView, views);
        BOOL form = NO; NSMutableArray<NSTextField *> *labels = [NSMutableArray array], *fields = [NSMutableArray array];
        for (NSView *v in views) {
            if ([v isKindOfClass:NSForm.class] || [v isKindOfClass:NSMatrix.class]) form = YES;
            if (![v isKindOfClass:NSTextField.class]) continue;
            NSTextField *f = (NSTextField *)v;
            [(f.isBezeled ? fields : labels) addObject:f];
        }
        Check(!form, [NSString stringWithFormat:@"%@ Statistics: no form", lang]);
        NSArray *connected = @[owner->statisticsWords ?: NSNull.null, owner->statisticsLines ?: NSNull.null, owner->statisticsCharacters ?: NSNull.null];
        Check(labels.count == 3 && fields.count == 3 && [[NSSet setWithArray:connected] isEqual:[NSSet setWithArray:fields]],
              [NSString stringWithFormat:@"%@ Statistics: three labels and three fields, the fields connected", lang]);
        if (fields.count == 3 && labels.count == 3) {
            Check(NSMinY(((NSView *)connected[0]).frame) > NSMinY(((NSView *)connected[1]).frame) && NSMinY(((NSView *)connected[1]).frame) > NSMinY(((NSView *)connected[2]).frame),
                  [NSString stringWithFormat:@"%@ Statistics: words, lines and characters from the top", lang]);
            for (NSUInteger k = 0; k < 3; k++) {
                NSTextField *field = fields[k], *label = labels[k];
                Check(!field.isEditable && field.isSelectable, [NSString stringWithFormat:@"%@ Statistics: a field can be selected, not edited", lang]);
                Check(fabs(NSMinX(field.frame) - NSMinX(fields[0].frame)) < 0.5 && fabs(NSWidth(field.frame) - NSWidth(fields[0].frame)) < 0.5,
                      [NSString stringWithFormat:@"%@ Statistics: the fields share one left edge and width", lang]);
                Check(label.alignment == NSTextAlignmentRight && fabs(NSMaxX(label.frame) - NSMaxX(labels[0].frame)) < 0.5 && NSWidth(label.frame) >= ceil(label.fittingSize.width) - 0.5,
                      [NSString stringWithFormat:@"%@ Statistics: \"%@\" is right-aligned, whole, and ends where the others end", lang, label.stringValue]);
                Check(NSMinX(field.frame) - NSMaxX(label.frame) >= 2 && fabs(NSMidY(field.frame) - NSMidY(label.frame)) < 1.5,
                      [NSString stringWithFormat:@"%@ Statistics: \"%@\" stands beside its field", lang, label.stringValue]);
            }
            Check(fabs(NSWidth(statistics.contentView.bounds) - NSMaxX(fields[0].frame) - 20) < 0.5, [NSString stringWithFormat:@"%@ Statistics: 20 points to the right edge", lang]);
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
    printf("PASS: the console's push buttons, the Text panel's choices, the Statistics fields and the Magnification labels in %d languages (%d checks)\n", argc - 1, checks);
} return 0; }
