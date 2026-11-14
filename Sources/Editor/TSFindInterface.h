// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
// FindMethod: 0 Apple find panel, 1 Apple find bar, 2 OgreKit (legacy), 3 Advanced Find panel. The values stay as they
// were, so the settings list the Advanced Find panel before OgreKit although its value is larger.
static const NSInteger TSFindMethodApplePanel = 0;
static const NSInteger TSFindMethodFindBar = 1;
static const NSInteger TSFindMethodOgreKit = 2;
static const NSInteger TSFindMethodAdvancedPanel = 3;
// Reconcile all flags, including turning off a previously enabled find bar.
// The Advanced Find panel takes the find actions before NSTextView (TSTextView); its views keep the Apple panel's flags.
static inline void TSConfigureFindInterface(NSTextView *view, NSInteger method, BOOL incremental) {
    if (method != TSFindMethodFindBar) view.enclosingScrollView.findBarVisible = NO;
    view.usesFindBar = method == TSFindMethodFindBar;
    view.usesFindPanel = method != TSFindMethodFindBar;
    view.incrementalSearchingEnabled = method == TSFindMethodFindBar && incremental;
}
