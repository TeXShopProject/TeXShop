#!/usr/bin/env python3
"""The Change Encoding sheet takes the size its contents need, in every language.

The warning of the sheet is two lines in Korean and Chinese, three in most languages and four in German
and Dutch. The harness compiles Base.lproj/CustomModalWindowController.xib with the strings of each
language and the real CustomModalWindowController.m against stand-ins for the document and the encoding
list, prepares the sheet as Change Encoding does, and checks that the window is exactly as large as its
contents need: no part outside, the warning not cut, and the standard 20 points between the pop-up menu
and the buttons. The window is never shown. With --mutation NAME the harness runs against mutated sources
and must fail; --mutations runs them all."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
INTERFACES = root / 'Resources/Interfaces'
XIB = INTERFACES / 'Base.lproj/CustomModalWindowController.xib'
SOURCE = root / 'Sources/Windows/CustomModalWindowController.m'
MUTATIONS = {
    # The sheet keeps the size of the nib (the state of 6.00 beta 1 in Korean, Chinese and English).
    'no-fit': (SOURCE, '    [self fitWindowToContents];\n', '\n'),
    # Only the minimum follows the contents, so a nib larger than the contents leaves empty space.
    'min-only': (SOURCE, '    [self.window setContentSize:size];\n', '\n'),
    # The pop-up menu stands farther from the buttons than the standard 20 points.
    'wide-gap': (XIB, 'secondAttribute="bottom" constant="20" id="Enc-bt-Top"',
                 'secondAttribute="bottom" constant="32" id="Enc-bt-Top"'),
}
STUBS = {
    'TSDocument.h': '''#import <Cocoa/Cocoa.h>
@interface TSDocument : NSObject
- (void)initializeTempEncoding;
- (void)activateTempEncoding;
- (void)chooseTempEncoding:(id)sender;
- (NSStringEncoding)currentDocumentEncoding;
@end
''',
    'TSTextEditorWindow.h': '''#import <Cocoa/Cocoa.h>
@interface TSTextEditorWindow : NSWindow
- (id)document;
@end
''',
    'TSEncodingSupport.h': '''#import <Cocoa/Cocoa.h>
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
- (NSStringEncoding)defaultEncoding;
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)target action:(SEL)action;
@end
''',
}
PROBE = r'''
#import <Cocoa/Cocoa.h>
#import "CustomModalWindowController.h"
#import "TSEncodingSupport.h"
@implementation TSDocument
- (void)initializeTempEncoding {}
- (void)activateTempEncoding {}
- (void)chooseTempEncoding:(id)sender {}
- (NSStringEncoding)currentDocumentEncoding { return NSUTF8StringEncoding; }
@end
@implementation TSTextEditorWindow
- (id)document { return nil; }
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSStringEncoding)defaultEncoding { return NSUTF8StringEncoding; }
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)target action:(SEL)action
{
    // Names as long as the real list's (Japanese (Mac OS), Western (Windows Latin 1), ...).
    for (NSString *name in @[@"Unicode (UTF-8)", @"Japanese (Shift JIS X0213)", @"Western (Windows Latin 1)",
                              @"Central European (ISO Latin 2)", @"Simplified Chinese (GB 18030)"]) {
        NSMenuItem *item = [menu addItemWithTitle:name action:action keyEquivalent:@""];
        item.tag = menu.numberOfItems == 1 ? NSUTF8StringEncoding : 1000 + menu.numberOfItems;
    }
}
@end
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (int i = 1; i < argc; i++) {
        NSString *nib = [NSString stringWithUTF8String:argv[i]];
        // The controller owns its nib, as with initWithWindowNibName: in TSDocument's changeEncoding:.
        CustomModalWindowController *controller = [CustomModalWindowController alloc];
        controller = [controller initWithWindowNibPath:nib owner:controller];
        [controller initializeEncodingMatrix:[TSDocument new]];
        NSWindow *window = controller.window;
        NSView *contents = window.contentView;
        [contents layoutSubtreeIfNeeded];
        NSMutableArray *views = [NSMutableArray array];
        for (NSView *view in contents.subviews) {
            NSRect r = [view alignmentRectForFrame:view.frame];
            NSString *kind = NSStringFromClass(view.class);
            double needed = 0;
            if ([view isKindOfClass:NSTextField.class]) {
                NSTextField *field = (NSTextField *)view;
                needed = [field.cell cellSizeForBounds:NSMakeRect(0, 0, field.bounds.size.width, CGFLOAT_MAX)].height;
            }
            [views addObject:@{@"kind": kind, @"x": @(r.origin.x), @"y": @(r.origin.y), @"w": @(r.size.width),
                               @"h": @(r.size.height), @"needed": @(needed),
                               @"inside": @(NSContainsRect(NSInsetRect(contents.bounds, -0.5, -0.5), view.frame))}];
        }
        NSSize fit = contents.fittingSize;
        out[nib.lastPathComponent] = @{@"w": @(contents.frame.size.width), @"h": @(contents.frame.size.height),
                                       @"fitW": @(fit.width), @"fitH": @(fit.height),
                                       @"minW": @(window.contentMinSize.width), @"minH": @(window.contentMinSize.height),
                                       @"visible": @(window.isVisible), @"views": views};
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:NULL];
    fwrite(json.bytes, 1, json.length, stdout);
} return 0; }
'''


def measure(tmp, xib, source):
    include = tmp / 'include'
    include.mkdir(exist_ok=True)
    for name, text in STUBS.items():
        (include / name).write_text(text, encoding='utf-8')
    (include / 'CustomModalWindowController.h').write_bytes((SOURCE.parent / 'CustomModalWindowController.h').read_bytes())
    (tmp / 'controller.m').write_text(source, encoding='utf-8')
    (tmp / 'probe.m').write_text(PROBE, encoding='utf-8')
    (tmp / 'sheet.xib').write_text(xib, encoding='utf-8')
    binary = tmp / 'probe'
    subprocess.run(['clang', '-fobjc-arc', '-w', '-I', str(include), '-framework', 'Cocoa', str(tmp / 'controller.m'),
                    str(tmp / 'probe.m'), '-o', str(binary)], check=True)
    nibs = []
    for folder in sorted(INTERFACES.glob('*.lproj')):
        strings = folder / 'CustomModalWindowController.strings'
        language = folder.name[:-len('.lproj')]
        nib = tmp / f'{language}.nib'
        command = ['ibtool', '--compile', str(nib), str(tmp / 'sheet.xib')]
        if strings.exists():
            command[1:1] = ['--strings-file', str(strings)]
        elif language != 'Base':
            continue
        subprocess.run(command, check=True, capture_output=True)
        nibs.append(str(nib))
    result = subprocess.run([str(binary)] + nibs, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr[-2000:]
    return json.loads(result.stdout)


def problems(sizes):
    found = []
    heights = set()
    for nib, s in sorted(sizes.items()):
        name = nib[:-len('.nib')]
        heights.add(round(s['h']))
        if s['visible']:
            found.append(f'{name}: the window was shown')
        if abs(s['w'] - s['fitW']) > 0.5 or abs(s['h'] - s['fitH']) > 0.5:
            found.append(f'{name}: the sheet is {s["w"]:.0f}×{s["h"]:.0f}, its contents need {s["fitW"]:.0f}×{s["fitH"]:.0f}')
        if abs(s['minW'] - s['w']) > 0.5 or abs(s['minH'] - s['h']) > 0.5:
            found.append(f'{name}: the minimum {s["minW"]:.0f}×{s["minH"]:.0f} differs from the size {s["w"]:.0f}×{s["h"]:.0f}')
        views = s['views']
        for v in views:
            if not v['inside']:
                found.append(f'{name}: {v["kind"]} is outside the sheet')
            if v['kind'] == 'NSTextField' and v['needed'] > v['h'] + 0.5:
                found.append(f'{name}: the text is cut ({v["h"]:.0f} of {v["needed"]:.0f} points)')
        buttons = [v for v in views if v['kind'] == 'NSButton']
        popup = [v for v in views if v['kind'] == 'NSPopUpButton']
        if buttons and popup:
            gap = popup[0]['y'] - max(b['y'] + b['h'] for b in buttons)
            if abs(gap - 20) > 0.5:
                found.append(f'{name}: {gap:.0f} points between the pop-up menu and the buttons, not 20')
    if len(sizes) < 12:
        found.append(f'only {len(sizes)} languages were measured')
    if len(heights) < 2:
        found.append(f'every language has the same height {heights}: the languages are not told apart')
    return found


def run(mutation=None):
    xib = XIB.read_text(encoding='utf-8')
    source = SOURCE.read_text(encoding='utf-8')
    if mutation:
        path, old, new = MUTATIONS[mutation]
        if path == XIB:
            assert xib.count(old) == 1, mutation
            xib = xib.replace(old, new)
        else:
            assert source.count(old) == 1, mutation
            source = source.replace(old, new)
    with tempfile.TemporaryDirectory(prefix='texshop-encoding-sheet-') as name:
        sizes = measure(Path(name), xib, source)
    return sizes, problems(sizes)


if __name__ == '__main__':
    if '--mutations' in sys.argv or '--mutation' in sys.argv:
        names = list(MUTATIONS) if '--mutations' in sys.argv else [sys.argv[sys.argv.index('--mutation') + 1]]
        missed = []
        for m in names:
            _, found = run(m)
            print(f'DETECTED {m}: {found[0]}' if found else f'MISSED {m}')
            if not found:
                missed.append(m)
        sys.exit(1 if missed else 0)
    sizes, found = run()
    if found:
        print('FAIL:\n' + '\n'.join(found))
        sys.exit(1)
    summary = ', '.join(f'{n[:-4]} {s["w"]:.0f}×{s["h"]:.0f}' for n, s in sorted(sizes.items()))
    print(f'PASS: the Change Encoding sheet fits its contents in {len(sizes)} languages ({summary})')
