// SPDX-License-Identifier: GPL-2.0-or-later
// The key binding list in Settings › Keyboard, in an unordered window. Key
// bindings are read from and written to a temporary folder only; copying and
// pasting use a private pasteboard; beeps are counted, not sounded.
#import "TestAppKitIsolation.h"
// The Paste boxes take the right end of the rows.
#define TS_TEST_STRIPE_END_INSET 120
#import "StripedRows.h"
#import "TSKeyBindingsController.h"
#import "GlobalData.h"
#import "globals.h"

@interface TSMarkMenu : NSObject @end
@implementation TSMarkMenu
+ (instancetype)sharedInstance { static TSMarkMenu *shared; if (shared == nil) shared = [self new]; return shared; }
- (void)showMarkHelp:(id)sender {}
@end

static NSUInteger beeps;
void TSTestBeep(void) { beeps++; }

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (ok) printf("PASS: %s\n", what.UTF8String);
    else { fprintf(stderr, "FAIL: %s\n", what.UTF8String); failures++; }
}

// Answers the replacement question as told, and remembers that it was asked.
@interface TestBindings : TSKeyBindingsController
@property BOOL answer;
@property (copy) NSString *asked;
@end
@implementation TestBindings
- (void)askToReplaceKey:(NSString *)key completion:(void (^)(BOOL))completion { self.asked = key; completion(self.answer); }
@end

@interface TestDrop : NSObject
@property (strong) NSPasteboard *draggingPasteboard;
@property (weak) id draggingSource;
@end
@implementation TestDrop
@end

