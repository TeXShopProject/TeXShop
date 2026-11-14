// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSKeyBindingsController.h"
#import "GlobalData.h"
#import "globals.h"
#import "TSMarkMenu.h"

static NSPasteboardType const TSKeyBindingRowType = @"org.texshop.key-binding-row";
static NSString *const TSKeyBindingMark = @"•";
static NSString *const TSKeyBindingKeyColumn = @"key";
static NSString *const TSKeyBindingOutputColumn = @"output";
// Rows the list shows at least; a taller window shows more.
static const NSInteger TSKeyBindingMinimumRows = 6;

// Symbols shown as tokens, in the order Insert lists them. Line breaks and tabs
// are written to the file as themselves.
static NSArray<NSString *> *TSKeyBindingSymbols(void)
{
    return @[@"#SEL#", @"#INS#", @"#PASTE#", @"\n", @"\t", TSKeyBindingMark];
}

static NSString *TSKeyBindingSymbolTitle(NSString *symbol)
{
    if ([symbol isEqualToString:@"#SEL#"]) return NSLocalizedString(@"Selected Text", @"Key binding token for #SEL#");
    if ([symbol isEqualToString:@"#INS#"]) return NSLocalizedString(@"Insertion Point", @"Key binding token for #INS#: where the insertion point is placed after the output");
    if ([symbol isEqualToString:@"#PASTE#"]) return NSLocalizedString(@"Clipboard Text", @"Key binding token for #PASTE#");
    if ([symbol isEqualToString:@"\n"]) return NSLocalizedString(@"Line Break", @"Key binding token for a line break in the output");
    if ([symbol isEqualToString:@"\t"]) return NSLocalizedString(@"Tab", @"Key binding token for a tab in the output");
    return NSLocalizedString(@"Mark", @"Key binding token for •");
}

static NSFont *TSKeyBindingKeyFont(void) { return [NSFont systemFontOfSize:NSFont.systemFontSize]; }
static NSFont *TSKeyBindingOutputFont(void) { return [NSFont monospacedSystemFontOfSize:NSFont.systemFontSize - 1 weight:NSFontWeightRegular]; }

// A symbol shown as a rounded token. The file text is kept in `symbol`.
@interface TSKeyBindingToken : NSTextAttachment
@property (copy) NSString *symbol;
@end
@implementation TSKeyBindingToken
@end

static NSAttributedString *TSKeyBindingTokenString(NSString *symbol, NSFont *font)
{
    NSString *title = TSKeyBindingSymbolTitle(symbol);
    NSFont *labelFont = [NSFont systemFontOfSize:round(font.pointSize * 0.85)];
    NSSize textSize = [title sizeWithAttributes:@{NSFontAttributeName: labelFont}];
    CGFloat height = ceil(font.ascender - font.descender) + 2;
    NSSize size = NSMakeSize(ceil(textSize.width) + 14, height);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSRect pill = NSInsetRect(rect, 1.5, 0.5);
        CGFloat radius = NSHeight(pill) / 2;
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:radius yRadius:radius];
        [[NSColor.controlAccentColor colorWithAlphaComponent:0.16] setFill];
        [path fill];
        [[NSColor.controlAccentColor colorWithAlphaComponent:0.55] setStroke];
        path.lineWidth = 1;
        [path stroke];
        [title drawAtPoint:NSMakePoint(7, floor((NSHeight(rect) - textSize.height) / 2))
            withAttributes:@{NSFontAttributeName: labelFont, NSForegroundColorAttributeName: NSColor.labelColor}];
        return YES;
    }];
    image.accessibilityDescription = title;
    TSKeyBindingToken *token = [TSKeyBindingToken new];
    token.symbol = symbol;
    token.image = image;
    token.bounds = NSMakeRect(0, floor(font.descender) - 1, size.width, size.height);
    NSMutableAttributedString *string = [[NSAttributedString attributedStringWithAttachment:token] mutableCopy];
    [string addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, string.length)];
    return string;
}

@interface TSKeyBindingsTableView : NSTableView
@property (weak) TSKeyBindingsController *bindings;
@end

// Edits an output string: copying writes the file text (#SEL#, line breaks),
// pasting and dropping text show its symbols as tokens, and Option-Return and
// Option-Tab insert a line break or a tab.
@interface TSKeyBindingFieldEditor : NSTextView
- (void)insertOutput:(NSString *)output;
@end

