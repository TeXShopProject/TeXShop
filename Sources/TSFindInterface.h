// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
// Reconcile all flags, including turning off a previously enabled find bar.
static inline void TSConfigureFindInterface(NSTextView *view, NSInteger method, BOOL incremental) {
    view.usesFindBar = method == 1;
    view.usesFindPanel = method != 1;
    view.incrementalSearchingEnabled = method == 1 && incremental;
}
