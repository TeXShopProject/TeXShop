// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsThemeList.h"
#import "TSThemeFileStore.h"
#import "TSListBottomBar.h"

static const NSInteger TSThemeListVisibleRows = 8;
static const CGFloat TSThemeListRowHeight = 24;

/// The space the inset style keeps at each side of the rows.
static CGFloat TSThemeListInset(NSTableView *table)
{
    return table.effectiveStyle == NSTableViewStyleInset ? 10 : 0;
}

/// A table that offers files dropped on it to the list, and whose contextual menu names the row clicked.
@interface TSSettingsThemeTable : NSTableView
@end
@implementation TSSettingsThemeTable
@end

@interface TSSettingsThemeList () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate, NSMenuItemValidation>
@property (weak) id<TSSettingsThemeListOwner> owner;
@property (strong) TSThemeFileStore *store;
@property (copy, nullable) NSURL *bundledDirectory;
@property (copy) NSString *(^text)(NSString *);
@property (readwrite, copy) NSArray<NSString *> *titles;
@property (strong) NSMenu *contextMenu;
@property BOOL reloading;
@end

@implementation TSSettingsThemeList

- (instancetype)initWithStore:(TSThemeFileStore *)store bundledDirectory:(NSURL *)bundledDirectory
                        owner:(id<TSSettingsThemeListOwner>)owner text:(NSString *(^)(NSString *))text
{
    if (!(self = [super init])) return nil;
    _store = store;
    _bundledDirectory = [bundledDirectory copy];
    _owner = owner;
    _text = [text copy];
    _titles = @[];
    [self buildView];
    return self;
}

#pragma mark View

- (void)buildView
{
    NSTableView *table = [[TSSettingsThemeTable alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    column.minWidth = 40;
    column.width = 40;
    column.title = self.text(@"group.appearance.1.title");
    [table addTableColumn:column];
    table.headerView = nil;
    table.style = NSTableViewStyleInset;
    table.rowHeight = TSThemeListRowHeight;
    table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    table.allowsEmptySelection = NO;
    table.backgroundColor = NSColor.clearColor;
    table.dataSource = self;
    table.delegate = self;
    table.identifier = @"settings.theme-list.table";
    table.accessibilityLabel = self.text(@"group.appearance.1.title");
    [table registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    self.contextMenu = [[NSMenu alloc] initWithTitle:@""];
    self.contextMenu.delegate = self;
    table.menu = self.contextMenu;
    _tableView = table;

    NSScrollView *scroll = [NSScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.horizontalScrollElasticity = NSScrollElasticityNone;
    scroll.documentView = table;
    // The names take the visible width of the list, never more: the list never scrolls sideways.
    scroll.contentView.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitColumn) name:NSViewFrameDidChangeNotification object:scroll.contentView];

    TSListBottomBar *bar = [[TSListBottomBar alloc] initWithTarget:self
                                                         addAction:@selector(addTheme:) addToolTip:self.text(@"theme.list.add")
                                                      removeAction:@selector(deleteTheme:) removeToolTip:self.text(@"theme.list.remove")
                                                    actionsToolTip:self.text(@"theme.list.actions")];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.actionsButton.menu.delegate = self;
    _addButton = bar.addButton;
    _removeButton = bar.removeButton;
    _actionsButton = bar.actionsButton;
    _addButton.identifier = @"settings.theme-list.add";
    _removeButton.identifier = @"settings.theme-list.remove";
    _actionsButton.identifier = @"settings.theme-list.actions";

    // The rounded frame around the list and its bar.
    NSView *frame = [TSListFrameView new];
    frame.translatesAutoresizingMaskIntoConstraints = NO;
    frame.identifier = @"settings.theme-list.frame";
    [frame addSubview:scroll];
    [frame addSubview:bar];
    CGFloat height = TSThemeListVisibleRows * TSThemeListRowHeight + 12;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:frame.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
        [scroll.heightAnchor constraintEqualToConstant:height],
        [bar.topAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor],
    ]];
    // Settings places the list by its outer view and removes that view's own constraints (the frame's stay with it),
    // then fits the frame to the outer view again (TSSettingsPaneComposer).
    NSView *view = [NSView new];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.identifier = @"settings.theme-list";
    [view addSubview:frame];
    [self fitFrameToView:view];
    _view = view;
}

