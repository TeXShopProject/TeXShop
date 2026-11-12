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

// Whether a command runs ps2pdf: simpdftex, and the altpdftex and altpdflatex
// scripts used for continuous typesetting, unless --distiller names another
// converter.
static BOOL TSCommandNeedsGhostscript(NSString *program, NSArray *arguments)
{
    if (![@[@"simpdftex", @"altpdftex", @"altpdflatex"] containsObject:program.lastPathComponent ?: @""])
        return NO;
    for (id argument in arguments)
        if ([argument isKindOfClass:NSString.class] && [argument hasPrefix:@"--distiller"] && ![argument hasPrefix:@"--distilleropts"])
            return NO;
    return YES;
}
