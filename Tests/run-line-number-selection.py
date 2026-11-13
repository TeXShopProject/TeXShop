#!/usr/bin/env python3
"""Clicking or dragging on the line numbers selects whole lines (no window is shown).

With --mutation NAME the harness runs against a mutated copy of
NoodleLineNumberView.m and must fail."""
from pathlib import Path
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # The empty line after a final line ending is not reached.
    'no-extra-line': ('if (!NSIsEmptyRect(extraRect) && (point.y >= NSMinY(extraRect)))',
                      'if (NO)'),
    # Shift does not extend the existing selection.
    'no-shift': ('extending = ((modifiers & NSEventModifierFlagShift) != 0);', 'extending = NO;'),
    # The text does not scroll while dragging outside it.
    'no-autoscroll': ('[view scrollRectToVisible:NSMakeRect(NSMidX(visibleRect), pointInView.y, 1.0, 1.0)];', ';'),
    # The scroll target lies under the ruler and the text moves sideways.
    'left-edge-target': ('NSMakeRect(NSMidX(visibleRect), pointInView.y', 'NSMakeRect(NSMinX(visibleRect), pointInView.y'),
    # The selected lines' numbers are not bold.
    'no-bold': ('currentTextAttributes = selectedAttributes;', 'currentTextAttributes = textAttributes;'),
    # The numbers stay bold after the selection changes otherwise.
    'bold-stays': ('return (([ranges count] == 1) && NSEqualRanges([[ranges firstObject] rangeValue], _lineSelection));', 'return YES;'),
    # The ruler is not redrawn when the selection changes otherwise.
    'no-redisplay': ('\t\t_hasLineSelection = NO;\n\t\t[self setNeedsDisplay:YES];', '\t\t_hasLineSelection = NO;'),
    # Bold numbers are placed by their regular width.
    'measure-regular': ('stringSize = [labelText sizeWithAttributes:currentTextAttributes];',
                        'stringSize = [labelText sizeWithAttributes:textAttributes];'),
    # The rect stays narrower than a wide bold number.
    'fixed-rect': ('MAX(NSWidth(bounds) - RULER_MARGIN * 2.0, ceil(stringSize.width))', 'NSWidth(bounds) - RULER_MARGIN * 2.0'),
    # Every drag step posts a selection change.
    'notify-each-step': ('stillSelecting:YES];\n\t\t\t[self showLineSelection:selection];\n\t\t}',
                         'stillSelecting:NO];\n\t\t\t[self showLineSelection:selection];\n\t\t}'),
}


def run(mutation=None):
    source = source_file(root, 'NoodleLineNumberView.m')
    with tempfile.TemporaryDirectory(prefix='texshop-line-number-selection-') as tmp:
        if mutation:
            old, new = MUTATIONS[mutation]
            text = source.read_text(encoding='utf-8')
            assert text.count(old) == 1, 'mutation target must be unique: ' + mutation
            source = Path(tmp) / 'NoodleLineNumberView.m'
            source.write_text(text.replace(old, new), encoding='utf-8')
        exe = Path(tmp) / 'line-number-selection'
        subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/LineNumberSelection.m'), str(source),
                        str(source_file(root, 'NoodleLineNumberMarker.m')), '-o', str(exe)], check=True)
        return subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)


if len(sys.argv) == 3 and sys.argv[1] == '--mutation':
    result = run(sys.argv[2])
    print(result.stdout, end='')
    if result.returncode == 0:
        sys.exit('MUTATION SURVIVED: ' + sys.argv[2])
    print('MUTATION CAUGHT:', sys.argv[2])
    sys.exit(0)

result = run()
print(result.stdout, end='')
if result.returncode:
    sys.exit(result.stderr or 'FAIL')
