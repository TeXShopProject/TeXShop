#!/usr/bin/env python3
"""The console's buttons, the Text panel's choices, the Statistics fields and the
Magnification labels of every localized TSDocument.nib, laid out as the
application lays them out (see ConsoleAndSmallPanels.m). Also checks that the
application lays out the document's console and the Experiment console with
the shared row (TSConsoleButtonRow.h). No window is shown; AppKit defaults stay
in memory."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
document = (root / 'Sources/Document/TSDocument.m').read_text(encoding='latin-1')
setup = document[document.index('- (void)setupConsole;'):document.index('- (void)setupLogWindow')]
assert setup.index('TSLayoutConsoleButtonRow(outputWindow);') > setup.index('[outputWindow setFrameAutosaveName:ConsoleWindowNameKey];'), \
    'The application lays out the console after its saved frame, as the check does'
assert 'TSLayoutConsoleButtons(content, @[], @[stop], scroll);' in (root / 'Sources/Typesetting/TSExperimentConsoleController.m').read_text(), \
    'The Experiment console shares the row of the document console'
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
