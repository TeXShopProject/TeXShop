#!/usr/bin/env python3
"""Exercise actual Experiment routing methods using Foundation-only window stubs.

No NSApplication, windows, user defaults, or real jobs are created. Optional
--mutation checks prove that the assertions reject specific routing regressions.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from source_tree import source_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument("--mutation", choices=["visible-route", "late-route", "abort-route", "self-target"])
args = parser.parse_args()


def method(filename, signature):
    source = (source_file(args.root, filename)).read_text(errors="replace")
    start = source.index(signature)
    # These methods all end with a closing brace at the start of a line.
    end = source.index("\n}\n", start) + 3
    return source[start:end]


route = method("TSDocument-Scrap.m", "- (BOOL)experimentHasKeyWindow")
typeset = method("TSDocument-Jobs.m", "- (void) doTypeset: sender;")
abort = method("TSDocument-Jobs.m", "- (void)abort:(id)sender")
toggle = method("TSExperimentConsoleController.m", "- (void)toggleFromWindow:")

if args.mutation == "visible-route":
    route = route.replace(".isKeyWindow", ".isVisible")
elif args.mutation == "late-route":
    guard = re.search(r"    if \(\[self experimentHasKeyWindow\]\) \{.*?\n    \}", typeset, re.S)
    assert guard, "Experiment guard not found"
    block = guard.group(0)
    typeset = typeset.replace(block, "", 1)
    marker = "[self callSaveAnnotations];"
    assert marker in typeset
    typeset = typeset.replace(marker, marker + "\n" + block, 1)
elif args.mutation == "abort-route":
    abort = abort.replace("if ([self experimentHasKeyWindow])", "if (NO)", 1)
elif args.mutation == "self-target":
    assert "target != self.window &&" in toggle
    toggle = toggle.replace("target != self.window &&", "", 1)

program = r'''
#import <Foundation/Foundation.h>
@interface Sender : NSObject
- (NSInteger)tag;
@end
@class Window;
static Window *routingKeyWindow;
@interface Window : NSObject
@property BOOL isVisible, isMiniaturized;
@property (copy) NSString *name;
- (BOOL)isKeyWindow;
- (void)makeKeyAndOrderFront:(id)sender;
@end
@implementation Window
- (BOOL)isKeyWindow { return routingKeyWindow == self; }
- (void)makeKeyAndOrderFront:(id)sender {
    routingKeyWindow = self; self.isVisible = YES; self.isMiniaturized = NO;
}
@end
#define NSWindow Window
@interface Event : NSObject
+ (NSUInteger)modifierFlags;
- (NSUInteger)modifierFlags;
@end
@implementation Event
+ (NSUInteger)modifierFlags { return 0; }
- (NSUInteger)modifierFlags { return 0; }
@end
#define NSEvent Event
enum { NSEventModifierFlagDeviceIndependentFlagsMask = 0xffff0000,
       NSAlternateKeyMask = 1 << 19, NSEventModifierFlagOption = 1 << 19 };
@interface Application : NSObject
+ (instancetype)sharedApplication;
- (Window *)keyWindow;
- (Event *)currentEvent;
@end
@implementation Application
+ (instancetype)sharedApplication { static Application *app; if (!app) app = [Application new]; return app; }
- (Window *)keyWindow { return routingKeyWindow; }
- (Event *)currentEvent { return [Event new]; }
@end
#define NSApplication Application
#define NSApp Application.sharedApplication
@interface Defaults : NSObject
+ (instancetype)shared;
- (NSInteger)integerForKey:(NSString *)key;
@end
@implementation Defaults
+ (instancetype)shared { static Defaults *d; if (!d) d = [Defaults new]; return d; }
- (NSInteger)integerForKey:(NSString *)key { return 2; }
@end
#define SUD Defaults.shared
static NSString *BringFrontOnTypesetKey = @"stub";
enum { TexEngine, LatexEngine, MetapostEngine, UserEngine = 10 };
@interface Output : NSObject
@property NSUInteger edits;
- (NSRange)selectedRange;
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s;
- (void)scrollRangeToVisible:(NSRange)r;
- (void)setSelectable:(BOOL)b;
@end
@implementation Output
- (NSRange)selectedRange { return NSMakeRange(0, 0); }
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s { self.edits++; }
- (void)scrollRangeToVisible:(NSRange)r { }
- (void)setSelectable:(BOOL)b { }
@end
@interface Console : NSObject
@property BOOL isWindowLoaded;
@property (strong) Window *window;
@property (weak) Window *returnWindow;
@property (copy) void (^returnHandler)(void);
@property NSUInteger aborts;
- (void)abort:(id)sender;
- (void)toggleFromWindow:(NSWindow *)origin;
@end
@implementation Console
- (void)abort:(id)sender { self.aborts++; }
TOGGLE
@end
@interface Document : NSObject {
@public
    Window *scrapWindow, *scrapPDFWindow, *WindowAfterTypeset;
    BOOL fromMenu, doAbort, fileIsTex, taskDone;
    NSInteger whichEngine;
    Output *outputText;
}
@property BOOL annotationsExist;
@property (strong) Console *experimentConsole;
@property (strong) id inputPipe;
@property (strong) NSFileHandle *readHandle;
@property NSUInteger regularJobs, experimentJobs, cancellations, annotationSaves, auxiliaryRemovals;
- (BOOL)experimentHasKeyWindow;
- (void)typesetScrap:(id)sender;
- (void)callSaveAnnotations;
- (void)trashAUXFiles:(id)sender;
- (void)doJob:(NSInteger)engine withError:(BOOL)error runContinuously:(BOOL)continuous;
- (void)killRunningTasks;
- (void)doTypeset:(id)sender;
- (void)abort:(id)sender;
@end
@implementation Document
- (void)typesetScrap:(id)sender { self.experimentJobs++; }
- (void)callSaveAnnotations { self.annotationSaves++; }
- (void)trashAUXFiles:(id)sender { self.auxiliaryRemovals++; }
- (void)doJob:(NSInteger)engine withError:(BOOL)error runContinuously:(BOOL)continuous { self.regularJobs++; }
- (void)killRunningTasks { self.cancellations++; }
ROUTE
TYPESET
ABORT
@end
static NSUInteger failures, checks;
static void Check(BOOL condition, NSString *label) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", label.UTF8String); }
}
static Window *W(NSString *name) {
    Window *w = [Window new]; w.name = name; w.isVisible = YES; return w;
}
static Document *D(void) {
    Document *d = [Document new]; d->scrapWindow = W(@"experiment source");
    d->scrapPDFWindow = W(@"experiment PDF"); d->WindowAfterTypeset = W(@"normal return sentinel");
    d->fileIsTex = YES; d->fromMenu = YES; d->whichEngine = LatexEngine;
    d->outputText = [Output new]; d.annotationsExist = YES; d.inputPipe = [NSObject new];
    d.experimentConsole = [Console new]; d.experimentConsole.isWindowLoaded = YES;
    d.experimentConsole.window = W(@"experiment console"); return d;
}
int main(void) { @autoreleasepool {
    // Experiment remains visible while the normal source or preview is active.
    for (NSString *name in @[@"normal source", @"normal preview"]) {
        Document *d = D(); routingKeyWindow = W(name);
        Check(!d.experimentHasKeyWindow, @"visible Experiment does not claim a normal window");
        [d doTypeset:nil];
        Check(d.regularJobs == 1 && d.experimentJobs == 0, @"normal window typesets the normal document");
        Check(d.annotationSaves == 1 && !d.annotationsExist, @"normal path retains annotation saving");
        Check(d->WindowAfterTypeset == routingKeyWindow && !d->fromMenu, @"normal path retains post-typeset window selection");
    }
    for (NSUInteger which = 0; which < 3; which++) {
        Document *d = D();
        routingKeyWindow = which == 0 ? d->scrapWindow : which == 1 ? d->scrapPDFWindow : d.experimentConsole.window;
        Window *normalReturn = d->WindowAfterTypeset; id normalInput = d.inputPipe;
        Check(d.experimentHasKeyWindow, @"each Experiment window is recognized");
        [d doTypeset:nil];
        Check(d.experimentJobs == 1 && d.regularJobs == 0, @"Experiment window routes only to Experiment");
        Check(d.annotationsExist && d.annotationSaves == 0, @"Experiment typesetting does not save ordinary annotations");
        Check(d->WindowAfterTypeset == normalReturn && d->fromMenu, @"Experiment preserves normal typeset routing state");
        Check(d.inputPipe == normalInput, @"Experiment typesetting preserves ordinary input ownership");
        [d abort:@"stop"];
        Check(d.experimentConsole.aborts == 1 && d.cancellations == 0, @"Experiment abort does not cancel ordinary jobs");
        Check(!d->doAbort && !d->taskDone && d->outputText.edits == 0 && d.inputPipe == normalInput,
              @"Experiment abort preserves ordinary console and completion state");
    }
    Document *d = D(); routingKeyWindow = W(@"normal source");
    [d abort:@"stop"];
    Check(d.cancellations == 1 && d.experimentConsole.aborts == 0, @"normal abort leaves Experiment running");
    Check(d->doAbort && d->taskDone && d->outputText.edits == 1 && !d.inputPipe, @"normal abort retains cleanup");
    d = D(); routingKeyWindow = d.experimentConsole.window; d.experimentConsole.isWindowLoaded = NO;
    Check(!d.experimentHasKeyWindow, @"an unloaded console is not an active Experiment window");

    Console *c = [Console new]; c.window = W(@"console");
    Window *source = W(@"source"), *preview = W(@"preview");
    __block NSUInteger fallbacks = 0;
    c.returnHandler = ^{ fallbacks++; [source makeKeyAndOrderFront:nil]; };
    for (Window *origin in @[source, preview]) {
        routingKeyWindow = origin; [c toggleFromWindow:origin];
        Check(routingKeyWindow == c.window && c.returnWindow == origin, @"show console remembers its caller");
        [c toggleFromWindow:c.window];
        Check(routingKeyWindow == origin && !c.returnWindow, @"console returns to its caller and clears it");
    }
    routingKeyWindow = c.window; c.returnWindow = c.window;
    [c toggleFromWindow:c.window];
    Check(routingKeyWindow == source && fallbacks == 1 && !c.returnWindow, @"self-target falls back to Experiment source");
    routingKeyWindow = c.window; c.returnWindow = preview; preview.isVisible = NO;
    [c toggleFromWindow:c.window];
    Check(routingKeyWindow == source && fallbacks == 2, @"closed caller falls back to Experiment source");
    routingKeyWindow = c.window; c.returnWindow = nil;
    [c toggleFromWindow:c.window];
    Check(routingKeyWindow == source && fallbacks == 3, @"absent caller falls back to Experiment source");
    routingKeyWindow = c.window; c.returnWindow = preview; preview.isMiniaturized = YES;
    [c toggleFromWindow:c.window];
    Check(routingKeyWindow == preview && !preview.isMiniaturized, @"minimized caller is restored");
    printf("%lu checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
    return failures ? 1 : 0;
} }
'''
for token, replacement in [("TOGGLE", toggle), ("ROUTE", route), ("TYPESET", typeset), ("ABORT", abort)]:
    program = program.replace(token, replacement)

with tempfile.TemporaryDirectory(prefix="texshop-experiment-routing-") as temporary:
    source, executable = Path(temporary) / "test.m", Path(temporary) / "test"
    source.write_text(program)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wno-deprecated-declarations",
                    "-framework", "Foundation", str(source), "-o", str(executable)], check=True)
    result = subprocess.run([str(executable)], capture_output=True, text=True)
    if args.mutation:
        if result.returncode == 0:
            raise SystemExit(f"FAIL: mutation {args.mutation} was not detected")
        if result.returncode != 1 or "FAIL:" not in result.stderr:
            raise SystemExit("Mutation run did not fail through an assertion:\n" + result.stdout + result.stderr)
        print(f"PASS: detected mutation {args.mutation}")
    else:
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print("PASS: Experiment/normal typeset and abort isolation; console return routing")
        print(result.stdout.strip())
