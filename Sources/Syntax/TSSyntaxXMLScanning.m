// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxXMLScanning.h"

// The letters of a tag name. The character is taken as its low byte, as it always has been.
static BOOL TSIsXMLNameLetter(char c)
{
    return (('A' <= c) && (c <= 'Z')) || (('a' <= c) && (c <= 'z')) || (c == '/');
}

static void TSXMLToken(TSSyntaxTokenBlock block, NSRange range, TSSyntaxRole role)
{
    block(range, role, TSSyntaxTokenFlagsNone);
}

void TSSyntaxScanXMLTag(NSString *string, NSUInteger *location, NSUInteger lineEnd, NS_NOESCAPE TSSyntaxTokenBlock block)
{
    NSRange colorRange, searchRange;
    char c;
    (*location)++;
    if ((*location) < lineEnd) {
        colorRange.location = *location;
        colorRange.length = 1;
        if (((*location) < lineEnd) && !TSIsXMLNameLetter((char)[string characterAtIndex:(*location)])) {
            (*location)++;
            colorRange.length = *location - colorRange.location;
        } else {
            while ((*location < lineEnd) && TSIsXMLNameLetter((char)[string characterAtIndex:(*location)])) {
                (*location)++;
                colorRange.length = *location - colorRange.location;
            }
        }
        TSXMLToken(block, colorRange, TSSyntaxRoleXMLTag);
    }
    searchRange = [string rangeOfString:@">" options:NSLiteralSearch range:NSMakeRange(*location, lineEnd - *location)];
    if (searchRange.location == NSNotFound)
        return;
    NSUInteger limit = searchRange.location;
    // Attributes: a name up to =, then a value between double quotes. A > ends the tag anywhere.
    do {
        do {
            c = (char)[string characterAtIndex:(*location)];
            (*location)++;
            if (c == '>')
                return;
        } while ((c == ' ') || (c == '?'));
        colorRange.location = *location - 1;
        do {
            c = (char)[string characterAtIndex:(*location)];
            (*location)++;
            if (c == '>')
                return;
        } while (c != '=');
        colorRange.length = *location - colorRange.location - 1;
        TSXMLToken(block, colorRange, TSSyntaxRoleXMLParameter);
        int mode = 4;
        do {
            c = (char)[string characterAtIndex:(*location)];
            (*location)++;
            if (c == '>')
                return;
            if ((c == '\"') && (mode == 4)) {
                mode = 5;
                colorRange.location = *location;
                c = 'x';
            }
            if ((c == '\"') && (mode == 5)) {
                mode = 6;
                colorRange.length = *location - colorRange.location - 1;
                TSXMLToken(block, colorRange, TSSyntaxRoleXMLValue);
            }
        } while (c != '\"');
    } while ((*location) < limit);
}

void TSSyntaxScanXMLEntity(NSString *string, NSUInteger *location, NSUInteger lineEnd, NS_NOESCAPE TSSyntaxTokenBlock block)
{
    NSRange searchRange = [string rangeOfString:@";" options:NSLiteralSearch range:NSMakeRange(*location + 1, lineEnd - (*location + 1))];
    if (searchRange.location != NSNotFound) {
        NSRange colorRange = NSMakeRange((*location) + 1, searchRange.location - ((*location) + 1));
        TSXMLToken(block, colorRange, TSSyntaxRoleXMLSpecial);
        (*location) = colorRange.location + 1;
    } else
        (*location)++;
}

void TSSyntaxScanXMLComments(NSString *string, NSRange range, NS_NOESCAPE TSSyntaxTokenBlock block)
{
    const NSUInteger lineStart = range.location, lineEnd = NSMaxRange(range);
    NSRange colorRange, searchRange, search1Range, myRange;
    NSUInteger location = lineStart;
    myRange = NSMakeRange(location, lineEnd - location);
    searchRange = [string rangeOfString:@"<!--" options:NSLiteralSearch range:myRange];
    search1Range = [string rangeOfString:@"-->" options:NSLiteralSearch range:myRange];
    // The range starts inside a comment.
    if ((search1Range.location != NSNotFound) && ((searchRange.location == NSNotFound) || (searchRange.location > search1Range.location))) {
        colorRange.location = lineStart;
        colorRange.length = search1Range.location - colorRange.location + 3;
        TSXMLToken(block, colorRange, TSSyntaxRoleXMLComment);
        location = search1Range.location + 4;
    }
    BOOL done = NO;
    while ((location < lineEnd) && !done) {
        myRange = NSMakeRange(location, lineEnd - location);
        searchRange = [string rangeOfString:@"<!--" options:NSLiteralSearch range:myRange];
        search1Range = [string rangeOfString:@"-->" options:NSLiteralSearch range:myRange];
        if ((searchRange.location != NSNotFound) && (search1Range.location != NSNotFound) && (searchRange.location < search1Range.location)) {
            colorRange.location = searchRange.location;
            colorRange.length = search1Range.location - colorRange.location + 3;
            TSXMLToken(block, colorRange, TSSyntaxRoleXMLComment);
            location = search1Range.location + 4;
        } else
            done = YES;
    }
    // A comment that is not closed in the range runs to its end (and three characters on, which is clipped).
    if (location < lineEnd) {
        myRange = NSMakeRange(location, lineEnd - location);
        searchRange = [string rangeOfString:@"<!--" options:NSLiteralSearch range:myRange];
        search1Range = [string rangeOfString:@"-->" options:NSLiteralSearch range:myRange];
        if ((searchRange.location != NSNotFound) && (search1Range.location == NSNotFound)) {
            colorRange.location = searchRange.location;
            colorRange.length = lineEnd - colorRange.location + 3;
            TSXMLToken(block, colorRange, TSSyntaxRoleXMLComment);
        }
    }
}
