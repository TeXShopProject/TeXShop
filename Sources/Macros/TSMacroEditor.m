/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSMacroEditor.m 108 2006-02-10 13:50:25Z fingolfin $
 *
 * Created by Mitsuhiro Shishikura on Fri Dec 20 2002.
 *
 */

#import "TSMacroSelection.h"
#import "TSMacroEditor.h"

#import "TSMacroOutlineController.h"
#import "TSMacroMenuController.h"
#import "TSKeyboardShortcuts.h"
#import "TSTextView.h"
#import "TSEncodingSupport.h"
#import "NSText-Extras.h"
#import "globals.h"
#import "TSDialogButtonLayout.h"
#import "TSColorSupport.h"
#import "TSMarkMenu.h"
#import "TSPreferenceEffects.h"
#import "TSSyntaxHighlighter.h"
#import "TSSyntaxMacroContentScanner.h"
#import "TSSyntaxTeXScanner.h"

static void *TSMacroContentAppearanceContext = &TSMacroContentAppearanceContext;


@implementation TSMacroEditor

static id sharedMacroEditor = nil;
static TSFilterMode savedFilter = kNoFilterMode;

+ (id)sharedInstance
{
	if (sharedMacroEditor == nil)
		sharedMacroEditor = [[TSMacroEditor alloc] init];
	return sharedMacroEditor;
}

- (id)init
{
	if (!sharedMacroEditor)
    {
		sharedMacroEditor = [super init];
		self.previousItem = nil;
	}
	return sharedMacroEditor;
}

/*
- (void)dealloc
{
	if (self != sharedMacroEditor)
		[super dealloc];	// Don't free our shared instance
}
*/

- (void)awakeFromNib
{
}


- (void)openMacroEditorSelectingMacroAtIndexPath:(NSIndexPath *)path name:(NSString *)name key:(NSString *)key
{
    [self openMacroEditor:nil];
    if (window == nil || outlineView == nil || outlineController == nil || [window attachedSheet] != nil) { return; }
    if (![window makeFirstResponder:window]) { return; }
    // Commit current fields to the in-memory tree only; never save or discard edits.
    [self reflectChangesInEditor:YES];
    TSMacroTreeNode *root = [outlineController rootOfTree];
    if (root == nil) { return; }
    TSMacroTreeNode *node = [TSMacroSelection nodeInRoot:root indexPath:path name:name key:key];
    if (node == nil) { return; }
    NSMutableArray<TSMacroTreeNode *> *parents = [NSMutableArray array];
    for (TSMacroTreeNode *parent = node.nodeParent; parent != nil && parent != root; parent = parent.nodeParent) { [parents addObject:parent]; }
    for (TSMacroTreeNode *parent in parents.reverseObjectEnumerator) { [outlineView expandItem:parent]; }
    NSInteger row = [outlineView rowForItem:node];
    if (row < 0) { return; }
    [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [outlineView scrollRowToVisible:row];
}

- (IBAction)openMacroEditor: (id)sender
{
	if (!outlineView) {
		// load TSMacroEditor window
		[self loadUI];
		// load tree from macroDictionary
		TSMacroTreeNode *newRoot = [TSMacroTreeNode nodeFromDictionary:
							[[TSMacroMenuController sharedInstance] macroDict]];
		savedFilter = g_shouldFilter;

		// register for ntification
		[[NSNotificationCenter defaultCenter] addObserver:self
					selector:@selector(outlineViewSelectionChanged:)
					name: NSOutlineViewSelectionDidChangeNotification object: outlineView];
		[[NSNotificationCenter defaultCenter] addObserver:self
					selector:@selector(outlineViewItemsChanged:)
					name: TSMacroOutlineViewAddedItemNotification object: outlineView];
		[[NSNotificationCenter defaultCenter] addObserver:self
					selector:@selector(outlineViewItemsChanged:)
					name: TSMacroOutlineViewRemovedItemNotification object: outlineView];
		[[NSNotificationCenter defaultCenter] addObserver:self
					selector:@selector(outlineViewItemsChanged:)
					name: TSMacroOutlineViewAcceptedDropNotification object: outlineView];
		// set up variables
		[outlineController setRootOfTree: newRoot];
        [self rememberOriginalShortcutKeys];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuShortcutsChanged:) name:TSMacroShortcutsChangedNotification object:nil]; // one can use [outlineView dataSource] instead
		self.previousItem = nil;
		dataTouched = NO;
		nameTouched = NO;
		contentTouched = NO;
		keyTouched = NO;
		// set up menu items
		NSMenu *macroMenu = [[[NSApp mainMenu] itemWithTitle:
					NSLocalizedString(@"Macros", @"Macros")] submenu];
		id item = [macroMenu itemWithTitle:
						NSLocalizedString(@"Open Macro Editor...", @"Open Macro Editor...")];
		if (item)
		{
			[item setTitle: NSLocalizedString(@"Close Macro Editor", @"Close Macro Editor")];
			[item setTarget: window];
			[item setAction: @selector(performClose:)];
		}
		item = [macroMenu insertItemWithTitle:
					NSLocalizedString(@"Add macros from file...", @"Add macros from file...")
					action: @selector(readDictionaryToMacroEditor:) keyEquivalent:@"" atIndex: 1];
		[item setTarget: self];
		item = [macroMenu insertItemWithTitle:
					NSLocalizedString(@"Save selection to file...", @"Save selection to file...")
					action: @selector(saveSelection:) keyEquivalent:@"" atIndex: 2];
		[item setTarget: self];
	}
	[self refreshShortcutConflicts];
	// Settings may have changed the font or the themes since the editor was last open.
	[contentTextView setFontSafely:[self contentFont]];
	[self applyContentAppearance:nil];
	[window makeKeyAndOrderFront: nil];
}