static NSString *folder;
static NSDictionary *SavedBindings(void) { return [NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"autocompletion.plist"]]; }
static NSArray *SavedOrder(void) { return [NSArray arrayWithContentsOfFile:[folder stringByAppendingPathComponent:@"autocompletionDisplayOrder.plist"]]; }
static NSArray *SavedPaste(void) { return [NSArray arrayWithContentsOfFile:[folder stringByAppendingPathComponent:@"autocompletionPaste.plist"]]; }
static void Spin(void) { for (int i = 0; i < 3; i++) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; }
// The Paste box of a row.
static NSButton *PasteBox(NSTableView *table, NSInteger row)
{
    NSView *cell = [table viewAtColumn:[table columnWithIdentifier:@"paste"] row:row makeIfNecessary:YES];
    for (NSView *view in cell.subviews) if ([view isKindOfClass:NSButton.class]) return (NSButton *)view;
    return nil;
}
static void ClickBox(NSButton *box)
{
    box.state = box.state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
    [NSApp sendAction:box.action to:box.target from:box];
    Spin();
}
// Ends editing and finishes the event, as the application does, so each change
// is one step of Undo.
static void EndEditing(NSWindow *window, NSTableView *table) { [window makeFirstResponder:table]; Spin(); }
static NSUInteger Tokens(NSAttributedString *text)
{
    __block NSUInteger count = 0;
    [text enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) count += range.length; }];
    return count;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    AutoCompletionPath = folder;
    NSFont *font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    NSMutableArray<NSView *> *pending = nil;

    // Every bundled output, and line breaks, tabs, marks and partial symbols,
    // survive the tokens unchanged.
    NSDictionary *bundled = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];
    Check(bundled.count > 40, @"The bundled key bindings load");
    NSMutableArray *outputs = [bundled.allValues mutableCopy];
    [outputs addObjectsFromArray:@[@"\\begin{itemize}\n\t\\item #INS#\n\\end{itemize}", @"\\int_{•‹lower›}^{•‹upper›}", @"#SE", @"##SEL##", @"#PASTE#PASTE#", @"\r\n", @"", @"é😀#INS#", @"A\uFFFCB", @"\uFFFC#SEL#\uFFFC"]];
    BOOL roundTrip = YES;
    for (NSString *output in outputs)
        roundTrip &= [[TSKeyBindingsController outputForDisplayString:[TSKeyBindingsController displayStringForOutput:output font:font]] isEqualToString:output];
    Check(roundTrip, @"Every output string returns to its file text");
    NSAttributedString *shown = [TSKeyBindingsController displayStringForOutput:@"a#SEL#b#INS#\n\t#PASTE#•‹x›" font:font];
    Check(Tokens(shown) == 6 && [shown.string hasSuffix:@"‹x›"] && [shown.string hasPrefix:@"a"], @"Symbols, line breaks and tabs are tokens; notes stay text");

    // Rows: the saved order, then keys the order does not know; keys of
    // several characters from a file are shown.
    [GlobalData sharedGlobalData].g_autocompletionDictionary = @{@"^": @"^{#SEL##INS#}", @"_": @"_{#SEL##INS#}", @"\"": @"``#SEL##INS#''", @"ab": @"\\alpha\\beta", @"≡": @"\\equiv"};
    [GlobalData sharedGlobalData].g_autocompletionKeys = @[@"_", @"gone", @"^", @"ab"];
    TestBindings *bindings = [TestBindings new];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    NSView *view = bindings.view;
    [window.contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:10], [view.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-10], [view.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:10]]];
    [window.contentView layoutSubtreeIfNeeded];
    NSTableView *table = bindings.tableView;
    NSArray *order = bindings.keys;
    Check([[order subarrayWithRange:NSMakeRange(0, 3)] isEqual:(@[@"_", @"^", @"ab"])] && order.count == 5 && [order containsObject:@"≡"] && ![order containsObject:@"gone"], @"Rows follow the saved order, then the other keys");
    Check(table.numberOfRows == 5 && NSHeight(table.enclosingScrollView.frame) >= 6 * table.rowHeight + 28, @"The list shows at least six rows");
    // Striped rows, like the menu shortcut list below it, light and dark.
    for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSString *detail = nil;
        BOOL striped = table.selectedRowIndexes.count == 0 && TSTestRowsStriped(table, name, &detail);
        printf("STRIPES %s\n", detail.UTF8String);
        Check(striped, @"Neighboring rows have different backgrounds, light and dark");
    }
    NSTableCellView *cell = [table viewAtColumn:1 row:0 makeIfNecessary:YES];
    Check(Tokens(cell.textField.attributedStringValue) == 2, @"An output is shown with its tokens");
    Check(SavedBindings() == nil, @"Opening the list writes nothing");

    // Editing an output saves it at once, uses it at once and can be undone.
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [table editColumn:1 row:0 withEvent:nil select:NO];
    NSTextView *editor = (NSTextView *)window.firstResponder;
    Check([editor isKindOfClass:NSTextView.class] && editor.isFieldEditor && [NSStringFromClass(editor.class) isEqual:@"TSKeyBindingFieldEditor"], @"Outputs are edited in place with the key binding field editor");
    editor.selectedRange = NSMakeRange(editor.string.length, 0);
    [editor doCommandBySelector:@selector(insertNewlineIgnoringFieldEditor:)];
    [editor doCommandBySelector:@selector(insertTabIgnoringFieldEditor:)];
    [editor insertText:@"x" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check([SavedBindings()[@"_"] isEqual:@"_{#SEL##INS#}\n\tx"] && [[GlobalData sharedGlobalData].g_autocompletionDictionary[@"_"] isEqual:@"_{#SEL##INS#}\n\tx"], @"Option-Return and Option-Tab save a real line break and tab, at once");
    Check([SavedOrder() isEqual:order] && [SavedBindings()[@"ab"] isEqual:@"\\alpha\\beta"], @"The order and a key of two characters are saved as they were");
    Check(Tokens([[table viewAtColumn:1 row:0 makeIfNecessary:YES] textField].attributedStringValue) == 4, @"The line break and tab show as tokens");
    Check(window.undoManager.canUndo, @"The change can be undone");
    [window.undoManager undo];
    Check([SavedBindings()[@"_"] isEqual:@"_{#SEL##INS#}"] && [[GlobalData sharedGlobalData].g_autocompletionDictionary[@"_"] isEqual:@"_{#SEL##INS#}"], @"Undo restores and saves the previous output");
    [window.undoManager redo];
    Check([SavedBindings()[@"_"] isEqual:@"_{#SEL##INS#}\n\tx"], @"Redo saves the change again");
    [window.undoManager undo];

    // Symbols typed as text become tokens when editing ends.
    [table editColumn:1 row:2 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"\\alpha#INS#" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check([SavedBindings()[@"ab"] isEqual:@"\\alpha#INS#"] && Tokens([[table viewAtColumn:1 row:2 makeIfNecessary:YES] textField].attributedStringValue) == 1, @"A typed #INS# is saved as text and shown as a token");

    // Copying writes the file text; pasting shows its symbols as tokens.
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [table editColumn:1 row:1 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    Check([editor writeSelectionToPasteboard:pasteboard types:editor.writablePasteboardTypes] && [[pasteboard stringForType:NSPasteboardTypeString] isEqual:@"^{#SEL##INS#}"], @"Copying an output with tokens copies #SEL# and #INS#");
    [pasteboard clearContents];
    [pasteboard setString:@"\\frac{#SEL#}{#INS#}\n" forType:NSPasteboardTypeString];
    editor.selectedRange = NSMakeRange(0, editor.string.length);
    Check([editor readSelectionFromPasteboard:pasteboard type:NSPasteboardTypeString], @"Pasting is accepted");
    Check(Tokens(editor.textStorage) == 3, @"Pasted symbols and line breaks become tokens");
    EndEditing(window, table);
    Check([SavedBindings()[@"^"] isEqual:@"\\frac{#SEL#}{#INS#}\n"], @"A pasted output is saved as its file text");

    // A character U+FFFC without an attachment is text: it is shown, saved and
    // copied as it is. Only another application's attachment is left out.
    [table editColumn:1 row:1 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [pasteboard clearContents];
    [pasteboard setString:@"A\uFFFCB" forType:NSPasteboardTypeString];
    editor.selectedRange = NSMakeRange(0, editor.string.length);
    [editor readSelectionFromPasteboard:pasteboard type:NSPasteboardTypeString];
    EndEditing(window, table);
    Check([SavedBindings()[@"^"] isEqual:@"A\uFFFCB"], @"A pasted U+FFFC without an attachment is saved");
    [table editColumn:1 row:1 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    Check([editor writeSelectionToPasteboard:pasteboard types:editor.writablePasteboardTypes] && [[pasteboard stringForType:NSPasteboardTypeString] isEqual:@"A\uFFFCB"], @"Copying keeps a U+FFFC without an attachment");
    EndEditing(window, table);
    NSMutableAttributedString *foreign = [[NSMutableAttributedString alloc] initWithString:@"x"];
    [foreign appendAttributedString:[NSAttributedString attributedStringWithAttachment:[NSTextAttachment new]]];
    [foreign appendAttributedString:[[NSAttributedString alloc] initWithString:@"y\uFFFCz"]];
    Check([[TSKeyBindingsController outputForDisplayString:foreign] isEqual:@"xy\uFFFCz"], @"Another application's attachment is left out, a plain U+FFFC is kept");

    // Insert: the menu, an insertion at the end of the selected row, and a
    // mark with a note leaves the insertion point in the note.
    NSMutableArray *inserted = [NSMutableArray array];
    for (NSMenuItem *item in bindings.insertButton.menu.itemArray) if (item.representedObject) [inserted addObject:item.representedObject];
    Check([inserted isEqual:(@[@"#SEL#", @"#INS#", @"#PASTE#", @"\n", @"\t", @"•", @"•‹›"])], @"Insert lists the symbols, the line break, the tab and both marks");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
    NSMenuItem *note = bindings.insertButton.menu.itemArray.lastObject;
    [bindings insertSymbol:note];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"n" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    NSString *last = bindings.keys[4];
    Check([SavedBindings()[last] hasSuffix:@"•‹n›"], @"Insert › Mark with Note puts the insertion point in the note");

    // Input characters: one character; typing replaces it.
    [table editColumn:0 row:3 withEvent:nil select:NO];
    editor = (NSTextView *)window.firstResponder;
    editor.selectedRange = NSMakeRange(editor.string.length, 0);
    [editor insertText:@"€" replacementRange:editor.selectedRange];
    Check([editor.string isEqual:@"€"], @"Typing in an input character keeps only the new character");
    EndEditing(window, table);
    NSString *replacedRow = order[3];
    Check(SavedBindings()[@"€"] != nil && SavedBindings()[replacedRow] == nil, @"A new input character is saved in place of the old one");
    NSUInteger before = beeps;
    [table editColumn:0 row:3 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"😀" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check(beeps == before + 1 && [bindings.keys[3] isEqual:@"€"], @"A character the editor cannot receive alone is refused");
    [table editColumn:0 row:3 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check(beeps == before + 2 && [bindings.keys[3] isEqual:@"€"], @"An existing input character cannot be emptied");

    // A repeated input character asks first; Cancel changes nothing, OK
    // replaces the other row, and Undo brings it back.
    NSDictionary *saved = SavedBindings();
    bindings.answer = NO;
    [table editColumn:0 row:3 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"^" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check([bindings.asked isEqual:@"^"] && [SavedBindings() isEqual:saved] && [bindings.keys[3] isEqual:@"€"], @"Cancel keeps both rows");
    bindings.answer = YES; bindings.asked = nil;
    NSString *replacedOutput = SavedBindings()[@"€"];
    [table editColumn:0 row:3 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"^" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check([bindings.asked isEqual:@"^"] && [SavedBindings()[@"^"] isEqual:replacedOutput] && SavedBindings()[@"€"] == nil && bindings.keys.count == 4, @"OK replaces the other row");
    [window.undoManager undo];
    Check([SavedBindings() isEqual:saved], @"Undo restores both rows");

    // + adds an empty row and edits it; a row left without an input character
    // disappears and is never saved.
    NSUInteger rows = bindings.keys.count;
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [bindings add:nil];
    editor = (NSTextView *)window.firstResponder;
    Check(table.numberOfRows == (NSInteger)rows + 1 && table.selectedRow == 1 && [editor isKindOfClass:NSTextView.class] && [table columnForView:(NSView *)editor.delegate] == 0, @"+ adds a row below the selection and edits its input character");
    EndEditing(window, table);
    Spin();
    Check(table.numberOfRows == (NSInteger)rows && [SavedBindings() isEqual:saved], @"An empty row disappears unsaved");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [bindings add:nil];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"§" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Spin();
    Check([SavedBindings()[@"§"] isEqual:@""] && [SavedOrder()[1] isEqual:@"§"], @"A new input character is saved with an empty output");
    [window.undoManager undo];
    Check(SavedBindings()[@"§"] == nil && table.numberOfRows == (NSInteger)rows, @"Undo removes the added row");

    // − deletes the selected rows; Undo restores them.
    [table selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] byExtendingSelection:NO];
    [bindings delete:nil];
    Spin();
    Check(table.numberOfRows == (NSInteger)rows - 2 && SavedBindings().count == rows - 2, @"Delete removes the selected rows and saves");
    [window.undoManager undo];
    Check([SavedBindings() isEqual:saved] && table.numberOfRows == (NSInteger)rows, @"Undo restores the deleted rows");

    // Dragging a row moves it; the order is saved.
    TestDrop *drop = [TestDrop new];
    drop.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [drop.draggingPasteboard clearContents];
    NSPasteboardItem *item = (NSPasteboardItem *)[(id<NSTableViewDataSource>)bindings tableView:table pasteboardWriterForRow:0];
    [drop.draggingPasteboard writeObjects:@[item]];
    drop.draggingSource = table;
    NSString *moved = bindings.keys[0];
    Spin();
    Check([(id<NSTableViewDataSource>)bindings tableView:table acceptDrop:(id<NSDraggingInfo>)drop row:3 dropOperation:NSTableViewDropAbove] && [bindings.keys[2] isEqual:moved] && [SavedOrder()[2] isEqual:moved], @"Dragging moves a row and saves the order");

    // Paste: a third column of boxes. A row is checked as saved, unless its output
    // has a placeholder or a mark: then its box is off and dimmed.
    [window.undoManager removeAllActions];
    [GlobalData sharedGlobalData].g_autocompletionDictionary = @{@"¥": @"\\", @"≡": @"\\equiv", @"^": @"^{#SEL##INS#}", @"†": @"\\dag•‹n›", @"§": @"\\S"};
    [GlobalData sharedGlobalData].g_autocompletionKeys = @[@"¥", @"≡", @"^", @"†", @"§"];
    [GlobalData sharedGlobalData].g_autocompletionPasteKeys = @[@"¥", @"^", @"†", @"gone"];
    [bindings reloadFromGlobalData];
    // TS_KEY_BINDINGS_CAPTURE=<folder> saves the list, light and dark, to look at.
    NSString *capture = NSProcessInfo.processInfo.environment[@"TS_KEY_BINDINGS_CAPTURE"];
    for (NSAppearanceName name in capture.length ? @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua] : @[]) {
        window.appearance = [NSAppearance appearanceNamed:name];
        [window.contentView layoutSubtreeIfNeeded];
        NSView *shown = window.contentView;
        NSBitmapImageRep *rep = [shown bitmapImageRepForCachingDisplayInRect:shown.bounds];
        [shown cacheDisplayInRect:shown.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[capture stringByAppendingPathComponent:[NSString stringWithFormat:@"key-bindings-%@.png", name]] atomically:YES];
    }
    window.appearance = nil;
    NSTableColumn *pasteColumn = table.tableColumns.lastObject;
    Check(table.numberOfColumns == 3 && [pasteColumn.identifier isEqual:@"paste"] && pasteColumn.title.length > 0, @"The list has a Paste column");
    printf("COLUMNS %.0f %.0f %.0f of %.0f\n", NSMinX([table rectOfColumn:2]), NSMaxX([table rectOfColumn:2]), NSWidth([table rectOfColumn:1]), NSWidth(table.bounds));
    Check(NSMaxX([table rectOfColumn:2]) >= NSWidth(table.bounds) - 20 && NSWidth([table rectOfColumn:2]) < 100 && NSWidth([table rectOfColumn:0]) < 150, @"The Paste column keeps its width at the right end; the output column takes the rest");
    Check(PasteBox(table, 0).enabled && PasteBox(table, 0).state == NSControlStateValueOn && PasteBox(table, 1).enabled && PasteBox(table, 1).state == NSControlStateValueOff, @"Rows are checked as saved");
    BOOL dimmed = YES;
    for (NSInteger r = 2; r <= 3; r++) dimmed &= !PasteBox(table, r).enabled && PasteBox(table, r).state == NSControlStateValueOff;
    Check(dimmed, @"A row with #SEL#, #INS# or a mark has its box off and dimmed, also when the file checks it");
    // A check the file kept for a row with a placeholder is not taken: giving
    // the row an output without one leaves it unchecked.
    NSUInteger hat = [bindings.keys indexOfObject:@"^"];
    [table editColumn:1 row:(NSInteger)hat withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"\\hat" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check(PasteBox(table, (NSInteger)hat).enabled && PasteBox(table, (NSInteger)hat).state == NSControlStateValueOff && ![SavedPaste() containsObject:@"^"] && ![[GlobalData sharedGlobalData].pasteKeyBindings objectForKey:@"^"], @"A check left in the file for a row with a placeholder stays off when the placeholder is gone");
    [window.undoManager undo];
    // Checking saves at once and can be undone.
    ClickBox(PasteBox(table, 4));
    Check([SavedPaste() isEqual:(@[@"¥", @"§"])] && [[GlobalData sharedGlobalData].g_autocompletionPasteKeys isEqual:(@[@"¥", @"§"])] && [bindings.pasteKeys isEqual:(@[@"¥", @"§"])], @"Checking Paste saves the row at once, and drops the rows that cannot be checked");
    Check([[[GlobalData sharedGlobalData] pasteKeyBindings] isEqual:(@{@"¥": @"\\", @"§": @"\\S"})], @"Pasting uses the checked rows");
    Check([SavedBindings()[@"¥"] isEqual:@"\\"] && SavedBindings().count == 5, @"autocompletion.plist keeps its format");
    [window.undoManager undo];
    Check(PasteBox(table, 4).state == NSControlStateValueOff && ![SavedPaste() containsObject:@"§"], @"Undo takes the check away");
    [window.undoManager redo];
    Check([SavedPaste() containsObject:@"§"] && PasteBox(table, 4).state == NSControlStateValueOn, @"Redo checks it again");
    ClickBox(PasteBox(table, 4));
    Check(![SavedPaste() containsObject:@"§"], @"Unchecking saves at once");
    // While an output is typed, its box follows it; a placeholder kept when
    // editing ends drops the saved check, and Undo brings both back.
    [table editColumn:1 row:0 withEvent:nil select:NO];
    editor = (NSTextView *)window.firstResponder;
    editor.selectedRange = NSMakeRange(editor.string.length, 0);
    [editor insertText:@"#INS#" replacementRange:editor.selectedRange];
    Check(!PasteBox(table, 0).enabled && PasteBox(table, 0).state == NSControlStateValueOff && [SavedPaste() containsObject:@"¥"], @"Typing #INS# turns the box off at once");
    [editor insertText:@"" replacementRange:NSMakeRange(editor.string.length - 5, 5)];
    Check(PasteBox(table, 0).enabled && PasteBox(table, 0).state == NSControlStateValueOn, @"Taking it out again brings the box back");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [bindings insertSymbol:bindings.insertButton.menu.itemArray.lastObject];
    Check(!PasteBox(table, 0).enabled, @"Insert › Mark with Note turns the box off; Insert stays available");
    EndEditing(window, table);
    Check(![SavedPaste() containsObject:@"¥"] && [SavedBindings()[@"¥"] hasSuffix:@"•‹›"] && !PasteBox(table, 0).enabled, @"Saving an output with a mark drops its check");
    // The check is gone, not hidden: taking the mark out again leaves the row unchecked.
    [table editColumn:1 row:0 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [editor insertText:@"\\" replacementRange:editor.selectedRange];
    EndEditing(window, table);
    Check(PasteBox(table, 0).enabled && PasteBox(table, 0).state == NSControlStateValueOff && ![SavedPaste() containsObject:@"¥"], @"Taking the mark out after saving leaves the row unchecked");
    [window.undoManager undo];
    [window.undoManager undo];
    Check([SavedPaste() containsObject:@"¥"] && [SavedBindings()[@"¥"] isEqual:@"\\"] && PasteBox(table, 0).enabled && PasteBox(table, 0).state == NSControlStateValueOn, @"Undo restores the output and its check");
    // A pasted output with a placeholder counts the same.
    [table editColumn:1 row:0 withEvent:nil select:YES];
    editor = (NSTextView *)window.firstResponder;
    [pasteboard clearContents];
    [pasteboard setString:@"\\x{#PASTE#}" forType:NSPasteboardTypeString];
    [editor readSelectionFromPasteboard:pasteboard type:NSPasteboardTypeString];
    Check(!PasteBox(table, 0).enabled, @"A pasted #PASTE# turns the box off");
    EndEditing(window, table);
    Check(![SavedPaste() containsObject:@"¥"], @"and saving drops the check");
    [window.undoManager undo];
    // Moving keeps the check with its row; deleting removes it.
    drop.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [drop.draggingPasteboard writeObjects:@[(NSPasteboardItem *)[(id<NSTableViewDataSource>)bindings tableView:table pasteboardWriterForRow:0]]];
    [(id<NSTableViewDataSource>)bindings tableView:table acceptDrop:(id<NSDraggingInfo>)drop row:5 dropOperation:NSTableViewDropAbove];
    Check([bindings.keys.lastObject isEqual:@"¥"] && PasteBox(table, 4).state == NSControlStateValueOn && [SavedPaste() isEqual:(@[@"¥"])], @"A moved row keeps its check");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
    [bindings delete:nil];
    Check([SavedPaste() isEqual:@[]], @"Deleting a row removes its check");
    [window.undoManager undo];
    Check([SavedPaste() isEqual:(@[@"¥"])], @"Undo brings the check back");
    // When the checks cannot be saved, the list and pasting keep the saved ones.
    NSString *pastePath = [folder stringByAppendingPathComponent:@"autocompletionPaste.plist"];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0444} ofItemAtPath:pastePath error:NULL];
    NSUInteger equiv = [bindings.keys indexOfObject:@"≡"], beepsBefore = beeps;
    ClickBox(PasteBox(table, (NSInteger)equiv));
    Check(PasteBox(table, (NSInteger)equiv).state == NSControlStateValueOff && [[GlobalData sharedGlobalData].g_autocompletionPasteKeys isEqual:(@[@"¥"])] && [SavedPaste() isEqual:(@[@"¥"])] && beeps == beepsBefore + 1, @"A check that cannot be saved is not shown or used, and beeps");
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:pastePath error:NULL];
    // The note under the list.
    NSTextField *pasteNote = nil;
    pending = [NSMutableArray arrayWithObject:bindings.view];
    while (pending.count) { NSView *v = pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews]; if ([v.identifier isEqual:@"keybindings.paste-note"]) pasteNote = (NSTextField *)v; }
    Check(pasteNote && [pasteNote.stringValue containsString:pasteColumn.title] && NSMinY(pasteNote.frame) < NSMinY(bindings.insertButton.frame), @"A note under the list says what Paste does");

    // The symbol list names every symbol.
    NSView *list = [bindings makeSymbolListView];
    NSMutableArray *texts = [NSMutableArray array];
    pending = [NSMutableArray arrayWithObject:list];
    while (pending.count) { NSView *v = pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews]; if ([v isKindOfClass:NSTextField.class]) [texts addObject:((NSTextField *)v).stringValue]; }
    BOOL named = YES;
    for (NSString *typed in @[@"#SEL#", @"#INS#", @"#PASTE#", @"⌥↩", @"⌥⇥", @"•"]) named &= [texts containsObject:typed];
    Check(named, @"The symbol list shows how each symbol is typed");

    Check(!window.visible, @"No window was ordered");
    [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
    return failures ? 1 : 0;
} }
