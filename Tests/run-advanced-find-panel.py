#!/usr/bin/env python3
"""The Advanced Find panel (Tests/AdvancedFindPanel.m): the controller on real text views, the routing of the
Find menu, the highlights drawn by the real TSLayoutManager (in pixels), and the panel in all 12 languages.
Nothing is displayed; the defaults stay in memory and the pasteboards are unique.

--image DIR writes the panel, its options and the highlights, light and dark, in English and Japanese
(--image-all-languages: in all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']

MUTATIONS = {
    'highlights are drawn before the background': ('TSLayoutManager.m',
        '\t[super drawBackgroundForGlyphRange:glyphsToShow atPoint:origin];\n\t[TSAdvancedFindHighlights drawInLayoutManager:self forGlyphRange:glyphsToShow atPoint:origin];',
        '\t[TSAdvancedFindHighlights drawInLayoutManager:self forGlyphRange:glyphsToShow atPoint:origin];\n\t[super drawBackgroundForGlyphRange:glyphsToShow atPoint:origin];'),
    'highlights do not follow edits': ('TSAdvancedFindHighlights.m',
        '    if (!(storage.editedMask & NSTextStorageEditedCharacters) || self.ranges.count == 0)', '    if (YES)'),
    'TSLayoutManager draws no highlights': ('TSLayoutManager.m',
        '\t[TSAdvancedFindHighlights drawInLayoutManager:self forGlyphRange:glyphsToShow atPoint:origin];\n', ''),
    'replacements are not registered for undo': ('TSAdvancedFindController.m',
        '    if (![textView shouldChangeTextInRanges:ranges replacementStrings:strings])\n        return NO;\n', ''),
    'read-only text views take replacing': ('TSAdvancedFindController.m', '            return textView.isEditable && !TSTextViewRefusesReplacing(textView);', '            return YES;'),
    'Find and Replace… is not routed': ('TSAdvancedFindController.m', '        case TSAdvancedFindActionShowReplacePanel:\n            if', '            if'),
    'the panel\'s field keeps the Find menu': ('TSAdvancedFindPanelController.m',
        '    if (controller && (item.action == @selector(performFindPanelAction:)', '    if (NO && (item.action == @selector(performFindPanelAction:)'),
    'the buttons ignore a read-only target': ('TSAdvancedFindPanelController+Actions.m',
        '    return target ? [self.findController validateAction:action forTextView:target] : YES;', '    return YES;'),
    'TSTextView keeps the Find menu': ('TSTextView.m', '\tif (advancedFind)\n\t\t[advancedFind performFindPanelAction:sender inTextView:self];\n\telse\n\t\t[super performFindPanelAction:sender];',
        '\t[super performFindPanelAction:sender];'),
    'TSTextView routes whatever the find method': ('TSAdvancedFindTextView.m', '    if ([SUD integerForKey:FindMethodKey] != TSFindMethodAdvancedPanel)\n        return nil;\n', ''),
    'TSTextView validates Find and Replace… itself': ('TSTextView.m', 'if (advancedFind && ([anItem action] == @selector(performFindPanelAction:) || [anItem action] == @selector(performTextFinderAction:)))',
        'if (advancedFind && [anItem action] == @selector(performFindPanelAction:))'),
    'ConvertLF is ignored': ('TSAdvancedFindTextView.m', 'return [SUD boolForKey:ConvertLFKey] ? @"\\n" : nil;', 'return @"\\n";'),
    'Find Selected Text escapes only metacharacters': ('TSAdvancedFindController.m',
        '    if (!extended && !yen)\n        return escaped;', '    return escaped;'),
    'Find Selected Text escapes a literal pattern': ('TSAdvancedFindController.m',
        'if (!(options & TSRegexFindRegularExpression) || (options & TSRegexFindIgnoreMetacharacters))', 'if (!(options & TSRegexFindRegularExpression))'),
    'Find Selected Text leaves the directional marks': ('TSAdvancedFindController.m', '    [whitespace addCharactersInString:@"\\u200E\\u200F"];\n', ''),
    'the line ending is not put into the find string': ('TSAdvancedFindController.m',
        'NSString *findString = lineEnding ? TSRegexStringByReplacingLineEndings(self.settings.findString, lineEnding) : self.settings.findString;',
        'NSString *findString = self.settings.findString;'),
}


ROUTING = r'''
// The routing of TSTextView (Sources/Editor/TSTextView.m), taken verbatim: with FindMethod 3 the Find menu reaches the
// shared Advanced Find controller, otherwise NSTextView's own find.
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSFindInterface.h"
#import "TSAdvancedFindPanelController.h"
#import "TSAdvancedFindTextView.h"
#undef SUD
#define SUD TSIsolatedAppKitDefaults
NSString *FindMethodKey = @"FindMethod", *ConvertLFKey = @"ConvertLF";
static BOOL g_canRegisterCommandCompletion = NO;
static int failures;
static void Check(BOOL ok, const char *what) { if (!ok) { fprintf(stderr, "FAIL: %s\n", what); failures++; } }
@interface RoutingTextView : NSTextView
- (BOOL)validateEditTextCommand:(NSMenuItem *)item enabled:(BOOL *)enabled;
- (void)registerForCommandCompletion:(id)sender;
@end
@implementation RoutingTextView
- (BOOL)validateEditTextCommand:(NSMenuItem *)item enabled:(BOOL *)enabled { return NO; }
- (void)registerForCommandCompletion:(id)sender {}
METHODS
@end
static NSMutableArray<NSNumber *> *performed;
static NSUInteger textViewFinds, validations;
static BOOL RecordPerform(id self, SEL _cmd, NSInteger action, NSTextView *view) { [performed addObject:@(action)]; return YES; }
static void RecordTextViewFind(id self, SEL _cmd, id sender) { textViewFinds++; }
static IMP originalValidate;
static BOOL CountValidate(id self, SEL _cmd, NSInteger action, NSTextView *view) { validations++; return ((BOOL (*)(id, SEL, NSInteger, NSTextView *))originalValidate)(self, _cmd, action, view); }
static NSMenuItem *Item(SEL action, NSInteger tag) { NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""]; item.tag = tag; return item; }
int main(void)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        performed = [NSMutableArray array];
        method_setImplementation(class_getInstanceMethod(TSAdvancedFindController.class, @selector(performAction:inTextView:)), (IMP)RecordPerform);
        method_setImplementation(class_getInstanceMethod(NSTextView.class, @selector(performFindPanelAction:)), (IMP)RecordTextViewFind);
        method_setImplementation(class_getInstanceMethod(NSTextView.class, @selector(performTextFinderAction:)), (IMP)RecordTextViewFind);
        Method validate = class_getInstanceMethod(TSAdvancedFindController.class, @selector(validateAction:forTextView:));
        originalValidate = method_setImplementation(validate, (IMP)CountValidate);
        RoutingTextView *view = [[RoutingTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        view.string = @"text";
        for (NSNumber *method in @[@0, @1, @2]) {
            [SUD setInteger:method.integerValue forKey:FindMethodKey];
            [view performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionNext)];
            [view performTextFinderAction:Item(@selector(performTextFinderAction:), NSTextFinderActionShowReplaceInterface)];
            [view validateMenuItem:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)];
        }
        Check(textViewFinds == 6 && performed.count == 0 && validations == 0, "with another find method, the Find menu stays with NSTextView");
        [SUD setInteger:TSFindMethodAdvancedPanel forKey:FindMethodKey];
        [view performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionNext)];
        [view performTextFinderAction:Item(@selector(performTextFinderAction:), NSTextFinderActionShowReplaceInterface)];
        [view performFindPanelAction:Item(@selector(performFindPanelAction:), NSFindPanelActionSetFindString)];
        Check(textViewFinds == 6 && [performed isEqualToArray:@[@2, @12, @7]], "with the Advanced Find panel, Find Next, Find and Replace… and Use Selection for Find reach its controller");
        view.editable = NO;
        Check(![view validateMenuItem:Item(@selector(performFindPanelAction:), NSFindPanelActionReplaceAll)] && validations == 1, "the menu is validated by the controller: no Replace All in a read-only view");
        Check([view validateMenuItem:Item(@selector(performTextFinderAction:), NSTextFinderActionShowReplaceInterface)], "Find and Replace… is enabled");
        Check(TSAdvancedFindPanelController.sharedPanelController.findController == TSAdvancedFindController.sharedController, "the shared panel works on the shared controller");
        NSString *_Nullable (^lineEnding)(NSTextView *) = TSAdvancedFindController.sharedController.lineEndingHandler;
        [SUD setBool:YES forKey:ConvertLFKey];
        Check(lineEnding && [lineEnding(view) isEqualToString:@"\n"], "with ConvertLF on, the find string and the replacements take LF");
        [SUD setBool:NO forKey:ConvertLFKey];
        Check(lineEnding && lineEnding(view) == nil, "with ConvertLF off, their line endings are kept");
        Check(!TSAdvancedFindPanelController.sharedPanelController.window.isVisible, "nothing is shown");
        if (failures)
            return 1;
        puts("PASS routing of TSTextView");
    }
    return 0;
}
'''


def text_view_methods(text):
    def method(signature):
        start = text.index(signature)
        return text[start:text.index('\n}\n', start) + 3]
    return ''.join(method(s) for s in ['- (BOOL)validateMenuItem:(NSMenuItem *)anItem\n', '- (nullable TSAdvancedFindController *)advancedFindController\n',
                                         '- (void)performFindPanelAction:(id)sender\n', '- (void)performTextFinderAction:(id)sender\n'])


def build(tmp, sources):
    """A small application bundle, so the strings tables are found as in TeXShop.app."""
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
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindPanel</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    globals_m = source_file(root, 'globals.m').read_text(encoding='latin1')
    keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
    marker_keys = '\n'.join(f'NSString *{k} = {keys[k]};' for k in [
        'showSpaceCharacterKey', 'showFullwidthSpaceCharacterKey', 'showTabCharacterKey', 'showNewLineCharacterKey',
        'SpaceCharacterKindKey', 'FullwidthSpaceCharacterKindKey', 'TabCharacterKindKey', 'NewLineCharacterKindKey', 'FindMethodKey', 'ConvertLFKey'])
    (tmp / 'keys.m').write_text('#import <Cocoa/Cocoa.h>\n' + marker_keys + '\nNSColor *InvisibleColor;\nBOOL atLeastMonterey = YES, atLeastSonoma = YES;\n')
    probe = app / 'Contents/MacOS/probe'
    (tmp / 'routing.m').write_text(ROUTING.replace('METHODS', text_view_methods((sources / 'TSTextView.m').read_text(encoding='latin1'))))
    finds = [str(p) for p in sorted(sources.glob('*.m')) if p.name not in ('TSLayoutManager.m', 'TSTextView.m')]
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter', '-Wno-unused-function',
                    '-Wno-undeclared-selector', '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa',
                    str(tmp / 'routing.m'), *finds, '-o', str(app / 'Contents/MacOS/routing')], check=True)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-Wno-deprecated-declarations', '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'),
                    '-framework', 'Cocoa', str(root / 'Tests/AdvancedFindPanel.m'), str(tmp / 'keys.m'),
                    *map(str, sorted(p for p in sources.glob('*.m') if p.name != 'TSTextView.m')),
                    '-o', str(probe)], check=True)
    return probe


def run(probe, mode, language='en', images=None):
    if mode == 'routing':
        return subprocess.run([str(probe.with_name('routing'))], capture_output=True, text=True, timeout=120)
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    return subprocess.run(command, capture_output=True, text=True, timeout=120)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in [*(root / 'Sources/Find').glob('*.[mh]'), source_file(root, 'TSLayoutManager.m'), source_file(root, 'TSLayoutManager.h'),
                 source_file(root, 'TSTextView.m')]:
        shutil.copy(path, sources / path.name)
    return sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true', help='images in all 12 languages, not only English and Japanese')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-panel-') as tmp:
        tmp = Path(tmp)
        probe = build(tmp, copy_sources(tmp))
        for mode in ['behavior', 'routing']:
            result = run(probe, mode)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit(f'FAIL: {mode}')
        project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text()
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings']:
            if len(re.findall(r'path = "?[\w-]+\.lproj/' + re.escape(table) + '"?;', project)) != len(LANGUAGES) or f'/* {table} in Resources */,' not in project:
                sys.exit(f'FAIL: {table} is not in the application in all 12 languages')
        print('PASS: both tables are in the application in all 12 languages')
        for language in LANGUAGES:
            images = args.image if args.image and (args.image_all_languages or language in ('en', 'ja')) else None
            result = run(probe, 'panel', language, images)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit(f'FAIL: the panel in {language}')
        if args.image:
            print(f'images in {args.image}')
        if args.mutations:
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new))
                    mprobe = build(mtmp, sources)
                    results = [run(mprobe, 'behavior'), run(mprobe, 'routing'), run(mprobe, 'panel')]
                    if all(r.returncode == 0 for r in results):
                        sys.exit(f'FAIL: mutation {name!r} was not detected')
                    print(f'PASS: detected mutation {name!r}')
    print('PASS: Advanced Find panel')


if __name__ == '__main__':
    main()
