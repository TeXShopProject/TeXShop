// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// The actions of the panel. The first values are those of NSFindPanelAction and NSTextFinderAction, so the tags of
/// the Find menu (Find… 1, Find Next 2, Find Previous 3, Use Selection for Find 7, Find and Replace… 12) can be
/// passed on as they are.
typedef NS_ENUM(NSInteger, TSAdvancedFindAction) {
    TSAdvancedFindActionShowFindPanel = NSFindPanelActionShowFindPanel,
    TSAdvancedFindActionNext = NSFindPanelActionNext,
    TSAdvancedFindActionPrevious = NSFindPanelActionPrevious,
    TSAdvancedFindActionReplaceAll = NSFindPanelActionReplaceAll,
    TSAdvancedFindActionReplace = NSFindPanelActionReplace,
    TSAdvancedFindActionReplaceAndFind = NSFindPanelActionReplaceAndFind,
    TSAdvancedFindActionSetFindString = NSFindPanelActionSetFindString,
    TSAdvancedFindActionReplaceAllInSelection = NSFindPanelActionReplaceAllInSelection,
    TSAdvancedFindActionSelectAll = NSFindPanelActionSelectAll,
    TSAdvancedFindActionSelectAllInSelection = NSFindPanelActionSelectAllInSelection,
    TSAdvancedFindActionHidePanel = NSTextFinderActionHideFindInterface,
    /// "Find and Replace…": the panel, with the replacement field selected.
    TSAdvancedFindActionShowReplacePanel = NSTextFinderActionShowReplaceInterface,
    TSAdvancedFindActionHideReplacePanel = NSTextFinderActionHideReplaceInterface,
    TSAdvancedFindActionSetReplaceString = 101,
    TSAdvancedFindActionHighlight = 102,
    TSAdvancedFindActionUnhighlight = 103,
    TSAdvancedFindActionFindSelectedText = 104,
    TSAdvancedFindActionJumpToSelection = 105,
} NS_SWIFT_NAME(AdvancedFindAction);

/// Carries out find and replace in a text view: selection, undo, highlights and status messages.
/// The computation itself is done by TSRegexTextFind.
NS_SWIFT_NAME(AdvancedFindController)
@interface TSAdvancedFindController : NSObject

/// The controller of the application's panel: the standard defaults and the find pasteboard.
@property (class, nonatomic, readonly) TSAdvancedFindController *sharedController;
@property (nonatomic, readonly) TSAdvancedFindSettings *settings;
/// Receives a short report after each action, such as "3 of 12" or an error.
@property (nonatomic, copy, nullable) void (^statusHandler)(NSString *message, BOOL isError);
/// Called for the actions that show the panel (with YES for "Find and Replace…") and when an error has to be shown.
@property (nonatomic, copy, nullable) void (^showPanelHandler)(BOOL replacing);
/// Called for TSAdvancedFindActionHidePanel.
@property (nonatomic, copy, nullable) void (^hidePanelHandler)(void);
/// Signals a failure to the user; NSBeep unless replaced (tests stay silent).
@property (nonatomic, copy) void (^beepHandler)(void);
/// The line ending of the text view's document, put into the find string and the replaced text; nil keeps them.
@property (nonatomic, copy, nullable) NSString *_Nullable (^lineEndingHandler)(NSTextView *textView);
/// Called after the find or replacement string was taken from a selection.
@property (nonatomic, copy, nullable) void (^stringsChangedHandler)(void);

- (instancetype)initWithSettings:(TSAdvancedFindSettings *)settings NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (BOOL)validateAction:(TSAdvancedFindAction)action forTextView:(NSTextView *)textView;
/// Returns NO and beeps when nothing was found or the action failed.
- (BOOL)performAction:(TSAdvancedFindAction)action inTextView:(NSTextView *)textView;
/// Finds the next match from the start of the selection, keeping a match that is already selected.
- (BOOL)incrementalSearchInTextView:(NSTextView *)textView;

@end

FOUNDATION_EXPORT NSString *TSAdvancedFindLocalized(NSString *key, NSString *english);
/// The find string of "Find Selected Text": one that finds `text` as it is with `options`.
FOUNDATION_EXPORT NSString *TSAdvancedFindPatternFindingText(NSString *text, TSRegexFindOptions options) NS_SWIFT_NAME(AdvancedFindPatternFindingText(_:options:));

NS_ASSUME_NONNULL_END
