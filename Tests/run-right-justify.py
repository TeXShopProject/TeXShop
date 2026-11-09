#!/usr/bin/env python3
"""Right justification while coloring must not edit the text when nothing changes."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Editor/TSDocument-Syntax.m').read_text(encoding='latin-1')
helper_start = source.index('static BOOL TSParagraphHasAlignment')
helper = source[helper_start:source.index('\n}\n', helper_start) + 3]
block_start = source.index('    if ([SUD boolForKey: RightJustifyKey]) {')
block = source[block_start:source.index('    // NSLog(@"after Hebrew");', block_start)]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'always-set':
    block = block.replace('if (! TSParagraphHasAlignment([aTextView textStorage], start, wanted))', 'if (YES)')
elif mutation == 'natural-is-left':
    helper = helper.replace('if (direction != NSWritingDirectionLeftToRight)', 'if (NO)')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
static NSString *RightJustifyKey = @"RightJustify", *RightJustifyIfAnyKey = @"RightJustifyIfAny";
@interface Defaults : NSObject @end
@implementation Defaults
- (BOOL)boolForKey:(NSString *)key { return [key isEqual:RightJustifyKey]; }
@end
#define SUD ((id)defaults)
static Defaults *defaults;
HELPER
static void Justify(NSTextView *aTextView, NSUInteger aLineStart, NSUInteger aLineEnd) {
    NSString *textString = [[aTextView textStorage] string];
    NSRange middleEastRange, lineRange, selectedLineRange, testRange;
    NSCharacterSet *middleEastSet; NSUInteger start, theend; NSString *theLine;
BLOCK
}
static NSUInteger edits;
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication]; defaults = [Defaults new];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"\\\\section{Intro}\nשלום עולם\nplain text\nسلام\n\n"];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:tv.textStorage queue:nil usingBlock:^(NSNotification *n) { edits++; }];
    NSUInteger end = tv.textStorage.length;
    int failures = 0;
    edits = 0;
    Justify(tv, 0, end);
    // Natural alignment already reads left to right; only the two right-to-left lines change.
    if (edits != 2) { printf("FAIL: first coloring edited the text %lu times, expected 2\n", (unsigned long)edits); failures++; }
    NSArray *expect = @[@(NSTextAlignmentLeft), @(NSTextAlignmentRight), @(NSTextAlignmentLeft), @(NSTextAlignmentRight)];
    NSMutableArray *starts = [NSMutableArray array];
    NSString *text = tv.textStorage.string;
    for (NSUInteger loc = 0; loc < text.length && starts.count < 4; loc = NSMaxRange([text lineRangeForRange:NSMakeRange(loc, 0)]))
        [starts addObject:@(loc)];
    for (NSUInteger i = 0; i < starts.count; i++) {
        NSParagraphStyle *ps = [tv.textStorage attribute:NSParagraphStyleAttributeName atIndex:[starts[i] unsignedIntegerValue] effectiveRange:NULL];
        NSTextAlignment a = ps ? ps.alignment : NSTextAlignmentNatural; if (a == NSTextAlignmentNatural) a = NSTextAlignmentLeft;
        if (a != (NSTextAlignment)[expect[i] integerValue]) { printf("FAIL: line %lu alignment %ld\n", (unsigned long)i, (long)a); failures++; }
    }
    edits = 0;
    Justify(tv, 0, end); Justify(tv, 0, end);
    if (edits != 0) { printf("FAIL: repeated coloring edited the text %lu times\n", (unsigned long)edits); failures++; }
    // A line that changes direction is updated once.
    NSUInteger third = [starts[2] unsignedIntegerValue];
    [tv.textStorage replaceCharactersInRange:NSMakeRange(third, 5) withString:@"עברית"];
    edits = 0; Justify(tv, 0, tv.textStorage.length);
    NSParagraphStyle *ps = [tv.textStorage attribute:NSParagraphStyleAttributeName atIndex:third effectiveRange:NULL];
    if (!ps || ps.alignment != NSTextAlignmentRight || edits == 0) { printf("FAIL: changed line not right aligned\n"); failures++; }
    // In an explicitly right-to-left paragraph natural alignment lays the line out on
    // the right, so a line that does not start with Hebrew must still be set left.
    NSTextView *rtl = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 200)];
    [rtl.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"    שלום עולם\n"];
    NSMutableParagraphStyle *natural = [NSMutableParagraphStyle new];
    natural.alignment = NSTextAlignmentNatural; natural.baseWritingDirection = NSWritingDirectionRightToLeft;
    [rtl.textStorage addAttribute:NSParagraphStyleAttributeName value:natural range:NSMakeRange(0, rtl.textStorage.length)];
    Justify(rtl, 0, rtl.textStorage.length);
    ps = [rtl.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    [rtl.layoutManager ensureLayoutForTextContainer:rtl.textContainer];
    NSRange glyphs = [rtl.layoutManager glyphRangeForCharacterRange:NSMakeRange(4, 4) actualCharacterRange:NULL];
    CGFloat x = [rtl.layoutManager boundingRectForGlyphRange:glyphs inTextContainer:rtl.textContainer].origin.x;
    if (!ps || ps.alignment != NSTextAlignmentLeft || x > 100) { printf("FAIL: right-to-left line laid out at x=%.2f, expected left\n", x); failures++; }
    edits = 0;
    [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:rtl.textStorage queue:nil usingBlock:^(NSNotification *n) { edits++; }];
    Justify(rtl, 0, rtl.textStorage.length);
    if (edits != 0) { printf("FAIL: repeated coloring edited the right-to-left line %lu times\n", (unsigned long)edits); failures++; }
    return failures ? 1 : 0;
} }
'''.replace('HELPER', helper).replace('BLOCK', block)
with tempfile.TemporaryDirectory(prefix='texshop-justify-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(program)
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-w', '-fobjc-arc', '-framework', 'Cocoa', str(src), '-o', str(exe)], check=True)
    r = subprocess.run([str(exe)], capture_output=True, text=True)
    print(r.stdout.strip())
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    elif r.returncode: raise SystemExit(r.stderr or 'FAIL')
    else: print('PASS: right justification is applied once, honors right-to-left paragraphs, and repeated coloring leaves the text untouched')
