// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMultipleReplaceWindowController.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindController+MultipleReplace.h"
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindHighlights.h"

#define TSLocalized TSAdvancedFindLocalized

@interface TSMultipleReplaceWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, readwrite) TSMultipleReplaceRuleTable *ruleTable;
@property (nonatomic, readwrite, copy, nullable) NSString *selectedSetName;
@property (nonatomic, readwrite) NSTextField *statusField;
@property (nonatomic) NSTableView *setTable;
@property (nonatomic, copy) NSArray<NSString *> *setNames;
@property (nonatomic) NSButton *inSelectionBox;
/// Highlight and Replace All.
@property (nonatomic, copy) NSArray<NSButton *> *actionButtons;
@property (nonatomic, strong, nullable) NSPopover *optionsPopover;
/// Kept while its view is shown: the check boxes target it.
@property (nonatomic, strong, nullable) TSAdvancedFindOptionsForm *optionsForm;
@end

@implementation TSMultipleReplaceWindowController

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 860, 440)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                  backing:NSBackingStoreBuffered defer:YES];
    panel.title = TSLocalized(@"MultipleReplace.Title", @"Multiple Replace");
    panel.hidesOnDeactivate = YES;
    panel.becomesKeyOnlyIfNeeded = NO;
    panel.contentMinSize = NSMakeSize(680, 300);
    if (!(self = [super initWithWindow:panel]))
        return nil;
    _findController = findController;
    _library = library;
    // After every event, as menu items are: the target may have changed (another window) or become read-only.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:NSApplicationDidUpdateNotification object:nil];
    // A long action starts or ends: Highlight and Replace All are gray meanwhile.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:TSAdvancedFindTaskDidChangeNotification object:findController];
    _setNames = @[];
    _ruleTable = [TSMultipleReplaceRuleTable new];
    __weak typeof(self) weakSelf = self;
    _ruleTable.setChangedHandler = ^(TSRegexMultipleReplace *set) { [weakSelf saveSet:set]; };
    [self buildContent];
    [self reloadSets];
    return self;
}

#pragma mark Building

- (NSScrollView *)scroll:(NSView *)document
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    scroll.documentView = document;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    return scroll;
}

- (NSButton *)symbolButton:(NSString *)symbol tipKey:(NSString *)key english:(NSString *)english action:(SEL)action
{
    NSString *tip = TSLocalized(key, english);
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip] ?: [NSImage new];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.bezelStyle = NSBezelStyleSmallSquare;
    button.toolTip = tip;
    return button;
}

- (NSButton *)button:(NSString *)key english:(NSString *)english action:(SEL)action
{
    return [NSButton buttonWithTitle:TSLocalized(key, english) target:self action:action];
}

- (NSView *)makeSetList
{
    self.setTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 180, 300)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.title = TSLocalized(@"MultipleReplace.Sets", @"Sets");
    [self.setTable addTableColumn:column];
    self.setTable.headerView = nil;
    self.setTable.style = NSTableViewStyleSourceList;
    self.setTable.dataSource = self;
    self.setTable.delegate = self;
    NSPopUpButton *action = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    action.bezelStyle = NSBezelStyleSmallSquare;
    NSMenuItem *icon = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    icon.image = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:nil];
    [action.menu addItem:icon];
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.Duplicate", @"Duplicate") action:@selector(duplicateSet:) keyEquivalent:@""].target = self;
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.Import", @"Import…") action:@selector(importSet:) keyEquivalent:@""].target = self;
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.Export", @"Export…") action:@selector(exportSet:) keyEquivalent:@""].target = self;
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.ShowInFinder", @"Show in Finder") action:@selector(showInFinder:) keyEquivalent:@""].target = self;
    NSStackView *bar = [NSStackView stackViewWithViews:@[
        [self symbolButton:@"plus" tipKey:@"MultipleReplace.AddSet" english:@"New Set" action:@selector(addSet:)],
        [self symbolButton:@"minus" tipKey:@"MultipleReplace.RemoveSet" english:@"Move the Set to the Trash" action:@selector(removeSet:)],
        action]];
    bar.spacing = 0;
    NSScrollView *scroll = [self scroll:self.setTable];
    NSStackView *list = [NSStackView stackViewWithViews:@[scroll, bar]];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 0;
    [scroll.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    [list.widthAnchor constraintEqualToConstant:180].active = YES;
    return list;
}

