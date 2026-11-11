#!/usr/bin/env python3
"""Exercise the production Experiment controller with real AppKit windows and text views.

Uses real child processes and encoding helpers. Window ordering and frame persistence are suppressed;
no TeXShop user settings are read and no windows are shown.
"""
from pathlib import Path
import subprocess, tempfile, os, argparse
from source_tree import include_args
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mutation", choices=["no-window-load", "no-yen-filter", "no-appearance-hook", "stale-child-appearance", "no-console-alpha"])
parser.add_argument("--artifacts", type=Path, help="Save headless light/dark console previews")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
def cut(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)]
enc = (root / 'Sources/App/TSEncodingSupport.m').read_text(encoding='latin1')
helpers = cut(enc, '// UTF-8 in which each byte that does not start or continue a valid character is replaced', '// The byte order mark that starts data')
japanese = cut(enc, '// Japanese encodings read the byte 0x5C', '- (BOOL)ptexUtfOutputCheck:')
filters = enc[enc.index('// replace backslashes by yens'):].rstrip() + '\n'
controller = (root / 'Sources/Typesetting/TSExperimentConsoleController.m').read_text().replace('#import "TSEncodingSupport.h"', '').replace('#import "globals.h"', '')
if args.mutation == "no-window-load":
    assert "[self loadWindow];" in controller
    controller = controller.replace("[self loadWindow];", "", 1)
elif args.mutation == "no-yen-filter":
    assert "command = filterYenToBackslash(command);" in controller
    controller = controller.replace("command = filterYenToBackslash(command);", "command = command;", 1)
elif args.mutation == "no-appearance-hook":
    assert "[self.controller updateConsoleColors:nil];" in controller
    controller = controller.replace("[self.controller updateConsoleColors:nil];", "", 1)
elif args.mutation == "stale-child-appearance":
    assert "self.window.contentView.effectiveAppearance" in controller
    controller = controller.replace("self.window.contentView.effectiveAppearance", "self.outputText.effectiveAppearance", 1)
if args.mutation == "no-console-alpha":
    controller = controller.replace('self.window.alphaValue = TSThemeWindowAlpha(theme, TSThemeConsoleAlphaKey);', '')