@implementation TSKeyBindingFieldEditor
- (void)insertOutput:(NSString *)output
{
    NSAttributedString *text = [TSKeyBindingsController displayStringForOutput:output font:TSKeyBindingOutputFont()];
    NSRange range = self.selectedRange;
    if (![self shouldChangeTextInRange:range replacementString:text.string]) return;
    [self.textStorage replaceCharactersInRange:range withAttributedString:text];
    [self didChangeText];
    self.selectedRange = NSMakeRange(range.location + text.length, 0);
}
- (void)insertNewlineIgnoringFieldEditor:(id)sender { [self insertOutput:@"\n"]; }
- (void)insertTabIgnoringFieldEditor:(id)sender { [self insertOutput:@"\t"]; }
- (NSArray<NSPasteboardType> *)writablePasteboardTypes { return @[NSPasteboardTypeString]; }
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard type:(NSPasteboardType)type
{
    if (![type isEqualToString:NSPasteboardTypeString]) return NO;
    NSMutableString *text = [NSMutableString string];
    for (NSValue *range in self.selectedRanges)
        [text appendString:[TSKeyBindingsController outputForDisplayString:(NSAttributedString *)[self.textStorage attributedSubstringFromRange:range.rangeValue]]];
    return [pasteboard setString:text forType:NSPasteboardTypeString];
}
- (NSArray<NSPasteboardType> *)readablePasteboardTypes { return @[NSPasteboardTypeString]; }
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pasteboard type:(NSPasteboardType)type
{
    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text == nil) return NO;
    [self insertOutput:text];
    return YES;
}
@end

@interface TSKeyBindingOutputCell : NSTextFieldCell
@end

@implementation TSKeyBindingOutputCell
- (NSTextView *)fieldEditorForView:(NSView *)controlView
{
    static TSKeyBindingFieldEditor *editor;
    if (editor == nil) { editor = [[TSKeyBindingFieldEditor alloc] initWithFrame:NSZeroRect]; editor.fieldEditor = YES; }
    return editor;
}
@end

@interface TSKeyBindingsController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate, NSMenuItemValidation>
@property (strong) NSMutableArray<NSString *> *mutableKeys;
@property (strong) NSMutableArray<NSString *> *mutableValues;
@property (strong, readwrite) NSTableView *tableView;
@property (strong, readwrite) NSPopUpButton *insertButton;
@property (strong, readwrite) NSButton *symbolsButton;
@property (strong) NSSegmentedControl *addRemoveControl;
@property (strong, nullable) NSPopover *symbolsPopover;
@end

@implementation TSKeyBindingsTableView
- (void)keyDown:(NSEvent *)event
{
    NSString *characters = event.charactersIgnoringModifiers;
    unichar c = characters.length ? [characters characterAtIndex:0] : 0;
    BOOL plain = (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl)) == 0;
    if (plain && (c == NSDeleteCharacter || c == NSBackspaceCharacter || c == NSDeleteFunctionKey) && self.selectedRowIndexes.count) {
        [self.bindings delete:self];
        return;
    }
    if (plain && (c == NSCarriageReturnCharacter || c == NSEnterCharacter) && self.selectedRowIndexes.count == 1) {
        [self editColumn:0 row:self.selectedRow withEvent:nil select:YES];
        return;
    }
    [super keyDown:event];
}
@end

// An input character as TSTextView compares it: one UTF-16 unit, composed.
static NSString *TSKeyBindingInputCharacter(NSString *text)
{
    return text.precomposedStringWithCanonicalMapping;
}

@implementation TSKeyBindingsController

+ (NSAttributedString *)displayStringForOutput:(NSString *)output font:(NSFont *)font
{
    NSMutableAttributedString *result = [NSMutableAttributedString new];
    NSDictionary *attributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: NSColor.labelColor};
    NSMutableString *run = [NSMutableString string];
    NSUInteger index = 0, length = output.length;
    while (index < length) {
        NSString *found = nil;
        for (NSString *symbol in TSKeyBindingSymbols()) {
            if (length - index >= symbol.length && [output compare:symbol options:NSLiteralSearch range:NSMakeRange(index, symbol.length)] == NSOrderedSame) { found = symbol; break; }
        }
        if (found) {
            if (run.length) { [result appendAttributedString:[[NSAttributedString alloc] initWithString:run attributes:attributes]]; [run setString:@""]; }
            [result appendAttributedString:TSKeyBindingTokenString(found, font)];
            index += found.length;
        } else {
            NSRange character = [output rangeOfComposedCharacterSequenceAtIndex:index];
            [run appendString:[output substringWithRange:character]];
            index = NSMaxRange(character);
        }
    }
    if (run.length) [result appendAttributedString:[[NSAttributedString alloc] initWithString:run attributes:attributes]];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    [result addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, result.length)];
    return result;
}

