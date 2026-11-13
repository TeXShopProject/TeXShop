// SPDX-License-Identifier: GPL-2.0-or-later
// A small shared piece for every text view that finds with the Advanced Find panel, not only TSTextView. The console and the log are plain NSTextViews, the Experiment source is ScrapTextView, the Experiment
// output a plain NSTextView made in code. Each one routes the find menu to the controller and draws the search
// highlights, which live in the layout manager's background pass.
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindController.h"
#import "TSAdvancedFindHighlights.h"

NS_ASSUME_NONNULL_BEGIN

/// The shared controller when the find method (FindMethod) is the Advanced Find panel, otherwise nil: the text view
/// then finds as it always has (the Apple panel or the find bar). It is read each time, so the setting takes effect
/// without a restart.
FOUNDATION_EXPORT TSAdvancedFindController *_Nullable TSAdvancedFindControllerForFindMethod(void);

/// Adopted by the text views whose find menu goes to the Advanced Find panel (TSTextView, TSAdvancedFindTextView):
/// the panel acts on the last of them that had the focus.
NS_SWIFT_NAME(AdvancedFindTarget)
@protocol TSAdvancedFindTarget <NSObject>
@end

/// A layout manager that only adds the search highlights over the background, for text views whose layout manager is
/// not TeXShop's own.
NS_SWIFT_NAME(AdvancedFindLayoutManager)
@interface TSAdvancedFindLayoutManager : NSLayoutManager <TSAdvancedFindHighlightDrawing>
/// Gives `textView` this layout manager, keeping its settings, unless its layout manager draws the highlights already.
+ (void)installInTextView:(NSTextView *)textView;
@end

@interface TSAdvancedFindController (TextViews)

/// For a text view's -performFindPanelAction: and -performTextFinderAction:: the action of the sender's tag.
- (void)performFindPanelAction:(id)sender inTextView:(NSTextView *)textView;
/// For a text view's -validateMenuItem:. NO for a replacing action in a read-only text view (the console, the
/// Experiment output).
- (BOOL)validateFindMenuItem:(NSMenuItem *)item inTextView:(NSTextView *)textView;

/// The text view that the panel and its other windows act on: the focused find target of the key window; else the one
/// that had the focus last, while its window is shown (the Experiment source and output are panels, which never become
/// main); else the main window's first responder.
@property (class, nonatomic, readonly, nullable) NSTextView *targetTextView;
/// For the tests, which never make a window main: the target instead of the main window's first responder.
@property (class, nonatomic, weak, nullable) NSTextView *testTargetTextView;
/// Starts following which find target has the focus. Called when the Find menu or the panel is first used.
+ (void)trackTargetTextViews;
/// For the tests: what a window that became or stopped being key leaves as the last target.
+ (void)noteKeyWindowChange:(NSWindow *)window;

@end

/// A plain text view that finds with the Advanced Find panel: in TeXShop, the console and the log (the class in the
/// nib), the Experiment output (made in code) and, as its superclass, the Experiment source. It routes the find menu
/// and draws the highlights; whether it may be edited is its own setting, and the replacing actions follow it.
NS_SWIFT_NAME(AdvancedFindTextView)
@interface TSAdvancedFindTextView : NSTextView <TSAdvancedFindTarget>
/// TSAdvancedFindControllerForFindMethod(): nil unless the find method is the Advanced Find panel.
@property (nonatomic, readonly, nullable) TSAdvancedFindController *findController;
@end

NS_ASSUME_NONNULL_END
