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

// Extends the window's content under the title bar and the toolbar. A drawer at the
// side of the window then starts below the toolbar.
void TSDocumentWindowUseFullSizeContent(NSWindow * _Nullable window);

// Puts the divider of a split view with two parts in the middle of the area that can
// be seen. In a window whose content runs under the toolbar, the band under the
// toolbar is not counted. Other windows keep the divider where AppKit put it.
void TSDocumentWindowSplitEvenly(NSSplitView *splitView);

NS_ASSUME_NONNULL_END
