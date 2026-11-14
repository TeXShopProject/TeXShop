// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceProfile.h"
#import "globals.h"

TSPreferenceKey const TSSettingsSelectedCategoryKey = @"TSSettingsSelectedCategory";

static NSUInteger profileApplicationDepth;
BOOL TSPreferenceProfileIsApplying(void) { return profileApplicationDepth != 0; }

// The two places for typesetting commands: DefaultScript 100 runs the commands that make PDF
// directly, 101 the commands that go through DVI.
static NSInteger const TSEngineProfileDirectPDF = 100;
static NSInteger const TSEngineProfileViaDVI = 101;

NSArray<NSArray<NSNumber *> *> *TSEngineProfileMenuSections(void)
{
    return @[@[@(TSEngineProfilePdfLaTeX), @(TSEngineProfileXeLaTeX), @(TSEngineProfileLuaLaTeX), @(TSEngineProfileLaTeXDvipdfmx)],
             @[@(TSEngineProfileLuaLaTeXJapanese), @(TSEngineProfilePLaTeXDvipdfmx), @(TSEngineProfileUpLaTeXDvipdfmx)],
             @[@(TSEngineProfileLaTeXDvipsGhostscript)]];
}

NSString *TSEngineProfileTitle(TSEngineProfile profile)
{
    switch (profile) {
        case TSEngineProfilePdfLaTeX: return @"pdfLaTeX";
        case TSEngineProfileXeLaTeX: return @"XeLaTeX";
        case TSEngineProfileLuaLaTeX: return @"LuaLaTeX";
        case TSEngineProfileLaTeXDvipdfmx: return @"LaTeX + dvipdfmx";
        case TSEngineProfileLuaLaTeXJapanese: return NSLocalizedString(@"LuaLaTeX (Japanese)", @"Engine profile");
        case TSEngineProfilePLaTeXDvipdfmx: return @"pLaTeX + dvipdfmx";
        case TSEngineProfileUpLaTeXDvipdfmx: return @"upLaTeX + dvipdfmx";
        case TSEngineProfileLaTeXDvipsGhostscript: return @"LaTeX + dvips + Ghostscript";
        default: return nil;
    }
}

BOOL TSEngineProfileIsJapanese(TSEngineProfile profile)
{
    return profile == TSEngineProfileLuaLaTeXJapanese || profile == TSEngineProfilePLaTeXDvipdfmx || profile == TSEngineProfileUpLaTeXDvipdfmx;
}

