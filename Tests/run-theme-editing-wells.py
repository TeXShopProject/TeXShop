#!/usr/bin/env python3
"""Exercise complete production Settings classes; no copied method bodies."""
from pathlib import Path
import subprocess,sys
subprocess.run([sys.executable,str(Path(__file__).with_name('run-settings-product-shell.py')),*sys.argv[1:]],check=True)