// BEGIN content appearance
// The contents show in the source font, or the console font when Settings asks
// for it, and in the text, background and insertion point colors of the theme
// for the window's light or dark appearance.
- (NSFont *)contentFont
{
    NSFont *font = nil;
    if ([SUD boolForKey:SameFontForMacroKey])
        font = [NSFont fontWithName:[SUD stringForKey:ConsoleFontNameKey] size:[SUD floatForKey:ConsoleFontSizeKey]];
    else {
        id data = [SUD objectForKey:DocumentFontKey];
        if ([data isKindOfClass:NSData.class]) {
            @try { font = [NSUnarchiver unarchiveObjectWithData:data]; } @catch (NSException *exception) { font = nil; }
        }
    }
    return [font isKindOfClass:NSFont.class] ? font : [NSFont userFontOfSize:12.0];
}
- (void)applyContentAppearance:(NSNotification *)notification
{
    if (contentTextView == nil) return;
    NSAppearance *appearance = [window effectiveAppearance] ?: NSApp.effectiveAppearance;
    BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSDictionary *theme = dark ? darkColors : liteColors;
    TSColorSupport *colors = [TSColorSupport sharedInstance];
    // As the document's source: opaque theme colors, whatever alpha a theme stores
    // (the Solarized themes store a transparent background), and the built-in
    // color for a key the theme does not have.
    NSColor *(^opaque)(NSString *) = ^NSColor *(NSString *key) {
        return [colors colorFromDictionary:theme andKey:key] ?: [[colors colorForKey:key fromDictionary:theme isWindowDark:dark] colorWithAlphaComponent:1];
    };
    NSColor *text = opaque(@"EditorText");
    contentTextView.drawsBackground = YES;
    contentTextView.backgroundColor = opaque(@"EditorBackground");
    contentTextView.textColor = text;
    contentTextView.insertionPointColor = opaque(@"EditorInsertionPoint");
    NSMutableDictionary *typing = [contentTextView.typingAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
    typing[NSForegroundColorAttributeName] = text;
    contentTextView.typingAttributes = typing;
    [self updateContentHighlightingWithTheme:theme dark:dark];
}
// END content appearance
// BEGIN content highlighting
// The contents are colored as the source is: a TeX macro by the rules of the source,
// an AppleScript macro by its own, each with the placeholders it replaces, in the
// theme's colors. Syntax coloring off in Settings leaves them plain.
- (void)updateContentHighlightingWithTheme:(NSDictionary *)theme dark:(BOOL)dark
{
    if (contentTextView == nil) return;
    if (![SUD boolForKey:SyntaxColoringEnabledKey]) {
        [self.contentHighlighter invalidate];
        self.contentHighlighter = nil;
        return;
    }
    TSSyntaxColorScheme *scheme = [[TSSyntaxColorScheme alloc] initWithTheme:theme ?: @{} dark:dark];
    TSMutableSyntaxTeXOptions *options = [TSMutableSyntaxTeXOptions new];
    options.texCharacter = (unichar)g_texChar;
    options.colorsExpl3 = [SUD boolForKey:expl3SyntaxColoringKey];
    options.makesAtLetter = [SUD boolForKey:MakeatletterEnabledKey];
    options.colorsIndex = [SUD boolForKey:IndexColorStartKey];
    options.colorsFootnote = [SUD boolForKey:SyntaxColorFootnoteKey];
    options.marksFullwidthSymbols = [scheme attributesForRole:TSSyntaxRoleFullwidthSymbol].count > 0;
    TSSyntaxMacroContentScanner *scanner = [[TSSyntaxMacroContentScanner alloc] initWithTeXOptions:options];
    if (self.contentHighlighter.textView != contentTextView) {
        [self.contentHighlighter invalidate];
        self.contentHighlighter = [[TSSyntaxHighlighter alloc] initWithTextView:contentTextView scanner:scanner scheme:scheme];
        [self.contentHighlighter followEdits];
    } else {
        self.contentHighlighter.scheme = scheme;
        self.contentHighlighter.scanner = scanner;
    }
}
// END content highlighting
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == TSMacroContentAppearanceContext) [self applyContentAppearance:nil];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)loadUI
{
    
	if (!outlineView) {
		if (![NSBundle loadNibNamed:@"MacroEditor" owner:self]) {
			// TODO: Show an error dialog to the user here
		//	NSLog(@"Failed to load MacroEditor.nib");
			NSBeep();
			return;
		}
        [self installShortcutStatus];
        [self installListControls];
        [self installPlaceholderNote];
        [self layoutDialogButtons];

		// set up window and UI elements
		// [window setDelegate: self];	// not necessary if it is connected in IB

		[outlineView setTarget: self];
		[outlineView setDoubleAction: @selector(doMacroTest:)];
        [outlineView setBackgroundColor: NSColor.textBackgroundColor];
		// custom text view, with a TextKit 1 text system for syntax coloring
		NSScrollView *scrollView = [contentTextView enclosingScrollView];
		NSSize contentSize = [scrollView contentSize];
		NSTextStorage *contentStorage = [[NSTextStorage alloc] init];
		NSLayoutManager *contentLayout = [[NSLayoutManager alloc] init];
		[contentStorage addLayoutManager:contentLayout];
		NSTextContainer *contentContainer = [[NSTextContainer alloc] initWithSize:NSMakeSize(contentSize.width, CGFLOAT_MAX)];
		[contentContainer setWidthTracksTextView:YES];
		[contentLayout addTextContainer:contentContainer];
		contentTextView = [[TSTextView alloc] initWithFrame:
						NSMakeRect(0, 0, contentSize.width, contentSize.height) textContainer:contentContainer];
		[contentTextView setMinSize:NSMakeSize(0, contentSize.height)];
		[contentTextView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
		[contentTextView setVerticallyResizable:YES];
		[contentTextView setHorizontallyResizable:NO];
		[contentTextView setAutoresizingMask: NSViewWidthSizable];
		[contentTextView setDelegate:self];
		[contentTextView setAllowsUndo:YES];
		// Plain text: what is pasted keeps no colors or fonts of its own, and the
		// Font panel changes the font of all the contents. Only the text is saved.
		[contentTextView setRichText:NO];
		[contentTextView setUsesFontPanel:YES];
        [contentTextView setFontSafely:[self contentFont]];
        [contentTextView setContinuousSpellCheckingEnabled: NO];
        [contentTextView setAutomaticSpellingCorrectionEnabled: NO];
        [contentTextView setSmartInsertDeleteEnabled: NO];
        [contentTextView setAutomaticDashSubstitutionEnabled: NO];
        [contentTextView setAutomaticDataDetectionEnabled: NO];
        [contentTextView setAutomaticLinkDetectionEnabled: NO];
        [contentTextView setAutomaticQuoteSubstitutionEnabled: NO];
        [contentTextView setAutomaticSpellingCorrectionEnabled: NO];
        [contentTextView setAutomaticTextReplacementEnabled: NO];

        [scrollView setDocumentView:contentTextView];
        [self applyContentAppearance:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyContentAppearance:) name:SourceColorChangedNotification object:nil];
        // Syntax coloring turned on or off, expl3 and \makeatletter.
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyContentAppearance:) name:DocumentSyntaxColorNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyContentAppearance:) name:TSPreferenceNeedsRecolorNotification object:nil];
        [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:TSMacroContentAppearanceContext];
		// [contentTextView release];
		// text fields
        [nameField setDelegate: [TSEncodingSupport sharedInstance]];
		[keyField setDelegate: [TSEncodingSupport sharedInstance]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pendingKeyChanged:) name:NSControlTextDidChangeNotification object:keyField];
		// set up properties for UI
		[nameField setEditable: NO];
		[contentTextView setEditable: NO];
		[keyField setEditable: NO];
		[shiftCheckBox setState: NSOffState];
		[shiftCheckBox setEnabled: NO];
		[optionCheckBox setState: NSOffState];
		[optionCheckBox setEnabled: NO];
		[controlCheckBox setState: NSOffState];
		[controlCheckBox setEnabled: NO];
		[testButton setEnabled: NO];
		[deleteButton setEnabled: NO];
		[duplicateButton setEnabled: NO];
		[self syncListControls];
	}
}


