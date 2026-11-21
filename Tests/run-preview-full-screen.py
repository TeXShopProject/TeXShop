#!/usr/bin/env python3
"""A Preview window entering and leaving full screen (#63).

The production enterFullScreen: and exitFullScreen: of TSDocument run against
stand-in views, window and settings:
- With Keep magnification and display format in full screen off (the default),
  the window is unsplit, both parts take the full-screen magnification and
  display format, a change made in full screen is remembered for the next time,
  and leaving full screen brings back the earlier ones.
- With the switch on, the split and each part's magnification and display
  format stay as they are, going in and coming out, and the remembered
  full-screen values are left alone.
- The switch as it was on entering decides what leaving does.
Mutations that drop either check must fail.
"""
from pathlib import Path
import subprocess, sys, tempfile
from production_fragments import method, verify_embedded

root = Path(__file__).resolve().parents[1]
doc = (root / 'Sources/Document/TSDocument.m').read_text()
enter = method(doc, '- (void)enterFullScreen: (NSNotification *)notification')
leave = method(doc, '- (void)exitFullScreen: (NSNotification *)notification')

program = r'''
#import <Cocoa/Cocoa.h>
static NSString *fullscreenPageStyleKey = @"fullscreenPageStyle";
static NSString *fullscreenResizeOptionKey = @"fullscreenResizeOption";
static NSString *KeepPreviewDisplayInFullScreenKey = @"KeepPreviewDisplayInFullScreen";
@interface FakeDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation FakeDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { self.values[key] = @(value); }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
@end
static FakeDefaults *fakeDefaults;
#define SUD fakeDefaults
@interface FakeView : NSObject
@property NSInteger pageStyle, resizeOption;
@end
@implementation FakeView
- (void)changePDFViewSizeTo:(NSInteger)option { if (option != 0) self.resizeOption = option; }
- (void)changePageStyleTo:(NSInteger)style { self.pageStyle = style; }
@end
@interface FakeWindow : NSObject
@property BOOL split;
@end
@implementation FakeWindow
- (BOOL)windowIsSplit { return self.split; }
- (void)splitPdfKitWindow:(id)sender { self.split = !self.split; }
@end
@interface Doc : NSObject {
    NSInteger oldPageStyle, oldResizeOption, fullscreenPageStyle, fullscreenResizeOption;
    BOOL fullscreenKeptDisplay;
}
@property FakeView *myPDFKitView, *myPDFKitView2;
@property FakeWindow *pdfKitWindow;
@end
@implementation Doc
ENTER
LEAVE
@end
static int failures = 0;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what.UTF8String); } }
static Doc *Make(BOOL split) {
    Doc *d = [Doc new]; d.myPDFKitView = [FakeView new]; d.myPDFKitView2 = [FakeView new]; d.pdfKitWindow = [FakeWindow new];
    d.pdfKitWindow.split = split;
    d.myPDFKitView.pageStyle = 3; d.myPDFKitView.resizeOption = 6;   // Multi-Page, Fit to Content Width
    d.myPDFKitView2.pageStyle = 4; d.myPDFKitView2.resizeOption = 2; // Double Multi-Page, Fixed Magnification
    return d;
}
int main(void) { @autoreleasepool {
    fakeDefaults = [FakeDefaults new];
    // Off, the default: the full-screen display of earlier versions.
    [fakeDefaults setInteger:2 forKey:fullscreenPageStyleKey]; [fakeDefaults setInteger:3 forKey:fullscreenResizeOptionKey];
    Doc *d = Make(YES);
    [d enterFullScreen:nil];
    Check(!d.pdfKitWindow.split, @"Off: full screen unsplits the window");
    Check(d.myPDFKitView.pageStyle == 2 && d.myPDFKitView.resizeOption == 3, @"Off: the first part takes the full-screen display format and magnification");
    Check(d.myPDFKitView2.pageStyle == 2 && d.myPDFKitView2.resizeOption == 3, @"Off: the second part takes them too");
    d.myPDFKitView.pageStyle = 1; d.myPDFKitView.resizeOption = 2;
    [d exitFullScreen:nil];
    Check([fakeDefaults integerForKey:fullscreenPageStyleKey] == 1 && [fakeDefaults integerForKey:fullscreenResizeOptionKey] == 2, @"Off: a change made in full screen is remembered");
    Check(d.myPDFKitView.pageStyle == 3 && d.myPDFKitView.resizeOption == 6, @"Off: leaving full screen brings back the earlier display");
    // On: everything stays as it is.
    [fakeDefaults setInteger:2 forKey:fullscreenPageStyleKey]; [fakeDefaults setInteger:3 forKey:fullscreenResizeOptionKey];
    [fakeDefaults setBool:YES forKey:KeepPreviewDisplayInFullScreenKey];
    d = Make(YES);
    [d enterFullScreen:nil];
    Check(d.pdfKitWindow.split, @"On: the window stays split");
    Check(d.myPDFKitView.pageStyle == 3 && d.myPDFKitView.resizeOption == 6, @"On: the first part keeps its display format and magnification");
    Check(d.myPDFKitView2.pageStyle == 4 && d.myPDFKitView2.resizeOption == 2, @"On: the second part keeps its own");
    d.myPDFKitView.pageStyle = 1; d.myPDFKitView.resizeOption = 2;
    [d exitFullScreen:nil];
    Check(d.pdfKitWindow.split, @"On: leaving full screen keeps the split");
    Check(d.myPDFKitView.pageStyle == 1 && d.myPDFKitView.resizeOption == 2, @"On: a change made in full screen stays after it");
    Check(d.myPDFKitView2.pageStyle == 4 && d.myPDFKitView2.resizeOption == 2, @"On: the second part is left alone on leaving");
    Check([fakeDefaults integerForKey:fullscreenPageStyleKey] == 2 && [fakeDefaults integerForKey:fullscreenResizeOptionKey] == 3, @"On: the remembered full-screen values are left alone");
    // Turned off while in full screen: leaving still changes nothing.
    d = Make(NO);
    [d enterFullScreen:nil];
    [fakeDefaults setBool:NO forKey:KeepPreviewDisplayInFullScreenKey];
    [d exitFullScreen:nil];
    Check(d.myPDFKitView.pageStyle == 3 && d.myPDFKitView.resizeOption == 6 && !d.pdfKitWindow.split, @"On at entry: leaving changes nothing though the switch was turned off");
    // Turned on while in full screen: leaving still brings back the earlier display.
    d = Make(NO);
    [d enterFullScreen:nil];
    [fakeDefaults setBool:YES forKey:KeepPreviewDisplayInFullScreenKey];
    [d exitFullScreen:nil];
    Check(d.myPDFKitView.pageStyle == 3 && d.myPDFKitView.resizeOption == 6, @"Off at entry: leaving brings back the earlier display though the switch was turned on");
    // A second round with the switch on after an off round.
    d = Make(YES);
    [d enterFullScreen:nil]; [d exitFullScreen:nil];
    Check(d.pdfKitWindow.split && d.myPDFKitView.pageStyle == 3, @"On again: the window stays as it was");
    if (failures) return 1;
    puts("PASS: full screen keeps the Preview display when the switch is on, and works as before when it is off");
} return 0; }
'''
program = program.replace('ENTER', enter).replace('LEAVE', leave)
verify_embedded(program, [('complete method:- (void)enterFullScreen:', doc, enter), ('complete method:- (void)exitFullScreen:', doc, leave)])

