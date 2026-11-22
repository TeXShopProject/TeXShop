//
//  TSTexdocReport.h
//
//  What Help > Show Help for Package says when texdoc shows nothing: texdoc is not in the folder of
//  the TeX engines, it could not run, or it found no documentation. In the last case it names the
//  TeX installation and the documentation folders that texdoc searched, since a Mac may have several
//  TeX installations and another one may have the documentation.
//

#import <Foundation/Foundation.h>

// texdoc's status when it found no documentation.
static const int TSTexdocNothingFound = 3;

// The settings that choose the folder of the TeX engines, in the words of the Settings window.
static inline NSString *TSTexdocEnginePathSetting(void)
{
    return [NSString stringWithFormat:@"%@ › %@ › %@ › %@", NSLocalizedString(@"Settings", @"The Settings window, as the first step of a path to a setting"),
            NSLocalizedStringFromTable(@"typesetting", @"SettingsCategories", nil),
            NSLocalizedStringFromTable(@"group.typesetting.3.title", @"SettingsCategories", nil),
            NSLocalizedStringFromTable(@"catalog.typesetting.3.0.title", @"SettingsCategories", nil)];
}

// The output of a short command (kpsewhich), or nil.
static inline NSString *TSTexdocRun(NSString *tool, NSArray<NSString *> *arguments, NSDictionary *environment)
{
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool])
        return nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = arguments;
    task.environment = environment;
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:NULL])
        return nil;
    NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0)
        return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// The TeX installation of the folder of the TeX engines (its SELFAUTOPARENT, such as
// /Applications/TeXLive/2026), and the documentation folders that texdoc searches there: the
// existing doc folders of its TEXDOCS path, as kpsewhich of that installation expands it.
static inline void TSTexdocSearch(NSString *binPath, NSDictionary *environment, NSString **installation, NSArray<NSString *> **folders)
{
    NSString *kpsewhich = [binPath stringByAppendingPathComponent:@"kpsewhich"];
    *installation = TSTexdocRun(kpsewhich, @[@"-var-value", @"SELFAUTOPARENT"], environment);
    if ((*installation).length == 0)
        *installation = binPath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (NSString *folder in [TSTexdocRun(kpsewhich, @[@"--expand-path=$TEXDOCS"], environment) componentsSeparatedByString:@":"])
        if ([folder.lastPathComponent isEqualToString:@"doc"] && ![found containsObject:folder])
            [found addObject:folder];
    *folders = found;
}

// The message and the details of the alert for a texdoc that ended with status, or nil when it
// showed the documentation. output is what texdoc wrote (its own hints, such as texdoc.org).
static inline NSArray<NSString *> *TSTexdocFailureTexts(int status, BOOL exited, NSString *package, NSString *texdoc,
                                                       NSString *output, NSString *installation, NSArray<NSString *> *folders)
{
    if (exited && status == 0)
        return nil;
    output = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    NSString *message;
    if (exited && status == TSTexdocNothingFound) {
        message = [NSString stringWithFormat:NSLocalizedString(@"No documentation was found for “%@”.", @"Help > Show Help for Package: texdoc found nothing"), package];
        NSString *searched = [NSString stringWithFormat:NSLocalizedString(@"texdoc of the TeX installation in %@ looked in:", @"Help > Show Help for Package: followed by the folders texdoc searched"), installation];
        [details addObject:[[@[searched] arrayByAddingObjectsFromArray:folders ?: @[]] componentsJoinedByString:@"\n"]];
        [details addObject:[NSString stringWithFormat:NSLocalizedString(@"Another TeX installation on this Mac may have it. The installation that TeXShop uses is set in %@.", @"Help > Show Help for Package: %@ is the path of the setting"), TSTexdocEnginePathSetting()]];
    } else {
        message = [NSString stringWithFormat:NSLocalizedString(@"texdoc could not show the documentation for “%@”.", @"Help > Show Help for Package: texdoc failed"), package];
        [details addObject:[NSString stringWithFormat:NSLocalizedString(@"%@ ended with status %d.", @"Help > Show Help for Package: the path of texdoc and its exit status"), texdoc, status]];
    }
    if (output.length)
        [details addObject:output];
    return @[message, [details componentsJoinedByString:@"\n\n"]];
}

// The message and the details when the folder of the TeX engines has no texdoc that can run.
static inline NSArray<NSString *> *TSTexdocMissingTexts(NSString *binPath)
{
    return @[NSLocalizedString(@"texdoc was not found.", @"Help > Show Help for Package: no texdoc"),
             [NSString stringWithFormat:NSLocalizedString(@"There is no texdoc in %@, the folder set in %@.", @"Help > Show Help for Package: the folder of the TeX engines and the path of the setting"),
              binPath.length ? binPath : @"—", TSTexdocEnginePathSetting()]];
}
