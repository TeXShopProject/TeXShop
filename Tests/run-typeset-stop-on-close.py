#!/usr/bin/env python3
"""Closing a document, or quitting TeXShop, stops the typesetting jobs it started, as Abort does.

The production -[TSDocument close] and -[TSAppDelegate applicationWillTerminate:] are compiled verbatim with stand-ins
for what they call: the windows, the status bar, the Experiment and the annotations are recorders, and
killRunningTasks records that it ran. -close stops the jobs before the windows close and the document goes, and not
when a Replace All in the document keeps it open; quitting stops the jobs of every document, and a running Experiment
job (a real TSExperimentJob running sleep, whose process must be gone). The real killRunningTasks
and stopJobTask: (process group, TERM then KILL) are checked by run-typeset-robustness.py. The folder of dragged
images that quitting empties is a temporary folder. Nothing is shown on screen. --mutations removes each call and the
test must then fail."""
from pathlib import Path
import os, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
document = (root / 'Sources/Document/TSDocument.m').read_text(encoding='utf-8')
delegate = (root / 'Sources/App/TSAppDelegate.m').read_text(encoding='utf-8')
close = method(document, '- (void)close\n{')
terminate = method(delegate, '- (void)applicationWillTerminate:(NSNotification *)aNotification')
fragments = [('complete method:close', document, close), ('complete method:applicationWillTerminate', delegate, terminate)]

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSExperimentJob.h"
#import "TestAppKitIsolation.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
static NSMutableArray<NSString *> *events;
static void Record(NSString *event) { [events addObject:event]; }
static BOOL g_canRegisterCommandCompletion;
static NSString *DraggedImagePath;
// Whatever -close and quitting send to the objects around the document: each message is recorded.
@interface Recorder : NSObject
@property (copy) NSString *name;
@property (copy) NSString *CommandCompletionPath;
- (id)toolbar;
@end
@implementation Recorder
+ (instancetype)named:(NSString *)name { Recorder *r = [self new]; r.name = name; return r; }
+ (instancetype)sharedInstance { return [self named:@"shared"]; }
+ (instancetype)sharedGlobalData { return nil; }
- (id)toolbar { return nil; }
- (void)stop { Record([self.name stringByAppendingString:@" stop"]); }
- (void)close { Record([self.name stringByAppendingString:@" close"]); }
- (void)breakConnections {}
- (void)invalidate {}
- (void)turnVisibleOff:(BOOL)flag {}
- (void)notifyActiveTextWindowClosed {}
- (void)finishPreferencesForTermination { Record(@"preferences"); }
@end
@compatibility_alias TSToolbar Recorder;
@compatibility_alias TSWindowManager Recorder;
@compatibility_alias GlobalData Recorder;
@compatibility_alias TSPreferences Recorder;

@interface Base : NSObject
- (void)close;
@end
@implementation Base
- (void)close { Record(@"document closed"); }
@end

// The Experiment console of a document, reduced to its job: -abort: stops the job first, as the production one does
// (TSExperimentConsoleController); run-experiment-console.py checks the rest of it.
@interface TSExperimentConsoleController : NSObject
@property TSExperimentJob *job;
- (void)abort:(id)sender;
@end
@implementation TSExperimentConsoleController
- (void)abort:(id)sender { Record(@"Experiment stopped"); [self.job cancel]; self.job = nil; }
@end

@interface TSDocument : Base {
@public
    Recorder *pdfWindow, *_htmlWindow, *outputWindow, *scrapPDFWindow, *scrapWindow;
    BOOL fileIsTex;
}
@property BOOL replacing, annotationsExist;
@property (copy) NSString *label;
@property TSExperimentConsoleController *experimentConsole;
@property Recorder *sourceStatusBar, *textStatistics, *pdfKitWindow, *logWindow;
@property id myPDFKitView, myPDFKitView2, pdfActivity;
@property NSTimer *tagTimer, *pdfRefreshTimer;
@end
@implementation TSDocument
+ (void)applySpellingDefaultUnlessDocumentIsMain {}
- (BOOL)isBeingReplacedIn { return self.replacing; }
- (NSURL *)fileURL { return nil; }
- (void)killRunningTasks { Record([self.label stringByAppendingString:@" jobs stopped"]); }
- (void)closeExperiment { Record(@"Experiment closed"); }
- (void)cancelWatchFile {}
- (void)stopExternalPDFObservation {}
- (void)callSaveAnnotations { Record([self.label stringByAppendingString:@" annotations saved"]); }
- (void)annotationWindowWillClose:(id)sender {}
CLOSE
@end

