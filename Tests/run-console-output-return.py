#!/usr/bin/env python3
"""Return in the console output answers TeX, in the Experiment console and in the normal console.

Key events are posted to the application queue, taken from it as AppKit takes them, and given to
real windows, so they go through NSTextView key handling, the production TSConsoleOutputReturn
delegate and the production send methods to real processes: TeX (pdftex) and a shell that reports
each line it reads. The Experiment console is the production controller. The normal console is a
probe with the production -doTexCommand:, -sendConsoleLine: and the delegate wiring of TSDocument.

Checks: an unmodified Return or keypad Enter (also with Caps Lock) in the output sends one empty
line, moves the focus to the input field and keeps the text typed there, unsent and unselected;
clicking into the output sends nothing; Return with Shift, Option, Control or Command, other keys,
and Return after the job stopped send nothing; a closed input pipe is reported and keeps the focus;
selected output stays selected and copyable; two Experiment consoles and a normal console running
at once each send only to their own process; TeX stopped at three errors resumes and writes its PDF
when answered from the output and from the input field. No window is shown and no TeXShop setting
is read. --mutation=NAME undoes one part, and the test must then fail."""
from pathlib import Path
import argparse, os, subprocess, tempfile
from source_tree import include_args
from experiment_console_source import advanced_find_sources

MUTATIONS = ['no-experiment-delegate', 'no-normal-delegate', 'send-field', 'modifiers', 'no-focus',
             'select-draft', 'send-when-stopped', 'normal-always-send', 'sigpipe',
             'unguarded-descriptor', 'ignore-fcntl-failure']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=MUTATIONS)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]


def cut(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)]


def mutate(text, old, new):
    assert old in text, old
    return text.replace(old, new, 1)


enc = (root / 'Sources/App/TSEncodingSupport.m').read_text(encoding='latin1')
helpers = cut(enc, '// UTF-8 in which each byte that does not start or continue a valid character is replaced',
              '// The byte order mark that starts data')
japanese = cut(enc, '// Japanese encodings read the byte 0x5C', '- (BOOL)ptexUtfOutputCheck:')
filters = enc[enc.index('// replace backslashes by yens'):].rstrip() + '\n'
controller = (root / 'Sources/Typesetting/TSExperimentConsoleController.m').read_text() \
    .replace('#import "TSEncodingSupport.h"', '').replace('#import "globals.h"', '')
delegate = (root / 'Sources/Typesetting/TSConsoleOutput.m').read_text()
header = (root / 'Sources/Typesetting/TSConsoleOutput.h').read_text()
job = (root / 'Sources/Typesetting/TSExperimentJob.m').read_text()
doc = (root / 'Sources/Document/TSDocument.m').read_text(encoding='latin1')
filter_method = cut(doc, '- (NSString *)filterBackslashes:', '// The code below to handle line break algorithms')
wiring_end = '[outputText setDelegate: self.consoleOutputReturn];'
wiring = doc[doc.index('\t__weak TSDocument *weakSelf = self;\n\tself.consoleOutputReturn'):doc.index(wiring_end) + len(wiring_end)]
wiring = wiring.replace('TSDocument', 'Probe')
jobs = (root / 'Sources/Typesetting/TSDocument-Jobs.m').read_text(encoding='latin1')
command = jobs[jobs.index('- (void) doTexCommand: sender'):]
command = command[:command.index('\n}\n', command.index('- (BOOL) sendConsoleLine:')) + 3]

m = args.mutation
if m == 'no-experiment-delegate':
    controller = mutate(controller, 'text.delegate = self.outputReturn;', '')
elif m == 'no-normal-delegate':
    wiring = mutate(wiring, '[outputText setDelegate: self.consoleOutputReturn];', '')
elif m == 'send-field':
    controller = mutate(controller, '[weakSelf sendLine:@""]', '[weakSelf sendLine:weakSelf.commandField.stringValue]')