// One row of the table: the place, the LaTeX and TeX commands without latexmk, the LaTeX
// command with latexmk, the BibTeX engine, the index command and the MetaPost command.
static NSArray *TSEngineProfileRow(TSEngineProfile profile)
{
    NSString *const pdfOptions = @"--file-line-error --synctex=1";
    NSString *const simpdfOptions = @"--extratexopts \"-file-line-error -synctex=1\"";
    NSString *const ptexOptions = @"-ot \"-synctex=1 -file-line-error\"";
    NSString *const dvipdfmx = @"-e \"$dvipdf=q/dvipdfmx %O -o %D %S/\"";
    switch (profile) {
        case TSEngineProfilePdfLaTeX:
            return @[@(TSEngineProfileDirectPDF), [@"pdflatex " stringByAppendingString:pdfOptions], [@"pdftex " stringByAppendingString:pdfOptions],
                     @"latexmk -pdf -e \"$pdflatex=q/pdflatex -synctex=1 -file-line-error/\" -norc", @"bibtex", @"makeindex", @"mpost"];
        case TSEngineProfileXeLaTeX:
            return @[@(TSEngineProfileDirectPDF), [@"xelatex " stringByAppendingString:pdfOptions], [@"xetex " stringByAppendingString:pdfOptions],
                     @"latexmk -xelatex -e \"$xelatex=q/xelatex -synctex=1 -file-line-error/\" -norc", @"bibtex", @"makeindex", @"mpost"];
        case TSEngineProfileLuaLaTeX:
            return @[@(TSEngineProfileDirectPDF), [@"lualatex " stringByAppendingString:pdfOptions], [@"luatex " stringByAppendingString:pdfOptions],
                     @"latexmk -lualatex -e \"$lualatex=q/lualatex -synctex=1 -file-line-error/\" -norc", @"bibtex", @"makeindex", @"mpost"];
        case TSEngineProfileLaTeXDvipdfmx:
            return @[@(TSEngineProfileViaDVI), [@"simpdftex latex --mode dvipdfmx " stringByAppendingString:simpdfOptions],
                     [@"simpdftex etex --mode dvipdfmx " stringByAppendingString:simpdfOptions],
                     [NSString stringWithFormat:@"latexmk -pdfdvi -e \"$latex=q/latex -synctex=1 -file-line-error/\" %@ -norc", dvipdfmx], @"bibtex", @"makeindex", @"mpost"];
        case TSEngineProfileLuaLaTeXJapanese:
            return @[@(TSEngineProfileDirectPDF), [@"lualatex " stringByAppendingString:pdfOptions], [@"luatex " stringByAppendingString:pdfOptions],
                     @"latexmk -lualatex -e \"$lualatex=q/lualatex -synctex=1 -file-line-error/\" -e \"$bibtex=q/upbibtex/\" -e \"$makeindex=q/upmendex/\" -norc", @"upbibtex", @"upmendex", @"mpost"];
        case TSEngineProfilePLaTeXDvipdfmx:
            return @[@(TSEngineProfileViaDVI), [@"ptex2pdf -l " stringByAppendingString:ptexOptions], [@"ptex2pdf -e " stringByAppendingString:ptexOptions],
                     [NSString stringWithFormat:@"latexmk -pdfdvi -e \"$latex=q/platex -synctex=1 -file-line-error/\" -e \"$bibtex=q/pbibtex/\" -e \"$makeindex=q/mendex/\" %@ -norc", dvipdfmx], @"pbibtex", @"mendex", @"pmpost"];
        case TSEngineProfileUpLaTeXDvipdfmx:
            return @[@(TSEngineProfileViaDVI), [@"ptex2pdf -u -l " stringByAppendingString:ptexOptions], [@"ptex2pdf -e -u " stringByAppendingString:ptexOptions],
                     [NSString stringWithFormat:@"latexmk -pdfdvi -e \"$latex=q/uplatex -synctex=1 -file-line-error/\" -e \"$bibtex=q/upbibtex/\" -e \"$makeindex=q/upmendex/\" %@ -norc", dvipdfmx], @"upbibtex", @"upmendex", @"upmpost"];
        case TSEngineProfileLaTeXDvipsGhostscript:
            return @[@(TSEngineProfileViaDVI), [@"simpdftex latex --maxpfb " stringByAppendingString:simpdfOptions],
                     [@"simpdftex etex --maxpfb " stringByAppendingString:simpdfOptions],
                     @"latexmk -pdfps -e \"$latex=q/latex -synctex=1 -file-line-error/\" -norc", @"bibtex", @"makeindex", @"mpost"];
        default: return nil;
    }
}

NSDictionary<TSPreferenceKey, id> *TSEngineProfileValues(TSEngineProfile profile, BOOL latexmk)
{
    NSArray *row = TSEngineProfileRow(profile);
    if (row == nil) return @{};
    BOOL direct = [row[0] integerValue] == TSEngineProfileDirectPDF;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    // Only the place that becomes the default is written; the other keeps the user's commands.
    values[DefaultScriptKey] = row[0];
    values[direct ? LatexCommandKey : LatexGSCommandKey] = latexmk ? row[3] : row[1];
    values[direct ? TexCommandKey : TexGSCommandKey] = row[2];
    values[BibTeXengineKey] = row[4];
    values[MakeIndexEngineKey] = row[5];
    values[MetaPostEngineKey] = row[6];
    // otf package support is a pTeX feature: every other engine turns it off.
    values[ptexUtfOutputEnabledKey] = profile == TSEngineProfilePLaTeXDvipdfmx ? @YES : @NO;
    if (TSEngineProfileIsJapanese(profile)) {
        // New documents in UTF-8, which the Japanese engines of today read.
        values[EncodingKey] = @"UTF-8 Unicode";
        values[AutomaticUTF8MACtoUTF8ConversionKey] = @YES;
        // macOS has no Japanese spelling dictionary: the language is identified automatically,
        // stored as the Settings choice of Automatic stores it.
        values[spellingAutomaticDefaultKey] = @YES;
        values[spellingLanguageDefaultKey] = @" ";
    }
    return values;
}

