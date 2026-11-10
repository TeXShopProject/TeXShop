#!/usr/bin/env python3
"""Every label in every localized window and panel shows its whole text.

Loads each compiled interface without ordering a window and measures each
non-editable label with its own cell: a single-line label must be as wide as
its text, and a wrapping label must hold its text in its height. Trailing line
breaks in titles are ignored. Buttons are not measured: their bezel padding is
not part of the visible text. Placeholder titles replaced at run time
("Button") are skipped. The Settings window is composed from its own labels
and is checked by run-settings-product-shell.py."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
@interface FitOwner : NSObject @end
@implementation FitOwner
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (id)valueForUndefinedKey:(NSString *)k { return nil; }
@end
static int problems;
static void Walk(NSView *v, NSString *nib) {
    if (v.isHidden) return;
    if ([v isKindOfClass:NSTextField.class] && !((NSTextField *)v).isEditable) {
        NSString *text = [[(NSTextField *)v stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
        if (text.length && ![text isEqual:@"Button"]) {
            NSTextFieldCell *cell = [[(NSTextField *)v cell] copy];
            cell.stringValue = text;
            NSRect b = v.bounds;
            BOOL wraps = (cell.lineBreakMode == NSLineBreakByWordWrapping || cell.lineBreakMode == NSLineBreakByCharWrapping) && !cell.usesSingleLineMode;
            CGFloat need = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, b.size.width, CGFLOAT_MAX)].height : cell.cellSize.width;
            CGFloat have = wraps ? b.size.height : b.size.width;
            if (need > have + 1) { printf("CLIPPED %s \"%s\": needs %.1f, has %.1f\n", nib.UTF8String, text.UTF8String, need, have); problems++; }
        }
    }
    for (NSView *s in v.subviews) Walk(s, nib);
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    int count = 0;
    for (int i = 1; i < argc; i++) {
        NSString *path = @(argv[i]);
        NSData *data = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"keyedobjects.nib"]] ?: [NSData dataWithContentsOfFile:path];
        NSArray *objects = nil;
        [[[NSNib alloc] initWithNibData:data bundle:nil] instantiateWithOwner:[FitOwner new] topLevelObjects:&objects];
        for (id o in objects) {
            if ([o isKindOfClass:NSWindow.class]) Walk([(NSWindow *)o contentView], path);
            else if ([o isKindOfClass:NSView.class]) Walk(o, path);
        }
        count++;
    }
    if (problems) return 1;
    printf("PASS: labels fit their text in %d localized interfaces\n", count);
} return 0; }
'''
nibs = [str(p) for p in sorted(interfaces.glob('*.lproj/*.nib')) if p.name not in ('Preferences.nib', 'Movie.nib')]
with tempfile.TemporaryDirectory(prefix='texshop-label-fit-') as tmp:
    tmp = Path(tmp)
    (tmp / 'fit.m').write_text(program)
    xibs = []
    # Settings*.xib only supply controls: the Settings window builds its own labels
    # from SettingsCategories.strings (run-settings-product-shell.py covers them).
    for xib in sorted(x for x in interfaces.glob('*.lproj/*.xib') if not x.name.startswith('Settings')):
        out = tmp / (xib.parent.name + '-' + xib.stem + '.nib')
        subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(xib)], check=True, stdout=subprocess.DEVNULL)
        xibs.append(str(out))
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'AVKit', '-framework', 'WebKit',
                    '-I', str(root / 'Tests'), str(tmp / 'fit.m'), '-o', str(tmp / 'fit')], check=True)
    result = subprocess.run([str(tmp / 'fit'), *nibs, *xibs], capture_output=True, text=True, timeout=600)
    print(result.stdout, end='')
    sys.exit(result.returncode)