+ (NSString *)outputForDisplayString:(NSAttributedString *)text
{
    NSMutableString *output = [NSMutableString string];
    NSString *string = text.string;
    [text enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if ([value isKindOfClass:TSKeyBindingToken.class]) {
            for (NSUInteger i = 0; i < range.length; i++) [output appendString:((TSKeyBindingToken *)value).symbol];
        } else if (value == nil) {
            // Text, including an object replacement character without an
            // attachment, is kept as it is.
            [output appendString:[string substringWithRange:range]];
        } else {
            // An attachment from elsewhere has no text in the file; only its
            // own replacement character is left out.
            NSString *part = [string substringWithRange:range];
            [output appendString:[part stringByReplacingOccurrencesOfString:@"￼" withString:@""]];
        }
    }];
    return output;
}

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) return nil;
    _mutableKeys = [NSMutableArray array];
    _mutableValues = [NSMutableArray array];
    return self;
}

- (NSArray<NSString *> *)keys { return [self.mutableKeys copy]; }
- (NSArray<NSString *> *)values { return [self.mutableValues copy]; }

- (void)loadView
{
    // Settings takes the outer view without its constraints and pins the body
    // again; the body keeps its own layout.
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 260)];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *body = [[NSView alloc] initWithFrame:view.bounds];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.identifier = @"keybindings.body";
    [view addSubview:body];

    TSKeyBindingsTableView *table = [TSKeyBindingsTableView new];
    table.bindings = self;
    table.style = NSTableViewStyleFullWidth;
    table.usesAlternatingRowBackgroundColors = YES;
    table.rowHeight = 24;
    table.intercellSpacing = NSMakeSize(0, 0);
    table.gridStyleMask = NSTableViewGridNone;
    table.allowsMultipleSelection = YES;
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    table.accessibilityLabel = NSLocalizedString(@"Key Bindings", @"Key binding list");
    table.identifier = @"keybindings.table";
    NSTableColumn *key = [[NSTableColumn alloc] initWithIdentifier:TSKeyBindingKeyColumn];
    key.title = NSLocalizedString(@"Input Character", @"Key binding column");
    // Wide enough for the column title in every language.
    key.width = MAX(110, ceil(key.headerCell.cellSize.width) + 16); key.minWidth = 70; key.maxWidth = 240;
    NSTableColumn *output = [[NSTableColumn alloc] initWithIdentifier:TSKeyBindingOutputColumn];
    output.title = NSLocalizedString(@"Output String", @"Key binding column");
    output.width = 420; output.minWidth = 160;
    [table addTableColumn:key];
    [table addTableColumn:output];
    table.dataSource = self;
    table.delegate = self;
    [table registerForDraggedTypes:@[TSKeyBindingRowType]];
    [table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    self.tableView = table;

    NSScrollView *scroll = [NSScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = table;
    scroll.identifier = @"keybindings.list";

    NSSegmentedControl *addRemove = [NSSegmentedControl segmentedControlWithImages:@[(NSImage *)[NSImage imageNamed:NSImageNameAddTemplate], (NSImage *)[NSImage imageNamed:NSImageNameRemoveTemplate]]
        trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(addOrRemove:)];
    addRemove.translatesAutoresizingMaskIntoConstraints = NO;
    addRemove.identifier = @"keybindings.add-remove";
    [addRemove setToolTip:NSLocalizedString(@"Add", @"Add a key binding") forSegment:0];
    [addRemove setToolTip:NSLocalizedString(@"Delete", @"Delete the selected key bindings") forSegment:1];
    [addRemove setWidth:28 forSegment:0];
    [addRemove setWidth:28 forSegment:1];
    self.addRemoveControl = addRemove;

    NSPopUpButton *insert = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    insert.translatesAutoresizingMaskIntoConstraints = NO;
    insert.identifier = @"keybindings.insert";
    [insert addItemWithTitle:NSLocalizedString(@"Insert", @"Key binding Insert menu")];
    for (NSString *symbol in TSKeyBindingSymbols()) {
        if ([symbol isEqualToString:@"\n"] || [symbol isEqualToString:TSKeyBindingMark]) [insert.menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:TSKeyBindingSymbolTitle(symbol) action:@selector(insertSymbol:) keyEquivalent:@""];
        item.target = self; item.representedObject = symbol;
        [insert.menu addItem:item];
    }
    NSMenuItem *note = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Mark with Note", @"Key binding Insert menu") action:@selector(insertSymbol:) keyEquivalent:@""];
    note.target = self; note.representedObject = [NSString stringWithFormat:@"%@‹›", TSKeyBindingMark];
    [insert.menu addItem:note];
    insert.menu.delegate = self;
    self.insertButton = insert;

    NSButton *help = [NSButton buttonWithTitle:@"" target:self action:@selector(showSymbols:)];
    help.translatesAutoresizingMaskIntoConstraints = NO;
    help.bezelStyle = NSBezelStyleHelpButton;
    help.identifier = @"keybindings.symbols";
    help.accessibilityLabel = NSLocalizedString(@"Symbols", @"Key binding symbols help button");
    help.toolTip = help.accessibilityLabel;
    self.symbolsButton = help;

    for (NSView *child in @[scroll, addRemove, insert, help]) [body addSubview:child];
    // At least six rows; a taller window gives the list, and the menu shortcut
    // list, more (TSShortcutPaneController shares the height between them).
    CGFloat minimum = TSKeyBindingMinimumRows * table.rowHeight + 28 + 2;
    NSLayoutConstraint *height = [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:minimum];
    NSLayoutConstraint *compact = [scroll.heightAnchor constraintEqualToConstant:minimum];
    compact.priority = 1;
    compact.active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [body.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [body.topAnchor constraintEqualToAnchor:view.topAnchor],
        [body.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [scroll.topAnchor constraintEqualToAnchor:body.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:body.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
        height,
        [addRemove.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:8],
        [addRemove.leadingAnchor constraintEqualToAnchor:body.leadingAnchor],
        [addRemove.bottomAnchor constraintEqualToAnchor:body.bottomAnchor],
        [insert.leadingAnchor constraintEqualToAnchor:addRemove.trailingAnchor constant:12],
        [insert.centerYAnchor constraintEqualToAnchor:addRemove.centerYAnchor],
        [help.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
        [help.centerYAnchor constraintEqualToAnchor:addRemove.centerYAnchor],
        [help.leadingAnchor constraintGreaterThanOrEqualToAnchor:insert.trailingAnchor constant:12]]];
    self.view = view;
    [self reloadFromGlobalData];
}

#pragma mark Model

- (void)reloadFromGlobalData
{
    GlobalData *data = [GlobalData sharedGlobalData];
    NSDictionary<NSString *, NSString *> *dictionary = data.g_autocompletionDictionary ?: @{};
    NSMutableArray *keys = [NSMutableArray array], *values = [NSMutableArray array];
    // The saved order first, then keys the order file does not know.
    for (NSString *key in data.g_autocompletionKeys ?: @[]) {
        if (![key isKindOfClass:NSString.class] || dictionary[key] == nil || [keys containsObject:key]) continue;
        [keys addObject:key]; [values addObject:(NSString *)dictionary[key]];
    }
    for (NSString *key in dictionary) {
        if ([keys containsObject:key]) continue;
        [keys addObject:key]; [values addObject:(NSString *)dictionary[key]];
    }
    self.mutableKeys = keys; self.mutableValues = values;
    [self.tableView reloadData];
    [self updateControls];
}

- (NSArray<NSString *> *)savedKeys
{
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in self.mutableKeys) if (key.length) [keys addObject:key];
    return keys;
}

- (NSArray<NSString *> *)savedValues
{
    NSMutableArray *values = [NSMutableArray array];
    [self.mutableKeys enumerateObjectsUsingBlock:^(NSString *key, NSUInteger i, BOOL *stop) { if (key.length) [values addObject:self.mutableValues[i]]; }];
    return values;
}

// The list as it is now is written at once and used by open documents.
- (void)save
{
    NSArray *keys = [self savedKeys], *values = [self savedValues];
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    [GlobalData sharedGlobalData].g_autocompletionDictionary = dictionary;
    [GlobalData sharedGlobalData].g_autocompletionKeys = keys;
    NSString *folder = [AutoCompletionPath stringByStandardizingPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    // Not atomic, as before: a linked file stays linked.
    BOOL written = [dictionary writeToFile:[folder stringByAppendingPathComponent:@"autocompletion.plist"] atomically:NO];
    written &= [keys writeToFile:[folder stringByAppendingPathComponent:@"autocompletionDisplayOrder.plist"] atomically:NO];
    if (!written) NSLog(@"TeXShop could not save the key bindings in %@", folder);
}

- (void)restoreKeys:(NSArray<NSString *> *)keys values:(NSArray<NSString *> *)values actionName:(NSString *)name
{
    NSArray *currentKeys = [self savedKeys], *currentValues = [self savedValues];
    self.mutableKeys = [keys mutableCopy]; self.mutableValues = [values mutableCopy];
    [self registerUndoToKeys:currentKeys values:currentValues actionName:name];
    [self.tableView reloadData];
    [self updateControls];
    [self save];
}

- (void)registerUndoToKeys:(NSArray<NSString *> *)keys values:(NSArray<NSString *> *)values actionName:(NSString *)name
{
    NSUndoManager *undo = self.viewIfLoaded.window.undoManager;
    if (undo == nil) return;
    [undo registerUndoWithTarget:self handler:^(TSKeyBindingsController *target) {
        [target restoreKeys:keys values:values actionName:name];
    }];
    [undo setActionName:name];
}

- (void)changeWithActionName:(NSString *)name change:(void (^)(void))change
{
    NSArray *keys = [self savedKeys], *values = [self savedValues];
    change();
    [self registerUndoToKeys:keys values:values actionName:name];
    [self updateControls];
    [self save];
}

#pragma mark Actions

- (void)addOrRemove:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment == 0) [self add:sender];
    else [self delete:sender];
}

- (IBAction)add:(id)sender
{
    NSTableView *table = self.tableView;
    [table.window makeFirstResponder:table];
    NSUInteger pending = [self.mutableKeys indexOfObject:@""];
    NSInteger row = pending != NSNotFound ? (NSInteger)pending : (table.selectedRowIndexes.count ? (NSInteger)table.selectedRowIndexes.lastIndex + 1 : (NSInteger)self.mutableKeys.count);
    if (pending == NSNotFound) {
        [self.mutableKeys insertObject:@"" atIndex:row];
        [self.mutableValues insertObject:@"" atIndex:row];
        [table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:row] withAnimation:NSTableViewAnimationEffectNone];
    }
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [table scrollRowToVisible:row];
    [table editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)delete:(id)sender
{
    NSTableView *table = self.tableView;
    [table.window makeFirstResponder:table];
    NSIndexSet *rows = table.selectedRowIndexes;
    if (rows.count == 0) { NSBeep(); return; }
    NSUInteger next = rows.firstIndex;
    [self changeWithActionName:NSLocalizedString(@"Delete Key Binding", @"Undo action name") change:^{
        [self.mutableKeys removeObjectsAtIndexes:rows];
        [self.mutableValues removeObjectsAtIndexes:rows];
        [table removeRowsAtIndexes:rows withAnimation:NSTableViewAnimationEffectNone];
    }];
    if (self.mutableKeys.count) [table selectRowIndexes:[NSIndexSet indexSetWithIndex:MIN(next, self.mutableKeys.count - 1)] byExtendingSelection:NO];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(delete:)) return self.tableView.selectedRowIndexes.count > 0;
    if (item.action == @selector(insertSymbol:)) return [self rowForInsertion] >= 0;
    return YES;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    for (NSMenuItem *item in menu.itemArray) if (item.action == @selector(insertSymbol:)) item.enabled = [self rowForInsertion] >= 0;
}

