// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// Space between push buttons and from a dialog's edges, as in the Human
// Interface Guidelines.
FOUNDATION_EXPORT const CGFloat TSDialogButtonSpacing, TSDialogMargin;
// Lays out one row of push buttons at their current height and baseline:
// trailing, from right to left, starts with the default button followed by
// Cancel, and those buttons share one width; leading holds actions that do not
// close the window, from left to right. Buttons are sized to their titles, and
// the window grows to fit the row if it has to.
FOUNDATION_EXPORT void TSLayoutDialogButtons(NSView *host, NSArray<NSButton *> *trailing, NSArray<NSButton *> *leading);
// Lays out a row of action buttons against the trailing edge, from right to
// left, each sized to its own title; the window grows to fit if it has to.
FOUNDATION_EXPORT void TSLayoutTrailingButtons(NSView *host, NSArray<NSButton *> *rightToLeft);
// Finds the bottom row of push buttons in a window loaded from an older nib
// and lays it out as above. The default (Return) button and Cancel (Escape)
// form the trailing group; the other buttons in the row lead.
FOUNDATION_EXPORT void TSLayoutDialogButtonRow(NSWindow *window);
// Keeps the bottom row of action buttons of a panel such as Find apart, in
// their order, against the trailing edge.
FOUNDATION_EXPORT void TSLayoutBottomActionRow(NSWindow *window);
NS_ASSUME_NONNULL_END
