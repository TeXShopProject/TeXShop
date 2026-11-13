// SPDX-License-Identifier: GPL-2.0-or-later
// Shared by the panel's files; not for other classes.
#import "TSAdvancedFindPanelController.h"
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindInputBox.h"
#import "TSAdvancedFindCheatSheet.h"

NS_ASSUME_NONNULL_BEGIN

#define TSLocalized TSAdvancedFindLocalized

/// A multi-line text field: Return finds, Tab moves on; Option-Return and Option-Tab insert the character.
@interface TSAdvancedFindFieldView : NSTextView
@property (nonatomic, weak, nullable) TSAdvancedFindInputBox *box;
@end

@interface TSAdvancedFindPanelController () <NSTextViewDelegate, NSPopoverDelegate>
@property (nonatomic, strong) TSAdvancedFindFieldView *findFieldView;
@property (nonatomic, strong) TSAdvancedFindFieldView *replaceFieldView;
@property (nonatomic, strong) TSAdvancedFindInputBox *findBox;
@property (nonatomic, strong) TSAdvancedFindInputBox *replaceBox;
@property (nonatomic, strong) NSButton *regexBox;
/// The "?" right after "Regular expression", and the cheat sheet it opens (also when dragged off as a window).
@property (nonatomic, strong) NSButton *cheatSheetButton;
@property (nonatomic, strong, nullable) NSPopover *cheatSheetPopover;
@property (nonatomic, strong) NSButton *ignoreCaseBox;
/// In the "More Options" popover, while it is open.
@property (nonatomic, strong, nullable) NSButton *wrapBox;
@property (nonatomic, strong) NSButton *inSelectionBox;
@property (nonatomic, strong) NSTextField *status;
@property (nonatomic, strong, nullable) NSPopover *optionsPopover;
@property (nonatomic, copy) NSArray<NSControl *> *buttons;
/// The option check boxes of the open popover, enabled or not by the regular expression setting.
@property (nonatomic, strong, nullable) TSAdvancedFindOptionsForm *optionsForm;
@end

@interface TSAdvancedFindPanelController (PrivateMethods)
- (NSButton *)checkBox:(NSString *)key english:(NSString *)english;
- (NSButton *)button:(NSString *)key english:(NSString *)english action:(SEL)action;
- (void)optionChanged:(NSControl *)sender;
- (void)clearHistory:(NSMenuItem *)sender;
- (void)showHistory:(NSButton *)sender;
- (void)showOptions:(NSButton *)sender;
/// The options popover's content, sized as the popover shows it.
- (NSViewController *)makeOptionsViewController;
- (void)updateModeControls;
- (void)optionsDidChange;
- (void)loadStrings;
/// The cheat sheet's content, loaded, for the replacement syntax of the settings.
- (TSAdvancedFindCheatSheet *)makeCheatSheet;
- (void)showCheatSheet:(nullable id)sender;
/// An open cheat sheet follows the replacement syntax of the settings.
- (void)updateCheatSheet;
/// The text view of the main window, which the panel acts on.
- (nullable NSTextView *)targetTextView;
/// The buttons' actions, on the main window's text view.
- (IBAction)advancedFindNext:(nullable id)sender;
- (IBAction)advancedReplace:(nullable id)sender;
- (IBAction)advancedReplaceAll:(nullable id)sender;
- (IBAction)advancedReplaceAndFind:(nullable id)sender;
- (IBAction)advancedSelectAll:(nullable id)sender;
- (IBAction)advancedHighlight:(nullable id)sender;
- (IBAction)advancedUnhighlight:(nullable id)sender;
- (IBAction)previousOrNext:(NSSegmentedControl *)sender;
/// The Find menu while the panel is key (from its fields): the actions go to the main window's text view, as the
/// buttons' do; Find… and Find and Replace… select the panel's own fields.
- (void)performFindMenuAction:(nullable id)sender;
- (BOOL)validateFindMenuItem:(NSMenuItem *)item;
@end

NS_ASSUME_NONNULL_END
