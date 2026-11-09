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
parser.add_argument('--mutation', choices=['unresolved-fallback', 'no-exact-preference'])
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
TEX = Path(os.environ.get('TEXLIVE_BIN', '/Applications/TeXLive/2026/bin/universal-darwin'))
source = (ROOT / 'Sources/TSDocument-SyncTeX.m').read_text(encoding='latin1')
helper = source[source.index('static NSString *TSSyncTeXResolvedPath'):source.index('@implementation TSDocument (SyncTeX)')]
if args.mutation == 'unresolved-fallback':
    helper = helper.replace('if (!resolved) return nil;', 'if (!resolved) return path;')
if args.mutation == 'no-exact-preference':
    statement = 'if ([source isEqualToString:candidate]) return name;'
    assert statement in helper
    helper = helper.replace(statement, '')
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
    if (!strcmp(argv[4], "exact")) {
        BOOL aliasBeforeExact = NO;
        for (synctex_node_p input = synctex_scanner_input(scanner); input;
             input = synctex_node_sibling(input)) {
            const char *recorded = synctex_scanner_get_name(scanner, synctex_node_tag(input));
            if (!recorded) continue;
            if (!strcmp(recorded, argv[2])) break;
            if (!strcmp(recorded, argv[5])) aliasBeforeExact = YES;
        }
        printf("alias-before-exact=%d\n", aliasBeforeExact);
        if (strcmp(name, argv[2])) return 7;
    }
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
        ROOT / '3rdparty/zlib/libz.a', '-o', exe)
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
    # Two Input records refer to the same physical file. Cover both scanner orders
    # and verify the exact recorded spelling wins even after an alias was seen.
    original = re.search(rb'(?m)^Input:([0-9]+):\./test\.tex$', data)
    assert original
    exact_record = b'Input:' + original[1] + b':' + os.fsencode(tex)
    tags = [int(tag) for tag in re.findall(rb'(?m)^Input:([0-9]+):', data)]
    alias_record = b'Input:' + str(max(tags) + 1).encode() + b':' + os.fsencode(file_alias)
    alias_first_seen = False
    for records in [(alias_record, exact_record), (exact_record, alias_record)]:
        duplicate_data = data.replace(original[0], b'\n'.join(records), 1)
        sync.write_bytes(gzip.compress(duplicate_data))
        result = subprocess.run([str(exe), str(tex.with_suffix('.pdf')), str(tex),
                                 str(actual), 'exact', str(file_alias)],
                                timeout=5, capture_output=True, text=True)
        alias_first = 'alias-before-exact=1' in result.stdout
        alias_first_seen |= alias_first
        if args.mutation == 'no-exact-preference' and alias_first and result.returncode == 7:
            print('PASS: detected no-exact-preference (earlier alias displaced exact spelling)')
            raise SystemExit(0)
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert alias_first_seen, 'Fixture must exercise an alias before the exact spelling'
    if args.mutation == 'no-exact-preference':
        raise AssertionError('Mutation escaped detection')
    sync.write_bytes(gzip.compress(data))
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
            if args.mutation == 'unresolved-fallback' and result.returncode == 3:
                print('PASS: detected unresolved-fallback (invalid path falsely matched)')
                raise SystemExit(0)
            assert result.returncode == 0, (recorded, requested, result.stdout, result.stderr, result.returncode)
            rejected += 1
    sync.write_bytes(gzip.compress(valid_data))
    for requested in invalid:
        run(exe, tex.with_suffix('.pdf'), requested, actual, 'missing')
        rejected += 1
    if args.mutation: raise AssertionError('Mutation escaped detection')
    print(f'PASS: 63 alias/query checks, 2 exact-preference checks, 16 unrelated/missing-file checks, {rejected} invalid-link checks.')
