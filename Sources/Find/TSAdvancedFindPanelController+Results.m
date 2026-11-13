// SPDX-License-Identifier: GPL-2.0-or-later
// The list of all matches inside the panel, as in CotEditor: "Find All" makes the panel taller, with an animation,
// and the list takes the new room; closing the list gives the room back.
//
// Only the window's frame is animated, by AppKit's own window resize animation, which lays the window out at each
// step. Everything above the list keeps its place and size: the window's top edge stays where it is, and the fields
// keep their height. The list takes whatever height is left, from nothing to its full height or back, its content
// fixed at the top and cut off at the bottom. It is shown before the window grows and hidden only after the window
// has shrunk, so the fields never take its room for a moment.
//
// (The first version animated the window and a height constraint of the list with implicit animations: every view's
// frame then trailed behind the window's, and the fields moved up and down while the window changed.)
#import "TSAdvancedFindPanelController+Private.h"

@implementation TSAdvancedFindPanelController (Results)

- (void)showResults:(TSAdvancedFindResults *)results textView:(NSTextView *)textView
{
    [self.resultsView setResults:results textView:textView];
    if (self.resultsView.hidden)
        [self setResultsShown:YES];
    if (self.showsResults && !self.window.isVisible)
        [self showWindow:nil];
}

/// The panel's saved frame is that without the list: closed at once when the application quits with it open.
- (void)applicationWillTerminate:(NSNotification *)notification
{
    if (self.resultsView.hidden)
        return;
    [self.resultsView clear];
    CGFloat height = [self prepareResultsTransition:NO];
    [self setWindowHeight:height animate:NO];
    [self endResultsTransition:NO];
    NSWindowFrameAutosaveName name = self.window.frameAutosaveName;
    if (name.length > 0)
        [self.window saveFrameUsingName:(NSWindowFrameAutosaveName _Nonnull)name];
}

- (void)hideResults
{
    [self.resultsView clear];
    if (!self.resultsView.hidden)
        [self setResultsShown:NO];
}

/// Readies the panel to open or close the list: the list is shown, as high as it is now, and the fields keep their
/// height. Returns the window's height at the end.
- (CGFloat)prepareResultsTransition:(BOOL)shown
{
    NSWindow *window = self.window;
    NSView *content = window.contentView;
    [content layoutSubtreeIfNeeded];
    if (!self.fieldHeightWhileListing) {
        self.fieldHeightWhileListing = [self.findBox.heightAnchor constraintEqualToConstant:NSHeight(self.findBox.frame)];
        self.fieldHeightWhileListing.priority = NSLayoutPriorityDefaultHigh + 10;
        self.fieldHeightWhileListing.active = YES;
    }
    CGFloat listHeight = self.resultsView.hidden ? 0 : NSHeight(self.resultsView.frame);
    if (!shown)
        self.resultsHeight = MAX(listHeight, 160);
    NSSize minimum = window.contentMinSize;
    minimum.height = 250; // not in the way of the animation
    window.contentMinSize = minimum;
    self.resultsView.hidden = NO; // hidden only once closed (-endResultsTransition:)
    [content layoutSubtreeIfNeeded];
    return NSHeight(window.frame) + (shown ? self.resultsHeight : 0) - listHeight;
}

/// One step of the animation, or the whole change at once: the window `height` high, its top edge where it is.
- (void)setWindowHeight:(CGFloat)height animate:(BOOL)animate
{
    NSWindow *window = self.window;
    NSRect frame = window.frame;
    frame.origin.y = NSMaxY(frame) - height;
    frame.size.height = height;
    [window setFrame:frame display:window.isVisible animate:animate];
    [window.contentView layoutSubtreeIfNeeded];
}

- (void)endResultsTransition:(BOOL)shown
{
    if (!shown) {
        self.resultsView.hidden = YES;
        self.fieldHeightWhileListing.active = NO;
        self.fieldHeightWhileListing = nil;
    }
    // While the list is shown, the window cannot get so small that the list is cut off: everything above it keeps
    // its height, and the list needs its header and a few rows.
    [self.window.contentView layoutSubtreeIfNeeded];
    NSSize minimum = self.window.contentMinSize;
    CGFloat contentHeight = NSHeight(self.window.contentView.frame);
    minimum.height = shown ? MAX(250, contentHeight - NSHeight(self.resultsView.frame) + self.resultsView.minimumHeight) : 250;
    self.window.contentMinSize = minimum;
}

/// The window grows or shrinks at its bottom edge by the height of the list. The animation runs to its end before
/// this returns (-[NSWindow setFrame:display:animate:]).
- (void)setResultsShown:(BOOL)shown
{
    CGFloat height = [self prepareResultsTransition:shown];
    [self setWindowHeight:height animate:self.window.isVisible];
    [self endResultsTransition:shown];
}

@end