- (void)fitFrameToView:(NSView *)view
{
    NSView *frame = view.subviews.firstObject;
    if (frame == nil) return;
    [NSLayoutConstraint activateConstraints:@[
        [frame.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [frame.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [frame.topAnchor constraintEqualToAnchor:view.topAnchor],
        [frame.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];
}

- (void)fitColumn
{
    NSTableColumn *column = self.tableView.tableColumns.firstObject;
    NSClipView *clip = self.tableView.enclosingScrollView.contentView;
    if (column == nil || clip == nil) return;
    CGFloat visible = NSWidth(clip.bounds);
    CGFloat width = MAX(column.minWidth, visible - self.tableView.intercellSpacing.width - 2 * TSThemeListInset(self.tableView));
    if (fabs(column.width - width) > 0.5) column.width = width;
    if (fabs(NSWidth(self.tableView.frame) - visible) > 0.5) [self.tableView setFrameSize:NSMakeSize(visible, NSHeight(self.tableView.frame))];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark State

- (BOOL)isBundledTitle:(NSString *)title
{
    NSURL *url = [self bundledURLForTitle:title];
    return url != nil && [NSFileManager.defaultManager fileExistsAtPath:url.path ?: @""];
}

- (nullable NSURL *)bundledURLForTitle:(NSString *)title
{
    if (self.bundledDirectory == nil || title.length == 0 || [title containsString:@"/"]) return nil;
    return [self.bundledDirectory URLByAppendingPathComponent:[title stringByAppendingPathExtension:@"plist"] ?: title];
}

- (nullable NSDictionary<NSString *, id> *)bundledColorsForTitle:(NSString *)title
{
    NSURL *url = [self isBundledTitle:title] ? [self bundledURLForTitle:title] : nil;
    NSData *data = url != nil ? [NSData dataWithContentsOfURL:url] : nil;
    id colors = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    return [colors isKindOfClass:NSDictionary.class] ? colors : nil;
}

/// A color the copy has and TeXShop's has too, but different. A color missing from either is not counted: TeXShop
/// gives a missing color its default, and older copies lack the colors added since.
- (BOOL)isChangedTitle:(NSString *)title
{
    NSDictionary<NSString *, id> *bundled = [self bundledColorsForTitle:title];
    NSDictionary<NSString *, id> *colors = bundled != nil ? [self.store readTitle:title] : nil;
    if (colors == nil) return NO;
    for (NSString *key in colors) {
        if ([key isEqualToString:@"Title"]) continue;
        id mine = colors[key], original = bundled[key];
        if (original == nil) continue;
        if ([mine isKindOfClass:NSArray.class] && [original isKindOfClass:NSArray.class]) {
            NSArray *a = mine, *b = original;
            if (a.count != b.count) return YES;
            for (NSUInteger i = 0; i < a.count; i++) {
                if (![a[i] isKindOfClass:NSNumber.class] || ![b[i] isKindOfClass:NSNumber.class]) {
                    if (![a[i] isEqual:b[i]]) return YES;
                } else if (fabs([a[i] doubleValue] - [b[i] doubleValue]) > 0.5 / 255) return YES;
            }
        } else if (![mine isEqual:original]) return YES;
    }
    return NO;
}

- (void)reload
{
    self.reloading = YES;
    self.titles = [self.store titles];
    [self.tableView reloadData];
    NSString *editing = self.owner.editingThemeTitle;
    NSUInteger row = editing != nil ? [self.titles indexOfObject:editing] : NSNotFound;
    if (row != NSNotFound) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:(NSInteger)row];
    } else [self.tableView deselectAll:nil];
    self.reloading = NO;
    [self updateButtons];
}

- (nullable NSString *)selectedTitle
{
    NSInteger row = self.tableView.selectedRow;
    return row >= 0 && (NSUInteger)row < self.titles.count ? self.titles[(NSUInteger)row] : nil;
}

/// The row of the contextual menu, else the selected row.
- (nullable NSString *)targetTitle
{
    NSInteger row = self.tableView.clickedRow;
    if (row >= 0 && (NSUInteger)row < self.titles.count) return self.titles[(NSUInteger)row];
    return [self selectedTitle];
}

- (void)updateButtons
{
    NSString *title = [self selectedTitle];
    self.removeButton.enabled = title != nil && ![self isBundledTitle:title];
}

- (void)selectTitle:(NSString *)title
{
    NSUInteger row = [self.titles indexOfObject:title];
    if (row == NSNotFound) return;
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:(NSInteger)row];
}

/// The owner learns of the change first, so that the rows show the themes of Light and Dark Mode as they now are.
- (void)changedTitle:(nullable NSString *)oldTitle to:(nullable NSString *)newTitle select:(nullable NSString *)select
{
    [self.owner themeListDidChangeTitle:oldTitle to:newTitle];
    self.reloading = YES;
    self.titles = [self.store titles];
    [self.tableView reloadData];
    self.reloading = NO;
    if (select != nil && [self.titles containsObject:(NSString *_Nonnull)select]) [self selectTitle:(NSString *_Nonnull)select];
    else [self reload];
    [self updateButtons];
}

- (void)showError:(NSError *)error title:(NSString *)title
{
    NSString *message = nil;
    if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileWriteFileExistsError)
        message = [NSString stringWithFormat:self.text(@"theme.list.nameTaken"), title];
    else if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileWriteInvalidFileNameError)
        message = [NSString stringWithFormat:self.text(@"theme.list.badName"), title];
    else if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileReadCorruptFileError)
        message = [NSString stringWithFormat:self.text(@"theme.list.notTheme"), title];
    else if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) &&
             [self errorIsAboutTheme:error title:title])
        message = [NSString stringWithFormat:self.text(@"theme.list.missing"), title];
    [self.owner themeListShowError:message ?: error.localizedDescription ?: title];
}

