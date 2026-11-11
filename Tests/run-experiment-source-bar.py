#!/usr/bin/env python3
"""The bar below the Experiment source is narrow, as the thin frames of the Experiment
windows are: a small Typeset button, 5 points from the bottom and from the source above
it and 20 points from the right edge, clear of the corner where the window is resized,
and wide enough for its title in every language.

The compiled TSDocument nib of every localization is loaded, as the application loads
it, and the Experiment source window is measured at its size in the nib and after it is
resized. The nib sources (designable.nib) are compiled again in a temporary directory
and measured too, so that the two agree. Windows are never ordered on screen;
--png DIR writes what the bar looks like in Light and Dark Mode."""
from pathlib import Path
import argparse, os, re, shutil, subprocess, sys, tempfile

MUTATIONS = {
    'tall-bar': ('ja', '<rect key="frame" x="-1" y="30" width="278" height="349"/>', '<rect key="frame" x="-1" y="54" width="278" height="325"/>'),
    'regular-button': ('Base', ' controlSize="small" borderStyle="border"', ' borderStyle="border"'),
    'clipped-title': ('ja', 'x="175" y="5" width="81" height="20"', 'x="196" y="5" width="60" height="20"'),
    'near-corner': ('fr', 'x="182" y="5" width="74" height="20"', 'x="194" y="5" width="74" height="20"'),
    'fixed-button': ('de', 'flexibleMinX="YES" flexibleMaxY="YES"/>\n                        <buttonCell key="cell" type="push" title="Compila"',
                     'flexibleMaxY="YES"/>\n                        <buttonCell key="cell" type="push" title="Compila"'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--png', help='directory for images of the bar')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib'))
assert len(nibs) == 12, nibs

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
// The nib's owner, a TSDocument in the application; only the Experiment source window is kept.
@interface Owner : NSObject
@property (strong) NSWindow *scrapWindow;
@end
@implementation Owner
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (void)typesetScrap:(id)sender {}
@end
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { printf("FAIL: %s\n", what.UTF8String); failures++; } }
static NSButton *Typeset(NSView *view) {
    for (NSView *sub in view.subviews)
        if ([sub isKindOfClass:NSButton.class] && ((NSButton *)sub).action == NSSelectorFromString(@"typesetScrap:")) return (NSButton *)sub;
    return nil;
}
static NSScrollView *Source(NSView *view) {
    for (NSView *sub in view.subviews) if ([sub isKindOfClass:NSScrollView.class]) return (NSScrollView *)sub;
    return nil;
}
static void Measure(NSString *label, NSView *content, Owner *owner) {
    NSButton *button = Typeset(content); NSScrollView *source = Source(content);
    Check(button && source && button.target == owner, [label stringByAppendingString:@": the Typeset button, which typesets, and the source are in the window"]);
    if (!button || !source) return;
    NSRect b = button.frame, s = source.frame, c = content.bounds;
    Check(button.controlSize == NSControlSizeSmall && button.bezelStyle == NSBezelStyleRounded,
          [label stringByAppendingString:@": a small push button"]);
    Check(fabs(NSHeight(b) - 20) < 0.5 && fabs(NSMinY(b) - 5) < 0.5, [label stringByAppendingString:@": 20 points high, 5 from the bottom"]);
    Check(fabs(NSMinY(s) - NSMaxY(b) - 5) < 0.5, [label stringByAppendingString:@": 5 points between the button and the source"]);
    Check(fabs(NSMaxX(c) - NSMaxX(b) - 20) < 0.5, [label stringByAppendingString:@": 20 points from the right edge"]);
    Check(NSMaxY(s) >= NSMaxY(c) && NSMinX(s) <= NSMinX(c) && NSMaxX(s) >= NSMaxX(c),
          [label stringByAppendingString:@": the source fills the rest of the window"]);
    Check(button.intrinsicContentSize.width <= NSWidth(b) + 0.5, [label stringByAppendingString:@": the title fits"]);
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    const char *png = getenv("TS_BAR_PNG");
    for (int i = 1; i + 1 < argc; i += 2) {
        NSString *label = @(argv[i]);
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i + 1])] bundle:nil];
        Owner *owner = [Owner new];
        NSArray *objects = nil;
        Check([nib instantiateWithOwner:owner topLevelObjects:&objects] && owner.scrapWindow, [label stringByAppendingString:@": loads"]);
        NSWindow *window = owner.scrapWindow;
        if (!window) continue;
        window.frameAutosaveName = @"";
        Measure(label, window.contentView, owner);
        [window setContentSize:NSMakeSize(520, 640)];
        Measure([label stringByAppendingString:@" resized"], window.contentView, owner);
        Check(!window.isVisible, [label stringByAppendingString:@": not shown"]);
        if (png && [label hasPrefix:@"ja "]) {
            [window setContentSize:NSMakeSize(360, 120)];
            for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                window.appearance = [NSAppearance appearanceNamed:name];
                [window displayIfNeeded];
                NSView *view = window.contentView.superview;  // with the window's background
                NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
                NSString *path = [NSString stringWithFormat:@"%s/bar-%@.png", png, [name isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"];
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
            }
        }
        [window close];
        for (id object in objects) if ([object isKindOfClass:NSWindow.class]) [(NSWindow *)object close];
    }
    if (failures) return 1;
    printf("PASS: the bar below the Experiment source is narrow in all %d localizations, compiled and from the nib sources\n", (argc - 1) / 4);
} return 0; }
'''

with tempfile.TemporaryDirectory(prefix='texshop-experiment-source-bar-') as tmp:
    tmp = Path(tmp)
    pairs = []
    for nib in nibs:
        locale = nib.parent.name.split('.')[0]
        source = (nib / 'designable.nib').read_text(encoding='utf-8')
        if args.mutation and MUTATIONS[args.mutation][0] == locale:
            _, old, new = MUTATIONS[args.mutation]
            assert source.count(old) == 1, args.mutation
            source = source.replace(old, new)
        xib, out = tmp / f'{locale}.xib', tmp / f'{locale}.nib'
        xib.write_text(source, encoding='utf-8')
        subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(xib)], check=True, stdout=subprocess.DEVNULL)
        compiled = out / 'keyedobjects.nib' if out.is_dir() else out
        if not args.mutation:
            pairs += [f'{locale} compiled', str(nib / 'keyedobjects.nib')]
        pairs += [f'{locale} source', str(compiled)]
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Quartz', '-I', str(root / 'Tests'),
                    str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], check=True)
    (tmp / 'home/Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(tmp / 'home'), CFFIXED_USER_HOME=str(tmp / 'home'))
    if args.png:
        Path(args.png).mkdir(parents=True, exist_ok=True)
        env['TS_BAR_PNG'] = str(Path(args.png).resolve())
    result = subprocess.run([str(tmp / 'probe'), *pairs], capture_output=True, text=True, timeout=300, env=env)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr[-3000:])
        sys.exit('FAIL')
