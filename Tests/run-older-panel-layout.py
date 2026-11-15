#!/usr/bin/env python3
"""Panels from older nibs and other interface parts keep the current macOS look.

Runtime part (OlderPanelLayout.m), for TSDocument.nib and MainMenu.nib of all
twelve localizations, loaded offscreen with the layout the application applies
after loading them (ProductionLayout.inc):
  * the Log File window keeps its check boxes and Refresh whole, 12 points apart
    and 20 points from the edges, and the log meets the window's edges;
  * the two notices (typeset before printing, save before setting a project)
    become alerts with the panel's text on one line and its OK button;
  * Select Source draws no vertical grid lines, and Encoding: in the open panel's
    accessory and Image Type: in the Save Selection panel's accessory have the size
    of their pop-ups and are centered on them;
  * the sheet that changes the encoding of a file shows its whole label, in the
    language of each strings table, 8 points from its pop-up.

Static part:
  * the application calls these functions where it loads the nibs;
  * the alerts that forget learned words, restore all shortcuts or replace a
    theme mark that button as destructive;
  * the OgreKit Find panel sources name no font, use no bold title bar font,
    no square history pop-ups and no fixed gray text;
  * the sources and Interface Builder files use no square or textured bezel
    styles beyond the uses listed below, which are left to the work on those
    windows (a listed use that is gone is reported so the list can shrink);
  * code names no font for interface text beyond the ones listed;
  * the link popup of the preview has round corners and a thin gray edge, not a
    square black frame;
  * the key binding list in Settings > Keyboard has the form of the menu shortcut
    list below it: no border, no background of its own, inset rows with
    alternating colors.

  --mutations  check that each mutation listed below is caught"""
from pathlib import Path
import argparse, re, shutil, subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']

PRODUCTION = {
    'Sources/Document/TSDocument.m': [
        'if (self.logWindow) TSLayoutLogWindow(self.logWindow);',
        'result = [TSAlertForNoticePanel(printRequestPanel) runModal];',
        'result = [TSAlertForNoticePanel(requestWindow) runModal];',
    ],
    'Sources/Document/TSDocumentController.m': ['TSFitLabelsBeforePopUps(encodingView);'],
    'Sources/App/TSStationery.m': ['TSRemoveVerticalGridLines(stationeryWindow.contentView);'],
    'Sources/Preview/MyPDFKitView.m': ['TSFitLabelsBeforePopUps(self.imageTypeView);'],
    'Sources/Preview/MyPDFView.m': ['TSFitLabelsBeforePopUps(imageTypeView);'],
}
DESTRUCTIVE = {
    'Sources/Editor/TSSpellSupport.m': '[alert addButtonWithTitle:NSLocalizedString(@"Forget Selected", @"")].hasDestructiveAction = YES;',
    'Sources/Shortcuts/TSShortcutPaneController.m': '[alert addButtonWithTitle:NSLocalizedString(@"Restore All", @"")].hasDestructiveAction = YES;',
    'Sources/Settings/TSPreferences-Color.m': '[alert addButtonWithTitle:NSLocalizedString(@"Replace", @"")].hasDestructiveAction = YES;',
}
OLD_BEZELS = re.compile(r'NSBezelStyle(ShadowlessSquare|SmallSquare|TexturedSquare|RoundRect|TexturedRounded|ThickSquare|ThickerSquare)\b'
                        r'|NS(ShadowlessSquare|SmallSquare|TexturedSquare|RoundRect|TexturedRounded|ThickSquare|ThickerSquare)BezelStyle\b')
# Uses that other work on those windows replaces; each is counted per file.
KNOWN_BEZELS = {
    'Sources/Typesetting/TSExperimentConsoleController.m': 1,  # Stop Experiment (console work)
    'Sources/Windows/TSToolbarController.m': 1,                 # toolbar items before macOS 26 (document window work)
}
XIB_OLD_BEZELS = re.compile(r'bezelStyle="(shadowlessSquare|smallSquare|texturedSquare|thickSquare|thickerSquare|texturedRounded)"')
NAMED_FONT = re.compile(r'fontWithName:\s*@"')
KNOWN_NAMED_FONTS = {
    'Sources/Utilities/NSString-CharacterConversion.m': 2,  # the character table of Character Type Conversion
}

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--mutations', action='store_true')
args = parser.parse_args()


