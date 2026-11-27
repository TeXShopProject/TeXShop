//
//  TSStationery.m
//  TeXShop
//
//  Created by Richard Koch on 7/8/10.
//  Copyright 2010 University of Oregon. All rights reserved.
//

#import "TSStationery.h"
#import "globals.h"
#import "TSDocument.h"
#import "TSListBottomBar.h"
#import <Quartz/Quartz.h>

static NSUserInterfaceItemIdentifier const TSStationeryNameColumn = @"Source";
static NSUserInterfaceItemIdentifier const TSStationeryDescriptionColumn = @"Description";

// The list: Space shows the selected stationery in Quick Look, as in the Finder.
@interface TSStationeryTableView : NSTableView
@property (weak) TSStationery *stationery;
@end

@interface TSStationery () <QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuDelegate>
- (NSURL *)selectedStationeryURL;
- (void)toggleQuickLook;
@end

@implementation TSStationeryTableView
- (void)keyDown:(NSEvent *)event
{
	BOOL plain = (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl)) == 0;
	if (plain && [event.charactersIgnoringModifiers isEqualToString:@" "]) {
		[self.stationery toggleQuickLook];
		return;
	}
	[super keyDown:event];
}
- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel { return YES; }
- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel
{
	panel.dataSource = self.stationery;
	panel.delegate = self.stationery;
}
- (void)endPreviewPanelControl:(QLPreviewPanel *)panel
{
	if (panel.dataSource == (id)self.stationery) panel.dataSource = nil;
	if (panel.delegate == (id)self.stationery) panel.delegate = nil;
}
@end

@interface TSStationery ()
@property (readwrite, nonatomic) NSPanel *stationeryWindow;
@property (readwrite, nonatomic) NSTableView *tableView;
@property (readwrite, nonatomic) NSButton *createButton;
@property (readwrite, nonatomic) NSButton *showInFinderButton;
@property (readwrite, nonatomic) NSArray<NSString *> *fullSourceData;
@property (readwrite, nonatomic) NSArray<NSString *> *commentData;
@property (readwrite, nonatomic) TSListBottomBar *listBar;
// The text of the name or description being edited, put back by Escape.
@property (nonatomic) NSString *textBeforeEditing;
@end

// A name or description cell; it tells the panel when its editing starts, before any key.
@interface TSStationeryEditableField : NSTextField
@property (copy) void (^willEdit)(NSTextField *field);
@end
@implementation TSStationeryEditableField
- (BOOL)becomeFirstResponder
{
	BOOL became = [super becomeFirstResponder];
	if (became && self.willEdit) self.willEdit(self);
	return became;
}
@end

