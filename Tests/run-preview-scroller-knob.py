#!/usr/bin/env python3
"""Scrollers take a knob that contrasts with the pages.

A light page gets a dark knob, so Dark Mode does not draw white on white.
An inverted page gets a light knob. A legacy scroller does the same: on a
light page its system knob is nearly the color of the light gutter.
The document preview and the Experiment preview apply that choice again when
the system scroller style changes.
"""
from pathlib import Path
import argparse, os, subprocess, tempfile
from source_tree import include_args

MUTATIONS = {
    'knob-not-matched': (
        'TSPreviewAppearance.h',
        '    TSPreviewMatchScrollerKnob(scrollView, invert);\n',
        '',
    ),
    'overlay-knob-swapped': (
        'TSPreviewAppearance.h',
        '    NSScrollerKnobStyle style = invert ? NSScrollerKnobStyleLight : NSScrollerKnobStyleDark;\n',
        '    NSScrollerKnobStyle style = invert ? NSScrollerKnobStyleDark : NSScrollerKnobStyleLight;\n',
    ),
    'fullscreen-gutter-stays-light': (
        'TSPreviewAppearance.h',
        '        if (TSPreviewFullScreenChromeIsDark(scrollView) && !invert) {\n'
        '            subview.appearance = nil;\n'
        '            subview.contentFilters = @[];\n'
        '        } else {\n'
        '            subview.appearance = light;\n'
        '            subview.contentFilters = filters;\n'
        '        }\n',
        '        subview.appearance = light;\n'
        '        subview.contentFilters = filters;\n',
    ),
    'fullscreen-fail-stays-dark': (
        'MyPDFKitView.m',
        '    TSPreviewUseDarkFullScreenChrome(self.myPDFWindow, NO);\n}\n\n\n- (NSDrawer *)drawer',
        '}\n\n\n- (NSDrawer *)drawer',
    ),
    'fullscreen-paper-follows-window': (
        'MyPDFKitView.m',
        '        choosing = NSApp.effectiveAppearance;\n',
        '        choosing = self.effectiveAppearance;\n',
    ),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root/'Sources/Preview/TSPreviewAppearance.h').read_text(encoding='utf-8')
document = (root/'Sources/Preview/MyPDFKitView.m').read_text(encoding='utf-8')
experiment = (root/'Sources/Preview/ScrapPDFKitView.m').read_text(encoding='utf-8')
def method_body(source, marker):
    if source.count(marker) != 1:
        return ''
    return source.split(marker, 1)[1].split('\n}\n', 1)[0]

def fullscreen_product_calls(source):
    fail = method_body(source, '- (void)windowDidFailToEnterFullScreen:(NSNotification *)notification')
    enter = method_body(source, '- (void)windowWillEnterFullScreen:(NSNotification *)notification')
    leave = method_body(source, '- (void)windowWillExitFullScreen:(NSNotification *)notification')
    paper = method_body(source, '- (void)updatePreviewPaperColor')
    dark = 'TSPreviewUseDarkFullScreenChrome(self.myPDFWindow, YES)'
    clear = 'TSPreviewUseDarkFullScreenChrome(self.myPDFWindow, NO)'
    if clear not in fail or enter.count(dark) != 2 or leave.count(clear) != 2:
        return False
    if enter.find(dark) > enter.find('enterFullScreen:') or enter.rfind(dark) < enter.find('enterFullScreen:'):
        return False
    if leave.find(clear) > leave.find('exitFullScreen:') or leave.rfind(clear) < leave.find('exitFullScreen:'):
        return False
    # The paper call also names NSApp.effectiveAppearance. Require the assignment
    # that runs only while the full-screen flag is set.
    paper_guard = (
        'if (objc_getAssociatedObject(self.window, TSPreviewFullScreenDarkKey) != nil)\n'
        '        choosing = NSApp.effectiveAppearance;'
    )
    return paper_guard in paper

if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    if name == 'TSPreviewAppearance.h':
        assert header.count(old) == 1, args.mutation
        header = header.replace(old, new)
    elif name == 'MyPDFKitView.m':
        assert document.count(old) == 1, args.mutation
        document = document.replace(old, new)
    else:
        raise SystemExit(args.mutation)
