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
@class TSMacroShortcutField;

@interface TSMacroEditor : NSObject <NSTextViewDelegate>
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
}

@property (retain) NSMapTable *originalShortcutKeys;
@property (retain) NSMapTable *shortcutConflicts;
@property (retain) NSTextField *shortcutStatus;
// The list and the bar under it (＋, − and the menu of the other commands), in one frame.
@property (retain) NSBox *listBox;
@property (retain) TSListBottomBar *listBar;
@property (retain) NSTextField *placeholderNote;
// The shortcut of the selected macro, set by pressing it; the nib's key field and
// Shift, Option and Control boxes stay hidden.
@property (retain) NSTextField *shortcutLabel;
@property (retain) TSMacroShortcutField *shortcutField;
// The shortcut being edited, as the macros store it (for example @"M+ShiftKey").
@property (copy) NSString *pendingShortcutKey;
- (void)installListControls;
- (void)installShortcutField;
- (void)syncShortcutField;
- (BOOL)recordShortcutEvent:(NSEvent *)event;
- (void)setPendingShortcut:(NSString *)key;
- (void)installPlaceholderNote;
- (void)layoutDialogButtons;
- (void)syncListControls;
- (NSString *)shortcutConflictForNode:(TSMacroTreeNode *)node;
- (void)refreshShortcutConflicts;
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
