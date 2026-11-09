#!/usr/bin/env python3
"""Compatibility entrypoint: complete production owner, no extracted methods."""
from pathlib import Path
import subprocess,sys
subprocess.run([sys.executable,str(Path(__file__).with_name('run-settings-product-shell.py')),*sys.argv[1:]],check=True)
