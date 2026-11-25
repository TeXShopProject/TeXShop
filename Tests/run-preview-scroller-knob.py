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
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root/'Sources/Preview/TSPreviewAppearance.h').read_text(encoding='utf-8')
document = (root/'Sources/Preview/MyPDFKitView.m').read_text(encoding='utf-8')
experiment = (root/'Sources/Preview/ScrapPDFKitView.m').read_text(encoding='utf-8')
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, new)
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
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    else:
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())
