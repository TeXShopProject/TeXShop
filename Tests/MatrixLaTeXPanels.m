// The Matrix and LaTeX panels, loaded offscreen with their own controllers as the application loads them,
// in every language given: what their buttons insert, and how they are laid out.
//   * Matrix panel: Insert, Clear, Identity and Zero insert and set what they did before; the columns
//     inserted follow the order shown; the rows are numbered in a column that cannot be edited or moved,
//     with no ruler; the first row is below the header; Insert is the default button, and Return in the
//     size and delimiter fields or in a cell being edited does not insert; the table, its cells and the
//     pictures of the border and grid buttons follow the light or dark appearance.
//   * LaTeX panel: each group has a segmented control above it that shows its pages; every kind of button
//     posts the same text as before; the custom buttons have their names whatever LPanelOutlines says;
//     every button shows a rounded frame under the pointer (always when LPanelOutlines is NO) and its
//     words in the color of text; the symbols are drawn in the color of text in light and dark appearance.
//   * Neither panel shows a placeholder title left in its compiled nibs ("Box", "Radio", "Switch", ...).
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
- (BOOL)tableView:(NSTableView *)tableView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex;
- (void)tableView:(NSTableView *)tv setObjectValue:(id)objectValue forTableColumn:(NSTableColumn *)tc row:(NSInteger)row;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pboard;
- (BOOL)tableView:(NSTableView *)tv acceptDrop:(id)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op;
@end
@interface TSMatrixPanelController (Undo)
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window;
@end
@interface TSMatrixTableView (Edit)
- (void)copy:(id)sender;
- (void)cut:(id)sender;
- (void)paste:(id)sender;
- (void)delete:(id)sender;
@end

static int failures;
static void Expect(BOOL ok, NSString *what) {
    if (!ok) { printf("FAIL %s\n", what.UTF8String); failures++; }
}

// A row dragged within the table, as AppKit hands it to the data source.
@interface RowDrag : NSObject
@property (strong) NSPasteboard *draggingPasteboard;
@property (strong) id draggingSource;
@end
@implementation RowDrag
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationEvery; }
@end

@interface Listener : NSObject
@property (strong) NSMutableArray<NSString *> *posted;
@end
@implementation Listener
- (instancetype)init { if ((self = [super init])) _posted = [NSMutableArray array]; return self; }
- (void)got:(NSNotification *)n { [self.posted addObject:[n.object description]]; }
@end

// A key as the application gets it: taken from the queue, so that it is the current event while the window
// handles it.
static void SendKey(NSWindow *w, NSEvent *key) {
    [NSApp postEvent:key atStart:YES];
    NSEvent *got = [NSApp nextEventMatchingMask:NSEventMaskKeyDown untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES];
    [w sendEvent:got ?: key];
}
static void Key(NSWindow *w, NSString *chars, unsigned short code) {
    SendKey(w, [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:w.windowNumber
                                 context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code]);
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

// The placeholder titles that Interface Builder gives new parts ("Box", "Radio", "Switch", "Button", and
// "Sy" and "Löschen" in these panels) are left in the compiled panels on prototype cells and an untitled
// line. None of them is ever on screen: every text the panel shows, on every page.
static NSArray<NSString *> *ShownTexts(NSView *view) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    if (view.isHiddenOrHasHiddenAncestor) return texts;
    if ([view isKindOfClass:NSBox.class] && ((NSBox *)view).titlePosition != NSNoTitle) [texts addObject:((NSBox *)view).title];
    if ([view isKindOfClass:NSTextField.class]) [texts addObject:((NSTextField *)view).stringValue];
    if ([view isKindOfClass:NSButton.class]) [texts addObject:((NSButton *)view).title];
    if ([view isKindOfClass:NSSegmentedControl.class])
        for (NSInteger i = 0; i < ((NSSegmentedControl *)view).segmentCount; i++) [texts addObject:[(NSSegmentedControl *)view labelForSegment:i] ?: @""];
    if ([view isKindOfClass:NSMatrix.class]) {
        for (NSCell *cell in ((NSMatrix *)view).cells) [texts addObject:cell.title ?: @""];
        return texts;
    }
    if ([view isKindOfClass:NSTabView.class]) {
        for (NSTabViewItem *item in ((NSTabView *)view).tabViewItems) if (item.view) [texts addObjectsFromArray:ShownTexts(item.view)];
        return texts;
    }
    for (NSView *sub in view.subviews) [texts addObjectsFromArray:ShownTexts(sub)];
    return texts;
}
static void CheckNoPlaceholders(NSWindow *w, NSString *language, NSString *what) {
    // In German, Löschen is also the real title of Clear.
    NSMutableSet *placeholders = [NSMutableSet setWithArray:@[@"Box", @"Radio", @"Switch", @"Button", @"Sy"]];
    if (![language isEqual:@"de"]) [placeholders addObject:@"Löschen"];
    NSMutableSet *shown = [NSMutableSet setWithArray:ShownTexts(w.contentView)];
    [shown intersectSet:placeholders];
    Expect(shown.count == 0, [NSString stringWithFormat:@"%@: no placeholder title is shown (%@)", what, [shown.allObjects componentsJoinedByString:@", "]]);
}

