#!/usr/bin/env python3
"""Run real isolated Experiment jobs without launching TeXShop or reading user settings."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='texshop-experiment-test-') as directory:
    executable = str(Path(directory) / 'ExperimentJob')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                    '-I', str(root / 'Sources'), str(root / 'Tests/ExperimentJob.m'),
                    str(root / 'Sources/TSExperimentJob.m'), '-o', executable], check=True)
    subprocess.run([executable], check=True, timeout=45)
