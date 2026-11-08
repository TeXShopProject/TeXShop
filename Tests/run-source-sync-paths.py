#!/usr/bin/env python3
"""Check production forward-SyncTeX path matching with real TeX output and aliases."""
from pathlib import Path
import os
import gzip
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEX = Path(os.environ.get('TEXLIVE_BIN', '/Applications/TeXLive/2026/bin/universal-darwin'))
source = (ROOT / 'Sources/TSDocument-SyncTeX.m').read_text(encoding='latin1')
helper = source[source.index('static const char *TSSyncTeXInputNameForSource'):source.index('@implementation TSDocument (SyncTeX)')]
program = r'''
#import <Foundation/Foundation.h>
#import "synctex_parser.h"
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
    return subprocess.run([str(x) for x in args], check=True, timeout=90, **kwargs)


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
    requests = [short / 'document folder/test.tex', tex, alias / 'test.tex', file_alias]
    # Recompile the same output using each spelling. Each invocation loads a fresh scanner.
    for recorded in [requests[0], requests[1], requests[2], Path('test.tex')]:
        run(TEX / 'lualatex', '-interaction=nonstopmode', '-halt-on-error', '-synctex=1',
            recorded, cwd=actual, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for requested in requests:
            run(exe, tex.with_suffix('.pdf'), requested, requested.parent, 'match')
        run(exe, tex.with_suffix('.pdf'), other, actual, 'missing')
        run(exe, tex.with_suffix('.pdf'), actual / 'missing.tex', actual, 'missing')
    # Explicitly cover SyncTeX files whose input records are relative to the root document.
    sync = tex.with_suffix('.synctex.gz')
    data = gzip.decompress(sync.read_bytes())
    data, count = re.subn(rb'(?m)^(Input:[0-9]+:)[^\n]*test\.tex$', rb'\g<1>./test.tex', data)
    assert count == 1
    sync.write_bytes(gzip.compress(data))
    for requested in requests:
        run(exe, tex.with_suffix('.pdf'), requested, actual, 'match')
    print('PASS: 20 alias/query checks and 8 unrelated/missing-file checks across four recompiles.')
