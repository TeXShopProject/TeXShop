#!/usr/bin/env python3
"""A Command key with a dead key (no characters) does not throw in the Preview window,
for a PDF preview (fromKit) and for an image preview alike. The branches of the real
-[TSPreviewWindow sendEvent:] are compiled into a probe and given such an event."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess, os, sys

root = Path(__file__).resolve().parent.parent
source = (root/'Sources/Windows/TSPreviewWindow.m').read_text(encoding='utf-8')


def branches(src):
    start = src.index('- (void)sendEvent:')
    a = src.index('if ([self.myDocument fromKit] && ([theEvent type] == NSEventTypeKeyDown)', start)
    b = src.index('#ifdef IMMEDIATEMAGNIFY', a)
    c = src.index('if (![self.myDocument fromKit])', b)
    d = src.index('switch (theChar)', c)
    return src[a:b] + src[c:d] + '(void)theChar; }}'


def probe(src):
    code = branches(src)
    program = r'''
#import <Cocoa/Cocoa.h>
@interface Probe : NSObject
- (void)zoomIn:(id)sender; - (void)zoomOut:(id)sender;
@property BOOL fromKit;
@end
@implementation Probe
- (Probe *)myDocument { return self; }
- (id)activeView { return nil; }
- (void)zoomIn:(id)sender {} - (void)zoomOut:(id)sender {}
- (void)probe:(NSEvent *)theEvent {
''' + code + r'''
}
@end
int main(void) { @autoreleasepool {
    Probe *p = [Probe new]; int failures = 0;
    NSEvent *dead = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
        timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:33];
    NSEvent *plain = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
        timestamp:0 windowNumber:0 context:nil characters:@"x" charactersIgnoringModifiers:@"x" isARepeat:NO keyCode:7];
    for (int kit = 0; kit < 2; kit++) for (NSEvent *event in @[dead, plain]) {
        p.fromKit = kit;
        @try { [p probe:event]; }
        @catch (NSException *e) { failures++; printf("FAIL: %s preview, %s: %s\n", kit ? "PDF" : "image",
            event.characters.length ? "a key with characters" : "a dead key", e.reason.UTF8String); }
    }
    return failures ? 1 : 0;
}}
'''
    with TemporaryDirectory(dir='/private/tmp') as t:
        p = Path(t)
        (p/'probe.m').write_text(program, encoding='utf-8')
        env = dict(os.environ, TMPDIR=t + '/')
        subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(p/'probe.m'), '-o', str(p/'probe')],
                       env=env, check=True)
        return subprocess.run([str(p/'probe')], env=env, capture_output=True, text=True)


result = probe(source)
if result.returncode != 0:
    print(result.stdout + result.stderr)
    sys.exit('FAIL: a dead key in the Preview window')

# Each guard is needed: taking away either one makes its preview throw.
mutations = {
    'PDF guard removed': ('NSEventModifierFlagCommand) && [[theEvent characters] length] > 0) {', 'NSEventModifierFlagCommand)) {'),
    'image guard removed': ('NSEventTypeKeyDown && [[theEvent characters] length] > 0) {', 'NSEventTypeKeyDown) {'),
}
for name, (old, new) in mutations.items():
    assert source.count(old) == 1, name
    if probe(source.replace(old, new)).returncode == 0:
        sys.exit('FAIL: mutation not detected: ' + name)
    print('DETECTED', name)
print('PASS: a Command key with a dead key goes through the PDF and image previews without an exception')
