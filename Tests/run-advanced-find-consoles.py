#!/usr/bin/env python3
"""The Advanced Find panel in the console, the log and the Experiment windows (Tests/AdvancedFindConsoles.m).

The shipped TSDocument nibs of all 12 languages, the production Experiment console controller, the Find sources, the
TSDocument method that reacts to a change of the find method (taken verbatim) and TSLayoutManager are compiled into a
small application. Nothing is displayed; the defaults stay in memory and the find pasteboard is unique.

--image DIR writes the console, the Experiment source and output with highlights and the panel acting on the console,
light and dark, in English and Japanese.
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file, advanced_find_syntax_sources
from experiment_console_source import prefix as console_prefix

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
NIB_DIRS = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']

MUTATIONS = {
    'a text view from a nib keeps its layout manager': ('TSAdvancedFindTextView.m',
        '    [TSAdvancedFindLayoutManager installInTextView:self]; // from a nib', '    // from a nib'),
    'a text view made in code keeps its layout manager': ('TSAdvancedFindTextView.m',
        '    if ((self = [super initWithFrame:frame textContainer:container]))\n        [TSAdvancedFindLayoutManager installInTextView:self];',
        '    self = [super initWithFrame:frame textContainer:container];'),
    'the text views route whatever the find method': ('TSAdvancedFindTextView.m',
        '    if ([defaults integerForKey:TSFindMethodKey] != TSFindMethodAdvancedPanel)\n        return nil;\n', ''),
    'the text views validate the find menu themselves': ('TSAdvancedFindTextView.m',
        '    if (controller && (item.action == @selector(performFindPanelAction:) || item.action == @selector(performTextFinderAction:)))\n        return [controller validateFindMenuItem:item inTextView:self];',
        '    if (controller && item.action == @selector(performFindPanelAction:))\n        return [controller validateFindMenuItem:item inTextView:self];'),
    'Find and Replace… is not routed': ('TSAdvancedFindTextView.m',
        '    if (controller)\n        [controller performFindPanelAction:sender inTextView:self];\n    else\n        [super performTextFinderAction:sender];',
        '    [super performTextFinderAction:sender];'),
    'the Experiment output is a plain NSTextView': ('TSExperimentConsoleController.m',
        'TSAdvancedFindTextView *text = [[TSAdvancedFindTextView alloc] initWithFrame:', 'NSTextView *text = [[NSTextView alloc] initWithFrame:'),
    'the key window is not followed': ('TSAdvancedFindTextView.m',
        '    NSTextView *key = TSFocusedTarget(NSApp.keyWindow);\n    if (key)\n        return key;\n', ''),
    'a panel clears the last target': ('TSAdvancedFindTextView.m', '    else if (window.canBecomeMainWindow)\n', '    else\n'),
    'a window stopping being key is not noted': ('TSAdvancedFindTextView.m',
        '        [center addObserverForName:NSWindowDidResignKeyNotification object:nil queue:nil usingBlock:note];\n', ''),
    'a closed window stays the target': ('TSAdvancedFindTextView.m', '    if (last.window.isVisible)', '    if (last)'),
    'the panel acts on the main window only': ('TSAdvancedFindTextView.m',
        '    if (TSTestTargetTextView)\n        return TSTestTargetTextView;\n',
        '    if (TSTestTargetTextView)\n        return TSTestTargetTextView;\n    if (YES) return [NSApp.mainWindow.firstResponder isKindOfClass:[NSTextView class]] ? (NSTextView *)NSApp.mainWindow.firstResponder : nil;\n'),
    'leaving the panel keeps the console\'s highlights': ('TSDocument.m',
        'NSTextView *views[] = {textView1, outputText, self.logTextView, scrapTextView, self.experimentConsole.outputText};',
        'NSTextView *views[] = {textView1};'),
    'leaving the panel keeps the Experiment output\'s highlights': ('TSDocument.m',
        'NSTextView *views[] = {textView1, outputText, self.logTextView, scrapTextView, self.experimentConsole.outputText};',
        'NSTextView *views[] = {textView1, outputText, self.logTextView, scrapTextView};'),
    'the console and the log take replacing': ('TSAdvancedFindController.m',
        '            return textView.isEditable && !TSTextViewRefusesReplacing(textView);', '            return textView.isEditable;'),
    'the Experiment source finds with NSTextView': ('ScrapTextView.h', '@interface ScrapTextView : TSAdvancedFindTextView', '@interface ScrapTextView : NSTextView'),
}

DOCUMENT_HEADER = r'''
#import <Cocoa/Cocoa.h>
@interface TestExperimentConsole : NSObject
@property (nonatomic, strong) NSTextView *outputText;
@end
/// The TSDocument instance variables and properties that -findInterfacePreferencesChanged: uses.
@interface TestDocumentFind : NSObject {
@public
    NSTextView *textView1, *textView2, *outputText, *scrapTextView;
}
@property (retain) NSTextView *logTextView;
@property (strong) TestExperimentConsole *experimentConsole;
- (void)findInterfacePreferencesChanged:(NSNotification *)notification;
@end
'''

DOCUMENT = r'''
// -[TSDocument findInterfacePreferencesChanged:] (Sources/Document/TSDocument.m), taken verbatim.
#import "TestDocumentFind.h"
#import "TSFindInterface.h"
#import "TSAdvancedFindPanelController.h"
#import "TSAdvancedFindHighlights.h"
#define SUD [NSUserDefaults standardUserDefaults]
static NSString *FindMethodKey = @"FindMethod";
static NSString *IncrementalSearchKey = @"IncrementalSearch";
static NSDictionary *TSSettingsLaunchValues(void) { return @{}; }
@implementation TestExperimentConsole
@end
@implementation TestDocumentFind
METHOD
@end
'''


def check_sources(sources):
    """ScrapTextView is not compiled here (it needs the whole TSDocument): its superclass routes and draws, and it
    overrides none of the routing."""
    header = (sources / 'ScrapTextView.h').read_text(encoding='latin1')
    body = (sources / 'ScrapTextView.m').read_text(encoding='latin1')
    problems = []
    if not re.search(r'@interface ScrapTextView\s*:\s*TSAdvancedFindTextView\b', header):
        problems.append('ScrapTextView is not a TSAdvancedFindTextView')
    for name in ['performFindPanelAction:', 'performTextFinderAction:', 'validateMenuItem:', 'findController']:
        if re.search(r'^-\s*\([^)]*\)\s*' + re.escape(name), body, re.M):
            problems.append(f'ScrapTextView overrides {name}')
    for nib in NIB_DIRS:
        text = (root / 'Resources/Interfaces' / f'{nib}.lproj/TSDocument.nib/designable.nib').read_text(encoding='utf-8')
        for outlet in ['outputText', 'logTextView']:
            (target,) = re.findall(r'<outlet property="%s" destination="([^"]+)"' % outlet, text)
            if not re.search(r'<textView [^>]*id="%s"[^>]*customClass="TSAdvancedFindTextView"' % re.escape(target), text):
                problems.append(f'{nib}: the {outlet} of designable.nib is not a TSAdvancedFindTextView')
            if not re.search(r'<textView [^>]*id="%s"[^>]*>(?:(?!</textView>).)*keyPath="refusesReplacing" value="YES"' % re.escape(target), text, re.S):
                problems.append(f'{nib}: the {outlet} of designable.nib does not refuse replacing')
        if b'TSAdvancedFindTextView' not in (root / 'Resources/Interfaces' / f'{nib}.lproj/TSDocument.nib/keyedobjects.nib').read_bytes():
            problems.append(f'{nib}: the compiled nib has no TSAdvancedFindTextView')
    return problems


def document_method(text):
    start = text.index('- (void)findInterfacePreferencesChanged:(NSNotification *)notification\n')
    return text[start:text.index('\n}\n', start) + 3]


def build(tmp, sources):
    """A small application bundle, so the panel's strings tables are found as in TeXShop.app."""
    app = tmp / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    for language in LANGUAGES:
        (resources / f'{language}.lproj').mkdir(parents=True)
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings']:
            shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindConsoles</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    globals_m = source_file(root, 'globals.m').read_text(encoding='latin1')
    keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
    marker_keys = '\n'.join(f'NSString *{k} = {keys[k]};' for k in [
        'showSpaceCharacterKey', 'showFullwidthSpaceCharacterKey', 'showTabCharacterKey', 'showNewLineCharacterKey',
        'SpaceCharacterKindKey', 'FullwidthSpaceCharacterKindKey', 'TabCharacterKindKey', 'NewLineCharacterKindKey'])
    (tmp / 'keys.m').write_text('#import <Cocoa/Cocoa.h>\n' + marker_keys + '\nNSColor *InvisibleColor;\nBOOL atLeastMonterey = YES, atLeastSonoma = YES;\n')
    controller = (sources / 'TSExperimentConsoleController.m').read_text().replace('#import "TSEncodingSupport.h"', '').replace('#import "globals.h"', '')
    # TestAppKitIsolation.h defines a class; the probe's own file includes it.
    (tmp / 'console.m').write_text(console_prefix(root).replace('#import "TestAppKitIsolation.h"', '') + controller)
    (tmp / 'TestDocumentFind.h').write_text(DOCUMENT_HEADER)
    (tmp / 'document.m').write_text(DOCUMENT.replace('METHOD', document_method((sources / 'TSDocument.m').read_text(encoding='latin1'))))
    probe = app / 'Contents/MacOS/probe'
    finds = [str(p) for p in sorted(sources.glob('TS*.m')) if p.name not in ('TSExperimentConsoleController.m', 'TSDocument.m')]
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-w', '-I', str(tmp), '-I', str(sources),
                    *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa', '-framework', 'PDFKit', '-framework', 'Quartz',
                    str(root / 'Tests/AdvancedFindConsoles.m'), str(tmp / 'console.m'), str(tmp / 'document.m'), str(tmp / 'keys.m'),
                    str(root / 'Sources/Typesetting/TSExperimentJob.m'), str(root / 'Sources/Typesetting/TSConsoleOutput.m'), *finds,
                    *(str(p) for p in advanced_find_syntax_sources(root) if p.name != 'TSColorSupportStub.m'),
                    '-o', str(probe)], check=True)
    return probe


