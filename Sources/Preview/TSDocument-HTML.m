/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2014 Richard Koch
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
 * $Id: TSDocument-Jobs.m 254 2014-06-28 21:09:25Z fingolfin $
 *
 */


#import "TSDocument.h"
#import "globals.h"
#import "TSWindowManager.h"


// The Home URL setting is a web address or the path of a file; empty means the bundled sample page.
static NSURL *TSHTMLHomeURL(NSString *home)
{
    home = [home stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([home hasPrefix:@"/"] || [home hasPrefix:@"~"])
        return [NSURL fileURLWithPath:home.stringByExpandingTildeInPath];
    if (home.length > 0) {
        NSURL *url = [NSURL URLWithString:home];
        if (url.scheme.length == 0)
            url = [NSURL URLWithString:[@"https://" stringByAppendingString:home]];
        if (url != nil)
            return url;
    }
    return [[NSBundle mainBundle] URLForResource:@"SamplePage" withExtension:@"html"];
}

@implementation TSDocument (HTML)

- (void)showHTMLWindow:sender
{
    NSURL *theURL = TSHTMLHomeURL([SUD stringForKey:HtmlHomeKey]);
    
    if (theURL.isFileURL)
        [self.htmlView loadFileURL:theURL allowingReadAccessToURL:theURL.URLByDeletingLastPathComponent];
    else
        [self.htmlView loadRequest:[NSURLRequest requestWithURL:theURL]];
    self.htmlView.allowsMagnification = YES;
    [self.htmlWindow makeKeyAndOrderFront:self];
   
}


- (void)saveHTMLPosition: sender
{
    {
        NSWindow    *activeWindow;
        activeWindow = [[TSWindowManager sharedInstance] activeHTMLWindow];

        
        if (activeWindow != nil) {
       //     [self fixPreferences];
            [SUD setInteger:HtmlWindowPosFixed forKey:HtmlWindowPosModeKey];
            [SUD setObject:[activeWindow stringWithSavedFrame] forKey:HtmlWindowFixedPosKey];
            [SUD synchronize];
            }
        

    }

}

- (void)gotoURL: sender
{
    NSString        *newURL;
    NSURL           *theURL;
    NSURLRequest    *theRequest;
    
    
    newURL = [sender stringValue];
    if ((newURL == NULL) || (newURL.length < 8))
        return;
    theURL = [NSURL URLWithString: newURL];
    theRequest = [NSURLRequest requestWithURL: theURL];
    [self.htmlView loadRequest: theRequest];
}

@end