elif m == 'modifiers':
    delegate = mutate(delegate, 'if (event.modifierFlags & modifiers)\n        return NO;', '')
elif m == 'no-focus':
    delegate = mutate(delegate, '[window makeFirstResponder:field]', 'NO')
elif m == 'select-draft':
    delegate = mutate(delegate, 'editor.selectedRange = NSMakeRange(editor.string.length, 0);', '')
elif m == 'send-when-stopped':
    controller = mutate(controller, 'canSend:^BOOL{ return weakSelf.job.active; }', 'canSend:^BOOL{ return YES; }')
    delegate = mutate(delegate, '!field.enabled || ', '')
elif m == 'sigpipe':
    header = mutate(header, 'if (fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) == -1) {', 'if (NO) {')
elif m == 'unguarded-descriptor':
    header = mutate(header, '    @try {\n        if (fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) == -1) {',
                    '    int descriptor = handle.fileDescriptor;\n    @try {\n        if (fcntl(descriptor, F_SETNOSIGPIPE, 1) == -1) {')
elif m == 'ignore-fcntl-failure':
    header = mutate(header, 'if (fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) == -1) {', 'if (fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) == -1 && NO) {')
elif m == 'normal-always-send':
    wiring = mutate(wiring, 'return document && document->typesetStart && document.inputPipe;', 'return YES;')

prefix = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSExperimentJob.h"
#import "TSColorSupport.h"
#import "TSEncodingSupport.h"
#import "TSConsoleOutput.h"
typedef enum { kNoFilterMode = 0, kMacJapaneseFilterMode = 1, kOtherJapaneseFilterMode = 2 } TSFilterMode;
static TSFilterMode g_shouldFilter = kNoFilterMode;
static NSString *yenString = @"\u00a5";
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static TSEncodingSupport *s; if (!s) s = [self new]; return s; }
HELPERS
JAPANESE
@end
FILTERS
static NSDictionary *liteColors;
static NSDictionary *darkColors;
@implementation TSColorSupport
+ (id)sharedInstance { static id s; if (!s) s = [self new]; return s; }
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{ return theme[key] ?: (dark ? NSColor.blackColor : NSColor.whiteColor); }
@end
@interface TestDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
@end
@implementation TestDefaults
- (NSString *)stringForKey:(NSString *)key { return @"Menlo"; }
- (float)floatForKey:(NSString *)key { return 12; }
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:@"ConsoleBehavior"] ? NO : YES; }
@end
#define SUD ((TestDefaults *)[TestDefaults new])
#define SourceColorChangedNotification @"SourceColorChanged"
#define ConsoleFontNameKey @"ConsoleFontName"
#define ConsoleFontSizeKey @"ConsoleFontSize"
#define ConsoleFontChangedNotification @"ConsoleFontChanged"
#define ConsoleBehaviorKey @"ConsoleBehavior"
#define BringPdfFrontOnTypesetKey @"BringPdfFront"
#define RedConsoleAfterErrorKey @"RedConsoleAfterError"
'''.replace('HELPERS', helpers).replace('JAPANESE', japanese).replace('FILTERS', filters)

probe = r'''
@implementation TSExperimentConsoleWindow (HeadlessOrdering)
- (BOOL)setFrameAutosaveName:(NSString *)name { return NO; }
- (void)makeKeyAndOrderFront:(id)sender { }
- (void)orderFront:(id)sender { }
- (void)orderBack:(id)sender { }
@end