// The error is about the theme's own file in the Themes folder, not a file elsewhere (where it was to be exported,
// or a file to import): only then is the theme "no longer in the Themes folder".
- (BOOL)errorIsAboutTheme:(NSError *)error title:(NSString *)title
{
    NSString *path = error.userInfo[NSFilePathErrorKey];
    if (path == nil) path = [error.userInfo[NSURLErrorKey] path];
    if (path == nil) return NO;
    if ([path isEqualToString:title]) return YES; // TSThemeFileStore names the theme by its title
    NSString *own = [self.store URLForTitle:title].path.stringByStandardizingPath;
    return own != nil && [path.stringByStandardizingPath isEqualToString:own];
}

- (void)refreshTitle:(NSString *)title
{
    NSUInteger row = [self.titles indexOfObject:title];
    if (row == NSNotFound) return;
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

- (void)themeWentMissing:(NSString *)title
{
    [self.owner themeListShowError:[NSString stringWithFormat:self.text(@"theme.list.missing"), title]];
    [self.owner themeListDidChangeTitle:title to:nil];
    NSArray<NSString *> *remaining = [self.store titles];
    NSString *next = [remaining containsObject:self.owner.lightThemeTitle ?: @""] ? self.owner.lightThemeTitle : remaining.firstObject;
    [self.owner themeListDidChooseTitle:next];
    [self reload];
}

- (void)themeCannotBeRead:(NSString *)title
{
    [self.owner themeListShowError:[NSString stringWithFormat:self.text(@"theme.list.notTheme"), title]];
    NSString *next = nil;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (self.owner.lightThemeTitle != nil) [candidates addObject:(NSString *_Nonnull)self.owner.lightThemeTitle];
    [candidates addObjectsFromArray:[self.store titles]];
    for (NSString *candidate in candidates)
        if (![candidate isEqualToString:title] && [self.store readTitle:candidate] != nil) { next = candidate; break; }
    [self.owner themeListDidChooseTitle:next];
    [self reload];
}

#pragma mark Actions

- (IBAction)addTheme:(id)sender
{
    NSDictionary<NSString *, id> *colors = self.owner.newThemeColors;
    if (colors == nil) return;
    NSString *untitled = self.text(@"theme.list.untitled");
    NSError *error = nil;
    NSString *title = [self.store addColors:colors title:untitled error:&error];
    if (title == nil) {
        [self showError:error title:untitled];
        return;
    }
    [self changedTitle:nil to:title select:title];
    [self beginEditingTitle:title];
}

- (IBAction)duplicateTheme:(id)sender
{
    NSString *title = [self targetTitle];
    NSDictionary<NSString *, id> *colors = title != nil ? [self.store readTitle:title] : nil;
    if (colors == nil) return;
    NSString *proposed = [NSString stringWithFormat:self.text(@"theme.list.copy"), title];
    NSError *error = nil;
    NSString *copy = [self.store addColors:colors title:proposed error:&error];
    if (copy == nil) {
        [self showError:error title:proposed];
        return;
    }
    [self changedTitle:nil to:copy select:copy];
}

- (IBAction)renameTheme:(id)sender
{
    NSString *title = [self targetTitle];
    if (title == nil || [self isBundledTitle:title]) return;
    [self selectTitle:title];
    [self beginEditingTitle:title];
}

- (void)beginEditingTitle:(NSString *)title
{
    NSUInteger row = [self.titles indexOfObject:title];
    if (row == NSNotFound || self.tableView.window == nil) return;
    [self.tableView editColumn:0 row:(NSInteger)row withEvent:nil select:YES];
}

- (IBAction)restoreTheme:(id)sender
{
    NSString *title = [self targetTitle];
    NSDictionary<NSString *, id> *bundled = title != nil ? [self bundledColorsForTitle:title] : nil;
    if (bundled == nil) return;
    NSError *error = nil;
    if (![self.store writeColors:bundled title:title error:&error]) {
        [self showError:error title:title];
        return;
    }
    [self changedTitle:title to:title select:self.selectedTitle];
}

- (IBAction)deleteTheme:(id)sender
{
    NSString *title = [self targetTitle];
    NSWindow *window = self.owner.themeListWindow;
    if (title == nil || [self isBundledTitle:title]) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:self.text(@"theme.list.deleteQuestion"), title];
    [alert addButtonWithTitle:self.text(@"theme.list.moveToTrash")].hasDestructiveAction = YES;
    [alert addButtonWithTitle:self.text(@"theme.list.cancel")];
    void (^answer)(NSModalResponse) = ^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [self trashTitle:title];
    };
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:answer];
}