// The row whose output Insert changes: the output being edited, or the only
// selected row.
- (NSInteger)rowForInsertion
{
    NSTextField *field = [self editedField];
    if (field) return [self.tableView rowForView:field];
    return self.tableView.selectedRowIndexes.count == 1 ? self.tableView.selectedRow : -1;
}

- (nullable NSTextField *)editedField
{
    NSResponder *responder = self.tableView.window.firstResponder;
    if (![responder isKindOfClass:NSTextView.class] || !((NSTextView *)responder).isFieldEditor) return nil;
    id delegate = ((NSTextView *)responder).delegate;
    if (![delegate isKindOfClass:NSTextField.class] || ![delegate isDescendantOf:self.tableView]) return nil;
    return delegate;
}

- (IBAction)insertSymbol:(id)sender
{
    NSString *symbol = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    if (![symbol isKindOfClass:NSString.class]) symbol = [sender isKindOfClass:NSString.class] ? sender : nil;
    NSInteger row = [self rowForInsertion];
    if (symbol == nil || row < 0) { NSBeep(); return; }
    NSTextField *field = [self editedField];
    NSTextView *editor = nil;
    if (field && [self.tableView columnForView:field] == [self.tableView columnWithIdentifier:TSKeyBindingOutputColumn]) {
        editor = (NSTextView *)field.currentEditor;
    } else {
        [self.tableView scrollRowToVisible:row];
        [self.tableView editColumn:[self.tableView columnWithIdentifier:TSKeyBindingOutputColumn] row:row withEvent:nil select:NO];
        editor = (NSTextView *)[self editedField].currentEditor;
        editor.selectedRange = NSMakeRange(editor.string.length, 0);
    }
    if (![editor isKindOfClass:TSKeyBindingFieldEditor.class]) { NSBeep(); return; }
    [(TSKeyBindingFieldEditor *)editor insertOutput:symbol];
    // A mark with a note leaves the insertion point in the note.
    if ([symbol hasSuffix:@"›"]) editor.selectedRange = NSMakeRange(editor.selectedRange.location - 1, 0);
}