// The normal console: the production send and wiring of TSDocument on a real window.
@interface Probe : NSObject {
@public
    BOOL typesetStart, consoleCleanStart;
    NSStringEncoding _encoding;
    NSWindow *outputWindow;
    NSTextView *outputText;
    NSTextField *texCommand;
}
@property (retain) NSFileHandle *writeHandle;
@property (retain) NSPipe *inputPipe;
@property (strong) TSConsoleOutputReturn *consoleOutputReturn;
@property (strong) NSTask *task;
@property (strong) NSMutableString *received;
@end
@implementation Probe
FILTERMETHOD
COMMAND
- (void)wire
{
WIRING
}
- (instancetype)init
{
    if (!(self = [super init])) return nil;
    _encoding = NSUTF8StringEncoding;
    _received = [NSMutableString string];
    outputWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    outputWindow.releasedWhenClosed = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 60, 500, 340)];
    outputText = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    outputText.editable = NO;
    outputText.selectable = YES;
    scroll.documentView = outputText;
    [outputWindow.contentView addSubview:scroll];
    texCommand = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 10, 460, 40)];
    texCommand.target = self;
    texCommand.action = @selector(doTexCommand:);
    [outputWindow.contentView addSubview:texCommand];
    TSConfigureConsoleInput(texCommand);
    [self wire];
    return self;
}
- (void)launch:(NSString *)path arguments:(NSArray *)arguments directory:(NSURL *)directory environment:(NSDictionary *)environment
{
    self.inputPipe = [NSPipe pipe];
    self.writeHandle = self.inputPipe.fileHandleForWriting;
    NSPipe *output = [NSPipe pipe];
    self.task = [NSTask new];
    self.task.executableURL = [NSURL fileURLWithPath:path];
    self.task.arguments = arguments;
    self.task.environment = environment;
    self.task.currentDirectoryURL = directory;
    self.task.standardInput = self.inputPipe;
    self.task.standardOutput = output;
    self.task.standardError = output;
    __weak Probe *weakSelf = self;
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        if (!data.length) handle.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            Probe *probe = weakSelf;
            [probe.received appendString:text];
            if (probe) TSAppendConsoleOutput(probe->outputText, text, nil);
        });
    };
    [self.task launchAndReturnError:NULL];
    typesetStart = YES;
    [outputWindow makeFirstResponder:texCommand];
}
- (void)finish
{
    if (self.task.running) [self.task terminate];
    [self.task waitUntilExit];
    typesetStart = NO;
    self.inputPipe = nil;
}
@end
'''.replace('FILTERMETHOD', filter_method).replace('COMMAND', command).replace('WIRING', wiring)

tests = r'''
static void require(BOOL ok, NSString *label) { if (!ok) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); } }
static void check(BOOL ok, NSString *label) { require(ok, label); printf("ok   %s\n", label.UTF8String); }
static void spin(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static BOOL waitFor(BOOL (^test)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!test() && end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return test();
}
static NSUInteger count(NSString *text, NSString *part) {
    return text.length ? [text componentsSeparatedByString:part].count - 1 : 0;
}
// Posts a key event, takes it from the queue as AppKit does (so it becomes the current event)
// and gives it to its window.
static void key(NSWindow *window, NSString *characters, unsigned short code, NSEventModifierFlags flags) {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
    [NSApp postEvent:event atStart:NO];
    for (;;) {
        NSEvent *next = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:2]
            inMode:NSDefaultRunLoopMode dequeue:YES];
        require(next != nil, @"posted key event arrives");
        if (next.type == NSEventTypeKeyDown && next.windowNumber == window.windowNumber) {
            require(NSApp.currentEvent == next, @"key event is the current event");
            [next.window sendEvent:next];
            return;
        }
        [NSApp sendEvent:next];
    }
}
static void returnKey(NSWindow *w) { key(w, @"\r", 36, 0); }
static NSURL *directory(void) {
    NSURL *d = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}
