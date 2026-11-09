#!/usr/bin/env python3
"""Real owner controls in twelve languages, plus independent renderer glyph checks."""
from pathlib import Path
import subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'Tests/run-settings-product-shell.py'),*sys.argv[1:]],check=True)
with tempfile.TemporaryDirectory(prefix="texshop-marker-draw-") as td:
 subprocess.run(["/bin/bash",str(root/"Tests/run-invisible-baseline.sh"),str(Path(td)/"markers.png")],check=True)