static NSString *TSStationeryOneLine(NSString *text)
{
	NSArray *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
	return [[lines componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

@implementation TSStationery

- (instancetype)init
{
	self = [super init];
	_fullSourceData = @[];
	_commentData = @[];
	return self;
}

- (NSString *)folderPath
{
	return _folderPath ?: [StationeryPath stringByStandardizingPath];
}

#pragma mark Panel

- (NSPanel *)stationeryWindow
{
	if (!_stationeryWindow) [self buildPanel];
	return _stationeryWindow;
}

- (NSTableView *)tableView
{
	if (!_tableView) [self buildPanel];
	return _tableView;
}

- (void)buildPanel
{
	NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
	                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
	                                              backing:NSBackingStoreBuffered defer:YES];
	panel.title = NSLocalizedString(@"Select Stationery", @"File > New from Stationery: window title");
	panel.releasedWhenClosed = NO;
	panel.hidesOnDeactivate = NO;
	panel.delegate = self;
	panel.identifier = @"stationery.panel";
	NSView *content = panel.contentView;

	// The same list as the key bindings in Settings: no border, rows inset, striped rows.
	TSStationeryTableView *table = [TSStationeryTableView new];
	table.stationery = self;
	table.style = NSTableViewStyleInset;
	table.usesAlternatingRowBackgroundColors = YES;
	table.rowHeight = 24;
	table.intercellSpacing = NSMakeSize(0, 0);
	table.gridStyleMask = NSTableViewGridNone;
	table.allowsMultipleSelection = NO;
	table.allowsEmptySelection = YES;
	table.allowsColumnReordering = NO;
	table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
	table.identifier = @"stationery.table";
	table.accessibilityLabel = NSLocalizedString(@"Stationery", @"File > New from Stationery: list column and list name");
	NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:TSStationeryNameColumn];
	name.title = NSLocalizedString(@"Stationery", @"File > New from Stationery: list column and list name");
	name.minWidth = 80;
	name.resizingMask = NSTableColumnUserResizingMask;
	NSTableColumn *description = [[NSTableColumn alloc] initWithIdentifier:TSStationeryDescriptionColumn];
	description.title = NSLocalizedString(@"Description", @"File > New from Stationery: list column");
	description.minWidth = 120;
	description.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
	[table addTableColumn:name];
	[table addTableColumn:description];
	table.dataSource = self;
	table.delegate = self;
	table.target = self;
	table.doubleAction = @selector(openClickedRow:);
	// The contextual menu names no stationery, as in the Finder and the theme list.
	table.menu = [[NSMenu alloc] initWithTitle:@""];
	table.menu.delegate = self;

	NSScrollView *scroll = [NSScrollView new];
	scroll.borderType = NSNoBorder;
	scroll.drawsBackground = NO;
	scroll.hasVerticalScroller = YES;
	scroll.autohidesScrollers = YES;
	scroll.documentView = table;
	scroll.identifier = @"stationery.list";

	// The list from the title bar to the window's sides, with + and - in the bar at its bottom
	// and a line under it, as the list of the macro editor.
	TSListBottomBar *bar = [[TSListBottomBar alloc] initWithTarget:self
	    addAction:@selector(addStationery:) addToolTip:NSLocalizedString(@"New Stationery", @"File > New from Stationery: the + button")
	    removeAction:@selector(removeSelectedStationery:) removeToolTip:NSLocalizedString(@"Move the Stationery to the Trash", @"File > New from Stationery: the - button")
	    actionsToolTip:NSLocalizedString(@"Stationery Actions", @"File > New from Stationery: the actions menu at the bottom of the list")];
	bar.actionsButton.menu.delegate = self;
	bar.actionsButton.identifier = @"stationery.actions";
	bar.addButton.identifier = @"stationery.add";
	bar.removeButton.identifier = @"stationery.remove";
	NSView *frame = [NSView new];
	frame.identifier = @"stationery.frame";
	NSBox *line = [NSBox new];
	line.boxType = NSBoxSeparator;
	line.identifier = @"stationery.line";
	table.backgroundColor = NSColor.clearColor;
	for (NSView *v in @[scroll, bar]) {
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[frame addSubview:v];
	}

	NSButton *finder = [NSButton buttonWithTitle:NSLocalizedString(@"Show in Finder", @"File > New from Stationery: opens the Stationery folder in the Finder")
	                                       image:[NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil]
	                                      target:self action:@selector(showStationeryInFinder:)];
	finder.imagePosition = NSImageLeading;
	finder.identifier = @"stationery.show-in-finder";
	NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"Cancel") target:self action:@selector(cancelForStationeryPanel:)];
	cancel.keyEquivalent = @"\033";
	cancel.identifier = @"stationery.cancel";
	NSButton *create = [NSButton buttonWithTitle:NSLocalizedString(@"Create", @"File > New from Stationery: opens the chosen stationery as a new document") target:self action:@selector(okForStationeryPanel:)];
	create.keyEquivalent = @"\r";
	create.identifier = @"stationery.create";

	for (NSView *v in @[frame, line, finder, cancel, create]) {
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[content addSubview:v];
	}
	[NSLayoutConstraint activateConstraints:@[
		[frame.topAnchor constraintEqualToAnchor:content.topAnchor],
		[frame.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
		[frame.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
		[scroll.topAnchor constraintEqualToAnchor:frame.topAnchor],
		[scroll.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
		[scroll.heightAnchor constraintGreaterThanOrEqualToConstant:4 * table.rowHeight + 28],
		[bar.topAnchor constraintEqualToAnchor:scroll.bottomAnchor],
		[bar.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
		[bar.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
		[bar.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor],
		[line.topAnchor constraintEqualToAnchor:frame.bottomAnchor],
		[line.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
		[line.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
		[create.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:20],
		[create.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
		[create.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
		[create.widthAnchor constraintGreaterThanOrEqualToConstant:88],
		[cancel.widthAnchor constraintEqualToAnchor:create.widthAnchor],
		[cancel.trailingAnchor constraintEqualToAnchor:create.leadingAnchor constant:-12],
		[cancel.centerYAnchor constraintEqualToAnchor:create.centerYAnchor],
		[finder.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
		[finder.centerYAnchor constraintEqualToAnchor:create.centerYAnchor],
		[finder.trailingAnchor constraintLessThanOrEqualToAnchor:cancel.leadingAnchor constant:-12]]];
	for (NSButton *b in @[finder, cancel, create])
		[b setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

	_stationeryWindow = panel;
	_tableView = table;
	_createButton = create;
	_showInFinderButton = finder;
	_listBar = bar;

	[content layoutSubtreeIfNeeded];
	panel.contentMinSize = NSMakeSize(MAX(420, content.fittingSize.width), 260);
	[panel center];
	panel.frameAutosaveName = @"StationeryPanel";
	[self updateCreateButton];
}

- (IBAction)newFromStationery:(id)sender
{
	NSPanel *panel = self.stationeryWindow;
	[self reloadStationery];
	if (self.tableView.selectedRow < 0 && self.fullSourceData.count > 0)
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[panel makeFirstResponder:self.tableView];
	[panel makeKeyAndOrderFront:self];
}

// Files added or removed in the Finder show up when the panel comes back.
- (void)windowDidBecomeKey:(NSNotification *)notification
{
	[self reloadStationery];
}

#pragma mark Model

- (void)reloadStationery
{
	NSTableView *table = self.tableView;
	NSInteger selected = table.selectedRow;
	NSString *selectedFile = (selected >= 0 && selected < (NSInteger)self.fullSourceData.count) ? self.fullSourceData[selected] : nil;

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *basePath = self.folderPath;
	NSArray *names = [[fileManager contentsOfDirectoryAtPath:basePath error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	NSMutableArray<NSString *> *files = [NSMutableArray array];
	NSMutableArray<NSString *> *comments = [NSMutableArray array];
	for (NSString *file in names) {
		if ([file hasPrefix:@"."] || [[file pathExtension] caseInsensitiveCompare:@"comment"] == NSOrderedSame) continue;
		BOOL isDirectory = NO;
		NSString *path = [basePath stringByAppendingPathComponent:file];
		if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) continue;
		NSStringEncoding encoding;
		NSString *commentPath = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"comment"];
		NSString *comment = [NSString stringWithContentsOfFile:commentPath usedEncoding:&encoding error:nil];
		// One line in the list.
		comment = TSStationeryOneLine(comment);
		[files addObject:file];
		[comments addObject:comment ?: @""];
	}
	BOOL changed = ![files isEqualToArray:self.fullSourceData] || ![comments isEqualToArray:self.commentData];
	self.fullSourceData = files;
	self.commentData = comments;
	if (changed) {
		[table reloadData];
		[self fitNameColumn];
		NSUInteger row = selectedFile ? [files indexOfObject:selectedFile] : NSNotFound;
		if (row != NSNotFound) [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		else [table deselectAll:nil];
	}
	[self updateCreateButton];
}

- (NSString *)titleAtRow:(NSInteger)row
{
	return [self.fullSourceData[row] stringByDeletingPathExtension];
}

// The names fit their column; the description takes the rest of the width.
- (void)fitNameColumn
{
	NSTableColumn *column = [self.tableView tableColumnWithIdentifier:TSStationeryNameColumn];
	NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.systemFontSize]};
	CGFloat width = ceil(column.headerCell.cellSize.width);
	for (NSInteger row = 0; row < (NSInteger)self.fullSourceData.count; row++)
		width = MAX(width, ceil([[self titleAtRow:row] sizeWithAttributes:attributes].width));
	column.width = MIN(MAX(width + 24, 120), 260);
	[self.tableView sizeLastColumnToFit];
}

- (void)updateCreateButton
{
	BOOL selected = self.tableView.selectedRow >= 0;
	self.createButton.enabled = selected;
	self.listBar.removeButton.enabled = selected;
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.fullSourceData.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTableCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
	if (!cell) {
		cell = [NSTableCellView new];
		cell.identifier = tableColumn.identifier;
		TSStationeryEditableField *field = [TSStationeryEditableField labelWithString:@""];
		field.lineBreakMode = NSLineBreakByTruncatingTail;
		// The name and the description are edited in place, as the names of the theme list: the
		// name renames the file, the description is kept in the .comment file.
		field.editable = YES;
		field.delegate = self;
		__weak TSStationery *weakSelf = self;
		field.willEdit = ^(NSTextField *edited) { [weakSelf beginEditingField:edited]; };
		field.translatesAutoresizingMaskIntoConstraints = NO;
		[field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		[cell addSubview:field];
		cell.textField = field;
		[NSLayoutConstraint activateConstraints:@[
			[field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
			[field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
			[field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
	}
	BOOL isName = [tableColumn.identifier isEqualToString:TSStationeryNameColumn];
	NSString *text = isName ? [self titleAtRow:row] : self.commentData[row];
	cell.textField.stringValue = text;
	// A long description is cut at the end of its column; the tooltip shows it whole.
	cell.textField.toolTip = (!isName && text.length) ? text : nil;
	return cell;
}

- (NSString *)tableView:(NSTableView *)tableView typeSelectStringForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	return [tableColumn.identifier isEqualToString:TSStationeryNameColumn] ? [self titleAtRow:row] : nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateCreateButton];
	// Quick Look follows the selection.
	if ([QLPreviewPanel sharedPreviewPanelExists] && [QLPreviewPanel sharedPreviewPanel].visible) [[QLPreviewPanel sharedPreviewPanel] reloadData];
}

#pragma mark Quick Look

- (NSURL *)selectedStationeryURL
{
	NSInteger row = self.tableView.selectedRow;
	if (row < 0 || row >= (NSInteger)self.fullSourceData.count) return nil;
	return [NSURL fileURLWithPath:[self.folderPath stringByAppendingPathComponent:self.fullSourceData[row]]];
}

- (void)toggleQuickLook
{
	QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
	if (panel.visible) [panel orderOut:nil];
	else if ([self selectedStationeryURL]) [panel makeKeyAndOrderFront:nil];
	else NSBeep();
}

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel
{
	return [self selectedStationeryURL] ? 1 : 0;
}

- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index
{
	return [self selectedStationeryURL];
}

// Up and down in the preview move in the list, as in the Finder.
- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event
{
	if (event.type == NSEventTypeKeyDown && (event.keyCode == 125 || event.keyCode == 126)) {
		[self.tableView keyDown:event];
		return YES;
	}
	return NO;
}

// The preview grows from the selected row and shrinks back to it.
- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id<QLPreviewItem>)item
{
	NSInteger row = self.tableView.selectedRow;
	if (row < 0 || !self.stationeryWindow.visible) return NSZeroRect;
	NSRect rect = [self.tableView frameOfCellAtColumn:0 row:row];
	if (!NSIntersectsRect(rect, self.tableView.visibleRect)) return NSZeroRect;
	return [self.stationeryWindow convertRectToScreen:[self.tableView convertRect:rect toView:nil]];
}

#pragma mark Actions

- (void)openClickedRow:(id)sender
{
	if (self.tableView.clickedRow >= 0) [self okForStationeryPanel:sender];
}

- (IBAction)okForStationeryPanel:(id)sender
{
	NSInteger row = self.tableView.selectedRow;
	if (row < 0 || row >= (NSInteger)self.fullSourceData.count) return;
	NSURL *url = [NSURL fileURLWithPath:[self.folderPath stringByAppendingPathComponent:self.fullSourceData[row]]];
	[self.stationeryWindow close];
	NSError *error = nil;
	NSDocumentController *controller = [NSDocumentController sharedDocumentController];
	TSDocument *document = nil;
	if ([self documentIsOpenForURL:url]) {
		// The stationery is open for editing (Show in Finder, +): a second document is made from
		// the file, so that the one being edited keeps its file.
		NSString *type = [controller typeForContentsOfURL:url error:&error];
		document = type ? [controller makeDocumentWithContentsOfURL:url ofType:type error:&error] : nil;
		if (document) {
			[controller addDocument:document];
			[document makeWindowControllers];
			[document showWindows];
		}
	} else
		document = [controller openDocumentWithContentsOfURL:url display:YES error:&error];
	if (!document) {
		if (error) [NSApp presentError:error];
		return;
	}
	[document setFileURL:nil];
	[document updateChangeCount:NSChangeDone];
}

- (BOOL)documentIsOpenForURL:(NSURL *)url
{
	NSDocumentController *controller = [NSDocumentController sharedDocumentController];
	if ([controller documentForURL:url]) return YES;
	for (NSDocument *document in controller.documents)
		if ([document respondsToSelector:@selector(isSameFileAs:)] && [(TSDocument *)document isSameFileAs:url]) return YES;
	return NO;
}

- (IBAction)cancelForStationeryPanel:(id)sender
{
	// Escape closes Quick Look first, as in the Finder.
	if ([self quickLookIsShowingStationery]) {
		[[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
		return;
	}
	[self.stationeryWindow close];
}

- (BOOL)quickLookIsShowingStationery
{
	if (![QLPreviewPanel sharedPreviewPanelExists]) return NO;
	QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
	return panel.visible && panel.dataSource == (id)self;
}

// Quick Look of a stationery goes with the panel.
- (void)windowWillClose:(NSNotification *)notification
{
	if (notification.object == self.stationeryWindow && [self quickLookIsShowingStationery])
		[[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
}

- (IBAction)showStationeryInFinder:(id)sender
{
	NSString *path = self.folderPath;
	NSError *error = nil;
	if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
		[NSApp presentError:error];
		return;
	}
	[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path isDirectory:YES]];
}

#pragma mark Adding and removing

- (NSButton *)plusButton { return self.listBar.addButton; }
- (NSButton *)minusButton { return self.listBar.removeButton; }

- (BOOL)isValidStationeryName:(NSString *)name
{
	name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return name.length > 0 && ![name hasPrefix:@"."] && [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]].location == NSNotFound;
}

// Files of the folder whose name without extension is name, the .comment file aside.
- (NSArray<NSString *> *)stationeryFilesNamed:(NSString *)name
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.folderPath error:nil])
		if ([file.stringByDeletingPathExtension caseInsensitiveCompare:name] == NSOrderedSame && [file.pathExtension caseInsensitiveCompare:@"comment"] != NSOrderedSame)
			[found addObject:file];
	return found;
}

// proposed, or proposed 2, 3 ... : a name that no stationery and no .comment file has.
- (NSString *)availableNameFor:(NSString *)proposed
{
	NSString *name = proposed;
	for (NSUInteger number = 2; [self stationeryFilesNamed:name].count || [[NSFileManager defaultManager] fileExistsAtPath:[[self.folderPath stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"comment"]]; number++)
		name = [NSString stringWithFormat:@"%@ %lu", proposed, (unsigned long)number];
	return name;
}

- (void)selectFile:(NSString *)file
{
	NSUInteger row = [self.fullSourceData indexOfObject:file];
	if (row == NSNotFound) return;
	[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[self.tableView scrollRowToVisible:row];
}

// + adds an empty stationery named Untitled, and its name is edited at once, as a new theme's.
- (IBAction)addStationery:(id)sender
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;
	if (![fileManager createDirectoryAtPath:self.folderPath withIntermediateDirectories:YES attributes:nil error:&error]) {
		[self showError:error];
		return;
	}
	NSString *name = [self availableNameFor:NSLocalizedString(@"Untitled Stationery", @"File > New from Stationery: the name of a new, empty stationery")];
	NSString *file = [name stringByAppendingPathExtension:@"tex"];
	if (![@"" writeToFile:[self.folderPath stringByAppendingPathComponent:file] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
		[self showError:error];
		return;
	}
	[self reloadStationery];
	[self selectFile:file];
	[self beginRenamingFile:file];
}

- (void)beginRenamingFile:(NSString *)file
{
	NSUInteger row = [self.fullSourceData indexOfObject:file];
	if (row == NSNotFound || self.stationeryWindow == nil) return;
	[self.tableView editColumn:[self.tableView columnWithIdentifier:TSStationeryNameColumn] row:(NSInteger)row withEvent:nil select:YES];
}

// Renames the file and its .comment file; a name in use is refused, as in the Finder.
- (BOOL)renameFile:(NSString *)file to:(NSString *)name
{
	NSString *old = file.stringByDeletingPathExtension;
	if ([name isEqualToString:old] || ![self isValidStationeryName:name]) return NO;
	NSString *renamed = file.pathExtension.length ? [name stringByAppendingPathExtension:file.pathExtension] : name;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *oldComment = [[self.folderPath stringByAppendingPathComponent:old] stringByAppendingPathExtension:@"comment"];
	NSString *newComment = [[self.folderPath stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"comment"];
	BOOL caseOnly = [name caseInsensitiveCompare:old] == NSOrderedSame;
	NSMutableArray *others = [[self stationeryFilesNamed:name] mutableCopy];
	[others removeObject:file];
	if (others.count || (!caseOnly && [fileManager fileExistsAtPath:newComment])) {
		[self showError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{NSFilePathErrorKey: [self.folderPath stringByAppendingPathComponent:renamed]}]];
		return NO;
	}
	NSError *error = nil;
	if (![fileManager moveItemAtPath:[self.folderPath stringByAppendingPathComponent:file] toPath:[self.folderPath stringByAppendingPathComponent:renamed] error:&error]) {
		[self showError:error];
		return NO;
	}
	// The description goes with it, unless another stationery of the old name keeps it.
	if ([fileManager fileExistsAtPath:oldComment] && [self stationeryFilesNamed:old].count == 0)
		[fileManager moveItemAtPath:oldComment toPath:newComment error:nil];
	[self reloadStationery];
	[self selectFile:renamed];
	return YES;
}

// name.comment holds the description on one line; an empty description removes it.
- (BOOL)writeDescription:(NSString *)description forName:(NSString *)name error:(NSError **)error
{
	NSString *path = [[self.folderPath stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"comment"];
	description = TSStationeryOneLine(description ?: @"");
	if (description.length == 0) {
		if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;
		return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
	}
	return [description writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (IBAction)removeSelectedStationery:(id)sender
{
	NSInteger row = self.tableView.selectedRow;
	if (row < 0 || row >= (NSInteger)self.fullSourceData.count) return;
	NSString *file = self.fullSourceData[row];
	NSAlert *alert = [NSAlert new];
	alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"Move “%@” to the Trash?", @"File > New from Stationery: asked before the - button removes a stationery"), [self titleAtRow:row]];
	[alert addButtonWithTitle:NSLocalizedString(@"Move to Trash", @"File > New from Stationery: removes the stationery")].hasDestructiveAction = YES;
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")];
	[alert beginSheetModalForWindow:self.stationeryWindow completionHandler:^(NSModalResponse response) {
		if (response == NSAlertFirstButtonReturn) [self trashStationeryFile:file];
	}];
}

- (void)trashStationeryFile:(NSString *)file
{
	NSUInteger row = [self.fullSourceData indexOfObject:file];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSString *name = file.stringByDeletingPathExtension;
	if (![fileManager trashItemAtURL:[NSURL fileURLWithPath:[self.folderPath stringByAppendingPathComponent:file]] resultingItemURL:nil error:&error]) {
		[self showError:error];
		return;
	}
	// The description goes too, unless another stationery of the same name keeps it.
	NSString *comment = [[self.folderPath stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"comment"];
	if ([self stationeryFilesNamed:name].count == 0 && [fileManager fileExistsAtPath:comment])
		[fileManager trashItemAtURL:[NSURL fileURLWithPath:comment] resultingItemURL:nil error:nil];
	[self reloadStationery];
	// The stationery after it takes its place, or the one before it at the end of the list.
	if (self.fullSourceData.count && row != NSNotFound) {
		NSUInteger next = MIN(row, self.fullSourceData.count - 1);
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
	}
	[self updateCreateButton];
}

- (void)showError:(NSError *)error
{
	if (error == nil) return;
	[[NSAlert alertWithError:error] beginSheetModalForWindow:self.stationeryWindow completionHandler:nil];
}

#pragma mark Duplicating

// The actions menu names the selected stationery; the contextual menu acts on the row clicked,
// without its name, as the theme list's.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
	BOOL context = menu == self.tableView.menu;
	NSMenuItem *icon = context ? nil : menu.itemArray.firstObject;
	[menu removeAllItems];
	if (icon) [menu addItem:icon];
	NSInteger row = context ? self.tableView.clickedRow : self.tableView.selectedRow;
	if (row < 0 || row >= (NSInteger)self.fullSourceData.count) return;
	NSString *name = [self titleAtRow:row];
	NSArray *items = @[
		@[NSLocalizedString(@"Edit Stationery", @"File > New from Stationery: contextual menu item that opens the stationery file"),
		  NSLocalizedString(@"Edit “%@”", @"File > New from Stationery: actions menu item that opens the stationery file"), NSStringFromSelector(@selector(editStationery:))],
		@[NSLocalizedString(@"Rename Stationery", @"File > New from Stationery: contextual menu item"),
		  NSLocalizedString(@"Rename “%@”", @"File > New from Stationery: actions menu item, with the name of the selected stationery"), NSStringFromSelector(@selector(renameStationery:))],
		@[NSLocalizedString(@"Duplicate", @"File > New from Stationery: contextual menu item"),
		  NSLocalizedString(@"Duplicate “%@”", @"File > New from Stationery: actions menu item, with the name of the selected stationery"), NSStringFromSelector(@selector(duplicateStationery:))],
		@[NSLocalizedString(@"Show in Finder", @"File > New from Stationery: opens the Stationery folder in the Finder"),
		  NSLocalizedString(@"Show “%@” in Finder", @"File > New from Stationery: actions menu item that shows the stationery file in the Finder"), NSStringFromSelector(@selector(revealStationeryInFinder:))]];
	for (NSArray *entry in items) {
		NSString *title = context ? entry[0] : [NSString stringWithFormat:entry[1], name];
		NSMenuItem *item = [menu addItemWithTitle:title action:NSSelectorFromString(entry[2]) keyEquivalent:@""];
		item.target = self;
		item.representedObject = self.fullSourceData[row];
	}
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	if (item.action == @selector(duplicateStationery:) || item.action == @selector(editStationery:) || item.action == @selector(renameStationery:) || item.action == @selector(revealStationeryInFinder:))
		return [self.fullSourceData containsObject:item.representedObject];
	return YES;
}

// The file of the menu item, or the selected one.
- (NSString *)fileOfSender:(id)sender
{
	NSString *file = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
	if ([file isKindOfClass:NSString.class] && [self.fullSourceData containsObject:file]) return file;
	NSInteger row = self.tableView.selectedRow;
	return row >= 0 && row < (NSInteger)self.fullSourceData.count ? self.fullSourceData[row] : nil;
}

// The stationery file itself is opened for editing; the panel stays.
- (IBAction)editStationery:(id)sender
{
	NSString *file = [self fileOfSender:sender];
	if (file == nil) return;
	NSURL *url = [NSURL fileURLWithPath:[self.folderPath stringByAppendingPathComponent:file]];
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES completionHandler:^(NSDocument *document, BOOL wasOpen, NSError *error) {
		if (document == nil && error) [NSApp presentError:error];
	}];
}

// The file selected in a Finder window of the Stationery folder.
- (IBAction)revealStationeryInFinder:(id)sender
{
	NSString *file = [self fileOfSender:sender];
	if (file == nil) return;
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:[self.folderPath stringByAppendingPathComponent:file]]]];
}

- (IBAction)renameStationery:(id)sender
{
	NSString *file = [self fileOfSender:sender];
	if (file == nil) return;
	[self selectFile:file];
	[self beginRenamingFile:file];
}

// A copy of the stationery and its description, named as the theme list names a copy, and selected.
- (IBAction)duplicateStationery:(id)sender
{
	NSString *file = [self fileOfSender:sender];
	if (file == nil) return;
	NSString *name = [self availableNameFor:[NSString stringWithFormat:NSLocalizedString(@"%@ copy", @"File > New from Stationery: the name of a duplicated stationery"), file.stringByDeletingPathExtension]];
	NSString *copy = file.pathExtension.length ? [name stringByAppendingPathExtension:file.pathExtension] : name;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;
	if (![fileManager copyItemAtPath:[self.folderPath stringByAppendingPathComponent:file] toPath:[self.folderPath stringByAppendingPathComponent:copy] error:&error]) {
		[self showError:error];
		return;
	}
	NSString *comment = [[self.folderPath stringByAppendingPathComponent:file.stringByDeletingPathExtension] stringByAppendingPathExtension:@"comment"];
	if ([fileManager fileExistsAtPath:comment])
		[fileManager copyItemAtPath:comment toPath:[[self.folderPath stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"comment"] error:nil];
	[self reloadStationery];
	[self selectFile:copy];
}

#pragma mark Editing names and descriptions

// While a name or description is edited, Return and Escape end the editing, not the panel.
- (void)beginEditingField:(NSTextField *)field
{
	self.textBeforeEditing = field.stringValue;
	self.createButton.keyEquivalent = @"";
	[self cancelButton].keyEquivalent = @"";
}

- (NSButton *)cancelButton
{
	for (NSView *v in self.stationeryWindow.contentView.subviews)
		if ([v.identifier isEqual:@"stationery.cancel"]) return (NSButton *)v;
	return nil;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	if (command == @selector(cancelOperation:)) {
		control.stringValue = self.textBeforeEditing ?: control.stringValue;
		[self.stationeryWindow makeFirstResponder:self.tableView];
		return YES;
	}
	if (command == @selector(insertNewline:) || command == @selector(insertTab:) || command == @selector(insertBacktab:)) {
		[self.stationeryWindow makeFirstResponder:self.tableView];
		return YES;
	}
	return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSTextField *field = notification.object;
	self.createButton.keyEquivalent = @"\r";
	[self cancelButton].keyEquivalent = @"\033";
	NSInteger row = [self.tableView rowForView:field];
	if (row < 0 || row >= (NSInteger)self.fullSourceData.count) return;
	if ([self.tableView columnForView:field] == [self.tableView columnWithIdentifier:TSStationeryNameColumn]) {
		NSString *name = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (![self renameFile:self.fullSourceData[row] to:name]) field.stringValue = [self titleAtRow:row];
		return;
	}
	NSString *description = TSStationeryOneLine(field.stringValue);
	field.stringValue = description;
	field.toolTip = description.length ? description : nil;
	if ([description isEqualToString:self.commentData[row]]) return;
	NSError *error = nil;
	if (![self writeDescription:description forName:[self titleAtRow:row] error:&error]) {
		[self showError:error];
		field.stringValue = self.commentData[row];
		return;
	}
	[self reloadStationery];
}

@end