def nibs():
    return [str(root / 'Resources/Interfaces' / f'{d}.lproj/TSDocument.nib/keyedobjects.nib') for d in NIB_DIRS]


def run(probe, mode, arguments, language='en'):
    """In a home of its own, so nothing of the user's is read or written."""
    command = [str(probe), mode, *arguments, '-AppleLanguages', f'({language})']
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-consoles-home-') as home:
        (Path(home) / 'Library/Preferences').mkdir(parents=True)
        env = dict(os.environ, HOME=home, CFFIXED_USER_HOME=home)
        return subprocess.run(command, capture_output=True, text=True, timeout=300, env=env)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in [*(root / 'Sources/Find').glob('*.[mh]'), source_file(root, 'TSLayoutManager.m'), source_file(root, 'TSLayoutManager.h'),
                 source_file(root, 'TSExperimentConsoleController.m'), source_file(root, 'TSDocument.m'),
                 source_file(root, 'ScrapTextView.h'), source_file(root, 'ScrapTextView.m')]:
        shutil.copy(path, sources / path.name)
    return sources


def failures(output):
    return '\n'.join(line for line in output.splitlines() if line.startswith('FAIL'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-consoles-') as tmp:
        tmp = Path(tmp)
        sources = copy_sources(tmp)
        problems = check_sources(sources)
        if problems:
            sys.exit('FAIL: ' + '; '.join(problems))
        print('PASS: ScrapTextView finds as a TSAdvancedFindTextView; the console and the log of all 12 nibs are TSAdvancedFindTextViews that refuse replacing')
        probe = build(tmp, sources)
        result = run(probe, 'behavior', nibs())
        print(result.stdout + failures(result.stderr), end='\n')
        if result.returncode:
            sys.exit('FAIL: behavior')
        if args.image:
            args.image.mkdir(parents=True, exist_ok=True)
            for language, nib in [('en', 'Base'), ('ja', 'ja')]:
                path = str(root / 'Resources/Interfaces' / f'{nib}.lproj/TSDocument.nib/keyedobjects.nib')
                result = run(probe, 'images', [path, str(args.image.resolve())], language)
                print(result.stdout + failures(result.stderr), end='\n')
                if result.returncode:
                    sys.exit(f'FAIL: images in {language}')
            print(f'images in {args.image}')
        if args.mutations:
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-consoles-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    msources = copy_sources(mtmp)
                    text = (msources / file).read_text(encoding='latin1')
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (msources / file).write_text(text.replace(old, new), encoding='latin1')
                    if check_sources(msources):
                        print(f'PASS: detected mutation {name!r} (sources)')
                        continue
                    try:
                        mprobe = build(mtmp, msources)
                    except subprocess.CalledProcessError:
                        sys.exit(f'FAIL: mutation {name!r} does not build')
                    if run(mprobe, 'behavior', nibs()).returncode == 0:
                        sys.exit(f'FAIL: mutation {name!r} was not detected')
                    print(f'PASS: detected mutation {name!r}')
    print('PASS: Advanced Find panel in the console, the log and the Experiment windows')


if __name__ == '__main__':
    main()
