#!/usr/bin/env python3
"""The buttons of the OgreKit Find panel do not touch or overlap, in every language.

OgreKit's Find panel placed its eight push buttons edge to edge with the margins that
buttons had in older macOS. Buttons now draw to the edges of their frames, so their
bezels overlapped. The sources of the panel (3rdparty/OgreKit-2.1.12-FindPanel) place
them as small buttons, 20 points high, 8 points apart, aligned with the boxes above,
each as wide as its title needs; Scripts/compile-ogrekit-find-panel.py compiles them
into the bundled framework.

The compiled nib of every localization in Frameworks/OgreKit.framework is loaded with
the real OgreKit, as the application loads it, and so is each source compiled again,
so that the two agree. The panel is measured at its size in the nib and widened.
Windows are never ordered on screen. Each panel is also drawn in Dark Mode into a folder
with a Japanese name, and the test checks that all the images were written; --png DIR
keeps them in DIR."""
from pathlib import Path
import argparse, os, re, subprocess, sys, tempfile

LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'nl', 'pt', 'ro']
MUTATIONS = {
    # The bundled layout, which drew the buttons over each other.
    'old-frames': ('ja', 'x="17" y="36" width="112" height="20"', 'x="15" y="29" width="120" height="28"'),
    'touching': ('es', 'x="131" y="36" width="132" height="20"', 'x="123" y="36" width="140" height="20"'),
    'clipped-title': ('fr', 'x="507" y="36" width="172" height="20"', 'x="527" y="36" width="152" height="20"'),
    'regular-size': ('de', 'title="Mehr Optionen" bezelStyle="rounded" alignment="center" controlSize="small"',
                     'title="Mehr Optionen" bezelStyle="rounded" alignment="center"'),
    'right-group-fixed': ('Base', 'flexibleMinX="YES" flexibleMaxY="YES"/>\n                        <buttonCell key="cell" type="push" title="Replace &amp; Find"',
                          'flexibleMaxY="YES"/>\n                        <buttonCell key="cell" type="push" title="Replace &amp; Find"'),
    # A source edited without compiling it into the framework.
    'stale-framework': ('it', 'x="17" y="8" width="111" height="20"', 'x="17" y="9" width="111" height="20"'),
}
# The image path as the first version of this test built it, which loses non-ASCII folder names.
IMAGE_PATH = '[png stringByAppendingPathComponent:[language stringByAppendingPathExtension:@"png"]]'
ASCII_IMAGE_PATH = '[NSString stringWithFormat:@"%s/%@.png", png.UTF8String, language]'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted([*MUTATIONS, 'ascii-image-path']))
parser.add_argument('--png', help='directory for images of the panels')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
frameworks = root / 'Frameworks'
resources = frameworks / 'OgreKit.framework/Versions/A/Resources'
sources = root / '3rdparty/OgreKit-2.1.12-FindPanel'

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
// The nib's owner is OgreTextFinder; whatever the panel controller asks of it answers nothing.
@interface Owner : NSObject
@end
@implementation Owner
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (id)valueForUndefinedKey:(NSString *)key { return nil; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{ return [super methodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"@@:@"]; }
- (void)forwardInvocation:(NSInvocation *)invocation
{ id nothing = nil; if (invocation.methodSignature.methodReturnLength) [invocation setReturnValue:&nothing]; }
@end
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { printf("FAIL: %s\n", what.UTF8String); failures++; } }
static void Collect(NSView *view, NSMutableArray *buttons) {
    for (NSView *sub in view.subviews) {
        if ([sub isKindOfClass:NSButton.class] && ((NSButton *)sub).bezelStyle == NSBezelStyleRounded && !sub.isHidden)
            [buttons addObject:sub];
        Collect(sub, buttons);
    }
}
static NSRect Frame(NSView *view) { return [view convertRect:view.bounds toView:nil]; }
// The visible boxes above the buttons (Options, Origin, Scope): their outer edges.
static NSRect Boxes(NSView *content) {
    NSRect all = NSZeroRect;
    for (NSView *sub in content.subviews)
        if ([sub isKindOfClass:NSBox.class] && !sub.isHidden && NSMinY(sub.frame) < 100)
            all = NSIsEmptyRect(all) ? sub.frame : NSUnionRect(all, sub.frame);
    return all;
}
static NSString *Layout(NSArray *buttons) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSButton *button in [buttons sortedArrayUsingComparator:^(NSButton *a, NSButton *b) { return [a.title compare:b.title]; }])
        [parts addObject:[NSString stringWithFormat:@"%@ %@", button.title, NSStringFromRect(Frame(button))]];
    return [parts componentsJoinedByString:@"; "];
}
static NSString *Measure(NSString *label, NSWindow *window) {
    NSView *content = window.contentView;
    NSMutableArray *buttons = [NSMutableArray array];
    Collect(content, buttons);
    Check(buttons.count == 8, [NSString stringWithFormat:@"%@: eight push buttons (%lu)", label, (unsigned long)buttons.count]);
    NSRect boxes = Boxes(content);
    CGFloat left = CGFLOAT_MAX, right = 0;
    for (NSButton *button in buttons) {
        NSRect r = Frame(button);
        Check(button.controlSize == NSControlSizeSmall && fabs(NSHeight(r) - 20) < 0.5,
              [NSString stringWithFormat:@"%@: %@ is a small button, 20 points high", label, button.title]);
        Check(button.intrinsicContentSize.width <= NSWidth(r) + 0.5,
              [NSString stringWithFormat:@"%@: the title of %@ fits (%.0f in %.0f)", label, button.title, button.intrinsicContentSize.width, NSWidth(r)]);
        Check(NSMaxY(r) + 8 <= NSMinY(boxes) + 0.5, [NSString stringWithFormat:@"%@: %@ stays below the boxes", label, button.title]);
        Check(NSMinY(r) >= 8 - 0.5, [NSString stringWithFormat:@"%@: %@ stays 8 points above the bottom", label, button.title]);
        left = MIN(left, NSMinX(r)); right = MAX(right, NSMaxX(r));
        for (NSButton *other in buttons) {
            if (other == button) continue;
            NSRect o = Frame(other);
            Check(!NSIntersectsRect(NSInsetRect(r, -3.5, -3.5), o),
                  [NSString stringWithFormat:@"%@: %@ and %@ are apart", label, button.title, other.title]);
            if (fabs(NSMinY(o) - NSMinY(r)) < 0.5 && NSMinX(o) > NSMinX(r))
                Check(NSMinX(o) - NSMaxX(r) >= 8 - 0.5, [NSString stringWithFormat:@"%@: 8 points between %@ and %@", label, button.title, other.title]);
            if (fabs(NSMinX(o) - NSMinX(r)) < 0.5 && NSMinY(o) > NSMinY(r))
                Check(NSMinY(o) - NSMaxY(r) >= 8 - 0.5, [NSString stringWithFormat:@"%@: 8 points between the rows at %@", label, button.title]);
        }
    }
    Check(fabs(left - NSMinX(boxes)) < 0.5 && fabs(right - NSMaxX(boxes)) < 0.5,
          [NSString stringWithFormat:@"%@: the buttons line up with the boxes (%.0f-%.0f, boxes %.0f-%.0f)", label, left, right, NSMinX(boxes), NSMaxX(boxes)]);
    // Each row spans the boxes, and each button sits above or below the one in its column.
    for (NSButton *button in buttons) {
        NSRect r = Frame(button);
        CGFloat rowLeft = CGFLOAT_MAX, rowRight = 0; BOOL column = NO;
        for (NSButton *other in buttons) {
            NSRect o = Frame(other);
            if (fabs(NSMinY(o) - NSMinY(r)) < 0.5) { rowLeft = MIN(rowLeft, NSMinX(o)); rowRight = MAX(rowRight, NSMaxX(o)); }
            else if (fabs(NSMinX(o) - NSMinX(r)) < 0.5 && fabs(NSWidth(o) - NSWidth(r)) < 0.5) column = YES;
        }
        Check(fabs(rowLeft - NSMinX(boxes)) < 0.5 && fabs(rowRight - NSMaxX(boxes)) < 0.5,
              [NSString stringWithFormat:@"%@: the row of %@ spans the boxes", label, button.title]);
        Check(column, [NSString stringWithFormat:@"%@: %@ lines up with the button in the other row", label, button.title]);
    }
    return Layout(buttons);
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    NSString *png = getenv("TS_OGRE_PNG") ? [NSString stringWithUTF8String:getenv("TS_OGRE_PNG")] : nil;
    NSMutableDictionary *layouts = [NSMutableDictionary dictionary];
    for (int i = 1; i + 2 < argc; i += 3) {
        NSString *language = @(argv[i]), *kind = @(argv[i + 1]), *label = [NSString stringWithFormat:@"%@ %@", language, kind];
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i + 2])] bundle:nil];
        NSArray *objects = nil;
        Owner *owner = [Owner new];
        Check([nib instantiateWithOwner:owner topLevelObjects:&objects], [label stringByAppendingString:@": loads"]);
        NSWindow *window = nil;
        for (id object in objects)
            if ([object isKindOfClass:NSWindow.class] && [object contentView].frame.size.height == 298) window = object;
        Check(window != nil, [label stringByAppendingString:@": the Find panel is in the nib"]);
        if (!window) continue;
        window.frameAutosaveName = @"";
        NSString *layout = Measure(label, window);
        if (layouts[language])
            Check([layouts[language] isEqual:layout], [NSString stringWithFormat:@"%@: the framework is compiled from the source\n  framework %@\n  source    %@", language, layouts[language], layout]);
        layouts[language] = layout;
        if (png && [kind isEqual:@"framework"]) {
            window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            [window displayIfNeeded];
            NSView *view = window.contentView.superview;
            NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
            NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *path = [png stringByAppendingPathComponent:[language stringByAppendingPathExtension:@"png"]];
            Check(data.length > 0 && [data writeToFile:path atomically:YES], [label stringByAppendingString:@": the image is written"]);
        }
        [window setContentSize:NSMakeSize(window.contentView.frame.size.width + 240, window.contentView.frame.size.height)];
        Measure([label stringByAppendingString:@" widened"], window);
        Check(!window.isVisible, [label stringByAppendingString:@": not shown"]);
        for (id object in objects) if ([object isKindOfClass:NSWindow.class]) [(NSWindow *)object close];
    }
    if (failures) return 1;
    printf("PASS: the OgreKit Find panel's buttons are apart and fit their titles in all %lu localizations, framework and sources\n",
           (unsigned long)layouts.count);
} return 0; }
'''

with tempfile.TemporaryDirectory(prefix='texshop-ogrekit-find-panel-') as tmp:
    tmp = Path(tmp)
    triples = []
    for language in LANGUAGES:
        nib_dir = resources / f'{language}.lproj/OgreAdvancedFindPanel.nib'
        compiled = sorted(p.name for p in nib_dir.glob('keyedobjects*.nib'))
        assert compiled == ['keyedobjects.nib'], (language, compiled)  # no older variant that macOS would prefer
        source = (sources / f'{language}.lproj/OgreAdvancedFindPanel.xib').read_text(encoding='utf-8')
        if args.mutation in MUTATIONS and MUTATIONS[args.mutation][0] == language:
            _, old, new = MUTATIONS[args.mutation]
            assert source.count(old) == 1, args.mutation
            source = source.replace(old, new)
        xib, out = tmp / f'{language}.xib', tmp / f'{language}.nib'
        xib.write_text(source, encoding='utf-8')
        subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(xib)], check=True, stdout=subprocess.DEVNULL)
        if args.mutation in (None, 'stale-framework', 'ascii-image-path'):
            triples += [language, 'framework', str(nib_dir / 'keyedobjects.nib')]
        triples += [language, 'source', str(out / 'keyedobjects.nib' if out.is_dir() else out)]
    if args.mutation == 'ascii-image-path':
        assert program.count(IMAGE_PATH) == 1
        program = program.replace(IMAGE_PATH, ASCII_IMAGE_PATH)
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Tests'),
                    '-F', str(frameworks), '-framework', 'OgreKit', str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], check=True)
    (tmp / 'home/Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(tmp / 'home'), CFFIXED_USER_HOME=str(tmp / 'home'), DYLD_FRAMEWORK_PATH=str(frameworks))
    images = Path(args.png).resolve() if args.png else tmp / '検索パネルの画像'
    images.mkdir(parents=True, exist_ok=True)
    for old in images.glob('*.png'):
        old.unlink()
    env['TS_OGRE_PNG'] = str(images)
    result = subprocess.run([str(tmp / 'probe'), *triples], capture_output=True, text=True, timeout=300, env=env)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr[-3000:])
        sys.exit('FAIL')
    else:
        written = sorted(p.stem for p in images.glob('*.png') if p.stat().st_size > 0)
        if written != sorted(LANGUAGES):
            sys.exit(f'FAIL: images of the panels were not all written to {images}: {written}')
        print(f'PASS: images of the panels in all {len(written)} localizations written to {images.name}')
