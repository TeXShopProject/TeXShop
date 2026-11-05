#!/usr/bin/env python3
"""Exercise the real typesetting/save-path methods against inputs that used to raise
exceptions or signal the wrong process.

Usage: run-typeset-robustness.py [ROOT]
ROOT defaults to the repository containing this script; the methods are read from
ROOT/Sources. Preferences are a dictionary-backed stub (NSUserDefaults is never used),
kill() is routed through a recorder that only forwards signals to the child process
this test starts itself, and the program is run once with PATH and once without it."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
sources = root / 'Sources'


def matching_brace(src, i):
    """Return the index just past the brace that closes the one at src[i]."""
    depth = 0
    while i < len(src):
        if src.startswith('//', i):
            i = src.index('\n', i)
            continue
        if src.startswith('/*', i):
            i = src.index('*/', i) + 2
            continue
        c = src[i]
        if c in '"\'':
            j = i + 1
            while src[j] != c:
                j += 2 if src[j] == '\\' else 1
            i = j + 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced braces')


def method(name, signature):
    src = (sources / name).read_text(errors='replace')
    start = src.index(signature)
    return src[start:matching_brace(src, src.index('{', start))]


def block(name, after, marker):
    """The statement starting at `marker` (searched after `after`) up to its closing brace."""
    src = (sources / name).read_text(errors='replace')
    start = src.index(marker, src.index(after))
    return src[start:matching_brace(src, src.index('{', start))]


def span(name, after, start_marker, end_marker):
    src = (sources / name).read_text(errors='replace')
    start = src.index(start_marker, src.index(after))
    end = src.index(end_marker, start) + len(end_marker)
    return src[start:end]


jobs = 'TSDocument-Jobs.m'
pieces = {
    'ENVIRONMENT': method(jobs, '- (NSDictionary *)environmentForSubTask'),
    'SCRAP_ENVIRONMENT': method('TSDocument-Scrap.m', '- (NSDictionary *)environmentWithNewPath:'),
    'HELP_PATH': span('HelpDocuments.m', '- (IBAction)displayHelpForPackage:',
                      'displayPackageHelpTask = nil;\n\t}', '[env setObject: path forKey: @"PATH"];')
                 .split('\n', 2)[2],
    'START_TASK': method(jobs, '- (BOOL) startTask: (NSTask*) task running:'),
    'KILL_RUNNING_TASKS': method(jobs, '- (void)killRunningTasks'),
    'TEX_TASK_SHUTDOWN': block(jobs, '- (void)killRunningTasks', 'if (self.texTask != nil) {'),
    'SEPARATE': method(jobs, '- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args'),
    'OLD_HEADING': block(jobs, '- (void) saveFinished:',
                         'if ((! done) && ([SUD boolForKey:UseOldHeadingCommandsKey])) {'),
    'SAVE_FOR_STATISTICS': method('TSDocument.m', '- (void)saveForStatistics:'),
    'HTML_HOME_CHANGED': method('TSPreferences.m', '- (IBAction)HtmlHomeChanged:sender'),
}

program = r'''
#import <Cocoa/Cocoa.h>
#include <signal.h>
#include <stdlib.h>

#define HIGHSIERRAORHIGHER
enum { TexEngine = 1, LatexEngine = 2, BibtexEngine = 3, IndexEngine = 4, MetapostEngine = 5, UserEngine = 6 };
typedef enum { kTypesetViaPDFTeX = 100, kTypesetViaGhostScript = 101, kTypesetViaPersonalScript = 102 } DefaultTypesetMode;
static NSString *TetexBinPath = @"TetexBinPath", *GSBinPath = @"GSBinPath", *HtmlHomeKey = @"HtmlHome";
static NSString *UseOldHeadingCommandsKey = @"UseOldHeadingCommands";
static BOOL atLeastElCapitan = YES, atLeastHighSierra = YES;
static int alertCount;
#define NSBeginAlertSheet(...) (alertCount++)

// Preferences backed by a dictionary, standing in for NSUserDefaults.
@interface ProbePreferences : NSObject
@property NSMutableDictionary *values;
@end
@implementation ProbePreferences
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return _values[key]; }
- (NSString *)stringForKey:(NSString *)key { id v = _values[key]; return [v isKindOfClass:[NSString class]] ? v : nil; }
- (BOOL)boolForKey:(NSString *)key { return [_values[key] boolValue]; }
- (void)setObject:(id)value forKey:(NSString *)key { if (value) _values[key] = value; else [_values removeObjectForKey:key]; }
@end
static ProbePreferences *probePreferences;
#define SUD probePreferences

// kill() recorder: signals reach only the child started by this test.
static NSMutableArray *killCalls;
static pid_t ownChild = -1;
static int probe_kill(pid_t pid, int sig) {
    [killCalls addObject:@[@(pid), @(sig)]];
    if (pid > 0 && pid == ownChild)
        return kill(pid, sig);
    return 0;
}
#define kill probe_kill

@interface ProbeText : NSObject
@property NSMutableString *text;
@end
@implementation ProbeText
- (instancetype)init { if ((self = [super init])) _text = [NSMutableString string]; return self; }
- (NSRange)selectedRange { return NSMakeRange(_text.length, 0); }
- (NSArray *)selectedRanges { return @[[NSValue valueWithRange:NSMakeRange(0, 0)]]; }
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string { [_text replaceCharactersInRange:range withString:string]; }
- (void)scrollRangeToVisible:(NSRange)range { }
- (NSWindow *)window { return nil; }
- (NSString *)stringValue { return _text; }
@end

@interface TSWindowManager : NSObject
+ (instancetype)sharedInstance;
- (void)checkProgramMenuItem:(NSInteger)item checked:(BOOL)checked;
@end
@implementation TSWindowManager
+ (instancetype)sharedInstance { return [self new]; }
- (void)checkProgramMenuItem:(NSInteger)item checked:(BOOL)checked { }
@end

@interface Probe : NSObject {
@public
    ProbeText *textView, *outputText;
    BOOL doAbort, withLatex, useTempEngine;
    NSInteger theScript, whichEngine, tempEngine;
    id programButton;
}
@property (strong) NSTask *texTask, *bibTask, *indexTask, *metaFontTask;
@property (strong) NSPipe *outputPipe, *inputPipe;
@property BOOL statisticsRaise;
@property (copy) NSString *helpEnginePath, *helpPATH;
- (NSDictionary *)environmentForSubTask;
- (void)checkATaskStatusFromTerminationRoutine:(id)task;
- (void)repeatTypeset;
- (void)fixMacroMenu;
- (void)showStatistics:sender;
@end

@implementation Probe
- (void)checkATaskStatusFromTerminationRoutine:(id)task { }
- (void)repeatTypeset { }
- (void)fixMacroMenu { }
- (void)showStatistics:sender { if (self.statisticsRaise) [NSException raise:NSRangeException format:@"probe"]; }
ENVIRONMENT
SCRAP_ENVIRONMENT
- (void)helpPathFor:(id)unused
{
    NSMutableDictionary *env = nil;
    NSString *path = nil, *enginePath = nil;
    __unused NSString *binPath = nil;
    self.helpEnginePath = nil;
    self.helpPATH = nil;
HELP_PATH
    self.helpEnginePath = enginePath;
    self.helpPATH = [env objectForKey:@"PATH"];
}
START_TASK
KILL_RUNNING_TASKS
- (void)shutDownTexTask
{
    NSDate *myDate;
TEX_TASK_SHUTDOWN
}
SEPARATE
- (void)oldHeadingFor:(NSString *)theSource
{
    NSArray *myList;
    NSString *theKey;
    NSRange myRange, theRange;
    NSUInteger mystart, myend, length;
    NSInteger i, j;
    BOOL done = NO;
OLD_HEADING
}
SAVE_FOR_STATISTICS
@end

@interface ProbePreferencesController : NSObject {
@public
    NSUndoManager *_undoManager;
    ProbeText *_HtmlHomeField;
}
@end
@implementation ProbePreferencesController
HTML_HOME_CHANGED
@end

static int failures;
static void report(BOOL ok, NSString *name, NSString *detail) {
    if (ok) printf("PASS: %s\n", name.UTF8String);
    else { failures++; printf("FAIL: %s: %s\n", name.UTF8String, detail.UTF8String); }
}
#define CHECK(title, ...) do { NSString *detail = @"condition not met"; BOOL ok = NO; \
    @try { __VA_ARGS__ } @catch (NSException *e) { ok = NO; detail = [NSString stringWithFormat:@"exception %@: %@", e.name, e.reason]; } \
    report(ok, title, detail); } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *bad = [NSString stringWithUTF8String:argv[1]];
        NSString *dir = [NSString stringWithUTF8String:argv[2]];
        const char *envPath = getenv("PATH");
        NSString *base = envPath ? [NSString stringWithUTF8String:envPath] : @"/usr/bin:/bin:/usr/sbin:/sbin";
        NSString *label = envPath ? @"with PATH" : @"without PATH";
        probePreferences = [ProbePreferences new];
        killCalls = [NSMutableArray array];
        Probe *p = [Probe new];
        p->textView = [ProbeText new];
        p->outputText = [ProbeText new];

        // Environment for typesetting tasks (A1).
        CHECK(([NSString stringWithFormat:@"environmentForSubTask %@, preference paths unset", label]), {
            [probePreferences.values removeAllObjects];
            ok = [[p environmentForSubTask][@"PATH"] isEqualToString:base];
        });
        CHECK(([NSString stringWithFormat:@"environmentForSubTask %@, preference paths empty", label]), {
            probePreferences.values[TetexBinPath] = @""; probePreferences.values[GSBinPath] = @"";
            ok = [[p environmentForSubTask][@"PATH"] isEqualToString:base];
        });
        CHECK(([NSString stringWithFormat:@"environmentForSubTask %@, preference paths set", label]), {
            probePreferences.values[TetexBinPath] = @"~/texbin"; probePreferences.values[GSBinPath] = @"/opt/gs";
            NSString *expected = [NSString stringWithFormat:@"%@:%@:/opt/gs", base, [@"~/texbin" stringByExpandingTildeInPath]];
            ok = [[p environmentForSubTask][@"PATH"] isEqualToString:expected];
        });
        CHECK(([NSString stringWithFormat:@"environmentWithNewPath: %@, preference paths unset", label]), {
            [probePreferences.values removeAllObjects];
            NSDictionary *env = [p environmentWithNewPath:@"/scrap"];
            ok = [env[@"PATH"] isEqualToString:[base stringByAppendingString:@":/scrap"]]
                && [env[@"TEXINPUTS"] isEqualToString:@".:/scrap:"];
        });
        CHECK(([NSString stringWithFormat:@"package help PATH %@, TeX bin path unset", label]), {
            [probePreferences.values removeAllObjects];
            [p helpPathFor:nil];
            ok = (p.helpEnginePath == nil);
        });
        CHECK(([NSString stringWithFormat:@"package help PATH %@, TeX bin path set", label]), {
            probePreferences.values[TetexBinPath] = @"/Library/TeX/texbin";
            [p helpPathFor:nil];
            ok = [p.helpEnginePath isEqualToString:@"/Library/TeX/texbin/texdoc"]
                && [p.helpPATH isEqualToString:[base stringByAppendingString:@":/Library/TeX/texbin"]];
        });

        if (envPath) {
            // Launch failures (A2): the executable bit is set but the file cannot be executed.
            for (int highSierra = 1; highSierra >= 0; highSierra--) {
                atLeastHighSierra = highSierra;
                NSString *name = highSierra ? @"startTask: launch failure (launchAndReturnError:)"
                                            : @"startTask: launch failure (-launch raises)";
                CHECK(name, {
                    [p->outputText.text setString:@""];
                    p.outputPipe = [NSPipe pipe]; p.inputPipe = [NSPipe pipe];
                    p.texTask = [NSTask new];
                    BOOL result = [p startTask:p.texTask running:bad withArgs:[NSMutableArray array]
                         inDirectoryContaining:[dir stringByAppendingPathComponent:@"doc.tex"] withEngine:LatexEngine];
                    ok = (result == FALSE) && (p.texTask == nil) && [p->outputText.text containsString:bad];
                    detail = [NSString stringWithFormat:@"result=%d texTask=%@ console=%@", result, p.texTask, p->outputText.text];
                });
                CHECK([name stringByAppendingString:@", bibTask and indexTask"], {
                    p.outputPipe = [NSPipe pipe]; p.inputPipe = [NSPipe pipe];
                    p.bibTask = [NSTask new];
                    BOOL r1 = [p startTask:p.bibTask running:bad withArgs:[NSMutableArray array]
                     inDirectoryContaining:[dir stringByAppendingPathComponent:@"doc.tex"] withEngine:BibtexEngine];
                    p.outputPipe = [NSPipe pipe]; p.inputPipe = [NSPipe pipe];
                    p.indexTask = [NSTask new];
                    BOOL r2 = [p startTask:p.indexTask running:bad withArgs:[NSMutableArray array]
                     inDirectoryContaining:[dir stringByAppendingPathComponent:@"doc.tex"] withEngine:IndexEngine];
                    ok = !r1 && !r2 && p.bibTask == nil && p.indexTask == nil;
                });
            }
            atLeastHighSierra = YES;

            // Unlaunched tasks must not be terminated or signalled (A2, A3).
            CHECK(@"tex task shutdown never calls kill() with pid 0 (GhostScript script)", {
                [killCalls removeAllObjects];
                p->theScript = kTypesetViaGhostScript;
                p.texTask = [NSTask new];
                [p shutDownTexTask];
                BOOL zero = NO;
                for (NSArray *call in killCalls) if ([call[0] intValue] <= 0) zero = YES;
                ok = !zero && p.texTask == nil;
                detail = [NSString stringWithFormat:@"kill calls %@", killCalls];
            });
            CHECK(@"tex task shutdown with an unlaunched task (pdfTeX script)", {
                p->theScript = kTypesetViaPDFTeX;
                p.texTask = [NSTask new];
                [p shutDownTexTask];
                ok = p.texTask == nil;
            });
            CHECK(@"killRunningTasks with unlaunched bib, index and MetaFont tasks", {
                [killCalls removeAllObjects];
                p.bibTask = [NSTask new]; p.indexTask = [NSTask new]; p.metaFontTask = [NSTask new];
                [p killRunningTasks];
                ok = p.bibTask == nil && p.indexTask == nil && p.metaFontTask == nil && killCalls.count == 0;
            });

            // killRunningTasks must stop a running TeX task (Abort, new typesetting job).
            CHECK(@"killRunningTasks stops a running TeX task", {
                NSTask *child = [NSTask new];
                child.launchPath = @"/bin/sleep";
                child.arguments = @[@"30"];
                [child launch];
                ownChild = child.processIdentifier;
                p->theScript = kTypesetViaPDFTeX;
                p.texTask = child;
                NSDate *start = [NSDate date];
                [p killRunningTasks];
                [child waitUntilExit];
                NSTimeInterval elapsed = -[start timeIntervalSinceNow];
                ok = p.texTask == nil && !child.isRunning && elapsed < 2.0;
                detail = [NSString stringWithFormat:@"texTask=%@ running=%d elapsed %.2f s",
                          p.texTask, child.isRunning, elapsed];
                ownChild = -1;
            });

            // Bounded wait (A4): a child that ignores SIGTERM is killed after the deadline.
            CHECK(@"killRunningTasks stops waiting for a task that ignores SIGTERM", {
                NSTask *child = [NSTask new];
                NSPipe *pipe = [NSPipe pipe];
                child.launchPath = @"/bin/sh";
                child.arguments = @[@"-c", @"trap '' TERM; echo ready; exec /bin/sleep 3"];
                child.standardOutput = pipe;
                [child launch];
                ownChild = child.processIdentifier;
                [[pipe fileHandleForReading] availableData];
                p.bibTask = child;
                NSDate *start = [NSDate date];
                [p killRunningTasks];
                NSTimeInterval elapsed = -[start timeIntervalSinceNow];
                [child waitUntilExit];
                ok = elapsed < 2.0 && child.terminationReason == NSTaskTerminationReasonUncaughtSignal
                    && child.terminationStatus == SIGKILL;
                detail = [NSString stringWithFormat:@"elapsed %.2f s, reason %ld, status %d",
                          elapsed, (long)child.terminationReason, child.terminationStatus];
                ownChild = -1;
            });

            // Engine command parsing (A7).
            CHECK(@"separate:into: with quoted and lone-quote arguments", {
                NSMutableArray *args = [NSMutableArray array];
                NSString *engine = [p separate:@"prog \"a b\" c \"d\"" into:args];
                BOOL quoted = [engine isEqualToString:@"prog"] && [args isEqualToArray:@[@"a b", @"c", @"d"]];
                [args removeAllObjects];
                engine = [p separate:@"bibtex \"" into:args];
                BOOL lone = [engine isEqualToString:@"bibtex"] && args.count == 0;
                [args removeAllObjects];
                engine = [p separate:@"bibtex \" x\"" into:args];
                BOOL reopened = [engine isEqualToString:@"bibtex"] && [args isEqualToArray:@[@" x"]];
                ok = quoted && lone && reopened;
                detail = [NSString stringWithFormat:@"quoted=%d lone=%d reopened=%d", quoted, lone, reopened];
            });

            // First-line %& commands (A6).
            CHECK(@"UseOldHeadingCommands with an empty document", {
                probePreferences.values[UseOldHeadingCommandsKey] = @YES;
                p->theScript = kTypesetViaGhostScript;
                [p oldHeadingFor:@""];
                BOOL empty = p->theScript == kTypesetViaGhostScript;
                [p oldHeadingFor:@"%&pdflatex\n\\relax\n"];
                ok = empty && p->theScript == kTypesetViaPDFTeX && p->withLatex;
            });

            // Save completion (A8).
            CHECK(@"saveForStatistics:didSave:contextInfo: contains exceptions", {
                p.statisticsRaise = YES;
                [p saveForStatistics:nil didSave:YES contextInfo:NULL];
                p.statisticsRaise = NO;
                ok = YES;
            });

            // Preferences undo (A5).
            CHECK(@"HtmlHomeChanged: undo restores HTML Home and keeps the TeX bin path", {
                ProbePreferencesController *c = [ProbePreferencesController new];
                c->_undoManager = [NSUndoManager new];
                c->_undoManager.groupsByEvent = NO;
                c->_HtmlHomeField = [ProbeText new];
                [c->_HtmlHomeField.text setString:@"  /new/home \n"];
                [probePreferences.values removeAllObjects];
                probePreferences.values[TetexBinPath] = @"/Library/TeX/texbin";
                probePreferences.values[HtmlHomeKey] = @"/old/home";
                [c->_undoManager beginUndoGrouping];
                [c HtmlHomeChanged:nil];
                [c->_undoManager endUndoGrouping];
                BOOL changed = [probePreferences.values[HtmlHomeKey] isEqualToString:@"/new/home"];
                [c->_undoManager undo];
                ok = changed && [probePreferences.values[HtmlHomeKey] isEqualToString:@"/old/home"]
                    && [probePreferences.values[TetexBinPath] isEqualToString:@"/Library/TeX/texbin"];
                detail = [NSString stringWithFormat:@"after undo %@", probePreferences.values];
            });
        }
    }
    return failures ? 1 : 0;
}
'''
for key, value in pieces.items():
    program = program.replace('\n' + key + '\n', '\n' + value + '\n')

failed = False
# Every undo registration in the preferences must restore the key it reads.
preferences = (sources / 'TSPreferences.m').read_text(errors='replace')
mismatched = []
for m in re.finditer(r'prepareWithInvocationTarget:\s*SUD\]\s*\w+:\s*\[SUD \w+ForKey:\s*(\w+)\]\s*forKey:\s*(\w+)\]',
                     preferences):
    if m.group(1) != m.group(2):
        mismatched.append(f'{m.group(1)} -> {m.group(2)}')
if mismatched:
    failed = True
    print('FAIL: preference undo registrations use another key:', ', '.join(mismatched))
else:
    print('PASS: every preference undo registration restores the key it reads')

temporary = Path(subprocess.check_output(['mktemp', '-d', '/tmp/texshop-typeset.XXXXXX'], text=True).strip())
try:
    (temporary / 'test.m').write_text(program)
    bad = temporary / 'not-an-executable'
    bad.write_bytes(b'\x00\x01\x02 not a program\n')
    bad.chmod(0o755)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', str(temporary / 'test.m'),
                    '-o', str(temporary / 'test')], check=True)
    environment = {k: v for k, v in os.environ.items() if k != 'PATH'}
    for env in (dict(os.environ), environment):
        if subprocess.run([str(temporary / 'test'), str(bad), str(temporary)], env=env).returncode != 0:
            failed = True
finally:
    shutil.rmtree(temporary)
sys.exit(1 if failed else 0)
