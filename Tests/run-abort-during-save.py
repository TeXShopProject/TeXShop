#!/usr/bin/env python3
"""Abort while the document is being saved for typesetting: the typesetting does not start when the save ends.

Typesetting first saves the document, and starts the job when the save is done (saveFinished:). An Abort in between
found no job to stop, and the job then started anyway. The production -doJob:withError:runContinuously:,
-doJobForScript:withError:runContinuously: and -abort: of TSDocument-Jobs.m are compiled verbatim, with the check at
the start of -saveFinished:didSave:contextInfo:; the save is a stand-in that ends when the test says so, as a save
that is not over at once (a Save panel for a new document, a save that waits for another one). Nothing is shown on
screen. --mutations removes each part and the test must then fail."""
from pathlib import Path
import subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
jobs = (root / 'Sources/Typesetting/TSDocument-Jobs.m').read_text(encoding='utf-8')
do_job = method(jobs, '- (void) doJob:(NSInteger)type withError:(BOOL)error runContinuously:(BOOL)continuous')
do_script = method(jobs, '- (void) doJobForScript:(NSInteger)type withError:(BOOL)error runContinuously:(BOOL)continuous')
abort_method = method(jobs, '- (void)abort:(id)sender')
save = jobs[jobs.index('- (void) saveFinished: (NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)contextInfo'):]
save = save[save.index('    @try {\n') + len('    @try {\n'):save.index('    [self RescanMagicComments: self];')]
fragments = [('complete method:doJob', jobs, do_job), ('complete method:doJobForScript', jobs, do_script),
             ('complete method:abort', jobs, abort_method)]
if save.strip():
    fragments.append(('statement span:saveFinished start', jobs, save))

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "TestAppKitIsolation.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
enum { TexEngine = 1, LatexEngine = 2, BibtexEngine = 3, IndexEngine = 4 };
static NSMutableArray<NSString *> *events;
static void Record(NSString *event) { [events addObject:event]; }
#define TSAppendConsoleOutput(view, text, color) Record(text)
@interface TSTeXRootReplaceGuard : NSObject
+ (BOOL)isApplyingInProjectOfURL:(NSURL *)url;
@end
@implementation TSTeXRootReplaceGuard
+ (BOOL)isApplyingInProjectOfURL:(NSURL *)url { return NO; }
@end
@interface TSWindowManager : NSObject
@end
@implementation TSWindowManager
+ (instancetype)sharedInstance { return [self new]; }
- (void)checkProgramMenuItem:(NSInteger)engine checked:(BOOL)checked {}
@end
@interface Probe : NSObject {
@public
    BOOL fileIsTex, useTempEngine, typesetContinuously, makeError, doAutoSave, _externalEditor, doAbort, taskDone;
    NSInteger tempEngine, whichEngine, errorNumber, whichError;
    id outputText;
}
@property id readHandle, inputPipe, experimentConsole;
@property (copy) void (^pendingSave)(void);
@property BOOL edited;
@end
@implementation Probe
- (BOOL)isBeingReplacedIn { return NO; }
- (NSURL *)fileURL { return [NSURL fileURLWithPath:@"/tmp/probe.tex"]; }
- (BOOL)isDocumentEdited { return self.edited; }
- (BOOL)experimentHasKeyWindow { return NO; }
- (void)killRunningTasks { Record(@"jobs stopped"); }
- (void)fixMacroMenu {}
- (void)checkFileLinksA {}
- (NSString *)windowNibName { return @"TSDocument"; }
// A save that is not over at once: it ends when the test runs pendingSave.
- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)selector contextInfo:(void *)info
{
    __weak Probe *weak = self;
    self.pendingSave = ^{ ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, weak, YES, NULL); };
}
- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)selector contextInfo:(void *)info
{
    [self saveDocumentWithDelegate:delegate didSaveSelector:selector contextInfo:info];
}
- (void)autosaveFinished:(id)doc didSave:(BOOL)didSave contextInfo:(void *)info {}
- (void) saveFinished: (NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)contextInfo
{
SAVE
    Record(useTempEngine ? @"started (one engine)" : @"started");
}
DOJOB
DOSCRIPT
ABORT
@end

static void Finish(Probe *p)
{
    REQUIRE(p.pendingSave != nil);
    void (^save)(void) = p.pendingSave;
    p.pendingSave = nil;
    save();
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    events = [NSMutableArray array];
    for (int autosave = 0; autosave <= 1; autosave++) {
        Probe *p = [Probe new];
        p->fileIsTex = YES; p->doAutoSave = autosave; p.edited = YES;
        // Typeset, then the save ends: the job starts.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p);
        REQUIRE([events containsObject:@"started"]);
        // Abort while the save goes on: nothing starts when it ends.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        [p abort:nil];
        Finish(p);
        REQUIRE([events containsObject:@"\nProcess aborted\n"] && ![events containsObject:@"started"]);
        // The next Typeset starts again.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p);
        REQUIRE([events containsObject:@"started"]);
        // The same for a single engine (BibTeX, MakeIndex, the Typeset menu's engines).
        [events removeAllObjects];
        [p doJobForScript:BibtexEngine withError:NO runContinuously:NO];
        [p abort:nil];
        Finish(p);
        REQUIRE(![events containsObject:@"started (one engine)"] && !p->useTempEngine);
        [events removeAllObjects];
        [p doJobForScript:BibtexEngine withError:NO runContinuously:NO];
        Finish(p);
        REQUIRE([events containsObject:@"started (one engine)"]);
        // An Abort with nothing going on does not keep the next Typeset from starting.
        [events removeAllObjects];
        [p abort:nil];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p);
        REQUIRE([events containsObject:@"started"]);
        printf("PASS: %s: Abort while saving keeps the job from starting; the next Typeset starts\n", autosave ? "autosave" : "save");
    }
} return 0; }
'''


def run(parts, label):
    program = (PROGRAM.replace('SAVE', parts['save']).replace('DOJOB', parts['job']).replace('DOSCRIPT', parts['script'])
               .replace('ABORT', parts['abort']))
    with tempfile.TemporaryDirectory(prefix='texshop-abort-during-save-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(folder / 'test.m'), '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        return subprocess.run([str(folder / 'test')], capture_output=True, text=True, timeout=60)


parts = {'save': save, 'job': do_job, 'script': do_script, 'abort': abort_method}
result = run(parts, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: an Abort while the document is being saved does not keep the typesetting from starting')
if '--mutations' in sys.argv:
    mutations = {
        'no check after the save': ('save', 'if (doAbort) {', 'if (NO) {'),
        'Typeset keeps an earlier Abort': ('job', '\tdoAbort = NO;\n', ''),
        'one engine keeps an earlier Abort': ('script', '\tdoAbort = NO;\n', ''),
    }
    for name, (where, before, after) in mutations.items():
        changed = dict(parts)
        assert changed[where].count(before) == 1, name
        changed[where] = changed[where].replace(before, after)
        r = run(changed, name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, r.stderr.strip().splitlines()[-1])
print('PASS: an Abort while the document is being saved keeps the typesetting from starting')