def build_and_run(text, tmp, name):
    src = Path(tmp) / (name + '.m'); exe = Path(tmp) / name
    src.write_text(text)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-Wno-objc-method-access', str(src), '-o', str(exe)], check=True)
    return subprocess.run([str(exe)], capture_output=True, text=True)

with tempfile.TemporaryDirectory(prefix='TeXShop-full-screen-', dir=None) as tmp:
    result = build_and_run(program, tmp, 'FullScreen')
    sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
    if result.returncode != 0:
        sys.exit('FAIL: full screen harness')
    mutations = [
        ('entry ignores the switch', '    if (fullscreenKeptDisplay)\n        return;\n', ''),
        ('leaving ignores the entry', '    if (fullscreenKeptDisplay) {\n        fullscreenKeptDisplay = NO;\n        return;\n    }\n', ''),
        ('leaving reads the switch again', '    if (fullscreenKeptDisplay) {\n        fullscreenKeptDisplay = NO;', '    if ([SUD boolForKey: KeepPreviewDisplayInFullScreenKey]) {\n        fullscreenKeptDisplay = NO;'),
    ]
    for label, old, new in mutations:
        assert program.count(old) == 1, 'Mutation target missing: ' + label
        mutated = build_and_run(program.replace(old, new), tmp, 'Mutant')
        if mutated.returncode == 0:
            sys.exit('FAIL: mutation survived: ' + label)
        print('MUTATION CAUGHT:', label)
print('PASS: run-preview-full-screen')
