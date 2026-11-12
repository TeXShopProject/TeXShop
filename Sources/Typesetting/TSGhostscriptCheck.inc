// SPDX-License-Identifier: GPL-2.0-or-later
// Ghostscript turns PostScript into PDF: when a .ps or .eps file is opened, and
// in the Via DVI commands that run dvips and then ps2pdf. Typesetting that makes
// PDF directly, or through dvipdfmx, does not need it.

// Whether gs is in one of the folders of a PATH value.
static BOOL TSGhostscriptFoundInPath(NSString *path)
{
    for (NSString *folder in [path componentsSeparatedByString:@":"]) {
        if (folder.length == 0)
            continue;
        NSString *program = [[folder stringByExpandingTildeInPath] stringByAppendingPathComponent:@"gs"];
        BOOL isFolder = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:program isDirectory:&isFolder] && !isFolder &&
            [[NSFileManager defaultManager] isExecutableFileAtPath:program])
            return YES;
    }
    return NO;
}

// simpdftex, and the altpdftex and altpdflatex scripts used for continuous
// typesetting, run dvips and then a distiller: ps2pdf unless --distiller or
// --distiller-filter names another program. Before that they put the folder of
// --distiller-path, /usr/local/bin by default, in front of the PATH.
// Returns nil when the command does not run Ghostscript, and otherwise the
// folders the command adds to the PATH before it runs the distiller.
static NSArray<NSString *> *TSGhostscriptFoldersForCommand(NSString *program, NSArray *arguments)
{
    if (![@[@"simpdftex", @"altpdftex", @"altpdflatex"] containsObject:program.lastPathComponent ?: @""])
        return nil;
    NSString *distiller = @"ps2pdf", *distillerPath = @"/usr/local/bin";
    NSArray<NSString *> *options = @[@"--distiller", @"--distiller-filter", @"--distiller-path", @"--distilleropts"];
    for (NSUInteger index = 0; index < arguments.count; index++) {
        if (![arguments[index] isKindOfClass:NSString.class])
            continue;
        NSString *argument = arguments[index], *name = argument, *value = nil;
        NSRange equals = [argument rangeOfString:@"="];
        if ([argument hasPrefix:@"--"] && equals.location != NSNotFound) {
            name = [argument substringToIndex:equals.location];
            value = [argument substringFromIndex:NSMaxRange(equals)];
        }
        if (![options containsObject:name])
            continue;
        if (value == nil) {
            value = (index + 1 < arguments.count && [arguments[index + 1] isKindOfClass:NSString.class]) ? arguments[index + 1] : @"";
            index++;
        }
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"' "]];
        if ([name isEqualToString:@"--distiller-path"])
            distillerPath = value;
        else if (![name isEqualToString:@"--distilleropts"])
            distiller = value;
    }
    NSString *converter = [[distiller componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] firstObject] ?: @"";
    NSString *converterName = converter.lastPathComponent;
    if (!([converterName hasPrefix:@"ps2pdf"] || [@[@"gs", @"gsc", @"gsx"] containsObject:converterName]))
        return nil;
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    if (distillerPath.length > 0)
        [folders addObject:distillerPath];
    if (converter.isAbsolutePath)
        [folders addObject:converter.stringByDeletingLastPathComponent];
    return folders;
}
