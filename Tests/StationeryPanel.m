// File › New from Stationery (TSStationery), built offscreen in each language:
//   * the list shows the files of the folder, sorted without regard to case, without
//     .comment files, hidden files or folders, each with the text of its .comment file
//     on one line;
//   * Create is enabled only while a stationery is selected; Return and Escape are
//     Create and Cancel; a double click on a row opens it;
//   * the list is read again when the panel opens and when it becomes key, and the
//     selected file stays selected while it is there;
//   * Create opens the selected file as an untitled, edited document; when the file is
//     already open for editing, a second document is made from it and the open one keeps
//     its file;
//   * Show in Finder creates the folder if it is missing and opens it;
//   * + is enabled while a source document is in front; its sheet proposes the
//     document's name, refuses empty names and names with / or :, and adds the
//     document's text with its extension and the description as name.comment; a name
//     in use asks before replacing;
//   * - is enabled with a stationery selected, asks before moving it and its
//     .comment file to the Trash, and selects the next one;
//   * the actions menu at the bottom of the list duplicates the selected stationery and its
//     description as "name copy", "name copy 2" ..., and selects the copy; the contextual
//     menu does it for the row clicked;
//   * Space shows the selected stationery in Quick Look and hides it again; the preview
//     follows the selection and grows from the selected row;
//   * a description edited in the list is written to the .comment file (an empty one
//     removes it); while it is edited Return and Escape end the editing, not the panel;
//   * the title, the column titles and the buttons are translated and fit, with
//     Show in Finder at the left and Cancel and Create at the right, at the usual
//     and the smallest size of the panel.
// No window is ordered on screen, no sheet or alert is shown, no document is opened,
// nothing is opened in the Finder and nothing goes to the Trash (files are removed in the
// work folder); AppKit defaults stay in memory.
// Usage: StationeryPanel <work folder> <png folder or -> <language>=<Localizable.strings> ...
#import "TestAppKitIsolation.h"
#import "TSStationery.h"
#import "TSListBottomBar.h"
#import <Quartz/Quartz.h>

NSString *StationeryPath = @"~/Library/TeXShop/Stationery";

static int failures, checks;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) { failures++; printf("FAIL %s\n", what.UTF8String); } }

// Strings of the language under test.
static NSDictionary *Table;
static NSString *TestLocalized(id self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    if (table == nil || [table isEqualToString:@"Localizable"]) { NSString *s = Table[key]; if (s) return s; }
    return value.length ? value : key;
}

// Opening documents and the Finder are recorded, not done.
static NSMutableArray<NSURL *> *OpenedInWorkspace, *OpenedDocuments;
static BOOL TestOpenURL(id self, SEL _cmd, NSURL *url) { [OpenedInWorkspace addObject:url]; return YES; }
@interface FakeDocument : NSObject
@property (nonatomic) NSURL *fileURL;
@property BOOL fileURLWasSet;
@property NSInteger changes;
@property BOOL shown;
@end
@implementation FakeDocument
- (void)setFileURL:(NSURL *)url { _fileURL = url; self.fileURLWasSet = YES; }
- (void)updateChangeCount:(NSDocumentChangeType)change { if (change == NSChangeDone) self.changes++; }
- (BOOL)isSameFileAs:(NSURL *)url { return [self.fileURL.path isEqualToString:url.path]; }
- (void)makeWindowControllers {}
- (void)showWindows { self.shown = YES; }
@end
// Documents open in the application, and documents made from a file beside them.
static NSArray *OpenDocuments;
static NSMutableArray *MadeDocuments, *AddedDocuments;
static NSArray *TestDocuments(id self, SEL _cmd) { return OpenDocuments ?: @[]; }
static id TestDocumentForURL(id self, SEL _cmd, NSURL *url) { return nil; }
static NSString *TestTypeForURL(id self, SEL _cmd, NSURL *url, NSError **error) { return @"edu.uo.texshop.tex"; }
static id TestMakeDocument(id self, SEL _cmd, NSURL *url, NSString *type, NSError **error) {
    FakeDocument *made = [FakeDocument new];
    made.fileURL = url;
    [MadeDocuments addObject:made];
    return made;
}
static void TestAddDocument(id self, SEL _cmd, id document) { [AddedDocuments addObject:document]; }
static FakeDocument *LastDocument;
static id TestOpenDocument(id self, SEL _cmd, NSURL *url, BOOL display, NSError **error) {
    [OpenedDocuments addObject:url];
    LastDocument = [FakeDocument new];
    LastDocument.fileURL = url;
    return LastDocument;
}
static void TestNoKeyAndFront(id self, SEL _cmd, id sender) {}

// The front source document, behind a document that is not a source document.
@interface FakeSource : NSObject
@property NSURL *fileURL;
@property NSString *displayName;
@property NSTextView *textView;
@end
@implementation FakeSource @end
static id FrontDocument;
static NSArray *TestOrderedDocuments(id self, SEL _cmd) { return FrontDocument ? @[[NSObject new], FrontDocument] : @[]; }

