#!/usr/bin/env python3
"""Control characters in the editor: width, marker and layout after a form feed."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
globals_m = source_file(root, 'globals.m').read_text(encoding='latin-1')
keys = re.findall(r'^NSString \*(?:show(?:Space|FullwidthSpace|Tab|NewLine)CharacterKey|(?:Space|FullwidthSpace|Tab|NewLine)CharacterKindKey)\s*=.*?;', globals_m, re.M)
assert len(keys) == 8
with tempfile.TemporaryDirectory(prefix='texshop-control-characters-') as tmp:
    (Path(tmp) / 'MarkerKeys.h').write_text('\n'.join(keys))
    exe = Path(tmp) / 'control-characters'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', tmp, '-I', str(root / 'Tests'), *include_args(root),
                    str(root / 'Tests/ControlCharacters.m'), str(source_file(root, 'TSLayoutManager.m')), '-o', str(exe)], check=True)
    result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit(result.stderr or 'FAIL')
