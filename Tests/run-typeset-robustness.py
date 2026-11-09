#!/usr/bin/env python3
"""Exercise the real typesetting/save-path methods against inputs that used to raise
exceptions or signal the wrong process.

Usage: run-typeset-robustness.py [ROOT]
ROOT defaults to the repository containing this script; the methods are read from
ROOT/Sources. Preferences are a dictionary-backed stub (NSUserDefaults is never used),
kill() is routed through a recorder that only forwards signals to the child process
and the process group this test starts itself, and the program is run once with PATH
and once without it. Job tasks started by the test stop on their own after 20 seconds."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
from production_fragments import method as production_method, verify_embedded
fragments=[]
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
    fragment=production_method(src,signature)
    fragments.append(('complete method:'+signature,src,fragment))
    return fragment


def block(name, after, marker):
    """The statement starting at `marker` (searched after `after`) up to its closing brace."""
    src = (sources / name).read_text(errors='replace')
    start = src.index(marker, src.index(after))
    fragment=src[start:matching_brace(src, src.index('{', start))]
    fragments.append(('statement block:'+marker,src,fragment));return fragment


def optional_method(name, signature):
    """Like method(), but empty when the source does not define it."""
    try:
        return method(name, signature)
    except ValueError:
        return ''


def span(name, after, start_marker, end_marker):
    src = (sources / name).read_text(errors='replace')
    start = src.index(start_marker, src.index(after))
    end = src.index(end_marker, start) + len(end_marker)
    fragment=src[start:end]
    fragments.append(('statement span:'+start_marker,src,fragment));return fragment


jobs = 'TSDocument-Jobs.m'
pieces = {
    'ENVIRONMENT': method(jobs, '- (NSDictionary *)environmentForSubTask'),
    'SCRAP_ENVIRONMENT': method('TSDocument-Scrap.m', '- (NSDictionary *)environmentWithNewPath:'),
    'HELP_PATH': span('HelpDocuments.m', '- (IBAction)displayHelpForPackage:',
                      'displayPackageHelpTask = nil;\n\t}', '[env setObject: path forKey: @"PATH"];')
                 .split('\n', 2)[2],
    'START_TASK': method(jobs, '- (BOOL) startTask: (NSTask*) task running:'),
    'KILL_RUNNING_TASKS': method(jobs, '- (void)killRunningTasks'),
    'PROCESS_GROUP_HELPERS': '\n'.join(optional_method(jobs, signature) for signature in (
        '- (void)recordProcessGroupOfTask:', '- (void)forgetProcessGroupOfTask:', '- (void)stopJobTask:')),
    'TEX_TASK_SHUTDOWN': block(jobs, '- (void)killRunningTasks', 'if (self.texTask != nil) {'),
    'SEPARATE': method(jobs, '- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args'),
    'OLD_HEADING': block(jobs, '- (void) saveFinished:',
                         'if ((! done) && ([SUD boolForKey:UseOldHeadingCommandsKey])) {'),
    'SAVE_FOR_STATISTICS': method('TSDocument.m', '- (void)saveForStatistics:'),
    'HTML_HOME_CHANGED': method('TSPreferences.m', '- (IBAction)HtmlHomeChanged:(id)sender'),
}

program = r'''
#import <Cocoa/Cocoa.h>
#import "TSPreferenceInput.h"
#import <objc/runtime.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

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

// kill() recorder: signals reach only the child and the process group started by this
// test. Distinct calls are recorded per check, and every call over the whole run.
static NSMutableOrderedSet *killCalls, *allKillCalls;
static pid_t ownChild = -1, ownGroup = -1;
static int real_kill(pid_t pid, int sig) { return kill(pid, sig); }
static int probe_kill(pid_t pid, int sig) {
    [killCalls addObject:@[@(pid), @(sig)]];
    [allKillCalls addObject:@[@(pid), @(sig)]];
    if (pid > 0 && pid == ownChild)
        return kill(pid, sig);
    if (ownGroup > 1 && ownGroup != getpgrp() && pid == -ownGroup)
        return kill(pid, sig);
    errno = ESRCH;
    return -1;
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
- (void)fixMacroMenu;
- (void)showStatistics:sender;
@end

@implementation Probe
- (void)checkATaskStatusFromTerminationRoutine:(id)task { }
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
PROCESS_GROUP_HELPERS
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
    ProbeText *_HtmlHomeField;
}
@end
@implementation ProbePreferencesController
- (BOOL)commitPreferenceField:(id)field showError:(BOOL)showError reflect:(BOOL)reflect {
    TSPreferenceInput *rule=[[TSPreferenceInput alloc]initWithKey:HtmlHomeKey kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil];
    TSPreferenceInputValue *value=[rule validatedValue:[field stringValue]];
    if (value == nil) return NO;
    [value storeInDefaults:(id)SUD forKey:rule.key];return YES;
}
HTML_HOME_CHANGED
@end

static int failures;
static void report(BOOL ok, NSString *name, NSString *detail) {
    if (ok) printf("PASS: %s\n", name.UTF8String);
    else { failures++; printf("FAIL: %s: %s\n", name.UTF8String, detail.UTF8String); }
}
static unsigned long long fileSize(NSString *path) {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileSize];
}

// Ensure the group started by a check is gone before the next check.
static void reapOwnGroup(NSTask *task) {
    if (ownGroup > 1 && ownGroup != getpgrp() && real_kill(-ownGroup, 0) == 0)
        real_kill(-ownGroup, SIGKILL);
    if (task.processIdentifier > 0)
        [task waitUntilExit];
    for (int i = 0; i < 200 && ownGroup > 1 && real_kill(-ownGroup, 0) == 0; i++)
        usleep(10000);
    ownChild = -1;
    ownGroup = -1;
}

#define CHECK(title, ...) do { NSString *detail = @"condition not met"; BOOL ok = NO; \
    @try { __VA_ARGS__ } @catch (NSException *e) { ok = NO; detail = [NSString stringWithFormat:@"exception %@: %@", e.name, e.reason]; } \
    report(ok, title, detail); } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *bad = [NSString stringWithUTF8String:argv[1]];
        NSString *dir = [NSString stringWithUTF8String:argv[2]];
        NSString *job = [NSString stringWithUTF8String:argv[3]];
        const char *envPath = getenv("PATH");
        NSString *base = envPath ? [NSString stringWithUTF8String:envPath] : @"/usr/bin:/bin:/usr/sbin:/sbin";
        NSString *label = envPath ? @"with PATH" : @"without PATH";
        probePreferences = [ProbePreferences new];
        killCalls = [NSMutableOrderedSet orderedSet];
        allKillCalls = [NSMutableOrderedSet orderedSet];
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

            // A job whose processes ignore SIGTERM: the task's own child keeps writing a
            // heartbeat, while the task either ignores SIGTERM too or exits on it first.
            // Stopping the job must stop the whole process group the task was started in.
            int scripts[] = { kTypesetViaGhostScript, kTypesetViaPDFTeX };
            for (int s = 0; s < 2; s++) for (int exits = 0; exits <= 1; exits++) {
                NSString *name = [NSString stringWithFormat:@"killRunningTasks stops the process group of a TeX task (%@ script, task %@ SIGTERM)",
                                  scripts[s] == kTypesetViaGhostScript ? @"GhostScript" : @"pdfTeX",
                                  exits ? @"exits on" : @"ignores"];
                CHECK(name, {
                    [killCalls removeAllObjects];
                    NSString *pidFile = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"job-%d-%d.pid", s, exits]];
                    NSString *beat = [pidFile stringByAppendingString:@".beat"];
                    p.outputPipe = [NSPipe pipe]; p.inputPipe = [NSPipe pipe];
                    p->theScript = scripts[s];
                    p.texTask = [NSTask new];
                    NSTask *task = p.texTask;
                    BOOL launched = [p startTask:task running:job withArgs:[@[pidFile, beat, exits ? @"1" : @"0"] mutableCopy]
                           inDirectoryContaining:[dir stringByAppendingPathComponent:@"doc.tex"] withEngine:LatexEngine];
                    pid_t pid = task.processIdentifier;
                    pid_t group = pid > 1 ? getpgid(pid) : -1;
                    if (!launched || pid <= 1 || group != pid || group == getpgrp()) {
                        detail = [NSString stringWithFormat:@"launched=%d pid=%d group=%d own group=%d", launched, pid, group, getpgrp()];
                        if (pid > 1) { ownChild = pid; real_kill(pid, SIGKILL); }
                        reapOwnGroup(launched ? task : nil);
                    } else {
                        ownChild = pid;
                        ownGroup = group;
                        for (int i = 0; i < 200 && fileSize(beat) == 0; i++)
                            usleep(10000);
                        BOOL started = fileSize(beat) > 0;
                        NSDate *start = [NSDate date];
                        [p killRunningTasks];
                        NSTimeInterval elapsed = -[start timeIntervalSinceNow];
                        // The heartbeat must stop and the group must be gone within 2 seconds.
                        BOOL stopped = NO, gone = NO;
                        unsigned long long before = fileSize(beat), after = before;
                        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
                        while (!(stopped && gone) && [deadline timeIntervalSinceNow] > 0) {
                            usleep(250000);
                            after = fileSize(beat);
                            stopped = (after == before);
                            gone = real_kill(-group, 0) != 0;
                            before = after;
                        }
                        BOOL foreign = NO;
                        for (NSArray *call in killCalls)
                            if ([call[0] intValue] != pid && [call[0] intValue] != -group) foreign = YES;
                        ok = started && stopped && gone && !foreign && p.texTask == nil && elapsed < 2.0;
                        detail = [NSString stringWithFormat:@"started=%d heartbeat stopped=%d (%llu bytes) group gone=%d "
                                  "foreign signal=%d texTask=%@ elapsed %.2f s, kill calls %@",
                                  started, stopped, after, gone, foreign, p.texTask, elapsed, killCalls];
                        reapOwnGroup(task);
                    }
                });
            }

            // Once a task has been cleaned up, its process group is no longer signalled:
            // the group id may belong to an unrelated group by then.
            CHECK(@"killRunningTasks does not signal the group of a task that was cleaned up", {
#ifdef HAVE_PROCESS_GROUP_HELPERS
                p.outputPipe = [NSPipe pipe]; p.inputPipe = [NSPipe pipe];
                p.texTask = [NSTask new];
                NSTask *task = p.texTask;
                BOOL launched = [p startTask:task running:@"/usr/bin/true" withArgs:[NSMutableArray array]
                       inDirectoryContaining:[dir stringByAppendingPathComponent:@"doc.tex"] withEngine:LatexEngine];
                BOOL recorded = objc_getAssociatedObject(task, @selector(recordProcessGroupOfTask:)) != nil;
                if (launched)
                    [task waitUntilExit];
                [p forgetProcessGroupOfTask:task];
                [killCalls removeAllObjects];
                [p killRunningTasks];
                ok = launched && recorded && killCalls.count == 0 && p.texTask == nil;
                detail = [NSString stringWithFormat:@"launched=%d recorded=%d kill calls %@", launched, recorded, killCalls];
#else
                detail = @"process group helpers are missing";
#endif
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

            // Immediate HTML Home persistence (A5); full validator lifecycle is tested separately.
            CHECK(@"HtmlHomeChanged: saves HTML Home immediately and keeps the TeX bin path", {
                ProbePreferencesController *c = [ProbePreferencesController new];
                c->_HtmlHomeField = [ProbeText new];
                [c->_HtmlHomeField.text setString:@"  /new/home \n"];
                [probePreferences.values removeAllObjects];
                probePreferences.values[TetexBinPath] = @"/Library/TeX/texbin";
                probePreferences.values[HtmlHomeKey] = @"/old/home";
                [c HtmlHomeChanged:nil];
                BOOL changed = [probePreferences.values[HtmlHomeKey] isEqualToString:@"/new/home"];
                ok = changed && [probePreferences.values[HtmlHomeKey] isEqualToString:@"/new/home"]
                    && [probePreferences.values[TetexBinPath] isEqualToString:@"/Library/TeX/texbin"];
                detail = [NSString stringWithFormat:@"after commit %@", probePreferences.values];
            });
        }

        // No signal of any kind may reach TeXShop's own process group or process.
        CHECK(([NSString stringWithFormat:@"no kill() call targets the test's own process group (%@)", label]), {
            NSMutableArray *bad = [NSMutableArray array];
            for (NSArray *call in allKillCalls) {
                pid_t target = [call[0] intValue];
                if (target == 0 || target == -1 || target == getpgrp() || target == -getpgrp() || target == getpid())
                    [bad addObject:call];
            }
            ok = bad.count == 0;
            detail = [NSString stringWithFormat:@"calls %@", bad];
        });
    }
    return failures ? 1 : 0;
}
'''
if pieces['PROCESS_GROUP_HELPERS'].strip():
    program = '#define HAVE_PROCESS_GROUP_HELPERS\n' + program
for key, value in pieces.items():
    program = program.replace('\n' + key + '\n', '\n' + value + '\n')

verify_embedded(program,[f for f in fragments if not f[0].startswith('statement span:')]+[('help path fragment',(sources/'HelpDocuments.m').read_text(errors='replace'),pieces['HELP_PATH'])])

# A job task for the process group checks: argv[1] receives the pid of a child that
# ignores SIGTERM and appends to argv[2] every 10 ms; the task itself ignores SIGTERM
# unless argv[3] is 1. Both stop on their own after 20 seconds.
job_program = r'''
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 4) return 2;
    signal(SIGTERM, SIG_IGN);
    pid_t child = fork();
    if (child == 0) {
        FILE *beat = fopen(argv[2], "a");
        if (!beat) _exit(1);
        for (int i = 0; i < 2000; i++) { fputc('.', beat); fflush(beat); usleep(10000); }
        _exit(0);
    }
    if (child < 0) return 1;
    FILE *f = fopen(argv[1], "w");
    if (f) { fprintf(f, "%d", child); fclose(f); }
    if (atoi(argv[3])) signal(SIGTERM, SIG_DFL);
    alarm(20);
    for (;;) pause();
}
'''

failed = False
# A task's recorded process group is dropped when the task is cleaned up after it exits,
# before the termination routine can return.
routine = method(jobs, '- (void)checkATaskStatusFromTerminationRoutine:')
forget = routine.find('[self forgetProcessGroupOfTask: theTask];')
if forget < 0 or 0 <= routine.find('return', 0, forget):
    failed = True
    print('FAIL: checkATaskStatusFromTerminationRoutine: drops the process group of the task first')
else:
    print('PASS: checkATaskStatusFromTerminationRoutine: drops the process group of the task first')

temporary = Path(subprocess.check_output(['mktemp', '-d', '/tmp/texshop-typeset.XXXXXX'], text=True).strip())
try:
    (temporary / 'test.m').write_text(program)
    bad = temporary / 'not-an-executable'
    bad.write_bytes(b'\x00\x01\x02 not a program\n')
    bad.chmod(0o755)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(sources), str(sources / 'TSPreferenceInput.m'), str(temporary / 'test.m'),
                    '-o', str(temporary / 'test')], check=True)
    (temporary / 'job.c').write_text(job_program)
    subprocess.run(['xcrun', 'clang', '-w', str(temporary / 'job.c'), '-o', str(temporary / 'job')], check=True)
    environment = {k: v for k, v in os.environ.items() if k != 'PATH'}
    for env in (dict(os.environ), environment):
        if subprocess.run([str(temporary / 'test'), str(bad), str(temporary), str(temporary / 'job')],
                          env=env).returncode != 0:
            failed = True
finally:
    shutil.rmtree(temporary)
sys.exit(1 if failed else 0)