- (void)installShortcutStatus
{
    if (self.shortcutStatus) return;
    NSView *host = [window contentView];
    NSMutableSet *bottomControls = [NSMutableSet set];
    CGFloat bottom = 0, lowest = CGFLOAT_MAX;
    for (NSView *button in @[saveButton, cancelButton, testButton]) {
        NSView *view = button;
        while (view.superview != host) view = view.superview;
        [bottomControls addObject:view]; bottom = MAX(bottom, NSMaxY(view.frame));
    }
    for (NSView *view in host.subviews)
        if (![bottomControls containsObject:view]) lowest = MIN(lowest, NSMinY(view.frame));
    CGFloat statusY = bottom + 6, statusHeight = 52;
    CGFloat height = MAX(56, statusY + statusHeight + 6 - lowest);
    // Reserve a band by shortening the resizable editors, not by enlarging the
    // window: its frame may already have been restored from an earlier opening.
    CGFloat editorBottom = CGFLOAT_MAX;
    for (NSView *view in host.subviews)
        if ([view isKindOfClass:NSScrollView.class]) editorBottom = MIN(editorBottom, NSMinY(view.frame));
    for (NSView *view in host.subviews) if (![bottomControls containsObject:view]) {
        NSRect frame = view.frame;
        if ([view isKindOfClass:NSScrollView.class]) {
            frame.origin.y += height; frame.size.height -= height;
        } else if (NSMinY(frame) < editorBottom) frame.origin.y += height;
        view.frame = frame;
    }
    NSSize minimum = [window minSize];
    minimum.height += height;
    // Some older nibs have no useful minimum. Keep at least 64pt of editor
    // content even there, without enlarging a normally sized window.
    for (NSView *view in host.subviews) if ([view isKindOfClass:NSScrollView.class])
        minimum.height = MAX(minimum.height, NSHeight([window frame]) - NSHeight(view.frame) + 64);
    [window setMinSize:minimum];
    NSRect windowFrame = [window frame];
    if (NSHeight(windowFrame) < minimum.height) {
        windowFrame.origin.y -= minimum.height - NSHeight(windowFrame);
        windowFrame.size.height = minimum.height;
        [window setFrame:windowFrame display:NO];
    }
    self.shortcutStatus = [NSTextField wrappingLabelWithString:@""];
    self.shortcutStatus.frame = NSMakeRect(20, statusY, NSWidth(host.bounds)-40, statusHeight);
    self.shortcutStatus.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.shortcutStatus.textColor = NSColor.secondaryLabelColor;
    [host addSubview:self.shortcutStatus];
}

