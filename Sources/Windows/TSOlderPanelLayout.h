// SPDX-License-Identifier: GPL-2.0-or-later
// Brings panels loaded from older nibs in line with the current controls of
// macOS after loading, without editing the nibs of each localization.
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// The Log File window: the columns of check boxes and Refresh apart from each
// other and from the window's edges, and the log against the window's edges.
FOUNDATION_EXPORT void TSLayoutLogWindow(NSWindow *window);
// A panel that only tells something and has OK, shown as an alert with its
// text and the title of its button.
FOUNDATION_EXPORT NSAlert *TSAlertForNoticePanel(NSWindow *panel);
// A label before a pop-up button, such as Encoding: in an accessory view, at
// the size of the pop-up's text and centered on it.
FOUNDATION_EXPORT void TSFitLabelsBeforePopUps(NSView *view);
// Tables drawn without the vertical lines between their columns, as lists in
// current macOS; the column headers still separate the columns.
FOUNDATION_EXPORT void TSRemoveVerticalGridLines(NSView *root);
NS_ASSUME_NONNULL_END
