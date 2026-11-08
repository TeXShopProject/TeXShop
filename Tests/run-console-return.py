#!/usr/bin/env python3
"""Show Console in the console returns to the window it was shown from."""
from pathlib import Path
import re, subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSDocument.m').read_text(encoding='latin-1')
tail = (root / 'Sources/TSConsoleWindow.m').read_text(encoding='latin-1')

def method(text, signature):
    start = text.index(signature)
    end = text.index('\n}\n', start) + 3
    return text[start:end]

methods = ''.join(method(source, s) for s in
                  ['- (void)displayConsole: (id)sender', '- (void)returnFromConsole', '- (void)consoleDidResignKey'])
methods = methods.replace('[NSApp keyWindow]', 'KeyWindow()')
if mutation := (sys.argv[1] if len(sys.argv) > 1 else ''):
    if mutation == 'no-return':
        methods = methods.replace('if ([outputWindow isKeyWindow]) {', 'if (NO) {')
    elif mutation == 'keep-target':
        methods = re.sub(r'(- \(void\)consoleDidResignKey\n\{).*?\n\}', r'\1\n}', methods, flags=re.S)
resign = method(tail, '- (void)resignKeyWindow')
assert '[self.myDocument consoleDidResignKey]' in resign

program = r'''
#import <Cocoa/Cocoa.h>
@class Doc;
@interface Win : NSObject
@property (copy) NSString *name;
@property BOOL isVisible, isMiniaturized;
@property (weak) Doc *myDocument;
- (BOOL)isKeyWindow;
- (void)makeKeyAndOrderFront:(id)sender;
@end
static Win *gKey;
static Win *KeyWindow(void) { return gKey; }
@interface Doc : NSObject {
@public
    Win *outputWindow, *textWindow, *fullSplitWindow;
    BOOL useFullSplitWindow;
    NSTextStorage *_textStorage;
}
@property (weak) NSWindow *consoleReturnWindow;
@property BOOL experimentContext;
@property NSUInteger experimentConsoleCalls;
- (BOOL)experimentHasKeyWindow;
- (void)showExperimentConsole;
@property (strong) Win *pdfKitWindow;
- (BOOL)checkMasterFile:(NSString *)s forTask:(int)t;
- (BOOL)checkRootFile_forTask:(int)t;
- (void)returnFromConsole;
- (void)consoleDidResignKey;
@end
enum { RootForConsole = 1 };
@implementation Win
- (BOOL)isKeyWindow { return gKey == self; }
- (void)makeKeyAndOrderFront:(id)sender {
    Win *old = gKey; self.isVisible = YES; self.isMiniaturized = NO;
    if (old == self) return;
    gKey = self;
    if (old && old.myDocument && old == old.myDocument->outputWindow) [old.myDocument consoleDidResignKey];
}
@end
@implementation Doc
- (BOOL)experimentHasKeyWindow { return self.experimentContext; }
- (void)showExperimentConsole { self.experimentConsoleCalls++; }
- (BOOL)checkMasterFile:(NSString *)s forTask:(int)t { return NO; }
- (BOOL)checkRootFile_forTask:(int)t { return NO; }
METHODS
@end
static Win *W(NSString *n) { Win *w = [Win new]; w.name = n; w.isVisible = YES; return w; }
static int failures;
static void Expect(NSString *label, Win *w) {
    if (gKey != w) { printf("FAIL %s: key=%s expected=%s\n", label.UTF8String, gKey.name.UTF8String, w.name.UTF8String); failures++; }
}
int main(void) { @autoreleasepool {
    Doc *d = [Doc new];
    d->outputWindow = W(@"console"); d->outputWindow.myDocument = d;
    d->textWindow = W(@"source"); d->fullSplitWindow = W(@"combined"); d->fullSplitWindow.isVisible = NO;
    d.pdfKitWindow = W(@"preview");
    d->_textStorage = [[NSTextStorage alloc] initWithString:@"x"];
    #define CMD0 [(id)d displayConsole:nil]
    [d->textWindow makeKeyAndOrderFront:nil]; CMD0; Expect(@"source -> console", d->outputWindow);
    CMD0; Expect(@"console -> source", d->textWindow);
    [d.pdfKitWindow makeKeyAndOrderFront:nil]; CMD0; Expect(@"preview -> console", d->outputWindow);
    CMD0; Expect(@"console -> preview", d.pdfKitWindow);
    [d->outputWindow makeKeyAndOrderFront:nil]; CMD0; Expect(@"clicked console -> source", d->textWindow);
    [d.pdfKitWindow makeKeyAndOrderFront:nil]; CMD0;
    [d->textWindow makeKeyAndOrderFront:nil]; [d->outputWindow makeKeyAndOrderFront:nil];
    CMD0; Expect(@"left and clicked back -> source", d->textWindow);
    [d.pdfKitWindow makeKeyAndOrderFront:nil]; CMD0; d.pdfKitWindow.isVisible = NO;
    CMD0; Expect(@"closed caller -> source", d->textWindow);
    d.pdfKitWindow.isVisible = YES;
    [d.pdfKitWindow makeKeyAndOrderFront:nil]; CMD0; d.pdfKitWindow.isVisible = NO; d.pdfKitWindow.isMiniaturized = YES;
    CMD0; Expect(@"minimized caller is restored", d.pdfKitWindow);
    d->useFullSplitWindow = YES; d->fullSplitWindow.isVisible = YES; d->textWindow.isVisible = NO;
    [d->outputWindow makeKeyAndOrderFront:nil]; CMD0; Expect(@"combined window mode -> combined", d->fullSplitWindow);
    d->useFullSplitWindow = NO; d->fullSplitWindow.isVisible = NO; d->textWindow.isVisible = NO;
    [d->outputWindow makeKeyAndOrderFront:nil]; CMD0; Expect(@"no source window -> preview", d.pdfKitWindow);
    d.experimentContext = YES;
    Win *before = gKey; CMD0;
    Expect(@"Experiment routing leaves ordinary console unchanged", before);
    if (d.experimentConsoleCalls != 1) failures++;
    return failures ? 1 : 0;
} }
'''.replace('METHODS', methods)

with tempfile.TemporaryDirectory(prefix='texshop-console-return-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(src), '-o', str(exe)], check=True)
    r = subprocess.run([str(exe)], capture_output=True, text=True)
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    else:
        if r.returncode: raise SystemExit(r.stdout + r.stderr)
        print('PASS: return to source/preview, clicked console, closed/minimized caller, combined window, no source window')
