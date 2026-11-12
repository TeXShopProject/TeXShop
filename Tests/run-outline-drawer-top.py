#!/usr/bin/env python3
"""The first entries of the outline in the Preview drawer are not hidden under its column header.

The outline view in the drawer has a column header. Its clip view starts above 0, so that the
first entry is right below the header. The drawer is taken from the compiled TSDocument nib of
every localization, and from the Base nib source compiled again, and shown in a window that is
never ordered on screen, at the size of an open drawer. The outline of the TeXShop Manual is
loaded through the production methods of MyPDFKitView: when the document opens, when the
drawer is opened (toggleDrawer: rebuilds the outline), and after typesetting, when the PDF is
read again. The first entry must stay right below the header each time, and a position
scrolled to inside the outline must be kept. --png DIR writes the drawer after typesetting in
Light and Dark Mode.
"""
from pathlib import Path
import argparse
import os
import subprocess
import sys
import tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

KEEP = '        bounds.origin = origin;\n        bounds = [clipView constrainBoundsRect:bounds];\n'
MUTATIONS = {
    # The position kept by beta-6 to beta-7: 0 is below the header.
    'clamp-at-zero': (KEEP, '        CGFloat maxY = MAX(0, NSHeight(outlineView.frame) - NSHeight(clipView.bounds));\n'
                            '        bounds.origin = NSMakePoint(0, MIN(MAX(origin.y, 0), maxY));\n'),
    'always-top': (KEEP, '        bounds.origin = NSMakePoint(origin.x, -1e6);\n        bounds = [clipView constrainBoundsRect:bounds];\n'),
    'header-height-guessed': (KEEP, '        bounds.origin = NSMakePoint(origin.x, MAX(origin.y, -17));\n'
                                    '        bounds = [clipView constrainBoundsRect:bounds];\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--png', help='directory for images of the drawer')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib'))
assert len(nibs) == 12, nibs
manual = root / 'DocumentSources/Manual Source/Manual.pdf'
assert manual.exists(), manual

view = source_file(root, 'MyPDFKitView.m').read_text(encoding='latin1')
signatures = ['- (void) setupOutline',
              '- (void) didUnlock',
              '- (IBAction) toggleDrawer: (id) sender',
              '- (NSInteger) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem:',
              '- (id) outlineView: (NSOutlineView *) outlineView child:',
              '- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable:',
              '- (id) outlineView: (NSOutlineView *) outlineView objectValueForTableColumn:']
fragments = [method(view, signature) for signature in signatures]
expansion = source_file(root, 'TSOutlineExpansion.m').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert expansion.count(old) == 1, args.mutation
    expansion = expansion.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSOutlineExpansion.h"
#import "TestAppKitIsolation.h"
#define SUD [NSUserDefaults standardUserDefaults]
NSString *UseOutlineKey = @"UseOutline";

// The nib's owner, a TSDocument in the application.
@interface Owner : NSObject
@end
@implementation Owner
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
@end

// Stands in for the NSDrawer, which opens only next to a window on screen.
// Its content view is put in a window that is never ordered on screen.
@interface DrawerStandIn : NSObject
@property NSInteger toggles;
@end
@implementation DrawerStandIn
- (void)toggle:(id)sender { self.toggles++; }
@end

// The parts of MyPDFKitView that build the drawer's outline, verbatim.
@interface PreviewHarness : NSObject <NSOutlineViewDataSource> {
    NSOutlineView *_outlineView;
    id _drawer;
}
@property (retain) PDFOutline *outline;
@property (retain) TSOutlineExpansion *outlineExpansion;
@property (strong) PDFDocument *shownDocument;
@end
@implementation PreviewHarness
- (instancetype)initWithOutlineView:(NSOutlineView *)view drawer:(id)drawer
{
    self = [super init];
    _outlineView = view;
    _drawer = drawer;
    view.dataSource = self;
    return self;
}
- (PDFDocument *)document { return self.shownDocument; }
METHODS
@end

static int failures;
static void Check(BOOL ok, NSString *what) { printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String); if (!ok) failures++; }