assert 'name:NSPreferredScrollerStyleDidChangeNotification object:nil];' in document, 'document preview watches the scroller style'
assert 'name:NSPreferredScrollerStyleDidChangeNotification object:nil];' in experiment, 'experiment preview watches the scroller style'

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
HEADER
static int checks;
static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    checks++;
}
static NSScrollView *Scroll(NSScrollerStyle style) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 240, 240)];
    scroll.scrollerStyle = style;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.documentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1600)];
    return scroll;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSScrollView *overlay = Scroll(NSScrollerStyleOverlay);
        TSApplyPreviewInversion(overlay, NO);
        check(overlay.scrollerKnobStyle == NSScrollerKnobStyleDark, "a light page has a dark overlay knob");
        check(overlay.verticalScroller.knobStyle == NSScrollerKnobStyleDark, "the vertical knob is dark");
        check(overlay.horizontalScroller.knobStyle == NSScrollerKnobStyleDark, "the horizontal knob is dark");
        TSApplyPreviewInversion(overlay, YES);
        check(overlay.scrollerKnobStyle == NSScrollerKnobStyleLight, "an inverted page has a light overlay knob");
        check(overlay.verticalScroller.knobStyle == NSScrollerKnobStyleLight && overlay.horizontalScroller.knobStyle == NSScrollerKnobStyleLight, "both inverted knobs are light");
        NSScrollView *legacy = Scroll(NSScrollerStyleLegacy);
        TSApplyPreviewInversion(legacy, NO);
        check(legacy.scrollerKnobStyle == NSScrollerKnobStyleDark, "a light page has a dark legacy knob");
        check(legacy.verticalScroller.knobStyle == NSScrollerKnobStyleDark && legacy.horizontalScroller.knobStyle == NSScrollerKnobStyleDark, "both legacy knobs are dark");
        TSApplyPreviewInversion(legacy, YES);
        check(legacy.scrollerKnobStyle == NSScrollerKnobStyleLight, "an inverted page has a light legacy knob");
        check(legacy.verticalScroller.knobStyle == NSScrollerKnobStyleLight && legacy.horizontalScroller.knobStyle == NSScrollerKnobStyleLight, "both inverted legacy knobs are light");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 320)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSScrollView *full = Scroll(NSScrollerStyleLegacy);
        NSView *gutter = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 200)];
        [full addSubview:gutter];
        [window.contentView addSubview:full];
        TSApplyPreviewInversion(full, NO);
        check([gutter.appearance.name isEqualToString:NSAppearanceNameAqua], "outside full screen the gutter is light");
        TSPreviewUseDarkFullScreenChrome(window, YES);
        check([window.appearance.name isEqualToString:NSAppearanceNameDarkAqua], "full screen uses the dark appearance");
        check(gutter.appearance == nil, "full screen leaves the gutter on the dark window");
        check(full.scrollerKnobStyle == NSScrollerKnobStyleDark, "a light page keeps a dark knob in full screen");
        check(full.verticalScroller.appearance == nil && full.contentView.appearance == nil, "the scroller and the clip stay unset in full screen");
        TSApplyPreviewInversion(full, YES);
        check([gutter.appearance.name isEqualToString:NSAppearanceNameAqua], "an inverted page still draws the gutter light");
        check(full.scrollerKnobStyle == NSScrollerKnobStyleLight, "an inverted page keeps a light knob in full screen");
        TSApplyPreviewInversion(full, NO);
        check(gutter.appearance == nil, "a light page in full screen keeps the gutter on the dark window");
        TSPreviewUseDarkFullScreenChrome(window, NO);
        check(window.appearance == nil, "leaving full screen follows the system");
        check([gutter.appearance.name isEqualToString:NSAppearanceNameAqua], "leaving full screen draws the gutter light");
        printf("PASS: %d scroller knob checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('HEADER', header)
with tempfile.TemporaryDirectory(prefix='texshop-scroller-knob-') as temp:
    temp = Path(temp)
    (temp/'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-I', str(root/'Tests'), *include_args(root),
                    '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'PDFKit',
                    str(temp/'test.m'), '-o', str(temp/'test')], check=True)
    result = subprocess.run([str(temp/'test')], capture_output=True, text=True, timeout=60,
                            env=dict(os.environ, HOME=str(temp)))
    source_ok = fullscreen_product_calls(document)
    if args.mutation:
        if MUTATIONS[args.mutation][0] == 'MyPDFKitView.m':
            assert result.returncode == 0, result.stdout + result.stderr
            assert not source_ok, 'mutation was not detected'
        else:
            assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    else:
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        if not source_ok:
            raise SystemExit('FAIL: a failed full screen leaves the dark appearance')
        print(result.stdout.strip())