- (IBAction)showSymbols:(id)sender
{
    if (self.symbolsPopover.shown) { [self.symbolsPopover close]; return; }
    NSPopover *popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    NSViewController *content = [[NSViewController alloc] initWithNibName:nil bundle:nil];
    NSView *list = [self makeSymbolListView];
    list.frame = (NSRect){NSZeroPoint, list.fittingSize};
    content.view = list;
    content.preferredContentSize = list.frame.size;
    popover.contentViewController = content;
    self.symbolsPopover = popover;
    NSView *anchor = self.symbolsButton;
    [popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
}

- (NSView *)makeSymbolListView
{
    NSFont *font = TSKeyBindingOutputFont();
    NSTextField *(^heading)(NSString *) = ^NSTextField *(NSString *title) {
        NSTextField *label = [NSTextField labelWithString:title];
        label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
        label.textColor = NSColor.secondaryLabelColor;
        return label;
    };
    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray arrayWithObject:@[heading(NSLocalizedString(@"Display", @"Key binding symbols: how a symbol is shown")), heading(NSLocalizedString(@"Typed As", @"Key binding symbols: how a symbol is typed in an output string"))]];
    NSMutableArray<NSString *> *symbols = [TSKeyBindingSymbols() mutableCopy];
    [symbols addObject:[NSString stringWithFormat:@"%@‹%@›", TSKeyBindingMark, NSLocalizedString(@"note", @"Placeholder for the note of a mark: •‹note›")]];
    for (NSString *symbol in symbols) {
        NSTextField *shown = [NSTextField labelWithAttributedString:[TSKeyBindingsController displayStringForOutput:symbol font:font]];
        // Line breaks and tabs are typed with Option, as in other text fields.
        NSString *typed = [symbol isEqualToString:@"\n"] ? @"⌥↩" : ([symbol isEqualToString:@"\t"] ? @"⌥⇥" : symbol);
        NSTextField *written = [NSTextField labelWithString:typed];
        written.font = font;
        written.selectable = YES;
        [rows addObject:@[shown, written]];
    }
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 6; grid.columnSpacing = 18;
    grid.rowAlignment = NSGridRowAlignmentNone;
    for (NSInteger r = 0; r < grid.numberOfRows; r++) [grid rowAtIndex:r].yPlacement = NSGridCellPlacementCenter;
    [grid rowAtIndex:0].bottomPadding = 2;

    NSButton *marks = [NSButton buttonWithTitle:NSLocalizedString(@"How to Use Marks…", @"Edit › Mark") target:[TSMarkMenu sharedInstance] action:@selector(showMarkHelp:)];
    marks.bordered = NO;
    marks.attributedTitle = [[NSAttributedString alloc] initWithString:marks.title attributes:@{NSForegroundColorAttributeName: NSColor.linkColor, NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize]}];
    marks.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[grid, marks]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    stack.identifier = @"keybindings.symbol-list";
    // Leading alignment alone lets the fitting width cut the widest symbol.
    for (NSView *child in stack.arrangedSubviews)
        [stack.widthAnchor constraintGreaterThanOrEqualToAnchor:child.widthAnchor constant:stack.edgeInsets.left + stack.edgeInsets.right].active = YES;
    return stack;
}

