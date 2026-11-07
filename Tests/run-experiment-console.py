#!/usr/bin/env python3
"""Exercise the production Experiment controller with headless window/text doubles.

Uses real child processes and encoding helpers; no TeXShop user settings or UI.
"""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
def cut(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)]
enc = (root / 'Sources/TSEncodingSupport.m').read_text(encoding='latin1')
helpers = cut(enc, '// UTF-8 in which each byte that does not start or continue a valid character is replaced', '// The byte order mark that starts data')
japanese = cut(enc, '// Japanese encodings read the byte 0x5C', '- (BOOL)ptexUtfOutputCheck:')
filters = enc[enc.index('// replace backslashes by yens'):].rstrip() + '\n'
controller = (root / 'Sources/TSExperimentConsoleController.m').read_text().replace('#import "TSEncodingSupport.h"', '').replace('#import "globals.h"', '')
prefix = r'''
#import <Cocoa/Cocoa.h>
#import "TSExperimentJob.h"
#import "TSEncodingSupport.h"
typedef enum { kNoFilterMode = 0, kMacJapaneseFilterMode = 1, kOtherJapaneseFilterMode = 2 } TSFilterMode;
static TSFilterMode g_shouldFilter = kNoFilterMode;
static NSString *yenString = @"\u00a5";
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static TSEncodingSupport *s; if (!s) s = [self new]; return s; }
HELPERS
JAPANESE
@end
FILTERS
static BOOL behind;
@interface TestDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation TestDefaults
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:@"ConsoleBehavior"] ? behind : YES; }
@end
#define SUD ((TestDefaults *)[TestDefaults new])
#define ConsoleBehaviorKey @"ConsoleBehavior"
#define BringPdfFrontOnTypesetKey @"BringPdfFront"
'''.replace('HELPERS', helpers).replace('JAPANESE', japanese).replace('FILTERS', filters)
tests = r'''
@interface TestWindow : NSObject
@property BOOL isVisible, isKeyWindow, isMiniaturized;
@property (copy) NSString *title;
@property NSUInteger backCount;
- (BOOL)makeFirstResponder:(id)responder;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)orderBack:(id)sender;
@end
@implementation TestWindow
- (BOOL)makeFirstResponder:(id)responder { return YES; }
- (void)makeKeyAndOrderFront:(id)sender { self.isVisible = YES; self.isKeyWindow = YES; }
- (void)orderFront:(id)sender { self.isVisible = YES; }
- (void)orderBack:(id)sender { self.isVisible = YES; self.backCount++; }
@end
@interface TestField : NSObject
@property (copy) NSString *stringValue, *string;
@property (getter=isEnabled) BOOL enabled;
@end
@implementation TestField
@end
@interface TestConsole : TSExperimentConsoleController
@property (strong) TestWindow *fakeWindow;
@property (strong) NSMutableString *captured;
@property BOOL closed;
@end
@implementation TestConsole
- (instancetype)init {
    if ((self = [super init])) {
        self.fakeWindow = [TestWindow new]; self.captured = [NSMutableString new];
        self.commandField = (id)[TestField new]; self.stopButton = (id)[TestField new];
        self.outputText = (id)[TestField new];
    } return self;
}
- (NSWindow *)window { return (id)self.fakeWindow; }
- (BOOL)isWindowLoaded { return YES; }
- (void)appendText:(NSString *)text { if (text) [self.captured appendString:text]; }
- (void)close { self.closed = YES; }
@end
static void check(BOOL ok, NSString *label) { if (!ok) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); } }
static BOOL waitFor(BOOL (^test)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!test() && end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return test();
}
static NSURL *directory(void) {
    NSURL *d = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    check([[NSFileManager defaultManager] createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:NULL], @"temporary directory");
    return d;
}
static BOOL exists(NSURL *d) { return [[NSFileManager defaultManager] fileExistsAtPath:d.path]; }
int main(void) { @autoreleasepool {
    TestConsole *console = [TestConsole new];
    NSURL *dir = directory();
    behind = YES;
    __block BOOL completed = NO;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf prompt; read line; printf '%s' \"$line\"; printf pdf > file.pdf"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:^(NSURL *pdf) {
        check(exists(pdf), @"PDF exists during callback"); completed = YES;
    }];
    check(console.fakeWindow.backCount == 1, @"background preference orders new console behind");
    check(waitFor(^BOOL{ return [console.captured isEqualToString:@"prompt"]; }), @"prompt reaches separate console");
    console.commandField.stringValue = @"hello"; [console sendCommand:nil];
    check(waitFor(^BOOL{ return completed; }), @"input completes job");
    check([console.captured isEqualToString:@"prompthello\nhello"], @"echo and engine output retained");
    check(!console.commandField.enabled && !console.stopButton.enabled && !exists(dir), @"completion disables input and removes temporary directory");
    // Closing/replacing an Experiment cancels its job and suppresses stale completion.
    dir = directory(); completed = NO;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"sleep 10; printf pdf > file.pdf"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:^(NSURL *pdf) { completed = YES; }];
    NSURL *old = dir; dir = directory();
    [console startExecutable:@"/bin/echo" arguments:@[@"replacement"] environment:@{} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:nil];
    check(!exists(old), @"replacement removes old directory");
    check(waitFor(^BOOL{ return !console.job.active; }), @"replacement completes");
    check(!completed && !exists(dir), @"stale result suppressed and replacement cleaned up");
    dir = directory();
    [console startExecutable:@"/not/a/real/engine" arguments:@[] environment:@{} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:nil];
    check(!exists(dir) && !console.commandField.enabled, @"failed launch cleanup");
    // A split UTF-8 character must survive a pause longer than the prompt flush timer.
    console.captured.string = @""; console.carry = nil; console.encoding = NSUTF8StringEncoding;
    NSData *utf8 = [@"日本語" dataUsingEncoding:NSUTF8StringEncoding];
    [console appendData:[utf8 subdataWithRange:NSMakeRange(0, 1)] atEnd:NO];
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:0.4];
    while (end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(console.captured.length == 0, @"paused partial UTF-8 is not replaced");
    [console appendData:[utf8 subdataWithRange:NSMakeRange(1, utf8.length - 1)] atEnd:YES];
    check([console.captured isEqualToString:@"日本語"], @"UTF-8 survives split prompt");
    // Closing the source/document invalidates callbacks and cancels the independent job.
    dir = directory(); completed = NO;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"sleep 10"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:^(NSURL *pdf) { completed = YES; }];
    [console invalidate];
    check(console.closed && !exists(dir) && !console.job && !completed, @"invalidate closes and cleans only this Experiment");
    puts("PASS: real controller input/output, background visibility, output decoding, completion, replacement, failed launch and close cleanup (headless views)");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-experiment-console-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(prefix + controller + tests)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Sources'), str(src), str(root / 'Sources/TSExperimentJob.m'), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=30)
