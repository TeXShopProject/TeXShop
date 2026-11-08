#!/usr/bin/env python3
"""Check production forward-SyncTeX path matching with real TeX output and aliases."""
from pathlib import Path
import argparse
import os
import gzip
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['unresolved-fallback'])
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
TEX = Path(os.environ.get('TEXLIVE_BIN', '/Applications/TeXLive/2026/bin/universal-darwin'))
source = (ROOT / 'Sources/TSDocument-SyncTeX.m').read_text(encoding='latin1')
helper = source[source.index('static NSString *TSSyncTeXResolvedPath'):source.index('@implementation TSDocument (SyncTeX)')]
if args.mutation:
    helper = helper.replace('if (!resolved) return nil;', 'if (!resolved) return path;')
program = r'''
#import <Foundation/Foundation.h>
#import "synctex_parser.h"
#import <stdlib.h>
#import <string.h>
HELPER
int main(int argc, char **argv) { @autoreleasepool {
    NSString *output = @(argv[1]), *requested = @(argv[2]), *root = @(argv[3]);
    synctex_scanner_p scanner = synctex_scanner_new_with_output_file(output.fileSystemRepresentation, NULL, 1);
    if (!scanner) return 2;
    const char *name = TSSyncTeXInputNameForSource(scanner, requested, root);
    if (!strcmp(argv[4], "missing")) {
        synctex_scanner_free(scanner);
        return name ? 3 : 0;
    }
    if (!name) { fprintf(stderr,"No match for %s\n", argv[2]); return 4; }
    // Query with the unmodified recorded name, not its canonicalized spelling.
    if (synctex_display_query(scanner, name, 3, 0, 0) <= 0) return 5;
    synctex_node_p node = synctex_scanner_next_result(scanner);
    if (!node || synctex_node_page(node) != 1) return 6;
    printf("PASS: %s -> %s\n", argv[2], name);
    synctex_scanner_free(scanner);
    return 0;
}}
'''.replace('HELPER', helper)


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, timeout=20, **kwargs)


with tempfile.TemporaryDirectory(prefix='texshop-sync-path-', dir='/tmp') as temporary:
    short = Path(temporary)
    physical = short.resolve()
    actual = physical / 'document folder'
    actual.mkdir()
    alias = short / '日本語 alias'
    alias.symlink_to(actual, target_is_directory=True)
    tex = actual / 'test.tex'
    tex.write_text('\\documentclass{article}\n\\begin{document}\n'
                   'Synchronization target.\\par\n\\end{document}\n')
    file_alias = actual / 'file-alias.tex'
    file_alias.symlink_to(tex)
    alias2 = physical / 'second directory alias'
    alias2.symlink_to(actual, target_is_directory=True)
    file_alias2 = physical / 'second-file.tex'
    file_alias2.symlink_to(tex)
    # A lexical cleanup of "alias/.." would incorrectly lead to physical/test.tex.
    nested = actual / 'nested'
    nested.mkdir()
    parent_alias = physical / 'nested-alias'
    parent_alias.symlink_to(nested, target_is_directory=True)
    other = actual / 'different.tex'
    other.write_text(tex.read_text())
    native = physical / 'test.m'
    native.write_text(program)
    exe = physical / 'check'
    run('xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
        '-I', ROOT / 'Sources', '-I', ROOT / '3rdparty/zlib/zlib-1.4',
        native, ROOT / 'Sources/synctex_parser.c', ROOT / 'Sources/synctex_parser_utils.c',
        ROOT / 'Resources/Binaries/libz.a', '-o', exe)
    env = dict(os.environ, PATH=str(TEX) + os.pathsep + os.environ.get('PATH', ''))
    requests = [short / 'document folder/test.tex', tex, alias / 'test.tex', file_alias, alias2 / 'test.tex', file_alias2,
                parent_alias / '../test.tex']
    # Recompile the same output using each spelling. Each invocation loads a fresh scanner.
    for recorded in requests + [Path('test.tex')]:
        run(TEX / 'lualatex', '-interaction=nonstopmode', '-halt-on-error', '-synctex=1',
            recorded, cwd=actual, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = actual / (recorded.stem + '.pdf')
        for requested in requests:
            run(exe, output, requested, requested.parent, 'match')
        run(exe, output, other, actual, 'missing')
        run(exe, output, actual / 'missing.tex', actual, 'missing')
    # Explicitly cover SyncTeX files whose input records are relative to the root document.
    sync = tex.with_suffix('.synctex.gz')
    data = gzip.decompress(sync.read_bytes())
    data, count = re.subn(rb'(?m)^(Input:[0-9]+:)[^\n]*test\.tex$', rb'\g<1>./test.tex', data)
    assert count == 1
    sync.write_bytes(gzip.compress(data))
    for requested in requests:
        run(exe, tex.with_suffix('.pdf'), requested, actual, 'match')
    # Rewrite a real SyncTeX record to check both sides of invalid matches, including
    # identical spellings, which used to bypass link resolution entirely.
    valid_data = data
    self_link = actual / 'self.tex'
    self_link.symlink_to('self.tex')
    cycle_a, cycle_b = actual / 'cycle-a.tex', actual / 'cycle-b.tex'
    cycle_a.symlink_to(cycle_b.name); cycle_b.symlink_to(cycle_a.name)
    broken = actual / 'broken.tex'
    broken.symlink_to('nonexistent.tex')
    directory_cycle = actual / 'loop'
    directory_cycle.symlink_to('loop')
    deep = actual / 'deep.tex'
    for i in range(80):
        name = deep if i == 0 else actual / f'deep-{i}.tex'
        name.symlink_to(tex.name if i == 79 else f'deep-{i+1}.tex')
    invalid = [self_link, cycle_a, cycle_b, broken, directory_cycle / 'test.tex',
               deep, actual / 'absent.tex', tex / 'not-a-directory.tex']
    rejected = 0
    for recorded in invalid:
        # Corrupt input records must not accidentally resolve to the valid source.
        bad_data, count = re.subn(rb'(?m)^(Input:[0-9]+:)\./test\.tex$',
            lambda m: m[1] + os.fsencode(recorded), valid_data)
        assert count == 1
        sync.write_bytes(gzip.compress(bad_data))
        for requested in [recorded, tex]:
            result = subprocess.run([str(exe), str(tex.with_suffix('.pdf')), str(requested), str(actual), 'missing'],
                                    timeout=5, capture_output=True, text=True)
            if args.mutation and result.returncode == 3:
                print('PASS: detected unresolved-fallback (invalid path falsely matched)')
                raise SystemExit(0)
            assert result.returncode == 0, (recorded, requested, result.stdout, result.stderr, result.returncode)
            rejected += 1
    sync.write_bytes(gzip.compress(valid_data))
    for requested in invalid:
        run(exe, tex.with_suffix('.pdf'), requested, actual, 'missing')
        rejected += 1
    if args.mutation: raise AssertionError('Mutation escaped detection')
    print(f'PASS: 63 alias/query checks, 16 unrelated/missing-file checks, {rejected} invalid-link checks.')
