// The Matrix and LaTeX panels, loaded offscreen with their own controllers as the application loads them,
// in every language given: what their buttons insert, and how they are laid out.
//   * Matrix panel: Insert, Clear, Identity and Zero insert and set what they did before; the columns
//     inserted follow the order shown; there is no ruler; the first row is below the header; Insert is
//     the default button, and Return in the size and delimiter fields or in a cell being edited does not
//     insert; the table, its cells and the
//     pictures of the border and grid buttons follow the light or dark appearance.
//   * LaTeX panel: each group has a segmented control above it that shows its pages; every kind of button
//     posts the same text as before; the custom buttons have their names whatever LPanelOutlines says;
//     every button shows a rounded frame under the pointer (always when LPanelOutlines is NO) and its
//     words in the color of text; the symbols are drawn in the color of text in light and dark appearance.
// Usage: MatrixLaTeXPanels <language>|<matrixpanel nib>|<completionpanel nib> ...
#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "TestAppKitIsolation.h"
#import "TSMatrixPanelController.h"
#import "TSMatrixTableView.h"
#import "TSLaTeXPanelController.h"
#import "PanelEnvironment.h"
// The table's data source and delegate.
@interface TSMatrixPanelController (Table)
- (void)tableView:(NSTableView *)tv setObjectValue:(id)objectValue forTableColumn:(NSTableColumn *)tc row:(NSInteger)row;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
@end

static int failures;
static void Expect(BOOL ok, NSString *what) {
    if (!ok) { printf("FAIL %s\n", what.UTF8String); failures++; }
}

@interface Listener : NSObject
@property (strong) NSMutableArray<NSString *> *posted;
@end
@implementation Listener
- (instancetype)init { if ((self = [super init])) _posted = [NSMutableArray array]; return self; }
- (void)got:(NSNotification *)n { [self.posted addObject:[n.object description]]; }
@end

static void Key(NSWindow *w, NSString *chars, unsigned short code) {
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:w.windowNumber
                                    context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code]];
}

static id Load(Class controllerClass, NSString *path, NSWindow **window) {
    NSWindowController *controller = [[controllerClass alloc] initWithWindow:nil];
    NSArray *objects = nil;
    if (![[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil] instantiateWithOwner:controller topLevelObjects:&objects]) return nil;
    [controller windowDidLoad];
    *window = controller.window;
    [*window layoutIfNeeded]; [*window displayIfNeeded];
    return controller;
}

// The color a view draws at a point, in the given appearance.
static NSColor *ColorAt(NSView *view, NSPoint point) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    CGFloat scale = rep.pixelsWide / NSWidth(view.bounds);
    NSInteger y = view.isFlipped ? point.y * scale : (NSHeight(view.bounds) - point.y) * scale;
    return [[rep colorAtX:(NSInteger)(point.x * scale) y:MIN(MAX(0, y), rep.pixelsHigh - 1)] colorUsingColorSpace:NSColorSpace.genericGrayColorSpace];
}