// The list is edited with the standard + and - buttons attached below it and an
// action menu for the less frequent commands. The nib's five text buttons stay
// hidden and keep their actions, titles and enabled state.
- (void)installListControls
{
    if (self.listButtons) return;
    NSView *host = [window contentView];
    NSScrollView *list = [outlineView enclosingScrollView];
    NSArray<NSButton *> *old = @[newItemButton, submenuButton, separatorButton, deleteButton, duplicateButton];
    CGFloat oldBottom = CGFLOAT_MAX;
    for (NSButton *button in old) { oldBottom = MIN(oldBottom, NSMinY([host convertRect:button.bounds fromView:button])); button.hidden = YES; }
    const CGFloat barHeight = 24, segmentWidth = 32;
    NSImage *more = [NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:nil];
    NSSegmentedControl *buttons = [NSSegmentedControl segmentedControlWithImages:@[[[NSImage imageNamed:NSImageNameAddTemplate] copy], [[NSImage imageNamed:NSImageNameRemoveTemplate] copy], more]
        trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(listButtonPressed:)];
    buttons.segmentStyle = NSSegmentStyleSmallSquare;
    buttons.identifier = @"macro.list.buttons";
    NSMenu *actions = [[NSMenu alloc] initWithTitle:@""];
    actions.autoenablesItems = NO;
    for (NSButton *source in @[submenuButton, separatorButton, duplicateButton]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:source.title action:@selector(listActionChosen:) keyEquivalent:@""];
        item.target = self; item.representedObject = source;
        [actions addItem:item];
    }
    NSArray<NSString *> *labels = @[newItemButton.title, deleteButton.title, [NSString stringWithFormat:@"%@, %@, %@", submenuButton.title, separatorButton.title, duplicateButton.title]];
    for (NSInteger segment = 0; segment < 3; segment++) {
        [buttons setWidth:segmentWidth forSegment:segment];
        [buttons setToolTip:labels[segment] forSegment:segment];
        [buttons imageForSegment:segment].accessibilityDescription = labels[segment];
    }
    // The third segment opens the menu of the less frequent commands on a click.
    [buttons setMenu:actions forSegment:2];
    [buttons setShowsMenuIndicator:YES forSegment:2];
    // The bar takes the place of the old buttons, directly below the list,
    // which grows into the space they left.
    NSRect listFrame = list.frame;
    CGFloat barY = oldBottom;
    [buttons sizeToFit];
    buttons.frame = NSMakeRect(NSMinX(listFrame), barY, NSWidth(buttons.frame), barHeight);
    CGFloat top = NSMaxY(listFrame);
    listFrame.origin.y = barY + barHeight - 1; listFrame.size.height = top - listFrame.origin.y;
    list.frame = listFrame;
    buttons.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [host addSubview:buttons];
    self.listButtons = buttons; self.listActions = actions;
    [self syncListControls];
}
- (void)syncListControls
{
    [self.listButtons setEnabled:newItemButton.enabled forSegment:0];
    [self.listButtons setEnabled:deleteButton.enabled forSegment:1];
    for (NSMenuItem *item in self.listActions.itemArray) item.enabled = [item.representedObject isEnabled];
}
- (void)listButtonPressed:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment > 1) return;
    NSButton *source = sender.selectedSegment == 0 ? newItemButton : deleteButton;
    if (source.enabled) [NSApp sendAction:source.action to:source.target from:source];
}
- (void)listActionChosen:(NSMenuItem *)sender
{
    NSButton *source = sender.representedObject;
    if (source.enabled) [NSApp sendAction:source.action to:source.target from:source];
}
// What the placeholders in a macro stand for, below its contents.
- (void)installPlaceholderNote
{
    if (self.placeholderNote) return;
    NSView *host = [window contentView];
    NSScrollView *contents = [contentTextView enclosingScrollView];
    NSTextField *note = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"#SEL# = selected text, #INS# = insertion point after the macro, #PASTE# = text on the clipboard. AppleScript macros can also use #FILEPATH# and other placeholders (see Help).", @"Macro editor placeholder guide"), [TSMarkMenu markGuide]]];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    note.textColor = NSColor.secondaryLabelColor;
    note.identifier = @"macro.placeholders";
    note.selectable = YES;
    NSRect frame = contents.frame;
    // Size the note for its narrowest width, which the window's minimum width keeps.
    CGFloat narrowest = MIN(NSWidth(frame), 300);
    CGFloat height = ceil([note.cell cellSizeForBounds:NSMakeRect(0, 0, narrowest, CGFLOAT_MAX)].height);
    const CGFloat gap = 6;
    // When the contents cannot give up the room and keep 64pt, grow the window
    // downwards first, keeping its top edge, so the contents grow with it.
    CGFloat deficit = height + gap + 64 - NSHeight(frame);
    if (deficit > 0) {
        NSRect grown = [window frame];
        grown.origin.y -= deficit; grown.size.height += deficit;
        [window setFrame:grown display:NO];
        frame = contents.frame;
    }
    note.frame = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), height);
    frame.origin.y += height + gap; frame.size.height -= height + gap;
    contents.frame = frame;
    note.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [host addSubview:note];
    self.placeholderNote = note;
    // The contents keep the room they had at the smallest window size.
    NSSize smallest = [window minSize];
    // The contents keep at least 64pt at the smallest window size.
    smallest.height = MAX(smallest.height + height + gap, NSHeight([window frame]) - NSHeight(frame) + 64);
    smallest.width = MAX(smallest.width, narrowest + NSWidth([window frame]) - NSWidth(frame));
    [window setMinSize:smallest];
    NSRect current = [window frame];
    if (NSHeight(current) < smallest.height || NSWidth(current) < smallest.width) {
        current.origin.y -= MAX(0, smallest.height - NSHeight(current));
        current.size.height = MAX(NSHeight(current), smallest.height);
        current.size.width = MAX(NSWidth(current), smallest.width);
        [window setFrame:current display:NO];
    }
}
// Save is the default button at the trailing edge with Cancel before it; Test,
// which does not close the window, starts the row at the leading edge.
- (void)layoutDialogButtons
{
    TSLayoutDialogButtons([window contentView], @[saveButton, cancelButton], @[testButton]);
}

- (void)collectShortcutCandidates:(TSMacroTreeNode *)parent path:(NSString *)path
                           nodes:(NSMutableArray *)nodes candidates:(NSMutableArray *)candidates
{
    for (TSMacroTreeNode *node in parent.children) {
        NSString *title = path.length ? [path stringByAppendingFormat:@" › %@", node.name] : node.name;
        if (node.isGroup) [self collectShortcutCandidates:node path:title nodes:nodes candidates:candidates];
        else if (node.isStandardItem) {
            [nodes addObject:node];
            [candidates addObject:@{@"path":title ?: @"", @"key":getKeyEquivalentFromString(node.key),
                @"modifiers":@(getKeyModifierMaskFromString(node.key))}];
        }
    }
}

