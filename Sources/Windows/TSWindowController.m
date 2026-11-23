/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSWindowManager.m 108 2006-02-10 13:50:25Z fingolfin $
 *
 * Created by dirk on Sat Feb 17 2001.
 *
 */

#import "TSWindowController.h"
#import "TSDocument.h"
#import "globals.h"


@implementation TSWindowController
/*"

"*/

- (IBAction)showWindow:(id)sender
{
    [super showWindow: sender];
}


- (void)windowWillLoad
{
    [super windowWillLoad];
}

// AppKit names the window again whenever the document changes (saves, autosaves, Edited); with Show Full Path
// the name it gives the source window is the full path, so it never falls back to the file name.
// The single window of source and preview keeps AppKit's name.
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
    NSDocument *document = self.document;
    if ([document isKindOfClass:[TSDocument class]] && ((TSDocument *)document).standardController == self
        && [(TSDocument *)document showsFullPath] && document.fileURL != nil)
        return document.fileURL.path;
    return [super windowTitleForDocumentDisplayName:displayName];
}

// The Experiment panels are named after the source window, so they are named again with it.
- (void)synchronizeWindowTitleWithDocumentName
{
    [super synchronizeWindowTitleWithDocumentName];
    NSDocument *document = self.document;
    if ([document isKindOfClass:[TSDocument class]] && ((TSDocument *)document).standardController == self)
        [(TSDocument *)document refreshExperimentTitles];
}



@end
