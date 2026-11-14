#!/usr/bin/env python3
"""Engine profiles: the table of keys each one writes, the profile the settings match, whether latexmk runs,
the language-based first-launch choice, and an apply that writes only the profile's keys. Each production rule is
then removed in turn, and the probe must notice."""
from pathlib import Path
import json, subprocess, sys, tempfile
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]
FACTORY = R / 'Resources/Defaults/FactoryDefaults.plist'
PDF = '--file-line-error --synctex=1'
SIMP = '--extratexopts "-file-line-error -synctex=1"'
PT = '-ot "-synctex=1 -file-line-error"'
DVIPDF = '-e "$dvipdf=q/dvipdfmx %O -o %D %S/"'
# The expected table, written out independently of the source: place, LaTeX, TeX, LaTeX with latexmk, BibTeX.
TABLE = {
    1: (100, 'pdflatex ' + PDF, 'pdftex ' + PDF, 'latexmk -pdf -e "$pdflatex=q/pdflatex -synctex=1 -file-line-error/" -norc', 'bibtex'),
    2: (100, 'xelatex ' + PDF, 'xetex ' + PDF, 'latexmk -xelatex -e "$xelatex=q/xelatex -synctex=1 -file-line-error/" -norc', 'bibtex'),
    3: (100, 'lualatex ' + PDF, 'luatex ' + PDF, 'latexmk -lualatex -e "$lualatex=q/lualatex -synctex=1 -file-line-error/" -norc', 'bibtex'),
    4: (101, 'simpdftex latex --mode dvipdfmx ' + SIMP, 'simpdftex etex --mode dvipdfmx ' + SIMP,
        'latexmk -pdfdvi -e "$latex=q/latex -synctex=1 -file-line-error/" ' + DVIPDF + ' -norc', 'bibtex'),
    5: (100, 'lualatex ' + PDF, 'luatex ' + PDF,
        'latexmk -lualatex -e "$lualatex=q/lualatex -synctex=1 -file-line-error/" -e "$bibtex=q/upbibtex/" -e "$makeindex=q/upmendex/" -norc', 'upbibtex'),
    6: (101, 'ptex2pdf -l ' + PT, 'ptex2pdf -e ' + PT,
        'latexmk -pdfdvi -e "$latex=q/platex -synctex=1 -file-line-error/" -e "$bibtex=q/pbibtex/" -e "$makeindex=q/mendex/" ' + DVIPDF + ' -norc', 'pbibtex'),
    7: (101, 'ptex2pdf -u -l ' + PT, 'ptex2pdf -e -u ' + PT,
        'latexmk -pdfdvi -e "$latex=q/uplatex -synctex=1 -file-line-error/" -e "$bibtex=q/upbibtex/" -e "$makeindex=q/mendex/" ' + DVIPDF + ' -norc', 'upbibtex'),
    8: (101, 'simpdftex latex --maxpfb ' + SIMP, 'simpdftex etex --maxpfb ' + SIMP,
        'latexmk -pdfps -e "$latex=q/latex -synctex=1 -file-line-error/" -norc', 'bibtex'),
}
JAPANESE = {5, 6, 7}


def expected(profile, latexmk):
    place, latex, tex, mk, bib = TABLE[profile]
    direct = place == 100
    values = {'DefaultScript': place, 'LatexCommand' if direct else 'LatexGSCommand': mk if latexmk else latex,
              'TexCommand' if direct else 'TexGSCommand': tex, 'BibTeXengine': bib, 'ptexUtfOutput': profile == 6}
    if profile in JAPANESE:
        values.update({'Encoding': 'UTF-8 Unicode', 'AutomaticUTF8MACtoUTF8Conversion': True, 'SpellingAutomaticDefault': True, 'SpellingLanguageDefault': ' '})
    return values


