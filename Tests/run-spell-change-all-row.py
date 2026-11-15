#!/usr/bin/env python3
"""The Change All row below the Spelling and Grammar panel follows the panel.

Puts the production row (TSChangeAllAccessory and FitChangeAllRow) into the
real system panel, off screen, and resizes the panel to its default width,
wider and narrower. The replacement field must keep the edges of the panel's
language pop-up, Change All those of the panel's Change button, and the row
must leave 16 points below the field, as the panel leaves below the pop-up
without the row, and 12 points between the field and the pop-up.
--mutation applies a known defect; the check must then fail.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--mutation', choices=['no-fit', 'fixed-field', 'tall-row'])
args = p.parse_args()

source = (root / 'Sources/Editor/TSSpellSupport.m').read_text(encoding='utf-8')
begin, end = '// BEGIN change all accessory', '// END change all accessory'
block = source[source.index(begin):source.index(end) + len(end)]
assert 'FitChangeAllRow(accessory);' in source, 'the application fits the row to the panel'

mutations = {
    'no-fit': ('    if (!container) return;', '    if (container) return;'),
    'fixed-field': ('    replacement.autoresizingMask = NSViewWidthSizable;', '    replacement.autoresizingMask = NSViewMaxXMargin;'),
    'tall-row': ('NSMakeRect(0, 0, 431, 36)', 'NSMakeRect(0, 0, 431, 76)'),
}
if args.mutation:
    old, new = mutations[args.mutation]
    assert block.count(old) == 1, args.mutation
    block = block.replace(old, new)

program = r'''
#import <AppKit/AppKit.h>
''' + block + r'''
@interface Target : NSObject @end
@implementation Target - (void)changeAll:(id)sender {} @end
static id Find(NSView *view, Class cls, NSString *title, NSView *skip) {
    if (view == skip) return nil;
    if ([view isKindOfClass:cls] && (!title || [[(id)view title] isEqual:title])) return view;
    for (NSView *child in view.subviews) { id found = Find(child, cls, title, skip); if (found) return found; }
    return nil;
}
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.6; }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSSpellChecker *checker = NSSpellChecker.sharedSpellChecker;
    NSPanel *panel = checker.spellingPanel;
    if (panel.isVisible) { printf("ERROR the spelling panel is on screen\n"); return 2; }
    NSTextField *field = nil, *status = nil;
    NSView *row = TSChangeAllAccessory([Target new], &field, &status);
    NSButton *changeAll = Find(row, NSButton.class, nil, nil);
    checker.accessoryView = row;
    FitChangeAllRow(row);
    NSPopUpButton *popUp = Find(panel.contentView, NSPopUpButton.class, nil, row);
    NSButton *change = Find(panel.contentView, NSButton.class, @"Change", row);
    if (!popUp || !change || !changeAll) { printf("ERROR the panel's controls were not found\n"); checker.accessoryView = nil; return 2; }
    NSRect start = panel.frame;
    CGFloat widths[] = {0, 500, -110, 0};
    const char *names[] = {"default", "wider", "narrower", "default again"};
    for (int i = 0; i < 4; i++) {
        NSRect frame = start;
        frame.size.width = MAX(NSWidth(start) + widths[i], panel.minSize.width);
        frame.size.height = NSHeight(start) + (i == 1 ? 200 : 0);
        [panel setFrame:frame display:NO];
        [panel.contentView layoutSubtreeIfNeeded];
        NSRect p = [popUp convertRect:popUp.bounds toView:nil], f = [field convertRect:field.bounds toView:nil];
        NSRect c = [change convertRect:change.bounds toView:nil], a = [changeAll convertRect:changeAll.bounds toView:nil];
        NSString *at = [NSString stringWithFormat:@" (%s, panel %.0f wide)", names[i], NSWidth(frame)];
        Check(Near(NSMinX(f), NSMinX(p)) && Near(NSMaxX(f), NSMaxX(p)), [@"the replacement field keeps the pop-up's edges" stringByAppendingString:at]);
        Check(Near(NSMinX(a), NSMinX(c)) && Near(NSMaxX(a), NSMaxX(c)) && Near(NSHeight(a), NSHeight(c)), [@"Change All keeps the Change button's edges" stringByAppendingString:at]);
        Check(Near(NSMidY(a), NSMidY(f)), [@"Change All is centered on the field" stringByAppendingString:at]);
        Check(Near(NSMinY(f), 16), [NSString stringWithFormat:@"16 points below the field, not %.1f%@", NSMinY(f), at]);
        Check(Near(NSMinY(p) - NSMaxY(f), 12), [NSString stringWithFormat:@"12 points between the field and the pop-up, not %.1f%@", NSMinY(p) - NSMaxY(f), at]);
        Check(NSMaxX(a) <= NSWidth(panel.contentView.bounds) && NSMinX(f) >= 0, [@"the row stays inside the panel" stringByAppendingString:at]);
    }
    checker.accessoryView = nil;
    if (failures) return 1;
    printf("PASS: the Change All row keeps the panel's columns at its default width, wider and narrower, 16 points from the bottom and 12 below the pop-up\n");
}}
'''

with tempfile.TemporaryDirectory(prefix='texshop-change-all-row-') as td:
    t = Path(td)
    (t / 'row.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'AppKit', str(t / 'row.m'), '-o', str(t / 'probe')], check=True)
    home = t / 'home'; (home / 'Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    result = subprocess.run([str(t / 'probe')], env=env, timeout=60, capture_output=True, text=True)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 1:
            print(f'mutation {args.mutation} detected')
            raise SystemExit(0)
        print(f'FAIL: mutation {args.mutation} not detected')
        raise SystemExit(1)
    raise SystemExit(result.returncode)
