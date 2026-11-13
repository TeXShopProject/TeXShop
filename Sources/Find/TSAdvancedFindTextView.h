// SPDX-License-Identifier: GPL-2.0-or-later
// A small shared piece for every text view that finds with the Advanced Find panel, not only TSTextView. The console and the log are plain NSTextViews, the Experiment source is ScrapTextView, the Experiment
// output a plain NSTextView made in code. Each one routes the find menu to the controller and draws the search
// highlights, which live in the layout manager's background pass.
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindController.h"
#import "TSAdvancedFindHighlights.h"

NS_ASSUME_NONNULL_BEGIN

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
/// For a text view's -validateMenuItem:. NO for a replacing action in a read-only text view (console, log).
- (BOOL)validateFindMenuItem:(NSMenuItem *)item inTextView:(NSTextView *)textView;

/// The text view that the panel and the multiple replacement window act on: the main window's first responder.
@property (class, nonatomic, readonly, nullable) NSTextView *targetTextView;
/// For the tests, which never make a window main: the target instead of the main window's first responder.
@property (class, nonatomic, weak, nullable) NSTextView *testTargetTextView;

@end

/// A plain text view that finds with the Advanced Find panel: in TeXShop, the console (the class in its nib), the log
/// and the Experiment output (made in code). It routes the find menu and draws the highlights; whether it may be
/// edited is its own setting, and the replacing actions follow it.
NS_SWIFT_NAME(AdvancedFindTextView)
@interface TSAdvancedFindTextView : NSTextView
/// nil: the text view's own find (the Apple panel or the find bar). In TeXShop it is the shared controller when the
/// setting is the Advanced Find panel.
@property (nonatomic, weak, nullable) TSAdvancedFindController *findController;
@end

NS_ASSUME_NONNULL_END