// Sheets and alerts are recorded with their completion handler, not shown.
static NSWindow *LastSheet;
static void (^SheetHandler)(NSModalResponse);
static void TestBeginSheet(id self, SEL _cmd, NSWindow *sheet, void (^handler)(NSModalResponse)) { LastSheet = sheet; SheetHandler = handler; }
static NSAlert *LastAlert;
static void (^AlertHandler)(NSModalResponse);
static void TestAlertSheet(id self, SEL _cmd, NSWindow *window, void (^handler)(NSModalResponse)) { LastAlert = self; AlertHandler = handler; }

// Moving to the Trash removes the file in the work folder.
static NSString *WorkFolder;
static NSMutableArray<NSString *> *Trashed;
static BOOL TestTrash(id self, SEL _cmd, NSURL *url, NSURL **result, NSError **error) {
    if (![url.path hasPrefix:WorkFolder]) { printf("FAIL the Trash was asked for %s\n", url.path.UTF8String); exit(1); }
    [Trashed addObject:url.lastPathComponent];
    return [[NSFileManager defaultManager] removeItemAtURL:url error:error];
}
// Quick Look is recorded, not shown.
@interface FakeQuickLook : NSObject
@property (getter=isVisible) BOOL visible;
@property NSInteger reloads;
@property (weak) id dataSource, delegate;
@end
@implementation FakeQuickLook
- (void)makeKeyAndOrderFront:(id)sender { self.visible = YES; }
- (void)orderOut:(id)sender { self.visible = NO; }
- (void)reloadData { self.reloads++; }
@end
static FakeQuickLook *QuickLook;
static id TestSharedPreview(id self, SEL _cmd) { return QuickLook; }
static BOOL TestPreviewExists(id self, SEL _cmd) { return YES; }
static NSEvent *Key(NSString *characters, NSEventModifierFlags flags, unsigned short code) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil
                          characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
}
static NSString *Read(NSString *path) { return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]; }