- (void)pendingKeyChanged:(NSNotification *)notification { [self updatePendingShortcutStatus]; }
- (void)updatePendingShortcutStatus
{
    if (!self.previousItem.isStandardItem) return;
    NSString *saved = self.previousItem.key;
    self.previousItem.key = getStringFormKeyEquivalent(keyField.stringValue, shiftCheckBox.state == NSControlStateValueOn,
        optionCheckBox.state == NSControlStateValueOn, controlCheckBox.state == NSControlStateValueOn);
    [self refreshShortcutConflicts];
    self.previousItem.key = saved;
}
- (void)rememberOriginalShortcutKeys
{
    self.originalShortcutKeys = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray *nodes = [NSMutableArray array], *candidates = [NSMutableArray array];
    [self collectShortcutCandidates:[outlineController rootOfTree] path:@"" nodes:nodes candidates:candidates];
    for (TSMacroTreeNode *node in nodes) [self.originalShortcutKeys setObject:[TSShortcutStore normalizedKey:getKeyEquivalentFromString(node.key) modifiers:getKeyModifierMaskFromString(node.key)] forKey:node];
}
- (NSArray *)currentShortcutConflictsWithNodes:(NSMutableArray *)nodes candidates:(NSMutableArray *)candidates
{
    [self collectShortcutCandidates:[outlineController rootOfTree] path:NSLocalizedString(@"Macros", @"") nodes:nodes candidates:candidates];
    return [[TSKeyboardShortcuts sharedController] conflictsForMacroShortcuts:candidates];
}
- (NSString *)shortcutConflictForNode:(TSMacroTreeNode *)node { return node ? [self.shortcutConflicts objectForKey:node] : nil; }
- (void)refreshShortcutConflicts
{
    if (!outlineView) return;
    NSMutableArray *nodes = [NSMutableArray array], *candidates = [NSMutableArray array];
    NSArray *conflicts = [self currentShortcutConflictsWithNodes:nodes candidates:candidates];
    self.shortcutConflicts = [NSMapTable strongToStrongObjectsMapTable];
    for (NSDictionary *conflict in conflicts)
        [self.shortcutConflicts setObject:[TSShortcutStore reasonForMacroConflict:conflict] forKey:nodes[[conflict[@"index"] unsignedIntegerValue]]];
    self.shortcutStatus.stringValue = [self shortcutConflictForNode:self.previousItem] ?: @"";
    self.shortcutStatus.toolTip = self.shortcutStatus.stringValue;
    // Repaint cells without rebuilding the tree or changing its current selection.
    [outlineView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [outlineView numberOfRows])]
                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [outlineView numberOfColumns])]];
}
- (void)menuShortcutsChanged:(NSNotification *)notification { [self refreshShortcutConflicts]; }
- (NSModalResponse)showShortcutConflicts:(NSString *)details
{
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"Macro shortcut conflicts", @"");
    alert.informativeText = NSLocalizedString(@"These newly assigned or changed shortcuts overlap other assignments. The list explains which shortcuts will be inactive. You can edit them, keep them as written, or remove only the changed conflicting shortcuts. Macro names and contents will be kept.", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Return to Editing", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Save Anyway (Conflicting Shortcuts Inactive)", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Remove Conflicting Shortcuts and Save", @"")];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,520,180)];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.bounds];
    text.editable = NO; text.selectable = YES;
    text.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    text.textContainerInset = NSMakeSize(8,8); text.textContainer.widthTracksTextView = YES;
    text.autoresizingMask = NSViewWidthSizable; text.string = details;
    scroll.documentView = text; alert.accessoryView = scroll;
    return TSRunShortcutAlert(alert);
}
- (BOOL)validateMacroShortcutsBeforeSaving
{
    NSMutableArray *nodes = [NSMutableArray array], *candidates = [NSMutableArray array], *changed = [NSMutableArray array], *lines = [NSMutableArray array];
    NSMutableArray *conflicts = [[self currentShortcutConflictsWithNodes:nodes candidates:candidates] mutableCopy];
    NSMutableIndexSet *inactive = [NSMutableIndexSet indexSet];
    for (NSDictionary *conflict in conflicts) [inactive addIndex:[conflict[@"index"] unsignedIntegerValue]];
    // A newly changed earlier macro may take a key from a later, unchanged one.
    // Confirm that change too, while preserving file-order precedence at runtime.
    for (NSUInteger index = 0; index < nodes.count; index++) {
        TSMacroTreeNode *node = nodes[index];
        NSDictionary *binding = [TSShortcutStore normalizedKey:getKeyEquivalentFromString(node.key) modifiers:getKeyModifierMaskFromString(node.key)];
        if (![binding[@"key"] length] || [inactive containsIndex:index] || [[self.originalShortcutKeys objectForKey:node] isEqual:binding]) continue;
        for (NSUInteger later = index + 1; later < candidates.count; later++) {
            NSDictionary *candidate = candidates[later];
            if (![binding isEqual:[TSShortcutStore normalizedKey:candidate[@"key"] modifiers:[candidate[@"modifiers"] unsignedIntegerValue]]]) continue;
            NSMutableDictionary *other = [candidate mutableCopy]; other[@"macro"] = @YES;
            [conflicts addObject:@{@"index":@(index), @"other":other, @"displaced":@YES}];
            break;
        }
    }
    for (NSDictionary *conflict in conflicts) {
        NSUInteger index = [conflict[@"index"] unsignedIntegerValue];
        TSMacroTreeNode *node = nodes[index];
        NSDictionary *original = [self.originalShortcutKeys objectForKey:node];
        NSDictionary *binding = [TSShortcutStore normalizedKey:getKeyEquivalentFromString(node.key) modifiers:getKeyModifierMaskFromString(node.key)];
        if (original && [original isEqual:binding]) continue;
        [changed addObject:conflict];
        NSDictionary *candidate = candidates[index];
        [lines addObject:[NSString stringWithFormat:@"%@ (%@)\n%@", candidate[@"path"],
            [TSShortcutStore displayKey:candidate[@"key"] modifiers:[candidate[@"modifiers"] unsignedIntegerValue]],
            [TSShortcutStore reasonForMacroConflict:conflict]]];
    }
    if (!changed.count) return YES;
    NSModalResponse response = [self showShortcutConflicts:[lines componentsJoinedByString:@"\n\n"]];
    if (response == NSAlertThirdButtonReturn) {
        for (NSDictionary *conflict in changed) [nodes[[conflict[@"index"] unsignedIntegerValue]] setKey:@""];
        [self reflectChangesInEditor:YES];
        return YES;
    }
    if (response == NSAlertSecondButtonReturn) return YES;
    TSMacroTreeNode *node = nodes[[changed.firstObject[@"index"] unsignedIntegerValue]];
    NSMutableArray *parents = [NSMutableArray array];
    for (TSMacroTreeNode *parent = node.nodeParent; parent; parent = parent.nodeParent) [parents addObject:parent];
    for (TSMacroTreeNode *parent in parents.reverseObjectEnumerator) [outlineView expandItem:parent];
    [outlineView selectItems:@[node] byExtendingSelection:NO];
    [self reflectChangesInEditor:YES]; [window makeFirstResponder:keyField];
    return NO;
}

