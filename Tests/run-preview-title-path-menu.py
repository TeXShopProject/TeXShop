#!/usr/bin/env python3
"""Check path-menu event routing with real AppKit titles in windows kept off screen."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-title-path-') as directory:
    binary = Path(directory) / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Cocoa',
                    '-I', str(root / 'Sources/Windows'), str(root / 'Tests/PreviewTitlePathMenu.m'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
