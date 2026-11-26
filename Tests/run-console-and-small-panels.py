#!/usr/bin/env python3
"""The console's buttons and the Magnification labels
of every localized TSDocument.nib (which no longer holds the former Statistics panel), laid out as the
application lays them out (see ConsoleAndSmallPanels.m): the console keeps the
square bars of the nib along its top edge. No window is shown; AppKit defaults stay
in memory."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
document = (root / 'Sources/Document/TSDocument.m').read_text(encoding='latin-1')
assert 'TSLayoutConsole' not in document and not (root / 'Sources/Windows/TSConsoleButtonRow.h').exists(), \
    'The console keeps the square bars of the nib'
nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib/keyedobjects.nib'))
assert len(nibs) == 12, nibs
with tempfile.TemporaryDirectory(prefix='texshop-console-small-panels-') as tmp:
    tmp = Path(tmp)
    binary = tmp / 'ConsoleAndSmallPanels'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'AVKit', '-framework', 'WebKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(root / 'Tests/ConsoleAndSmallPanels.m'),
                    str(root / 'Sources/Windows/TSDialogButtonLayout.m'), str(root / 'Sources/Windows/TSOlderPanelLayout.m'),
                    str(root / 'Sources/Editor/TSMarkMenu.m'), '-o', str(binary)], check=True)
    home = tmp / 'home'
    (home / 'Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(binary), *(f'{nib.parent.parent.stem}={nib}' for nib in nibs)], capture_output=True, text=True, timeout=600,
                            env={'HOME': str(home), 'CFFIXED_USER_HOME': str(home), 'PATH': '/usr/bin:/bin'})
    print(result.stdout, end='')
    if result.returncode and not result.stdout.strip():
        print(result.stderr[-3000:], file=sys.stderr)
    sys.exit(result.returncode)