// action for Save button
- (IBAction)savePressed:(id)sender
{
	NSString *pathStr, *defaultPathStr;
	
	defaultPathStr = [MacrosPath stringByStandardizingPath];
	defaultPathStr = [defaultPathStr stringByAppendingPathComponent:@"Macros_Latex"];
	defaultPathStr = [defaultPathStr stringByAppendingPathExtension:@"plist"];
	
	pathStr = [MacrosPath stringByStandardizingPath];
	switch (g_macroType) {
		case TexEngine: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Tex"]; break;
		case LatexEngine: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Latex"]; break;
		case BibtexEngine: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Bibtex"]; break;
		case IndexEngine: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Index"]; break;
		case MetapostEngine: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Metapost"]; break;
	//	case ContextEngine: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Context"]; break;
		default: pathStr = [pathStr stringByAppendingPathComponent:@"Macros_Latex"]; break;
	}
	pathStr = [pathStr stringByAppendingPathExtension:@"plist"];
	
	if (![window makeFirstResponder:window]) return; // finish editing fields
										//[outlineView deselectAll: sender];
		[self reflectChangesInEditor: YES];
		if (dataTouched) {	// save only if data was touched
            if (![self validateMacroShortcutsBeforeSaving]) return;
			// mitsu 1.29 (U)-- back up old macro file, so that you can recover it manually if needed
			NS_DURING
				if ([[NSFileManager defaultManager] fileExistsAtPath:pathStr]) {
					NSString *backupPath = [pathStr stringByDeletingPathExtension];
					backupPath = [backupPath stringByAppendingString:@"~"];
					backupPath = [backupPath stringByAppendingPathExtension:@"plist"];
					[[NSFileManager defaultManager] removeItemAtPath:backupPath error:NULL];
					[[NSFileManager defaultManager] copyItemAtPath:pathStr toPath:backupPath error:NULL];
				}
				NS_HANDLER
					NS_ENDHANDLER
					// end mitsu 1.29
					// save the node data to a file
					if (![self saveNodes: [outlineController rootOfTree] toFile: pathStr]) return;
					// reload macros
					[[TSMacroMenuController sharedInstance] reloadMacros: self];
		}
				[window close];
}

// action for Cancel button
- (IBAction)cancelPressed:(id)sender
{
	[window close];
}

// action for Test button
- (IBAction)doMacroTest:(id)sender
{
	//[window orderOut: self];
	// In order to test an AppleScript properly, especially if it refers to the first window,
	// it may be better to hide the TSMacroEditor window on "Test".
	// On the other hand, users might think that something wrong has happened if the window
	// suddenly goes away.
	[[TSMacroMenuController sharedInstance] doMacro: [contentTextView string]];
	//[window makeKeyAndOrderFront:nil]; // get the window back
}


// action for nameField
- (IBAction)nameFieldAction:(id)sender
{
	nameTouched = YES;
	[self reflectChangesInEditor: YES];
}

// delegate method for contentTextView
- (IBAction)textDidChange:(id)sender
{
	contentTouched = YES;
}

// action for keyField
- (IBAction)keyFieldAction:(id)sender
{
	NSString *key = [keyField stringValue];
	if ([key length] > 1) {
		[keyField setStringValue: [key substringToIndex: 1]];
	}
	keyTouched = YES;
    [self updatePendingShortcutStatus];
	[self reflectChangesInEditor: YES];
}

// action for Shift/Option/Control check box
- (IBAction)modifiersAction:(id)sender
{
	keyTouched = YES;
    [self updatePendingShortcutStatus];
	[self reflectChangesInEditor: YES];
}

// action for outline view
- (IBAction)outlineAction:(id)sender
{
}

// a method called on "Selection changed" notification
- (void)outlineViewSelectionChanged: (NSNotification *)note
{
	[self reflectChangesInEditor: NO];
}

// a method called on "Items changed" (added/removed) notification
- (void)outlineViewItemsChanged: (NSNotification *)note
{
	dataTouched = YES;	// user may have changed the order or dropped an item
    [self refreshShortcutConflicts];
}

// interation bewteen outline data and nameField/contentTextView/etc
- (void)reflectChangesInEditor: (BOOL)forceUpdate
{
	NSString *contentString;
	NSArray *selectedNodes = [outlineController selectedNodes];
	[deleteButton setEnabled: ([selectedNodes count] > 0)];
	[duplicateButton setEnabled: ([selectedNodes count] > 0)];
	[self syncListControls];
	
	TSMacroTreeNode *newItem = ([selectedNodes count] == 1)?[selectedNodes objectAtIndex: 0]:nil;
	if (newItem == self.previousItem && !forceUpdate)
		return;	// maybe item was simply dragged and dropped
	
	if (self.previousItem) {
		if (![self.previousItem isSeparator] && nameTouched) {
			[self.previousItem setName: [nameField stringValue]];
			dataTouched = YES;
		}
		if ([self.previousItem isStandardItem]) {
			if (contentTouched) {
				// note: [NSTextView string] returns currently edited string. make sure to copy it
				if (savedFilter != kMacJapaneseFilterMode)
					contentString = [NSString stringWithString: [contentTextView string]];
				else
					contentString = filterYenToBackslash([contentTextView string]);
				[self.previousItem setContent: contentString];
				dataTouched = YES;
			}
			if (keyTouched)
			{
				[self.previousItem setKey: getStringFormKeyEquivalent([keyField stringValue],
																 ([shiftCheckBox state] == NSOnState), ([optionCheckBox state] == NSOnState),
																 ([controlCheckBox state] == NSOnState))];
				dataTouched = YES;
			}
		}
		if ([self.previousItem isAlive])
			[outlineView reloadItem: self.previousItem]; //this causes a problem if the item is dead
		self.previousItem = nil;
	}
	
	[nameField setStringValue: (newItem)?[newItem name]:@""];
	[nameField setEditable: (newItem && ![newItem isSeparator])?YES:NO];
	if (newItem && [newItem isStandardItem]) {
		contentString = [newItem content]?[newItem content]:@"";
 		if (g_shouldFilter == kMacJapaneseFilterMode)
			contentString = filterBackslashToYen(contentString);
		savedFilter = g_shouldFilter;	// remember this filter option
		[contentTextView setString: contentString];
		[contentTextView setEditable: YES];
		NSString *KeyEquiv = getKeyEquivalentFromString([newItem key]);
		BOOL hasKeyEquiv = ([KeyEquiv length] > 0);
		[keyField setStringValue: (hasKeyEquiv)?(KeyEquiv):@""];
		[keyField setEditable: YES];
		NSUInteger modifier = getKeyModifierMaskFromString([newItem key]);
		[shiftCheckBox setState: (hasKeyEquiv && (modifier & NSShiftKeyMask))?NSOnState:NSOffState];
		[shiftCheckBox setEnabled: YES];
		[optionCheckBox setState: (hasKeyEquiv && (modifier & NSAlternateKeyMask))?NSOnState:NSOffState];
		[optionCheckBox setEnabled: YES];
		[controlCheckBox setState: (hasKeyEquiv && (modifier & NSControlKeyMask))?NSOnState:NSOffState];
		[controlCheckBox setEnabled: YES];
		[testButton setEnabled: YES];
	} else {
		[contentTextView setString: @""];
		[contentTextView setEditable: NO];
		[keyField setStringValue: @""];
		[keyField setEditable: NO];
		[shiftCheckBox setState: NSOffState];
		[shiftCheckBox setEnabled: NO];
		[optionCheckBox setState: NSOffState];
		[optionCheckBox setEnabled: NO];
		[controlCheckBox setState: NSOffState];
		[controlCheckBox setEnabled: NO];
		[testButton setEnabled: NO];
	}
    if (newItem)
        self.previousItem = newItem;
    else
        self.previousItem = nil;
//	self.previousItem = (newItem)?[newItem retain]:nil;
	nameTouched = NO;
	contentTouched = NO;
	keyTouched = NO;
    [self refreshShortcutConflicts];
	//	[outlineView reloadData];// this caused a crash if a node and its child are selected and the disclosure triangle is pressed
}

