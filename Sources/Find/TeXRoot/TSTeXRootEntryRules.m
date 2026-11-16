// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootEntryRules.h"
#import "TSRootFileResolver.h"
#import "TSAdvancedFindController.h"

#define TSLocalized TSAdvancedFindLocalized

@implementation TSTeXRootEntryRules

+ (TSTeXRootEntryState)stateForDocumentURL:(nullable NSURL *)url text:(nullable NSString *)text
                         allowingSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken
                                   rootURL:(NSURL *_Nullable *_Nullable)rootURL
{
    if (rootURL)
        *rootURL = nil;
    if (!url)
        return TSTeXRootEntryStateUntitled;
    if (![url.pathExtension isEqualToString:@"tex"])
        return TSTeXRootEntryStateNotTeX;
    NSString *path = [TSRootFileResolver rootPathInSource:text documentPath:url.path allowingSourceDoc:allowsSourceDoc
                                             jobNameToken:jobNameToken specifier:NULL];
    if (rootURL)
        *rootURL = path ? [NSURL fileURLWithPath:path] : url;
    return path ? TSTeXRootEntryStateChild : TSTeXRootEntryStateRoot;
}

+ (NSString *)titleForState:(TSTeXRootEntryState)state applying:(BOOL)applying
{
    if (state == TSTeXRootEntryStateRoot)
        return applying ? TSLocalized(@"TeXRootSearch.Menu.ApplyThisRoot", @"Apply to TeX Sources with This File as TEX root…")
                        : TSLocalized(@"TeXRootSearch.Menu.FindThisRoot", @"Find in TeX Sources with This File as TEX root…");
    return applying ? TSLocalized(@"TeXRootSearch.Menu.ApplySameRoot", @"Apply to TeX Sources with the Same TEX root…")
                    : TSLocalized(@"TeXRootSearch.Menu.FindSameRoot", @"Find in TeX Sources with the Same TEX root…");
}

+ (NSString *)messageForProblem:(TSTeXRootProblem)problem
{
    switch (problem) {
        case TSTeXRootProblemNotRegularFile:
            return TSLocalized(@"TeXRootSearch.Problem.NotFile", @"The TEX root is not a file.");
        case TSTeXRootProblemNotTeXFile:
            return TSLocalized(@"TeXRootSearch.Problem.NotTeX", @"The name of the TEX root file does not end in .tex.");
        default:
            return TSLocalized(@"TeXRootSearch.Problem.Missing", @"The TEX root file cannot be found.");
    }
}

@end
