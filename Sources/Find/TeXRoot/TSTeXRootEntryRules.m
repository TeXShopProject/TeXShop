// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootEntryRules.h"
#import "TSRootFileResolver.h"
#import "TSAdvancedFindController.h"

#define TSLocalized TSAdvancedFindLocalized

/// Only the lowercase extension "tex" (spec §1 decision 22).
static BOOL TSIsTeXFile(NSURL *url)
{
    return [url.pathExtension isEqualToString:@"tex"];
}

@implementation TSTeXRootEntryRules

+ (TSTeXRootEntryState)stateForDocumentURL:(nullable NSURL *)url text:(nullable NSString *)text
                         allowingSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken
                                   rootURL:(NSURL *_Nullable *_Nullable)rootURL
{
    if (rootURL)
        *rootURL = nil;
    if (!url)
        return TSTeXRootEntryStateUntitled;
    if (!TSIsTeXFile(url))
        return TSTeXRootEntryStateNotTeX;
    NSString *path = [TSRootFileResolver rootPathInSource:text documentPath:url.path allowingSourceDoc:allowsSourceDoc
                                             jobNameToken:jobNameToken specifier:NULL];
    if (rootURL)
        *rootURL = path ? [NSURL fileURLWithPath:path] : url;
    return path ? TSTeXRootEntryStateChild : TSTeXRootEntryStateRoot;
}

+ (TSTeXRootEntryState)menuStateForDocumentURL:(nullable NSURL *)url text:(nullable NSString *)text allowingSourceDoc:(BOOL)allowsSourceDoc
{
    if (!url)
        return TSTeXRootEntryStateUntitled;
    if (!TSIsTeXFile(url))
        return TSTeXRootEntryStateNotTeX;
    return [TSRootFileResolver specifierInSource:text allowingSourceDoc:allowsSourceDoc] ? TSTeXRootEntryStateChild : TSTeXRootEntryStateRoot;
}

+ (dispatch_queue_t)queue
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("org.texshop.TeXRootEntry", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

+ (void)menuStateForDocumentURL:(NSURL *)url textLoader:(NSString *_Nullable (^)(void))loader allowingSourceDoc:(BOOL)allowsSourceDoc
                     completion:(void (^)(TSTeXRootEntryState state))completion
{
    NSURL *copied = [url copy];
    dispatch_async(self.queue, ^{
        TSTeXRootEntryState state = [self menuStateForDocumentURL:copied text:loader() allowingSourceDoc:allowsSourceDoc];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(state); });
    });
}

+ (void)resolveRootForDocumentURL:(NSURL *)url textLoader:(NSString *_Nullable (^)(void))loader allowingSourceDoc:(BOOL)allowsSourceDoc
                     jobNameToken:(NSString *)jobNameToken
                       completion:(void (^)(TSTeXRootEntryState state, NSURL *_Nullable rootURL, TSTeXRootProblem problem))completion
{
    NSURL *copied = [url copy];
    NSString *token = [jobNameToken copy];
    dispatch_async(self.queue, ^{
        NSURL *root = nil;
        TSTeXRootEntryState state = [self stateForDocumentURL:copied text:loader() allowingSourceDoc:allowsSourceDoc jobNameToken:token rootURL:&root];
        TSTeXRootProblem problem = root ? [TSTeXRootProjectCollector problemWithRootURL:(NSURL *_Nonnull)root] : TSTeXRootProblemNone;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(state, root, problem); });
    });
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