- (NSView *)makeRuleArea
{
    NSScrollView *scroll = [self scroll:self.ruleTable.tableView];
    NSStackView *ruleButtons = [NSStackView stackViewWithViews:@[
        [self symbolButton:@"plus" tipKey:@"MultipleReplace.AddRule" english:@"Add a Rule" action:@selector(addRule:)],
        [self symbolButton:@"minus" tipKey:@"MultipleReplace.RemoveRule" english:@"Remove the Selected Rules" action:@selector(removeRules:)]]];
    ruleButtons.spacing = 0;
    NSButton *options = [self button:@"MultipleReplace.Options" english:@"Options…" action:@selector(showOptions:)];
    self.inSelectionBox = [NSButton checkboxWithTitle:TSLocalized(@"AdvancedFind.InSelection", @"In selection") target:self action:@selector(inSelectionChanged:)];
    NSButton *highlight = [self button:@"AdvancedFind.Highlight" english:@"Highlight" action:@selector(highlight:)];
    NSButton *replace = [self button:@"AdvancedFind.ReplaceAll" english:@"Replace All" action:@selector(replaceAll:)];
    replace.keyEquivalent = @"\r";
    self.actionButtons = @[highlight, replace];
    NSStackView *bar = [NSStackView stackViewWithViews:@[ruleButtons, [NSView new], options, self.inSelectionBox, highlight, replace]];
    bar.spacing = 8;
    [bar setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    // A message wraps rather than being cut: in some languages a rule's problem is two or three lines long.
    self.statusField = [NSTextField wrappingLabelWithString:@""];
    self.statusField.selectable = NO;
    self.statusField.textColor = NSColor.secondaryLabelColor;
    [self.statusField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.statusField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    NSStackView *area = [NSStackView stackViewWithViews:@[scroll, bar, self.statusField]];
    area.orientation = NSUserInterfaceLayoutOrientationVertical;
    area.alignment = NSLayoutAttributeLeading;
    area.spacing = 8;
    for (NSView *view in @[scroll, bar, self.statusField])
        [view.widthAnchor constraintEqualToAnchor:area.widthAnchor].active = YES;
    return area;
}

- (void)buildContent
{
    NSStackView *content = [NSStackView stackViewWithViews:@[[self makeSetList], [self makeRuleArea]]];
    content.alignment = NSLayoutAttributeTop;
    content.distribution = NSStackViewDistributionFill;
    content.spacing = 20;
    content.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    for (NSView *view in content.arrangedSubviews)
        [view.heightAnchor constraintEqualToAnchor:content.heightAnchor constant:-40].active = YES;
    self.window.contentView = content;
}

#pragma mark Sets

- (void)reloadSets
{
    NSString *selected = self.selectedSetName;
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    NSUInteger index = selected ? [self.setNames indexOfObject:selected] : NSNotFound;
    if (index == NSNotFound && self.setNames.count > 0)
        index = 0;
    if (index != NSNotFound)
        [self selectSetNamed:self.setNames[index]];
    else
        [self showSetNamed:nil];
}

- (void)selectSetNamed:(NSString *)name
{
    NSUInteger index = [self.setNames indexOfObject:name];
    if (index == NSNotFound)
        return;
    [self.setTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self showSetNamed:name];
}

- (void)showSetNamed:(nullable NSString *)name
{
    NSString *shown = self.selectedSetName;
    if (name && shown && [shown isEqualToString:(NSString *_Nonnull)name] && self.ruleTable.set)
        return;
    NSError *error = nil;
    TSRegexMultipleReplace *set = name ? [self.library setNamed:(NSString *_Nonnull)name error:&error] : nil;
    self.selectedSetName = set ? name : nil;
    self.ruleTable.set = set;
    [self showStatus:error ? error.localizedDescription : @"" error:error != nil];
}

- (void)saveSet:(TSRegexMultipleReplace *)set
{
    NSString *name = self.selectedSetName;
    NSError *error = nil;
    if (name && ![self.library saveSet:set named:name error:&error])
        [self showStatus:error.localizedDescription error:YES];
    else
        [self showProblems];
}

- (void)showStatus:(NSString *)message error:(BOOL)error
{
    self.statusField.stringValue = message;
    self.statusField.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
}

- (void)showProblems
{
    NSDictionary<NSNumber *, NSError *> *problems = self.ruleTable.set ? TSMultipleReplaceProblems((TSRegexMultipleReplace *_Nonnull)self.ruleTable.set) : @{};
    if (problems.count == 0) {
        [self showStatus:@"" error:NO];
        return;
    }
    NSNumber *first = [problems.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject;
    NSString *format = TSLocalized(@"MultipleReplace.Problem", @"Rule %lu is skipped: %@");
    [self showStatus:[NSString stringWithFormat:format, first.unsignedLongValue + 1, problems[first].localizedDescription] error:YES];
}

- (IBAction)addSet:(nullable id)sender
{
    NSString *name = [self.library availableNameForName:TSLocalized(@"MultipleReplace.Untitled", @"Untitled")];
    TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"" replaceString:@"" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:TSRegexMultipleReplace.defaultTextualOptions
                                                       regularExpressionOptions:TSRegexMultipleReplace.defaultRegularExpressionOptions
                                                              replacementSyntax:TSRegexReplacementSyntaxICU];
    NSError *error = nil;
    if (![self.library saveSet:set named:name error:&error]) {
        [self showStatus:error.localizedDescription error:YES];
        return;
    }
    self.selectedSetName = nil;
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    [self selectSetNamed:name];
    NSInteger row = (NSInteger)[self.setNames indexOfObject:name];
    if (self.window.isVisible && row >= 0)
        [self.setTable editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)duplicateSet:(nullable id)sender
{
    NSString *name = self.selectedSetName;
    TSRegexMultipleReplace *set = self.ruleTable.set;
    if (!name || !set)
        return;
    NSString *copyName = [self.library availableNameForName:[NSString stringWithFormat:TSLocalized(@"MultipleReplace.CopyName", @"%@ copy"), name]];
    NSError *error = nil;
    if (![self.library saveSet:set named:copyName error:&error])
        [self showStatus:error.localizedDescription error:YES];
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    [self selectSetNamed:copyName];
}

- (IBAction)removeSet:(nullable id)sender
{
    NSString *name = self.selectedSetName;
    if (!name)
        return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:TSLocalized(@"MultipleReplace.RemoveQuestion", @"Move “%@” to the Trash?"), name];
    [alert addButtonWithTitle:TSLocalized(@"MultipleReplace.MoveToTrash", @"Move to Trash")];
    [alert addButtonWithTitle:TSLocalized(@"AdvancedFind.Cancel", @"Cancel")];
    NSWindow *window = self.window;
    if (!window)
        return;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn)
            return;
        NSError *error = nil;
        if (![self.library removeSetNamed:name error:&error])
            [self showStatus:error.localizedDescription error:YES];
        self.selectedSetName = nil;
        [self reloadSets];
    }];
}

