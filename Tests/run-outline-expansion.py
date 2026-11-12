#!/usr/bin/env python3
"""Check that open entries of the Preview drawer's outline stay open after the PDF is read again."""
from pathlib import Path
import argparse
import os
import re
import subprocess
import tempfile
from source_tree import include_args, source_file

MUTATIONS = {
    'no-reopen': ('    [outlineView reloadData];\n    [self expandRememberedChildrenOf:nil];\n',
                  '    [outlineView reloadData];\n'),
    'title-only': ('                occurrence++;\n', '                ;\n'),
    'no-scroll': ('        [clipView scrollToPoint:bounds.origin];\n', ''),
    'forget-inner': ('    // as NSOutlineView does for items it already knows.\n    [self expandRememberedChildrenOf:item];\n',
                     '    // as NSOutlineView does for items it already knows.\n'),
    'keep-closed': ('    [_expandedKeys removeObject:', '    [_expandedKeys member:'),
    'forget-on-parent-close': ('    if (parent != nil && ![_outlineView isItemExpanded:parent] && !closingAll)\n        return;\n', ''),
    'option-ignored': ('&& !closingAll)', ')'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

# MyPDFKitView must rebuild the drawer's outline through TSOutlineExpansion.
view = source_file(root, 'MyPDFKitView.m').read_bytes().decode('latin-1')
setup = re.search(r'- \(void\) setupOutline\n\{(.*?)\n\}\n', view, re.S).group(1)
assert '[_outlineView reloadData]' not in setup, 'setupOutline reloads the outline view directly'
assert setup.count('[self.outlineExpansion reloadOutline]') == 2, 'setupOutline does not use TSOutlineExpansion'
assert 'initWithOutlineView: _outlineView' in setup, 'setupOutline does not create TSOutlineExpansion'

with tempfile.TemporaryDirectory(prefix='texshop-outline-expansion-') as directory:
    implementation = source_file(root, 'TSOutlineExpansion.m')
    if args.mutation:
        text = implementation.read_text()
        old, new = MUTATIONS[args.mutation]
        assert text.count(old) == 1, args.mutation
        implementation = Path(directory) / 'TSOutlineExpansion.m'
        implementation.write_text(text.replace(old, new))
    executable = Path(directory) / 'probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Quartz',
                    '-I', str(root / 'Tests'), *include_args(root), str(implementation), str(root / 'Tests/OutlineExpansion.m'),
                    '-o', str(executable)], check=True)
    home = Path(directory) / 'home'
    (home / 'Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    result = subprocess.run([str(executable), str(root / 'DocumentSources/Manual Source/Manual.pdf')],
                            capture_output=True, text=True, env=env, timeout=120)
    print(result.stdout, end='')
    if args.mutation:
        assert result.returncode != 0, 'mutation %s was not detected' % args.mutation
        print('PASS: detected mutation %s' % args.mutation)
    else:
        print(result.stderr, end='')
        result.check_returncode()