- (void)updateControls
{
    NSUInteger selected = self.tableView.selectedRowIndexes.count;
    [self.addRemoveControl setEnabled:selected > 0 forSegment:1];
    self.insertButton.enabled = [self rowForInsertion] >= 0;
}

#pragma mark Editing

- (void)controlTextDidBeginEditing:(NSNotification *)notification { [self updateControls]; }

// An input character field holds one character: typing replaces it.
- (void)controlTextDidChange:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    if ([self.tableView columnForView:field] != [self.tableView columnWithIdentifier:TSKeyBindingKeyColumn]) return;
    NSTextView *editor = notification.userInfo[@"NSFieldEditor"];
    if (![editor isKindOfClass:NSTextView.class] || editor.hasMarkedText) return;
    NSString *text = editor.string;
    if (text.length == 0 || [text rangeOfComposedCharacterSequenceAtIndex:0].length == text.length) return;
    NSUInteger caret = editor.selectedRange.location;
    NSString *character = [text substringWithRange:[text rangeOfComposedCharacterSequenceAtIndex:caret > 0 ? MIN(caret, text.length) - 1 : 0]];
    editor.string = character;
    editor.selectedRange = NSMakeRange(character.length, 0);
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSInteger row = [self.tableView rowForView:field];
    if (row < 0 || (NSUInteger)row >= self.mutableKeys.count) return;
    if ([self.tableView columnForView:field] == [self.tableView columnWithIdentifier:TSKeyBindingKeyColumn])
        [self commitKey:field.stringValue row:row];
    else
        [self commitOutput:[TSKeyBindingsController outputForDisplayString:field.attributedStringValue] row:row];
    [self updateControls];
}

