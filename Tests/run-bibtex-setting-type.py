#!/usr/bin/env python3
"""Only text in the BibTeX setting is a command, at typesetting as in Settings > Typesetting.

-stringForKey: turns a number or a Boolean into "17" or "0", which TeXShop would then run as the BibTeX program.
Production statements of the typesetting (Sources/Typesetting/TSDocument-Jobs.m, with -separate:into:) and of
Settings (Sources/Settings/TSSettingsPaneRefresh.inc) run with a suite of the test: a number, a Boolean, an array
and an empty text give bibtex; a command with arguments stays as it is. --mutations checks that the type is looked at."""
import os, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded

root = Path(__file__).resolve().parents[1]
jobs = (root/'Sources/Typesetting/TSDocument-Jobs.m').read_text()
pane = (root/'Sources/Settings/TSSettingsPaneRefresh.inc').read_text()
fragments = []
def span(source, label, first, last):
    start = source.index(first); end = source.index(last, start) + len(last)
    fragment = source[start:end]
    assert source.count(fragment) == 1, first
    fragments.append((label, source, fragment))
    return fragment

separate = production_method(jobs, '- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args')
fragments.append(('complete method separate:into:', jobs, separate))
typesetting = span(jobs, 'typesetting', '                 id bibSetting = [SUD objectForKey:BibTeXengineKey];',
                   'bibtexEngineString = @"bibtex";')
settings = span(pane, 'settings', '    id bibTeXSetting = [defaults objectForKey:BibTeXengineKey];', '        bibTeXengine = @"bibtex";\n    }')

MUTATIONS = {
    'typesetting-stringForKey': ('id bibSetting = [SUD objectForKey:BibTeXengineKey];', 'id bibSetting = [SUD stringForKey:BibTeXengineKey];'),
    'settings-stringForKey': ('id bibTeXSetting = [defaults objectForKey:BibTeXengineKey];', 'id bibTeXSetting = [defaults stringForKey:BibTeXengineKey];'),
}

PROGRAM = r'''
#import <Foundation/Foundation.h>
static NSString *BibTeXengineKey = @"BibTeXengine";
static NSUserDefaults *SUD;
@interface Jobs : NSObject
- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args;
@end
@implementation Jobs
SEPARATE
- (NSString *)typeset:(NSMutableArray *)bibtexArgs
{
    NSString *bibtexEngineString;
    NSArray *args = @[];  // the file name and options TeXShop adds
    if (NO) {
    } else {
TYPESETTING
    return bibtexEngineString;
}
@end
static NSString *Settings(NSUserDefaults *defaults)
{
SETTINGS
    return bibTeXengine;
}
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
int main(void) { @autoreleasepool {
    SUD = [[NSUserDefaults alloc] initWithSuiteName:@"TSBibTeXSettingTest-61842"];
    [SUD removePersistentDomainForName:@"TSBibTeXSettingTest-61842"];
    Jobs *jobs = [Jobs new];
    for (id value in @[@17, @NO, @YES, @[@"biber"], @"", @2.5]) {
        [SUD setObject:value forKey:BibTeXengineKey];
        NSMutableArray *args = [NSMutableArray array];
        NSString *program = [jobs typeset:args];
        Check([program isEqual:@"bibtex"] && args.count == 0, [NSString stringWithFormat:@"typesetting with %@ (%@) runs bibtex, not %@", value, [value class], program]);
        Check([Settings(SUD) isEqual:@"bibtex"], [NSString stringWithFormat:@"Settings with %@ shows bibtex, not %@", value, Settings(SUD)]);
    }
    [SUD setObject:@"upbibtex -kanji=utf8" forKey:BibTeXengineKey];
    NSMutableArray *args = [NSMutableArray array];
    Check([[jobs typeset:args] isEqual:@"upbibtex"] && [args isEqual:@[@"-kanji=utf8"]], @"a command with arguments is kept");
    Check([Settings(SUD) isEqual:@"upbibtex -kanji=utf8"], @"Settings shows the command");
    [SUD removePersistentDomainForName:@"TSBibTeXSettingTest-61842"];
    if (!failures) puts("PASS: only text in the BibTeX setting is a command");
    return failures ? 1 : 0;
} }
'''

def run(program):
    with tempfile.TemporaryDirectory(prefix='texshop-bibtex-setting-') as temp:
        t = Path(temp)
        (t/'probe.m').write_text(program)
        build = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Foundation', str(t/'probe.m'), '-o', str(t/'probe')],
                               capture_output=True, text=True)
        if build.returncode:
            return 2, build.stderr
        home = t/'Home'; (home/'Library/Preferences').mkdir(parents=True)
        result = subprocess.run([str(t/'probe')], capture_output=True, text=True, timeout=60,
                                env={**os.environ, 'HOME': str(home), 'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(t)})
        return result.returncode, result.stdout + result.stderr

program = PROGRAM.replace('SEPARATE', separate).replace('TYPESETTING', typesetting).replace('SETTINGS', settings)
verify_embedded(program, fragments)
if '--mutations' in sys.argv:
    for name, (old, new) in MUTATIONS.items():
        if old not in program:
            raise SystemExit(f'FAIL: mutation {name} does not apply')
        code, output = run(program.replace(old, new, 1))
        if code != 1:
            raise SystemExit(f'FAIL: mutation {name} was not detected')
        print('detected mutation', name)
code, output = run(program)
print(output.strip())
raise SystemExit(code)
