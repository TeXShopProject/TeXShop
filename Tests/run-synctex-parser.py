#!/usr/bin/env python3
"""Check both architectures with compressed/plain data, Unicode paths and mag<1000.

Requires TeX Live (set TEXLIVE_BIN if it is not installed in the default location)
and Rosetta on Apple Silicon. Does not launch TeXShop or change user settings.
"""
from pathlib import Path
import os
import subprocess
import tempfile
from source_tree import include_args

ROOT = Path(__file__).resolve().parents[1]
TEX = Path(os.environ.get('TEXLIVE_BIN', '/Applications/TeXLive/2026/bin/universal-darwin'))


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, timeout=90, **kwargs)


def main():
    with tempfile.TemporaryDirectory(prefix='texshop-synctex-') as temporary:
        directory = Path(temporary)
        executables = []
        for arch in ('arm64', 'x86_64'):
            for legacy in (False, True):
                executable = directory / ('test-' + arch + ('-legacy' if legacy else ''))
                defines = ['-DTEST_LEGACY_PARSER'] if legacy else []
                run('xcrun', 'clang', '-arch', arch, '-mmacosx-version-min=14.6', *defines,
                    *include_args(ROOT), '-I', ROOT / '3rdparty/zlib/zlib-1.4',
                    ROOT / 'Tests/SyncTeXParser.c', ROOT / 'Sources/ThirdParty/SyncTeX/synctex_parser.c',
                    ROOT / 'Sources/ThirdParty/SyncTeX/synctex_parser_old.c',
                    ROOT / 'Sources/ThirdParty/SyncTeX/synctex_parser_utils.c', ROOT / '3rdparty/zlib/libz.a',
                    '-o', executable)
                executables.append(executable)
        for engine, text, queries in [
            ('lualatex', '\\documentclass{article}\n\\begin{document}\n'
             '\\noindent First page synchronization target.\\par\n\\newpage\n'
             '\\noindent Second page synchronization target.\\par\n\\end{document}\n',
             [(3, 1), (5, 2)]),
            ('pdftex', '\\mag=900\n\\nopagenumbers\n'
             '\\noindent Reduced page synchronization target.\\par\n\\eject\n'
             '\\noindent Second reduced page target.\\par\n\\bye\n',
             [(3, 1), (5, 2)]),
        ]:
            for compression in (1, -1):
                case = directory / f'{engine}-{compression}'
                case.mkdir()
                source = case / '日本語 document.tex'
                source.write_text(text)
                environment = os.environ.copy()
                environment['PATH'] = str(TEX) + os.pathsep + environment.get('PATH', '')
                run(TEX / engine, '-interaction=nonstopmode', '-halt-on-error',
                    f'-synctex={compression}', source.name, cwd=case, env=environment,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                suffix = '.synctex.gz' if compression == 1 else '.synctex'
                assert source.with_suffix(suffix).exists()
                for executable in executables:
                    for line, page in queries:
                        run(executable, source.with_suffix('.pdf'), source.name, line, page, cwd=case)
        invalid = directory / 'invalid.synctex'
        invalid.write_text('This is not a SyncTeX file.\n')
        for executable in executables:
            run(executable, invalid.with_suffix('.pdf'), 'invalid')
            run(executable, directory / 'missing.pdf', 'invalid')
    print('PASS: both architectures and parsers; LuaLaTeX/pdfTeX; gzip/plain; Unicode; mag=900; invalid/missing.')


if __name__ == '__main__':
    main()
