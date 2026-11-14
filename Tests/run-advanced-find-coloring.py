#!/usr/bin/env python3
"""The coloring of the Advanced Find panel's fields and of the multiple replacement rules
(Tests/AdvancedFindColoring.m): the tokens of patterns and replacement strings from the engine's own lexers, the
brackets that pair up, the real named groups (also the engine's), the marks of OgreKit's differences from the engine's
one table, the message line, bracket matching in the find field, the rule table, every mark's message in the
smallest panel in all 12 languages, and the source's theme (the bundled themes, read with TSColorSupport's own
look-ups), font and TeX coloring in the fields and the rules. Nothing is displayed; the defaults stay in memory and
the pasteboards are unique.

--image DIR writes the panel (a TeX pattern with Regular expression on and off, and every role) and the rules in three
pairs of bundled themes, light and dark, in English and Japanese (--image-all-languages: all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file, advanced_find_syntax_sources
from production_fragments import method

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
NEW_FILES = ['TSRegexPatternLexer.h', 'TSRegexPatternLexer.m', 'TSAdvancedFindFieldScanners.h', 'TSAdvancedFindFieldScanners.m',
             'TSAdvancedFindPanelController+Coloring.m', 'TSAdvancedFindFieldStyle.h', 'TSAdvancedFindFieldStyle.m']
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
    # Inline flags and comment ends as ICU reads them (first audit F1, F2)
    'an inline x is ignored': ('TSRegexPatternLexer.m', '        _extended = extended;     // (?x): until the enclosing group ends\n', ''),
    'a group does not end its x': ('TSRegexPatternLexer.m', '                _extended = _openExtended.lastObject.boolValue;\n', ''),
    'U+2028 does not end a comment': ('TSRegexPatternLexer.m', ' && [self at:j] != 0x2028)', ')'),
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
    'plain text is read as a regular expression': ('TSAdvancedFindPanelController+Coloring.m', '    if (!regex) {\n        // A new scanner', '    if (NO) {\n        // A new scanner'),
    'the message line ignores the marks': ('TSAdvancedFindPanelController.m', '    NSArray<TSSyntaxDiagnostic *> *diagnostics = [self fieldDiagnostics];', '    NSArray<TSSyntaxDiagnostic *> *diagnostics = @[];'),
    'the message line ignores the replace field': ('TSAdvancedFindPanelController+Coloring.m', '@[self.findHighlighter, self.replaceHighlighter]) {\n        id<TSSyntaxScanner> scanner',
                                                   '@[self.findHighlighter]) {\n        id<TSSyntaxScanner> scanner'),
    'typing in the replace field leaves the line': ('TSAdvancedFindPanelController.m', '        [self validatePattern]; // the marks of the replace field\n', ''),
    'the count of more marks is left out': ('TSAdvancedFindPanelController.m', '        if (diagnostics.count > 1) {', '        if (NO) {'),
    'incompatibilities are red': ('TSAdvancedFindPanelController.m', 'NSColor.systemRedColor : NSColor.systemOrangeColor', 'NSColor.systemRedColor : NSColor.systemRedColor'),
    'rules are not colored': ('TSMultipleReplaceWindowController.m', '        return TSMultipleReplaceColoredField(string, rule, field, options, weakSelf.ruleTable.set.replacementSyntax, attributes, weakSelf.fieldStyle);', '        return nil;'),
    'plain rules are read as regular expressions': ('TSMultipleReplaceWindowController.m', '    if (!rule.usesRegularExpression || !(options & TSRegexFindRegularExpression))\n', '    if (NO)\n'),
    'a rule ignores the set\'s syntax': ('TSMultipleReplaceWindowController.m', 'weakSelf.ruleTable.set.replacementSyntax, attributes, weakSelf.fieldStyle);', 'TSRegexReplacementSyntaxICU, attributes, weakSelf.fieldStyle);'),
    'unescaped places are those of the unescaped text': ('TSRegexReplacementTemplate.m',
        '                block(from[k].length > 1 ? TSRegexReplacementPieceEscape : TSRegexReplacementPieceText, from[k], [unescaped substringWithRange:NSMakeRange(k, 1)], 0);',
        '                block(TSRegexReplacementPieceText, NSMakeRange(k, 1), [unescaped substringWithRange:NSMakeRange(k, 1)], 0);'),
    # The theme, the font and the appearance
    'escapes take XMLSpecial': ('TSSyntaxColorScheme.m', '{TSSyntaxRoleRegexEscape, @"explIntenseFunction"', '{TSSyntaxRoleRegexEscape, @"XMLSpecial"'),
    'symbols have no theme key': ('TSSyntaxColorScheme.m', '    {TSSyntaxRoleRegexSymbol, @"SyntaxMarkerParen", TSSyntaxThemeFallbackBuiltIn, NO},\n', ''),
    'the marks are lost': ('TSAdvancedFindFieldStyle.m', '        [roles addEntriesFromDictionary:TSMarkAttributes()];\n', ''),
    'coloring off keeps colors': ('TSAdvancedFindFieldStyle.m', '        TSSyntaxColorScheme *scheme = self.scheme;',
                                  '        TSSyntaxColorScheme *scheme = self.scheme ?: [[TSSyntaxColorScheme alloc] initWithTheme:@{} dark:NO];'),
    'the font is not kept in its sizes': ('TSAdvancedFindFieldStyle.m', 'CGFloat size = MIN(MAX(font.pointSize, 11), 16);', 'CGFloat size = font.pointSize;'),
    'the window\'s late appearance is used': ('TSAdvancedFindFieldStyle.m', 'window.appearance ?: NSApp.effectiveAppearance ?: window.effectiveAppearance', 'window.effectiveAppearance ?: NSApp.effectiveAppearance'),
    'the box keeps the text background': ('TSAdvancedFindInputBox.m', 'fill = (self.fillColor ?: NSColor.textBackgroundColor).CGColor;', 'fill = NSColor.textBackgroundColor.CGColor;'),
    'the box of a dark theme is light': ('TSAdvancedFindPanelController+Coloring.m', 'field.box.appearance = style.fieldAppearance;', 'field.box.appearance = nil;'),
    'the insertion point keeps the text color': ('TSAdvancedFindPanelController+Coloring.m', 'field.insertionPointColor = style.insertionPointColor ?: NSColor.textColor;',
                                                 'field.insertionPointColor = NSColor.textColor;'),
    'the appearance is not followed': ('TSAdvancedFindPanelController+Coloring.m', '    if (context == TSFieldAppearanceContext)\n        [self applyFieldStyle];',
                                       '    if (context == TSFieldAppearanceContext)\n        ;'),
    'the theme is not followed': ('TSAdvancedFindPanelController+Coloring.m', '- (void)fieldStyleDidChange:(NSNotification *)notification\n{\n    [self applyFieldStyle];\n}',
                                  '- (void)fieldStyleDidChange:(NSNotification *)notification\n{\n}'),
    'the rules keep their cells': ('TSMultipleReplaceWindowController.m', '    [self.ruleTable reloadFieldCells];\n', ''),
    'the rules ignore the appearance': ('TSMultipleReplaceWindowController.m', '    if (context == TSRuleAppearanceContext)\n        [self fieldStyleDidChange:nil];',
                                        '    if (context == TSRuleAppearanceContext)\n        ;'),
}


def color_support(tmp):
    """The theme look-ups of the application's TSColorSupport, unchanged: the fields take the theme's colors through the
    color scheme (Sources/Syntax/TSSyntaxColorScheme.m), which reads themes with them."""
    text = source_file(root, 'TSColorSupport.m').read_text(encoding='latin1')
    methods = '\n'.join(method(text, signature) for signature in [
        '- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:',
        '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:', '- (NSColor *)liteColorAndAlphaWithKey:', '- (NSColor *)darkColorAndAlphaWithKey:'])
    path = tmp / 'ColorSupport.m'
    path.write_text('#import "TSColorSupport.h"\n#pragma clang diagnostic ignored "-Wincomplete-implementation"\n@implementation TSColorSupport\n'
                    '+ (id)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }\n' + methods + '\n@end\n')
    return path


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
                    str(root / 'Tests/AdvancedFindColoring.m'), str(tmp / 'keys.m'), *map(str, sorted(sources.glob('*.m'))), str(color_support(tmp)),
                    '-o', str(probe)], check=True)
    return probe


def run(probe, mode, language='en', images=None):
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    environment = dict(os.environ, ADVANCED_FIND_THEMES=str(root / 'Resources/TeXShop/Themes'))
    return subprocess.run(command, capture_output=True, text=True, timeout=900, env=environment)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    syntax = [path for path in advanced_find_syntax_sources(root) if path.name != 'TSColorSupportStub.m']
    for path in [*(root / 'Sources/Find').glob('*.[mh]'), source_file(root, 'TSLayoutManager.m'), source_file(root, 'TSLayoutManager.h'),
                 *syntax, *(root / 'Sources/Syntax').glob('*.h')]:
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


def bracket_problems(themes):
    """The brackets and the marker ($, & and the quantifiers of a pattern) of every bundled theme are readable on its
    background, in the find and replace fields and in the source (contrast as WCAG measures it, at least 3). A theme
    whose source window is translucent (SourceAlpha below 1) is also measured as the window shows it over white and
    over black."""
    def luminance(rgb):
        linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb[:3]]
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]

    def contrast(a, b):
        lighter, darker = sorted([luminance(a), luminance(b)], reverse=True)
        return (lighter + 0.05) / (darker + 0.05)

    problems = []
    for name, theme in themes.items():
        background = theme['EditorBackground'][:3]
        alpha = theme.get('SourceAlpha', [0, 0, 0, 1])[3]
        behind = [None] + ([[1, 1, 1], [0, 0, 0]] if alpha < 1 else [])
        for key in ('SyntaxMarker', 'SyntaxMarkerParen', 'SyntaxMarkerCurly', 'SyntaxMarkerSquare'):
            color = theme.get(key) or theme.get('SyntaxMarker')
            if not color:
                continue
            for desk in behind:
                shown = (lambda c: c[:3]) if desk is None else (lambda c: [alpha * x + (1 - alpha) * d for x, d in zip(c[:3], desk)])
                if contrast(shown(color), shown(background)) < 3:
                    problems.append(f'{name} {key}' + ('' if desk is None else f' over {"white" if desk[0] else "black"}'))
    return problems


def bundled_themes():
    return {f'{folder}/{path.stem}': plistlib.loads(path.read_bytes())
            for folder in ('Resources/TeXShop/Themes', 'Resources/Themes') for path in sorted((root / folder).glob('*.plist'))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true', help='images in all 12 languages, not only English and Japanese')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    check_project()
    problems = bracket_problems(bundled_themes())
    if problems:
        sys.exit(f'FAIL: brackets that cannot be read on the background: {problems}')
    print('PASS: the brackets and the marker of every bundled theme can be read on its background')
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
            themes = bundled_themes()
            for label, theme, key, color in [('Dracula has black parentheses again', 'Dracula', 'SyntaxMarkerParen', [0, 0, 0, 1]),
                                             ('TransparentTheme has its yellow marker again', 'TransparentTheme', 'SyntaxMarker', [1, 0.97, 0.235, 1]),
                                             ('TransparentTheme\'s marker is read only opaque', 'TransparentTheme', 'SyntaxMarker', [0.58, 0.44, 0, 1]),
                                             ('SolarizedLite has its cyan marker again', 'SolarizedLite', 'SyntaxMarker', [0.165, 0.63, 0.596, 1])]:
                mutated = dict(themes)
                path = f'Resources/TeXShop/Themes/{theme}'
                mutated[path] = dict(themes[path], **{key: color})
                if not bracket_problems(mutated):
                    sys.exit(f'FAIL: mutation {label!r} was not detected')
                print(f'PASS: detected mutation {label!r}')
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