static void CheckMatrixPanel(NSString *language, NSString *path, Listener *listener) {
    NSWindow *w = nil;
    TSMatrixPanelController *panel = Load(TSMatrixPanelController.class, path, &w);
    if (!panel) { Expect(NO, [NSString stringWithFormat:@"%@ matrix panel loads", language]); return; }
    NSString *(^name)(NSString *) = ^(NSString *what) { return [NSString stringWithFormat:@"%@ matrix panel: %@", language, what]; };
    TSMatrixTableView *table = [panel valueForKey:@"matrixtable"];
    NSScrollView *scroll = table.enclosingScrollView;
    NSMatrix *modify = [panel valueForKey:@"matmod"];
    NSButton *insert = nil;
    for (NSView *v in w.contentView.subviews) if ([v isKindOfClass:NSButton.class] && ((NSButton *)v).action == @selector(insertMatrix:)) insert = (NSButton *)v;

    Expect(!scroll.hasVerticalRuler && !scroll.rulersVisible, name(@"no ruler"));
    Expect(table.matrixColumns.count == 12, name(@"12 matrix columns"));
    // The first row below the header, as the panel opens.
    NSRect row = [w.contentView convertRect:[table rectOfRow:0] fromView:table];
    NSRect header = [w.contentView convertRect:table.headerView.visibleRect fromView:table.headerView];
    Expect(NSMaxY(row) <= NSMinY(header) + 0.5, name(@"the first row is below the header"));

    // Insert, with the defaults: a 3 by 3 matrix of zeros in parentheses.
    [listener.posted removeAllObjects];
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}0 & 0 & 0 \\\\0 & 0 & 0 \\\\0 & 0 & 0\\end{array}\\right)"], name([@"Insert gives a 3 by 3 zero matrix: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    // Identity, then Insert.
    [modify selectCellWithTag:1]; [panel resetMatrix:modify];
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}1 & 0 & 0 \\\\0 & 1 & 0 \\\\0 & 0 & 1\\end{array}\\right)"], name([@"Identity: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    // A value typed in the second column of the first row, then the first two matrix columns swapped: the
    // columns are inserted in the order shown.
    [panel tableView:table setObjectValue:@"a" forTableColumn:table.matrixColumns[1] row:0];
    [table moveColumn:[table.tableColumns indexOfObject:table.matrixColumns[1]] toColumn:[table.tableColumns indexOfObject:table.matrixColumns[0]]];
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}a & 1 & 0 \\\\1 & 0 & 0 \\\\0 & 0 & 1\\end{array}\\right)"], name([@"moved columns: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    // Identity follows the order shown too; Clear, then Zero.
    [panel resetMatrix:modify];
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}1 & 0 & 0 \\\\0 & 1 & 0 \\\\0 & 0 & 1\\end{array}\\right)"], name([@"Identity after moving: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    [modify selectCellWithTag:0]; [panel resetMatrix:modify];
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}  &   &   \\\\  &   &   \\\\  &   &  \\end{array}\\right)"], name([@"Clear: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    [modify selectCellWithTag:2]; [panel resetMatrix:modify];
    // tabular in a table with a border and a grid, 2 by 2.
    NSMatrix *environment = [panel valueForKey:@"envsel"];
    [environment selectCellWithTag:1]; [panel envselChange:environment];
    NSButton *embed = [panel valueForKey:@"chbfig"], *border = [panel valueForKey:@"borderbutton"], *grid = [panel valueForKey:@"gridbutton"];
    Expect(embed.isEnabled, name(@"tabular enables Embed in table"));
    embed.state = NSControlStateValueOn; border.state = NSControlStateValueOn; grid.state = NSControlStateValueOn;
    NSTextField *rows = [panel valueForKey:@"vtf"], *columns = [panel valueForKey:@"htf"];
    rows.integerValue = 2; [panel resizeMatrix:rows]; columns.integerValue = 2; [panel resizeMatrix:columns];
    [panel insertMatrix:insert];
    // The pieces of the Matrix panel's file (matrixpanel_1.plist): table, tabular, |, c, }, \\hline, & , \\, end.
    NSArray<NSString *> *m = [NSDictionary dictionaryWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/TeXShop/MatrixPanel/matrixpanel_1.plist"]][@"Matrix"];
    NSString *tabular = [@[m[20], m[17], m[14], m[1], m[14], m[1], m[14], m[2], m[19], @"0", m[3], @"0", m[4], m[19], @"0", m[3], @"0", m[4], m[19], m[18], m[21]] componentsJoinedByString:@""];
    Expect([listener.posted.lastObject isEqual:tabular],
           name([@"tabular with border and grid: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    [environment selectCellWithTag:0]; [panel envselChange:environment];

    // The border and grid buttons stay pressed, and their pictures follow the appearance.
    Expect(border.image.isTemplate && grid.image.isTemplate, name(@"the border and grid pictures are templates"));
    // Insert is the default button; Return inserts only when no field is being edited.
    Expect([insert.keyEquivalent isEqual:@"\r"], name(@"Insert is the default button"));
    [listener.posted removeAllObjects];
    [w makeFirstResponder:rows]; Key(w, @"4", 21); Key(w, @"\r", 36);
    Expect(listener.posted.count == 0 && rows.integerValue == 4, name(@"Return in the rows field sets the rows and does not insert"));
    [w makeFirstResponder:table]; [table editColumn:[table.tableColumns indexOfObject:table.matrixColumns[0]] row:0 withEvent:nil select:YES];
    Key(w, @"7", 26); Key(w, @"\r", 36);
    Expect(listener.posted.count == 0, name(@"Return in a cell being edited does not insert"));
    [w makeFirstResponder:nil]; Key(w, @"\r", 36);
    Expect(listener.posted.count == 1, name(@"Return with nothing being edited inserts"));

    // Light and dark: the table's background and the cells that are not inserted.
    for (NSAppearanceName mode in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        w.appearance = [NSAppearance appearanceNamed:mode];
        [w displayIfNeeded];
        NSRect last = [table frameOfCellAtColumn:table.numberOfColumns - 1 row:table.numberOfRows - 1];
        NSPoint corner = [scroll convertPoint:NSMakePoint(NSMaxX(last) - 2, NSMaxY(last) - 2) fromView:table];
        corner = NSMakePoint(MIN(corner.x, NSWidth(scroll.bounds) - 20), MIN(MAX(corner.y, 20), NSHeight(scroll.bounds) - 20));
        CGFloat white = [ColorAt(scroll, corner) whiteComponent];
        BOOL dark = [mode isEqual:NSAppearanceNameDarkAqua];
        Expect(dark ? white < 0.3 : white > 0.8, name([NSString stringWithFormat:@"the table is %@ in %@ appearance (gray %.2f)", dark ? @"dark" : @"light", dark ? @"dark" : @"light", white]));
    }
    w.appearance = nil;
}

static void CheckLaTeXPanel(NSString *language, NSString *path, Listener *listener, BOOL outlinesOnHover) {
    [NSUserDefaults.standardUserDefaults setObject:outlinesOnHover ? @"YES" : @"NO" forKey:@"LPanelOutlines"];
    NSWindow *w = nil;
    TSLaTeXPanelController *panel = Load(TSLaTeXPanelController.class, path, &w);
    if (!panel) { Expect(NO, [NSString stringWithFormat:@"%@ LaTeX panel loads", language]); return; }
    NSString *(^name)(NSString *) = ^(NSString *what) { return [NSString stringWithFormat:@"%@ LaTeX panel%@: %@", language, outlinesOnHover ? @"" : @" (LPanelOutlines NO)", what]; };
    NSMutableArray<NSTabView *> *pages = [NSMutableArray array];
    NSMutableArray<NSSegmentedControl *> *choosers = [NSMutableArray array];
    for (NSView *v in w.contentView.subviews) {
        if ([v isKindOfClass:NSTabView.class]) [pages addObject:(NSTabView *)v];
        if ([v isKindOfClass:NSSegmentedControl.class]) [choosers addObject:(NSSegmentedControl *)v];
    }
    Expect(pages.count == 2 && choosers.count == 2, name(@"two groups, each with a segmented control"));
    [pages sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) { return NSMaxY(a.frame) > NSMaxY(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    [choosers sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) { return NSMaxY(a.frame) > NSMaxY(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    for (NSUInteger i = 0; i < 2 && pages.count == 2 && choosers.count == 2; i++) {
        NSTabView *page = pages[i]; NSSegmentedControl *chooser = choosers[i];
        Expect(page.tabViewType == NSNoTabsNoBorder, name(@"the groups have no tab view frame"));
        Expect(chooser.segmentCount == page.numberOfTabViewItems && chooser.selectedSegment == 0 && [page.selectedTabViewItem isEqual:page.tabViewItems[0]],
               name(@"each group opens at its first page"));
        Expect(NSMinY(chooser.frame) > NSMaxY(page.frame), name(@"the segmented control is above its group"));
        for (NSInteger s = 0; s < chooser.segmentCount; s++) {
            Expect([[chooser labelForSegment:s] isEqual:page.tabViewItems[s].label], name(@"the segments are named as the pages"));
            chooser.selectedSegment = s;
            [chooser sendAction:chooser.action to:chooser.target];
            Expect([page indexOfTabViewItem:page.selectedTabViewItem] == s, name([NSString stringWithFormat:@"segment %ld shows page %ld", (long)s, (long)s]));
        }
        chooser.selectedSegment = 0; [chooser sendAction:chooser.action to:chooser.target];
    }
    NSDictionary *completion = [NSDictionary dictionaryWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/TeXShop/LatexPanel/completion.plist"]];
    // Every kind of button posts what it did before.
    struct { const char *outlet, *action, *key; NSInteger tag, index; } buttons[] = {
        {"environbuttonmatrix", "putenvironments:", "Environments", 0, 0},
        {"typefacebuttonmatrix", "puttypeface:", "Typeface", 2, 2},
        {"functionsbuttonmatrix", "putfunctions1:", "Functions1", 5, 5},
        {"mathbuttonmatrix", "putmath:", "Math", 7, 7},
        {"symbolsbuttonmatrix", "putsymbols:", "Symbols", 12, 12},
        {"greekbuttonmatrix", "putgreek:", "Greek", 44, 30},
        {"intlbuttonmatrix", "putintl:", "International", 44, 35},
        {"custombuttonmatrix", "putcustomized:", "Customized", 1, 3},
    };
    for (size_t i = 0; i < sizeof buttons / sizeof buttons[0]; i++) {
        NSMatrix *m = [panel valueForKey:@(buttons[i].outlet)];
        [m selectCellWithTag:buttons[i].tag];
        [listener.posted removeAllObjects];
        ((void (*)(id, SEL, id))objc_msgSend)(panel, NSSelectorFromString(@(buttons[i].action)), m);
        NSString *expected = [completion[@(buttons[i].key)] objectAtIndex:buttons[i].index];
        Expect([listener.posted.lastObject isEqual:expected], name([NSString stringWithFormat:@"%s posts %@", buttons[i].action, expected]));
    }
    // The custom buttons have the names of the custom commands, outlined, and the others stay empty.
    NSMatrix *custom = [panel valueForKey:@"custombuttonmatrix"];
    NSArray *customized = completion[@"Customized"];
    for (NSInteger tag = 0; tag < 16; tag++) {
        NSButtonCell *cell = [custom cellWithTag:tag];
        BOOL used = tag < (NSInteger)customized.count / 2;
        Expect(used ? ([cell.title isEqual:customized[tag * 2]] && cell.isBordered && cell.isEnabled) : !cell.isBordered,
               name([NSString stringWithFormat:@"custom button %ld %@", (long)tag, used ? customized[tag * 2] : @"stays empty"]));
    }
    // Every button shows its frame only under the pointer unless LPanelOutlines is NO, with rounded corners;
    // the words and text symbols are in the color of text, not in the gray of a title whose frame is hidden.
    for (NSString *outlet in @[@"environbuttonmatrix", @"typefacebuttonmatrix", @"functionsbuttonmatrix", @"greekbuttonmatrix", @"custombuttonmatrix", @"mathbuttonmatrix"]) {
        NSButtonCell *cell = [[panel valueForKey:outlet] cellWithTag:0];
        Expect(cell.showsBorderOnlyWhileMouseInside == outlinesOnHover && [NSStringFromClass(cell.class) isEqual:@"TSLaTeXPanelButtonCell"],
               name([outlet stringByAppendingString:@" show a rounded frame as LPanelOutlines says"]));
        if (cell.title.length)
            Expect([[cell.attributedTitle attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:NSColor.labelColor], name([outlet stringByAppendingString:@" are in the color of text"]));
    }
    NSButtonCell *symbol = [[panel valueForKey:@"mathbuttonmatrix"] cellWithTag:0];
    // The pictures of the symbols in the color of text: dark in light appearance, light in dark appearance,
    // whether or not the application has asked for templates (TSTextView does in dark appearance).
    for (NSNumber *template in @[@NO, @YES]) {
        [panel setIconTemplate:template.boolValue];
        for (NSAppearanceName mode in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:mode];
            NSImage *image = symbol.image;
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)image.size.width * 2 pixelsHigh:(NSInteger)image.size.height * 2
                                                                         bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [appearance performAsCurrentDrawingAppearance:^{ [image drawInRect:NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh)]; }];
            [NSGraphicsContext restoreGraphicsState];
            CGFloat darkest = 1, lightest = 0;
            for (NSInteger y = 0; y < rep.pixelsHigh; y++) for (NSInteger x = 0; x < rep.pixelsWide; x++) {
                NSColor *c = [rep colorAtX:x y:y];
                if (c.alphaComponent < 0.9) continue;
                CGFloat g = [[c colorUsingColorSpace:NSColorSpace.genericGrayColorSpace] whiteComponent];
                darkest = MIN(darkest, g); lightest = MAX(lightest, g);
            }
            BOOL dark = [mode isEqual:NSAppearanceNameDarkAqua];
            Expect(dark ? lightest > 0.9 : darkest < 0.1, name([NSString stringWithFormat:@"a symbol is drawn %@ in %@ appearance%@", dark ? @"white" : @"black", dark ? @"dark" : @"light", template.boolValue ? @" after setIconTemplate:YES" : @""]));
        }
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    TSInstallPanelEnvironment();
    Listener *listener = [Listener new];
    [NSNotificationCenter.defaultCenter addObserver:listener selector:@selector(got:) name:@"matrixpanel" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:listener selector:@selector(got:) name:@"completionpanel" object:nil];
    for (int i = 1; i < argc; i++) {
        NSArray<NSString *> *parts = [@(argv[i]) componentsSeparatedByString:@"|"];
        CheckMatrixPanel(parts[0], parts[1], listener);
        for (NSNumber *hover in @[@YES, @NO]) CheckLaTeXPanel(parts[0], parts[2], listener, hover.boolValue);
    }
    if (failures) { printf("FAIL: %d problems\n", failures); return 1; }
    printf("PASS: in %d languages the Matrix panel inserts what it did, has no ruler, starts its rows below the header and makes Insert the default button, and the LaTeX panel shows its groups with segmented controls, posts what it did, names its custom buttons and draws its symbols in the color of text\n", argc - 1);
} return 0; }
