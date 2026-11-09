#!/usr/bin/env python3
"""Exercise detection against isolated fake installations; no app settings are used."""
from pathlib import Path
import subprocess, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
    exe = Path(td) / 'EnginePathDiscovery'
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', *include_args(root), str(root/'Sources/Typesetting/TSEnginePathDiscovery.m'), str(root/'Tests/EnginePathDiscovery.m'), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=15)
