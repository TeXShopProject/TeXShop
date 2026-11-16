// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSDocumentWindowGlass.h
 *
 * On macOS 26 and later, the source window, the Preview window and the window
 * that shows both let their content run under the title bar and the toolbar.
 * The toolbar's glass then shows the text or the pages scrolling beneath it.
 * Earlier systems keep the windows as they were.
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// YES when document windows are built with a full-size content view.
BOOL TSDocumentWindowsUseFullSizeContent(void);

// Gets a document window ready after its toolbar is set. On macOS 26 and later its
// content runs under the title bar and the toolbar, and a drawer at its side starts
// below the toolbar. On every system the drawer's frame takes the window's colors.
void TSDocumentWindowPrepare(NSWindow * _Nullable window);

// The height of the band at the top of a view that lies under the title bar and the
// toolbar, or 0 in a window whose content does not run under them.
CGFloat TSDocumentWindowHiddenTop(NSView *view);

// YES when a point of a window, in the window's coordinates, lies in the band of its
// content under the title bar and the toolbar. A click or a pointer there belongs to
// them, not to the view under them. NO in a window whose content does not run under them.
BOOL TSDocumentWindowPointIsUnderToolbar(NSWindow * _Nullable window, NSPoint point);

// The part of a rectangle of a view, in the view's coordinates, that does not lie under
// the title bar and the toolbar. The rectangle itself in a window whose content does
// not run under them.
NSRect TSDocumentWindowRectBelowToolbar(NSView *view, NSRect rect);

// Puts the divider of a split view with two parts so that the parts share the area
// that can be seen in the ratio first : second. The band under the toolbar is not
// counted.
void TSDocumentWindowSplitInShares(NSSplitView *splitView, CGFloat first, CGFloat second);

// The same, with two parts of equal size.
void TSDocumentWindowSplitEvenly(NSSplitView *splitView);

NS_ASSUME_NONNULL_END
