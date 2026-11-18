#!/usr/bin/env python3
"""Abort while the document is being saved for typesetting: the typesetting does not start when the save ends, and
only the Typeset asked for last starts, once, with its own engine.

Typesetting first saves the document, and starts the job when the save is done (saveFinished:). The production
-doJob:withError:runContinuously:, -doJobForScript:withError:runContinuously:, -doAlternateTypeset: and -abort: of
TSDocument-Jobs.m are compiled verbatim, with the start of -saveFinished:didSave:contextInfo: up to where it picks the
engine; the saves are stand-ins that end when the test says so, in any order, as saves that are not over at once (a
Save panel for a new document, a save that waits for another one). Checked: an Abort during the save keeps the job
from starting; the save of an earlier Typeset, aborted or not, does not start the later one, and the later one starts
once; the end of an earlier job (its termination handler clears doAbort) does not undo an Abort; an aborted
Typeset › Alternate is not carried over to the next Typeset; a save that fails or is cancelled starts nothing and
does not keep the next Typeset from starting; the answer to the confirmation of --shell-escape (the one wait between
the save and the launch) goes on only with the Typeset asked for last, and not after an Abort. Nothing is shown on screen. --mutations removes each
part and the test must then fail."""
from pathlib import Path
import subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
jobs = (root / 'Sources/Typesetting/TSDocument-Jobs.m').read_text(encoding='utf-8')
do_job = method(jobs, '- (void) doJob:(NSInteger)type withError:(BOOL)error runContinuously:(BOOL)continuous')
do_script = method(jobs, '- (void) doJobForScript:(NSInteger)type withError:(BOOL)error runContinuously:(BOOL)continuous')
do_alternate = method(jobs, '- (void)doAlternateTypeset: sender')
abort_method = method(jobs, '- (void)abort:(id)sender')
save = jobs[jobs.index('- (void) saveFinished: (NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)contextInfo'):]
save = save[save.index('    @try {\n') + len('    @try {\n'):save.index('\twhichEngineLocal = (useTempEngine ? tempEngine : whichEngine);')]
# The confirmation of --shell-escape, the one wait between the save and the launch, and its answer.
shell = jobs[jobs.index('\tif ((! warningGiven) && ((whichEngineLocal == TexEngine) || (whichEngineLocal == LatexEngine))'):]
shell = shell[:shell.index('\t[self completeSaveFinished];\n') + len('\t[self completeSaveFinished];\n')]
sheet = method(jobs, '-(void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo')
fragments = [('complete method:doJob', jobs, do_job), ('complete method:doJobForScript', jobs, do_script),
             ('complete method:doAlternateTypeset', jobs, do_alternate), ('complete method:abort', jobs, abort_method),
             ('statement span:saveFinished start', jobs, save), ('statement span:shell escape confirmation', jobs, shell),
             ('complete method:sheetDidEnd', jobs, sheet)]

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "TestAppKitIsolation.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
enum { TexEngine = 1, LatexEngine = 2, BibtexEngine = 3, IndexEngine = 4, MetapostEngine = 5, UserEngine = 6 };
static NSMutableArray<NSString *> *events;
static void Record(NSString *event) { [events addObject:event]; }
#define TSAppendConsoleOutput(view, text, color) Record(text)
#define SUD TSIsolatedAppKitDefaults
static NSString *WarnForShellEscapeKey = @"WarnForShellEscape", *LatexCommandKey = @"LatexCommand", *TexCommandKey = @"TexCommand";
enum { kTypesetViaPDFTeX = 100, kTypesetViaGhostScript = 101 };
// The confirmation sheet: its answer is given by the test, later.
static NSMutableArray *sheets;
static void RecordSheet(id delegate, SEL selector, void *info)
{
    [sheets addObject:^(NSInteger answer) { ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, selector, nil, answer, info); }];
}
#define NSBeginCriticalAlertSheet(title, defaultButton, alternateButton, otherButton, window, delegate, selector, didDismiss, info, ...) RecordSheet(delegate, selector, info)
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
    BOOL fileIsTex, useTempEngine, typesetContinuously, makeError, doAutoSave, _externalEditor, doAbort, taskDone, fromAlternate, fromMenu;
    NSInteger tempEngine, whichEngine, errorNumber, whichError, numberingCorrection;
    NSUInteger typesetRequest, savedTypesetRequest, abortedTypesetRequest;
    BOOL typesetRequestFromAlternate, warningGiven, omitShellEscape, withLatex, lastAlternate, lastOneEngine;
    NSInteger theScript;
    id outputText, textWindow;
}
@property id readHandle, inputPipe, experimentConsole;
@property NSMutableArray *pendingSaves;
@property BOOL edited, automaticCorrection;
@property NSInteger numberingCorrection;
@end
@implementation Probe
- (BOOL)isBeingReplacedIn { return NO; }
- (NSURL *)fileURL { return [NSURL fileURLWithPath:@"/tmp/probe.tex"]; }
- (BOOL)isDocumentEdited { return self.edited; }
- (BOOL)experimentHasKeyWindow { return NO; }
- (void)killRunningTasks { Record(@"jobs stopped"); }
- (void)fixMacroMenu {}
- (void)checkFileLinksA {}
- (void)RescanMagicComments:(id)sender {}
- (NSString *)windowNibName { return @"TSDocument"; }
// A save that is not over at once: it ends when the test says so.
- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)selector contextInfo:(void *)info
{
    if (!self.pendingSaves) self.pendingSaves = [NSMutableArray array];
    __weak Probe *weak = self;
    [self.pendingSaves addObject:^(BOOL didSave) { ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, weak, didSave, info); }];
}
- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)selector contextInfo:(void *)info
{
    [self saveDocumentWithDelegate:delegate didSaveSelector:selector contextInfo:info];
}
- (void)autosaveFinished:(id)doc didSave:(BOOL)didSave contextInfo:(void *)info {}
- (void) saveFinished: (NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)contextInfo
{
    BOOL fromAlternateTemp = NO;
    NSInteger whichEngineLocal;
    NSString *myEngine;
    NSRange aRange;
SAVE
    // The engine, as the rest of saveFinished: picks it for LaTeX.
    whichEngineLocal = (useTempEngine ? tempEngine : whichEngine);
    withLatex = (whichEngineLocal == LatexEngine);
    theScript = kTypesetViaPDFTeX;
    lastAlternate = fromAlternateTemp;
    lastOneEngine = useTempEngine;
SHELL
}
- (void)completeSaveFinished
{
    Record([NSString stringWithFormat:@"started %@%@", lastOneEngine ? @"one engine" : @"Typeset", lastAlternate ? @" (Alternate)" : @""]);
}
SHEET
DOJOB
DOSCRIPT
DOALTERNATE
ABORT
@end

