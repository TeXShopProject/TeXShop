#!/usr/bin/env python3
"""Exercise detection against isolated fake installations; no app settings are used."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
    exe = Path(td) / 'EnginePathDiscovery'
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(root/'Sources'), str(root/'Sources/TSEnginePathDiscovery.m'), str(root/'Tests/EnginePathDiscovery.m'), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=15)
