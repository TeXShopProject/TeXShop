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
#import "TSFontSupport.h"
#import "TSMacroEditor.h"

#import "TSMacroOutlineController.h"
#import "TSMacroMenuController.h"
#import "TSKeyboardShortcuts.h"
#import "TSTextView.h"
#import "TSEncodingSupport.h"
#import "NSText-Extras.h"
#import "globals.h"
#import "TSDialogButtonLayout.h"
#import "TSListBottomBar.h"
#import "TSShortcutKeyRecorder.h"
#import "TSShortcutInternal.h"
#import "TSPrefPaneLayout.h"
#import "TSPlaceholderToken.h"
#import "TSMacroContentTokens.h"
#import "TSMacroContentKind.h"
#import "TSColorSupport.h"
#import "TSThemeSystemColor.h"
#import "TSMarkMenu.h"
#import "TSPreferenceEffects.h"
#import "TSSyntaxHighlighter.h"
#import "TSSyntaxMacroContentScanner.h"
#import "TSSyntaxTeXScanner.h"
#import "TSAdvancedFindTextView.h"

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
        font = TSConsoleFontFromDefaults(SUD, ConsoleFontNameKey, ConsoleFontSizeKey);
    else
        font = TSArchivedFont([SUD objectForKey:DocumentFontKey]);
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
    contentTextView.insertionPointColor = [colors insertionPointColorFromDictionary:theme isWindowDark:dark];
    TSThemeSetSelectionColor(contentTextView, [colors selectionColorFromDictionary:theme isWindowDark:dark]);
    NSMutableDictionary *typing = [contentTextView.typingAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
    typing[NSForegroundColorAttributeName] = text;
    contentTextView.typingAttributes = typing;
    [self updateContentHighlightingWithTheme:theme dark:dark];
}
// END content appearance
// BEGIN content text view
// The contents: a TextKit 1 text system for syntax coloring, whose layout manager
// also draws the highlights of the Advanced Find panel, and plain text, so that
// what is pasted keeps no colors or fonts of its own and the Font panel changes
// the font of all the contents. Only the text is saved.
- (NSTextView *)makeContentTextViewWithSize:(NSSize)contentSize
{
    NSTextStorage *storage = [[NSTextStorage alloc] init];
    // The placeholders show as tokens (TSMacroContentTokens), over the Advanced Find highlights.
    NSLayoutManager *layout = [[TSMacroContentLayoutManager alloc] init];
    [storage addLayoutManager:layout];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(contentSize.width, CGFLOAT_MAX)];
    [container setWidthTracksTextView:YES];
    [layout addTextContainer:container];
    NSTextView *view = [[TSMacroContentTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height) textContainer:container];
    [view setMinSize:NSMakeSize(0, contentSize.height)];
    [view setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [view setVerticallyResizable:YES];
    [view setHorizontallyResizable:NO];
    [view setAutoresizingMask:NSViewWidthSizable];
    [view setRichText:NO];
    return view;
}
// END content text view
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
    options.marksFullwidthSymbols = [SUD boolForKey:HighlightFullwidthSymbolsKey] && [scheme attributesForRole:TSSyntaxRoleFullwidthSymbol].count > 0;
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
        [self useSystemFont];
        [self installShortcutStatus];
        [self hideNibShortcutRows];
        [self installPlaceholderControls];
        [self layoutDialogButtons];
        [self installSidebar];

		// set up window and UI elements
		// [window setDelegate: self];	// not necessary if it is connected in IB

		[outlineView setTarget: self];
		[outlineView setAction: @selector(listClicked:)];
		[outlineView setDoubleAction: @selector(listDoubleClicked:)];
		// custom text view
		NSScrollView *scrollView = [contentTextView enclosingScrollView];
		NSSize contentSize = [scrollView contentSize];
		NSTextView *nibTextView = contentTextView;
		contentTextView = [self makeContentTextViewWithSize:contentSize];
		// As installSidebar left the nib's: the margin of the text and the name read out by VoiceOver.
		[contentTextView setTextContainerInset:[nibTextView textContainerInset]];
		[contentTextView setAccessibilityLabel:[nibTextView accessibilityLabel]];
		[contentTextView setDelegate:self];
		[contentTextView setAllowsUndo:YES];
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
		// set up properties for UI
		[nameField setEditable: NO];
		[contentTextView setEditable: NO];
		self.pendingShortcutKey = @"";
		[self syncPlaceholderControls];
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
    // The message in the small font of the Multiple Replace window's messages, in a band of
    // four lines: beside the sidebar, the longest messages take four at the narrowest width.
    NSTextField *status = [NSTextField wrappingLabelWithString:@"1\n2\n3\n4"];
    status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    CGFloat statusY = bottom + 6, statusHeight = ceil([status.cell cellSizeForBounds:NSMakeRect(0, 0, 1000, CGFLOAT_MAX)].height);
    status.stringValue = @"";
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
    self.shortcutStatus = status;
    // The message says why a key was refused or a shortcut is inactive, as the warnings of Settings ›
    // Keyboard say it: after the yellow warning triangle, in the label color.
    self.shortcutStatus.textColor = NSColor.labelColor;
    NSImageView *mark = [TSPrefPaneLayout warningSymbolForFont:status.font ?: [NSFont systemFontOfSize:NSFont.smallSystemFontSize]];
    mark.identifier = @"macro.shortcut.warning";
    mark.hidden = YES;
    mark.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    self.shortcutStatusMark = mark;
    // At the trailing end of the warning, when the menu command can be cleared.
    NSButton *remove = [NSButton buttonWithTitle:NSLocalizedString(@"Remove…", @"") target:self action:@selector(removeConflictingMenuShortcut:)];
    remove.bezelStyle = NSBezelStylePush;
    remove.controlSize = NSControlSizeSmall;
    remove.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    remove.hidden = YES;
    remove.identifier = @"macro.shortcut.remove";
    remove.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.removeMenuShortcutButton = remove;
    [self layoutShortcutStatusInBand:NSMakeRect(20, statusY, NSWidth(host.bounds)-40, statusHeight)];
    self.shortcutStatus.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [host addSubview:self.shortcutStatus];
    [host addSubview:mark];
    [host addSubview:remove];
}

// Between the warning triangle and the message, as in the warnings of Settings.
static const CGFloat TSMacroWarningSpacing = 4;
// The triangle where the message would begin, the message after it; the lines that follow begin under its first.
// Remove…, when it is showing, takes the trailing end of that text and the message keeps the gap before it.
- (void)layoutShortcutStatusInBand:(NSRect)band
{
    NSTextField *label = self.shortcutStatus;
    NSImageView *mark = self.shortcutStatusMark;
    NSButton *button = self.removeMenuShortcutButton;
    NSRect text = [label alignmentRectForFrame:band];
    NSSize size = mark.intrinsicContentSize;
    mark.frame = [mark frameForAlignmentRect:NSMakeRect(NSMinX(text), 0, size.width, size.height)];
    text.origin.x += size.width + TSMacroWarningSpacing;
    text.size.width -= size.width + TSMacroWarningSpacing;
    label.frame = [label frameForAlignmentRect:text];
    [self alignShortcutStatusMark];
    // Hidden, Remove… sits at the trailing end of the message (it does not take any of the
    // message's width). Showing it keeps that trailing edge and leaves a gap before it.
    if (button && button.hidden) {
        NSSize fit = button.fittingSize;
        button.frame = NSMakeRect(NSMaxX(label.frame) - fit.width, NSMaxY(label.frame) - fit.height, fit.width, fit.height);
    } else if (button) {
        button.hidden = YES;
        [self placeRemoveMenuShortcutButton:YES];
    }
}

