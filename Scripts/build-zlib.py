#!/usr/bin/env python3
"""Rebuild the bundled zlib from vendored source and run its upstream tests."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '3rdparty/zlib/zlib-1.4'


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    with tempfile.TemporaryDirectory(prefix='texshop-zlib-') as temporary:
        products = []
        for architecture in ('arm64', 'x86_64'):
            build = Path(temporary) / architecture
            shutil.copytree(SOURCE, build)
            environment = os.environ.copy()
            environment.update(CC=f'xcrun clang -arch {architecture}',
                               CFLAGS='-O2 -mmacosx-version-min=14.6',
                               MACOSX_DEPLOYMENT_TARGET='14.6')
            run('./configure', '--static', cwd=build, env=environment)
            run('make', '-j4', cwd=build, env=environment)
            # x86_64 tests require Rosetta on an Apple Silicon build host.
            run('make', 'test', cwd=build, env=environment)
            products.append(build / 'libz.a')
        combined = Path(temporary) / 'libz.a'
        run('xcrun', 'lipo', '-create', *products, '-output', combined)
        architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', combined], text=True).split()
        if set(architectures) != {'arm64', 'x86_64'}:
            raise SystemExit('Expected both arm64 and x86_64')
        # Copy only after both architecture builds and test suites succeed.
        for source, target in [(products[0], '3rdparty/zlib/libz-arm.a'),
                               (products[1], '3rdparty/zlib/libz-intel.a'),
                               (combined, '3rdparty/zlib/libz.a'),
                               (combined, 'Resources/Binaries/libz.a')]:
            shutil.copy2(source, ROOT / target)
    print('Updated bundled zlib 1.4 for Apple Silicon and Intel.')


if __name__ == '__main__':
    main()
