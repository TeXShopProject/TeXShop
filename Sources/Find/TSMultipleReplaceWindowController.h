// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindController.h"
#import "TSMultipleReplaceLibrary.h"
#import "TSMultipleReplaceRuleTable.h"

NS_ASSUME_NONNULL_BEGIN

/// The multiple replacement window: the saved sets on the left, the rules of the chosen set on the right, and the
/// set's options, "in selection", highlight and replace all below. A panel, so the document stays the main window
/// that it acts on. Every change is saved at once, as in CotEditor.
NS_SWIFT_NAME(MultipleReplaceWindowController)
@interface TSMultipleReplaceWindowController : NSWindowController

@property (nonatomic, readonly) TSAdvancedFindController *findController;
@property (nonatomic, readonly) TSMultipleReplaceLibrary *library;
@property (nonatomic, readonly) TSMultipleReplaceRuleTable *ruleTable;
@property (nonatomic, readonly, copy, nullable) NSString *selectedSetName;
@property (nonatomic, readonly) NSTextField *statusField;
@property (nonatomic) BOOL inSelection;

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)reloadSets;
- (void)selectSetNamed:(NSString *)name;
/// The options view of the selected set (the popover's content).
- (NSView *)makeOptionsView;

/// Starts applying the shown set to the text view (the main window's when nil), as a background task; when it ends,
/// shows the counts and the status. NO when it cannot start (no set or target, a read-only target, another task).
- (BOOL)replaceAllInTextView:(nullable NSTextView *)textView;
- (BOOL)highlightInTextView:(nullable NSTextView *)textView;

- (IBAction)addSet:(nullable id)sender;
- (IBAction)duplicateSet:(nullable id)sender;
- (IBAction)removeSet:(nullable id)sender;
/// Brings Highlight and Replace All up to date with the target text view now (as after each event).
- (void)updateButtons;

@end

NS_ASSUME_NONNULL_END