static NSOutlineView *FindOutline(NSView *view)
{
    if ([view isKindOfClass:NSOutlineView.class]) return (NSOutlineView *)view;
    for (NSView *sub in view.subviews) { NSOutlineView *found = FindOutline(sub); if (found) return found; }
    return nil;
}

// Where the visible part of the outline begins: below the column header, if there is one.
static CGFloat VisibleTop(NSOutlineView *outline)
{
    NSClipView *clip = outline.enclosingScrollView.contentView;
    NSView *header = outline.headerView;
    if (header == nil || header.window == nil) return NSMinY(clip.bounds);
    return NSMaxY([outline convertRect:header.bounds fromView:header]);
}

// The first row shown in full below the header.
static NSInteger FirstWholeRow(NSOutlineView *outline)
{
    CGFloat top = VisibleTop(outline);
    for (NSInteger row = 0; row < outline.numberOfRows; row++)
        if (NSMinY([outline rectOfRow:row]) >= top - 0.5) return row;
    return -1;
}

static NSString *Label(NSOutlineView *outline, NSInteger row)
{
    return row >= 0 && row < outline.numberOfRows ? [(PDFOutline *)[outline itemAtRow:row] label] : @"(none)";
}

static void CheckTop(NSString *label, NSString *when, NSOutlineView *outline)
{
    NSInteger row = FirstWholeRow(outline);
    Check(outline.numberOfRows > 2 && row == 0,
          [NSString stringWithFormat:@"%@: %@, the first entry \"%@\" is right below the header (first whole row %ld, \"%@\"; clip y %.1f, header %.1f high)",
           label, when, Label(outline, 0), (long)row, Label(outline, row), outline.enclosingScrollView.contentView.bounds.origin.y,
           NSHeight(outline.headerView.frame)]);
}

static void Typeset(PreviewHarness *h, NSString *path)
{
    @autoreleasepool { h.shownDocument = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]]; }
    [h setupOutline];
}

