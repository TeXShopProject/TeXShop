// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindController.h"

NS_ASSUME_NONNULL_BEGIN

/// The floating Advanced Find panel. Built in code, without a nib.
NS_SWIFT_NAME(AdvancedFindPanelController)
@interface TSAdvancedFindPanelController : NSWindowController

/// The application's panel, on TSAdvancedFindController.sharedController; made on first use.
@property (class, nonatomic, readonly) TSAdvancedFindPanelController *sharedPanelController;
/// Whether the shared panel has been made, without making it.
@property (class, nonatomic, readonly) BOOL hasSharedPanelController;
@property (nonatomic, readonly) TSAdvancedFindController *findController;

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/// Shows the panel with the find field selected, or the replacement field (Find and Replace…).
- (void)showPanelSelectingReplaceField:(BOOL)replacing;
- (void)showPanel;
/// The buttons under the options: Find All (▾ Highlight All, Select All, Remove Highlights), Replace All,
/// Replace & Find (▾ Replace), Previous / Next.
@property (nonatomic, readonly) NSArray<NSControl *> *buttons;
/// "Multiple Replace…" right of Replace All: opens the Multiple Replace window, as Edit Multiple Replace… does.
/// Always enabled; it acts on no text.
@property (nonatomic, readonly) NSButton *multipleReplaceButton;

@end

/// For the tests and images; not used by the application itself.
@interface TSAdvancedFindPanelController (Testing)
@property (nonatomic, readonly) NSTextView *findField;
@property (nonatomic, readonly) NSTextView *replaceField;
@property (nonatomic, readonly) NSTextField *statusField;
/// The check boxes of the options row: regular expression, ignore case, in selection.
@property (nonatomic, readonly) NSArray<NSButton *> *optionBoxes;
/// Loads the strings and options from the settings without showing the panel.
- (void)reloadFromSettings;
/// The menu of recent strings of a field (0: find, 1: replace).
- (NSMenu *)historyMenuForField:(NSInteger)tag;
/// The content of the "More Options" popover, made for the current settings.
- (NSView *)makeOptionsView;
/// Brings the buttons up to date with the target text view now (as after each event).
- (void)updateButtons;
@end

NS_ASSUME_NONNULL_END
