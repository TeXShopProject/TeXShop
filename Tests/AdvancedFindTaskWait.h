// SPDX-License-Identifier: GPL-2.0-or-later
// For the tests of the Advanced Find panel: Replace All, Find All and Multiple Replace run as background tasks, which
// end on the main thread; these wait for them by running the run loop.
#import "TSAdvancedFindController.h"

/// Runs the run loop until the controller's task has ended, or `seconds` have passed. YES when it ended.
static inline BOOL TSTestWaitForTask(TSAdvancedFindController *controller, NSTimeInterval seconds)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (controller.runningTask && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return controller.runningTask == nil;
}

/// Performs `action` and waits for the task it may have started. Returns what -performAction:inTextView: returned.
static inline BOOL TSTestPerform(TSAdvancedFindController *controller, TSAdvancedFindAction action, NSTextView *textView)
{
    BOOL started = [controller performAction:action inTextView:textView];
    TSTestWaitForTask(controller, 60);
    return started;
}