prefix = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSExperimentJob.h"
#import "TSColorSupport.h"
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
static NSDictionary *liteColors;
static NSDictionary *darkColors;
@implementation TSColorSupport
+ (id)sharedInstance { static id s; if (!s) s = [self new]; return s; }
- (NSColor *)colorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{ return theme[key] ?: (dark ? NSColor.blackColor : NSColor.whiteColor); }
@end
static BOOL behind;
@interface TestDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
@end
@implementation TestDefaults
- (NSString *)stringForKey:(NSString *)key { return @"Menlo"; }
- (float)floatForKey:(NSString *)key { return 15; }
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:@"ConsoleBehavior"] ? behind : YES; }
@end
#define SUD ((TestDefaults *)[TestDefaults new])
#define SourceColorChangedNotification @"SourceColorChanged"
#define ConsoleFontNameKey @"ConsoleFontName"
#define ConsoleFontSizeKey @"ConsoleFontSize"
#define ConsoleFontChangedNotification @"ConsoleFontChanged"
#define ConsoleBehaviorKey @"ConsoleBehavior"
#define BringPdfFrontOnTypesetKey @"BringPdfFront"
'''.replace('HELPERS', helpers).replace('JAPANESE', japanese).replace('FILTERS', filters)
tests = r'''
// Keep the production initializer, window getter, loadWindow and appendText.
// Suppress window ordering and keep frame autosave bookkeeping in memory.
static NSUInteger backCount;
static NSString *requestedFrameName;
@implementation TSExperimentConsoleWindow (HeadlessOrdering)
- (BOOL)setFrameAutosaveName:(NSString *)name { requestedFrameName = [name copy]; return NO; }
- (void)makeKeyAndOrderFront:(id)sender { }
- (void)orderFront:(id)sender { }
- (void)orderBack:(id)sender { backCount++; }
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
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    liteColors = @{@"ConsoleBackground":NSColor.whiteColor, @"ConsoleText":NSColor.blackColor};
    darkColors = @{@"ConsoleBackground":NSColor.blackColor, @"ConsoleText":NSColor.whiteColor, @"ConsoleAlpha":@[@0,@0,@0,@.85]};
    TSExperimentConsoleController *console = [TSExperimentConsoleController new];
    check(console.window != nil && console.isWindowLoaded, @"production initializer creates window");
    check(console.outputText != nil && console.commandField != nil && console.stopButton != nil, @"production controls exist");
    check(!console.commandField.enabled && !console.stopButton.enabled, @"idle console controls disabled");
    check(console.outputText.font.pointSize == 15, @"console font preference applied");
    check([requestedFrameName isEqualToString:@"ExperimentConsole"] && console.window.frameAutosaveName.length == 0, @"separate frame autosave name");
    console.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [console updateConsoleColors:nil];
    [console appendText:@"initial output"];
    check([console.outputText.string isEqualToString:@"initial output"], @"production appendText stores text");
    NSScrollView *output = console.outputText.enclosingScrollView;
    for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(504,430)], [NSValue valueWithSize:NSMakeSize(720,600)]]) {
        [console.window setContentSize:size.sizeValue];
        check(fabs(NSMaxY(output.frame)-NSMinY(console.stopButton.frame))<1, @"stop button sits above output");
        check(NSMaxY(console.commandField.frame)<=NSMinY(output.frame), @"input sits below output");
        check(NSMaxX(console.commandField.frame)<=NSWidth(console.window.contentView.bounds), @"input fits resized console");
    }
    console.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    check([console.outputText.backgroundColor isEqual:NSColor.blackColor] && [console.outputText.textColor isEqual:NSColor.whiteColor], @"dark console theme applied through appearance hook");
    check([[console.outputText.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:NSColor.whiteColor], @"appearance hook recolors existing output");
    check(fabs(console.window.alphaValue-.85)<.001, @"dark console transparency");
    NSDictionary *preview = @{@"ConsoleBackground":NSColor.blueColor, @"ConsoleText":NSColor.yellowColor, @"ConsoleAlpha":@[@0,@0,@0,@.75]};
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:nil userInfo:preview];
    check(fabs(console.window.alphaValue-.75)<.001, @"live console transparency");
    for(id invalid in @[@"bad",NSNull.null,@[@0],@[@0,@0,@0,@"0.5"],@[@0,@0,@0,@(-0.1)],@[@0,@0,@0,@1.1],@[@0,@0,@0,@(NAN)],@[@0,@0,@0,@(INFINITY)]]){
        NSMutableDictionary *bad=[preview mutableCopy];bad[@"ConsoleAlpha"]=invalid;
        [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:nil userInfo:bad];
        check(console.window.alphaValue==1,@"invalid console opacity uses the common opaque fallback");
    }
    check([console.outputText.backgroundColor isEqual:NSColor.blueColor], @"live theme preview applied");
    check([[console.outputText.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:NSColor.yellowColor], @"existing output recolored");
    console.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    check([console.outputText.backgroundColor isEqual:NSColor.whiteColor] && [console.outputText.textColor isEqual:NSColor.blackColor], @"light console theme restored through appearance hook");
    check(fabs(console.window.alphaValue-1)<.001, @"missing alpha restores opaque console");
    NSString *artifacts = NSProcessInfo.processInfo.environment[@"CONSOLE_ARTIFACTS"];
    if (artifacts) {
        [console.window setContentSize:NSMakeSize(504,430)];
        console.outputText.string = @"This is LuaHBTeX, Version 1.22.0 (TeX Live 2026)\n(file.tex\nLaTeX2e <2026-06-01>\n! Undefined control sequence.\nl.8 \\example\n? ";
        console.commandField.enabled = YES; console.stopButton.enabled = YES;
        for (NSString *mode in @[@"light", @"dark"]) {
            BOOL dark = [mode isEqualToString:@"dark"];
            console.window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            NSView *content = console.window.contentView;
            [content layoutSubtreeIfNeeded];
            NSBitmapImageRep *bitmap = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
            [content cacheDisplayInRect:content.bounds toBitmapImageRep:bitmap];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            check([png writeToFile:[artifacts stringByAppendingPathComponent:[mode stringByAppendingString:@".png"]] atomically:YES], @"save console preview");
        }
    }
    NSURL *dir = directory();
    behind = YES;
    __block BOOL completed = NO;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf prompt; read line; printf '%s' \"$line\"; printf pdf > file.pdf"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:^(NSURL *pdf) {
        check(exists(pdf), @"PDF exists during callback"); completed = YES;
    }];
    check(backCount == 1, @"background preference orders new console behind");
    check(waitFor(^BOOL{ return [console.outputText.string isEqualToString:@"prompt"]; }), @"prompt reaches separate console");
    console.commandField.stringValue = @"hello"; [console sendCommand:nil];
    check(waitFor(^BOOL{ return completed; }), @"input completes job");
    check([console.outputText.string isEqualToString:@"prompthello\nhello"], @"echo and engine output retained");
    check(!console.commandField.enabled && !console.stopButton.enabled && !exists(dir), @"completion disables input and removes temporary directory");
    // Yen mode displays yen signs but sends TeX ASCII backslashes.
    dir = directory(); completed = NO; g_shouldFilter = kMacJapaneseFilterMode;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf prompt; read -r line; printf '%s' \"$line\" | od -An -tx1"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Yen" completion:^(NSURL *pdf) { completed = YES; }];
    check(waitFor(^BOOL{ return [console.outputText.string isEqualToString:@"prompt"]; }), @"yen prompt");
    console.commandField.stringValue = @"¥a"; [console sendCommand:nil];
    check(waitFor(^BOOL{ return completed; }), @"yen job completes");
    check([console.outputText.string containsString:@"¥a\n"] && [console.outputText.string containsString:@"5c  61"], @"yen display and ASCII backslash bytes");
    g_shouldFilter = kNoFilterMode;
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
    console.outputText.string = @""; console.carry = nil; console.encoding = NSUTF8StringEncoding;
    NSData *utf8 = [@"日本語" dataUsingEncoding:NSUTF8StringEncoding];
    [console appendData:[utf8 subdataWithRange:NSMakeRange(0, 1)] atEnd:NO];
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:0.4];
    while (end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(console.outputText.string.length == 0, @"paused partial UTF-8 is not replaced");
    [console appendData:[utf8 subdataWithRange:NSMakeRange(1, utf8.length - 1)] atEnd:YES];
    check([console.outputText.string isEqualToString:@"日本語"], @"UTF-8 survives split prompt");
    // Closing the source/document invalidates callbacks and cancels the independent job.
    dir = directory(); completed = NO;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"sleep 10"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:^(NSURL *pdf) { completed = YES; }];
    [console invalidate];
    check(!console.window.isVisible && !exists(dir) && !console.job && !completed, @"invalidate closes and cleans only this Experiment");
    puts("PASS: real controller input/output, background visibility, output decoding, completion, replacement, failed launch and close cleanup (production AppKit controls, no displayed windows)");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-experiment-console-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(prefix + controller + tests)
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-w', '-fobjc-arc', '-framework', 'Cocoa', *include_args(root), str(src), str(root / 'Sources/Typesetting/TSExperimentJob.m'), str(root / 'Sources/Typesetting/TSConsoleOutput.m'), '-o', str(exe)], check=True)
    (Path(tmp)/'home'/'Library'/'Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(Path(tmp)/'home'), CFFIXED_USER_HOME=str(Path(tmp)/'home'))
    if args.artifacts:
        args.artifacts.mkdir(parents=True, exist_ok=True)
        env["CONSOLE_ARTIFACTS"] = str(args.artifacts.resolve())
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=30)
    if args.mutation:
        assert result.returncode == 1 and "FAIL:" in result.stderr, result.stdout + result.stderr
        print("PASS: detected", args.mutation)
    else:
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())