def static_problems(base):
    problems, notes = [], []
    for path, calls in PRODUCTION.items():
        text = (base / path).read_text(encoding='utf-8', errors='replace')
        problems += [f'{path} does not call {call}' for call in calls if call not in text]
    for path, line in DESTRUCTIVE.items():
        if line not in (base / path).read_text(encoding='utf-8', errors='replace'):
            problems.append(f'{path}: the button is not marked destructive: {line}')
    popup = (base / 'Sources/Preview/TSLinkPreviewView.m').read_text(encoding='utf-8')
    if 'NSFrameRect(bounds)' in popup or '[[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] addClip];' not in popup:
        problems.append('Sources/Preview/TSLinkPreviewView.m draws a square popup')
    bindings = (base / 'Sources/Settings/TSKeyBindingsController.m').read_text(encoding='utf-8')
    shortcuts = (base / 'Sources/Shortcuts/TSShortcutPaneController.m').read_text(encoding='utf-8')
    for line in ('scroll.borderType = NSNoBorder;', 'scroll.drawsBackground = NO;', 'table.style = NSTableViewStyleInset;', 'table.usesAlternatingRowBackgroundColors = YES;'):
        if line not in bindings:
            problems.append(f'Sources/Settings/TSKeyBindingsController.m: the key binding list does not have {line}')
    for part in ('scroll.borderType = NSNoBorder;', 'scroll.drawsBackground = NO;', 'self.table.style = NSTableViewStyleInset;', 'self.table.usesAlternatingRowBackgroundColors = YES;'):
        if part not in shortcuts:
            problems.append(f'Sources/Shortcuts/TSShortcutPaneController.m: the menu shortcut list no longer has {part}; the key binding list follows it')
    for xib in sorted((base / '3rdparty/OgreKit-2.1.12-FindPanel').glob('*.lproj/*.xib')):
        text = xib.read_text(encoding='utf-8')
        rel = xib.relative_to(base)
        for pattern, what in [(r'<font [^>]*\bname="', 'names a font'), (r'metaFont="titleBar"', 'uses the bold title bar font'),
                              (r'metaFont="cellTitle"', 'uses the bold cell title font'), (r'bezelStyle="shadowlessSquare"', 'has a square pop-up'),
                              (r'<color key="textColor" red=', 'has a fixed text color')]:
            if re.search(pattern, text):
                problems.append(f'{rel} {what}')
    counts = {}
    for path in sorted((base / 'Sources').rglob('*.m')):
        rel = str(path.relative_to(base))
        text = path.read_text(encoding='utf-8', errors='replace')
        text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
        text = re.sub(r'//[^\n]*', '', text)
        n = len(OLD_BEZELS.findall(text))
        if n:
            counts[rel] = n
        f = len(NAMED_FONT.findall(text))
        if f > KNOWN_NAMED_FONTS.get(rel, 0):
            problems.append(f'{rel} names {f} fonts for interface text')
    for rel, n in counts.items():
        if n > KNOWN_BEZELS.get(rel, 0):
            problems.append(f'{rel} uses an old square or textured bezel style ({n})')
    for rel, n in KNOWN_BEZELS.items():
        if counts.get(rel, 0) < n:
            notes.append(f'NOTE {rel} no longer uses its listed old bezel style; the list can shrink')
    # TSDocument.nib (console, toolbar), the macro editor and the matrix and LaTeX
    # panels are rebuilt by their own work; Preferences.nib is not built.
    for xib in sorted((base / 'Resources/Interfaces').glob('*.lproj/*.xib')) + sorted((base / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib')):
        for m in XIB_OLD_BEZELS.finditer(xib.read_text(encoding='utf-8', errors='replace')):
            problems.append(f'{xib.relative_to(base)} uses bezelStyle="{m.group(1)}"')
    return problems, notes


def compiled(path):
    if path.is_dir():
        for name in ('keyedobjects-101300.nib', 'keyedobjects.nib'):
            if (path / name).exists():
                return path / name
    return path


def run_runtime(base, tmp):
    interfaces = base / 'Resources/Interfaces'
    entries = []
    for language in LANGUAGES:
        strings = interfaces / f'{language}.lproj/Localizable.strings'
        if not strings.exists():
            strings = interfaces / 'en.lproj/Localizable.strings'
        for nib in ('TSDocument.nib', 'MainMenu.nib'):
            entries.append(f'{language}.lproj/{nib}|{compiled(interfaces / language / nib) if False else compiled(interfaces / f"{language}.lproj" / nib)}|{strings}')
    # The encoding sheet: one Base interface, a strings table per language.
    sheet = tmp / 'CustomModalWindowController.nib'
    subprocess.run(['xcrun', 'ibtool', '--compile', str(sheet), str(interfaces / 'Base.lproj/CustomModalWindowController.xib')], check=True, capture_output=True)
    sheet = compiled(sheet)
    for language in LANGUAGES:
        table = interfaces / f'{"en" if language == "Base" else language}.lproj/CustomModalWindowController.strings'
        entries.append(f'{language}.lproj/CustomModalWindowController.nib|{sheet}|{interfaces / "en.lproj/Localizable.strings"}|{table}')
    binary = tmp / 'OlderPanelLayout'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'AVKit', '-framework', 'Quartz', '-framework', 'Carbon',
                    '-I', str(base / 'Tests'), *include_args(base), str(base / 'Tests/OlderPanelLayout.m'),
                    str(base / 'Sources/Windows/TSDialogButtonLayout.m'), str(base / 'Sources/Windows/TSOlderPanelLayout.m'),
                    str(base / 'Sources/Editor/TSMarkMenu.m'), '-o', str(binary)], check=True)
    return subprocess.run([str(binary), *entries], capture_output=True, text=True, timeout=900)


