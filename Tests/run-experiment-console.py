#!/usr/bin/env python3
"""Exercise the production Experiment controller with real AppKit windows and text views.

Uses real child processes and encoding helpers. Window ordering and frame persistence are suppressed;
no TeXShop user settings are read and no windows are shown. Ordering calls go to a model of the
window list, which stacks windows by level as the window server does, so the console can be compared
with the Experiment panels and document windows of the shipped TSDocument nib.
"""
from pathlib import Path
import subprocess, tempfile, os, argparse
from source_tree import include_args
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mutation", choices=["no-window-load", "no-yen-filter", "no-appearance-hook", "stale-child-appearance", "no-console-alpha",
                                           "no-floating", "no-error-front", "no-prompt", "front-always", "prompt-no-wait", "echo-scanned"])
parser.add_argument("--artifacts", type=Path, help="Save headless light/dark console previews")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
from experiment_console_source import prefix as console_prefix, controller_source, advanced_find_sources
controller = controller_source(root)
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
elif args.mutation == "no-floating":
    assert "window.floatingPanel = YES;" in controller
    controller = controller.replace("window.floatingPanel = YES;", "", 1)
elif args.mutation == "no-error-front":
    assert "if (self.window.isKeyWindow) return;" in controller
    controller = controller.replace("if (self.window.isKeyWindow) return;", "return;", 1)
elif args.mutation == "no-prompt":
    prompt = "if (!TSExperimentIsPrompt([output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])) return;"
    assert prompt in controller
    controller = controller.replace(prompt, "return;", 1)
elif args.mutation == "front-always":
    assert "if (!self.job || ![SUD boolForKey:ConsoleBehaviorKey]) return;" in controller
    controller = controller.replace("if (!self.job || ![SUD boolForKey:ConsoleBehaviorKey]) return;", "if (!self.job) return;", 1)
elif args.mutation == "prompt-no-wait":
    assert "controller.outputCount == count && " in controller
    controller = controller.replace("controller.outputCount == count && ", "", 1)
elif args.mutation == "echo-scanned":
    echo = "        self.engineLine = @\"\";\n        self.outputCount++;"
    assert echo in controller
    controller = controller.replace(echo, "        self.engineLine = [self.engineLine stringByAppendingString:displayCommand];\n        self.outputCount++;", 1)
if args.mutation == "no-console-alpha":
    controller = controller.replace('self.window.alphaValue = TSThemeWindowAlpha(theme, TSThemeConsoleAlphaKey);', '')
