#!/usr/bin/env python3
"""The coloring of the Advanced Find panel's fields and of the multiple replacement rules
(Tests/AdvancedFindColoring.m): the tokens of patterns and replacement strings from the engine's own lexers, the
brackets that pair up, the real named groups (also the engine's), the marks of OgreKit's differences from the engine's
one table, the message line, bracket matching in the find field, the rule table, and every mark's message in the
smallest panel in all 12 languages. Nothing is displayed; the defaults stay in memory and the pasteboards are unique.

--image DIR writes the colored panel and rules, light and dark, in English and Japanese (--image-all-languages: all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file, advanced_find_syntax_sources

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
NEW_FILES = ['TSRegexPatternLexer.h', 'TSRegexPatternLexer.m', 'TSAdvancedFindFieldScanners.h', 'TSAdvancedFindFieldScanners.m',
             'TSAdvancedFindPanelController+Coloring.m']
KEYS = ['AdvancedFind.MoreMarks', 'AdvancedFind.Mark.UnmatchedParen', 'AdvancedFind.Mark.UnclosedParen', 'AdvancedFind.Mark.TrailingBackslash',
        'AdvancedFind.Mark.UnclosedName', 'AdvancedFind.Mark.UnclosedClass', 'AdvancedFind.Mark.UnclosedComment', 'AdvancedFind.Mark.BadGroup',
        'AdvancedFind.Mark.NothingToRepeat', 'AdvancedFind.Mark.TrailingBackslashReplacement', 'AdvancedFind.Mark.NoSuchGroup', 'AdvancedFind.Mark.NoSuchName']

MUTATIONS = {
    # The lab's stage 6 mutations that 6a did not take
    'a class loses its pairs': ('TSRegexPatternLexer.m', '    if (depth == 0)\n        [_pairs addObjectsFromArray:pairs];\n', ''),
    'the engine reads names with its own regular expression': ('TSRegexFindPattern.m',
        '_captureGroupNames = [[TSRegexPatternLexer alloc] initWithString:normalized options:options].groupNames;',
        '_captureGroupNames = [[NSRegularExpression regularExpressionWithPattern:@"\\\\(\\\\?<([A-Za-z][A-Za-z0-9]*)>" options:0 error:NULL] matchesInString:normalized options:0 range:NSMakeRange(0, normalized.length)].count ? @[@"a", @"b"] : @[];'),
    'the partner is the bracket itself': ('TSAdvancedFindPanelController+Coloring.m', '    NSUInteger partner = pair.location == bracket ? NSMaxRange(pair) - 1 : pair.location;',
                                          '    NSUInteger partner = bracket;'),
    'a double-click does not select the pair': ('TSAdvancedFindPanelController+Coloring.m', '    return pair.location == NSNotFound ? range : pair;', '    return range;'),
    '\\h has another message': ('TSAdvancedFindFieldScanners.m',
        '            ? [TSRegexFindPattern onigmoIncompatibilityOfKind:(TSRegexOnigmoIncompatibilityKind)token.incompatibility].message',
        '            ? [TSRegexFindPattern onigmoIncompatibilityOfKind:TSRegexOnigmoIncompatibilityKeep].message'),
    '\\( counts as a bracket': ('TSRegexPatternLexer.m', '    if (d >= \'1\' && d <= \'9\') {', '    if (d == \'(\') [_openGroups addObject:@(i + 1)];\n    if (d >= \'1\' && d <= \'9\') {'),
    # The coloring itself
    'quantifiers are text': ('TSRegexPatternLexer.m', '        [self add:i end:end role:TSSyntaxRoleRegexQuantifier];', '        [self add:i end:end role:TSSyntaxRoleNone];'),
    'a quantifier after nothing is valid': ('TSRegexPatternLexer.m', '    if (!_canRepeat)\n        [self add:i end:end problem:TSRegexLexerProblemNothingToRepeat];',
                                            '    if (NO)\n        [self add:i end:end problem:TSRegexLexerProblemNothingToRepeat];'),
    'a missing group is a reference': ('TSAdvancedFindFieldScanners.m', '                if (known && group > self.numberOfCaptureGroups) {', '                if (NO) {'),
    'a missing name is a reference': ('TSAdvancedFindFieldScanners.m', '                if (known && ![self.captureGroupNames containsObject:text]) {', '                if (NO) {'),
    'the replace field ignores the pattern': ('TSAdvancedFindPanelController+Coloring.m',
        "    TSRegexFindPattern *pattern = settings.findString.length > 0 ? [[TSRegexFindPattern alloc] initWithFindString:settings.findString options:options error:NULL] : nil;",
        "    TSRegexFindPattern *pattern = nil;"),
    'the replace field keeps its first scanner': ('TSAdvancedFindPanelController+Coloring.m', '        self.replaceHighlighter.scanner = replace;\n', '        (void)replace;\n'),
    'plain text is colored': ('TSAdvancedFindPanelController+Coloring.m', '    if (!regex) {\n        if (find)', '    if (NO) {\n        if (find)'),
    'the message line ignores the marks': ('TSAdvancedFindPanelController.m', '    NSArray<TSSyntaxDiagnostic *> *diagnostics = [self fieldDiagnostics];', '    NSArray<TSSyntaxDiagnostic *> *diagnostics = @[];'),
    'the message line ignores the replace field': ('TSAdvancedFindPanelController+Coloring.m', '@[self.findHighlighter, self.replaceHighlighter]', '@[self.findHighlighter]'),
    'typing in the replace field leaves the line': ('TSAdvancedFindPanelController.m', '        [self validatePattern]; // the marks of the replace field\n', ''),
    'the count of more marks is left out': ('TSAdvancedFindPanelController.m', '        if (diagnostics.count > 1) {', '        if (NO) {'),
    'incompatibilities are red': ('TSAdvancedFindPanelController.m', 'NSColor.systemRedColor : NSColor.systemOrangeColor', 'NSColor.systemRedColor : NSColor.systemRedColor'),
    'rules are not colored': ('TSMultipleReplaceWindowController.m', '        return TSMultipleReplaceColoredField(string, rule, field, options, weakSelf.ruleTable.set.replacementSyntax, attributes);', '        return nil;'),
    'plain rules are colored': ('TSMultipleReplaceWindowController.m', '    if (!rule.usesRegularExpression || !rule.enabled || !(options & TSRegexFindRegularExpression))', '    if (NO)'),
    'a rule ignores the set\'s syntax': ('TSMultipleReplaceWindowController.m', 'weakSelf.ruleTable.set.replacementSyntax, attributes);', 'TSRegexReplacementSyntaxICU, attributes);'),
    'unescaped places are those of the unescaped text': ('TSRegexReplacementTemplate.m',
        '                block(from[k].length > 1 ? TSRegexReplacementPieceEscape : TSRegexReplacementPieceText, from[k], [unescaped substringWithRange:NSMakeRange(k, 1)], 0);',
        '                block(TSRegexReplacementPieceText, NSMakeRange(k, 1), [unescaped substringWithRange:NSMakeRange(k, 1)], 0);'),
}


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
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindColoring</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    globals_m = source_file(root, 'globals.m').read_text(encoding='latin1')
    keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
    marker_keys = '\n'.join(f'NSString *{k} = {keys[k]};' for k in [
        'showSpaceCharacterKey', 'showFullwidthSpaceCharacterKey', 'showTabCharacterKey', 'showNewLineCharacterKey',
        'SpaceCharacterKindKey', 'FullwidthSpaceCharacterKindKey', 'TabCharacterKindKey', 'NewLineCharacterKindKey'])
    (tmp / 'keys.m').write_text('#import <Cocoa/Cocoa.h>\n' + marker_keys + '\nNSColor *InvisibleColor;\nBOOL atLeastMonterey = YES, atLeastSonoma = YES;\n')
    probe = app / 'Contents/MacOS/probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-Wno-deprecated-declarations', '-Wno-deprecated-implementations', '-Wnullability-completeness', '-Werror=nullability-completeness',
                    '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa',
                    str(root / 'Tests/AdvancedFindColoring.m'), str(tmp / 'keys.m'), *map(str, sorted(sources.glob('*.m'))), *map(str, advanced_find_syntax_sources(root)),
                    '-o', str(probe)], check=True)
    return probe


def run(probe, mode, language='en', images=None):
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    return subprocess.run(command, capture_output=True, text=True, timeout=900)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in [*(root / 'Sources/Find').glob('*.[mh]'), source_file(root, 'TSLayoutManager.m'), source_file(root, 'TSLayoutManager.h')]:
        shutil.copy(path, sources / path.name)
    return sources


def check_project():
    project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text()
    for name in NEW_FILES:
        quoted = f'"{name}"' if '+' in name else name
        if f'path = {quoted};' not in project or (name.endswith('.m') and f'/* {name} in Sources */,' not in project):
            sys.exit(f'FAIL: {name} is not in the application')
    for language in LANGUAGES:
        table = (root / 'Resources/Interfaces' / f'{language}.lproj/AdvancedFind.strings').read_text()
        missing = [k for k in KEYS if f'"{k}" = ' not in table]
        if missing:
            sys.exit(f'FAIL: {language} AdvancedFind.strings lacks {missing}')
    print('PASS: the coloring files and their strings in all 12 languages are in the application')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true', help='images in all 12 languages, not only English and Japanese')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    check_project()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-coloring-') as tmp:
        tmp = Path(tmp)
        probe = build(tmp, copy_sources(tmp))
        result = run(probe, 'behavior')
        print(result.stdout + result.stderr, end='')
        if result.returncode:
            sys.exit('FAIL: behavior')
        for language in LANGUAGES:
            images = args.image if args.image and (args.image_all_languages or language in ('en', 'ja')) else None
            result = run(probe, 'layout', language, images)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit(f'FAIL: the messages in {language}')
        if args.image:
            print(f'images in {args.image}')
        if args.mutations:
            survivors = []
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-coloring-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new))
                    mprobe = build(mtmp, sources)
                    results = [run(mprobe, 'behavior'), run(mprobe, 'layout')]
                    if all(r.returncode == 0 for r in results):
                        print(f'FAIL: mutation {name!r} was not detected')
                        survivors.append(name)
                    else:
                        print(f'PASS: detected mutation {name!r}')
            if survivors:
                sys.exit(f'FAIL: {len(survivors)} of {len(MUTATIONS)} mutations were not detected')
            print(f'PASS: all {len(MUTATIONS)} mutations detected')
    print('PASS: the coloring of the Advanced Find fields')


if __name__ == '__main__':
    main()