EXPECTED = {f'{p}.{int(mk)}': expected(p, mk) for p in TABLE for mk in (False, True)}

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TSPreferenceProfile.h"
static int failures;
static void check(BOOL ok, NSString *why) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", why.UTF8String); } }
static BOOL semantic(id stored, id value) {
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return [stored boolValue] == [value boolValue];
    return [stored isEqual:value];
}
static BOOL same(id a, id b) {
    if ([a isKindOfClass:NSNumber.class] && [b isKindOfClass:NSNumber.class]) return [a isEqualToNumber:b];
    return [a isEqual:b];
}
int main(int argc, char **argv) { @autoreleasepool {
    NSDictionary *table = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
    NSDictionary *factory = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
    // 1. The table: exactly the expected keys and values for every profile and form.
    NSMutableSet *seen = [NSMutableSet set];
    for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections()) for (NSNumber *p in section) {
        check(![seen containsObject:p], @"each profile appears once in the menu"); [seen addObject:p];
        check(TSEngineProfileTitle(p.integerValue).length > 0, @"each profile has a title");
        for (NSNumber *mk in @[@NO, @YES]) {
            NSDictionary *want = table[[NSString stringWithFormat:@"%@.%d", p, mk.intValue]];
            NSDictionary *got = TSEngineProfileValues(p.integerValue, mk.boolValue);
            check([[NSSet setWithArray:got.allKeys] isEqualToSet:[NSSet setWithArray:want.allKeys]],
                  [NSString stringWithFormat:@"profile %@ latexmk %@ writes exactly its keys: %@", p, mk, got.allKeys]);
            for (NSString *key in want) check(same(got[key], want[key]), [NSString stringWithFormat:@"profile %@ latexmk %@ value of %@: %@", p, mk, key, got[key]]);
        }
    }
    check(seen.count == 8, @"eight profiles");
    check([TSEngineProfileMenuSections().lastObject isEqual:@[@8]], @"the dvips profile alone is under Other");
    check(TSEngineProfileValues(0, NO).count == 0 && TSEngineProfileValues(9, YES).count == 0 && TSEngineProfileTitle(9) == nil, @"unknown profiles write nothing");
    // 2. Matching: each profile and form matches itself, on top of other settings.
    for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections()) for (NSNumber *p in section) for (NSNumber *mk in @[@NO, @YES]) {
        TSMemoryDefaults *d = [TSMemoryDefaults new]; [d registerDefaults:factory];
        [d.values addEntriesFromDictionary:TSEngineProfileValues(p.integerValue, mk.boolValue)];
        BOOL latexmk = !mk.boolValue;
        check(TSEngineProfileMatchingSettings(d, &latexmk) == p.integerValue && latexmk == mk.boolValue,
              [NSString stringWithFormat:@"profile %@ latexmk %@ is recognized", p, mk]);
        // The settings that go with a profile do not decide.
        d.values[@"SpellingAutomaticDefault"] = @NO; d.values[@"ptexUtfOutput"] = @(p.integerValue != 6);
        check(TSEngineProfileMatchingSettings(d, NULL) == p.integerValue, @"companion settings do not change the match");
        // A command typed by hand, or another BibTeX engine, is Custom.
        NSString *key = [TSEngineProfileValues(p.integerValue, mk.boolValue)[@"DefaultScript"] integerValue] == 100 ? @"LatexCommand" : @"LatexGSCommand";
        d.values[key] = [d.values[key] stringByAppendingString:@" --shell-escape"];
        check(TSEngineProfileMatchingSettings(d, NULL) == 0, [NSString stringWithFormat:@"edited command of %@ is Custom", p]);
        d.values[key] = TSEngineProfileValues(p.integerValue, mk.boolValue)[key];
        d.values[@"BibTeXengine"] = @"biber";
        check(TSEngineProfileMatchingSettings(d, NULL) == 0, [NSString stringWithFormat:@"another BibTeX engine with %@ is Custom", p]);
        d.values[@"BibTeXengine"] = TSEngineProfileValues(p.integerValue, mk.boolValue)[@"BibTeXengine"];
        d.values[@"DefaultScript"] = @102;
        check(TSEngineProfileMatchingSettings(d, NULL) == 0, @"the personal script is Custom");
    }
    TSMemoryDefaults *fresh = [TSMemoryDefaults new]; [fresh registerDefaults:factory];
    BOOL mk = YES;
    check(TSEngineProfileMatchingSettings(fresh, &mk) == 1 && !mk, @"factory settings are pdfLaTeX");
    // Settings of the earlier upTeX (ptex2pdf) profile.
    TSMemoryDefaults *upTeX = [TSMemoryDefaults new]; [upTeX registerDefaults:factory];
    [upTeX.values addEntriesFromDictionary:@{@"DefaultScript": @101, @"LatexGSCommand": @"ptex2pdf -u -l -ot \"-synctex=1 -file-line-error\"",
        @"TexGSCommand": @"ptex2pdf -e -u -ot \"-synctex=1 -file-line-error\"", @"BibTeXengine": @"upbibtex",
        @"LatexCommand": @"lualatex --file-line-error --synctex=1", @"TexCommand": @"luatex --file-line-error --synctex=1"}];
    check(TSEngineProfileMatchingSettings(upTeX, NULL) == 7, @"the earlier upTeX (ptex2pdf) settings are upLaTeX + dvipdfmx");
    upTeX.values[@"LatexGSCommand"] = @"  ptex2pdf -u -l -ot \"-synctex=1 -file-line-error\"\n";
    check(TSEngineProfileMatchingSettings(upTeX, NULL) == 7, @"surrounding blanks do not decide");
    // 3. Apply: only the profile's keys, one deferred notification, and the keys that changed.
    TSMemoryDefaults *d = [TSMemoryDefaults new]; [d registerDefaults:factory];
    d.values[@"FindMethod"] = @0; d.values[@"Encoding"] = @"DOSJapanese"; d.values[@"LatexCommand"] = @"mine";
    d.values[@"ConvertToYen"] = @NO; d.values[@"SpellingLanguageDefault"] = @"en";
    NSDictionary *before = [d.values copy];
    __block NSUInteger notes = 0; __block BOOL deferred = NO;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:d queue:nil
        usingBlock:^(NSNotification *n) { notes++; deferred = !TSPreferenceProfileIsApplying(); }];
    NSDictionary *values = TSEngineProfileValues(7, NO);
    NSMutableSet *want = [NSMutableSet set];
    for (NSString *key in values) if (!semantic([d objectForKey:key], values[key])) [want addObject:key];
    check(want.count >= 5 && ![want containsObject:@"ptexUtfOutput"], [NSString stringWithFormat:@"the factory already has some of the values: %@", want]);
    NSSet *changed = TSEngineProfileApply(d, values);
    [NSNotificationCenter.defaultCenter removeObserver:token];
    check(notes == 1 && deferred, @"one notification, after every key is stored");
    check(!TSPreferenceProfileIsApplying(), @"applying ends");
    for (NSString *key in values) check(same(d.values[key], values[key]), [NSString stringWithFormat:@"applied %@", key]);
    for (NSString *key in before) if (values[key] == nil) check([d.values[key] isEqual:before[key]], [NSString stringWithFormat:@"untouched %@", key]);
    NSMutableSet *written = [NSMutableSet setWithArray:before.allKeys]; [written addObjectsFromArray:values.allKeys];
    check(d.values.count == written.count && [d.values[@"Encoding"] isEqual:@"UTF-8 Unicode"], @"no other key is written; a Japanese profile sets UTF-8");
    check([d.values[@"LatexCommand"] isEqual:@"mine"], @"the other place keeps the user's command");
    check([changed isEqualToSet:want], [NSString stringWithFormat:@"changed keys: %@", changed]);
    check(TSEngineProfileApply(d, values).count == 0, @"applying again changes nothing");
    // 4b. Whether latexmk runs now, for a profile and for commands typed by hand.
    TSMemoryDefaults *typed = [TSMemoryDefaults new]; [typed registerDefaults:factory];
    check(!TSEngineProfileSettingsUseLatexmk(typed), @"factory settings run the engine once");
    [typed.values addEntriesFromDictionary:TSEngineProfileValues(6, YES)];
    check(TSEngineProfileSettingsUseLatexmk(typed), @"a latexmk profile runs latexmk");
    typed.values[@"LatexGSCommand"] = @" latexmk -pdfdvi mine";
    check(TSEngineProfileMatchingSettings(typed, NULL) == 0 && TSEngineProfileSettingsUseLatexmk(typed), @"a latexmk command typed by hand runs latexmk");
    typed.values[@"LatexGSCommand"] = @"latexmkfoo"; check(!TSEngineProfileSettingsUseLatexmk(typed), @"only the program latexmk counts");
    typed.values[@"DefaultScript"] = @100; typed.values[@"LatexCommand"] = @"latexmk"; check(TSEngineProfileSettingsUseLatexmk(typed), @"the command of the default method decides");
    // 5. The first-launch choice.
    check(TSEngineProfileForLanguages(@[@"ja-JP", @"en"]) == 7 && TSEngineProfileForLanguages(@[@"ja"]) == 7, @"Japanese first: upLaTeX + dvipdfmx");
    check(TSEngineProfileForLanguages(@[@"en-JP", @"ja"]) == 1 && TSEngineProfileForLanguages(@[]) == 1 && TSEngineProfileForLanguages(@[@"jv"]) == 1, @"otherwise pdfLaTeX");
    // 6. The factory engine file became LuaLaTeX in 6.00; an earlier choice of the factory one keeps XeLaTeX.
    check([factory[@"DefaultEngine"] isEqual:@"LuaLaTeX"] && [factory[@"DefaultCommand"] integerValue] == 1, @"the factory engine file is LuaLaTeX and new documents use LaTeX");
    NSArray *cases = @[@[@{@"DefaultCommand": @2}, @"XeLaTeX"], @[@{@"DefaultCommand": @"2"}, @"XeLaTeX"],
                       @[@{@"DefaultCommand": @2, @"DefaultEngine": @"pdflatexmk"}, @"pdflatexmk"],
                       @[@{@"DefaultCommand": @1}, @"LuaLaTeX"], @[@{}, @"LuaLaTeX"], @[@{@"DefaultCommand": @[]}, @"LuaLaTeX"]];
    for (NSArray *c in cases) {
        TSMemoryDefaults *d = [TSMemoryDefaults new]; [d registerDefaults:factory];
        [c[0] enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) { [d setObject:value forKey:key]; }];
        TSKeepEarlierFactoryEngineFile(d, c[0]); TSKeepEarlierFactoryEngineFile(d, c[0]);
        check([[d stringForKey:@"DefaultEngine"] isEqual:c[1]], [NSString stringWithFormat:@"stored %@ typesets with %@", c[0], c[1]]);
    }
    if (failures) return 1;
    puts("PASS: 8 profiles x 2 forms write exactly their keys; matching, apply, latexmk in use, first-launch language choice and the earlier factory engine file");
} return 0; }
'''

MUTATIONS = {
    'other place written': ('    values[direct ? TexCommandKey : TexGSCommandKey] = row[2];',
                            '    values[direct ? TexCommandKey : TexGSCommandKey] = row[2]; values[direct ? LatexGSCommandKey : LatexCommandKey] = row[1];'),
    'latexmk ignored': ('latexmk ? row[3] : row[1]', 'row[1]'),
    'otf for every Japanese engine': ('profile == TSEngineProfilePLaTeXDvipdfmx ? @YES : @NO;', 'TSEngineProfileIsJapanese(profile) ? @YES : @NO;'),
    'no Japanese companions': ('    if (TSEngineProfileIsJapanese(profile)) {\n        // New documents', '    if (NO) {\n        // New documents'),
    'stored NO differs from @NO': ('        return [value respondsToSelector:@selector(boolValue)] && [value boolValue] == [expected boolValue];', '        return [value isEqual:expected];'),
    'no Japanese encoding': ('        values[EncodingKey] = @"UTF-8 Unicode";\n', ''),
    'match ignores BibTeX': ('TexGSCommandKey, BibTeXengineKey]', 'TexGSCommandKey]'),
    'match only one form': ("for (NSNumber *form in @[@NO, @YES])", "for (NSNumber *form in @[@NO])"),
    'no deferral': ('    profileApplicationDepth++;\n', '\n'),
    'every key reported changed': ('if (!TSEngineProfileSame([defaults objectForKey:key], value)) [changed addObject:key];', '[changed addObject:key];'),
    'every language Japanese': ('? TSEngineProfileUpLaTeXDvipdfmx : TSEngineProfilePdfLaTeX', '? TSEngineProfileUpLaTeXDvipdfmx : TSEngineProfileUpLaTeXDvipdfmx'),
    'latexmk by prefix only': ('    return [command isEqualToString:@"latexmk"] || [command hasPrefix:@"latexmk "];', '    return [command hasPrefix:@"latexmk"];'),
    'latexmk of the other method': ('[defaults integerForKey:DefaultScriptKey] == TSEngineProfileViaDVI ? LatexGSCommandKey : LatexCommandKey;', 'LatexGSCommandKey;'),
    'earlier engine file lost': ('    [defaults setObject:@"XeLaTeX" forKey:DefaultEngineKey];', ''),
    'stored engine file replaced': ('    if (stored[DefaultEngineKey] != nil) return;\n', ''),
    'any command keeps XeLaTeX': ('|| [command integerValue] != 2) return;', ') return;'),
    'dvips offered first': ('             @[@(TSEngineProfileLaTeXDvipsGhostscript)]];', '             @[@(TSEngineProfileLaTeXDvipsGhostscript), @(TSEngineProfilePdfLaTeX)]];'),
}

with tempfile.TemporaryDirectory(prefix='texshop-engine-profiles-') as temp:
    t = Path(temp)
    (t / 'probe.m').write_text(PROGRAM)
    (t / 'table.json').write_text(json.dumps(EXPECTED))
    original = source_file(R, 'TSPreferenceProfile.m').read_text()

    def run(source):
        (t / 'TSPreferenceProfile.m').write_text(source)
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', *include_args(R), '-I', str(R / 'Tests'),
                        '-framework', 'Cocoa', str(t / 'probe.m'), str(t / 'TSPreferenceProfile.m'), str(source_file(R, 'globals.m')),
                        '-o', str(t / 'probe')], check=True)
        return subprocess.run([str(t / 'probe'), str(t / 'table.json'), str(FACTORY)], capture_output=True, text=True)

    result = run(original)
    if result.returncode:
        sys.exit(result.stderr)
    print(result.stdout.strip(), flush=True)
    for name, (old, new) in MUTATIONS.items():
        assert original.count(old) == 1, name
        result = run(original.replace(old, new))
        assert result.returncode and 'FAIL:' in result.stderr, (name, result.stdout, result.stderr)
        print('DETECTED', name, flush=True)
    assert run(original).returncode == 0
    print('NORMAL CONTROL passes again')