- (void)importSet:(id)sender
{
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowsMultipleSelection = YES;
    NSWindow *window = self.window;
    if (!window)
        return;
    [open beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK)
            return;
        NSString *last = nil;
        for (NSURL *url in open.URLs) {
            NSError *error = nil;
            NSString *name = [self.library importFileAtURL:url error:&error];
            if (name)
                last = name;
            else
                [self showStatus:error.localizedDescription error:YES];
        }
        self.setNames = self.library.setNames;
        [self.setTable reloadData];
        if (last)
            [self selectSetNamed:last];
    }];
}

- (void)exportSet:(id)sender
{
    NSString *name = self.selectedSetName;
    NSWindow *window = self.window;
    if (!name || !window)
        return;
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = [name stringByAppendingPathExtension:TSMultipleReplaceLibrary.fileExtension] ?: name;
    [save beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        NSError *error = nil;
        if (response == NSModalResponseOK && save.URL && ![self.library exportSetNamed:name toURL:(NSURL *_Nonnull)save.URL error:&error])
            [self showStatus:error.localizedDescription error:YES];
    }];
}

- (void)showInFinder:(id)sender
{
    [NSFileManager.defaultManager createDirectoryAtURL:self.library.directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.library.directory]];
}

#pragma mark Set list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.setNames.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row
{
    NSTextField *field = [NSTextField textFieldWithString:self.setNames[(NSUInteger)row]];
    field.bordered = NO;
    field.drawsBackground = NO;
    field.editable = YES;
    field.delegate = self;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    return field;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = self.setTable.selectedRow;
    [self showSetNamed:row >= 0 ? self.setNames[(NSUInteger)row] : nil];
}