prefix = console_prefix(root)
tests = r'''
// Keep the production initializer, window getter, loadWindow and appendText.
// Keep frame autosave bookkeeping in memory.
static NSString *requestedFrameName;
@implementation TSExperimentConsoleWindow (HeadlessFrame)
- (BOOL)setFrameAutosaveName:(NSString *)name { requestedFrameName = [name copy]; return NO; }
@end
// No window is ordered. The model keeps the window list from back to front: a window ordered
// to the front goes above the windows of its level and below higher levels, and one ordered
// to the back goes below the windows of its level and above lower levels.
static NSMutableArray<NSWindow *> *stack;
static NSWindow *modelKey;
static NSUInteger backCount, frontCount;
static IMP originalClose;
static void ModelOrder(NSWindow *window, BOOL front) {
    [stack removeObject:window];
    NSUInteger i = 0;
    if (front) { i = stack.count; while (i > 0 && stack[i - 1].level > window.level) i--; }
    else { while (i < stack.count && stack[i].level < window.level) i++; }
    [stack insertObject:window atIndex:i];
}
static void ModelKey(NSWindow *window) {
    if (modelKey == window) return;
    NSWindow *old = modelKey; modelKey = window;
    [old resignKeyWindow];
}
static void ModelMakeKeyAndOrderFront(NSWindow *self, SEL _cmd, id sender) { frontCount++; ModelOrder(self, YES); ModelKey(self); }
static void ModelOrderFront(NSWindow *self, SEL _cmd, id sender) { ModelOrder(self, YES); }
static void ModelOrderBack(NSWindow *self, SEL _cmd, id sender) { backCount++; ModelOrder(self, NO); }
static void ModelOrderOut(NSWindow *self, SEL _cmd, id sender) { [stack removeObject:self]; if (modelKey == self) ModelKey(nil); }
static void ModelClose(NSWindow *self, SEL _cmd) { ModelOrderOut(self, _cmd, nil); ((void (*)(id, SEL))originalClose)(self, _cmd); }
static BOOL ModelIsVisible(NSWindow *self, SEL _cmd) { return [stack containsObject:self]; }
static BOOL ModelIsKey(NSWindow *self, SEL _cmd) { return modelKey == self; }
static NSWindow *ModelAppKey(NSApplication *self, SEL _cmd) { return modelKey; }
static void InstallWindowModel(void) {
    stack = [NSMutableArray array];
    struct { Class c; SEL s; IMP i; } replacements[] = {
        {NSWindow.class, @selector(makeKeyAndOrderFront:), (IMP)ModelMakeKeyAndOrderFront},
        {NSWindow.class, @selector(orderFront:), (IMP)ModelOrderFront},
        {NSWindow.class, @selector(orderBack:), (IMP)ModelOrderBack},
        {NSWindow.class, @selector(orderOut:), (IMP)ModelOrderOut},
        {NSWindow.class, @selector(isVisible), (IMP)ModelIsVisible},
        {NSWindow.class, @selector(isKeyWindow), (IMP)ModelIsKey},
        {NSApplication.class, @selector(keyWindow), (IMP)ModelAppKey},
    };
    for (size_t i = 0; i < sizeof replacements / sizeof replacements[0]; i++)
        TSReplaceTestMethod(class_getInstanceMethod(replacements[i].c, replacements[i].s), replacements[i].i);
    Method close = class_getInstanceMethod(NSWindow.class, @selector(close));
    originalClose = method_getImplementation(close);
    method_setImplementation(close, (IMP)ModelClose);
}
static BOOL above(NSWindow *upper, NSWindow *lower) {
    NSUInteger a = [stack indexOfObject:upper], b = [stack indexOfObject:lower];
    return a != NSNotFound && b != NSNotFound && a > b;
}
static NSWindow *documentWindow(NSArray *objects, NSString *title) {
    for (id object in objects)
        if ([object isKindOfClass:NSWindow.class] && [[object title] isEqualToString:title]) return object;
    fprintf(stderr, "FAIL: TSDocument nib window %s\n", title.UTF8String); exit(1);
}
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
static void waitSeconds(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
// Runs a job with the console hidden and the source panel key; returns whether the console came forward.
static BOOL showsConsole(TSExperimentConsoleController *console, NSWindow *panel, NSString *script, void (^during)(void)) {
    [console.window orderOut:nil]; [panel makeKeyAndOrderFront:nil];
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", script] environment:@{@"PATH":@"/usr/bin:/bin"} directory:directory() encoding:NSUTF8StringEncoding title:@"Case" completion:nil];
    if (during) during();
    BOOL ended = waitFor(^BOOL{ return !console.job.active; });
    waitSeconds(0.7);
    BOOL shown = console.window.isVisible && [stack lastObject] == console.window;
    if (!ended) [console abort:nil];
    return shown;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication]; InstallWindowModel();
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
    check(!console.window.isVisible && backCount == 0 && frontCount == 0, @"error-only preference leaves the new console hidden");
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
    // The console floats with the Experiment panels of the shipped document nib, above the document's windows.
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:NSProcessInfo.processInfo.environment[@"TSDOCUMENT_NIB"]] bundle:nil];
    NSArray *objects = nil;
    check([nib instantiateWithOwner:nil topLevelObjects:&objects], @"TSDocument nib loads");
    NSWindow *sourcePanel = documentWindow(objects, @"Try This"), *outputPanel = documentWindow(objects, @"Try This Output");
    NSWindow *text = documentWindow(objects, @"Tex"), *documentConsole = documentWindow(objects, @"Console");
    check(sourcePanel.level == NSFloatingWindowLevel && outputPanel.level == NSFloatingWindowLevel, @"Experiment panels float");
    check(text.level == NSNormalWindowLevel && documentConsole.level == NSNormalWindowLevel, @"document windows do not float");
    check(console.window.level == sourcePanel.level && ((NSPanel *)console.window).floatingPanel, @"Experiment console floats with the panels");
    check(console.window.hidesOnDeactivate && sourcePanel.hidesOnDeactivate && outputPanel.hidesOnDeactivate, @"Experiment windows hide together");
    [console.window orderOut:nil];
    [text makeKeyAndOrderFront:nil]; [documentConsole orderFront:nil];
    [sourcePanel makeKeyAndOrderFront:nil]; [outputPanel orderFront:nil];
    check(above(sourcePanel, documentConsole) && above(outputPanel, sourcePanel), @"model stacks the panels over the document");
    // Typesetting with "always" brings the console in front of both panels.
    behind = NO; dir = directory(); completed = NO;
    console.returnWindow = sourcePanel;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf '[1]\\n'; printf '! Undefined control sequence.\\nl.3 \\\\foo\\n? '; read line"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Order" completion:^(NSURL *pdf) { completed = YES; }];
    check(stack.lastObject == console.window && console.window.isKeyWindow, @"console comes in front of the panels when typesetting starts");
    check(above(console.window, outputPanel) && above(console.window, text), @"console is above panels and document");
    // A click on a panel brings it back in front; the console stays above the document.
    [outputPanel makeKeyAndOrderFront:nil];
    check(stack.lastObject == outputPanel && above(console.window, text) && above(console.window, documentConsole), @"clicked panel returns to the front");
    // "Always" keeps its behavior: an error does not bring the console forward again.
    check(waitFor(^BOOL{ return [console.outputText.string hasSuffix:@"? "]; }), @"always: error prompt shown");
    waitSeconds(0.8);
    check(stack.lastObject == outputPanel, @"always: error leaves the clicked panel in front");
    // Command-0 in a panel brings the console to the front, and again returns to the panel.
    [console toggleFromWindow:outputPanel];
    check(stack.lastObject == console.window && console.window.isKeyWindow, @"Command-0 brings the console in front of the panels");
    [console toggleFromWindow:console.window];
    check(stack.lastObject == outputPanel && outputPanel.isKeyWindow, @"Command-0 again returns to the panel");
    [console sendLine:@""];
    check(waitFor(^BOOL{ return !console.job.active; }), @"always: job ends");
    // "When error occurs": the console stays hidden until TeX stops with an error prompt.
    behind = YES; [console.window orderOut:nil]; [sourcePanel makeKeyAndOrderFront:nil];
    console.returnWindow = sourcePanel; dir = directory(); NSUInteger fronts = frontCount;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf 'Package: babel 2026/01/01 v3.0\\n(./file.aux) [1] [2'; sleep 0.3; printf ']\\n! Undefined control sequence.\\nl.3 \\\\foo\\n? '; read line"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Prompt" completion:nil];
    check(waitFor(^BOOL{ return [console.outputText.string containsString:@"[2"]; }), @"error-only: output before the error");
    check(!console.window.isVisible && frontCount == fronts, @"error-only: ordinary output keeps the console hidden");
    check(waitFor(^BOOL{ return console.window.isVisible; }), @"error-only: error prompt shows the console");
    check(stack.lastObject == console.window && console.window.isKeyWindow && above(console.window, sourcePanel), @"error-only: console in front of the panels");
    check(console.returnWindow == sourcePanel, @"error-only: Command-0 returns to the panel");
    [console sendLine:@""];
    check(waitFor(^BOOL{ return !console.job.active; }), @"error-only: prompt job ends");
    // An error line of -file-line-error shows the console even when TeX does not stop.
    [console.window orderOut:nil]; [sourcePanel makeKeyAndOrderFront:nil]; dir = directory();
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf 'This is pdfTeX\\n'; sleep 0.2; printf './file.tex:3: Undefined control sequence.\\n'; sleep 0.2"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Line" completion:nil];
    check(waitFor(^BOOL{ return console.window.isVisible; }), @"error-only: file:line: error shows the console");
    check(stack.lastObject == console.window, @"error-only: file:line: console in front");
    check(waitFor(^BOOL{ return !console.job.active; }), @"error-only: file-line job ends");
    // Pieces of ordinary lines that look like prompts, and times, do not show the console.
    check(!showsConsole(console, sourcePanel, @"printf '*'; sleep 0.1; printf 'geometry* driver: auto-detecting\\n'; sleep 0.7", nil), @"error-only: split '*geometry*' line is not a prompt");
    check(!showsConsole(console, sourcePanel, @"printf '?'; sleep 0.1; printf 'x\\n'; sleep 0.7", nil), @"error-only: split '?x' line is not a prompt");
    check(!showsConsole(console, sourcePanel, @"printf '**'; sleep 0.1; printf 'file.tex\\n'; sleep 0.7", nil), @"error-only: split '**file' line is not a prompt");
    check(!showsConsole(console, sourcePanel, @"printf '12:34: time\\n'; sleep 0.2", nil), @"error-only: a time is not a file:line: error");
    // Prompts at which TeX stops show the console.
    check(showsConsole(console, sourcePanel, @"printf '*'; read line", ^{ check(waitFor(^BOOL{ return console.window.isVisible; }), @"star prompt"); [console sendLine:@""]; }), @"error-only: '*' prompt shows the console");
    check(showsConsole(console, sourcePanel, @"printf 'Enter file name: '; read line", ^{ check(waitFor(^BOOL{ return console.window.isVisible; }), @"file name prompt"); [console sendLine:@""]; }), @"error-only: 'Enter file name:' shows the console");
    // A line typed in the console is not engine output; the same text written by TeX is.
    check(!showsConsole(console, sourcePanel, @"printf 'ready'; read line; printf 'OK\\n'; sleep 0.2", ^{
        check(waitFor(^BOOL{ return [console.outputText.string isEqualToString:@"ready"]; }), @"echo case ready");
        [console sendLine:@"file.tex:7: user text"]; }), @"error-only: typed file:line: text is not an error");
    check(showsConsole(console, sourcePanel, @"printf 'ready'; read line; printf './file.tex:7: Undefined control sequence.\\n'; sleep 0.2", ^{
        check(waitFor(^BOOL{ return [console.outputText.string isEqualToString:@"ready"]; }), @"answer case ready");
        [console sendLine:@"x"]; }), @"error-only: file:line: error right after an answer shows the console");
    // Output without errors leaves the console hidden to the end; a stopped job does not show it.
    [console.window orderOut:nil]; [sourcePanel makeKeyAndOrderFront:nil]; dir = directory(); fronts = frontCount;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"printf 'Document Class: article 2024/06/29 v1.4n\\nWhy?\\n?x\\n*\\nOutput written on file.pdf (2 pages, 1234 bytes).\\nTranscript written on file.log.\\n'"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Clean" completion:nil];
    check(waitFor(^BOOL{ return !console.job.active; }), @"error-only: clean job ends");
    check(!console.window.isVisible && frontCount == fronts, @"error-only: clean output keeps the console hidden");
    // Closing the source/document invalidates callbacks and cancels the independent job.
    dir = directory(); completed = NO;
    [console startExecutable:@"/bin/sh" arguments:@[@"-c", @"sleep 10"] environment:@{@"PATH":@"/usr/bin:/bin"} directory:dir encoding:NSUTF8StringEncoding title:@"Sample" completion:^(NSURL *pdf) { completed = YES; }];
    [console invalidate];
    check(!console.window.isVisible && !exists(dir) && !console.job && !completed, @"invalidate closes and cleans only this Experiment");
    puts("PASS: real controller input/output, console order with the floating Experiment panels, error-only console, output decoding, completion, replacement, failed launch and close cleanup (production AppKit controls, no displayed windows)");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-experiment-console-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(prefix + controller + tests)
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit', '-framework', 'WebKit', '-framework', 'Quartz', *include_args(root), str(src), str(root / 'Sources/Typesetting/TSExperimentJob.m'), str(root / 'Sources/Typesetting/TSConsoleOutput.m'), *advanced_find_sources(root, tmp), '-o', str(exe)], check=True)
    (Path(tmp)/'home'/'Library'/'Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(Path(tmp)/'home'), CFFIXED_USER_HOME=str(Path(tmp)/'home'),
               TSDOCUMENT_NIB=str(root / 'Resources/Interfaces/Base.lproj/TSDocument.nib/keyedobjects.nib'))
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