- (void)trashTitle:(NSString *)title
{
    NSUInteger row = [self.titles indexOfObject:title];
    NSError *error = nil;
    if (![self.store trashTitle:title error:&error]) {
        [self showError:error title:title];
        return;
    }
    // The theme after it takes its place, or the one before it at the end of the list.
    NSString *next = nil;
    NSArray<NSString *> *remaining = [self.store titles];
    if (remaining.count > 0 && row != NSNotFound) next = remaining[MIN(row, remaining.count - 1)];
    BOOL wasEditing = [self.owner.editingThemeTitle isEqualToString:title];
    [self.owner themeListDidChangeTitle:title to:nil];
    if (wasEditing) [self.owner themeListDidChooseTitle:next];
    [self reload];
}

- (IBAction)exportTheme:(id)sender
{
    NSString *title = [self targetTitle];
    NSWindow *window = self.owner.themeListWindow;
    if (title == nil || window == nil) return;
    // Exported is what can be imported again. A theme that is gone, cannot be opened, or is not one (changed
    // elsewhere, or without a color) is not offered, and the reason is told.
    NSURL *source = [self.store URLForTitle:title];
    NSError *readError = nil;
    NSData *data = source != nil ? [NSData dataWithContentsOfURL:(NSURL *_Nonnull)source options:0 error:&readError] : nil;
    if (data == nil) {
        [self showError:readError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:@{NSFilePathErrorKey: title}] title:title];
        return;
    }
    if ([self.store readTitle:title] == nil || ![self exportable:(NSData *_Nonnull)data]) {
        [self.owner themeListShowError:[NSString stringWithFormat:self.text(@"theme.list.notTheme"), title]];
        return;
    }
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = [title stringByAppendingPathExtension:@"plist"] ?: title;
    [save beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        NSError *error = nil;
        NSURL *url = save.URL;
        if (response == NSModalResponseOK && url != nil && ![self.store exportTitle:title toURL:url check:^BOOL(NSData *exported) { return [self exportable:exported]; } error:&error])
            [self showError:error title:title];
    }];
}

