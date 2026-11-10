#!/usr/bin/env python3
"""Console output can be selected and copied while TeX runs (no window is shown)."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-console-selection-') as tmp:
    exe = Path(tmp) / 'console-selection'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                    str(root / 'Tests/ConsoleSelection.m'), '-o', str(exe)], check=True)
    result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit(result.stderr or 'FAIL')

# Every place that writes TeX output, an echoed command or a status line uses the helper.
jobs = source_file(root, 'TSDocument-Jobs.m').read_text(encoding='latin-1')
document = source_file(root, 'TSDocument.m').read_text(encoding='latin-1')
experiment = source_file(root, 'TSExperimentConsoleController.m').read_text(encoding='utf-8')
writes = re.findall(r'\[(?:self->)?outputText replaceCharactersInRange: *\[(?:self->)?outputText selectedRange\] withString: *([^\]]+)\]', jobs + document)
assert writes == ['@""'], writes  # only the clearing at the start of a typeset remains
start = jobs[jobs.index('consoleCleanStart = YES;'):]
start = start[:start.index('typesetStart = NO;')]
assert start.index('[outputText setEditable: NO];') < start.rindex('[outputText setSelectable: YES];') and 'setSelectable: NO' not in start
assert 'TSConfigureConsoleInput(texCommand);' in document
assert 'TSConfigureConsoleInput(field);' in experiment and 'if (!selecting)' in experiment
print('PASS: console output paths, typeset start and both input fields use the selectable console')
