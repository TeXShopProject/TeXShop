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
 * $Id: TSMacroEditor.h 108 2006-02-10 13:50:25Z fingolfin $
 *
 * Created by Mitsuhiro Shishikura on Fri Dec 20 2002.
 *
 */

#import <Cocoa/Cocoa.h>

#import "TSMacroTreeNode.h"

@class TSSyntaxHighlighter;
@class TSListBottomBar;
@class TSShortcutRecordingCell;

// The line of a separator in the list of macros, `width` points long.
NSImage *TSMacroSeparatorImage(CGFloat width);

@interface TSMacroEditor : NSObject <NSTextViewDelegate, NSMenuDelegate>
{
	IBOutlet id outlineController;
	IBOutlet id outlineView;
	IBOutlet id window;

	IBOutlet NSButton *saveButton;
	IBOutlet NSButton *cancelButton;
	IBOutlet NSButton *testButton;
	IBOutlet NSButton *newItemButton;
	IBOutlet NSButton *submenuButton;
	IBOutlet NSButton *separatorButton;
	IBOutlet NSButton *deleteButton;
	IBOutlet NSButton *duplicateButton;

	IBOutlet NSTextField *nameField;
	IBOutlet NSTextView *contentTextView;
	IBOutlet NSTextField *keyField;
	IBOutlet NSButton *shiftCheckBox;
	IBOutlet NSButton *optionCheckBox;
	IBOutlet NSButton *controlCheckBox;

//	TSMacroTreeNode *previousItem;	// record previously selected item
	BOOL dataTouched;
	BOOL nameTouched;
	BOOL contentTouched;
	BOOL keyTouched;
	// A conflicting shortcut was sent back to editing. Later edits do not ask again;
	// closing the window, Command-S, or a new shortcut does.
	BOOL reviewPending;
	// The backup beside the macro file is taken once each time the editor opens.
	BOOL macrosBackedUp;
	// autosaveMacroEdits is on the stack (a conflict sheet can commit fields again).
	BOOL writingMacros;
}

@property (retain) NSMapTable *originalShortcutKeys;
@property (retain) NSMapTable *shortcutConflicts;
// The same conflicts, so a warning about a menu command Keyboard settings can clear
// can remove that command's shortcut.
@property (retain) NSMapTable *shortcutConflictInfo;
@property (retain) NSTextField *shortcutStatus;
// The warning triangle before the message (hidden without one).
@property (retain) NSImageView *shortcutStatusMark;
// Beside that warning when the menu command can be cleared. Hidden otherwise.
@property (retain) NSButton *removeMenuShortcutButton;
// The sidebar: the list and the bar under it (＋, − and the menu of the other commands).
@property (retain) NSVisualEffectView *sidebar;
@property (retain) TSListBottomBar *listBar;
// Beside the sidebar: the fields, the message and the buttons.
@property (retain) NSView *editorView;
// Return, Enter and Escape for the contents, before the buttons take them (keyForContents:).
@property (retain) id contentsKeyMonitor;
// While the list starts renaming an item (beginRenamingSelectedItem).
@property (getter=isRenaming) BOOL renaming;
// Below the contents: Insert adds a placeholder, the help button lists them.
@property (retain) NSPopUpButton *insertPlaceholderButton;
@property (retain) NSButton *placeholdersButton;
@property (retain) NSPopover *placeholdersPopover;
// The shortcut of the selected macro, as the macros store it (for example @"M+ShiftKey"); it is
// recorded in the list, and the nib's key field and Shift, Option and Control boxes stay hidden.
@property (copy) NSString *pendingShortcutKey;
// While a shortcut is recorded in the list: the item, the field over its shortcut with the place of the
// warning triangle, why the last key pressed was refused, and that key as the field shows it (⌃⌘E, A).
@property (retain) TSMacroTreeNode *recordingItem;
@property (retain) TSShortcutRecordingCell *recordingCell;
@property (copy) NSString *recordingError;
@property (copy) NSString *refusedShortcut;
@property BOOL endingShortcutRecording;
- (void)installSidebar;
- (NSEvent *)keyForContents:(NSEvent *)event;
- (BOOL)beginRenamingSelectedItem;
- (void)cancelPendingListRename;
- (IBAction)renameSelectedMacro:(id)sender;
- (IBAction)saveDocument:(id)sender;
// Writes macros that have changed. Does not close the window.
- (BOOL)autosaveMacroEdits;
- (void)stopKeyMonitor;
- (void)releaseWindowControls;
- (void)useSystemFont;
- (void)hideNibShortcutRows;
- (BOOL)beginRecordingShortcutAtRow:(NSInteger)row;
- (BOOL)beginRecordingShortcutForItem:(TSMacroTreeNode *)item;
- (void)endShortcutRecording;
- (void)finishShortcutRecordingFocusingList:(BOOL)focusList;
- (void)endShortcutRecordingUnlessSelected;
- (void)handleShortcutRecordingEvent:(NSEvent *)event;
- (BOOL)recordShortcutEvent:(NSEvent *)event;
- (NSString *)shortcutConflictForEvent:(NSEvent *)event;
- (IBAction)removeRecordedShortcut:(id)sender;
- (void)listClicked:(id)sender;
- (void)setPendingShortcut:(NSString *)key;
- (void)installPlaceholderControls;
- (void)syncPlaceholderControls;
- (NSView *)makePlaceholderListView;
- (IBAction)showPlaceholders:(id)sender;
- (void)insertPlaceholder:(NSMenuItem *)sender;
- (void)layoutDialogButtons;
- (void)syncListControls;
- (NSString *)shortcutConflictForNode:(TSMacroTreeNode *)node;
- (void)refreshShortcutConflicts;
- (void)layoutShortcutStatusInBand:(NSRect)band;
- (void)updateShortcutStatus;
- (void)showShortcutStatus:(NSString *)message;
// The menu command behind the warning now showing, when Keyboard settings can clear it.
- (NSDictionary *)removableMenuShortcutForStatus:(NSString *)message;
// Cancel is the first button. OK, the second, removes the menu shortcut.
- (NSModalResponse)confirmRemovingShortcut:(NSString *)shown fromMenuItem:(NSString *)path;
- (IBAction)removeConflictingMenuShortcut:(id)sender;
// Colors the contents as the source is colored.
@property (retain) TSSyntaxHighlighter *contentHighlighter;
@property (retain) TSMacroTreeNode *previousItem;	// record previously selected item

+ (id)sharedInstance;

- (IBAction)openMacroEditor: (id)sender;
- (void)openMacroEditorSelectingMacroAtIndexPath:(NSIndexPath *)path name:(NSString *)name key:(NSString *)key;
- (void)loadUI;

- (IBAction)savePressed:(id)sender;
- (IBAction)cancelPressed:(id)sender;
- (IBAction)doMacroTest:(id)sender;

- (IBAction)nameFieldAction:(id)sender;
- (IBAction)textDidChange:(id)sender;	// to receive notification from contentTextView
- (IBAction)keyFieldAction:(id)sender;
- (IBAction)modifiersAction:(id)sender;
- (IBAction)outlineAction:(id)sender;

- (void)outlineViewSelectionChanged: (NSNotification *)note;
- (void)outlineViewItemsChanged: (NSNotification *)note;
- (void)reflectChangesInEditor: (BOOL)forceUpdate;

- (void)saveMacrosSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;

- (BOOL)saveNodes: (id)nodes toFile: (NSString *)filePath;
- (void)saveSelection: (id)sender;
- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void  *)contextInfo;
- (void)readDictionaryToMacroEditor: (id)sender;
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void  *)contextInfo;

@end