static NSString *const Echo = @"echo ready; while IFS= read -r l; do printf 'got:[%s]\\n' \"$l\"; done";
static NSString *const Closed = @"exec 0<&-; echo ready; sleep 20";
static NSDictionary *environment(void) {
    NSDictionary *e = NSProcessInfo.processInfo.environment;
    return @{@"PATH": [NSString stringWithFormat:@"%s:/usr/bin:/bin", TEXBIN], @"HOME": e[@"HOME"],
             @"CFFIXED_USER_HOME": e[@"CFFIXED_USER_HOME"]};
}
static TSExperimentConsoleController *experiment(NSString *script) {
    TSExperimentConsoleController *c = [TSExperimentConsoleController new];
    [c startExecutable:@"/bin/sh" arguments:@[@"-c", script] environment:environment() directory:directory()
              encoding:NSUTF8StringEncoding title:@"Return probe" completion:nil];
    check(waitFor(^BOOL{ return [c.outputText.string containsString:@"ready"]; }), @"Experiment job started");
    return c;
}
static BOOL fieldHasFocus(NSTextField *field) {
    return field.currentEditor != nil && field.window.firstResponder == field.currentEditor;
}
static void typeIntoField(NSWindow *w, NSTextField *field, NSString *text) {
    [w makeFirstResponder:field];
    for (NSUInteger i = 0; i < text.length; i++) key(w, [text substringWithRange:NSMakeRange(i, 1)], 7, 0);
    check([field.currentEditor.string isEqualToString:text], @"typed draft reaches the input field");
}
// The checks shared by both consoles, on a running job that reports each line it reads.
static void exerciseOutputReturn(NSString *name, NSWindow *w, NSTextView *output, NSTextField *field, NSString *(^seen)(void)) {
    typeIntoField(w, field, @"x");
    [w makeFirstResponder:output];                            // what a click into the output does
    spin(0.3);
    check(count(seen(), @"got:[") == 0, [name stringByAppendingString:@": focusing the output sends nothing"]);
    returnKey(w);
    check(waitFor(^BOOL{ return count(seen(), @"got:[") >= 1; }), [name stringByAppendingString:@": Return in the output sends"]);
    spin(0.4);
    check(count(seen(), @"got:[]") == 1 && count(seen(), @"got:[") == 1, [name stringByAppendingString:@": exactly one empty line, not the draft"]);
    check(fieldHasFocus(field), [name stringByAppendingString:@": focus moves to the input field"]);
    check([field.stringValue isEqualToString:@"x"] && [field.currentEditor.string isEqualToString:@"x"], [name stringByAppendingString:@": draft kept"]);
    check(NSEqualRanges(field.currentEditor.selectedRange, NSMakeRange(1, 0)), [name stringByAppendingString:@": draft not selected, insertion point after it"]);

    NSArray *keys = @[@[@"\003", @76, @(NSEventModifierFlagNumericPad | NSEventModifierFlagFunction), @"keypad Enter"],
                      @[@"\r", @36, @(NSEventModifierFlagCapsLock), @"Return with Caps Lock"]];
    NSUInteger expected = 1;
    for (NSArray *k in keys) {
        [w makeFirstResponder:output];
        key(w, k[0], [k[1] unsignedShortValue], [k[2] unsignedLongValue]);
        expected++;
        check(waitFor(^BOOL{ return count(seen(), @"got:[]") == expected; }), [NSString stringWithFormat:@"%@: %@ in the output sends", name, k[3]]);
        check(fieldHasFocus(field), [NSString stringWithFormat:@"%@: %@ moves the focus", name, k[3]]);
    }
    NSArray *ignored = @[@[@"\r", @36, @(NSEventModifierFlagShift), @"Shift-Return"],
                         @[@"\r", @36, @(NSEventModifierFlagOption), @"Option-Return"],
                         @[@"\r", @36, @(NSEventModifierFlagControl), @"Control-Return"],
                         @[@"\r", @36, @(NSEventModifierFlagCommand), @"Command-Return"],
                         @[@"a", @0, @0, @"a letter"]];
    for (NSArray *k in ignored) {
        [w makeFirstResponder:output];
        key(w, k[0], [k[1] unsignedShortValue], [k[2] unsignedLongValue]);
        spin(0.2);
        check(count(seen(), @"got:[") == expected, [NSString stringWithFormat:@"%@: %@ in the output sends nothing", name, k[3]]);
        check(!fieldHasFocus(field) && [field.stringValue isEqualToString:@"x"], [NSString stringWithFormat:@"%@: %@ leaves the input alone", name, k[3]]);
    }

    // Selected output stays selected and copyable while Return answers and output arrives.
    [w makeFirstResponder:output];
    NSRange chosen = NSMakeRange(0, 5);
    output.selectedRange = chosen;
    returnKey(w);
    expected++;
    check(waitFor(^BOOL{ return count(seen(), @"got:[]") == expected; }), [name stringByAppendingString:@": Return with output selected sends"]);
    spin(0.2);
    check(NSEqualRanges(output.selectedRange, chosen), [name stringByAppendingString:@": output selection kept while output arrives"]);
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    check([output validateMenuItem:copyItem] && [[output.string substringWithRange:output.selectedRange] isEqualToString:[output.string substringWithRange:chosen]],
          [name stringByAppendingString:@": selected output can be copied"]);

    // Return in the input field still sends what it holds.
    returnKey(w);
    check(waitFor(^BOOL{ return count(seen(), @"got:[x]") == 1; }), [name stringByAppendingString:@": Return in the input sends the draft"]);
    check(field.stringValue.length == 0, [name stringByAppendingString:@": input cleared after sending"]);
}