def check(base, tmp, quiet=False):
    problems, notes = static_problems(base)
    result = run_runtime(base, tmp)
    if not quiet:
        for line in notes:
            print(line)
        print(result.stdout, end='')
    failed = [l for l in result.stdout.splitlines() if l.startswith('FAIL')]
    if result.returncode and not failed:
        problems.append('runtime check did not run: ' + result.stderr[-1500:])
    return problems + failed


MUTATIONS = {
    'log columns too close': ('Sources/Windows/TSOlderPanelLayout.m', 'TSColumnSpacing = 20;', 'TSColumnSpacing = 4;'),
    'line breaks kept in alerts': ('Sources/Windows/TSOlderPanelLayout.m', '[texts addObject:TSOneLine(label.stringValue)]', '[texts addObject:label.stringValue]'),
    'space between CJK': ('Sources/Windows/TSOlderPanelLayout.m', 'if (result.length && !(TSIsCJK([result characterAtIndex:result.length - 1]) && TSIsCJK([line characterAtIndex:0])))',
                          'if (result.length)'),
    'small Encoding label': ('Sources/Windows/TSOlderPanelLayout.m', 'nearest.font = [NSFont systemFontOfSize:popUp.font.pointSize ?: NSFont.systemFontSize];', 'nearest.font = [NSFont systemFontOfSize:11];'),
    'grid lines kept': ('Sources/Windows/TSOlderPanelLayout.m', 'table.gridStyleMask &= ~NSTableViewSolidVerticalGridLineMask;', ''),
    'bold OgreKit button': ('3rdparty/OgreKit-2.1.12-FindPanel/de.lproj/OgreAdvancedFindPanel.xib', '<font key="font" metaFont="smallSystem"/>',
                            '<font key="font" metaFont="titleBar" size="12" textStyle="headline"/>'),
    'not destructive': ('Sources/Settings/TSPreferences-Color.m', '.hasDestructiveAction = YES;', ';'),
    'new square bezel': ('Sources/Find/TSAdvancedFindProgressSheet.m', '_cancelButton.bordered = NO;', '_cancelButton.bordered = NO; _cancelButton.bezelStyle = NSBezelStyleShadowlessSquare;'),
    'square link popup': ('Sources/Preview/TSLinkPreviewView.m', '[edge stroke];', '[edge stroke]; NSFrameRect(bounds);'),
    'encoding label fixed width': ('Resources/Interfaces/Base.lproj/CustomModalWindowController.xib', '<constraint firstItem="jo5-hk-3mm" firstAttribute="leading" secondItem="BEr-Px-Bqw" secondAttribute="trailing" constant="8" id="Enc-pu-Gap"/>',
                                   '<constraint firstItem="BEr-Px-Bqw" firstAttribute="width" constant="81" id="Enc-lb-Wid"/><constraint firstItem="jo5-hk-3mm" firstAttribute="leading" secondItem="BEr-Px-Bqw" secondAttribute="trailing" constant="8" id="Enc-pu-Gap"/>'),
    'key binding list framed': ('Sources/Settings/TSKeyBindingsController.m', 'scroll.borderType = NSNoBorder;', 'scroll.borderType = NSBezelBorder;'),
    'key binding rows plain': ('Sources/Settings/TSKeyBindingsController.m', 'table.usesAlternatingRowBackgroundColors = YES;', 'table.usesAlternatingRowBackgroundColors = NO;'),
    'menu shortcut rows plain': ('Sources/Shortcuts/TSShortcutPaneController.m', 'self.table.usesAlternatingRowBackgroundColors = YES;', 'self.table.usesAlternatingRowBackgroundColors = NO;'),
    'call removed': ('Sources/Document/TSDocument.m', 'if (self.logWindow) TSLayoutLogWindow(self.logWindow);', ''),
}

with tempfile.TemporaryDirectory(prefix='texshop-older-panels-') as tmp:
    tmp = Path(tmp)
    problems = check(root, tmp)
    for p in problems:
        print('FAIL', p) if not p.startswith('FAIL') else None
    if problems:
        sys.exit(f'FAIL: {len(problems)} problems')
    print('PASS: older panels, notices, accessory labels, lists, destructive buttons, OgreKit Find panel sources and bezel styles')
    if args.mutations:
        missed = []
        for name, (path, old, new) in MUTATIONS.items():
            copy = tmp / 'mutant'
            if copy.exists():
                shutil.rmtree(copy)
            for part in ('Sources', 'Tests', 'Resources/Interfaces', '3rdparty/OgreKit-2.1.12-FindPanel'):
                shutil.copytree(root / part, copy / part, symlinks=True)
            target = copy / path
            text = target.read_text(encoding='utf-8', errors='surrogateescape')
            assert old in text, (name, path)
            target.write_text(text.replace(old, new, 1), encoding='utf-8', errors='surrogateescape')
            found = check(copy, tmp, quiet=True)
            print(f'MUTATION {name}: {"caught" if found else "MISSED"}' + (f' ({found[0][:120]})' if found else ''))
            if not found:
                missed.append(name)
        if missed:
            sys.exit(f'FAIL: mutations not caught: {", ".join(missed)}')
        print(f'PASS: all {len(MUTATIONS)} mutations caught')
