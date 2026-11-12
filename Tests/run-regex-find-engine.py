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
    'ICU drops line feeds': ("TSRegexReplacementTemplate.m", "n == 'n' ? @\"\\n\" : ", ''),
    'ICU keeps a lone backslash': ('TSRegexReplacementTemplate.m', '            if (i + 1 >= length) // A lone backslash at the end stands for nothing, as in NSRegularExpression.\n                break;\n', '            if (i + 1 >= length) { [text appendString:@"\\\\"]; break; }\n'),
    'the syntax is ignored': ('TSRegexReplacementTemplate.m', 'syntax == TSRegexReplacementSyntaxOgreKit ?', 'NO ?'),
    'rules use one syntax': ('TSRegexMultipleReplace.m', 'syntax:rule.replacementSyntax]', 'syntax:TSRegexReplacementSyntaxOgreKit]'),
    'missing syntax reads as OgreKit': ('TSRegexReplacementRule.m', ': TSRegexReplacementSyntaxICU\n                            enabled:', ': TSRegexReplacementSyntaxOgreKit\n                            enabled:'),
    'named groups are ignored': ('TSRegexReplacementTemplate.m', 'if (result && [self.groupNames containsObject:token.text])', 'if (NO)'),
    'whole words are not checked': ('TSRegexFindPattern.m', 'if (wholeWord && ![self isWholeWord:found inString:string]) {', 'if (NO) {'),
    'empty matches are kept': ('TSRegexFindPattern.m', 'if (ignoresEmpty && result.range.length == 0)', 'if (NO)'),
    'search does not wrap': ('TSRegexTextFind.m', '    if (!wraps)\n', '    if (YES)\n'),
    'scope offsets are dropped': ('TSRegexTextFind.m', 'offset += (NSInteger)scopeText.length - (NSInteger)scope.length;', ';'),
    'rules see the original text': ('TSRegexMultipleReplace.m', '            current = next;', '            (void)next;'),
    'disabled rules run': ('TSRegexMultipleReplace.m', '        if (!rule.enabled)\n            continue;', '        if (NO)\n            continue;'),
    'anchoring bounds are used': ('TSRegexFindPattern.m', 'NSMatchingWithTransparentBounds | NSMatchingWithoutAnchoringBounds', 'NSMatchingWithoutAnchoringBounds'),
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


parser = argparse.ArgumentParser()
parser.add_argument('--mutations', action='store_true')
args = parser.parse_args()
engine = ['TSRegexFindOptions', 'TSRegexFindPattern', 'TSRegexReplacementTemplate', 'TSRegexFindReplacement', 'TSRegexReplaceAllResult', 'TSRegexTextFind', 'TSRegexReplacementRule', 'TSRegexMultipleReplace']
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