static void CheckMatrixPanel(NSString *language, NSString *path, Listener *listener) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"MatrixPanelColumns"];
    NSWindow *w = nil;
    TSMatrixPanelController *panel = Load(TSMatrixPanelController.class, path, &w);
    if (!panel) { Expect(NO, [NSString stringWithFormat:@"%@ matrix panel loads", language]); return; }
    NSString *(^name)(NSString *) = ^(NSString *what) { return [NSString stringWithFormat:@"%@ matrix panel: %@", language, what]; };
    TSMatrixTableView *table = [panel valueForKey:@"matrixtable"];
    NSScrollView *scroll = table.enclosingScrollView;
    NSMatrix *modify = [panel valueForKey:@"matmod"];
    NSButton *insert = nil;
    for (NSView *v in w.contentView.subviews) if ([v isKindOfClass:NSButton.class] && ((NSButton *)v).action == @selector(insertMatrix:)) insert = (NSButton *)v;

    // The row numbers.
    Expect(!scroll.hasVerticalRuler && !scroll.rulersVisible, name(@"no ruler"));
    CheckNoPlaceholders(w, language, name(@"as it opens"));
    NSTableColumn *numbers = table.tableColumns.firstObject;
    Expect([numbers.identifier isEqual:TSMatrixRowNumberColumn] && !numbers.isEditable && numbers.resizingMask == NSTableColumnNoResizing, name(@"the first column numbers the rows and cannot be edited or resized"));
    Expect([[panel tableView:table objectValueForTableColumn:numbers row:4] isEqual:@5], name(@"the fifth row is numbered 5"));
    Expect(table.matrixColumns.count == 12 && ![table.matrixColumns containsObject:numbers], name(@"12 matrix columns, without the row numbers"));
    Expect([panel respondsToSelector:@selector(tableView:shouldReorderColumn:toColumn:)] && ![panel tableView:table shouldReorderColumn:0 toColumn:3] && ![panel tableView:table shouldReorderColumn:3 toColumn:0] && [panel tableView:table shouldReorderColumn:2 toColumn:3],
           name(@"the row numbers stay first; the matrix columns can be moved"));
    Expect([[numbers.dataCell font] isEqual:[table.matrixColumns[0].headerCell font]], name(@"the row numbers use the font of the column numbers"));
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
    // A row dragged below another moves its values; the row numbers stay 1, 2, 3 (they number the places).
    [panel tableView:table setObjectValue:@"x" forTableColumn:table.matrixColumns[0] row:0];
    RowDrag *drag = [RowDrag new];
    drag.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    drag.draggingSource = table;
    [panel tableView:table writeRowsWithIndexes:[NSIndexSet indexSetWithIndex:0] toPasteboard:drag.draggingPasteboard];
    [panel tableView:table acceptDrop:drag row:2 dropOperation:NSTableViewDropAbove];
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}0 & 0 & 0 \\\\x & 0 & 0 \\\\0 & 0 & 0\\end{array}\\right)"], name([@"a dragged row moves its values: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    Expect([[panel tableView:table objectValueForTableColumn:numbers row:0] isEqual:@1] && [[panel tableView:table objectValueForTableColumn:numbers row:1] isEqual:@2], name(@"the row numbers stay in order after a drag"));
    // The blue of the cells inserted starts at the first column of the matrix, not under the row numbers.
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; [w displayIfNeeded];
    NSRect numberCell = [table frameOfCellAtColumn:0 row:1], firstCell = [table frameOfCellAtColumn:1 row:1];
    NSColor *(^rgb)(NSRect) = ^NSColor *(NSRect cell) {
        NSBitmapImageRep *rep = [table bitmapImageRepForCachingDisplayInRect:table.bounds];
        [table cacheDisplayInRect:table.bounds toBitmapImageRep:rep];
        CGFloat scale = rep.pixelsWide / NSWidth(table.bounds);
        return [[rep colorAtX:(NSInteger)((NSMinX(cell) + 3) * scale) y:(NSInteger)((NSMinY(cell) + 3) * scale)] colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    };
    NSColor *number = rgb(numberCell), *inserted = rgb(firstCell);
    Expect(inserted.blueComponent - inserted.redComponent > 0.03 && fabs(number.blueComponent - number.redComponent) < 0.02,
           name([NSString stringWithFormat:@"blue under the cells inserted (%.2f/%.2f), not under the row numbers (%.2f/%.2f)", inserted.redComponent, inserted.blueComponent, number.redComponent, number.blueComponent]));
    w.appearance = nil;
    [panel resetMatrix:modify];
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

// A key with modifiers, as the window gets it.
static void KeyWith(NSWindow *w, NSString *chars, unsigned short code, NSEventModifierFlags flags) {
    SendKey(w, [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:w.windowNumber
                                 context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code]);
}
static NSString *Arrow(unichar key) { return [NSString stringWithCharacters:&key length:1]; }
// A click in a cell of the table: the button comes up at once.
static void Click(NSTableView *table, NSInteger tableColumn, NSInteger row, NSInteger count, NSEventModifierFlags flags) {
    NSRect cell = [table frameOfCellAtColumn:tableColumn row:row];
    NSPoint p = [table convertPoint:NSMakePoint(NSMidX(cell), NSMidY(cell)) toView:nil];
    NSWindow *w = table.window;
    NSEvent *(^mouse)(NSEventType) = ^(NSEventType type) {
        return [NSEvent mouseEventWithType:type location:p modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:count pressure:1];
    };
    [NSApp postEvent:mouse(NSEventTypeLeftMouseUp) atStart:NO];
    [table mouseDown:mouse(NSEventTypeLeftMouseDown)];
}

// Each event is one change to undo: the run loop closes the group, as after an event in the application.
static void CloseUndoGroups(NSUndoManager *undo) {
    for (int i = 0; i < 20 && undo.groupingLevel > 0; i++) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Expect(undo.groupingLevel == 0, @"the run loop closes the group of changes to undo");
}

// The table of the Matrix panel used like a spreadsheet, the size of the panel and of the matrix, and the
// fields for other delimiters.
static void CheckMatrixSpreadsheet(NSString *language, NSString *path, Listener *listener) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"MatrixPanelColumns"];
    NSWindow *w = nil;
    TSMatrixPanelController *panel = Load(TSMatrixPanelController.class, path, &w);
    if (!panel) { Expect(NO, [NSString stringWithFormat:@"%@ matrix panel loads", language]); return; }
    NSString *(^name)(NSString *) = ^(NSString *what) { return [NSString stringWithFormat:@"%@ matrix table: %@", language, what]; };
    TSMatrixTableView *table = [panel valueForKey:@"matrixtable"];
    table.pasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSButton *insert = nil;
    for (NSView *v in w.contentView.subviews) if ([v isKindOfClass:NSButton.class] && ((NSButton *)v).action == @selector(insertMatrix:)) insert = (NSButton *)v;
    NSString *(^at)(NSInteger, NSInteger) = ^(NSInteger r, NSInteger c) { return [panel valueAtRow:r shownColumn:c]; };
    NSInteger (^tc)(NSInteger) = ^NSInteger(NSInteger c) { return (NSInteger)[table.tableColumns indexOfObject:table.matrixColumns[c]]; };

    // The panel has no largest size.
    Expect(w.contentMaxSize.width > 10000 && w.contentMaxSize.height > 10000, name([NSString stringWithFormat:@"the panel can be made as large as wanted (%@)", NSStringFromSize(w.contentMaxSize)]));
    Expect(table.columnAutoresizingStyle == NSTableViewNoColumnAutoresizing && table.enclosingScrollView.hasHorizontalScroller, name(@"the columns keep their widths and the table scrolls sideways"));
    // A larger panel shows more rows and columns.
    NSInteger rowsBefore = panel.gridRows, columnsBefore = panel.gridColumns;
    [w setContentSize:NSMakeSize(1400, 1100)]; [w.contentView layoutSubtreeIfNeeded];
    [NSNotificationCenter.defaultCenter postNotificationName:NSViewFrameDidChangeNotification object:table.enclosingScrollView.contentView];
    Expect(panel.gridRows > rowsBefore && panel.gridColumns > columnsBefore && panel.gridColumns == (NSInteger)table.matrixColumns.count,
           name([NSString stringWithFormat:@"a larger panel fills with rows and columns (%ld x %ld -> %ld x %ld)", (long)rowsBefore, (long)columnsBefore, (long)panel.gridRows, (long)panel.gridColumns]));

    // The rows and columns go up to 999, and the cells left out keep their values.
    NSTextField *rowsField = [panel valueForKey:@"vtf"], *columnsField = [panel valueForKey:@"htf"];
    NSStepper *rowsStepper = [panel valueForKey:@"vstep"], *columnsStepper = [panel valueForKey:@"hstep"];
    Expect(rowsStepper.maxValue == TSMatrixLargestSize && columnsStepper.maxValue == TSMatrixLargestSize && TSMatrixLargestSize == 999, name(@"the steppers go up to 999"));
    columnsField.integerValue = 40; [panel resizeMatrix:columnsField];
    Expect(panel.theMatrix.actCols == 40 && panel.gridColumns >= 40 && columnsStepper.integerValue == 40, name(@"40 columns"));
    rowsField.integerValue = 2; [panel resizeMatrix:rowsField];
    [panel insertMatrix:insert];
    NSString *forty = [@"" stringByPaddingToLength:40 withString:@"c" startingAtIndex:0];
    Expect([listener.posted.lastObject hasPrefix:[NSString stringWithFormat:@"\\left(\\begin{array}{%@}", forty]], name(@"40 columns are inserted"));
    NSDate *start = NSDate.date;
    columnsField.integerValue = 5000; [panel resizeMatrix:columnsField];
    rowsField.integerValue = 5000; [panel resizeMatrix:rowsField];
    Expect(panel.theMatrix.actCols == 999 && panel.theMatrix.actRows == 999 && panel.gridColumns == 999 && panel.gridRows == 999 && columnsField.integerValue == 999,
           name(@"5000 rows and columns become 999"));
    Expect(-start.timeIntervalSinceNow < 20, name([NSString stringWithFormat:@"999 by 999 takes %.1f s", -start.timeIntervalSinceNow]));
    [panel setValues:@[@[@"kept"]] atRow:998 shownColumn:998];
    columnsField.integerValue = 3; [panel resizeMatrix:columnsField];
    rowsField.integerValue = 3; [panel resizeMatrix:rowsField];
    Expect(panel.gridColumns == 999 && [at(998, 998) isEqual:@"kept"], name(@"fewer rows and columns keep the table and its values"));
    // Copy, Delete, Undo and Paste of every cell of a 999 by 999 table take little time.
    CloseUndoGroups(w.undoManager);
    [table selectAll:nil];
    start = NSDate.date; [table copy:nil];
    NSTimeInterval copying = -start.timeIntervalSinceNow;
    start = NSDate.date; [table delete:nil];
    NSTimeInterval deleting = -start.timeIntervalSinceNow;
    CloseUndoGroups(w.undoManager);
    start = NSDate.date; [w.undoManager undo];
    NSTimeInterval undoing = -start.timeIntervalSinceNow;
    start = NSDate.date; [table selectRow:0 column:0 extending:NO]; [table paste:nil];
    NSTimeInterval pasting = -start.timeIntervalSinceNow;
    CloseUndoGroups(w.undoManager);
    Expect(copying < 8 && deleting < 8 && undoing < 8 && pasting < 8 && [at(998, 998) isEqual:@"kept"],
           name([NSString stringWithFormat:@"every cell of 999 by 999: Copy %.1f s, Delete %.1f s, Undo %.1f s, Paste %.1f s", copying, deleting, undoing, pasting]));
    [panel insertMatrix:insert];
    Expect([listener.posted.lastObject isEqual:@"\\left(\\begin{array}{ccc}0 & 0 & 0 \\\\0 & 0 & 0 \\\\0 & 0 & 0\\end{array}\\right)"], name([@"3 by 3 again: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    [table scrollRowToVisible:0]; [table scrollColumnToVisible:0];

    // Typing in a cell, Return and Tab as in a spreadsheet.
    [w makeFirstResponder:table];
    [table selectRow:0 column:0 extending:NO];
    [listener.posted removeAllObjects];
    Key(w, @"5", 23);
    Expect(table.currentEditor != nil, name(@"typing starts editing the cell"));
    Key(w, @"\r", 36);
    Expect([at(0, 0) isEqual:@"5"] && table.activeRow == 1 && table.activeColumn == 0 && table.currentEditor == nil && w.firstResponder == table,
           name([NSString stringWithFormat:@"Return keeps 5 and goes down (%@ at %ld,%ld)", at(0, 0), (long)table.activeRow, (long)table.activeColumn]));
    Key(w, @"a", 0); Key(w, @"\t", 48); Key(w, @"b", 11); Key(w, @"\t", 48); Key(w, @"c", 8); Key(w, @"\r", 36);
    Expect([at(1, 0) isEqual:@"a"] && [at(1, 1) isEqual:@"b"] && [at(1, 2) isEqual:@"c"] && table.activeRow == 2 && table.activeColumn == 0,
           name([NSString stringWithFormat:@"Tab goes right and Return comes back to the first column (%ld,%ld)", (long)table.activeRow, (long)table.activeColumn]));
    Expect(listener.posted.count == 0, name(@"Return in the table does not insert"));
    // Return and Tab without editing move too.
    Key(w, @"\r", 36);
    Expect(table.activeRow == 3 && listener.posted.count == 0, name(@"Return without editing goes down and does not insert"));
    KeyWith(w, @"\r", 36, NSEventModifierFlagShift);
    Expect(table.activeRow == 2, name(@"Shift-Return goes up"));
    Key(w, @"s", 1); KeyWith(w, @"\r", 36, NSEventModifierFlagShift);
    Expect([at(2, 0) isEqual:@"s"] && table.activeRow == 1, name(@"Shift-Return in a cell being edited keeps the value and goes up"));
    Key(w, @"t", 17); KeyWith(w, @"\x19", 48, NSEventModifierFlagShift);
    Expect([at(1, 0) isEqual:@"t"] && table.activeColumn == 0 && table.currentEditor == nil, name(@"Shift-Tab in a cell being edited keeps the value"));
    [table selectRow:2 column:0 extending:NO];
    KeyWith(w, @"\r", 36, NSEventModifierFlagCommand);
    Expect(listener.posted.count == 1, name(@"Command-Return inserts from the table"));
    // What is being typed goes in when Insert is clicked, or with Command-Return.
    [table selectRow:0 column:0 extending:NO];
    Key(w, @"v", 9);
    [insert performClick:nil];
    Expect(listener.posted.count == 2 && [listener.posted.lastObject hasPrefix:@"\\left(\\begin{array}{ccc}v & "] && table.currentEditor == nil,
           name([@"Insert clicked while a cell is edited inserts what is typed: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    Key(w, @"w", 13);
    KeyWith(w, @"\r", 36, NSEventModifierFlagCommand);
    Expect(listener.posted.count == 3 && [listener.posted.lastObject hasPrefix:@"\\left(\\begin{array}{ccc}w & "] && [at(0, 0) isEqual:@"w"],
           name([@"Command-Return while a cell is edited inserts what is typed: " stringByAppendingString:listener.posted.lastObject ?: @"nothing"]));
    // Typing replaces; an arrow key keeps it and moves; Escape puts the value back.
    [table selectRow:1 column:1 extending:NO];
    Key(w, @"x", 7); Key(w, Arrow(NSRightArrowFunctionKey), 124);
    Expect([at(1, 1) isEqual:@"x"] && table.activeColumn == 2 && table.currentEditor == nil, name(@"typing replaces the value and an arrow key moves on"));
    Key(w, @"9", 25); Key(w, @"\x1b", 53);
    Expect([at(1, 2) isEqual:@"c"] && table.currentEditor == nil && w.firstResponder == table, name([@"Escape puts the value back: " stringByAppendingString:at(1, 2)]));
    // F2 and a double click edit the value: the arrow keys move in the text.
    Key(w, Arrow(NSF2FunctionKey), 120);
    Expect([table.currentEditor.string isEqual:@"c"] && table.currentEditor.selectedRange.location == 1 && table.currentEditor.selectedRange.length == 0, name(@"F2 edits the value, the caret at its end"));
    Key(w, Arrow(NSLeftArrowFunctionKey), 123); Key(w, @"d", 2); Key(w, @"\r", 36);
    Expect([at(1, 2) isEqual:@"dc"] && table.activeRow == 2, name([@"the arrow keys move in a cell being edited: " stringByAppendingString:at(1, 2)]));
    [table selectRow:1 column:2 extending:NO];
    KeyWith(w, @"u", 32, NSEventModifierFlagControl);
    Expect([table.currentEditor.string isEqual:@"dc"], name(@"Control-U edits the value"));
    Key(w, @"\x1b", 53);

    // Arrow keys, Shift, Command; going past the last column adds one.
    [table selectRow:0 column:0 extending:NO];
    KeyWith(w, Arrow(NSRightArrowFunctionKey), 124, NSEventModifierFlagShift); KeyWith(w, Arrow(NSDownArrowFunctionKey), 125, NSEventModifierFlagShift);
    Expect(NSEqualRanges(table.selectedRows, NSMakeRange(0, 2)) && NSEqualRanges(table.selectedColumns, NSMakeRange(0, 2)) && table.activeRow == 0 && table.activeColumn == 0, name(@"Shift and the arrow keys choose a range"));
    KeyWith(w, Arrow(NSRightArrowFunctionKey), 124, NSEventModifierFlagCommand);
    Expect(table.activeColumn == 2 && table.selectedColumns.length == 1, name(@"Command-Right goes to the last column inserted"));
    [table selectRow:0 column:panel.gridColumns - 1 extending:NO];
    NSInteger columns = panel.gridColumns;
    Key(w, Arrow(NSRightArrowFunctionKey), 124);
    Expect(columns == 999 ? panel.gridColumns == 999 : panel.gridColumns == columns + 1, name(@"going past the last column adds one, up to 999"));

    // What was typed in a cell is undone as a change of the table.
    CloseUndoGroups(w.undoManager);
    [table selectRow:2 column:2 extending:NO];
    Key(w, @"q", 12); Key(w, @"\r", 36);
    Expect([at(2, 2) isEqual:@"q"], name(@"q typed"));
    CloseUndoGroups(w.undoManager);
    [w.undoManager undo];
    Expect([at(2, 2) isEqual:@"0"] && w.firstResponder == table, name([@"Undo takes back what was typed in a cell: " stringByAppendingString:at(2, 2)]));
    CloseUndoGroups(w.undoManager);
    [w.undoManager redo];
    Expect([at(2, 2) isEqual:@"q"], name(@"Redo types it again"));
    // Delete empties the cells chosen; Undo and Redo.
    [table selectRows:NSMakeRange(1, 1) columns:NSMakeRange(0, 2)];
    CloseUndoGroups(w.undoManager);
    Key(w, @"\x7f", 51);
    Expect([at(1, 0) isEqual:@""] && [at(1, 1) isEqual:@""] && [at(1, 2) isEqual:@"dc"], name(@"Delete empties the cells chosen"));
    CloseUndoGroups(w.undoManager);
    [w.undoManager undo];
    Expect([at(1, 0) isEqual:@"t"] && [at(1, 1) isEqual:@"x"], name([NSString stringWithFormat:@"Undo puts them back (%@, %@)", at(1, 0), at(1, 1)]));
    CloseUndoGroups(w.undoManager);
    [w.undoManager redo];
    Expect([at(1, 0) isEqual:@""], name(@"Redo empties them again"));
    Expect(w.undoManager == [panel windowWillReturnUndoManager:w], name(@"the panel has its own undo"));

    // Copy and paste tab separated text, as spreadsheets do.
    CloseUndoGroups(w.undoManager);
    [panel setValues:@[@[@"1", @"2"], @[@"3", @"a\tb"]] atRow:0 shownColumn:0];
    [table selectRows:NSMakeRange(0, 2) columns:NSMakeRange(0, 2)];
    [table copy:nil];
    Expect([[table.pasteboard stringForType:NSPasteboardTypeString] isEqual:@"1\t2\n3\t\"a\tb\""], name([@"Copy gives tab separated text: " stringByAppendingString:[table.pasteboard stringForType:NSPasteboardTypeString] ?: @"nothing"]));
    [table selectRow:4 column:1 extending:NO];
    CloseUndoGroups(w.undoManager);
    [table paste:nil];
    Expect([at(4, 1) isEqual:@"1"] && [at(4, 2) isEqual:@"2"] && [at(5, 1) isEqual:@"3"] && [at(5, 2) isEqual:@"a\tb"] && NSEqualRanges(table.selectedRows, NSMakeRange(4, 2)) && NSEqualRanges(table.selectedColumns, NSMakeRange(1, 2)),
           name(@"Paste puts the cells in place and chooses them"));
    [table.pasteboard clearContents];
    [table.pasteboard setString:@"p\t\"q\"\"r\"\r\ns\r\n" forType:NSPasteboardTypeString];
    [table selectRow:6 column:0 extending:NO];
    CloseUndoGroups(w.undoManager);
    [table paste:nil];
    Expect([at(6, 0) isEqual:@"p"] && [at(6, 1) isEqual:@"q\"r"] && [at(7, 0) isEqual:@"s"], name(@"Paste reads quotes and Windows line ends"));
    [table.pasteboard clearContents];
    [table.pasteboard setString:@"7" forType:NSPasteboardTypeString];
    [table selectRows:NSMakeRange(8, 2) columns:NSMakeRange(0, 2)];
    CloseUndoGroups(w.undoManager);
    [table paste:nil];
    Expect([at(8, 0) isEqual:@"7"] && [at(9, 1) isEqual:@"7"], name(@"one value fills the range chosen"));
    CloseUndoGroups(w.undoManager);
    [w.undoManager undo];
    Expect([at(8, 0) isEqual:@"0"] && [at(9, 1) isEqual:@"0"], name(@"Undo takes a paste back"));
    [table selectRows:NSMakeRange(4, 1) columns:NSMakeRange(1, 1)];
    CloseUndoGroups(w.undoManager);
    [table cut:nil];
    Expect([at(4, 1) isEqual:@""] && [[table.pasteboard stringForType:NSPasteboardTypeString] isEqual:@"1"], name(@"Cut copies and empties"));
    // Empty cells are copied and pasted as they are, also at the end.
    [panel setValues:@[@[@"OLD", @"OLD", @""], @[@"OLD", @"x", @""]] atRow:10 shownColumn:0];
    [table selectRows:NSMakeRange(10, 1) columns:NSMakeRange(2, 1)];
    [table copy:nil];
    [table selectRow:10 column:0 extending:NO];
    CloseUndoGroups(w.undoManager);
    [table paste:nil];
    Expect([at(10, 0) isEqual:@""], name([@"an empty cell pasted empties the cell: " stringByAppendingString:at(10, 0)]));
    [table selectRows:NSMakeRange(10, 2) columns:NSMakeRange(2, 1)];
    [table copy:nil];
    [table selectRow:10 column:1 extending:NO];
    [table paste:nil];
    Expect([at(10, 1) isEqual:@""] && [at(11, 1) isEqual:@""], name(@"a range ending with an empty cell is pasted whole"));
    [table.pasteboard clearContents];
    [table.pasteboard setString:@"t\tu" forType:NSPasteboardTypeString];
    [table selectRow:11 column:0 extending:NO];
    [table paste:nil];
    Expect([at(11, 0) isEqual:@"t"] && [at(11, 1) isEqual:@"u"], name(@"text from other applications is pasted after a copy in the panel"));
    // Clear, Identity and Zero can be undone.
    NSMatrix *modify = [panel valueForKey:@"matmod"];
    CloseUndoGroups(w.undoManager);
    [modify selectCellWithTag:2]; [panel resetMatrix:modify];
    Expect([at(0, 0) isEqual:@"0"], name(@"Zero"));
    CloseUndoGroups(w.undoManager);
    [w.undoManager undo];
    Expect([at(0, 0) isEqual:@"1"], name(@"Undo takes Zero back"));

    // Clicks: a cell, Shift, a double click; the header of a column; only the row numbers drag rows.
    [w makeFirstResponder:table];
    Click(table, tc(1), 2, 1, 0);
    Expect(table.activeRow == 2 && table.activeColumn == 1 && table.currentEditor == nil, name(@"a click chooses a cell"));
    Click(table, tc(2), 3, 1, NSEventModifierFlagShift);
    Expect(table.activeRow == 2 && table.activeColumn == 1 && NSEqualRanges(table.selectedRows, NSMakeRange(2, 2)) && NSEqualRanges(table.selectedColumns, NSMakeRange(1, 2)), name(@"Shift-click chooses a range"));
    Click(table, tc(0), 1, 2, 0);
    Expect(table.currentEditor != nil && table.activeRow == 1 && table.activeColumn == 0, name(@"a double click edits the cell"));
    Click(table, tc(1), 1, 1, 0);
    Expect(table.currentEditor == nil && table.activeColumn == 1, name(@"a click elsewhere ends editing"));
    [table.delegate tableView:table didClickTableColumn:table.matrixColumns[2]];
    Expect(NSEqualRanges(table.selectedColumns, NSMakeRange(2, 1)) && table.selectedRows.length == (NSUInteger)panel.gridRows, name(@"a click on a column header chooses the column"));
    [table.delegate tableView:table didClickTableColumn:table.tableColumns[0]];
    Expect(table.selectedColumns.length == (NSUInteger)panel.gridColumns && table.selectedRows.length == (NSUInteger)panel.gridRows, name(@"a click above the row numbers chooses every cell"));
    NSRect numberCell = [table frameOfCellAtColumn:0 row:2], valueCell = [table frameOfCellAtColumn:tc(0) row:2];
    NSIndexSet *two = [NSIndexSet indexSetWithIndex:2];
    Expect([table canDragRowsWithIndexes:two atPoint:NSMakePoint(NSMidX(numberCell), NSMidY(numberCell))] && ![table canDragRowsWithIndexes:two atPoint:NSMakePoint(NSMidX(valueCell), NSMidY(valueCell))],
           name(@"rows are dragged by their numbers only"));
    Expect(table.verticalMotionCanBeginDrag, name(@"a row number can be dragged up or down"));

    // The order and widths of the columns are kept, also of columns added later.
    {
        NSTextField *cf = [panel valueForKey:@"htf"];
        cf.integerValue = 14; [panel resizeMatrix:cf];
        NSInteger index = [table columnWithIdentifier:@"13"];
        [table moveColumn:index toColumn:[table.tableColumns indexOfObject:table.matrixColumns[0]]];
        table.matrixColumns[0].width = 137;
        NSWindow *w2 = nil;
        TSMatrixPanelController *again = Load(TSMatrixPanelController.class, path, &w2);
        TSMatrixTableView *table2 = [again valueForKey:@"matrixtable"];
        Expect([table2.matrixColumns[0].identifier isEqual:@"13"] && table2.matrixColumns[0].width == 137 && [table2.matrixColumns[1].identifier isEqual:table.matrixColumns[1].identifier],
               name([NSString stringWithFormat:@"a panel made again keeps the 14th column first, 137 wide (%@, %.0f)", table2.matrixColumns[0].identifier, table2.matrixColumns[0].width]));
        Expect([table2.tableColumns[0].identifier isEqual:TSMatrixRowNumberColumn], name(@"the row numbers stay first"));
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"MatrixPanelColumns"];
    }

    // The fields for other delimiters keep what was typed when they are turned off.
    NSMatrix *open = [panel valueForKey:@"brselop"], *environment = [panel valueForKey:@"envsel"];
    NSTextField *other = [panel valueForKey:@"brtfop"];
    [open selectCellWithTag:5]; [panel brselChange:open];
    Expect(other.isEnabled, name(@"the field for another delimiter is on with its choice"));
    [w makeFirstResponder:other]; Key(w, @"z", 6);
    [open selectCellWithTag:0]; [panel brselChange:open];
    Expect(!other.isEnabled && [other.stringValue isEqual:@"z"], name([@"another choice turns the field off and keeps what was typed: " stringByAppendingString:other.stringValue]));
    [environment selectCellWithTag:1]; [panel envselChange:environment];
    [environment selectCellWithTag:0]; [panel envselChange:environment];
    Expect(!other.isEnabled && [other.stringValue isEqual:@"z"], name(@"going to tabular and back leaves the field off while its choice is not chosen"));
    [open selectCellWithTag:5]; [panel brselChange:open];
    Expect(other.isEnabled && [other.stringValue isEqual:@"z"], name(@"choosing it again turns the field on with what was typed"));
    [w makeFirstResponder:other]; Key(w, @"y", 16);
    [environment selectCellWithTag:1]; [panel envselChange:environment];
    Expect(!other.isEnabled && [other.stringValue hasSuffix:@"y"], name([@"tabular keeps what is being typed: " stringByAppendingString:other.stringValue]));
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
    CheckNoPlaceholders(w, language, name(@"on every page"));
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
        if ([parts[0] isEqual:@"Base"]) CheckMatrixSpreadsheet(parts[0], parts[1], listener);
        for (NSNumber *hover in @[@YES, @NO]) CheckLaTeXPanel(parts[0], parts[2], listener, hover.boolValue);
    }
    if (failures) { printf("FAIL: %d problems\n", failures); return 1; }
    printf("PASS: in %d languages the Matrix panel inserts what it did, numbers its rows without a ruler, starts its rows below the header, makes Insert the default button and its table works like a spreadsheet, and the LaTeX panel shows its groups with segmented controls, posts what it did, names its custom buttons and draws its symbols in the color of text\n", argc - 1);
} return 0; }
