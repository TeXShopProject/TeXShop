// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSKeyboardShortcuts.h"
NSModalResponse TSRunShortcutAlert(NSAlert *alert) {
    id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (NSApp.modalWindow == alert.window && event.keyCode == 53) {
            [NSApp stopModalWithCode:NSAlertFirstButtonReturn];
            return nil;
        }
        return event;
    }];
    @try { return [alert runModal]; }
    @finally { [NSEvent removeMonitor:monitor]; }
}