- (void)reloadRow:(NSInteger)row
{
    if (row < 0 || row >= self.tableView.numberOfRows) return;
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)self.tableView.numberOfColumns)]];
}

// A new row without an input character is dropped when nothing in it is being
// edited any more; it is never saved.
- (void)dropUnfinishedRowLater
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger row = [self.mutableKeys indexOfObject:@""];
        if (row == NSNotFound) return;
        NSTextField *field = [self editedField];
        if (field && [self.tableView rowForView:field] == (NSInteger)row) return;
        [self.mutableKeys removeObjectAtIndex:row];
        [self.mutableValues removeObjectAtIndex:row];
        [self.tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:row] withAnimation:NSTableViewAnimationEffectNone];
        [self updateControls];
    });
}

- (void)commitKey:(NSString *)typed row:(NSInteger)row
{
    NSString *old = self.mutableKeys[row];
    NSString *key = [typed isEqualToString:old] ? old : TSKeyBindingInputCharacter(typed);
    if ([key isEqualToString:old]) { if (key.length == 0) [self dropUnfinishedRowLater]; [self reloadRow:row]; return; }
    if (key.length > 1) {
        // Only a single character can start a key binding.
        NSBeep();
        if (old.length == 0) [self dropUnfinishedRowLater];
        [self reloadRow:row];
        return;
    }
    if (key.length == 0) {
        // An existing binding keeps its input character; Delete removes it.
        NSBeep();
        [self reloadRow:row];
        return;
    }
    NSUInteger other = NSNotFound;
    for (NSUInteger i = 0; i < self.mutableKeys.count; i++) if ((NSInteger)i != row && [self.mutableKeys[i] isEqualToString:key]) { other = i; break; }
    NSString *name = old.length ? NSLocalizedString(@"Change Key Binding", @"Undo action name") : NSLocalizedString(@"Add Key Binding", @"Undo action name");
    if (other == NSNotFound) {
        [self changeWithActionName:name change:^{ self.mutableKeys[row] = key; }];
        return;
    }
    [self confirmReplacingKey:key row:row other:other actionName:name];
}