static void Render(NSView *view, NSString *directory, NSString *label)
{
    for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        view.window.appearance = [NSAppearance appearanceNamed:name];
        [view.window displayIfNeeded];
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        NSString *path = [NSString stringWithFormat:@"%@/drawer-%@-%@.png", directory, label,
                          [name isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }
    view.window.appearance = nil;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    [SUD registerDefaults:@{UseOutlineKey: @YES}];
    NSString *manual = @(argv[1]);
    const char *png = getenv("TS_DRAWER_PNG");
    for (int i = 2; i + 1 < argc; i += 2) {
        NSString *label = @(argv[i]);
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i + 1])] bundle:nil];
        Owner *owner = [Owner new];
        NSArray *objects = nil;
        NSDrawer *drawer = nil;
        if ([nib instantiateWithOwner:owner topLevelObjects:&objects])
            for (id object in objects) if ([object isKindOfClass:NSDrawer.class]) drawer = object;
        NSView *content = drawer.contentView;
        NSOutlineView *outline = FindOutline(content);
        Check(outline != nil && outline.enclosingScrollView != nil, [label stringByAppendingString:@": the drawer has the outline view"]);
        if (outline == nil) continue;

        // The size of an open drawer beside a Preview window.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 784) styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        drawer.contentView = [[NSView alloc] init];
        window.contentView = content;
        [window layoutIfNeeded];

        DrawerStandIn *standIn = [DrawerStandIn new];
        PreviewHarness *h = [[PreviewHarness alloc] initWithOutlineView:outline drawer:standIn];
        NSClipView *clip = outline.enclosingScrollView.contentView;

        // The document opens: showWithPath: builds the outline, then the drawer is opened.
        Typeset(h, manual);
        [h toggleDrawer:nil];
        Check(standIn.toggles == 1, [label stringByAppendingString:@": toggleDrawer: toggles the drawer"]);
        CheckTop(label, @"when the drawer is opened for the first time", outline);

        Typeset(h, manual);
        CheckTop(label, @"after typesetting", outline);
        Typeset(h, manual);
        CheckTop(label, @"after typesetting again", outline);

        [h toggleDrawer:nil];
        [h toggleDrawer:nil];
        CheckTop(label, @"after closing and opening the drawer", outline);

        // A chapter opened, and the outline scrolled to its fifth entry: the position is kept.
        id chapter = nil;
        for (NSInteger row = 0; row < outline.numberOfRows && chapter == nil; row++)
            if ([outline isExpandable:[outline itemAtRow:row]]) chapter = [outline itemAtRow:row];
        [outline expandItem:chapter];
        CGFloat header = VisibleTop(outline) - NSMinY(clip.bounds);
        [clip scrollToPoint:NSMakePoint(0, NSMinY([outline rectOfRow:5]) - header)];
        [outline.enclosingScrollView reflectScrolledClipView:clip];
        CGFloat y = NSMinY(clip.bounds);
        NSString *fifth = Label(outline, 5);
        Typeset(h, manual);
        Check(FirstWholeRow(outline) == 5 && fabs(NSMinY(clip.bounds) - y) < 0.5 && [Label(outline, 5) isEqualToString:fifth],
              [NSString stringWithFormat:@"%@: scrolled to \"%@\", the outline stays there after typesetting (clip y %.1f, now %.1f, first whole row %ld)",
               label, fifth, y, NSMinY(clip.bounds), (long)FirstWholeRow(outline)]);

        // Scrolled back to the top by the user: the top stays in view.
        [clip scrollToPoint:NSMakePoint(0, -1e6)];
        [outline.enclosingScrollView reflectScrolledClipView:clip];
        Typeset(h, manual);
        CheckTop(label, @"scrolled back to the top, after typesetting", outline);

        if (png && [label isEqualToString:@"Base compiled"])
            Render(content, @(png), @"after-typesetting");
        Check(!window.isVisible, [label stringByAppendingString:@": nothing is shown on screen"]);
        [outline collapseItem:chapter];
        [window close];
        for (id object in objects) if ([object isKindOfClass:NSWindow.class]) [(NSWindow *)object close];
    }
    if (failures) { printf("%d failed\n", failures); return 1; }
    printf("PASS: the first entries of the drawer's outline stay below the header in all %d nibs\n", (argc - 2) / 2);
} return 0; }
'''
program = program.replace('METHODS', '\n'.join(fragments))
verify_embedded(program, [('complete method: ' + signature, view, fragment)
                          for signature, fragment in zip(signatures, fragments)]
                if not args.mutation else [])

with tempfile.TemporaryDirectory(prefix='texshop-outline-drawer-top-') as tmp:
    tmp = Path(tmp)
    pairs = []
    for nib in nibs:
        locale = nib.parent.name.split('.')[0]
        pairs += [f'{locale} compiled', str(nib / 'keyedobjects.nib')]
    xib, out = tmp / 'Base.xib', tmp / 'Base.nib'
    xib.write_text((root / 'Resources/Interfaces/Base.lproj/TSDocument.nib/designable.nib').read_text(encoding='utf-8'), encoding='utf-8')
    subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(xib)], check=True, stdout=subprocess.DEVNULL)
    pairs += ['Base source', str(out / 'keyedobjects.nib' if out.is_dir() else out)]
    (tmp / 'test.m').write_text(program, encoding='utf-8')
    (tmp / 'TSOutlineExpansion.m').write_text(expansion, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=14.6', '-w', '-fobjc-arc', '-framework', 'Cocoa',
                    '-framework', 'PDFKit', '-framework', 'Quartz', '-I', str(root / 'Tests'), *include_args(root),
                    str(tmp / 'test.m'), str(tmp / 'TSOutlineExpansion.m'), '-o', str(tmp / 'test')], check=True)
    (tmp / 'home/Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(tmp / 'home'), CFFIXED_USER_HOME=str(tmp / 'home'))
    if args.png:
        Path(args.png).mkdir(parents=True, exist_ok=True)
        env['TS_DRAWER_PNG'] = str(Path(args.png).resolve())
    result = subprocess.run([str(tmp / 'test'), str(manual), *pairs], capture_output=True, text=True, timeout=300, env=env)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr[-3000:])
        sys.exit('FAIL')