// delegate method for window
- (BOOL)windowShouldClose:(id)sender
{
    if (sender == self) return YES;
    if (![window makeFirstResponder:window]) return NO;
    [self reflectChangesInEditor:YES];
    if (!dataTouched) return YES;
    if ([window attachedSheet]) return NO;
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Do you want to save macros?", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Save", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Don't Save", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        [alert.window orderOut:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (response == NSAlertFirstButtonReturn) [self savePressed:self];
            else if (response == NSAlertSecondButtonReturn) [self cancelPressed:self];
        });
    }];
    return NO;
}
// Compatibility for any older nib callback; defer until the sheet has gone.
- (void)saveMacrosSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (returnCode == NSAlertDefaultReturn) [self savePressed:self];
        else if (returnCode == NSAlertAlternateReturn) [self cancelPressed:self];
    });
}

// delegate method for window
- (void) windowWillClose: (NSNotification *)aNotification
{
	// clean up
	if (self.previousItem)
		self.previousItem = nil;
	self.previousItem = nil;
	[outlineController setRootOfTree: nil]; // this release the tree structure
    self.originalShortcutKeys = nil; self.shortcutConflicts = nil; self.shortcutStatus = nil;
	outlineView = nil;
	window = nil;
	// restore menu item
	NSMenu *macroMenu = [[[NSApp mainMenu] itemWithTitle:
				NSLocalizedString(@"Macros", @"Macros")] submenu];
	id item = [macroMenu itemWithTitle:
					NSLocalizedString(@"Close Macro Editor", @"Close Macro Editor")];
	if (item) {
		[item setTitle: NSLocalizedString(@"Open Macro Editor...", @"Open Macro Editor...")];
		[item setTarget: self];
		[item setAction: @selector(openMacroEditor:)];
	}
	item = [macroMenu itemWithTitle:
				NSLocalizedString(@"Add macros from file...", @"Add macros from file...")];
	if (item)
		[macroMenu removeItem: item];
	item = [macroMenu itemWithTitle:
				NSLocalizedString(@"Save selection to file...", @"Save selection to file...")];
	if (item)
		[macroMenu removeItem: item];
	[[NSNotificationCenter defaultCenter] removeObserver: self];
}

// delegate method for window
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
	NSRect outlineFrame = [[outlineView enclosingScrollView] frame];
	NSRect buttonFrame = [testButton frame];
	if ((proposedFrameSize.width < outlineFrame.size.width + 110) &&
		(buttonFrame.origin.x > outlineFrame.origin.x + 100)) {
		[testButton setFrameOrigin: NSMakePoint(outlineFrame.origin.x-3, buttonFrame.origin.y)];
	}
	if ((proposedFrameSize.width >= outlineFrame.size.width + 110) &&
		(buttonFrame.origin.x <= outlineFrame.origin.x + 100)) {
		[testButton setFrameOrigin: NSMakePoint(outlineFrame.origin.x+outlineFrame.size.width+24,
																		buttonFrame.origin.y)];
	}
	// I think there is a bug in Cocoa which requires the fix below.
	// If one make the window so narrow that the name and content fields disappear,
	// then next time they appear, they stick to the right border.
	NSRect contentBounds = [[window contentView] bounds];	// use this instead of proposedFrameSize
	NSRect fieldFrame = [nameField frame];
	if (fieldFrame.size.width > contentBounds.size.width-fieldFrame.origin.x-10 && fieldFrame.size.width > 0) {
		fieldFrame.size.width = contentBounds.size.width-fieldFrame.origin.x-10;
		[nameField setFrame:fieldFrame];
	}
	fieldFrame = [[contentTextView enclosingScrollView] frame];	// don't forget to apply it to the scroll view
	if (fieldFrame.size.width > contentBounds.size.width-fieldFrame.origin.x-10 && fieldFrame.size.width > 0) {
		fieldFrame.size.width = contentBounds.size.width-fieldFrame.origin.x-10;
		[[contentTextView enclosingScrollView] setFrame:fieldFrame];
	}
	//
	return proposedFrameSize;
}

// delegate method for window
- (void)windowDidResize:(NSNotification *)aNotification
{
	//[outlineView reloadData];
}

// delegate method for window
- (void)windowDidBecomeKey: (NSNotification *)aNotification
{
	NSString *string;
	// FIXME/TODO: Instead of using savedFilter, register for notification
	// when the encoding changes
	if (g_shouldFilter != savedFilter) { // if the encoding was changed while TSMacroEditor is open...
		if (g_shouldFilter == kMacJapaneseFilterMode) {
			string = [contentTextView string];
			string = filterBackslashToYen(string);
			[contentTextView setDelegate: nil]; // to avoid sending a message "text changed"
			[contentTextView setString: string];
			[contentTextView setDelegate: self];
		} else if(savedFilter == kMacJapaneseFilterMode) {
			string = [contentTextView string];
			string = filterYenToBackslash(string);
			[contentTextView setDelegate: nil]; // to avoid sending a message "text changed"
			[contentTextView setString: string];
			[contentTextView setDelegate: self];
		}
		savedFilter = g_shouldFilter;
	}
}

// set up menu items' enable/disable
- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	if ([anItem action] == @selector(saveSelection:)) {
		return ([[outlineView allSelectedItems] count] > 0);
	} else
		return YES;
}