static void realTeX(void) {
    NSString *source = @"\\pdfoutput=1\n\\errmessage{FIRST}\n\\errmessage{SECOND}\n\\errmessage{THIRD}\n\\message{PASSED-ALL}Hello\\bye\n";
    // Experiment console.
    TSExperimentConsoleController *c = [TSExperimentConsoleController new];
    NSURL *dir = directory();
    [source writeToURL:[dir URLByAppendingPathComponent:@"file.tex"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    __block BOOL done = NO, pdf = NO;
    [c startExecutable:[NSString stringWithFormat:@"%s/pdftex", TEXBIN] arguments:@[@"-interaction=errorstopmode", @"file.tex"]
           environment:environment() directory:dir encoding:NSUTF8StringEncoding title:@"TeX" completion:^(NSURL *url) {
        done = YES; pdf = [[NSFileManager defaultManager] fileExistsAtPath:url.path]; }];
    NSWindow *w = c.window;
    for (NSString *error in @[@"FIRST", @"SECOND", @"THIRD"]) {
        check(waitFor(^BOOL{ return [c.outputText.string containsString:error] && [c.outputText.string hasSuffix:@"? "]; }),
              [@"Experiment TeX stops at " stringByAppendingString:error]);
        if ([error isEqual:@"SECOND"]) {
            [w makeFirstResponder:c.commandField];
            returnKey(w);
        } else {
            if ([error isEqual:@"FIRST"]) typeIntoField(w, c.commandField, @"x");
            [w makeFirstResponder:c.outputText];
            returnKey(w);
            if ([error isEqual:@"FIRST"]) {
                check([c.commandField.stringValue isEqualToString:@"x"], @"Experiment TeX: draft x kept, not sent");
                c.commandField.stringValue = @"";
            }
        }
    }
    check(waitFor(^BOOL{ return done; }) && pdf && [c.outputText.string containsString:@"PASSED-ALL"],
          @"Experiment TeX resumes from output and input Returns and writes its PDF");
    [c invalidate];

    // Normal console.
    Probe *p = [Probe new];
    NSURL *dir2 = directory();
    [source writeToURL:[dir2 URLByAppendingPathComponent:@"doc.tex"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [p launch:[NSString stringWithFormat:@"%s/pdftex", TEXBIN] arguments:@[@"-interaction=errorstopmode", @"doc.tex"] directory:dir2 environment:environment()];
    for (NSString *error in @[@"FIRST", @"SECOND", @"THIRD"]) {
        check(waitFor(^BOOL{ return [p.received containsString:error] && [p.received hasSuffix:@"? "]; }),
              [@"normal TeX stops at " stringByAppendingString:error]);
        [p->outputWindow makeFirstResponder:[error isEqual:@"SECOND"] ? (id)p->texCommand : p->outputText];
        returnKey(p->outputWindow);
    }
    check(waitFor(^BOOL{ return !p.task.running; }), @"normal TeX finishes");
    spin(0.2);
    check([p.received containsString:@"PASSED-ALL"] && [[NSFileManager defaultManager] fileExistsAtPath:[dir2 URLByAppendingPathComponent:@"doc.pdf"].path],
          @"normal TeX resumes from output and input Returns and writes its PDF");
    [p finish];
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    liteColors = @{}; darkColors = @{};

    // Experiment console.
    TSExperimentConsoleController *a = experiment(Echo);
    exerciseOutputReturn(@"Experiment", a.window, a.outputText, a.commandField, ^NSString *{ return a.outputText.string; });

    // Normal console.
    Probe *p = [Probe new];
    [p launch:@"/bin/sh" arguments:@[@"-c", Echo] directory:directory() environment:environment()];
    check(waitFor(^BOOL{ return [p.received containsString:@"ready"]; }), @"normal job started");
    exerciseOutputReturn(@"normal", p->outputWindow, p->outputText, p->texCommand, ^NSString *{ return p.received; });

    // Two Experiment consoles and a normal console at once: each sends only to its own process.
    TSExperimentConsoleController *b = experiment(Echo);
    NSUInteger aBefore = count(a.outputText.string, @"got:[]"), pBefore = count(p.received, @"got:[]");
    [b.window makeFirstResponder:b.outputText];
    returnKey(b.window);
    check(waitFor(^BOOL{ return count(b.outputText.string, @"got:[]") == 1; }), @"second Experiment console sends to its job");
    [p->outputWindow makeFirstResponder:p->outputText];
    returnKey(p->outputWindow);
    check(waitFor(^BOOL{ return count(p.received, @"got:[]") == pBefore + 1; }), @"normal console sends to its job");
    spin(0.3);
    check(count(a.outputText.string, @"got:[]") == aBefore && count(b.outputText.string, @"got:[]") == 1 &&
          count(p.received, @"got:[]") == pBefore + 1, @"no line reaches another console's process");

    // After the job stopped, Return in the output is left to AppKit: nothing sent, no focus move.
    [b abort:b];
    check(!b.commandField.enabled, @"stopped Experiment disables its input");
    [b.window makeFirstResponder:b.outputText];
    returnKey(b.window);
    check(!fieldHasFocus(b.commandField) && b.window.firstResponder != b.outputText,
          @"stopped Experiment: Return in the output is not handled");
    [p finish];
    p->typesetStart = NO;
    [p->outputWindow makeFirstResponder:p->outputText];
    returnKey(p->outputWindow);
    check(!fieldHasFocus(p->texCommand) && p->outputWindow.firstResponder != p->outputText,
          @"finished normal console: Return in the output is not handled");

    // A job whose input is closed: the failure is reported and the focus stays in the output.
    TSExperimentConsoleController *closed = experiment(Closed);
    [closed.window makeFirstResponder:closed.outputText];
    NSString *before = closed.outputText.string.copy;
    returnKey(closed.window);
    check(closed.window.firstResponder == closed.outputText && !fieldHasFocus(closed.commandField),
          @"closed Experiment input: focus stays in the output");
    check(closed.outputText.string.length > before.length && ![closed.outputText.string hasPrefix:[before stringByAppendingString:@"\n"]],
          @"closed Experiment input: the failure is shown, not an echoed line");
    [closed invalidate];
    Probe *q = [Probe new];
    [q launch:@"/bin/sh" arguments:@[@"-c", Closed] directory:directory() environment:environment()];
    check(waitFor(^BOOL{ return [q.received containsString:@"ready"]; }), @"closed normal job started");
    spin(0.2);
    [q->outputWindow makeFirstResponder:q->outputText];
    NSString *shown = q->outputText.string.copy;
    returnKey(q->outputWindow);
    check(q->outputWindow.firstResponder == q->outputText && [q->outputText.string isEqualToString:shown],
          @"closed normal input: nothing echoed, focus stays in the output");
    [q finish];
    [a invalidate];
    [b invalidate];

    // The input writer itself: a handle closed here, and a descriptor SIGPIPE cannot be turned off for.
    NSData *line = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSPipe *closedPipe = [NSPipe pipe];
    [closedPipe.fileHandleForWriting closeFile];
    BOOL wrote = YES;
    @try { wrote = TSWriteConsoleInput(closedPipe.fileHandleForWriting, line, NULL); }
    @catch (NSException *exception) { check(NO, @"closed handle: no exception escapes"); }
    check(!wrote, @"closed handle: the write fails");
    NSFileHandle *invalid = [[NSFileHandle alloc] initWithFileDescriptor:-1 closeOnDealloc:NO];
    NSError *error = nil;
    wrote = YES;
    @try { wrote = TSWriteConsoleInput(invalid, line, &error); }
    @catch (NSException *exception) { check(NO, @"invalid descriptor: no exception escapes"); }
    check(!wrote && [error.domain isEqual:NSPOSIXErrorDomain] && error.code == EBADF,
          @"invalid descriptor: SIGPIPE cannot be turned off, so nothing is written and the error is POSIX");

    // The normal console after its write handle was closed here, with TeX still listed as running.
    Probe *shut = [Probe new];
    [shut launch:@"/bin/sh" arguments:@[@"-c", Echo] directory:directory() environment:environment()];
    check(waitFor(^BOOL{ return [shut.received containsString:@"ready"]; }), @"closed-handle normal job started");
    [shut.writeHandle closeFile];
    [shut->outputWindow makeFirstResponder:shut->outputText];
    NSString *shownBefore = shut->outputText.string.copy;
    @try { returnKey(shut->outputWindow); }
    @catch (NSException *exception) { check(NO, @"closed normal handle: no exception escapes the key event"); }
    check(shut->outputWindow.firstResponder == shut->outputText && [shut->outputText.string isEqualToString:shownBefore],
          @"closed normal handle: nothing echoed, focus stays in the output");
    [shut finish];

    realTeX();
    puts("PASS: Return in the console output answers TeX through AppKit key events in both consoles");
} return 0; }
'''

texbin = next((d for d in ['/Applications/TeXLive/2026/bin/universal-darwin', '/Library/TeX/texbin', '/usr/local/teTeX/bin']
               if Path(d, 'pdftex').exists()), None)
if texbin is None:
    raise SystemExit('pdftex not found')
with tempfile.TemporaryDirectory(prefix='texshop-console-output-return-') as tmp:
    # The console sources are compiled from copies, so that a mutation of the header reaches them all.
    src, exe, dsrc, jsrc = Path(tmp) / 'test.m', Path(tmp) / 'test', Path(tmp) / 'TSConsoleOutput.m', Path(tmp) / 'TSExperimentJob.m'
    src.write_text(prefix + controller + probe + tests)
    dsrc.write_text(delegate)
    jsrc.write_text(job)
    (Path(tmp) / 'TSConsoleOutput.h').write_text(header)
    subprocess.run(['xcrun', 'clang', '-I', tmp, '-I', str(root / 'Tests'), '-w', '-fobjc-arc', '-framework', 'Cocoa',
                    f'-DTEXBIN="{texbin}"', *include_args(root), str(src), str(dsrc), str(jsrc), *advanced_find_sources(root, tmp), '-o', str(exe)], check=True)
    home = Path(tmp) / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=240)
    if m:
        assert result.returncode != 0 and ('FAIL:' in result.stderr or result.returncode < 0), result.stdout + result.stderr
        print('PASS: detected', m, '-', result.stderr.strip().splitlines()[-1] if result.stderr.strip() else f'signal {-result.returncode}')
    else:
        if result.returncode:
            raise SystemExit(f"exit {result.returncode}\n" + result.stdout + result.stderr)
        print(result.stdout.strip().splitlines()[-1])
