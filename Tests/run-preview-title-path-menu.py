#!/usr/bin/env python3
"""実際の AppKit タイトルで、親パスメニューへの転送範囲を検証する。画面には表示しない。"""
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