// The save asked for index-th (0 = the first still pending) ends now.
static void FinishSaving(Probe *p, NSUInteger index, BOOL didSave)
{
    REQUIRE(index < p.pendingSaves.count);
    void (^save)(BOOL) = p.pendingSaves[index];
    [p.pendingSaves removeObjectAtIndex:index];
    save(didSave);
}
static void Finish(Probe *p, NSUInteger index) { FinishSaving(p, index, YES); }
// The answer to the confirmation sheet asked for index-th.
static void Answer(NSUInteger index, NSInteger answer)
{
    REQUIRE(index < sheets.count);
    void (^reply)(NSInteger) = sheets[index];
    [sheets removeObjectAtIndex:index];
    reply(answer);
}
static NSUInteger Started(void)
{
    NSUInteger n = 0;
    for (NSString *e in events) if ([e hasPrefix:@"started"]) n++;
    return n;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    events = [NSMutableArray array];
    for (int autosave = 0; autosave <= 1; autosave++) {
        Probe *p = [Probe new];
        p->fileIsTex = YES; p->doAutoSave = autosave; p.edited = YES; p->whichEngine = LatexEngine;
        // Typeset, then the save ends: the job starts.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE([events containsObject:@"started Typeset"] && Started() == 1);
        // Abort while the save goes on: nothing starts when it ends.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        [p abort:nil];
        Finish(p, 0);
        REQUIRE([events containsObject:@"\nProcess aborted\n"] && Started() == 0);
        // The next Typeset starts again.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE([events containsObject:@"started Typeset"] && Started() == 1);
        // The same for a single engine (BibTeX, MakeIndex, the Typeset menu's engines).
        [events removeAllObjects];
        [p doJobForScript:BibtexEngine withError:NO runContinuously:NO];
        [p abort:nil];
        Finish(p, 0);
        REQUIRE(Started() == 0 && !p->useTempEngine);
        [events removeAllObjects];
        [p doJobForScript:BibtexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE([events containsObject:@"started one engine"] && Started() == 1);
        // An Abort with nothing going on does not keep the next Typeset from starting.
        [events removeAllObjects];
        [p abort:nil];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE([events containsObject:@"started Typeset"] && Started() == 1);
        // Typeset A, Abort, then B (BibTeX) while A is still being saved: whichever save ends first, only B starts,
        // once, with its own engine.
        for (int order = 0; order <= 1; order++) {
            [events removeAllObjects];
            [p doJob:LatexEngine withError:NO runContinuously:NO];
            [p abort:nil];
            [p doJobForScript:BibtexEngine withError:NO runContinuously:NO];
            REQUIRE(p.pendingSaves.count == 2);
            Finish(p, order == 0 ? 0 : 1);
            Finish(p, 0);
            REQUIRE(Started() == 1 && [events containsObject:@"started one engine"]);
        }
        // Typeset A, then B without an Abort, while A is being saved: B starts once.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0); Finish(p, 0);
        REQUIRE(Started() == 1);
        // A save that tells of its end twice starts the job once.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        [p.pendingSaves addObject:p.pendingSaves[0]];
        Finish(p, 0); Finish(p, 0);
        REQUIRE(Started() == 1);
        // The end of an earlier job clears doAbort in its termination handler (TSDocument-Jobs.m): it does not undo an
        // Abort of the Typeset that is being saved.
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        [p abort:nil];
        p->doAbort = NO;
        Finish(p, 0);
        REQUIRE(Started() == 0);
        // Typeset › Alternate: it starts with the alternate engine; aborted while it is saved, the next Typeset is
        // not an Alternate one, whether it is asked for after the save or while it goes on.
        [events removeAllObjects];
        [p doAlternateTypeset:nil];
        Finish(p, 0);
        REQUIRE([events containsObject:@"started Typeset (Alternate)"] && Started() == 1);
        [events removeAllObjects];
        [p doAlternateTypeset:nil];
        [p abort:nil];
        Finish(p, 0);
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE(Started() == 1 && [events containsObject:@"started Typeset"]);
        [events removeAllObjects];
        [p doAlternateTypeset:nil];
        [p abort:nil];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0); Finish(p, 0);
        REQUIRE(Started() == 1 && [events containsObject:@"started Typeset"]);
        // A save that fails, or that is cancelled, starts nothing; the next Typeset starts, with its own engine.
        [events removeAllObjects];
        [p doJobForScript:BibtexEngine withError:NO runContinuously:NO];
        FinishSaving(p, 0, NO);
        REQUIRE(Started() == 0 && !p->useTempEngine);
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE(Started() == 1 && [events containsObject:@"started Typeset"]);
        // The confirmation of --shell-escape: the answer starts the Typeset, but not after an Abort, and not one that a
        // later Typeset replaced.
        sheets = [NSMutableArray array];
        [SUD setBool:YES forKey:WarnForShellEscapeKey];
        [SUD setObject:@"pdflatex --shell-escape --file-line-error --synctex=1" forKey:LatexCommandKey];
        p->warningGiven = NO;
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE(Started() == 0 && sheets.count == 1);
        Answer(0, NSAlertDefaultReturn);
        REQUIRE(Started() == 1);
        p->warningGiven = NO;
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE(sheets.count == 1);
        [p abort:nil];
        Answer(0, NSAlertDefaultReturn);
        REQUIRE(Started() == 0);
        [events removeAllObjects];
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        [p doJob:LatexEngine withError:NO runContinuously:NO];
        Finish(p, 0);
        REQUIRE(sheets.count == 2);
        Answer(0, NSAlertAlternateReturn);
        REQUIRE(Started() == 0);
        Answer(0, NSAlertDefaultReturn);
        REQUIRE(Started() == 1);
        [SUD setBool:NO forKey:WarnForShellEscapeKey];
        printf("PASS: %s: Abort while saving keeps the job from starting; only the last Typeset starts, once, with its own engine\n", autosave ? "autosave" : "save");
    }
} return 0; }
'''


def run(parts, label):
    program = (PROGRAM.replace('SAVE', parts['save']).replace('SHELL', parts['shell']).replace('SHEET', parts['sheet']).replace('DOJOB', parts['job']).replace('DOSCRIPT', parts['script'])
               .replace('DOALTERNATE', parts['alternate']).replace('ABORT', parts['abort']))
    with tempfile.TemporaryDirectory(prefix='texshop-abort-during-save-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(folder / 'test.m'), '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        return subprocess.run([str(folder / 'test')], capture_output=True, text=True, timeout=60)


parts = {'save': save, 'shell': shell, 'sheet': sheet, 'job': do_job, 'script': do_script, 'alternate': do_alternate, 'abort': abort_method}
result = run(parts, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: an Abort while the document is being saved does not keep the typesetting from starting')
if '--mutations' in sys.argv:
    mutations = {
        'no check after the save': ('save', 'if (request == abortedTypesetRequest || ! didSave) {', 'if (! didSave) {'),
        'earlier saves start the job': ('save', 'if (request != typesetRequest || request == savedTypesetRequest)', 'if (request == savedTypesetRequest)'),
        'a request starts twice': ('save', 'if (request != typesetRequest || request == savedTypesetRequest)', 'if (request != typesetRequest)'),
        'Abort not recorded': ('abort', '    abortedTypesetRequest = typesetRequest;\n', ''),
        'Alternate carried over': ('job', '\tfromAlternate = NO;\n', ''),
        'a failed save starts the job': ('save', 'if (request == abortedTypesetRequest || ! didSave) {', 'if (request == abortedTypesetRequest) {'),
        'the answer goes on after an Abort': ('sheet', 'if (request != typesetRequest || request == abortedTypesetRequest)', 'if (request != typesetRequest)'),
        'the answer of a replaced Typeset goes on': ('sheet', 'if (request != typesetRequest || request == abortedTypesetRequest)', 'if (request == abortedTypesetRequest)'),
    }
    for name, (where, before, after) in mutations.items():
        changed = dict(parts)
        assert changed[where].count(before) == 1, name
        changed[where] = changed[where].replace(before, after)
        r = run(changed, name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, r.stderr.strip().splitlines()[-1])
print('PASS: an Abort while the document is being saved keeps the typesetting from starting')
