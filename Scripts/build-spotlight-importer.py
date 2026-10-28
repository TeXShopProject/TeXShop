#!/usr/bin/env python3
"""Terada: rebuild the bundled Spotlight importer for Intel and Apple Silicon."""
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-importer-') as temporary:
    build = Path(temporary)
    subprocess.run(['xcodebuild', '-project', str(root / '3rdparty/TeX-mdim-Universal/TeX.xcodeproj'),
                    '-target', 'TeX', '-configuration', 'Release', 'ARCHS=arm64 x86_64',
                    'ONLY_ACTIVE_ARCH=NO', 'MACOSX_DEPLOYMENT_TARGET=14.6', 'CODE_SIGNING_ALLOWED=NO',
                    'SYMROOT=' + str(build), 'OBJROOT=' + str(build / 'Intermediates'), 'build'], check=True)
    product = build / 'Release/TeX.mdimporter'
    binary = product / 'Contents/MacOS/TeX'
    architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    if set(architectures) != {'arm64', 'x86_64'}:
        raise SystemExit('The importer must contain both arm64 and x86_64')
    subprocess.run(['codesign', '--force', '--sign', '-', str(product)], check=True)
    target = root / '3rdparty/TeX.mdimporter'
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(product, target, symlinks=True)
print('Updated 3rdparty/TeX.mdimporter; the application signs it on copy.')