- (void)confirmReplacingKey:(NSString *)key row:(NSInteger)row other:(NSUInteger)other actionName:(NSString *)name
{
    NSString *old = self.mutableKeys[row];
    void (^finish)(BOOL) = ^(BOOL replace) {
        if (replace) {
            [self changeWithActionName:name change:^{
                self.mutableKeys[row] = key;
                [self.mutableKeys removeObjectAtIndex:other];
                [self.mutableValues removeObjectAtIndex:other];
            }];
            [self.tableView reloadData];
            NSInteger kept = (NSInteger)other < row ? row - 1 : row;
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:kept] byExtendingSelection:NO];
        } else if (old.length == 0) {
            [self dropUnfinishedRowLater];
            [self reloadRow:row];
        } else {
            [self reloadRow:row];
        }
    };
    [self askToReplaceKey:key completion:finish];
}

- (void)askToReplaceKey:(NSString *)key completion:(void (^)(BOOL replace))completion
{
    NSWindow *window = self.tableView.window;
    if (window == nil) { completion(NO); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"Your current setting of %@ will be replaced. OK?", @"Your current setting of %@ will be replaced. OK?"), key];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) { completion(response == NSAlertFirstButtonReturn); }];
}

- (void)commitOutput:(NSString *)output row:(NSInteger)row
{
    NSString *old = self.mutableValues[row];
    if ([output isEqualToString:old] || self.mutableKeys[row].length == 0) {
        self.mutableValues[row] = output;
        // Symbols typed as text become tokens.
        [self reloadRow:row];
        if (self.mutableKeys[row].length == 0) [self dropUnfinishedRowLater];
        return;
    }
    [self changeWithActionName:NSLocalizedString(@"Change Key Binding", @"Undo action name") change:^{ self.mutableValues[row] = output; }];
    [self reloadRow:row];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)self.mutableKeys.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSString *identifier = column.identifier;
    BOOL output = [identifier isEqualToString:TSKeyBindingOutputColumn];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, column.width, tableView.rowHeight)];
        cell.identifier = identifier;
        NSTextField *field = [NSTextField new];
        if (output) field.cell = [[TSKeyBindingOutputCell alloc] initTextCell:@""];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.bordered = NO; field.drawsBackground = NO;
        field.editable = YES; field.selectable = YES;
        field.usesSingleLineMode = YES;
        field.cell.scrollable = YES;
        field.cell.wraps = NO;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        field.font = output ? TSKeyBindingOutputFont() : TSKeyBindingKeyFont();
        field.allowsEditingTextAttributes = output;
        field.importsGraphics = NO;
        field.delegate = self;
        field.accessibilityIdentifier = @"settings.user-data";
        field.identifier = output ? @"keybindings.output" : @"keybindings.key";
        [cell addSubview:field];
        cell.textField = field;
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
            [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
    }
    if (output) cell.textField.attributedStringValue = [TSKeyBindingsController displayStringForOutput:self.mutableValues[row] font:TSKeyBindingOutputFont()];
    else cell.textField.stringValue = self.mutableKeys[row];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateControls]; }

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    if (self.mutableKeys[row].length == 0) return nil;
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:TSKeyBindingRowType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (info.draggingSource != tableView) return NSDragOperationNone;
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    NSMutableIndexSet *moved = [NSMutableIndexSet indexSet];
    for (NSPasteboardItem *item in info.draggingPasteboard.pasteboardItems) {
        NSString *string = [item stringForType:TSKeyBindingRowType];
        if (string) [moved addIndex:(NSUInteger)string.integerValue];
    }
    if (moved.count == 0) return NO;
    NSUInteger target = (NSUInteger)MAX(row, 0) - [moved countOfIndexesInRange:NSMakeRange(0, (NSUInteger)MAX(row, 0))];
    NSIndexSet *destination = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(target, moved.count)];
    [self changeWithActionName:NSLocalizedString(@"Move Key Binding", @"Undo action name") change:^{
        NSArray *keys = [self.mutableKeys objectsAtIndexes:moved], *values = [self.mutableValues objectsAtIndexes:moved];
        [self.mutableKeys removeObjectsAtIndexes:moved]; [self.mutableValues removeObjectsAtIndexes:moved];
        [self.mutableKeys insertObjects:keys atIndexes:destination]; [self.mutableValues insertObjects:values atIndexes:destination];
    }];
    [tableView reloadData];
    [tableView selectRowIndexes:destination byExtendingSelection:NO];
    return YES;
}

@end