// At first as wide as the sidebar of the Multiple Replace window.
static const CGFloat TSMacroEditorSidebarWidth = 240;
// Between the line under the contents and the row of Insert and its help.
static const CGFloat TSMacroContentsLineGap = 10;
// The margin of the text from the edges of the contents.
static const NSSize TSMacroContentsInset = {8, 8};
// The items run down the left of the window in a sidebar, as the sets of the Multiple
// Replace window do: the list from the top edge, under the title bar, to the bar of ＋, −
// and a menu of the less frequent commands at the bottom edge. The rest of the window is
// beside it. The nib's five text buttons stay hidden and keep their actions, titles and
// enabled state. The other controls are laid out before, in the nib's window; this puts
// them in the part beside the sidebar.
- (void)installSidebar
{
    if (self.sidebar) return;
    NSWindow *editor = window;
    NSView *host = editor.contentView;
    NSScrollView *list = [outlineView enclosingScrollView];
    for (NSButton *button in @[newItemButton, submenuButton, separatorButton, deleteButton, duplicateButton]) button.hidden = YES;
    NSString *more = [NSString stringWithFormat:@"%@, %@, %@", submenuButton.title, separatorButton.title, duplicateButton.title];
    TSListBottomBar *bar = [[TSListBottomBar alloc] initWithTarget:self addAction:@selector(listAddPressed:) addToolTip:newItemButton.title
                                                      removeAction:@selector(listRemovePressed:) removeToolTip:deleteButton.title actionsToolTip:more];
    bar.identifier = @"macro.list.bar";
    bar.actionsButton.autoenablesItems = NO;
    for (NSButton *source in @[submenuButton, separatorButton, duplicateButton]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:source.title action:@selector(listActionChosen:) keyEquivalent:@""];
        item.target = self; item.representedObject = source;
        [bar.actionsButton.menu addItem:item];
    }
    // A list without headings, its selection rounded inside the sidebar as the sets': the
    // names, and the shortcuts at the trailing edge as in a menu.
    NSOutlineView *rows = outlineView;
    rows.headerView = nil;
    rows.cornerView = nil;
    rows.style = NSTableViewStyleInset;
    rows.backgroundColor = NSColor.clearColor;
    // No focus ring around the sidebar, as around the sets: the selection shows the focus. (AppKit draws one
    // around the scroll view of a list of cells, as this nib's, not around one of views, as the sets'.)
    rows.focusRingType = NSFocusRingTypeNone;
    // Rows 24 points apart, as the sets', their text in the middle of each.
    rows.rowHeight = 17;
    rows.intercellSpacing = NSMakeSize(rows.intercellSpacing.width, 7);
    NSTableColumn *name = [rows tableColumnWithIdentifier:@"Name"], *key = [rows tableColumnWithIdentifier:@"Key"];
    // In the font of the Multiple Replace window's sets (some nibs have a bold or smaller one).
    NSFont *font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    for (NSTableColumn *column in @[name, key]) {
        NSCell *cell = column.dataCell;
        cell.font = font;
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    key.width = MAX(key.width, ceil([@"⌃⌥⇧⌘W" sizeWithAttributes:@{NSFontAttributeName: font}].width) + 8);
    key.resizingMask = NSTableColumnNoResizing;
    ((NSCell *)key.dataCell).alignment = NSTextAlignmentRight;
    // The names take what the shortcuts leave of the list's width, whatever the sidebar's
    // width: the list never scrolls sideways and the selection keeps its rounded ends inside.
    name.resizingMask = NSTableColumnAutoresizingMask;
    rows.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    [list removeFromSuperview];
    NSVisualEffectView *sidebar = TSListSidebarView(list, bar);
    // The first row 10 points below the title bar, as the first set in its source list.
    list.contentInsets = NSEdgeInsetsMake(5, 0, 0, 0);
    sidebar.identifier = @"macro.sidebar";

    // Beside it, the rest of the window: the fields 20 points from the sidebar and from the
    // window's right edge, as the rules of the Multiple Replace window, the message and the
    // buttons below them.
    CGFloat shift = NSMinX([nameField frame]) - TSDialogMargin;
    CGFloat width = NSMaxX([nameField frame]) - shift + TSDialogMargin, widened = width - NSWidth(host.bounds);
    NSView *main = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, NSHeight(host.bounds))];
    main.identifier = @"macro.main";
    for (NSView *view in [host.subviews copy]) {
        NSRect frame = view.frame;
        frame.origin.x -= shift;
        [view removeFromSuperview];
        view.frame = frame;
        [main addSubview:view];
    }
    // The name is edited in the list (renameSelectedMacro:), so the name field and the labels
    // of the name and the contents go: the contents fill the top of this part, from the title
    // bar and the sidebar to the window's trailing edge, with a line under them. Below the line,
    // Insert and its help, the shortcut, the message and the buttons stay where they were.
    NSScrollView *contents = [contentTextView enclosingScrollView];
    // What the contents gain in height: the smallest window is that much lower.
    CGFloat taller = 0;
    if (contents) {
        NSString *contentsName = nil;
        for (NSView *view in main.subviews) {
            if (view == nameField) { view.hidden = YES; continue; }
            if (![view isKindOfClass:NSTextField.class] || [(NSTextField *)view isEditable] || view.hidden) continue;
            // Above the contents (some nibs' labels are two lines tall and run into them).
            if (NSMaxY(view.frame) <= NSMaxY(contents.frame) + 2) continue;
            NSString *text = [[(NSTextField *)view stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            // The label nearest above the contents names them (for VoiceOver), without its colon.
            if (NSMinY(view.frame) < NSMinY([nameField frame])) contentsName = [text stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":： "]];
            view.hidden = YES;
        }
        CGFloat below = 0;
        for (NSView *view in @[self.insertPlaceholderButton ?: NSNull.null, self.placeholdersButton ?: NSNull.null])
            if ([view isKindOfClass:NSView.class]) below = MAX(below, NSMaxY(view.frame));
        NSRect line = NSMakeRect(0, below + TSMacroContentsLineGap, width, 1);
        NSBox *rule = [[NSBox alloc] initWithFrame:line];
        rule.boxType = NSBoxSeparator;
        rule.frame = [rule frameForAlignmentRect:line]; // the line itself where line is
        rule.identifier = @"macro.contents.line";
        rule.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [main addSubview:rule];
        taller = NSHeight(main.bounds) - NSMaxY(line) - NSHeight(contents.frame);
        contents.frame = NSMakeRect(0, NSMaxY(line), width, NSHeight(main.bounds) - NSMaxY(line));
        contents.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        contents.borderType = NSNoBorder;
        contents.drawsBackground = NO;
        // The text keeps a margin from the edges it now touches.
        contentTextView.textContainerInset = TSMacroContentsInset;
        if (contentsName.length) contentTextView.accessibilityLabel = contentsName;
    }
    NSRect status = self.shortcutStatus.frame;
    [self layoutShortcutStatusInBand:NSMakeRect(TSDialogMargin, NSMinY(status), width - 2 * TSDialogMargin, NSHeight(status))];
    self.editorView = main;
    // The buttons as the Multiple Replace window's: AppKit's own style at its own height, 20
    // points above the bottom edge. Save is the default button (Return), Cancel takes
    // Escape; in the contents both keys stay with the text (keyForContents:).
    for (NSButton *button in @[saveButton, cancelButton, testButton]) {
        button.bezelStyle = NSBezelStyleAutomatic;
        NSRect frame = button.frame;
        frame.size.height = button.fittingSize.height;
        frame.origin.y = TSDialogMargin;
        button.frame = frame;
    }
    saveButton.keyEquivalent = @"\r";
    cancelButton.keyEquivalent = @"\033";
    [self layoutDialogButtons];
    // As narrow as the fields and the buttons allow: what the nib's window allowed for the fields.
    CGFloat narrowest = MAX(MAX(editor.minSize.width, editor.contentMinSize.width) + widened,
                            TSDialogButtonsWidth(@[saveButton, cancelButton], @[testButton]));
    NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, NSHeight(editor.frame))];
    main.translatesAutoresizingMaskIntoConstraints = NO;
    [pane addSubview:main];
    [NSLayoutConstraint activateConstraints:@[
        [main.topAnchor constraintEqualToAnchor:pane.safeAreaLayoutGuide.topAnchor],
        [main.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [main.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [main.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor],
    ]];
    NSViewController *sidebarController = [NSViewController new], *mainController = [NSViewController new];
    sidebarController.view = sidebar;
    mainController.view = pane;
    CGFloat minimumHeight = editor.minSize.height - MAX(0, taller);
    NSSplitViewController *split = TSInstallListSidebar(editor, sidebarController, mainController, TSMacroEditorSidebarWidth, narrowest, @"TSMacroEditorSplit");
    editor.minSize = NSMakeSize(TSListSidebarMinimumWidth + split.splitView.dividerThickness + narrowest, minimumHeight);
    [split.view layoutSubtreeIfNeeded];
    self.sidebar = sidebar; self.listBar = bar;
    // The name is edited in place in the list, not by a double click (listDoubleClicked:).
    [rows tableColumnWithIdentifier:@"Name"].editable = YES;
    [rows tableColumnWithIdentifier:@"Key"].editable = NO;
    __weak TSMacroEditor *weakSelf = self;
    // The field a shortcut is recorded in, over the item's shortcut (beginRecordingShortcutAtRow:): ⊖ removes
    // the shortcut, and a click elsewhere ends the recording.
    TSShortcutRecordingCell *recording = [TSShortcutRecordingCell new];
    recording.recorder.removeButton.target = self;
    recording.recorder.removeButton.action = @selector(removeRecordedShortcut:);
    recording.recorder.resigned = ^{ [weakSelf finishShortcutRecordingFocusingList:NO]; };
    self.recordingCell = recording;
    // Wide enough for the longest shortcut, ⊖ and the triangle.
    CGFloat recordingWidth = 0;
    for (NSString *longest in @[@"⌃⌥⇧⌘F20", @"⌃⌥⇧⌘W", @"⌃⌥⇧⌘M"])
        recordingWidth = MAX(recordingWidth, [TSShortcutRecordingCell widthForShortcut:longest]);
    ((TSMacroOutlineView *)rows).recordingWidth = recordingWidth;
    self.contentsKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return weakSelf ? [weakSelf keyForContents:event] : event;
    }];
    [self syncListControls];
}
// Return, Enter and Escape go where the keyboard focus is before the window looks for a
// button with that key (Save, Cancel), as in Finder and the source:
// - in the list, Return and Enter start renaming the selected item, and Escape does nothing;
// - while an item is renamed, Return and Enter keep the new name, Escape keeps the old one;
// - in the contents, Return and Enter start a new line and Escape completes.
// Elsewhere (Insert, the buttons) Return saves and Escape cancels. Save also takes Command-S
// (saveDocument:). While a shortcut is recorded, every key goes to the recording first, Command-S,
// Command-W and Command-Q too (handleShortcutRecordingEvent:).
- (NSEvent *)keyForContents:(NSEvent *)event
{
    NSWindow *editor = window;
    NSResponder *responder = editor.firstResponder;
    if (event.type != NSEventTypeKeyDown || event.windowNumber != editor.windowNumber) return event;
    if (self.recordingItem && responder == self.recordingCell.recorder) {
        [self handleShortcutRecordingEvent:event];
        return nil;
    }
    // Any key cancels the renaming that a second click on a name would start.
    [self cancelPendingListRename];
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) return event;
    NSString *key = event.charactersIgnoringModifiers;
    BOOL newline = [key isEqual:@"\r"] || [key isEqual:@"\x03"], escape = [key isEqual:@"\x1b"];
    if (!newline && !escape) return event;
    BOOL text = [responder isKindOfClass:NSTextView.class];
    if (text && ((NSTextView *)responder).isFieldEditor && ((NSTextView *)responder).delegate == outlineView) {
        if (escape) [outlineView abortEditing];
        [editor makeFirstResponder:outlineView]; // ends the renaming, keeping what was typed
        return nil;
    }
    if (responder == outlineView) {
        if (escape) return nil;
        if (![self beginRenamingSelectedItem]) NSBeep();
        return nil;
    }
    if (!text || ((NSTextView *)responder).isFieldEditor) return event;
    [editor sendEvent:event];
    return nil;
}
// Renames the selected item in place in the list, as Finder does: not a separator, which has
// no name, nor several items at once. The name is kept when the renaming ends (Return, a click
// elsewhere), and Escape keeps the old one (keyForContents:).
- (BOOL)beginRenamingSelectedItem
{
    [self cancelPendingListRename];
    NSOutlineView *rows = outlineView;
    if (rows == nil || rows.numberOfSelectedRows != 1 || [window attachedSheet]) return NO;
    NSInteger row = rows.selectedRow, column = [rows columnWithIdentifier:@"Name"];
    TSMacroTreeNode *item = [rows itemAtRow:row];
    if (column < 0 || ![item isKindOfClass:TSMacroTreeNode.class] || item.isSeparator) return NO;
    if (![window makeFirstResponder:rows]) return NO;
    [rows scrollRowToVisible:row];
    self.renaming = YES;
    [rows editColumn:column row:row withEvent:nil select:YES];
    self.renaming = NO;
    return rows.currentEditor != nil;
}
// The list (TSMacroOutlineView) forgets the renaming a second click on a name would start.
- (void)cancelPendingListRename
{
    if ([outlineView respondsToSelector:@selector(cancelPendingRename)]) [outlineView performSelector:@selector(cancelPendingRename)];
}
// A second click on the name of the selected item (TSMacroOutlineView) and a new item or submenu.
- (IBAction)renameSelectedMacro:(id)sender
{
    if (![self beginRenamingSelectedItem]) NSBeep();
}
- (void)stopKeyMonitor
{
    id monitor = self.contentsKeyMonitor;
    if (monitor) [NSEvent removeMonitor:monitor];
    self.contentsKeyMonitor = nil;
}
// The editor outlives its window (it is shared): when the window closes, it lets go of the
// controls it added, so that the next window gets its own sidebar, fields and key monitor.
- (void)releaseWindowControls
{
    [self cancelPendingListRename];
    [self stopKeyMonitor];
    [self endShortcutRecording];
    [self.placeholdersPopover close];
    self.placeholdersPopover = nil;
    self.shortcutStatus = nil; self.shortcutStatusMark = nil; self.removeMenuShortcutButton = nil;
    self.sidebar = nil; self.listBar = nil; self.editorView = nil;
    self.insertPlaceholderButton = nil; self.placeholdersButton = nil;
    self.recordingCell = nil;
    self.pendingShortcutKey = @"";
}
// The line of a separator in the list, as the lines of menus are now.
NSImage *TSMacroSeparatorImage(CGFloat width)
{
    return [NSImage imageWithSize:NSMakeSize(MAX(1, width), 3) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.separatorColor setFill];
        NSRectFill(NSMakeRect(0, 1, NSWidth(rect), 1));
        return YES;
    }];
}
// Interface text in the system font: some nibs name another font (the Chinese one STHeiti).
- (void)useSystemFont
{
    NSView *content = [window contentView];
    NSMutableArray<NSView *> *pending = content ? [NSMutableArray arrayWithObject:content] : [NSMutableArray array];
    while (pending.count) {
        NSView *view = pending.lastObject; [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (![view isKindOfClass:NSControl.class]) continue;
        NSControl *control = (NSControl *)view;
        NSFont *font = control.font;
        if (font == nil || [font.fontName hasPrefix:@"."]) continue;
        BOOL bold = ([NSFontManager.sharedFontManager traitsOfFont:font] & NSBoldFontMask) != 0;
        control.font = bold ? [NSFont boldSystemFontOfSize:font.pointSize] : [NSFont systemFontOfSize:font.pointSize];
    }
}
- (void)syncListControls
{
    self.listBar.addButton.enabled = newItemButton.enabled;
    self.listBar.removeButton.enabled = deleteButton.enabled;
    for (NSMenuItem *item in self.listBar.actionItems) item.enabled = [item.representedObject isEnabled];
}
// What one of the hidden nib buttons does, while it is enabled.
static void TSSendButtonAction(NSButton *button)
{
    SEL action = button.action;
    if (button.enabled && action) [NSApp sendAction:action to:button.target from:button];
}
// A new item or submenu is named at once, as a new folder in Finder and a new set of the
// Multiple Replace window.
- (void)listAddPressed:(id)sender
{
    if (!newItemButton.enabled) return;
    TSSendButtonAction(newItemButton);
    [self beginRenamingSelectedItem];
}
- (void)listRemovePressed:(id)sender { TSSendButtonAction(deleteButton); }
- (void)listActionChosen:(NSMenuItem *)sender
{
    NSButton *button = sender.representedObject;
    if (!button.enabled) return;
    TSSendButtonAction(button);
    if (button == submenuButton) [self beginRenamingSelectedItem];
}
// The shortcut is recorded in the list (beginRecordingShortcutAtRow:): the nib's key field, its Shift,
// Option and Control boxes and their labels stay hidden, and the contents take their rows, down to the
// bottom of the field the shortcut had there; the row of Insert comes below the contents.
- (void)hideNibShortcutRows
{
    if ([keyField isHidden]) return;
    NSView *host = [window contentView];
    NSArray<NSView *> *controls = @[keyField, shiftCheckBox, optionCheckBox, controlCheckBox];
    NSRect upper = NSInsetRect([keyField frame], 0, -4), lower = NSInsetRect([shiftCheckBox frame], 0, -4);
    NSMutableArray<NSView *> *hidden = [controls mutableCopy];
    for (NSView *view in host.subviews) {
        if (![view isKindOfClass:NSTextField.class] || [controls containsObject:view] || [(NSTextField *)view isEditable]) continue;
        NSRect frame = view.frame;
        if (NSMinX(frame) < NSMinX([nameField frame]) - 12) continue; // the right column only
        if ((NSMinY(frame) < NSMaxY(upper) && NSMaxY(frame) > NSMinY(upper)) || (NSMinY(frame) < NSMaxY(lower) && NSMaxY(frame) > NSMinY(lower)))
            [hidden addObject:view];
    }
    for (NSView *view in hidden) view.hidden = YES;
    // The field was as tall as a text field is now (the nibs' are 22 points), in the middle of the boxes' row.
    CGFloat middle = NSMidY([shiftCheckBox frame]), height = MAX(NSHeight([keyField frame]), [NSTextField textFieldWithString:@""].fittingSize.height);
    CGFloat bottom = round(middle - height / 2);
    NSScrollView *contents = [contentTextView enclosingScrollView];
    NSRect frame = contents.frame;
    if (NSMinY(frame) > bottom) { frame.size.height += NSMinY(frame) - bottom; frame.origin.y = bottom; }
    contents.frame = frame;
    // The key view loop goes past the hidden controls.
    NSView *next = [keyField nextKeyView];
    for (NSUInteger guard = 0; next && [hidden containsObject:next] && guard < 8; guard++) next = [next nextKeyView];
    NSMutableArray<NSView *> *pending = [host.subviews mutableCopy];
    while (pending.count) {
        NSView *view = pending.lastObject; [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.nextKeyView == keyField) view.nextKeyView = next;
    }
}
// BEGIN shortcut recording
// A macro's shortcut is recorded in its own cell of the list, as the menu shortcuts are in Settings ›
// Keyboard: a click on the shortcut of the item that was selected alone, a double click on a shortcut, or
// VoiceOver's press on it starts; the key pressed becomes the shortcut at once, unless it cannot be one or
// another command uses it. Separators and submenus have no shortcut.
- (BOOL)beginRecordingShortcutForItem:(TSMacroTreeNode *)item
{
    return [self beginRecordingShortcutAtRow:item ? [outlineView rowForItem:item] : -1];
}
- (BOOL)beginRecordingShortcutAtRow:(NSInteger)row
{
    TSMacroOutlineView *rows = outlineView;
    TSMacroTreeNode *item = row >= 0 && row < [rows numberOfRows] ? [rows itemAtRow:row] : nil;
    TSShortcutKeyRecorder *recorder = self.recordingCell.recorder;
    if (![item isKindOfClass:TSMacroTreeNode.class] || !item.isStandardItem || recorder == nil || window == nil || [window attachedSheet]) return NO;
    [self cancelPendingListRename];
    if (self.recordingItem != item) {
        [self endShortcutRecording];
        // A renaming in the list ends first, keeping the name typed.
        if ([rows currentEditor] && ![window makeFirstResponder:rows]) return NO;
        if ([rows numberOfSelectedRows] != 1 || [rows selectedRow] != row)
            [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        if (self.previousItem != item) return NO;
        self.recordingItem = item; self.recordingError = nil; self.refusedShortcut = nil;
        [self updateShortcutRecorder];
        rows.recordingItem = item;
        rows.recordingView = self.recordingCell;
        [rows setNeedsDisplayInRect:[rows rectOfRow:row]];
        [rows scrollRowToVisible:row];
    }
    [window makeFirstResponder:recorder];
    if ([window firstResponder] != recorder) { [self endShortcutRecording]; return NO; }
    [self updateShortcutStatus];
    return YES;
}
// Ends the recording and keeps the shortcut as it is now; the list takes the focus the field had.
- (void)endShortcutRecording { [self finishShortcutRecordingFocusingList:YES]; }
- (void)finishShortcutRecordingFocusingList:(BOOL)focusList
{
    TSMacroTreeNode *item = self.recordingItem;
    if (item == nil || self.endingShortcutRecording) return;
    self.endingShortcutRecording = YES;
    self.recordingItem = nil; self.recordingError = nil; self.refusedShortcut = nil;
    if (focusList) {
        if ([window firstResponder] == self.recordingCell.recorder) [window makeFirstResponder:outlineView];
        [self removeShortcutRecorderOfItem:item];
    } else {
        // The field is giving up the focus to a click elsewhere: it leaves the row once the focus has moved.
        __weak TSMacroEditor *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            TSMacroEditor *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf.recordingItem != item) [strongSelf removeShortcutRecorderOfItem:item];
        });
    }
    self.endingShortcutRecording = NO;
    [self updateShortcutStatus];
}
// The row shows its shortcut again; the field leaves the list unless it records another item's by now.
- (void)removeShortcutRecorderOfItem:(TSMacroTreeNode *)item
{
    TSMacroOutlineView *rows = outlineView;
    if (rows.recordingItem == item) { rows.recordingView = nil; rows.recordingItem = nil; }
    NSInteger row = [rows rowForItem:item];
    if (row >= 0) [rows setNeedsDisplayInRect:[rows rectOfRow:row]];
}
// Another selection ends the recording and keeps the shortcut.
- (void)endShortcutRecordingUnlessSelected
{
    TSMacroTreeNode *item = self.recordingItem;
    NSArray *selected = [outlineView allSelectedItems];
    if (item && !(selected.count == 1 && selected.firstObject == item)) [self endShortcutRecording];
}
// A click on the shortcut of the item that was selected alone records a new one; a click on another
// item only selects it, as in Settings › Keyboard and Xcode.
- (void)listClicked:(id)sender
{
    TSMacroOutlineView *rows = outlineView;
    NSInteger row = [rows clickedRow];
    if (row < 0 || row != rows.rowSelectedAtMouseDown || [rows clickedColumn] != [rows columnWithIdentifier:@"Key"]) return;
    if ([rows numberOfSelectedRows] != 1 || [rows selectedRow] != row) return;
    [self beginRecordingShortcutAtRow:row];
}
// While recording: Escape and Return end it and keep the shortcut, Tab moves on, Delete removes the
// shortcut; any other key may become it.
- (void)handleShortcutRecordingEvent:(NSEvent *)event
{
    NSString *key = event.charactersIgnoringModifiers;
    unichar c = key.length == 1 ? [key characterAtIndex:0] : 0;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if (!flags && (c == 27 || c == '\r' || c == 3)) { [self endShortcutRecording]; return; }
    if ((c == '\t' || c == 25) && !(flags & ~NSEventModifierFlagShift)) {
        NSWindow *editor = window;
        [self endShortcutRecording];
        if (c == 25 || (flags & NSEventModifierFlagShift)) [editor selectPreviousKeyView:nil]; else [editor selectNextKeyView:nil];
        return;
    }
    if (!flags && (c == 127 || c == 8 || c == NSDeleteFunctionKey)) { [self removeRecordedShortcut:nil]; return; }
    [self recordShortcutEvent:event];
}
// ⊖ in the field, and Delete.
- (IBAction)removeRecordedShortcut:(id)sender
{
    if (self.recordingItem == nil) return;
    [self endShortcutRecording];
    [self setPendingShortcut:@""];
}
// A key pressed while recording: Command or Control with a key, or F1–F20, as in Settings, that no menu
// command and no other macro uses, becomes the shortcut and ends the recording. Another key is refused
// with the reason below the contents, and the recording goes on.
- (BOOL)recordShortcutEvent:(NSEvent *)event
{
    TSMacroTreeNode *item = self.recordingItem;
    if (!item.isStandardItem || self.previousItem != item) return NO;
    TSShortcutBinding *binding = TSRecordedBinding(event, [event charactersByApplyingModifiers:0]);
    NSString *globe = TSGlobeRecordingRefusal(event);
    if (globe) {
        self.refusedShortcut = TSShortcutDisplayKey(binding.key, binding.modifiers | NSEventModifierFlagFunction);
        [self showShortcutRecordingError:globe];
        return NO;
    }
    if (binding.key.length != 1 || ![TSShortcutStore isAllowedKey:binding.key modifiers:binding.modifiers]) {
        // The field shows the key pressed, as for a key another command uses; a key without a character, the shortcut.
        self.refusedShortcut = binding.key.length ? TSShortcutDisplayKey(binding.key, binding.modifiers) : nil;
        [self showShortcutRecordingError:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"")];
        return NO;
    }
    NSString *shortcut = getStringFormKeyEquivalentWithModifiers(binding.key, binding.modifiers);
    NSString *conflict = [self shortcutConflictForEvent:event];
    if (conflict) {
        self.refusedShortcut = getMenuItemString(shortcut);
        [self showShortcutRecordingError:conflict];
        return NO;
    }
    [self endShortcutRecording];
    [self setPendingShortcut:shortcut];
    return YES;
}
// Who else uses the key pressed, as Settings › Keyboard says it: menu commands whose keys work (those
// that make a macro's shortcut inactive, TSShortcutStore's conflictsForMacroShortcuts:), and the other
// macros of the list (Macros › …); nil when no one does.
- (NSString *)shortcutConflictForEvent:(NSEvent *)event
{
    NSArray<TSShortcutBinding *> *bindings = TSEventBindings(event, [event charactersByApplyingModifiers:0]);
    TSShortcutStore *store = [TSKeyboardShortcuts sharedController].store;
    NSMutableArray *nodes = [NSMutableArray array], *candidates = [NSMutableArray array];
    [self collectShortcutCandidates:[outlineController rootOfTree] path:NSLocalizedString(@"Macros", @"") nodes:nodes candidates:candidates];
    NSMutableOrderedSet<NSString *> *users = [NSMutableOrderedSet orderedSet];
    for (TSShortcutBinding *binding in bindings) {
        for (TSShortcutMatch *match in [store menuMatchesKey:binding.key modifiers:binding.modifiers excluding:nil])
            if (!match.menuItem.hidden || match.menuItem.allowsKeyEquivalentWhenHidden) [users addObject:match.path];
        for (NSUInteger index = 0; index < candidates.count; index++) {
            NSDictionary *candidate = candidates[index];
            NSString *path = candidate[@"path"];
            if (path && nodes[index] != self.recordingItem && [TSBinding(candidate[@"key"], [candidate[@"modifiers"] unsignedIntegerValue]) isEqual:binding])
                [users addObject:path];
        }
    }
    if (users.count == 0) return nil;
    if (users.count == 1) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), users.firstObject];
    return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by:\n%@", @""), [users.array componentsJoinedByString:@"\n"]];
}
// The reason under the contents and the triangle in the field's cell; VoiceOver reads the reason.
- (void)showShortcutRecordingError:(NSString *)error
{
    self.recordingError = error;
    [self updateShortcutRecorder];
    [self updateShortcutStatus];
    if ([window isKeyWindow])
        NSAccessibilityPostNotificationWithUserInfo(self.recordingCell.recorder, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey: error, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh)});
}
// The field shows the shortcut, or the key pressed that was refused; empty for a macro without one
// (the list shows nothing either). ⊖ only while the macro has a shortcut to remove.
- (void)updateShortcutRecorder
{
    TSMacroTreeNode *item = self.recordingItem;
    if (item == nil) return;
    NSString *current = (self.previousItem == item ? self.pendingShortcutKey : item.key) ?: @"";
    self.recordingCell.recorder.shortcut = self.refusedShortcut ?: getMenuItemString(current);
    self.recordingCell.recorder.removeButton.hidden = current.length == 0;
    self.recordingCell.warning.hidden = self.recordingError == nil;
}
// END shortcut recording
- (void)setPendingShortcut:(NSString *)key
{
    if (!self.previousItem.isStandardItem) return;
    self.pendingShortcutKey = key;
    keyTouched = YES;
    [self updatePendingShortcutStatus];
    [self reflectChangesInEditor:YES];
}
// Below the contents, as in the key binding list of Settings › Keyboard: Insert
// adds a placeholder (shown as a token), and the help button lists them.
- (void)installPlaceholderControls
{
    if (self.insertPlaceholderButton) return;
    NSView *host = [window contentView];
    NSScrollView *contents = [contentTextView enclosingScrollView];
    NSPopUpButton *insert = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    insert.identifier = @"macro.insert";
    insert.autoenablesItems = NO;
    [insert addItemWithTitle:NSLocalizedString(@"Insert", @"Key binding Insert menu")];
    NSMenu *menu = insert.menu;
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"TeX"]];
    for (NSString *symbol in @[@"#SEL#", @"#INS#", @"#PASTE#", @"•"])
        [menu addItem:[self placeholderItemWithTitle:TSPlaceholderTokenTitle(symbol) symbol:symbol]];
    [menu addItem:[self placeholderItemWithTitle:NSLocalizedString(@"Mark with Note", @"Key binding Insert menu") symbol:@"•‹›"]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"AppleScript"]];
    for (NSString *symbol in TSSyntaxMacroContentScanner.appleScriptPlaceholders)
        [menu addItem:[self placeholderItemWithTitle:TSPlaceholderTokenTitle(symbol) symbol:symbol]];
    menu.delegate = self;
    [insert sizeToFit];
    NSButton *help = [NSButton buttonWithTitle:@"" target:self action:@selector(showPlaceholders:)];
    help.bezelStyle = NSBezelStyleHelpButton;
    help.identifier = @"macro.placeholders";
    help.accessibilityLabel = NSLocalizedString(@"Symbols", @"Key binding symbols help button");
    help.toolTip = help.accessibilityLabel;
    [help sizeToFit];
    NSRect frame = contents.frame;
    CGFloat height = ceil(MAX(NSHeight(insert.frame), NSHeight(help.frame)));
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
    insert.frame = NSMakeRect(NSMinX(frame), NSMinY(frame) + round((height - NSHeight(insert.frame)) / 2), NSWidth(insert.frame), NSHeight(insert.frame));
    help.frame = NSMakeRect(NSMaxX(frame) - NSWidth(help.frame), NSMinY(frame) + round((height - NSHeight(help.frame)) / 2), NSWidth(help.frame), NSHeight(help.frame));
    frame.origin.y += height + gap; frame.size.height -= height + gap;
    contents.frame = frame;
    insert.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    help.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [host addSubview:insert];
    [host addSubview:help];
    self.insertPlaceholderButton = insert;
    self.placeholdersButton = help;
    // The contents keep at least 64pt at the smallest window size, and the row its two controls.
    NSSize smallest = [window minSize];
    CGFloat narrowest = NSWidth(insert.frame) + 12 + NSWidth(help.frame);
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
    [self syncPlaceholderControls];
}
- (NSMenuItem *)placeholderItemWithTitle:(NSString *)title symbol:(NSString *)symbol
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(insertPlaceholder:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = symbol;
    return item;
}
// Insert works on a macro, not on a submenu or a separator. Its items are those
// of the kind of the macro: a TeX macro does not replace #FILEPATH#, nor an
// AppleScript macro #SEL#.
- (void)syncPlaceholderControls
{
    self.insertPlaceholderButton.enabled = self.previousItem.isStandardItem && [contentTextView isEditable];
}
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu != self.insertPlaceholderButton.menu) return;
    BOOL teX = TSMacroContentKindForString([contentTextView string] ?: @"") == TSMacroContentKindTeX;
    NSArray<NSString *> *appleScript = TSSyntaxMacroContentScanner.appleScriptPlaceholders;
    for (NSMenuItem *item in menu.itemArray) {
        NSString *symbol = item.representedObject;
        if (![symbol isKindOfClass:NSString.class]) continue;
        item.enabled = [appleScript containsObject:symbol] ? !teX : teX;
    }
}
- (void)insertPlaceholder:(NSMenuItem *)sender
{
    NSString *symbol = sender.representedObject;
    if (![symbol isKindOfClass:NSString.class] || ![contentTextView isEditable]) return;
    [window makeFirstResponder:contentTextView];
    NSRange range = [contentTextView selectedRange];
    [contentTextView insertText:symbol replacementRange:range];
    // A mark with a note leaves the insertion point in the note.
    if ([symbol hasSuffix:@"›"]) [contentTextView setSelectedRange:NSMakeRange(range.location + symbol.length - 1, 0)];
}
- (IBAction)showPlaceholders:(id)sender
{
    if (self.placeholdersPopover.shown) { [self.placeholdersPopover close]; return; }
    NSPopover *popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    NSViewController *content = [[NSViewController alloc] initWithNibName:nil bundle:nil];
    NSView *list = [self makePlaceholderListView];
    list.frame = (NSRect){NSZeroPoint, list.fittingSize};
    content.view = list;
    content.preferredContentSize = list.frame.size;
    popover.contentViewController = content;
    self.placeholdersPopover = popover;
    NSView *anchor = self.placeholdersButton;
    [popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
}
// What each token stands for and how it is typed: the TeX placeholders and marks,
// and beside them the AppleScript ones, with the help about marks below.
- (NSView *)makePlaceholderListView
{
    NSFont *font = [NSFont monospacedSystemFontOfSize:NSFont.systemFontSize - 1 weight:NSFontWeightRegular];
    NSTextField *(^heading)(NSString *, BOOL) = ^NSTextField *(NSString *title, BOOL section) {
        NSTextField *label = [NSTextField labelWithString:title];
        label.font = section ? [NSFont boldSystemFontOfSize:NSFont.systemFontSize]
                             : [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
        label.textColor = section ? NSColor.labelColor : NSColor.secondaryLabelColor;
        return label;
    };
    NSView *(^token)(NSString *, NSString *) = ^NSView *(NSString *title, NSString *after) {
        NSImageView *image = [NSImageView imageViewWithImage:TSPlaceholderTokenImage(title, font)];
        image.imageAlignment = NSImageAlignLeft;
        if (after.length == 0) return image;
        NSTextField *note = [NSTextField labelWithString:after];
        note.font = font;
        NSStackView *both = [NSStackView stackViewWithViews:@[image, note]];
        both.spacing = 0;
        return both;
    };
    NSView *(^typed)(NSString *) = ^NSView *(NSString *symbol) {
        NSTextField *label = [NSTextField labelWithString:symbol];
        label.font = font;
        label.selectable = YES;
        return label;
    };
    NSView *(^section)(NSString *, NSArray<NSArray<NSView *> *> *) = ^NSView *(NSString *title, NSArray<NSArray<NSView *> *> *rows) {
        NSMutableArray<NSArray<NSView *> *> *all = [NSMutableArray arrayWithObject:@[heading(NSLocalizedString(@"Display", @"Key binding symbols: how a symbol is shown"), NO),
                                                                                     heading(NSLocalizedString(@"Typed As", @"Key binding symbols: how a symbol is typed in an output string"), NO)]];
        [all addObjectsFromArray:rows];
        NSGridView *grid = [NSGridView gridViewWithViews:all];
        grid.rowSpacing = 6; grid.columnSpacing = 18;
        for (NSInteger r = 0; r < grid.numberOfRows; r++) [grid rowAtIndex:r].yPlacement = NSGridCellPlacementCenter;
        [grid rowAtIndex:0].bottomPadding = 2;
        [grid columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
        NSStackView *stack = [NSStackView stackViewWithViews:@[heading(title, YES), grid]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 8;
        // The shorter list keeps its rows together at the top.
        for (NSView *view in @[grid, stack])
            [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        return stack;
    };
    NSMutableArray<NSArray<NSView *> *> *teX = [NSMutableArray array];
    for (NSString *symbol in @[@"#SEL#", @"#INS#", @"#PASTE#", @"•"])
        [teX addObject:@[token(TSPlaceholderTokenTitle(symbol), nil), typed(symbol)]];
    NSString *note = NSLocalizedString(@"note", @"Placeholder for the note of a mark: •‹note›");
    [teX addObject:@[token(TSPlaceholderTokenTitle(@"•"), [NSString stringWithFormat:@"‹%@›", note]), typed([NSString stringWithFormat:@"•‹%@›", note])]];
    NSMutableArray<NSArray<NSView *> *> *appleScript = [NSMutableArray array];
    for (NSString *symbol in TSSyntaxMacroContentScanner.appleScriptPlaceholders)
        [appleScript addObject:@[token(TSPlaceholderTokenTitle(symbol), nil), typed(symbol)]];
    NSView *left = section(@"TeX", teX), *right = section(@"AppleScript", appleScript);
    NSStackView *columns = [NSStackView stackViewWithViews:@[left, right]];
    columns.alignment = NSLayoutAttributeTop;
    columns.spacing = 28;

    NSButton *marks = [NSButton buttonWithTitle:NSLocalizedString(@"How to Use Marks…", @"Edit › Mark") target:[TSMarkMenu sharedInstance] action:@selector(showMarkHelp:)];
    marks.bordered = NO;
    marks.attributedTitle = [[NSAttributedString alloc] initWithString:marks.title attributes:@{NSForegroundColorAttributeName: NSColor.linkColor, NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize]}];

    NSStackView *stack = [NSStackView stackViewWithViews:@[columns, marks]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    stack.identifier = @"macro.placeholder-list";
    // Leading alignment alone lets the fitting width cut the widest column.
    for (NSView *child in stack.arrangedSubviews)
        [stack.widthAnchor constraintGreaterThanOrEqualToAnchor:child.widthAnchor constant:stack.edgeInsets.left + stack.edgeInsets.right].active = YES;
    return stack;
}
// Save is the default button at the trailing edge with Cancel before it; Test,
// which does not close the window, starts the row at the leading edge.
- (void)layoutDialogButtons
{
    TSLayoutDialogButtons(self.editorView ?: [window contentView], @[saveButton, cancelButton], @[testButton]);
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

// BEGIN shortcut status
// The triangle on the message's first line (layoutShortcutStatusInBand: puts it before the message): its
// baseline on the line's, as the warnings of Settings line them up (NSStackView's first baselines).
- (void)alignShortcutStatusMark
{
    NSTextField *label = self.shortcutStatus;
    NSImageView *mark = self.shortcutStatusMark;
    if (label == nil || mark == nil) return;
    NSRect text = [label alignmentRectForFrame:label.frame];
    NSSize size = mark.intrinsicContentSize;
    CGFloat baseline = NSMaxY(text) - label.firstBaselineOffsetFromTop;
    NSRect rect = NSMakeRect(NSMinX([mark alignmentRectForFrame:mark.frame]),
                             baseline + mark.firstBaselineOffsetFromTop - size.height, size.width, size.height);
    mark.frame = [mark frameForAlignmentRect:rect];
}
// Below the contents: why the key pressed while recording was refused, otherwise why the selected
// macro's shortcut is inactive; nothing, not even the triangle, when there is no reason.
- (void)updateShortcutStatus
{
    NSString *message = self.recordingItem ? self.recordingError : nil;
    [self showShortcutStatus:message ?: [self shortcutConflictForNode:self.previousItem]];
}
- (void)showShortcutStatus:(NSString *)message
{
    self.shortcutStatus.stringValue = message ?: @"";
    self.shortcutStatusMark.hidden = message.length == 0;
    [self placeRemoveMenuShortcutButton:[self removableMenuShortcutForStatus:message] != nil];
}
// The menu command of the warning now showing, when Settings › Keyboard can clear its shortcut.
// Nothing while a recording error replaces that warning, or when the other use is a macro,
// a command macOS keeps, or an item with no command.
- (NSDictionary *)removableMenuShortcutForStatus:(NSString *)message
{
    if (self.recordingItem || message.length == 0 || !self.previousItem) return nil;
    NSString *reason = [self shortcutConflictForNode:self.previousItem];
    if (!reason.length || ![message isEqualToString:reason]) return nil;
    NSDictionary *other = [self.shortcutConflictInfo objectForKey:self.previousItem][@"other"];
    NSString *commandID = other[@"commandID"];
    if (![commandID isKindOfClass:NSString.class] || !commandID.length) return nil;
    return other;
}
// Between the message and Remove…, when that button is showing.
static const CGFloat TSMacroRemoveShortcutGap = 8;
// Show or hide Remove… at the trailing end of the message. The label grows and shrinks with
// the window; the button stays at the trailing end, and the gap between them stays.
- (void)placeRemoveMenuShortcutButton:(BOOL)show
{
    NSButton *button = self.removeMenuShortcutButton;
    NSTextField *label = self.shortcutStatus;
    if (button == nil || label == nil || button.hidden == !show) {
        [self alignShortcutStatusMark];
        return;
    }
    NSRect labelFrame = label.frame;
    if (show) {
        // Keep the size from the last layout. Measuring again can differ by half a point
        // once the button is in the window, and the message would not come back exactly.
        NSSize fit = button.frame.size;
        if (fit.width < 1 || fit.height < 1) fit = button.fittingSize;
        CGFloat trailing = NSMaxX(labelFrame);
        labelFrame.size.width = MAX(0, NSWidth(labelFrame) - fit.width - TSMacroRemoveShortcutGap);
        NSRect buttonFrame = NSMakeRect(NSMaxX(labelFrame) + TSMacroRemoveShortcutGap, NSMaxY(labelFrame) - fit.height, fit.width, fit.height);
        if (NSMaxX(buttonFrame) > trailing + 0.5) buttonFrame.origin.x = trailing - fit.width;
        button.frame = buttonFrame;
        button.hidden = NO;
    } else {
        labelFrame.size.width = NSMaxX(button.frame) - NSMinX(labelFrame);
        button.hidden = YES;
    }
    label.frame = labelFrame;
    [self alignShortcutStatusMark];
}
// Cancel is first, so Return and Escape leave the shortcut (TSRunShortcutAlert sends Escape to
// the first button). OK removes it.
- (NSModalResponse)confirmRemovingShortcut:(NSString *)shown fromMenuItem:(NSString *)path
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"Remove the shortcut %2$@ from the menu item “%1$@”?", @""), path ?: @"", shown ?: @""];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
    return TSRunShortcutAlert(alert);
}
- (void)clearMenuShortcutWithID:(NSString *)commandID
{
    TSShortcutStore *store = [TSKeyboardShortcuts sharedController].store;
    TSShortcutCommand *command = nil;
    for (TSShortcutCommand *candidate in store.commands)
        if ([candidate.commandID isEqualToString:commandID]) { command = candidate; break; }
    NSString *error = command ? [store setKey:@"" modifiers:0 forCommand:command] : NSLocalizedString(@"This command is no longer available.", @"");
    [[TSKeyboardShortcuts sharedController] refreshMenuAndMacros];
    if (error.length) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = error;
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
        TSRunShortcutAlert(alert);
    }
}
- (IBAction)removeConflictingMenuShortcut:(id)sender
{
    NSDictionary *other = [self removableMenuShortcutForStatus:self.shortcutStatus.stringValue];
    if (!other) return;
    NSString *shown = [TSShortcutStore displayKey:other[@"key"] ?: @"" modifiers:[other[@"modifiers"] unsignedIntegerValue]];
    if ([self confirmRemovingShortcut:shown fromMenuItem:other[@"path"]] != NSAlertSecondButtonReturn) return;
    [self clearMenuShortcutWithID:other[@"commandID"]];
}
// END shortcut status

- (void)updatePendingShortcutStatus
{
    if (!self.previousItem.isStandardItem) return;
    NSString *saved = self.previousItem.key;
    self.previousItem.key = self.pendingShortcutKey ?: @"";
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
    self.shortcutConflictInfo = [NSMapTable strongToStrongObjectsMapTable];
    for (NSDictionary *conflict in conflicts) {
        TSMacroTreeNode *node = nodes[[conflict[@"index"] unsignedIntegerValue]];
        [self.shortcutConflicts setObject:[TSShortcutStore reasonForMacroConflict:conflict] forKey:node];
        [self.shortcutConflictInfo setObject:conflict forKey:node];
    }
    [self updateShortcutStatus];
    // Repaint cells without rebuilding the tree or changing its current selection.
    [outlineView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [outlineView numberOfRows])]
                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [outlineView numberOfColumns])]];
}
- (void)menuShortcutsChanged:(NSNotification *)notification { [self refreshShortcutConflicts]; }
// BEGIN shortcut conflicts alert
// The alert that lists the macro shortcuts that conflict, with the three ways on.
static NSAlert *TSShortcutConflictsAlert(NSString *details)
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
    return alert;
}
// END shortcut conflicts alert
- (NSModalResponse)showShortcutConflicts:(NSString *)details
{
    return TSRunShortcutAlert(TSShortcutConflictsAlert(details));
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
        // A key that cannot be a shortcut overlaps nothing; the list already marks it and says why.
        if ([conflict[@"refused"] boolValue]) continue;
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
    // Back to the list, recording a new shortcut for the first of them.
    [self reflectChangesInEditor:YES]; [self beginRecordingShortcutForItem:node];
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

// File › Save (Command-S) saves the macros, as Save does: the editor is not a document, and
// without this the document behind it would be saved.
- (IBAction)saveDocument:(id)sender
{
	[self savePressed:sender];
}

// A double click on a macro's shortcut records a new one; elsewhere a double click runs a macro
// (Test) and opens or closes a submenu. It does not rename (a second, slower click on the name
// does, as in Finder).
- (void)listDoubleClicked:(id)sender
{
	NSInteger row = [outlineView clickedRow];
	TSMacroTreeNode *item = row >= 0 ? [outlineView itemAtRow:row] : nil;
	if ([item isStandardItem] && [outlineView clickedColumn] == [outlineView columnWithIdentifier:@"Key"]) {
		[self beginRecordingShortcutAtRow:row];
		return;
	}
	if ([item isGroup]) {
		if ([outlineView isItemExpanded:item]) [outlineView collapseItem:item];
		else [outlineView expandItem:item];
	} else if ([item isStandardItem])
		[self doMacroTest:sender];
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

// The nib's key field and Shift/Option/Control boxes are hidden: the shortcut is recorded in
// the list (hideNibShortcutRows). Their actions stay for the nibs' connections.
- (IBAction)keyFieldAction:(id)sender
{
}

- (IBAction)modifiersAction:(id)sender
{
}

// action for outline view
- (IBAction)outlineAction:(id)sender
{
}

// a method called on "Selection changed" notification
- (void)outlineViewSelectionChanged: (NSNotification *)note
{
	[self endShortcutRecordingUnlessSelected];
	[self reflectChangesInEditor: NO];
}

// a method called on "Items changed" (added/removed) notification
- (void)outlineViewItemsChanged: (NSNotification *)note
{
	dataTouched = YES;	// user may have changed the order or dropped an item
    [self endShortcutRecording];
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
				[self.previousItem setKey: self.pendingShortcutKey ?: @""];
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
		self.pendingShortcutKey = [newItem key] ?: @"";
		[testButton setEnabled: YES];
	} else {
		[contentTextView setString: @""];
		[contentTextView setEditable: NO];
		self.pendingShortcutKey = @"";
		[testButton setEnabled: NO];
	}
    if (newItem)
        self.previousItem = newItem;
    else
        self.previousItem = nil;
//	self.previousItem = (newItem)?[newItem retain]:nil;
	[self syncPlaceholderControls];
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
    self.originalShortcutKeys = nil; self.shortcutConflicts = nil; self.shortcutConflictInfo = nil;
    [self releaseWindowControls];
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:TSMacroContentAppearanceContext];
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
		// The path is shown as text, never read as a format.
		NSRunAlertPanel(@"Error", @"%@", nil, nil, nil, [NSString stringWithFormat:
			@"failed to save macros to %@\n%@", filePath, error]);
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