static void Write(NSString *path, NSString *text) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static NSArray *Names(TSStationery *s) { return s.fullSourceData; }
static NSString *Selected(TSStationery *s) {
    NSInteger row = s.tableView.selectedRow;
    return row >= 0 ? s.fullSourceData[row] : nil;
}
static void Select(TSStationery *s, NSString *file) {
    NSUInteger row = [s.fullSourceData indexOfObject:file];
    [s.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}
static void All(NSView *v, NSMutableArray *out) { [out addObject:v]; for (NSView *c in v.subviews) All(c, out); }
static NSRect InContent(NSView *v) { return [v convertRect:v.bounds toView:v.window.contentView]; }

static void Behavior(NSString *work) {
    NSString *folder = [work stringByAppendingPathComponent:@"Stationery"];
    NSFileManager *fm = NSFileManager.defaultManager;
    Write([folder stringByAppendingPathComponent:@"b.tex"], @"b");
    Write([folder stringByAppendingPathComponent:@"A.tex"], @"a");
    Write([folder stringByAppendingPathComponent:@"A.comment"], @"  First line\nsecond line\n");
    Write([folder stringByAppendingPathComponent:@"c.md"], @"c");
    Write([folder stringByAppendingPathComponent:@"Old.COMMENT"], @"stray");
    Write([folder stringByAppendingPathComponent:@".DS_Store"], @"x");
    Write([folder stringByAppendingPathComponent:@"Folder/inside.tex"], @"x");

    TSStationery *s = [TSStationery new];
    s.folderPath = folder;
    NSPanel *panel = s.stationeryWindow;
    [s newFromStationery:nil];
    Check([Names(s) isEqualToArray:@[@"A.tex", @"b.tex", @"c.md"]], [NSString stringWithFormat:@"the list is the stationery files in order: %@", Names(s)]);
    Check([s.commentData isEqualToArray:@[@"First line second line", @"", @""]], [NSString stringWithFormat:@"the descriptions come from the .comment files on one line: %@", s.commentData]);
    Check(s.tableView.numberOfRows == 3, @"the table shows every stationery");
    NSTableCellView *cell = [s.tableView viewAtColumn:0 row:0 makeIfNecessary:YES];
    Check([cell.textField.stringValue isEqualToString:@"A"], @"the list shows the name without its extension");
    cell = [s.tableView viewAtColumn:1 row:0 makeIfNecessary:YES];
    Check([cell.textField.stringValue isEqualToString:@"First line second line"], @"the list shows the description");
    Check([Selected(s) isEqualToString:@"A.tex"], @"opening the panel selects the first stationery");
    Check(s.createButton.enabled, @"Create is enabled with a stationery selected");
    Check(panel.firstResponder == s.tableView, @"the list has the keyboard focus");
    Check([s.createButton.keyEquivalent isEqualToString:@"\r"], @"Return is Create");
    NSButton *cancel = nil;
    NSMutableArray *views = [NSMutableArray array]; All(panel.contentView, views);
    for (NSView *v in views) if ([v.identifier isEqual:@"stationery.cancel"]) cancel = (NSButton *)v;
    Check([cancel.keyEquivalent isEqualToString:@"\033"], @"Escape is Cancel");
    Check(s.tableView.doubleAction == NSSelectorFromString(@"openClickedRow:") && s.tableView.target == s, @"a double click on a row opens it");

    [s.tableView deselectAll:nil];
    Check(!s.createButton.enabled, @"Create is disabled with nothing selected");

    // Files added or removed in the Finder.
    Select(s, @"b.tex");
    Write([folder stringByAppendingPathComponent:@"0.tex"], @"0");
    Write([folder stringByAppendingPathComponent:@"0.comment"], @"Zero");
    [s windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:panel]];
    Check([Names(s) isEqualToArray:@[@"0.tex", @"A.tex", @"b.tex", @"c.md"]], @"a file added in the Finder shows when the panel becomes key");
    Check([s.commentData.firstObject isEqualToString:@"Zero"], @"its description shows too");
    Check([Selected(s) isEqualToString:@"b.tex"], @"the selected stationery stays selected after a new file comes");
    [fm removeItemAtPath:[folder stringByAppendingPathComponent:@"b.tex"] error:nil];
    [s windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:panel]];
    Check([Names(s) isEqualToArray:@[@"0.tex", @"A.tex", @"c.md"]], @"a file removed in the Finder leaves the list");
    Check(Selected(s) == nil && !s.createButton.enabled, @"when the selected file is gone, nothing is selected and Create is disabled");
    Write([folder stringByAppendingPathComponent:@"c.comment"], @"See");
    [s newFromStationery:nil];
    Check([s.commentData.lastObject isEqualToString:@"See"], @"opening the panel again reads the descriptions again");
    Check([Selected(s) isEqualToString:@"0.tex"], @"opening the panel again with nothing selected selects the first stationery");

    // Create.
    Select(s, @"A.tex");
    [s okForStationeryPanel:nil];
    Check(OpenedDocuments.count == 1 && [OpenedDocuments.firstObject.path isEqualToString:[folder stringByAppendingPathComponent:@"A.tex"]], @"Create opens the selected file");
    Check(LastDocument.fileURLWasSet && LastDocument.fileURL == nil && LastDocument.changes == 1, @"the new document is untitled and edited");
    // The same stationery open for editing.
    FakeDocument *editing = [FakeDocument new];
    editing.fileURL = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"A.tex"]];
    editing.fileURLWasSet = NO;
    OpenDocuments = @[editing];
    Select(s, @"A.tex");
    [s okForStationeryPanel:nil];
    FakeDocument *made = MadeDocuments.lastObject;
    Check(OpenedDocuments.count == 1 && MadeDocuments.count == 1 && [AddedDocuments isEqualToArray:@[made]] && made.shown, @"Create on a stationery open for editing makes a second document from the file");
    Check(made.fileURL == nil && made.changes == 1 && !editing.fileURLWasSet && editing.changes == 0, @"the second document is untitled and edited; the open one keeps its file");
    OpenDocuments = nil;
    [s.tableView deselectAll:nil];
    [s okForStationeryPanel:nil];
    Check(OpenedDocuments.count == 1, @"Create with nothing selected opens nothing");

    // Show in Finder.
    [s showStationeryInFinder:nil];
    Check(OpenedInWorkspace.count == 1 && [OpenedInWorkspace.firstObject.path isEqualToString:folder], @"Show in Finder opens the folder");
    NSString *missing = [work stringByAppendingPathComponent:@"Missing/Stationery"];
    TSStationery *empty = [TSStationery new];
    empty.folderPath = missing;
    [empty newFromStationery:nil];
    Check(empty.fullSourceData.count == 0 && !empty.createButton.enabled, @"with no folder the list is empty and Create is disabled");
    [empty showStationeryInFinder:nil];
    BOOL isDirectory = NO;
    Check([fm fileExistsAtPath:missing isDirectory:&isDirectory] && isDirectory, @"Show in Finder creates a missing folder");
    Check(OpenedInWorkspace.count == 2 && [OpenedInWorkspace.lastObject.path isEqualToString:missing], @"and opens it");
    Write([missing stringByAppendingPathComponent:@"New.tex"], @"n");
    [empty windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:empty.stationeryWindow]];
    Check([empty.fullSourceData isEqualToArray:@[@"New.tex"]], @"a stationery added to the new folder shows when the panel comes back");

    // + : the front document.
    FrontDocument = nil;
    [s newFromStationery:nil];
    Check(!s.plusButton.enabled, @"+ is disabled with no source document in front");
    FakeSource *source = [FakeSource new];
    source.fileURL = [NSURL fileURLWithPath:@"/Somewhere/Paper.ltx"];
    source.displayName = @"Paper.ltx";
    source.textView = [NSTextView new];
    source.textView.string = @"\\documentclass{article}\n% 日本語\n";
    FrontDocument = source;
    [s windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:panel]];
    Check(s.plusButton.enabled, @"+ is enabled with a source document in front");
    Check(s.plusButton.target == s && s.plusButton.action == @selector(addFrontDocument:) && s.minusButton.target == s && s.minusButton.action == @selector(removeSelectedStationery:), @"+ and - send their actions to the panel");
    [s addFrontDocument:nil];
    Check(LastSheet == s.addSheet && SheetHandler, @"+ shows the sheet on the panel");
    Check([s.addNameField.stringValue isEqualToString:@"Paper"] && s.addDescriptionField.stringValue.length == 0, @"the sheet proposes the name of the document");
    Check(s.addButton.enabled && [s.addButton.keyEquivalent isEqualToString:@"\r"], @"Add is enabled and is Return");
    for (NSString *bad in @[@"", @"  ", @"a/b", @"a:b", @".hidden"]) {
        s.addNameField.stringValue = bad;
        [s controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:s.addNameField]];
        Check(!s.addButton.enabled, [NSString stringWithFormat:@"Add is disabled for the name '%@'", bad]);
    }
    s.addNameField.stringValue = @"My Paper";
    s.addDescriptionField.stringValue = @"A paper\nwith notes";
    [s controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:s.addNameField]];
    Check(s.addButton.enabled, @"Add is enabled for a good name");
    SheetHandler(NSModalResponseCancel);
    Check(![fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"My Paper.ltx"]], @"Cancel adds nothing");
    SheetHandler(NSModalResponseOK);
    Check([Read([folder stringByAppendingPathComponent:@"My Paper.ltx"]) isEqualToString:source.textView.string], @"Add writes the document's text with its extension");
    Check([Read([folder stringByAppendingPathComponent:@"My Paper.comment"]) isEqualToString:@"A paper with notes"], @"and the description, on one line, as name.comment");
    Check([Selected(s) isEqualToString:@"My Paper.ltx"], @"the new stationery is selected");
    // The same name again.
    LastAlert = nil;
    source.textView.string = @"second";
    [s addFrontDocument:nil];
    s.addNameField.stringValue = @"my paper";
    s.addDescriptionField.stringValue = @"";
    SheetHandler(NSModalResponseOK);
    Check(LastAlert && [LastAlert.messageText containsString:@"my paper"] && LastAlert.buttons.count == 2 && LastAlert.buttons[0].hasDestructiveAction, @"a name in use asks before replacing");
    AlertHandler(NSAlertSecondButtonReturn);
    Check([Read([folder stringByAppendingPathComponent:@"My Paper.ltx"]) hasPrefix:@"\\documentclass"], @"Cancel keeps the stationery in use");
    AlertHandler(NSAlertFirstButtonReturn);
    Check(![fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"My Paper.ltx"]] || [[fm contentsOfDirectoryAtPath:folder error:nil] containsObject:@"my paper.ltx"], @"Replace moves the old stationery to the Trash");
    Check([Read([folder stringByAppendingPathComponent:@"my paper.ltx"]) isEqualToString:@"second"], @"and writes the new one");
    Check(![fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"my paper.comment"]], @"an empty description leaves no .comment file");
    source.fileURL = nil; source.displayName = @"Untitled 2";
    [s addFrontDocument:nil];
    Check([s.addNameField.stringValue isEqualToString:@"Untitled 2"], @"an untitled document proposes its window name");
    s.addNameField.stringValue = @"Untitled Note";
    SheetHandler(NSModalResponseOK);
    Check([fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"Untitled Note.tex"]], @"an untitled document is added as .tex");

    // - : asks, then moves the stationery and its description to the Trash.
    Select(s, @"A.tex");
    Check(s.minusButton.enabled, @"- is enabled with a stationery selected");
    LastAlert = nil;
    [s removeSelectedStationery:nil];
    Check(LastAlert && [LastAlert.messageText containsString:@"“A”"] && LastAlert.buttons.count == 2 && LastAlert.buttons[0].hasDestructiveAction, @"- asks before moving the stationery to the Trash");
    AlertHandler(NSAlertSecondButtonReturn);
    Check([fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"A.tex"]], @"Cancel keeps the stationery");
    NSUInteger before = [Names(s) indexOfObject:@"A.tex"];
    [Trashed removeAllObjects];
    AlertHandler(NSAlertFirstButtonReturn);
    Check([Trashed isEqualToArray:@[@"A.tex", @"A.comment"]] && ![Names(s) containsObject:@"A.tex"], [NSString stringWithFormat:@"the stationery and its description go to the Trash: %@", Trashed]);
    Check(s.tableView.selectedRow == (NSInteger)before, @"the next stationery is selected");
    [s.tableView deselectAll:nil];
    Check(!s.minusButton.enabled, @"- is disabled with nothing selected");

    // Duplicate.
    Select(s, @"0.tex");
    TSListBottomBar *bar = nil;
    for (NSView *v = s.plusButton; v; v = v.superview) if ([v isKindOfClass:TSListBottomBar.class]) bar = (TSListBottomBar *)v;
    NSMenu *actions = bar.actionsButton.menu;
    Check(bar && !bar.actionsButton.hidden && actions.delegate == (id)s, @"the bar has the actions menu");
    [actions.delegate menuNeedsUpdate:actions];
    NSMenuItem *duplicate = actions.itemArray.lastObject;
    Check(actions.numberOfItems == 2 && [duplicate.title containsString:@"0"] && [(id)s validateMenuItem:duplicate], @"the actions menu duplicates the selected stationery by name");
    [NSApp sendAction:duplicate.action to:duplicate.target from:duplicate];
    Check([Read([folder stringByAppendingPathComponent:@"0 copy.tex"]) isEqualToString:@"0"] && [Read([folder stringByAppendingPathComponent:@"0 copy.comment"]) isEqualToString:@"Zero"], @"Duplicate copies the stationery and its description");
    Check([Selected(s) isEqualToString:@"0 copy.tex"], @"the copy is selected");
    Select(s, @"0.tex");
    [actions.delegate menuNeedsUpdate:actions];
    duplicate = actions.itemArray.lastObject;
    [NSApp sendAction:duplicate.action to:duplicate.target from:duplicate];
    Check([Selected(s) isEqualToString:@"0 copy 2.tex"] && [fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"0 copy 2.comment"]], @"a second copy takes the next free name");
    Check([Read([folder stringByAppendingPathComponent:@"0 copy.tex"]) isEqualToString:@"0"], @"and leaves the first copy alone");
    [s.tableView deselectAll:nil];
    [actions.delegate menuNeedsUpdate:actions];
    Check(actions.numberOfItems == 1, @"with nothing selected the actions menu has no command");
    NSMenu *context = s.tableView.menu;
    [context.delegate menuNeedsUpdate:context];
    Check(context.numberOfItems == 0, @"the contextual menu of no row is empty");
    for (NSString *copy in @[@"0 copy.tex", @"0 copy.comment", @"0 copy 2.tex", @"0 copy 2.comment"]) [fm removeItemAtPath:[folder stringByAppendingPathComponent:copy] error:nil];
    [s reloadStationery];

    // Quick Look, recorded only here: text views also ask the shared panel.
    IMP sharedPanel = method_setImplementation(class_getClassMethod(QLPreviewPanel.class, @selector(sharedPreviewPanel)), (IMP)TestSharedPreview);
    IMP panelExists = method_setImplementation(class_getClassMethod(QLPreviewPanel.class, @selector(sharedPreviewPanelExists)), (IMP)TestPreviewExists);
    Select(s, @"0.tex");
    id list = s.tableView;
    Check([list respondsToSelector:@selector(acceptsPreviewPanelControl:)] && [list acceptsPreviewPanelControl:(id)QuickLook], @"the list takes Quick Look");
    [list beginPreviewPanelControl:(id)QuickLook];
    Check(QuickLook.dataSource == s && QuickLook.delegate == s, @"the panel gives Quick Look what to show");
    [list keyDown:Key(@" ", 0, 49)];
    Check(QuickLook.visible, @"Space shows Quick Look");
    id<QLPreviewPanelDataSource> source2 = (id)s;
    Check([source2 numberOfPreviewItemsInPreviewPanel:(id)QuickLook] == 1 && [((NSURL *)[source2 previewPanel:(id)QuickLook previewItemAtIndex:0]).path isEqualToString:[folder stringByAppendingPathComponent:@"0.tex"]],
          @"Quick Look shows the selected stationery");
    NSInteger reloads = QuickLook.reloads;
    Select(s, @"c.md");
    Check(QuickLook.reloads > reloads && [((NSURL *)[source2 previewPanel:(id)QuickLook previewItemAtIndex:0]).lastPathComponent isEqualToString:@"c.md"], @"Quick Look follows the selection");
    [list keyDown:Key(@" ", 0, 49)];
    Check(!QuickLook.visible, @"Space again hides Quick Look");
    __block NSInteger closed = 0;
    Method closeMethod = class_getInstanceMethod(NSWindow.class, @selector(close));
    IMP close = method_setImplementation(closeMethod, imp_implementationWithBlock(^(NSWindow *w) { if (w == panel) closed++; }));
    [list keyDown:Key(@" ", 0, 49)];
    [s cancelForStationeryPanel:nil];
    Check(!QuickLook.visible && closed == 0, @"Escape closes Quick Look only, not the panel");
    [s cancelForStationeryPanel:nil];
    Check(closed == 1, @"the next Escape closes the panel");
    method_setImplementation(closeMethod, close);
    [list keyDown:Key(@" ", 0, 49)];
    [s windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:s.stationeryWindow]];
    Check(!QuickLook.visible, @"closing the panel hides its Quick Look");
    [list keyDown:Key(@" ", NSEventModifierFlagCommand, 49)];
    Check(!QuickLook.visible, @"Command-Space is left alone");
    [s.tableView deselectAll:nil];
    [list keyDown:Key(@" ", 0, 49)];
    Check(!QuickLook.visible && [source2 numberOfPreviewItemsInPreviewPanel:(id)QuickLook] == 0, @"with nothing selected Space shows nothing");
    [list endPreviewPanelControl:(id)QuickLook];
    Check(QuickLook.dataSource == nil && QuickLook.delegate == nil, @"the panel lets Quick Look go");
    method_setImplementation(class_getClassMethod(QLPreviewPanel.class, @selector(sharedPreviewPanel)), sharedPanel);
    method_setImplementation(class_getClassMethod(QLPreviewPanel.class, @selector(sharedPreviewPanelExists)), panelExists);

    // Descriptions edited in the list.
    Select(s, @"c.md");
    NSInteger row = s.tableView.selectedRow;
    NSTableCellView *edited = [s.tableView viewAtColumn:1 row:row makeIfNecessary:YES];
    NSTextField *field = edited.textField;
    Check(field.editable, @"the description can be edited");
    Check([panel makeFirstResponder:field], @"the description takes the keyboard");
    Check(s.createButton.keyEquivalent.length == 0, @"while it is edited, Return does not press Create");
    field.stringValue = @"Changed\nhere";
    NSTextView *editor = (NSTextView *)[panel fieldEditor:YES forObject:field];
    Check([field.delegate control:field textView:editor doCommandBySelector:@selector(insertNewline:)], @"Return ends the editing");
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidEndEditingNotification object:field];
    [field.delegate controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
    Check([Read([folder stringByAppendingPathComponent:@"c.comment"]) isEqualToString:@"Changed here"], @"the edited description is written to the .comment file");
    Check([s.createButton.keyEquivalent isEqualToString:@"\r"], @"after the editing Return is Create again");
    Check([s.commentData[[Names(s) indexOfObject:@"c.md"]] isEqualToString:@"Changed here"], @"the list shows the new description");
    edited = [s.tableView viewAtColumn:1 row:[Names(s) indexOfObject:@"c.md"] makeIfNecessary:YES];
    field = edited.textField;
    [panel makeFirstResponder:field];
    field.stringValue = @"Not kept";
    Check([field.delegate control:field textView:editor doCommandBySelector:@selector(cancelOperation:)], @"Escape ends the editing");
    Check([field.stringValue isEqualToString:@"Changed here"], @"Escape brings the description back");
    [field.delegate controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
    Check([Read([folder stringByAppendingPathComponent:@"c.comment"]) isEqualToString:@"Changed here"], @"Escape leaves the .comment file as it was");
    edited = [s.tableView viewAtColumn:1 row:[Names(s) indexOfObject:@"c.md"] makeIfNecessary:YES];
    field = edited.textField;
    [panel makeFirstResponder:field];
    field.stringValue = @"   ";
    [field.delegate controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
    Check(![fm fileExistsAtPath:[folder stringByAppendingPathComponent:@"c.comment"]], @"an emptied description removes the .comment file");
    // A description added where there was none.
    NSUInteger zero = [Names(s) indexOfObject:@"Untitled Note.tex"];
    edited = [s.tableView viewAtColumn:1 row:zero makeIfNecessary:YES];
    field = edited.textField;
    [panel makeFirstResponder:field];
    field.stringValue = @"Notes";
    [field.delegate controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
    Check([Read([folder stringByAppendingPathComponent:@"Untitled Note.comment"]) isEqualToString:@"Notes"], @"a description given to a stationery without one creates its .comment file");
}

static void Render(NSPanel *panel, NSString *path) {
    NSView *frame = panel.contentView.superview;
    [panel displayIfNeeded];
    NSBitmapImageRep *rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void Layout(NSString *language, NSString *folder, NSString *pngs) {
    TSStationery *s = [TSStationery new];
    s.folderPath = folder;
    NSPanel *panel = s.stationeryWindow;
    [s newFromStationery:nil];
    NSString *(^L)(NSString *) = ^(NSString *key) { return Table[key] ?: key; };
    Check([panel.title isEqualToString:L(@"Select Stationery")] && Table[@"Select Stationery"], [NSString stringWithFormat:@"%@: the title is translated", language]);
    NSTableColumn *name = s.tableView.tableColumns[0], *description = s.tableView.tableColumns[1];
    Check(Table[@"Stationery"] && [name.title isEqualToString:Table[@"Stationery"]] && Table[@"Description"] && [description.title isEqualToString:Table[@"Description"]],
          [NSString stringWithFormat:@"%@: the column titles are translated", language]);
    Check(Table[@"Create"] && [s.createButton.title isEqualToString:Table[@"Create"]] && Table[@"Show in Finder"] && [s.showInFinderButton.title isEqualToString:Table[@"Show in Finder"]] && Table[@"Cancel"],
          [NSString stringWithFormat:@"%@: the buttons are translated", language]);
    NSMutableArray *views = [NSMutableArray array]; All(panel.contentView, views);
    NSButton *cancel = nil;
    for (NSView *v in views) if ([v.identifier isEqual:@"stationery.cancel"]) cancel = (NSButton *)v;
    for (NSString *key in @[@"Add the Front Document as Stationery", @"Move the Stationery to the Trash", @"Add as Stationery", @"Name:", @"Description:",
                            @"A stationery named “%@” already exists. Replace it?", @"Move “%@” to the Trash?", @"Move to Trash", @"Add", @"Replace"])
        Check(Table[key] != nil, [NSString stringWithFormat:@"%@: %@ is translated", language, key]);
    for (NSString *key in @[@"Stationery Actions", @"Duplicate", @"Duplicate “%@”", @"%@ copy"])
        Check(Table[key] != nil, [NSString stringWithFormat:@"%@: %@ is translated", language, key]);
    NSButton *actionsButton = nil;
    for (NSView *v in views) if ([v.identifier isEqual:@"stationery.actions"]) actionsButton = (NSButton *)v;
    Check([actionsButton.toolTip isEqualToString:L(@"Stationery Actions")], [NSString stringWithFormat:@"%@: the actions menu has a translated tooltip", language]);
    Check([s.plusButton.toolTip isEqualToString:L(@"Add the Front Document as Stationery")] && [s.minusButton.toolTip isEqualToString:L(@"Move the Stationery to the Trash")],
          [NSString stringWithFormat:@"%@: + and - have translated tooltips", language]);
    // The sheet of +: labels and buttons whole, the fields after the longer label.
    FakeSource *front = [FakeSource new];
    front.displayName = @"Untitled"; front.textView = [NSTextView new];
    FrontDocument = front;
    [s addFrontDocument:nil];
    NSWindow *sheet = s.addSheet;
    [sheet.contentView layoutSubtreeIfNeeded];
    NSMutableArray *sheetViews = [NSMutableArray array]; All(sheet.contentView, sheetViews);
    NSRect sheetBounds = sheet.contentView.bounds;
    for (NSView *v in sheetViews) {
        if (v == sheet.contentView) continue;
        Check(NSContainsRect(sheetBounds, InContent(v)), [NSString stringWithFormat:@"%@: the sheet shows %@ whole", language, v.className]);
        if ([v isKindOfClass:NSTextField.class] && !((NSTextField *)v).editable)
            Check(NSWidth(v.frame) + 0.5 >= v.intrinsicContentSize.width, [NSString stringWithFormat:@"%@: the sheet label %@ fits", language, ((NSTextField *)v).stringValue]);
        if ([v isKindOfClass:NSButton.class])
            Check(NSWidth(v.frame) + 0.5 >= v.intrinsicContentSize.width, [NSString stringWithFormat:@"%@: the sheet button %@ fits", language, ((NSButton *)v).title]);
    }
    Check(fabs(NSMinX(InContent(s.addNameField)) - NSMinX(InContent(s.addDescriptionField))) < 0.5 && NSWidth(s.addNameField.frame) >= 279.5,
          [NSString stringWithFormat:@"%@: the name and description fields line up", language]);
    if (![pngs isEqualToString:@"-"]) {
        sheet.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        Render((NSPanel *)sheet, [pngs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-sheet.png", language]]);
    }
    FrontDocument = nil;
    [s windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:panel]];
    for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(600, 400)], [NSValue valueWithSize:panel.contentMinSize]]) {
        [panel setContentSize:size.sizeValue];
        [panel.contentView layoutSubtreeIfNeeded];
        [s.tableView sizeLastColumnToFit];
        NSString *where = [NSString stringWithFormat:@"%@ at %.0fx%.0f", language, size.sizeValue.width, size.sizeValue.height];
        NSRect plus = InContent(s.plusButton), minus = InContent(s.minusButton), frame = InContent(s.plusButton.superview.superview), list = InContent(s.tableView.enclosingScrollView), finder = InContent(s.showInFinderButton), c = InContent(cancel), create = InContent(s.createButton);
        NSRect content = panel.contentView.bounds;
        for (NSButton *b in @[s.showInFinderButton, cancel, s.createButton])
            Check(NSWidth(b.frame) + 0.5 >= b.intrinsicContentSize.width && NSContainsRect(content, InContent(b)), [NSString stringWithFormat:@"%@: %@ shows its whole title in the panel", where, b.title]);
        Check(NSMaxX(finder) + 12 <= NSMinX(c) + 0.5 && NSMaxX(c) + 12 <= NSMinX(create) + 0.5,
              [NSString stringWithFormat:@"%@: Show in Finder, Cancel and Create are in order, 12 points apart or more", where]);
        Check(fabs(NSMinX(finder) - 20) < 0.5 && fabs(NSMaxX(content) - NSMaxX(create) - 20) < 0.5, [NSString stringWithFormat:@"%@: the buttons are 20 points from the sides", where]);
        NSView *box = s.plusButton;
        while (box && ![box.identifier isEqual:@"stationery.frame"]) box = box.superview;
        frame = box ? InContent(box) : NSZeroRect;
        Check(box && NSContainsRect(frame, plus) && NSContainsRect(frame, minus) && NSContainsRect(frame, list),
              [NSString stringWithFormat:@"%@: the list and + and - are in one part", where]);
        Check(NSMaxX(plus) <= NSMinX(minus) && NSMaxY(plus) <= NSMinY(list) + 0.5 && fabs(NSMidY(plus) - NSMidY(minus)) < 0.5 && NSMinY(plus) - NSMinY(frame) < 12,
              [NSString stringWithFormat:@"%@: + and - are in the bar at the bottom of the list, + first", where]);
        Check(fabs(NSMinX(frame)) < 0.5 && fabs(NSMaxX(content) - NSMaxX(frame)) < 0.5 && fabs(NSMaxY(content) - NSMaxY(frame)) < 0.5 && fabs(NSWidth(list) - NSWidth(content)) < 0.5,
              [NSString stringWithFormat:@"%@: the list meets the title bar and the window's sides", where]);
        NSView *rule = nil;
        for (NSView *v in views) if ([v.identifier isEqual:@"stationery.line"]) rule = v;
        NSRect ruleRect = rule ? [rule.superview convertRect:[rule alignmentRectForFrame:rule.frame] toView:nil] : NSZeroRect;
        Check(rule && fabs(NSWidth(ruleRect) - NSWidth(content)) < 1 && NSMaxY(ruleRect) <= NSMinY(frame) + 1 && NSMinY(ruleRect) >= NSMaxY(create) + 18,
              [NSString stringWithFormat:@"%@: a line across the window under the list, 20 points above the buttons", where]);
        Check(fabs(NSMinY(create) - 20) < 0.5, [NSString stringWithFormat:@"%@: the buttons are 20 points above the bottom", where]);
        Check(fabs(NSWidth(c) - NSWidth(create)) < 0.5, [NSString stringWithFormat:@"%@: Cancel and Create have the same width", where]);
        Check(fabs(NSMidY(finder) - NSMidY(create)) < 0.5 && fabs(NSMidY(c) - NSMidY(create)) < 0.5, [NSString stringWithFormat:@"%@: the buttons stand on one line", where]);
        for (NSTableColumn *column in @[name, description])
            Check(column.width + 0.5 >= ceil(column.headerCell.cellSize.width), [NSString stringWithFormat:@"%@: the column title %@ fits", where, column.title]);
        for (NSInteger row = 0; row < s.tableView.numberOfRows; row++) {
            NSTableCellView *cell = [s.tableView viewAtColumn:0 row:row makeIfNecessary:YES];
            Check(NSWidth(cell.textField.frame) + 0.5 >= cell.textField.intrinsicContentSize.width,
                  [NSString stringWithFormat:@"%@: the name %@ fits its column", where, cell.textField.stringValue]);
        }
        Check(NSMaxX([s.tableView rectOfColumn:1]) <= NSWidth(s.tableView.enclosingScrollView.contentView.bounds) + 0.5, [NSString stringWithFormat:@"%@: the description column ends inside the list", where]);
    }
    if (![pngs isEqualToString:@"-"]) {
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            panel.appearance = [NSAppearance appearanceNamed:appearance];
            [panel setContentSize:NSMakeSize(600, 400)];
            [panel.contentView layoutSubtreeIfNeeded];
            [s.tableView sizeLastColumnToFit];
            Render(panel, [pngs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", language, [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"]]);
        }
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    setvbuf(stdout, NULL, _IONBF, 0);
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:)), (IMP)TestLocalized);
    method_setImplementation(class_getInstanceMethod(NSWorkspace.class, @selector(openURL:)), (IMP)TestOpenURL);
    method_setImplementation(class_getInstanceMethod(NSDocumentController.class, @selector(openDocumentWithContentsOfURL:display:error:)), (IMP)TestOpenDocument);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(makeKeyAndOrderFront:)), (IMP)TestNoKeyAndFront);
    method_setImplementation(class_getInstanceMethod(NSApplication.class, @selector(orderedDocuments)), (IMP)TestOrderedDocuments);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(beginSheet:completionHandler:)), (IMP)TestBeginSheet);
    method_setImplementation(class_getInstanceMethod(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:)), (IMP)TestAlertSheet);
    method_setImplementation(class_getInstanceMethod(NSFileManager.class, @selector(trashItemAtURL:resultingItemURL:error:)), (IMP)TestTrash);
    Trashed = [NSMutableArray array];
    QuickLook = [FakeQuickLook new];
    MadeDocuments = [NSMutableArray array];
    AddedDocuments = [NSMutableArray array];
    method_setImplementation(class_getInstanceMethod(NSDocumentController.class, @selector(documents)), (IMP)TestDocuments);
    method_setImplementation(class_getInstanceMethod(NSDocumentController.class, @selector(documentForURL:)), (IMP)TestDocumentForURL);
    method_setImplementation(class_getInstanceMethod(NSDocumentController.class, @selector(typeForContentsOfURL:error:)), (IMP)TestTypeForURL);
    method_setImplementation(class_getInstanceMethod(NSDocumentController.class, @selector(makeDocumentWithContentsOfURL:ofType:error:)), (IMP)TestMakeDocument);
    method_setImplementation(class_getInstanceMethod(NSDocumentController.class, @selector(addDocument:)), (IMP)TestAddDocument);
    OpenedInWorkspace = [NSMutableArray array];
    OpenedDocuments = [NSMutableArray array];
    NSString *work = @(argv[1]), *pngs = @(argv[2]);
    WorkFolder = work;
    NSString *bundled = [work stringByAppendingPathComponent:@"Bundled"];
    for (int i = 3; i < argc; i++) {
        NSArray *parts = [@(argv[i]) componentsSeparatedByString:@"="];
        NSString *language = parts[0];
        Table = [[NSString stringWithContentsOfFile:parts[1] encoding:NSUTF8StringEncoding error:nil] propertyListFromStringsFileFormat];
        if (!Table.count) { Check(NO, [NSString stringWithFormat:@"%@: the strings table is read", language]); continue; }
        if (i == 3) Behavior(work);
        Layout(language, bundled, pngs);
    }
    if (failures) { printf("FAIL: %d of %d checks\n", failures, checks); return 1; }
    printf("PASS: %d checks in %d languages\n", checks, argc - 3);
} return 0; }