/// Renaming in the list renames the file.
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSInteger row = [self.setTable rowForView:field];
    if (row < 0)
        return;
    NSString *old = self.setNames[(NSUInteger)row], *new = field.stringValue;
    NSError *error = nil;
    if (![self.library renameSetNamed:old to:new error:&error]) {
        field.stringValue = old;
        [self showStatus:error.localizedDescription error:YES];
        return;
    }
    self.selectedSetName = new;
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    [self selectSetNamed:new];
}

#pragma mark Rules and running

- (void)addRule:(id)sender { [self.ruleTable addRule]; }
- (void)removeRules:(id)sender { [self.ruleTable removeSelectedRules]; }
- (void)inSelectionChanged:(NSButton *)sender { self.inSelection = sender.state == NSControlStateValueOn; }

- (void)setInSelection:(BOOL)inSelection
{
    _inSelection = inSelection;
    self.inSelectionBox.state = inSelection ? NSControlStateValueOn : NSControlStateValueOff;
}

- (NSView *)makeOptionsView
{
    TSRegexMultipleReplace *set = self.ruleTable.set;
    TSAdvancedFindOptionsForm *form = [[TSAdvancedFindOptionsForm alloc] initWithStyle:TSAdvancedFindOptionsFormStyleSet
        textualOptions:set ? set.textualOptions : TSRegexMultipleReplace.defaultTextualOptions
        regularExpressionOptions:set ? set.regularExpressionOptions : TSRegexMultipleReplace.defaultRegularExpressionOptions
        replacementSyntax:set ? set.replacementSyntax : TSRegexReplacementSyntaxICU];
    __weak typeof(self) weakSelf = self;
    form.changeHandler = ^(TSAdvancedFindOptionsForm *changed) {
        TSRegexMultipleReplace *current = weakSelf.ruleTable.set;
        if (!current)
            return;
        TSRegexMultipleReplace *updated = [[TSRegexMultipleReplace alloc] initWithRules:current.rules textualOptions:changed.textualOptions
                                                               regularExpressionOptions:changed.regularExpressionOptions replacementSyntax:changed.replacementSyntax];
        weakSelf.ruleTable.set = updated;
        [weakSelf saveSet:updated];
    };
    self.optionsForm = form;
    return form.view;
}