@interface TSDocumentController : NSObject
@property NSArray *documents;
@end
@implementation TSDocumentController
+ (instancetype)sharedDocumentController { static TSDocumentController *shared; if (!shared) shared = [self new]; return shared; }
@end
@interface Delegate : NSObject
@end
@implementation Delegate
TERMINATE
@end

static TSDocument *Document(NSString *label)
{
    TSDocument *document = [TSDocument new];
    document.label = label;
    document->outputWindow = [Recorder named:@"console"];
    document.sourceStatusBar = [Recorder named:@"status bar"];
    return document;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    events = [NSMutableArray array];
    // Closing: the jobs stop first, before the windows close and the document goes.
    TSDocument *document = Document(@"a");
    [document close];
    REQUIRE([events containsObject:@"a jobs stopped"] && [events containsObject:@"document closed"]);
    REQUIRE([events indexOfObject:@"a jobs stopped"] < [events indexOfObject:@"status bar stop"]);
    REQUIRE([events indexOfObject:@"a jobs stopped"] < [events indexOfObject:@"console close"]);
    REQUIRE([events indexOfObject:@"a jobs stopped"] < [events indexOfObject:@"document closed"]);
    // A document that a Replace All keeps open is not closed, and its jobs go on.
    [events removeAllObjects];
    document.replacing = YES;
    [document close];
    REQUIRE(events.count == 0);
    printf("PASS: closing a document stops its typesetting jobs first, unless a Replace All keeps it open\n");
    // Quitting: the jobs of every document stop.
    [events removeAllObjects];
    NSString *folder = [NSString stringWithUTF8String:argv[1]];
    DraggedImagePath = [folder stringByAppendingPathComponent:@"texshop_image"];
    TSDocument *b = Document(@"b"), *c = Document(@"c");
    c.annotationsExist = YES;
    [TSDocumentController sharedDocumentController].documents = @[b, c];
    [[Delegate new] applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil]];
    REQUIRE([events containsObject:@"b jobs stopped"] && [events containsObject:@"c jobs stopped"] && [events containsObject:@"c annotations saved"]);
    REQUIRE(![events containsObject:@"document closed"]);
    printf("PASS: quitting stops the typesetting jobs of every document\n");
    // Quitting while an Experiment job runs: its process is gone when quitting is done.
    [events removeAllObjects];
    TSDocument *e = Document(@"e");
    e.experimentConsole = [TSExperimentConsoleController new];
    TSExperimentJob *job = [TSExperimentJob new];
    e.experimentConsole.job = job;
    NSError *error = nil;
    REQUIRE([job startExecutable:@"/bin/sleep" arguments:@[@"10"] environment:@{@"PATH": @"/bin:/usr/bin"} directory:[NSURL fileURLWithPath:folder] error:&error]);
    NSTask *child = [job valueForKey:@"task"];
    pid_t pid = child.processIdentifier;
    REQUIRE(pid > 1 && kill(pid, 0) == 0);
    [TSDocumentController sharedDocumentController].documents = @[e];
    [[Delegate new] applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil]];
    REQUIRE([events containsObject:@"Experiment stopped"] && !job.active);
    REQUIRE(kill(pid, 0) != 0);
    printf("PASS: quitting stops a running Experiment job, and its process is gone\n");
} return 0; }
'''


def run(close_text, terminate_text, label):
    program = PROGRAM.replace('CLOSE', close_text).replace('TERMINATE', terminate_text)
    with tempfile.TemporaryDirectory(prefix='texshop-typeset-stop-on-close-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        (folder / 'DraggedImages').mkdir()
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(folder / 'test.m'), str(root / 'Sources/Typesetting/TSExperimentJob.m'), '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        return subprocess.run([str(folder / 'test'), str(folder / 'DraggedImages')], capture_output=True, text=True, timeout=60)


result = run(close, terminate, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: closing a document or quitting leaves its typesetting running')
if '--mutations' in sys.argv:
    mutations = {
        'close does not stop the jobs': ('close', '    [self killRunningTasks];\n', ''),
        'quitting does not stop the jobs': ('terminate', '            [aDocument killRunningTasks];\n', '            ;\n'),
        'quitting does not stop the Experiment': ('terminate', '            [aDocument.experimentConsole abort:nil];\n', '            ;\n'),
    }
    for name, (where, before, after) in mutations.items():
        c, t = close, terminate
        if where == 'close':
            assert c.count(before) == 1, name; c = c.replace(before, after)
        else:
            assert t.count(before) == 1, name; t = t.replace(before, after)
        r = run(c, t, name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, r.stderr.strip().splitlines()[-1])
print('PASS: typesetting stops when its document closes and when TeXShop quits')