// What an import of the file would require (themeListAcceptsData:).
- (BOOL)exportable:(NSData *)data
{
    id<TSSettingsThemeListOwner> owner = self.owner;
    return ![owner respondsToSelector:@selector(themeListAcceptsData:)] || [owner themeListAcceptsData:data];
}

- (IBAction)importThemes:(id)sender
{
    NSWindow *window = self.owner.themeListWindow;
    if (window == nil) return;
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowsMultipleSelection = YES;
    [open beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) [self importURLs:open.URLs];
    }];
}

- (NSArray<NSString *> *)importURLs:(NSArray<NSURL *> *)urls
{
    NSMutableArray<NSString *> *imported = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSError *error = nil;
        id<TSSettingsThemeListOwner> owner = self.owner;
        NSString *title = [self.store importFileAtURL:url check:^BOOL(NSData *data) {
            return ![owner respondsToSelector:@selector(themeListAcceptsData:)] || [owner themeListAcceptsData:data];
        } error:&error];
        if (title == nil) {
            [self showError:error title:url.lastPathComponent ?: @""];
            continue;
        }
        [imported addObject:title];
        [self.owner themeListDidChangeTitle:nil to:title];
    }
    [self reload];
    if (imported.lastObject != nil) [self selectTitle:imported.lastObject];
    return imported;
}

- (IBAction)showThemeInFinder:(id)sender
{
    NSString *title = [self targetTitle];
    NSURL *url = title != nil ? [self.store URLForTitle:title] : nil;
    if (url != nil) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
}

#pragma mark Menus

/// The actions menu names the selected theme; the contextual menu names none, as in Finder and CotEditor.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    BOOL context = menu == self.contextMenu;
    NSString *title = context ? [self targetTitle] : [self selectedTitle];
    NSMenuItem *icon = context ? nil : menu.itemArray.firstObject;
    [menu removeAllItems];
    if (icon != nil) [menu addItem:icon];
    if (context && self.tableView.clickedRow < 0) return;
    NSString *(^named)(NSString *) = ^NSString *(NSString *key) {
        return context ? self.text(key) : [NSString stringWithFormat:self.text([key stringByAppendingString:@".named"]), title ?: @""];
    };
    if (title != nil) {
        [self addItem:named(@"theme.list.duplicate") action:@selector(duplicateTheme:) to:menu];
        [self addItem:named(@"theme.list.rename") action:@selector(renameTheme:) to:menu];
        [self addItem:named(@"theme.list.restore") action:@selector(restoreTheme:) to:menu];
        if (context) [self addItem:self.text(@"theme.list.delete") action:@selector(deleteTheme:) to:menu];
        [self addItem:named(@"theme.list.export") action:@selector(exportTheme:) to:menu];
        NSMenuItem *finder = [self addItem:named(@"theme.list.showInFinder") action:@selector(showThemeInFinder:) to:menu];
        finder.alternate = YES;
        finder.keyEquivalentModifierMask = NSEventModifierFlagOption;
    }
    if (!context) {
        if (title != nil) [menu addItem:NSMenuItem.separatorItem];
        [self addItem:self.text(@"theme.list.import") action:@selector(importThemes:) to:menu];
    }
}

- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action to:(NSMenu *)menu
{
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    NSString *title = item.menu == self.contextMenu ? [self targetTitle] : [self selectedTitle];
    SEL action = item.action;
    if (action == @selector(importThemes:)) return YES;
    if (title == nil) return NO;
    if (action == @selector(renameTheme:) || action == @selector(deleteTheme:)) return ![self isBundledTitle:title];
    if (action == @selector(restoreTheme:)) return [self isChangedTitle:title];
    return YES;
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.titles.count;
}

- (NSImageView *)markWithSymbol:(NSString *)symbol description:(NSString *)description pointSize:(CGFloat)size
{
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
    image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular]] ?: image;
    NSImageView *view = [NSImageView imageViewWithImage:image ?: [NSImage new]];
    view.contentTintColor = NSColor.secondaryLabelColor;
    view.toolTip = description;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row
{
    NSString *title = self.titles[(NSUInteger)row];
    BOOL bundled = [self isBundledTitle:title];
    NSTableCellView *cell = [NSTableCellView new];
    NSTextField *field = [NSTextField textFieldWithString:title];
    field.bordered = NO;
    field.drawsBackground = NO;
    field.editable = !bundled;
    field.delegate = self;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.allowsExpansionToolTips = YES;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    // A theme's name is the user's own: Settings search does not index it.
    field.accessibilityIdentifier = @"settings.user-data";
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    cell.textField = field;
    [cell addSubview:field];

    NSMutableArray<NSView *> *marks = [NSMutableArray array];
    if (bundled && [self isChangedTitle:title])
        [marks addObject:[self markWithSymbol:@"circle.fill" description:self.text(@"theme.list.changed") pointSize:6]];
    if ([self.owner.lightThemeTitle isEqualToString:title])
        [marks addObject:[self markWithSymbol:@"sun.max" description:self.text(@"catalog.appearance.0.0.title") pointSize:12]];
    if ([self.owner.darkThemeTitle isEqualToString:title])
        [marks addObject:[self markWithSymbol:@"moon" description:self.text(@"catalog.appearance.0.1.title") pointSize:12]];
    NSStackView *stack = [NSStackView stackViewWithViews:marks];
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [cell addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
        [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:field.trailingAnchor constant:6],
        [stack.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
        [stack.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    cell.identifier = [@"settings.theme-list.row." stringByAppendingString:title];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
    if (self.reloading) return;
    NSString *title = [self selectedTitle];
    if (title != nil && ![title isEqualToString:self.owner.editingThemeTitle ?: @""]) [self.owner themeListDidChooseTitle:title];
}

/// Renaming in the list renames the theme's file.
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSInteger row = [self.tableView rowForView:field];
    if (row < 0 || (NSUInteger)row >= self.titles.count) return;
    NSString *old = self.titles[(NSUInteger)row];
    // Composed, as the names of the list (TSThemeFileStore titles).
    NSString *new = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].precomposedStringWithCanonicalMapping;
    if (new.length == 0 || [new isEqualToString:old]) {
        field.stringValue = old;
        return;
    }
    NSError *error = nil;
    if (![self.store renameTitle:old to:new error:&error]) {
        field.stringValue = old;
        [self showError:error title:new];
        return;
    }
    [self changedTitle:old to:new select:new];
}

#pragma mark Dragging

/// Theme files dropped on the list are added; a row dragged out is a copy of its file.
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (info.draggingSource == tableView) return NSDragOperationNone;
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls)
        if ([url.pathExtension.lowercaseString isEqualToString:@"plist"]) {
            [tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
            return NSDragOperationCopy;
        }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray<NSURL *> *themes = [NSMutableArray array];
    for (NSURL *url in urls)
        if ([url.pathExtension.lowercaseString isEqualToString:@"plist"]) [themes addObject:url];
    return [self importURLs:themes].count > 0;
}

- (nullable id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= self.titles.count) return nil;
    return [self.store URLForTitle:self.titles[(NSUInteger)row]];
}

@end
