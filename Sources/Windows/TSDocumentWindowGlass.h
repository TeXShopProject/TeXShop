// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSDocumentWindowGlass.h
 *
 * On macOS 26 and later, the source window and the window that shows both let
 * their content run under the title bar and the toolbar. The Preview window
 * keeps its pages below the toolbar on every system, so a page does not show
 * through the glass. On macOS 26 and later that toolbar ends in a hard edge
 * with no line, and stays a solid color when a page scrolls, as Preview.app
 * does. Earlier systems leave the separator the nib built, the line and short
 * shadow Preview.app uses there.
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// YES when document windows are built with a full-size content view.
BOOL TSDocumentWindowsUseFullSizeContent(void);

// Gets a document window ready after its toolbar is set. On macOS 26 and later its
// content runs under the title bar and the toolbar, and a drawer at its side starts where
// the rounding of the window's top corner ends, beside the title bar (#67). On earlier
// systems the drawer starts right below the title bar. On every system the drawer's frame
// takes the window's colors.
void TSDocumentWindowPrepare(NSWindow * _Nullable window);

// The Preview window. Its pages stay below the toolbar on every system. On macOS 26 and
// later the toolbar ends in a hard edge with no line, and stays a solid color when a
// page scrolls. Earlier systems leave the nib's separator.
void TSDocumentWindowPrepareSolidToolbar(NSWindow * _Nullable window);

// The source window, the Preview window and the window that shows both. The Preview
// window goes through TSDocumentWindowPrepareSolidToolbar. The other two go through
// TSDocumentWindowPrepare. A missing window is skipped.
void TSDocumentWindowPrepareTrio(NSWindow * _Nullable textWindow, NSWindow * _Nullable previewWindow, NSWindow * _Nullable combinedWindow);

// Places the open drawers of a document window again after the band under its toolbar
// changed height, as when the annotation toolbar is shown or hidden; the window does this
// itself when it goes into or out of full screen. A drawer never starts above that band
// where the band is lower than the rounding of the window's corner, as in full screen.
void TSDocumentWindowPlaceDrawers(NSWindow * _Nullable window);

// The height of the band at the top of a view that lies under the title bar and the
// toolbar, or 0 in a window whose content does not run under them.
CGFloat TSDocumentWindowHiddenTop(NSView *view);

// YES when a point of a window, in the window's coordinates, lies in the band of its
// content under the title bar and the toolbar. A click or a pointer there belongs to
// them, not to the view under them. NO in a window whose content does not run under them.
BOOL TSDocumentWindowPointIsUnderToolbar(NSWindow * _Nullable window, NSPoint point);

// The part of a rectangle of a view, in the view's coordinates, that does not lie under
// the title bar and the toolbar. The rectangle itself in a window whose content does
// not run under them, and for a view that is in no window.
NSRect TSDocumentWindowRectBelowToolbar(NSView * _Nullable view, NSRect rect);

// Puts the divider of a split view with two parts so that the parts share the area
// that can be seen in the ratio first : second. The band under the toolbar is not
// counted.
void TSDocumentWindowSplitInShares(NSSplitView *splitView, CGFloat first, CGFloat second);

// The same, with two parts of equal size.
void TSDocumentWindowSplitEvenly(NSSplitView *splitView);

NS_ASSUME_NONNULL_END