// Equal in meaning: a stored "NO" is the same switch as @NO, and blanks around a command do not count.
static BOOL TSEngineProfileSame(id value, id expected)
{
    if ([expected isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)expected) == CFBooleanGetTypeID())
        return [value respondsToSelector:@selector(boolValue)] && [value boolValue] == [expected boolValue];
    if ([value isKindOfClass:NSNumber.class] || [expected isKindOfClass:NSNumber.class])
        return [value respondsToSelector:@selector(integerValue)] && [value integerValue] == [expected integerValue];
    if (![value isKindOfClass:NSString.class]) return NO;
    NSCharacterSet *blank = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    return [[value stringByTrimmingCharactersInSet:blank] isEqualToString:[expected stringByTrimmingCharactersInSet:blank]];
}

TSEngineProfile TSEngineProfileMatchingSettings(NSUserDefaults *defaults, BOOL *latexmk)
{
    for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections())
        for (NSNumber *number in section)
            for (NSNumber *form in @[@NO, @YES]) {
                NSDictionary *values = TSEngineProfileValues(number.integerValue, form.boolValue);
                BOOL same = YES;
                // The commands decide; the settings that go with them do not.
                for (NSString *key in @[DefaultScriptKey, LatexCommandKey, TexCommandKey, LatexGSCommandKey, TexGSCommandKey, BibTeXengineKey])
                    if (values[key] != nil && !TSEngineProfileSame([defaults objectForKey:key], values[key])) { same = NO; break; }
                if (!same) continue;
                if (latexmk != NULL) *latexmk = form.boolValue;
                return number.integerValue;
            }
    if (latexmk != NULL) *latexmk = NO;
    return TSEngineProfileNone;
}

BOOL TSEngineProfileSettingsUseLatexmk(NSUserDefaults *defaults)
{
    BOOL latexmk = NO;
    if (TSEngineProfileMatchingSettings(defaults, &latexmk) != TSEngineProfileNone) return latexmk;
    NSString *key = [defaults integerForKey:DefaultScriptKey] == TSEngineProfileViaDVI ? LatexGSCommandKey : LatexCommandKey;
    NSString *command = [[defaults stringForKey:key] ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [command isEqualToString:@"latexmk"] || [command hasPrefix:@"latexmk "];
}

TSEngineProfile TSEngineProfileForLanguages(NSArray<NSString *> *languages)
{
    NSString *first = languages.firstObject.lowercaseString ?: @"";
    return [first isEqualToString:@"ja"] || [first hasPrefix:@"ja-"] || [first hasPrefix:@"ja_"] ? TSEngineProfileUpLaTeXDvipdfmx : TSEngineProfilePdfLaTeX;
}

NSSet<TSPreferenceKey> *TSEngineProfileApply(NSUserDefaults *defaults, NSDictionary<TSPreferenceKey, id> *values)
{
    NSCAssert(NSThread.isMainThread, @"Apply an engine profile on the main thread");
    NSMutableSet *changed = [NSMutableSet set];
    profileApplicationDepth++;
    @try {
        [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (!TSEngineProfileSame([defaults objectForKey:key], value)) [changed addObject:key];
            [defaults setObject:value forKey:key];
        }];
    } @finally {
        profileApplicationDepth--;
    }
    // Observers of individual defaults changes were deferred above.
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
    return changed;
}

void TSKeepEarlierFactoryEngineFile(NSUserDefaults *defaults, NSDictionary *stored)
{
    id command = stored[DefaultCommandKey];
    if (![command respondsToSelector:@selector(integerValue)] || [command integerValue] != 2) return;
    if (stored[DefaultEngineKey] != nil) return;
    [defaults setObject:@"XeLaTeX" forKey:DefaultEngineKey];
}
