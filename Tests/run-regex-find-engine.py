#!/usr/bin/env python3
"""The engine of the Advanced Find panel (Sources/Find), compiled and run on its own, and its OgreKit
replacement syntax compared with OgreKit itself (Frameworks/OgreKit.framework); nothing is displayed.

--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
find_dir = root / 'Sources/Find'
frameworks = root / 'Frameworks'

MUTATIONS = {
    'yen signs are kept': ('TSRegexFindPattern.m', 'if (!(options & TSRegexFindYenIsBackslash) ||', 'if (YES ||'),
    'escaped digits are text': ('TSRegexReplacementTemplate.m', 'if (TSIsDigit(n)) {', 'if (NO) {'),
    'OgreKit text before the match is dropped': ('TSRegexReplacementTemplate.m', '                [output appendString:[string substringToIndex:matchRange.location]];\n', ''),
    'OgreKit surrogate escapes are joined': ('TSRegexReplacementTemplate.m', 'if (value <= 0xFFFF) //', 'if (value <= 0xD7FF) //'),
    'ICU reads one digit only': ('TSRegexReplacementTemplate.m', '            for (NSUInteger n = groups; n >= 10; n /= 10)\n                maxDigits++;\n', ''),
    'ICU reads every digit': ('TSRegexReplacementTemplate.m', 'digits < maxDigits && ', ''),
    'ICU keeps a lone backslash': ('TSRegexReplacementTemplate.m', '            if (i + 1 >= length) // A lone backslash at the end stands for nothing, as in NSRegularExpression.\n                break;\n', '            if (i + 1 >= length) { [text appendString:@"\\\\"]; break; }\n'),
    'the syntax is ignored': ('TSRegexReplacementTemplate.m', 'syntax == TSRegexReplacementSyntaxOgreKit ?', 'NO ?'),
    'named groups are ignored': ('TSRegexReplacementTemplate.m', 'if (result && [self.groupNames containsObject:token.text])', 'if (NO)'),
    'whole words are not checked': ('TSRegexFindPattern.m', 'if (wholeWord && ![self isWholeWord:found inString:string]) {', 'if (NO) {'),
    'empty matches are kept': ('TSRegexFindPattern.m', 'if (ignoresEmpty && result.range.length == 0)', 'if (NO)'),
    'search does not wrap': ('TSRegexTextFind.m', '    if (!wraps)\n', '    if (YES)\n'),
    'scope offsets are dropped': ('TSRegexTextFind.m', 'offset += (NSInteger)scopeText.length - (NSInteger)scope.length;', ';'),
    'rules see the original text': ('TSRegexMultipleReplace.m', '            current = next;', '            (void)next;'),
    'disabled rules run': ('TSRegexMultipleReplace.m', '            return nil;\n        if (!rule.enabled) {\n', '            return nil;\n        if (NO) {\n'),
    'anchoring bounds are used': ('TSRegexFindPattern.m', 'NSMatchingWithTransparentBounds | NSMatchingWithoutAnchoringBounds', 'NSMatchingWithoutAnchoringBounds'),
    'ICU surrogates are single units': ('TSRegexReplacementTemplate.m', '            NSUInteger size = MIN((NSUInteger)2, length - i);\n', '            NSUInteger size = 1;\n'),
    'ICU escapes take a whole character': ('TSRegexReplacementTemplate.m', '            [text appendString:[s substringWithRange:NSMakeRange(i + 1, 1)]];\n            i += 2;\n', '            NSRange whole = [s rangeOfComposedCharacterSequenceAtIndex:i + 1];\n            [text appendString:[s substringWithRange:whole]];\n            i = NSMaxRange(whole);\n'),
    'unescaping drops line feeds': ('TSRegexReplacementTemplate.m', "n == 'n' ? '\\n' : ", ''),
    'unescaping keeps \\0': ('TSRegexReplacementTemplate.m', "n == '0' ? 0 :", "n == '0' ? '0' :"),
    'unescaping halves backslashes': ('TSRegexReplacementTemplate.m', '            [result appendString:@"\\\\\\\\"];\n', '            [result appendString:@"\\\\"];\n'),
    'unescaping is always on': ('TSRegexReplacementTemplate.m', '(pattern.options & TSRegexFindUnescapesReplacement) ?', 'YES ?'),
    'whole words need a boundary before a non-word edge': ('TSRegexFindPattern.m', '\\\\A(?:(?=\\\\W)|\\\\b)(?>', '\\\\A\\\\b(?>'),
    'whole words need a boundary after a non-word edge': ('TSRegexFindPattern.m', '(?:\\\\b|(?<=\\\\W))\\\\z', '\\\\b\\\\z'),
    'replacements keep their line endings': ('TSRegexTextFind.m', 'return lineEnding ? TSRegexStringByReplacingLineEndings(text, (NSString *_Nonnull)lineEnding) : text;', 'return text;'),
    'rule find strings keep their line endings': ('TSRegexMultipleReplace.m', 'NSString *findString = lineEnding ? TSRegexStringByReplacingLineEndings(rule.findString, (NSString *_Nonnull)lineEnding) : rule.findString;', 'NSString *findString = rule.findString;'),
    'the set\'s syntax is ignored': ('TSRegexMultipleReplace.m', 'syntax:self.replacementSyntax]', 'syntax:TSRegexReplacementSyntaxICU]'),
    'a rule\'s case option is ignored': ('TSRegexMultipleReplace.m', 'return rule.ignoresCase ? options | TSRegexFindIgnoreCase : options;', 'return options;'),
    'rules take the other kind of options': ('TSRegexMultipleReplace.m', 'rule.usesRegularExpression ? self.regularExpressionOptions | TSRegexFindRegularExpression : self.textualOptions', 'rule.usesRegularExpression ? self.textualOptions | TSRegexFindRegularExpression : self.regularExpressionOptions'),
    'a missing unescape value reads as on': ('TSRegexMultipleReplace.m', 'if ([unescapes boolValue]) regularExpressionOptions', 'if (!unescapes || [unescapes boolValue]) regularExpressionOptions'),
    'booleans are written as numbers': ('TSRegexMultipleReplace.m', 'TSSettingsWholeWordKey: (textual & TSRegexFindWholeWord) ? @YES : @NO,', 'TSSettingsWholeWordKey: @((textual & TSRegexFindWholeWord) != 0),'),
    'numbers are read as booleans': ('TSRegexReplacementRule.m', 'return CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();', 'return [value isKindOfClass:[NSNumber class]];'),
    'tab-separated lines without a tab are read': ('TSRegexMultipleReplace.m', 'if (items.count < 2 || items[0].length == 0)', 'if (items[0].length == 0)'),
    'literal patterns are regular expressions': ('TSRegexFindPattern.m', '    if (options & TSRegexFindIgnoreMetacharacters) result |= NSRegularExpressionIgnoreMetacharacters;\n', ''),
    'Unix line separators are ignored': ('TSRegexFindPattern.m', '    if (options & TSRegexFindUseUnixLineSeparators) result |= NSRegularExpressionUseUnixLineSeparators;\n', ''),
    'literal patterns list group names': ('TSRegexFindPattern.m', '(options & TSRegexFindIgnoreMetacharacters) ? @[] :', 'NO ? @[] :'),
    'a file\'s literal option is dropped': ('TSRegexMultipleReplace.m', '    if (regexOptions & NSRegularExpressionIgnoreMetacharacters) regularExpressionOptions |= TSRegexFindIgnoreMetacharacters;\n', ''),
    'a file\'s Unix option is not written': ('TSRegexMultipleReplace.m', '    if (regex & TSRegexFindUseUnixLineSeparators) regexOptions |= NSRegularExpressionUseUnixLineSeparators;\n', ''),
    'the upper limit is not checked': ('TSRegexMultipleReplace.m', 'd >= 0 && d < 0x1p64 && d == floor(d)', 'd >= 0 && d == floor(d)'),
    'fractions are accepted': ('TSRegexMultipleReplace.m', ' && d == floor(d)))', '))'),
    'negative numbers are accepted': ('TSRegexMultipleReplace.m', 'if (!(d >= 0 && ', 'if (!(d > -2 && '),
    'large numbers are read as doubles': ('TSRegexMultipleReplace.m', 'if (d < 0x1p53) {', 'if (d < 0x1p64) {'),
    'large digits are not limited to 64 bits': ('TSRegexMultipleReplace.m', ' || negative || mantissa > UINT64_MAX)', ' || negative)'),
    'large fractions are rounded': ('TSRegexMultipleReplace.m', '        value /= 10;\n', '        value = (value + 5) / 10;\n'),
    'trailing zeros are kept': ('TSRegexMultipleReplace.m', 'while (m % 10 == 0) {', 'while (NO && m % 10 == 0) {'),
    'digits beyond 128 bits are refused': ('TSRegexMultipleReplace.m', '                tooBig = YES;\n                continue;\n', '                return NO;\n'),
    'the last of duplicate keys is used': ('TSRegexMultipleReplace.m', '        if (!members[key])\n', '        if (YES)\n'),
    'escaped keys are not decoded': ('TSRegexMultipleReplace.m', '[keyText rangeOfString:@"\\\\"].location == NSNotFound\n', 'YES\n'),
    'numbers are read from NSJSONSerialization': ('TSRegexMultipleReplace.m', 'return TSUnsignedValueOfNumberText((NSString *_Nonnull)text, result);', 'return TSUnsignedValueOfNumberText([value stringValue], result);'),
    'other encodings are read as UTF-8': ('TSRegexMultipleReplace.m', 'initWithData:data encoding:TSJSONEncodingOfData(data).encoding];', 'initWithData:data encoding:NSUTF8StringEncoding];'),
    'numbers reach NSJSONSerialization as they are': ('TSRegexMultipleReplace.m', 'JSONObjectWithData:TSJSONDataWithPlainNumbers(data) options:0', 'JSONObjectWithData:data options:0'),
    'numbers in strings are replaced': ('TSRegexMultipleReplace.m', '        } else if (c == \'"\') {\n            inString = YES;\n', '        } else if (NO) {\n'),
    'escaped quotes end strings': ('TSRegexMultipleReplace.m', "            if (c == '\\\\')\n                i++;\n            else if", "            if"),
    'only the first character of a number is replaced': ('TSRegexMultipleReplace.m', '            while (i + 1 < count && TSIsJSONNumberCharacter', '            while (NO && TSIsJSONNumberCharacter'),
    'plus signs end a number': ('TSRegexMultipleReplace.m', "c == '.' || c == '+' || c == '-'", "c == '.' || c == '-'"),
    'numbers are replaced byte by byte': ('TSRegexMultipleReplace.m', '    TSJSONEncoding encoding = TSJSONEncodingOfData(data);\n    NSMutableData *plain', '    TSJSONEncoding encoding = {NSUTF8StringEncoding, 1, NO};\n    NSMutableData *plain'),
    'big-endian units are read little-endian': ('TSRegexMultipleReplace.m', 'unit[encoding.bigEndian ? i : encoding.width - 1 - i]', 'unit[NO ? i : encoding.width - 1 - i]'),
    'big-endian units are written little-endian': ('TSRegexMultipleReplace.m', 'unit[encoding.bigEndian ? encoding.width - 1 : 0] = character;', 'unit[0] = character;'),
    'leading zeros are accepted': ('TSRegexMultipleReplace.m', "    if (*digits == '0' && digits[1] && ", "    if (NO && "),
    'a minus sign needs no digit': ('TSRegexMultipleReplace.m', "    if (!(*digits >= '0' && *digits <= '9'))\n        return NO;\n", ""),
    'an exponent may follow a point': ('TSRegexMultipleReplace.m', "    if (e && !(e[-1] >= '0' && e[-1] <= '9'))", "    if (NO)"),
    'a number may end in a non-digit': ('TSRegexMultipleReplace.m', "    return last >= '0' && last <= '9';", "    return last || YES;"),
    'the double need not read all of the text': ('TSRegexMultipleReplace.m', '    if (!*end) {', '    if (YES) {'),
    'the Decimal need not read all of the text': ('TSRegexMultipleReplace.m', '    if (*s)\n        return NO;\n    if (m != 0) {', '    if (m != 0) {'),
    'replace all does not end with 1': ('TSRegexTextFind.m', '    if (progress)\n        progress(1.0, total);\n', ''),
    'replace all reports every match': ('TSRegexTextFind.m', 'if ((total + count) % 256 == 0)', 'if ((total + count) % 1 == 0)'),
    'replace all counts the scope range only': ('TSRegexTextFind.m', 'report(searched + (location - scope.location), total + count);', 'report(searched + (location - scope.location), count);'),
    'replace all measures the scope range only': ('TSRegexTextFind.m', 'report(searched + (location - scope.location), total + count);', 'report(location - scope.location, total + count);'),
    'the end of a scope range is not reported': ('TSRegexTextFind.m', '        if (scopeValue != self.scopeRanges.lastObject)\n            report(searched, total);\n', ''),
    'a cancelled scope range is reported': ('TSRegexTextFind.m', '        if (cancellation && cancellation())\n            return nil;\n        [scopeText appendString:', '        [scopeText appendString:'),
    'a disabled rule is not reported': ('TSRegexMultipleReplace.m', '        if (!rule.enabled) {\n            ruleDone(index);\n', '        if (!rule.enabled) {\n'),
    'an unusable rule is not reported': ('TSRegexMultipleReplace.m', '            errors[@(index)] = error;\n            ruleDone(index);\n', '            errors[@(index)] = error;\n'),
    'a rule reports the next index': ('TSRegexMultipleReplace.m', '            progress(index, ruleCount, fraction);', '            progress(index + 1, ruleCount, fraction);'),
    'line feeds are kept for any line ending': ('TSRegexTextFind.m', " || (c == '\\n' && !keepsLineFeeds)", ''),
    'line separators are kept': ('TSRegexTextFind.m', ' || c == 0x2028', ''),
    'look-alikes in the text are ignored': ('TSRegexFindPattern.m', '[quick addObject:(word->_others || word->_astralOthers || word->_hasDigit) && ', '[quick addObject:NO && '),
    'look-alikes outside the BMP are ignored': ('TSRegexFindPattern.m', 'quick->_astralOthers = astral.count ? astral : nil;', 'quick->_astralOthers = nil;'),
    'literal matches are not checked': ('TSRegexFindPattern.m', 'NSRange found = [string rangeOfString:word options:NSAnchoredSearch range:NSMakeRange(at, limit - at)];', 'NSRange found = NSMakeRange(at, quick->_length);'),
    'quick words may hold any character': ('TSRegexFindPattern.m', '        if (!TSIsQuickCharacter(u[i]))\n            return nil;\n', ''),
    'decomposable words are quick': ('TSRegexFindPattern.m', "    if (length == 0 || [word rangeOfCharacterFromSet:NSCharacterSet.nonBaseCharacterSet].location != NSNotFound\n        || [word.decomposedStringWithCanonicalMapping compare:word options:NSLiteralSearch] != NSOrderedSame)", "    if (length == 0 || [word rangeOfCharacterFromSet:NSCharacterSet.nonBaseCharacterSet].location != NSNotFound)"),
    'the skip goes one too far': ('TSRegexFindPattern.m', 'quick->_skip[u[i] & 0xFF] = (uint32_t)(length - 1 - i);', 'quick->_skip[u[i] & 0xFF] = (uint32_t)(length - i);'),
    'the character before a match is not checked': ('TSRegexFindPattern.m', 'if (at > 0 && !TSIsQuickCharacter(', 'if (NO && !TSIsQuickCharacter('),
    'soft hyphens are quick': ('TSRegexFindPattern.m', ' && c != 0xAD)', ')'),
    'controls are quick': ('TSRegexFindPattern.m', "return (c == '\\t' || c == '\\n' || (c >= 0x20 && c < 0x7F) || (c >= 0xA0 && c < 0x0300 && c != 0xAD)", "return ((c < 0x0300 && c != '\\r')"),
    'replace all forgets a cancellation': ('TSRegexTextFind.m', '    BOOL (^cancellation)(void) = isCancelled ? ^BOOL { return cancelled || (cancelled = isCancelled()); } : nil;\n    NSString *string = self.string;', '    BOOL (^cancellation)(void) = isCancelled;\n    NSString *string = self.string;'),
    'find all forgets a cancellation': ('TSRegexTextFind.m', '    BOOL (^cancellation)(void) = isCancelled ? ^BOOL { return cancelled || (cancelled = isCancelled()); } : nil;\n    NSMutableArray<NSValue *> *matches', '    BOOL (^cancellation)(void) = isCancelled;\n    NSMutableArray<NSValue *> *matches'),
    'rules are not asked about': ('TSRegexMultipleReplace.m', '        if (cancellation && cancellation())\n            return nil;\n        if (!rule.enabled) {\n', '        if (!rule.enabled) {\n'),
    'highlight rules are not asked about': ('TSRegexMultipleReplace.m', '        if (cancellation && cancellation())\n            return nil;\n        if (!rule.enabled)\n            continue;\n', '        if (!rule.enabled)\n            continue;\n'),
    'other numbers beside digits are ignored': ('TSRegexFindPattern.m', "    quick->_hasDigit = [own intersectsIndexesInRange:NSMakeRange('0', 10)];", "    quick->_hasDigit = NO;"),
    'numbers outside the BMP are ignored': ('TSRegexFindPattern.m', '[astralNumbers containsObject:scalar]', 'NO'),
    'other numbers are quick': ('TSRegexFindPattern.m', '        && ![TSNumbersButASCIIDigits() characterIsMember:c];', ';'),
    'equal lengths are taken as no change': ('TSRegexTextFind.m', '(scopeText.length != scope.length || [scopeText compare:[string substringWithRange:scope] options:NSLiteralSearch] != NSOrderedSame)', 'scopeText.length != scope.length'),
}


def run(sources: Path, tmp: Path, strict: bool = True) -> subprocess.CompletedProcess:
    """Runs the engine test, then compares the OgreKit syntax with OgreKit itself (Frameworks/OgreKit.framework)."""
    # A mutation may leave a variable unused, so only the real sources are compiled with -Werror.
    warnings = ['-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter'] if strict else ['-w']
    engine_sources = list(map(str, sorted(sources.glob('*.m'))))
    exe = tmp / 'regex-find-engine'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', *warnings, '-framework', 'Foundation', '-I', str(sources),
                    str(root / 'Tests/RegexFindEngine.m'), *engine_sources, '-o', str(exe)], check=True)
    first = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
    if first.returncode:
        return first
    ogre = tmp / 'regex-find-ogrekit'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', *warnings, '-F', str(frameworks), '-framework', 'OgreKit', '-framework', 'Foundation',
                    '-I', str(sources), str(root / 'Tests/RegexFindOgreKitReplacement.m'), *engine_sources, '-o', str(ogre)], check=True)
    second = subprocess.run([str(ogre)], capture_output=True, text=True, timeout=300, env=dict(os.environ, DYLD_FRAMEWORK_PATH=str(frameworks)))
    return subprocess.CompletedProcess(second.args, second.returncode, first.stdout + second.stdout, second.stderr)


def check_message_tables():
    """Every message of the engine is in AdvancedFindEngine.strings of every language, and nothing else is."""
    import json, re
    keys = set()
    for path in find_dir.glob('*.m'):
        # As the compiler reads them: \\ is one backslash.
        keys |= {re.sub(r'\\(.)', r'\1', k) for k in re.findall(r'NSLocalizedStringFromTable\(@"((?:[^"\\]|\\.)*)", @"AdvancedFindEngine"', path.read_text(encoding='utf-8'))}
    problems = []
    for table in sorted((root / 'Resources/Interfaces').glob('*.lproj/AdvancedFindEngine.strings')):
        data = json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(table)], capture_output=True, check=True).stdout)
        if set(data) != keys:
            problems.append(f'{table.parent.name}: missing {sorted(keys - set(data))}, extra {sorted(set(data) - keys)}')
        if table.parent.name != 'en.lproj':
            problems += [f'{table.parent.name}: untranslated {k!r}' for k, v in data.items() if v == k]
    languages = {p.name for p in (root / 'Resources/Interfaces').glob('*.lproj')} - {'Base.lproj'}
    found = {p.parent.name for p in (root / 'Resources/Interfaces').glob('*.lproj/AdvancedFindEngine.strings')}
    problems += [f'{name}: no AdvancedFindEngine.strings' for name in sorted(languages - found)]
    if len(keys) < 5 or problems:
        sys.exit('FAIL message tables: ' + '; '.join(problems or ['messages not found in the sources']))
    print(f'PASS: the {len(keys)} messages of the engine are translated in {len(found)} languages')


parser = argparse.ArgumentParser()
parser.add_argument('--mutations', action='store_true')
args = parser.parse_args()
engine = ['TSRegexFindOptions', 'TSRegexFindPattern', 'TSRegexReplacementTemplate', 'TSRegexFindReplacement', 'TSRegexReplaceAllResult', 'TSRegexTextFind', 'TSRegexReplacementRule', 'TSRegexMultipleReplace']
check_message_tables()
with tempfile.TemporaryDirectory(prefix='texshop-regex-find-') as tmp:
    tmp = Path(tmp)
    sources = tmp / 'src'
    sources.mkdir()
    for name in engine:
        for ext in ('.h', '.m'):
            shutil.copy(find_dir / (name + ext), sources)
    result = run(sources, tmp)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit(result.stderr or 'FAIL')
    if args.mutations:
        for label, (name, old, new) in MUTATIONS.items():
            original = (find_dir / name).read_text()
            assert original.count(old) == 1, (label, old)
            (sources / name).write_text(original.replace(old, new))
            mutated = run(sources, tmp, strict=False)
            (sources / name).write_text(original)
            if mutated.returncode == 0:
                sys.exit(f'MUTATION SURVIVED: {label}')
            print(f'PASS: mutation caught: {label}')
