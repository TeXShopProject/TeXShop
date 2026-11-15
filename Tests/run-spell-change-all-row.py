#!/usr/bin/env python3
"""The Change All row below the Spelling and Grammar panel follows the panel.

Puts the production row (TSChangeAllAccessory and FitChangeAllRow) into the
real system panel, off screen, in a probe application that has the
localizations TeXShop has, so that AppKit lays the panel out for each language.
For each language the panel is resized to its default width, wider and
narrower. The replacement field must keep the edges of the panel's language
pop-up, Change All those of the panel's Change button, and the row must leave
16 points below the field, as the panel leaves below the pop-up without the
row, and 12 points between the field and the pop-up.
--mutation applies a known defect; the check must then fail.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--mutation', choices=['no-fit', 'no-column', 'no-tie', 'tall-row', 'no-widen'])
args = p.parse_args()

source = (root / 'Sources/Editor/TSSpellSupport.m').read_text(encoding='utf-8')
begin, end = '// BEGIN change all accessory', '// END change all accessory'
block = source[source.index(begin):source.index(end) + len(end)]
assert 'FitChangeAllRow(accessory);' in source, 'the application fits the row to the panel'

mutations = {
    # Negative control for the check itself: without widening the window to the
    # content, the panel's own columns, and the row with them, run out of the
    # window in the languages whose columns need more than the narrowest width.
    'no-widen': ('if (needed > NSWidth([panel contentRectForFrameRect:panel.frame]) + 0.5) { // WIDEN TO CONTENT', 'if (0) { // WIDEN TO CONTENT'),
    'no-fit': ('    if (!container) return;', '    if (container) return;'),
    'no-tie': ('    if (!popUp || !column || !field || !button) return;', '    return;'),
    'no-column': ('[button.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],', ''),
    'tall-row': ('NSMakeRect(0, 0, 431, 36)', 'NSMakeRect(0, 0, 431, 76)'),
}
if args.mutation and args.mutation != 'no-widen':
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
static NSArray<NSButton *> *Buttons(NSView *view, NSView *skip) {
    if (view == skip) return @[];
    NSMutableArray *all = [NSMutableArray array];
    if ([view isKindOfClass:NSButton.class] && ![view isKindOfClass:NSPopUpButton.class] && ((NSButton *)view).bezelStyle == NSBezelStylePush) [all addObject:view];
    for (NSView *child in view.subviews) [all addObjectsFromArray:Buttons(child, skip)];
    return all;
}
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.6; }
static NSRect Edges(NSView *v) { return [v.superview convertRect:[v alignmentRectForFrame:v.frame] toView:nil]; }
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
    NSButton *change = nil;
    for (NSButton *b in Buttons(panel.contentView, row))
        if (!change || NSMaxY(Edges(b)) > NSMaxY(Edges(change))) change = b;
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
        // AppKit keeps the content as wide as the panel's columns need in this
        // language, wider than a narrower window. Check at the narrowest width
        // the window shows all of it, as a user narrowing the panel sees it.
        CGFloat needed = NSWidth(panel.contentView.bounds);
        if (needed > NSWidth([panel contentRectForFrameRect:panel.frame]) + 0.5) { // WIDEN TO CONTENT
            frame.size.width = NSWidth([panel frameRectForContentRect:NSMakeRect(0, 0, needed, 100)]);
            [panel setFrame:frame display:NO];
            [panel.contentView layoutSubtreeIfNeeded];
        } // END WIDEN TO CONTENT
        CGFloat visible = NSWidth([panel contentRectForFrameRect:panel.frame]);
        NSRect p = Edges(popUp), f = Edges(field);
        NSRect c = Edges(change), a = Edges(changeAll);
        NSString *at = [NSString stringWithFormat:@" (%s, %s, panel %.0f wide)", NSBundle.mainBundle.preferredLocalizations.firstObject.UTF8String, names[i], NSWidth(frame)];
        Check(Near(NSMinX(f), NSMinX(p)) && Near(NSMaxX(f), NSMaxX(p)), [@"the replacement field keeps the pop-up's edges" stringByAppendingString:at]);
        Check(Near(NSMinX(a), NSMinX(c)) && Near(NSMaxX(a), NSMaxX(c)) && Near(NSHeight(a), NSHeight(c)), [@"Change All keeps the Change button's edges" stringByAppendingString:at]);
        Check(Near(NSMidY(a), NSMidY(f)), [@"Change All is centered on the field" stringByAppendingString:at]);
        Check(Near(NSMinY(f), 16), [NSString stringWithFormat:@"16 points below the field, not %.1f%@", NSMinY(f), at]);
        Check(Near(NSMinY(p) - NSMaxY(f), 12), [NSString stringWithFormat:@"12 points between the field and the pop-up, not %.1f%@", NSMinY(p) - NSMaxY(f), at]);
        Check(NSMaxX(a) <= visible + 0.5 && NSMaxX(f) <= visible + 0.5 && NSMinX(f) >= 0,
              [NSString stringWithFormat:@"the row stays inside the window, %.1f wide, not to %.1f%@", visible, NSMaxX(a), at]);
    }
    checker.accessoryView = nil;
    if (failures) return 1;
    printf("%s ok\n", NSBundle.mainBundle.preferredLocalizations.firstObject.UTF8String);
}}
'''

if args.mutation == 'no-widen':
    old, new = mutations[args.mutation]
    assert program.count(old) == 1, args.mutation
    program = program.replace(old, new)

languages = sorted(d.name[:-len('.lproj')] for d in (root / 'Resources/Interfaces').glob('*.lproj') if d.name != 'Base.lproj')
assert len(languages) >= 12, languages
with tempfile.TemporaryDirectory(prefix='texshop-change-all-row-') as td:
    t = Path(td)
    (t / 'row.m').write_text(program, encoding='utf-8')
    app = t / 'Probe.app/Contents'
    (app / 'MacOS').mkdir(parents=True)
    for language in languages:
        (app / 'Resources' / f'{language}.lproj').mkdir(parents=True)
    (app / 'Info.plist').write_text("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>probe</string>
<key>CFBundleIdentifier</key><string>org.texshop.tests.change-all-row</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSBackgroundOnly</key><true/></dict></plist>""", encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'AppKit', str(t / 'row.m'), '-o', str(app / 'MacOS/probe')], check=True)
    home = t / 'home'; (home / 'Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    failed = 0
    for language in languages:
        result = subprocess.run([str(app / 'MacOS/probe'), '-AppleLanguages', f'({language})'], env=env, timeout=60, capture_output=True, text=True)
        if result.returncode == 2 or (result.returncode != 0 and not args.mutation):
            print(result.stdout + result.stderr, end='')
        if result.returncode == 2: raise SystemExit(2)
        if result.returncode != 0: failed += 1
    if args.mutation:
        if failed:
            print(f'mutation {args.mutation} detected in {failed} of {len(languages)} languages')
            raise SystemExit(0)
        print(f'FAIL: mutation {args.mutation} not detected')
        raise SystemExit(1)
    if failed: raise SystemExit(1)
    print(f"PASS: the Change All row keeps the panel's columns in {len(languages)} languages at the default width, wider and narrower, 16 points from the bottom and 12 below the pop-up")
