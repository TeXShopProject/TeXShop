/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2019 Richard Koch
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
#import "GlobalData.h"
#import "TSColorSupport.h"
#import "MyPDFKitView.h"
#import "TSAppDelegate.h"


@implementation TSDocument (XML)

// The coloring of XML is done by TSSyntaxTeXScanner (TSSyntaxXMLScanning.m).

- (NSInteger)xmlTag: (NSString *)line;
{
    NSInteger i, result;
    NSString *tag, *cleanline;
    
    result = -1;
    cleanline = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    
    for (i = 0; i < [g_taggedXMLSections count]; ++i)
        if (g_activeXMLTags[i])
        {
        tag = [g_taggedXMLSections objectAtIndex:i];
        if ([cleanline hasPrefix:tag])
        {   result = i;
            break;
        }
    }
    return result;
}

- (NSString *)xmlGetTitle: (NSString *)titleLine
{
    NSString *cleanline;
    NSRange titleRange, closeTitleRange;
    NSString *returnString = @"";
    
    cleanline = [titleLine stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    if ([cleanline hasPrefix:@"<title>"])
    {
        titleRange.location = 7;
        titleRange.length = [cleanline length] - 7;
        cleanline = [cleanline substringWithRange: titleRange];
        if ([cleanline length] > 0)
        {
            closeTitleRange = [cleanline rangeOfString:@"</title>"];
            if (closeTitleRange.location != NSNotFound)
            {
                titleRange.location = 0;
                titleRange.length = closeTitleRange.location;
                cleanline = [cleanline substringWithRange: titleRange];
                if ([cleanline length] > 0)
                    returnString = cleanline;
            }
        }
   }
    else if ([cleanline hasPrefix:@"<caption>"])
    {
        titleRange.location = 9;
        titleRange.length = [cleanline length] - 9;
        cleanline = [cleanline substringWithRange: titleRange];
        if ([cleanline length] > 0)
        {
            closeTitleRange = [cleanline rangeOfString:@"</caption>"];
            if (closeTitleRange.location != NSNotFound)
            {
                titleRange.location = 0;
                titleRange.length = closeTitleRange.location;
                cleanline = [cleanline substringWithRange: titleRange];
                if ([cleanline length] > 0)
                    returnString = cleanline;
            }
        }
    }
    
    else if ([cleanline hasPrefix:@"<p>"])
    {
        titleRange.location = 3;
        titleRange.length = [cleanline length] - 3;
        cleanline = [cleanline substringWithRange: titleRange];
        if ([cleanline length] > 0)
        {
            closeTitleRange = [cleanline rangeOfString:@"</p>"];
            if (closeTitleRange.location != NSNotFound)
            {
                titleRange.location = 0;
                titleRange.length = closeTitleRange.location;
                cleanline = [cleanline substringWithRange: titleRange];
                if ([cleanline length] > 0)
                    returnString = cleanline;
            }
        }
    }
    
    else
        xmlNoParameter = true;
        
    
return returnString;
}

- (NSString *)xmlGetImageSource: (NSString *)titleLine
{
    NSString *cleanline;
    NSRange titleRange, closeTitleRange;
    NSString *firstSearch, *secondSearch;
    NSString *returnString = @"";
    
    cleanline = [titleLine stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    
    firstSearch = @"<image source=\"";
    if ([cleanline hasPrefix:firstSearch])
    {
        titleRange.location = 15;
        titleRange.length = [cleanline length] - 15;
        cleanline = [cleanline substringWithRange: titleRange];
        if ([cleanline length] > 0)
        {
            secondSearch = @"\"";
            closeTitleRange = [cleanline rangeOfString:secondSearch];
            if (closeTitleRange.location != NSNotFound)
            {
                titleRange.location = 0;
                titleRange.length = closeTitleRange.location;
                cleanline = [cleanline substringWithRange: titleRange];
                if ([cleanline length] > 0)
                {
                    returnString = cleanline;
                }
             
            }
        }
    }
         return returnString;
}
        
 - (IBAction) toggleXML: sender
{
    
    NSMenuItem *theItem;
    theItem = sender;
    if (theItem.state == YES)
    {
        self.fileIsXML = NO;
        theItem.state = NO;
    }
    else
    {
        self.fileIsXML = YES;
        theItem.state = YES;
    }
    [self colorizeVisibleAreaInTextView:textView1];
    [self colorizeVisibleAreaInTextView:textView2];
    [self colorizeExperimentSource];
    
    if (self.fileIsXML)
    {
        if (! [[GlobalData sharedGlobalData].CommandCompletionPath isEqualToString: CommandCompletionPathXML])
        {
            [GlobalData sharedGlobalData].CommandCompletionPath = CommandCompletionPathXML;
            [(TSAppDelegate *)[[NSApplication sharedApplication] delegate] reReadCommandCompletionData];
        }
        
    }
    else
    {
        if (! [[GlobalData sharedGlobalData].CommandCompletionPath isEqualToString: CommandCompletionPathRegular])
        {
            [GlobalData sharedGlobalData].CommandCompletionPath = CommandCompletionPathRegular;
            [(TSAppDelegate *)[[NSApplication sharedApplication] delegate] reReadCommandCompletionData];
        }
    }


}

@end