- (void)showOptions:(NSButton *)sender
{
    if (!self.ruleTable.set)
        return;
    NSViewController *controller = [NSViewController new];
    NSView *view = [self makeOptionsView];
    [view layoutSubtreeIfNeeded];
    controller.preferredContentSize = view.fittingSize; // otherwise the popover squeezes the rows
    [view setFrameSize:view.fittingSize];
    controller.view = view;
    self.optionsPopover = [NSPopover new];
    self.optionsPopover.behavior = NSPopoverBehaviorTransient;
    self.optionsPopover.contentViewController = controller;
    self.optionsPopover.contentSize = controller.preferredContentSize;
    [self.optionsPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (nullable NSTextView *)target:(nullable NSTextView *)textView
{
    return textView ?: TSAdvancedFindController.targetTextView;
}

- (BOOL)replaceAllInTextView:(nullable NSTextView *)textView
{
    NSTextView *target = [self target:textView];
    TSRegexMultipleReplace *set = self.ruleTable.set;
    if (!target || !set) {
        self.findController.beepHandler();
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    return [self.findController applyMultipleReplace:set inTextView:target inSelection:self.inSelection completion:^(TSRegexMultipleReplaceResult *_Nullable result) {
        [weakSelf showResult:result];
    }];
}

/// The counts of each rule and the status line after a multiple replacement; nothing when it was cancelled (the find
/// panel's status says so) or the text changed meanwhile.
- (void)showResult:(nullable TSRegexMultipleReplaceResult *)result
{
    if (!result)
        return;
    {
        self.ruleTable.counts = result.counts;
        NSString *message = [NSString stringWithFormat:TSLocalized(@"AdvancedFind.Replaced", @"%lu replaced"), (unsigned long)result.totalCount];
        if (result.errors.count > 0) {
            NSMutableArray<NSString *> *numbers = [NSMutableArray array];
            for (NSNumber *index in [result.errors.allKeys sortedArrayUsingSelector:@selector(compare:)])
                [numbers addObject:@(index.unsignedIntegerValue + 1).stringValue];
            NSString *format = TSLocalized(@"MultipleReplace.SkippedRules", @"(rule %@ skipped; see ⚠︎)");
            message = [message stringByAppendingFormat:@" %@", [NSString stringWithFormat:format, [numbers componentsJoinedByString:@", "]]];
        }
        [self showStatus:message error:NO];
    }
}

- (BOOL)highlightInTextView:(nullable NSTextView *)textView
{
    NSTextView *target = [self target:textView];
    TSRegexMultipleReplace *set = self.ruleTable.set;
    if (!target || !set) {
        self.findController.beepHandler();
        return NO;
    }
    NSUInteger count = [self.findController highlightMultipleReplace:set inTextView:target inSelection:self.inSelection];
    [self showStatus:[NSString stringWithFormat:TSLocalized(@"AdvancedFind.Found", @"%lu found"), (unsigned long)count] error:NO];
    return count > 0;
}

- (void)replaceAll:(id)sender { [self replaceAllInTextView:nil]; }

- (void)applicationDidUpdate:(NSNotification *)notification
{
    if (self.window.isVisible || TSAdvancedFindController.testTargetTextView)
        [self updateButtons];
}

/// Highlight and Replace All, as the panel's buttons: Replace All is gray in a read-only text view. With no target
/// they stay as they are and beep.
- (void)updateButtons
{
    NSTextView *target = [self target:nil];
    TSAdvancedFindController *controller = self.findController;
    static const TSAdvancedFindAction actions[] = {TSAdvancedFindActionHighlight, TSAdvancedFindActionReplaceAll};
    NSArray<NSButton *> *buttons = self.actionButtons;
    for (NSUInteger index = 0; index < buttons.count && index < sizeof(actions) / sizeof(actions[0]); index++) {
        BOOL enabled = target ? [controller validateAction:actions[index] forTextView:target] : controller.runningTask == nil;
        if (buttons[index].enabled != enabled)
            buttons[index].enabled = enabled;
    }
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)highlight:(id)sender { [self highlightInTextView:nil]; }

@end
