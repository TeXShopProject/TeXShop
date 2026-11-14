// SPDX-License-Identifier: GPL-2.0-or-later
// Shared by the panel's files; not for other classes.
#import "TSAdvancedFindPanelController.h"
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindInputBox.h"
#import "TSAdvancedFindResultsView.h"
#import "TSAdvancedFindCheatSheet.h"
#import "TSSyntaxHighlighter.h"

NS_ASSUME_NONNULL_BEGIN

#define TSLocalized TSAdvancedFindLocalized

/// A multi-line text field: Return finds, Tab moves on; Option-Return and Option-Tab insert the character.
/// With `bracketScanner` (the find field with "Regular expression" on), as in CotEditor: when the caret comes right
/// after a bracket, its partner is shown with the find indicator; a double-click on a bracket selects both and what
/// is between them. Only the scanner's pairs count: not \( nor a bracket inside a class (+Coloring).
@interface TSAdvancedFindFieldView : NSTextView
@property (nonatomic, weak, nullable) TSAdvancedFindInputBox *box;
@property (nonatomic, strong, nullable) id<TSSyntaxScanner> bracketScanner;
/// Shows a range: the find indicator when nil (the tests record it instead).
@property (nonatomic, copy, nullable) void (^bracketIndicator)(NSTextView *view, NSRange range);
@end

@interface TSAdvancedFindFieldView (Brackets)
/// The pair whose opening or closing bracket is at `index`, or {NSNotFound, 0}.
- (NSRange)bracketPairAtIndex:(NSUInteger)index;
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
/// The coloring of the find and replace fields (+Coloring).
@property (nonatomic, strong) TSSyntaxHighlighter *findHighlighter;
@property (nonatomic, strong) TSSyntaxHighlighter *replaceHighlighter;
/// The list of all matches, under the options while shown (+Results).
@property (nonatomic, strong) TSAdvancedFindResultsView *resultsView;
/// The height of the list when it was last shown, for the next time.
@property (nonatomic) CGFloat resultsHeight;
/// Keeps the fields' height while the list is shown, so the list takes the room the window grows by.
@property (nonatomic, strong, nullable) NSLayoutConstraint *fieldHeightWhileListing;
/// Whether a Find All brings the panel to the front with its list (YES); the tests turn it off, to show nothing.
@property (nonatomic) BOOL showsResults;
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
/// Colors the fields as the engine reads them (+Coloring): starts following their edits.
- (void)setUpFieldColoring;
/// The scanners for the current options, pattern and replacement syntax; colors the fields again when they changed.
- (void)updateFieldScanners;
/// The marks of both fields, the find field's first: errors and what OgreKit reads otherwise.
- (NSArray<TSSyntaxDiagnostic *> *)fieldDiagnostics;
/// The list of all matches (+Results): shown in the panel, which grows downward for it, or closed.
- (void)showResults:(TSAdvancedFindResults *)results textView:(NSTextView *)textView;
- (void)hideResults;
/// The steps of opening and closing the list, run one by one by the tests (+Results).
- (CGFloat)prepareResultsTransition:(BOOL)shown;
- (void)setWindowHeight:(CGFloat)height animate:(BOOL)animate;
- (void)endResultsTransition:(BOOL)shown;
/// Closes the list first, so the panel's saved frame is that without it.
- (void)applicationWillTerminate:(NSNotification *)notification;
/// The cheat sheet's content, loaded, for the replacement syntax of the settings.
- (TSAdvancedFindCheatSheet *)makeCheatSheet;
- (void)showCheatSheet:(nullable id)sender;
/// An open cheat sheet follows the replacement syntax of the settings.
- (void)updateCheatSheet;
/// The text view of the main window, which the panel acts on.
- (nullable NSTextView *)targetTextView;
/// The buttons' actions, on the main window's text view.
- (IBAction)advancedFindNext:(nullable id)sender;
- (IBAction)advancedFindAll:(nullable id)sender;
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