// save given nodes of the tree to a file
- (BOOL)saveNodes: (id)nodes toFile: (NSString *)filePath
{
	id 	propertyList;
	NSString *pathStr, *error;
	NSData *xmlData;

	if ([nodes isKindOfClass: [TSMacroTreeNode class]]) {
		propertyList = [nodes makeDictionary];
		[propertyList setObject: @"ROOT" forKey: NAME_KEY];
	} else if ([nodes isKindOfClass: [NSArray class]]) {
		NSMutableArray *array = [NSMutableArray array];
		NSEnumerator *enumerator = [nodes objectEnumerator];
		TSMacroTreeNode *child;
		while ((child = [enumerator nextObject])) {
			[array addObject: [child makeDictionary]];
		}
		propertyList = [NSDictionary dictionaryWithObjectsAndKeys:
						@"ROOT", NAME_KEY, array, CHILDREN_KEY, nil];
	} else
		return NO;
	// convert to XML in UTF8 format
	NS_DURING
	error = nil;
	xmlData = [NSPropertyListSerialization dataFromPropertyList: propertyList
										format: NSPropertyListXMLFormat_v1_0
										errorDescription: &error];
	if (!xmlData)
		[NSException raise: @"XML error" format: @""];
	// finally write to file
	pathStr = [[NSString stringWithString: filePath] stringByStandardizingPath];
	if (![xmlData writeToFile: pathStr atomically: YES])
        [NSException raise:@"Macro write failed" format:@"%@", pathStr];

	NS_HANDLER
		NSRunAlertPanel(@"Error", [NSString stringWithFormat:
			@"failed to save macros to %@\n%@", filePath, error], nil, nil, nil);
    return NO;
	NS_ENDHANDLER
    return YES;
}

// action for "save selection to file" menu item
- (void)saveSelection: (id)sender
{
	NSSavePanel *aPanel = [NSSavePanel savePanel];
    NSArray *types = [NSArray arrayWithObject:@"plist"];
	[aPanel setAllowedFileTypes:types];
    [aPanel setNameFieldStringValue:@"My macros"];
    
 //	[aPanel beginSheetForDirectory: nil //[MACRO_DATA_PATH stringByDeletingLastPathComponent]
    //          file: @"My macros" modalForWindow:window modalDelegate:self
	//			didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
    [aPanel beginSheetModalForWindow:window
        completionHandler: ^ (NSInteger result ) {
        if (result == NSFileHandlingPanelOKButton) {
            NS_DURING
            // NSString *fileName = [sheet fileName];
            NSURL *fileURL = [aPanel URL];
            NSString *fileName = [fileURL path];
            if (fileName) {
                NSArray *selectionArray = [TSMacroTreeNode minimumNodeCoverFromNodesInArray:
                                           [outlineView allSelectedItems]];
                [self saveNodes: selectionArray toFile: fileName];
            }
            NS_HANDLER
			NSRunAlertPanel(@"Error", @"failed to save macros to the file.", nil, nil, nil);
            NS_ENDHANDLER
       }
            }];
}

// handler for savePanel for macros saving
/*
- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void  *)contextInfo
{
	if (returnCode == NSOKButton) {
		NS_DURING
		// NSString *fileName = [sheet fileName];
        NSURL *fileURL = [sheet URL];
        NSString *fileName = [fileURL path];
		if (fileName) {
			NSArray *selectionArray = [TSMacroTreeNode minimumNodeCoverFromNodesInArray:
										[outlineView allSelectedItems]];
			[self saveNodes: selectionArray toFile: fileName];
		}
		NS_HANDLER
			NSRunAlertPanel(@"Error", @"failed to save macros to the file.", nil, nil, nil);
		NS_ENDHANDLER
	}
}
*/

// action for "Add macros from file"
- (void)readDictionaryToMacroEditor: (id)sender
{
	NSOpenPanel *aPanel = [NSOpenPanel openPanel];
	[aPanel setCanChooseFiles: YES];
	[aPanel setCanChooseDirectories: NO];
	[aPanel setAllowsMultipleSelection: NO];
	[aPanel setResolvesAliases: YES];
    // [aPanel setDirectoryUrl: nil];
    // [aPanel setAllowedFileTypes: nil];

// 	[aPanel beginSheetForDirectory: nil file: nil types: nil modalForWindow: window
//		modalDelegate: self didEndSelector: @selector(openPanelDidEnd:returnCode:contextInfo:)
//		contextInfo:nil];
    
    [aPanel beginSheetModalForWindow:window
                   completionHandler: ^ (NSInteger result ) {
                       if (result == NSFileHandlingPanelOKButton) {
                           NSDictionary *newDict = nil;
                           NSURL *myURL = [aPanel URL];
                           NSString *fileName = [myURL path];
                           NS_DURING
                           NSData *myData = [NSData dataWithContentsOfFile: fileName];
                           NSString *aString = [[NSString alloc] initWithData:myData encoding:
                                                NSUTF8StringEncoding];
                           if (aString)
                                   newDict = (NSDictionary *)[aString propertyList];
                           if (newDict) {
                                   NSArray *newNodeArray = [TSMacroTreeNode nodeArrayFromPropertyList: newDict];
                                   [outlineController addNewDataArrayToSelection: newNodeArray];
                               }
                           NS_HANDLER
                           newDict = nil;
                           NS_ENDHANDLER
                           if (newDict == nil)
                                   NSRunAlertPanel(@"Error", @"failed to read the file as a dictionary", nil, nil, nil);
                        }
                   }];
}

    


// handler for openPanel for loading macros
/*
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void  *)contextInfo
{
	NSDictionary *newDict = nil;
	if (returnCode == NSOKButton) {
		NSArray *array = [sheet filenames];
		NS_DURING
			NSData *myData = [NSData dataWithContentsOfFile: [array objectAtIndex: 0]];
			NSString *aString = [[[NSString alloc] initWithData:myData encoding:
							NSUTF8StringEncoding] autorelease];
			if (aString)
				newDict = (NSDictionary *)[aString propertyList];
			if (newDict) {
				NSArray *newNodeArray = [TSMacroTreeNode nodeArrayFromPropertyList: newDict];
				[outlineController addNewDataArrayToSelection: newNodeArray];
			}
		NS_HANDLER
			newDict = nil;
		NS_ENDHANDLER
		if (newDict == nil)
			NSRunAlertPanel(@"Error", @"failed to read the file as a dictionary", nil, nil, nil);
	}
}
 */



@end
