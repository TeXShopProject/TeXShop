#!/usr/bin/env python3
"""Every window, panel and view in every localized nib keeps its bezel buttons
apart: no two side-by-side or stacked buttons draw closer than the minimum gap."""
from pathlib import Path
import subprocess, sys, tempfile, argparse
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--minimum', type=float, default=12)
parser.add_argument('--report', action='store_true', help='print findings without failing')
args = parser.parse_args()
# The application applies the same layout where it loads each window.
production = {
    'Sources/Document/TSDocument.m': 'for (NSWindow *panel in @[linePanel ?: (id)NSNull.null, projectPanel ?: (id)NSNull.null, extensionPanel ?: (id)NSNull.null])\n\t\tif ([panel isKindOfClass:NSWindow.class]) TSLayoutDialogButtonRow(panel);',
    'Sources/App/HelpDocuments.m': 'if (packageHelpPanel) TSLayoutDialogButtonRow(packageHelpPanel);\n\tif (openStyleFilePanel) TSLayoutDialogButtonRow(openStyleFilePanel);',
    'Sources/App/TSStationery.m': 'if (stationeryWindow) TSLayoutDialogButtonRow(stationeryWindow);',
    'Sources/Editor/TextFinder.m': 'TSLayoutBottomActionRow([findTextField window]);',
}
for path, call in production.items():
    text = (root / path).read_text(encoding='latin-1' if path.endswith('TextFinder.m') else 'utf-8', errors='replace')
    assert call in text, ('The application lays out this window as the check does', path)
sources = []
for lproj in sorted((root / 'Resources/Interfaces').glob('*.lproj')):
    for item in sorted(lproj.iterdir()):
        # Preferences.nib is no longer loaded; the Settings panes, the macro editor
        # and the toolbar items are laid out and checked by their own code and tests.
        if item.name == 'Preferences.nib' or item.name.startswith('Settings') or item.name == 'MacroEditor.nib':
            continue
        if item.suffix == '.xib':
            sources.append((f'{lproj.stem}/{item.name}', item))
        elif item.suffix == '.nib' and item.is_dir() and (item / 'keyedobjects.nib').exists():
            # The compiled nib is what ships; many bundles have no designable source.
            sources.append((f'{lproj.stem}/{item.name}', item / 'keyedobjects.nib'))
        elif item.suffix == '.nib' and item.is_file():
            sources.append((f'{lproj.stem}/{item.name}', item))
with tempfile.TemporaryDirectory(prefix='texshop-button-spacing-') as tmp:
    tmp = Path(tmp)
    binary = tmp / 'ButtonSpacing'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'AVKit', '-I', str(tmp), '-I', str(root / 'Tests'), *include_args(root),
                    str(root / 'Tests/ButtonSpacing.m'), str(root / 'Sources/Windows/TSDialogButtonLayout.m'), str(root / 'Sources/Editor/TSMarkMenu.m'), '-o', str(binary)], check=True)
    compiled = []
    for index, (label, source) in enumerate(sources):
        if source.suffix == '.xib':
            out = tmp / f'{index}.nib'
            subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(source)], check=True, capture_output=True)
            source = out / 'keyedobjects.nib' if out.is_dir() else out
        compiled.append(f'{label}={source}')
    result = subprocess.run([str(binary), str(args.minimum), *compiled], capture_output=True, text=True, timeout=900)
    print(result.stdout, end='')
    if result.returncode: sys.exit(result.stderr[-2000:])
    close = [line for line in result.stdout.splitlines() if line.startswith('CLOSE ')]
    stat = [line for line in result.stdout.splitlines() if line.startswith('STAT ')][-1]
    assert 'buttons=0' not in stat, 'The check found buttons to measure'
    if close and not args.report:
        sys.exit(f'FAIL: {len(close)} button pairs are closer than {args.minimum:g} points')
    print(f'PASS: {len(sources)} interface files; no bezel buttons closer than {args.minimum:g} points' if not close else 'REPORT ONLY')
